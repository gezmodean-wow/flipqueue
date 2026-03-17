-- UI/MiniView.lua
-- Compact overlay showing current-character tasks, moveable with action icons
local addonName, ns = ...

local UI = ns.UI
local MINI_ROW_HEIGHT = 18
local MINI_WIDTH = 280

--------------------------
-- Mini Frame
--------------------------

local mini = CreateFrame("Frame", "FlipQueueMiniFrame", UIParent, "BackdropTemplate")
mini:SetSize(MINI_WIDTH, 60)
mini:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200)
mini:SetMovable(true)
mini:EnableMouse(true)
mini:RegisterForDrag("LeftButton")
mini:SetScript("OnDragStart", mini.StartMoving)
mini:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Save position
    if ns.db then
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.settings.miniPos = {point = point, relPoint = relPoint, x = x, y = y}
    end
end)
mini:SetClampedToScreen(true)
mini:SetFrameStrata("MEDIUM")
mini:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = {left = 3, right = 3, top = 3, bottom = 3},
})
mini:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
mini:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

--------------------------
-- Header bar
--------------------------

local header = CreateFrame("Frame", nil, mini)
header:SetHeight(20)
header:SetPoint("TOPLEFT", mini, "TOPLEFT", 4, -4)
header:SetPoint("TOPRIGHT", mini, "TOPRIGHT", -4, -4)

local titleIcon = header:CreateTexture(nil, "ARTWORK")
titleIcon:SetSize(16, 16)
titleIcon:SetPoint("LEFT", header, "LEFT", 2, 0)
titleIcon:SetTexture("Interface\\AddOns\\flipqueue\\Art\\flipqueue-icon")

local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("LEFT", titleIcon, "RIGHT", 3, 0)
titleText:SetText(ns.COLORS.YELLOW .. "FQ" .. ns.COLORS.RESET)

-- Icon buttons (right side of header)
local ICON_SIZE = 16
local ICON_SPACING = 2

local function CreateIconButton(parent, icon, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexture(icon)
    btn.tex:SetDesaturated(false)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)

    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(tooltip, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

-- Close button
local closeBtn = CreateIconButton(header, "Interface\\Buttons\\UI-StopButton", "Hide mini view", function()
    mini:Hide()
    if ns.db then ns.db.settings.showMini = false end
end)
closeBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)

-- Open main window button
local mainBtn = CreateIconButton(header, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "Open FlipQueue", function()
    UI.mainFrame:Show()
    UI:Refresh()
end)
mainBtn:SetPoint("RIGHT", closeBtn, "LEFT", -ICON_SPACING, 0)

-- Rescan button
local scanBtn = CreateIconButton(header, "Interface\\Buttons\\UI-RefreshButton", "Rescan bags", function()
    ns.Scanner:ScanCurrentCharacter()
    UI:RefreshMini()
end)
scanBtn:SetPoint("RIGHT", mainBtn, "LEFT", -ICON_SPACING, 0)

-- Import button
local importBtn = CreateIconButton(header, "Interface\\Buttons\\UI-GuildButton-MOTD-Up", "Import", function()
    UI.currentPage = "import"
    UI.mainFrame:Show()
    UI:Refresh()
end)
importBtn:SetPoint("RIGHT", scanBtn, "LEFT", -ICON_SPACING, 0)

--------------------------
-- Task rows area
--------------------------

local taskArea = CreateFrame("Frame", nil, mini)
taskArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
taskArea:SetPoint("RIGHT", mini, "RIGHT", -4, 0)

local miniRows = {}

