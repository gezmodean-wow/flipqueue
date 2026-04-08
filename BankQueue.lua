-- BankQueue.lua
-- Transactional queue processor for bank/warbank item moves.
-- Processes batches through a single destructive pipeline with
-- post-batch verification — no move is counted as success until
-- the source slot is confirmed empty.
local addonName, ns = ...

local BankQueue = {}
ns.BankQueue = BankQueue

--------------------------
-- Constants
--------------------------

local VERIFY_DELAY = 0.5     -- seconds after lock events settle before verifying batch
local BATCH_TIMEOUT = 5      -- seconds before verifying batch without lock event
local MAX_RETRIES = 4        -- retry attempts per failed move
local INTER_BATCH_DELAY = 0.3  -- pause between batches

--------------------------
-- Helpers
--------------------------

-- Determine the bank type for a bag ID
local function GetBankTypeForBag(bagID)
    if bagID >= Enum.BagIndex.AccountBankTab_1 and bagID <= Enum.BagIndex.AccountBankTab_5 then
        return Enum.BankType.Account
    elseif bagID == Enum.BagIndex.Bank or (bagID >= Enum.BagIndex.BankBag_1 and bagID <= Enum.BagIndex.BankBag_7) then
        return Enum.BankType.Character
    end
    return nil
end

-- Ensure BankFrame's active panel matches the given bank type. Baganator does
-- the same thing — BankFrame.BankPanel:SetBankType() must match the bag type
-- being operated on, or the server silently rejects the move.
local function SetBankPanelType(bankType)
    if not bankType then return end
    if BankFrame and BankFrame.BankPanel and BankFrame.BankPanel.SetBankType then
        local current = BankFrame.BankPanel.GetActiveBankType and BankFrame.BankPanel:GetActiveBankType()
        if current ~= bankType then
            BankFrame.BankPanel:SetBankType(bankType)
        end
    end
end

-- Wrapper that derives the bank type from a bag ID. For inventory bags this
-- is a no-op (no bank panel state to set).
local function EnsureBankType(bagID)
    SetBankPanelType(GetBankTypeForBag(bagID))
end

-- Snapshot total stack counts of every itemID across a list of bags.
-- Used to verify moves by destination delta — checking that the source slot
-- went empty is unreliable, because a server-rejected destination placement
-- can leave the source empty (item returned to a different bank slot) while
-- the item never actually arrived in the destination.
local function CountItemsInBags(bagList)
    local counts = {}
    if not bagList then return counts end
    for _, bag in ipairs(bagList) do
        local ok, num = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and num then
            for slot = 1, num do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if ok2 and info and info.itemID then
                    counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
                end
            end
        end
    end
    return counts
end

-- Find first empty slot in a list of bag IDs
local function FindFreeSlot(bagList)
    for _, bagIdx in ipairs(bagList) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIdx)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIdx, slot)
                if ok2 and not info then
                    return bagIdx, slot
                end
            end
        end
    end
    return nil, nil
end

-- Execute a cursor-based item move: pick up from src, place at dst.
-- Returns true if the move was issued, false otherwise.
-- Kept as a fallback for cases where ShiftMove can't be used.
local function CursorMove(srcBag, srcSlot, dstBag, dstSlot)
    pcall(ClearCursor)
    pcall(C_Container.PickupContainerItem, srcBag, srcSlot)
    if CursorHasItem() then
        pcall(C_Container.PickupContainerItem, dstBag, dstSlot)
        if not CursorHasItem() then
            return true
        end
        pcall(ClearCursor)
    end
    return false
end

-- Shift-click style move: a single C_Container.UseContainerItem call.
-- When a bank frame is open, this routes the item to/from the bank in one
-- server message instead of two — half the rate-limit pressure of the
-- pickup+place dance, no cursor state to leak between back-to-back moves,
-- and the server picks the destination slot (including auto-stacking onto
-- existing partial stacks). This is what Baganator/Bagnon use for mass
-- transfers.
--
-- IMPORTANT: must NOT be called when no bank frame is open — otherwise
-- UseContainerItem falls back to "use the item" semantics (eats food, drinks
-- a potion, etc.). Caller must verify BankFrame:IsShown() first.
local function ShiftMove(srcBag, srcSlot)
    pcall(ClearCursor)
    local ok = pcall(C_Container.UseContainerItem, srcBag, srcSlot)
    return ok
end

-- Is a bank frame currently open? Required precondition for ShiftMove —
-- without an open bank, UseContainerItem would consume/use the item.
local function IsBankOpen()
    return BankFrame and BankFrame:IsShown()
