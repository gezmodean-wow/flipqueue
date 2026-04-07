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

-- Ensure BankFrame is in the correct bank type mode before container operations.
-- Baganator does the same thing — BankFrame.BankPanel:SetBankType() must match
-- the bag type being operated on, or the server silently rejects the move.
local function EnsureBankType(bagID)
    local bankType = GetBankTypeForBag(bagID)
    if not bankType then return end
    if BankFrame and BankFrame.BankPanel and BankFrame.BankPanel.SetBankType then
        local current = BankFrame.BankPanel.GetActiveBankType and BankFrame.BankPanel:GetActiveBankType()
        if current ~= bankType then
            BankFrame.BankPanel:SetBankType(bankType)
        end
    end
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

local function VerifyBatch(issuedOps)
    local retryOps = {}

    for _, op in ipairs(issuedOps) do
        local ok, info = pcall(C_Container.GetContainerItemInfo, op.srcBag, op.srcSlot)
        local moved = ok and not info

        if moved then
            table.insert(stats.successes, op.name)
        else
            op._retries = (op._retries or 0) + 1
            if op._retries <= MAX_RETRIES then
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

    local issuedOps = {}
    local abortPulls = false
    local abortDeposits = false

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
            else
                local freeBag, freeSlot = FindFreeSlot(ns.INVENTORY_BAGS)
                if not freeBag then
                    abortPulls = true
                    ns:Print(ns.COLORS.RED .. "Bags full!|r Skipping remaining pulls.")
                else
                    EnsureBankType(op.srcBag)
                    if CursorMove(op.srcBag, op.srcSlot, freeBag, freeSlot) then
                        table.insert(issuedOps, op)
                    else
                        op._retries = (op._retries or 0) + 1
                        if op._retries <= MAX_RETRIES then
                            table.insert(queue, op)
                        else
                            stats.errors = stats.errors + 1
                        end
                    end
                end
            end
        elseif op.op == "deposit" then
            if abortDeposits then
                -- skip
            else
                local destBags
                if op.destType == "warbank" then
                    destBags = ns:GetEnabledWarbankTabs()
                elseif op.destType == "bank" then
                    destBags = ns:GetEnabledBankTabs()
                else
                    destBags = {}
                    for _, b in ipairs(ns:GetEnabledWarbankTabs()) do table.insert(destBags, b) end
                    for _, b in ipairs(ns:GetEnabledBankTabs()) do table.insert(destBags, b) end
                end

                local destBag, destSlot = FindFreeSlot(destBags)
                if not destBag then
                    abortDeposits = true
                    ns:Print(ns.COLORS.RED .. "No free " .. (op.destType or "") .. " slots!|r Skipping remaining deposits.")
                else
                    EnsureBankType(destBag)
                    if CursorMove(op.srcBag, op.srcSlot, destBag, destSlot) then
                        table.insert(issuedOps, op)
                    else
                        op._retries = (op._retries or 0) + 1
                        if op._retries <= MAX_RETRIES then
                            table.insert(queue, op)
                        else
                            stats.errors = stats.errors + 1
                        end
                    end
                end
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
                VerifyBatch(issuedOps)
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
            VerifyBatch(issuedOps)
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

function BankQueue:ProcessSync(ops, label, callback)
    if #ops == 0 then
        if callback then callback({}, 0) end
        return
    end

    BankQueue.processing = true
    local successNames = {}
    local errorCount = 0
    local issuedOps = {}

    for _, op in ipairs(ops) do
        local ok, info = pcall(C_Container.GetContainerItemInfo, op.srcBag, op.srcSlot)
        if not ok or not info then
            -- Source empty, skip
        elseif info.isLocked then
            errorCount = errorCount + 1
        elseif op.op == "pull" then
            local freeBag, freeSlot = FindFreeSlot(ns.INVENTORY_BAGS)
            if freeBag then
                EnsureBankType(op.srcBag)
                if CursorMove(op.srcBag, op.srcSlot, freeBag, freeSlot) then
                    table.insert(issuedOps, op)
                else
                    errorCount = errorCount + 1
                end
            end
        elseif op.op == "deposit" then
            local destBags
            if op.destType == "warbank" then
                destBags = ns:GetEnabledWarbankTabs()
            elseif op.destType == "bank" then
                destBags = ns:GetEnabledBankTabs()
            else
                destBags = {}
                for _, b in ipairs(ns:GetEnabledWarbankTabs()) do table.insert(destBags, b) end
                for _, b in ipairs(ns:GetEnabledBankTabs()) do table.insert(destBags, b) end
            end
            local destBag, destSlot = FindFreeSlot(destBags)
            if destBag then
                EnsureBankType(destBag)
                if CursorMove(op.srcBag, op.srcSlot, destBag, destSlot) then
                    table.insert(issuedOps, op)
                else
                    errorCount = errorCount + 1
                end
            end
        end
    end

    pcall(ClearCursor)

    if #issuedOps == 0 then
        BankQueue.processing = false
        if callback then callback(successNames, errorCount) end
        return
    end

    -- Verify after a short delay for server round-trip
    C_Timer.After(1.0, function()
        for _, op in ipairs(issuedOps) do
            local ok2, info2 = pcall(C_Container.GetContainerItemInfo, op.srcBag, op.srcSlot)
            if ok2 and not info2 then
                table.insert(successNames, op.name)
            else
                errorCount = errorCount + 1
            end
        end
        BankQueue.processing = false
        if callback then callback(successNames, errorCount) end
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
