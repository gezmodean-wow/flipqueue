-- UI/MainFrame.lua
-- Main window: side nav, content area, scroll tables, refresh orchestration
local addonName, ns = ...

local UI = ns.UI

UI.currentPage = "todo"

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
resizeGrip:SetSize(24, 24)
resizeGrip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -3, 3)
resizeGrip:SetHitRectInsets(-8, -4, -8, -4)
resizeGrip:SetFrameLevel(mainFrame:GetFrameLevel() + 10)

-- Diagonal grip dots: 3x3px squares in a triangle pattern
local gripDots = {}
local dotPositions = {
    {1, 1},
    {7, 1}, {1, 7},
    {13, 1}, {7, 7}, {1, 13},
}
for _, pos in ipairs(dotPositions) do
    local dot = resizeGrip:CreateTexture(nil, "ARTWORK", nil, 7)
    dot:SetColorTexture(1, 1, 1, 0.5)
    dot:SetSize(3, 3)
    dot:SetPoint("BOTTOMRIGHT", resizeGrip, "BOTTOMRIGHT", -pos[1], pos[2])
    table.insert(gripDots, dot)
end

resizeGrip:SetScript("OnEnter", function()
    for _, dot in ipairs(gripDots) do
        dot:SetColorTexture(1, 0.82, 0, 1.0)
    end
end)
resizeGrip:SetScript("OnLeave", function()
    for _, dot in ipairs(gripDots) do
        dot:SetColorTexture(1, 1, 1, 0.5)
    end
end)
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

-- Sidebar resize handle (4px drag strip on right edge)
local sidebarHandle = CreateFrame("Button", nil, mainFrame)
sidebarHandle:SetWidth(4)
sidebarHandle:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
sidebarHandle:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
sidebarHandle:SetFrameLevel(sidebar:GetFrameLevel() + 5)

local sidebarHandleTex = sidebarHandle:CreateTexture(nil, "ARTWORK")
sidebarHandleTex:SetAllPoints()
sidebarHandleTex:SetColorTexture(0.3, 0.3, 0.4, 0)

sidebarHandle:SetScript("OnEnter", function()
    sidebarHandleTex:SetColorTexture(0.5, 0.5, 0.6, 0.6)
end)
sidebarHandle:SetScript("OnLeave", function()
    if not sidebarHandle._dragging then
        sidebarHandleTex:SetColorTexture(0.3, 0.3, 0.4, 0)
    end
end)
sidebarHandle:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        self._dragging = true
        self._startX = GetCursorPosition() / UIParent:GetEffectiveScale()
        self._startW = sidebar:GetWidth()
        sidebarHandleTex:SetColorTexture(1, 0.82, 0, 0.6)
        self:SetScript("OnUpdate", function()
            local curX = GetCursorPosition() / UIParent:GetEffectiveScale()
            local newW = math.max(80, math.min(200, self._startW + (curX - self._startX)))
            sidebar:SetWidth(newW)
        end)
    end
end)
sidebarHandle:SetScript("OnMouseUp", function(self)
    self._dragging = false
    sidebarHandleTex:SetColorTexture(0.3, 0.3, 0.4, 0)
    self:SetScript("OnUpdate", nil)
    if ns.db then
        ns.db.settings.sidebarWidth = sidebar:GetWidth()
    end
end)

