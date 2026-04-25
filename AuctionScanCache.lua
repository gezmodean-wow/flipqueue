-- AuctionScanCache.lua
-- Passive listener for live AH scan results. Any addon running a search
-- (TSM Post/Cancel Scan, Auctionator, Blizzard default UI) triggers Blizzard
-- events with the scan results; we harvest those into a per-variant cache.
--
-- Why this exists: TSM's DBMinBuyout is stale (TSM Desktop App injects it
-- hourly, nothing updates it from in-game scans). TSM's own posting
-- algorithm uses live C_AuctionHouse scan data — we do the same, indirectly,
-- by reading the events TSM's scans generate.
--
-- Cache key format:
--   "<itemID>:<itemLevel>:<itemSuffix>:<speciesID>"  non-commodity
--   "c:<itemID>"                                      commodity
-- Matches Blizzard's ItemKey tuple so lookup is a simple format string.

local addonName, ns = ...

local ScanCache = {}
ns.AuctionScanCache = ScanCache

local cache = {}
-- Entries persist across sessions via FlipQueueDB.scanCache. We keep them
-- indefinitely in memory; lookup decides freshness per call. This lets a
-- TSM scan from yesterday still inform today's posting decisions, with the
-- staleness surfaced in the tooltip rather than silently dropped.
local PERSIST_MAX_AGE = 7 * 24 * 3600  -- prune entries older than 7 days at save time
local PERSIST_MAX_ENTRIES = 20000      -- cap on saved entries (keep most recent)

--------------------------
-- Keys
--------------------------

local function TupleKey(itemID, itemLevel, itemSuffix, speciesID)
    if speciesID and speciesID > 0 then
        return "p:" .. tostring(speciesID)
    end
    return string.format("%d:%d:%d:0",
        tonumber(itemID) or 0,
        tonumber(itemLevel) or 0,
        tonumber(itemSuffix) or 0)
end

local function CommodityKey(itemID)
    return "c:" .. tostring(tonumber(itemID) or 0)
end

-- Derive a Blizzard ItemKey tuple from an item hyperlink. We need itemLevel
-- from GetDetailedItemLevelInfo to match what Blizzard puts in auction
-- ItemKeys (the scan event keys by the same level).
local function TupleFromLink(itemLink)
    if not itemLink or type(itemLink) ~= "string" then return nil end

    -- Battle pets: itemID is always 82800, suffix/level are 0, speciesID
    -- distinguishes variants.
    local speciesID = itemLink:match("|Hbattlepet:(%d+)")
    if speciesID then
        return tonumber(speciesID), 0, 0, tonumber(speciesID)
    end

    local itemID = itemLink:match("|Hitem:(%d+):")
    if not itemID then return nil end

    local ilvl = 0
    if GetDetailedItemLevelInfo then
        local v = GetDetailedItemLevelInfo(itemLink)
        if type(v) == "number" then ilvl = v end
    end

    return tonumber(itemID), ilvl, 0, 0
end

--------------------------
-- Harvest helpers
--------------------------

