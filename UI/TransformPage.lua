-- UI/TransformPage.lua
-- Transform page: source -> preview -> output pipeline
local addonName, ns = ...

local UI = ns.UI
local tableContainer = UI.tableContainer

-- ==========================================
-- STATE
-- ==========================================

local sourceMode = "todo"        -- "tsm", "todo", "paste", "inventory", "auctionator"
local sourceValue = ""           -- group path, source name, charKey, list name
local inventoryFilter = "all"    -- "all", "bags", "bank", "warbank"
local outputFormat = "aaa"       -- "aaa", "csv", "tsmgroup", "auctionator", "pbs"
local priceSource = "45% DBRegionMarketAvg"
local priceDiscount = 100
local priceMode = "tsm"          -- "tsm" (TSM × discount) or "imported" (PBS maxPrice / expectedPrice raw)
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

local srcTodoBtn = CreateToggleBtn("To-Do", transformPage)
srcTodoBtn:SetPoint("LEFT", srcTSMBtn, "RIGHT", 4, 0)

local srcPasteBtn = CreateToggleBtn("Paste", transformPage)
srcPasteBtn:SetPoint("LEFT", srcTodoBtn, "RIGHT", 4, 0)

local srcInvBtn = CreateToggleBtn("Inventory", transformPage)
srcInvBtn:SetPoint("LEFT", srcPasteBtn, "RIGHT", 4, 0)

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

-- To-Do list picker
local todoListFrame = CreateFrame("Frame", nil, transformPage)
todoListFrame:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 4, -28)
todoListFrame:SetPoint("RIGHT", transformPage, "RIGHT", -4, 0)
todoListFrame:SetHeight(80)
todoListFrame:Hide()

local todoFilterLabel = todoListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
todoFilterLabel:SetPoint("TOPLEFT", todoListFrame, "TOPLEFT", 4, 0)
todoFilterLabel:SetText("Tasks:")
todoFilterLabel:SetTextColor(0.6, 0.6, 0.6)

local todoActionFilter = "all"  -- "all", "buy", "sell"
local todoFilterBtns = {}
local todoFilterNames = {"all", "buy", "sell"}
local todoFilterLabels = {all = "All", buy = "Buy", sell = "Sell"}

local prevTodoFilterBtn
for _, mode in ipairs(todoFilterNames) do
    local btn = CreateToggleBtn(todoFilterLabels[mode], todoListFrame)
    if prevTodoFilterBtn then
        btn:SetPoint("LEFT", prevTodoFilterBtn, "RIGHT", 4, 0)
    else
        btn:SetPoint("LEFT", todoFilterLabel, "RIGHT", 6, 0)
    end
    local capturedMode = mode
    btn:SetScript("OnClick", function()
        todoActionFilter = capturedMode
        for m, b in pairs(todoFilterBtns) do
            b._active = (todoActionFilter == m)
            if todoActionFilter == m then
                b:SetBackdropColor(0.2, 0.4, 0.2, 1)
            else
                b:SetBackdropColor(0.15, 0.15, 0.2, 1)
            end
        end
    end)
    todoFilterBtns[mode] = btn
    prevTodoFilterBtn = btn
end

local todoListScroll = CreateFrame("ScrollFrame", nil, todoListFrame, "UIPanelScrollFrameTemplate")
todoListScroll:SetPoint("TOPLEFT", todoListFrame, "TOPLEFT", 0, -18)
todoListScroll:SetPoint("BOTTOMRIGHT", todoListFrame, "BOTTOMRIGHT", -16, 0)

local todoListContent = CreateFrame("Frame", nil, todoListScroll)
todoListContent:SetWidth(1)
todoListContent:SetHeight(1)
todoListScroll:SetScrollChild(todoListContent)
todoListScroll:SetScript("OnSizeChanged", function(sf, w)
    todoListContent:SetWidth(w)
end)
local todoListRows = {}
local todoSelectedIndex = nil  -- nil = active, 1..N = queued index

-- Paste (raw data) area
local pasteFrame = CreateFrame("Frame", nil, transformPage)
pasteFrame:SetPoint("TOPLEFT", transformPage, "TOPLEFT", 4, -28)
pasteFrame:SetPoint("RIGHT", transformPage, "RIGHT", -4, 0)
pasteFrame:SetHeight(90)
pasteFrame:Hide()

local pasteInstr = pasteFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
pasteInstr:SetPoint("TOPLEFT", pasteFrame, "TOPLEFT", 4, 0)
pasteInstr:SetText("Paste data below (auto-detects format: FP, CSV, TSM, Auctionator, PBS, item names)")
pasteInstr:SetTextColor(0.6, 0.6, 0.6)

local pasteEditBg = CreateFrame("Frame", nil, pasteFrame, "BackdropTemplate")
pasteEditBg:SetPoint("TOPLEFT", pasteFrame, "TOPLEFT", 0, -14)
pasteEditBg:SetPoint("BOTTOMRIGHT", pasteFrame, "BOTTOMRIGHT", 0, 0)
pasteEditBg:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = {left = 2, right = 2, top = 2, bottom = 2},
})
pasteEditBg:SetBackdropColor(0.08, 0.08, 0.12, 1)
pasteEditBg:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

local pasteScroll = CreateFrame("ScrollFrame", nil, pasteEditBg, "UIPanelScrollFrameTemplate")
pasteScroll:SetPoint("TOPLEFT", pasteEditBg, "TOPLEFT", 6, -4)
pasteScroll:SetPoint("BOTTOMRIGHT", pasteEditBg, "BOTTOMRIGHT", -22, 4)

local pasteEdit = CreateFrame("EditBox", nil, pasteScroll)
pasteEdit:SetMultiLine(true)
pasteEdit:SetAutoFocus(false)
pasteEdit:SetFontObject("ChatFontNormal")
pasteEdit:SetWidth(400)
pasteScroll:SetScrollChild(pasteEdit)
pasteScroll:SetScript("OnSizeChanged", function(sf, w)
    pasteEdit:SetWidth(w)
end)
pasteEdit:SetScript("OnEscapePressed", function() pasteEdit:ClearFocus() end)

local pastedItems = {}  -- parsed items from paste

-- Source status text
local srcStatus = transformPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
srcStatus:SetPoint("TOPLEFT", configArea, "BOTTOMLEFT", 0, -2)
srcStatus:SetTextColor(0.5, 0.5, 0.5)
srcStatus:SetText("")

-- ==========================================
-- PREVIEW BUTTON + WARM CACHE BUTTON
-- ==========================================

local previewBtn = CreateActionBtn("Preview Source", transformPage)

