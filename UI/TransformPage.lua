-- UI/TransformPage.lua
-- Transform page: source -> preview -> output pipeline
local addonName, ns = ...

local UI = ns.UI
local tableContainer = UI.tableContainer

-- ==========================================
-- STATE
-- ==========================================

local sourceMode = "imports"     -- "tsm", "imports", "inventory", "auctionator"
local sourceValue = ""           -- group path, source name, charKey, list name
local inventoryFilter = "all"    -- "all", "bags", "bank", "warbank"
local outputFormat = "aaa"       -- "aaa", "csv", "tsmgroup", "auctionator"
local priceSource = "DBMarket"
local priceDiscount = 90
local currentItems = {}
local outputListName = "FlipQueue Export"

-- ==========================================
-- UNIFIED COLUMN DEFINITION
-- ==========================================
-- Same columns for all sources so the user can verify the full superset of
-- data that feeds into every output format.

local PREVIEW_COLUMNS = {
    {key = "name",    label = "Item",    width = 170, sortable = true},
    {key = "type",    label = "Type",    width = 32,  align = "CENTER", sortable = true},
    {key = "qty",     label = "Qty",     width = 30,  align = "CENTER", sortable = true},
    {key = "quality", label = "Qual",    width = 55,  sortable = true},
    {key = "price",   label = "Price",   width = 70,  sortable = true},
    {key = "detail",  label = "Detail",  width = 100, sortable = true},
}

-- ==========================================
-- PAGE FRAME
-- ==========================================

local transformPage = CreateFrame("Frame", nil, tableContainer)
transformPage:SetAllPoints()
transformPage:Hide()

-- ==========================================
-- SOURCE PICKER ROW
-- ==========================================

local srcLabel = transformPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
srcLabel:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, -6)
srcLabel:SetText("Source:")
srcLabel:SetTextColor(0.6, 0.6, 0.6)

local function CreateToggleBtn(label, parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(20)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetWidth(btn.text:GetStringWidth() + 16)
    btn:SetScript("OnEnter", function(self)
        if not self._active then self:SetBackdropColor(0.2, 0.2, 0.3, 1) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self._active then
            self:SetBackdropColor(0.2, 0.4, 0.2, 1)
        else
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        end
    end)
    return btn
end

-- Create a prominent action button (wider, brighter)
local function CreateActionBtn(label, parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(24)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.15, 0.3, 0.5, 1)
    btn:SetBackdropBorderColor(0.3, 0.5, 0.7, 0.9)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetWidth(math.max(120, btn.text:GetStringWidth() + 24))
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.4, 0.6, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.3, 0.5, 1)
    end)
    return btn
end

local srcTSMBtn = CreateToggleBtn("TSM Group", transformPage)
srcTSMBtn:SetPoint("LEFT", srcLabel, "RIGHT", 6, 0)

local srcImportsBtn = CreateToggleBtn("Imports", transformPage)
srcImportsBtn:SetPoint("LEFT", srcTSMBtn, "RIGHT", 4, 0)

local srcInvBtn = CreateToggleBtn("Inventory", transformPage)
srcInvBtn:SetPoint("LEFT", srcImportsBtn, "RIGHT", 4, 0)

local srcAuctBtn = CreateToggleBtn("Auctionator", transformPage)
srcAuctBtn:SetPoint("LEFT", srcInvBtn, "RIGHT", 4, 0)

-- ==========================================
-- SOURCE CONFIG AREA
-- ==========================================

local configArea = CreateFrame("Frame", nil, transformPage)
configArea:SetHeight(26)
configArea:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, -28)
configArea:SetPoint("RIGHT", transformPage, "RIGHT", -8, 0)

-- TSM group tree
local tsmTreeFrame = CreateFrame("Frame", nil, transformPage)
tsmTreeFrame:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 4, -28)
tsmTreeFrame:SetPoint("RIGHT", transformPage, "RIGHT", -4, 0)
tsmTreeFrame:SetHeight(130)
tsmTreeFrame:Hide()

local tsmGroupTree
local tsmTreeOnSelect  -- deferred: assigned after UpdateSourceButtons is defined
if UI.CreateGroupTree then
    tsmGroupTree = UI:CreateGroupTree(tsmTreeFrame, function(path)
        sourceValue = path or ""
        if tsmTreeOnSelect then tsmTreeOnSelect() end
    end)
end

-- Inventory filter row
local invFilterLabel = configArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
invFilterLabel:SetPoint("LEFT", configArea, "LEFT", 0, 0)
invFilterLabel:SetText("Scope:")
invFilterLabel:SetTextColor(0.6, 0.6, 0.6)
invFilterLabel:Hide()

local invFilterBtns = {}
local invFilterNames = {"all", "bags", "bank", "warbank"}
local invFilterLabels = {all = "All", bags = "Bags", bank = "Bank", warbank = "Warbank"}

