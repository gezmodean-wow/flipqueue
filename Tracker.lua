-- Tracker.lua
-- Detects auction posts by monitoring bag changes while AH is open
-- Auto-pulls queued items from bank when bank frame opens
-- Checks owned auctions for already-listed queue items
local addonName, ns = ...

local Tracker = {}
ns.Tracker = Tracker

local isAHOpen = false

-- Pre-post snapshot: queueIndex -> {queueItem, qty, bagKey}
-- Tracks bag quantities per queue item so we can detect decreases
local prePostSnapshot = {}

--------------------------
-- Item Name Extraction
--------------------------

-- Extract item name from a hyperlink (handles battle pets and regular items)
local function GetNameFromLink(link)
    if not link then return nil end
    if link:find("|Hbattlepet:") then
        return link:match("|h%[(.-)%]|h")
    end
    local ok, n = pcall(C_Item.GetItemInfo, link)
    return ok and n or nil
end

-- Get the bag quantity for a specific queue item across all inventory bags
local function CountInBags(queueItem)
    local total = 0
    for _, bagIndex in ipairs(ns.INVENTORY_BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bagIndex)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagIndex, slot)
            if info and info.hyperlink then
                local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                if itemID then
                    local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                    -- Try key/ID matching first, only resolve name if needed
                    local matched = ns:ItemsMatch(key, nil, queueItem)
                    if not matched then
                        matched = ns:ItemsMatch(key, GetNameFromLink(info.hyperlink), queueItem)
                    end
                    if matched then
                        total = total + (info.stackCount or 1)
                    end
                end
            end
        end
    end
    return total
end

--------------------------
-- Bag Snapshot for Post Detection
--------------------------

local function SnapshotBags()
    wipe(prePostSnapshot)
    if not ns.db then return end

    -- Only snapshot queue items targeted at this character's realm
    local currentRealm = GetRealmName()

    for i, queueItem in ipairs(ns.db.queue) do
        if queueItem.status == "pending" and ns:RealmMatches(queueItem.targetRealm, currentRealm) then
            prePostSnapshot[i] = {
                queueItem = queueItem,
                qty = CountInBags(queueItem),
            }
        end
    end
end

local function CheckForPosts()
    if not ns.db then return end

    -- Check each tracked queue item for quantity decreases
    local posted = {}
    for qIdx, snap in pairs(prePostSnapshot) do
        -- Queue may have shifted indices if items were removed, find by reference
        local currentIdx
        for i, qi in ipairs(ns.db.queue) do
            if qi == snap.queueItem then
                currentIdx = i
                break
            end
        end

        if currentIdx and snap.queueItem.status == "pending" then
            local curQty = CountInBags(snap.queueItem)
            if curQty < snap.qty then
                local count = snap.qty - curQty
                table.insert(posted, {idx = currentIdx, item = snap.queueItem, count = count})
            end
        end
    end

    -- Process posts in reverse order so index removal doesn't shift later entries
    table.sort(posted, function(a, b) return a.idx > b.idx end)

    -- Each detected bag decrease should only satisfy one queue item
    -- (items with same name across different realms are filtered out by SnapshotBags)
    for _, p in ipairs(posted) do
        ns:Print(ns.COLORS.GREEN .. "Posted:|r " .. p.item.name .. " (x" .. p.count .. ")")
        ns.Queue:MoveToLog(p.idx)
    end

    if #posted > 0 then
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    end

    SnapshotBags()
end

--------------------------
-- Owned Auction Check
--------------------------

-- When AH opens, check if any queue items are already listed
-- Only checks queue items targeted at the current character's realm
local ownedAuctionCheckRetries = 0

