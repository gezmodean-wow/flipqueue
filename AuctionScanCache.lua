-- AuctionScanCache.lua
-- Passive listener for live AH scan results. Any addon running a search
-- (TSM Post/Cancel Scan, Auctionator, Blizzard default UI) triggers Blizzard
-- events with the scan results; we harvest those into a per-variant cache.
--
-- Why this exists: TSM-the-addon makes posting decisions from live
-- C_AuctionHouse scan results, not from its DBMinBuyout snapshot (which is
-- only refreshed hourly by the TSM Desktop App). To match TSM's posting we
-- need the same live data.
--
-- We store per-listing detail (top N by buyout) so the posting decision tree
-- can apply TSM's IsAuctionFiltered (timeLeft / matchStackSize / threshold-
-- ignore filters) before picking the lowest non-filtered competitor — same
-- logic as TSM's Util.GetLowestAuction.

local addonName, ns = ...

local ScanCache = {}
ns.AuctionScanCache = ScanCache

local cache = {}
-- Tracks "we ran an item-search query for itemID X on realm R at time T".
-- ITEM_SEARCH_RESULTS_UPDATED fires once for the queried itemKey and the
-- server returns ALL variants of that itemID. So if we record the scan
-- here, Lookup for a variant fqKey that DIDN'T appear in the harvest can
-- return a "scanned, no listings" sentinel — distinguishing
-- "this variant has no listings on this realm" (post at normal) from
-- "we never scanned" (status: scan_pending). Keyed "<realm>|<itemID>".
local itemScans = {}

-- Per-fqKey we store the cheapest N listings. TSM's IsAuctionFiltered may
-- drop the lowest few (low time-left, wrong stack size, below-threshold
-- ignore), so we need a few backups to fall through to. Ten covers the
-- usual case without bloating SavedVariables.
local CACHE_LISTING_LIMIT = 10

-- Persisted entries can survive across sessions. A listing harvested
-- yesterday is rarely meaningful for today's posting decision, so we prune
-- aggressively at save time.
local PERSIST_MAX_AGE = 7 * 24 * 3600
local PERSIST_MAX_ENTRIES = 20000

-- Default freshness ceiling on Lookup. Anything older than this returns
-- nil so callers know to trigger an auto-scan instead of trusting a stale
-- entry. 30 minutes is short enough that turnover won't have moved the
-- market materially in the typical "open AH and post" workflow.
local DEFAULT_FRESH_AGE_SEC = 30 * 60

--------------------------
-- Keys
--------------------------

-- AH listings are per connected-realm cluster. A 3.2k price scanned on
-- realm A would leak into realm B's posting decisions if we shared a
-- single cache, so prefix everything with the player's normalized realm.
-- Connected realms each get their own bucket and converge after one
-- scan each — acceptable for v1.
local function CurrentRealm()
    local r = (GetNormalizedRealmName and GetNormalizedRealmName())
        or GetRealmName() or "Unknown"
    return r:gsub("%s+", ""):lower()
end

-- Cache key shape:
--   commodities:   "<realm>|c:<itemID>"
--   non-commodities: "<realm>|t:<tsmCanonicalString>"  when TSM is loaded
--                    "<realm>|<fqKey>"                  fallback
--
-- Why TSM's canonical string: TSM_API.ToItemString runs BonusIds.Filter,
-- which strips upgrade-track bonus IDs (and other "decorative" bonuses
-- TSM treats as cosmetic). Different raw bonus combos that TSM views as
-- the same variant collapse to the same canonical string. If we keyed
-- on the raw fqKey, our cache would have separate buckets for what TSM
-- (and posting decisions) treats as one — lookups for the bag item's
-- canonical form would miss listings stored under the listing's raw form.
local function CanonicalizeFqKey(fqKey)
    if not fqKey or fqKey == "" then return nil end
    if not (ns.TSM and ns.TSM.ItemKeyToTSMString) then return nil end
    local s = ns.TSM:ItemKeyToTSMString(fqKey)
    if type(s) == "string" and s ~= "" then return s end
    return nil
end

local function MakeCacheKey(fqKey, isCommodity, realm)
    if not fqKey or fqKey == "" then return nil end
    realm = realm or CurrentRealm()
    if isCommodity then
        local id = fqKey:match("^([^;]+)")
        return realm .. "|c:" .. tostring(id)
    end
    local canonical = CanonicalizeFqKey(fqKey)
    if canonical then
        return realm .. "|t:" .. canonical
    end
    return realm .. "|" .. fqKey
