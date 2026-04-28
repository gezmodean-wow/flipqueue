-- TrackerMail.lua
-- Mail scanning to detect auction sales and expired/cancelled auction returns
local addonName, ns = ...

local Tracker = ns.Tracker

--------------------------
-- Mail Scanning for Sales
--------------------------

local isMailOpen = false
local mailScanRetries = 0

function Tracker:ScanMailForSales()
    if not ns.db or not isMailOpen then return end

    -- numItems may be 0 when the player opens an empty mailbox. Don't bail
    -- on that — the cleanup pass at the bottom of this function still needs
    -- to run, otherwise expired/cancelled entries with no actual mail to
    -- recover (because the mail was already collected externally, taken on
    -- another character, or the auction was never actually returned) stay
    -- stuck forever and re-fire the "N expired auction(s) to collect"
    -- login notification (#122).
    local numItems = GetInboxNumItems() or 0

    local currentCharKey = ns:GetCharKey()

    -- Collect active, expired, and cancelled log entries for this character,
    -- grouped by lowercased name AND by pet species ID. Cancelled auctions
    -- also return their item via mail (same shape as expired), so they share
    -- the returned-item code path.
    --
    -- Pets need a separate index because Blizzard's mail item link for a
    -- returned battle pet is always "[Pet Cage]" — never the species name —
    -- so name matching alone would miss every pet auction. The mail link
    -- still carries the species ID via |Hbattlepet:speciesID:..., which we
    -- match against entry.itemKey ("pet:speciesID;...").
    local activeByName = {}     -- name:lower() -> list of log indices (oldest first)
    local expiredByName = {}    -- name:lower() -> list of log indices for expired/cancelled auctions
    local activeBySpecies = {}  -- speciesID -> list of log indices for active pet auctions
    local expiredBySpecies = {} -- speciesID -> list of log indices for expired/cancelled pet auctions
    for i, entry in ipairs(ns.db.log) do
        if entry.charKey == currentCharKey then
            local key = (entry.name or ""):lower()
            local petSpecies = entry.itemKey and entry.itemKey:match("^pet:(%d+)") or nil
            if entry.auctionStatus == "active" then
                if key ~= "" then
                    if not activeByName[key] then activeByName[key] = {} end
                    table.insert(activeByName[key], i)
                end
                if petSpecies then
                    if not activeBySpecies[petSpecies] then activeBySpecies[petSpecies] = {} end
                    table.insert(activeBySpecies[petSpecies], i)
                end
            elseif entry.auctionStatus == "expired" or entry.auctionStatus == "cancelled" then
                if key ~= "" then
                    if not expiredByName[key] then expiredByName[key] = {} end
                    table.insert(expiredByName[key], i)
                end
                if petSpecies then
                    if not expiredBySpecies[petSpecies] then expiredBySpecies[petSpecies] = {} end
                    table.insert(expiredBySpecies[petSpecies], i)
                end
            end
        end
    end

    local hasActive = next(activeByName)
    local hasExpired = next(expiredByName)
    -- We still want to run the cleanup pass below even if no log entries are
    -- open — it's cheap and keeps collectedAt fresh on sold entries.

    local consumed = {} -- log index -> true
    local soldCount = 0
    local collectedCount = 0
    local hasMissing = false

    for mailIndex = 1, numItems do
        local okH, _, _, _, _, money, _, _, _, _, _, _, _, hasItem = pcall(GetInboxHeaderInfo, mailIndex)
        if okH then
            if money and money > 0 then
                -- Mail with gold: potential AH sale
                local ok, invoiceType, itemName, _, _, buyout, _, ahCut = pcall(GetInboxInvoiceInfo, mailIndex)
                if ok and invoiceType == "seller" and itemName then
                    local nameKey = itemName:lower()
                    -- Sales mail with gold uses the species name as itemName
                    -- ("Lab Rat"), not "Pet Cage" — so name match works for
                    -- sales. Only the returned-item path below needs the
                    -- species-ID workaround.
                    local candidates = activeByName[nameKey]
                    if candidates then
                        for _, logIndex in ipairs(candidates) do
                            if not consumed[logIndex] then
                                consumed[logIndex] = true
                                local entry = ns.db.log[logIndex]
                                entry.auctionStatus = "sold"
                                entry.saleOutcome = "sold"
                                entry.endReason = "sold"
                                entry.soldAt = time()
                                entry.soldPrice = buyout or money or 0
                                entry.ahFee = ahCut or 0
                                entry.collectedAt = time()
                                soldCount = soldCount + 1
                                break
                            end
                        end
                    end
                elseif ok and invoiceType == nil and money > 0 then
                    hasMissing = true
                end
            elseif hasItem then
                -- Mail with item but no gold: expired/cancelled auction returned
                local okL, itemLink = pcall(GetInboxItemLink, mailIndex, 1)
                if okL and itemLink then
                    -- Pet cages always carry a |Hbattlepet:speciesID:...|h
                    -- link with display text "[Pet Cage]". Match by species
                    -- first since the visible name is identical for every
                    -- species and would never match an entry's stored name.
                    local petSpecies = itemLink:match("|Hbattlepet:(%d+)")
                    local itemName = itemLink:match("%[(.-)%]")
                    local candidates
                    if petSpecies then
                        candidates = expiredBySpecies[petSpecies]
                            or activeBySpecies[petSpecies]
                    end
                    if not candidates and itemName then
                        local nameKey = itemName:lower()
                        -- Match against expired log entries first; fall back
                        -- to active (entry may not have been marked expired
                        -- yet by the lazy expiresAt transition).
                        candidates = expiredByName[nameKey] or activeByName[nameKey]
                    end
                    if candidates then
                        for _, logIndex in ipairs(candidates) do
                            if not consumed[logIndex] then
                                consumed[logIndex] = true
                                local entry = ns.db.log[logIndex]
                                entry.auctionStatus = "collected"
                                entry.saleOutcome = "expired"
                                -- Mail-side returned-item match can't tell
                                -- expired from cancelled — both arrive as
                                -- item-without-gold. Default to "expired"
                                -- but preserve any prior endReason (e.g.
                                -- TrackerAuctions cancellation detection
                                -- already set "cancelled").
                                entry.endReason = entry.endReason or "expired"
                                entry.collectedAt = time()

                                -- Track repeated failed sales (#71)
                                entry.postAttempts = (entry.postAttempts or 0) + 1
                                if not entry.postHistory then
                                    entry.postHistory = {}
                                end
                                -- Record this failed posting attempt
                                local attemptRecord = {
                                    postedAt = entry.postedAt,
                                    expiredAt = entry.expiresAt or time(),
                                    postedPrice = entry.postedPrice,
                                    fee = entry.ahFee or 0,
                                }
                                -- Capture TSM price data at time of expiry
                                if ns.TSM and ns.TSM:IsEnabled() and entry.itemKey then
                                    local dbMinBuyout = ns.TSM:GetPrice(entry.itemKey, "DBMinBuyout")
                                    local dbRegionSaleAvg = ns.TSM:GetPrice(entry.itemKey, "DBRegionSaleAvg")
                                    if dbMinBuyout then
                                        attemptRecord.tsmMinBuyout = dbMinBuyout
                                    end
                                    if dbRegionSaleAvg then
                                        attemptRecord.tsmRegionSaleAvg = dbRegionSaleAvg
                                    end
                                end
                                table.insert(entry.postHistory, attemptRecord)
                                -- Accumulate total fees spent on failed listings
                                entry.totalFeesSpent = (entry.totalFeesSpent or 0) + (entry.ahFee or 0)

                                collectedCount = collectedCount + 1
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- Retry if invoice data wasn't loaded yet (up to 3 times)
    if hasMissing and soldCount == 0 and collectedCount == 0 and mailScanRetries < 3 then
        mailScanRetries = mailScanRetries + 1
        C_Timer.After(1, function()
            if isMailOpen then
                Tracker:ScanMailForSales()
            end
        end)
        return
    end
    mailScanRetries = 0

    -- Cleanup: anything still in expired/cancelled for this char after the
    -- scan represents returns the user already looted in a previous session
    -- (or returns whose item mail we couldn't match). Mark them collected so
    -- they don't linger in the "done but not yet collected" bucket. We set
    -- saleOutcome="expired" if unset — both expired (timer) and cancelled
    -- (user aborted) count as unsold for sales stats.
    --
    -- Also finalize "collected, saleOutcome unset" entries whose auction
    -- window has clearly closed (posted > 49h ago). These come from
    -- CheckOwnedAuctions phase 2 reconciling a stale active entry; if the
    -- mail scan hasn't matched them by now and TSM hasn't either, conclude
    -- they didn't sell. Without this step they stay in limbo forever, not
    -- counted as sold or failed.
    local finalizedCount = 0
    local now = time()
    local AUCTION_WINDOW = 48 * 60 * 60 + 60 * 60 -- 48h + 1h grace
    for _, entry in ipairs(ns.db.log) do
        if entry.charKey == currentCharKey then
            local s = entry.auctionStatus
            if s == "expired" or s == "cancelled" then
                entry.auctionStatus = "collected"
                entry.saleOutcome = entry.saleOutcome or "expired"
                -- Preserve the precise end reason if one of the upstream
                -- transitions (cancel detection, TSM reconcile) already
                -- recorded it; otherwise infer from the prior status.
                entry.endReason = entry.endReason or s
                entry.collectedAt = entry.collectedAt or now
                finalizedCount = finalizedCount + 1
            elseif s == "collected" and not entry.saleOutcome then
                local postedAt = entry.postedAt or 0
                if postedAt > 0 and (postedAt + AUCTION_WINDOW) < now then
                    entry.saleOutcome = "expired"
                    finalizedCount = finalizedCount + 1
                end
            end
        end
    end

    if soldCount > 0 then
        ns:Print(ns.COLORS.GREEN .. soldCount .. " auction sale(s) detected!|r")
    end
    if collectedCount > 0 then
        ns:Print(ns.COLORS.YELLOW .. collectedCount .. " returned auction(s) collected.|r")
    end
    if soldCount > 0 or collectedCount > 0 or finalizedCount > 0 then
        if ns.SalesIndex then ns.SalesIndex:Invalidate() end
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    end
end

--------------------------
-- Stale Expired Reconciliation
--------------------------

-- Finalize log entries that were marked "expired" or "cancelled" but have
-- been sitting uncollected past the AH-mail TTL (30 days). At that point the
-- mail has either been collected externally (warband mail picked up on
-- another character, Postal/automail addon, manual one-off open without
-- ScanMailForSales running) or the mail itself has expired and the item is
-- gone — in either case the user can't collect it now and we shouldn't keep
-- nagging.
--
-- Returns the number of entries finalized. Safe to call repeatedly.
-- Diagnostic helper: /fq debug expired.
function Tracker:FinalizeStaleExpired()
    if not ns.db or not ns.db.log then return 0 end

    local now = time()
    -- Blizzard mail TTL is 30 days for AH-returned items and money. After
    -- that the mail evaporates server-side, so an entry stuck in
    -- "expired"/"cancelled" beyond expiresAt + 30d can never be collected.
    local STALE_THRESHOLD = 30 * 24 * 60 * 60
    local finalized = 0

    for _, entry in ipairs(ns.db.log) do
        if (entry.auctionStatus == "expired" or entry.auctionStatus == "cancelled")
            and not entry.collectedAt then
            -- Prefer expiresAt (when the mail was actually sent), fall back
            -- to postedAt + the 48h auction window (when it would have
            -- expired naturally).
            local origin = entry.expiresAt
                or (entry.postedAt and (entry.postedAt + 48 * 60 * 60))
                or nil
            if origin and (origin + STALE_THRESHOLD) < now then
                local prior = entry.auctionStatus
                entry.auctionStatus = "collected"
                entry.saleOutcome = entry.saleOutcome or "expired"
                entry.endReason = entry.endReason or prior  -- prior was "expired" or "cancelled"
                entry.collectedAt = now
                entry.finalReason = "stale_mail_window"
                finalized = finalized + 1
            end
        end
    end

    if finalized > 0 then
        if ns.SalesIndex then ns.SalesIndex:Invalidate() end
        if ns.PrintDebug then
            ns:PrintDebug(string.format(
                "[expired-reconcile] finalized %d stale expired entries (>30d past expiry)",
                finalized))
        end
    end
    return finalized
end

--------------------------
-- Mail Event Handling
--------------------------

local mailFrame = CreateFrame("Frame")
mailFrame:RegisterEvent("MAIL_SHOW")
mailFrame:RegisterEvent("MAIL_CLOSED")

mailFrame:SetScript("OnEvent", function(self, event)
    if event == "MAIL_SHOW" then
        isMailOpen = true
        mailScanRetries = 0

        -- Stamp collectedAt on sold entries that haven't been marked yet — the
        -- user is at the mailbox, which is when "collected" becomes true for
        -- sales. Do NOT flip expired/cancelled entries here: ScanMailForSales
        -- needs their status intact so it can match returned-item mail to the
        -- correct log entry and record postHistory / totalFeesSpent. The
        -- scan's cleanup pass converts unmatched expired/cancelled entries to
        -- collected after matching runs.
        if ns.db then
            local charKey = ns:GetCharKey()
            for _, entry in ipairs(ns.db.log) do
                if entry.charKey == charKey
                    and entry.auctionStatus == "sold"
                    and not entry.collectedAt then
                    entry.collectedAt = time()
                end
            end
        end

        -- Refresh task steps (collect step may advance)
        if ns.TodoList and ns.TodoList.RefreshTaskSteps then
            ns.TodoList:RefreshTaskSteps()
        end

        -- Refresh UI to clear "Check Mail" tasks
        if ns.UI then
            if ns.UI.RefreshMini then ns.UI:RefreshMini() end
            if ns.UI.Refresh then ns.UI:Refresh() end
        end

        -- Delay to allow mail data to load
        C_Timer.After(1, function()
            if isMailOpen then
                Tracker:ScanMailForSales()
            end
        end)

    elseif event == "MAIL_CLOSED" then
        isMailOpen = false
    end
end)
