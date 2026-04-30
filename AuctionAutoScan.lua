-- AuctionAutoScan.lua
-- Auto-scan kicker: when the AH opens with a queue of items to post, fire
-- per-item search queries so AuctionScanCache has fresh data when the
-- posting decision tree runs. Same pattern TSM uses internally for its
-- Post Scan — Blizzard returns ALL listings for the item via
-- ITEM_SEARCH_RESULTS_UPDATED / COMMODITY_SEARCH_RESULTS_UPDATED, our
-- AuctionScanCache listener harvests them, and ResolvePostPrice then has
-- live data to decide against.
--
-- Why we need this rather than relying on TSM's own scan:
--   1. The player may have FlipQueue open without ever clicking TSM's
--      Post Scan button — we'd be stuck reading stale snapshot data.
--   2. TSM's DBMinBuyout snapshot is loaded once per session from the
--      Desktop App, so without a live scan we can't know the current
--      lowest competitor.
--   3. Cache entries can be hours stale across sessions; the freshness
--      ceiling on Lookup means stale data is treated as "no data" and we
--      need a path to refresh on demand.

local addonName, ns = ...

local AutoScan = {}
ns.AuctionAutoScan = AutoScan

--------------------------
-- Throttle
--------------------------

-- Blizzard rate-limits AH search queries (the global API throttle is
-- ~10 queries/sec but in practice we get a "throttled" toast much sooner
-- on a packed realm). Spacing queries out 350ms apart stays well under
-- any threshold and lets results come back in order so the cache update
-- listener can refresh the UI in batches.
local QUERY_SPACING_MS = 350
-- After our auto-scan kicker queues a query, we wait this long for the
-- expected event before assuming the item has zero listings. The cache
-- entry is then marked empty so ResolvePostPrice treats it as the
-- empty-market branch.
local QUERY_TIMEOUT_SEC = 4

local pendingQueue = {}      -- ordered queue of pending scan tasks
-- inflight is keyed by an opaque scan key — the itemID for normal items
-- and "pet:<species>" for caged pets (so two species don't collapse onto
-- the shared Pet Cage itemID 82800).
local inflight = {}          -- scanKey -> { itemID, speciesID, isCommodity, fqKey, sentAt, callback }
local lastSendTime = 0       -- monotonic-ish (GetTime) of last SendSearchQuery
local kickerTicker = nil     -- C_Timer driving the queue

local function ScanKeyFor(itemID, speciesID)
    if speciesID and speciesID > 0 then
        return "pet:" .. tostring(speciesID)
    end
    return tostring(itemID)
end

local function ItemKeyFromID(itemID, speciesID)
    -- Blizzard's SendSearchQuery wants a full ItemKey tuple. We always pass
    -- itemLevel = 0 to match TSM's workaround for the old 9.0.1 ilvl bug:
    -- the server returns ALL variants of that itemID in one combined result
    -- list, which AuctionScanCache then buckets per-link.
    --
    -- For caged pets (itemID 82800 / Pet Cage), the AH search keys on
    -- battlePetSpeciesID — passing 0 yields a malformed query that returns
    -- nothing useful and never fires ITEM_SEARCH_RESULTS_UPDATED. Pass the
    -- caller's species so each species gets its own valid query.
    return {
        itemID              = itemID,
        itemLevel           = 0,
        itemSuffix          = 0,
        battlePetSpeciesID  = tonumber(speciesID) or 0,
    }
end

-- Pet fqKeys look like "pet:<species>;...". Extract the species so callers
-- can dedupe pet tasks by species (rather than the shared Pet Cage itemID
-- 82800) and feed it into ItemKeyFromID for a valid pet search.
local function PetSpeciesFromFqKey(fqKey)
    if type(fqKey) ~= "string" then return nil end
    local s = fqKey:match("^pet:(%d+)")
    return s and tonumber(s) or nil
end

local function NowSec()
    return GetTime and GetTime() or time()
end

local function HandleResolved(task, gotResults)
    if task.callback then
        pcall(task.callback, gotResults)
    end
end

