-- TodoGenerator.lua
-- To-Do list generation: item pool building, deal allocation, assignment optimization
local addonName, ns = ...

local TodoList = ns.TodoList

--------------------------
-- Item Pool
--------------------------

-- Build a unified pool of all tradeable items across characters and warbank.
-- Returns: array of pool items, each with:
--   itemKey, itemID, name, icon, sources (array), totalQuantity
-- Each source: { source = charKey|"Warbank", location = bags|bank|reagent|warbank, quantity }
function TodoList:BuildItemPool()
    if not ns.db then return {} end

    local pool = {}
    local keyIndex = {} -- itemKey -> pool array index

    local function AddToPool(itemKey, itemData, source, location, quantity)
        if quantity <= 0 then return end

        local idx = keyIndex[itemKey]
        if not idx then
            idx = #pool + 1
            pool[idx] = {
                itemKey       = itemKey,
                itemID        = itemData.itemID or itemKey:match("^(%d+)"),
                name          = itemData.name or "Unknown",
                icon          = itemData.icon,
                sources       = {},
                totalQuantity = 0,
            }
            keyIndex[itemKey] = idx
        end

        table.insert(pool[idx].sources, {
            source   = source,
            location = location,
            quantity = quantity,
        })
        pool[idx].totalQuantity = pool[idx].totalQuantity + quantity

        if itemData.icon and not pool[idx].icon then
            pool[idx].icon = itemData.icon
        end
        if itemData.name and pool[idx].name == "Unknown" then
            pool[idx].name = itemData.name
        end
    end

    -- Character inventories
    for charKey, charData in pairs(ns.db.characters or {}) do
        if charData.inventory and charData.inventory.items then
            for itemKey, itemData in pairs(charData.inventory.items) do
                local numID = tonumber(itemData.itemID)
                local isDNT = numID and ns:IsDoNotTrack(numID)
                local tradeable = not itemData.isBound
                    and (not itemData.bindType or itemData.bindType ~= 1)

                if not isDNT and tradeable then
                    if itemData.locations then
                        for loc, qty in pairs(itemData.locations) do
                            AddToPool(itemKey, itemData, charKey, loc, qty)
                        end
                    elseif (itemData.quantity or 0) > 0 then
                        AddToPool(itemKey, itemData, charKey, "bags", itemData.quantity)
                    end
                end
            end
        end
    end

    -- Warbank
    if ns.db.warbank and ns.db.warbank.items then
        for itemKey, itemData in pairs(ns.db.warbank.items) do
            local numID = tonumber(itemData.itemID)
            local isDNT = numID and ns:IsDoNotTrack(numID)
            if not isDNT and (itemData.quantity or 0) > 0 then
                AddToPool(itemKey, itemData, "Warbank", "warbank", itemData.quantity)
            end
        end
    end

    -- Guild bank(s) — disabled: Blizzard API returns unreliable item data
    -- (stripped bonus IDs, wrong ilvl, pets show as "Pet Cage")
    -- Re-enable when API is fixed.
    -- if ns.db.guilds then
    --     for guildName, guildData in pairs(ns.db.guilds) do
    --         if guildData.enabled and guildData.items then
    --             for itemKey, itemData in pairs(guildData.items) do
    --                 AddToPool(itemKey, itemData, "Guild:" .. guildName, "guildbank", itemData.quantity)
    --             end
    --         end
    --     end
    -- end

    return pool
end

