-- UI/MainFrame.lua
-- Main window: side nav, content area, scroll tables, refresh orchestration
local addonName, ns = ...

local UI = ns.UI

UI.currentPage = "todo"

-- ==========================================
-- MAIN FRAME (dark, clean styling)
-- ==========================================

local SIDEBAR_WIDTH = 130
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
    mainFrame:SetResizeBounds(720, 450, 1200, 900)
else
    mainFrame:SetMinResize(720, 450)
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
    -- Guild bank page disabled: Blizzard API returns unreliable item data
    -- {key = "guilds",     label = "Guilds",          icon = "Interface\\Icons\\INV_Misc_Tabard_ClutchofTheConclave"},
    {key = "section", label = "TOOLS"},
    {key = "transform", label = "Transform",     icon = "Interface\\Icons\\Trade_Engineering"},
    {key = "section", label = "INTEGRATIONS"},
    {key = "tsm",        label = "TSM",            icon = "Interface\\Icons\\INV_Misc_Coin_17"},
    {key = "auctionator", label = "Auctionator",   icon = "Interface\\Icons\\INV_Misc_Note_01"},
    {key = "sep"},
    {key = "log",        label = "Log",            icon = "Interface\\Icons\\INV_Misc_Book_09"},
    {key = "debug",      label = "Task Debug",     icon = "Interface\\Icons\\INV_Misc_Wrench_01"},
    {key = "settings",   label = "Settings",       icon = "Interface\\Icons\\INV_Gizmo_02"},
}

local navButtons = {}
UI._navButtons = navButtons  -- expose for tutorial highlighting
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
            ns:ClearLog()
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
            ns:ImportClear("fpScanner")
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
            "fpScanner", UI:GetGenAllocationOrder())
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

mainFrame.actionBtns.commitSave = CreateActionBtn("Save", "Save generated to-do list (queues behind current)", function()
    if UI._generatorPreview and ns.TodoList then
        local count = UI._generatorPreview.items and #UI._generatorPreview.items or 0
        -- If there's an active list, queue the new one behind it; otherwise set as active
        local currentList = ns.TodoList:GetCurrentList()
        if currentList then
            ns.TodoList:CommitList(UI._generatorPreview, "upcoming")
            ns:Print(ns.COLORS.GREEN .. "Queued new to-do list with " .. count .. " tasks (behind current list).|r")
        else
            ns.TodoList:CommitList(UI._generatorPreview, "replace")
            ns:Print(ns.COLORS.GREEN .. "Saved to-do list with " .. count .. " tasks.|r")
        end
        UI._generatorPreview = nil
        UI:Refresh()
        if UI.RefreshMini then UI:RefreshMini() end
    end
end)

