-- UI/Sections.lua
-- Renders collapsible queue sections in the main frame
local addonName, ns = ...

local UI = ns.UI

--------------------------
-- Sort helpers
--------------------------

local function SortItems(items, sortMode)
    if sortMode == "name" then
        table.sort(items, function(a, b)
            local nameA = (a.name or a.queueItem and a.queueItem.name or "")
            local nameB = (b.name or b.queueItem and b.queueItem.name or "")
            return nameA:lower() < nameB:lower()
        end)
    end
    -- "realm" is the default grouping, no re-sort needed
end

--------------------------
-- Section: Items to post on THIS character
--------------------------

function UI:RenderThisCharacter(rowIndex, charKey, myRealm)
    local allTasks = ns.Queue:GetCharacterTasks(charKey)

    -- Filter: only items whose target realm matches current character's realm
    local tasks = {}
    for _, task in ipairs(allTasks) do
        if ns:RealmMatches(task.queueItem.targetRealm, myRealm) then
            table.insert(tasks, task)
        end
    end

    if #tasks == 0 then return rowIndex end

    SortItems(tasks, ns.db.settings.sortMode)

    rowIndex = rowIndex + 1
    local collapsed = self:CreateSectionHeader(rowIndex, "thisChar",
        "Items to post (" .. charKey .. ")", ns.COLORS.GREEN, #tasks)

    if collapsed then return rowIndex end

    for _, task in ipairs(tasks) do
        rowIndex = rowIndex + 1
        local row = self:GetOrCreateRow(rowIndex)

        local locParts = {}
        if task.locations then
            for loc, qty in pairs(task.locations) do
                table.insert(locParts, loc .. ": " .. qty)
            end
        end
        local locStr = #locParts > 0 and (" [" .. table.concat(locParts, ", ") .. "]") or ""

        local fuzzyTag = task.fuzzyMatch and ns.COLORS.ORANGE .. " ~" .. ns.COLORS.RESET or ""

        local sellInfo = ""
        if task.queueItem.targetRealm and task.queueItem.targetRealm ~= "" then
            sellInfo = ns.COLORS.BLUE .. " -> " .. task.queueItem.targetRealm .. ns.COLORS.RESET
        end
        if task.queueItem.expectedPrice and task.queueItem.expectedPrice ~= "" then
            sellInfo = sellInfo .. ns.COLORS.GREEN .. " @ " .. task.queueItem.expectedPrice .. ns.COLORS.RESET
        end

        row.icon:SetTexture(task.icon)
        row.tooltipItemID = task.queueItem.itemID
        row.tooltipItemName = task.queueItem.name
        row.tooltipExtra = (task.queueItem.targetRealm or "") ~= "" and
            ("Sell on: " .. task.queueItem.targetRealm .. "  @  " .. (task.queueItem.expectedPrice or "?")) or nil
        row.text:SetText(string.format("%s%s|r (x%d)%s%s%s%s",
            ns.COLORS.WHITE,
            task.queueItem.name,
            task.quantity,
            fuzzyTag,
            sellInfo,
            ns.COLORS.GRAY,
            locStr .. ns.COLORS.RESET
        ))

        -- Right-click to mark as posted (moves to log)
        local capturedTask = task
        row:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                ns.Queue:MarkPosted(capturedTask.queueIndex)
                ns:Print("Posted: " .. capturedTask.queueItem.name .. " -> moved to log")
                UI:Refresh()
            end
        end)

        row:Show()
    end

    return rowIndex
end

--------------------------
-- Section: Post on other realms
--------------------------

