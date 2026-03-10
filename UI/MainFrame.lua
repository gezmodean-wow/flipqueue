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
    {key = "postNow",   label = "Post Now",   icon = "Interface\\Icons\\INV_Misc_Coin_02"},
    {key = "queue",     label = "Queue",       icon = "Interface\\Icons\\INV_Scroll_03"},
    {key = "log",       label = "Log",         icon = "Interface\\Icons\\INV_Misc_Book_09"},
    {key = "inventory", label = "Inventory",   icon = "Interface\\Icons\\INV_Misc_Bag_07"},
    {key = "sep"},
    {key = "import",    label = "Import",      icon = "Interface\\Icons\\Ability_Creature_Cursed_04", action = true},
    {key = "rescan",    label = "Rescan",      icon = "Interface\\Icons\\Spell_Shadow_MindSteal", action = true},
    {key = "sep2"},
    {key = "settings",  label = "Settings",    icon = "Interface\\Icons\\INV_Gizmo_02", action = true},
}

local navButtons = {}
local navY = -8

for _, nav in ipairs(NAV_ITEMS) do
    if nav.key:find("^sep") then
        -- Separator line
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

        -- Background highlight
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(1, 1, 1, 0)

        -- Icon
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(16, 16)
        btn.icon:SetPoint("LEFT", btn, "LEFT", 6, 0)
        btn.icon:SetTexture(nav.icon)

        -- Label
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
        btn.label:SetText(nav.label)
        btn.label:SetJustifyH("LEFT")

        -- Count badge (for non-action pages)
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
                elseif navKey == "rescan" then
                    ns.Scanner:ScanCurrentCharacter()
                    UI:Refresh()
                elseif navKey == "settings" then
                    UI:ShowSettings()
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

-- Page title in action bar
mainFrame.pageTitle = actionBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mainFrame.pageTitle:SetPoint("LEFT", actionBar, "LEFT", 8, 0)

-- Action buttons (right side of action bar)
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

mainFrame.actionBtns.markAll = CreateActionBtn("Mark All Posted", "Mark all visible items as posted", function()
    -- Handled per-page
    if UI._markAllPosted then UI._markAllPosted() end
end)

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

-- Table container (below action bar)
local tableContainer = CreateFrame("Frame", nil, contentArea)
tableContainer:SetPoint("TOPLEFT", actionBar, "BOTTOMLEFT", 0, -1)
tableContainer:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", 0, 0)

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

-- Adjust table container to end above status bar
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

