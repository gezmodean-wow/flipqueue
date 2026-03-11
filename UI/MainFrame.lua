-- UI/MainFrame.lua
-- Main window: side nav, content area, scroll tables, refresh orchestration
local addonName, ns = ...

local UI = ns.UI

UI.currentPage = "postNow"

-- ==========================================
-- MAIN FRAME (dark, clean styling)
-- ==========================================

local SIDEBAR_WIDTH = 110
local FRAME_WIDTH = 750
local FRAME_HEIGHT = 550

local mainFrame = CreateFrame("Frame", "FlipQueueMainFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
mainFrame:SetPoint("CENTER")
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
mainFrame:SetFrameStrata("HIGH")
mainFrame:SetClampedToScreen(true)
mainFrame:SetResizable(true)
if mainFrame.SetResizeBounds then
    mainFrame:SetResizeBounds(600, 400, 1200, 900)
else
    mainFrame:SetMinResize(600, 400)
    mainFrame:SetMaxResize(1200, 900)
end

-- Resize grip (bottom-right corner)
local resizeGrip = CreateFrame("Button", nil, mainFrame)
resizeGrip:SetSize(16, 16)
resizeGrip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)
resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetScript("OnMouseDown", function()
    mainFrame:StartSizing("BOTTOMRIGHT")
end)
resizeGrip:SetScript("OnMouseUp", function()
    mainFrame:StopMovingOrSizing()
    -- Save size
    if ns.db then
        ns.db.settings.frameWidth = mainFrame:GetWidth()
        ns.db.settings.frameHeight = mainFrame:GetHeight()
    end
end)

mainFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4},
})
mainFrame:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
mainFrame:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)

-- Title bar
local titleBar = CreateFrame("Frame", nil, mainFrame)
titleBar:SetHeight(28)
titleBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -4)
titleBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -4, -4)

local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
titleBg:SetAllPoints()
titleBg:SetColorTexture(0.12, 0.12, 0.18, 1)

local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
titleText:SetText(ns.COLORS.YELLOW .. "FlipQueue" .. ns.COLORS.RESET)

-- Version
local verText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
verText:SetPoint("LEFT", titleText, "RIGHT", 6, 0)
verText:SetText("v" .. ns.VERSION)

-- Close button
local closeBtn = CreateFrame("Button", nil, titleBar)
closeBtn:SetSize(18, 18)
closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
closeBtn:GetHighlightTexture():SetAlpha(0.3)
closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

-- Summary bar (below title)
local summaryBar = CreateFrame("Frame", nil, mainFrame)
summaryBar:SetHeight(20)
summaryBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -1)
summaryBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -1)

local summaryBg = summaryBar:CreateTexture(nil, "BACKGROUND")
summaryBg:SetAllPoints()
summaryBg:SetColorTexture(0.1, 0.1, 0.15, 1)

mainFrame.summary = summaryBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
mainFrame.summary:SetPoint("LEFT", summaryBar, "LEFT", 8, 0)
mainFrame.summary:SetJustifyH("LEFT")

-- ==========================================
-- SIDEBAR
-- ==========================================

local sidebar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
sidebar:SetWidth(SIDEBAR_WIDTH)
sidebar:SetPoint("TOPLEFT", summaryBar, "BOTTOMLEFT", 0, -1)
sidebar:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 4, 4)
sidebar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = nil,
})
sidebar:SetBackdropColor(0.1, 0.1, 0.15, 1)

local NAV_ITEMS = {
    {key = "postNow",    label = "Post Now",    icon = "Interface\\Icons\\INV_Misc_Coin_02"},
    {key = "queue",      label = "Queue",        icon = "Interface\\Icons\\INV_Scroll_03"},
    {key = "log",        label = "Log",          icon = "Interface\\Icons\\INV_Misc_Book_09"},
    {key = "inventory",  label = "Inventory",    icon = "Interface\\Icons\\INV_Misc_Bag_07"},
    {key = "characters", label = "Characters",   icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"},
    {key = "sep"},
    {key = "import",     label = "Import",       icon = "Interface\\Icons\\Ability_Creature_Cursed_04"},
    {key = "export",     label = "Export",       icon = "Interface\\Icons\\INV_Scroll_11"},
    {key = "rescan",     label = "Rescan",       icon = "Interface\\Icons\\Spell_Shadow_MindSteal", action = true},
    {key = "sep2"},
    {key = "settings",   label = "Settings",     icon = "Interface\\Icons\\INV_Gizmo_02"},
}

local navButtons = {}
local navY = -8

for _, nav in ipairs(NAV_ITEMS) do
    if nav.key:find("^sep") then
        local sep = sidebar:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, navY - 4)
        sep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -6, navY - 4)
        sep:SetColorTexture(0.3, 0.3, 0.4, 0.5)
        navY = navY - 10
    else
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetHeight(28)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, navY)
        btn:SetPoint("RIGHT", sidebar, "RIGHT", -4, 0)

        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(1, 1, 1, 0)

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(16, 16)
        btn.icon:SetPoint("LEFT", btn, "LEFT", 6, 0)
        btn.icon:SetTexture(nav.icon)

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
        btn.label:SetText(nav.label)
        btn.label:SetJustifyH("LEFT")

        btn.badge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.badge:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        btn.badge:SetJustifyH("RIGHT")

        btn:SetScript("OnEnter", function(self)
            if UI.currentPage ~= nav.key then
                self.bg:SetColorTexture(1, 1, 1, 0.05)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if UI.currentPage ~= nav.key then
                self.bg:SetColorTexture(1, 1, 1, 0)
            end
        end)

        local navKey = nav.key
        local isAction = nav.action
        btn:SetScript("OnClick", function()
            if isAction then
                if navKey == "import" then
                    UI.importFrame:Show()
                    UI.importEditBox:SetFocus(true)
                elseif navKey == "export" then
                    ns.Export:ShowExportFrame("bags")
                elseif navKey == "rescan" then
                    ns.Scanner:ScanCurrentCharacter()
                    UI:Refresh()
                end
            else
                UI.currentPage = navKey
                UI:Refresh()
            end
        end)

        navButtons[nav.key] = btn
        navY = navY - 30
    end
end

local function UpdateNavHighlights()
    for key, btn in pairs(navButtons) do
        if key == UI.currentPage then
            btn.bg:SetColorTexture(0.2, 0.3, 0.5, 0.6)
            btn.label:SetTextColor(1, 1, 1)
        else
            btn.bg:SetColorTexture(1, 1, 1, 0)
            btn.label:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

-- ==========================================
-- CONTENT AREA
-- ==========================================

local contentArea = CreateFrame("Frame", nil, mainFrame)
contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 1, 0)
contentArea:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -4, 4)

-- Action bar at top of content area
local actionBar = CreateFrame("Frame", nil, contentArea)
actionBar:SetHeight(26)
actionBar:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 0, 0)
actionBar:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", 0, 0)

local actionBg = actionBar:CreateTexture(nil, "BACKGROUND")
actionBg:SetAllPoints()
actionBg:SetColorTexture(0.1, 0.1, 0.15, 1)

mainFrame.pageTitle = actionBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mainFrame.pageTitle:SetPoint("LEFT", actionBar, "LEFT", 8, 0)

-- Action button factory
local function CreateActionBtn(label, tooltip, onClick)
    local btn = CreateFrame("Button", nil, actionBar, "BackdropTemplate")
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

    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.3, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tooltip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        GameTooltip:Hide()
    end)
    return btn
end

-- Context-sensitive action buttons
mainFrame.actionBtns = {}