local function GetOrCreateMiniRow(index)
    if miniRows[index] then return miniRows[index] end

    local row = CreateFrame("Frame", nil, taskArea)
    row:SetHeight(MINI_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", taskArea, "TOPLEFT", 0, -(index - 1) * MINI_ROW_HEIGHT)
    row:SetPoint("RIGHT", taskArea, "RIGHT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(MINI_ROW_HEIGHT - 2, MINI_ROW_HEIGHT - 2)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.tooltipItemID = nil
    row.tooltipItemName = nil

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.tooltipItemID or self.tooltipItemName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local numID = tonumber(self.tooltipItemID)
            if numID and numID > 0 then
                GameTooltip:SetItemByID(numID)
            elseif self.tooltipItemName and self.tooltipItemName ~= "" then
                GameTooltip:SetText(self.tooltipItemName, 1, 1, 1)
                if self.tooltipExtra then
                    GameTooltip:AddLine(self.tooltipExtra, 0.7, 0.7, 0.7, true)
                end
                GameTooltip:Show()
            end
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    miniRows[index] = row
    return row
end

--------------------------
-- Refresh
--------------------------

function UI:RefreshMini()
    if not mini:IsShown() then return end
    if not ns.db then return end

    -- Hide all rows
    for _, row in ipairs(miniRows) do
        row:Hide()
        row:SetScript("OnMouseDown", nil)
        row.tooltipItemID = nil
        row.tooltipItemName = nil
        row.tooltipExtra = nil
    end

    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""

    -- Build a set of item IDs in bags for quick lookup
    local bagsItemIDs = {}
    pcall(function()
        for _, bagIdx in ipairs(ns.INVENTORY_BAGS) do
            local numSlots = C_Container.GetContainerNumSlots(bagIdx)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bagIdx, slot)
                if info and info.hyperlink then
                    local slotID = tonumber((ns:ParseItemLink(info.hyperlink)))
                    if slotID then
                        bagsItemIDs[slotID] = (bagsItemIDs[slotID] or 0) + (info.stackCount or 1)
                    end
                end
            end
        end
    end)

    -- Get tasks: prefer TodoList
    local tasks = {}
    local useTodoList = ns.TodoList and ns.TodoList:GetCurrentList()

    if useTodoList then
        local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(todoTasks) do
            if ns:RealmMatches(task.item.targetRealm or "", myRealm) then
                local itemNumID = tonumber(task.item.itemID) or tonumber(task.item.itemKey and task.item.itemKey:match("^(%d+)"))
                local inBags = itemNumID and bagsItemIDs[itemNumID] and bagsItemIDs[itemNumID] > 0
                table.insert(tasks, {
                    name     = task.item.name or "?",
                    itemID   = task.item.itemID,
                    price    = task.item.expectedPrice,
                    realm    = task.item.targetRealm,
                    icon     = task.item.icon,
                    source   = task.item.source,
                    inBags   = inBags,
                    _taskIdx = task.taskIndex,
                    _isTodo  = true,
                })
            end
        end
    end

    local rowIndex = 0

    -- Pre-check for char tasks (Check AH, Expiring, etc.)
    local preCharTasks = UI.BuildCurrentCharTasks and UI.BuildCurrentCharTasks() or {}

    if #tasks == 0 then
        local todoPending = useTodoList and ns.TodoList:GetPendingCount() or 0
        if #preCharTasks > 0 then
            titleText:SetText(ns.COLORS.YELLOW .. "FQ" .. ns.COLORS.RESET ..
                ns.COLORS.YELLOW .. " - " .. #preCharTasks .. " task(s)" .. ns.COLORS.RESET)
        elseif todoPending > 0 then
            titleText:SetText(ns.COLORS.YELLOW .. "FQ" .. ns.COLORS.RESET ..
                ns.COLORS.GRAY .. " - " .. todoPending .. " on other chars" .. ns.COLORS.RESET)

            -- Show grouped summary of the to-do list (top 5 chars + up to 2 create char)
            local currentList = ns.TodoList:GetCurrentList()
            if currentList and currentList.items then
                local MAX_MINI_CHARS = 5
                local sortMode = (UI.GetGenSortMode and UI:GetGenSortMode()) or "profit"
                local displayGroups = ns.TodoList:BuildDisplayGroups(currentList.items, sortMode)

                local assignedGroups = {}
                local unassignedGroups = {}
                for _, group in ipairs(displayGroups) do
                    if group.charKey then
                        table.insert(assignedGroups, group)
                    else
                        table.insert(unassignedGroups, group)
                    end
                end

                local shownCount = 0
                for _, group in ipairs(assignedGroups) do
                    if shownCount >= MAX_MINI_CHARS then break end
                    shownCount = shownCount + 1
                    rowIndex = rowIndex + 1
                    local row = GetOrCreateMiniRow(rowIndex)
                    row.icon:SetTexture(nil)
                    row.tooltipItemID = nil
                    row.tooltipItemName = group.charKey
                    local goldStr = group.totalGold >= 1000 and string.format("%.1fk", group.totalGold / 1000) or (math.floor(group.totalGold) .. "g")
                    row.tooltipExtra = #group.items .. " items, ~" .. goldStr
                    row:SetScript("OnMouseDown", nil)

                    local charInv = ns.db.inventory and ns.db.inventory[group.charKey]
                    local cc = charInv and UI._CLASS_COLORS and UI._CLASS_COLORS[charInv.class] or "888888"
                    local charName = group.charName or "?"
                    local realmShort = group.realm:match("^([^,]+)") or group.realm

                    row.text:SetText(
                        "|cff" .. cc .. charName .. "|r" ..
                        ns.COLORS.GRAY .. " " .. realmShort .. ns.COLORS.RESET ..
                        ns.COLORS.GRAY .. " (" .. #group.items .. ")" .. ns.COLORS.RESET ..
                        ns.COLORS.GREEN .. " ~" .. goldStr .. ns.COLORS.RESET)
                    row:Show()
                end

                if #assignedGroups > MAX_MINI_CHARS then
                    rowIndex = rowIndex + 1
                    local row = GetOrCreateMiniRow(rowIndex)
                    row.icon:SetTexture(nil)
                    row.text:SetText(ns.COLORS.GRAY .. "+" .. (#assignedGroups - MAX_MINI_CHARS) ..
                        " more characters... (open /fq)" .. ns.COLORS.RESET)
                    row.tooltipItemID = nil
                    row.tooltipItemName = nil
                    row.tooltipExtra = nil
                    row:SetScript("OnMouseDown", nil)
                    row:Show()
                end

                if #unassignedGroups > 0 then
                    local MAX_MINI_UNASSIGNED = 2
                    local unassignedShown = 0
                    for _, group in ipairs(unassignedGroups) do
                        if unassignedShown >= MAX_MINI_UNASSIGNED then break end
                        unassignedShown = unassignedShown + 1
                        rowIndex = rowIndex + 1
                        local row = GetOrCreateMiniRow(rowIndex)
                        row.icon:SetTexture(nil)
                        row.tooltipItemID = nil
                        row.tooltipItemName = nil
                        local realmName = group.realm ~= "" and group.realm or "?"
                        row.tooltipExtra = "Create a character on " .. realmName .. " (" .. #group.items .. " items)"
                        row:SetScript("OnMouseDown", nil)
                        row.text:SetText(
                            ns.COLORS.GRAY .. "Create char " .. ns.COLORS.RESET ..
                            ns.COLORS.RED .. realmName .. ns.COLORS.RESET ..
                            ns.COLORS.GRAY .. " (" .. #group.items .. ")" .. ns.COLORS.RESET)
                        row:Show()
                    end
                    if #unassignedGroups > MAX_MINI_UNASSIGNED then
                        rowIndex = rowIndex + 1
                        local row = GetOrCreateMiniRow(rowIndex)
                        row.icon:SetTexture(nil)
                        row.text:SetText(ns.COLORS.GRAY .. "+" .. (#unassignedGroups - MAX_MINI_UNASSIGNED) ..
                            " more realms need chars" .. ns.COLORS.RESET)
                        row.tooltipItemID = nil
                        row.tooltipItemName = nil
                        row.tooltipExtra = nil
                        row:SetScript("OnMouseDown", nil)
                        row:Show()
                    end
                end
            end
        else
            titleText:SetText(ns.COLORS.YELLOW .. "FQ" .. ns.COLORS.RESET ..
                ns.COLORS.GRAY .. " - queue empty" .. ns.COLORS.RESET)
        end
    else
        titleText:SetText(ns.COLORS.YELLOW .. "FQ" .. ns.COLORS.RESET ..
            ns.COLORS.GREEN .. " - " .. #tasks .. " to post" .. ns.COLORS.RESET)

        for _, task in ipairs(tasks) do
            rowIndex = rowIndex + 1
            local row = GetOrCreateMiniRow(rowIndex)

            row.icon:SetTexture(task.icon)
            row.tooltipItemID = task.itemID
            row.tooltipItemName = task.name
            row.tooltipExtra = (task.realm or "") ~= "" and
                ("Sell on: " .. task.realm .. "  @  " .. (task.price or "?")) or nil

            local priceStr = ""
            if task.price and task.price ~= "" then
                priceStr = ns.COLORS.GREEN .. " " .. task.price .. ns.COLORS.RESET
            end

            -- Status icon using WoW's built-in ReadyCheck textures
            local statusIcon
            if task.inBags then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
            elseif task.source == "warbank" or task.source == "bank" then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t "
            else
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t "
            end

            row.text:SetText(statusIcon .. ns.COLORS.WHITE .. task.name .. ns.COLORS.RESET .. priceStr)

            -- Right-click to mark posted, Shift+Right to skip
            local capturedTask = task
            row:SetScript("OnMouseDown", function(self, button)
                if button == "RightButton" then
                    if capturedTask._isTodo and ns.TodoList then
                        if IsShiftKeyDown() then
                            ns.TodoList:SkipTask(capturedTask._taskIdx, "manual skip")
                            ns:Print(ns.COLORS.ORANGE .. "Skipped:|r " .. capturedTask.name)
                        else
                            ns.TodoList:MoveTaskToLog(capturedTask._taskIdx)
                            ns:Print("Posted: " .. capturedTask.name .. " -> moved to log")
                        end
                    end
                    UI:RefreshMini()
                    if UI.mainFrame and UI.mainFrame:IsShown() then UI:Refresh() end
                end
            end)

            row:Show()
        end
    end

    -- Current character tasks (Check AH, Check Mail, Expiring)
    local charTasks = UI.BuildCurrentCharTasks and UI.BuildCurrentCharTasks() or {}
    if #charTasks > 0 then
        for _, task in ipairs(charTasks) do
            rowIndex = rowIndex + 1
            local row = GetOrCreateMiniRow(rowIndex)
            row.icon:SetTexture(task.icon)
            row.text:SetText(task.text)
            row.tooltipItemID = nil
            row.tooltipItemName = nil
            row.tooltipExtra = nil
            row:SetScript("OnMouseDown", nil)
            row:Show()
        end
    end

    -- Next Steps section (always show — login tasks, expiring auctions, etc.)
    local nextData = UI.BuildNextStepsData and UI.BuildNextStepsData() or {}
    local MAX_MINI_STEPS = 3

    if #nextData > 0 then
        -- Separator row
        rowIndex = rowIndex + 1
        local sepRow = GetOrCreateMiniRow(rowIndex)
        sepRow.icon:SetTexture(nil)
        sepRow.text:SetText(ns.COLORS.GRAY .. "--- Next Steps ---" .. ns.COLORS.RESET)
        sepRow.tooltipItemID = nil
        sepRow.tooltipItemName = nil
        sepRow.tooltipExtra = nil
        sepRow:SetScript("OnMouseDown", nil)
        sepRow:Show()

        for idx = 1, math.min(#nextData, MAX_MINI_STEPS) do
            local step = nextData[idx]
            rowIndex = rowIndex + 1
            local row = GetOrCreateMiniRow(rowIndex)

            row.icon:SetTexture(nil)
            row.tooltipItemID = nil
            row.tooltipItemName = step._tooltipText
            row.tooltipExtra = step._tooltipExtra
            row:SetScript("OnMouseDown", nil)

            local extraStr = ""
            if step.detail and step.detail ~= "" then
                extraStr = " " .. step.detail
            elseif step.value and step.value ~= "" then
                extraStr = ns.COLORS.GREEN .. " " .. step.value .. ns.COLORS.RESET
            end

            row.text:SetText(step.action .. " " .. step.target ..
                ns.COLORS.GRAY .. " (" .. step.itemCount .. ")" .. ns.COLORS.RESET .. extraStr)
            row:Show()
        end

        if #nextData > MAX_MINI_STEPS then
            rowIndex = rowIndex + 1
            local moreRow = GetOrCreateMiniRow(rowIndex)
            moreRow.icon:SetTexture(nil)
            moreRow.text:SetText(ns.COLORS.GRAY .. "+" .. (#nextData - MAX_MINI_STEPS) ..
                " more... (open /fq)" .. ns.COLORS.RESET)
            moreRow.tooltipItemID = nil
            moreRow.tooltipItemName = nil
            moreRow.tooltipExtra = nil
            moreRow:SetScript("OnMouseDown", nil)
            moreRow:Show()
        end
    elseif #tasks == 0 and (not useTodoList or ns.TodoList:GetPendingCount() == 0) then
        rowIndex = rowIndex + 1
        local row = GetOrCreateMiniRow(rowIndex)
        row.icon:SetTexture(nil)
        row.text:SetText(ns.COLORS.GREEN .. "All done!" .. ns.COLORS.RESET ..
            ns.COLORS.GRAY .. " Time to go shopping!" .. ns.COLORS.RESET)
        row.tooltipItemID = nil
        row.tooltipItemName = nil
        row.tooltipExtra = nil
        row:SetScript("OnMouseDown", nil)
        row:Show()
    end

    -- Resize frame to fit content
    local contentHeight = math.max(1, rowIndex) * MINI_ROW_HEIGHT
    taskArea:SetHeight(contentHeight)
    mini:SetHeight(24 + contentHeight + 8)
end

--------------------------
-- Position restore & show/hide
--------------------------

function UI:ShowMini()
    if ns.db and ns.db.settings.miniPos then
        local p = ns.db.settings.miniPos
        mini:ClearAllPoints()
        mini:SetPoint(p.point or "TOPRIGHT", UIParent, p.relPoint or "TOPRIGHT", p.x or -200, p.y or -200)
    end
    mini:Show()
    if ns.db then ns.db.settings.showMini = true end
    self:RefreshMini()
end

function UI:HideMini()
    mini:Hide()
    if ns.db then ns.db.settings.showMini = false end
end

function UI:ToggleMini()
    if mini:IsShown() then
        self:HideMini()
    else
        self:ShowMini()
    end
end

UI.miniFrame = mini

--------------------------
-- Hide in combat (optional)
--------------------------

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- entering combat
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- leaving combat
local hiddenForCombat = false

combatFrame:SetScript("OnEvent", function(_, event)
    if not ns.db or not ns.db.settings.hideMiniInCombat then return end
    if event == "PLAYER_REGEN_DISABLED" then
        if mini:IsShown() then
            hiddenForCombat = true
            mini:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if hiddenForCombat then
            hiddenForCombat = false
            mini:Show()
            UI:RefreshMini()
        end
    end
end)

--------------------------
-- Auto-show on login if enabled
--------------------------

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    C_Timer.After(3, function()
        if ns.db and ns.db.settings.showMini then
            UI:ShowMini()
        end
    end)
end)

mini:Hide()

--------------------------
-- Refresh on bag changes
--------------------------

local bagUpdateFrame = CreateFrame("Frame")
bagUpdateFrame:RegisterEvent("BAG_UPDATE_DELAYED")
local bagUpdatePending = false
bagUpdateFrame:SetScript("OnEvent", function()
    if not mini:IsShown() then return end
    if not bagUpdatePending then
        bagUpdatePending = true
        C_Timer.After(0.5, function()
            bagUpdatePending = false
            if mini:IsShown() then
                UI:RefreshMini()
            end
        end)
    end
end)