-- Get a filtered view of the item pool based on filter mode.
-- filterMode: "all" | "tsm" | "auctionator"
-- filterValue: TSM group path or Auctionator list name
-- excludedItems: table of itemKey -> true to exclude
-- Returns filtered pool array.
function TodoList:GetFilteredItemPool(filterMode, filterValue, excludedItems)
    local pool = self:BuildItemPool()
    if not filterMode or filterMode == "all" then
        if not excludedItems or not next(excludedItems) then
            return pool
        end
        -- Just apply exclusions
        local filtered = {}
        for _, item in ipairs(pool) do
            if not excludedItems[item.itemKey] then
                table.insert(filtered, item)
            end
        end
        return filtered
    end

    local filtered = {}

    if filterMode == "tsm" and ns.TSM and ns.TSM:IsEnabled() then
        local profile = ns.TSM:GetSelectedProfile()
        if profile then
            -- Items DB: tsmItemString -> groupPath (e.g., ["i:12345"] = "Crafts`Enchanting")
            local itemsDB = ns.TSM:GetItemsDB(profile)

            -- Build a reverse lookup: base item ID -> groupPath for fast matching
            local itemToGroup = {}      -- full TSM string -> groupPath
            local baseToGroup = {}      -- "i:12345" -> groupPath
            if itemsDB then
                for tsmStr, groupPath in pairs(itemsDB) do
                    if type(tsmStr) == "string" and type(groupPath) == "string" then
                        itemToGroup[tsmStr] = groupPath
                        local base = tsmStr:match("^(i:%d+)") or tsmStr:match("^(p:%d+)")
                        if base then
                            baseToGroup[base] = groupPath
                        end
                    end
                end
            end

            for _, item in ipairs(pool) do
                if not (excludedItems and excludedItems[item.itemKey]) then
                    -- Find this pool item's TSM group path
                    local tsmStr = ns.TSM:ItemKeyToTSMString(item.itemKey)
                    local baseID = item.itemKey and item.itemKey:match("^(%d+)")
                    local baseStr = baseID and ("i:" .. baseID)

                    local groupPath = (tsmStr and itemToGroup[tsmStr])
                        or (baseStr and itemToGroup[baseStr])
                        or (tsmStr and baseToGroup[tsmStr])
                        or (baseStr and baseToGroup[baseStr])

                    if groupPath then
                        if not filterValue or filterValue == "" then
                            -- No group selected — show all items in any TSM group
                            table.insert(filtered, item)
                        elseif groupPath == filterValue
                            or groupPath:find(filterValue .. "`", 1, true) == 1 then
                            -- Item is in the selected group or a child group
                            table.insert(filtered, item)
                        end
                    end
                end
            end
        end
    elseif filterMode == "auctionator" then
        -- Get items from Auctionator shopping list
        local listItems = {}

        -- Helper: extract item name from Auctionator search string
        -- Format: "Name;;;...;;" or '"Quoted Name";;;...;;'
        local function AddSearchTermName(searchTerm)
            if not searchTerm or searchTerm == "" then return end
            local name = searchTerm:match('^"([^"]+)"') or searchTerm:match("^([^;]+)")
            if name and name ~= "" then
                listItems[strtrim(name):lower()] = true
            end
        end

        -- Method 1: Read directly from AUCTIONATOR_SHOPPING_LISTS SavedVariable
        if type(AUCTIONATOR_SHOPPING_LISTS) == "table" then
            for _, list in ipairs(AUCTIONATOR_SHOPPING_LISTS) do
                if type(list) == "table" and list.name == filterValue and list.items then
                    for _, searchTerm in ipairs(list.items) do
                        AddSearchTermName(searchTerm)
                    end
                    break
                end
            end
        end

        -- Method 2: Auctionator API fallback
        if not next(listItems) and type(Auctionator) == "table"
            and Auctionator.API and Auctionator.API.v1
            and Auctionator.API.v1.GetShoppingListItems then
            local ok, items = pcall(Auctionator.API.v1.GetShoppingListItems, "FlipQueue", filterValue)
            if ok and items then
                for _, searchTerm in ipairs(items) do
                    AddSearchTermName(searchTerm)
                end
            end
        end

        for _, item in ipairs(pool) do
            if not (excludedItems and excludedItems[item.itemKey]) then
                if listItems[item.name:lower()] then
                    table.insert(filtered, item)
                end
            end
        end
    end

    return filtered
end

--------------------------
-- Generator Helpers
--------------------------

-- Find pool item matching a deal. Returns pool index or nil.
local function FindPoolMatch(pool, deal, poolRemaining)
    local resolvedID = ns:ResolveItemID(deal)

    for idx, poolItem in ipairs(pool) do
        if poolRemaining[idx] > 0 then
            local matched = ns:ItemsMatch(
                poolItem.itemKey, poolItem.name, deal, resolvedID or false)
            if matched then
                return idx
            end
        end
    end
    return nil