end

--------------------------
-- Queue Processor
--------------------------

local queue = {}             -- ordered operations awaiting processing
local stats = { successes = {}, errors = 0 }
local onComplete = nil
local progressLabel = ""
local totalQueued = 0
local listener = nil

local function GetListener()
    if not listener then
        listener = CreateFrame("Frame")
    end
    return listener
end

local function Finish()
    local l = GetListener()
    l:UnregisterAllEvents()
    l:SetScript("OnEvent", nil)
    BankQueue.processing = false
    if onComplete then
        local cb = onComplete
        onComplete = nil
        cb(stats.successes, stats.errors)
    end
end

local ProcessNextBatch  -- forward declaration

local function VerifyBatch(issuedOps, snapshot)
    local retryOps = {}

    -- Re-snapshot the destination bags so we can verify by delta.
    local invAfter = CountItemsInBags(ns.INVENTORY_BAGS)
    local warbankAfter = CountItemsInBags(snapshot.warbankBags)
    local bankAfter = CountItemsInBags(snapshot.bankBags)
    local invDelta, warbankDelta, bankDelta = {}, {}, {}
    local function deltaFor(t, after, before, id)
        if t[id] == nil then t[id] = (after[id] or 0) - (before[id] or 0) end
        return t[id]
    end

    for _, op in ipairs(issuedOps) do
        local id = op._itemID
        local consume = op._stackBefore or 1
        local moved = false
        if id then
            if op.op == "pull" then
                if deltaFor(invDelta, invAfter, snapshot.inv, id) >= consume then
                    invDelta[id] = invDelta[id] - consume
                    moved = true
                end
            elseif op.op == "deposit" then
                if op.destType == "warbank" then
                    if deltaFor(warbankDelta, warbankAfter, snapshot.warbank, id) >= consume then
                        warbankDelta[id] = warbankDelta[id] - consume
                        moved = true
                    end
                elseif op.destType == "bank" then
                    if deltaFor(bankDelta, bankAfter, snapshot.bank, id) >= consume then
                        bankDelta[id] = bankDelta[id] - consume
                        moved = true
                    end
                else
                    if deltaFor(warbankDelta, warbankAfter, snapshot.warbank, id) >= consume then
                        warbankDelta[id] = warbankDelta[id] - consume
                        moved = true
                    elseif deltaFor(bankDelta, bankAfter, snapshot.bank, id) >= consume then
                        bankDelta[id] = bankDelta[id] - consume
                        moved = true
                    end
                end
            end
        else
            local ok, info = pcall(C_Container.GetContainerItemInfo, op.srcBag, op.srcSlot)
            moved = ok and not info
        end

        if moved then
            table.insert(stats.successes, op.name)
        else
            op._retries = (op._retries or 0) + 1
            if op._retries <= MAX_RETRIES then
                -- Clear captured snapshot fields so the retry recaptures fresh state.
                op._itemID = nil
                op._stackBefore = nil
                table.insert(retryOps, op)
            else
                stats.errors = stats.errors + 1
            end
        end
    end

    for _, op in ipairs(retryOps) do
        table.insert(queue, op)
    end

    -- Notify progress callback if registered
    if BankQueue.onProgress then
        BankQueue.onProgress(#stats.successes, totalQueued)
    end
    C_Timer.After(INTER_BATCH_DELAY, ProcessNextBatch)
end

ProcessNextBatch = function()
    if #queue == 0 then
        C_Timer.After(0.1, Finish)
        return
    end

    local batchSize = ns.db and ns.db.settings.pullBatchSize or 5
    local batchCount = math.min(batchSize, #queue)

    local batch = {}
    for i = 1, batchCount do
        table.insert(batch, table.remove(queue, 1))
    end

    -- Snapshot bags before issuing this batch's moves so VerifyBatch can
    -- check destination delta instead of just source-slot emptiness.
    local snapshot = {
        warbankBags = ns:GetEnabledWarbankTabs() or {},
        bankBags = ns:GetEnabledBankTabs() or {},
    }
    snapshot.inv = CountItemsInBags(ns.INVENTORY_BAGS)
    snapshot.warbank = CountItemsInBags(snapshot.warbankBags)
    snapshot.bank = CountItemsInBags(snapshot.bankBags)

    local issuedOps = {}
    local abortPulls = false
    local abortDeposits = false
    local bankOpen = IsBankOpen()

    for _, op in ipairs(batch) do
        local ok, info = pcall(C_Container.GetContainerItemInfo, op.srcBag, op.srcSlot)
        if not ok or not info then
            -- Source empty — already moved or gone
        elseif info.isLocked then
            op._lockWaits = (op._lockWaits or 0) + 1
            if op._lockWaits > 10 then
                stats.errors = stats.errors + 1
            else
                table.insert(queue, op)
            end
        elseif op.op == "pull" then
            if abortPulls then
                -- skip
            elseif not bankOpen then
                abortPulls = true
                ns:Print(ns.COLORS.RED .. "Bank closed!|r Skipping remaining pulls.")
            else
                EnsureBankType(op.srcBag)
                op._itemID = info.itemID
                op._stackBefore = info.stackCount or 1
                ShiftMove(op.srcBag, op.srcSlot)
                table.insert(issuedOps, op)
            end
        elseif op.op == "deposit" then
            if abortDeposits then
                -- skip
            elseif not bankOpen then
                abortDeposits = true
                ns:Print(ns.COLORS.RED .. "Bank closed!|r Skipping remaining deposits.")
            else
                local destBankType
                if op.destType == "warbank" then
                    destBankType = Enum.BankType.Account
                elseif op.destType == "bank" then
                    destBankType = Enum.BankType.Character
                else
                    destBankType = Enum.BankType.Account
                end
                SetBankPanelType(destBankType)
                op._itemID = info.itemID
                op._stackBefore = info.stackCount or 1
                ShiftMove(op.srcBag, op.srcSlot)
                table.insert(issuedOps, op)
            end
        end
    end

    if abortPulls then
        for i = #queue, 1, -1 do
            if queue[i].op == "pull" then table.remove(queue, i) end
        end
    end
    if abortDeposits then
        for i = #queue, 1, -1 do
            if queue[i].op == "deposit" then table.remove(queue, i) end
        end
    end

    if #issuedOps == 0 then
        if BankQueue.onProgress then
            BankQueue.onProgress(#stats.successes, totalQueued)
        end
        if #queue > 0 then
            C_Timer.After(0.3, ProcessNextBatch)
        else
            C_Timer.After(0.1, Finish)
        end
        return
    end

    -- Debounced verification via ITEM_LOCK_CHANGED events
    local awaitingConfirm = true
    local verifyTimer = nil
    local l = GetListener()

    local function ScheduleVerify()
        if verifyTimer then verifyTimer:Cancel() end
        verifyTimer = C_Timer.NewTimer(VERIFY_DELAY, function()
            if awaitingConfirm then
                awaitingConfirm = false
                VerifyBatch(issuedOps, snapshot)
            end
        end)
    end

    l:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "UI_ERROR_MESSAGE" then
            local message = arg2
            if message == ERR_INV_FULL
                or (type(message) == "string" and message:find("Inventory is full")) then
                local opType = issuedOps[1] and issuedOps[1].op
                if opType then
                    for i = #queue, 1, -1 do
                        if queue[i].op == opType then table.remove(queue, i) end
                    end
                end
            end
        elseif event == "ITEM_LOCK_CHANGED" and awaitingConfirm then
            ScheduleVerify()
        end
    end)

    C_Timer.After(BATCH_TIMEOUT, function()
        if awaitingConfirm then
            awaitingConfirm = false
            if verifyTimer then verifyTimer:Cancel() end
            VerifyBatch(issuedOps, snapshot)
        end
    end)
end

--------------------------
-- Public API
--------------------------

BankQueue.processing = false
BankQueue.onProgress = nil  -- callback(current, total) for UI progress updates

function BankQueue:Process(ops, label, callback)
    if #ops == 0 then
        if callback then callback({}, 0) end
        return
    end

    queue = ops
    stats = { successes = {}, errors = 0 }
    onComplete = callback
    progressLabel = label
    totalQueued = #ops
    BankQueue.processing = true

    local l = GetListener()
    l:RegisterEvent("UI_ERROR_MESSAGE")
    l:RegisterEvent("ITEM_LOCK_CHANGED")

    if BankQueue.onProgress then
        BankQueue.onProgress(0, totalQueued)
    end
    ProcessNextBatch()
end

function BankQueue:Abort()
    if not BankQueue.processing then return end
    wipe(queue)
    local l = GetListener()
    l:UnregisterAllEvents()
    l:SetScript("OnEvent", nil)
    BankQueue.processing = false
    if onComplete then
        local cb = onComplete
        onComplete = nil
        cb(stats.successes, stats.errors)
    end
end

--------------------------
-- Synchronous Execution (for hardware event context)
--------------------------

local SYNC_MAX_RETRIES = 4      -- per-op retries inside ProcessSync
local SYNC_VERIFY_DELAY = 0.4   -- short delay after last move before verifying
local SYNC_RETRY_DELAY = 0.2    -- pause between attempts
local SYNC_INTER_MOVE_DELAY = 0.1  -- pause between successive UseContainerItem calls
                                   -- (Blizzard rate-limits container ops; ~16ms/frame
                                   -- isn't enough — 100ms is safe and barely noticeable)
local SYNC_PANEL_SETTLE_DELAY = 0.05  -- pause after BankFrame:SetBankType() so the
                                       -- panel switch propagates before the next move

function BankQueue:ProcessSync(ops, label, callback)
    if #ops == 0 then
        if callback then callback({}, 0) end
        return
    end

    BankQueue.processing = true

    -- Cache enabled bag lists once so every snapshot scans identical bag sets,
    -- even if settings change while we're retrying.
    local warbankBags = ns:GetEnabledWarbankTabs() or {}
    local bankBags = ns:GetEnabledBankTabs() or {}

    local successNames = {}

    -- One attempt at moving the given ops. Failed ops are retried up to
    -- SYNC_MAX_RETRIES times — most "failed" pulls are transient (cursor
    -- state conflict from rapid back-to-back pickups, server rate limiting,
    -- bank panel mode mid-flight) and succeed on the next pass.
    --
    -- Moves are issued one per frame (via C_Timer.After(0, ...)) instead of
    -- all in a tight loop, to avoid the "Internal bag error" rate limit
    -- Blizzard throws when too many container ops happen in a single frame.
    local Attempt
    Attempt = function(remainingOps, attemptNum, finishAttempts)
        local issuedOps = {}
        local nonRetryableErrors = 0  -- e.g. bags full

        local invBefore = CountItemsInBags(ns.INVENTORY_BAGS)
        local warbankBefore = CountItemsInBags(warbankBags)
        local bankBefore = CountItemsInBags(bankBags)

        -- Hard safety gate: ShiftMove must NOT be invoked unless a bank
        -- frame is open, otherwise UseContainerItem would consume/use the
        -- item instead of moving it.
        local bankOpen = IsBankOpen()

        -- Track the active bank panel locally so we only call SetBankType
        -- when the type actually needs to change. Each switch costs a settle
        -- delay before the next move, so we want to minimise switches.
        local currentPanelType = nil
        if BankFrame and BankFrame.BankPanel and BankFrame.BankPanel.GetActiveBankType then
            currentPanelType = BankFrame.BankPanel:GetActiveBankType()
        end

        -- Compute the bank type required to route this op via shift-click.
        local function NeededBankType(op)
            if op.op == "pull" then
                return GetBankTypeForBag(op.srcBag)
            elseif op.op == "deposit" then
                if op.destType == "warbank" then return Enum.BankType.Account
                elseif op.destType == "bank" then return Enum.BankType.Character
                else return Enum.BankType.Account end  -- prefer warbank
            end
        end

        -- Returns true if a panel switch was performed (so the caller can
        -- delay the next move to let the switch settle).
        local function EnsurePanel(neededType)
            if not neededType or currentPanelType == neededType then return false end
            SetBankPanelType(neededType)
            currentPanelType = neededType
            return true
        end

        local function IssueOne(op)
            local ok, info = pcall(C_Container.GetContainerItemInfo, op.srcBag, op.srcSlot)
            if not ok or not info then
                -- Source slot empty: item is gone (already moved by a prior
                -- attempt or removed externally). Don't count as success or
                -- error here — if a prior attempt moved it, that was already
                -- counted in successNames.
                return false
            elseif info.isLocked then
                -- Locked from a prior in-flight move. Treat as retryable —
                -- queue it for the next attempt.
                op._itemID = info.itemID
                op._stackBefore = info.stackCount or 1
                table.insert(issuedOps, op)
                return false
            elseif op.op == "pull" or op.op == "deposit" then
                if not bankOpen then
                    nonRetryableErrors = nonRetryableErrors + 1
                    return false
                end
                op._itemID = info.itemID
                op._stackBefore = info.stackCount or 1
                ShiftMove(op.srcBag, op.srcSlot)
                table.insert(issuedOps, op)
                return true
            end
            return false
        end

        -- Continuation called once every op has been issued (one per frame).
        local function AfterAllIssued()
            pcall(ClearCursor)

            if #issuedOps == 0 then
                finishAttempts(nonRetryableErrors)
                return
            end

            C_Timer.After(SYNC_VERIFY_DELAY, function()
            local invAfter = CountItemsInBags(ns.INVENTORY_BAGS)
            local warbankAfter = CountItemsInBags(warbankBags)
            local bankAfter = CountItemsInBags(bankBags)

            local invDelta, warbankDelta, bankDelta = {}, {}, {}
            local function deltaFor(t, after, before, id)
                if t[id] == nil then t[id] = (after[id] or 0) - (before[id] or 0) end
                return t[id]
            end

            local nextRound = {}
            for _, op in ipairs(issuedOps) do
                local id = op._itemID
                local consume = op._stackBefore or 1
                local moved = false
                if id then
                    if op.op == "pull" then
                        if deltaFor(invDelta, invAfter, invBefore, id) >= consume then
                            invDelta[id] = invDelta[id] - consume
                            moved = true
                        end
                    elseif op.op == "deposit" then
                        if op.destType == "warbank" then
                            if deltaFor(warbankDelta, warbankAfter, warbankBefore, id) >= consume then
                                warbankDelta[id] = warbankDelta[id] - consume
                                moved = true
                            end
                        elseif op.destType == "bank" then
                            if deltaFor(bankDelta, bankAfter, bankBefore, id) >= consume then
                                bankDelta[id] = bankDelta[id] - consume
                                moved = true
                            end
                        else
                            if deltaFor(warbankDelta, warbankAfter, warbankBefore, id) >= consume then
                                warbankDelta[id] = warbankDelta[id] - consume
                                moved = true
                            elseif deltaFor(bankDelta, bankAfter, bankBefore, id) >= consume then
                                bankDelta[id] = bankDelta[id] - consume
                                moved = true
                            end
                        end
                    end
                else
                    -- itemID unavailable: fall back to source-empty check
                    local ok2, info2 = pcall(C_Container.GetContainerItemInfo, op.srcBag, op.srcSlot)
                    moved = ok2 and not info2
                end

                if moved then
                    table.insert(successNames, op.name)
                else
                    -- Reset captured fields so the retry recaptures fresh state.
                    op._itemID = nil
                    op._stackBefore = nil
                    table.insert(nextRound, op)
                end
            end

            if #nextRound > 0 and attemptNum < SYNC_MAX_RETRIES then
                ns:PrintDebug("BankQueue: retry " .. attemptNum .. " for " ..
                    #nextRound .. " failed move(s)")
                C_Timer.After(SYNC_RETRY_DELAY, function()
                    Attempt(nextRound, attemptNum + 1, function(extraErrors)
                        finishAttempts(nonRetryableErrors + extraErrors)
                    end)
                end)
            else
                finishAttempts(nonRetryableErrors + #nextRound)
            end
            end)  -- C_Timer.After(SYNC_VERIFY_DELAY, ...)
        end  -- AfterAllIssued

        -- Issue one move at a time with a small inter-move delay. Per-frame
        -- (~16ms) wasn't enough — Blizzard's container-op rate limit is
        -- coarser than that. SYNC_INTER_MOVE_DELAY (~100ms) gives the server
        -- enough room to process each move before the next is issued.
        --
        -- If a panel switch is needed (e.g. mixed bank/warbank ops in the
        -- same batch) we add a small extra settle delay so the switch
        -- propagates before the next move's UseContainerItem call.
        local i = 0
        local function IssueNext()
            i = i + 1
            if i > #remainingOps then
                AfterAllIssued()
                return
            end

            local op = remainingOps[i]
            local panelChanged = bankOpen and EnsurePanel(NeededBankType(op))
            local doIssue = function()
                IssueOne(op)
                if i < #remainingOps then
                    C_Timer.After(SYNC_INTER_MOVE_DELAY, IssueNext)
                else
                    AfterAllIssued()
                end
            end
            if panelChanged then
                C_Timer.After(SYNC_PANEL_SETTLE_DELAY, doIssue)
            else
                doIssue()
            end
        end
        IssueNext()
    end

    Attempt(ops, 1, function(totalErrors)
        BankQueue.processing = false
        if callback then callback(successNames, totalErrors) end
    end)
end

-- Legacy stubs — BankPopup replaces the old pull button
function BankQueue:ShowPullButton(ops, callback)
    if ns.UI and ns.UI.ShowBankPopup then
        ns.UI:ShowBankPopup({ pulls = ops }, function()
            BankQueue:ProcessSync(ops, "Pulling from bank...", callback)
        end)
    else
        BankQueue:Process(ops, "Pulling from bank...", callback)
    end
end

function BankQueue:HidePullButton()
    if ns.UI and ns.UI.HideBankPopup then
        ns.UI:HideBankPopup()
    end
end
