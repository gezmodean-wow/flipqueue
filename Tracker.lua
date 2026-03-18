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
local preTodoSnapshot = {} -- taskIdx -> {todoItem, qty}

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
        local okSlots, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if not okSlots or not numSlots then numSlots = 0 end
        for slot = 1, numSlots do
            local okInfo, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
            if not okInfo then info = nil end
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
    wipe(preTodoSnapshot)
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

    -- Snapshot todo list items for bag-based post detection
    if ns.TodoList then
        local charKey = ns:GetCharKey()
        local todoList = ns.TodoList:GetCurrentList()
        if todoList and todoList.items then
            for taskIdx, todoItem in ipairs(todoList.items) do
                if todoItem.status == "pending" and todoItem.assignedChar == charKey
                    and ns:RealmMatches(todoItem.targetRealm or "", currentRealm) then
                    preTodoSnapshot[taskIdx] = {
                        todoItem = todoItem,
                        qty = CountInBags(todoItem),
                    }
                end
            end
        end
    end
end

local function CheckForPosts()
    if not ns.db then return end

    local hasTodoTracking = next(preTodoSnapshot) ~= nil

    -- Check todo list items first (primary system in v0.6.0)
    local todoPosted = {}
    for taskIdx, snap in pairs(preTodoSnapshot) do
        if snap.todoItem.status == "pending" then
            local curQty = CountInBags(snap.todoItem)
            if curQty < snap.qty then
                local count = snap.qty - curQty
                table.insert(todoPosted, {taskIdx = taskIdx, item = snap.todoItem, count = count})
            end
        end
    end

    -- Process todo posts (reverse order to preserve indices)
    table.sort(todoPosted, function(a, b) return a.taskIdx > b.taskIdx end)
    for _, p in ipairs(todoPosted) do
        local taskQty = p.item.quantity or 1
        if p.count < taskQty then
            ns:Print(ns.COLORS.GREEN .. "Posted:|r " .. p.item.name .. " (x" .. p.count .. " of " .. taskQty .. ")")
        else
            ns:Print(ns.COLORS.GREEN .. "Posted:|r " .. p.item.name .. " (x" .. p.count .. ")")
        end
        ns.TodoList:MoveTaskToLog(p.taskIdx, nil, nil, p.count)
    end

    -- Check queue items (legacy — skip if todo tracking is active to avoid double-counting)
    local posted = {}
    if not hasTodoTracking then
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

        table.sort(posted, function(a, b) return a.idx > b.idx end)
        for _, p in ipairs(posted) do
            local queueQty = p.item.quantity or 1
            if p.count < queueQty then
                ns:Print(ns.COLORS.GREEN .. "Posted:|r " .. p.item.name .. " (x" .. p.count .. " of " .. queueQty .. ")")
            else
                ns:Print(ns.COLORS.GREEN .. "Posted:|r " .. p.item.name .. " (x" .. p.count .. ")")
            end
            ns.Queue:MoveToLog(p.idx, nil, nil, p.count)
        end
    end

    if #todoPosted > 0 or #posted > 0 then
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
    if not owned then return end

    -- If no auctions on AH, reconcile all "active" log entries for this character
    if #owned == 0 then
        local charKey = ns:GetCharKey()
        local cleared = 0
        for _, entry in ipairs(ns.db.log) do
            if entry.auctionStatus == "active" and entry.charKey == charKey then
                entry.auctionStatus = "collected"
                cleared = cleared + 1
            end
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
    -- Match against queue items
    for i = #ns.db.queue, 1, -1 do
        local queueItem = ns.db.queue[i]
        if queueItem.status == "pending" and ns:RealmMatches(queueItem.targetRealm, currentRealm) then
            for aIdx, auction in ipairs(owned) do
                if not consumed[aIdx] then
                    local auctionName = auctionNames[aIdx]
                    local auctionKey = tostring(auction.itemKey.itemID) .. ";;"
                    local matches = ns:ItemsMatch(auctionKey, auctionName, queueItem, resolvedIDs[i] or false)

                    if matches then
                        consumed[aIdx] = true
                        found = found + 1
                        local auctionQty = auction.quantity or 1
                        local queueQty = queueItem.quantity or 1
                        if auctionQty < queueQty then
                            ns:PrintDebug("Already listed: " .. queueItem.name ..
                                " (x" .. auctionQty .. " of " .. queueQty .. ") — moving to log")
                        else
                            ns:PrintDebug("Already listed: " .. queueItem.name .. " — moving to log")
                        end
                        local expirySec = auction.timeLeftSeconds
                        ns.Queue:MoveToLog(i, nil, expirySec, auctionQty)
                        break
                    end
                end
            end
        end
    end

    -- Match against active to-do list items (consume multiple auctions per todo item)
    if ns.TodoList then
        local todoList = ns.TodoList:GetCurrentList()
        if todoList and todoList.items then
            local charKey = ns:GetCharKey()
            for taskIdx, todoItem in ipairs(todoList.items) do
                if todoItem.status == "pending" and todoItem.assignedChar == charKey
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
                        ns:PrintDebug("Listed: " .. (todoItem.name or "?") .. " x" .. totalMatched .. " — marking done")
                        ns.TodoList:MoveTaskToLog(taskIdx, nil, firstExpiry, totalMatched)
                    end
                end
            end
        end
    end

    -- State recovery: discover orphaned auctions not in queue or log
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

    -- Count consumed auctions (matched to queue) per item ID
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
            local auctionID = tostring(auction.itemKey.itemID)
            local accounted = accountedFor[auctionID] or 0

            if accounted > 0 then
                -- This auction is accounted for by an existing log entry
                accountedFor[auctionID] = accounted - 1
            else
                -- Orphaned auction: not in queue or log
                local auctionKey = auctionID .. ";;"
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

    -- Walk log entries for this character: if "active" but not on AH, mark collected
    local reconciledCount = 0
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
                    -- No matching auction on AH — this entry is stale
                    entry.auctionStatus = "collected"
                    reconciledCount = reconciledCount + 1
                end
            end
        end
    end

    if reconciledCount > 0 then
        ns:PrintDebug("Reconciled " .. reconciledCount ..
            " stale log entries (not found on AH).|r")
    end

    if found > 0 or recovered > 0 or reconciledCount > 0 then
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

    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
    local tsmEnabled = ns.TSM and ns.TSM:IsEnabled()
    local defaultQty = ns.db.settings.defaultSellQty or 1

    -- Build needed list from the active to-do list
    local needed = {} -- item -> qty still needed from bank

    if ns.TodoList and ns.TodoList:GetCurrentList() then
        local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(todoTasks) do
            local item = task.item
            if ns:RealmMatches(item.targetRealm or "", currentRealm) then
                local targetQty = math.max(item.quantity or 1, defaultQty)
                if tsmEnabled then
                    local op = ns.TSM:GetItemAuctioningOp(item.itemKey)
                    if op and op.postCap then
                        local tsmQty = tonumber(op.postCap)
                        if tsmQty and tsmQty > 0 then targetQty = tsmQty end
                    end
                end
                local inBags = CountInBags(item)
                local stillNeeded = targetQty - inBags
                if stillNeeded > 0 then
                    needed[item] = stillNeeded
                end
            end
        end
    end

    if not next(needed) then return end

    local allBankTabs = {}
    for _, b in ipairs(ns:GetEnabledBankTabs()) do table.insert(allBankTabs, b) end
    for _, b in ipairs(ns:GetEnabledWarbankTabs()) do table.insert(allBankTabs, b) end

    if not next(needed) then return end

    -- Build a list of moves to make — only pull items that match task queue items
    local moves = {}
    for _, bagIndex in ipairs(allBankTabs) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink and not info.isBound then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                        local slotName  -- lazy name cache per slot
                        for queueItem, count in pairs(needed) do
                            if count > 0 then
                                -- Use false for resolvedID to prevent wrong ID matches
                                local matched = ns:ItemsMatch(key, nil, queueItem, false, false)
                                if not matched then
                                    if slotName == nil then slotName = GetNameFromLink(info.hyperlink) or false end
                                    if slotName then
                                        matched = ns:ItemsMatch(key, slotName, queueItem, false, false)
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
            if ns.Scanner then
                ns.Scanner:ScanCurrentCharacter()
                ns.Scanner:ScanBank()
            end
            if ns.TodoList and ns.TodoList.RefreshLocations then
                ns.TodoList:RefreshLocations()
            end
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
            if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
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

    ns:PrintDebug("Pulling " .. totalMoves .. " item(s) from bank...")
    ExecuteNextBatch()