end

-- Find best character + source to post an item on a target realm.
-- Returns { charKey, location, quantity } or nil.
local function FindBestAssignment(poolItem, targetRealm, inventory)
    if not targetRealm or targetRealm == "" then return nil end

    local PRIORITY = { bags = 1, reagent = 2, bank = 3, warbank = 4, guildbank = 5 }

    -- Characters on the target realm
    local realmChars = {}
    for charKey in pairs(inventory or {}) do
        local charRealm = charKey:match("%-(.+)$")
        if charRealm and ns:RealmMatches(targetRealm, charRealm) then
            table.insert(realmChars, charKey)
        end
    end

    if #realmChars == 0 then return nil end
    table.sort(realmChars) -- deterministic ordering

    -- Collect candidates
    local candidates = {}
    for _, src in ipairs(poolItem.sources) do
        if src.quantity > 0 then
            if src.source == "Warbank" then
                table.insert(candidates, {
                    charKey  = realmChars[1],
                    location = "warbank",
                    quantity = src.quantity,
                    priority = PRIORITY.warbank,
                })
            elseif src.location == "guildbank" then
                table.insert(candidates, {
                    charKey  = realmChars[1],
                    location = "guildbank",
                    quantity = src.quantity,
                    priority = PRIORITY.guildbank,
                })
            else
                for _, charKey in ipairs(realmChars) do
                    if src.source == charKey then
                        table.insert(candidates, {
                            charKey  = charKey,
                            location = src.location,
                            quantity = src.quantity,
                            priority = PRIORITY[src.location] or 99,
                        })
                        break
                    end
                end
            end
        end
    end

    if #candidates == 0 then
        -- Characters exist on realm but item not in accessible inventory
        -- Find which characters actually hold this item (for deposit prompts)
        local depositSources = {}
        for _, src in ipairs(poolItem.sources) do
            if src.quantity > 0 and src.source ~= "Warbank" then
                table.insert(depositSources, {
                    charKey  = src.source,
                    location = src.location,
                    quantity = src.quantity,
                })
            end
        end
        return { charKey = realmChars[1], location = nil, quantity = 0, depositSources = depositSources }
    end

    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.charKey < b.charKey
    end)

    return candidates[1]
end

-- Multi-key comparator: compares two items using an ordered list of criteria.
-- Each criterion is compared; if equal, falls through to the next.
-- Returns true if a should come before b (descending for value-based, ascending for name-based).
local function CompareByKeys(a, b, keys)
    for _, key in ipairs(keys) do
        if key == "gold" then
            local ag = ns:ParseGoldValue(a.expectedPrice or "")
            local bg = ns:ParseGoldValue(b.expectedPrice or "")
            if ag ~= bg then return ag > bg end
        elseif key == "noCompetition" then
            local ac = a.noCompetition and 1 or 0
            local bc = b.noCompetition and 1 or 0
            if ac ~= bc then return ac > bc end
        elseif key == "population" then
            -- Use sellRate as proxy for realm demand (higher = better)
            local as = tonumber(a.sellRate) or 0
            local bs = tonumber(b.sellRate) or 0
            if as ~= bs then return as > bs end
        elseif key == "character" then
            local ac = a.assignedChar or ""
            local bc = b.assignedChar or ""
            if ac ~= bc then return ac < bc end
        elseif key == "tasks" then
            -- Sort by number of tasks per character (fewest first = spread load)
            local at = a._charTaskCount or 0
            local bt = b._charTaskCount or 0
            if at ~= bt then return at < bt end
        end
    end
    -- Final tiebreaker: alphabetical by name
    return (a.name or "") < (b.name or "")
end

-- Sort deals for allocation priority (which deal gets inventory first when pool is limited)
local function SortDealsForAllocation(deals, allocationOrder)
    if not allocationOrder or #allocationOrder == 0 then
        allocationOrder = {"gold"}
    end
    table.sort(deals, function(a, b)
        return CompareByKeys(a, b, allocationOrder)
    end)
