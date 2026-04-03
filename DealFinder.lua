-- DealFinder.lua
-- Scans inventory items against TSM per-realm pricing to find profitable
-- sell opportunities. Produces item-centric groups with per-realm options,
-- outlier detection, and priority-based auto-selection.
local addonName, ns = ...

local DealFinder = {}
ns.DealFinder = DealFinder

--------------------------
-- State
--------------------------

local lastScanResult = nil   -- { itemGroups, stats }
local scanInProgress = false

local CHUNK_SIZE = 5

--------------------------
-- Readiness
--------------------------

function DealFinder:IsReady()
    if not ns.TSM or not ns.TSM:IsAvailable() then
        return false, "TSM is not installed or not available."
    end
    for _, charData in pairs(ns.db.characters or {}) do
        local role = charData.role or "both"
        if role == "sell" or role == "both" then
            return true, nil
        end
    end
    return false, "No characters with a sell role. Assign roles on the Characters page."
end

function DealFinder:IsScanning()
    return scanInProgress
end

--------------------------
-- Sell Realm Detection
--------------------------

function DealFinder:GetSellRealms()
    local realms = {}
    for charKey, charData in pairs(ns.db.characters or {}) do
        local role = charData.role or "both"
        if role == "sell" or role == "both" then
            local realm = charKey:match("%-(.+)$")
            if realm and realm ~= "" then
                local normalized = ns:NormalizeRealmKey(realm)
                if not realms[normalized] then
                    realms[normalized] = { display = realm, chars = {} }
                end
                table.insert(realms[normalized].chars, charKey)
            end
        end
    end
    return realms
end

--------------------------
-- Helpers
--------------------------

local function FindRealmPricing(allRealmPrices, targetRealm)
    if not allRealmPrices then return nil end
    if allRealmPrices[targetRealm] then return allRealmPrices[targetRealm] end
    for realmName, pricing in pairs(allRealmPrices) do
        if ns:RealmMatches(realmName, targetRealm) then return pricing end
    end
    return nil
end

-- Pre-build personal sales index from log.
-- Tracks both sold and failed (expired/cancelled) entries for success rate.
-- Returns: { itemKey = { _sold=N, _failed=N, realmNorm = { total, count, failed } } }
local function BuildPersonalSalesIndex()
    local index = {}     -- itemKey -> data
    local nameIndex = {} -- lowercase name -> data (fallback for key mismatches)
    if not ns.db or not ns.db.log then return index, nameIndex end

    for _, entry in ipairs(ns.db.log) do
        local key = entry.itemKey
        if not key then key = nil end  -- skip entries with no key

        if key then
            if not index[key] then index[key] = { _sold = 0, _failed = 0, _posted = 0 } end
            -- Also index by name for fallback matching
            local entryName = entry.name and entry.name:lower() or nil
            if entryName and not nameIndex[entryName] then
                nameIndex[entryName] = index[key]
            elseif entryName and nameIndex[entryName] ~= index[key] then
                nameIndex[entryName] = nameIndex[entryName] or index[key]
            end

            local isSold = (entry.auctionStatus == "sold" or entry.saleOutcome == "sold")
            local isFailed = (entry.auctionStatus == "expired" or entry.auctionStatus == "cancelled"
                or entry.saleOutcome == "expired" or entry.saleOutcome == "cancelled")
            local isPosted = (entry.auctionStatus == "collected" or entry.auctionStatus == "active")

            -- Parse price from any available field
            local price = entry.soldPrice or entry.postedPrice
            if type(price) == "string" then
                price = (ns:ParseGoldValue(price) or 0) * 10000
            end
            local realmNorm = entry.targetRealm and ns:NormalizeRealmKey(entry.targetRealm) or nil

            if isSold then
                index[key]._sold = index[key]._sold + 1
                if realmNorm then
                    if not index[key][realmNorm] then
                        index[key][realmNorm] = { total = 0, count = 0, failed = 0, posted = 0 }
                    end
                    if price and price > 0 then
                        index[key][realmNorm].total = index[key][realmNorm].total + price
                    end
                    index[key][realmNorm].count = index[key][realmNorm].count + 1
                end
            elseif isFailed then
                index[key]._failed = index[key]._failed + 1
                if realmNorm then
                    if not index[key][realmNorm] then
                        index[key][realmNorm] = { total = 0, count = 0, failed = 0, posted = 0 }
                    end
                    index[key][realmNorm].failed = index[key][realmNorm].failed + 1
                end
            elseif isPosted then
                index[key]._posted = index[key]._posted + 1
                if realmNorm then
                    if not index[key][realmNorm] then
                        index[key][realmNorm] = { total = 0, count = 0, failed = 0, posted = 0 }
                    end
                    index[key][realmNorm].posted = index[key][realmNorm].posted + 1
                end
            end
        end
    end

    return index, nameIndex