mainFrame.actionBtns.clearLog = CreateActionBtn("Clear Log", "Remove all entries from the log", function()
    StaticPopupDialogs["FLIPQUEUE_CLEAR_LOG"] = {
        text = "Clear ALL items from the FlipQueue log?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            ns.Queue:ClearLog()
            ns:Print("Log cleared.")
            UI:Refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FLIPQUEUE_CLEAR_LOG")
end)

mainFrame.actionBtns.pullBank = CreateActionBtn("Pull Bank", "Pull queued items from bank to bags", function()
    local saved = ns.db.settings.autoPullBank
    ns.db.settings.autoPullBank = true
    ns.Tracker:AutoPullFromBank()
    ns.db.settings.autoPullBank = saved
end)

mainFrame.actionBtns.clearQueue = CreateActionBtn("Clear Queue", "Remove all items from queue", function()
    StaticPopupDialogs["FLIPQUEUE_CLEAR_ALL"] = {
        text = "Clear ALL items from the FlipQueue?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            ns.Queue:Clear()
            ns:Print("Queue cleared.")
            UI:Refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FLIPQUEUE_CLEAR_ALL")
end)

mainFrame.actionBtns.dnt = CreateActionBtn("DNT List", "Manage Do Not Track list", function()
    UI:ShowDoNotTrackFrame()
end)

mainFrame.actionBtns.importDo = CreateActionBtn("Import", "Import pasted data to queue", function()
    local text = UI._importEdit:GetText()
    if text and text ~= "" then
        local items = ns.Import:Parse(text)
        if #items > 0 then
            local added = ns.Queue:Add(items)
            ns:Print("Imported " .. added .. " new items (" .. #items .. " parsed, duplicates merged).")
            UI._importEdit:SetText("")
            UI._importStatus:SetText(ns.COLORS.GREEN .. added .. " items imported!|r")
            UI:Refresh()
            UI:RefreshMini()
        else
            UI._importStatus:SetText(ns.COLORS.RED .. "No items found in pasted data.|r")
        end
    end
end)

mainFrame.actionBtns.importClear = CreateActionBtn("Clear", "Clear the import text", function()
    UI._importEdit:SetText("")
    UI._importStatus:SetText("")
    UI._importEdit:SetFocus(true)
end)

mainFrame.actionBtns.exportBags = CreateActionBtn("Bags", "Export bag inventory", function()
    local csv, count = ns.Export:ExportBags()
    UI._exportEdit:SetText(csv)
    UI._exportStatus:SetText(ns.COLORS.GREEN .. count .. " items|r from bags")
    UI._exportEdit:HighlightText()
    UI._exportEdit:SetFocus(true)
end)

mainFrame.actionBtns.exportBank = CreateActionBtn("Bank", "Export bank (bank must be open)", function()
    local csv, count = ns.Export:ExportBank()
    UI._exportEdit:SetText(csv)
    UI._exportStatus:SetText(ns.COLORS.GREEN .. count .. " items|r from bank")
    UI._exportEdit:HighlightText()
    UI._exportEdit:SetFocus(true)
end)

mainFrame.actionBtns.exportWarbank = CreateActionBtn("Warbank", "Export warbank (bank must be open)", function()
    local csv, count = ns.Export:ExportWarbank()
    UI._exportEdit:SetText(csv)
    UI._exportStatus:SetText(ns.COLORS.GREEN .. count .. " items|r from warbank")
    UI._exportEdit:HighlightText()
    UI._exportEdit:SetFocus(true)
end)

mainFrame.actionBtns.exportAll = CreateActionBtn("All", "Export all containers (live scan)", function()
    local csv, count = ns.Export:ExportAll()
    UI._exportEdit:SetText(csv)
    UI._exportStatus:SetText(ns.COLORS.GREEN .. count .. " items|r from all containers (live)")
    UI._exportEdit:HighlightText()
    UI._exportEdit:SetFocus(true)
end)

mainFrame.actionBtns.exportSaved = CreateActionBtn("Saved All", "Export all from saved scans (no bank needed)", function()
    local csv, count = ns.Export:ExportSaved("all")
    UI._exportEdit:SetText(csv)
    UI._exportStatus:SetText(ns.COLORS.GREEN .. count .. " items|r from saved data (bags+bank+warbank)")
    UI._exportEdit:HighlightText()
    UI._exportEdit:SetFocus(true)
end)

-- Status bar at bottom of content
local statusBar = CreateFrame("Frame", nil, contentArea)
statusBar:SetHeight(18)
statusBar:SetPoint("BOTTOMLEFT", contentArea, "BOTTOMLEFT", 0, 0)
statusBar:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)

local statusBg = statusBar:CreateTexture(nil, "BACKGROUND")
statusBg:SetAllPoints()
statusBg:SetColorTexture(0.1, 0.1, 0.15, 1)

mainFrame.statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
mainFrame.statusText:SetPoint("LEFT", statusBar, "LEFT", 6, 0)

-- Table container (between action bar and status bar)
local tableContainer = CreateFrame("Frame", nil, contentArea)
tableContainer:SetPoint("TOPLEFT", actionBar, "BOTTOMLEFT", 0, -1)
tableContainer:SetPoint("BOTTOMRIGHT", statusBar, "TOPRIGHT", 0, 0)

UI.tableContainer = tableContainer

-- ==========================================
-- SCROLL TABLES (one per page)
-- ==========================================

-- Post Now columns
UI.postNowTable = UI:CreateScrollTable(tableContainer, {
    {key = "name",     label = "Item",     width = 200, sortable = true},
    {key = "qty",      label = "Qty",      width = 40,  align = "CENTER", sortable = true},
    {key = "price",    label = "Price",    width = 90,  sortable = true},
    {key = "realm",    label = "Realm",    width = 140, sortable = true},
    {key = "location", label = "Location", width = 100, sortable = true},
})
UI.postNowTable:SetSort("name", true)

-- Full Queue columns - "Found On" shows where item exists in inventory
UI.queueTable = UI:CreateScrollTable(tableContainer, {
    {key = "name",    label = "Item",     width = 180, sortable = true},
    {key = "qty",     label = "Qty",      width = 40,  align = "CENTER", sortable = true},
    {key = "price",   label = "Price",    width = 80,  sortable = true},
    {key = "realm",   label = "Sell Realm", width = 130, sortable = true},
    {key = "foundOn", label = "Found On", width = 130, sortable = true},
    {key = "status",  label = "Status",   width = 60,  align = "CENTER", sortable = true},
})
UI.queueTable:SetSort("realm", true)

-- Log columns
UI.logTable = UI:CreateScrollTable(tableContainer, {
    {key = "name",      label = "Item",      width = 170, sortable = true},
    {key = "posted",    label = "Posted",    width = 80,  sortable = true},
    {key = "guide",     label = "FP Guide",  width = 80,  sortable = true},
    {key = "realm",     label = "Realm",     width = 130, sortable = true},
    {key = "character", label = "Character", width = 100, sortable = true},
    {key = "date",      label = "Date",      width = 80,  sortable = true,
        format = function(v) return v or "" end},
})
UI.logTable:SetSort("date", false)

-- Inventory (untracked) columns
UI.inventoryTable = UI:CreateScrollTable(tableContainer, {
    {key = "name",     label = "Item",     width = 220, sortable = true},
    {key = "qty",      label = "Qty",      width = 50,  align = "CENTER", sortable = true},
    {key = "source",   label = "Source",   width = 120, sortable = true},
    {key = "location", label = "Location", width = 150, sortable = true},
})
UI.inventoryTable:SetSort("name", true)

-- Characters table
UI.charsTable = UI:CreateScrollTable(tableContainer, {
    {key = "name",      label = "Character",   width = 110, sortable = true},
    {key = "realm",     label = "Realm",        width = 130, sortable = true},
    {key = "gold",      label = "Gold",         width = 70,  align = "RIGHT", sortable = true},
    {key = "tasks",     label = "Tasks",        width = 40,  align = "CENTER", sortable = true},
    {key = "auctions",  label = "Auctions",     width = 65,  align = "CENTER", sortable = true},
    {key = "lastLogin", label = "Last Login",   width = 75,  sortable = true},
    {key = "status",    label = "Status",       width = 65,  sortable = true},
})
UI.charsTable:SetSort("name", true)

-- "Realms needing characters" table
UI.needCharsTable = UI:CreateScrollTable(tableContainer, {
    {key = "realm",      label = "Realm",           width = 250, sortable = true},
    {key = "itemCount",  label = "Queue Items",     width = 80,  align = "CENTER", sortable = true},
    {key = "totalValue", label = "Est. Value",      width = 100, sortable = true},
    {key = "note",       label = "Note",            width = 180, sortable = false},
})
UI.needCharsTable:SetSort("itemCount", false)

-- Next Steps table (shown on Post Now page)
UI.nextStepsTable = UI:CreateScrollTable(tableContainer, {
    {key = "action",    label = "Action",     width = 90,  sortable = true},
    {key = "target",    label = "Target",     width = 200, sortable = true},
    {key = "itemCount", label = "Items",      width = 50,  align = "CENTER", sortable = true},
    {key = "value",     label = "Est. Value", width = 90,  sortable = true},
    {key = "detail",    label = "Detail",     width = 130, sortable = false},
})
UI.nextStepsTable:SetSort("_sortValue", false)

-- Keep references for backward compatibility
UI.content = tableContainer
UI.contentRows = {}

-- ==========================================
-- IMPORT / EXPORT PAGES (in-frame)
-- ==========================================

-- Import page
local importPage = CreateFrame("Frame", nil, tableContainer)
importPage:SetAllPoints()
importPage:Hide()

local importInstr = importPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
importInstr:SetPoint("TOPLEFT", importPage, "TOPLEFT", 8, -8)
importInstr:SetText("Paste FlippingPal data below, then click Import:")
importInstr:SetTextColor(0.7, 0.7, 0.7)

local importScroll = CreateFrame("ScrollFrame", "FlipQueueImportScrollInline", importPage, "UIPanelScrollFrameTemplate")
importScroll:SetPoint("TOPLEFT", importPage, "TOPLEFT", 4, -28)
importScroll:SetPoint("BOTTOMRIGHT", importPage, "BOTTOMRIGHT", -24, 34)

local importEdit = CreateFrame("EditBox", "FlipQueueImportEditInline", importScroll)
importEdit:SetMultiLine(true)
importEdit:SetAutoFocus(false)
importEdit:SetMaxLetters(0)
importEdit:SetFontObject("ChatFontNormal")
importEdit:SetWidth(importScroll:GetWidth() or 500)
importScroll:SetScrollChild(importEdit)
importScroll:SetScript("OnSizeChanged", function(sf, w)
    importEdit:SetWidth(w)
end)

local importStatus = importPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
importStatus:SetPoint("LEFT", importPage, "BOTTOMLEFT", 8, 17)
importStatus:SetTextColor(0.5, 0.5, 0.5)
importStatus:SetText("")

-- Auto-detect paste
local importLastLen = 0
importEdit:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    local text = self:GetText()
    local newLen = #text
    if importLastLen < 10 and newLen > 50 and text:find("\n") then
        local items = ns.Import:Parse(text)
        if #items > 0 then
            importStatus:SetText(ns.COLORS.GREEN .. #items .. " items detected|r — click Import")
        end
    end
    importLastLen = newLen
end)
importEdit:SetScript("OnEscapePressed", function() importEdit:ClearFocus() end)

UI._importPage = importPage
UI._importEdit = importEdit
UI._importStatus = importStatus

-- Export page
local exportPage = CreateFrame("Frame", nil, tableContainer)
exportPage:SetAllPoints()
exportPage:Hide()

local exportInstr = exportPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
exportInstr:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -8)
exportInstr:SetText("Select source, then Ctrl+A / Ctrl+C to copy:")
exportInstr:SetTextColor(0.7, 0.7, 0.7)

local exportScroll = CreateFrame("ScrollFrame", "FlipQueueExportScrollInline", exportPage, "UIPanelScrollFrameTemplate")
exportScroll:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 4, -28)
exportScroll:SetPoint("BOTTOMRIGHT", exportPage, "BOTTOMRIGHT", -24, 34)