local prevInvBtn
for _, mode in ipairs(invFilterNames) do
    local btn = CreateToggleBtn(invFilterLabels[mode], configArea)
    if prevInvBtn then
        btn:SetPoint("LEFT", prevInvBtn, "RIGHT", 4, 0)
    else
        btn:SetPoint("LEFT", invFilterLabel, "RIGHT", 6, 0)
    end
    btn:Hide()
    local capturedMode = mode
    btn:SetScript("OnClick", function()
        inventoryFilter = capturedMode
        -- Update filter button visuals
        for m, b in pairs(invFilterBtns) do
            b._active = (inventoryFilter == m)
            if inventoryFilter == m then
                b:SetBackdropColor(0.2, 0.4, 0.2, 1)
            else
                b:SetBackdropColor(0.15, 0.15, 0.2, 1)
            end
        end
    end)
    invFilterBtns[mode] = btn
    prevInvBtn = btn
end

-- Auctionator list picker
local auctListFrame = CreateFrame("Frame", nil, transformPage)
auctListFrame:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 4, -28)
auctListFrame:SetPoint("RIGHT", transformPage, "RIGHT", -4, 0)
auctListFrame:SetHeight(80)
auctListFrame:Hide()

local auctListScroll = CreateFrame("ScrollFrame", nil, auctListFrame, "UIPanelScrollFrameTemplate")
auctListScroll:SetPoint("TOPLEFT", auctListFrame, "TOPLEFT", 0, 0)
auctListScroll:SetPoint("BOTTOMRIGHT", auctListFrame, "BOTTOMRIGHT", -16, 0)

local auctListContent = CreateFrame("Frame", nil, auctListScroll)
auctListContent:SetWidth(1)
auctListContent:SetHeight(1)
auctListScroll:SetScrollChild(auctListContent)
auctListScroll:SetScript("OnSizeChanged", function(sf, w)
    auctListContent:SetWidth(w)
end)
local auctListRows = {}

-- Source status text
local srcStatus = transformPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
srcStatus:SetPoint("TOPLEFT", configArea, "BOTTOMLEFT", 0, -2)
srcStatus:SetTextColor(0.5, 0.5, 0.5)
srcStatus:SetText("")

-- ==========================================
-- PREVIEW BUTTON
-- ==========================================

local previewBtn = CreateActionBtn("Preview Source", transformPage)

-- ==========================================
-- PREVIEW TABLE
-- ==========================================

local previewContainer = CreateFrame("Frame", nil, transformPage)
previewContainer:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 0, -56)
previewContainer:SetPoint("RIGHT", transformPage, "RIGHT", 0, 0)
previewContainer:SetHeight(180)

UI.transformPreviewTable = UI:CreateScrollTable(previewContainer, PREVIEW_COLUMNS)
UI.transformPreviewTable:SetSort("name", true)
if UI._RegisterTable then UI._RegisterTable(UI.transformPreviewTable) end

local previewStatus = transformPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
previewStatus:SetPoint("TOPLEFT", previewContainer, "BOTTOMLEFT", 8, -2)
previewStatus:SetTextColor(0.5, 0.5, 0.5)
previewStatus:SetText("")

-- ==========================================
-- TRANSFORM BUTTON + OUTPUT FORMAT ROW
-- ==========================================

local transformBtn = CreateActionBtn("Transform", transformPage)

local outLabel = transformPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
outLabel:SetText("Output:")
outLabel:SetTextColor(0.6, 0.6, 0.6)

local outAAABtn = CreateToggleBtn("AAA JSON", transformPage)
outAAABtn:SetPoint("LEFT", outLabel, "RIGHT", 6, 0)

local outCSVBtn = CreateToggleBtn("FP CSV", transformPage)
outCSVBtn:SetPoint("LEFT", outAAABtn, "RIGHT", 4, 0)

local outTSMBtn = CreateToggleBtn("TSM String", transformPage)
outTSMBtn:SetPoint("LEFT", outCSVBtn, "RIGHT", 4, 0)

local outAuctBtn = CreateToggleBtn("Auctionator", transformPage)
outAuctBtn:SetPoint("LEFT", outTSMBtn, "RIGHT", 4, 0)

-- ==========================================
-- PRICE SETTINGS ROW (shown for AAA output)
-- ==========================================

local priceRow = CreateFrame("Frame", nil, transformPage)
priceRow:SetHeight(22)
priceRow:Hide()

local priceDiscountLabel = priceRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
priceDiscountLabel:SetPoint("LEFT", priceRow, "LEFT", 0, 0)
priceDiscountLabel:SetText("Discount %:")
priceDiscountLabel:SetTextColor(0.6, 0.6, 0.6)

local priceDiscountBox = CreateFrame("EditBox", nil, priceRow, "InputBoxTemplate")
priceDiscountBox:SetSize(40, 20)
priceDiscountBox:SetPoint("LEFT", priceDiscountLabel, "RIGHT", 4, 0)
priceDiscountBox:SetAutoFocus(false)
priceDiscountBox:SetMaxLetters(3)
priceDiscountBox:SetText(tostring(priceDiscount))
priceDiscountBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
priceDiscountBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    local val = tonumber(self:GetText())
    if val and val >= 0 and val <= 100 then
        priceDiscount = val
        if ns.db and ns.db.settings then ns.db.settings.transformDiscount = val end
    end
end)

local priceSrcLabel = priceRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
priceSrcLabel:SetPoint("LEFT", priceDiscountBox, "RIGHT", 12, 0)
priceSrcLabel:SetText("Price source:")
priceSrcLabel:SetTextColor(0.6, 0.6, 0.6)

