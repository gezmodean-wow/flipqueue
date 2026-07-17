-- TrackerTSMReconcile.lua
-- Cross-reference FlipQueue's auction log against TSM's accounting sales CSV
-- to upgrade entries that were really sold but didn't get their "sold" status
-- through the normal mail-scan path (e.g. user looted the gold-mail without FQ
-- running, or mail-scan missed a name match).
--
-- TSM stores sales per realm at TradeSkillMasterDB["r@<realm>@internalData@csvSales"]
-- with the header "itemString,stackSize,quantity,price,otherPlayer,player,time,source".
-- `price` is per-unit copper; total paid by buyer = price * quantity. `player`
-- is the seller character name (no realm — realm is implicit in the storage key).
local addonName, ns = ...

local Tracker = ns.Tracker

--------------------------
-- Cooperative yielding
--------------------------

-- The reconcile parses TSM's whole CSV corpus (three CSVs, tens of thousands of
-- rows for a heavy TSM user) and then walks the entire FQ log. It ran inline 2s
-- after AUCTION_HOUSE_SHOW and was a multi-second freeze on "open the AH and
-- post" (FQ-223). It's throttled to once an hour, but the throttle is
-- deliberately reset on PLAYER_LOGIN — and switching characters fires that — so
-- a player hopping realms pays it on nearly every AH open.
--
-- MaybeYield is a no-op when called on the main thread, so the synchronous entry
-- point (/fq slash command) keeps working unchanged.
local YIELD_EVERY = 2000
local yieldCounter = 0

local function MaybeYield()
    -- Lua 5.1: coroutine.running() returns nil on the main thread.
    if not coroutine.running() then return end
    yieldCounter = yieldCounter + 1
    if yieldCounter >= YIELD_EVERY then
        yieldCounter = 0
        coroutine.yield()
    end
end

--------------------------
-- Key helpers
--------------------------

-- Extract base item ID token from a FlipQueue itemKey ("itemID;bonus;mod" or
-- "pet:speciesID;;").
local function FQBaseID(fqKey)
    if not fqKey or fqKey == "" then return nil end
    local petID = fqKey:match("^pet:(%d+)")
    if petID then return "pet:" .. petID end
    return fqKey:match("^(%d+)")
end

-- Extract base item ID token from a TSM itemString ("i:12345", "i:12345::…",
-- "p:speciesID").
local function TSMBaseID(tsmItem)
    if not tsmItem or tsmItem == "" then return nil end
    local petID = tsmItem:match("^p:(%d+)")
    if petID then return "pet:" .. petID end
    return tsmItem:match("^i:(%d+)")
end

--------------------------
-- CSV parsing
--------------------------