local exportEdit = CreateFrame("EditBox", "FlipQueueExportEditInline", exportScroll)
exportEdit:SetMultiLine(true)
exportEdit:SetAutoFocus(false)
exportEdit:SetFontObject("ChatFontNormal")
exportEdit:SetWidth(exportScroll:GetWidth() or 500)
exportScroll:SetScrollChild(exportEdit)
exportScroll:SetScript("OnSizeChanged", function(sf, w)
    exportEdit:SetWidth(w)
end)
exportEdit:SetScript("OnEscapePressed", function() exportEdit:ClearFocus() end)

local exportStatus = exportPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
exportStatus:SetPoint("LEFT", exportPage, "BOTTOMLEFT", 8, 17)
exportStatus:SetTextColor(0.5, 0.5, 0.5)
exportStatus:SetText("")

UI._exportPage = exportPage
UI._exportEdit = exportEdit
UI._exportStatus = exportStatus

-- ==========================================
-- HIDE/SHOW HELPERS
-- ==========================================

local allTables = {}
local function RegisterTable(tbl)
    table.insert(allTables, tbl)
end
RegisterTable(UI.postNowTable)
RegisterTable(UI.queueTable)
RegisterTable(UI.logTable)
RegisterTable(UI.inventoryTable)
RegisterTable(UI.charsTable)
RegisterTable(UI.needCharsTable)
RegisterTable(UI.nextStepsTable)

local function HideAllTables()
    for _, tbl in ipairs(allTables) do
        tbl.headerFrame:Hide()
        tbl.scrollFrame:Hide()
    end
    UI:HideSettingsPage()
    importPage:Hide()
    exportPage:Hide()
    if UI._nextStepsLabel then UI._nextStepsLabel:Hide() end
    if UI._needCharsLabel then UI._needCharsLabel:Hide() end
    if UI._postSummaryFrame then UI._postSummaryFrame:Hide() end
end

local function ShowTable(tbl)
    tbl.headerFrame:Show()
    tbl.scrollFrame:Show()
end

local function HideAllActionBtns()
    for _, btn in pairs(mainFrame.actionBtns) do
        btn:Hide()
    end
end

local function LayoutActionBtns(...)
    HideAllActionBtns()
    local prev = nil
    for i = 1, select("#", ...) do
        local btn = select(i, ...)
        if prev then
            btn:SetPoint("RIGHT", prev, "LEFT", -4, 0)
        else
            btn:SetPoint("RIGHT", actionBar, "RIGHT", -4, 0)
        end
        btn:Show()
        prev = btn
    end
end

-- Forward declarations (defined later in file)
local QualityColorName
local LookupItemInfo
local CLASS_COLORS

-- ==========================================
-- POST NOW PAGE
-- ==========================================

local function BuildPostNowData()
    if not ns.db then return {} end

    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""
    local tasks = ns.Queue:GetCharacterTasks(charKey)
    local data = {}

    for _, task in ipairs(tasks) do
        if ns:RealmMatches(task.queueItem.targetRealm, myRealm) then
            local qi = task.queueItem
            local displayName = qi.name ~= "" and qi.name or tostring(qi.itemID)

            -- Safely lookup icon/quality (pcall protects against missing API)
            local lookupIcon, quality, resolvedID
            local ok, err = pcall(function()
                lookupIcon, quality, resolvedID = LookupItemInfo(qi.itemID, qi.itemKey, qi.name)
            end)

            if quality then
                displayName = QualityColorName(displayName, quality)
            elseif qi.quality and qi.quality ~= "" then
                displayName = QualityColorName(displayName, qi.quality)
            end

            local locParts = {}
            if task.locations then
                for loc, qty in pairs(task.locations) do
                    table.insert(locParts, loc)
                end
            end

            table.insert(data, {
                name     = displayName,
                qty      = task.quantity,
                price    = qi.expectedPrice or "",
                realm    = qi.targetRealm or "",
                location = table.concat(locParts, ", "),
                _icon    = task.icon or lookupIcon,
                _tooltipItemID = resolvedID,
                _tooltipText   = qi.name ~= "" and qi.name or tostring(qi.itemID),
                _tooltipExtra  = (qi.targetRealm or "") ~= "" and
                    ("Sell on: " .. qi.targetRealm .. "  @  " .. (qi.expectedPrice or "?")) or nil,
                _queueIndex = task.queueIndex,
                _queueItem  = qi,
                _fuzzy = task.fuzzyMatch,
            })
        end
    end

    return data
end

-- ==========================================
-- NEXT STEPS (shown on Post Now page)
-- ==========================================

local function ParseGoldValue(priceStr)
    if not priceStr or priceStr == "" then return 0 end
    local goldNum = priceStr:gsub(",", ""):match("(%d+)g")
    return goldNum and tonumber(goldNum) or 0
end

local function FormatGoldValue(totalGold)
    if totalGold <= 0 then return "" end
    if totalGold >= 1000 then
        return string.format("%.1fk gold", totalGold / 1000)
    end
    return tostring(totalGold) .. " gold"
end

