-- UI/MiniView.lua
-- Compact overlay showing current-character tasks, moveable with action icons
local addonName, ns = ...

local UI = ns.UI
local MINI_ROW_HEIGHT = 18
local MINI_WIDTH_DEFAULT = 280
local MINI_WIDTH_MIN = 200
local MINI_WIDTH_MAX = 500
local COLLAPSED_ROWS = 2

--------------------------
-- Mini Frame
--------------------------

local mini = CreateFrame("Frame", "FlipQueueMiniFrame", UIParent, "BackdropTemplate")
mini:SetSize(MINI_WIDTH_DEFAULT, 60)
mini:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200)
mini:SetMovable(true)
mini:SetResizable(true)
mini:SetResizeBounds(MINI_WIDTH_MIN, 40, MINI_WIDTH_MAX, 600)
mini:EnableMouse(true)
mini:RegisterForDrag("LeftButton")
mini:SetScript("OnDragStart", mini.StartMoving)
mini:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
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

-- Collapsed state
local miniCollapsed = false

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

-- Collapse/expand toggle button
local collapseBtn = CreateIconButton(header, "Interface\\Buttons\\UI-MinusButton-Up", "Collapse", function()
    miniCollapsed = not miniCollapsed
    if ns.db then ns.db.settings.miniCollapsed = miniCollapsed end
    UI:RefreshMini()
end)
collapseBtn:SetPoint("RIGHT", importBtn, "LEFT", -ICON_SPACING, 0)

