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

-- Runtime ceiling on the live cache (FQ-223). PERSIST_MAX_ENTRIES used to be
-- enforced only at PLAYER_LOGOUT, so a session that harvested a full auction
-- house grew `cache` without bound — a heavy user reported addon memory going
-- from 109 MB to 438 MB in one session, because a busy realm has far more
-- distinct item variants than the persist cap. Evict here instead, so the live
-- set is bounded regardless of how much gets harvested.
--
-- Evicting exactly at the cap would mean a sort per insert once full. Let the
-- table run up to _SLACK over the cap, then sweep back down to it, so the
-- O(n log n) sweep amortizes to roughly one pass per EVICT_SLACK inserts.
local RUNTIME_MAX_ENTRIES = PERSIST_MAX_ENTRIES
local EVICT_SLACK = 4000

local cacheCount = 0

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
-- Memoized: the realm can't change without a full client restart, and this sits
-- on every Lookup/Forget/MarkEmpty and every iteration of the replicate harvest
-- — it was allocating two strings per call (FQ-223). Only cache once the API
-- returns a real name; it's nil this early on some load paths, and caching
-- "Unknown" would poison every key for the session.
local realmCache
local function CurrentRealm()
    if realmCache then return realmCache end
    local r = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    -- Lowercase to match the old gsub():lower() fallback exactly — keys written
    -- during the early nil-realm window must stay comparable across builds.
    if not r or r == "" then return "unknown" end
    realmCache = r:gsub("%s+", ""):lower()
    return realmCache
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
-- Cache accessors (counted + bounded)
--------------------------

-- All cache writes/deletes go through these so `cacheCount` stays honest --
-- counting a 20k-entry hash with pairs() on every insert would defeat the point.