local NAV_ITEMS = {
    {key = "section", label = "WORK"},
    {key = "todo",       label = "To-Do",          icon = "Interface\\Icons\\INV_Misc_Coin_02"},
    {key = "generator",  label = "To-Do Generator", icon = "Interface\\Icons\\INV_Scroll_03"},
    {key = "section", label = "DATA"},
    {key = "inventory",  label = "Inventory",      icon = "Interface\\Icons\\INV_Misc_Bag_07"},
    {key = "characters", label = "Characters",     icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"},
    {key = "section", label = "FLIPPINGPAL"},
    {key = "import",     label = "Import",         icon = "Interface\\Icons\\Ability_Creature_Cursed_04"},
    {key = "export",     label = "Export",         icon = "Interface\\Icons\\INV_Scroll_11"},
    {key = "section", label = "INTEGRATIONS"},
    {key = "tsm",        label = "TSM",            icon = "Interface\\Icons\\INV_Misc_Coin_17"},
    {key = "auctionator", label = "Auctionator",   icon = "Interface\\Icons\\INV_Misc_Note_01"},
    {key = "sep"},
    {key = "log",        label = "Log",            icon = "Interface\\Icons\\INV_Misc_Book_09"},
    {key = "settings",   label = "Settings",       icon = "Interface\\Icons\\INV_Gizmo_02"},
}

local navButtons = {}
local navY = -8

for _, nav in ipairs(NAV_ITEMS) do
    if nav.key == "section" then
        -- Section header: small gray uppercase text + thin divider
        navY = navY - 2
        local sep = sidebar:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6, navY)
        sep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -6, navY)
        sep:SetColorTexture(0.3, 0.3, 0.4, 0.4)
        navY = navY - 10

        local sectionLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sectionLabel:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, navY)
        sectionLabel:SetText(nav.label)
        sectionLabel:SetTextColor(0.45, 0.45, 0.5)
        navY = navY - 12
    elseif nav.key:find("^sep") then
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
        btn:SetScript("OnClick", function()
            UI.currentPage = navKey
            UI:Refresh()
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

mainFrame.actionBtns.rescan = CreateActionBtn("Rescan", "Rescan current character's bags", function()
    ns.Scanner:ScanCurrentCharacter()
    UI:Refresh()
end)

mainFrame.actionBtns.generate = CreateActionBtn("Generate", "Match queue deals against inventory (preview)", function()
    if ns.TodoList then
        UI._generatorPreview = ns.TodoList:GenerateTodoList(
            UI:GetGenAllocationOrder())
        local count = UI._generatorPreview and UI._generatorPreview.items and #UI._generatorPreview.items or 0
        local pending, missing = 0, 0
        for _, item in ipairs(UI._generatorPreview.items) do
            if item.status == "pending" then pending = pending + 1
            elseif item.status == "missing" then missing = missing + 1 end
        end
        ns:Print(ns.COLORS.GREEN .. "Generated " .. count .. " task(s): " ..
            pending .. " ready" ..
            (missing > 0 and (", " .. missing .. " missing") or "") ..
            " — click Save to commit|r")
        UI:Refresh()
    end
end)

mainFrame.actionBtns.commitSave = CreateActionBtn("Save", "Save generated to-do list", function()
    if UI._generatorPreview and ns.TodoList then
        ns.TodoList:CommitList(UI._generatorPreview, "replace")
        local count = #UI._generatorPreview.items
        UI._generatorPreview = nil
        ns:Print(ns.COLORS.GREEN .. "Saved to-do list with " .. count .. " tasks.|r")
        UI:Refresh()
        if UI.RefreshMini then UI:RefreshMini() end
    end
end)

mainFrame.actionBtns.exportPoolToFP = CreateActionBtn("Export to FP", "Export filtered item pool as FP CSV", function()
    if ns.TodoList then
        local pool = ns.TodoList:GetFilteredItemPool(
            UI._genFilterMode or "all", UI._genFilterValue or "", UI._genExcludedItems or {})
        if #pool == 0 then
            ns:Print(ns.COLORS.RED .. "No items in pool to export.|r")
            return
        end
        -- Build CSV: ItemID;Name;Quality;iLvl;BonusIDs;Modifiers;Quantity
        local lines = {"ItemID;Name;Quality;iLvl;BonusIDs;Modifiers;Quantity"}
        for _, item in ipairs(pool) do
            local itemID = item.itemKey and item.itemKey:match("^(%d+)") or item.itemID or ""
            local bonusIDs = item.itemKey and item.itemKey:match("^%d+;([^;]*)") or ""
            local modifiers = item.itemKey and item.itemKey:match("^%d+;[^;]*;(.*)$") or ""
            table.insert(lines, table.concat({
                itemID,
                item.name or "Unknown",
                "", -- quality
                "0", -- ilvl
                bonusIDs,
                modifiers,
                tostring(item.totalQuantity or 1),
            }, ";"))
        end
        local csv = table.concat(lines, "\n")
        -- Store pending export data, switch to export page, render will pick it up
        UI._pendingExportCSV = csv
        UI._pendingExportCount = #pool
        UI.currentPage = "export"
        UI:Refresh()
    end
end)

mainFrame.actionBtns.clearTodoList = CreateActionBtn("Clear All Lists", "Clear current and all queued to-do lists", function()
    StaticPopupDialogs["FLIPQUEUE_CLEAR_TODOLIST"] = {
        text = "Clear ALL to-do lists (current + queued)?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            if ns.TodoList then
                ns.TodoList:ClearCurrent()
                if ns.db and ns.db.todoLists then
                    wipe(ns.db.todoLists.queue)
                end
                UI._generatorPreview = nil
                ns:Print("All to-do lists cleared.")
                UI:Refresh()
                if UI.RefreshMini then UI:RefreshMini() end
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FLIPQUEUE_CLEAR_TODOLIST")
end)

mainFrame.actionBtns.importFromFP = CreateActionBtn("Import from FP", "Switch to Import page to paste FlippingPal data", function()
    UI.currentPage = "import"
    UI:Refresh()
end)

mainFrame.actionBtns.importPreview = CreateActionBtn("Preview", "Parse and preview import results", function()
    local text = UI._importEdit:GetText()
    if text and text ~= "" then
        local items = ns.Import:Parse(text)
        if #items > 0 then
            UI._importPreviewClear()
            -- Re-parse to get fresh preview
            local previewItems = ns.Import:Parse(text)
            -- Store preview data via a direct approach
            UI._importSetPreview(previewItems, ns.Queue:PreviewAdd(previewItems))
            UI:RefreshImportPreview()
        else
            UI._importStatus:SetText(ns.COLORS.RED .. "No items found in pasted data.|r")
        end
    end
end)

mainFrame.actionBtns.importDo = CreateActionBtn("Import", "Import previewed items to queue", function()
    local previewData = UI._importPreviewData()
    if previewData and #previewData > 0 then
        local added = ns.Queue:Add(previewData)
        ns:Print("Imported " .. added .. " new items (" .. #previewData .. " parsed, duplicates merged).")
        UI._importEdit:SetText("")
        UI._importPreviewClear()
        UI.importPreviewTable:SetData({})
        UI._importStatus:SetText(ns.COLORS.GREEN .. added .. " items imported!|r")
        if UI._tryAutoGenerateTodo then UI._tryAutoGenerateTodo() end
        UI:Refresh()
        UI:RefreshMini()
    else
        -- No preview data — try direct parse
        local text = UI._importEdit:GetText()
        if text and text ~= "" then
            local items = ns.Import:Parse(text)
            if #items > 0 then
                local added = ns.Queue:Add(items)
                ns:Print("Imported " .. added .. " new items (" .. #items .. " parsed, duplicates merged).")
                UI._importEdit:SetText("")
                UI._importPreviewClear()
                UI.importPreviewTable:SetData({})
                UI._importStatus:SetText(ns.COLORS.GREEN .. added .. " items imported!|r")
                if UI._tryAutoGenerateTodo then UI._tryAutoGenerateTodo() end
                UI:Refresh()
                UI:RefreshMini()
            else
                UI._importStatus:SetText(ns.COLORS.RED .. "No items found in pasted data.|r")
            end
        end
    end
end)

mainFrame.actionBtns.importClear = CreateActionBtn("Clear", "Clear import text and preview", function()
    UI._importEdit:SetText("")
    UI._importPreviewClear()
    UI.importPreviewTable:SetData({})
    UI._importStatus:SetText("")
    UI._importEdit:SetFocus(true)
end)

-- Helper: perform export with current filter and format settings
local function DoFilteredExport(getItemsFn, source)
    local csv, count = getItemsFn()

    -- If format is AAA JSON, re-export as AAA
    if ns.Export:GetFormat() == "aaa" then
        -- Parse CSV back to item data list for AAA export
        -- Instead, use ExportSaved which returns aggregated data
        -- For live scans, we need the raw data — export CSV then re-parse
        -- Simpler: use ExportSaved for AAA mode
        local savedCsv, savedCount = ns.Export:ExportSaved("all")

        -- Parse CSV into item data list
        local itemDataList = {}
        local first = true
        for line in savedCsv:gmatch("[^\n]+") do
            if first then
                first = false -- skip header
            else
                local id, name, quality, ilvl, bonus, mods, qty = line:match("([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*)")
                if id then
                    table.insert(itemDataList, {
                        itemID = id, itemName = name, quality = quality,
                        ilvl = tonumber(ilvl) or 0, bonusIDs = bonus or "",
                        modifiers = mods or "", quantity = tonumber(qty) or 1,
                    })
                end
            end
        end

        -- Apply filter
        itemDataList = ns.Export:ApplyFilter(itemDataList)

        local result, countFn = ns.Export:ExportAAA(itemDataList,
            ns.Export:GetAAADiscount(), ns.Export:GetAAAPriceSource())
        local ic, pc = countFn()

        local output = "// Items:\n" .. result.items .. "\n\n// Pets:\n" .. result.pets
        UI._exportEdit:SetText(output)
        UI._exportStatus:SetText(ns.COLORS.GREEN .. ic .. " items, " .. pc .. " pets|r — AAA JSON from " .. source)
    else
        UI._exportEdit:SetText(csv)
        UI._exportStatus:SetText(ns.COLORS.GREEN .. count .. " items|r from " .. source)
    end

    UI._exportEdit:HighlightText()
    UI._exportEdit:SetFocus(true)
end

mainFrame.actionBtns.exportBags = CreateActionBtn("Bags", "Export bag inventory", function()
    DoFilteredExport(function() return ns.Export:ExportBags() end, "bags")
end)

mainFrame.actionBtns.exportBank = CreateActionBtn("Bank", "Export bank (bank must be open)", function()
    DoFilteredExport(function() return ns.Export:ExportBank() end, "bank")
end)

mainFrame.actionBtns.exportWarbank = CreateActionBtn("Warbank", "Export warbank (bank must be open)", function()
    DoFilteredExport(function() return ns.Export:ExportWarbank() end, "warbank")
end)

mainFrame.actionBtns.exportAll = CreateActionBtn("All", "Export all containers (live scan)", function()
    DoFilteredExport(function() return ns.Export:ExportAll() end, "all containers")
end)

mainFrame.actionBtns.exportSaved = CreateActionBtn("Saved All", "Export all from saved scans (no bank needed)", function()
    DoFilteredExport(function() return ns.Export:ExportSaved("all") end, "saved data")
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

-- Post Now columns (base — TSM column added dynamically)
local POST_NOW_COLS_BASE = {
    {key = "name",     label = "Item",     width = 200, sortable = true},
    {key = "qty",      label = "Qty",      width = 40,  align = "CENTER", sortable = true},
    {key = "price",    label = "Price",    width = 90,  sortable = true},
    {key = "realm",    label = "Realm",    width = 140, sortable = true},
    {key = "location", label = "Location", width = 100, sortable = true},
}
local POST_NOW_COLS_TSM = {
    {key = "name",     label = "Item",     width = 170, sortable = true},
    {key = "qty",      label = "Qty",      width = 35,  align = "CENTER", sortable = true},
    {key = "price",    label = "Price",    width = 70,  sortable = true},
    {key = "ahPrice",  label = "AH Price", width = 95,  sortable = true},
    {key = "realm",    label = "Realm",    width = 115, sortable = true},
    {key = "location", label = "Location", width = 85,  sortable = true},
}

UI.postNowTable = UI:CreateScrollTable(tableContainer, POST_NOW_COLS_BASE)
UI.postNowTable:SetSort("name", true)

-- Full Queue columns (base — TSM column added dynamically)
local QUEUE_COLS_BASE = {
    {key = "name",    label = "Item",     width = 180, sortable = true},
    {key = "qty",     label = "Qty",      width = 40,  align = "CENTER", sortable = true},
    {key = "price",   label = "Price",    width = 80,  sortable = true},
    {key = "realm",   label = "Sell Realm", width = 130, sortable = true},
    {key = "foundOn", label = "Found On", width = 130, sortable = true},
    {key = "status",  label = "Status",   width = 60,  align = "CENTER", sortable = true},
}
local QUEUE_COLS_TSM = {
    {key = "name",    label = "Item",     width = 150, sortable = true},
    {key = "qty",     label = "Qty",      width = 35,  align = "CENTER", sortable = true},
    {key = "price",   label = "Price",    width = 65,  sortable = true},
    {key = "ahPrice", label = "AH Price", width = 90,  sortable = true},
    {key = "realm",   label = "Sell Realm", width = 105, sortable = true},
    {key = "foundOn", label = "Found On", width = 105, sortable = true},
    {key = "status",  label = "Status",   width = 55,  align = "CENTER", sortable = true},
}

UI.queueTable = UI:CreateScrollTable(tableContainer, QUEUE_COLS_BASE)
UI.queueTable:SetSort("realm", true)

-- Track current TSM column state to avoid unnecessary rebuilds
local tsmColumnsActive = false

function UI:UpdateTSMColumns()
    local shouldShow = ns.db and ns.db.settings.tsmEnabled and ns.db.settings.tsmShowColumns and ns.TSM:IsAvailable()
    if shouldShow == tsmColumnsActive then return end
    tsmColumnsActive = shouldShow

    if shouldShow then
        self.postNowTable:SetColumns(POST_NOW_COLS_TSM)
        self.postNowTable:SetSort("name", true)
        self.queueTable:SetColumns(QUEUE_COLS_TSM)
        self.queueTable:SetSort("realm", true)
    else
        self.postNowTable:SetColumns(POST_NOW_COLS_BASE)
        self.postNowTable:SetSort("name", true)
        self.queueTable:SetColumns(QUEUE_COLS_BASE)
        self.queueTable:SetSort("realm", true)
    end
end

-- Log columns
UI.logTable = UI:CreateScrollTable(tableContainer, {
    {key = "name",      label = "Item",      width = 150, sortable = true},
    {key = "qty",       label = "Qty",       width = 30,  align = "CENTER", sortable = true},
    {key = "status",    label = "Status",    width = 52,  align = "CENTER", sortable = true},
    {key = "posted",    label = "Posted",    width = 72,  sortable = true},
    {key = "guide",     label = "FP Guide",  width = 72,  sortable = true},
    {key = "realm",     label = "Realm",     width = 100, sortable = true},
    {key = "character", label = "Character", width = 80,  sortable = true},
    {key = "date",      label = "Date",      width = 75,  sortable = true,
        format = function(v) return v or "" end},
})
UI.logTable:SetSort("date", false)

-- Inventory columns (full tradeable inventory)
UI.inventoryTable = UI:CreateScrollTable(tableContainer, {
    {key = "name",        label = "Item",         width = 180, sortable = true},
    {key = "qty",         label = "Qty",          width = 40,  align = "CENTER", sortable = true},
    {key = "owner",       label = "Owner",        width = 100, sortable = true},
    {key = "location",    label = "Location",     width = 80,  sortable = true},
    {key = "status",      label = "Status",       width = 70,  align = "CENTER", sortable = true},
    {key = "targetRealm", label = "Target Realm", width = 100, sortable = true},
})
UI.inventoryTable:SetSort("name", true)

-- Characters table
UI.charsTable = UI:CreateScrollTable(tableContainer, {
    {key = "toggle",    label = "",             width = 28,  align = "CENTER", sortable = false},
    {key = "name",      label = "Character",   width = 105, sortable = true},
    {key = "realm",     label = "Realm",        width = 120, sortable = true},
    {key = "gold",      label = "Gold",         width = 70,  align = "RIGHT", sortable = true},
    {key = "tasks",     label = "Tasks",        width = 40,  align = "CENTER", sortable = true},
    {key = "auctions",  label = "Auctions",     width = 100, align = "CENTER", sortable = true},
    {key = "lastLogin", label = "Last Login",   width = 75,  sortable = true},
    {key = "status",    label = "Status",       width = 62,  sortable = true},
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
    {key = "action",    label = "Action",     width = 85,  sortable = true},
    {key = "target",    label = "Target",     width = 185, sortable = true},
    {key = "itemCount", label = "Items",      width = 45,  align = "CENTER", sortable = true},
    {key = "value",     label = "Est. Value", width = 85,  sortable = true},
    {key = "detail",    label = "Detail",     width = 160, sortable = false},
})
UI.nextStepsTable:SetSort("_sortValue", false)

-- Generator preview table
UI.generatorPreviewTable = UI:CreateScrollTable(tableContainer, {
    {key = "name",      label = "Item",      width = 170, sortable = true},
    {key = "qty",       label = "Qty",       width = 35,  align = "CENTER", sortable = true},
    {key = "realm",     label = "Realm",     width = 110, sortable = true},
    {key = "character", label = "Character", width = 100, sortable = true},
    {key = "source",    label = "Source",    width = 65,  sortable = true},
    {key = "price",     label = "Price",     width = 70,  sortable = true},
    {key = "status",    label = "Status",    width = 60,  align = "CENTER", sortable = true},
})
UI.generatorPreviewTable:SetSort("status", true)

-- Generator state
UI._generatorPreview = nil

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
importInstr:SetPoint("TOPLEFT", importPage, "TOPLEFT", 8, -4)
importInstr:SetText("Paste FlippingPal data below, then click Preview:")
importInstr:SetTextColor(0.7, 0.7, 0.7)

-- Edit box area (top 100px)
local importEditBg = CreateFrame("Frame", nil, importPage, "BackdropTemplate")
importEditBg:SetPoint("TOPLEFT", importPage, "TOPLEFT", 4, -20)
importEditBg:SetPoint("TOPRIGHT", importPage, "TOPRIGHT", -4, -20)
importEditBg:SetHeight(80)
importEditBg:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = {left = 2, right = 2, top = 2, bottom = 2},
})
importEditBg:SetBackdropColor(0.05, 0.05, 0.08, 1)
importEditBg:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)

local importScroll = CreateFrame("ScrollFrame", "FlipQueueImportScrollInline", importEditBg, "UIPanelScrollFrameTemplate")
importScroll:SetPoint("TOPLEFT", importEditBg, "TOPLEFT", 6, -4)
importScroll:SetPoint("BOTTOMRIGHT", importEditBg, "BOTTOMRIGHT", -22, 4)

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

-- Preview table (below editbox, fills remaining space)
UI.importPreviewTable = UI:CreateScrollTable(importPage, {
    {key = "status",   label = "Status",  width = 52,  align = "CENTER", sortable = true},
    {key = "name",     label = "Item",    width = 160, sortable = true},
    {key = "realm",    label = "Realm",   width = 110, sortable = true},
    {key = "price",    label = "Price",   width = 70,  sortable = true},
    {key = "qty",      label = "Qty",     width = 30,  align = "CENTER", sortable = true},
    {key = "reason",   label = "Reason",  width = 128, sortable = true},
})
UI.importPreviewTable:SetSort("status", true)

-- Position the preview table below the editbox
UI.importPreviewTable.headerFrame:SetParent(importPage)
UI.importPreviewTable.headerFrame:ClearAllPoints()
UI.importPreviewTable.headerFrame:SetPoint("TOPLEFT", importEditBg, "BOTTOMLEFT", 0, -4)
UI.importPreviewTable.headerFrame:SetPoint("TOPRIGHT", importEditBg, "BOTTOMRIGHT", 0, -4)

UI.importPreviewTable.scrollFrame:SetParent(importPage)
UI.importPreviewTable.scrollFrame:ClearAllPoints()
UI.importPreviewTable.scrollFrame:SetPoint("TOPLEFT", UI.importPreviewTable.headerFrame, "BOTTOMLEFT", 0, 0)
UI.importPreviewTable.scrollFrame:SetPoint("BOTTOMRIGHT", importPage, "BOTTOMRIGHT", -22, 20)

local importStatus = importPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
importStatus:SetPoint("LEFT", importPage, "BOTTOMLEFT", 8, 10)
importStatus:SetTextColor(0.5, 0.5, 0.5)
importStatus:SetText("")

-- Auto-generate To-Do checkbox (right side, next to auto-import)
local importAutoGenCheck = CreateFrame("CheckButton", "FlipQueueImportAutoGenCheck", importPage, "UICheckButtonTemplate")
importAutoGenCheck:SetSize(22, 22)
importAutoGenCheck:SetPoint("RIGHT", importPage, "BOTTOMRIGHT", -8, 10)
local importAutoGenLabel = importPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
importAutoGenLabel:SetPoint("RIGHT", importAutoGenCheck, "LEFT", -2, 0)
importAutoGenLabel:SetText("Auto-generate To-Do")
importAutoGenLabel:SetTextColor(0.5, 0.5, 0.5)
importAutoGenCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Auto-generate To-Do List", 1, 1, 1)
    GameTooltip:AddLine("After import, automatically generate and save a\nTo-Do list using your current Generator settings.\n\n|cffff8800Warning:|r This replaces your current To-Do list.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
importAutoGenCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
importAutoGenCheck:SetScript("OnClick", function(self)
    if ns.db then ns.db.settings.importAutoGenerate = self:GetChecked() end
end)

-- Skip-preview checkbox
local importSkipCheck = CreateFrame("CheckButton", "FlipQueueImportSkipCheck", importPage, "UICheckButtonTemplate")
importSkipCheck:SetSize(22, 22)
importSkipCheck:SetPoint("RIGHT", importAutoGenLabel, "LEFT", -12, 0)
local importSkipLabel = importPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
importSkipLabel:SetPoint("RIGHT", importSkipCheck, "LEFT", -2, 0)
importSkipLabel:SetText("Auto-import")
importSkipLabel:SetTextColor(0.5, 0.5, 0.5)

-- Auto-generate To-Do list after import (if checkbox is checked)
local function TryAutoGenerateTodo()
    if not importAutoGenCheck:GetChecked() then return end
    if not ns.TodoList then return end
    local allocationOrder = UI:GetGenAllocationOrder()
    local preview = ns.TodoList:GenerateTodoList(allocationOrder)
    if preview and preview.items and #preview.items > 0 then
        ns.TodoList:CommitList(preview, "replace")
        local count = #preview.items
        ns:Print(ns.COLORS.CYAN .. "Auto-generated To-Do list with " .. count .. " tasks (replaced previous list).|r")
    end
end
UI._tryAutoGenerateTodo = TryAutoGenerateTodo

-- Stored preview data for import confirmation
local importPreviewData = nil -- raw items from Parse
local importPreviewResults = nil -- annotated items from PreviewAdd

-- Auto-detect paste and build preview
local importLastLen = 0
importEdit:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    local text = self:GetText()
    local newLen = #text
    if importLastLen < 10 and newLen > 50 and text:find("\n") then
        local items = ns.Import:Parse(text)
        if #items > 0 then
            if importSkipCheck:GetChecked() then
                -- Auto-import mode: skip preview, add directly
                local added = ns.Queue:Add(items)
                ns:Print("Imported " .. added .. " new items (" .. #items .. " parsed, duplicates merged).")
                importEdit:SetText("")
                importPreviewData = nil
                importPreviewResults = nil
                UI.importPreviewTable:SetData({})
                importStatus:SetText(ns.COLORS.GREEN .. added .. " items imported!|r")
                importLastLen = 0
                TryAutoGenerateTodo()
                UI:Refresh()
                UI:RefreshMini()
            else
                -- Preview mode: show preview table
                importPreviewData = items
                importPreviewResults = ns.Queue:PreviewAdd(items)
                UI:RefreshImportPreview()
            end
        else
            importStatus:SetText(ns.COLORS.RED .. "No items found in pasted data.|r")
        end
    end
    importLastLen = newLen
end)
importEdit:SetScript("OnEscapePressed", function() importEdit:ClearFocus() end)

-- Quality color map (inline since QUALITY_COLORS isn't in scope yet)
local IMPORT_QUALITY_COLORS = {
    Poor = "9d9d9d", Common = "ffffff", Uncommon = "1eff00",
    Rare = "0070dd", Epic = "a335ee", Legendary = "ff8000",
    Artifact = "e6cc80", Heirloom = "00ccff",
}

-- Build preview table display data
function UI:RefreshImportPreview()
    if not importPreviewResults then
        UI.importPreviewTable:SetData({})
        return
    end

    local data = {}
    local newCount, dupCount, updateCount = 0, 0, 0

    for _, result in ipairs(importPreviewResults) do
        local item = result.item
        local st = result._importStatus

        local dupeReason = result._dupeReason
        local statusStr, statusSort
        if st == "new" then
            statusStr = ns.COLORS.GREEN .. "New" .. "|r"
            statusSort = "1new"
            newCount = newCount + 1
        elseif st == "update" then
            statusStr = ns.COLORS.YELLOW .. "Update" .. "|r"
            statusSort = "2update"
            updateCount = updateCount + 1
        elseif st == "duplicate" then
            statusStr = ns.COLORS.GRAY .. "Dupe" .. "|r"
            statusSort = "3dupe"
            dupCount = dupCount + 1
        else
            statusStr = st or "?"
            statusSort = "4" .. (st or "")
        end

        local displayName = item.name or "?"
        local qColor = item.quality and IMPORT_QUALITY_COLORS[item.quality]
        if qColor then
            displayName = "|cff" .. qColor .. displayName .. "|r"
        end

        local reasonStr = ""
        if dupeReason then
            if st == "duplicate" then
                reasonStr = ns.COLORS.GRAY .. dupeReason .. "|r"
            elseif st == "update" then
                reasonStr = ns.COLORS.YELLOW .. dupeReason .. "|r"
            end
        end

        table.insert(data, {
            status   = statusStr,
            name     = displayName,
            realm    = item.targetRealm or "",
            price    = item.expectedPrice or "",
            qty      = item.quantity or 1,
            reason   = reasonStr,
            _sortStatus = statusSort,
            _tooltipText = item.name,
            _tooltipExtra = (item.targetRealm and item.targetRealm ~= "" and ("Sell on: " .. item.targetRealm) or "")
                .. (item.expectedPrice and item.expectedPrice ~= "" and ("\nPrice: " .. item.expectedPrice) or "")
                .. (st == "duplicate" and "\n" .. ns.COLORS.GRAY .. "Already in queue (" .. (dupeReason or "exact match") .. ") — will be skipped|r" or "")
                .. (st == "update" and "\n" .. ns.COLORS.YELLOW .. "Will update existing entry (" .. (dupeReason or "match") .. ")|r" or ""),
        })
    end

    UI.importPreviewTable:SetData(data)

    -- Show the preview table
    UI.importPreviewTable.headerFrame:Show()
    UI.importPreviewTable.scrollFrame:Show()

    local parts = {}
    if newCount > 0 then table.insert(parts, ns.COLORS.GREEN .. newCount .. " new|r") end
    if updateCount > 0 then table.insert(parts, ns.COLORS.YELLOW .. updateCount .. " updates|r") end
    if dupCount > 0 then table.insert(parts, ns.COLORS.GRAY .. dupCount .. " dupes|r") end
    importStatus:SetText(table.concat(parts, "  ") .. "  — click Import to confirm")
end

UI._importPage = importPage
UI._importEdit = importEdit
UI._importStatus = importStatus
UI._importPreviewData = function() return importPreviewData end
UI._importPreviewClear = function()
    importPreviewData = nil
    importPreviewResults = nil
    importLastLen = 0
end
UI._importSetPreview = function(items, results)
    importPreviewData = items
    importPreviewResults = results
end

-- Export page
local exportPage = CreateFrame("Frame", nil, tableContainer)
exportPage:SetAllPoints()
exportPage:Hide()

-- Format toggle row
local exportFormatLabel = exportPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
exportFormatLabel:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -6)
exportFormatLabel:SetText("Format:")
exportFormatLabel:SetTextColor(0.6, 0.6, 0.6)

local function CreateExportToggle(label, parent)
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
    btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.3, 1) end)
    btn:SetScript("OnLeave", function(self)
        if not self._active then self:SetBackdropColor(0.15, 0.15, 0.2, 1) end
    end)
    return btn
end

local fmtCSVBtn = CreateExportToggle("FP CSV", exportPage)
fmtCSVBtn:SetPoint("LEFT", exportFormatLabel, "RIGHT", 6, 0)

local fmtAAABtn = CreateExportToggle("AAA JSON", exportPage)
fmtAAABtn:SetPoint("LEFT", fmtCSVBtn, "RIGHT", 4, 0)

-- Filter toggle row
local exportFilterLabel = exportPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
exportFilterLabel:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -28)
exportFilterLabel:SetText("Filter:")
exportFilterLabel:SetTextColor(0.6, 0.6, 0.6)