function Tracker:CheckOwnedAuctions()
    if not ns.db or not C_AuctionHouse then return end

    local owned = C_AuctionHouse.GetOwnedAuctions()
    if not owned or #owned == 0 then return end

    local currentRealm = GetRealmName()

    -- Pre-cache item names and track if any are missing
    local auctionNames = {}
    local hasMissing = false
    for aIdx, auction in ipairs(owned) do
        if auction.itemKey then
            local name
            -- Battle pets: look up name via PetJournal
            local speciesID = auction.itemKey.battlePetSpeciesID
            if speciesID and speciesID > 0 and C_PetJournal then
                name = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            end
            -- Regular items
            if not name and auction.itemKey.itemID then
                local okI, n = pcall(C_Item.GetItemInfo, auction.itemKey.itemID)
                name = okI and n or nil
                if not name then
                    hasMissing = true
                    C_Item.RequestLoadItemDataByID(auction.itemKey.itemID)
                end
            end
            auctionNames[aIdx] = name
        end
    end

    -- If item names aren't cached yet, retry after a delay (up to 3 times)
    if hasMissing and ownedAuctionCheckRetries < 3 then
        ownedAuctionCheckRetries = ownedAuctionCheckRetries + 1
        C_Timer.After(1, function()
            if isAHOpen then
                Tracker:CheckOwnedAuctions()
            end
        end)
        return
    end
    ownedAuctionCheckRetries = 0

    -- Pre-resolve queue item numeric IDs from scanned inventory data
    local resolvedIDs = {}
    for i, queueItem in ipairs(ns.db.queue) do
        if queueItem.status == "pending" then
            resolvedIDs[i] = ns:ResolveItemID(queueItem)
        end
    end

    -- Track which owned auctions have been consumed so each only satisfies one queue item
    local consumed = {}

    local found = 0
    for i = #ns.db.queue, 1, -1 do
        local queueItem = ns.db.queue[i]
        -- Only match queue items targeted at this realm
        if queueItem.status == "pending" and ns:RealmMatches(queueItem.targetRealm, currentRealm) then
            for aIdx, auction in ipairs(owned) do
                if not consumed[aIdx] then
                    local auctionName = auctionNames[aIdx]
                    local auctionKey = tostring(auction.itemKey.itemID) .. ";;"
                    local matches = ns:ItemsMatch(auctionKey, auctionName, queueItem, resolvedIDs[i] or false)

                    if matches then
                        consumed[aIdx] = true
                        found = found + 1
                        ns:Print(ns.COLORS.YELLOW .. "Already listed:|r " .. queueItem.name .. " — moving to log")
                        local expirySec = auction.timeLeftSeconds
                        ns.Queue:MoveToLog(i, nil, expirySec)
                        break
                    end
                end
            end
        end
    end

    if found > 0 then
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    end
end

--------------------------
-- Bank Auto-Pull
--------------------------

local PULL_TIMEOUT = 5  -- seconds to wait for locks before giving up on a batch

