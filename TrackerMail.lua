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

    -- Collect active and expired log entries for this character, grouped by name
    local activeByName = {} -- name:lower() -> list of log indices (oldest first)
    local expiredByName = {} -- name:lower() -> list of log indices for expired auctions
    for i, entry in ipairs(ns.db.log) do
        if entry.charKey == currentCharKey then
            local key = (entry.name or ""):lower()
            if key ~= "" then
                if entry.auctionStatus == "active" then
                    if not activeByName[key] then activeByName[key] = {} end
                    table.insert(activeByName[key], i)
                elseif entry.auctionStatus == "expired" then
                    if not expiredByName[key] then expiredByName[key] = {} end
                    table.insert(expiredByName[key], i)
                end
            end
        end
    end

    local hasActive = next(activeByName)
    local hasExpired = next(expiredByName)
    if not hasActive and not hasExpired then return end

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

    if soldCount > 0 then
        ns:Print(ns.COLORS.GREEN .. soldCount .. " auction sale(s) detected!|r")
    end
    if collectedCount > 0 then
        ns:Print(ns.COLORS.YELLOW .. collectedCount .. " returned auction(s) collected.|r")
    end
    if soldCount > 0 or collectedCount > 0 then
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

        -- Mark expired auctions as collected (user is checking mail)
        if ns.db then
            local charKey = ns:GetCharKey()
            for _, entry in ipairs(ns.db.log) do
                if entry.auctionStatus == "expired" and entry.charKey == charKey then
                    entry.auctionStatus = "collected"
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