-- TSM writes plain CSV without quoting (AH item strings, numeric fields, and
-- player names don't contain commas). Keep the parser minimal to match.
local function SplitCSVRow(row)
    local fields = {}
    local start = 1
    while true do
        local comma = row:find(",", start, true)
        if not comma then
            fields[#fields + 1] = row:sub(start)
            break
        end
        fields[#fields + 1] = row:sub(start, comma - 1)
        start = comma + 1
    end
    return fields
end

-- Returns a map colName -> index for a CSV header row.
local function IndexHeader(header)
    local cols = {}
    local idx = 1
    for col in header:gmatch("([^,]+)") do
        cols[col] = idx
        idx = idx + 1
    end
    return cols
end

--------------------------
-- Read TSM sales records
--------------------------

-- TSM and FQ may differ on how they represent realm names with whitespace —
-- TSM strips spaces in some session contexts; FQ uses the raw GetRealmName().
-- To make comparisons robust, canonicalize both sides by stripping whitespace.
local function CanonicalCharKey(charKey)
    if not charKey then return nil end
    return (charKey:gsub("%s+", ""))
end

-- Generic reader for any per-realm TSM CSV under
-- TradeSkillMasterDB[r@<realm>@internalData@<csvName>]. Returns an array of
-- normalized records of the shape:
--   { charKey, baseID, price, quantity, stackSize, time, realm }
--
-- - `csvName`        — TSM key suffix ("csvSales" | "csvExpired" | "csvCancelled").
-- - `requireSource`  — optional string; when set, rows are kept only if the CSV
--                      has a `source` column with that value (sales records
--                      include both Auction and Vendor; we want Auction only).
--                      Expired/cancelled CSVs don't have a source column, so
--                      pass nil to skip the filter.
--
-- Missing optional columns (price, source) are tolerated — the parser keys
-- only on whatever's present in the header, so future TSM schema additions
-- won't break us.
local function ReadTSMCSV(csvName, requireSource)
    if type(TradeSkillMasterDB) ~= "table" then return {} end

    local records = {}
    local pattern = "^r@(.-)@internalData@" .. csvName .. "$"
    for key, value in pairs(TradeSkillMasterDB) do
        local realm = key:match(pattern)
        if realm and type(value) == "string" and value ~= "" then
            local headerEnd = value:find("\n", 1, true)
            if headerEnd then
                local header = value:sub(1, headerEnd - 1)
                local cols = IndexHeader(header)
                local colItem   = cols.itemString
                local colStack  = cols.stackSize
                local colQty    = cols.quantity
                local colPrice  = cols.price          -- absent on expire/cancel
                local colPlayer = cols.player
                local colTime   = cols.time
                local colSource = cols.source         -- absent on expire/cancel
                if colItem and colPlayer and colTime then
                    local pos = headerEnd + 1
                    local len = #value
                    while pos <= len do
                        MaybeYield()
                        local nlPos = value:find("\n", pos, true) or (len + 1)
                        if nlPos > pos then
                            local row = value:sub(pos, nlPos - 1)
                            local fields = SplitCSVRow(row)
                            local sourceOk = (not requireSource)
                                or (colSource and fields[colSource] == requireSource)
                            if sourceOk then
                                local baseID = TSMBaseID(fields[colItem])
                                local price = colPrice and tonumber(fields[colPrice]) or 0
                                local quantity = tonumber(fields[colQty] or "1") or 1
                                local stackSize = tonumber(fields[colStack] or "1") or 1
                                local timestamp = tonumber(fields[colTime])
                                local player = fields[colPlayer]
                                if baseID and timestamp and player and player ~= "" then
                                    records[#records + 1] = {
                                        charKey   = CanonicalCharKey(player .. "-" .. realm),
                                        baseID    = baseID,
                                        price     = price,
                                        quantity  = quantity,
                                        stackSize = stackSize,
                                        time      = timestamp,
                                        realm     = realm,
                                    }
                                end
                            end
                        end
                        pos = nlPos + 1
                    end
                end
            end
        end
    end
    return records
end

-- Returns array of sale records (Auction only — Vendor sales filtered out).
function Tracker:GetTSMSalesRecords()
    return ReadTSMCSV("csvSales", "Auction")
end

-- Returns array of expiration records. Each row corresponds to an auction
-- whose timer ran out and the item was returned to the seller.
function Tracker:GetTSMExpireRecords()
    return ReadTSMCSV("csvExpired", nil)
end

-- Returns array of cancellation records. Each row corresponds to an auction
-- the player (or an addon like TSM Cancelling) cancelled before it sold.
function Tracker:GetTSMCancelRecords()
    return ReadTSMCSV("csvCancelled", nil)
end

--------------------------
-- Reconcile
--------------------------

-- Entries are eligible if:
--   - _tsmReconciled flag not yet set AND
--   - status in {expired, cancelled} OR (status==collected AND saleOutcome != "sold")
-- A "collected" entry with no saleOutcome is unresolved (came from phase-2 of
-- CheckOwnedAuctions without a mail match); collected+"expired" is what the
-- mail scan set for returned items. We allow TSM to override the latter: TSM
-- reads invoice data with auction-specific IDs, so it's a stronger signal
-- than a name match against a returned-item mail.
local function IsEligible(entry)
    if entry._tsmReconciled then return false end
    local s = entry.auctionStatus
    if s == "sold" then return false end
    if s == "expired" or s == "cancelled" then return true end
    if s == "collected" and entry.saleOutcome ~= "sold" then return true end
    return false
end

-- Match window: an auction can sell any time between postedAt and
-- postedAt + 48h (AH duration). Add 1h of slack for clock drift / delayed
-- invoice timestamps.
local MATCH_WINDOW_PRE  = 60 * 60
local MATCH_WINDOW_POST = 48 * 60 * 60 + 60 * 60

-- Build a charKey -> baseID -> [records] index. Used three times below
-- (sales, expires, cancels) so worth a helper.
local function IndexByCharAndBase(records)
    local index = {}
    for _, rec in ipairs(records) do
        index[rec.charKey] = index[rec.charKey] or {}
        index[rec.charKey][rec.baseID] = index[rec.charKey][rec.baseID] or {}
        local list = index[rec.charKey][rec.baseID]
        list[#list + 1] = rec
    end
    return index
end

-- Find a TSM record matching the given log entry within the auction window.
-- Marks the record as consumed via usedRec so two log entries can't claim
-- the same TSM record. Returns the matched record or nil.
local function FindTSMMatch(entry, index, usedRec)
    local baseID = FQBaseID(entry.itemKey)
    local canonKey = entry.charKey and CanonicalCharKey(entry.charKey) or nil
    local byChar = canonKey and index[canonKey] or nil
    local candidates = baseID and byChar and byChar[baseID] or nil
    if not candidates then return nil end

    local postedAt = entry.postedAt or 0
    local earliest = postedAt - MATCH_WINDOW_PRE
    local latest   = postedAt + MATCH_WINDOW_POST
    for _, rec in ipairs(candidates) do
        if not usedRec[rec]
            and rec.time >= earliest
            and rec.time <= latest then
            usedRec[rec] = true
            return rec
        end
    end
    return nil
end

-- Mirror the postHistory tracking that ScanMailForSales does for returned-item
-- mail, so accounting reflects this attempt's posting fee even when TSM is
-- the only authoritative source. Idempotent only via the _tsmReconciled flag
-- — callers must guard against double-invocation.
local function RecordFailedAttempt(entry, endTime, endKind)
    entry.postAttempts = (entry.postAttempts or 0) + 1
    entry.postHistory = entry.postHistory or {}
    table.insert(entry.postHistory, {
        postedAt    = entry.postedAt,
        expiredAt   = endTime,
        postedPrice = entry.postedPrice,
        fee         = entry.ahFee or 0,
        endReason   = endKind,
    })
    entry.totalFeesSpent = (entry.totalFeesSpent or 0) + (entry.ahFee or 0)
end

-- Public API. verbose=true prints summary to chat; otherwise silent unless
-- there's a non-zero upgrade.
function Tracker:ReconcileWithTSM(verbose)
    if not ns.db or not ns.db.log then return 0, 0 end
    if type(TradeSkillMasterDB) ~= "table" then
        if verbose then
            ns:Print(ns.COLORS.YELLOW .. "TSM is not loaded — reconcile skipped.|r")
        end
        return 0, 0
    end

    local salesRecords  = self:GetTSMSalesRecords()
    local expireRecords = self:GetTSMExpireRecords()
    local cancelRecords = self:GetTSMCancelRecords()

    if #salesRecords == 0 and #expireRecords == 0 and #cancelRecords == 0 then
        if verbose then
            ns:Print(ns.COLORS.YELLOW .. "No TSM accounting records found.|r")
        end
        return 0, 0
    end

    local salesIndex  = IndexByCharAndBase(salesRecords)
    local expireIndex = IndexByCharAndBase(expireRecords)
    local cancelIndex = IndexByCharAndBase(cancelRecords)

    -- Each TSM record can only be claimed once. Sales, expires, and cancels
    -- are physically distinct rows so we technically only need three sets,
    -- but a single shared set keeps the bookkeeping uniform.
    local usedRec = {}
    local upgraded, expiredMatched, cancelledMatched, scanned, finalized = 0, 0, 0, 0, 0
    local now = time()

    for _, entry in ipairs(ns.db.log) do
        MaybeYield()
        if IsEligible(entry) then
            scanned = scanned + 1
            local matched = false

            -- Priority 1: sale match. If TSM saw this auction sell, that's
            -- the strongest signal — overrides any prior expired/cancelled
            -- guess from mail-side reconciliation.
            local saleRec = FindTSMMatch(entry, salesIndex, usedRec)
            if saleRec then
                entry.auctionStatus  = "sold"
                entry.saleOutcome    = "sold"
                entry.endReason      = "sold"
                entry.soldAt         = saleRec.time
                entry.soldPrice      = saleRec.price * saleRec.quantity
                entry.collectedAt    = entry.collectedAt or saleRec.time
                entry._tsmMatchedAt  = now
                upgraded = upgraded + 1
                matched = true
            end

            -- Priority 2: expire match. Only run for entries that aren't
            -- already finalized (collected) — those have whatever accounting
            -- the mail-side path produced and we don't want to double-count
            -- postHistory or fees.
            if not matched and entry.auctionStatus ~= "collected" then
                local expireRec = FindTSMMatch(entry, expireIndex, usedRec)
                if expireRec then
                    entry.auctionStatus       = "collected"
                    entry.saleOutcome         = "expired"
                    entry.endReason           = "expired"
                    entry.expiresAt           = entry.expiresAt or expireRec.time
                    entry.collectedAt         = entry.collectedAt or now
                    entry._tsmExpireMatchedAt = now
                    RecordFailedAttempt(entry, expireRec.time, "expired")
                    expiredMatched = expiredMatched + 1
                    matched = true
                end
            end

            -- Priority 3: cancel match. Same guard as expires. Cancellations
            -- get saleOutcome="expired" for backward-compat with code that
            -- treats anything non-sold as failed; the precise cause lives in
            -- endReason.
            if not matched and entry.auctionStatus ~= "collected" then
                local cancelRec = FindTSMMatch(entry, cancelIndex, usedRec)
                if cancelRec then
                    entry.auctionStatus       = "collected"
                    entry.saleOutcome         = "expired"
                    entry.endReason           = "cancelled"
                    entry.cancelledAt         = cancelRec.time
                    entry.collectedAt         = entry.collectedAt or now
                    entry._tsmCancelMatchedAt = now
                    RecordFailedAttempt(entry, cancelRec.time, "cancelled")
                    cancelledMatched = cancelledMatched + 1
                    matched = true
                end
            end

            if not matched then
                -- No TSM match of any kind. If the auction window has
                -- definitely closed (posted > 49h ago) and the entry is in
                -- the "collected, outcome unknown" limbo set by
                -- CheckOwnedAuctions phase 2, finalize it as expired.
                -- Without this step, entries sit forever counted as neither
                -- sold nor failed.
                local postedAt = entry.postedAt or 0
                local ended = (postedAt > 0) and (postedAt + MATCH_WINDOW_POST < now)
                if ended
                    and entry.auctionStatus == "collected"
                    and not entry.saleOutcome then
                    entry.saleOutcome = "expired"
                    entry.endReason   = entry.endReason or "expired"
                    finalized = finalized + 1
                end
            end

            -- Flag so we don't re-check the same entry against the same TSM
            -- DB on every AH open. `/fq reconcile reset` clears this.
            entry._tsmReconciled = true
        end
    end

    local touched = upgraded + expiredMatched + cancelledMatched + finalized
    if touched > 0 then
        if ns.SalesIndex then ns.SalesIndex:Invalidate() end
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    end

    if verbose or touched > 0 then
        local parts = {}
        if upgraded > 0 then table.insert(parts, ns.COLORS.GREEN .. upgraded .. "|r upgraded to sold") end
        if expiredMatched > 0 then table.insert(parts, ns.COLORS.YELLOW .. expiredMatched .. "|r matched as expired") end
        if cancelledMatched > 0 then table.insert(parts, ns.COLORS.YELLOW .. cancelledMatched .. "|r matched as cancelled") end
        if finalized > 0 then table.insert(parts, finalized .. " finalized as expired") end
        if #parts == 0 then table.insert(parts, "no eligible entries matched") end
        ns:Print("TSM reconcile: " .. table.concat(parts, ", ") ..
            " (scanned " .. scanned .. ").")
    end
    return upgraded + expiredMatched + cancelledMatched, scanned
end

-- Clear the _tsmReconciled flag on all entries so the next reconcile pass
-- rechecks them. Useful if the user imports fresh TSM data mid-session.
function Tracker:ResetTSMReconcile()
    if not ns.db or not ns.db.log then return 0 end
    local cleared = 0
    for _, entry in ipairs(ns.db.log) do
        if entry._tsmReconciled then
            entry._tsmReconciled = nil
            entry._tsmMatchedAt = nil
            cleared = cleared + 1
        end
    end
    return cleared
end

-- Async form of ReconcileWithTSM (FQ-223). Same work, same result, spread
-- across frames via the MaybeYield calls in the CSV and log loops. Used by the
-- automatic AH-open path; /fq's manual reconcile still calls the sync form,
-- where a brief stall is expected and the player asked for it.
-- onDone(upgraded, finalized) fires when complete, or (0, 0) if it errored.
-- Only one reconcile at a time. The async form now spans many frames while
-- iterating ns.db.log, so a second run (or a manual /fq reconcile) starting
-- mid-flight would walk the same entries against the same TSM records with a
-- separate `usedRec` claim set.
function Tracker:IsReconcilingTSM()
    return Tracker._tsmReconcileInFlight and true or false
end

function Tracker:ReconcileWithTSMAsync(verbose, onDone)
    if Tracker._tsmReconcileInFlight then
        if onDone then onDone(0, 0) end
        return false
    end
    Tracker._tsmReconcileInFlight = true
    yieldCounter = 0

    local co = coroutine.create(function()
        return self:ReconcileWithTSM(verbose)
    end)

    local function Pump()
        local ok, a, b = coroutine.resume(co)
        if not ok then
            Tracker._tsmReconcileInFlight = false
            if geterrorhandler then geterrorhandler()(a) end
            if onDone then onDone(0, 0) end
            return
        end
        if coroutine.status(co) == "dead" then
            Tracker._tsmReconcileInFlight = false
            if onDone then onDone(a or 0, b or 0) end
        else
            C_Timer.After(0, Pump)
        end
    end

    Pump()
    return true
end

-- TSM rewrites csvSales on logout, so each new session may bring data that
-- wasn't available when we last reconciled. Drop the per-entry flag and the
-- throttle timestamp on PLAYER_LOGIN so the next AH open re-scans all
-- eligible entries once.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    C_Timer.After(5, function()
        if Tracker.ResetTSMReconcile then Tracker:ResetTSMReconcile() end
        Tracker._tsmLastReconcile = nil
    end)
end)