function Tracker:AutoPullFromBank()
    if not ns.db or not ns.db.settings.autoPullBank then return end

    local allBankTabs = {}
    for _, b in ipairs(ns:GetEnabledBankTabs()) do table.insert(allBankTabs, b) end
    for _, b in ipairs(ns:GetEnabledWarbankTabs()) do table.insert(allBankTabs, b) end

    -- Only pull items that are targeted for this character's realm
    local currentRealm = GetRealmName()

    local needed = {}
    for _, queueItem in ipairs(ns.db.queue) do
        if queueItem.status == "pending" and ns:RealmMatches(queueItem.targetRealm, currentRealm) then
            local inBags = CountInBags(queueItem)
            local stillNeeded = (queueItem.quantity or 1) - inBags
            if stillNeeded > 0 then
                needed[queueItem] = stillNeeded
            end
        end
    end

    -- Build a list of moves to make (bag, slot, name)
    local moves = {}
    for _, bagIndex in ipairs(allBankTabs) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                        local slotName  -- lazy name cache per slot
                        for queueItem, count in pairs(needed) do
                            if count > 0 then
                            -- Try key/ID matching first, only resolve name if needed
                            local matched = ns:ItemsMatch(key, nil, queueItem, nil, false)
                            if not matched then
                                if slotName == nil then slotName = GetNameFromLink(info.hyperlink) or false end
                                if slotName then
                                    matched = ns:ItemsMatch(key, slotName, queueItem, nil, false)
                                end
                            end
                            if matched then
                                table.insert(moves, {bag = bagIndex, slot = slot, name = queueItem.name or "?"})
                                needed[queueItem] = count - (info.stackCount or 1)
                                break
                            end
                            end -- count > 0
                        end
                    end
                end
            end
        end
    end

    if #moves == 0 then return end

    -- Event-driven batch execution
    -- Pattern from Baganator: move a small batch, wait for ITEM_LOCK_CHANGED
    -- to signal the server has processed the moves, then continue
    local totalMoves = #moves
    local moveIndex = 1
    local pulledNames = {}
    local pullErrors = 0
    local aborted = false

    local listener = CreateFrame("Frame")

    local function Cleanup()
        listener:UnregisterAllEvents()
        listener:SetScript("OnEvent", nil)
    end

    local function FinishPull()
        Cleanup()
        local successCount = #pulledNames
        if successCount > 0 then
            if successCount == totalMoves then
                ns:Print("Auto-pulled " .. successCount .. " item(s) from bank: " .. table.concat(pulledNames, ", "))
            else
                ns:Print("Auto-pulled " .. successCount .. " of " .. totalMoves .. " item(s) from bank: " .. table.concat(pulledNames, ", "))
            end
        end
        if pullErrors > 0 then
            ns:Print(ns.COLORS.YELLOW .. pullErrors .. " item(s) failed to move. Try opening your bank again.|r")
        end
        C_Timer.After(1, function()
            if ns.Scanner then ns.Scanner:ScanCurrentCharacter() end
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        end)
    end

    local function ExecuteNextBatch()
        if aborted or moveIndex > totalMoves then
            FinishPull()
            return
        end

        local batchSize = ns.db and ns.db.settings.pullBatchSize or 5
        local batchEnd = math.min(moveIndex + batchSize - 1, totalMoves)
        local batchMoved = 0

        for i = moveIndex, batchEnd do
            local move = moves[i]
            -- Check if slot is locked before attempting
            local okLock, isLocked = pcall(C_Container.GetContainerItemInfo, move.bag, move.slot)
            if okLock and isLocked and isLocked.isLocked then
                -- Slot is locked from a previous operation — skip, will retry
                pullErrors = pullErrors + 1
            else
                local ok, err = pcall(C_Container.UseContainerItem, move.bag, move.slot)
                if ok then
                    table.insert(pulledNames, move.name)
                    batchMoved = batchMoved + 1
                else
                    pullErrors = pullErrors + 1
                end
            end
        end

        moveIndex = batchEnd + 1

        if moveIndex > totalMoves then
            -- All batches issued — wait briefly for any trailing events
            C_Timer.After(0.3, FinishPull)
        elseif batchMoved > 0 then
            -- Wait for items to unlock before continuing
            -- ITEM_LOCK_CHANGED fires when server finishes processing
            local waitingForUnlock = true
            listener:RegisterEvent("ITEM_LOCK_CHANGED")
            listener:RegisterEvent("UI_ERROR_MESSAGE")
            listener:SetScript("OnEvent", function(_, event, errorType, message)
                if event == "UI_ERROR_MESSAGE" then
                    if message == ERR_INTERNAL_BAG_ERROR
                        or (message and message:find("Internal Bag Error")) then
                        aborted = true
                        pullErrors = pullErrors + 1
                        listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                        listener:UnregisterEvent("UI_ERROR_MESSAGE")
                        FinishPull()
                        return
                    elseif message == ERR_INV_FULL
                        or (message and message:find("Inventory is full")) then
                        aborted = true
                        listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                        listener:UnregisterEvent("UI_ERROR_MESSAGE")
                        FinishPull()
                        return
                    end
                elseif event == "ITEM_LOCK_CHANGED" and waitingForUnlock then
                    waitingForUnlock = false
                    listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                    listener:UnregisterEvent("UI_ERROR_MESSAGE")
                    -- Items unlocked — server processed the batch, continue
                    C_Timer.After(0.1, ExecuteNextBatch)
                end
            end)

            -- Safety timeout in case ITEM_LOCK_CHANGED never fires
            C_Timer.After(PULL_TIMEOUT, function()
                if waitingForUnlock then
                    waitingForUnlock = false
                    listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                    listener:UnregisterEvent("UI_ERROR_MESSAGE")
                    -- Continue anyway — items may have moved without firing the event
                    ExecuteNextBatch()
                end
            end)
        else
            -- Nothing moved in this batch (all locked) — short delay then retry next batch
            C_Timer.After(0.5, ExecuteNextBatch)
        end
    end

    ns:Print(ns.COLORS.YELLOW .. "Pulling " .. totalMoves .. " item(s) from bank..." .. "|r")
    ExecuteNextBatch()
