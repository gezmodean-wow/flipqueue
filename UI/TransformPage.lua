-- UI/TransformPage.lua
-- Transform page: input -> transform -> output pipeline UI
local addonName, ns = ...

local UI = ns.UI
local tableContainer = UI.tableContainer

-- ==========================================
-- STATE
-- ==========================================

local sourceMode = "tsm"       -- "tsm", "imports", "inventory", "auctionator"
local sourceValue = ""          -- group path, source name, charKey, list name
local inventoryFilter = "all"   -- "all", "character", "warbank", "bags", "bank"
local outputFormat = "aaa"      -- "aaa", "csv", "tsmgroup", "auctionator"
local priceSource = "DBMarket"
local priceDiscount = 90        -- percentage discount (buy at 10% of market = 90% discount)
local currentItems = {}         -- normalized items after input
local outputListName = "FlipQueue Export"

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

local srcTSMBtn = CreateToggleBtn("TSM Group", transformPage)
srcTSMBtn:SetPoint("LEFT", srcLabel, "RIGHT", 6, 0)

local srcImportsBtn = CreateToggleBtn("Imports", transformPage)
srcImportsBtn:SetPoint("LEFT", srcTSMBtn, "RIGHT", 4, 0)

local srcInvBtn = CreateToggleBtn("Inventory", transformPage)
srcInvBtn:SetPoint("LEFT", srcImportsBtn, "RIGHT", 4, 0)

local srcAuctBtn = CreateToggleBtn("Auctionator", transformPage)
srcAuctBtn:SetPoint("LEFT", srcInvBtn, "RIGHT", 4, 0)

-- ==========================================
-- SOURCE CONFIG AREA (row 2)
-- ==========================================

local configArea = CreateFrame("Frame", nil, transformPage)
configArea:SetHeight(26)
configArea:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, -28)
configArea:SetPoint("RIGHT", transformPage, "RIGHT", -8, 0)

-- TSM group tree (reusable widget)
local tsmTreeFrame = CreateFrame("Frame", nil, transformPage)
tsmTreeFrame:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 4, -28)
tsmTreeFrame:SetPoint("RIGHT", transformPage, "RIGHT", -4, 0)
tsmTreeFrame:SetHeight(130)
tsmTreeFrame:Hide()

local tsmGroupTree
if UI.CreateGroupTree then
    tsmGroupTree = UI:CreateGroupTree(tsmTreeFrame, function(path)
        sourceValue = path or ""
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
        UI:RefreshTransformPage()
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
-- OUTPUT FORMAT ROW
-- ==========================================

local outLabel = transformPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
outLabel:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, -56)
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
priceRow:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, -78)
priceRow:SetPoint("RIGHT", transformPage, "RIGHT", -8, 0)
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
end)

-- ==========================================
-- PREVIEW TABLE
-- ==========================================

-- Preview table sits between the config rows and the output area
local previewContainer = CreateFrame("Frame", nil, transformPage)
previewContainer:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 0, -100)
previewContainer:SetPoint("RIGHT", transformPage, "RIGHT", 0, 0)
previewContainer:SetHeight(180)

UI.transformPreviewTable = UI:CreateScrollTable(previewContainer, {
    {key = "name",     label = "Item",     width = 180, sortable = true},
    {key = "qty",      label = "Qty",      width = 40,  align = "CENTER", sortable = true},
    {key = "quality",  label = "Quality",  width = 70,  sortable = true},
    {key = "price",    label = "Price",    width = 80,  sortable = true},
    {key = "realm",    label = "Realm",    width = 120, sortable = true},
})
UI.transformPreviewTable:SetSort("name", true)
if UI._RegisterTable then UI._RegisterTable(UI.transformPreviewTable) end

local previewStatus = transformPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
previewStatus:SetPoint("TOPLEFT", previewContainer, "BOTTOMLEFT", 8, -2)
previewStatus:SetTextColor(0.5, 0.5, 0.5)
previewStatus:SetText("")

-- ==========================================
-- OUTPUT AREA
-- ==========================================

local outputScroll = CreateFrame("ScrollFrame", "FlipQueueTransformOutputScroll", transformPage, "UIPanelScrollFrameTemplate")
outputScroll:SetPoint("TOPLEFT", previewContainer, "BOTTOMLEFT", 4, -18)
outputScroll:SetPoint("BOTTOMRIGHT", transformPage, "BOTTOMRIGHT", -24, 4)