local filterAllBtn = CreateExportToggle("Everything", exportPage)
filterAllBtn:SetPoint("LEFT", exportFilterLabel, "RIGHT", 6, 0)

local filterTSMBtn = CreateExportToggle("TSM Group", exportPage)
filterTSMBtn:SetPoint("LEFT", filterAllBtn, "RIGHT", 4, 0)

local filterAuctBtn = CreateExportToggle("Auctionator List", exportPage)
filterAuctBtn:SetPoint("LEFT", filterTSMBtn, "RIGHT", 4, 0)

-- Filter value input (hidden text box — kept for backwards compat, used by tree/list selection)
local filterValueBox = CreateFrame("EditBox", nil, exportPage, "InputBoxTemplate")
filterValueBox:SetSize(200, 20)
filterValueBox:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 52, -48)
filterValueBox:SetAutoFocus(false)
filterValueBox:SetMaxLetters(200)
filterValueBox:Hide()
filterValueBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
filterValueBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    ns.Export:SetFilter(ns.Export:GetFilterMode(), self:GetText())
end)

local filterValueLabel = exportPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
filterValueLabel:SetPoint("LEFT", filterValueBox, "RIGHT", 6, 0)
filterValueLabel:SetText("")

-- TSM Group Tree for export filter (shown when TSM Group filter selected)
local exportTreeFrame = CreateFrame("Frame", nil, exportPage)
exportTreeFrame:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 4, -48)
exportTreeFrame:SetPoint("RIGHT", exportPage, "RIGHT", -4, 0)
exportTreeFrame:SetHeight(100)
exportTreeFrame:Hide()

local exportGroupTree
if UI.CreateGroupTree then
    exportGroupTree = UI:CreateGroupTree(exportTreeFrame, function(path)
        filterValueBox:SetText(path or "")
        ns.Export:SetFilter("tsmgroup", path or "")
        -- Update status text
        if filterValueLabel then
            filterValueLabel:SetText(path and path ~= "" and (ns.COLORS.YELLOW .. path:gsub("`", " > ") .. "|r") or "")
        end
    end)
end

-- Auctionator list picker for export filter
local exportAuctFrame = CreateFrame("Frame", nil, exportPage)
exportAuctFrame:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 4, -48)
exportAuctFrame:SetPoint("RIGHT", exportPage, "RIGHT", -4, 0)
exportAuctFrame:SetHeight(80)
exportAuctFrame:Hide()

local exportAuctScroll = CreateFrame("ScrollFrame", nil, exportAuctFrame, "UIPanelScrollFrameTemplate")
exportAuctScroll:SetPoint("TOPLEFT", exportAuctFrame, "TOPLEFT", 0, 0)
exportAuctScroll:SetPoint("BOTTOMRIGHT", exportAuctFrame, "BOTTOMRIGHT", -16, 0)

local exportAuctContent = CreateFrame("Frame", nil, exportAuctScroll)
exportAuctContent:SetWidth(1)
exportAuctContent:SetHeight(1)
exportAuctScroll:SetScrollChild(exportAuctContent)
exportAuctScroll:SetScript("OnSizeChanged", function(sf, w)
    exportAuctContent:SetWidth(w)
end)
local exportAuctRows = {}

-- AAA settings row (shown when AAA format selected)
local aaaRow = CreateFrame("Frame", nil, exportPage)
aaaRow:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -48)
aaaRow:SetPoint("RIGHT", exportPage, "RIGHT", -8, 0)
aaaRow:SetHeight(22)
aaaRow:Hide()

local aaaDiscountLabel = aaaRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aaaDiscountLabel:SetPoint("LEFT", aaaRow, "LEFT", 0, 0)
aaaDiscountLabel:SetText("Discount %:")
aaaDiscountLabel:SetTextColor(0.6, 0.6, 0.6)

local aaaDiscountBox = CreateFrame("EditBox", nil, aaaRow, "InputBoxTemplate")
aaaDiscountBox:SetSize(40, 20)
aaaDiscountBox:SetPoint("LEFT", aaaDiscountLabel, "RIGHT", 4, 0)
aaaDiscountBox:SetAutoFocus(false)
aaaDiscountBox:SetMaxLetters(3)
aaaDiscountBox:SetText("90")
aaaDiscountBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
aaaDiscountBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    local val = tonumber(self:GetText())
    if val and val >= 0 and val <= 100 then
        ns.Export:SetAAASettings(val, nil)
    end
end)

local aaaSrcLabel = aaaRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aaaSrcLabel:SetPoint("LEFT", aaaDiscountBox, "RIGHT", 12, 0)
aaaSrcLabel:SetText("Price source:")
aaaSrcLabel:SetTextColor(0.6, 0.6, 0.6)

local aaaSrcBox = CreateFrame("EditBox", nil, aaaRow, "InputBoxTemplate")
aaaSrcBox:SetSize(120, 20)
aaaSrcBox:SetPoint("LEFT", aaaSrcLabel, "RIGHT", 4, 0)
aaaSrcBox:SetAutoFocus(false)
aaaSrcBox:SetMaxLetters(100)
aaaSrcBox:SetText("DBMarket")
aaaSrcBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
aaaSrcBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    ns.Export:SetAAASettings(nil, self:GetText())
end)

-- Active filter text
local exportFilterStatus = exportPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
exportFilterStatus:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -70)
exportFilterStatus:SetTextColor(0.5, 0.5, 0.5)
exportFilterStatus:SetText("")

-- Toggle state update functions
local function UpdateFormatButtons()
    local fmt = ns.Export:GetFormat()
    fmtCSVBtn._active = (fmt == "csv")
    fmtAAABtn._active = (fmt == "aaa")
    fmtCSVBtn:SetBackdropColor(fmt == "csv" and 0.2 or 0.15, fmt == "csv" and 0.4 or 0.15, fmt == "csv" and 0.2 or 0.2, 1)
    fmtAAABtn:SetBackdropColor(fmt == "aaa" and 0.2 or 0.15, fmt == "aaa" and 0.4 or 0.15, fmt == "aaa" and 0.2 or 0.2, 1)

    if fmt == "aaa" then
        aaaRow:Show()
        -- Shift filter row down
        exportFilterStatus:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -92)
    else
        aaaRow:Hide()
        exportFilterStatus:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -70)
    end
end

