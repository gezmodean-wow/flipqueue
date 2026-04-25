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

-- Realm-scope all cache keys. AH listings are per connected-realm cluster,
-- so a 3.2k price scanned on Realm A would leak into Realm B's posting
-- decisions if we shared a single cache. Use the player's normalized realm
-- name as a prefix; connected realms each get their own bucket and converge
-- after one scan each — acceptable for v1.
local function CurrentRealm()
    local r = (GetNormalizedRealmName and GetNormalizedRealmName())
        or GetRealmName() or "Unknown"
    return r:gsub("%s+", ""):lower()
end

-- Cache key = "<realm>|<fqKey>" where fqKey is FlipQueue's canonical
-- "<itemID>;<bonusIDs>;<modifiers>" string. Bucketing on the full fqKey
-- distinguishes bonus-ID variants (Design ranks 1/2/3, gear ilvl upgrades,
-- etc.) the same way TSM does internally. Earlier versions bucketed by
-- (itemID, GetDetailedItemLevelInfo, ...) which collapsed all ranks of a
-- Design into one bucket and could pick up the *base* ilvl when item info
-- hadn't finished loading (boots ilvl 240 cached as "44" because 44 was the
-- pre-upgrade base). Bonus IDs are present in the link string itself, no
-- item-info load needed, so this is robust against async load timing.
local function MakeCacheKey(fqKey, isCommodity, realm)
    if not fqKey or fqKey == "" then return nil end
    realm = realm or CurrentRealm()
    if isCommodity then
        local id = fqKey:match("^([^;]+)")
        return realm .. "|c:" .. tostring(id)
    end
    return realm .. "|" .. fqKey
end

--------------------------
-- Harvest helpers
--------------------------

-- TSM (and the default UI's sell flow) sends non-commodity searches with
-- itemKey.itemLevel = 0 — a deliberate workaround for an old Blizzard bug,
-- still in TSM as of v4.14.66 (LibTSMWoW/Source/API/AuctionHouseWrapper.lua).
-- The server returns ALL variants of that itemID (every bonus-ID combo and
-- every ilvl) in one combined result list. Each per-result itemLink carries
-- its own bonus IDs and modifiers — that's what we bucket on. Bonus IDs
-- are in the link string itself, so we don't depend on async item-info
-- loading (which is what made GetDetailedItemLevelInfo return base ilvls
-- for upgraded gear in the previous bucketing scheme).
local function HarvestNonCommodity(itemKey, now)
    local getNum = C_AuctionHouse.GetNumItemSearchResults
    local n = getNum and getNum(itemKey) or 0
    if n == 0 then return 0 end

    local realm = CurrentRealm()
    local buckets = {} -- cache-key -> { minUnit, isPlayer }
    for i = 1, n do
        local ok, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        if ok and info and info.buyoutAmount and info.buyoutAmount > 0 and info.itemLink then
            local qty = info.quantity or 1
            if qty > 0 then
                local unit = math.floor(info.buyoutAmount / qty)
                if unit > 0 then
                    local id, bonus, mods = ns:ParseItemLink(info.itemLink)
                    if id then
                        local fqKey = ns:MakeItemKey(id, bonus, mods)
                        local k = MakeCacheKey(fqKey, false, realm)
                        if k then
                            local b = buckets[k]
                            if not b then
                                buckets[k] = {
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
        end
    end

    local stored = 0
    for k, b in pairs(buckets) do
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

    local realm = CurrentRealm()
    local now = time()
    local buckets = {} -- cache-key -> { minUnit, isPlayer }
    for i = 0, n - 1 do
        local _, _, count, _, _, _, _, _, _, buyout = C_AuctionHouse.GetReplicateItemInfo(i)
        if buyout and buyout > 0 and count and count > 0 then
            local link = C_AuctionHouse.GetReplicateItemLink(i)
            if link then
                local id, bonus, mods = ns:ParseItemLink(link)
                if id then
                    local fqKey = ns:MakeItemKey(id, bonus, mods)
                    local k = MakeCacheKey(fqKey, false, realm)
                    if k then
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
        local fqKey = ns:MakeItemKey(itemID, "", "")
        local k = MakeCacheKey(fqKey, true)
        if k then
            cache[k] = {
                minUnit = unit,
                isPlayer = isPlayer,
                scannedAt = time(),
                source = "commodity",
            }
            ScheduleNotify()
        end

    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        -- Browse/full scan (e.g. TSM Shopping with broad search, Auctionator
        -- full scan). Per-entry data is coarser — Blizzard gives us minPrice
        -- per ItemKey, not per-auction detail with full bonus IDs. We can't
        -- distinguish bonus-ID variants here, so browse results land in a
        -- coarser bucket that an item-level search will refine on next scan.
        if not C_AuctionHouse.GetBrowseResults then return end
        local results = C_AuctionHouse.GetBrowseResults() or {}
        local realm = CurrentRealm()
        local now = time()
        local stored = 0
        for _, br in ipairs(results) do
            if br.itemKey and br.minPrice and br.minPrice > 0 then
                local fqKey
                if br.itemKey.battlePetSpeciesID and br.itemKey.battlePetSpeciesID > 0 then
                    fqKey = "pet:" .. br.itemKey.battlePetSpeciesID .. ";;"
                else
                    fqKey = string.format("%d;;", br.itemKey.itemID or 0)
                end
                local k = MakeCacheKey(fqKey, false, realm)
                if k then
                    -- Don't overwrite a more precise per-link entry if we
                    -- already have one — browse data is coarser.
                    if not cache[k] then
                        cache[k] = {
                            minUnit = br.minPrice,
                            isPlayer = br.containsOwnerItem == true,
                            scannedAt = now,
                            source = "browse",
                        }
                        stored = stored + 1
                    end
                end
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
-- fqKey: FlipQueue's canonical "<itemID>;<bonusIDs>;<modifiers>" string —
--        the same key the caller already has from MakeItemKey.
-- isCommodity: caller already knows this from C_AuctionHouse.GetItemCommodityStatus.
-- Returns a table { minUnit, isPlayer, age, source } or nil.
function ScanCache:Lookup(fqKey, isCommodity)
    local key = MakeCacheKey(fqKey, isCommodity)
    if not key then return nil end

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
            -- Current key shape is "<realm>|<fqKey>" (with ";" inside the
            -- suffix, since fqKey is "<itemID>;<bonusIDs>;<modifiers>") or
            -- "<realm>|c:<itemID>" for commodities. Drop anything that
            -- doesn't match — covers older builds that keyed on
            -- "<itemID>:<ilvl>:0:0" tuples, since those collapsed bonus-ID
            -- variants and would inject wrong prices into the new lookup.
            local kept, dropped = 0, 0
            for k, v in pairs(FlipQueueDB.scanCache) do
                local valid = false
                if type(k) == "string" and type(v) == "table"
                    and v.minUnit and v.scannedAt then
                    local suffix = k:match("|(.+)$")
                    if suffix and (suffix:find(";", 1, true) or suffix:find("^c:")) then
                        valid = true
                    end
                end
                if valid then
                    cache[k] = v
                    kept = kept + 1
                else
                    dropped = dropped + 1
                end
            end
            if dropped > 0 then
                ns:PrintDebug("[ScanCache] loaded " .. kept ..
                    " entries, dropped " .. dropped .. " from older build")
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
