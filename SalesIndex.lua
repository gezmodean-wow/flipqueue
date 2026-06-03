-- SalesIndex.lua
-- Unified query layer for sales/auction log data.
-- Single source of truth for "sold" status, sales counts, and revenue
-- across all views (LogPage, ItemResearch, DealFinder, Scanner, MiniView).
local addonName, ns = ...

local SalesIndex = {}
ns.SalesIndex = SalesIndex

--------------------------
-- Canonical Status Predicates
--------------------------

function SalesIndex.IsSold(entry)
    return entry.auctionStatus == "sold"
        or (entry.auctionStatus == "collected" and entry.saleOutcome == "sold")
end

function SalesIndex.IsFailed(entry)
    return entry.auctionStatus == "expired"
        or entry.auctionStatus == "cancelled"
        or (entry.auctionStatus == "collected" and entry.saleOutcome == "expired")
end

function SalesIndex.IsActive(entry)
    return entry.auctionStatus == "active"
end

function SalesIndex.IsUncollectedSold(entry)
    return entry.auctionStatus == "sold" and not entry.collectedAt
end

--------------------------
-- Cached Index
--------------------------

local indexCache = nil   -- { byKey, byName, logStats, uncollected, builtAt }
local INDEX_TTL = 10     -- seconds before considering stale

function SalesIndex:Invalidate()
    indexCache = nil
end

local function NormalizeRealm(realm)
    return ns.NormalizeRealmKey and ns:NormalizeRealmKey(realm or "") or (realm or ""):lower()
end

-- Canonical item-ID key for matching across bonus/modifier variants. Mirrors
-- TrackerAuctions' EntryItemID so the deal-finder "already posted" check agrees
-- with the AH-time reconciliation that removes the task: battle pets get a
-- "pet:<speciesID>" form, everything else collapses to its base itemID.
local function BaseItemID(itemKey)
    if not itemKey or itemKey == "" then return nil end
    local petID = itemKey:match("^pet:(%d+)")
    if petID then return "pet:" .. petID end
    return itemKey:match("^(%d+)")
end

local function BuildIndex()
    local log = ns.db and ns.db.log
    if not log then return nil end

    local byKey = {}    -- itemKey -> { sold, failed, posted, revenue, byRealm }
    local byName = {}   -- lower(name) -> same structure
    local logStats = { sold = 0, active = 0, expired = 0, cancelled = 0, skipped = 0, collected = 0, totalRevenue = 0, totalFees = 0 }
    local uncollected = {}  -- charKey -> { sold, expired, cancelled }
    local activeByItem = {} -- baseItemID -> { [targetRealm display] = true }

    for _, entry in ipairs(log) do
        local key = entry.itemKey
        local name = entry.name and entry.name:lower() or nil
        local realm = NormalizeRealm(entry.targetRealm)
        local isSold = SalesIndex.IsSold(entry)
        local isFailed = SalesIndex.IsFailed(entry)
        local isActive = SalesIndex.IsActive(entry)
        local soldCopper = isSold and (entry.soldPrice or 0) or 0

        -- Active auctions, indexed by base itemID -> the realms they sit on.
        -- Keep the raw display realm (not normalized) so connected-realm
        -- matching via ns:RealmsOverlap works at query time.
        if isActive then
            local baseID = BaseItemID(entry.itemKey)
            if baseID and entry.targetRealm and entry.targetRealm ~= "" then
                activeByItem[baseID] = activeByItem[baseID] or {}
                activeByItem[baseID][entry.targetRealm] = true
            end
        end

        -- Per-item index (by key)
        if key then
            if not byKey[key] then
                byKey[key] = { sold = 0, failed = 0, posted = 0, revenue = 0, byRealm = {} }
            end
            local rec = byKey[key]
            rec.posted = rec.posted + 1
            if isSold then
                rec.sold = rec.sold + 1
                rec.revenue = rec.revenue + soldCopper
            elseif isFailed then
                rec.failed = rec.failed + 1
            end
            -- Per-realm
            if not rec.byRealm[realm] then
                rec.byRealm[realm] = { sold = 0, failed = 0, posted = 0, revenue = 0 }
            end
            local rr = rec.byRealm[realm]
            rr.posted = rr.posted + 1
            if isSold then
                rr.sold = rr.sold + 1
                rr.revenue = rr.revenue + soldCopper
            elseif isFailed then
                rr.failed = rr.failed + 1
            end
        end

        -- Per-item index (by name, for fallback matching)
        if name and name ~= "" then
            if not byName[name] then
                byName[name] = { sold = 0, failed = 0, posted = 0, revenue = 0, byRealm = {} }
            end
            local nrec = byName[name]
            nrec.posted = nrec.posted + 1
            if isSold then
                nrec.sold = nrec.sold + 1
                nrec.revenue = nrec.revenue + soldCopper
            elseif isFailed then
                nrec.failed = nrec.failed + 1
            end
            if not nrec.byRealm[realm] then
                nrec.byRealm[realm] = { sold = 0, failed = 0, posted = 0, revenue = 0 }
            end
            local nrr = nrec.byRealm[realm]
            nrr.posted = nrr.posted + 1
            if isSold then
                nrr.sold = nrr.sold + 1
                nrr.revenue = nrr.revenue + soldCopper
            elseif isFailed then
                nrr.failed = nrr.failed + 1
            end
        end

        -- Global log stats
        local status = entry.auctionStatus
        if isSold then
            logStats.sold = logStats.sold + 1
            logStats.totalRevenue = logStats.totalRevenue + soldCopper
        elseif status == "active" then
            logStats.active = logStats.active + 1
        elseif status == "expired" then
            logStats.expired = logStats.expired + 1
        elseif status == "cancelled" then
            logStats.cancelled = logStats.cancelled + 1
        elseif status == "skipped" then
            logStats.skipped = logStats.skipped + 1
        elseif status == "collected" then
            if entry.saleOutcome == "expired" then
                logStats.expired = logStats.expired + 1
            else
                logStats.collected = logStats.collected + 1
            end
        end
        logStats.totalFees = logStats.totalFees + (entry.ahFee or 0)

        -- Per-character uncollected
        local charKey = entry.charKey
        if charKey then
            if not uncollected[charKey] then
                uncollected[charKey] = { sold = 0, expired = 0, cancelled = 0 }
            end
            local uc = uncollected[charKey]
            if entry.auctionStatus == "sold" and not entry.collectedAt then
                uc.sold = uc.sold + 1
            elseif entry.auctionStatus == "expired" and not entry.collectedAt then
                uc.expired = uc.expired + 1
            elseif entry.auctionStatus == "cancelled" and not entry.collectedAt then
                uc.cancelled = uc.cancelled + 1
            end
        end
    end

    return {
        byKey = byKey,
        byName = byName,
        logStats = logStats,
        uncollected = uncollected,
        activeByItem = activeByItem,
        builtAt = time(),
    }