function UI:RenderOtherRealms(rowIndex, charKey, myRealm)
    local realmGroups = {}

    for _, item in ipairs(ns.db.queue) do
        if item.status == "pending" and item.targetRealm and item.targetRealm ~= "" then
            if not ns:RealmMatches(item.targetRealm, myRealm) then
                if not realmGroups[item.targetRealm] then
                    realmGroups[item.targetRealm] = {items = {}, characters = {}}
                end
                table.insert(realmGroups[item.targetRealm].items, item)
            end
        end
    end

    -- Find which characters cover each realm
    for realmStr, group in pairs(realmGroups) do
        for otherCharKey, charData in pairs(ns.db.inventory) do
            local otherRealm = otherCharKey:match("%-(.+)$")
            if otherRealm and ns:RealmMatches(realmStr, otherRealm) then
                table.insert(group.characters, {
                    charKey  = otherCharKey,
                    class    = charData.class,
                })
            end
        end
    end

    -- Sort realms by item count descending
    local sortedRealms = {}
    for realmStr, group in pairs(realmGroups) do
        table.insert(sortedRealms, {realm = realmStr, group = group})
    end
    table.sort(sortedRealms, function(a, b) return #a.group.items > #b.group.items end)

    -- Store for use by NeedAccount section
    self._sortedRealms = sortedRealms

    if #sortedRealms == 0 then return rowIndex end

    -- Count total items across all realms
    local totalItems = 0
    for _, entry in ipairs(sortedRealms) do
        totalItems = totalItems + #entry.group.items
    end

    rowIndex = rowIndex + 1
    local collapsed = self:CreateSectionHeader(rowIndex, "otherRealms",
        "Post on other realms", ns.COLORS.YELLOW, totalItems)

    if collapsed then return rowIndex end

    local sortMode = ns.db.settings.sortMode

    if sortMode == "name" then
        -- Flat list sorted by item name
        local allItems = {}
        for _, entry in ipairs(sortedRealms) do
            for _, item in ipairs(entry.group.items) do
                table.insert(allItems, {item = item, realm = entry.realm, characters = entry.group.characters})
            end
        end
        table.sort(allItems, function(a, b) return (a.item.name or ""):lower() < (b.item.name or ""):lower() end)

        for _, data in ipairs(allItems) do
            rowIndex = rowIndex + 1
            local row = self:GetOrCreateRow(rowIndex)

            local charStr = ""
            if #data.characters > 0 then
                charStr = ns.COLORS.BLUE .. " [" .. data.characters[1].charKey .. "]" .. ns.COLORS.RESET
            else
                charStr = ns.COLORS.RED .. " [NO CHAR]" .. ns.COLORS.RESET
            end

            local priceStr = ""
            if data.item.expectedPrice and data.item.expectedPrice ~= "" then
                priceStr = ns.COLORS.GREEN .. " @ " .. data.item.expectedPrice .. ns.COLORS.RESET
            end

            row.icon:SetTexture(nil)
            row.tooltipItemID = data.item.itemID
            row.tooltipItemName = data.item.name
            row.tooltipExtra = "Sell on: " .. data.realm .. "  @  " .. (data.item.expectedPrice or "?")
            row.text:SetText(string.format("  %s%s|r (x%d) -> %s%s|r%s%s",
                ns.COLORS.WHITE, data.item.name, data.item.quantity,
                ns.COLORS.ORANGE, data.realm, priceStr, charStr))
            row:Show()
        end
    else
        -- Default: grouped by realm
        for _, entry in ipairs(sortedRealms) do
            rowIndex = rowIndex + 1
            local row = self:GetOrCreateRow(rowIndex)
            row.icon:SetTexture(nil)

            local charStr
            if #entry.group.characters > 0 then
                local charNames = {}
                for _, c in ipairs(entry.group.characters) do
                    table.insert(charNames, c.charKey)
                end
                charStr = ns.COLORS.BLUE .. table.concat(charNames, ", ") .. ns.COLORS.RESET
            else
                charStr = ns.COLORS.RED .. "NO CHARACTER" .. ns.COLORS.RESET
            end

            row.text:SetText(string.format("  %s%s|r - %d items - log onto %s",
                ns.COLORS.ORANGE, entry.realm,
                #entry.group.items, charStr))
            row:Show()

            for _, item in ipairs(entry.group.items) do
                rowIndex = rowIndex + 1
                local itemRow = self:GetOrCreateRow(rowIndex)

                local priceStr = ""
                if item.expectedPrice and item.expectedPrice ~= "" then
                    priceStr = ns.COLORS.GREEN .. " @ " .. item.expectedPrice .. ns.COLORS.RESET
                end
                if item.noCompetition then
                    priceStr = priceStr .. ns.COLORS.ORANGE .. " [No comp]" .. ns.COLORS.RESET
                end

                itemRow.icon:SetTexture(nil)
                itemRow.tooltipItemID = item.itemID
                itemRow.tooltipItemName = item.name
                itemRow.tooltipExtra = "Sell on: " .. entry.realm .. "  @  " .. (item.expectedPrice or "?")
                itemRow.text:SetText(string.format("    %s%s|r (x%d)%s",
                    ns.COLORS.WHITE, item.name,
                    item.quantity, priceStr))
                itemRow:Show()
            end
        end
    end

    return rowIndex
end

--------------------------
-- Section: Realms needing a character
--------------------------

function UI:RenderNeedAccount(rowIndex)
    local sortedRealms = self._sortedRealms or {}

    local needAccount = {}
    for _, entry in ipairs(sortedRealms) do
        if #entry.group.characters == 0 then
            table.insert(needAccount, {realm = entry.realm, count = #entry.group.items})
        end
    end

    if #needAccount == 0 then return rowIndex end

    rowIndex = rowIndex + 1
    local collapsed = self:CreateSectionHeader(rowIndex, "needAccount",
        "Realms needing a character", ns.COLORS.RED, #needAccount)

    if collapsed then return rowIndex end

    for _, info in ipairs(needAccount) do
        rowIndex = rowIndex + 1
        local row = self:GetOrCreateRow(rowIndex)
        row.icon:SetTexture(nil)
        row.text:SetText(string.format("  %s%s|r - %d items",
            ns.COLORS.ORANGE, info.realm, info.count))
        row:Show()
    end

    return rowIndex
end

--------------------------
-- Section: Full Queue
--------------------------

function UI:RenderFullQueue(rowIndex)
    if #ns.db.queue == 0 then return rowIndex end

    rowIndex = rowIndex + 1
    local collapsed = self:CreateSectionHeader(rowIndex, "fullQueue",
        "Full Queue", ns.COLORS.YELLOW, #ns.db.queue)

    if collapsed then return rowIndex end

    -- Build sorted copy if needed
    local items = {}
    for i, item in ipairs(ns.db.queue) do
        table.insert(items, {index = i, item = item})
    end

    if ns.db.settings.sortMode == "name" then
        table.sort(items, function(a, b)
            return (a.item.name or ""):lower() < (b.item.name or ""):lower()
        end)
    end

    for _, entry in ipairs(items) do
        local i = entry.index
        local item = entry.item

        rowIndex = rowIndex + 1
        local row = self:GetOrCreateRow(rowIndex)

        local statusStr, statusColor
        if item.status == "posted" then
            statusStr = "POSTED"
            statusColor = ns.COLORS.GREEN
        else
            statusStr = "pending"
            statusColor = ns.COLORS.GRAY
        end

        local locs = ns.Queue:FindItemLocations(item.itemKey)
        local locStr = ""
        if #locs > 0 then
            local parts = {}
            for _, loc in ipairs(locs) do
                table.insert(parts, loc.charKey .. "(x" .. loc.quantity .. ")")
            end
            locStr = " -> " .. table.concat(parts, ", ")
        elseif item.name ~= "" then
            local nameLocs = ns.Queue:FindItemByName(item.name)
            if #nameLocs > 0 then
                local parts = {}
                for _, loc in ipairs(nameLocs) do
                    table.insert(parts, loc.charKey .. "(x" .. loc.quantity .. ")")
                end
                locStr = " ~> " .. table.concat(parts, ", ")
            end
        end

        local sellInfo = ""
        if item.targetRealm and item.targetRealm ~= "" then
            sellInfo = ns.COLORS.BLUE .. " -> " .. item.targetRealm .. ns.COLORS.RESET
        end
        if item.expectedPrice and item.expectedPrice ~= "" then
            sellInfo = sellInfo .. ns.COLORS.GREEN .. " @ " .. item.expectedPrice .. ns.COLORS.RESET
        end
        if item.noCompetition then
            sellInfo = sellInfo .. ns.COLORS.ORANGE .. " [No comp]" .. ns.COLORS.RESET
        end

        row.icon:SetTexture(nil)
        row.tooltipItemID = item.itemID
        row.tooltipItemName = item.name ~= "" and item.name or item.itemID
        row.tooltipExtra = (item.targetRealm or "") ~= "" and
            ("Sell on: " .. item.targetRealm .. "  @  " .. (item.expectedPrice or "?")) or nil
        row.text:SetText(string.format("  %s[%s]|r %s (x%d)%s%s%s%s",
            statusColor, statusStr,
            item.name ~= "" and item.name or item.itemID,
            item.quantity,
            sellInfo,
            ns.COLORS.GRAY, locStr, ns.COLORS.RESET
        ))

        -- Right-click to mark posted (move to log)
        local capturedIndex = i
        local capturedItem = item
        row:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                if capturedItem.status == "pending" then
                    ns.Queue:MarkPosted(capturedIndex)
                    ns:Print("Posted: " .. (capturedItem.name ~= "" and capturedItem.name or capturedItem.itemID) .. " -> moved to log")
                end
                UI:Refresh()
            end
        end)

        row:Show()
    end

    return rowIndex
end