mainFrame.actionBtns.exportPoolToFP = CreateActionBtn("Export to FP", "Export filtered item pool as FP CSV (popup)", function()
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
        -- Show popup with export result
        UI:ShowExportPopup(csv, #pool .. " items exported — Ctrl+A then Ctrl+C to copy")
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
                    wipe(ns.db.todoLists.upcoming)
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

mainFrame.actionBtns.auctBuyList = CreateActionBtn("Buy List", "Create Auctionator shopping lists from buy tasks", function()
    local count, result = UI.CreateBuyTaskShoppingList()
    if count then
        ns:Print(ns.COLORS.GREEN .. "Created " .. result .. " with " .. count .. " items.|r")
    else
        ns:Print(ns.COLORS.RED .. (result or "Error creating list") .. "|r")
    end
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
            UI._importSetPreview(previewItems, ns.Import:PreviewAdd(previewItems))
            UI:RefreshImportPreview()
        else
            UI._importStatus:SetText(ns.COLORS.RED .. "No items found in pasted data.|r")
        end
    end
end)

mainFrame.actionBtns.importDo = CreateActionBtn("Import", "Import previewed items to queue", function()
    local previewData = UI._importPreviewData()
    if previewData and #previewData > 0 then
        local added = ns.Import:Save(previewData)
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
                local added = ns.Import:Save(items)
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
mainFrame.statusText:SetPoint("RIGHT", statusBar, "RIGHT", -6, 0)
mainFrame.statusText:SetJustifyH("LEFT")
mainFrame.statusText:SetWordWrap(false)

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

-- Track current TSM column state to avoid unnecessary rebuilds
local tsmColumnsActive = false

function UI:UpdateTSMColumns()
    local shouldShow = ns.db and ns.db.settings.tsmEnabled and ns.db.settings.tsmShowColumns and ns.TSM:IsAvailable()
    if shouldShow == tsmColumnsActive then return end
    tsmColumnsActive = shouldShow

    if shouldShow then
        self.postNowTable:SetColumns(POST_NOW_COLS_TSM)
        self.postNowTable:SetSort("name", true)
    else
        self.postNowTable:SetColumns(POST_NOW_COLS_BASE)
        self.postNowTable:SetSort("name", true)
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
    {key = "name",      label = "Character",   width = 105, sortable = true},
    {key = "realm",     label = "Realm",        width = 100, sortable = true},
    {key = "gold",      label = "Gold",         width = 70,  align = "RIGHT", sortable = true},
    {key = "tasks",     label = "Tasks",        width = 36,  align = "CENTER", sortable = true},
    {key = "auctions",  label = "Auctions",     width = 90, align = "CENTER", sortable = true},
    {key = "pull",      label = "Pull",         width = 30,  align = "CENTER", sortable = false},
    {key = "dep",       label = "Dep",          width = 30,  align = "CENTER", sortable = false},
    {key = "depAll",    label = "All",           width = 30,  align = "CENTER", sortable = false},
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

-- Guilds table
UI.guildsTable = UI:CreateScrollTable(tableContainer, {
    {key = "toggle",   label = "",           width = 28,  align = "CENTER", sortable = false},
    {key = "name",     label = "Guild",      width = 160, sortable = true},
    {key = "members",  label = "Members",    width = 140, sortable = false},
    {key = "items",    label = "Items",      width = 50,  align = "CENTER", sortable = true},
    {key = "lastScan", label = "Last Scan",  width = 100, sortable = true},
    {key = "status",   label = "Status",     width = 80,  sortable = true},
})
UI.guildsTable:SetSort("name", true)

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
-- HIDE/SHOW HELPERS
-- ==========================================

local allTables = {}
local function RegisterTable(tbl)
    table.insert(allTables, tbl)
end
RegisterTable(UI.postNowTable)
RegisterTable(UI.logTable)
RegisterTable(UI.inventoryTable)
RegisterTable(UI.charsTable)
RegisterTable(UI.needCharsTable)
RegisterTable(UI.guildsTable)
RegisterTable(UI.nextStepsTable)
RegisterTable(UI.generatorPreviewTable)

local function HideAllTables()
    for _, tbl in ipairs(allTables) do
        tbl.headerFrame:Hide()
        tbl.scrollFrame:Hide()
    end
    UI:HideSettingsPage()
    if UI.HideTSMPage then UI:HideTSMPage() end
    if UI.HideAuctionatorPage then UI:HideAuctionatorPage() end
    if UI._importPage then UI._importPage:Hide() end
    if UI._exportPage then UI._exportPage:Hide() end
    if UI._transformPage then UI._transformPage:Hide() end
    if UI._genInfoFrame then UI._genInfoFrame:Hide() end
    if UI._genFrame then UI._genFrame:Hide() end
    if UI._todoOverviewScroll then UI._todoOverviewScroll:Hide() end
    if UI._charTasksFrame then UI._charTasksFrame:Hide() end
    if UI._nextStepsLabel then UI._nextStepsLabel:Hide() end
    if UI._needCharsLabel then UI._needCharsLabel:Hide() end
    if UI._postSummaryFrame then UI._postSummaryFrame:Hide() end
    if UI._tsmDetectedFrame then UI._tsmDetectedFrame:Hide() end
    if UI._tsmDetectedLabel then UI._tsmDetectedLabel:Hide() end
    if UI._tsmDetectedScroll then UI._tsmDetectedScroll:Hide() end
    if UI._listSelectorBar then UI._listSelectorBar:Hide() end
    if UI._charConfigPanel then UI._charConfigPanel:Hide() end
    if UI._globalDefaultsBar then UI._globalDefaultsBar:Hide() end
    if UI._debugPage then UI._debugPage:Hide() end
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
    local pending = ns:ImportGetCount("fpScanner")
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
    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() then
        if ns.Sync:IsConnected() then
            table.insert(summaryParts, "|cff00ff00Sync: Online|r")
        else
            local qc = ns.Sync:GetPendingCount()
            table.insert(summaryParts, "|cffff0000Sync: Offline" .. (qc > 0 and (" (" .. qc .. " queued)") or "") .. "|r")
        end
    end
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
        local allTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(allTasks) do
            if ns:RealmMatches(task.item.targetRealm, myRealm) then
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

    -- Tutorial: auto-activate on first open with no data
    if not ns.db.settings.tutorialDone
        and not UI._tutorialActive
        and ns:ImportGetCount("fpScanner") == 0
        and (not ns.TodoList or not ns.TodoList:GetCurrentList()) then
        UI._tutorialActive = true
        UI._tutorialStep = 1
        UI._tutorialCallout = 1
    end

    -- Hide old standalone tutorial frame if it exists
    if self._tutorialFrame then self._tutorialFrame:Hide() end

    -- Render active page
    if self.currentPage == "todo" then
        self:RefreshTodoPage()

    elseif self.currentPage == "generator" then
        self:RefreshGeneratorPage(pending)

    elseif self.currentPage == "log" then
        self:RefreshLogPage()

    elseif self.currentPage == "inventory" then
        self:RefreshInventoryPage()

    elseif self.currentPage == "characters" then
        self:RefreshCharactersPage()

    elseif self.currentPage == "guilds" then
        self:RefreshGuildsPage()

    elseif self.currentPage == "import" then
        self:RefreshImportPage()

    elseif self.currentPage == "export" then
        self:RefreshExportPage()

    elseif self.currentPage == "transform" then
        self:RefreshTransformPage()

    elseif self.currentPage == "debug" then
        self:RefreshDebugPage()

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

    -- Tutorial overlay: show callouts on top of the rendered page
    if UI._tutorialActive and not ns.db.settings.tutorialDone then
        self:ShowTutorialCallouts()
    else
        self:HideTutorialCallouts()
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

-- Expose internals for page files
UI._LayoutActionBtns = LayoutActionBtns
UI._HideAllActionBtns = HideAllActionBtns
UI._ShowTable = ShowTable
UI._RegisterTable = RegisterTable

mainFrame:SetScript("OnShow", function()
    -- Restore saved size (clamp to new minimums)
    if ns.db and ns.db.settings.frameWidth and ns.db.settings.frameHeight then
        local w = math.max(720, ns.db.settings.frameWidth)
        local h = math.max(450, ns.db.settings.frameHeight)
        mainFrame:SetSize(w, h)
        ns.db.settings.frameWidth = w
        ns.db.settings.frameHeight = h
    end
    -- Restore saved sidebar width
    if ns.db and ns.db.settings.sidebarWidth then
        sidebar:SetWidth(math.max(80, math.min(200, ns.db.settings.sidebarWidth)))
    end
    UI:Refresh()
end)