local priceSrcBox = CreateFrame("EditBox", nil, priceRow, "InputBoxTemplate")
priceSrcBox:SetSize(120, 20)
priceSrcBox:SetPoint("LEFT", priceSrcLabel, "RIGHT", 4, 0)
priceSrcBox:SetAutoFocus(false)
priceSrcBox:SetMaxLetters(100)
priceSrcBox:SetText(priceSource)
priceSrcBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
priceSrcBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    priceSource = self:GetText()
    if ns.db and ns.db.settings then ns.db.settings.transformPriceSource = priceSource end
end)

-- ==========================================
-- OUTPUT AREAS
-- ==========================================

-- Single output (CSV, TSM String, Auctionator)
local outputScroll = CreateFrame("ScrollFrame", "FlipQueueTransformOutputScroll", transformPage, "UIPanelScrollFrameTemplate")
outputScroll:Hide()

local outputEdit = CreateFrame("EditBox", "FlipQueueTransformOutputEdit", outputScroll)
outputEdit:SetMultiLine(true)
outputEdit:SetAutoFocus(false)
outputEdit:SetFontObject("ChatFontNormal")
outputEdit:SetWidth(500)
outputScroll:SetScrollChild(outputEdit)
outputScroll:SetScript("OnSizeChanged", function(sf, w)
    outputEdit:SetWidth(w)
end)
outputEdit:SetScript("OnEscapePressed", function() outputEdit:ClearFocus() end)

-- Items output (AAA format)
local itemsOutputLabel = transformPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
itemsOutputLabel:SetText("Items:")
itemsOutputLabel:SetTextColor(0.6, 0.6, 0.6)
itemsOutputLabel:Hide()

local itemsOutputScroll = CreateFrame("ScrollFrame", "FlipQueueTransformItemsScroll", transformPage, "UIPanelScrollFrameTemplate")
itemsOutputScroll:Hide()

local itemsOutputEdit = CreateFrame("EditBox", "FlipQueueTransformItemsEdit", itemsOutputScroll)
itemsOutputEdit:SetMultiLine(true)
itemsOutputEdit:SetAutoFocus(false)
itemsOutputEdit:SetFontObject("ChatFontNormal")
itemsOutputEdit:SetWidth(500)
itemsOutputScroll:SetScrollChild(itemsOutputEdit)
itemsOutputScroll:SetScript("OnSizeChanged", function(sf, w)
    itemsOutputEdit:SetWidth(w)
end)
itemsOutputEdit:SetScript("OnEscapePressed", function() itemsOutputEdit:ClearFocus() end)

-- Pets output (AAA format)
local petsOutputLabel = transformPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
petsOutputLabel:SetText("Pets:")
petsOutputLabel:SetTextColor(0.6, 0.6, 0.6)
petsOutputLabel:Hide()

local petsOutputScroll = CreateFrame("ScrollFrame", "FlipQueueTransformPetsScroll", transformPage, "UIPanelScrollFrameTemplate")
petsOutputScroll:Hide()

local petsOutputEdit = CreateFrame("EditBox", "FlipQueueTransformPetsEdit", petsOutputScroll)
petsOutputEdit:SetMultiLine(true)
petsOutputEdit:SetAutoFocus(false)
petsOutputEdit:SetFontObject("ChatFontNormal")
petsOutputEdit:SetWidth(500)
petsOutputScroll:SetScrollChild(petsOutputEdit)
petsOutputScroll:SetScript("OnSizeChanged", function(sf, w)
    petsOutputEdit:SetWidth(w)
end)
petsOutputEdit:SetScript("OnEscapePressed", function() petsOutputEdit:ClearFocus() end)

-- ==========================================
-- HELPERS
-- ==========================================

local function HideAllOutputs()
    outputScroll:Hide()
    itemsOutputLabel:Hide()
    itemsOutputScroll:Hide()
    petsOutputLabel:Hide()
    petsOutputScroll:Hide()
end

local function ClearOutputs()
    HideAllOutputs()
    outputEdit:SetText("")
    itemsOutputEdit:SetText("")
    petsOutputEdit:SetText("")
end


-- ==========================================
-- STATE UPDATE FUNCTIONS
-- ==========================================

