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
-- Item Matching
--------------------------

-- Check if a scanned item matches a queue item by key, ID, or name
local function MatchesQueueItem(scannedKey, scannedLink, queueItem)
    -- Exact key match
    if scannedKey == queueItem.itemKey then
        return true
    end

    -- Numeric ID match: compare scanned item's ID with resolved queue ID
    local scannedID = scannedKey and scannedKey:match("^(%d+);")
    local scannedNumID = tonumber(scannedID)
    if scannedNumID and scannedNumID > 0 then
        local queueNumID = tonumber(queueItem.itemID)
        if queueNumID and queueNumID > 0 and scannedNumID == queueNumID then
            return true
        end
        -- Try resolved ID from inventory
        local resolvedID = ns:ResolveItemID(queueItem)
        if resolvedID and scannedNumID == resolvedID then
            return true
        end
    end

    -- Name-based fallback: extract name from link and compare
    if queueItem.name and queueItem.name ~= "" then
        local scannedName
        if scannedLink:find("|Hbattlepet:") then
            scannedName = scannedLink:match("|h%[(.-)%]|h")
        else
            scannedName = C_Item.GetItemInfo(scannedLink)
        end
        if scannedName then
            local sName = scannedName:lower()
            local qName = queueItem.name:lower()
            -- Exact match
            if sName == qName then return true end
            -- Fuzzy: substring match (min 8 chars to avoid false positives)
            if #queueItem.name >= 8 then
                if sName:find(qName, 1, true) or qName:find(sName, 1, true) then
                    return true
                end
            end
        end
    end

    return false
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
                    if MatchesQueueItem(key, info.hyperlink, queueItem) then
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
                name = C_Item.GetItemInfo(auction.itemKey.itemID)
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

                    local matches = false
                    -- 1) Match by queue item's direct numeric ID
                    local queueNumID = tonumber(queueItem.itemID)
                    if queueNumID and queueNumID > 0 and auction.itemKey
                        and auction.itemKey.itemID == queueNumID then
                        matches = true
                    end

                    -- 2) Match by resolved numeric ID from inventory data
                    if not matches and resolvedIDs[i] and auction.itemKey
                        and auction.itemKey.itemID == resolvedIDs[i] then
                        matches = true
                    end

                    -- 3) Exact name match
                    if not matches and auctionName and queueItem.name ~= "" then
                        if auctionName:lower() == queueItem.name:lower() then
                            matches = true
                        end
                    end

                    -- 4) Fuzzy name match: substring in either direction
                    --    Handles recipe prefix differences, shortened names, etc.
                    if not matches and auctionName and queueItem.name ~= ""
                        and #queueItem.name >= 8 then
                        local qName = queueItem.name:lower()
                        local aName = auctionName:lower()
                        if aName:find(qName, 1, true) or qName:find(aName, 1, true) then
                            matches = true
                        end
                    end

                    if matches then
                        consumed[aIdx] = true
                        found = found + 1
                        ns:Print(ns.COLORS.YELLOW .. "Already listed:|r " .. queueItem.name .. " — moving to log")
                        ns.Queue:MoveToLog(i)
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

function Tracker:AutoPullFromBank()
    if not ns.db or not ns.db.settings.autoPullBank then return end

    local pulled = 0
    local allBankTabs = {}
    for _, b in ipairs(ns.BANK_TABS) do table.insert(allBankTabs, b) end
    for _, b in ipairs(ns.WARBANK_TABS) do table.insert(allBankTabs, b) end

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

    for _, bagIndex in ipairs(allBankTabs) do
        local numSlots = C_Container.GetContainerNumSlots(bagIndex)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagIndex, slot)
            if info and info.hyperlink then
                local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                if itemID then
                    local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                    for queueItem, count in pairs(needed) do
                        if count > 0 and MatchesQueueItem(key, info.hyperlink, queueItem) then
                            C_Container.UseContainerItem(bagIndex, slot)
                            needed[queueItem] = count - (info.stackCount or 1)
                            pulled = pulled + 1
                            break  -- This slot is consumed, move to next slot
                        end
                    end
                end
            end
        end
    end

    if pulled > 0 then
        ns:Print("Auto-pulled " .. pulled .. " stack(s) from bank/warbank to bags.")
        C_Timer.After(1, function()
            ns.Scanner:ScanCurrentCharacter()
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        end)
    end
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
            local priceStr = queueItem.expectedPrice or ""
            local goldNum = priceStr:gsub(",", ""):match("(%d+)g")
            totalExpectedGold = totalExpectedGold + (tonumber(goldNum) or 0)
        end
    end

    if totalExpectedGold <= 0 then return end

    -- Estimate AH listing fees as 5% of total expected value (conservative)
    local estimatedFees = math.ceil(totalExpectedGold * 0.05)
    estimatedFees = math.max(estimatedFees, 100) -- minimum 100g

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
-- Event Handling
--------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("OWNED_AUCTIONS_UPDATED")

frame:SetScript("OnEvent", function(self, event)
    if event == "AUCTION_HOUSE_SHOW" then
        isAHOpen = true
        SnapshotBags()

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
            Tracker:AutoPullFromBank()
            Tracker:AutoWithdrawGold()
        end)

    elseif event == "OWNED_AUCTIONS_UPDATED" then
        if isAHOpen then
            Tracker:CheckOwnedAuctions()
        end
    end
end)