-- Warm Cache button: proactively loads WoW's client item cache for every
-- item ID TSM's per-realm pricing data has seen, so PBS files from other
-- users (items the local player has never personally searched for) can
-- resolve names → IDs. Shown only when there are unresolved items after
-- the initial preview. See the Warm Cache state machine further down.
local warmCacheBtn = CreateActionBtn("Deep Search", transformPage)
warmCacheBtn:Hide()

-- Forward declarations for the Warm Cache state machine so DoPreview /
-- RepositionLayout / SetSource / the button click handler (all defined
-- earlier in the file) can reference them. Assigned to the real
-- implementations further down.
local UpdateWarmCacheButtonVisibility
local StartWarmCache
local CompleteWarmCache
local CancelWarm

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

local outPBSBtn = CreateToggleBtn("PBS", transformPage)
outPBSBtn:SetPoint("LEFT", outAuctBtn, "RIGHT", 4, 0)

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

-- TSM price source dropdown
local PRICE_SOURCE_OPTIONS = {
    "DBMarket",
    "DBMinBuyout",
    "DBHistorical",
    "DBRegionMarketAvg",
    "DBRegionSaleAvg",
    "45% DBRegionMarketAvg",
    "70% DBRegionMarketAvg",
    "80% DBMarket",
}

local priceSrcBox = CreateFrame("Button", nil, priceRow, "BackdropTemplate")
priceSrcBox:SetSize(180, 20)
priceSrcBox:SetPoint("LEFT", priceSrcLabel, "RIGHT", 4, 0)
priceSrcBox:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = {left = 2, right = 2, top = 2, bottom = 2},
})
priceSrcBox:SetBackdropColor(0.1, 0.1, 0.15, 1)
priceSrcBox:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
priceSrcBox.text = priceSrcBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
priceSrcBox.text:SetPoint("LEFT", 6, 0)
priceSrcBox.text:SetPoint("RIGHT", -14, 0)
priceSrcBox.text:SetJustifyH("LEFT")
priceSrcBox.text:SetText(priceSource)
local priceSrcArrow = priceSrcBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
priceSrcArrow:SetPoint("RIGHT", -3, 0)
priceSrcArrow:SetText("v")
priceSrcArrow:SetTextColor(0.5, 0.5, 0.6)

-- Dropdown menu frame
local priceSrcMenu = CreateFrame("Frame", nil, priceSrcBox, "BackdropTemplate")
priceSrcMenu:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = {left = 2, right = 2, top = 2, bottom = 2},
})
priceSrcMenu:SetBackdropColor(0.06, 0.06, 0.1, 0.95)
priceSrcMenu:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
priceSrcMenu:SetPoint("TOPLEFT", priceSrcBox, "BOTTOMLEFT", 0, -2)
priceSrcMenu:SetFrameStrata("DIALOG")
priceSrcMenu:Hide()

local function SetPriceSource(val)
    priceSource = val
    priceSrcBox.text:SetText(val)
    if ns.db and ns.db.settings then ns.db.settings.transformPriceSource = val end
    priceSrcMenu:Hide()
end

local function BuildPriceSourceMenu()
    -- Collect options; include current value if not in the standard list
    local options = {}
    local seen = {}
    for _, opt in ipairs(PRICE_SOURCE_OPTIONS) do
        options[#options + 1] = opt
        seen[opt] = true
    end
    if not seen[priceSource] and priceSource ~= "" then
        table.insert(options, 1, priceSource)
    end

    local ROW_HEIGHT = 18
    local menuRows = priceSrcMenu.rows or {}
    for _, r in ipairs(menuRows) do r:Hide() end

    for i, opt in ipairs(options) do
        local row = menuRows[i]
        if not row then
            row = CreateFrame("Button", nil, priceSrcMenu)
            row:SetHeight(ROW_HEIGHT)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.text:SetPoint("LEFT", 6, 0)
            row.text:SetJustifyH("LEFT")
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            menuRows[i] = row
        end
        row:SetPoint("TOPLEFT", priceSrcMenu, "TOPLEFT", 2, -(i - 1) * ROW_HEIGHT - 2)
        row:SetPoint("RIGHT", priceSrcMenu, "RIGHT", -2, 0)
        row.text:SetText(opt)
        if opt == priceSource then
            row.text:SetTextColor(0.3, 1, 0.3)
        else
            row.text:SetTextColor(0.8, 0.8, 0.8)
        end
        row:SetScript("OnClick", function() SetPriceSource(opt) end)
        row:Show()
    end
    priceSrcMenu.rows = menuRows
    priceSrcMenu:SetSize(priceSrcBox:GetWidth(), #options * ROW_HEIGHT + 4)
end

priceSrcBox:SetScript("OnClick", function()
    if priceSrcMenu:IsShown() then
        priceSrcMenu:Hide()
    else
        BuildPriceSourceMenu()
        priceSrcMenu:Show()
    end
end)
priceSrcBox:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.15, 0.15, 0.2, 1)
end)
priceSrcBox:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.1, 0.1, 0.15, 1)
end)
-- Close when clicking elsewhere
priceSrcMenu:SetScript("OnShow", function(self)
    self:SetPropagateKeyboardInput(true)
end)
priceSrcBox:SetScript("OnHide", function() priceSrcMenu:Hide() end)

-- Price mode toggle: TSM discount (default, uses the discount% and price
-- source above) vs Imported (uses PBS maxPrice / expectedPrice directly,
-- no discount). Useful when importing a PBS snipe list where each item
-- has a hand-set max-price the user wants AAA to use as-is.
local priceModeLabel = priceRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
priceModeLabel:SetPoint("LEFT", priceSrcBox, "RIGHT", 16, 0)
priceModeLabel:SetText("Mode:")
priceModeLabel:SetTextColor(0.6, 0.6, 0.6)

local priceModeTSMBtn = CreateToggleBtn("TSM discount", priceRow)
priceModeTSMBtn:SetPoint("LEFT", priceModeLabel, "RIGHT", 6, 0)

local priceModeImportedBtn = CreateToggleBtn("Imported", priceRow)
priceModeImportedBtn:SetPoint("LEFT", priceModeTSMBtn, "RIGHT", 4, 0)

local function UpdatePriceModeButtons()
    priceModeTSMBtn._active = (priceMode == "tsm")
    priceModeImportedBtn._active = (priceMode == "imported")
    if priceMode == "tsm" then
        priceModeTSMBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
        priceModeImportedBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    else
        priceModeTSMBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        priceModeImportedBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
    end
end

priceModeTSMBtn:SetScript("OnClick", function()
    priceMode = "tsm"
    UpdatePriceModeButtons()
    if ns.db and ns.db.settings then ns.db.settings.transformPriceMode = "tsm" end
end)