local function EvictOldest()
    local rows = {}
    for k, v in pairs(cache) do
        rows[#rows + 1] = { k = k, at = v.scannedAt or 0 }
    end
    table.sort(rows, function(a, b) return a.at > b.at end)
    for i = RUNTIME_MAX_ENTRIES + 1, #rows do
        cache[rows[i].k] = nil
    end
    cacheCount = math.min(#rows, RUNTIME_MAX_ENTRIES)
    ns:PrintDebug("[ScanCache] evicted to " .. cacheCount .. " entries")
end

local function SetCacheEntry(k, v)
    if cache[k] == nil then cacheCount = cacheCount + 1 end
    cache[k] = v
    if cacheCount > RUNTIME_MAX_ENTRIES + EVICT_SLACK then
        EvictOldest()
    end
end

local function DeleteCacheEntry(k)
    if cache[k] ~= nil then
        cache[k] = nil
        cacheCount = cacheCount - 1
    end
end

--------------------------
-- Listing insertion
--------------------------

-- Insert a listing into a buyout-ascending array, capped at `limit`. Listings
-- past the cap fall off; ties preserve insertion order so the player's own
-- listing doesn't get bumped by an identically-priced competitor.
-- Cheap pre-check so callers in a 200k-auction loop don't allocate a listing
-- table that InsertListing would immediately drop (FQ-223). `listings` is
-- buyout-ascending and capped at `limit`, so once it's full the only way in is
-- to beat the current worst. Mirrors InsertListing's strict `<` so ties are
-- rejected identically (insertion order preserved).
local function WouldAcceptListing(listings, buyout, limit)
    local n = #listings
    if n < limit then return true end
    return buyout < listings[n].buyout
end

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
                -- Non-commodity listings are atomic: buyers pay the full
                -- buyoutAmount for the whole stack. Store the listing-level
                -- buyout (NOT per-unit) so MakePostDecision compares against
                -- TSM's "lowest auction buyout" — TSM's posting flow keys
                -- below-min / undercut on listing buyout for items, and on
                -- per-unit price only for commodities.
                local listingBuyout = info.buyoutAmount
                if listingBuyout > 0 then
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
                                buyout      = listingBuyout,
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
        SetCacheEntry(k, {
            listings         = b.listings,
            scannedAt        = now,
            source           = "item",
            hasInvalidSeller = b.hasInvalidSeller,
        })
        stored = stored + 1
        -- Per-bucket detail for canonicalisation diagnostics. Helps spot
        -- when listings TSM treats as the same variant land in different
        -- buckets (or vice versa) — that's where post-price mismatches
        -- with TSM originate.
        local lo = b.listings[1]
        if lo and ns:IsDebugEnabled() then
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
    SetCacheEntry(k, {
        listings         = listings,
        scannedAt        = now,
        source           = "commodity",
        hasInvalidSeller = hasInvalidSeller,
    })
    return true
end

-- Auctionator's Full Scan path uses C_AuctionHouse.ReplicateItems →
-- REPLICATE_ITEM_LIST_UPDATE.
--
-- Replicate batches can be 50k–200k auctions on a busy realm. This used to
-- iterate inline in the event handler and was a multi-second hard freeze
-- (FQ-223) — and FlipQueue doesn't even initiate it: any Auctionator full scan
-- triggers the event, so the stall hit players who never asked FQ to scan. The
-- cost scales with realm auction volume, which is why the same user saw it
-- "better on some servers and much worse on others".
--
-- Now chunked across frames via C_Timer. Blizzard's replicate list stays valid
-- until the next ReplicateItems() call, so a fresh REPLICATE_ITEM_LIST_UPDATE
-- mid-run invalidates our indices — we cancel and restart rather than commit
-- data read across two different snapshots.
local REPLICATE_CHUNK = 2000
local replicateRun = 0

local function HarvestReplicateAsync(onDone)
    if not C_AuctionHouse or not C_AuctionHouse.GetNumReplicateItems then
        if onDone then onDone(0) end
        return
    end
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    if n == 0 then
        if onDone then onDone(0) end
        return
    end

    replicateRun = replicateRun + 1
    local myRun = replicateRun

    local realm = CurrentRealm()
    local now = time()
    local buckets = {}
    local i = 0

    local function Step()
        -- A newer replicate snapshot superseded us; drop this run's work.
        if myRun ~= replicateRun then return end

        -- ReplicateItems() invalidates the list when it's CALLED, but
        -- REPLICATE_ITEM_LIST_UPDATE (which bumps replicateRun) only fires when
        -- the new data lands — so the run token alone can't catch a snapshot
        -- swapped out mid-walk. Reading indices across two snapshots would
        -- commit a mixed cheapest-10 and mark it fresh: silently wrong post
        -- prices, no error. A size change is the cheap detectable signal; on
        -- any change, abandon rather than commit half-truth. The old inline
        -- harvest was atomic within one event and immune to this.
        local live = C_AuctionHouse.GetNumReplicateItems() or 0
        if live ~= n then return end

        local stop = math.min(i + REPLICATE_CHUNK, n)
        while i < stop do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner = C_AuctionHouse.GetReplicateItemInfo(i)
            if buyout and buyout > 0 and count and count > 0 then
                local link = C_AuctionHouse.GetReplicateItemLink(i)
                if link then
                    local id, bonus, mods = ns:ParseItemLink(link)
                    if id then
                        local fqKey = ns:MakeItemKey(id, bonus, mods)
                        local k = MakeCacheKey(fqKey, false, realm)
                        if k then
                            -- Replicate is non-commodity in retail (commodities
                            -- go through SendSearchQuery → GetCommoditySearchResults).
                            -- Same per-listing semantic as HarvestNonCommodity:
                            -- store the full listing buyout, not buyout/count.
                            local b = buckets[k]
                            if not b then
                                b = { listings = {}, hasInvalidSeller = false }
                                buckets[k] = b
                            end
                            local seller = owner or ""
                            -- Check before allocating: on a full realm most
                            -- auctions lose to the 10 cheapest already held, so
                            -- building the table first made ~199k of every 200k
                            -- immediate garbage.
                            if seller == "" then b.hasInvalidSeller = true end
                            if WouldAcceptListing(b.listings, buyout, CACHE_LISTING_LIMIT) then
                                InsertListing(b.listings, {
                                    buyout      = buyout,
                                    quantity    = count,
                                    seller      = seller,
                                    timeLeftSec = nil,  -- replicate has no timeLeft
                                    isPlayer    = false,
                                    hasOwner    = (seller ~= ""),
                                }, CACHE_LISTING_LIMIT)
                            end
                        end
                    end
                end
            end
            i = i + 1
        end

        if i < n then
            C_Timer.After(0, Step)
            return
        end

        local stored = 0
        for k, b in pairs(buckets) do
            SetCacheEntry(k, {
                listings         = b.listings,
                scannedAt        = now,
                source           = "replicate",
                hasInvalidSeller = b.hasInvalidSeller,
            })
            stored = stored + 1
        end
        if onDone then onDone(stored) end
    end

    Step()
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
        --
        -- Caged pets all share itemID 82800; key per-species instead so
        -- "we scanned species X" doesn't get misread as "we scanned all
        -- pets" when only one species was queried.
        local scanIdent
        if itemKey.battlePetSpeciesID and itemKey.battlePetSpeciesID > 0 then
            scanIdent = "pet:" .. tostring(itemKey.battlePetSpeciesID)
        else
            scanIdent = tostring(itemKey.itemID)
        end
        itemScans[CurrentRealm() .. "|" .. scanIdent] = now
        ns:PrintDebug("[ScanCache] ITEM_SEARCH_RESULTS_UPDATED itemID=" ..
            tostring(itemKey.itemID) ..
            ((itemKey.battlePetSpeciesID and itemKey.battlePetSpeciesID > 0)
                and (" species=" .. itemKey.battlePetSpeciesID) or "") ..
            " harvested=" .. n)
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
                -- Overwrite synthetic empty sentinels: a real browse hit
                -- is better than a stale "we timed out, assume empty"
                -- marker. Don't overwrite real item-scan data — that has
                -- per-listing detail (sellers, time-left) browse can't
                -- provide.
                local existing = k and cache[k]
                local stomp = existing and existing.source == "empty"
                if k and (not existing or stomp) then
                    SetCacheEntry(k, {
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
                    })
                    stored = stored + 1
                end
            end
        end
        if stored > 0 then ScheduleNotify() end

    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        HarvestReplicateAsync(function(stored)
            if stored > 0 then
                ns:PrintDebug("[ScanCache] Replicate harvested " .. stored .. " entries")
                ScheduleNotify()
            end
        end)
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
-- Walks the cache ONCE for the whole itemID set (FQ-223). This used to nest a
-- full pairs(cache) inside the itemID loop, and CheckTimeouts calls it per
-- timed-out item — on a realm where many queued items simply aren't listed,
-- 150 timeouts x 20k entries was ~3M iterations, each allocating a substring
-- via k:sub(). Build the prefix set first, then one pass with an
-- allocation-free find(..., plain) prefix test.
function ScanCache:PruneStaleForItemIDs(itemIDs, beforeTime)
    if not itemIDs then return end
    local realm = CurrentRealm()

    local itemPrefixes, commodKeys = {}, {}
    local any = false
    for itemID in pairs(itemIDs) do
        itemPrefixes[#itemPrefixes + 1] = realm .. "|" .. tostring(itemID) .. ";"
        commodKeys[realm .. "|c:" .. tostring(itemID)] = true
        any = true
    end
    if not any then return end

    for k, v in pairs(cache) do
        if v.scannedAt and v.scannedAt < beforeTime then
            local match = commodKeys[k]
            if not match then
                for i = 1, #itemPrefixes do
                    if k:find(itemPrefixes[i], 1, true) == 1 then
                        match = true
                        break
                    end
                end
            end
            if match then DeleteCacheEntry(k) end
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
    --
    -- Pet fqKeys ("pet:<species>;...") need their own branch: the digit-
    -- prefix regex doesn't match them, and we key itemScans per-species
    -- (not by the shared Pet Cage itemID 82800) so each species has its
    -- own "scanned" sentinel.
    local scanIdent
    if fqKey then
        local species = fqKey:match("^pet:(%d+)")
        if species then
            scanIdent = "pet:" .. species
        else
            scanIdent = fqKey:match("^(%d+)")
        end
    end
    if scanIdent then
        local scanKey = CurrentRealm() .. "|" .. scanIdent
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
    cacheCount = 0
end

-- Drop the entry for a single fqKey. Used when an item is sold or
-- cancelled and we want the next post decision to require a fresh scan.
function ScanCache:Forget(fqKey, isCommodity)
    local key = MakeCacheKey(fqKey, isCommodity)
    if key then DeleteCacheEntry(key) end
end

-- Write a sentinel "we scanned and there are zero listings" entry. Lets
-- ResolvePostPrice tell the difference between "never scanned" (status
-- scan_pending, post button stays disabled) and "scanned, market is
-- empty" (status ready, post at normalPrice). Used by AuctionAutoScan
-- when a SendSearchQuery times out without firing any event.
function ScanCache:MarkEmpty(fqKey, isCommodity)
    local key = MakeCacheKey(fqKey, isCommodity)
    if not key then return end
    -- Don't stomp real listings the browse or item listener already
    -- harvested. SendSearchQuery timeouts are a hint, not authoritative —
    -- if we have actual data, keep it.
    local existing = cache[key]
    if existing and existing.listings and #existing.listings > 0 then
        return
    end
    SetCacheEntry(key, {
        listings         = {},
        scannedAt        = time(),
        source           = "empty",
        hasInvalidSeller = false,
    })
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
            -- Seed the counter from the load rather than incrementing through
            -- SetCacheEntry per key — the saved set is already within the cap,
            -- and this avoids an eviction sweep during login.
            cacheCount = kept
            if dropped > 0 then
                ns:PrintDebug("[ScanCache] loaded " .. kept ..
                    " entries, dropped " .. dropped .. " from older build")
            end
            -- Release the SavedVariables table now that `cache` holds the
            -- entries (FQ-223). It shares references with `cache`, so keeping it
            -- around pinned every *superseded* entry — each rescan of a cached
            -- item leaked its previous listings for the rest of the session.
            -- PLAYER_LOGOUT rebuilds it from scratch, including on /reload.
            FlipQueueDB.scanCache = nil
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