-- Resize grip (bottom-right corner)
local resizeGrip = CreateFrame("Button", nil, mini)
resizeGrip:SetSize(12, 12)
resizeGrip:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", -2, 2)
resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetScript("OnMouseDown", function()
    mini:StartSizing("RIGHT")
end)
resizeGrip:SetScript("OnMouseUp", function()
    mini:StopMovingOrSizing()
    if ns.db then
        ns.db.settings.miniWidth = math.floor(mini:GetWidth() + 0.5)
    end
    UI:RefreshMini()
end)

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

    -- Hide all rows and clean up action buttons
    for _, row in ipairs(miniRows) do
        row:Hide()
        row:SetScript("OnMouseDown", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row.tooltipItemID = nil
        row.tooltipItemName = nil
        row.tooltipExtra = nil
        if row._taskActionBtns then
            UI.HideTaskActionBtns(row)
        end
    end

    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""

    -- Build bag lookup: item IDs, pet species, and names
    local bagsItemIDs = {}
    local bagsItemKeys = {}
    local bagsPetSpecies = {}
    local bagsItemNames = {}
    pcall(function()
        for _, bagIdx in ipairs(ns.INVENTORY_BAGS) do
            local numSlots = C_Container.GetContainerNumSlots(bagIdx)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bagIdx, slot)
                if info and info.hyperlink then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                        bagsItemKeys[key] = (bagsItemKeys[key] or 0) + (info.stackCount or 1)
                        local numID = tonumber(itemID)
                        if numID then
                            bagsItemIDs[numID] = (bagsItemIDs[numID] or 0) + (info.stackCount or 1)
                        end
                        local speciesID = itemID:match("^pet:(%d+)") or itemID:match("^pet_(%d+)")
                        if speciesID then
                            bagsPetSpecies[speciesID] = (bagsPetSpecies[speciesID] or 0) + 1
                        end
                    end
                    local itemName = info.hyperlink:match("|h%[(.-)%]|h")
                    if itemName and itemName ~= "" then
                        bagsItemNames[itemName:lower()] = (bagsItemNames[itemName:lower()] or 0) + (info.stackCount or 1)
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
            local isBuyTask = task.item.action == "buy"
            local realmToMatch = isBuyTask and task.item.buyRealm or task.item.targetRealm
            if ns:RealmMatches(realmToMatch or "", myRealm) then
                -- Skip tasks where another character needs to deposit first
                local needsOtherDeposit = task.item.depositFrom and task.item.depositFrom ~= charKey
                if not isBuyTask and needsOtherDeposit then
                    -- skip — item is on another character, not actionable here
                else

                local itemNumID = tonumber(task.item.itemID) or tonumber(task.item.itemKey and task.item.itemKey:match("^(%d+)"))
                local itemKey = task.item.itemKey or ""
                local petSpecies = itemKey:match("^pet:(%d+)") or itemKey:match("^pet_(%d+)")
                    or (task.item.itemID and (task.item.itemID:match("^pet:(%d+)") or task.item.itemID:match("^pet_(%d+)")))
                local taskName = task.item.name and task.item.name:lower() or nil
                local inBags = (bagsItemKeys[itemKey] and bagsItemKeys[itemKey] > 0)
                    or (itemNumID and bagsItemIDs[itemNumID] and bagsItemIDs[itemNumID] > 0)
                    or (petSpecies and bagsPetSpecies[petSpecies] and bagsPetSpecies[petSpecies] > 0)
                    or (taskName and bagsItemNames[taskName] and bagsItemNames[taskName] > 0)
                table.insert(tasks, {
                    name     = task.item.name or "?",
                    itemID   = task.item.itemID,
                    price    = isBuyTask and task.item.buyPrice or task.item.expectedPrice,
                    realm    = isBuyTask and task.item.buyRealm or task.item.targetRealm,
                    icon     = task.item.icon,
                    source   = task.item.source,
                    inBags   = inBags,
                    _taskIdx = task.taskIndex,
                    _isTodo  = true,
                    _isBuy   = isBuyTask,
                    _deferred = task.item.deferredAt and true or false,
                    _depositFrom = task.item.depositFrom,
                })
                end -- else (not deferred)
            end
        end
    end

    local rowIndex = 0
    local personalRowEnd = 0  -- tracks end of current character's rows (collapse preserves these)

    -- Count buy vs post tasks (used for title and Auctionator button)
    local buyCount, postCount = 0, 0
    for _, t in ipairs(tasks) do
        if t._isBuy then buyCount = buyCount + 1 else postCount = postCount + 1 end
    end

    -- Pre-check for char tasks (Check Mail, Expiring, etc.)
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
            if currentList and currentList.tasks then
                -- Annotate task indices (same as TodoPage) so bulk actions work
                for i, task in ipairs(currentList.tasks) do
                    task._taskIndex = i
                end
                local MAX_MINI_CHARS = 5
                local sortMode = (UI.GetGenSortMode and UI:GetGenSortMode()) or "profit"
                local displayGroups = ns.TodoList:BuildDisplayGroups(currentList.tasks, sortMode)

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
                    -- Count buy vs sell in group
                    local gBuys, gPosts = 0, 0
                    for _, gi in ipairs(group.items) do
                        if gi.action == "buy" then gBuys = gBuys + 1 else gPosts = gPosts + 1 end
                    end
                    local gParts = {}
                    if gPosts > 0 then table.insert(gParts, gPosts .. " to post") end
                    if gBuys > 0 then table.insert(gParts, gBuys .. " to buy") end
                    row.tooltipExtra = table.concat(gParts, ", ") .. ", ~" .. goldStr

                    -- Collect task indices for bulk action buttons
                    local grpIndices = {}
                    for _, gi in ipairs(group.items) do
                        if gi._taskIndex then table.insert(grpIndices, gi._taskIndex) end
                    end
                    row:SetScript("OnMouseDown", nil)
                    if #grpIndices > 0 then
                        local miniRefresh = function()
                            UI:RefreshMini()
                            if UI.mainFrame and UI.mainFrame:IsShown() then UI:Refresh() end
                        end
                        UI.SetupTaskActionBtns(row)
                        local btns = row._taskActionBtns
                        btns.complete:SetScript("OnClick", function()
                            ns.TodoList:BulkComplete(grpIndices)
                            miniRefresh()
                        end)
                        btns.skip:SetScript("OnClick", function()
                            ns.TodoList:BulkSkip(grpIndices, "bulk skip")
                            miniRefresh()
                        end)
                        btns.delete:SetScript("OnClick", function()
                            ns.TodoList:BulkDelete(grpIndices)
                            miniRefresh()
                        end)
                        UI.HideTaskActionBtns(row)
                        row:SetScript("OnEnter", function(self)
                            UI.ShowTaskActionBtns(self)
                            if self.tooltipItemName then
                                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                GameTooltip:SetText(self.tooltipItemName, 1, 1, 1)
                                if self.tooltipExtra then
                                    GameTooltip:AddLine(self.tooltipExtra, 0.7, 0.7, 0.7, true)
                                end
                                GameTooltip:Show()
                            end
                        end)
                        row:SetScript("OnLeave", function(self)
                            self._actionBtnHovered = false
                            C_Timer.After(0.1, function()
                                if not self._actionBtnHovered and not self:IsMouseOver() then
                                    GameTooltip:Hide()
                                    UI.HideTaskActionBtns(self)
                                end
                            end)
                        end)
                    end

                    local charEntry = ns.db.characters and ns.db.characters[group.charKey]
                    local cc = charEntry and UI._CLASS_COLORS and UI._CLASS_COLORS[charEntry.class] or "888888"
                    local charName = group.charName or "?"
                    local realmShort = group.realm:match("^([^,]+)") or group.realm

                    local countLabel = gBuys > 0 and gPosts > 0
                        and (gPosts .. "P+" .. gBuys .. "B")
                        or (gBuys > 0 and (gBuys .. "B") or tostring(#group.items))
                    row.text:SetText(
                        "|cff" .. cc .. charName .. "|r" ..
                        ns.COLORS.GRAY .. " " .. realmShort .. ns.COLORS.RESET ..
                        ns.COLORS.GRAY .. " (" .. countLabel .. ")" .. ns.COLORS.RESET ..
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

                        -- Bulk action buttons for unassigned (create char) groups
                        local uIndices = {}
                        for _, gi in ipairs(group.items) do
                            if gi._taskIndex then table.insert(uIndices, gi._taskIndex) end
                        end
                        row:SetScript("OnMouseDown", nil)
                        if #uIndices > 0 then
                            local miniRefresh = function()
                                UI:RefreshMini()
                                if UI.mainFrame and UI.mainFrame:IsShown() then UI:Refresh() end
                            end
                            UI.SetupTaskActionBtns(row)
                            local btns = row._taskActionBtns
                            btns.complete:SetScript("OnClick", function()
                                ns.TodoList:BulkComplete(uIndices)
                                miniRefresh()
                            end)
                            btns.skip:SetScript("OnClick", function()
                                ns.TodoList:BulkSkip(uIndices, "bulk skip")
                                miniRefresh()
                            end)
                            btns.delete:SetScript("OnClick", function()
                                ns.TodoList:BulkDelete(uIndices)
                                miniRefresh()
                            end)
                            UI.HideTaskActionBtns(row)
                            row:SetScript("OnEnter", function(self)
                                UI.ShowTaskActionBtns(self)
                                if self.tooltipExtra then
                                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                    GameTooltip:SetText(self.tooltipExtra, 0.7, 0.7, 0.7)
                                    GameTooltip:Show()
                                end
                            end)
                            row:SetScript("OnLeave", function(self)
                                self._actionBtnHovered = false
                                C_Timer.After(0.1, function()
                                    if not self._actionBtnHovered and not self:IsMouseOver() then
                                        GameTooltip:Hide()
                                        UI.HideTaskActionBtns(self)
                                    end
                                end)
                            end)
                        end

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
                ns.COLORS.GRAY .. " - nothing to do" .. ns.COLORS.RESET)
        end
    else
        local titleParts = {}
        if postCount > 0 then table.insert(titleParts, postCount .. " to post") end
        if buyCount > 0 then table.insert(titleParts, buyCount .. " to buy") end
        titleText:SetText(ns.COLORS.YELLOW .. "FQ" .. ns.COLORS.RESET ..
            ns.COLORS.GREEN .. " - " .. table.concat(titleParts, ", ") .. ns.COLORS.RESET)

        for _, task in ipairs(tasks) do
            rowIndex = rowIndex + 1
            local row = GetOrCreateMiniRow(rowIndex)

            row.icon:SetTexture(task.icon)
            row.tooltipItemID = task.itemID
            row.tooltipItemName = task.name
            if task._isBuy then
                row.tooltipExtra = "BUY on: " .. (task.realm or "?") .. "  @  " .. (task.price or "?")
            else
                row.tooltipExtra = (task.realm or "") ~= "" and
                    ("Sell on: " .. task.realm .. "  @  " .. (task.price or "?")) or nil
            end

            local priceStr = ""
            if task.price and task.price ~= "" then
                priceStr = ns.COLORS.GREEN .. " " .. task.price .. ns.COLORS.RESET
            end

            -- Status icon and suffix tag
            local statusIcon, statusTag
            if task._isBuy then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t "
                statusTag = ""
            elseif task.inBags then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
                statusTag = ""
            elseif task.source == "warbank" then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t "
                statusTag = ns.COLORS.YELLOW .. " [wb]" .. ns.COLORS.RESET
            elseif task.source == "bank" then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t "
                statusTag = ns.COLORS.BLUE .. " [bank]" .. ns.COLORS.RESET
            elseif task._depositFrom then
                local depName = task._depositFrom:match("^(.-)%-") or task._depositFrom
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t "
                statusTag = ns.COLORS.CYAN .. " [via " .. depName .. "]" .. ns.COLORS.RESET
            elseif task._deferred then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t "
                statusTag = ns.COLORS.RED .. " [deferred]" .. ns.COLORS.RESET
            else
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t "
                statusTag = ns.COLORS.RED .. " [not found]" .. ns.COLORS.RESET
            end

            local namePrefix = task._isBuy and (ns.COLORS.CYAN .. "[BUY] " .. ns.COLORS.RESET) or ""
            row.text:SetText(statusIcon .. namePrefix .. ns.COLORS.WHITE .. task.name .. ns.COLORS.RESET .. statusTag .. priceStr)

            -- Action buttons (complete/skip/delete) on mouseover
            local capturedTask = task
            if capturedTask._isTodo and capturedTask._taskIdx then
                local miniRefresh = function()
                    UI:RefreshMini()
                    if UI.mainFrame and UI.mainFrame:IsShown() then UI:Refresh() end
                end
                UI.SetupTaskActionBtns(row)
                UI.WireTaskActionBtns(row, capturedTask._taskIdx, miniRefresh)
                UI.HideTaskActionBtns(row)

                row:SetScript("OnEnter", function(self)
                    UI.ShowTaskActionBtns(self)
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
                row:SetScript("OnLeave", function(self)
                    self._actionBtnHovered = false
                    C_Timer.After(0.1, function()
                        if not self._actionBtnHovered and not self:IsMouseOver() then
                            GameTooltip:Hide()
                            UI.HideTaskActionBtns(self)
                        end
                    end)
                end)
            else
                UI.HideTaskActionBtns(row)
            end

            -- Right-click to mark posted, Shift+Right to skip (kept as alternative)
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

    -- Auctionator shopping list button (when buy tasks exist and Auctionator is loaded)
    if buyCount and buyCount > 0 and type(Auctionator) == "table"
            and type(Auctionator.API) == "table" and type(Auctionator.API.v1) == "table" then
        rowIndex = rowIndex + 1
        local auctRow = GetOrCreateMiniRow(rowIndex)
        auctRow.icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
        auctRow.text:SetText(ns.COLORS.YELLOW .. "Create Auctionator Buy List" .. ns.COLORS.RESET)
        auctRow.tooltipItemID = nil
        auctRow.tooltipItemName = "Create Shopping List"
        auctRow.tooltipExtra = "Create Auctionator shopping lists grouped by realm (" .. buyCount .. " buy items)"
        auctRow:SetScript("OnMouseDown", function()
            local count, result = UI.CreateBuyTaskShoppingList()
            if count then
                ns:Print(ns.COLORS.GREEN .. "Created " .. result .. " with " .. count .. " items.|r")
            else
                ns:Print(ns.COLORS.RED .. "Error: " .. (result or "unknown") .. "|r")
            end
            UI:RefreshMini()
        end)
        auctRow:Show()
    end

    -- Current character tasks (Check Mail, Expiring)
    local charTasks = UI.BuildCurrentCharTasks and UI.BuildCurrentCharTasks() or {}
    if #charTasks > 0 then
        for _, task in ipairs(charTasks) do
            rowIndex = rowIndex + 1
            local row = GetOrCreateMiniRow(rowIndex)
            row.icon:SetTexture(task.icon)
            row.text:SetText(task.text)
            row.tooltipItemID = nil
            row.tooltipItemName = task._dismissible and "Right-click to dismiss" or nil
            row.tooltipExtra = nil
            if task._dismissible and task._onDismiss then
                local capturedDismiss = task._onDismiss
                row:SetScript("OnMouseDown", function(_, button)
                    if button == "RightButton" then
                        capturedDismiss()
                        UI:RefreshMini()
                        if UI.mainFrame and UI.mainFrame:IsShown() then UI:Refresh() end
                    end
                end)
            else
                row:SetScript("OnMouseDown", nil)
            end
            row:Show()
        end
    end

    -- Mark end of personal rows (collapse preserves everything above this point)
    personalRowEnd = rowIndex

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

        -- "Open Generator" clickable row
        rowIndex = rowIndex + 1
        local genRow = GetOrCreateMiniRow(rowIndex)
        genRow.icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
        genRow.text:SetText(ns.COLORS.YELLOW .. "Open To-Do Generator" .. ns.COLORS.RESET)
        genRow.tooltipItemID = nil
        genRow.tooltipItemName = "Open Generator"
        genRow.tooltipExtra = "Click to open the main window on the To-Do Generator page"
        genRow:SetScript("OnMouseDown", function()
            UI.currentPage = "generator"
            UI.mainFrame:Show()
            UI:Refresh()
        end)
        genRow:Show()
    end

    -- Auto-width: measure text and stretch to fit (within bounds)
    local savedWidth = ns.db and ns.db.settings.miniWidth
    local maxTextW = 0
    for i = 1, rowIndex do
        local row = miniRows[i]
        if row and row:IsShown() and row.text then
            local tw = row.text:GetStringWidth()
            local iconW = (row.icon and row.icon:IsShown()) and (MINI_ROW_HEIGHT + 3) or 0
            local totalW = tw + iconW + 12 -- padding
            if totalW > maxTextW then maxTextW = totalW end
        end
    end
    local desiredW = math.max(maxTextW + 12, MINI_WIDTH_MIN)
    if savedWidth and savedWidth >= MINI_WIDTH_MIN then
        desiredW = math.max(desiredW, savedWidth)
    end
    desiredW = math.min(desiredW, MINI_WIDTH_MAX)
    mini:SetWidth(desiredW)

    -- Collapse: hide rows beyond personal tasks, show "+N more" hint
    -- personalRowEnd marks the last row that belongs to the current character's tasks
    local visibleRows = rowIndex
    if miniCollapsed and rowIndex > personalRowEnd then
        for i = personalRowEnd + 1, rowIndex do
            if miniRows[i] then miniRows[i]:Hide() end
        end
        visibleRows = personalRowEnd
        -- Show "+N more" hint
        local hiddenCount = rowIndex - personalRowEnd
        if hiddenCount > 0 then
            visibleRows = visibleRows + 1
            local hintRow = GetOrCreateMiniRow(visibleRows)
            hintRow.icon:SetTexture(nil)
            hintRow.text:SetText(ns.COLORS.GRAY .. "+" .. hiddenCount .. " more... (click + to expand)" .. ns.COLORS.RESET)
            hintRow.tooltipItemID = nil
            hintRow.tooltipItemName = nil
            hintRow.tooltipExtra = nil
            hintRow:SetScript("OnMouseDown", nil)
            hintRow:SetScript("OnEnter", nil)
            hintRow:SetScript("OnLeave", nil)
            if hintRow._taskActionBtns then UI.HideTaskActionBtns(hintRow) end
            hintRow:Show()
        end
    end

    -- Update collapse button icon
    if miniCollapsed then
        collapseBtn.tex:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
        collapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Expand (" .. rowIndex .. " rows)", 1, 1, 1)
            GameTooltip:Show()
        end)
    else
        collapseBtn.tex:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
        collapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Collapse", 1, 1, 1)
            GameTooltip:Show()
        end)
    end

    -- Resize frame to fit content
    local contentHeight = math.max(1, visibleRows) * MINI_ROW_HEIGHT
    taskArea:SetHeight(contentHeight)
    mini:SetHeight(24 + contentHeight + 8)
    resizeGrip:SetShown(not miniCollapsed)
end

--------------------------
-- Position restore & show/hide
--------------------------

function UI:ShowMini()
    if ns.db then
        -- Restore position
        if ns.db.settings.miniPos then
            local p = ns.db.settings.miniPos
            mini:ClearAllPoints()
            mini:SetPoint(p.point or "TOPRIGHT", UIParent, p.relPoint or "TOPRIGHT", p.x or -200, p.y or -200)
        end
        -- Restore width
        if ns.db.settings.miniWidth and ns.db.settings.miniWidth >= MINI_WIDTH_MIN then
            mini:SetWidth(ns.db.settings.miniWidth)
        end
        -- Restore collapsed state
        if ns.db.settings.miniCollapsed then
            miniCollapsed = true
        end
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
