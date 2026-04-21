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

    local numItems = GetInboxNumItems()
    if numItems == 0 then return end

    local currentCharKey = ns:GetCharKey()

    -- Collect active, expired, and cancelled log entries for this character,
    -- grouped by lowercased name. Cancelled auctions also return their item
    -- via mail (same shape as expired), so they share the returned-item code
    -- path.
    local activeByName = {} -- name:lower() -> list of log indices (oldest first)
    local expiredByName = {} -- name:lower() -> list of log indices for expired/cancelled auctions
    for i, entry in ipairs(ns.db.log) do
        if entry.charKey == currentCharKey then
            local key = (entry.name or ""):lower()
            if key ~= "" then
                if entry.auctionStatus == "active" then
                    if not activeByName[key] then activeByName[key] = {} end
                    table.insert(activeByName[key], i)
                elseif entry.auctionStatus == "expired" or entry.auctionStatus == "cancelled" then
                    if not expiredByName[key] then expiredByName[key] = {} end
                    table.insert(expiredByName[key], i)
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
                    local candidates = activeByName[nameKey]
                    if candidates then
                        for _, logIndex in ipairs(candidates) do
                            if not consumed[logIndex] then
                                consumed[logIndex] = true
                                local entry = ns.db.log[logIndex]
                                entry.auctionStatus = "sold"
                                entry.saleOutcome = "sold"
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
                    local itemName = itemLink:match("%[(.-)%]")
                    if itemName then
                        local nameKey = itemName:lower()
                        -- Match against expired log entries first
                        local candidates = expiredByName[nameKey]
                        if not candidates then
                            -- Also check active entries (might not have been marked expired yet)
                            candidates = activeByName[nameKey]
                        end
                        if candidates then
                            for _, logIndex in ipairs(candidates) do
                                if not consumed[logIndex] then
                                    consumed[logIndex] = true
                                    local entry = ns.db.log[logIndex]
                                    entry.auctionStatus = "collected"
                                    entry.saleOutcome = "expired"
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