local function CheckTimeouts()
    local now = NowSec()
    local expired = {}
    for scanKey, task in pairs(inflight) do
        if (now - task.sentAt) > QUERY_TIMEOUT_SEC then
            expired[#expired + 1] = scanKey
        end
    end
    if #expired == 0 then return end

    for _, scanKey in ipairs(expired) do
        local task = inflight[scanKey]
        inflight[scanKey] = nil
        if task then
            ns:PrintDebug("[AutoScan] TIMEOUT scanKey=" .. tostring(scanKey) ..
                " itemID=" .. tostring(task.itemID) ..
                (task.speciesID and (" species=" .. task.speciesID) or "") ..
                " (no event in " .. QUERY_TIMEOUT_SEC .. "s — assuming empty market)")
            -- No event came back. Treat as confirmed empty market for this
            -- item: wipe any stale cache entries AND mark each expected
            -- fqKey as empty so ResolvePostPrice flips from "scan pending"
            -- to "ready (no competition)" instead of staying stuck.
            local cache = ns.AuctionScanCache
            -- Prune is per-itemID; for pets that's the shared Pet Cage ID,
            -- but the prune walks listings by realm|<itemID>; prefix and
            -- bucket key collisions would only matter if we keyed pet
            -- buckets by itemID too — we don't, so this is a no-op for pets.
            if cache and cache.PruneStaleForItemIDs and not task.speciesID then
                cache:PruneStaleForItemIDs({ [task.itemID] = true }, time() + 1)
            end
            if cache and cache.MarkEmpty and task.expectedFqKeys then
                for fq in pairs(task.expectedFqKeys) do
                    cache:MarkEmpty(fq, task.isCommodity)
                end
            end
            HandleResolved(task, false)
        end
    end
    -- Push a synthetic update so the drawer's RerunPricing fires against
    -- the now-empty cache and rows flip from "scan pending" to "ready
    -- (no competition)" instead of staying stuck.
    if ns.AuctionScanCache and ns.AuctionScanCache.Notify then
        ns.AuctionScanCache:Notify()
    end
end

local function ProcessQueue()
    if #pendingQueue == 0 then
        return  -- ticker keeps running so CheckTimeouts can fire
    end

    local now = NowSec() * 1000
    local elapsed = now - lastSendTime
    if elapsed < QUERY_SPACING_MS then
        return  -- ticker will retry
    end

    -- Skip queries that have already been collapsed into an inflight slot.
    while #pendingQueue > 0 do
        local task = pendingQueue[1]
        local scanKey = ScanKeyFor(task.itemID, task.speciesID)
        if inflight[scanKey] then
            table.remove(pendingQueue, 1)
            -- Hand the callback off to whichever scan is in flight.
            local existing = inflight[scanKey]
            local prev = existing.callback
            existing.callback = function(ok)
                if prev then pcall(prev, ok) end
                if task.callback then pcall(task.callback, ok) end
            end
        else
            break
        end
    end
    if #pendingQueue == 0 then return end

    local task = table.remove(pendingQueue, 1)
    if not C_AuctionHouse then
        HandleResolved(task, false)
        return
    end

    local sent, errMsg
    -- Blizzard_AuctionHouseUI is load-on-demand and the AH wrapper APIs
    -- (SendSearchQuery, GetItemSearchResultInfo, etc.) only work once it
    -- has loaded. TSM doesn't always trigger the load — when the player
    -- has TSM's UI replacing the default frame, the Blizzard panel may
    -- never initialise. Force-load it before our first query.
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuctionHouseUI")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_AuctionHouseUI")
    end

    if C_AuctionHouse and C_AuctionHouse.SendSearchQuery then
        -- Both commodities and items use SendSearchQuery; the AH client
        -- routes based on itemID and fires the appropriate event
        -- (COMMODITY_SEARCH_RESULTS_UPDATED vs ITEM_SEARCH_RESULTS_UPDATED).
        -- Pass an empty sorts array — Blizzard documents `sorts` as a table,
        -- and some builds reject nil here.
        sent, errMsg = pcall(C_AuctionHouse.SendSearchQuery,
            ItemKeyFromID(task.itemID, task.speciesID), {}, false)
    end

    if not sent then
        ns:PrintDebug("[AutoScan] SendSearchQuery FAILED for itemID=" ..
            tostring(task.itemID) ..
            (task.speciesID and (" species=" .. task.speciesID) or "") ..
            " err=" .. tostring(errMsg) ..
            " UIloaded=" .. tostring(
                (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI"))
                or (IsAddOnLoaded and IsAddOnLoaded("Blizzard_AuctionHouseUI"))
                or "?"))
        HandleResolved(task, false)
        return
    end

    lastSendTime = NowSec() * 1000
    task.sentAt = NowSec()
    local scanKey = ScanKeyFor(task.itemID, task.speciesID)
    inflight[scanKey] = task
    ns:PrintDebug("[AutoScan] SendSearchQuery itemID=" .. tostring(task.itemID) ..
        (task.speciesID and (" species=" .. task.speciesID) or "") ..
        " commodity=" .. tostring(task.isCommodity) ..
        " (queued=" .. #pendingQueue .. ", inflight=" .. (function()
            local n = 0; for _ in pairs(inflight) do n = n + 1 end; return n
        end)() .. ")")
end