local function UpdateFilterButtons()
    local mode = ns.Export:GetFilterMode()
    filterAllBtn._active = (mode == "everything")
    filterTSMBtn._active = (mode == "tsmgroup")
    filterAuctBtn._active = (mode == "auctionator")
    filterAllBtn:SetBackdropColor(mode == "everything" and 0.2 or 0.15, mode == "everything" and 0.4 or 0.15, mode == "everything" and 0.2 or 0.2, 1)
    filterTSMBtn:SetBackdropColor(mode == "tsmgroup" and 0.2 or 0.15, mode == "tsmgroup" and 0.4 or 0.15, mode == "tsmgroup" and 0.2 or 0.2, 1)
    filterAuctBtn:SetBackdropColor(mode == "auctionator" and 0.2 or 0.15, mode == "auctionator" and 0.4 or 0.15, mode == "auctionator" and 0.2 or 0.2, 1)

    -- Hide all filter-specific controls first
    filterValueBox:Hide()
    filterValueLabel:SetText("")
    exportTreeFrame:Hide()
    exportAuctFrame:Hide()
    for _, row in ipairs(exportAuctRows) do row:Hide() end

    if mode == "tsmgroup" then
        -- Show TSM Group Tree navigator
        if exportGroupTree and ns.TSM and ns.TSM:IsEnabled() then
            local profile = ns.TSM:GetSelectedProfile()
            exportTreeFrame:Show()
            if profile and exportGroupTree._profile ~= profile then
                exportGroupTree:SetProfile(profile)
            end
            -- Show current selection
            local val = ns.Export:GetFilterValue()
            if val and val ~= "" then
                filterValueLabel:SetPoint("TOPLEFT", exportTreeFrame, "BOTTOMLEFT", 6, -2)
                filterValueLabel:SetText(ns.COLORS.YELLOW .. "Group: " .. val:gsub("`", " > ") .. "|r")
            end
        else
            -- Fallback to text box if TSM not available
            filterValueBox:Show()
            filterValueBox:SetText(ns.Export:GetFilterValue())
            filterValueLabel:SetText("TSM group path")
        end
    elseif mode == "auctionator" then
        -- Show Auctionator list dropdown
        local listNames = ns:GetAuctionatorListNames()
        local auctAvailable = #listNames > 0 or type(AUCTIONATOR_SHOPPING_LISTS) == "table"

        if auctAvailable then

            exportAuctFrame:Show()
            local listHeight = math.min(80, math.max(20, #listNames * 18 + 4))
            exportAuctFrame:SetHeight(listHeight)

            exportAuctContent:SetWidth(exportAuctScroll:GetWidth() or 200)

            local currentVal = ns.Export:GetFilterValue()
            local auctY = 0
            for idx, listName in ipairs(listNames) do
                local row = exportAuctRows[idx]
                if not row then
                    row = CreateFrame("Button", nil, exportAuctContent)
                    row:SetHeight(18)
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
                    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                    row.label:SetJustifyH("LEFT")
                    row:EnableMouse(true)
                    exportAuctRows[idx] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", exportAuctContent, "TOPLEFT", 0, -auctY)
                row:SetPoint("RIGHT", exportAuctContent, "RIGHT", 0, 0)

                local isSelected = (currentVal == listName)
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
                    ns.Export:SetFilter("auctionator", capturedName)
                    UpdateFilterButtons()
                end)
                row:SetScript("OnEnter", function(self)
                    if not isSelected then self.bg:SetColorTexture(1, 1, 1, 0.05) end
                end)
                row:SetScript("OnLeave", function(self)
                    if not (ns.Export:GetFilterValue() == capturedName) then self.bg:SetColorTexture(0, 0, 0, 0) end
                end)

                row:Show()
                auctY = auctY + 18
            end
            exportAuctContent:SetHeight(math.max(1, auctY))
        else
            -- Fallback to text box
            filterValueBox:Show()
            filterValueBox:SetText(ns.Export:GetFilterValue())
            filterValueLabel:SetText("Shopping list name")
        end
    else
        -- "everything" — nothing extra to show
    end

    -- Status text
    if mode == "everything" then
        exportFilterStatus:SetText("")
    else
        local val = ns.Export:GetFilterValue()
        if mode == "tsmgroup" then
            exportFilterStatus:SetText(val ~= "" and (ns.COLORS.YELLOW .. "Group: " .. val:gsub("`", " > ") .. "|r") or "")
        elseif mode == "auctionator" then
            exportFilterStatus:SetText(val ~= "" and (ns.COLORS.YELLOW .. "List: " .. val .. "|r") or "")
        else
            exportFilterStatus:SetText(ns.COLORS.YELLOW .. "Filter: " .. mode .. (val ~= "" and (" = " .. val) or "") .. "|r")
        end
    end

    -- Reposition export scroll to account for filter controls height
    local scrollTop = -90
    if mode == "tsmgroup" and exportTreeFrame:IsShown() then
        -- Tree at -48, height 100, plus selected path label + padding
        scrollTop = -48 - exportTreeFrame:GetHeight() - 20
        if filterValueLabel:GetText() and filterValueLabel:GetText() ~= "" then
            scrollTop = scrollTop - 14
        end
    elseif mode == "auctionator" and exportAuctFrame:IsShown() then
        scrollTop = -48 - exportAuctFrame:GetHeight() - 12
    end
    exportScroll:ClearAllPoints()
    exportScroll:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 4, scrollTop)
    exportScroll:SetPoint("BOTTOMRIGHT", exportPage, "BOTTOMRIGHT", -24, 34)
    exportFilterStatus:ClearAllPoints()
    exportFilterStatus:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, scrollTop + 16)
end

fmtCSVBtn:SetScript("OnClick", function()
    ns.Export:SetFormat("csv")
    UpdateFormatButtons()
end)
fmtAAABtn:SetScript("OnClick", function()
    ns.Export:SetFormat("aaa")
    UpdateFormatButtons()
end)

filterAllBtn:SetScript("OnClick", function()
    ns.Export:SetFilter("everything", "")
    UpdateFilterButtons()
end)
filterTSMBtn:SetScript("OnClick", function()
    ns.Export:SetFilter("tsmgroup", filterValueBox:GetText())
    UpdateFilterButtons()
end)
filterAuctBtn:SetScript("OnClick", function()
    ns.Export:SetFilter("auctionator", filterValueBox:GetText())
    UpdateFilterButtons()
end)

-- Export edit box (below controls)
local exportScroll = CreateFrame("ScrollFrame", "FlipQueueExportScrollInline", exportPage, "UIPanelScrollFrameTemplate")
exportScroll:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 4, -90)
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
UI._updateExportToggles = function()
    UpdateFormatButtons()
    UpdateFilterButtons()
end

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
RegisterTable(UI.importPreviewTable)
RegisterTable(UI.generatorPreviewTable)

local function HideAllTables()
    for _, tbl in ipairs(allTables) do
        tbl.headerFrame:Hide()
        tbl.scrollFrame:Hide()
    end
    UI:HideSettingsPage()
    if UI.HideTSMPage then UI:HideTSMPage() end
    if UI.HideAuctionatorPage then UI:HideAuctionatorPage() end
    importPage:Hide()
    exportPage:Hide()
    if UI._genInfoFrame then UI._genInfoFrame:Hide() end
    if UI._genFrame then UI._genFrame:Hide() end
    if UI._todoOverviewScroll then UI._todoOverviewScroll:Hide() end
    if UI._charTasksFrame then UI._charTasksFrame:Hide() end
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

            local row = {
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
            }

            -- TSM price data
            if ns.TSM:IsEnabled() then
                local priceSource = ns.db.settings.tsmPriceSource or "DBMinBuyout"
                local copper = ns.TSM:GetPrice(qi.itemKey, priceSource)
                if copper then
                    row.ahPrice = ns.TSM:FormatCopper(copper)
                    row._sortAhPrice = copper

                    -- Per-item threshold from TSM Auctioning operation
                    local belowThreshold, ahMin, threshold, opName = ns.TSM:IsBelowThreshold(qi.itemKey)
                    if belowThreshold then
                        row.ahPrice = "|cffff4444" .. row.ahPrice .. "|r"
                        row._rowColor = {0.8, 0.2, 0.2, 0.10}
                        row.location = "|cffff4444TSM: SKIP|r"
                        local threshStr = ns.TSM:FormatCopper(threshold) or "?"
                        local opStr = opName and (" [" .. opName .. "]") or ""
                        row._tooltipExtra = (row._tooltipExtra or "")
                            .. "\n|cffff4444TSM will skip this item — AH price below min (" .. threshStr .. ")" .. opStr .. "|r"
                            .. "\n|cffff4444Right-click to skip, or wait for price to recover|r"
                    else
                        row.ahPrice = "|cff00ff00" .. row.ahPrice .. "|r"
                    end

                    -- Auto-update expected price (only if import is old enough)
                    if ns.db.settings.tsmAutoUpdatePrice then
                        local maxAge = ns.db.settings.tsmPriceMaxAge or 3600
                        local priceAge = qi.priceUpdatedAt or qi.addedAt or 0
                        if maxAge == 0 or (time() - priceAge) > maxAge then
                            qi.expectedPrice = ns:FormatGold(copper)
                            qi.priceSource = "TSM"
                            qi.priceUpdatedAt = time()
                            row.price = qi.expectedPrice
                        end
                    end
                else
                    row.ahPrice = "|cff888888" .. "\226\128\148" .. "|r"  -- em dash
                    row._sortAhPrice = 0
                end
            end

            table.insert(data, row)
        end
    end

    return data
end

-- Build To-Do data from TodoList (new system)
local function BuildTodoData()
    if not ns.db or not ns.TodoList then return nil end
    local currentList = ns.TodoList:GetCurrentList()
    if not currentList then return nil end

    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""
    local tasks = ns.TodoList:GetCharacterTasks(charKey)
    local data = {}

    for _, task in ipairs(tasks) do
        local item = task.item
        if ns:RealmMatches(item.targetRealm or "", myRealm) then
            local displayName = item.name or "?"

            local lookupIcon, quality, resolvedID
            pcall(function()
                lookupIcon, quality, resolvedID = LookupItemInfo(item.itemID, item.itemKey, item.name)
            end)

            if quality then
                displayName = QualityColorName(displayName, quality)
            elseif item.quality and item.quality ~= "" then
                displayName = QualityColorName(displayName, item.quality)
            end

            local sourceStr = item.source or ""
            if sourceStr == "warbank" then
                sourceStr = ns.COLORS.YELLOW .. "warbank" .. "|r"
            elseif sourceStr == "bags" then
                sourceStr = ns.COLORS.GREEN .. "in bags" .. "|r"
            elseif sourceStr == "bank" then
                sourceStr = ns.COLORS.BLUE .. "bank" .. "|r"
            elseif sourceStr == "reagent" then
                sourceStr = "reagent"
            elseif sourceStr == "guildbank" then
                sourceStr = ns.COLORS.ORANGE .. "guild bank" .. "|r"
            elseif sourceStr == "unavailable" and item.depositFrom then
                local depName = item.depositFrom:match("^(.-)%-") or item.depositFrom
                sourceStr = ns.COLORS.CYAN .. "via " .. depName .. "|r"
            elseif sourceStr == "unavailable" then
                sourceStr = ns.COLORS.RED .. "unavailable" .. "|r"
            end

            local row = {
                name     = displayName,
                qty      = item.quantity or 1,
                price    = item.expectedPrice or "",
                realm    = item.targetRealm or "",
                location = sourceStr,
                _icon    = item.icon or lookupIcon,
                _tooltipItemID = resolvedID or tonumber(item.itemID),
                _tooltipText   = item.name or "?",
                _tooltipExtra  = (item.targetRealm and item.targetRealm ~= ""
                    and ("Sell on: " .. item.targetRealm .. "  @  " .. (item.expectedPrice or "?")) or nil),
                _taskIndex = task.taskIndex,
                _todoItem  = item,
            }

            -- TSM price data
            if ns.TSM:IsEnabled() then
                local priceSource = ns.db.settings.tsmPriceSource or "DBMinBuyout"
                local copper = ns.TSM:GetPrice(item.itemKey, priceSource)
                if copper then
                    row.ahPrice = ns.TSM:FormatCopper(copper)
                    row._sortAhPrice = copper
                    local belowThreshold, _, threshold, opName = ns.TSM:IsBelowThreshold(item.itemKey)
                    if belowThreshold then
                        row.ahPrice = "|cffff4444" .. row.ahPrice .. "|r"
                        row._rowColor = {0.8, 0.2, 0.2, 0.10}
                        row.location = "|cffff4444TSM: SKIP|r"
                    else
                        row.ahPrice = "|cff00ff00" .. row.ahPrice .. "|r"
                    end
                else
                    row.ahPrice = "|cff888888" .. "\226\128\148" .. "|r"
                    row._sortAhPrice = 0
                end
            end

            table.insert(data, row)
        end
    end

    return data
end

-- ==========================================
-- CURRENT CHARACTER TASKS (shown above items on To-Do)
-- ==========================================