end

-- Build grouped display data from generated items.
-- Groups items by assignedChar (each char implies a realm).
-- sortMode: "profit" | "character" | "realm" | "noCompetition"
-- Returns array of groups: { charKey, realm, charName, totalGold, hasNoCompetition, items = {...} }
-- sorted by the chosen sort mode.
function TodoList:BuildDisplayGroups(items, sortMode)
    if not items then return {} end
    sortMode = sortMode or "profit"

    -- Group by assignedChar. Only pending/unassigned items are actionable.
    -- Posted, skipped, and missing items are excluded from display groups.
    local byChar = {}
    local charOrder = {}
    local skippedMissing = 0
    for _, item in ipairs(items) do
        local key
        if item.status == "pending" and item.assignedChar then
            key = item.assignedChar
        elseif item.status == "unassigned" then
            key = "_realm:" .. ns:NormalizeRealmKey(item.targetRealm or "")
        elseif item.status == "missing" then
            skippedMissing = skippedMissing + 1
            key = nil
        else
            -- posted, skipped — done, skip entirely
            key = nil
        end

        if key then
            if not byChar[key] then
                local isRealmGroup = key:find("^_realm:")
                byChar[key] = {
                    charKey = item.assignedChar,  -- nil for realm groups
                    realm = item.targetRealm or "",
                    charName = item.assignedChar and (item.assignedChar:match("^(.-)%-") or item.assignedChar) or nil,
                    totalGold = 0,
                    hasNoCompetition = false,
                    items = {},
                }
                table.insert(charOrder, key)
            end
            local group = byChar[key]
            table.insert(group.items, item)
            group.totalGold = group.totalGold + ns:ParseGoldValue(item.expectedPrice or "")
            if item.noCompetition then
                group.hasNoCompetition = true
            end
        end
    end

    local groups = {}
    for _, key in ipairs(charOrder) do
        table.insert(groups, byChar[key])
    end

    -- Pre-compute deferred status: groups where ALL items have been deferred
    -- (checked on login but no inventory found) sort lower
    for _, group in ipairs(groups) do
        local allDeferred = #group.items > 0
        for _, item in ipairs(group.items) do
            if not item.deferredAt then
                allDeferred = false
                break
            end
        end
        group._allDeferred = allDeferred
    end

    -- Sort groups by the chosen mode.
    -- Tiers: assigned+active > assigned+deferred > unassigned
    table.sort(groups, function(a, b)
        -- Unassigned always last
        local aAssigned = a.charKey and 1 or 0
        local bAssigned = b.charKey and 1 or 0
        if aAssigned ~= bAssigned then return aAssigned > bAssigned end

        -- Fully deferred groups (no inventory) sort below active groups
        if a._allDeferred ~= b._allDeferred then return not a._allDeferred end

        if sortMode == "profit" then
            return a.totalGold > b.totalGold
        elseif sortMode == "character" then
            return (a.charName or ""):lower() < (b.charName or ""):lower()
        elseif sortMode == "realm" then
            local ar = ns:NormalizeRealmKey(a.realm)
            local br = ns:NormalizeRealmKey(b.realm)
            if ar ~= br then return ar < br end
            return (a.charName or ""):lower() < (b.charName or ""):lower()
        elseif sortMode == "noCompetition" then
            local ac = a.hasNoCompetition and 1 or 0
            local bc = b.hasNoCompetition and 1 or 0
            if ac ~= bc then return ac > bc end
            return a.totalGold > b.totalGold
        end
        return a.totalGold > b.totalGold
    end)

    -- Sort items within each group by gold desc
    for _, group in ipairs(groups) do
        table.sort(group.items, function(a, b)
            return ns:ParseGoldValue(a.expectedPrice or "") > ns:ParseGoldValue(b.expectedPrice or "")
        end)
    end

    return groups, skippedMissing
end

--------------------------
-- Generator
--------------------------