priceModeImportedBtn:SetScript("OnClick", function()
    priceMode = "imported"
    UpdatePriceModeButtons()
    if ns.db and ns.db.settings then ns.db.settings.transformPriceMode = "imported" end
end)

UpdatePriceModeButtons()

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
    local modes = {tsm = srcTSMBtn, todo = srcTodoBtn, paste = srcPasteBtn, inventory = srcInvBtn, auctionator = srcAuctBtn}
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
    todoListFrame:Hide()
    pasteFrame:Hide()
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

    elseif sourceMode == "todo" then
        todoListFrame:Show()

        -- Update filter button visuals
        for m, btn in pairs(todoFilterBtns) do
            btn._active = (todoActionFilter == m)
            if todoActionFilter == m then
                btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
            else
                btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
            end
        end

        -- Build list of available to-do lists
        local entries = {}  -- { label, index (nil=active, 1..N=queued), taskCount }
        local TL = ns.TodoList
        if TL then
            local active = TL:GetCurrentList()
            if active and active.tasks and #active.tasks > 0 then
                local label = (active.name and active.name ~= "") and active.name or "Active List"
                table.insert(entries, {
                    label = "|cff00ff00[Active]|r " .. label,
                    index = nil,
                    taskCount = #active.tasks,
                })
            end
            local queued = TL:GetQueuedLists()
            for qi, qList in ipairs(queued) do
                if qList.tasks and #qList.tasks > 0 then
                    local label = (qList.name and qList.name ~= "") and qList.name or ("Queued #" .. qi)
                    table.insert(entries, {
                        label = ns.COLORS.YELLOW .. "[Queued]|r " .. label,
                        index = qi,
                        taskCount = #qList.tasks,
                    })
                end
            end
        end

        if #entries > 0 then
            local listHeight = math.min(80, math.max(20, #entries * 18 + 4))
            todoListFrame:SetHeight(listHeight + 18)  -- +18 for filter row
            todoListContent:SetWidth(todoListScroll:GetWidth() or 200)

            local todoY = 0
            for idx, entry in ipairs(entries) do
                local row = todoListRows[idx]
                if not row then
                    row = CreateFrame("Button", nil, todoListContent)
                    row:SetHeight(18)
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
                    row.label:SetPoint("RIGHT", row, "RIGHT", -40, 0)
                    row.label:SetJustifyH("LEFT")
                    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                    row.count:SetJustifyH("RIGHT")
                    row:EnableMouse(true)
                    todoListRows[idx] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", todoListContent, "TOPLEFT", 0, -todoY)
                row:SetPoint("RIGHT", todoListContent, "RIGHT", 0, 0)

                local isSelected = (todoSelectedIndex == entry.index)
                if isSelected then
                    row.bg:SetColorTexture(0.2, 0.35, 0.5, 0.6)
                    row.label:SetText("|cffffffff" .. entry.label .. "|r")
                else
                    row.bg:SetColorTexture(0, 0, 0, 0)
                    row.label:SetText(entry.label)
                end
                row.count:SetText(ns.COLORS.GRAY .. entry.taskCount .. " tasks|r")

                local capturedIndex = entry.index
                row:SetScript("OnClick", function()
                    todoSelectedIndex = capturedIndex
                    UpdateSourceButtons()
                end)
                row:SetScript("OnEnter", function(self)
                    if not isSelected then self.bg:SetColorTexture(1, 1, 1, 0.05) end
                end)
                row:SetScript("OnLeave", function(self)
                    if todoSelectedIndex ~= capturedIndex then self.bg:SetColorTexture(0, 0, 0, 0) end
                end)

                row:Show()
                todoY = todoY + 18
            end
            for i = #entries + 1, #todoListRows do
                todoListRows[i]:Hide()
            end
            todoListContent:SetHeight(math.max(1, todoY))

            -- Auto-select active list if nothing selected yet
            if todoSelectedIndex == nil and entries[1] then
                todoSelectedIndex = entries[1].index
            end
        else
            todoListFrame:SetHeight(18)
            srcStatus:ClearAllPoints()
            srcStatus:SetPoint("TOPLEFT", todoListFrame, "BOTTOMLEFT", 4, -2)
            srcStatus:SetText(ns.COLORS.GRAY .. "No to-do lists with tasks|r")
        end

    elseif sourceMode == "paste" then
        pasteFrame:Show()
        if #pastedItems > 0 then
            srcStatus:ClearAllPoints()
            srcStatus:SetPoint("TOPLEFT", pasteFrame, "BOTTOMLEFT", 4, -2)
            srcStatus:SetText(ns.COLORS.YELLOW .. #pastedItems .. " items|r parsed from pasted data")
        end

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
    local modes = {
        aaa = outAAABtn, csv = outCSVBtn, tsmgroup = outTSMBtn,
        auctionator = outAuctBtn, pbs = outPBSBtn,
    }
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
    elseif sourceMode == "todo" and todoListFrame:IsShown() then
        configBottom = configBottom - todoListFrame:GetHeight() - 4
        if srcStatus:GetText() ~= "" then
            configBottom = configBottom - 14
        end
    elseif sourceMode == "paste" and pasteFrame:IsShown() then
        configBottom = configBottom - pasteFrame:GetHeight() - 4
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

    -- Warm Cache button sits to the right of Preview when visible
    warmCacheBtn:ClearAllPoints()
    warmCacheBtn:SetPoint("LEFT", previewBtn, "RIGHT", 8, 0)
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
    elseif sourceMode == "todo" then
        return T:InputFromTodoList(todoSelectedIndex, todoActionFilter)
    elseif sourceMode == "paste" then
        -- Parse fresh from the edit box text
        if ns.Import and ns.Import.Parse then
            local text = pasteEdit:GetText()
            if text and text ~= "" then
                pastedItems = ns.Import:Parse(text)
                return pastedItems
            end
        end
        return {}
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

        -- Detail: owner for inventory, realm for imports, PBS filter for
        -- imported shopping lists, group path for TSM
        local detailStr = ""
        if item._owner and item._owner ~= "" then
            detailStr = item._owner
        elseif item.targetRealm and item.targetRealm ~= "" then
            detailStr = item.targetRealm
        elseif item._pbs then
            -- Surface the most useful PBS filter in the detail column so
            -- users can see their imported search constraints at a glance.
            local pbs = item._pbs
            local parts = {}
            if pbs.minItemLevel or pbs.maxItemLevel then
                if pbs.minItemLevel and pbs.maxItemLevel and pbs.minItemLevel == pbs.maxItemLevel then
                    parts[#parts + 1] = "ilvl=" .. pbs.minItemLevel
                elseif pbs.minItemLevel and pbs.maxItemLevel then
                    parts[#parts + 1] = "ilvl " .. pbs.minItemLevel .. "-" .. pbs.maxItemLevel
                elseif pbs.minItemLevel then
                    parts[#parts + 1] = "ilvl\226\137\165" .. pbs.minItemLevel  -- ≥
                elseif pbs.maxItemLevel then
                    parts[#parts + 1] = "ilvl\226\137\164" .. pbs.maxItemLevel  -- ≤
                end
            end
            if pbs.maxPrice and pbs.maxPrice > 0 then
                parts[#parts + 1] = "\226\137\164" .. pbs.maxPrice .. "g"  -- ≤ Ng
            end
            if pbs.tier then
                parts[#parts + 1] = "R" .. pbs.tier
            end
            detailStr = table.concat(parts, " ")
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
    local diag = {
        names = 0, pets = 0, tsmLookups = 0, tsmHits = 0,
        importPriced = 0, unpriced = 0, tsmAvail = tsmAvail,
        resolved = 0,         -- items with a numeric itemID (or battle pet)
        unresolved = 0,       -- items lacking an itemID (name→ID resolution miss)
        nameless = 0,         -- items with numeric ID but placeholder name ("Item NNNN" / "Unknown")
        bySource = {          -- per-source tally of where each item's ID came from
            itemKey = 0, import = 0, inventory = 0, warbank = 0,
            pbs = 0, tsm = 0, cache = 0, lookup = 0,
        },
    }
    for _, item in ipairs(items) do
        if item._nameResolved then diag.names = diag.names + 1 end
        if item.isBattlePet then
            diag.pets = diag.pets + 1
            diag.resolved = diag.resolved + 1
        else
            local numID = tonumber(item.itemID)
            if numID and numID > 0 then
                diag.resolved = diag.resolved + 1
                local iname = item.name or ""
                if iname == "Unknown" or iname:match("^Item %d+$") then
                    diag.nameless = diag.nameless + 1
                end
                local src = item._resolvedFrom
                if src and diag.bySource[src] ~= nil then
                    diag.bySource[src] = diag.bySource[src] + 1
                end
            else
                diag.unresolved = diag.unresolved + 1
            end
        end
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

-- Build a name→itemID map from all available data: imports, inventory,
-- warbank, PBS's item-key cache, TSM's persistent item-info cache, and
-- (on-demand) proactively-warmed client cache entries.
--
-- Each map entry is a `{ id = <numericID>, source = <sourceTag> }` tuple so
-- the preview can show a per-source breakdown of where each resolved item
-- came from — useful for debugging "why didn't this item resolve?" and for
-- deciding whether to offer the user the Warm Cache button.
--
-- Source tags used by consumers:
--   "import"    -- ns.db.imports (FP scanner CSVs etc.)
--   "inventory" -- ns.db.characters[*].inventory
--   "warbank"   -- ns.db.warbank
--   "pbs"       -- PointBlankSniper.ItemKeyCache
--   "tsm"       -- TSMItemInfoDB (persisted TSM item cache)
--   "cache"     -- client item cache (post-warming, via LookupItemInfo)
--   "itemKey"   -- parsed out of the item's own itemKey field
--
-- PBS and TSM are the decisive sources for PBS file imports: a snipe list
-- is typically filled with items the user does NOT own (that's the point
-- of sniping), so FlipQueue's own data sources miss on most entries and
-- C_Item.GetItemIDForItemInfo only works for items in the client cache
-- (~0% hit rate for rare mounts/tools in a snipe list). PBS's cache covers
-- user-authored files; TSM's cache covers foreign files the user imports
-- from other people.
local nameToIDMap   ---@type table<string, {id:integer, source:string}>
local nameMapCounts ---@type table<string, integer> source → count of entries

local function GetNameToIDMap()
    if nameToIDMap then return nameToIDMap, nameMapCounts end
    nameToIDMap = {}
    nameMapCounts = {
        import = 0, inventory = 0, warbank = 0,
        pbs = 0, tsm = 0, cache = 0,
    }
    if not ns.db then return nameToIDMap, nameMapCounts end

    local function addEntry(lname, id, source)
        if not lname or lname == "" or nameToIDMap[lname] then return end
        if not id or id <= 0 then return end
        nameToIDMap[lname] = { id = id, source = source }
        nameMapCounts[source] = (nameMapCounts[source] or 0) + 1
    end

    -- Import database (FP CSV imports have item IDs)
    if ns.db.imports then
        for _, srcMap in pairs(ns.db.imports) do
            for _, importItem in pairs(srcMap) do
                local name = importItem.name and importItem.name:lower()
                addEntry(name, tonumber(importItem.itemID), "import")
            end
        end
    end

    -- Character inventories
    for _, charData in pairs(ns.db.characters or {}) do
        if charData.inventory and charData.inventory.items then
            for _, itemData in pairs(charData.inventory.items) do
                local name = itemData.name and itemData.name:lower()
                addEntry(name, tonumber(itemData.itemID), "inventory")
            end
        end
    end

    -- Warbank
    if ns.db.warbank and ns.db.warbank.items then
        for _, itemData in pairs(ns.db.warbank.items) do
            local name = itemData.name and itemData.name:lower()
            addEntry(name, tonumber(itemData.itemID), "warbank")
        end
    end

    -- Helper: extract the first numeric itemID from a TSM-format item key
    -- string. Handles both "i:NNNN" and "i:NNNN::K:b1:b2:..." forms.
    local function firstIDFromKey(k)
        if type(k) ~= "string" then return nil end
        return tonumber(k:match("^i:(%d+)"))
    end

    -- PBS item-key cache (hits on PBS files the user authored themselves)
    -- Structure (see PointBlankSniper/Source/ItemKeyCache/MergeKeys.lua):
    --   orderedKeys = {
    --     names = { "lowercase name", ... },           -- sorted
    --     itemKeyStrings = { {tsmKey, tsmKey2, ...}, ... },  -- parallel
    --   }
    local pbs = _G.PointBlankSniper
    local state = pbs and pbs.ItemKeyCache and pbs.ItemKeyCache.State
    if state then
        local function absorbPBSKey(lname, keyList)
            if not lname or lname == "" or nameToIDMap[lname] then return end
            local id
            if type(keyList) == "table" then
                for _, k in ipairs(keyList) do
                    id = firstIDFromKey(k)
                    if id and id > 0 then break end
                    id = nil
                end
            elseif type(keyList) == "string" then
                id = firstIDFromKey(keyList)
            end
            addEntry(lname, id, "pbs")
        end

        local ordered = state.orderedKeys
        if ordered and ordered.names and ordered.itemKeyStrings then
            for i, name in ipairs(ordered.names) do
                -- PBS already lowercases names (MergeKeys.lua:12)
                absorbPBSKey(name, ordered.itemKeyStrings[i])
            end
        end

        -- Staging area: items PBS has seen this session but hasn't merged
        -- into orderedKeys yet. MergeKeys only runs when PBS decides to
        -- flush, which may not have happened yet when we read the cache.
        local newKeys = state.newKeys
        if newKeys and newKeys.names and newKeys.itemKeyStrings then
            for i, name in ipairs(newKeys.names) do
                absorbPBSKey(name and name:lower(), newKeys.itemKeyStrings[i])
            end
        end
    end

    -- TSM's persistent item-info database (hits on PBS files authored by
    -- OTHER people — the user's personal PBS cache only contains items
    -- they've searched, but TSM's cache is populated from every auction
    -- scan and item-info lookup TSM has ever performed across the user's
    -- TSM lifetime, which typically covers tens of thousands of items
    -- including the kinds of rare mounts and crafted gear that end up in
    -- snipe lists). Structure (see TradeSkillMaster/LibTSMTypes/Source/
    -- Item/ItemInfoCache.lua:21-25, :291-304):
    --   TSMItemInfoDB = {
    --     versionStr  = "...",
    --     data        = "<encoded>",
    --     names       = <LongString>,  -- string | string[] | nil
    --     itemStrings = <LongString>,  -- parallel to names
    --   }
    -- LongString encoding (TSM/LibTSMUtil/Source/BaseType/LongString.lua):
    --   separator = "\002"
    --   chunks    = a single string, or an array of strings each holding
    --               up to MAX_LONG_STRING_ENTRIES = 1000 values
    -- The `names` and `itemStrings` arrays are parallel: element i of
    -- names is the display name of the item whose TSM item-string is
    -- element i of itemStrings. We decode once and reverse-index.
    local tsmDB = _G.TSMItemInfoDB
    if type(tsmDB) == "table" and tsmDB.names and tsmDB.itemStrings then
        local LONG_STRING_SEP = "\002"

        -- Decode a LongString-encoded value (either a single string or a
        -- list of string chunks) into a flat list of values.
        local function decodeLongString(value, out)
            if type(value) == "string" then
                -- gmatch with "([^\002]*)\002" would drop the last value;
                -- append the separator so every value is followed by one.
                for part in (value .. LONG_STRING_SEP):gmatch("([^" .. LONG_STRING_SEP .. "]*)" .. LONG_STRING_SEP) do
                    out[#out + 1] = part
                end
            elseif type(value) == "table" then
                for _, chunk in ipairs(value) do
                    if type(chunk) == "string" then
                        for part in (chunk .. LONG_STRING_SEP):gmatch("([^" .. LONG_STRING_SEP .. "]*)" .. LONG_STRING_SEP) do
                            out[#out + 1] = part
                        end
                    end
                end
            end
        end

        local tsmNames, tsmItemStrings = {}, {}
        decodeLongString(tsmDB.names, tsmNames)
        decodeLongString(tsmDB.itemStrings, tsmItemStrings)

        -- Only use the overlap length — if the two arrays decoded to
        -- different counts we'd be cross-indexing unrelated items. TSM's
        -- own validator does the same check (ItemInfoCache.lua:294).
        local n = math.min(#tsmNames, #tsmItemStrings)
        for i = 1, n do
            local name = tsmNames[i]
            local lname = name and name:lower()
            addEntry(lname, firstIDFromKey(tsmItemStrings[i]), "tsm")
        end
    end

    return nameToIDMap, nameMapCounts
end

-- Folds a newly-warmed cache entry into the name→ID map. Called by the
-- Warm Cache button's GET_ITEM_INFO_RECEIVED handler as each forced-load
-- response arrives.
local function AddWarmedEntry(lname, id)
    if not nameToIDMap then return end
    if not lname or lname == "" or nameToIDMap[lname] then return end
    if not id or id <= 0 then return end
    nameToIDMap[lname] = { id = id, source = "cache" }
    nameMapCounts.cache = (nameMapCounts.cache or 0) + 1
end

-- Process items[startIdx..endIdx] (or all if omitted): resolve IDs, names, prices.
-- Modifies items in place. Diagnostics are tallied separately via BuildDiagnostics.
local function ProcessItems(items, startIdx, endIdx)
    local T = ns.Transformer
    local LookupItemInfo = ns.UI and ns.UI._LookupItemInfo
    local pMap = T and T._GetPetNameMap and T:_GetPetNameMap() or {}
    local idMap = GetNameToIDMap()  -- also populates nameMapCounts

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
                        item._resolvedFrom = item._resolvedFrom or "itemKey"
                    end
                end
            end
            -- 2. From name→ID map (imports + inventory + warbank + PBS + TSM)
            if (not numID or numID <= 0) and item.name and item.name ~= "" then
                local entry = idMap[item.name:lower()]
                if entry then
                    numID = entry.id
                    item.itemID = tostring(entry.id)
                    item._resolvedFrom = entry.source
                end
            end
            -- 3. From WoW API + inventory search (LookupItemInfo). Runs
            -- after the map lookup so post-warm cache hits land here even
            -- if the item wasn't in the map when GetNameToIDMap was built.
            if (not numID or numID <= 0) and LookupItemInfo then
                local _, _, resolvedID = LookupItemInfo(item.itemID, item.itemKey, item.name)
                if resolvedID then
                    numID = resolvedID
                    item.itemID = tostring(resolvedID)
                    item._resolvedFrom = item._resolvedFrom or "lookup"
                end
            end
            -- 4. Pet name hint: if still unresolved and the name matches
            -- a known C_PetJournal species, stash the speciesID so
            -- pet-aware outputs (AAA JSON) can use it. We do NOT
            -- convert to isBattlePet here — PBS and other item-ID-based
            -- outputs need the real item ID, not a speciesID. The
            -- category-gated pet detection above handles the explicit
            -- "pet"/"companions" case; this is the fallback for paste
            -- sources that lack a category field.
            if (not numID or numID <= 0) and item.name and item.name ~= "" then
                local sid = pMap[(item.name):lower()]
                if sid then
                    item._petSpeciesID = sid
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

    -- Unresolved count (items whose name→ID lookup failed and will drop
    -- out of AAA/TSM/FP output because resolveItemID can't produce a
    -- numeric ID). Surfaces what was previously invisible: users pasting
    -- foreign PBS files used to see "64 items" with no indication that
    -- 36 more were silently dropped.
    if diag.unresolved and diag.unresolved > 0 then
        text = text .. "  " .. ns.COLORS.RED .. diag.unresolved .. " unresolved|r"
    end
    if diag.nameless and diag.nameless > 0 then
        text = text .. "  " .. ns.COLORS.YELLOW .. diag.nameless .. " nameless|r"
    end

    -- Per-source breakdown of where resolved items came from. Only shown
    -- when multiple sources contributed, to avoid clutter on simple
    -- imports (e.g. a TSM-group import has 100% itemKey resolution and
    -- showing "itemKey=100" on its own is noise).
    if diag.bySource then
        local srcParts = {}
        local function addSrc(label, n, color)
            if n and n > 0 then
                table.insert(srcParts, (color or "") .. label .. "=" .. n .. (color and "|r" or ""))
            end
        end
        addSrc("itemKey", diag.bySource.itemKey, ns.COLORS.GRAY)
        addSrc("inv", diag.bySource.inventory, "|cff88cc88")
        addSrc("imp", diag.bySource.import, "|cff88cc88")
        addSrc("wb", diag.bySource.warbank, "|cff88cc88")
        addSrc("pbs", diag.bySource.pbs, "|cffffaa00")
        addSrc("tsm", diag.bySource.tsm, "|cff00ccff")
        addSrc("cache", diag.bySource.cache, "|cff44ff88")
        addSrc("lookup", diag.bySource.lookup, ns.COLORS.GRAY)
        if #srcParts >= 2 then
            text = text .. "  " .. ns.COLORS.GRAY .. "(" .. table.concat(srcParts, " ") .. ns.COLORS.GRAY .. ")|r"
        end
    end

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

    -- Invalidate the name→ID map on paste so PBS cache additions from the
    -- current session (items PBS saw via AH searches since the last
    -- preview) are picked up. For other source modes the cached map is
    -- fine because the underlying data sources don't change mid-session.
    if sourceMode == "paste" then
        nameToIDMap = nil
    end

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
                    if UpdateWarmCacheButtonVisibility then
                        UpdateWarmCacheButtonVisibility(diag2)
                    end
                end)
            end

            -- Show/hide the Warm Cache button based on whether unresolved
            -- items remain. The button loads WoW's client item cache for
            -- every item TSM knows about from its per-realm pricing data,
            -- which typically covers PBS files sourced from other players.
            if UpdateWarmCacheButtonVisibility then
                UpdateWarmCacheButtonVisibility(diag)
            end
        end
    end

    processChunk()
end

-- ==========================================
-- WARM CACHE — on-demand client item cache warming
-- ==========================================
-- Problem: when users paste a PBS file authored by someone else (the
-- "expert gives me a snipe list" workflow), most items in the list are
-- neither in the user's inventory nor in their PBS cache nor in TSM's
-- persistent item-info DB. The name→ID resolution chain in ProcessItems
-- misses them, they fall out of the AAA/FP/TSM output, and the user sees
-- "64 of 100 items resolved" with no recourse.
--
-- Fix: on demand, walk every unique item ID TSM's realm-pricing data has
-- seen across every tracked realm (~30-50k IDs for a typical multi-realm
-- user) and fire C_Item.RequestLoadItemDataByID for each. WoW's server
-- streams back item info via GET_ITEM_INFO_RECEIVED. We listen for those
-- events, match incoming names against the unresolved PBS names, and
-- fold matches into the name→ID map with source="cache". When the
-- warming pass completes (or every unresolved name is accounted for),
-- we re-run the preview to fold the newly-resolved items in.
--
-- Throttling: RequestLoadItemDataByID is cheap on the client side but
-- each call hits the server, and firing 30k in one frame gets rate-
-- limited (can cause disconnects on some setups). We batch 250 per
-- 0.05s tick — ~30k/6s, well under any realistic rate limit.

local WARM_BATCH_SIZE = 250
local WARM_TICK_DELAY = 0.05

local warmState = nil  -- active warming session, or nil when idle

CancelWarm = function()
    if not warmState then return end
    if warmState.frame then
        warmState.frame:UnregisterAllEvents()
        warmState.frame:SetScript("OnEvent", nil)
    end
    if warmState.timer then warmState.timer:Cancel() end
    warmState = nil
end

-- Union every item ID we can plausibly warm from any available data
-- source. Used by the Warm Cache button to cast the widest possible net.
--
-- Sources:
--   TSMRealms.realmRaw         — items currently listed on any tracked
--                                 realm's AH, hourly refresh
--   AUCTIONATOR_PRICE_DATABASE — items Auctionator has EVER seen on any
--                                 realm (historical; persists forever,
--                                 critical for rare snipe targets like
--                                 TCG mounts that aren't currently on
--                                 the AH but Auctionator browsed them
--                                 at some point in the past)
--
-- dbKey formats (see Auctionator/Source/Utilities/DBKeyFromLink.lua:1):
--   "NNNN"                -- bare numeric string for non-gear items
--   "g:NNNN:<ilvl>"       -- gear items (modern AH)
--   "gr:NNNN:<suffix>"    -- gear items (legacy AH)
--   "p:NNNN"              -- battle pets (by speciesID, NOT itemID)
local function CollectWarmingPool()
    local seen = {}

    -- TSMRealms per-realm pricing data
    if ns.TSMRealms and ns.TSMRealms.CollectAllItemIDs then
        local tsmIDs = ns.TSMRealms:CollectAllItemIDs()
        for id in pairs(tsmIDs) do seen[id] = true end
    end

    -- Auctionator price database (historical per-realm records)
    local aucDB = _G.AUCTIONATOR_PRICE_DATABASE
    if type(aucDB) == "table" then
        for realm, realmData in pairs(aucDB) do
            -- Skip the "__dbversion" key at the root (not a realm)
            if type(realm) == "string" and realm ~= "__dbversion"
                and type(realmData) == "table" then
                for dbKey in pairs(realmData) do
                    if type(dbKey) == "string" then
                        -- Bare itemID (non-gear items — mounts, consumables,
                        -- reagents, etc.)
                        local id = tonumber(dbKey:match("^(%d+)$"))
                        if id then
                            seen[id] = true
                        else
                            -- Gear items: "g:<id>:<ilvl>"
                            id = tonumber(dbKey:match("^g:(%d+)"))
                            if id then
                                seen[id] = true
                            end
                            -- Gear items (legacy): "gr:<id>:<suffix>"
                            id = tonumber(dbKey:match("^gr:(%d+)"))
                            if id then seen[id] = true end
                        end
                        -- Pets ("p:<speciesID>") are deliberately skipped;
                        -- speciesID ≠ itemID and warming them as items
                        -- would fire spurious server requests.
                    end
                end
            end
        end
    end

    -- TSM group items (selected profile). Every profile contains the
    -- same items (unassigned items fall back to the Default group), so
    -- walking a single profile covers the full item set. This catches
    -- ultra-rare items (TCG mounts, companion pets) that may never
    -- appear on an AH or in Auctionator's history but ARE in the
    -- user's TSM groups. When we fire RequestLoadItemDataByID for
    -- these, the server returns the name, which we match against the
    -- unresolved wanted set.
    if ns.TSM and ns.TSM.GetSelectedProfile then
        local profile = ns.TSM:GetSelectedProfile()
        if profile then
            local itemsDB = ns.TSM:GetItemsDB(profile)
            if type(itemsDB) == "table" then
                for tsmStr in pairs(itemsDB) do
                    local id = type(tsmStr) == "string" and tonumber(tsmStr:match("^i:(%d+)"))
                    if id then seen[id] = true end
                end
            end
        end
    end

    return seen
end

-- Called by DoPreview after a preview completes; decides whether to
-- show the Warm Cache button.
UpdateWarmCacheButtonVisibility = function(diag)
    local unresolvedN = (diag and diag.unresolved) or 0
    local namelessN   = (diag and diag.nameless) or 0
    local missing     = unresolvedN + namelessN
    if missing == 0 then
        warmCacheBtn:Hide()
        return
    end
    -- For unresolved items we need a realm data source to discover IDs;
    -- nameless items already have IDs so they can always be warmed.
    if unresolvedN > 0 then
        local hasSource = (ns.TSMRealms and ns.TSMRealms.IsLoaded and ns.TSMRealms:IsLoaded())
            or (type(_G.AUCTIONATOR_PRICE_DATABASE) == "table")
        if not hasSource and namelessN == 0 then
            warmCacheBtn:Hide()
            return
        end
    end
    warmCacheBtn.text:SetText("Deep Search (" .. missing .. " missing)")
    warmCacheBtn:SetWidth(math.max(140, warmCacheBtn.text:GetStringWidth() + 24))
    warmCacheBtn:Show()
    RepositionLayout()
end

StartWarmCache = function()
    CancelWarm()

    -- Build the wanted set: lowercase names of currently-unresolved items.
    -- These are the names we're trying to resolve via cache warming.
    local wanted = {}
    local wantedCount = 0
    local namelessIDs = {}   -- IDs of items that have a numeric ID but placeholder name
    local namelessCount = 0
    for _, item in ipairs(currentItems) do
        if not item.isBattlePet then
            local numID = tonumber(item.itemID)
            if (not numID or numID <= 0) and item.name and item.name ~= "" then
                wanted[item.name:lower()] = true
                wantedCount = wantedCount + 1
            elseif numID and numID > 0 then
                local iname = item.name or ""
                if iname == "Unknown" or iname:match("^Item %d+$") then
                    namelessIDs[numID] = true
                    namelessCount = namelessCount + 1
                end
            end
        end
    end

    local totalMissing = wantedCount + namelessCount
    if totalMissing == 0 then
        previewStatus:SetText(ns.COLORS.GRAY .. "Nothing to search for.|r")
        warmCacheBtn:Hide()
        return
    end

    -- Collect item IDs to request from ALL available sources (TSM realm
    -- data + Auctionator DB). Flatten the set to an ordered array so we
    -- can batch through it deterministically.
    local idSet = CollectWarmingPool()

    -- Also include nameless items directly — we already know their IDs,
    -- we just need RequestLoadItemDataByID to populate their names.
    for id in pairs(namelessIDs) do
        idSet[id] = true
    end
    local ids = {}
    for id in pairs(idSet) do ids[#ids + 1] = id end
    table.sort(ids)
    local totalIDs = #ids

    if totalIDs == 0 then
        previewStatus:SetText(ns.COLORS.RED .. "No search data available (TSM realm data + Auctionator DB both empty).|r")
        return
    end

    -- Set up the listener frame BEFORE firing any requests so nothing
    -- gets missed. Incoming GET_ITEM_INFO_RECEIVED events arrive async
    -- and carry (itemID, success) — we call GetItemInfo(id) for the
    -- name, match against `wanted`, and fold matches into the map.
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

    warmState = {
        frame = frame,
        ids = ids,
        idx = 1,
        totalIDs = totalIDs,
        wanted = wanted,
        namelessIDs = namelessIDs,
        wantedCount = totalMissing,
        resolved = 0,
        generation = previewGeneration,
    }

    frame:SetScript("OnEvent", function(_, event, itemID, success)
        if event ~= "GET_ITEM_INFO_RECEIVED" then return end
        if not warmState or not success then return end
        local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _ = C_Item.GetItemInfo(itemID)
        if not name then return end
        local foundNew = false
        local lname = name:lower()
        if warmState.wanted[lname] then
            AddWarmedEntry(lname, itemID)
            warmState.wanted[lname] = nil
            warmState.resolved = warmState.resolved + 1
            foundNew = true
        end
        -- Also update nameless items — items that had numeric IDs but
        -- placeholder names ("Item NNNN" / "Unknown"). The server just
        -- told us the real name, so fold it back into currentItems.
        if warmState.namelessIDs[itemID] then
            local itemName, _, quality, _, _, _, _, _, _, tex = C_Item.GetItemInfo(itemID)
            if itemName and itemName ~= "" then
                for _, item in ipairs(currentItems) do
                    if tonumber(item.itemID) == itemID then
                        local iname = item.name or ""
                        if iname == "Unknown" or iname:match("^Item %d+$") then
                            item.name = itemName
                            if quality then item.quality = quality end
                            if tex then item.icon = tex end
                            foundNew = true
                        end
                    end
                end
                warmState.namelessIDs[itemID] = nil
                warmState.resolved = warmState.resolved + 1
            end
        end
        if foundNew then
            -- Update progress text
            if transformPage:IsShown() then
                previewStatus:SetText(string.format(
                    "%sSearching: %d/%d sent, %s%d|r%s resolved of %s%d|r missing",
                    ns.COLORS.YELLOW, warmState.idx - 1, warmState.totalIDs,
                    ns.COLORS.GREEN, warmState.resolved, ns.COLORS.YELLOW,
                    ns.COLORS.RED, warmState.wantedCount
                ))
            end
            -- Early exit if everything resolved
            if warmState.resolved >= warmState.wantedCount then
                CompleteWarmCache()
            end
        end
    end)

    -- Start the batched request loop.
    local function tick()
        if not warmState then return end
        if previewGeneration ~= warmState.generation then
            CancelWarm()
            return
        end

        local endIdx = math.min(warmState.idx + WARM_BATCH_SIZE - 1, warmState.totalIDs)
        for i = warmState.idx, endIdx do
            -- RequestLoadItemDataByID queues a server fetch for the item.
            -- If the item is already cached it's a cheap no-op.
            pcall(C_Item.RequestLoadItemDataByID, warmState.ids[i])
        end
        warmState.idx = endIdx + 1

        if transformPage:IsShown() and previewStatus then
            previewStatus:SetText(string.format(
                "%sSearching: %d/%d sent, %s%d|r%s/%s%d|r resolved",
                ns.COLORS.YELLOW, warmState.idx - 1, warmState.totalIDs,
                ns.COLORS.GREEN, warmState.resolved, ns.COLORS.YELLOW,
                ns.COLORS.RED, warmState.wantedCount
            ))
        end

        if warmState.idx <= warmState.totalIDs then
            warmState.timer = C_Timer.NewTimer(WARM_TICK_DELAY, tick)
        else
            -- All requests sent. The responses are still arriving; wait
            -- a short window for them to finish landing, then re-run
            -- the preview to pick up any items that resolved post-request.
            warmState.timer = C_Timer.NewTimer(1.5, CompleteWarmCache)
        end
    end

    warmCacheBtn:Hide()
    previewStatus:SetText(ns.COLORS.YELLOW .. "Searching: 0/" .. totalIDs .. " sent...|r")
    tick()
end

CompleteWarmCache = function()
    if not warmState then return end
    local resolved = warmState.resolved

    -- Retry pass: some items may have loaded silently without firing
    -- GET_ITEM_INFO_RECEIVED, or the event arrived before GetItemInfo
    -- was ready. One final sweep catches these stragglers.
    local retryResolved = 0
    for _, item in ipairs(currentItems) do
        if not item.isBattlePet then
            local numID = tonumber(item.itemID)
            if numID and numID > 0 then
                local iname = item.name or ""
                if iname == "Unknown" or iname:match("^Item %d+$") then
                    local itemName, _, quality, _, _, _, _, _, _, tex = C_Item.GetItemInfo(numID)
                    if itemName and itemName ~= "" then
                        item.name = itemName
                        if quality then item.quality = quality end
                        if tex then item.icon = tex end
                        retryResolved = retryResolved + 1
                    end
                end
            end
        end
    end
    resolved = resolved + retryResolved

    CancelWarm()
    -- Re-run the preview so items with freshly-cached names flow through
    -- ProcessItems again and pick up their itemIDs from the updated map
    -- (or from C_Item.GetItemIDForItemInfo which now returns non-nil for
    -- warmed items).
    ProcessItems(currentItems)
    local diag = BuildDiagnostics(currentItems)
    local data = BuildPreviewData(currentItems)
    UI.transformPreviewTable:SetData(data)
    previewStatus:SetText(BuildStatusText(currentItems, diag)
        .. "  " .. ns.COLORS.GREEN .. "(+" .. resolved .. " found)|r")
    UpdateWarmCacheButtonVisibility(diag)

    -- Dump remaining unresolved/nameless items to debug so the user can
    -- identify what the client truly can't resolve.
    if ns.PrintDebug then
        local remaining = {}
        for _, item in ipairs(currentItems) do
            if not item.isBattlePet then
                local numID = tonumber(item.itemID)
                if not numID or numID <= 0 then
                    table.insert(remaining, "  [no ID] " .. (item.name or "?"))
                elseif (item.name or "") == "Unknown" or (item.name or ""):match("^Item %d+$") then
                    table.insert(remaining, "  [nameless] id=" .. tostring(numID) .. " name=" .. (item.name or "?"))
                end
            end
        end
        if #remaining > 0 then
            ns:PrintDebug("[deep-search] " .. #remaining .. " items still unresolved after search:")
            for _, line in ipairs(remaining) do
                ns:PrintDebug(line)
            end
        end
    end
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
        local itemsJSON, petsJSON, ic, pc, uic, upc =
            T:OutputAAAJSON(currentItems, priceDiscount, priceSource, priceMode)
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
        -- Prefer the imported list name (set by ParsePBS / ParseAuctionator*
        -- when the source was a shopping-list export) so round-trip
        -- preserves the original name instead of clobbering it with the
        -- static "FlipQueue Export" default.
        local importedName = currentItems[1] and currentItems[1]._listName
        local name = (importedName and importedName ~= "") and importedName or outputListName
        local output = T:OutputAuctionatorList(currentItems, name)
        outputEdit:SetText(output)
        if output ~= "" then
            outputEdit:HighlightText()
        end
    elseif outputFormat == "pbs" then
        -- PBS round-trip: same list-name precedence as Auctionator.
        local importedName = currentItems[1] and currentItems[1]._listName
        local name = (importedName and importedName ~= "") and importedName or outputListName
        local output = T:OutputPBS(currentItems, name)
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

    -- Cancel any in-flight cache warming since the items we were warming
    -- for no longer exist, and hide the button until the next preview
    -- determines whether it's needed again.
    CancelWarm()
    warmCacheBtn:Hide()

    -- Clear table and output
    UI.transformPreviewTable:SetData({})
    previewStatus:SetText("")
    ClearOutputs()

    RepositionLayout()
    UI._ShowTable(UI.transformPreviewTable)
end

srcTSMBtn:SetScript("OnClick", function() SetSource("tsm") end)
srcTodoBtn:SetScript("OnClick", function()
    todoSelectedIndex = nil  -- default to active list
    pastedItems = {}
    SetSource("todo")
end)
srcPasteBtn:SetScript("OnClick", function()
    pastedItems = {}
    SetSource("paste")
end)
srcInvBtn:SetScript("OnClick", function() SetSource("inventory") end)
srcAuctBtn:SetScript("OnClick", function() SetSource("auctionator") end)

previewBtn:SetScript("OnClick", function() DoPreview() end)

warmCacheBtn:SetScript("OnClick", function()
    if StartWarmCache then StartWarmCache() end
end)

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
outPBSBtn:SetScript("OnClick", function() SetOutput("pbs") end)

transformBtn:SetScript("OnClick", function() DoTransform() end)

-- ==========================================
-- EXPOSE REFERENCES
-- ==========================================

UI._transformPage = transformPage

-- Register layout callback for container resize
UI:RegisterPageLayout("transform", function()
    if transformPage:IsShown() then
        RepositionLayout()
    end
end)

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
        priceMode = ns.db.settings.transformPriceMode or priceMode
        priceSrcBox.text:SetText(priceSource)
        priceDiscountBox:SetText(tostring(priceDiscount))
    end

    transformPage:Show()

    UpdateSourceButtons()
    UpdateOutputButtons()
    UpdatePriceModeButtons()
    RepositionLayout()
    UI._ShowTable(UI.transformPreviewTable)

    mainFrame.statusText:SetText("Transform  |  Select source, Preview, then Transform")
end