local function BuildCurrentCharTasks()
    if not ns.db then return {} end
    local tasks = {}
    local myCharKey = ns:GetCharKey()
    local myRealm = myCharKey:match("%-(.+)$") or ""

    -- Auction summary for current character
    local auctionsByChar = ns.Tracker and ns.Tracker.GetAuctionSummaryByCharacter
        and ns.Tracker:GetAuctionSummaryByCharacter() or {}
    local myAuctions = auctionsByChar[myCharKey]

    -- Check AH: expired auctions to collect
    if myAuctions and myAuctions.done > 0 then
        table.insert(tasks, {
            icon   = "Interface\\Icons\\INV_Misc_Coin_02",
            text   = ns.COLORS.GREEN .. "Check AH:|r " .. myAuctions.done .. " auction(s) expired — collect at AH",
            sort   = 1,
        })
    end

    -- Check Mail: expired items waiting to be collected (not yet marked "collected")
    -- Only count "expired" status — "sold" and "collected" are already handled
    -- Note: "expired" means the auction ended without a sale and items are in mailbox
    local expiredInMail = 0
    for _, entry in ipairs(ns.db.log) do
        if entry.charKey == myCharKey and entry.auctionStatus == "expired" then
            expiredInMail = expiredInMail + 1
        end
    end
    if expiredInMail > 0 then
        table.insert(tasks, {
            icon   = "Interface\\Icons\\INV_Letter_15",
            text   = ns.COLORS.YELLOW .. "Check Mail:|r " .. expiredInMail .. " expired auction(s) to collect",
            sort   = 2,
        })
    end

    -- Expiring soon on this character
    if myAuctions and myAuctions.active > 0 and myAuctions.soonest then
        local alertMinutes = ns.db.settings.expiryAlertMinutes or 15
        if myAuctions.soonest < (alertMinutes * 60) then
            local h = math.floor(myAuctions.soonest / 3600)
            local m = math.floor((myAuctions.soonest % 3600) / 60)
            local countdown = h > 0 and (h .. "h " .. m .. "m") or (m .. "m")
            table.insert(tasks, {
                icon   = "Interface\\Icons\\Spell_Holy_BorrowedTime",
                text   = ns.COLORS.ORANGE .. "Expiring:|r " .. myAuctions.active .. " auction(s) — soonest in " .. countdown,
                sort   = 3,
            })
        end
    end

    -- Active auctions info (not urgent, just informational)
    if myAuctions and myAuctions.active > 0 and #tasks == 0 then
        -- Only show if no urgent tasks — just a status line
        table.insert(tasks, {
            icon   = "Interface\\Icons\\INV_Misc_Coin_17",
            text   = ns.COLORS.GRAY .. myAuctions.active .. " active auction(s) on this character|r",
            sort   = 10,
        })
    end

    -- Deposit to warbank: items on this character that another character needs
    local todoList = ns.TodoList and ns.TodoList:GetCurrentList()
    if todoList and todoList.items then
        local depositCount = 0
        for _, item in ipairs(todoList.items) do
            if item.source == "unavailable" and item.depositFrom == myCharKey then
                depositCount = depositCount + 1
            end
        end
        if depositCount > 0 then
            table.insert(tasks, {
                icon   = "Interface\\Icons\\INV_Misc_Bag_10",
                text   = ns.COLORS.CYAN .. "Deposit:|r " .. depositCount .. " item(s) to warbank for other characters",
                sort   = 0,  -- highest priority
            })
        end
    end

    table.sort(tasks, function(a, b) return a.sort < b.sort end)
    return tasks
end

-- ==========================================
-- NEXT STEPS (other characters, shown below on To-Do)
-- ==========================================

-- Gold parsing now uses ns:ParseGoldValue() from Core.lua
local function ParseGoldValue(priceStr)
    return ns:ParseGoldValue(priceStr)
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

    -- 1) Build "Log in" entries from the to-do list (primary source)
    local todoList = ns.TodoList and ns.TodoList:GetCurrentList()
    local depositsByChar = {}  -- charKey -> { count, items }
    local receiverOf = {}      -- receiverCharKey -> { depositorCharKey = true }

    if todoList and todoList.items then
        -- Collect deposit dependencies
        for _, item in ipairs(todoList.items) do
            if item.source == "unavailable" and item.depositFrom then
                if not depositsByChar[item.depositFrom] then
                    depositsByChar[item.depositFrom] = { count = 0, gold = 0 }
                end
                depositsByChar[item.depositFrom].count = depositsByChar[item.depositFrom].count + 1
                depositsByChar[item.depositFrom].gold = depositsByChar[item.depositFrom].gold
                    + (ns:ParseGoldValue(item.expectedPrice or "") or 0)

                -- Track dependency: receiver depends on depositor
                if item.assignedChar and item.depositFrom ~= item.assignedChar then
                    if not receiverOf[item.assignedChar] then
                        receiverOf[item.assignedChar] = {}
                    end
                    receiverOf[item.assignedChar][item.depositFrom] = true
                end
            end
        end

        local sortMode = (UI.GetGenSortMode and UI:GetGenSortMode()) or "profit"
        local displayGroups = ns.TodoList:BuildDisplayGroups(todoList.items, sortMode)

        for _, group in ipairs(displayGroups) do
            if group.charKey and group.charKey ~= myCharKey then
                local name = group.charName or "?"
                local realm = group.realm or ""
                local charInv = ns.db.inventory and ns.db.inventory[group.charKey]
                local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
                local coloredName = "|cff" .. classColor .. name .. "|r"

                -- Check if this character also has deposit tasks
                local depInfo = depositsByChar[group.charKey]
                local detailStr = #group.items .. " items to post"
                if depInfo then
                    detailStr = detailStr .. " + " .. depInfo.count .. " to deposit"
                    depositsByChar[group.charKey] = nil  -- merged, don't create standalone
                end

                table.insert(data, {
                    action    = ns.COLORS.YELLOW .. "Log in" .. "|r",
                    target    = coloredName .. "  (" .. realm .. ")",
                    itemCount = #group.items + (depInfo and depInfo.count or 0),
                    value     = FormatGoldValue(group.totalGold),
                    detail    = detailStr,
                    _sortValue = group.totalGold,
                    _charKey   = group.charKey,
                    _tooltipText = group.charKey,
                    _tooltipExtra = string.format("Log in to %s to post %d items\nEstimated value: %s",
                        group.charKey, #group.items, FormatGoldValue(group.totalGold)),
                })
            elseif not group.charKey then
                -- Unassigned group = "Create char" entry
                local realmName = group.realm ~= "" and group.realm or "unknown realm"
                table.insert(data, {
                    action    = "|cffff6666" .. "Create char" .. "|r",
                    target    = realmName,
                    itemCount = #group.items,
                    value     = FormatGoldValue(group.totalGold),
                    detail    = "",
                    _sortValue = -1,  -- always sort last
                    _tooltipText = realmName,
                    _tooltipExtra = string.format("Create a character on %s\n%d items worth ~%s waiting",
                        realmName, #group.items, FormatGoldValue(group.totalGold)),
                })
            end
        end
    end

    -- 2) Standalone deposit entries (depositors not already merged with "Log in")
    for charKey, depInfo in pairs(depositsByChar) do
        if charKey ~= myCharKey then
            local name = charKey:match("^(.-)%-") or charKey
            local realm = charKey:match("%-(.+)$") or ""
            local charInv = ns.db.inventory and ns.db.inventory[charKey]
            local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
            local coloredName = "|cff" .. classColor .. name .. "|r"

            table.insert(data, {
                action    = ns.COLORS.CYAN .. "Deposit" .. "|r",
                target    = coloredName .. "  (" .. realm .. ")",
                itemCount = depInfo.count,
                value     = FormatGoldValue(depInfo.gold),
                detail    = depInfo.count .. " to warbank",
                _sortValue = depInfo.gold,
                _charKey   = charKey,
                _tooltipText = charKey,
                _tooltipExtra = string.format("Log in to %s to deposit %d item(s) to warbank",
                    charKey, depInfo.count),
            })
        end
    end

    -- 3) Other characters with done (expired) auctions to check
    local auctionsByChar = ns.Tracker and ns.Tracker.GetAuctionSummaryByCharacter
        and ns.Tracker:GetAuctionSummaryByCharacter() or {}

    for charKey, info in pairs(auctionsByChar) do
        if info.done > 0 and charKey ~= myCharKey then
            local name = charKey:match("^(.-)%-") or charKey
            local realm = charKey:match("%-(.+)$") or ""
            local charInv = ns.db.inventory[charKey]
            local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
            local coloredName = "|cff" .. classColor .. name .. "|r"

            table.insert(data, {
                action    = ns.COLORS.GREEN .. "Check AH" .. "|r",
                target    = coloredName .. "  (" .. realm .. ")",
                itemCount = info.done,
                value     = FormatGoldValue(info.totalValue or 0),
                detail    = info.done .. " auction(s) done",
                _sortValue = -2,  -- sort after "Log in" entries, before "Create char"
                _tooltipText = charKey,
                _tooltipExtra = string.format("Log in to %s to collect %d expired auction(s)%s",
                    charKey, info.done,
                    info.active > 0 and ("\n" .. info.active .. " still active") or ""),
            })
        end
    end

    -- 4) Other characters with auctions expiring soon
    local alertMinutes = ns.db.settings.expiryAlertMinutes or 15
    local alertThreshold = alertMinutes * 60
    for charKey, info in pairs(auctionsByChar) do
        if charKey ~= myCharKey and info.active > 0 and info.soonest and info.soonest < alertThreshold then
            -- Skip if already shown as "Check AH" (has done auctions)
            if not (info.done > 0) then
                local name = charKey:match("^(.-)%-") or charKey
                local realm = charKey:match("%-(.+)$") or ""
                local charInv = ns.db.inventory[charKey]
                local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
                local coloredName = "|cff" .. classColor .. name .. "|r"

                -- Format countdown
                local h = math.floor(info.soonest / 3600)
                local m = math.floor((info.soonest % 3600) / 60)
                local countdown = h > 0 and (h .. "h " .. m .. "m") or (m .. "m")

                table.insert(data, {
                    action    = ns.COLORS.ORANGE .. "Expiring" .. "|r",
                    target    = coloredName .. "  (" .. realm .. ")",
                    itemCount = info.active,
                    value     = FormatGoldValue(info.totalValue or 0),
                    detail    = ns.COLORS.ORANGE .. countdown .. "|r",
                    _sortValue = 0,  -- sort after "Log in" entries (positive gold), before "Create char" (-1)
                    _tooltipText = charKey,
                    _tooltipExtra = string.format("%d active auction(s)\nSoonest expires in %s",
                        info.active, countdown),
                })
            end
        end
    end

    -- Dependency-aware sort: depositors before their receivers, then by gold value
    table.sort(data, function(a, b)
        local aKey = a._charKey
        local bKey = b._charKey

        -- If B depends on A (A deposits for B), A comes first
        if aKey and bKey and receiverOf[bKey] and receiverOf[bKey][aKey] then
            return true
        end
        if aKey and bKey and receiverOf[aKey] and receiverOf[aKey][bKey] then
            return false
        end

        return (a._sortValue or 0) > (b._sortValue or 0)
    end)

    return data
end

-- Expose for MiniView
UI.BuildNextStepsData = BuildNextStepsData
UI.BuildCurrentCharTasks = BuildCurrentCharTasks

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
                local ok3, _, _, _, _, iconTexture = pcall(C_Item.GetItemInfoInstant, nameID)
                if ok3 and iconTexture then icon = iconTexture end
            end
            if not quality then
                local ok4, _, _, itemQuality = pcall(C_Item.GetItemInfo, nameID)
                if ok4 and itemQuality then quality = itemQuality end
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
    local tsmEnabled = ns.TSM:IsEnabled()
    local myCharKey = tsmEnabled and ns:GetCharKey() or nil
    local myRealm = myCharKey and (myCharKey:match("%-(.+)$") or "") or ""

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

        local row = {
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
        }

        -- TSM price data (only meaningful for current realm)
        if tsmEnabled then
            local isMyRealm = ns:RealmMatches(item.targetRealm or "", myRealm)

            if isMyRealm then
                local priceSource = ns.db.settings.tsmPriceSource or "DBMinBuyout"
                local copper = ns.TSM:GetPrice(item.itemKey, priceSource)
                if copper then
                    row.ahPrice = ns.TSM:FormatCopper(copper)
                    row._sortAhPrice = copper

                    local belowThreshold = ns.TSM:IsBelowThreshold(item.itemKey)
                    if belowThreshold then
                        row.ahPrice = "|cffff4444" .. row.ahPrice .. "|r"
                        row._rowColor = {0.8, 0.2, 0.2, 0.10}
                    else
                        row.ahPrice = "|cff00ff00" .. row.ahPrice .. "|r"
                    end
                else
                    row.ahPrice = "|cff888888" .. "\226\128\148" .. "|r"
                    row._sortAhPrice = 0
                end
            else
                row.ahPrice = "|cff666666" .. "\226\128\148" .. "|r"
                row._sortAhPrice = -1
            end
        end

        table.insert(data, row)
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

        -- Status display
        local aStatus = entry.auctionStatus or "active"
        local statusStr
        if aStatus == "sold" then
            statusStr = ns.COLORS.GREEN .. "Sold" .. "|r"
        elseif aStatus == "expired" then
            statusStr = ns.COLORS.RED .. "Expired" .. "|r"
        elseif aStatus == "collected" then
            statusStr = ns.COLORS.GRAY .. "Done" .. "|r"
        else
            statusStr = ns.COLORS.YELLOW .. "Active" .. "|r"
        end

        -- Price display: show sold price if sold, posted price otherwise
        local priceStr
        if aStatus == "sold" and entry.soldPrice and entry.soldPrice > 0 then
            priceStr = ns.COLORS.GREEN .. ns:FormatGold(entry.soldPrice) .. "|r"
        else
            priceStr = entry.postedPrice or "?"
        end

        -- Recovered entry indicator
        if entry.isRecovered then
            statusStr = statusStr .. " *"
        end

        -- Tooltip with sale info
        local tooltipExtra = string.format("Posted: %s\nListed for: %s\nFP suggested: %s",
            dateStr, entry.postedPrice or "?", entry.expectedPrice or "?")
        if entry.isRecovered then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.YELLOW .. "Recovered from AH (approx. post time)|r"
        end
        if aStatus == "sold" then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.GREEN .. "Sold for: " ..
                (entry.soldPrice and entry.soldPrice > 0 and ns:FormatGold(entry.soldPrice) or "unknown") .. "|r"
            if entry.soldAt then
                tooltipExtra = tooltipExtra .. "\nSold: " .. date("%m/%d %H:%M", entry.soldAt)
            end
        elseif aStatus == "expired" then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.RED .. "Auction expired|r"
        end

        table.insert(data, {
            name      = displayName,
            qty       = entry.postedQuantity or 1,
            status    = statusStr,
            posted    = priceStr,
            guide     = entry.expectedPrice or "?",
            realm     = entry.targetRealm or "",
            character = entry.charKey or "",
            date      = dateStr,
            _icon     = icon,
            _sortDate = entry.postedAt or 0,
            _tooltipItemID = resolvedID,
            _tooltipText   = entry.name,
            _tooltipExtra  = tooltipExtra,
            _logIndex = i,
        })
    end

    return data