local outputEdit = CreateFrame("EditBox", "FlipQueueTransformOutputEdit", outputScroll)
outputEdit:SetMultiLine(true)
outputEdit:SetAutoFocus(false)
outputEdit:SetFontObject("ChatFontNormal")
outputEdit:SetWidth(outputScroll:GetWidth() or 500)
outputScroll:SetScrollChild(outputEdit)
outputScroll:SetScript("OnSizeChanged", function(sf, w)
    outputEdit:SetWidth(w)
end)
outputEdit:SetScript("OnEscapePressed", function() outputEdit:ClearFocus() end)

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
    configArea:Show()

    if sourceMode == "tsm" then
        if tsmGroupTree and ns.TSM and ns.TSM:IsEnabled() then
            tsmTreeFrame:Show()
            configArea:Hide()
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
            srcStatus:SetText(ns.COLORS.GRAY .. "TSM not available|r")
        end

    elseif sourceMode == "imports" then
        -- Show import source info
        local count = ns:ImportGetCount("fpScanner")
        srcStatus:ClearAllPoints()
        srcStatus:SetPoint("TOPLEFT", configArea, "BOTTOMLEFT", 0, -2)
        srcStatus:SetText(count > 0
            and (ns.COLORS.YELLOW .. count .. " deals|r in imports")
            or (ns.COLORS.GRAY .. "No imports — use Import page first|r"))

    elseif sourceMode == "inventory" then
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
            configArea:Hide()
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
                    UI:RefreshTransformPage()
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
            -- Hide extra rows
            for i = #listNames + 1, #auctListRows do
                auctListRows[i]:Hide()
            end
            auctListContent:SetHeight(math.max(1, auctY))
        else
            srcStatus:ClearAllPoints()
            srcStatus:SetPoint("TOPLEFT", configArea, "BOTTOMLEFT", 0, -2)
            srcStatus:SetText(ns.COLORS.GRAY .. "Auctionator not loaded or no shopping lists|r")
        end
    end
end

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

    -- Show/hide price settings based on output format
    if outputFormat == "aaa" then
        priceRow:Show()
    else
        priceRow:Hide()
    end
end

local function RepositionLayout()
    -- Calculate dynamic Y offsets based on visible elements
    local configBottom = -56  -- default: after source row + config area
    if sourceMode == "tsm" and tsmTreeFrame:IsShown() then
        configBottom = -28 - tsmTreeFrame:GetHeight() - 4
        if srcStatus:GetText() ~= "" then
            configBottom = configBottom - 14
        end
    elseif sourceMode == "auctionator" and auctListFrame:IsShown() then
        configBottom = -28 - auctListFrame:GetHeight() - 4
    end

    -- Output row
    outLabel:ClearAllPoints()
    outLabel:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, configBottom)

    -- Price row (if visible)
    local priceBottom = configBottom - 22
    priceRow:ClearAllPoints()
    priceRow:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 8, priceBottom)

    -- Preview table
    local previewTop = priceBottom - (outputFormat == "aaa" and 24 or 2)
    previewContainer:ClearAllPoints()
    previewContainer:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 0, previewTop)
    previewContainer:SetPoint("RIGHT", transformPage, "RIGHT", 0, 0)

    -- Dynamic height: split remaining space between preview and output
    local pageHeight = transformPage:GetHeight()
    local remainingSpace = pageHeight + previewTop - 4  -- 4px bottom margin
    local previewHeight = math.max(80, math.floor(remainingSpace * 0.45))
    local outputHeight = remainingSpace - previewHeight - 20 -- 20 for status text

    previewContainer:SetHeight(previewHeight)

    -- Preview status
    previewStatus:ClearAllPoints()
    previewStatus:SetPoint("TOPLEFT", previewContainer, "BOTTOMLEFT", 8, -2)

    -- Output scroll
    outputScroll:ClearAllPoints()
    outputScroll:SetPoint("TOPLEFT", previewContainer, "BOTTOMLEFT", 4, -18)
    outputScroll:SetPoint("BOTTOMRIGHT", transformPage, "BOTTOMRIGHT", -24, 4)
end

-- ==========================================
-- LOAD & TRANSFORM
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