-- TSM (and the default UI's sell flow) sends non-commodity searches with
-- itemKey.itemLevel = 0 — a deliberate workaround for an old Blizzard bug,
-- still in TSM as of v4.14.66 (LibTSMWoW/Source/API/AuctionHouseWrapper.lua).
-- The server returns ALL ilvl variants of that itemID in a single result
-- list, and the scanning addon buckets per-variant client-side using each
-- result's itemLink. Without this, we'd cache `<itemID>:0:0:0` (the event's
-- itemKey) and never match the per-variant ilvl we compute from bag items.
--
-- HarvestNonCommodity reads every result, extracts per-result ilvl from the
-- itemLink, buckets by (real ilvl), and writes one cache entry per variant.
local function HarvestNonCommodity(itemKey, now)
    local getNum = C_AuctionHouse.GetNumItemSearchResults
    local n = getNum and getNum(itemKey) or 0
    if n == 0 then return 0 end

    -- Battle pets are keyed by speciesID; ilvl is meaningless for them.
    local isPet = itemKey.battlePetSpeciesID and itemKey.battlePetSpeciesID > 0

    local buckets = {} -- ilvl -> { minUnit, isPlayer }
    for i = 1, n do
        local ok, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        if ok and info and info.buyoutAmount and info.buyoutAmount > 0 then
            local qty = info.quantity or 1
            if qty > 0 then
                local unit = math.floor(info.buyoutAmount / qty)
                if unit > 0 then
                    local bucketKey = 0
                    if not isPet and info.itemLink and GetDetailedItemLevelInfo then
                        local v = GetDetailedItemLevelInfo(info.itemLink)
                        if type(v) == "number" then bucketKey = v end
                    end
                    local b = buckets[bucketKey]
                    if not b then
                        buckets[bucketKey] = {
                            minUnit  = unit,
                            isPlayer = info.containsOwnerItem == true,
                        }
                    elseif unit < b.minUnit then
                        b.minUnit  = unit
                        b.isPlayer = info.containsOwnerItem == true
                    end
                end
            end
        end
    end

    local stored = 0
    for ilvl, b in pairs(buckets) do
        local k
        if isPet then
            k = TupleKey(itemKey.itemID, 0, 0, itemKey.battlePetSpeciesID)
        else
            k = TupleKey(itemKey.itemID, ilvl, itemKey.itemSuffix or 0, 0)
        end
        cache[k] = {
            minUnit   = b.minUnit,
            isPlayer  = b.isPlayer,
            scannedAt = now,
            source    = "item",
        }
        stored = stored + 1
    end
    return stored
end

local function LowestUnitCommodity(itemID)
    local n = C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    if not n or n == 0 then return nil, false end

    local ok, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
    if ok and info and info.unitPrice and info.unitPrice > 0 then
        return info.unitPrice, info.containsOwnerItem == true
    end
    return nil, false
end

--------------------------
-- Update notifications
--------------------------

-- A scan typically fires many events in quick succession (one per item TSM
-- queries). Notifying on every single event would re-resolve pricing dozens
-- of times per scan. Debounce until the burst settles, then fire once.
-- Declared before the event handler so the OnEvent closure captures
-- ScheduleNotify as a real local upvalue (not a missing global).
local listeners = {}
local DEBOUNCE_SEC = 2

local debounceTicker

local function ScheduleNotify()
    if debounceTicker then debounceTicker:Cancel() end
    debounceTicker = C_Timer.NewTimer(DEBOUNCE_SEC, function()
        debounceTicker = nil
        for _, fn in ipairs(listeners) do
            pcall(fn)
        end
    end)
end

function ScanCache:RegisterUpdated(fn)
    if type(fn) == "function" then
        listeners[#listeners + 1] = fn
    end
end

--------------------------
-- Event handling
--------------------------

-- Harvest a full bulk-replicate dump (Auctionator's "Full Scan" path uses
-- C_AuctionHouse.ReplicateItems → REPLICATE_ITEM_LIST_UPDATE). Returns a
-- count of cache entries written. Iterates every auction in the replicate
-- batch, derives per-result ilvl from the link, buckets per (itemID, ilvl).
local function HarvestReplicate()
    if not C_AuctionHouse or not C_AuctionHouse.GetNumReplicateItems then return 0 end
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    if n == 0 then return 0 end

    local now = time()
    local buckets = {} -- key -> { minUnit, isPlayer }
    for i = 0, n - 1 do
        local _, _, count, _, _, _, _, _, _, buyout = C_AuctionHouse.GetReplicateItemInfo(i)
        if buyout and buyout > 0 and count and count > 0 then
            local link = C_AuctionHouse.GetReplicateItemLink(i)
            local itemID, ilvl, suffix, species = TupleFromLink(link)
            if itemID then
                local k
                if species and species > 0 then
                    k = TupleKey(itemID, 0, 0, species)
                else
                    k = TupleKey(itemID, ilvl, suffix or 0, 0)
                end
                local unit = math.floor(buyout / count)
                if unit > 0 then
                    local b = buckets[k]
                    if not b or unit < b.minUnit then
                        buckets[k] = { minUnit = unit, isPlayer = false }
                    end
                end
            end
        end
    end

    local stored = 0
    for k, b in pairs(buckets) do
        cache[k] = {
            minUnit   = b.minUnit,
            isPlayer  = b.isPlayer,
            scannedAt = now,
            source    = "replicate",
        }
        stored = stored + 1
    end
    return stored
end

local listener = CreateFrame("Frame", "FlipQueueScanListener")
listener:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
listener:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
listener:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
listener:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")

listener:SetScript("OnEvent", function(_, event, arg1)
    if event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemKey = arg1
        if type(itemKey) ~= "table" or not itemKey.itemID then return end
        local n = HarvestNonCommodity(itemKey, time())
        if n > 0 then ScheduleNotify() end

    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local itemID = arg1
        if not itemID then return end
        local unit, isPlayer = LowestUnitCommodity(itemID)
        if not unit then return end
        cache[CommodityKey(itemID)] = {
            minUnit = unit,
            isPlayer = isPlayer,
            scannedAt = time(),
            source = "commodity",
        }
        ScheduleNotify()

    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        -- Browse/full scan (e.g. TSM Shopping with broad search, Auctionator
        -- full scan). Per-entry data is coarser — we get minPrice per
        -- ItemKey, not per-auction detail. Good enough for our use: lowest
        -- unit price is what we need.
        if not C_AuctionHouse.GetBrowseResults then return end
        local results = C_AuctionHouse.GetBrowseResults() or {}
        local now = time()
        local stored = 0
        for _, br in ipairs(results) do
            if br.itemKey and br.minPrice and br.minPrice > 0 then
                local k = TupleKey(br.itemKey.itemID, br.itemKey.itemLevel, br.itemKey.itemSuffix, br.itemKey.battlePetSpeciesID)
                cache[k] = {
                    minUnit = br.minPrice,
                    isPlayer = br.containsOwnerItem == true,
                    scannedAt = now,
                    source = "browse",
                }
                stored = stored + 1
            end
        end
        if stored > 0 then ScheduleNotify() end

    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        -- Auctionator's Full Scan triggers this. Heavy event — replicate
        -- batches can be 50k–200k auctions on a busy realm. Harvest inline;
        -- if frame hitching becomes a complaint we can shift to a coroutine.
        local stored = HarvestReplicate()
        if stored > 0 then
            ns:PrintDebug("[ScanCache] Replicate harvested " .. stored .. " entries")
            ScheduleNotify()
        end
    end
end)

--------------------------
-- Public API
--------------------------

-- Look up the freshest live-scan minimum unit price for an item.
-- itemLink: hyperlink from bags / auction data — needed to derive ilvl.
-- isCommodity: caller already knows this from C_AuctionHouse.GetItemCommodityStatus.
-- Returns a table { minUnit, isPlayer, age, source } or nil.
function ScanCache:Lookup(itemLink, isCommodity)
    local itemID, itemLevel, itemSuffix, speciesID = TupleFromLink(itemLink)
    if not itemID then return nil end

    local key
    if isCommodity then
        key = CommodityKey(itemID)
    else
        key = TupleKey(itemID, itemLevel, itemSuffix, speciesID)
    end

    local entry = cache[key]
    if not entry then return nil end

    return {
        minUnit  = entry.minUnit,
        isPlayer = entry.isPlayer,
        age      = time() - entry.scannedAt,
        source   = entry.source,
    }
end

function ScanCache:GetSize()
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    return n
end

function ScanCache:Clear()
    wipe(cache)
end

-- For /fq debug — dump a few cache entries most recently touched.
function ScanCache:DebugDump(limit)
    limit = limit or 20
    local rows = {}
    for k, v in pairs(cache) do
        rows[#rows + 1] = { key = k, entry = v }
    end
    table.sort(rows, function(a, b) return a.entry.scannedAt > b.entry.scannedAt end)
    local out = {}
    for i = 1, math.min(limit, #rows) do
        local r = rows[i]
        -- %.0f instead of %d — copper values can exceed the 32-bit signed
        -- limit Lua's %d uses (e.g. 4.25B copper for a 425k gold listing).
        out[#out + 1] = string.format("%s: %.0f copper (%s, %ds old%s)",
            r.key, r.entry.minUnit, r.entry.source or "?",
            time() - r.entry.scannedAt,
            r.entry.isPlayer and ", owned" or "")
    end
    return out, #rows
end

--------------------------
-- Persistence (cross-session)
--------------------------

-- Load cache from FlipQueueDB.scanCache on session start. Survives logout
-- so the player gets immediate live-data fidelity for items they've scanned
-- before, without needing to re-run TSM on first AH open of the session.
local persistFrame = CreateFrame("Frame")
persistFrame:RegisterEvent("PLAYER_LOGIN")
persistFrame:RegisterEvent("PLAYER_LOGOUT")
persistFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if type(FlipQueueDB) == "table" and type(FlipQueueDB.scanCache) == "table" then
            -- Restore entries. Save format matches in-memory format exactly.
            for k, v in pairs(FlipQueueDB.scanCache) do
                if type(v) == "table" and v.minUnit and v.scannedAt then
                    cache[k] = v
                end
            end
        end

    elseif event == "PLAYER_LOGOUT" then
        if type(FlipQueueDB) ~= "table" then return end
        -- Prune old entries and cap size before saving. We sort by recency
        -- and keep the newest PERSIST_MAX_ENTRIES.
        local now = time()
        local rows = {}
        for k, v in pairs(cache) do
            if v.scannedAt and (now - v.scannedAt) <= PERSIST_MAX_AGE then
                rows[#rows + 1] = { k = k, v = v }
            end
        end
        table.sort(rows, function(a, b) return a.v.scannedAt > b.v.scannedAt end)
        local saved = {}
        for i = 1, math.min(PERSIST_MAX_ENTRIES, #rows) do
            saved[rows[i].k] = rows[i].v
        end
        FlipQueueDB.scanCache = saved
    end
end)
