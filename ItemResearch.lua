-- ItemResearch.lua
-- Data aggregation for the Item Research page.
-- Collects everything known about an item across inventory, log, imports, and TSM.
local addonName, ns = ...

local ItemResearch = {}
ns.ItemResearch = ItemResearch

--------------------------
-- Cache
--------------------------

local researchCache = {}   -- itemKey -> { record, ts }
local CACHE_TTL = 30       -- seconds; TSM prices have their own 60s cache

function ItemResearch:InvalidateCache(itemKey)
    if itemKey then
        researchCache[itemKey] = nil
    else
        wipe(researchCache)
    end
    if ns.SalesIndex then ns.SalesIndex:Invalidate() end
end

--------------------------
-- Helpers
--------------------------

local function ExtractNumericID(itemKey)
    if not itemKey then return nil end
    -- Handle pet:SPECIESID format
    if itemKey:match("^pet:") then
        local n = tonumber(itemKey:match("^pet:(%d+)"))
        return (n and n > 0) and n or nil
    end
    local n = tonumber(itemKey:match("^(%d+);"))
    return (n and n > 0) and n or nil
end

-- Pet cage item ID (82800) — used to detect orphaned pet log entries
local PET_CAGE_ID = 82800

-- Adapter: uses ns:ItemsMatch (the canonical matcher) with a synthetic queueItem
local function ItemMatches(entryKey, entryName, targetKey, targetID, targetName)
    local queueItem = { itemKey = targetKey, itemID = targetID, name = targetName or "" }
    local matched = ns:ItemsMatch(entryKey, entryName, queueItem, false, false)
    return matched
end

local function ParseCopper(val)
    if type(val) == "number" then return val end
    if type(val) == "string" then
        return (ns:ParseGoldValue(val) or 0) * 10000
    end
    return 0
end

--------------------------
-- BuildItemIndex
--------------------------
-- Returns a deduplicated array of all known items across sources.
-- Each entry: { itemKey, itemID, name, icon, quality, totalQty,
--               hasInventory, hasLog, hasDeals }