end

function SalesIndex:EnsureIndex()
    if indexCache and (time() - indexCache.builtAt) < INDEX_TTL then
        return indexCache
    end
    indexCache = BuildIndex()
    return indexCache
end

--------------------------
-- Query API
--------------------------

-- Resolve an item's sales record, trying exact key first, then name fallback
local function ResolveRecord(index, itemKey, itemName)
    if not index then return nil end
    -- Exact key match
    if itemKey and index.byKey[itemKey] then
        return index.byKey[itemKey]
    end
    -- Base ID match (strip bonus/modifier suffixes)
    if itemKey then
        local baseID = itemKey:match("^(%d+);")
        if baseID then
            local baseKey = baseID .. ";;"
            if index.byKey[baseKey] then
                return index.byKey[baseKey]
            end
        end
    end
    -- Name fallback
    if itemName and itemName ~= "" then
        local lower = itemName:lower()
        if index.byName[lower] then
            return index.byName[lower]
        end
    end
    return nil
end

function SalesIndex:GetSalesSummary(itemKey, itemName)
    local index = self:EnsureIndex()
    local rec = ResolveRecord(index, itemKey, itemName)
    if not rec then
        return { sold = 0, failed = 0, posted = 0, revenue = 0, avgPrice = 0, successRate = 0, byRealm = {} }
    end
    local avgPrice = rec.sold > 0 and math.floor(rec.revenue / rec.sold) or 0
    local successRate = rec.posted > 0 and (rec.sold / rec.posted) or 0
    return {
        sold = rec.sold,
        failed = rec.failed,
        posted = rec.posted,
        revenue = rec.revenue,
        avgPrice = avgPrice,
        successRate = successRate,
        byRealm = rec.byRealm,
    }
end

function SalesIndex:GetSalesForRealm(itemKey, itemName, targetRealm)
    local index = self:EnsureIndex()
    local rec = ResolveRecord(index, itemKey, itemName)
    if not rec then return 0, 0 end
    local realm = NormalizeRealm(targetRealm)
    local rr = rec.byRealm[realm]
    if not rr or rr.sold == 0 then return 0, 0 end
    return math.floor(rr.revenue / rr.sold), rr.sold
end

-- True if the player currently has an *active* auction for this item on a
-- realm sharing a connected-realm AH with targetRealm. Matched at base-itemID
-- level (across bonus/modifier variants) to agree with the AH-time owned-auction
-- reconciliation in TrackerAuctions. Used by the Deal Finder to avoid assigning
-- a deal to a realm where the player is already posted.
function SalesIndex:HasActiveAuction(itemKey, targetRealm)
    if not targetRealm or targetRealm == "" then return false end
    local index = self:EnsureIndex()
    if not index or not index.activeByItem then return false end
    local baseID = BaseItemID(itemKey)
    if not baseID then return false end
    local realms = index.activeByItem[baseID]
    if not realms then return false end
    for postedRealm in pairs(realms) do
        if ns:RealmsOverlap(postedRealm, targetRealm) then return true end
    end
    return false
end

function SalesIndex:GetLogStats()
    local index = self:EnsureIndex()
    return index and index.logStats or { sold = 0, active = 0, expired = 0, cancelled = 0, skipped = 0, collected = 0, totalRevenue = 0, totalFees = 0 }
end

function SalesIndex:GetUncollectedForChar(charKey)
    local index = self:EnsureIndex()
    if not index or not index.uncollected[charKey] then
        return { sold = 0, expired = 0, cancelled = 0 }
    end
    return index.uncollected[charKey]
end