end

--------------------------
-- Listing insertion
--------------------------

-- Insert a listing into a buyout-ascending array, capped at `limit`. Listings
-- past the cap fall off; ties preserve insertion order so the player's own
-- listing doesn't get bumped by an identically-priced competitor.
local function InsertListing(listings, listing, limit)
    local n = #listings
    local insertAt = n + 1
    for i = 1, n do
        if listing.buyout < listings[i].buyout then
            insertAt = i
            break
        end
    end
    if insertAt > limit then return end
    table.insert(listings, insertAt, listing)
    if #listings > limit then
        table.remove(listings, limit + 1)
    end
end

--------------------------
-- Harvest helpers
--------------------------

-- TSM (and the default UI's sell flow) sends non-commodity searches with
-- itemKey.itemLevel = 0 — a deliberate workaround for an old Blizzard bug,
-- still in TSM as of v4.14.66. The server returns ALL variants of that
-- itemID in one combined result list. Each per-result itemLink carries its
-- own bonus IDs and modifiers — that's what we bucket on.
local function HarvestNonCommodity(itemKey, now)
    local getNum = C_AuctionHouse.GetNumItemSearchResults
    local n = getNum and getNum(itemKey) or 0
    if n == 0 then return 0 end

    local realm = CurrentRealm()
    local buckets = {} -- cacheKey -> { listings = {}, hasInvalidSeller = bool }
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
                                b = { listings = {}, hasInvalidSeller = false }
                                buckets[k] = b
                            end
                            -- containsOwnerItem is the retail per-result
                            -- analog of TSM's numOwnerAuctions > 0 check.
                            local isPlayer = info.containsOwnerItem == true
                            local owners = info.owners
                            local seller = (owners and owners[1]) or ""
                            -- TSM's hasInvalidSeller is set when the server
                            -- returned a result with no owner string AND a
                            -- whitelist is configured (so missing seller
                            -- means "we can't tell if this is whitelisted").
                            -- Capture per-listing; the post decision can
                            -- propagate it when the lowest is the offender.
                            local listing = {
                                buyout      = unit,
                                quantity    = qty,
                                seller      = seller,
                                timeLeftSec = info.timeLeftSeconds,
                                isPlayer    = isPlayer,
                                hasOwner    = (seller ~= "") or isPlayer,
                            }
                            if not listing.hasOwner then
                                b.hasInvalidSeller = true
                            end
                            InsertListing(b.listings, listing, CACHE_LISTING_LIMIT)
                        end
                    end
                end
            end
        end
    end

    local stored = 0
    for k, b in pairs(buckets) do
        cache[k] = {
            listings         = b.listings,
            scannedAt        = now,
            source           = "item",
            hasInvalidSeller = b.hasInvalidSeller,
        }
        stored = stored + 1
        -- Per-bucket detail for canonicalisation diagnostics. Helps spot
        -- when listings TSM treats as the same variant land in different
        -- buckets (or vice versa) — that's where post-price mismatches
        -- with TSM originate.
        local lo = b.listings[1]
        if lo then
            ns:PrintDebug("[ScanCache]   bucket " .. k ..
                " lowest=" .. string.format("%.0f", lo.buyout) .. "c x" .. tostring(lo.quantity) ..
                " seller=" .. tostring(lo.seller) ..
                " (" .. #b.listings .. " listings)")
        end
    end
    return stored
end

local function HarvestCommodity(itemID, now)
    local n = C_AuctionHouse.GetNumCommoditySearchResults
        and C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    if not n or n == 0 then return false end

    local realm = CurrentRealm()
    local fqKey = ns:MakeItemKey(itemID, "", "")
    local k = MakeCacheKey(fqKey, true, realm)
    if not k then return false end

    local listings = {}
    local hasInvalidSeller = false
    -- Commodities present a stack of cheapest-first results; first is the
    -- per-unit floor. Pull up to the cap to mirror non-commodity behavior
    -- (lets future stack-size or seller filtering choose past the lowest).
    local upper = math.min(n, CACHE_LISTING_LIMIT)
    for i = 1, upper do
        local ok, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
        if ok and info and info.unitPrice and info.unitPrice > 0 then
            local owners = info.owners
            local seller = (owners and owners[1]) or ""
            local isPlayer = info.containsOwnerItem == true
            local listing = {
                buyout      = info.unitPrice,
                quantity    = info.quantity or 1,
                seller      = seller,
                timeLeftSec = info.timeLeftSeconds,
                isPlayer    = isPlayer,
                hasOwner    = (seller ~= "") or isPlayer,
            }
            if not listing.hasOwner then hasInvalidSeller = true end
            listings[#listings + 1] = listing
        end
    end

    if #listings == 0 then return false end
    cache[k] = {
        listings         = listings,
        scannedAt        = now,
        source           = "commodity",
        hasInvalidSeller = hasInvalidSeller,
    }
    return true
end

-- Auctionator's Full Scan path uses C_AuctionHouse.ReplicateItems →
-- REPLICATE_ITEM_LIST_UPDATE. Returns count of cache entries written.
-- Replicate batches can be 50k–200k auctions on a busy realm; we iterate
-- inline. If frame hitching becomes a complaint we can shift to a coroutine.
local function HarvestReplicate()
    if not C_AuctionHouse or not C_AuctionHouse.GetNumReplicateItems then return 0 end
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    if n == 0 then return 0 end

    local realm = CurrentRealm()
    local now = time()
    local buckets = {}
    for i = 0, n - 1 do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner = C_AuctionHouse.GetReplicateItemInfo(i)
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
                            if not b then
                                b = { listings = {}, hasInvalidSeller = false }
                                buckets[k] = b
                            end
                            local seller = owner or ""
                            local listing = {
                                buyout      = unit,
                                quantity    = count,
                                seller      = seller,
                                timeLeftSec = nil,  -- replicate has no timeLeft
                                isPlayer    = false,
                                hasOwner    = (seller ~= ""),
                            }
                            if not listing.hasOwner then b.hasInvalidSeller = true end
                            InsertListing(b.listings, listing, CACHE_LISTING_LIMIT)
                        end
                    end
                end
            end
        end
    end

    local stored = 0
    for k, b in pairs(buckets) do
        cache[k] = {
            listings         = b.listings,
            scannedAt        = now,
            source           = "replicate",
            hasInvalidSeller = b.hasInvalidSeller,
        }
        stored = stored + 1
    end
    return stored
end

--------------------------
-- Update notifications
--------------------------

-- A scan typically fires many events in quick succession. Notifying on
-- every single event would re-resolve pricing dozens of times per scan.
-- Debounce until the burst settles, then fire once.
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

-- Fire listeners immediately. Used by the auto-scanner when it knows it
-- just got the result it asked for and shouldn't wait the debounce window.
local function NotifyNow()
    if debounceTicker then
        debounceTicker:Cancel()
        debounceTicker = nil
    end
    for _, fn in ipairs(listeners) do
        pcall(fn)
    end
end

function ScanCache:RegisterUpdated(fn)
    if type(fn) == "function" then
        listeners[#listeners + 1] = fn
    end
end

function ScanCache:Notify()
    NotifyNow()
end

--------------------------
-- Event handling
--------------------------

local listener = CreateFrame("Frame", "FlipQueueScanListener")
listener:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
listener:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
listener:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
listener:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")

listener:SetScript("OnEvent", function(_, event, arg1)
    if event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemKey = arg1
        if type(itemKey) ~= "table" or not itemKey.itemID then return end
        local now = time()
        local n = HarvestNonCommodity(itemKey, now)
        -- Record that we covered this itemID on this realm. Variants that
        -- DIDN'T appear in the harvest get treated as "scanned, empty"
        -- on Lookup — letting ResolvePostPrice flip from scan_pending to
        -- ready (no competition) for ilvl variants no one's listed.
        itemScans[CurrentRealm() .. "|" .. tostring(itemKey.itemID)] = now
        ns:PrintDebug("[ScanCache] ITEM_SEARCH_RESULTS_UPDATED itemID=" ..
            tostring(itemKey.itemID) .. " harvested=" .. n)
        ScheduleNotify()  -- always fire, even if n=0 — empty harvest is still news

    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local itemID = arg1
        if not itemID then return end
        local now = time()
        local got = HarvestCommodity(itemID, now)
        itemScans[CurrentRealm() .. "|" .. tostring(itemID)] = now
        ns:PrintDebug("[ScanCache] COMMODITY_SEARCH_RESULTS_UPDATED itemID=" ..
            tostring(itemID) .. " harvested=" .. tostring(got))
        ScheduleNotify()

    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        -- Browse data is coarser — Blizzard gives us minPrice per ItemKey,
        -- not per-auction detail with full bonus IDs. Without per-listing
        -- data we can't apply IsAuctionFiltered, so a per-item or
        -- replicate scan should refine these. We still capture the floor
        -- as a hint when nothing better exists.
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
                if k and not cache[k] then
                    cache[k] = {
                        listings = {{
                            buyout      = br.minPrice,
                            quantity    = 1,
                            seller      = "",
                            timeLeftSec = nil,
                            isPlayer    = br.containsOwnerItem == true,
                            hasOwner    = false,
                        }},
                        scannedAt        = now,
                        source           = "browse",
                        hasInvalidSeller = true,  -- browse never gives sellers
                    }
                    stored = stored + 1
                end
            end
        end
        if stored > 0 then ScheduleNotify() end

    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        local stored = HarvestReplicate()
        if stored > 0 then
            ns:PrintDebug("[ScanCache] Replicate harvested " .. stored .. " entries")
            ScheduleNotify()
        end
    end
end)

--------------------------
-- Stale-entry hygiene
--------------------------

-- When the auto-scanner runs SendSearchQuery for an item, the resulting
-- ITEM_SEARCH_RESULTS_UPDATED event is authoritative for that itemID on
-- this realm at this moment. Any pre-existing cache entries for the same
-- itemID that DIDN'T appear in the new harvest are listings that have
-- since been bought, cancelled, or expired — wipe them so they stop
-- poisoning future posting decisions (the original 3,666g phantom-listing
-- bug was exactly this).
--
-- The auto-scanner registers `expectedItemIDs` before issuing the search;
-- after harvest fires NotifyNow(), it calls PruneStaleForItemIDs to wipe
-- entries that weren't refreshed.
function ScanCache:PruneStaleForItemIDs(itemIDs, beforeTime)
    if not itemIDs then return end
    local realm = CurrentRealm()
    for itemID in pairs(itemIDs) do
        local prefixItem = realm .. "|" .. tostring(itemID) .. ";"
        local prefixCommod = realm .. "|c:" .. tostring(itemID)
        for k, v in pairs(cache) do
            if v.scannedAt and v.scannedAt < beforeTime then
                if k:sub(1, #prefixItem) == prefixItem or k == prefixCommod then
                    cache[k] = nil
                end
            end
        end
    end
end

--------------------------
-- Public API
--------------------------

-- Look up the live-scan data for an item.
-- fqKey: FlipQueue's canonical "<itemID>;<bonusIDs>;<modifiers>" string.
-- isCommodity: caller already knows from C_AuctionHouse.GetItemCommodityStatus.
-- maxAgeSec: optional freshness ceiling. nil means no ceiling (return any age).
--   Pass DEFAULT_FRESH_AGE_SEC (or shorter) for posting decisions.
-- Returns a table or nil:
--   {
--     listings  = {{buyout, quantity, seller, timeLeftSec, isPlayer, hasOwner}, ...} (sorted asc by buyout),
--     lowestUnit, lowestIsPlayer  -- convenience for the cheapest listing
--     age       = seconds since scan,
--     source    = "item" | "commodity" | "browse" | "replicate",
--     hasInvalidSeller = bool,
--   }
function ScanCache:Lookup(fqKey, isCommodity, maxAgeSec)
    local key = MakeCacheKey(fqKey, isCommodity)
    if not key then return nil end

    local entry = cache[key]
    if entry then
        local age = time() - entry.scannedAt
        if not (maxAgeSec and age > maxAgeSec) then
            local lowest = entry.listings and entry.listings[1]
            return {
                listings         = entry.listings or {},
                lowestUnit       = lowest and lowest.buyout or nil,
                lowestIsPlayer   = lowest and lowest.isPlayer or false,
                age              = age,
                source           = entry.source,
                hasInvalidSeller = entry.hasInvalidSeller or false,
            }
        end
    end

    -- No entry for this fqKey, but if we recently scanned this itemID at
    -- all (any addon's query covers all variants), the variant just had
    -- no listings. Return a synthetic empty entry so the decision tree
    -- runs the empty-market branch (post at normal) instead of waiting
    -- forever in scan_pending.
    local itemID = fqKey and fqKey:match("^(%d+)") or nil
    if itemID then
        local scanKey = CurrentRealm() .. "|" .. itemID
        local lastScan = itemScans[scanKey]
        if lastScan then
            local age = time() - lastScan
            if not (maxAgeSec and age > maxAgeSec) then
                return {
                    listings         = {},
                    lowestUnit       = nil,
                    lowestIsPlayer   = false,
                    age              = age,
                    source           = "scanned-empty",
                    hasInvalidSeller = false,
                }
            end
        end
    end
    return nil
end

function ScanCache:DefaultFreshAge() return DEFAULT_FRESH_AGE_SEC end

function ScanCache:GetSize()
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    return n
end

function ScanCache:Clear()
    wipe(cache)
end

-- Drop the entry for a single fqKey. Used when an item is sold or
-- cancelled and we want the next post decision to require a fresh scan.
function ScanCache:Forget(fqKey, isCommodity)
    local key = MakeCacheKey(fqKey, isCommodity)
    if key then cache[key] = nil end
end

-- Write a sentinel "we scanned and there are zero listings" entry. Lets
-- ResolvePostPrice tell the difference between "never scanned" (status
-- scan_pending, post button stays disabled) and "scanned, market is
-- empty" (status ready, post at normalPrice). Used by AuctionAutoScan
-- when a SendSearchQuery times out without firing any event.
function ScanCache:MarkEmpty(fqKey, isCommodity)
    local key = MakeCacheKey(fqKey, isCommodity)
    if not key then return end
    cache[key] = {
        listings         = {},
        scannedAt        = time(),
        source           = "empty",
        hasInvalidSeller = false,
    }
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
        local lowest = r.entry.listings and r.entry.listings[1]
        local lowestStr = lowest and string.format("%.0fc", lowest.buyout) or "(empty)"
        local nList = r.entry.listings and #r.entry.listings or 0
        out[#out + 1] = string.format("%s: %s [%d listings] (%s, %ds old%s)",
            r.key, lowestStr, nList, r.entry.source or "?",
            time() - r.entry.scannedAt,
            (lowest and lowest.isPlayer) and ", own" or "")
    end
    return out, #rows
end

--------------------------
-- Persistence (cross-session)
--------------------------

local persistFrame = CreateFrame("Frame")
persistFrame:RegisterEvent("PLAYER_LOGIN")
persistFrame:RegisterEvent("PLAYER_LOGOUT")
persistFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if type(FlipQueueDB) == "table" and type(FlipQueueDB.scanCache) == "table" then
            local kept, dropped = 0, 0
            for k, v in pairs(FlipQueueDB.scanCache) do
                local valid = false
                -- Only accept the new key format (realm prefix + "t:" or
                -- "c:" suffix) AND a per-listing array. Legacy entries
                -- keyed on raw fqKey or the old minUnit shape are
                -- dropped — they don't align with TSM's canonical view
                -- and would inject ghost prices into post decisions. The
                -- cache rebuilds within a session or two from fresh scans.
                if type(k) == "string" and type(v) == "table" and v.scannedAt then
                    local suffix = k:match("|(.+)$")
                    if suffix and (suffix:find("^t:") or suffix:find("^c:")) then
                        if type(v.listings) == "table" then
                            valid = true
                        end
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
        if type(FlipQueueDB) == "table" and type(FlipQueueDB.itemScans) == "table" then
            for k, t in pairs(FlipQueueDB.itemScans) do
                if type(k) == "string" and type(t) == "number" then
                    itemScans[k] = t
                end
            end
        end

    elseif event == "PLAYER_LOGOUT" then
        if type(FlipQueueDB) ~= "table" then return end
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

        -- Persist itemScans too so the synthetic "scanned, no listings
        -- of this variant" branch survives logout. Same staleness window.
        local scans = {}
        for k, t in pairs(itemScans) do
            if (now - t) <= PERSIST_MAX_AGE then
                scans[k] = t
            end
        end
        FlipQueueDB.itemScans = scans
    end
end)