function ItemResearch:BuildItemIndex()
    if not ns.db then return {} end

    local map = {}      -- itemKey -> entry (exact key match)
    local idMap = {}     -- numericID -> entry (fallback for dedup)

    local nameMap = {}   -- lowercase name -> entry (for pet cage dedup)

    local function Ensure(itemKey, itemID, name, icon, quality)
        if not itemKey or itemKey == "" then
            if itemID and itemID ~= "" then
                itemKey = tostring(itemID) .. ";;"
            elseif name then
                itemKey = "name:" .. name:lower()
            else
                return nil
            end
        end

        -- Pet cage dedup: log entries with "82800;;" are pets — match by name
        local numID = ExtractNumericID(itemKey)
        local isCageEntry = (numID == PET_CAGE_ID)
        if isCageEntry and name and name ~= "" then
            local nameKey = name:lower()
            if nameMap[nameKey] then
                local entry = nameMap[nameKey]
                map[itemKey] = entry
                -- Don't overwrite the pet: key with the cage key
                return entry
            end
        end

        -- Check exact key first
        local entry = map[itemKey]
        if entry then
            -- Merge into existing exact match
        else
            -- Check numeric ID fallback for dedup (e.g., "12345;;" and "12345;bonus;")
            if numID and not isCageEntry and idMap[numID] then
                entry = idMap[numID]
                map[itemKey] = entry
                -- Prefer the key with bonus IDs (more specific)
                if itemKey:find(";.+;") and not entry.itemKey:find(";.+;") then
                    entry.itemKey = itemKey
                end
            else
                entry = {
                    itemKey = itemKey,
                    itemID = itemID or (not isCageEntry and numID) or "",
                    name = name or "",
                    icon = icon,
                    quality = quality,
                    ilvl = nil,  -- resolved below
                    totalQty = 0,
                    hasInventory = false,
                    hasLog = false,
                    hasDeals = false,
                }
                map[itemKey] = entry
                if numID and not isCageEntry then idMap[numID] = entry end
            end
        end

        if (not entry.name or entry.name == "") and name and name ~= "" then
            entry.name = name
        end
        if not entry.icon and icon then entry.icon = icon end
        if not entry.quality and quality then entry.quality = quality end
        if not entry.itemID or entry.itemID == "" then
            entry.itemID = itemID or (not isCageEntry and ExtractNumericID(itemKey)) or ""
        end
        -- Register name for pet dedup (prefer pet: entries over cage entries)
        if name and name ~= "" then
            local nameKey = name:lower()
            if not nameMap[nameKey] or (not isCageEntry and itemKey:match("^pet:")) then
                nameMap[nameKey] = entry
            end
        end
        return entry
    end

    -- 1. Character inventories
    for charKey, charData in pairs(ns.db.characters or {}) do
        if charData.inventory and charData.inventory.items then
            for key, item in pairs(charData.inventory.items) do
                local e = Ensure(key, item.itemID, item.name, item.icon)
                if e then
                    e.totalQty = e.totalQty + (item.quantity or 0)
                    e.hasInventory = true
                end
            end
        end
    end

    -- 2. Warbank
    if ns.db.warbank and ns.db.warbank.items then
        for key, item in pairs(ns.db.warbank.items) do
            local e = Ensure(key, item.itemID, item.name, item.icon)
            if e then
                e.totalQty = e.totalQty + (item.quantity or 0)
                e.hasInventory = true
            end
        end
    end

    -- 3. Guild banks
    for guildName, guildData in pairs(ns.db.guilds or {}) do
        if guildData.items then
            for key, item in pairs(guildData.items) do
                local e = Ensure(key, item.itemID, item.name, item.icon)
                if e then
                    e.totalQty = e.totalQty + (item.quantity or 0)
                    e.hasInventory = true
                end
            end
        end
    end

    -- 4. Log
    for _, entry in ipairs(ns.db.log or {}) do
        local e = Ensure(entry.itemKey, entry.itemID, entry.name, entry.icon, entry.quality)
        if e then e.hasLog = true end
    end

    -- 5. FP Scanner deals
    for _, deal in pairs(ns.db.imports and ns.db.imports.fpScanner or {}) do
        local e = Ensure(deal.itemKey, deal.itemID, deal.name, deal.icon, deal.quality)
        if e then e.hasDeals = true end
    end

    -- 6. FP Cross-Realm deals
    for _, deal in pairs(ns.db.imports and ns.db.imports.fpCrossRealm or {}) do
        local e = Ensure(deal.itemKey, deal.itemID, deal.name, deal.icon, deal.quality)
        if e then e.hasDeals = true end
    end

    -- 7. Deal Finder deals
    for _, deal in pairs(ns.db.imports and ns.db.imports.dealFinder or {}) do
        local e = Ensure(deal.itemKey, deal.itemID, deal.name, deal.icon, deal.quality)
        if e then e.hasDeals = true end
    end

    -- Fallback ilvl: only use GetItemInfo for items WITHOUT bonus IDs (base = actual).
    -- Items with bonuses show blank ilvl until rescanned by the scanner.
    for _, entry in pairs(map) do
        if not entry.ilvl or entry.ilvl == 0 then
            local ek = entry.itemKey or ""
            local bp = ek:match("^[^;]+;([^;]*)") or ""
            local mp = ek:match(";([^;]*)$") or ""
            if bp == "" and mp == "" then
                local nid = tonumber(tostring(entry.itemID):match("^(%d+)"))
                if nid and nid > 0 and nid ~= PET_CAGE_ID then
                    local ok, _, _, _, ilvl = pcall(C_Item.GetItemInfo, nid)
                    if ok and ilvl and ilvl > 0 then entry.ilvl = ilvl end
                end
            end
        end
    end

    -- Convert to sorted array (deduplicate since multiple keys can map to same entry)
    local result = {}
    local seen = {}
    for _, entry in pairs(map) do
        if not seen[entry] then
            seen[entry] = true
            table.insert(result, entry)
        end
    end
    table.sort(result, function(a, b)
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)

    return result
end

--------------------------
-- GetItemResearch
--------------------------
-- Deep-dive for a single item. Returns a ResearchRecord.

