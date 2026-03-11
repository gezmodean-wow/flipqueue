-- Queue.lua
-- Manages the flip queue: add/remove items, match against inventory, character routing
local addonName, ns = ...

local Queue = {}
ns.Queue = Queue

--------------------------
-- Queue Operations
--------------------------

-- Use shared ns:RealmsOverlap from Core.lua
local function RealmsOverlap(realm1, realm2)
    return ns:RealmsOverlap(realm1, realm2)
end

function Queue:Add(items)
    if not ns.db then return 0 end

    local added = 0
    local duped = 0
    for _, item in ipairs(items) do
        local isDuplicate = false
        -- Match by key or name (handles FP website vs CSV key differences)
        local itemName = (item.name or ""):lower()
        for _, existing in ipairs(ns.db.queue) do
            if existing.status == "pending" then
                local keyMatch = existing.itemKey == item.itemKey
                local nameMatch = itemName ~= "" and existing.name
                    and existing.name:lower() == itemName
                if (keyMatch or nameMatch) and RealmsOverlap(existing.targetRealm, item.targetRealm) then
                    -- Keep the longer/more descriptive realm string
                    if #(item.targetRealm or "") > #(existing.targetRealm or "") then
                        existing.targetRealm = item.targetRealm
                    end
                    -- Keep higher price if available
                    if item.expectedPrice and (not existing.expectedPrice or existing.expectedPrice == "") then
                        existing.expectedPrice = item.expectedPrice
                    end
                    isDuplicate = true
                    duped = duped + 1
                    break
                end
            end
        end

        if not isDuplicate then
            table.insert(ns.db.queue, {
                itemKey       = item.itemKey,
                itemID        = item.itemID or "",
                name          = item.name or "",
                quality       = item.quality or "",
                ilvl          = item.ilvl or 0,
                bonusIDs      = item.bonusIDs or "",
                modifiers     = item.modifiers or "",
                quantity      = item.quantity or 1,
                category      = item.category,
                expansion     = item.expansion,
                sellRate      = item.sellRate,
                targetRealm   = item.targetRealm,
                expectedPrice = item.expectedPrice,
                noCompetition = item.noCompetition,
                status        = "pending",
                addedAt       = time(),
                postedAt      = nil,
            })
            added = added + 1
        end
    end

    if duped > 0 then
        ns:Print(ns.COLORS.GRAY .. "Deduped " .. duped .. " connected-realm duplicates.|r")
    end

    return added
end

function Queue:Remove(index)
    if ns.db and ns.db.queue[index] then
        table.remove(ns.db.queue, index)
    end
end

function Queue:Clear(statusFilter)
    if not ns.db then return end
    if statusFilter then
        for i = #ns.db.queue, 1, -1 do
            if ns.db.queue[i].status == statusFilter then
                table.remove(ns.db.queue, i)
            end
        end
    else
        wipe(ns.db.queue)
    end
end

function Queue:GetPendingCount()
    local count = 0
    if ns.db then
        for _, item in ipairs(ns.db.queue) do
            if item.status == "pending" then
                count = count + 1
            end
        end
    end
    return count
end

--------------------------
-- Log Operations
--------------------------

-- Move a queue item to the completed log
function Queue:MoveToLog(queueIndex, postedPrice)
    if not ns.db then return end
    local item = ns.db.queue[queueIndex]
    if not item then return end

    table.insert(ns.db.log, {
        itemKey       = item.itemKey,
        itemID        = item.itemID,
        name          = item.name,
        quality       = item.quality,
        icon          = nil, -- populated by scanner if available
        targetRealm   = item.targetRealm,
        expectedPrice = item.expectedPrice,
        postedPrice   = postedPrice or item.expectedPrice,
        postedAt      = time(),
        charKey       = ns:GetCharKey(),
        soldAt        = nil,
        soldPrice     = nil,
    })

    table.remove(ns.db.queue, queueIndex)
end

-- Mark posted and move to log (replaces old MarkPosted)
function Queue:MarkPosted(index)
    if ns.db and ns.db.queue[index] then
        self:MoveToLog(index)
    end
end

function Queue:ClearLog()
    if ns.db then
        wipe(ns.db.log)
    end
end

--------------------------
-- Inventory Matching
--------------------------