end

-- ==========================================
-- INVENTORY PAGE (Full Tradeable Inventory)
-- ==========================================

local BOUND_TYPES = {
    [1] = true, [4] = true, [7] = true, [8] = true, [9] = true,
}

-- Determine item status: Queued, Posted, DNT, or Untracked
local function GetItemStatus(key, itemData)
    -- Check DNT first
    if ns.Queue:IsDoNotTrack(itemData.itemID) then
        return "DNT", ns.COLORS.RED .. "DNT" .. "|r"
    end

    -- Check queue (pending items)
    local itemName = (itemData.name or ""):lower()
    for _, qItem in ipairs(ns.db.queue) do
        if qItem.status == "pending" then
            if qItem.itemKey == key then
                return "Queued", ns.COLORS.GREEN .. "Queued" .. "|r", qItem.targetRealm
            end
            if itemName ~= "" and qItem.name and qItem.name:lower() == itemName then
                return "Queued", ns.COLORS.GREEN .. "Queued" .. "|r", qItem.targetRealm
            end
        end
    end

    -- Check log (posted items)
    for _, entry in ipairs(ns.db.log) do
        if entry.itemKey == key then
            return "Posted", ns.COLORS.YELLOW .. "Posted" .. "|r"
        end
        if itemName ~= "" and entry.name and entry.name:lower() == itemName then
            return "Posted", ns.COLORS.YELLOW .. "Posted" .. "|r"
        end
    end

    return "Untracked", ns.COLORS.GRAY .. "Untracked" .. "|r"
end

