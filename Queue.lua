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
function Queue:MoveToLog(queueIndex, postedPrice, expirySeconds)
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
        expiresAt     = expirySeconds and (time() + expirySeconds) or nil,
        auctionStatus = "active",
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

-- Skip a queue item (price too low, etc.) — hides from Post Now for 24h
function Queue:Skip(index)
    if ns.db and ns.db.queue[index] then
        ns.db.queue[index].status = "skipped"
        ns.db.queue[index].skippedAt = time()
    end
end

-- Unskip a queue item — returns to pending
function Queue:Unskip(index)
    if ns.db and ns.db.queue[index] and ns.db.queue[index].status == "skipped" then
        ns.db.queue[index].status = "pending"
        ns.db.queue[index].skippedAt = nil
    end
end

-- Auto-unskip items that have been skipped for more than 24h
function Queue:UnskipExpired()
    if not ns.db then return end
    local now = time()
    for _, item in ipairs(ns.db.queue) do
        if item.status == "skipped" and item.skippedAt then
            if now - item.skippedAt > 86400 then
                item.status = "pending"
                item.skippedAt = nil
            end
        end
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

function Queue:FindItemLocations(itemKey, itemName)
    if not ns.db then return {} end

    local locations = {}
    -- Try to resolve numeric ID for cross-format matching
    local resolvedID
    local numID = tonumber(itemKey and itemKey:match("^(%d+);"))
    if numID and numID > 0 then
        resolvedID = numID
    elseif itemName and itemName ~= "" then
        -- Look up by name to get numeric ID
        resolvedID = ns:ResolveItemID({itemID = "", name = itemName})
    end

    for charKey, charData in pairs(ns.db.inventory) do
        if charData.items then
            for key, itemData in pairs(charData.items) do
                local matched = (key == itemKey)
                -- Also try numeric ID match
                if not matched and resolvedID then
                    local invNumID = tonumber(key:match("^(%d+);"))
                    if invNumID and invNumID == resolvedID then matched = true end
                end
                if matched then
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
            local matched = (key == itemKey)
            if not matched and resolvedID then
                local invNumID = tonumber(key:match("^(%d+);"))
                if invNumID and invNumID == resolvedID then matched = true end
            end
            if matched then
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

-- Match a queue item against an inventory item by key, ID, or name
local function InventoryMatchesQueue(invKey, invData, queueItem, resolvedID)
    -- Exact key match
    if invKey == queueItem.itemKey then return true, false end

    -- Numeric ID match: extract ID from inventory key, compare with queue item's resolved ID
    if resolvedID then
        local invNumID = tonumber(invKey:match("^(%d+);"))
        if invNumID and invNumID == resolvedID then return true, false end
    end

    -- Exact name match
    if invData.name and queueItem.name ~= "" then
        if invData.name:lower() == queueItem.name:lower() then
            return true, true
        end
        -- Fuzzy name match (substring, min 8 chars)
        if #queueItem.name >= 8 then
            local iName = invData.name:lower()
            local qName = queueItem.name:lower()
            if iName:find(qName, 1, true) or qName:find(iName, 1, true) then
                return true, true
            end
        end
    end

    return false, false
end

function Queue:GetCharacterTasks(charKey)
    if not ns.db then return {} end

    local tasks = {}
    local charData = ns.db.inventory[charKey]

    -- Track remaining quantity per inventory key so one physical item
    -- can only satisfy as many queue items as its actual quantity
    local remainingQty = {}

    for i, queueItem in ipairs(ns.db.queue) do
        if queueItem.status == "pending" then
            local found = false
            local resolvedID = ns:ResolveItemID(queueItem)

            if charData and charData.items then
                for itemKey, itemData in pairs(charData.items) do
                    if remainingQty[itemKey] == nil then
                        remainingQty[itemKey] = itemData.quantity or 1
                    end
                    if remainingQty[itemKey] > 0 then
                        local matched, fuzzy = InventoryMatchesQueue(itemKey, itemData, queueItem, resolvedID)
                        if matched then
                            remainingQty[itemKey] = remainingQty[itemKey] - (queueItem.quantity or 1)
                            table.insert(tasks, {
                                queueIndex = i,
                                queueItem  = queueItem,
                                source     = "character",
                                charKey    = charKey,
                                quantity   = itemData.quantity,
                                locations  = itemData.locations,
                                icon       = itemData.icon,
                                fuzzyMatch = fuzzy,
                            })
                            found = true
                            break
                        end
                    end
                end
            end

            if not found and ns.db.warbank and ns.db.warbank.items then
                for itemKey, itemData in pairs(ns.db.warbank.items) do
                    local wbKey = "wb:" .. itemKey
                    if remainingQty[wbKey] == nil then
                        remainingQty[wbKey] = itemData.quantity or 1
                    end
                    if remainingQty[wbKey] > 0 then
                        local matched, fuzzy = InventoryMatchesQueue(itemKey, itemData, queueItem, resolvedID)
                        if matched then
                            remainingQty[wbKey] = remainingQty[wbKey] - (queueItem.quantity or 1)
                            table.insert(tasks, {
                                queueIndex = i,
                                queueItem  = queueItem,
                                source     = "warbank",
                                quantity   = itemData.quantity,
                                locations  = {warbank = itemData.quantity},
                                icon       = itemData.icon,
                                fuzzyMatch = fuzzy,
                            })
                            break
                        end
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