function ItemResearch:GetItemResearch(itemKey, itemName, skipCache)
    if not ns.db then return nil end

    -- Check cache
    if not skipCache and itemKey then
        local cached = researchCache[itemKey]
        if cached and (time() - cached.ts) < CACHE_TTL then
            return cached.record
        end
    end

    local targetID = ExtractNumericID(itemKey)
    local record = {
        itemKey = itemKey,
        itemID = targetID,
        name = itemName or "",
        icon = nil,
        quality = nil,

        inventory = {},
        totalInventory = 0,

        sales = {},
        salesSummary = { count = 0, totalRevenue = 0, avgPrice = 0, byRealm = {} },

        failures = {},
        failureSummary = { expiredCount = 0, cancelledCount = 0, totalFeesLost = 0 },

        activeAuctions = {},

        fpDeals = {},

        tsm = nil,

        purchases = {},
    }

    -- ---- Inventory ----
    for charKey, charData in pairs(ns.db.characters or {}) do
        if charData.inventory and charData.inventory.items then
            for key, item in pairs(charData.inventory.items) do
                if ItemMatches(key, item.name, itemKey, targetID, itemName) then
                    if not record.icon and item.icon then record.icon = item.icon end
                    if not record.name or record.name == "" then record.name = item.name end
                    table.insert(record.inventory, {
                        charKey = charKey,
                        class = charData.class,
                        quantity = item.quantity or 0,
                        locations = item.locations or {},
                        lastScan = charData.inventory.lastScan,
                    })
                    record.totalInventory = record.totalInventory + (item.quantity or 0)
                end
            end
        end
    end

    if ns.db.warbank and ns.db.warbank.items then
        for key, item in pairs(ns.db.warbank.items) do
            if ItemMatches(key, item.name, itemKey, targetID, itemName) then
                if not record.icon and item.icon then record.icon = item.icon end
                table.insert(record.inventory, {
                    charKey = "Warbank",
                    quantity = item.quantity or 0,
                    locations = { warbank = item.quantity or 0 },
                    lastScan = ns.db.warbank.lastScan,
                })
                record.totalInventory = record.totalInventory + (item.quantity or 0)
            end
        end
    end

    for guildName, guildData in pairs(ns.db.guilds or {}) do
        if guildData.items then
            for key, item in pairs(guildData.items) do
                if ItemMatches(key, item.name, itemKey, targetID, itemName) then
                    table.insert(record.inventory, {
                        charKey = "Guild: " .. guildName,
                        quantity = item.quantity or 0,
                        locations = { guildbank = item.quantity or 0 },
                        lastScan = guildData.lastScan,
                    })
                    record.totalInventory = record.totalInventory + (item.quantity or 0)
                end
            end
        end
    end

    -- ---- Log scan (sales, failures, active, purchases) ----
    for _, entry in ipairs(ns.db.log or {}) do
        if ItemMatches(entry.itemKey, entry.name, itemKey, targetID, itemName) then
            if not record.icon and entry.icon then record.icon = entry.icon end
            if not record.quality and entry.quality then record.quality = entry.quality end
            if (not record.name or record.name == "") and entry.name then record.name = entry.name end

            if ns.SalesIndex.IsSold(entry) then
                local soldCopper = entry.soldPrice or ParseCopper(entry.postedPrice or entry.expectedPrice)
                table.insert(record.sales, {
                    soldPrice = soldCopper,
                    postedPrice = entry.postedPrice or "",
                    targetRealm = entry.targetRealm or "Unknown",
                    charKey = entry.charKey or "",
                    soldAt = entry.soldAt,
                    postedAt = entry.postedAt,
                    quantity = entry.postedQuantity or 1,
                })
            elseif ns.SalesIndex.IsFailed(entry) then
                table.insert(record.failures, {
                    postedPrice = entry.postedPrice or "",
                    targetRealm = entry.targetRealm or "Unknown",
                    charKey = entry.charKey or "",
                    postedAt = entry.postedAt,
                    auctionStatus = entry.auctionStatus,
                    saleOutcome = entry.saleOutcome,
                    fee = entry.ahFee or 0,
                    totalFeesSpent = entry.totalFeesSpent or 0,
                    postAttempts = entry.postAttempts or 0,
                    postHistory = entry.postHistory,
                })
            elseif ns.SalesIndex.IsActive(entry) then
                table.insert(record.activeAuctions, {
                    postedPrice = entry.postedPrice or "",
                    expectedPrice = entry.expectedPrice or "",
                    targetRealm = entry.targetRealm or "Unknown",
                    charKey = entry.charKey or "",
                    postedAt = entry.postedAt,
                    quantity = entry.postedQuantity or 1,
                })
            end

            -- Detect purchases (buy tasks that were logged)
            if entry.buyPrice and entry.buyPrice ~= "" then
                table.insert(record.purchases, {
                    price = ParseCopper(entry.buyPrice),
                    priceStr = entry.buyPrice,
                    realm = entry.buyLocation or entry.targetRealm or "Unknown",
                    charKey = entry.charKey or "",
                    timestamp = entry.postedAt,
                })
            end
        end
    end

    -- ---- Sales Summary ----
    local totalRev = 0
    local byRealm = {}
    for _, sale in ipairs(record.sales) do
        local copper = sale.soldPrice or 0
        totalRev = totalRev + copper
        local r = sale.targetRealm or "Unknown"
        if not byRealm[r] then byRealm[r] = { count = 0, total = 0 } end
        byRealm[r].count = byRealm[r].count + 1
        byRealm[r].total = byRealm[r].total + copper
    end
    for r, data in pairs(byRealm) do
        data.avg = data.count > 0 and (data.total / data.count) or 0
    end
    record.salesSummary = {
        count = #record.sales,
        totalRevenue = totalRev,
        avgPrice = #record.sales > 0 and (totalRev / #record.sales) or 0,
        byRealm = byRealm,
    }

    -- ---- Failure Summary ----
    local expCount, canCount, feesLost = 0, 0, 0
    for _, fail in ipairs(record.failures) do
        if fail.auctionStatus == "expired" or fail.auctionStatus == "collected" then
            expCount = expCount + 1
        else
            canCount = canCount + 1
        end
        feesLost = feesLost + (fail.totalFeesSpent or fail.fee or 0)
    end
    record.failureSummary = {
        expiredCount = expCount,
        cancelledCount = canCount,
        totalFeesLost = feesLost,
    }

    -- ---- FP Deals ----
    for importKey, deal in pairs(ns.db.imports and ns.db.imports.fpScanner or {}) do
        if ItemMatches(deal.itemKey, deal.name, itemKey, targetID, itemName) then
            table.insert(record.fpDeals, {
                source = "fpScanner",
                targetRealm = deal.targetRealm or "",
                expectedPrice = deal.expectedPrice or "",
                sellRate = deal.sellRate,
                noCompetition = deal.noCompetition,
                category = deal.category,
                saleAvg = deal.saleAvg,
                ilvl = deal.ilvl,
            })
        end
    end

    for importKey, deal in pairs(ns.db.imports and ns.db.imports.fpCrossRealm or {}) do
        if ItemMatches(deal.itemKey, deal.name, itemKey, targetID, itemName) then
            table.insert(record.fpDeals, {
                source = "fpCrossRealm",
                targetRealm = deal.targetRealm or "",
                expectedPrice = deal.expectedPrice or "",
                buyRealm = deal.buyRealm,
                buyPrice = deal.buyPrice,
                profitAmount = deal.profitAmount,
                profitPct = deal.profitPct,
                sellRate = deal.sellRate,
                noCompetition = deal.noCompetition,
            })
        end
    end

    -- ---- TSM Data ----
    if ns.TSM and ns.TSM:IsEnabled() and itemKey then
        -- Current realm prices
        local minBuyout = ns.TSM:GetPrice(itemKey, "DBMinBuyout")
        local market = ns.TSM:GetPrice(itemKey, "DBMarket")
        local historical = ns.TSM:GetPrice(itemKey, "DBHistorical")
        -- Region-wide prices (all realms aggregated)
        local regionMarketAvg = ns.TSM:GetPrice(itemKey, "DBRegionMarketAvg")
        local regionMinBuyoutAvg = ns.TSM:GetPrice(itemKey, "DBRegionMinBuyoutAvg")
        local regionHistorical = ns.TSM:GetPrice(itemKey, "DBRegionHistorical")
        local regionSaleAvg = ns.TSM:GetPrice(itemKey, "DBRegionSaleAvg")
        local regionSaleRate = ns.TSM:GetPrice(itemKey, "DBRegionSaleRate")
        local regionSoldPerDay = ns.TSM:GetPrice(itemKey, "DBRegionSoldPerDay")
        -- TSM Accounting cost basis (what we paid on average across our characters)
        local smartAvgBuy = ns.TSM:GetPrice(itemKey, "SmartAvgBuy")
        local auctionOp = ns.TSM:GetItemAuctioningOp(itemKey)

        if minBuyout or market or regionSaleAvg or regionMarketAvg or auctionOp or smartAvgBuy then
            record.tsm = {
                -- Current realm
                minBuyout = minBuyout,
                market = market,
                historical = historical,
                -- Region
                regionMarketAvg = regionMarketAvg,
                regionMinBuyoutAvg = regionMinBuyoutAvg,
                regionHistorical = regionHistorical,
                regionSaleAvg = regionSaleAvg,
                regionSaleRate = regionSaleRate,
                regionSoldPerDay = regionSoldPerDay,
                -- Cost basis from TSM Accounting
                smartAvgBuy = smartAvgBuy,
                -- Operation
                auctioningOp = auctionOp,
            }
        end
    end

    -- ---- TSM Per-Realm Data (from AppData hourly downloads) ----
    record.tsmRealms = {}
    if ns.TSMRealms and ns.TSMRealms:IsLoaded() and itemKey then
        local tsmStr = ns.TSM and ns.TSM:ItemKeyToTSMString(itemKey)
        if tsmStr then
            record.tsmRealms = ns.TSMRealms:GetAllRealmPricing(tsmStr)
        end
    end

    -- Cache the result
    if itemKey then
        researchCache[itemKey] = { record = record, ts = time() }
    end

    return record
end