end

-- Resolve sales index entry: exact key → base ID fallback → pet fallback → name fallback
local function ResolveSalesData(salesIndex, nameIndex, itemKey, itemName)
    -- 1. Exact key match
    if salesIndex[itemKey] then return salesIndex[itemKey] end

    -- 2. Try without bonus/modifier suffix (e.g., "12345;;" matches "12345;bonus;mod")
    local baseKey = itemKey:match("^([^;]+)") .. ";;"
    if baseKey ~= itemKey and salesIndex[baseKey] then return salesIndex[baseKey] end

    -- 3. Pet fallback: try species variants
    local speciesID = itemKey:match("^(pet:%d+)")
    if speciesID then
        local fallback = salesIndex[speciesID .. ";;"]
        if fallback then return fallback end
        for k, v in pairs(salesIndex) do
            if k:match("^" .. speciesID) then return v end
        end
    end

    -- 4. Name-based fallback
    if nameIndex and itemName then
        local data = nameIndex[itemName:lower()]
        if data then return data end
    end

    return nil
end

-- Get personal sales summary for an item across all realms.
local function GetPersonalSummary(salesIndex, nameIndex, itemKey, itemName)
    local data = ResolveSalesData(salesIndex, nameIndex, itemKey, itemName)
    if not data then return { sold = 0, failed = 0, posted = 0, successRate = 0, avgPrice = 0, byRealm = {} } end

    local totalCopper, totalSold = 0, 0
    local byRealm = {}
    for k, r in pairs(data) do
        if k:sub(1, 1) ~= "_" then
            totalCopper = totalCopper + (r.total or 0)
            totalSold = totalSold + (r.count or 0)
            byRealm[k] = {
                count = r.count or 0,
                failed = r.failed or 0,
                posted = r.posted or 0,
                avg = (r.count or 0) > 0 and math.floor((r.total or 0) / r.count) or 0,
            }
        end
    end

    local totalAttempts = (data._sold or 0) + (data._failed or 0)
    return {
        sold = data._sold or 0,
        failed = data._failed or 0,
        posted = data._posted or 0,
        successRate = totalAttempts > 0 and (data._sold or 0) / totalAttempts or 0,
        avgPrice = totalSold > 0 and math.floor(totalCopper / totalSold) or 0,
        byRealm = byRealm,
    }
end

local function GetPersonalForRealm(salesIndex, nameIndex, itemKey, itemName, targetRealm)
    local data = ResolveSalesData(salesIndex, nameIndex, itemKey, itemName)
    if not data then return nil, 0 end
    local realmNorm = ns:NormalizeRealmKey(targetRealm)
    local r = data[realmNorm]
    if r and r.count > 0 then return math.floor(r.total / r.count), r.count end
    return nil, 0
end

local function BlendPrice(tsmPrice, personalAvg, personalCount)
    if not tsmPrice or tsmPrice <= 0 then return personalAvg or 0 end
    if not personalAvg or personalAvg <= 0 or personalCount < 2 then return tsmPrice end
    local weight = math.min(0.4, personalCount / 10)
    return math.floor(tsmPrice * (1 - weight) + personalAvg * weight)
end

--------------------------
-- Outlier Detection
--------------------------

function DealFinder:IsOutlier(realmPrice, regionAvg, multiplier)
    if not regionAvg or regionAvg <= 0 then return false end
    multiplier = multiplier or (ns.db and ns.db.settings.dfOutlierMultiplier) or 1.5
    return realmPrice > (regionAvg * multiplier)
end

--------------------------
-- Priority Scoring
--------------------------