local function BuildNextStepsData()
    if not ns.db then return {} end

    local data = {}
    local myCharKey = ns:GetCharKey()
    local myRealm = myCharKey:match("%-(.+)$") or ""

    -- Track consumed queue indices so each item is counted exactly once
    local consumed = {}

    -- Gather all covered realms from inventory (excluding hidden characters)
    local coveredRealms = {}
    for charKey, _ in pairs(ns.db.inventory) do
        if not ns.db.hiddenCharacters[charKey] then
            local realm = charKey:match("%-(.+)$") or ""
            if realm ~= "" then
                if not coveredRealms[realm] then
                    coveredRealms[realm] = {}
                end
                table.insert(coveredRealms[realm], charKey)
            end
        end
    end

    -- Include external accounts as realm coverage
    if ns.db.externalAccounts then
        for _, acct in ipairs(ns.db.externalAccounts) do
            for _, realm in ipairs(acct.realms) do
                if not coveredRealms[realm] then
                    coveredRealms[realm] = {}
                end
                table.insert(coveredRealms[realm], acct.label .. " (external)")
            end
        end
    end

    -- 0) Consume current character's items (already shown in Post Now)
    local myTasks = ns.Queue:GetCharacterTasks(myCharKey)
    for _, task in ipairs(myTasks) do
        if ns:RealmMatches(task.queueItem.targetRealm, myRealm) then
            consumed[task.queueIndex] = true
        end
    end

    -- 1) Other characters with pending tasks (not current char, not hidden)
    -- Process characters with personal inventory matches first, then warbank-only
    local otherChars = {}
    for charKey, _ in pairs(ns.db.inventory) do
        if charKey ~= myCharKey and not ns.db.hiddenCharacters[charKey] then
            table.insert(otherChars, charKey)
        end
    end

    local charTasks = {} -- charKey -> {count, totalGold}
    for _, charKey in ipairs(otherChars) do
        local charRealm = charKey:match("%-(.+)$") or ""
        local tasks = ns.Queue:GetCharacterTasks(charKey)
        local realmCount = 0
        local totalGold = 0

        for _, task in ipairs(tasks) do
            if not consumed[task.queueIndex] then
                local targetRealm = task.queueItem.targetRealm or ""
                if targetRealm ~= "" and ns:RealmMatches(targetRealm, charRealm) then
                    consumed[task.queueIndex] = true
                    realmCount = realmCount + 1
                    totalGold = totalGold + ParseGoldValue(task.queueItem.expectedPrice)
                end
            end
        end

        if realmCount > 0 then
            charTasks[charKey] = {
                count = realmCount,
                totalGold = totalGold,
            }
        end
    end

    for charKey, info in pairs(charTasks) do
        local name = charKey:match("^(.-)%-") or charKey
        local realm = charKey:match("%-(.+)$") or ""
        local charInv = ns.db.inventory[charKey]
        local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
        local coloredName = "|cff" .. classColor .. name .. "|r"

        table.insert(data, {
            action    = ns.COLORS.YELLOW .. "Log in" .. "|r",
            target    = coloredName .. "  (" .. realm .. ")",
            itemCount = info.count,
            value     = FormatGoldValue(info.totalGold),
            detail    = info.count .. " items to post",
            _sortValue = info.totalGold,
            _tooltipText = charKey,
            _tooltipExtra = string.format("Log in to %s to post %d items\nEstimated value: %s",
                charKey, info.count, FormatGoldValue(info.totalGold)),
        })
    end

    -- 2) Realms needing new characters
    -- Only count items that actually exist in the warbank (the only cross-realm storage)
    local realmNeeds = {} -- realmKey -> {realmStr, count, totalGold}

    -- Build warbank remaining quantity tracker (same approach as GetCharacterTasks)
    local wbRemaining = {}
    if ns.db.warbank and ns.db.warbank.items then
        for wbKey, wbData in pairs(ns.db.warbank.items) do
            wbRemaining[wbKey] = wbData.quantity or 1
        end
    end

    for i, item in ipairs(ns.db.queue) do
        if item.status == "pending" and not consumed[i]
            and item.targetRealm and item.targetRealm ~= "" then
            local hasCoverage = false
            for realm, _ in pairs(coveredRealms) do
                if ns:RealmMatches(item.targetRealm, realm) then
                    hasCoverage = true
                    break
                end
            end

            if not hasCoverage then
                -- Check if this item actually exists in warbank
                local inWarbank = false
                if ns.db.warbank and ns.db.warbank.items then
                    local resolvedID = ns:ResolveItemID(item)
                    for wbKey, wbData in pairs(ns.db.warbank.items) do
                        if (wbRemaining[wbKey] or 0) > 0 then
                            local matched = (wbKey == item.itemKey)
                            if not matched and resolvedID then
                                local wbNumID = tonumber(wbKey:match("^(%d+);"))
                                if wbNumID and wbNumID == resolvedID then matched = true end
                            end
                            if not matched and wbData.name and item.name ~= "" then
                                if wbData.name:lower() == item.name:lower() then
                                    matched = true
                                end
                            end
                            if matched then
                                wbRemaining[wbKey] = wbRemaining[wbKey] - (item.quantity or 1)
                                inWarbank = true
                                break
                            end
                        end
                    end
                end

                if inWarbank then
                    -- Group by exact targetRealm string to avoid cross-cluster merging
                    local realmKey = item.targetRealm:lower()
                    if not realmNeeds[realmKey] then
                        realmNeeds[realmKey] = {
                            realmStr = item.targetRealm,
                            count = 0,
                            totalGold = 0,
                        }
                    end
                    realmNeeds[realmKey].count = realmNeeds[realmKey].count + 1
                    realmNeeds[realmKey].totalGold = realmNeeds[realmKey].totalGold + ParseGoldValue(item.expectedPrice)
                end
            end
        end
    end

    for _, info in pairs(realmNeeds) do
        table.insert(data, {
            action    = "|cffff6666" .. "Create char" .. "|r",
            target    = info.realmStr,
            itemCount = info.count,
            value     = FormatGoldValue(info.totalGold),
            detail    = "New character needed",
            _sortValue = info.totalGold,
            _tooltipText = info.realmStr,
            _tooltipExtra = string.format("Create a character on %s\n%d items worth ~%s waiting",
                info.realmStr, info.count, FormatGoldValue(info.totalGold)),
        })
    end

    -- Sort by value descending
    table.sort(data, function(a, b) return (a._sortValue or 0) > (b._sortValue or 0) end)

    return data
end

-- Expose for MiniView
UI.BuildNextStepsData = BuildNextStepsData

-- ==========================================
-- ITEM QUALITY COLORS
-- ==========================================

local QUALITY_COLORS = {
    Poor      = "9d9d9d",
    Common    = "ffffff",
    Uncommon  = "1eff00",
    Rare      = "0070dd",
    Epic      = "a335ee",
    Legendary = "ff8000",
    Artifact  = "e6cc80",
    Heirloom  = "00ccff",
}

-- WoW Enum.ItemQuality numeric -> color
local QUALITY_NUM_COLORS = {
    [0] = "9d9d9d", -- Poor
    [1] = "ffffff", -- Common
    [2] = "1eff00", -- Uncommon
    [3] = "0070dd", -- Rare
    [4] = "a335ee", -- Epic
    [5] = "ff8000", -- Legendary
    [6] = "e6cc80", -- Artifact
    [7] = "00ccff", -- Heirloom
}

-- Colorize a name by quality (string name like "Rare" or numeric 3)
QualityColorName = function(name, quality)
    local color
    if type(quality) == "number" then
        color = QUALITY_NUM_COLORS[quality]
    elseif type(quality) == "string" and quality ~= "" then
        color = QUALITY_COLORS[quality]
    end
    if color then
        return "|cff" .. color .. name .. "|r"
    end
    return name
end