end

--------------------------
-- Warbank Gold Withdrawal
--------------------------

function Tracker:AutoWithdrawGold()
    if not ns.db or not ns.db.settings.autoWithdrawGold then return end
    if not C_Bank or not C_Bank.WithdrawMoney then return end

    local currentRealm = GetRealmName()

    -- Calculate estimated AH fees from queue items for this realm
    local totalExpectedGold = 0
    for _, queueItem in ipairs(ns.db.queue) do
        if queueItem.status == "pending" and ns:RealmMatches(queueItem.targetRealm, currentRealm) then
            totalExpectedGold = totalExpectedGold + ns:ParseGoldValue(queueItem.expectedPrice)
        end
    end

    if totalExpectedGold <= 0 then return end

    -- AH deposits are 15%/30%/60% of vendor sell price based on 12h/24h/48h duration.
    -- Vendor price is typically ~1-5% of AH market value.
    -- Conservatively estimate: vendor ~5% of AH price, at 60% deposit (48h worst case).
    -- So deposit ≈ 3% of expected AH value. Cap at 200g to be safe.
    local estimatedFees = math.min(math.ceil(totalExpectedGold * 0.03), 200)

    local playerGold = math.floor(GetMoney() / 10000)
    if playerGold >= estimatedFees then return end -- already have enough

    local shortfall = estimatedFees - playerGold
    local shortfallCopper = shortfall * 10000

    -- Check permission
    local ok, canWithdraw = pcall(C_Bank.CanWithdrawMoney, Enum.BankType.Account)
    if not ok or not canWithdraw then
        ns:Print(ns.COLORS.YELLOW .. "Cannot withdraw from warbank (permission denied).|r")
        return
    end

    -- Check warbank balance
    local ok2, warbankCopper = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    if not ok2 or not warbankCopper then
        ns:Print(ns.COLORS.RED .. "Could not check warbank balance.|r")
        return
    end

    if warbankCopper < shortfallCopper then
        local warbankGold = math.floor(warbankCopper / 10000)
        ns:Print(ns.COLORS.RED .. "Not enough in warbank.|r Need " .. shortfall ..
            "g more, warbank has " .. warbankGold .. "g")
        return
    end

    -- Withdraw
    local ok3, err = pcall(C_Bank.WithdrawMoney, Enum.BankType.Account, shortfallCopper)
    if ok3 then
        ns:Print(ns.COLORS.GREEN .. "Withdrew " .. shortfall .. "g|r from warbank" ..
            " (est. " .. estimatedFees .. "g needed for AH fees, had " .. playerGold .. "g)")
    else
        ns:Print(ns.COLORS.RED .. "Failed to withdraw: " .. tostring(err) .. "|r")
    end
end

--------------------------
-- Auction Expiry Tracking
--------------------------

