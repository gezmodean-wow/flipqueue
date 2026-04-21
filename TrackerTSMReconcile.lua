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

-- Returns array of sale records: {charKey, baseID, price, quantity, stackSize, time, realm}.
-- Reads every realm stored in TradeSkillMasterDB — reconciling across all our
-- characters at once means a single pass can resolve sales on any alt.
function Tracker:GetTSMSalesRecords()
    if type(TradeSkillMasterDB) ~= "table" then return {} end

    local records = {}
    for key, value in pairs(TradeSkillMasterDB) do
        local realm = key:match("^r@(.-)@internalData@csvSales$")
        if realm and type(value) == "string" and value ~= "" then
            local headerEnd = value:find("\n", 1, true)
            if headerEnd then
                local header = value:sub(1, headerEnd - 1)
                local cols = IndexHeader(header)
                local colItem   = cols.itemString
                local colStack  = cols.stackSize
                local colQty    = cols.quantity
                local colPrice  = cols.price
                local colPlayer = cols.player
                local colTime   = cols.time
                local colSource = cols.source
                if colItem and colPrice and colPlayer and colTime and colSource then
                    local pos = headerEnd + 1
                    local len = #value
                    while pos <= len do
                        local nlPos = value:find("\n", pos, true) or (len + 1)
                        if nlPos > pos then
                            local row = value:sub(pos, nlPos - 1)
                            local fields = SplitCSVRow(row)
                            if fields[colSource] == "Auction" then
                                local baseID = TSMBaseID(fields[colItem])
                                local price = tonumber(fields[colPrice])
                                local quantity = tonumber(fields[colQty] or "1") or 1
                                local stackSize = tonumber(fields[colStack] or "1") or 1
                                local timestamp = tonumber(fields[colTime])
                                local player = fields[colPlayer]
                                if baseID and price and timestamp and player and player ~= "" then
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

    local records = self:GetTSMSalesRecords()
    if #records == 0 then
        if verbose then
            ns:Print(ns.COLORS.YELLOW .. "No TSM sales records found.|r")
        end
        return 0, 0
    end

    -- Index: charKey -> baseID -> array of records, sorted by time ascending
    local index = {}
    for _, rec in ipairs(records) do
        index[rec.charKey] = index[rec.charKey] or {}
        index[rec.charKey][rec.baseID] = index[rec.charKey][rec.baseID] or {}
        local list = index[rec.charKey][rec.baseID]
        list[#list + 1] = rec
    end

    -- Track which TSM records we've already consumed so two log entries can't
    -- both claim the same sale.
    local usedRec = {}
    local upgraded, scanned, finalized = 0, 0, 0
    local now = time()

    for _, entry in ipairs(ns.db.log) do
        if IsEligible(entry) then
            scanned = scanned + 1
            local matched = false
            local baseID = FQBaseID(entry.itemKey)
            local canonKey = entry.charKey and CanonicalCharKey(entry.charKey) or nil
            local byChar = canonKey and index[canonKey] or nil
            local candidates = baseID and byChar and byChar[baseID] or nil
            if candidates then
                local postedAt = entry.postedAt or 0
                local earliest = postedAt - MATCH_WINDOW_PRE
                local latest   = postedAt + MATCH_WINDOW_POST
                for _, rec in ipairs(candidates) do
                    if not usedRec[rec]
                        and rec.time >= earliest
                        and rec.time <= latest then
                        entry.auctionStatus  = "sold"
                        entry.saleOutcome    = "sold"
                        entry.soldAt         = rec.time
                        entry.soldPrice      = rec.price * rec.quantity
                        entry.collectedAt    = entry.collectedAt or rec.time
                        entry._tsmMatchedAt  = now
                        usedRec[rec] = true
                        upgraded = upgraded + 1
                        matched = true
                        break
                    end
                end
            end

            if not matched then
                -- No TSM match. If the auction window has definitely closed
                -- (posted > 49h ago) and the entry is in the "collected,
                -- outcome unknown" limbo set by CheckOwnedAuctions phase 2,
                -- finalize it as expired. Without this step, entries sit
                -- forever counted as neither sold nor failed.
                local postedAt = entry.postedAt or 0
                local ended = (postedAt > 0) and (postedAt + MATCH_WINDOW_POST < now)
                if ended
                    and entry.auctionStatus == "collected"
                    and not entry.saleOutcome then
                    entry.saleOutcome = "expired"
                    finalized = finalized + 1
                end
            end

            -- Flag so we don't re-check the same entry against the same TSM
            -- DB on every AH open. `/fq reconcile reset` clears this.
            entry._tsmReconciled = true
        end
    end

    if upgraded > 0 or finalized > 0 then
        if ns.SalesIndex then ns.SalesIndex:Invalidate() end
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    end

    if verbose or upgraded > 0 then
        ns:Print(ns.COLORS.GREEN .. upgraded .. "|r of " .. scanned ..
            " eligible entries upgraded to sold via TSM" ..
            (finalized > 0 and (" (+ " .. finalized .. " finalized as expired).") or "."))
    end
    return upgraded, scanned
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