-- Look up icon, quality, and resolved numeric ID for an item
-- Returns: icon, quality, resolvedNumericID
LookupItemInfo = function(itemID, itemKey, itemName)
    local icon, quality, resolvedID

    -- Try WoW API with numeric ID
    local numID = tonumber(itemID)
    if numID and numID > 0 then
        resolvedID = numID
        local ok1, _, _, _, _, iconTexture = pcall(C_Item.GetItemInfoInstant, numID)
        if ok1 and iconTexture then icon = iconTexture end
        local ok2, _, _, itemQuality = pcall(C_Item.GetItemInfo, numID)
        if ok2 and itemQuality then quality = itemQuality end
    end

    -- If no numeric ID, try resolving by item name via WoW API
    if not resolvedID and itemName and itemName ~= "" then
        -- C_Item.GetItemIDForItemInfo may not exist in all WoW versions
        local ok, nameID = pcall(function()
            if C_Item.GetItemIDForItemInfo then
                return C_Item.GetItemIDForItemInfo(itemName)
            end
            return nil
        end)
        if ok and nameID and nameID > 0 then
            resolvedID = nameID
            if not icon then
                local _, _, _, _, iconTexture = C_Item.GetItemInfoInstant(nameID)
                if iconTexture then icon = iconTexture end
            end
            if not quality then
                local _, _, itemQuality = C_Item.GetItemInfo(nameID)
                if itemQuality then quality = itemQuality end
            end
        end
    end

    -- Fall back to scanned inventory data for icon
    if not icon and ns.db then
        local searchKey = itemKey or ""
        local searchName = itemName and itemName:lower() or ""

        -- Search character inventories
        for _, charData in pairs(ns.db.inventory) do
            if charData.items then
                for key, data in pairs(charData.items) do
                    if key == searchKey or (data.name and data.name:lower() == searchName) then
                        if data.icon then icon = data.icon end
                        -- Try to resolve ID from inventory itemID
                        if not resolvedID then
                            local invNumID = tonumber(data.itemID)
                            if invNumID and invNumID > 0 then resolvedID = invNumID end
                        end
                        break
                    end
                end
                if icon then break end
            end
        end

        -- Search warbank
        if not icon and ns.db.warbank and ns.db.warbank.items then
            for key, data in pairs(ns.db.warbank.items) do
                if key == searchKey or (data.name and data.name:lower() == searchName) then
                    if data.icon then icon = data.icon end
                    if not resolvedID then
                        local wbNumID = tonumber(data.itemID)
                        if wbNumID and wbNumID > 0 then resolvedID = wbNumID end
                    end
                    break
                end
            end
        end
    end

    return icon, quality, resolvedID
end

-- ==========================================
-- QUEUE PAGE
-- ==========================================

local function BuildQueueData()
    if not ns.db then return {} end
    local data = {}

    for i, item in ipairs(ns.db.queue) do
        -- Build "Found On" string showing where this item exists
        local locs = ns.Queue:FindItemLocations(item.itemKey, item.name)
        local foundParts = {}
        local fuzzy = false

        if #locs > 0 then
            for _, loc in ipairs(locs) do
                local detail = loc.charKey
                -- Add storage type detail
                if loc.locations then
                    local storageParts = {}
                    for storage, qty in pairs(loc.locations) do
                        table.insert(storageParts, storage)
                    end
                    if #storageParts > 0 then
                        detail = detail .. " [" .. table.concat(storageParts, ",") .. "]"
                    end
                end
                table.insert(foundParts, detail)
            end
        elseif item.name ~= "" then
            local nameLocs = ns.Queue:FindItemByName(item.name)
            if #nameLocs > 0 then
                fuzzy = true
                for _, loc in ipairs(nameLocs) do
                    local detail = loc.charKey
                    if loc.locations then
                        local storageParts = {}
                        for storage, qty in pairs(loc.locations) do
                            table.insert(storageParts, storage)
                        end
                        if #storageParts > 0 then
                            detail = detail .. " [" .. table.concat(storageParts, ",") .. "]"
                        end
                    end
                    table.insert(foundParts, detail)
                end
            end
        end

        local foundStr = table.concat(foundParts, ", ")
        if fuzzy and foundStr ~= "" then
            foundStr = "~" .. foundStr
        end
        if foundStr == "" then
            foundStr = ns.COLORS.RED .. "Not found" .. "|r"
        end

        -- Look up icon, quality, and resolved numeric ID
        local icon, quality, resolvedID = LookupItemInfo(item.itemID, item.itemKey, item.name)
        local displayName = item.name ~= "" and item.name or tostring(item.itemID)

        -- Apply quality color (prefer API quality, fall back to imported string)
        if quality then
            displayName = QualityColorName(displayName, quality)
        elseif item.quality and item.quality ~= "" then
            displayName = QualityColorName(displayName, item.quality)
        end

        table.insert(data, {
            name    = displayName,
            qty     = item.quantity,
            price   = item.expectedPrice or "",
            realm   = item.targetRealm or "",
            foundOn = foundStr,
            status  = item.status == "skipped" and (ns.COLORS.ORANGE .. "Skipped" .. "|r") or
                      item.status == "posted" and "POSTED" or "pending",
            _icon   = icon,
            _tooltipItemID = resolvedID,
            _tooltipText   = item.name ~= "" and item.name or tostring(item.itemID),
            _tooltipExtra  = (item.targetRealm or "") ~= "" and
                ("Sell on: " .. item.targetRealm .. "  @  " .. (item.expectedPrice or "?")) or nil,
            _queueIndex = i,
            _queueItem  = item,
        })
    end

    return data
end

-- ==========================================
-- LOG PAGE
-- ==========================================

local function BuildLogData()
    if not ns.db then return {} end
    local data = {}

    for i, entry in ipairs(ns.db.log) do
        local dateStr = ""
        if entry.postedAt then
            dateStr = date("%m/%d %H:%M", entry.postedAt)
        end

        local icon, quality, resolvedID = LookupItemInfo(entry.itemID, entry.itemKey, entry.name)
        local displayName = entry.name or "?"
        if quality then
            displayName = QualityColorName(displayName, quality)
        elseif entry.quality and entry.quality ~= "" then
            displayName = QualityColorName(displayName, entry.quality)
        end

        table.insert(data, {
            name      = displayName,
            posted    = entry.postedPrice or "?",
            guide     = entry.expectedPrice or "?",
            realm     = entry.targetRealm or "",
            character = entry.charKey or "",
            date      = dateStr,
            _icon     = icon,
            _sortDate = entry.postedAt or 0,
            _tooltipItemID = resolvedID,
            _tooltipText   = entry.name,
            _tooltipExtra  = string.format("Posted: %s\nPosted for: %s\nFP suggested: %s",
                dateStr, entry.postedPrice or "?", entry.expectedPrice or "?"),
            _logIndex = i,
        })
    end

    return data
end

-- ==========================================
-- INVENTORY (UNTRACKED) PAGE
-- ==========================================

local BOUND_TYPES = {
    [1] = true, [4] = true, [7] = true, [8] = true, [9] = true,
}

local function BuildInventoryData()
    if not ns.db then return {} end

    local queuedKeys = {}
    local queuedNames = {}
    for _, item in ipairs(ns.db.queue) do
        queuedKeys[item.itemKey] = true
        if item.name and item.name ~= "" then
            queuedNames[item.name:lower()] = true
        end
    end
    for _, item in ipairs(ns.db.log) do
        queuedKeys[item.itemKey] = true
        if item.name and item.name ~= "" then
            queuedNames[item.name:lower()] = true
        end
    end

    local data = {}
    local seen = {}

    local charKey = ns:GetCharKey()
    local charData = ns.db.inventory[charKey]
    if charData and charData.items then
        for key, itemData in pairs(charData.items) do
            if not queuedKeys[key]
                and not (itemData.name and queuedNames[(itemData.name or ""):lower()])
                and not ns.Queue:IsDoNotTrack(itemData.itemID)
                and not BOUND_TYPES[itemData.bindType or 0]
                and not itemData.isBound then
                seen[key] = true
                local locParts = {}
                if itemData.locations then
                    for loc, qty in pairs(itemData.locations) do
                        table.insert(locParts, loc .. ": " .. qty)
                    end
                end
                local _, invQuality, invResolvedID = LookupItemInfo(itemData.itemID, key, itemData.name)
                local invDisplayName = itemData.name or "Unknown"
                if invQuality then
                    invDisplayName = QualityColorName(invDisplayName, invQuality)
                end

                table.insert(data, {
                    name     = invDisplayName,
                    qty      = itemData.quantity,
                    source   = charKey,
                    location = table.concat(locParts, ", "),
                    _icon    = itemData.icon,
                    _tooltipItemID = invResolvedID,
                    _itemKey  = key,
                    _itemID   = itemData.itemID,
                    _itemName = itemData.name,
                    _quantity = itemData.quantity,
                })
            end
        end
    end

    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            if not seen[key]
                and not queuedKeys[key]
                and not (itemData.name and queuedNames[(itemData.name or ""):lower()])
                and not ns.Queue:IsDoNotTrack(itemData.itemID)
                and not BOUND_TYPES[itemData.bindType or 0]
                and not itemData.isBound then
                local _, wbQuality, wbResolvedID = LookupItemInfo(itemData.itemID, key, itemData.name)
                local wbDisplayName = itemData.name or "Unknown"
                if wbQuality then
                    wbDisplayName = QualityColorName(wbDisplayName, wbQuality)
                end

                table.insert(data, {
                    name     = wbDisplayName,
                    qty      = itemData.quantity,
                    source   = "Warbank",
                    location = "warbank",
                    _icon    = itemData.icon,
                    _tooltipItemID = wbResolvedID,
                    _itemKey  = key,
                    _itemID   = itemData.itemID,
                    _itemName = itemData.name,
                    _quantity = itemData.quantity,
                })
            end
        end
    end

    return data