-- Update log entries with expiry data from owned auctions
function Tracker:UpdateLogExpiry()
    if not ns.db or not C_AuctionHouse then return end

    local owned = C_AuctionHouse.GetOwnedAuctions()
    if not owned or #owned == 0 then return end

    local now = time()

    -- Pre-cache auction names
    local auctionNames = {}
    for aIdx, auction in ipairs(owned) do
        if auction.itemKey then
            local name
            local speciesID = auction.itemKey.battlePetSpeciesID
            if speciesID and speciesID > 0 and C_PetJournal then
                name = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            end
            if not name and auction.itemKey.itemID then
                local okI, n = pcall(C_Item.GetItemInfo, auction.itemKey.itemID)
                name = okI and n or nil
            end
            auctionNames[aIdx] = name
        end
    end

    local currentCharKey = ns:GetCharKey()
    local updated = 0

    for _, logEntry in ipairs(ns.db.log) do
        if logEntry.auctionStatus == "active" and logEntry.charKey == currentCharKey then
            -- Check if expired based on stored expiresAt
            if logEntry.expiresAt and logEntry.expiresAt <= now then
                logEntry.auctionStatus = "expired"
            else
                -- Try to match against owned auctions to update/confirm expiry
                for aIdx, auction in ipairs(owned) do
                    local auctionName = auctionNames[aIdx]
                    local auctionKey = tostring(auction.itemKey.itemID) .. ";;"
                    local matches = ns:ItemsMatch(auctionKey, auctionName, logEntry, nil, false)

                    if matches and auction.timeLeftSeconds then
                        logEntry.expiresAt = now + auction.timeLeftSeconds
                        updated = updated + 1
                        break
                    end
                end
            end
        end
    end
end

-- Return log entries with auctions expiring soon (for login alerts)
function Tracker:CheckExpiringAuctions()
    if not ns.db then return {} end

    local now = time()
    local alertHours = ns.db.settings.expiryAlertHours or 6
    local threshold = alertHours * 3600
    local expiring = {}

    for _, entry in ipairs(ns.db.log) do
        if entry.auctionStatus == "active" and entry.expiresAt then
            if entry.expiresAt <= now then
                entry.auctionStatus = "expired"
            elseif entry.expiresAt - now < threshold then
                table.insert(expiring, entry)
            end
        end
    end

    return expiring
end

-- Get characters that have expiring auctions (for Characters page)
function Tracker:GetExpiringByCharacter()
    if not ns.db then return {} end

    local now = time()
    local byChar = {} -- charKey -> {count, soonest}

    for _, entry in ipairs(ns.db.log) do
        if entry.auctionStatus == "active" and entry.expiresAt and entry.charKey then
            if entry.expiresAt <= now then
                entry.auctionStatus = "expired"
            else
                local remaining = entry.expiresAt - now
                if not byChar[entry.charKey] then
                    byChar[entry.charKey] = {count = 0, soonest = remaining}
                end
                byChar[entry.charKey].count = byChar[entry.charKey].count + 1
                if remaining < byChar[entry.charKey].soonest then
                    byChar[entry.charKey].soonest = remaining
                end
            end
        end
    end

    return byChar
end

-- Get full auction summary by character: active + done counts
function Tracker:GetAuctionSummaryByCharacter()
    if not ns.db then return {} end

    local now = time()
    local byChar = {} -- charKey -> {active, done, soonest}

    for _, entry in ipairs(ns.db.log) do
        if entry.charKey then
            -- Auto-expire active auctions past their time
            if entry.auctionStatus == "active" and entry.expiresAt and entry.expiresAt <= now then
                entry.auctionStatus = "expired"
            end

            if not byChar[entry.charKey] then
                byChar[entry.charKey] = {active = 0, done = 0, soonest = nil}
            end

            if entry.auctionStatus == "active" then
                byChar[entry.charKey].active = byChar[entry.charKey].active + 1
                if entry.expiresAt then
                    local remaining = entry.expiresAt - now
                    if not byChar[entry.charKey].soonest or remaining < byChar[entry.charKey].soonest then
                        byChar[entry.charKey].soonest = remaining
                    end
                end
            elseif entry.auctionStatus == "expired" then
                byChar[entry.charKey].done = byChar[entry.charKey].done + 1
            end
        end
    end

    return byChar