local function GenerateOutput(items)
    local T = ns.Transformer
    if not T or #items == 0 then
        return "", 0
    end

    if outputFormat == "aaa" then
        local output, ic, pc = T:OutputAAAJSON(items, priceDiscount, priceSource)
        return output, ic + pc
    elseif outputFormat == "csv" then
        return T:OutputFPCSV(items)
    elseif outputFormat == "tsmgroup" then
        return T:OutputTSMGroupString(items)
    elseif outputFormat == "auctionator" then
        return T:OutputAuctionatorList(items, outputListName)
    end
    return "", 0
end

local function RunTransform()
    local T = ns.Transformer
    if not T then return end

    currentItems = LoadItems()

    -- Enrich with icons/quality
    T:Enrich(currentItems)

    -- Merge duplicates for preview
    local merged = T:MergeByKey(currentItems)

    -- Build preview table data
    local QualityColorName = UI._QualityColorName
    local previewData = {}
    for _, item in ipairs(merged) do
        local displayName = item.name or "Unknown"
        if QualityColorName and item.quality then
            displayName = QualityColorName(displayName, item.quality)
        end

        local priceStr = ""
        if item.expectedPrice then
            if type(item.expectedPrice) == "number" then
                priceStr = string.format("%.0fg", item.expectedPrice)
            else
                priceStr = tostring(item.expectedPrice)
            end
        end

        table.insert(previewData, {
            name    = displayName,
            qty     = item.quantity or 1,
            quality = item.quality or "",
            price   = priceStr,
            realm   = item.targetRealm or "",
            _icon   = item.icon,
            _tooltipItemID = tonumber(tostring(item.itemID)) or nil,
            _tooltipText = item.name,
        })
    end

    UI.transformPreviewTable:SetData(previewData)
    previewStatus:SetText(ns.COLORS.GREEN .. #merged .. " items|r loaded from " .. sourceMode)

    -- Generate output
    local output, count = GenerateOutput(currentItems)
    outputEdit:SetText(output)
    if output ~= "" then
        outputEdit:HighlightText()
        outputEdit:SetFocus(true)
    end
end

-- ==========================================
-- BUTTON WIRING
-- ==========================================

local function SetSource(mode)
    sourceMode = mode
    sourceValue = ""
    UI:RefreshTransformPage()
end

srcTSMBtn:SetScript("OnClick", function() SetSource("tsm") end)
srcImportsBtn:SetScript("OnClick", function() SetSource("imports") end)
srcInvBtn:SetScript("OnClick", function() SetSource("inventory") end)
srcAuctBtn:SetScript("OnClick", function() SetSource("auctionator") end)

local function SetOutput(fmt)
    outputFormat = fmt
    UI:RefreshTransformPage()
end

outAAABtn:SetScript("OnClick", function() SetOutput("aaa") end)
outCSVBtn:SetScript("OnClick", function() SetOutput("csv") end)
outTSMBtn:SetScript("OnClick", function() SetOutput("tsmgroup") end)
outAuctBtn:SetScript("OnClick", function() SetOutput("auctionator") end)

-- ==========================================
-- EXPOSE REFERENCES
-- ==========================================

UI._transformPage = transformPage

-- ==========================================
-- REFRESH
-- ==========================================

function UI:RefreshTransformPage()
    local mainFrame = UI.mainFrame
    mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Transform" .. "|r")
    UI._HideAllActionBtns()

    -- Show "Run" action button
    if not mainFrame.actionBtns.transformRun then
        local btn = CreateFrame("Button", nil, mainFrame.pageTitle:GetParent(), "BackdropTemplate")
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
        btn.text:SetText("Transform")
        btn:SetWidth(btn.text:GetStringWidth() + 16)
        btn:SetScript("OnClick", function()
            RunTransform()
        end)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.3, 1)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Load items from source, apply transforms, and generate output", 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
            GameTooltip:Hide()
        end)
        mainFrame.actionBtns.transformRun = btn
    end

    UI._LayoutActionBtns(mainFrame.actionBtns.transformRun)

    transformPage:Show()

    UpdateSourceButtons()
    UpdateOutputButtons()
    RepositionLayout()

    -- Show preview table
    UI._ShowTable(UI.transformPreviewTable)

    mainFrame.statusText:SetText("Transform pipeline  |  Select source, configure, click Transform")
end
