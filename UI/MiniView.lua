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

local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("LEFT", header, "LEFT", 2, 0)
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
        row:SetScript("OnMouseUp", nil)
        row.tooltipItemID = nil
        row.tooltipItemName = nil
        row.tooltipExtra = nil
    end

    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""

    -- Get tasks for this character filtered by realm
    local allTasks = ns.Queue:GetCharacterTasks(charKey)
    local tasks = {}
    for _, task in ipairs(allTasks) do
        if ns:RealmMatches(task.queueItem.targetRealm, myRealm) then
            table.insert(tasks, task)
        end
    end

    local rowIndex = 0

    if #tasks == 0 then
        local pending = ns.Queue:GetPendingCount()
        if pending > 0 then
            titleText:SetText(ns.COLORS.YELLOW .. "FQ" .. ns.COLORS.RESET ..
                ns.COLORS.GRAY .. " - " .. pending .. " pending (other realms)" .. ns.COLORS.RESET)
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
            row.tooltipItemID = task.queueItem.itemID
            row.tooltipItemName = task.queueItem.name
            row.tooltipExtra = (task.queueItem.targetRealm or "") ~= "" and
                ("Sell on: " .. task.queueItem.targetRealm .. "  @  " .. (task.queueItem.expectedPrice or "?")) or nil

            local priceStr = ""
            if task.queueItem.expectedPrice and task.queueItem.expectedPrice ~= "" then
                priceStr = ns.COLORS.GREEN .. " " .. task.queueItem.expectedPrice .. ns.COLORS.RESET
            end

            local locParts = {}
            if task.locations then
                for loc, qty in pairs(task.locations) do
                    table.insert(locParts, loc)
                end
            end
            local locStr = #locParts > 0 and (ns.COLORS.GRAY .. " [" .. table.concat(locParts, ",") .. "]" .. ns.COLORS.RESET) or ""

            row.text:SetText(ns.COLORS.WHITE .. task.queueItem.name .. ns.COLORS.RESET .. priceStr .. locStr)

            -- Right-click to mark posted
            local capturedTask = task
            row:SetScript("OnMouseUp", function(self, button)
                if button == "RightButton" then
                    ns.Queue:MarkPosted(capturedTask.queueIndex)
                    ns:Print("Posted: " .. capturedTask.queueItem.name .. " -> moved to log")
                    UI:RefreshMini()
                    UI:Refresh()
                end
            end)

            row:Show()
        end
    end

    -- Next Steps section (from BuildNextStepsData in MainFrame)
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
        sepRow:SetScript("OnMouseUp", nil)
        sepRow:Show()

        for idx = 1, math.min(#nextData, MAX_MINI_STEPS) do
            local step = nextData[idx]
            rowIndex = rowIndex + 1
            local row = GetOrCreateMiniRow(rowIndex)

            row.icon:SetTexture(nil)
            row.tooltipItemID = nil
            row.tooltipItemName = step._tooltipText
            row.tooltipExtra = step._tooltipExtra
            row:SetScript("OnMouseUp", nil)

            local valueStr = ""
            if step.value and step.value ~= "" then
                valueStr = ns.COLORS.GREEN .. " " .. step.value .. ns.COLORS.RESET
            end

            row.text:SetText(step.action .. " " .. step.target ..
                ns.COLORS.GRAY .. " (" .. step.itemCount .. ")" .. ns.COLORS.RESET .. valueStr)
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
            moreRow:SetScript("OnMouseUp", nil)
            moreRow:Show()
        end
    elseif #tasks == 0 and ns.Queue:GetPendingCount() == 0 then
        -- Queue completely empty — fun message
        rowIndex = rowIndex + 1
        local row = GetOrCreateMiniRow(rowIndex)
        row.icon:SetTexture(nil)
        row.text:SetText(ns.COLORS.GREEN .. "All done!" .. ns.COLORS.RESET ..
            ns.COLORS.GRAY .. " Time to go shopping!" .. ns.COLORS.RESET)
        row.tooltipItemID = nil
        row.tooltipItemName = nil
        row.tooltipExtra = nil
        row:SetScript("OnMouseUp", nil)
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