local function UpdateSourceButtons()
    local modes = {tsm = srcTSMBtn, imports = srcImportsBtn, inventory = srcInvBtn, auctionator = srcAuctBtn}
    for mode, btn in pairs(modes) do
        btn._active = (sourceMode == mode)
        if sourceMode == mode then
            btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        end
    end

    -- Hide all source-specific UIs
    tsmTreeFrame:Hide()
    auctListFrame:Hide()
    invFilterLabel:Hide()
    for _, btn in pairs(invFilterBtns) do btn:Hide() end
    srcStatus:SetText("")
    configArea:Hide()

    if sourceMode == "tsm" then
        if tsmGroupTree and ns.TSM and ns.TSM:IsEnabled() then
            tsmTreeFrame:Show()
            local profile = ns.TSM:GetSelectedProfile()
            if profile and tsmGroupTree._profile ~= profile then
                tsmGroupTree:SetProfile(profile)
            end
            if sourceValue ~= "" then
                srcStatus:ClearAllPoints()
                srcStatus:SetPoint("TOPLEFT", tsmTreeFrame, "BOTTOMLEFT", 6, -2)
                srcStatus:SetText(ns.COLORS.YELLOW .. "Group: " .. sourceValue:gsub("`", " > ") .. "|r")
            end
        else
            srcStatus:ClearAllPoints()
            srcStatus:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, -30)
            srcStatus:SetText(ns.COLORS.GRAY .. "TSM not available|r")
        end

    elseif sourceMode == "imports" then
        local count = ns:ImportGetCount("fpScanner")
        srcStatus:ClearAllPoints()
        srcStatus:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, -30)
        srcStatus:SetText(count > 0
            and (ns.COLORS.YELLOW .. count .. " deals|r in imports")
            or (ns.COLORS.GRAY .. "No imports — use Import page first|r"))

    elseif sourceMode == "inventory" then
        configArea:Show()
        invFilterLabel:Show()
        for mode, btn in pairs(invFilterBtns) do
            btn:Show()
            btn._active = (inventoryFilter == mode)
            if inventoryFilter == mode then
                btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
            else
                btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
            end
        end

    elseif sourceMode == "auctionator" then
        local listNames = ns:GetAuctionatorListNames()
        if #listNames > 0 then
            auctListFrame:Show()
            local listHeight = math.min(80, math.max(20, #listNames * 18 + 4))
            auctListFrame:SetHeight(listHeight)
            auctListContent:SetWidth(auctListScroll:GetWidth() or 200)

            local auctY = 0
            for idx, listName in ipairs(listNames) do
                local row = auctListRows[idx]
                if not row then
                    row = CreateFrame("Button", nil, auctListContent)
                    row:SetHeight(18)
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
                    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                    row.label:SetJustifyH("LEFT")
                    row:EnableMouse(true)
                    auctListRows[idx] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", auctListContent, "TOPLEFT", 0, -auctY)
                row:SetPoint("RIGHT", auctListContent, "RIGHT", 0, 0)

                local isSelected = (sourceValue == listName)
                if isSelected then
                    row.bg:SetColorTexture(0.2, 0.35, 0.5, 0.6)
                    row.label:SetText("|cffffffff" .. listName .. "|r")
                else
                    row.bg:SetColorTexture(0, 0, 0, 0)
                    row.label:SetText(listName)
                    row.label:SetTextColor(0.8, 0.8, 0.8)
                end

                local capturedName = listName
                row:SetScript("OnClick", function()
                    sourceValue = capturedName
                    -- Refresh list highlight only
                    UpdateSourceButtons()
                end)
                row:SetScript("OnEnter", function(self)
                    if not isSelected then self.bg:SetColorTexture(1, 1, 1, 0.05) end
                end)
                row:SetScript("OnLeave", function(self)
                    if sourceValue ~= capturedName then self.bg:SetColorTexture(0, 0, 0, 0) end
                end)

                row:Show()
                auctY = auctY + 18
            end
            for i = #listNames + 1, #auctListRows do
                auctListRows[i]:Hide()
            end
            auctListContent:SetHeight(math.max(1, auctY))
        else
            srcStatus:ClearAllPoints()
            srcStatus:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, -30)
            srcStatus:SetText(ns.COLORS.GRAY .. "Auctionator not loaded or no shopping lists|r")
        end
    end
end

-- Wire up the deferred TSM tree callback now that UpdateSourceButtons exists
tsmTreeOnSelect = function() UpdateSourceButtons() end

local function UpdateOutputButtons()
    local modes = {aaa = outAAABtn, csv = outCSVBtn, tsmgroup = outTSMBtn, auctionator = outAuctBtn}
    for mode, btn in pairs(modes) do
        btn._active = (outputFormat == mode)
        if outputFormat == mode then
            btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        end
    end

    if outputFormat == "aaa" then
        priceRow:Show()
    else
        priceRow:Hide()
    end
end

-- ==========================================
-- LAYOUT
-- ==========================================

local function RepositionLayout()
    -- Calculate Y offset after source config area
    local configBottom = -28  -- start after source row
    if sourceMode == "tsm" and tsmTreeFrame:IsShown() then
        configBottom = configBottom - tsmTreeFrame:GetHeight() - 4
        if srcStatus:GetText() ~= "" then
            configBottom = configBottom - 14
        end
    elseif sourceMode == "auctionator" and auctListFrame:IsShown() then
        configBottom = configBottom - auctListFrame:GetHeight() - 4
    elseif sourceMode == "inventory" and configArea:IsShown() then
        configBottom = configBottom - 26 - 4
    elseif srcStatus:GetText() ~= "" then
        configBottom = configBottom - 18
    else
        configBottom = configBottom - 4
    end

    -- Preview button
    previewBtn:ClearAllPoints()
    previewBtn:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, configBottom)
    local afterPreviewBtn = configBottom - 28

    -- Preview table
    previewContainer:ClearAllPoints()
    previewContainer:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 0, afterPreviewBtn)
    previewContainer:SetPoint("RIGHT", transformPage, "RIGHT", 0, 0)

    -- Calculate remaining space for table + transform controls + output
    local pageHeight = transformPage:GetHeight()
    local usedAbove = -afterPreviewBtn
    local remaining = pageHeight - usedAbove - 4

    -- Reserve: transform btn (28) + output row (24) + price row (26 if AAA) + padding
    local controlsHeight = 28 + 24 + (outputFormat == "aaa" and 26 or 0) + 12
    local tableAndOutputSpace = remaining - controlsHeight
    local tableHeight = math.max(60, math.floor(tableAndOutputSpace * 0.40))
    previewContainer:SetHeight(tableHeight)

    -- Preview status
    previewStatus:ClearAllPoints()
    previewStatus:SetPoint("TOPLEFT", previewContainer, "BOTTOMLEFT", 8, -2)

    -- Transform button + output format row
    local transformY = afterPreviewBtn - tableHeight - 18
    transformBtn:ClearAllPoints()
    transformBtn:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, transformY)

    outLabel:ClearAllPoints()
    outLabel:SetPoint("LEFT", transformBtn, "RIGHT", 12, 0)

    -- Price row
    local afterTransformY = transformY - 28
    priceRow:ClearAllPoints()
    priceRow:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, afterTransformY)
    priceRow:SetPoint("RIGHT", transformPage, "RIGHT", -8, 0)

    -- Output area start
    local outputStartY = afterTransformY - (outputFormat == "aaa" and 26 or 2)

    HideAllOutputs()

    if outputFormat == "aaa" then
        local outputSpace = pageHeight + outputStartY - 4
        local halfHeight = math.max(30, math.floor((outputSpace - 32) / 2))

        itemsOutputLabel:ClearAllPoints()
        itemsOutputLabel:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, outputStartY)
        itemsOutputLabel:Show()

        itemsOutputScroll:ClearAllPoints()
        itemsOutputScroll:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 4, outputStartY - 14)
        itemsOutputScroll:SetPoint("RIGHT", transformPage, "RIGHT", -24, 0)
        itemsOutputScroll:SetHeight(halfHeight)
        itemsOutputScroll:Show()

        local petsY = outputStartY - 14 - halfHeight - 4
        petsOutputLabel:ClearAllPoints()
        petsOutputLabel:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, petsY)
        petsOutputLabel:Show()

        petsOutputScroll:ClearAllPoints()
        petsOutputScroll:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 4, petsY - 14)
        petsOutputScroll:SetPoint("RIGHT", transformPage, "RIGHT", -24, 0)
        petsOutputScroll:SetHeight(halfHeight)
        petsOutputScroll:Show()
    else
        outputScroll:ClearAllPoints()
        outputScroll:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 4, outputStartY)
        outputScroll:SetPoint("BOTTOMRIGHT", transformPage, "BOTTOMRIGHT", -24, 4)
        outputScroll:Show()
    end