-- Score a realm option based on priority order.
-- Higher score = better. Returns numeric score.
function DealFinder:ScoreRealm(realmOpt, priorityOrder)
    local score = 0
    local weight = 1000000  -- decreasing weight per priority level

    for _, key in ipairs(priorityOrder or {"profit"}) do
        if key == "profit" then
            score = score + (realmOpt.profit or 0) / 10000 * weight  -- normalize copper
        elseif key == "noCompetition" then
            score = score + (realmOpt.noCompetition and weight or 0)
        elseif key == "previousSales" then
            score = score + (realmOpt.personalCount or 0) * weight
        elseif key == "population" then
            -- More auctions = higher population/demand (proxy)
            score = score + (realmOpt.numAuctions or 0) * weight
        end
        weight = weight / 100  -- each subsequent priority has 100x less impact
    end

    -- Penalize or exclude outliers based on setting
    if realmOpt.isOutlier then
        local ignore = ns.db and ns.db.settings.dfIgnoreOutliers
        if ignore then
            score = -1  -- effectively excludes from auto-selection
        else
            score = score * 0.5
        end
    end

    return score
end

-- Apply priority order: score all realms, auto-select the best one per item.
-- Sets _selected = true on best realm, false on others.
function DealFinder:ApplyPriority(itemGroups, priorityOrder)
    priorityOrder = priorityOrder or (ns.db and ns.db.settings.dfPriorityOrder) or {"profit"}

    for _, group in ipairs(itemGroups) do
        if #group.realms > 0 then
            local bestIdx, bestScore = 1, -1
            for i, realmOpt in ipairs(group.realms) do
                realmOpt.score = self:ScoreRealm(realmOpt, priorityOrder)
                realmOpt._selected = false
                if realmOpt.score > bestScore then
                    bestScore = realmOpt.score
                    bestIdx = i
                end
            end
            group.realms[bestIdx]._selected = true
            group.selectedRealm = bestIdx
        end
    end
end

--------------------------
-- Core Scan (chunked)
--------------------------