local function BuildFullInventoryData()
    if not ns.db then return {} end

    local data = {}

    -- Process each character's inventory
    for charKey, charData in pairs(ns.db.inventory) do
        if charData.items then
            local charName = charKey:match("^(.-)%-") or charKey
            local classColor = CLASS_COLORS[charData.class] or "888888"
            local coloredOwner = "|cff" .. classColor .. charName .. "|r"

            for key, itemData in pairs(charData.items) do
                -- Filter out bound/untradeable
                if not BOUND_TYPES[itemData.bindType or 0] and not itemData.isBound then
                    local _, invQuality, invResolvedID = LookupItemInfo(itemData.itemID, key, itemData.name)
                    local invDisplayName = itemData.name or "Unknown"
                    if invQuality then
                        invDisplayName = QualityColorName(invDisplayName, invQuality)
                    end

                    local statusKey, statusStr, targetRealm = GetItemStatus(key, itemData)

                    -- Build location string
                    local locParts = {}
                    if itemData.locations then
                        for loc, qty in pairs(itemData.locations) do
                            table.insert(locParts, loc)
                        end
                    end

                    table.insert(data, {
                        name        = invDisplayName,
                        qty         = itemData.quantity,
                        owner       = coloredOwner,
                        location    = table.concat(locParts, ", "),
                        status      = statusStr,
                        targetRealm = targetRealm or "",
                        _icon       = itemData.icon,
                        _tooltipItemID = invResolvedID,
                        _itemKey    = key,
                        _itemID     = itemData.itemID,
                        _itemName   = itemData.name,
                        _quantity   = itemData.quantity,
                        _statusKey  = statusKey,
                        _sortStatus = statusKey == "Queued" and 1 or statusKey == "Posted" and 2
                            or statusKey == "Untracked" and 3 or 4,
                        _charKey    = charKey,
                    })
                end
            end
        end
    end

    -- Warbank items
    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            if not BOUND_TYPES[itemData.bindType or 0] and not itemData.isBound then
                local _, wbQuality, wbResolvedID = LookupItemInfo(itemData.itemID, key, itemData.name)
                local wbDisplayName = itemData.name or "Unknown"
                if wbQuality then
                    wbDisplayName = QualityColorName(wbDisplayName, wbQuality)
                end

                local statusKey, statusStr, targetRealm = GetItemStatus(key, itemData)

                table.insert(data, {
                    name        = wbDisplayName,
                    qty         = itemData.quantity,
                    owner       = ns.COLORS.YELLOW .. "Warbank" .. "|r",
                    location    = "warbank",
                    status      = statusStr,
                    targetRealm = targetRealm or "",
                    _icon       = itemData.icon,
                    _tooltipItemID = wbResolvedID,
                    _itemKey    = key,
                    _itemID     = itemData.itemID,
                    _itemName   = itemData.name,
                    _quantity   = itemData.quantity,
                    _statusKey  = statusKey,
                    _sortStatus = statusKey == "Queued" and 1 or statusKey == "Posted" and 2
                        or statusKey == "Untracked" and 3 or 4,
                    _charKey    = "Warbank",
                })
            end
        end
    end

    -- Guild bank items
    if ns.db.guildbank then
        for guildName, gbData in pairs(ns.db.guildbank) do
            if gbData.items then
                for key, itemData in pairs(gbData.items) do
                    local _, gbQuality, gbResolvedID = LookupItemInfo(itemData.itemID, key, itemData.name)
                    local gbDisplayName = itemData.name or "Unknown"
                    if gbQuality then
                        gbDisplayName = QualityColorName(gbDisplayName, gbQuality)
                    end

                    local statusKey, statusStr, targetRealm = GetItemStatus(key, itemData)

                    table.insert(data, {
                        name        = gbDisplayName,
                        qty         = itemData.quantity,
                        owner       = ns.COLORS.ORANGE .. guildName .. "|r",
                        location    = "guild bank",
                        status      = statusStr,
                        targetRealm = targetRealm or "",
                        _icon       = itemData.icon,
                        _tooltipItemID = gbResolvedID,
                        _itemKey    = key,
                        _itemID     = itemData.itemID,
                        _itemName   = itemData.name,
                        _quantity   = itemData.quantity,
                        _statusKey  = statusKey,
                        _sortStatus = statusKey == "Queued" and 1 or statusKey == "Posted" and 2
                            or statusKey == "Untracked" and 3 or 4,
                        _charKey    = "Guild:" .. guildName,
                    })
                end
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

    -- Get auction summary (active + done) grouped by character
    local auctionsByChar = ns.Tracker and ns.Tracker.GetAuctionSummaryByCharacter
        and ns.Tracker:GetAuctionSummaryByCharacter() or {}

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

        -- Auction summary: active + done
        local auctionInfo = auctionsByChar[charKey]
        local auctionStr = ""
        if auctionInfo then
            local parts = {}
            if auctionInfo.active > 0 then
                if auctionInfo.soonest and auctionInfo.soonest < 7200 then
                    table.insert(parts, ns.COLORS.RED .. auctionInfo.active .. " live|r")
                else
                    table.insert(parts, ns.COLORS.ORANGE .. auctionInfo.active .. " live|r")
                end
            end
            if auctionInfo.done > 0 then
                table.insert(parts, ns.COLORS.GREEN .. auctionInfo.done .. " done|r")
            end
            auctionStr = table.concat(parts, " / ")
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
        elseif auctionInfo and auctionInfo.done > 0 then
            rowColor = {0.3, 1.0, 0.3, 0.1} -- green tint for done auctions
        elseif auctionInfo and auctionInfo.soonest and auctionInfo.soonest < 7200 then
            rowColor = {1.0, 0.3, 0.3, 0.1} -- red tint for urgent auctions
        elseif duplicateRealms[realm] then
            rowColor = {0.8, 0.5, 0.1, 0.1}
        end

        local itemCount = 0
        if inv.items then
            for _ in pairs(inv.items) do itemCount = itemCount + 1 end
        end

        -- Manual character order position
        local charOrder = ns.db.settings.characterOrder or {}
        local orderPos = 999
        for oi, oKey in ipairs(charOrder) do
            if oKey == charKey then orderPos = oi; break end
        end

        local toggleIcon = isHidden and "|cff666666X|r" or "|cff00ff00O|r"
        table.insert(charData, {
            toggle    = toggleIcon,
            name      = coloredName,
            realm     = realm,
            gold      = goldStr,
            tasks     = isHidden and "-" or tostring(#tasks),
            auctions  = auctionStr ~= "" and auctionStr or "",
            lastLogin = lastLoginStr,
            status    = statusStr,
            _sortName = name:lower(),
            _sortGold = goldCopper,
            _sortLastLogin = lastLoginTime,
            _sortAuctions = auctionInfo and (auctionInfo.done * 1000 + auctionInfo.active) or 0,
            _charKey = charKey,
            _isHidden = isHidden,
            _rowColor = rowColor,
            _orderPos = orderPos,
            _tooltipText = charKey,
            _tooltipExtra = string.format(
                "Gold: %s\n%d queue tasks%s\nLast login: %s\nStatus: %s%s\n\nClick to %s\nShift+Right-click: move up\nCtrl+Right-click: move down",
                goldStr, #tasks,
                auctionInfo and ("\n" .. auctionInfo.active .. " active, " .. auctionInfo.done .. " done auction(s)") or "",
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

    -- "Realms needing characters" from the to-do list unassigned groups
    local needData = {}
    local charTodoList = ns.TodoList and ns.TodoList:GetCurrentList()
    if charTodoList and charTodoList.items then
        local displayGroups = ns.TodoList:BuildDisplayGroups(charTodoList.items, "profit")
        for _, group in ipairs(displayGroups) do
            if not group.charKey then
                table.insert(needData, {
                    realm      = group.realm ~= "" and group.realm or "unknown",
                    itemCount  = #group.items,
                    totalValue = FormatGoldValue(group.totalGold),
                    note       = "Create character (flex slot)",
                })
            end
        end
    end

    return charData, needData
end

-- ==========================================
-- REFRESH ORCHESTRATION
-- ==========================================

function UI:Refresh()
    if not mainFrame:IsShown() then return end
    if not ns.db then return end

    -- Ensure TSM columns match current settings
    self:UpdateTSMColumns()

    UpdateNavHighlights()
    HideAllTables()

    -- Update summary
    local pending = ns.Queue:GetPendingCount()
    local todoPending = ns.TodoList and ns.TodoList:GetPendingCount() or 0
    local logCount = #ns.db.log

    -- Tally active auctions across all characters
    local totalActiveAuctions = 0
    local totalActiveGold = 0
    local auctionsByChar = ns.Tracker and ns.Tracker.GetAuctionSummaryByCharacter
        and ns.Tracker:GetAuctionSummaryByCharacter() or {}
    for _, info in pairs(auctionsByChar) do
        totalActiveAuctions = totalActiveAuctions + info.active
        totalActiveGold = totalActiveGold + (info.totalValue or 0)
    end

    local summaryParts = {}
    if todoPending > 0 then
        table.insert(summaryParts, ns.COLORS.GREEN .. "To-Do: " .. todoPending .. "|r")
    end
    if totalActiveAuctions > 0 then
        local goldStr = totalActiveGold >= 1000 and string.format("%.1fk", totalActiveGold / 1000) or (math.floor(totalActiveGold) .. "g")
        table.insert(summaryParts, ns.COLORS.ORANGE .. totalActiveAuctions .. " auctions ~" .. goldStr .. "|r")
    end
    table.insert(summaryParts, ns.COLORS.YELLOW .. "Deals: " .. pending .. "|r")
    table.insert(summaryParts, ns.COLORS.GRAY .. "Log: " .. logCount .. "|r")
    mainFrame.summary:SetText(table.concat(summaryParts, "  "))

    -- Update nav badges
    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""

    -- To-Do badge: TodoList tasks for this character, or fall back to queue
    local postCount = 0
    if ns.TodoList and ns.TodoList:GetCurrentList() then
        local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(todoTasks) do
            if ns:RealmMatches(task.item.targetRealm or "", myRealm) then
                postCount = postCount + 1
            end
        end
    else
        local allTasks = ns.Queue:GetCharacterTasks(charKey)
        for _, task in ipairs(allTasks) do
            if ns:RealmMatches(task.queueItem.targetRealm, myRealm) then
                postCount = postCount + 1
            end
        end
    end
    if navButtons.todo then
        if postCount > 0 then
            navButtons.todo.badge:SetText(ns.COLORS.GREEN .. postCount .. "|r")
        elseif todoPending > 0 then
            -- Show total in gray to indicate tasks exist on other characters
            navButtons.todo.badge:SetText(ns.COLORS.GRAY .. todoPending .. "|r")
        else
            navButtons.todo.badge:SetText("")
        end
    end
    if navButtons.generator then
        navButtons.generator.badge:SetText(pending > 0 and (ns.COLORS.YELLOW .. pending .. "|r") or "")
    end
    if navButtons.log then
        navButtons.log.badge:SetText(logCount > 0 and (ns.COLORS.GRAY .. logCount .. "|r") or "")
    end

    -- Render active page
    if self.currentPage == "todo" then
        mainFrame.pageTitle:SetText(ns.COLORS.GREEN .. "To-Do" .. "|r" ..
            ns.COLORS.GRAY .. " - " .. charKey .. "|r")
        LayoutActionBtns(mainFrame.actionBtns.clearTodoList, mainFrame.actionBtns.rescan, mainFrame.actionBtns.pullBank)

        -- Try TodoList first, fall back to queue-based data
        local todoData = BuildTodoData()
        local data = todoData or BuildPostNowData()

        -- If we have a to-do list but no items for this character, show a helpful message
        local currentTodoList = ns.TodoList and ns.TodoList:GetCurrentList()
        local totalTodoTasks = currentTodoList and ns.TodoList:GetPendingCount() or 0
        local thisCharTasks = #data
        local nextData = BuildNextStepsData()
        local myTasks = BuildCurrentCharTasks()

        -- Current character tasks frame (Check AH, Check Mail, Expiring)
        if not self._charTasksFrame then
            local ctf = CreateFrame("Frame", nil, tableContainer)
            ctf:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
            ctf:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
            ctf:SetHeight(1)
            ctf.rows = {}
            self._charTasksFrame = ctf
        end

        -- Hide old task rows
        for _, row in ipairs(self._charTasksFrame.rows) do
            row:Hide()
        end

        local charTaskHeight = 0
        if #myTasks > 0 then
            self._charTasksFrame:Show()
            for i, task in ipairs(myTasks) do
                local row = self._charTasksFrame.rows[i]
                if not row then
                    row = CreateFrame("Frame", nil, self._charTasksFrame)
                    row:SetHeight(22)
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(16, 16)
                    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
                    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                    row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                    row.text:SetJustifyH("LEFT")
                    self._charTasksFrame.rows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self._charTasksFrame, "TOPLEFT", 0, -(i - 1) * 22)
                row:SetPoint("RIGHT", self._charTasksFrame, "RIGHT", 0, 0)
                row.bg:SetColorTexture(0.12, 0.15, 0.12, 0.6)
                row.icon:SetTexture(task.icon)
                row.text:SetText(task.text)
                row:Show()
            end
            charTaskHeight = #myTasks * 22 + 4
            self._charTasksFrame:SetHeight(charTaskHeight)
        else
            self._charTasksFrame:Hide()
            charTaskHeight = 0
        end

        -- Offset everything below by charTaskHeight
        local contentOffset = -charTaskHeight

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
            -- Nothing to post on this character
            self._postSummaryFrame:Hide()

            if totalTodoTasks == 0 and #nextData == 0 and #myTasks == 0 and ns.Queue:GetPendingCount() == 0 then
                -- Everything is done! Show fun message
                if not self._postSummaryFrame then self:Refresh() return end
                self._postSummaryFrame:Show()
                self._postSummaryFrame:ClearAllPoints()
                self._postSummaryFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, contentOffset)
                self._postSummaryFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", 0, 0)
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

            elseif totalTodoTasks > 0 and currentTodoList then
                -- Show the FULL to-do list grouped by character so user can see everything
                -- Create/reuse the todo overview scroll frame
                if not self._todoOverviewScroll then
                    local s = CreateFrame("ScrollFrame", nil, tableContainer, "UIPanelScrollFrameTemplate")
                    local c = CreateFrame("Frame", nil, s)
                    c:SetWidth(1)
                    c:SetHeight(1)
                    s:SetScrollChild(c)
                    s:SetScript("OnSizeChanged", function(sf, w) c:SetWidth(w) end)
                    self._todoOverviewScroll = s
                    self._todoOverviewContent = c
                    self._todoOverviewRows = {}
                end

                local todoScroll = self._todoOverviewScroll
                local todoContent = self._todoOverviewContent
                local todoRows = self._todoOverviewRows

                todoScroll:ClearAllPoints()
                todoScroll:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, contentOffset)
                todoScroll:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)
                todoScroll:Show()
                todoContent:SetWidth(todoScroll:GetWidth() or 500)

                -- Hide old rows
                for _, row in ipairs(todoRows) do row:Hide() end

                -- Build grouped display
                local displayGroups, missingCount = ns.TodoList:BuildDisplayGroups(
                    currentTodoList.items, UI:GetGenSortMode())

                local HDR_H = 22
                local ITEM_H = 18
                local y = 0
                local rowIdx = 0

                local function GetRow(height)
                    rowIdx = rowIdx + 1
                    local row = todoRows[rowIdx]
                    if not row then
                        row = CreateFrame("Frame", nil, todoContent)
                        row.bg = row:CreateTexture(nil, "BACKGROUND")
                        row.bg:SetAllPoints()
                        row.icon = row:CreateTexture(nil, "ARTWORK")
                        row.icon:SetSize(14, 14)
                        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                        row.icon:Hide()
                        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                        row.text:SetJustifyH("LEFT")
                        row.text:SetWordWrap(false)
                        row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                        row.rightText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                        row.rightText:SetJustifyH("RIGHT")
                        row.rightText:SetWordWrap(false)
                        row.rightText:SetMaxLines(1)
                        row.text:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                        todoRows[rowIdx] = row
                    end
                    row:SetHeight(height)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", todoContent, "TOPLEFT", 0, -y)
                    row:SetPoint("RIGHT", todoContent, "RIGHT", 0, 0)
                    row.icon:Hide()
                    row.text:SetText("")
                    row.rightText:SetText("")
                    row.text:ClearAllPoints()
                    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                    row.text:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                    row:Show()
                    return row
                end

                for gi, group in ipairs(displayGroups) do
                    local isUnassigned = not group.charKey
                    local isCurrentChar = group.charKey == charKey

                    -- Group header
                    local hdr = GetRow(HDR_H)
                    if isUnassigned then
                        hdr.bg:SetColorTexture(0.15, 0.08, 0.08, 0.7)
                        local realmName = group.realm ~= "" and group.realm or "unknown realm"
                        hdr.text:SetText(ns.COLORS.RED .. "Create character on " .. realmName .. "|r" ..
                            ns.COLORS.GRAY .. "  (" .. #group.items .. " items)|r")
                    elseif isCurrentChar then
                        hdr.bg:SetColorTexture(0.1, 0.2, 0.1, 0.8)
                        local cc = CLASS_COLORS[ns.db.inventory[group.charKey] and ns.db.inventory[group.charKey].class] or "888888"
                        hdr.text:SetText("|cff" .. cc .. group.charName .. "|r" ..
                            ns.COLORS.GRAY .. " - " .. group.realm .. "|r" ..
                            ns.COLORS.GREEN .. "  (YOU — " .. #group.items .. " items)|r")
                    else
                        hdr.bg:SetColorTexture(0.12, 0.15, 0.2, 0.8)
                        local charInv = ns.db.inventory and ns.db.inventory[group.charKey]
                        local cc = charInv and CLASS_COLORS[charInv.class] or "888888"
                        hdr.text:SetText("|cff" .. cc .. group.charName .. "|r" ..
                            ns.COLORS.GRAY .. " - " .. group.realm .. "  (" .. #group.items .. " items)|r")
                    end

                    local goldStr = FormatGoldValue(group.totalGold)
                    local goldColor = isUnassigned and ns.COLORS.GRAY or ns.COLORS.YELLOW
                    hdr.rightText:SetText(goldColor .. "~" .. goldStr .. "|r")
                    y = y + HDR_H

                    -- Item rows
                    for ii, item in ipairs(group.items) do
                        local row = GetRow(ITEM_H)
                        if isUnassigned then
                            row.bg:SetColorTexture(0.1, 0.06, 0.06, 0.4)
                        else
                            row.bg:SetColorTexture(ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.12 or 0.1, 0.5)
                        end

                        local lookupIcon, quality
                        pcall(function()
                            lookupIcon, quality = LookupItemInfo(item.itemID, item.itemKey, item.name)
                        end)
                        local itemIcon = item.icon or lookupIcon
                        if itemIcon then
                            row.icon:SetTexture(itemIcon)
                            row.icon:ClearAllPoints()
                            row.icon:SetPoint("LEFT", row, "LEFT", 14, 0)
                            row.icon:SetDesaturated(isUnassigned)
                            row.icon:SetAlpha(isUnassigned and 0.5 or 1)
                            row.icon:Show()
                            row.text:ClearAllPoints()
                            row.text:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
                            row.text:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                        else
                            row.text:ClearAllPoints()
                            row.text:SetPoint("LEFT", row, "LEFT", 16, 0)
                            row.text:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                        end

                        local displayName = item.name or "?"
                        if isUnassigned then
                            displayName = ns.COLORS.GRAY .. displayName .. "|r"
                        elseif quality then
                            displayName = QualityColorName(displayName, quality)
                        elseif item.quality and item.quality ~= "" then
                            displayName = QualityColorName(displayName, item.quality)
                        end
                        local qtyStr = (item.quantity or 1) > 1 and (" x" .. (item.quantity or 1)) or ""
                        row.text:SetText(displayName .. qtyStr)

                        -- Right side: price + source status
                        local priceStr = item.expectedPrice or ""
                        local sourceTag = ""
                        if isUnassigned then
                            priceStr = ns.COLORS.GRAY .. priceStr .. "|r"
                        elseif isCurrentChar then
                            -- Live check: is this item currently in bags?
                            local inBags = false
                            pcall(function()
                                for _, bagIdx in ipairs(ns.INVENTORY_BAGS) do
                                    local numSlots = C_Container.GetContainerNumSlots(bagIdx)
                                    for slot = 1, numSlots do
                                        local info = C_Container.GetContainerItemInfo(bagIdx, slot)
                                        if info and info.hyperlink then
                                            local slotID = tonumber((ns:ParseItemLink(info.hyperlink)))
                                            local itemNumID = tonumber(item.itemID) or tonumber(item.itemKey and item.itemKey:match("^(%d+)"))
                                            if slotID and itemNumID and slotID == itemNumID then
                                                inBags = true
                                                return
                                            end
                                        end
                                    end
                                end
                            end)
                            if inBags then
                                sourceTag = ns.COLORS.GREEN .. " [in bags]" .. "|r"
                            elseif item.source == "warbank" then
                                sourceTag = ns.COLORS.YELLOW .. " [warbank]" .. "|r"
                            elseif item.source == "bank" then
                                sourceTag = ns.COLORS.BLUE .. " [bank]" .. "|r"
                            else
                                sourceTag = ns.COLORS.RED .. " [not found]" .. "|r"
                            end
                        else
                            -- Other characters: show source from generation
                            if item.source == "bags" then
                                sourceTag = ns.COLORS.GREEN .. " [bags]" .. "|r"
                            elseif item.source == "warbank" then
                                sourceTag = ns.COLORS.YELLOW .. " [wb]" .. "|r"
                            elseif item.source == "bank" then
                                sourceTag = ns.COLORS.BLUE .. " [bank]" .. "|r"
                            elseif item.source == "guildbank" then
                                sourceTag = ns.COLORS.ORANGE .. " [guild]" .. "|r"
                            elseif item.source == "unavailable" and item.depositFrom then
                                local depName = item.depositFrom:match("^(.-)%-") or item.depositFrom
                                sourceTag = ns.COLORS.CYAN .. " [via " .. depName .. "]" .. "|r"
                            elseif item.source == "unavailable" then
                                sourceTag = ns.COLORS.RED .. " [unavail]" .. "|r"
                            end
                        end
                        row.rightText:SetText(priceStr .. sourceTag)

                        y = y + ITEM_H
                    end
                    y = y + 2 -- gap between groups
                end

                todoContent:SetHeight(math.max(1, y))

                -- Status bar
                local assignedCount = 0
                for _, g in ipairs(displayGroups) do
                    if g.charKey then assignedCount = assignedCount + #g.items end
                end
                mainFrame.statusText:SetText(
                    "Nothing to post on " .. charKey:match("^(.-)%-") ..
                    "  |  " .. assignedCount .. " tasks across " .. #displayGroups .. " groups" ..
                    (missingCount > 0 and ("  |  " .. missingCount .. " not in inventory") or ""))
            else
                -- No to-do list, but there are next steps or queue items
                self._postSummaryFrame:Show()
                local bannerHeight = 50
                self._postSummaryFrame:ClearAllPoints()
                self._postSummaryFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, contentOffset)
                self._postSummaryFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, contentOffset)
                self._postSummaryFrame:SetHeight(bannerHeight)
                self._postSummaryFrame.title:ClearAllPoints()
                self._postSummaryFrame.title:SetPoint("TOP", self._postSummaryFrame, "TOP", 0, -10)
                self._postSummaryFrame.title:SetText(ns.COLORS.GREEN .. "No to-do list generated yet|r")
                self._postSummaryFrame.sub:SetText(
                    ns.COLORS.GRAY .. "Go to the To-Do Generator to build your task list.|r")

                local belowBanner = contentOffset - bannerHeight
                if #nextData > 0 then
                    if not self._nextStepsLabel then
                        self._nextStepsLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    end
                    self._nextStepsLabel:ClearAllPoints()
                    self._nextStepsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, belowBanner + 2)
                    self._nextStepsLabel:SetTextColor(0.6, 0.8, 1.0)
                    self._nextStepsLabel:SetText("Next Steps (" .. #nextData .. ")")
                    self._nextStepsLabel:Show()

                    self.nextStepsTable.headerFrame:ClearAllPoints()
                    self.nextStepsTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, belowBanner - 10)
                    self.nextStepsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, belowBanner - 10)
                    self.nextStepsTable.scrollFrame:ClearAllPoints()
                    self.nextStepsTable.scrollFrame:SetPoint("TOPLEFT", self.nextStepsTable.headerFrame, "BOTTOMLEFT", 0, 0)
                    self.nextStepsTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)
                    ShowTable(self.nextStepsTable)
                    self.nextStepsTable:SetData(nextData)
                end

                mainFrame.statusText:SetText("No to-do list  |  Use the Generator to create one")
            end
        else
            -- Has items to post — show char tasks at top, then post table, then next steps
            self._postSummaryFrame:Hide()

            -- Offset the post now table header below char tasks
            self.postNowTable.headerFrame:ClearAllPoints()
            self.postNowTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, contentOffset)
            self.postNowTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, contentOffset)

            ShowTable(self.postNowTable)

            self.postNowTable:SetRowClickHandler(function(rowData, button)
                if button == "RightButton" then
                    if rowData._taskIndex and ns.TodoList then
                        -- TodoList item
                        if IsShiftKeyDown() then
                            ns.TodoList:SkipTask(rowData._taskIndex, "manual skip")
                            ns:Print(ns.COLORS.ORANGE .. "Skipped:|r " .. rowData.name)
                        else
                            ns.TodoList:MoveTaskToLog(rowData._taskIndex)
                            ns:Print("Posted: " .. rowData.name .. " -> moved to log")
                        end
                        self:Refresh()
                        if self.RefreshMini then self:RefreshMini() end
                    elseif rowData._queueIndex then
                        -- Queue item (legacy)
                        if IsShiftKeyDown() then
                            ns.Queue:Skip(rowData._queueIndex)
                            ns:Print(ns.COLORS.ORANGE .. "Skipped:|r " .. rowData.name .. " (will reappear in 24h)")
                        else
                            ns.Queue:MarkPosted(rowData._queueIndex)
                            ns:Print("Posted: " .. rowData.name .. " -> moved to log")
                        end
                        self:Refresh()
                        if self.RefreshMini then self:RefreshMini() end
                    end
                end
            end)
            self.postNowTable:SetData(data)

            if #nextData > 0 then
                local postNowHeight = math.max(60, (#data + 1) * 20 + 22) + charTaskHeight
                if postNowHeight > 250 + charTaskHeight then postNowHeight = 250 + charTaskHeight end

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
                self.postNowTable.scrollFrame:SetHeight(postNowHeight - charTaskHeight - 22)
            else
                if self._nextStepsLabel then self._nextStepsLabel:Hide() end
                -- Reset postNow scroll to fill the full container
                self.postNowTable.scrollFrame:ClearAllPoints()
                self.postNowTable.scrollFrame:SetPoint("TOPLEFT", self.postNowTable.headerFrame, "BOTTOMLEFT", 0, 0)
                self.postNowTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)
            end

            mainFrame.statusText:SetText(postCount .. " items to post  |  " .. #nextData .. " next steps  |  Right-click: posted  |  Shift+Right: skip")
        end

    elseif self.currentPage == "generator" then
        self:RefreshGeneratorPage(pending)

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
        local soldCount, activeCount, expiredCount = 0, 0, 0
        for _, entry in ipairs(ns.db.log) do
            if entry.auctionStatus == "sold" then soldCount = soldCount + 1
            elseif entry.auctionStatus == "expired" then expiredCount = expiredCount + 1
            elseif entry.auctionStatus == "active" then activeCount = activeCount + 1
            end
        end
        local logStatus = logCount .. " logged"
        local parts = {}
        if soldCount > 0 then table.insert(parts, ns.COLORS.GREEN .. soldCount .. " sold|r") end
        if activeCount > 0 then table.insert(parts, ns.COLORS.YELLOW .. activeCount .. " active|r") end
        if expiredCount > 0 then table.insert(parts, ns.COLORS.RED .. expiredCount .. " expired|r") end
        if #parts > 0 then logStatus = logStatus .. " (" .. table.concat(parts, ", ") .. ")" end
        logStatus = logStatus .. "  |  Shift+Right-click to remove"
        mainFrame.statusText:SetText(logStatus)

    elseif self.currentPage == "inventory" then
        mainFrame.pageTitle:SetText("Inventory")
        LayoutActionBtns(mainFrame.actionBtns.dnt)
        ShowTable(self.inventoryTable)

        local data = BuildFullInventoryData()
        self.inventoryTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" then
                local statusKey = rowData._statusKey
                if statusKey == "Untracked" then
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
                elseif statusKey == "DNT" then
                    ns.Queue:RemoveDoNotTrack(tostring(rowData._itemID))
                    ns:Print("Removed from Do Not Track: " .. (rowData._itemName or rowData.name))
                elseif statusKey == "Queued" then
                    -- Find and remove from queue
                    if IsShiftKeyDown() then
                        for i, qItem in ipairs(ns.db.queue) do
                            if qItem.itemKey == rowData._itemKey or
                                (qItem.name and rowData._itemName and qItem.name:lower() == rowData._itemName:lower()) then
                                table.remove(ns.db.queue, i)
                                ns:Print(ns.COLORS.RED .. "Removed from queue:|r " .. (rowData._itemName or rowData.name))
                                break
                            end
                        end
                    end
                end
                self:Refresh()
            end
        end)
        self.inventoryTable:SetData(data)

        -- Count by status
        local statusCounts = {Queued = 0, Posted = 0, Untracked = 0, DNT = 0}
        for _, row in ipairs(data) do
            statusCounts[row._statusKey] = (statusCounts[row._statusKey] or 0) + 1
        end
        local statusParts = {#data .. " tradeable items"}
        if statusCounts.Queued > 0 then table.insert(statusParts, ns.COLORS.GREEN .. statusCounts.Queued .. " queued|r") end
        if statusCounts.Posted > 0 then table.insert(statusParts, ns.COLORS.YELLOW .. statusCounts.Posted .. " posted|r") end
        if statusCounts.Untracked > 0 then table.insert(statusParts, ns.COLORS.GRAY .. statusCounts.Untracked .. " untracked|r") end
        if statusCounts.DNT > 0 then table.insert(statusParts, ns.COLORS.RED .. statusCounts.DNT .. " DNT|r") end
        mainFrame.statusText:SetText(table.concat(statusParts, "  |  "))

    elseif self.currentPage == "characters" then
        mainFrame.pageTitle:SetText("Characters & Realms")
        HideAllActionBtns()

        local charData, needData = BuildCharactersData()

        -- Show known characters table
        ShowTable(self.charsTable)
        self.charsTable:SetRowClickHandler(function(rowData, button, rowIndex)
            if button == "LeftButton" and rowData._charKey then
                -- Left-click: toggle hide/show
                if ns.db.hiddenCharacters[rowData._charKey] then
                    ns.db.hiddenCharacters[rowData._charKey] = nil
                    ns:Print("Re-enabled character: " .. rowData._charKey)
                else
                    ns.db.hiddenCharacters[rowData._charKey] = true
                    ns:Print("Hidden character: " .. rowData._charKey .. " (will be skipped for task routing)")
                end
                self:Refresh()
            elseif button == "RightButton" and rowData._charKey then
                if IsShiftKeyDown() then
                    -- Shift+Right-click: move character up in manual order
                    local order = ns.db.settings.characterOrder
                    -- Ensure all chars are in the order list
                    local seen = {}
                    for _, k in ipairs(order) do seen[k] = true end
                    for ck in pairs(ns.db.inventory) do
                        if not seen[ck] then table.insert(order, ck) end
                    end
                    -- Find and move up
                    for idx, ck in ipairs(order) do
                        if ck == rowData._charKey and idx > 1 then
                            order[idx], order[idx - 1] = order[idx - 1], order[idx]
                            ns:Print("Moved up: " .. rowData._charKey)
                            break
                        end
                    end
                    self:Refresh()
                elseif IsControlKeyDown() then
                    -- Ctrl+Right-click: move character down in manual order
                    local order = ns.db.settings.characterOrder
                    local seen = {}
                    for _, k in ipairs(order) do seen[k] = true end
                    for ck in pairs(ns.db.inventory) do
                        if not seen[ck] then table.insert(order, ck) end
                    end
                    for idx, ck in ipairs(order) do
                        if ck == rowData._charKey and idx < #order then
                            order[idx], order[idx + 1] = order[idx + 1], order[idx]
                            ns:Print("Moved down: " .. rowData._charKey)
                            break
                        end
                    end
                    self:Refresh()
                else
                    -- Plain right-click: toggle hide/show
                    if ns.db.hiddenCharacters[rowData._charKey] then
                        ns.db.hiddenCharacters[rowData._charKey] = nil
                        ns:Print("Re-enabled character: " .. rowData._charKey)
                    else
                        ns.db.hiddenCharacters[rowData._charKey] = true
                        ns:Print("Hidden character: " .. rowData._charKey .. " (will be skipped for task routing)")
                    end
                    self:Refresh()
                end
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
            self._needCharsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, -charsHeight - 2)
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
        table.insert(statusParts, ns.COLORS.GRAY .. "Click to hide/show" .. "|r")
        mainFrame.statusText:SetText(table.concat(statusParts, "  |  "))

    elseif self.currentPage == "import" then
        mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Import" .. "|r")
        LayoutActionBtns(mainFrame.actionBtns.importClear, mainFrame.actionBtns.importDo, mainFrame.actionBtns.importPreview)
        importPage:Show()
        -- Restore checkbox states from settings
        importAutoGenCheck:SetChecked(ns.db.settings.importAutoGenerate or false)
        -- Show preview table if we have data
        if UI._importPreviewData() then
            UI.importPreviewTable.headerFrame:Show()
            UI.importPreviewTable.scrollFrame:Show()
        end
        UI._importEdit:SetFocus(true)
        mainFrame.statusText:SetText("Paste FlippingPal website, CSV, or tab-delimited data")

    elseif self.currentPage == "export" then
        mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Export" .. "|r")
        LayoutActionBtns(mainFrame.actionBtns.exportSaved, mainFrame.actionBtns.exportAll,
            mainFrame.actionBtns.exportWarbank, mainFrame.actionBtns.exportBank, mainFrame.actionBtns.exportBags)
        exportPage:Show()
        if UI._updateExportToggles then UI._updateExportToggles() end

        -- Check for pending export from Generator's "Export to FP"
        if UI._pendingExportCSV then
            UI._exportEdit:SetText(UI._pendingExportCSV)
            UI._exportEdit:HighlightText()
            UI._exportEdit:SetFocus(true)
            UI._exportStatus:SetText(ns.COLORS.GREEN .. (UI._pendingExportCount or 0) .. " items|r exported from item pool  |  Ctrl+A then Ctrl+C to copy")
            mainFrame.statusText:SetText("Item pool export  |  Ctrl+A then Ctrl+C to copy")
            UI._pendingExportCSV = nil
            UI._pendingExportCount = nil
        else
            local fmtName = ns.Export:GetFormat() == "aaa" and "AAA JSON" or "FP CSV"
            mainFrame.statusText:SetText(fmtName .. " export  |  Ctrl+A then Ctrl+C to copy")
        end

    elseif self.currentPage == "tsm" then
        mainFrame.pageTitle:SetText("TSM Integration")
        HideAllActionBtns()
        if self.ShowTSMPage then
            self:ShowTSMPage()
        end
        mainFrame.statusText:SetText(ns.TSM:IsAvailable() and "TSM detected" or "TSM not installed")

    elseif self.currentPage == "auctionator" then
        mainFrame.pageTitle:SetText("Auctionator Integration")
        HideAllActionBtns()
        if self.ShowAuctionatorPage then
            self:ShowAuctionatorPage()
        end
        local auctAvailable = type(Auctionator) == "table"
        mainFrame.statusText:SetText(auctAvailable and "Auctionator detected" or "Auctionator not installed")

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

-- Expose internals for GeneratorPage.lua
UI._LayoutActionBtns = LayoutActionBtns
UI._HideAllActionBtns = HideAllActionBtns
UI._ShowTable = ShowTable
UI._LookupItemInfo = LookupItemInfo
UI._QualityColorName = QualityColorName
UI._CLASS_COLORS = CLASS_COLORS
UI._FormatGoldValue = FormatGoldValue

mainFrame:SetScript("OnShow", function()
    -- Restore saved size
    if ns.db and ns.db.settings.frameWidth and ns.db.settings.frameHeight then
        mainFrame:SetSize(ns.db.settings.frameWidth, ns.db.settings.frameHeight)
    end
    -- Restore saved sidebar width
    if ns.db and ns.db.settings.sidebarWidth then
        sidebar:SetWidth(math.max(80, math.min(200, ns.db.settings.sidebarWidth)))
    end
    UI:Refresh()
end)