end

-- ==========================================
-- LOAD & PREVIEW (triggered by Preview button)
-- ==========================================

local function LoadItems()
    local T = ns.Transformer
    if not T then return {} end

    if sourceMode == "tsm" then
        local profile = ns.TSM and ns.TSM:GetSelectedProfile()
        if profile and sourceValue ~= "" then
            return T:InputFromTSMGroup(profile, sourceValue)
        end
    elseif sourceMode == "imports" then
        return T:InputFromImports("fpScanner")
    elseif sourceMode == "inventory" then
        return T:InputFromInventory(inventoryFilter)
    elseif sourceMode == "auctionator" then
        if sourceValue ~= "" then
            return T:InputFromAuctionatorList(sourceValue)
        end
    end
    return {}
end

local function BuildPreviewData(items)
    local QualityColorName = UI._QualityColorName
    local data = {}

    for _, item in ipairs(items) do
        local displayName = item.name or "Unknown"
        if QualityColorName and item.quality then
            displayName = QualityColorName(displayName, item.quality)
        end

        -- Type indicator
        local typeStr = item.isBattlePet and "|cff44ff44Pet|r" or ""

        -- Price with source color: yellow = import, cyan = TSM, gray = none
        local priceStr, sortPrice
        local src = item._priceSource
        if src == "import" then
            priceStr = "|cffffff00" .. tostring(item.expectedPrice) .. "|r"
        elseif src == "tsm" then
            priceStr = "|cff00ccff" .. tostring(item.expectedPrice) .. "|r"
        else
            priceStr = ns.COLORS.GRAY .. "\226\128\148" .. "|r"  -- em dash
        end
        -- Numeric sort value for price column
        if item.expectedPrice then
            if type(item.expectedPrice) == "number" then
                sortPrice = item.expectedPrice
            else
                sortPrice = ns:ParseGoldValue(tostring(item.expectedPrice)) or 0
            end
        else
            sortPrice = 0
        end

        -- Detail: owner for inventory, realm for imports, group path for TSM
        local detailStr = ""
        if item._owner and item._owner ~= "" then
            detailStr = item._owner
        elseif item.targetRealm and item.targetRealm ~= "" then
            detailStr = item.targetRealm
        end

        table.insert(data, {
            name       = displayName,
            type       = typeStr,
            qty        = item.quantity or 1,
            quality    = item.quality or "",
            price      = priceStr,
            _sortPrice = sortPrice,
            detail     = detailStr,
            _icon      = item.icon,
            _tooltipItemID = tonumber(tostring(item.itemID)) or nil,
            _tooltipText = item.name,
        })
    end

    return data