local function EnsureKickerRunning()
    if kickerTicker then return end
    -- Short repeating tick. Cancels itself only when both the pending
    -- queue is empty AND there are no inflight queries left waiting on
    -- responses (otherwise CheckTimeouts wouldn't run).
    kickerTicker = C_Timer.NewTicker(0.1, function()
        ProcessQueue()
        CheckTimeouts()
        if #pendingQueue == 0 and next(inflight) == nil then
            if kickerTicker then
                kickerTicker:Cancel()
                kickerTicker = nil
            end
        end
    end)
end

--------------------------
-- Public API
--------------------------

-- Player-facing gate. When the user has turned off FlipQueue's posting
-- flow (preferring TSM / Auctionator to drive the AH), we don't initiate
-- any scans. Passive cache harvesting still runs because the listener
-- frame is registered unconditionally — that's free data flowing in
-- whenever other addons scan.
local function PostingEnabled()
    return not (ns.db and ns.db.settings and ns.db.settings.ahPostingEnabled == false)
end

-- Snapshot for /fq debug perf. Exposes the queue/inflight counts so the
-- diagnostic command can report them without reaching into the file-locals.
function AutoScan:GetStats()
    local inflightCount = 0
    for _ in pairs(inflight) do inflightCount = inflightCount + 1 end
    return {
        queued   = #pendingQueue,
        inflight = inflightCount,
    }
end

-- Queue a single-item search. callback(gotResults) fires after the result
-- event lands or the timeout elapses. Idempotent on (itemID, isCommodity)
-- — if a scan is already inflight for this item, the callback chains on.
-- expectedFqKeys (optional): array of fqKey strings the caller already
-- knows about for this itemID. If the search times out with no event
-- (item not listed on this realm), we mark these fqKeys as "empty market"
-- in the cache so ResolvePostPrice flips from "scan pending" to "ready
-- (no competition)" instead of staying stuck.
function AutoScan:ScanItem(itemID, isCommodity, callback, expectedFqKeys)
    if not PostingEnabled() then
        if callback then pcall(callback, false) end
        return
    end
    itemID = tonumber(itemID)
    if not itemID then
        if callback then pcall(callback, false) end
        return
    end

    -- For caged pets all rows share itemID 82800; the differentiator is
    -- battlePetSpeciesID. Pull the species off the first expected fqKey
    -- so dedupe and SendSearchQuery target the right pet.
    local speciesID
    if expectedFqKeys then
        for _, fq in ipairs(expectedFqKeys) do
            local s = PetSpeciesFromFqKey(fq)
            if s then speciesID = s; break end
        end
    end

    local scanKey = ScanKeyFor(itemID, speciesID)
    if inflight[scanKey] then
        local existing = inflight[scanKey]
        if expectedFqKeys then
            existing.expectedFqKeys = existing.expectedFqKeys or {}
            for _, fq in ipairs(expectedFqKeys) do
                existing.expectedFqKeys[fq] = true
            end
        end
        local prev = existing.callback
        existing.callback = function(ok)
            if prev then pcall(prev, ok) end
            if callback then pcall(callback, ok) end
        end
        return
    end

    local fqSet
    if expectedFqKeys then
        fqSet = {}
        for _, fq in ipairs(expectedFqKeys) do fqSet[fq] = true end
    end
    pendingQueue[#pendingQueue + 1] = {
        itemID         = itemID,
        speciesID      = speciesID,
        isCommodity    = isCommodity == true,
        callback       = callback,
        expectedFqKeys = fqSet,
    }
    EnsureKickerRunning()
end

-- Queue scans for every item in a scanResults list (typically what
-- ContextDrawer holds). Skips items we already have fresh-enough data for.
-- onAllSettled() fires when the last scan completes (or times out).
function AutoScan:ScanQueue(scanResults, maxAgeSec, onAllSettled)
    if not PostingEnabled() then
        if onAllSettled then pcall(onAllSettled) end
        return
    end
    if not scanResults or #scanResults == 0 then
        if onAllSettled then pcall(onAllSettled) end
        return
    end

    local cache = ns.AuctionScanCache
    local fresh = maxAgeSec or (cache and cache:DefaultFreshAge()) or (30 * 60)

    -- Dedupe by itemID for normal items, but by speciesID for caged pets:
    -- every pet shares itemID 82800 / Pet Cage, so an itemID dedupe would
    -- eat every pet after the first regardless of how many distinct
    -- species are in the bag.
    local seen = {}
    local toScan = {}
    for _, entry in ipairs(scanResults) do
        if entry.itemID and entry.status ~= "dnt" then
            local species = PetSpeciesFromFqKey(entry.itemKey)
            local dedupeKey = species and ("pet:" .. species) or tostring(entry.itemID)
            if not seen[dedupeKey] then
                seen[dedupeKey] = true
                local stale = true
                if cache then
                    local hit = cache:Lookup(entry.itemKey, entry.isCommodity, fresh)
                    stale = (hit == nil)
                end
                if stale then
                    toScan[#toScan + 1] = entry
                end
            end
        end
    end

    ns:PrintDebug("[AutoScan] ScanQueue: " .. #scanResults .. " input, " ..
        #toScan .. " stale (need scan), freshAge=" .. fresh)
    if #toScan == 0 then
        if onAllSettled then pcall(onAllSettled) end
        return
    end

    local remaining = #toScan
    local function complete()
        remaining = remaining - 1
        if remaining <= 0 and onAllSettled then
            pcall(onAllSettled)
        end
    end

    for _, entry in ipairs(toScan) do
        local fqs = entry.itemKey and { entry.itemKey } or nil
        self:ScanItem(entry.itemID, entry.isCommodity, complete, fqs)
    end
end

-- Pre-post: ensure we have a fresh scan for THIS item before deciding the
-- price. callback(gotResults) fires once the scan settles. If we already
-- have fresh data, callback fires synchronously with true.
function AutoScan:EnsureFresh(fqKey, itemID, isCommodity, callback)
    if not PostingEnabled() then
        if callback then pcall(callback, false) end
        return
    end
    local cache = ns.AuctionScanCache
    if cache then
        local hit = cache:Lookup(fqKey, isCommodity, cache:DefaultFreshAge())
        if hit then
            if callback then pcall(callback, true) end
            return
        end
    end
    self:ScanItem(itemID, isCommodity, callback)
end

--------------------------
-- Event-driven resolution
--------------------------

-- When AuctionScanCache fires an updated notification (debounced burst end),
-- mark whichever inflight items got data as resolved. The cache lookup
-- itself is the authoritative "did the scan land?" check.
local function ResolveInflightFromCache()
    if next(inflight) == nil then return end
    local cache = ns.AuctionScanCache
    if not cache then return end
    local now = time()
    for scanKey, task in pairs(inflight) do
        local fqKey = task.fqKey
        if not fqKey then
            if task.speciesID then
                fqKey = "pet:" .. tostring(task.speciesID) .. ";;"
            else
                fqKey = tostring(task.itemID) .. ";;"
            end
        end
        local hit = cache:Lookup(fqKey, task.isCommodity)
        -- Result is "fresh" if the cache scan time is at or after when we
        -- queued the search. Loose timestamp comparison (1s slack) since
        -- cache uses time() seconds and our sentAt uses GetTime() seconds.
        if hit and (now - hit.age + 1) >= math.floor(task.sentAt) then
            inflight[scanKey] = nil
            HandleResolved(task, true)
        end
    end
end

-- Hook into the AH lifecycle. Listen for the cache's update notification
-- via RegisterUpdated, and trigger a queue scan when the AH first opens.
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
hookFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
hookFrame:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        ns:PrintDebug("[AutoScan] AH opened, posting=" .. tostring(PostingEnabled()))
        -- Auto-scan-on-open is opt-in via Settings → AH → "Auto-scan on AH
        -- open" (ahAutoScanOnOpen, default false). Without this gate FQ used
        -- to issue SendSearchQuery for every postable bag item on every AH
        -- open — running in parallel with TSM's Post Scan, doubling the
        -- AH-side load and producing the slowness reported in FQ-137. The
        -- passive AuctionScanCache listener still harvests whatever TSM
        -- scans regardless, and the drawer ships a "Scan Now" button for
        -- on-demand refresh.
        local autoOn = ns.db and ns.db.settings and ns.db.settings.ahAutoScanOnOpen
        if not autoOn then
            ns:PrintDebug("[AutoScan] auto-scan-on-open disabled — skipping")
            return
        end
        C_Timer.After(0.3, function()
            local results = ns._currentAHScanResults
            local source = "_currentAHScanResults"
            if (not results or #results == 0) and ns.AuctionPost and ns.AuctionPost.ScanBags then
                results = ns.AuctionPost:ScanBags(false)
                ns._currentAHScanResults = results
                source = "ScanBags(false)"
            end
            ns:PrintDebug("[AutoScan] post-open: " .. (results and #results or 0) ..
                " items via " .. source)
            if results and #results > 0 then
                AutoScan:ScanQueue(results)
            end
        end)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        wipe(pendingQueue)
        wipe(inflight)
        if kickerTicker then
            kickerTicker:Cancel()
            kickerTicker = nil
        end
    end
end)

-- Register late so AuctionScanCache is loaded.
local registerFrame = CreateFrame("Frame")
registerFrame:RegisterEvent("PLAYER_LOGIN")
registerFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if ns.AuctionScanCache and ns.AuctionScanCache.RegisterUpdated then
        ns.AuctionScanCache:RegisterUpdated(ResolveInflightFromCache)
    end
end)