end

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

    -- Collect active log entries for this character, grouped by name
    local activeByName = {} -- name:lower() -> list of log indices (oldest first)
    for i, entry in ipairs(ns.db.log) do
        if entry.auctionStatus == "active" and entry.charKey == currentCharKey then
            local key = (entry.name or ""):lower()
            if key ~= "" then
                if not activeByName[key] then activeByName[key] = {} end
                table.insert(activeByName[key], i)
            end
        end
    end

    if not next(activeByName) then return end

    local consumed = {} -- log index -> true
    local updated = 0
    local hasMissing = false

    for mailIndex = 1, numItems do
        local okH, _, _, _, _, money = pcall(GetInboxHeaderInfo, mailIndex)
        -- Only check mail with gold attached (potential AH sale)
        if okH and money and money > 0 then
            local ok, invoiceType, itemName, _, _, buyout = pcall(GetInboxInvoiceInfo, mailIndex)
            if ok and invoiceType == "seller" and itemName then
                local nameKey = itemName:lower()
                local candidates = activeByName[nameKey]
                if candidates then
                    for _, logIndex in ipairs(candidates) do
                        if not consumed[logIndex] then
                            consumed[logIndex] = true
                            local entry = ns.db.log[logIndex]
                            entry.auctionStatus = "sold"
                            entry.soldAt = time()
                            entry.soldPrice = buyout or money or 0
                            updated = updated + 1
                            break
                        end
                    end
                end
            elseif ok and invoiceType == nil and money > 0 then
                -- Has gold but no invoice data yet — might not be loaded
                hasMissing = true
            end
        end
    end

    -- Retry if invoice data wasn't loaded yet (up to 3 times)
    if hasMissing and updated == 0 and mailScanRetries < 3 then
        mailScanRetries = mailScanRetries + 1
        C_Timer.After(1, function()
            if isMailOpen then
                Tracker:ScanMailForSales()
            end
        end)
        return
    end
    mailScanRetries = 0

    if updated > 0 then
        ns:Print(ns.COLORS.GREEN .. updated .. " auction sale(s) detected!|r")
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    end
end

--------------------------
-- Event Handling
--------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("OWNED_AUCTIONS_UPDATED")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("MAIL_CLOSED")

frame:SetScript("OnEvent", function(self, event)
    if event == "AUCTION_HOUSE_SHOW" then
        isAHOpen = true
        SnapshotBags()

        -- Mark expired auctions as collected (user is at the AH)
        if ns.db then
            local charKey = ns:GetCharKey()
            for _, entry in ipairs(ns.db.log) do
                if entry.auctionStatus == "expired" and entry.charKey == charKey then
                    entry.auctionStatus = "collected"
                end
            end
        end

        if ns.Queue then
            local tasks = ns.Queue:GetCharacterTasks(ns:GetCharKey())
            if tasks and #tasks > 0 then
                ns:Print(ns.COLORS.GREEN .. #tasks .. " items|r in your queue ready to post!")
            end
        end

        -- Request owned auctions to check for already-listed items
        if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then
            C_AuctionHouse.QueryOwnedAuctions({})
        end

    elseif event == "AUCTION_HOUSE_CLOSED" then
        isAHOpen = false
        wipe(prePostSnapshot)

    elseif event == "BAG_UPDATE_DELAYED" then
        if isAHOpen and next(prePostSnapshot) then
            C_Timer.After(0.3, CheckForPosts)
        end

    elseif event == "BANKFRAME_OPENED" then
        C_Timer.After(1, function()
            -- Rescan warbank so task counts stay in sync
            if ns.Scanner and ns.Scanner.ScanWarbank then
                ns.Scanner:ScanWarbank()
            end
            Tracker:AutoPullFromBank()
            Tracker:AutoWithdrawGold()
        end)

    elseif event == "OWNED_AUCTIONS_UPDATED" then
        if isAHOpen then
            Tracker:CheckOwnedAuctions()
            Tracker:UpdateLogExpiry()
            -- Sold detection only via mail scanning (ScanMailForSales)
            -- Owned auction disappearance can't distinguish sold vs cancelled
        end

    elseif event == "MAIL_SHOW" then
        isMailOpen = true
        mailScanRetries = 0
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