end

-- ==========================================
-- PREVIEW PROCESSING
-- ==========================================
-- Single-pass enrichment + pricing that builds the intermediate format.
-- Runs synchronously. For items whose names haven't loaded yet (async
-- C_Item.GetItemInfo), a deferred second pass fills them in.

local previewGeneration = 0

-- Tally diagnostics from already-processed items
local function BuildDiagnostics(items)
    local tsmAvail = TSM_API and type(TSM_API) == "table"
        and type(TSM_API.GetCustomPriceValue) == "function"
    local diag = {names = 0, pets = 0, tsmLookups = 0, tsmHits = 0,
                  importPriced = 0, unpriced = 0, tsmAvail = tsmAvail}
    for _, item in ipairs(items) do
        if item._nameResolved then diag.names = diag.names + 1 end
        if item.isBattlePet then diag.pets = diag.pets + 1 end
        if item._priceSource == "import" then
            diag.importPriced = diag.importPriced + 1
        elseif item._priceSource == "tsm" then
            diag.tsmHits = diag.tsmHits + 1
            diag.tsmLookups = diag.tsmLookups + 1
        else
            diag.unpriced = diag.unpriced + 1
            -- Count as a TSM lookup attempt if item had a key but no price
            if tsmAvail and item.itemKey and item.itemKey ~= "" then
                diag.tsmLookups = diag.tsmLookups + 1
            end
        end
    end
    return diag
end

-- Build a name→itemID map from all available data: imports, inventory, warbank.
-- Lazily built once per session; covers items the user has encountered.
local nameToIDMap

local function GetNameToIDMap()
    if nameToIDMap then return nameToIDMap end
    nameToIDMap = {}
    if not ns.db then return nameToIDMap end

    -- Import database (FP CSV imports have item IDs)
    if ns.db.imports then
        for _, srcMap in pairs(ns.db.imports) do
            for _, importItem in pairs(srcMap) do
                local name = importItem.name and importItem.name:lower()
                local numID = tonumber(importItem.itemID)
                if name and name ~= "" and numID and numID > 0 and not nameToIDMap[name] then
                    nameToIDMap[name] = numID
                end
            end
        end
    end

    -- Character inventories
    for _, charData in pairs(ns.db.characters or {}) do
        if charData.inventory and charData.inventory.items then
            for _, itemData in pairs(charData.inventory.items) do
                local name = itemData.name and itemData.name:lower()
                local numID = tonumber(itemData.itemID)
                if name and name ~= "" and numID and numID > 0 and not nameToIDMap[name] then
                    nameToIDMap[name] = numID
                end
            end
        end
    end

    -- Warbank
    if ns.db.warbank and ns.db.warbank.items then
        for _, itemData in pairs(ns.db.warbank.items) do
            local name = itemData.name and itemData.name:lower()
            local numID = tonumber(itemData.itemID)
            if name and name ~= "" and numID and numID > 0 and not nameToIDMap[name] then
                nameToIDMap[name] = numID
            end
        end
    end

    return nameToIDMap
end

