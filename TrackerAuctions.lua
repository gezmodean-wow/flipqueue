-- TrackerAuctions.lua
-- Auction monitoring: owned auction checks, expiry tracking, and periodic expiry ticker
local addonName, ns = ...

local Tracker = ns.Tracker

--------------------------
-- Owned Auction Check
--------------------------

-- When AH opens, check if any to-do items are already listed
-- Only checks items targeted at the current character's realm
local ownedAuctionCheckRetries = 0

function Tracker:CheckOwnedAuctions()
    if not ns.db or not C_AuctionHouse then return end

    local owned = C_AuctionHouse.GetOwnedAuctions()
    if not owned then return end

    -- If no auctions on AH, reconcile all "active" log entries for this character
    if #owned == 0 then
        local charKey = ns:GetCharKey()
        local pendingCancels = Tracker._pendingCancels or 0
        local cancelledCount = 0
        local cleared = 0
        for _, entry in ipairs(ns.db.log) do
            if entry.auctionStatus == "active" and entry.charKey == charKey then
                if pendingCancels > 0 then
                    entry.auctionStatus = "cancelled"
                    pendingCancels = pendingCancels - 1
                    cancelledCount = cancelledCount + 1
                else
                    entry.auctionStatus = "collected"
                end
                cleared = cleared + 1
            end
        end
        Tracker._pendingCancels = 0
        if cancelledCount > 0 then
            ns:Print(ns.COLORS.YELLOW .. cancelledCount .. " auction(s) cancelled — items in mail.|r")
        end
        if cleared > 0 then
            ns:PrintDebug("Reconciled " .. cleared ..
                " log entries (no auctions on AH).")
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
            if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
        end
        return
    end

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
            if Tracker._isAHOpen then
                Tracker:CheckOwnedAuctions()
            end
        end)
        return
    end
    ownedAuctionCheckRetries = 0

    -- Track which owned auctions have been consumed so each only satisfies one to-do item
    local consumed = {}

    local found = 0

    -- Match against active to-do list items (consume multiple auctions per todo item)
    if ns.TodoList then
        local todoList = ns.TodoList:GetCurrentList()
        if todoList and todoList.tasks then
            local charKey = ns:GetCharKey()
            for taskIdx, todoItem in ipairs(todoList.tasks) do
                if (todoItem.status == "pending" or todoItem.status == "skipped")
                    and todoItem.assignedChar == charKey
                    and ns:RealmMatches(todoItem.targetRealm or "", currentRealm) then
                    local remainingQty = todoItem.quantity or 1
                    local totalMatched = 0
                    local firstExpiry = nil
                    local todoResolvedID = ns:ResolveItemID(todoItem)

                    for aIdx, auction in ipairs(owned) do
                        if not consumed[aIdx] and remainingQty > 0 then
                            local auctionName = auctionNames[aIdx]
                            local auctionKey = tostring(auction.itemKey.itemID) .. ";;"
                            local matches = ns:ItemsMatch(auctionKey, auctionName, todoItem, todoResolvedID or false)

                            if matches then
                                consumed[aIdx] = true
                                local auctionQty = auction.quantity or 1
                                totalMatched = totalMatched + auctionQty
                                remainingQty = remainingQty - auctionQty
                                if not firstExpiry and auction.timeLeftSeconds then
                                    firstExpiry = auction.timeLeftSeconds
                                end
                            end
                        end
                    end

                    if totalMatched > 0 then
                        -- Clean up TSM skip if user posted anyway
                        if todoItem.status == "skipped" then
                            for i = #ns.db.log, 1, -1 do
                                local entry = ns.db.log[i]
                                if entry.auctionStatus == "skipped"
                                    and entry.itemKey == todoItem.itemKey
                                    and entry.charKey == charKey then
                                    table.remove(ns.db.log, i)
                                    break
                                end
                            end
                            todoItem.status = "pending"
                            ns:Print(ns.COLORS.CYAN .. "Override:|r " .. (todoItem.name or "?") .. " listed despite TSM skip")
                        end
                        ns:PrintDebug("Listed: " .. (todoItem.name or "?") .. " x" .. totalMatched .. " — marking done")
                        ns.TodoList:MoveTaskToLog(taskIdx, nil, firstExpiry, totalMatched)
                    end
                end
            end
        end
    end

    -- State recovery: discover orphaned auctions not in todo list or log
    local recovered = 0

    -- Count active log entries per item ID for this character
    local loggedByItemID = {} -- itemID string -> count
    local charKey = ns:GetCharKey()
    for _, entry in ipairs(ns.db.log) do
        if entry.auctionStatus == "active" and entry.charKey == charKey then
            local entryID = tostring((entry.itemKey or ""):match("^(%d+)")) or ""
            if entryID ~= "" then
                loggedByItemID[entryID] = (loggedByItemID[entryID] or 0) + 1
            end
        end
    end

    -- Count consumed auctions (matched to todo list) per item ID
    local consumedByItemID = {}
    for aIdx, _ in pairs(consumed) do
        local aID = tostring(owned[aIdx].itemKey.itemID)
        consumedByItemID[aID] = (consumedByItemID[aID] or 0) + 1
    end

    -- Track how many auctions per item ID we've already accounted for
    local accountedFor = {} -- itemID -> count
    for id, count in pairs(loggedByItemID) do
        accountedFor[id] = count
    end
    for id, count in pairs(consumedByItemID) do
        accountedFor[id] = (accountedFor[id] or 0) + count
    end

    local now = time()
    for aIdx, auction in ipairs(owned) do
        if not consumed[aIdx] then
            -- For battle pets, use pet:speciesID format to match inventory keys
            local speciesID = auction.itemKey.battlePetSpeciesID
            local isPet = speciesID and speciesID > 0
            local auctionID = isPet and ("pet:" .. speciesID) or tostring(auction.itemKey.itemID)
            local accounted = accountedFor[auctionID] or 0

            if accounted > 0 then
                -- This auction is accounted for by an existing log entry
                accountedFor[auctionID] = accounted - 1
            else
                -- Orphaned auction: not in todo list or log
                local auctionKey = isPet
                    and ("pet:" .. speciesID .. ";;")
                    or (auctionID .. ";;")
                local auctionName = auctionNames[aIdx] or ("Item " .. auctionID)
                local expirySec = auction.timeLeftSeconds
                local estPostedAt = expirySec and (now - (172800 - expirySec)) or now

                table.insert(ns.db.log, {
                    itemKey       = auctionKey,
                    itemID        = auctionID,
                    name          = auctionName,
                    quality       = "",
                    icon          = nil,
                    targetRealm   = currentRealm,
                    expectedPrice = "",
                    postedPrice   = auction.buyoutAmount and ns:FormatGold(auction.buyoutAmount) or "",
                    postedAt      = estPostedAt,
                    charKey       = charKey,
                    expiresAt     = expirySec and (now + expirySec) or nil,
                    auctionStatus = "active",
                    soldAt        = nil,
                    soldPrice     = nil,
                    postedQuantity = auction.quantity or 1,
                    isRecovered   = true,
                })
                recovered = recovered + 1
            end
        end
    end

    if recovered > 0 then
        ns:PrintDebug("Recovered " .. recovered .. " untracked auction(s) from AH.")
    end

    -- Reconcile: mark log entries as "collected" if they claim active on this
    -- character but are NOT found in the owned auctions list.
    -- The owned auctions list is the source of truth for what's actually on the AH.
    -- Build a set of item IDs actually on the AH (from owned auctions)
    local ownedByItemID = {} -- itemID string -> count on AH
    for _, auction in ipairs(owned) do
        local aID = tostring(auction.itemKey.itemID)
        ownedByItemID[aID] = (ownedByItemID[aID] or 0) + 1
    end

    -- Walk log entries for this character: if "active" but not on AH, determine fate
    -- Use pending cancel count to distinguish cancelled vs silently collected
    local pendingCancels = Tracker._pendingCancels or 0
    local reconciledCount = 0
    local cancelledCount = 0
    local ownedConsumed = {} -- track how many owned auctions we've "used up" per ID
    for _, entry in ipairs(ns.db.log) do
        if entry.auctionStatus == "active" and entry.charKey == charKey then
            local entryID = tostring((entry.itemKey or ""):match("^(%d+)"))
            if entryID and entryID ~= "" then
                local onAH = ownedByItemID[entryID] or 0
                local used = ownedConsumed[entryID] or 0
                if used < onAH then
                    -- This log entry is accounted for by an actual auction
                    ownedConsumed[entryID] = used + 1
                else
                    -- No matching auction on AH — determine why
                    if pendingCancels > 0 then
                        entry.auctionStatus = "cancelled"
                        pendingCancels = pendingCancels - 1
                        cancelledCount = cancelledCount + 1
                    else
                        -- Silently mark as collected — ScanMailForSales will detect
                        -- actual sales and set "sold" status with gold amount
                        entry.auctionStatus = "collected"
                    end
                    reconciledCount = reconciledCount + 1
                end
            end
        end
    end
    Tracker._pendingCancels = 0 -- reset after reconciliation

    if cancelledCount > 0 then
        ns:Print(ns.COLORS.YELLOW .. cancelledCount .. " auction(s) cancelled — items in mail.|r")
    end
    if reconciledCount > 0 then
        ns:PrintDebug("Reconciled " .. reconciledCount ..
            " stale log entries (not found on AH).|r")
    end

    if found > 0 or recovered > 0 or reconciledCount > 0 then
        if ns.SalesIndex then ns.SalesIndex:Invalidate() end
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
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
                logEntry.saleOutcome = "expired"  -- timer ran out = unsold
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
    local alertMinutes = ns.db.settings.expiryAlertMinutes or 15
    local threshold = alertMinutes * 60
    local expiring = {}

    for _, entry in ipairs(ns.db.log) do
        if entry.auctionStatus == "active" and entry.expiresAt then
            if entry.expiresAt <= now then
                entry.auctionStatus = "expired"
                entry.saleOutcome = "expired"  -- timer ran out = unsold
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
                entry.saleOutcome = "expired"  -- timer ran out = unsold
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
                entry.saleOutcome = "expired"  -- timer ran out = unsold
            end

            if not byChar[entry.charKey] then
                byChar[entry.charKey] = {active = 0, done = 0, soonest = nil, totalValue = 0}
            end

            if entry.auctionStatus == "active" then
                byChar[entry.charKey].active = byChar[entry.charKey].active + 1
                byChar[entry.charKey].totalValue = byChar[entry.charKey].totalValue
                    + (ns:ParseGoldValue(entry.postedPrice or entry.expectedPrice) or 0)
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
-- Auction Expiry Ticker
--------------------------

-- Periodically checks for newly expired auctions and notifies the player
function Tracker:StartExpiryTicker()
    if self._expiryTicker then return end -- already running
    self._expiryTicker = C_Timer.NewTicker(60, function()
        if not ns.db then return end

        local now = time()
        local newlyExpired = {}

        for _, entry in ipairs(ns.db.log) do
            if entry.auctionStatus == "active" and entry.expiresAt and entry.expiresAt <= now then
                entry.auctionStatus = "expired"
                entry.saleOutcome = "expired"  -- timer ran out = unsold
                local ck = entry.charKey or "Unknown"
                newlyExpired[ck] = (newlyExpired[ck] or 0) + 1
            end
        end

        if next(newlyExpired) then
            for ck, count in pairs(newlyExpired) do
                ns:Print(ns.COLORS.ORANGE .. count .. " auction(s) expired on " .. ck .. "!|r")
            end
            if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        end
    end)
end