function DealFinder:ScanChunked(pool, onProgress, onComplete)
    if scanInProgress then
        if onComplete then onComplete(nil) end
        return
    end
    scanInProgress = true

    local settings = ns.db.settings
    local minPrice = settings.dfMinPrice or 500000
    local outlierMult = settings.dfOutlierMultiplier or 1.5

    local sellRealms = self:GetSellRealms()
    local realmCount = 0
    for _ in pairs(sellRealms) do realmCount = realmCount + 1 end

    local hasRealmData = ns.TSMRealms and ns.TSMRealms:IsLoaded()
    local salesIndex, salesNameIndex = BuildPersonalSalesIndex()

    local itemGroups = {}
    local total = #pool
    local idx = 1
    local startTime = debugprofilestop and debugprofilestop() or 0

    local function ProcessChunk()
        if not scanInProgress then
            if onComplete then onComplete(nil) end
            return
        end

        local chunkEnd = math.min(idx + CHUNK_SIZE - 1, total)

        for i = idx, chunkEnd do
            local poolItem = pool[i]
            local itemKey = poolItem.itemKey
            local tsmStr = ns.TSM:ItemKeyToTSMString(itemKey)

            if not tsmStr and ns.db.settings.debugMessages then
                ns:PrintDebug("DealFinder SKIP (no TSM key): " .. (poolItem.name or "?") ..
                    " key=" .. (itemKey or "?"))
            end

            if tsmStr then

            local allRealmPrices = {}
            if hasRealmData then
                allRealmPrices = ns.TSMRealms:GetAllRealmPricing(tsmStr) or {}
            end

            local regionSaleRate = ns.TSM:GetPrice(itemKey, "DBRegionSaleRate")
            local regionSaleAvg = ns.TSM:GetPrice(itemKey, "DBRegionSaleAvg")
            local regionMarketAvg = ns.TSM:GetPrice(itemKey, "DBRegionMarketAvg")
            local regionSoldPerDay = ns.TSM:GetPrice(itemKey, "DBRegionSoldPerDay")
            local smartAvgBuy = ns.TSM:GetPrice(itemKey, "SmartAvgBuy")

            -- Normalize sale rate (TSM returns decimal, e.g. 0.25 = 25%)
            -- Safety: if somehow > 1, treat as percentage
            local saleRate = nil
            if regionSaleRate then
                saleRate = regionSaleRate > 1 and (regionSaleRate / 100) or regionSaleRate
            end

            local personalSummary = GetPersonalSummary(salesIndex, salesNameIndex, itemKey, poolItem.name)

            -- Extract base ID, bonus, modifiers (handle pet:SPECIESID format)
            local baseID, bonusStr, modStr
            if itemKey:match("^pet:") then
                baseID = itemKey:match("^(pet:%d+)")
                bonusStr = itemKey:match("^pet:%d+;([^;]*)")
                modStr = itemKey:match("^pet:%d+;[^;]*;(.*)$")
            else
                baseID = itemKey:match("^(%d+)")
                bonusStr = itemKey:match("^%d+;([^;]*)")
                modStr = itemKey:match("^%d+;[^;]*;(.*)$")
            end

            -- Build realm options for this item
            local realmOptions = {}
            for _, realmInfo in pairs(sellRealms) do
                local targetRealm = realmInfo.display
                local pricing = FindRealmPricing(allRealmPrices, targetRealm)

                local tsmPrice, numAuctions, dataQuality

                if pricing then
                    tsmPrice = pricing.marketValueRecent or pricing.minBuyout
                    numAuctions = pricing.numAuctions
                    dataQuality = "perRealm"
                elseif regionMarketAvg and regionMarketAvg > 0 then
                    tsmPrice = regionMarketAvg
                    dataQuality = "regional"
                end

                if tsmPrice and tsmPrice > 0 then
                    local personalAvg, personalCount = GetPersonalForRealm(salesIndex, salesNameIndex, itemKey, poolItem.name, targetRealm)
                    local blendedPrice = BlendPrice(tsmPrice, personalAvg, personalCount)

                    if blendedPrice >= minPrice then
                        local baseline = regionMarketAvg or regionSaleAvg or 0
                        local profit, profitPct = 0, 0
                        if baseline > 0 then
                            profit = math.floor(blendedPrice * 0.95) - baseline
                            profitPct = math.floor((blendedPrice - baseline) / baseline * 100)
                        else
                            profit = math.floor(blendedPrice * 0.95)
                        end

                        local isOutlier = self:IsOutlier(blendedPrice, regionMarketAvg, outlierMult)

                        -- Real profit based on cost basis (SmartAvgBuy)
                        local realProfit, realProfitPct
                        if smartAvgBuy and smartAvgBuy > 0 then
                            realProfit = math.floor(blendedPrice * 0.95) - smartAvgBuy
                            realProfitPct = math.floor((blendedPrice * 0.95 - smartAvgBuy) / smartAvgBuy * 100)
                        end

                        table.insert(realmOptions, {
                            realmName     = targetRealm,
                            tsmPrice      = tsmPrice,
                            personalAvg   = personalAvg,
                            personalCount = personalCount or 0,
                            blendedPrice  = blendedPrice,
                            numAuctions   = numAuctions or 0,
                            profit        = profit,
                            profitPct     = profitPct,
                            realProfit    = realProfit,
                            realProfitPct = realProfitPct,
                            isOutlier     = isOutlier,
                            noCompetition = (not numAuctions or numAuctions == 0),
                            hasPreviousSales = (personalCount or 0) > 0,
                            dataQuality   = dataQuality or "perRealm",
                            score         = 0,  -- set by ApplyPriority
                        })
                    end
                end
            end

            if #realmOptions == 0 and ns.db.settings.debugMessages then
                local reason = "no pricing"
                if regionMarketAvg and regionMarketAvg > 0 then
                    reason = "all realms below min " .. ns:FormatGold(minPrice)
                elseif not regionMarketAvg or regionMarketAvg == 0 then
                    reason = "no TSM market data"
                end
                ns:PrintDebug("DealFinder SKIP (" .. reason .. "): " ..
                    (poolItem.name or "?") .. " key=" .. (itemKey or "?"))
            end

            if #realmOptions > 0 then
                -- Sort realms by blended price descending as default
                table.sort(realmOptions, function(a, b) return a.blendedPrice > b.blendedPrice end)

                table.insert(itemGroups, {
                    itemKey        = itemKey,
                    itemID         = baseID or "",
                    name           = poolItem.name,
                    icon           = poolItem.icon,
                    quality        = "",
                    ilvl           = poolItem.ilvl,
                    quantity       = poolItem.totalQuantity,
                    bonusIDs       = bonusStr or "",
                    modifiers      = modStr or "",
                    sources        = poolItem.sources,
                    regionMarketAvg = regionMarketAvg,
                    regionSaleRate  = saleRate,
                    regionSaleAvg   = regionSaleAvg,
                    regionSoldPerDay = regionSoldPerDay,
                    smartAvgBuy     = smartAvgBuy,
                    personalSales   = personalSummary,
                    realms          = realmOptions,
                    selectedRealm   = 1,
                    denied          = false,
                })
            end

            end -- if tsmStr
        end -- for i

        idx = chunkEnd + 1

        if onProgress then
            onProgress(math.min(idx - 1, total), total)
        end

        if idx <= total then
            C_Timer.After(0, ProcessChunk)
        else
            -- Apply priority scoring
            local priorityOrder = settings.dfPriorityOrder or {"profit"}
            self:ApplyPriority(itemGroups, priorityOrder)

            -- Sort item groups by best realm score descending
            table.sort(itemGroups, function(a, b)
                local aScore = a.realms[a.selectedRealm] and a.realms[a.selectedRealm].score or 0
                local bScore = b.realms[b.selectedRealm] and b.realms[b.selectedRealm].score or 0
                return aScore > bScore
            end)

            local elapsed = 0
            if debugprofilestop then
                elapsed = (debugprofilestop() - startTime) / 1000
            end

            local result = {
                itemGroups = itemGroups,
                stats = {
                    itemsScanned  = total,
                    itemsWithDeals = #itemGroups,
                    realmsChecked = realmCount,
                    elapsed       = elapsed,
                },
            }

            lastScanResult = result
            scanInProgress = false
            if onComplete then onComplete(result) end
        end
    end

    if total == 0 then
        scanInProgress = false
        local result = { itemGroups = {}, stats = { itemsScanned = 0, itemsWithDeals = 0, realmsChecked = realmCount, elapsed = 0 } }
        lastScanResult = result
        if onComplete then onComplete(result) end
        return
    end

    ProcessChunk()