-- Process items[startIdx..endIdx] (or all if omitted): resolve IDs, names, prices.
-- Modifies items in place. Diagnostics are tallied separately via BuildDiagnostics.
local function ProcessItems(items, startIdx, endIdx)
    local T = ns.Transformer
    local LookupItemInfo = ns.UI and ns.UI._LookupItemInfo
    local pMap = T and T._GetPetNameMap and T:_GetPetNameMap() or {}
    local idMap = GetNameToIDMap()

    local tsmAPI = TSM_API and type(TSM_API) == "table"
        and type(TSM_API.GetCustomPriceValue) == "function"
        and TSM_API or nil

    startIdx = startIdx or 1
    endIdx = endIdx or #items

    local QNAMES = {[0]="Poor",[1]="Common",[2]="Uncommon",
        [3]="Rare",[4]="Epic",[5]="Legendary",[6]="Artifact",[7]="Heirloom"}

    for i = startIdx, endIdx do
        local item = items[i]
        local numID = tonumber(item.itemID)

        -- === PET DETECTION ===
        if not item.isBattlePet and item.category then
            local cat = item.category:lower()
            if cat == "pet" or cat == "companions" then
                local sid = pMap[(item.name or ""):lower()]
                if sid then
                    item.isBattlePet = true
                    item.speciesID = sid
                    item.itemID = "pet:" .. sid
                    item.itemKey = "pet:" .. sid .. ";q0;"
                    numID = nil
                end
            end
        end

        -- === ID RESOLUTION ===
        if not item.isBattlePet then
            -- 1. From itemKey "12345;bonusIDs;modifiers"
            if not numID or numID <= 0 then
                if item.itemKey then
                    local keyID = item.itemKey:match("^(%d+);")
                    numID = tonumber(keyID)
                    if numID and numID > 0 then
                        item.itemID = tostring(numID)
                    end
                end
            end
            -- 2. From name→ID map (imports + inventory + warbank)
            if (not numID or numID <= 0) and item.name and item.name ~= "" then
                local mapped = idMap[item.name:lower()]
                if mapped then
                    numID = mapped
                    item.itemID = tostring(mapped)
                end
            end
            -- 3. From WoW API + inventory search (LookupItemInfo)
            if (not numID or numID <= 0) and LookupItemInfo then
                local _, _, resolvedID = LookupItemInfo(item.itemID, item.itemKey, item.name)
                if resolvedID then
                    numID = resolvedID
                    item.itemID = tostring(resolvedID)
                end
            end
        end

        -- === NAME / ICON / QUALITY ===
        if numID and numID > 0 then
            if not item.icon then
                local ok, _, _, _, _, tex = pcall(C_Item.GetItemInfoInstant, numID)
                if ok and tex then item.icon = tex end
            end
            if not item._nameResolved then
                local ok, name, _, quality = pcall(C_Item.GetItemInfo, numID)
                if ok and name then
                    item.name = name
                    item._nameResolved = true
                    if quality then
                        item.quality = QNAMES[quality] or item.quality
                    end
                end
            end
        end

        -- === ITEMKEY ===
        if not item.itemKey or item.itemKey == "" then
            if item.isBattlePet and item.speciesID then
                item.itemKey = "pet:" .. item.speciesID .. ";q0;"
            elseif item.itemID and item.itemID ~= "" then
                item.itemKey = ns:MakeItemKey(item.itemID, item.bonusIDs or "", item.modifiers or "")
            end
        end

        -- === PRICE ===
        if not item._priceSource then
            if item.expectedPrice and item.expectedPrice ~= "" then
                item._priceSource = "import"
            elseif tsmAPI and item.itemKey and item.itemKey ~= "" then
                local copper
                local tsmStr = ns.TSM and ns.TSM:ItemKeyToTSMString(item.itemKey)
                if tsmStr then
                    local ok, val = pcall(tsmAPI.GetCustomPriceValue, priceSource, tsmStr)
                    if ok and val and val > 0 then copper = val end
                end
                if not copper then
                    local baseID = (item.itemKey or ""):match("^(%d+)")
                    if baseID then
                        local ok, val = pcall(tsmAPI.GetCustomPriceValue, priceSource, "i:" .. baseID)
                        if ok and val and val > 0 then copper = val end
                    end
                end
                if copper then
                    item.expectedPrice = ns:FormatGold(copper)
                    item._priceSource = "tsm"
                end
            end
        end
    end
end

local function BuildStatusText(items, diag)
    local itemCount, petCount = 0, 0
    for _, item in ipairs(items) do
        if item.isBattlePet then petCount = petCount + 1
        else itemCount = itemCount + 1 end
    end
    if itemCount == 0 and petCount == 0 then
        return ns.COLORS.GRAY .. "No items found|r"
    end

    local parts = {}
    if itemCount > 0 then table.insert(parts, ns.COLORS.GREEN .. itemCount .. " items|r") end
    if petCount > 0 then table.insert(parts, "|cff44ff44" .. petCount .. " pets|r") end
    local text = table.concat(parts, ", ") .. " from " .. sourceMode

    -- Price breakdown
    local pp = {}
    if diag.importPriced > 0 then table.insert(pp, "|cffffff00" .. diag.importPriced .. " imp|r") end
    if diag.tsmHits > 0 then table.insert(pp, "|cff00ccff" .. diag.tsmHits .. " tsm|r") end
    if diag.unpriced > 0 then table.insert(pp, ns.COLORS.GRAY .. diag.unpriced .. " unpriced|r") end
    if #pp > 0 then text = text .. "  [" .. table.concat(pp, ", ") .. "]" end

    -- TSM availability hint
    if not diag.tsmAvail and diag.unpriced > 0 then
        text = text .. "  " .. ns.COLORS.RED .. "TSM API not available|r"
    elseif diag.tsmLookups > 0 and diag.tsmHits == 0 then
        text = text .. "  " .. ns.COLORS.RED .. "TSM returned no prices for \""
            .. priceSource .. "\"|r"
    end

    return text
end

local CHUNK_SIZE = 50

