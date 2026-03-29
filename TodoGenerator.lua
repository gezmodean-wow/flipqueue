-- TodoGenerator.lua
-- To-Do list generation: item pool building, deal allocation, assignment optimization
local addonName, ns = ...

local TodoList = ns.TodoList

--------------------------
-- Import Type Labels
--------------------------

local IMPORT_TYPE_LABELS = {
    fpScanner    = "Inventory Scan",
    fpCrossRealm = "Cross-Realm Flip",
    tsm          = "TSM Import",
    auctionator  = "Auctionator Import",
}

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

    -- Character inventories (skip hidden characters)
    for charKey, charData in pairs(ns.db.characters or {}) do
        if (charData.role or "both") ~= "none" and charData.inventory and charData.inventory.items then
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

-- Get sorted array of unique realm names from known characters (skip ignored).
-- Uses NormalizeRealmKey for dedup so accent variants collapse.
function TodoList:GetKnownRealms()
    if not ns.db or not ns.db.characters then return {} end

    local seen = {}  -- normalizedRealm -> displayRealm
    for charKey, charData in pairs(ns.db.characters) do
        if (charData.role or "both") ~= "none" then
            local realm = charKey:match("%-(.+)$")
            if realm and realm ~= "" then
                local normalized = ns:NormalizeRealmKey(realm)
                if not seen[normalized] then
                    seen[normalized] = realm
                end
            end
        end
    end

    local realms = {}
    for _, realm in pairs(seen) do
        table.insert(realms, realm)
    end
    table.sort(realms)
    return realms
end

-- Filter deals to only those targeting allowed realms.
-- allowedRealms: table of { realmName = true }.
-- Matches deal.targetRealm or deal.buyRealm against allowed realms using RealmMatches.
function TodoList:FilterDealsByRealm(deals, allowedRealms)
    if not deals or not allowedRealms or not next(allowedRealms) then return deals end

    local filtered = {}
    for _, deal in ipairs(deals) do
        local matched = false
        for realm in pairs(allowedRealms) do
            if ns:RealmMatches(deal.targetRealm, realm)
                or (deal.buyRealm and ns:RealmMatches(deal.buyRealm, realm)) then
                matched = true
                break
            end
        end
        if matched then
            table.insert(filtered, deal)
        end
    end
    return filtered
end

-- Count total units of a deal's item across all character inventories and warbank.
-- Returns integer count. Used to set deal._inventoryCount before sorting.
function TodoList:CountInventoryForDeal(deal)
    if not ns.db then return 0 end

    local count = 0
    local resolvedID = ns:ResolveItemID(deal)

    -- Character inventories
    for charKey, charData in pairs(ns.db.characters or {}) do
        if (charData.role or "both") ~= "none" and charData.inventory and charData.inventory.items then
            for key, itemData in pairs(charData.inventory.items) do
                local matched = ns:ItemsMatch(key, itemData.name, deal, resolvedID or false)
                if matched then
                    count = count + (itemData.quantity or 0)
                end
            end
        end
    end

    -- Warbank
    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            local matched = ns:ItemsMatch(key, itemData.name, deal, resolvedID or false)
            if matched then
                count = count + (itemData.quantity or 0)
            end
        end
    end

    return count