-- Generate a to-do list by matching deals (import entries) against the item pool.
-- source: import source key (e.g., "fpScanner"); defaults to "fpScanner"
-- allocationOrder: ordered array of criteria for deal priority (e.g., {"gold", "noCompetition"})
-- Returns a preview list: { name, createdAt, source, items = { ... } }
-- Call CommitList() to save the preview.
-- Use BuildDisplayGroups() on the result for grouped display.
function TodoList:GenerateTodoList(source, allocationOrder)
    -- Handle backward compat: if source is a table, it's actually allocationOrder (old call style)
    if type(source) == "table" then
        allocationOrder = source
        source = "fpScanner"
    end
    source = source or "fpScanner"

    if type(allocationOrder) == "string" then
        -- Backward compat: single string -> array
        allocationOrder = {allocationOrder}
    end
    allocationOrder = allocationOrder or {"gold"}

    local pool = self:BuildItemPool()

    -- Collect deals from import source
    local deals = {}
    for importKey, deal in pairs(ns.db.imports[source] or {}) do
        deal._importKey = importKey
        deal._importSource = source
        table.insert(deals, deal)
    end

    local preview = {
        name      = "Generated " .. date("%Y-%m-%d %H:%M"),
        createdAt = time(),
        source    = source,
        items     = {},
    }

    if #deals == 0 then return preview end

    -- Sort deals by allocation priority so high-priority deals get inventory first
    SortDealsForAllocation(deals, allocationOrder)

    -- Track remaining pool quantities
    local poolRemaining = {}
    for i, p in ipairs(pool) do
        poolRemaining[i] = p.totalQuantity
    end

    local sellQtyMode = ns.db.settings.sellQtyMode or "tsm"
    local tsmEnabled = sellQtyMode == "tsm" and ns.TSM and ns.TSM.IsEnabled and ns.TSM:IsEnabled()
    local defaultQty = ns.db.settings.defaultSellQty or 1

    for _, deal in ipairs(deals) do
        local poolIdx = FindPoolMatch(pool, deal, poolRemaining)

        if poolIdx then
            local poolItem = pool[poolIdx]
            local assignment = FindBestAssignment(
                poolItem, deal.targetRealm, ns.db.characters)

            if assignment and assignment.location then
                -- Post quantity: defaultSellQty as base, TSM postCap overrides
                local qty = math.max(deal.quantity or 1, defaultQty)
                if tsmEnabled then
                    -- Try pool item key first, then deal key as fallback
                    local op
                    local ok1, res1 = pcall(function()
                        return ns.TSM:GetItemAuctioningOp(poolItem.itemKey)
                    end)
                    if ok1 and res1 then
                        op = res1
                    elseif deal.itemKey and deal.itemKey ~= poolItem.itemKey then
                        local ok2, res2 = pcall(function()
                            return ns.TSM:GetItemAuctioningOp(deal.itemKey)
                        end)
                        if ok2 and res2 then op = res2 end
                    end
                    if op and op.postCap then
                        local cap = tonumber(op.postCap)
                        if cap and cap > 0 then qty = cap end
                    end
                end
                qty = math.min(qty, poolRemaining[poolIdx])

                if qty > 0 then
                    -- Check TSM threshold — skip items TSM would reject
                    local itemStatus = "pending"
                    local failReason = nil
                    if tsmEnabled then
                        local belowThreshold, ahMin, threshold, opName = ns.TSM:IsBelowThreshold(poolItem.itemKey)
                        if not belowThreshold and deal.itemKey ~= poolItem.itemKey then
                            belowThreshold = ns.TSM:IsBelowThreshold(deal.itemKey)
                        end
                        if belowThreshold then
                            itemStatus = "skipped"
                            local threshStr = threshold and ns.TSM:FormatCopper(threshold) or "?"
                            failReason = "TSM: below min price (" .. threshStr .. ")" .. (opName and (" [" .. opName .. "]") or "")
                        end
                    end

                    table.insert(preview.items, {
                        itemKey       = poolItem.itemKey,
                        itemID        = poolItem.itemID,
                        name          = poolItem.name,
                        icon          = poolItem.icon,
                        targetRealm   = deal.targetRealm,
                        expectedPrice = deal.expectedPrice,
                        quantity      = qty,
                        assignedChar  = assignment.charKey,
                        status        = itemStatus,
                        failReason    = failReason,
                        source        = assignment.location,
                        quality       = deal.quality,
                        sellRate      = deal.sellRate,
                        noCompetition = deal.noCompetition,
                        category      = deal.category,
                        attempts      = 0,
                        importSource  = source,
                        importKey     = deal._importKey,
                        steps = (function()
                            local s = {}
                            if assignment.location == "bank" or assignment.location == "warbank" or assignment.location == "guildbank" then
                                table.insert(s, { type = "retrieve", from = assignment.location, status = "pending" })
                            end
                            table.insert(s, { type = "post", status = "pending" })
                            table.insert(s, { type = "collect", status = "pending" })
                            return s
                        end)(),
                        currentStep = 1,
                    })
                    poolRemaining[poolIdx] = poolRemaining[poolIdx] - qty
                end
            elseif assignment then
                -- Character exists on realm but item not in their bags/bank/warbank
                -- Assign to the character so it groups under "Log in", not "Create char"
                -- Don't consume pool — item needs to be moved to warbank first
                local depositFrom, depositLocation
                if assignment.depositSources and #assignment.depositSources > 0 then
                    depositFrom = assignment.depositSources[1].charKey
                    depositLocation = assignment.depositSources[1].location
                end
                table.insert(preview.items, {
                    itemKey         = poolItem.itemKey,
                    itemID          = poolItem.itemID,
                    name            = poolItem.name,
                    icon            = poolItem.icon,
                    targetRealm     = deal.targetRealm,
                    expectedPrice   = deal.expectedPrice,
                    quantity        = math.max(deal.quantity or 1, defaultQty),
                    assignedChar    = assignment.charKey,
                    status          = "pending",
                    source          = "unavailable",
                    depositFrom     = depositFrom,
                    depositLocation = depositLocation,
                    blockedBy       = depositFrom,
                    quality         = deal.quality,
                    sellRate        = deal.sellRate,
                    noCompetition   = deal.noCompetition,
                    category        = deal.category,
                    attempts        = 0,
                    importSource    = source,
                    importKey       = deal._importKey,
                    steps = (function()
                        local s = {}
                        table.insert(s, { type = "retrieve", from = "warbank", status = "pending" })
                        table.insert(s, { type = "post", status = "pending" })
                        table.insert(s, { type = "collect", status = "pending" })
                        return s
                    end)(),
                    currentStep = 1,
                })
            else
                -- No character on target realm at all
                table.insert(preview.items, {
                    itemKey       = poolItem.itemKey,
                    itemID        = poolItem.itemID,
                    name          = poolItem.name,
                    icon          = poolItem.icon,
                    targetRealm   = deal.targetRealm,
                    expectedPrice = deal.expectedPrice,
                    quantity      = math.max(deal.quantity or 1, defaultQty),
                    assignedChar  = nil,
                    status        = "unassigned",
                    source        = nil,
                    quality       = deal.quality,
                    sellRate      = deal.sellRate,
                    noCompetition = deal.noCompetition,
                    category      = deal.category,
                    attempts      = 0,
                    importSource  = source,
                    importKey     = deal._importKey,
                    steps         = {},
                    currentStep   = 1,
                })
            end
        else
            -- No pool match — item not in inventory
            table.insert(preview.items, {
                itemKey       = deal.itemKey,
                itemID        = deal.itemID,
                name          = deal.name,
                icon          = deal.icon,
                targetRealm   = deal.targetRealm,
                expectedPrice = deal.expectedPrice,
                quantity      = math.max(deal.quantity or 1, defaultQty),
                assignedChar  = nil,
                status        = "missing",
                source        = nil,
                quality       = deal.quality,
                sellRate      = deal.sellRate,
                noCompetition = deal.noCompetition,
                category      = deal.category,
                attempts      = 0,
                importSource  = source,
                importKey     = deal._importKey,
                steps         = {},
                currentStep   = 1,
            })
        end
    end

    -- Items are not pre-sorted here — the UI calls BuildDisplayGroups() for grouped display
    return preview
end