local function DoPreview()
    local T = ns.Transformer
    if not T then return end

    previewGeneration = previewGeneration + 1
    local myGen = previewGeneration

    currentItems = LoadItems()

    if #currentItems == 0 then
        previewStatus:SetText(ns.COLORS.GRAY .. "No items found|r")
        UI.transformPreviewTable:SetData({})
        UI._ShowTable(UI.transformPreviewTable)
        ClearOutputs()
        RepositionLayout()
        return
    end

    -- Show empty table + progress immediately
    UI.transformPreviewTable:SetData({})
    UI._ShowTable(UI.transformPreviewTable)
    ClearOutputs()
    RepositionLayout()

    local total = #currentItems
    previewStatus:SetText(ns.COLORS.YELLOW .. "Processing 0/" .. total .. "...|r")

    -- Process in chunks so the status line updates visibly
    local idx = 1

    local function processChunk()
        if previewGeneration ~= myGen or not transformPage:IsShown() then return end

        local endIdx = math.min(idx + CHUNK_SIZE - 1, total)

        -- Process this batch (one item at a time through ProcessItems' loop)
        -- We pass a slice-view by processing the range inline
        ProcessItems(currentItems, idx, endIdx)

        idx = endIdx + 1

        if idx <= total then
            previewStatus:SetText(ns.COLORS.YELLOW .. "Processing "
                .. (idx - 1) .. "/" .. total .. "...|r")
            C_Timer.After(0, processChunk)
        else
            -- All items processed — build table and show final state
            local diag = BuildDiagnostics(currentItems)
            local data = BuildPreviewData(currentItems)
            UI.transformPreviewTable:SetData(data)
            previewStatus:SetText(BuildStatusText(currentItems, diag))

            -- Deferred second pass for async C_Item.GetItemInfo name resolution
            local unresolved = 0
            for _, item in ipairs(currentItems) do
                if not item._nameResolved and not item.isBattlePet then
                    unresolved = unresolved + 1
                end
            end
            if unresolved > 0 and C_Timer and C_Timer.After then
                C_Timer.After(1, function()
                    if previewGeneration ~= myGen or not transformPage:IsShown() then return end
                    ProcessItems(currentItems)
                    local diag2 = BuildDiagnostics(currentItems)
                    local data2 = BuildPreviewData(currentItems)
                    UI.transformPreviewTable:SetData(data2)
                    previewStatus:SetText(BuildStatusText(currentItems, diag2))
                end)
            end
        end
    end

    processChunk()
end

-- ==========================================
-- GENERATE OUTPUT (triggered by Transform button)
-- ==========================================

local function DoTransform()
    local T = ns.Transformer
    if not T or #currentItems == 0 then
        ClearOutputs()
        RepositionLayout()
        return
    end

    RepositionLayout()

    if outputFormat == "aaa" then
        local itemsJSON, petsJSON, ic, pc, uic, upc = T:OutputAAAJSON(currentItems, priceDiscount, priceSource)
        local itemLabel = "Items (" .. ic .. ")"
        if uic and uic > 0 then itemLabel = itemLabel .. "  " .. ns.COLORS.GRAY .. uic .. " unpriced|r" end
        itemsOutputLabel:SetText(itemLabel .. ":")
        itemsOutputEdit:SetText(itemsJSON)
        local petLabel = "Pets (" .. pc .. ")"
        if upc and upc > 0 then petLabel = petLabel .. "  " .. ns.COLORS.GRAY .. upc .. " unpriced|r" end
        petsOutputLabel:SetText(petLabel .. ":")
        petsOutputEdit:SetText(petsJSON)
    elseif outputFormat == "csv" then
        local output = T:OutputFPCSV(currentItems)
        outputEdit:SetText(output)
        if output ~= "" then
            outputEdit:HighlightText()
        end
    elseif outputFormat == "tsmgroup" then
        local output = T:OutputTSMGroupString(currentItems)
        outputEdit:SetText(output)
        if output ~= "" then
            outputEdit:HighlightText()
        end
    elseif outputFormat == "auctionator" then
        local output = T:OutputAuctionatorList(currentItems, outputListName)
        outputEdit:SetText(output)
        if output ~= "" then
            outputEdit:HighlightText()
        end
    end
end

-- ==========================================
-- BUTTON WIRING
-- ==========================================

local function SetSource(mode)
    sourceMode = mode
    sourceValue = ""
    currentItems = {}

    UpdateSourceButtons()

    -- Clear table and output
    UI.transformPreviewTable:SetData({})
    previewStatus:SetText("")
    ClearOutputs()

    RepositionLayout()
    UI._ShowTable(UI.transformPreviewTable)
end

srcTSMBtn:SetScript("OnClick", function() SetSource("tsm") end)
srcImportsBtn:SetScript("OnClick", function() SetSource("imports") end)
srcInvBtn:SetScript("OnClick", function() SetSource("inventory") end)
srcAuctBtn:SetScript("OnClick", function() SetSource("auctionator") end)

previewBtn:SetScript("OnClick", function() DoPreview() end)

local function SetOutput(fmt)
    outputFormat = fmt
    UpdateOutputButtons()
    ClearOutputs()
    RepositionLayout()
end

outAAABtn:SetScript("OnClick", function() SetOutput("aaa") end)
outCSVBtn:SetScript("OnClick", function() SetOutput("csv") end)
outTSMBtn:SetScript("OnClick", function() SetOutput("tsmgroup") end)
outAuctBtn:SetScript("OnClick", function() SetOutput("auctionator") end)

transformBtn:SetScript("OnClick", function() DoTransform() end)

-- ==========================================
-- EXPOSE REFERENCES
-- ==========================================

UI._transformPage = transformPage

-- ==========================================
-- REFRESH (entry point from page navigation)
-- ==========================================

function UI:RefreshTransformPage()
    local mainFrame = UI.mainFrame
    mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Transform" .. "|r")
    UI._HideAllActionBtns()

    -- Load persisted settings
    if ns.db and ns.db.settings then
        priceSource = ns.db.settings.transformPriceSource or priceSource
        priceDiscount = ns.db.settings.transformDiscount or priceDiscount
        priceSrcBox:SetText(priceSource)
        priceDiscountBox:SetText(tostring(priceDiscount))
    end

    transformPage:Show()

    UpdateSourceButtons()
    UpdateOutputButtons()
    RepositionLayout()
    UI._ShowTable(UI.transformPreviewTable)

    mainFrame.statusText:SetText("Transform  |  Select source, Preview, then Transform")
end