-- Full Queue columns
UI.queueTable = UI:CreateScrollTable(tableContainer, {
    {key = "name",     label = "Item",     width = 180, sortable = true},
    {key = "qty",      label = "Qty",      width = 40,  align = "CENTER", sortable = true},
    {key = "price",    label = "Price",    width = 80,  sortable = true},
    {key = "realm",    label = "Realm",    width = 130, sortable = true},
    {key = "charInfo", label = "Character", width = 120, sortable = true},
    {key = "status",   label = "Status",   width = 60,  align = "CENTER", sortable = true},
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
UI.logTable:SetSort("date", false) -- newest first

-- Inventory (untracked) columns
UI.inventoryTable = UI:CreateScrollTable(tableContainer, {
    {key = "name",     label = "Item",     width = 220, sortable = true},
    {key = "qty",      label = "Qty",      width = 50,  align = "CENTER", sortable = true},
    {key = "source",   label = "Source",   width = 120, sortable = true},
    {key = "location", label = "Location", width = 150, sortable = true},
})
UI.inventoryTable:SetSort("name", true)

-- Keep references for backward compatibility
UI.content = tableContainer
UI.contentRows = {}

-- ==========================================
-- PAGE RENDERING
-- ==========================================

local function HideAllTables()
    UI.postNowTable.headerFrame:Hide()
    UI.postNowTable.scrollFrame:Hide()
    UI.queueTable.headerFrame:Hide()
    UI.queueTable.scrollFrame:Hide()
    UI.logTable.headerFrame:Hide()
    UI.logTable.scrollFrame:Hide()
    UI.inventoryTable.headerFrame:Hide()
    UI.inventoryTable.scrollFrame:Hide()
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
            local locParts = {}
            if task.locations then
                for loc, qty in pairs(task.locations) do
                    table.insert(locParts, loc)
                end
            end

            table.insert(data, {
                name     = task.queueItem.name,
                qty      = task.quantity,
                price    = task.queueItem.expectedPrice or "",
                realm    = task.queueItem.targetRealm or "",
                location = table.concat(locParts, ", "),
                _icon    = task.icon,
                _tooltipItemID = task.queueItem.itemID,
                _tooltipText   = task.queueItem.name,
                _tooltipExtra  = (task.queueItem.targetRealm or "") ~= "" and
                    ("Sell on: " .. task.queueItem.targetRealm .. "  @  " .. (task.queueItem.expectedPrice or "?")) or nil,
                _queueIndex = task.queueIndex,
                _queueItem  = task.queueItem,
                _fuzzy = task.fuzzyMatch,
            })
        end
    end

    return data
end

-- ==========================================
-- QUEUE PAGE
-- ==========================================

local function BuildQueueData()
    if not ns.db then return {} end
    local data = {}

    for i, item in ipairs(ns.db.queue) do
        local locs = ns.Queue:FindItemLocations(item.itemKey)
        local charStr = ""
        if #locs > 0 then
            local parts = {}
            for _, loc in ipairs(locs) do
                table.insert(parts, loc.charKey .. "(x" .. loc.quantity .. ")")
            end
            charStr = table.concat(parts, ", ")
        elseif item.name ~= "" then
            local nameLocs = ns.Queue:FindItemByName(item.name)
            if #nameLocs > 0 then
                local parts = {}
                for _, loc in ipairs(nameLocs) do
                    table.insert(parts, loc.charKey .. "(x" .. loc.quantity .. ")")
                end
                charStr = "~" .. table.concat(parts, ", ")
            end
        end

        table.insert(data, {
            name     = item.name ~= "" and item.name or item.itemID,
            qty      = item.quantity,
            price    = item.expectedPrice or "",
            realm    = item.targetRealm or "",
            charInfo = charStr,
            status   = item.status == "posted" and "POSTED" or "pending",
            _tooltipItemID = item.itemID,
            _tooltipText   = item.name ~= "" and item.name or item.itemID,
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

        table.insert(data, {
            name      = entry.name or "?",
            posted    = entry.postedPrice or "?",
            guide     = entry.expectedPrice or "?",
            realm     = entry.targetRealm or "",
            character = entry.charKey or "",
            date      = dateStr,
            _sortDate = entry.postedAt or 0,
            _tooltipItemID = entry.itemID,
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

-- Bind types to exclude
local BOUND_TYPES = {
    [1] = true,  -- BoP
    [4] = true,  -- Quest
    [7] = true,  -- BtA
    [8] = true,  -- BtW
    [9] = true,  -- WuE
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

    -- Current character
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
                table.insert(data, {
                    name     = itemData.name or "Unknown",
                    qty      = itemData.quantity,
                    source   = charKey,
                    location = table.concat(locParts, ", "),
                    _icon    = itemData.icon,
                    _tooltipItemID = itemData.itemID,
                    _itemKey  = key,
                    _itemID   = itemData.itemID,
                    _itemName = itemData.name,
                    _quantity = itemData.quantity,
                })
            end
        end
    end

    -- Warbank
    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            if not seen[key]
                and not queuedKeys[key]
                and not (itemData.name and queuedNames[(itemData.name or ""):lower()])
                and not ns.Queue:IsDoNotTrack(itemData.itemID)
                and not BOUND_TYPES[itemData.bindType or 0]
                and not itemData.isBound then
                table.insert(data, {
                    name     = itemData.name or "Unknown",
                    qty      = itemData.quantity,
                    source   = "Warbank",
                    location = "warbank",
                    _icon    = itemData.icon,
                    _tooltipItemID = itemData.itemID,
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
        ShowTable(self.postNowTable)

        local data = BuildPostNowData()
        self.postNowTable:SetData(data)
        self.postNowTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" and rowData._queueIndex then
                ns.Queue:MarkPosted(rowData._queueIndex)
                ns:Print("Posted: " .. rowData.name .. " -> moved to log")
                self:Refresh()
                self:RefreshMini()
            end
        end)

        mainFrame.statusText:SetText(postCount .. " items to post  |  Right-click to mark as posted")

    elseif self.currentPage == "queue" then
        mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Full Queue" .. "|r")
        LayoutActionBtns(mainFrame.actionBtns.clearQueue)
        ShowTable(self.queueTable)

        local data = BuildQueueData()
        self.queueTable:SetData(data)
        self.queueTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" and rowData._queueItem then
                if rowData._queueItem.status == "pending" then
                    ns.Queue:MarkPosted(rowData._queueIndex)
                    ns:Print("Posted: " .. rowData.name .. " -> moved to log")
                    self:Refresh()
                    self:RefreshMini()
                end
            end
        end)

        mainFrame.statusText:SetText(#ns.db.queue .. " items in queue  |  Right-click to mark as posted")

    elseif self.currentPage == "log" then
        mainFrame.pageTitle:SetText(ns.COLORS.GREEN .. "Posted Items Log" .. "|r")
        LayoutActionBtns(mainFrame.actionBtns.clearLog)
        ShowTable(self.logTable)

        local data = BuildLogData()
        self.logTable:SetData(data)
        self.logTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" and IsShiftKeyDown() and rowData._logIndex then
                table.remove(ns.db.log, rowData._logIndex)
                ns:Print("Removed from log: " .. rowData.name)
                self:Refresh()
            end
        end)

        mainFrame.statusText:SetText(logCount .. " logged items  |  Shift+Right-click to remove")

    elseif self.currentPage == "inventory" then
        mainFrame.pageTitle:SetText("Untracked Inventory")
        LayoutActionBtns(mainFrame.actionBtns.dnt)
        ShowTable(self.inventoryTable)

        local data = BuildInventoryData()
        self.inventoryTable:SetData(data)
        self.inventoryTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" then
                if IsShiftKeyDown() then
                    ns.Queue:Add({{
                        itemKey  = rowData._itemKey,
                        itemID   = rowData._itemID,
                        name     = rowData._itemName,
                        quantity = rowData._quantity,
                    }})
                    ns:Print("Added to queue: " .. rowData.name)
                else
                    ns.Queue:AddDoNotTrack(rowData._itemID, rowData._itemName)
                    ns:Print("Do not track: " .. rowData.name)
                end
                self:Refresh()
            end
        end)

        mainFrame.statusText:SetText(#data .. " untracked items  |  Right-click: DNT  |  Shift+Right: Add to queue")
    end
end

-- ==========================================
-- BACKWARD COMPATIBILITY
-- ==========================================

-- These methods are still called by MiniView, SlashCommands, etc.
function UI:HideAllRows()
    -- No-op in new system, tables handle their own cleanup
end

function UI:GetOrCreateRow(index)
    -- Minimal stub for any remaining callers
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
    UI:Refresh()
end)