end

--------------------------
-- Warbank Gold Withdrawal
--------------------------

-- Track withdrawals per session to avoid re-withdrawing
local sessionWithdrawnCopper = 0
local sessionWithdrawnRealm = nil

function Tracker:AutoWithdrawGold()
    if not ns.db or not ns.db.settings.autoWithdrawGold then return end
    if not C_Bank or not C_Bank.WithdrawMoney then return end

    -- Only withdraw if this character actually has tasks on its realm
    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
    local hasTasks = false
    if ns.Queue then
        local allTasks = ns.Queue:GetCharacterTasks(charKey)
        for _, task in ipairs(allTasks) do
            if ns:RealmMatches(task.queueItem.targetRealm, currentRealm) then
                hasTasks = true
                break
            end
        end
    end
    if not hasTasks then return end

    -- Reset session tracker if realm changed
    if sessionWithdrawnRealm ~= currentRealm then
        sessionWithdrawnCopper = 0
        sessionWithdrawnRealm = currentRealm
    end

    -- Calculate fees ONLY for items in GetCharacterTasks — same source as pull
    local DURATION_MULT = {[1] = 0.15, [2] = 0.30, [3] = 0.60}
    local DURATION_LABEL = {[1] = "12h", [2] = "24h", [3] = "48h"}
    local tsmEnabled = ns.TSM and ns.TSM:IsEnabled()

    local goldTasks = ns.Queue:GetCharacterTasks(charKey)
    local totalDepositCopper = 0
    local itemCount = 0
    local depositDetails = {} -- for verbose logging

    for _, task in ipairs(goldTasks) do
        if ns:RealmMatches(task.queueItem.targetRealm, currentRealm) then
            local queueItem = task.queueItem
            itemCount = itemCount + 1

            -- Determine post quantity: defaultSellQty as base, TSM postCap overrides
            local postQty = math.max(queueItem.quantity or 1, ns.db.settings.defaultSellQty or 1)
            local durationMult = 0.60 -- default: assume 48h
            local durationLabel = "48h"
            if tsmEnabled then
                local op = ns.TSM:GetItemAuctioningOp(queueItem.itemKey)
                if op then
                    if op.postCap then
                        local tsmQty = tonumber(op.postCap)
                        if tsmQty and tsmQty > 0 then
                            postQty = tsmQty
                        end
                    end
                    if op.duration then
                        durationMult = DURATION_MULT[op.duration] or 0.60
                        durationLabel = DURATION_LABEL[op.duration] or "48h"
                    end
                end
            end

            -- Look up vendor sell price from item ID
            local numID = tonumber(queueItem.itemID)
            if not numID or numID <= 0 then
                numID = tonumber((queueItem.itemKey or ""):match("^(%d+)"))
            end
            local itemDeposit = 0
            local vendorPrice = 0
            if numID and numID > 0 then
                -- Try to find the actual item link from bags for accurate vendor price
                -- Queue data often lacks bonus IDs, so base ID returns wrong price
                local sellPrice = nil

                -- Search bags for the actual item to get its real link
                for _, bagIndex in ipairs(ns.INVENTORY_BAGS) do
                    local okSlots, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
                    if not okSlots or not numSlots then numSlots = 0 end
                    for slot = 1, numSlots do
                        local okInfo, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                        if not okInfo then info = nil end
                        if info and info.hyperlink then
                            local slotID = tonumber((ns:ParseItemLink(info.hyperlink)))
                            if slotID == numID then
                                -- Found it in bags — use the real link for vendor price
                                local ok, _, _, _, _, _, _, _, _, _, _, sp =
                                    pcall(C_Item.GetItemInfo, info.hyperlink)
                                if ok and sp and type(sp) == "number" and sp > 0 then
                                    sellPrice = sp
                                end
                                break
                            end
                        end
                    end
                    if sellPrice then break end
                end

                -- Fallback: use base item ID (may be inaccurate for bonus ID items)
                if not sellPrice then
                    local ok, _, _, _, _, _, _, _, _, _, _, sp =
                        pcall(C_Item.GetItemInfo, numID)
                    if ok and sp and type(sp) == "number" and sp > 0 then
                        sellPrice = sp
                    end
                end

                if sellPrice then
                    vendorPrice = sellPrice
                    itemDeposit = math.ceil(sellPrice * durationMult) * postQty
                else
                    -- No vendor price found — estimate from expected sale price (5% of market)
                    local expectedGold = ns:ParseGoldValue(queueItem.expectedPrice or "")
                    if expectedGold > 0 then
                        vendorPrice = expectedGold * 100 * 0.05  -- 5% of gold as copper
                        itemDeposit = math.ceil(vendorPrice * durationMult) * postQty
                    else
                        -- Absolute minimum: 1s per item
                        vendorPrice = 100
                        itemDeposit = math.ceil(100 * durationMult) * postQty
                    end
                end
                totalDepositCopper = totalDepositCopper + itemDeposit
            end

            table.insert(depositDetails, {
                name = queueItem.name or tostring(queueItem.itemID),
                vendorCopper = vendorPrice,
                duration = durationLabel,
                mult = durationMult,
                deposit = itemDeposit,
                qty = postQty,
            })
        end
    end

    if itemCount == 0 then return end

    -- Print deposit breakdown (debug only)
    ns:PrintDebug(ns.COLORS.YELLOW .. "AH fee calc for " .. itemCount .. " task(s):|r")
    for _, d in ipairs(depositDetails) do
        local vendorStr = ns:FormatGold(d.vendorCopper)
        local depositStr = ns:FormatGold(d.deposit)
        ns:PrintDebug("  " .. d.name .. ": vendor=" .. vendorStr ..
            " x" .. d.qty .. " @ " .. d.duration ..
            " (" .. string.format("%.0f%%", d.mult * 100) .. ") = " .. depositStr)
    end

    -- Add a small buffer (1g minimum, 10% extra for rounding)
    local estimatedFeesCopper = math.max(10000, math.ceil(totalDepositCopper * 1.1))
    local estimatedFeesGold = math.ceil(estimatedFeesCopper / 10000)

    ns:PrintDebug("  Total deposit: " .. ns:FormatGold(totalDepositCopper) ..
        " + 10% buffer = " .. ns:FormatGold(estimatedFeesCopper))

    -- Account for what we've already withdrawn this session
    local playerCopper = GetMoney()
    local effectiveCopper = playerCopper + sessionWithdrawnCopper

    if effectiveCopper >= estimatedFeesCopper then return end -- already have enough (including prior withdrawals)

    -- Also just check raw gold — if player has enough, skip
    if playerCopper >= estimatedFeesCopper then return end

    local shortfallCopper = estimatedFeesCopper - playerCopper
    local shortfallGold = math.ceil(shortfallCopper / 10000)
    local playerGold = math.floor(playerCopper / 10000)

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

    -- Round up to whole gold
    shortfallCopper = shortfallGold * 10000

    if warbankCopper < shortfallCopper then
        local warbankGold = math.floor(warbankCopper / 10000)
        ns:Print(ns.COLORS.RED .. "Not enough in warbank.|r Need " .. shortfallGold ..
            "g more, warbank has " .. warbankGold .. "g")
        return
    end

    -- Withdraw
    local ok3, err = pcall(C_Bank.WithdrawMoney, Enum.BankType.Account, shortfallCopper)
    if ok3 then
        sessionWithdrawnCopper = sessionWithdrawnCopper + shortfallCopper
        ns:Print(ns.COLORS.GREEN .. "Withdrew " .. shortfallGold .. "g|r from warbank" ..
            " (est. " .. estimatedFeesGold .. "g fees for " .. itemCount .. " items, had " .. playerGold .. "g)")
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
    local alertMinutes = ns.db.settings.expiryAlertMinutes or 15
    local threshold = alertMinutes * 60
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
                local ck = entry.charKey or "Unknown"
                newlyExpired[ck] = (newlyExpired[ck] or 0) + 1

                -- Auto-skip the matching queue item so it won't be re-pulled
                -- It stays in the queue for the generator to reassign
                if ns.Queue then
                    for i, qItem in ipairs(ns.db.queue) do
                        if qItem.status == "pending" then
                            local nameMatch = entry.name and qItem.name
                                and entry.name:lower() == qItem.name:lower()
                            local keyMatch = entry.itemKey and entry.itemKey == qItem.itemKey
                            if keyMatch or nameMatch then
                                ns.Queue:Skip(i)
                                break
                            end
                        end
                    end
                end
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
            local cleared = 0
            for _, entry in ipairs(ns.db.log) do
                if entry.auctionStatus == "expired" and entry.charKey == charKey then
                    entry.auctionStatus = "collected"
                    cleared = cleared + 1
                end
            end
            if cleared > 0 then
                ns:Print(ns.COLORS.GREEN .. "Collected " .. cleared .. " expired auction(s).|r")
            end
        end

        if ns.Queue then
            local charKey = ns:GetCharKey()
            local myRealm = charKey:match("%-(.+)$") or ""
            local allTasks = ns.Queue:GetCharacterTasks(charKey)
            local realmTasks = 0
            for _, task in ipairs(allTasks) do
                if ns:RealmMatches(task.queueItem.targetRealm, myRealm) then
                    realmTasks = realmTasks + 1
                end
            end
            if realmTasks > 0 then
                ns:Print(ns.COLORS.GREEN .. realmTasks .. " items|r in your queue ready to post!")
            end
        end

        -- Request owned auctions to check for already-listed items
        if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then
            C_AuctionHouse.QueryOwnedAuctions({})
        end

        -- Refresh UI to clear "Check AH" tasks
        if ns.UI then
            if ns.UI.RefreshMini then ns.UI:RefreshMini() end
            if ns.UI.Refresh then ns.UI:Refresh() end
        end

    elseif event == "AUCTION_HOUSE_CLOSED" then
        isAHOpen = false
        wipe(prePostSnapshot)
        wipe(preTodoSnapshot)

    elseif event == "BAG_UPDATE_DELAYED" then
        if isAHOpen and (next(prePostSnapshot) or next(preTodoSnapshot)) then
            C_Timer.After(0.3, CheckForPosts)
        end
        -- Rescan inventory and refresh todo locations on every item movement
        C_Timer.After(0.5, function()
            if ns.Scanner then ns.Scanner:ScanCurrentCharacter() end
            if ns.TodoList and ns.TodoList.RefreshLocations then
                ns.TodoList:RefreshLocations()
            end
            if ns.UI and ns.UI.mainFrame and ns.UI.mainFrame:IsShown() then
                if ns.UI.currentPage == "todo" or ns.UI.currentPage == "generator" then
                    ns.UI:Refresh()
                end
            end
        end)

    elseif event == "BANKFRAME_OPENED" then
        C_Timer.After(1, function()
            -- Scanner already scans bags/bank/warbank at 0.5s — just do auto-pull and gold here
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

        -- Mark expired auctions as collected (user is checking mail)
        if ns.db then
            local charKey = ns:GetCharKey()
            for _, entry in ipairs(ns.db.log) do
                if entry.auctionStatus == "expired" and entry.charKey == charKey then
                    entry.auctionStatus = "collected"
                end
            end
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