function Queue:FindItemLocations(itemKey)
    if not ns.db then return {} end

    local locations = {}

    for charKey, charData in pairs(ns.db.inventory) do
        if charData.items then
            for key, itemData in pairs(charData.items) do
                if key == itemKey then
                    table.insert(locations, {
                        charKey   = charKey,
                        class     = charData.class,
                        quantity  = itemData.quantity,
                        locations = itemData.locations,
                        lastScan  = charData.lastScan,
                    })
                end
            end
        end
    end

    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            if key == itemKey then
                table.insert(locations, {
                    charKey   = "Warbank",
                    quantity  = itemData.quantity,
                    locations = {warbank = itemData.quantity},
                    lastScan  = ns.db.warbank.lastScan,
                })
            end
        end
    end

    return locations
end

function Queue:FindItemByName(itemName)
    if not ns.db or not itemName then return {} end
    itemName = itemName:lower()

    local locations = {}

    for charKey, charData in pairs(ns.db.inventory) do
        if charData.items then
            for key, itemData in pairs(charData.items) do
                if itemData.name and itemData.name:lower():find(itemName, 1, true) then
                    table.insert(locations, {
                        charKey   = charKey,
                        class     = charData.class,
                        itemKey   = key,
                        name      = itemData.name,
                        quantity  = itemData.quantity,
                        locations = itemData.locations,
                    })
                end
            end
        end
    end

    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            if itemData.name and itemData.name:lower():find(itemName, 1, true) then
                table.insert(locations, {
                    charKey   = "Warbank",
                    itemKey   = key,
                    name      = itemData.name,
                    quantity  = itemData.quantity,
                    locations = {warbank = itemData.quantity},
                })
            end
        end
    end

    return locations
end

--------------------------
-- Character Task Matching
--------------------------

function Queue:GetCharacterTasks(charKey)
    if not ns.db then return {} end

    local tasks = {}
    local charData = ns.db.inventory[charKey]

    for i, queueItem in ipairs(ns.db.queue) do
        if queueItem.status == "pending" then
            local found = false

            if charData and charData.items then
                for itemKey, itemData in pairs(charData.items) do
                    if itemKey == queueItem.itemKey then
                        table.insert(tasks, {
                            queueIndex = i,
                            queueItem  = queueItem,
                            source     = "character",
                            charKey    = charKey,
                            quantity   = itemData.quantity,
                            locations  = itemData.locations,
                            icon       = itemData.icon,
                        })
                        found = true
                        break
                    end
                end
            end

            if not found and charData and charData.items and queueItem.name ~= "" then
                for itemKey, itemData in pairs(charData.items) do
                    if itemData.name and itemData.name:lower() == queueItem.name:lower() then
                        table.insert(tasks, {
                            queueIndex = i,
                            queueItem  = queueItem,
                            source     = "character",
                            charKey    = charKey,
                            quantity   = itemData.quantity,
                            locations  = itemData.locations,
                            icon       = itemData.icon,
                            fuzzyMatch = true,
                        })
                        found = true
                        break
                    end
                end
            end

            if not found and ns.db.warbank and ns.db.warbank.items then
                for itemKey, itemData in pairs(ns.db.warbank.items) do
                    if itemKey == queueItem.itemKey or
                       (itemData.name and queueItem.name ~= "" and
                        itemData.name:lower() == queueItem.name:lower()) then
                        table.insert(tasks, {
                            queueIndex = i,
                            queueItem  = queueItem,
                            source     = "warbank",
                            quantity   = itemData.quantity,
                            locations  = {warbank = itemData.quantity},
                            icon       = itemData.icon,
                        })
                        break
                    end
                end
            end
        end
    end

    return tasks
end

function Queue:GetCharacterSummary()
    if not ns.db then return {} end

    local summary = {}

    for charKey, charData in pairs(ns.db.inventory) do
        local tasks = self:GetCharacterTasks(charKey)
        if #tasks > 0 then
            table.insert(summary, {
                charKey   = charKey,
                class     = charData.class,
                taskCount = #tasks,
                lastScan  = charData.lastScan,
            })
        end
    end

    table.sort(summary, function(a, b) return a.taskCount > b.taskCount end)

    return summary
end

--------------------------
-- Do Not Track
--------------------------

function Queue:IsDoNotTrack(itemID)
    if not ns.db then return false end
    return ns.db.doNotTrack[tostring(itemID)] == true
end

function Queue:AddDoNotTrack(itemID, itemName)
    if not ns.db then return end
    ns.db.doNotTrack[tostring(itemID)] = itemName or true
end

function Queue:RemoveDoNotTrack(itemID)
    if not ns.db then return end
    ns.db.doNotTrack[tostring(itemID)] = nil
end