end

-- ==========================================
-- CHARACTERS PAGE
-- ==========================================

-- WoW class colors for display
CLASS_COLORS = {
    WARRIOR     = "c79c6e", PALADIN     = "f58cba", HUNTER      = "abd473",
    ROGUE       = "fff569", PRIEST      = "ffffff", DEATHKNIGHT = "c41f3b",
    SHAMAN      = "0070de", MAGE        = "69ccf0", WARLOCK     = "9482c9",
    MONK        = "00ff96", DRUID       = "ff7d0a", DEMONHUNTER = "a330c9",
    EVOKER      = "33937f",
}

local function BuildCharactersData()
    if not ns.db then return {}, {} end

    local charData = {}

    -- First pass: count characters per realm for duplicate detection
    local realmCharCount = {} -- realm -> count of active (non-hidden) characters
    local realmAllChars = {} -- realm -> list of all charKeys
    for charKey, _ in pairs(ns.db.inventory) do
        local realm = charKey:match("%-(.+)$") or ""
        if realm ~= "" then
            realmAllChars[realm] = realmAllChars[realm] or {}
            table.insert(realmAllChars[realm], charKey)
            realmCharCount[realm] = (realmCharCount[realm] or 0) + 1
        end
    end

    -- Identify duplicate realms (2+ characters on same realm)
    local duplicateRealms = {}
    for realm, count in pairs(realmCharCount) do
        if count > 1 then
            duplicateRealms[realm] = count
        end
    end

    -- Get auction expiry data grouped by character
    local expiringByChar = ns.Tracker and ns.Tracker.GetExpiringByCharacter
        and ns.Tracker:GetExpiringByCharacter() or {}

    -- Build character list
    for charKey, inv in pairs(ns.db.inventory) do
        local name = charKey:match("^(.-)%-") or charKey
        local realm = charKey:match("%-(.+)$") or ""
        local allTasks = ns.Queue:GetCharacterTasks(charKey)
        local isHidden = ns.db.hiddenCharacters[charKey]

        -- Filter tasks by character's realm (warbank items match all chars otherwise)
        local tasks = {}
        for _, task in ipairs(allTasks) do
            if ns:RealmMatches(task.queueItem.targetRealm, realm) then
                table.insert(tasks, task)
            end
        end

        local classColor = CLASS_COLORS[inv.class] or "888888"
        local coloredName = "|cff" .. classColor .. name .. "|r"
        if isHidden then
            coloredName = "|cff666666" .. name .. "|r"
        end

        -- Character metadata (gold, lastLogin)
        local charMeta = ns.db.characters and ns.db.characters[charKey] or {}
        local goldCopper = charMeta.gold or 0
        local goldStr = ns:FormatGold(goldCopper)
        local lastLoginTime = charMeta.lastLogin or 0
        local lastLoginStr = ns:FormatRelativeTime(lastLoginTime)

        -- Auction expiry info
        local expiryInfo = expiringByChar[charKey]
        local auctionStr = ""
        if expiryInfo then
            local soonestStr = ns:FormatRelativeTime(time() + expiryInfo.soonest)
            -- Remove " ago" since this is time remaining
            soonestStr = soonestStr:gsub(" ago$", "")
            auctionStr = ns.COLORS.ORANGE .. expiryInfo.count .. "|r"
            if expiryInfo.soonest < 7200 then -- < 2h = red
                auctionStr = ns.COLORS.RED .. expiryInfo.count .. "!|r"
            end
        end

        -- Build status string
        local statusParts = {}
        if isHidden then
            table.insert(statusParts, "|cff666666Hidden|r")
        elseif duplicateRealms[realm] then
            table.insert(statusParts, "|cffff8800Dupe|r")
        else
            table.insert(statusParts, "|cff00ff00Active|r")
        end
        local statusStr = table.concat(statusParts, " ")

        -- Row color
        local rowColor = nil
        if isHidden then
            rowColor = {0.3, 0.3, 0.3, 0.1}
        elseif expiryInfo and expiryInfo.soonest < 7200 then
            rowColor = {1.0, 0.3, 0.3, 0.1} -- red tint for urgent auctions
        elseif duplicateRealms[realm] then
            rowColor = {0.8, 0.5, 0.1, 0.1}
        end

        local itemCount = 0
        if inv.items then
            for _ in pairs(inv.items) do itemCount = itemCount + 1 end
        end

        table.insert(charData, {
            name      = coloredName,
            realm     = realm,
            gold      = goldStr,
            tasks     = isHidden and "-" or tostring(#tasks),
            auctions  = auctionStr,
            lastLogin = lastLoginStr,
            status    = statusStr,
            _sortName = name:lower(),
            _sortGold = goldCopper,
            _sortLastLogin = lastLoginTime,
            _sortAuctions = expiryInfo and expiryInfo.count or 0,
            _charKey = charKey,
            _isHidden = isHidden,
            _rowColor = rowColor,
            _tooltipText = charKey,
            _tooltipExtra = string.format(
                "Gold: %s\n%d queue tasks%s\nLast login: %s\nStatus: %s%s\n\nRight-click to %s",
                goldStr, #tasks,
                expiryInfo and ("\n" .. expiryInfo.count .. " active auction(s)") or "",
                lastLoginStr,
                isHidden and "Hidden" or "Active",
                duplicateRealms[realm] and ("\nDuplicate realm: " .. duplicateRealms[realm] .. " chars on " .. realm) or "",
                isHidden and "re-enable" or "hide"),
        })
    end

    -- Build "realms needing characters" from queue
    -- Only count non-hidden characters as providing realm coverage
    local coveredRealms = {}
    for charKey, _ in pairs(ns.db.inventory) do
        if not ns.db.hiddenCharacters[charKey] then
            local realm = charKey:match("%-(.+)$") or ""
            if realm ~= "" then
                if not coveredRealms[realm] then
                    coveredRealms[realm] = {}
                end
                table.insert(coveredRealms[realm], charKey)
            end
        end
    end

    -- Include external accounts as realm coverage
    if ns.db.externalAccounts then
        for _, acct in ipairs(ns.db.externalAccounts) do
            for _, realm in ipairs(acct.realms) do
                if not coveredRealms[realm] then
                    coveredRealms[realm] = {}
                end
                table.insert(coveredRealms[realm], acct.label .. " (external)")
            end
        end
    end

    -- Group uncovered queue items by exact targetRealm string (no RealmsOverlap)
    local realmNeedsMap = {} -- realmKey -> {realmStr, count, prices}
    for _, item in ipairs(ns.db.queue) do
        if item.status == "pending" and item.targetRealm and item.targetRealm ~= "" then
            local hasCoverage = false
            for realm, _ in pairs(coveredRealms) do
                if ns:RealmMatches(item.targetRealm, realm) then
                    hasCoverage = true
                    break
                end
            end

            if not hasCoverage then
                local realmKey = item.targetRealm:lower()
                if not realmNeedsMap[realmKey] then
                    realmNeedsMap[realmKey] = {
                        realmStr = item.targetRealm,
                        count = 0,
                        prices = {},
                    }
                end
                realmNeedsMap[realmKey].count = realmNeedsMap[realmKey].count + 1
                if item.expectedPrice and item.expectedPrice ~= "" then
                    table.insert(realmNeedsMap[realmKey].prices, item.expectedPrice)
                end
            end
        end
    end

    local needData = {}
    for _, info in pairs(realmNeedsMap) do
        local totalGold = 0
        for _, price in ipairs(info.prices) do
            totalGold = totalGold + ParseGoldValue(price)
        end

        table.insert(needData, {
            realm      = info.realmStr,
            itemCount  = info.count,
            totalValue = FormatGoldValue(totalGold),
            note       = "Create character (flex slot)",
        })
    end

    return charData, needData
end

-- ==========================================
-- REFRESH ORCHESTRATION
-- ==========================================

function UI:Refresh()
    if not mainFrame:IsShown() then return end
    if not ns.db then return end

    UpdateNavHighlights()
    HideAllTables()

    -- Update summary
    local pending = ns.Queue:GetPendingCount()
    local logCount = #ns.db.log
    mainFrame.summary:SetText(string.format(
        "%sQueue: %d|r  %sLog: %d|r  %sTracked: %d|r",
        ns.COLORS.YELLOW, pending,
        ns.COLORS.GREEN, logCount,
        ns.COLORS.GRAY, #ns.db.queue + logCount
    ))

    -- Update nav badges
    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""
    local allTasks = ns.Queue:GetCharacterTasks(charKey)
    local postCount = 0
    for _, task in ipairs(allTasks) do
        if ns:RealmMatches(task.queueItem.targetRealm, myRealm) then
            postCount = postCount + 1
        end
    end
    if navButtons.postNow then
        navButtons.postNow.badge:SetText(postCount > 0 and (ns.COLORS.GREEN .. postCount .. "|r") or "")
    end
    if navButtons.queue then
        navButtons.queue.badge:SetText(pending > 0 and (ns.COLORS.YELLOW .. pending .. "|r") or "")
    end
    if navButtons.log then
        navButtons.log.badge:SetText(logCount > 0 and (ns.COLORS.GRAY .. logCount .. "|r") or "")
    end

    -- Render active page
    if self.currentPage == "postNow" then
        mainFrame.pageTitle:SetText(ns.COLORS.GREEN .. "Post Now" .. "|r" ..
            ns.COLORS.GRAY .. " - " .. charKey .. "|r")
        LayoutActionBtns(mainFrame.actionBtns.pullBank)

        local data = BuildPostNowData()
        local nextData = BuildNextStepsData()

        -- Create summary banner (reused across refreshes)
        if not self._postSummaryFrame then
            local sf = CreateFrame("Frame", nil, tableContainer)
            sf:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
            sf:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
            sf:SetHeight(60)
            self._postSummaryFrame = sf

            sf.title = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            sf.title:SetPoint("TOP", sf, "TOP", 0, -10)

            sf.sub = sf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            sf.sub:SetPoint("TOP", sf.title, "BOTTOM", 0, -6)
            sf.sub:SetWidth(sf:GetWidth() - 40)
            sf.sub:SetJustifyH("CENTER")

            sf:SetScript("OnSizeChanged", function(self, w)
                sf.sub:SetWidth(w - 40)
            end)
        end

        if #data == 0 then
            -- Nothing to post on this character — show summary banner + next steps table
            self._postSummaryFrame:Show()

            if #nextData == 0 and ns.Queue:GetPendingCount() == 0 then
                -- Everything is done! Full-height fun message
                self._postSummaryFrame:ClearAllPoints()
                self._postSummaryFrame:SetAllPoints(tableContainer)

                local doneMessages = {
                    {title = "All done!", sub = "Time to go shopping on FlippingPal!"},
                    {title = "Queue empty!", sub = "Hit the AH browser or import more flips."},
                    {title = "Everything posted!", sub = "Now sit back and wait for the gold to roll in."},
                    {title = "Nothing to do!", sub = "Browse FlippingPal.com for your next deals."},
                }
                local msg = doneMessages[math.random(#doneMessages)]
                self._postSummaryFrame.title:ClearAllPoints()
                self._postSummaryFrame.title:SetPoint("CENTER", self._postSummaryFrame, "CENTER", 0, 10)
                self._postSummaryFrame.title:SetText(ns.COLORS.GREEN .. msg.title .. "|r")
                self._postSummaryFrame.sub:SetText(ns.COLORS.GRAY .. msg.sub .. "|r")
                mainFrame.statusText:SetText("Queue empty  |  Import items from FlippingPal to get started")
            else
                -- This character is done, show banner + full next steps table below
                local bannerHeight = 50
                self._postSummaryFrame:ClearAllPoints()
                self._postSummaryFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
                self._postSummaryFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
                self._postSummaryFrame:SetHeight(bannerHeight)

                self._postSummaryFrame.title:ClearAllPoints()
                self._postSummaryFrame.title:SetPoint("TOP", self._postSummaryFrame, "TOP", 0, -10)

                local remaining = ns.Queue:GetPendingCount()
                self._postSummaryFrame.title:SetText(ns.COLORS.GREEN .. "Done on this character!" .. "|r")
                self._postSummaryFrame.sub:SetText(
                    ns.COLORS.GRAY .. remaining .. " items remaining across " ..
                    #nextData .. " step" .. (#nextData ~= 1 and "s" or "") .. "|r")

                -- Next Steps label
                if not self._nextStepsLabel then
                    self._nextStepsLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                end
                self._nextStepsLabel:ClearAllPoints()
                self._nextStepsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, -bannerHeight + 2)
                self._nextStepsLabel:SetTextColor(0.6, 0.8, 1.0)
                self._nextStepsLabel:SetText("Next Steps (" .. #nextData .. ")")
                self._nextStepsLabel:Show()

                -- Position next steps table below banner
                self.nextStepsTable.headerFrame:ClearAllPoints()
                self.nextStepsTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, -bannerHeight - 10)
                self.nextStepsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, -bannerHeight - 10)

                self.nextStepsTable.scrollFrame:ClearAllPoints()
                self.nextStepsTable.scrollFrame:SetPoint("TOPLEFT", self.nextStepsTable.headerFrame, "BOTTOMLEFT", 0, 0)
                self.nextStepsTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)

                ShowTable(self.nextStepsTable)
                self.nextStepsTable:SetData(nextData)

                mainFrame.statusText:SetText("Done here  |  " .. #nextData ..
                    " next step" .. (#nextData ~= 1 and "s" or "") ..
                    "  |  " .. remaining .. " items remaining")
            end
        else
            -- Has items to post — show normal tables
            self._postSummaryFrame:Hide()
            ShowTable(self.postNowTable)

            self.postNowTable:SetRowClickHandler(function(rowData, button)
                if button == "RightButton" and rowData._queueIndex then
                    if IsShiftKeyDown() then
                        ns.Queue:Skip(rowData._queueIndex)
                        ns:Print(ns.COLORS.ORANGE .. "Skipped:|r " .. rowData.name .. " (will reappear in 24h)")
                    else
                        ns.Queue:MarkPosted(rowData._queueIndex)
                        ns:Print("Posted: " .. rowData.name .. " -> moved to log")
                    end
                    self:Refresh()
                    self:RefreshMini()
                end
            end)
            self.postNowTable:SetData(data)

            if #nextData > 0 then
                local postNowHeight = math.max(60, (#data + 1) * 20 + 22)
                if postNowHeight > 250 then postNowHeight = 250 end

                -- Section label
                if not self._nextStepsLabel then
                    self._nextStepsLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                end
                self._nextStepsLabel:ClearAllPoints()
                self._nextStepsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, -postNowHeight + 2)
                self._nextStepsLabel:SetTextColor(0.6, 0.8, 1.0)
                self._nextStepsLabel:SetText("Next Steps (" .. #nextData .. ")")
                self._nextStepsLabel:Show()

                -- Position next steps table below
                self.nextStepsTable.headerFrame:ClearAllPoints()
                self.nextStepsTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, -postNowHeight - 10)
                self.nextStepsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, -postNowHeight - 10)

                self.nextStepsTable.scrollFrame:ClearAllPoints()
                self.nextStepsTable.scrollFrame:SetPoint("TOPLEFT", self.nextStepsTable.headerFrame, "BOTTOMLEFT", 0, 0)
                self.nextStepsTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)

                ShowTable(self.nextStepsTable)
                self.nextStepsTable:SetData(nextData)

                -- Resize postNow scroll to fit above
                self.postNowTable.scrollFrame:ClearAllPoints()
                self.postNowTable.scrollFrame:SetPoint("TOPLEFT", self.postNowTable.headerFrame, "BOTTOMLEFT", 0, 0)
                self.postNowTable.scrollFrame:SetPoint("RIGHT", tableContainer, "RIGHT", -22, 0)
                self.postNowTable.scrollFrame:SetHeight(postNowHeight - 22)
            else
                if self._nextStepsLabel then self._nextStepsLabel:Hide() end
                -- Reset postNow scroll to fill the full container
                self.postNowTable.scrollFrame:ClearAllPoints()
                self.postNowTable.scrollFrame:SetPoint("TOPLEFT", self.postNowTable.headerFrame, "BOTTOMLEFT", 0, 0)
                self.postNowTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)
            end

            mainFrame.statusText:SetText(postCount .. " items to post  |  " .. #nextData .. " next steps  |  Right-click: posted  |  Shift+Right: skip")
        end

    elseif self.currentPage == "queue" then
        mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Full Queue" .. "|r")
        LayoutActionBtns(mainFrame.actionBtns.clearQueue)
        ShowTable(self.queueTable)

        local data = BuildQueueData()
        self.queueTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" and rowData._queueItem then
                if rowData._queueItem.status == "skipped" then
                    ns.Queue:Unskip(rowData._queueIndex)
                    ns:Print(ns.COLORS.GREEN .. "Unskipped:|r " .. rowData.name)
                    self:Refresh()
                    self:RefreshMini()
                elseif rowData._queueItem.status == "pending" then
                    if IsShiftKeyDown() then
                        ns.Queue:Skip(rowData._queueIndex)
                        ns:Print(ns.COLORS.ORANGE .. "Skipped:|r " .. rowData.name)
                    else
                        ns.Queue:MarkPosted(rowData._queueIndex)
                        ns:Print("Posted: " .. rowData.name .. " -> moved to log")
                    end
                    self:Refresh()
                    self:RefreshMini()
                end
            end
        end)
        self.queueTable:SetData(data)
        local skippedCount = 0
        for _, item in ipairs(ns.db.queue) do
            if item.status == "skipped" then skippedCount = skippedCount + 1 end
        end
        local queueStatus = #ns.db.queue .. " items in queue"
        if skippedCount > 0 then
            queueStatus = queueStatus .. "  |  " .. skippedCount .. " skipped"
        end
        queueStatus = queueStatus .. "  |  Right-click: posted  |  Shift+Right: skip"
        mainFrame.statusText:SetText(queueStatus)

    elseif self.currentPage == "log" then
        mainFrame.pageTitle:SetText(ns.COLORS.GREEN .. "Posted Items Log" .. "|r")
        LayoutActionBtns(mainFrame.actionBtns.clearLog)
        ShowTable(self.logTable)

        local data = BuildLogData()
        self.logTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" and IsShiftKeyDown() and rowData._logIndex then
                table.remove(ns.db.log, rowData._logIndex)
                ns:Print("Removed from log: " .. rowData.name)
                self:Refresh()
            end
        end)
        self.logTable:SetData(data)
        mainFrame.statusText:SetText(logCount .. " logged items  |  Shift+Right-click to remove")

    elseif self.currentPage == "inventory" then
        mainFrame.pageTitle:SetText("Untracked Inventory")
        LayoutActionBtns(mainFrame.actionBtns.dnt)
        ShowTable(self.inventoryTable)

        local data = BuildInventoryData()
        self.inventoryTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" then
                if IsShiftKeyDown() then
                    local added = ns.Queue:Add({{
                        itemKey  = rowData._itemKey,
                        itemID   = rowData._itemID or "",
                        name     = rowData._itemName or "Unknown",
                        quantity = rowData._quantity or 1,
                    }})
                    if added > 0 then
                        ns:Print(ns.COLORS.GREEN .. "Added to queue:|r " .. (rowData._itemName or rowData.name))
                    else
                        ns:Print(ns.COLORS.GRAY .. "Already in queue:|r " .. (rowData._itemName or rowData.name))
                    end
                else
                    ns.Queue:AddDoNotTrack(rowData._itemID, rowData._itemName)
                    ns:Print("Do not track: " .. rowData.name)
                end
                self:Refresh()
            end
        end)
        self.inventoryTable:SetData(data)
        mainFrame.statusText:SetText(#data .. " untracked items  |  Right-click: DNT  |  Shift+Right: Add to queue")

    elseif self.currentPage == "characters" then
        mainFrame.pageTitle:SetText("Characters & Realms")
        HideAllActionBtns()

        local charData, needData = BuildCharactersData()

        -- Show known characters table
        ShowTable(self.charsTable)
        self.charsTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" and rowData._charKey then
                if ns.db.hiddenCharacters[rowData._charKey] then
                    ns.db.hiddenCharacters[rowData._charKey] = nil
                    ns:Print("Re-enabled character: " .. rowData._charKey)
                else
                    ns.db.hiddenCharacters[rowData._charKey] = true
                    ns:Print("Hidden character: " .. rowData._charKey .. " (will be skipped for task routing)")
                end
                self:Refresh()
            end
        end)
        self.charsTable:SetData(charData)

        -- Show "need characters" table below if there are entries
        if #needData > 0 then
            -- Position needCharsTable below charsTable
            local charsHeight = math.max(60, (#charData + 1) * 20 + 22) -- rows + header
            if charsHeight > 250 then charsHeight = 250 end

            self.needCharsTable.headerFrame:ClearAllPoints()
            self.needCharsTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, -charsHeight - 10)
            self.needCharsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, -charsHeight - 10)

            self.needCharsTable.scrollFrame:ClearAllPoints()
            self.needCharsTable.scrollFrame:SetPoint("TOPLEFT", self.needCharsTable.headerFrame, "BOTTOMLEFT", 0, 0)
            self.needCharsTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)

            -- Add section label
            if not self._needCharsLabel then
                self._needCharsLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            end
            self._needCharsLabel:ClearAllPoints()
            self._needCharsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, -charsHeight + 2)
            self._needCharsLabel:SetTextColor(1, 0.4, 0.4)
            self._needCharsLabel:SetText("Realms Needing a Character (" .. #needData .. ")")
            self._needCharsLabel:Show()

            ShowTable(self.needCharsTable)
            self.needCharsTable:SetData(needData)

            -- Resize chars scroll to fit above
            self.charsTable.scrollFrame:ClearAllPoints()
            self.charsTable.scrollFrame:SetPoint("TOPLEFT", self.charsTable.headerFrame, "BOTTOMLEFT", 0, 0)
            self.charsTable.scrollFrame:SetPoint("RIGHT", tableContainer, "RIGHT", -22, 0)
            self.charsTable.scrollFrame:SetHeight(charsHeight - 22)
        else
            if self._needCharsLabel then self._needCharsLabel:Hide() end
        end

        local charCount = 0
        local hiddenCount = 0
        local totalGold = 0
        for ck in pairs(ns.db.inventory) do
            charCount = charCount + 1
            if ns.db.hiddenCharacters[ck] then hiddenCount = hiddenCount + 1 end
            local meta = ns.db.characters and ns.db.characters[ck]
            if meta and meta.gold then totalGold = totalGold + meta.gold end
        end
        local statusParts = {charCount .. " characters"}
        if totalGold > 0 then
            table.insert(statusParts, ns:FormatGold(totalGold) .. " total")
        end
        if hiddenCount > 0 then
            table.insert(statusParts, hiddenCount .. " hidden")
        end
        table.insert(statusParts, #needData .. " realms need chars")
        mainFrame.statusText:SetText(table.concat(statusParts, "  |  "))

    elseif self.currentPage == "import" then
        mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Import" .. "|r")
        LayoutActionBtns(mainFrame.actionBtns.importClear, mainFrame.actionBtns.importDo)
        importPage:Show()
        UI._importEdit:SetFocus(true)
        mainFrame.statusText:SetText("Paste FlippingPal website, CSV, or tab-delimited data")

    elseif self.currentPage == "export" then
        mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Export" .. "|r")
        LayoutActionBtns(mainFrame.actionBtns.exportSaved, mainFrame.actionBtns.exportAll,
            mainFrame.actionBtns.exportWarbank, mainFrame.actionBtns.exportBank, mainFrame.actionBtns.exportBags)
        exportPage:Show()
        mainFrame.statusText:SetText("FlippingPalInventoryExport compatible CSV format")

    elseif self.currentPage == "settings" then
        mainFrame.pageTitle:SetText("Settings")
        HideAllActionBtns()
        self:ShowSettingsPage()
        mainFrame.statusText:SetText("FlipQueue v" .. ns.VERSION)
    end
end

-- ==========================================
-- BACKWARD COMPATIBILITY
-- ==========================================

function UI:HideAllRows()
    -- No-op in new system
end

function UI:GetOrCreateRow(index)
    if not self.contentRows[index] then
        local row = CreateFrame("Frame", nil, tableContainer)
        row:SetHeight(20)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 2, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.tooltipItemID = nil
        row.tooltipItemName = nil
        row.tooltipExtra = nil
        row:EnableMouse(true)
        self.contentRows[index] = row
    end
    return self.contentRows[index]
end

-- ==========================================
-- INIT
-- ==========================================

mainFrame:Hide()
UI.mainFrame = mainFrame

mainFrame:SetScript("OnShow", function()
    -- Restore saved size
    if ns.db and ns.db.settings.frameWidth and ns.db.settings.frameHeight then
        mainFrame:SetSize(ns.db.settings.frameWidth, ns.db.settings.frameHeight)
    end
    UI:Refresh()
end)
