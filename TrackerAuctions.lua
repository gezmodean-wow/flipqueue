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

-- Canonical item-ID key for reconciliation. Pet auctions and pet log entries
-- share the same namespace as regular items if we don't prefix them, so battle
-- pets get a "pet:<speciesID>" form.
local function AuctionItemID(auction)
    local speciesID = auction.itemKey.battlePetSpeciesID
    if speciesID and speciesID > 0 then
        return "pet:" .. speciesID
    end
    return tostring(auction.itemKey.itemID)
end

local function EntryItemID(entry)
    local key = entry.itemKey or ""
    local petID = key:match("^pet:(%d+)")
    if petID then return "pet:" .. petID end
    return key:match("^(%d+)")
end

function Tracker:CheckOwnedAuctions()
    if not ns.db or not C_AuctionHouse then return end

    local owned = C_AuctionHouse.GetOwnedAuctions()
    if not owned then return end

    local charKey = ns:GetCharKey()
    local currentRealm = GetRealmName()
    local now = time()

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

    -- If item names aren't cached yet, retry after a delay (up to 3 times).
    -- We skip the retry when there are no owned auctions — there's nothing to
    -- name-match against, and the reconcile pass below should still run so
    -- stale active log entries get cleared.
    if hasMissing and #owned > 0 and ownedAuctionCheckRetries < 3 then
        ownedAuctionCheckRetries = ownedAuctionCheckRetries + 1
        C_Timer.After(1, function()
            if Tracker._isAHOpen then
                Tracker:CheckOwnedAuctions()
            end
        end)
        return
    end
    ownedAuctionCheckRetries = 0

    -- Phase 1: match owned auctions to pending/skipped todo items.
    -- Each consumed auction results in a NEW "active" log entry via
    -- MoveTaskToLog; that entry participates in the count-based reconcile
    -- below alongside pre-existing active entries.
    local consumed = {} -- aIdx -> true
    local found = 0

    if ns.TodoList then
        local todoList = ns.TodoList:GetCurrentList()
        if todoList and todoList.tasks then
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
                        found = found + 1
                    end
                end
            end
        end
    end

    -- Phase 2: count-based reconciliation.
    -- Group owned auctions and this char's active log entries by item ID.
    -- For each ID: if log > owned, oldest excess entries are stale — mark
    -- them collected (or cancelled, consuming _pendingCancels). If owned >
    -- log, the difference becomes orphan entries in phase 3.
    local ownedListByID = {} -- itemID -> array of {aIdx, auction}
    for aIdx, auction in ipairs(owned) do
        local id = AuctionItemID(auction)
        if not ownedListByID[id] then ownedListByID[id] = {} end
        table.insert(ownedListByID[id], {aIdx = aIdx, auction = auction})
    end

    local activeByID = {} -- itemID -> array of entry refs (this char, active)
    for _, entry in ipairs(ns.db.log) do
        if entry.auctionStatus == "active" and entry.charKey == charKey then
            local id = EntryItemID(entry)
            if id then
                if not activeByID[id] then activeByID[id] = {} end
                table.insert(activeByID[id], entry)
            end
        end
    end

    local pendingCancels = Tracker._pendingCancels or 0
    local reconciledCount, cancelledCount = 0, 0

    for id, entries in pairs(activeByID) do
        local ownedCount = ownedListByID[id] and #ownedListByID[id] or 0
        local logCount = #entries
        if logCount > ownedCount then
            -- Stable-sort oldest-first so the freshest posts survive
            table.sort(entries, function(a, b)
                return (a.postedAt or 0) < (b.postedAt or 0)
            end)
            local excess = logCount - ownedCount
            for i = 1, excess do
                local entry = entries[i]
                if pendingCancels > 0 then
                    entry.auctionStatus = "cancelled"
                    entry.saleOutcome = "expired" -- cancelled = unsold
                    entry.endReason = "cancelled"
                    pendingCancels = pendingCancels - 1
                    cancelledCount = cancelledCount + 1
                else
                    -- Silently mark collected — ScanMailForSales or the TSM
                    -- reconcile will set saleOutcome when they can tell
                    -- whether this was a sale vs. an expire/cancel.
                    entry.auctionStatus = "collected"
                end
                reconciledCount = reconciledCount + 1
            end
        end
    end
    Tracker._pendingCancels = 0

    -- Phase 3: orphan recovery.
    -- For each owned auction without a matching active log entry, insert one.
    -- The accountedFor counter starts at the count of REMAINING active
    -- entries for this ID (after the phase-2 reconcile), and is decremented
    -- once per owned auction iterated. Consumed auctions (phase 1) already
    -- have matching active entries from MoveTaskToLog, so they naturally
    -- consume one slot each.
    local accountedFor = {}
    for id, entries in pairs(activeByID) do
        -- After reconcile, effective active count is min(log, owned)
        accountedFor[id] = math.min(#entries, ownedListByID[id] and #ownedListByID[id] or 0)
    end

    local recovered = 0
    for aIdx, auction in ipairs(owned) do
        local id = AuctionItemID(auction)
        local slots = accountedFor[id] or 0
        if slots > 0 then
            accountedFor[id] = slots - 1
        elseif ns.db.settings.salesLoggingEnabled ~= false then
            -- Orphan: no active log entry for this owned auction. Skipped
            -- entirely when sales logging is disabled (FQ-214) so the log
            -- isn't repopulated behind the player's back.
            local speciesID = auction.itemKey.battlePetSpeciesID
            local isPet = speciesID and speciesID > 0
            local auctionKey = isPet
                and ("pet:" .. speciesID .. ";;")
                or (tostring(auction.itemKey.itemID) .. ";;")
            local auctionName = auctionNames[aIdx] or ("Item " .. id)
            local expirySec = auction.timeLeftSeconds
            local estPostedAt = expirySec and (now - (172800 - expirySec)) or now

            table.insert(ns.db.log, {
                itemKey        = auctionKey,
                itemID         = id,
                name           = auctionName,
                quality        = "",
                icon           = nil,
                targetRealm    = currentRealm,
                expectedPrice  = "",
                postedPrice    = auction.buyoutAmount and ns:FormatGold(auction.buyoutAmount) or "",
                postedAt       = estPostedAt,
                charKey        = charKey,
                expiresAt      = expirySec and (now + expirySec) or nil,
                auctionStatus  = "active",
                soldAt         = nil,
                soldPrice      = nil,
                postedQuantity = auction.quantity or 1,
                isRecovered    = true,
            })
            recovered = recovered + 1
        end
    end

    if cancelledCount > 0 then
        ns:Print(ns.COLORS.YELLOW .. cancelledCount .. " auction(s) cancelled — items in mail.|r")
    end
    if recovered > 0 then
        ns:PrintDebug("Recovered " .. recovered .. " untracked auction(s) from AH.")
    end
    if reconciledCount > 0 then
        ns:PrintDebug("Reconciled " .. reconciledCount ..
            " stale log entries (not found on AH).")
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
                -- Resolve once per log entry, not once per (entry x auction)
                -- pair (FQ-223). Passing nil here meant ItemsMatch re-resolved
                -- inside the inner loop, and every miss walks all 69 characters'
                -- inventories plus the warbank via inventoryLookupByName — pet
                -- entries ("pet:<species>") and entries with no numeric itemID
                -- miss every time. `or false` tells ItemsMatch we've already
                -- done the lookup. Mirrors CheckOwnedAuctions above.
                local logResolvedID = ns:ResolveItemID(logEntry)
                -- Try to match against owned auctions to update/confirm expiry
                for aIdx, auction in ipairs(owned) do
                    local auctionName = auctionNames[aIdx]
                    local auctionKey = tostring(auction.itemKey.itemID) .. ";;"
                    local matches = ns:ItemsMatch(auctionKey, auctionName, logEntry, logResolvedID or false, false)

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