end

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

    -- Characters on the target realm with sell capability
    local realmChars = {}
    for charKey, charData in pairs(inventory or {}) do
        local charRealm = charKey:match("%-(.+)$")
        if charRealm and ns:RealmMatches(targetRealm, charRealm) then
            local role = type(charData) == "table" and (charData.role or "both") or "both"
            if role == "both" or role == "sell" then
                table.insert(realmChars, charKey)
            end
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
        elseif key == "profit" then
            -- Like "gold" but prefers profitAmount when available (cross-realm deals)
            local ag = ns:ParseGoldValue(a.profitAmount or "") or 0
            if ag == 0 then ag = ns:ParseGoldValue(a.expectedPrice or "") end
            local bg = ns:ParseGoldValue(b.profitAmount or "") or 0
            if bg == 0 then bg = ns:ParseGoldValue(b.expectedPrice or "") end
            if ag ~= bg then return ag > bg end
        elseif key == "lowInventory" then
            -- Fewer inventory = higher priority (buy what you don't have)
            local ai = a._inventoryCount or 0
            local bi = b._inventoryCount or 0
            if ai ~= bi then return ai < bi end
        elseif key == "highInventory" then
            -- More inventory = higher priority (sell what you have most of)
            local ai = a._inventoryCount or 0
            local bi = b._inventoryCount or 0
            if ai ~= bi then return ai > bi end
        elseif key == "discount" then
            -- Higher profitPct = higher priority (best deal percentage)
            local ap = tonumber(a.profitPct) or 0
            local bp = tonumber(b.profitPct) or 0
            if ap ~= bp then return ap > bp end
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
    -- Track realm group keys for connected realm merging
    local realmGroupKeys = {} -- array of { key, realm } for existing unassigned groups
    for _, item in ipairs(items) do
        local key
        if item.status == "pending" and item.assignedChar then
            key = item.assignedChar
        elseif item.status == "unassigned" then
            -- Merge connected realms: check if this realm overlaps an existing group
            local itemRealm = item.targetRealm or ""
            local merged = false
            for _, rg in ipairs(realmGroupKeys) do
                if ns:RealmMatches(itemRealm, rg.realm) then
                    key = rg.key
                    -- Keep the longer realm string (more complete cluster name)
                    if #itemRealm > #rg.realm then
                        rg.realm = itemRealm
                        if byChar[key] then byChar[key].realm = itemRealm end
                    end
                    merged = true
                    break
                end
            end
            if not merged then
                key = "_realm:" .. ns:NormalizeRealmKey(itemRealm)
                table.insert(realmGroupKeys, { key = key, realm = itemRealm })
            end
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
                -- For buy tasks, the relevant realm is buyRealm (where player goes to buy)
                local groupRealm = (item.action == "buy" and item.buyRealm) or item.targetRealm or ""
                byChar[key] = {
                    charKey = item.assignedChar,  -- nil for realm groups
                    realm = groupRealm,
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
            if item.action == "buy" then
                group.hasBuyTasks = true
            end
        end
    end

    local groups = {}
    for _, key in ipairs(charOrder) do
        table.insert(groups, byChar[key])
    end

    -- Pre-compute deferred status: groups where ALL items have been deferred
    -- (checked on login but no inventory found) sort lower
    -- Also compute depositor status: characters that need to deposit items
    -- to unblock other characters should sort first (login priority)
    local blockedBySet = {} -- charKey -> count of tasks they unblock
    for _, item in ipairs(items) do
        if item.blockedBy then
            blockedBySet[item.blockedBy] = (blockedBySet[item.blockedBy] or 0) + 1
        end
    end

    for _, group in ipairs(groups) do
        local allDeferred = #group.items > 0
        local allStuck = #group.items > 0  -- all deferred with no blocker (truly unresolvable)
        for _, item in ipairs(group.items) do
            if not item.deferredAt then
                allDeferred = false
                allStuck = false
            elseif item.blockedBy then
                -- Deferred but has a blocker — waiting on a deposit, not stuck
                allStuck = false
            end
        end
        group._allDeferred = allDeferred
        group._allStuck = allStuck  -- no items exist anywhere, nothing actionable
        -- A depositor is a character who holds items that other characters need.
        -- They should log in first to deposit, even if their own tasks are deferred.
        group._unblocksCount = group.charKey and blockedBySet[group.charKey] or 0
        group._isDepositor = group._unblocksCount > 0
        -- A group is "blocked only" if ALL its tasks are deferred and it has no deposit duties
        group._blockedOnly = allDeferred and not group._isDepositor
    end

    -- Remove stuck groups: all tasks deferred, no blocker, no deposit duties.
    -- These characters have nothing actionable — items don't exist anywhere.
    local filteredGroups = {}
    for _, group in ipairs(groups) do
        if not group._allStuck or group._isDepositor then
            table.insert(filteredGroups, group)
        end
    end
    groups = filteredGroups

    -- Sort groups by the chosen mode.
    -- Tiers: depositors > assigned+active > assigned+blocked-only > unassigned
    table.sort(groups, function(a, b)
        -- Unassigned always last
        local aAssigned = a.charKey and 1 or 0
        local bAssigned = b.charKey and 1 or 0
        if aAssigned ~= bAssigned then return aAssigned > bAssigned end

        -- Depositors (characters that unblock others) sort first
        if a._isDepositor ~= b._isDepositor then return a._isDepositor end

        -- Blocked-only groups (all deferred, no deposit duties) sort below active groups
        if a._blockedOnly ~= b._blockedOnly then return not a._blockedOnly end

        if sortMode == "profit" or sortMode == "mostProfitable" then
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
        elseif sortMode == "bestDeal" then
            -- Sort by average profitPct descending
            local function avgProfitPct(group)
                local total, count = 0, 0
                for _, item in ipairs(group.items) do
                    local pct = tonumber(item.profitPct) or 0
                    total = total + pct
                    count = count + 1
                end
                return count > 0 and (total / count) or 0
            end
            local ap = avgProfitPct(a)
            local bp = avgProfitPct(b)
            if ap ~= bp then return ap > bp end
            return a.totalGold > b.totalGold
        elseif sortMode == "prioritizeBuys" then
            -- Buy groups first, then sells
            local ab = a.hasBuyTasks and 1 or 0
            local bb = b.hasBuyTasks and 1 or 0
            if ab ~= bb then return ab > bb end
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
-- opts (optional): table with extended options:
--   opts.buyAllocationOrder — allocation order for buy tasks (cross-realm buys)
--   opts.dealFilter — function(deal) returning true to include, false to skip
--   opts.listMode — "separate" or "integrated" (nil = current behavior)
--   opts.integratedSortMode — "mostProfitable"/"bestDeal"/"prioritizeBuys" (for integrated mode)
-- Returns a preview list: { name, createdAt, source, items = { ... } }
-- When opts.listMode == "separate", returns { buy = buyPreview, sell = sellPreview } instead.
-- Call CommitList() to save the preview.
-- Use BuildDisplayGroups() on the result for grouped display.
function TodoList:GenerateTodoList(source, allocationOrder, opts)
    -- Handle backward compat: if source is a table, it's actually allocationOrder (old call style)
    if type(source) == "table" then
        allocationOrder = source
        source = "fpScanner"
    end
    source = source or "fpScanner"
    opts = opts or {}

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

    -- Apply deal filter if provided
    if opts.dealFilter then
        local filtered = {}
        for _, deal in ipairs(deals) do
            if opts.dealFilter(deal) then
                table.insert(filtered, deal)
            end
        end
        deals = filtered
    end

    local preview = {
        name      = "Generated " .. date("%Y-%m-%d %H:%M"),
        createdAt = time(),
        source    = source,
        importType = IMPORT_TYPE_LABELS[source] or source,
        items     = {},
    }

    if #deals == 0 then
        if opts.listMode == "separate" then
            return { buy = preview, sell = preview }
        end
        return preview
    end

    -- Pre-compute inventory counts if any allocation key needs them
    local needsInventoryCount = false
    local allKeys = {}
    for _, k in ipairs(allocationOrder) do allKeys[k] = true end
    if opts.buyAllocationOrder then
        for _, k in ipairs(opts.buyAllocationOrder) do allKeys[k] = true end
    end
    if allKeys["lowInventory"] or allKeys["highInventory"] then
        needsInventoryCount = true
    end
    if needsInventoryCount then
        for _, deal in ipairs(deals) do
            deal._inventoryCount = self:CountInventoryForDeal(deal)
        end
    end

    -- Sort deals by allocation priority so high-priority deals get inventory first
    -- For buy tasks with a separate buyAllocationOrder, we partition and sort separately
    if opts.buyAllocationOrder then
        local buyDeals = {}
        local sellDeals = {}
        for _, deal in ipairs(deals) do
            local isCR = (deal.dealType == "flip" or deal.dealType == "buy")
                and deal.buyRealm and deal.buyRealm ~= ""
            if isCR then
                table.insert(buyDeals, deal)
            else
                table.insert(sellDeals, deal)
            end
        end
        SortDealsForAllocation(sellDeals, allocationOrder)
        SortDealsForAllocation(buyDeals, opts.buyAllocationOrder)
        -- Recombine: sell deals first (they claim pool), then buy deals
        deals = {}
        for _, d in ipairs(sellDeals) do table.insert(deals, d) end
        for _, d in ipairs(buyDeals) do table.insert(deals, d) end
    else
        SortDealsForAllocation(deals, allocationOrder)
    end

    -- Track remaining pool quantities
    local poolRemaining = {}
    for i, p in ipairs(pool) do
        poolRemaining[i] = p.totalQuantity
    end

    local sellQtyMode = ns.db.settings.sellQtyMode or "tsm"
    local tsmEnabled = sellQtyMode == "tsm" and ns.TSM and ns.TSM.IsEnabled and ns.TSM:IsEnabled()
    local defaultQty = ns.db.settings.defaultSellQty or 1

    for _, deal in ipairs(deals) do
        local isCrossRealmFlip = (deal.dealType == "flip" or deal.dealType == "buy")
            and deal.buyRealm and deal.buyRealm ~= ""

        -- Cross-realm flip fields to carry forward to tasks
        local crossRealmFields = {}
        if isCrossRealmFlip then
            crossRealmFields = {
                action       = nil, -- set below: "sell" or "buy"
                dealType     = deal.dealType,
                buyRealm     = deal.buyRealm,
                buyPrice     = deal.buyPrice,
                profitAmount = deal.profitAmount,
                profitPct    = deal.profitPct,
                saleAvg      = deal.saleAvg,
            }
        end

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

                    -- Cross-realm flip: item IS in inventory → generate "sell" task
                    local taskCrossFields = {}
                    if isCrossRealmFlip then
                        taskCrossFields = crossRealmFields
                        taskCrossFields.action = "sell"
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
                        -- Cross-realm flip fields
                        action       = taskCrossFields.action,
                        dealType     = taskCrossFields.dealType,
                        buyRealm     = taskCrossFields.buyRealm,
                        buyPrice     = taskCrossFields.buyPrice,
                        profitAmount = taskCrossFields.profitAmount,
                        profitPct    = taskCrossFields.profitPct,
                        saleAvg      = taskCrossFields.saleAvg,
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
                -- Still consume pool to prevent multiple tasks claiming the same item
                local depositFrom, depositLocation
                if assignment.depositSources and #assignment.depositSources > 0 then
                    depositFrom = assignment.depositSources[1].charKey
                    depositLocation = assignment.depositSources[1].location
                end
                local depositQty = math.min(
                    math.max(deal.quantity or 1, defaultQty),
                    poolRemaining[poolIdx])
                if depositQty > 0 then
                    -- Cross-realm: item in inventory but not on sell realm
                    local taskCrossFields = {}
                    if isCrossRealmFlip then
                        taskCrossFields = crossRealmFields
                        taskCrossFields.action = "sell"
                    end

                    table.insert(preview.items, {
                        itemKey         = poolItem.itemKey,
                        itemID          = poolItem.itemID,
                        name            = poolItem.name,
                        icon            = poolItem.icon,
                        targetRealm     = deal.targetRealm,
                        expectedPrice   = deal.expectedPrice,
                        quantity        = depositQty,
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
                        -- Cross-realm flip fields
                        action       = taskCrossFields.action,
                        dealType     = taskCrossFields.dealType,
                        buyRealm     = taskCrossFields.buyRealm,
                        buyPrice     = taskCrossFields.buyPrice,
                        profitAmount = taskCrossFields.profitAmount,
                        profitPct    = taskCrossFields.profitPct,
                        saleAvg      = taskCrossFields.saleAvg,
                        steps = (function()
                            local s = {}
                            table.insert(s, { type = "retrieve", from = "warbank", status = "pending" })
                            table.insert(s, { type = "post", status = "pending" })
                            table.insert(s, { type = "collect", status = "pending" })
                            return s
                        end)(),
                        currentStep = 1,
                    })
                    poolRemaining[poolIdx] = poolRemaining[poolIdx] - depositQty
                end
            else
                -- No character on target realm at all
                -- Cross-realm: item in inventory but no char on sell realm
                if not ns.db.settings.skipUnassigned then
                    local taskCrossFields = {}
                    if isCrossRealmFlip then
                        taskCrossFields = crossRealmFields
                        taskCrossFields.action = "sell"
                    end

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
                        -- Cross-realm flip fields
                        action       = taskCrossFields.action,
                        dealType     = taskCrossFields.dealType,
                        buyRealm     = taskCrossFields.buyRealm,
                        buyPrice     = taskCrossFields.buyPrice,
                        profitAmount = taskCrossFields.profitAmount,
                        profitPct    = taskCrossFields.profitPct,
                        saleAvg      = taskCrossFields.saleAvg,
                        steps         = {},
                        currentStep   = 1,
                    })
                end
            end
        else
            -- No pool match — item not in inventory
            if isCrossRealmFlip then
                -- Cross-realm flip: item NOT in inventory → generate "buy" task
                -- Assign to a character on the buy realm (must have buy role)
                local buyAssignment = nil
                for charKey, charData in pairs(ns.db.characters or {}) do
                    local charRealm = charKey:match("%-(.+)$")
                    local role = type(charData) == "table" and (charData.role or "both") or "both"
                    if charRealm and ns:RealmMatches(deal.buyRealm, charRealm)
                        and (role == "both" or role == "buy") then
                        buyAssignment = charKey
                        break
                    end
                end

                -- Also find a sell-side character
                local sellAssignment = nil
                for charKey, charData in pairs(ns.db.characters or {}) do
                    local charRealm = charKey:match("%-(.+)$")
                    local role = type(charData) == "table" and (charData.role or "both") or "both"
                    if charRealm and ns:RealmMatches(deal.targetRealm, charRealm)
                        and (role == "both" or role == "sell") then
                        sellAssignment = charKey
                        break
                    end
                end

                -- Skip entire flip if either side is unassigned and setting is on
                local skipFlip = ns.db.settings.skipUnassigned and (not buyAssignment or not sellAssignment)

                if not skipFlip then
                local dealQty = math.max(deal.quantity or 1, defaultQty)
                table.insert(preview.items, {
                    itemKey       = deal.itemKey,
                    itemID        = deal.itemID,
                    name          = deal.name,
                    icon          = deal.icon,
                    targetRealm   = deal.targetRealm,
                    expectedPrice = deal.expectedPrice,
                    quantity      = dealQty,
                    assignedChar  = buyAssignment,
                    status        = buyAssignment and "pending" or "unassigned",
                    source        = nil,
                    quality       = deal.quality,
                    sellRate      = deal.sellRate,
                    noCompetition = deal.noCompetition,
                    category      = deal.category,
                    attempts      = 0,
                    importSource  = source,
                    importKey     = deal._importKey,
                    -- Cross-realm: buy task
                    action       = "buy",
                    dealType     = deal.dealType,
                    buyRealm     = deal.buyRealm,
                    buyPrice     = deal.buyPrice,
                    profitAmount = deal.profitAmount,
                    profitPct    = deal.profitPct,
                    saleAvg      = deal.saleAvg,
                    steps = {
                        { type = "browse", status = "pending" },
                        { type = "buy",    status = "pending" },
                        { type = "collect", status = "pending" },
                        { type = "deposit", to = "warbank", status = "pending" },
                    },
                    currentStep = 1,
                })

                -- Generate the sell-side task (blocked until buy deposits to warbank)
                table.insert(preview.items, {
                    itemKey       = deal.itemKey,
                    itemID        = deal.itemID,
                    name          = deal.name,
                    icon          = deal.icon,
                    targetRealm   = deal.targetRealm,
                    expectedPrice = deal.expectedPrice,
                    quantity      = dealQty,
                    assignedChar  = sellAssignment,
                    status        = sellAssignment and "pending" or "unassigned",
                    source        = "unavailable",
                    quality       = deal.quality,
                    sellRate      = deal.sellRate,
                    noCompetition = deal.noCompetition,
                    category      = deal.category,
                    attempts      = 0,
                    importSource  = source,
                    importKey     = deal._importKey,
                    -- Cross-realm: sell side (blocked by buy)
                    action          = "sell",
                    dealType        = deal.dealType,
                    buyRealm        = deal.buyRealm,
                    buyPrice        = deal.buyPrice,
                    profitAmount    = deal.profitAmount,
                    profitPct       = deal.profitPct,
                    saleAvg         = deal.saleAvg,
                    depositFrom     = buyAssignment,
                    depositLocation = "warbank",
                    blockedBy       = buyAssignment,
                    deferredAt      = time(),
                    steps = {
                        { type = "retrieve", from = "warbank", status = "pending" },
                        { type = "post", status = "pending" },
                        { type = "collect", status = "pending" },
                    },
                    currentStep = 1,
                })
                end -- not skipFlip
            else
                -- Standard same-realm: item not in inventory
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
    end

    -- Handle list mode options
    if opts.listMode == "separate" then
        -- Split into buy and sell preview lists
        local buyItems = {}
        local sellItems = {}
        for _, item in ipairs(preview.items) do
            if item.action == "buy" then
                table.insert(buyItems, item)
            else
                table.insert(sellItems, item)
            end
        end

        local buyPreview = {
            name      = preview.name .. " (Buy)",
            createdAt = preview.createdAt,
            source    = preview.source,
            importType = preview.importType,
            items     = buyItems,
        }
        local sellPreview = {
            name      = preview.name .. " (Sell)",
            createdAt = preview.createdAt,
            source    = preview.source,
            importType = preview.importType,
            items     = sellItems,
        }
        return { buy = buyPreview, sell = sellPreview }
    elseif opts.listMode == "integrated" then
        preview.integrated = true
        preview.integratedSortMode = opts.integratedSortMode
        return preview
    end

    -- Items are not pre-sorted here — the UI calls BuildDisplayGroups() for grouped display
    return preview
end