end

function DealFinder:CancelScan()
    scanInProgress = false
end

--------------------------
-- Import Storage
--------------------------

-- Save accepted items' selected realm deals to ns.db.imports.dealFinder.
function DealFinder:SaveSelectedToImports(itemGroups)
    if not ns.db or not ns.db.imports then return 0 end

    ns.db.imports.dealFinder = {}
    local count = 0

    for _, group in ipairs(itemGroups) do
        if not group.denied then
            for _, realm in ipairs(group.realms) do
                if realm._selected ~= false then
                    local key = ns:MakeImportKey(group.itemKey, group.name, realm.realmName)
                    ns.db.imports.dealFinder[key] = {
                        itemKey       = group.itemKey,
                        itemID        = group.itemID,
                        name          = group.name,
                        icon          = group.icon,
                        quality       = group.quality,
                        ilvl          = 0,
                        bonusIDs      = group.bonusIDs,
                        modifiers     = group.modifiers,
                        quantity      = 1,  -- per-deal baseline; actual post qty set by TSM postCap / defaultSellQty during generation
                        targetRealm   = realm.realmName,
                        expectedPrice = ns:FormatGold(realm.blendedPrice),
                        blendedPrice  = realm.blendedPrice,
                        sellRate      = group.regionSaleRate or 0,
                        noCompetition = realm.noCompetition,
                        category      = "",
                        saleAvg       = group.regionSaleAvg and ns:FormatGold(group.regionSaleAvg) or "",
                        dealType      = "sell",
                        profitAmount  = realm.profit > 0 and ns:FormatGold(realm.profit) or "",
                        profitPct     = realm.profitPct > 0 and realm.profitPct or 0,
                    }
                    count = count + 1
                end
            end
        end
    end

    return count
end

--------------------------
-- Cache
--------------------------

function DealFinder:GetLastScan()
    return lastScanResult
end

function DealFinder:ClearLastScan()
    lastScanResult = nil
end
