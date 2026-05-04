-- Tracker.lua
-- Core tracking: bag snapshots, post detection, and main event handling
-- Auction monitoring split to TrackerAuctions.lua
-- Bank pull/gold split to TrackerBank.lua
-- Mail scanning split to TrackerMail.lua
local addonName, ns = ...

local Tracker = {}
ns.Tracker = Tracker

local isAHOpen = false
Tracker._isAHOpen = false  -- exposed for TrackerAuctions (retry callback)

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

-- Expose for TrackerBank
Tracker._GetNameFromLink = GetNameFromLink

-- Get the bag quantity for a specific queue item across all carried bags
-- (regular bags + reagent bag — items in the reagent bag still count as
-- "in inventory" for our purposes).
-- Returns (total, bestKey) — bestKey is the most-decorated full bag-item
-- key seen for any matching slot ("itemID;bonusIDs;modifiers"). The snapshot
-- uses this so that when the user posts via TSM/Blizz UI (no scanResult to
-- pass through), the log entry can still preserve variant data instead of
-- falling back to the task's potentially-stripped imported key (FQ-130).
local function CountInBags(queueItem)
    local total = 0
    local bestKey = nil
    for _, bagIndex in ipairs(ns.ALL_PLAYER_BAGS) do
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
                        if not bestKey or (bonusIDs and bonusIDs ~= "") then
                            bestKey = key
                        end
                    end
                end
            end
        end
    end
    return total, bestKey
end

-- Expose for TrackerBank
Tracker._CountInBags = CountInBags

--------------------------
-- Bag Snapshot for Post Detection
--------------------------

local function SnapshotBags()
    wipe(preTodoSnapshot)
    if not ns.db then return end

    if ns.TodoList then
        local charKey = ns:GetCharKey()
        local currentRealm = GetRealmName()
        local todoList = ns.TodoList:GetCurrentList()
        if todoList and todoList.tasks then
            for taskIdx, todoItem in ipairs(todoList.tasks) do
                if (todoItem.status == "pending" or todoItem.status == "skipped")
                    and todoItem.assignedChar == charKey
                    and ns:RealmMatches(todoItem.targetRealm or "", currentRealm) then
                    local qty, bagKey = CountInBags(todoItem)
                    preTodoSnapshot[taskIdx] = {
                        todoItem = todoItem,
                        qty = qty,
                        itemKey = bagKey,
                    }
                end
            end
        end
    end
end

local function CheckForPosts()
    if not ns.db then return end

    local todoPosted = {}
    for taskIdx, snap in pairs(preTodoSnapshot) do
        if snap.todoItem.status == "pending" or snap.todoItem.status == "skipped" then
            local curQty = CountInBags(snap.todoItem)
            if curQty < snap.qty then
                -- Cap count at task's own quantity to prevent inflation
                -- when multiple tasks share the same item type
                local count = math.min(snap.qty - curQty, snap.todoItem.quantity or 1)
                table.insert(todoPosted, {taskIdx = taskIdx, item = snap.todoItem, count = count, itemKey = snap.itemKey})
            end
        end
    end

    table.sort(todoPosted, function(a, b) return a.taskIdx > b.taskIdx end)
    for _, p in ipairs(todoPosted) do
        -- If task was TSM-skipped but user posted anyway, clean up the skip
        if p.item.status == "skipped" then
            for i = #ns.db.log, 1, -1 do
                local entry = ns.db.log[i]
                if entry.auctionStatus == "skipped"
                    and entry.itemKey == p.item.itemKey
                    and entry.charKey == (p.item.assignedChar or ns:GetCharKey()) then
                    table.remove(ns.db.log, i)
                    break
                end
            end
            p.item.status = "pending"
            ns:Print(ns.COLORS.CYAN .. "Override:|r " .. (p.item.name or "?") .. " posted despite TSM skip")
        end
        local taskQty = p.item.quantity or 1
        if p.count < taskQty then
            ns:Print(ns.COLORS.GREEN .. "Posted:|r " .. p.item.name .. " (x" .. p.count .. " of " .. taskQty .. ")")
        else
            ns:Print(ns.COLORS.GREEN .. "Posted:|r " .. p.item.name .. " (x" .. p.count .. ")")
        end
        -- Pass the snapshotted bag-item key so log entries preserve bonus
        -- IDs / modifiers even for posts done via TSM / Blizz UI (FQ-130).
        ns.TodoList:MoveTaskToLog(p.taskIdx, nil, nil, p.count, p.itemKey)
    end

    if #todoPosted > 0 then
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    end

    SnapshotBags()
end

--------------------------
-- Authority Scope (#148, refined #155)
--------------------------
-- The scope-vs-trigger split. `InScope` answers "does FlipQueue have
-- authority to manage X for this character at all?" — the per-action
-- mode strings (todoMode / extrasMode / reagentsMode / goldWithdrawMode
-- / goldDepositMode) answer "for this specific action, what should
-- happen?" via `GetActionMode` below. Master-off forces every sub-action
-- to "disabled"; master-on lets each action sit independently in
-- "auto" / "manual" / "disabled".
--
-- (#155: dropped the `_automationPaused` check from InScope. Pause is no
-- longer a master-scope override — it forces every action's effective
-- mode to "manual", which keeps drawer buttons visible and manual
-- Execute working while just blocking auto-fire on bank open.)
function Tracker:InScope(charKey, kind)
    if not ns.db then return false end
    local master = (kind == "gold") and "manageGold" or "manageItems"
    -- Per-character override takes precedence; falls back to global.
    return ns:GetCharSetting(charKey, master) == true
end

-- (#155) Returns the effective tri-state for an action class:
-- "auto" / "manual" / "disabled".
--
-- Resolution chain:
--   1. Master off → "disabled" (one-click silence overrides everything)
--   2. Per-char mode override → global mode default
--   3. Pause Automation runtime override → "auto" → "manual"; "disabled"
--      and "manual" pass through unchanged
--
-- Action classes:
--   "todo"          — pull + deposit-to-do (paired)
--   "extras"        — non-task, non-reagent items
--   "reagents"      — Tradegoods (Item Class 7)
--   "goldWithdraw"  — withdraw from warbank
--   "goldDeposit"   — deposit to warbank
--
-- Callers should NEVER read raw mode keys directly — go through this
-- helper so the master + pause overrides apply uniformly.
local ACTION_MASTER = {
    todo         = "manageItems",
    extras       = "manageItems",
    reagents     = "manageItems",
    goldWithdraw = "manageGold",
    goldDeposit  = "manageGold",
}
local ACTION_MODE_KEY = {
    todo         = "todoMode",
    extras       = "extrasMode",
    reagents     = "reagentsMode",
    goldWithdraw = "goldWithdrawMode",
    goldDeposit  = "goldDepositMode",
}

function Tracker:GetActionMode(charKey, actionClass)
    if not ns.db then return "disabled" end
    local masterKey = ACTION_MASTER[actionClass]
    local modeKey   = ACTION_MODE_KEY[actionClass]
    if not masterKey or not modeKey then return "disabled" end

    -- Master off → forced disabled regardless of stored mode.
    if ns:GetCharSetting(charKey, masterKey) ~= true then
        return "disabled"
    end

    local mode = ns:GetCharSetting(charKey, modeKey) or "manual"
    if mode ~= "auto" and mode ~= "manual" and mode ~= "disabled" then
        -- Defensive: a corrupted SV could leave a non-tri-state value;
        -- treat unknowns as "manual" rather than failing closed.
        mode = "manual"
    end

    -- Pause Automation: "auto" → "manual" runtime-only. Stored value
    -- unchanged. Drawer buttons + manual Execute remain functional.
    if ns._automationPaused and mode == "auto" then
        return "manual"
    end
    return mode
end

-- Single source of truth for "which bags should we walk?" — both
-- planners (BuildExtraDepositOps / BuildReagentDepositOps) and executors
-- (AutoDepositExtraItems / AutoDepositReagents) call into this so they
-- can never disagree about the bag set or the filter.
--
-- opKind:
--   "extras"   — skip reagents (Tradegoods + bag 5). Non-reagent items
--                in player bags eligible for deposit-extras flow.
--   "reagents" — ONLY reagents. Tradegoods classID + the dedicated
--                reagent bag (bag 5).
--
-- (#155: previously a single opKind="extras" with `depositIncludeReagents`
-- toggling reagent inclusion. Reagents are now their own action class
-- with their own tri-state mode, so the inclusion test moves from a
-- bool to a separate walk.)
--
-- Callback signature:
--   cb(bagIndex, slot, info, itemID, bonusIDs, modifiers, isSoulbound)
function Tracker:WalkBagsInScope(opKind, cb)
    if not ns.db then return end

    local function IsReagent(bagIndex, hyperlink)
        if bagIndex == ns.REAGENT_BAG then return true end
        local _, _, _, _, _, _, _, _, _, _, _, classID =
            GetItemInfo(hyperlink)
        return classID == Enum.ItemClass.Tradegoods
    end

    for _, bagIndex in ipairs(ns.ALL_PLAYER_BAGS) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    -- Per-opKind reagent filter
                    local isReagent = IsReagent(bagIndex, info.hyperlink)
                    local include
                    if opKind == "reagents" then
                        include = isReagent
                    else
                        -- "extras" (default) — non-reagents only
                        include = not isReagent
                    end

                    if include then
                        -- BoP/Quest detection: warbound (7) and BoA (8)
                        -- can move to warbank; everything else with
                        -- isBound stays bank-only.
                        local isSoulbound = false
                        if info.isBound then
                            local okBind, _, _, _, _, _, _, _, _, _, _, _, _, _, bt =
                                pcall(C_Item.GetItemInfo, info.hyperlink)
                            if not okBind or not bt then
                                isSoulbound = true
                            elseif bt ~= 7 and bt ~= 8 then
                                isSoulbound = true
                            end
                        end

                        local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                        if itemID then
                            cb(bagIndex, slot, info, itemID, bonusIDs, modifiers, isSoulbound)
                        end
                    end
                end
            end
        end
    end
end

--------------------------
-- Bank Operations Popup
--------------------------

-- Collect all pending bank operations and show the popup.
-- The user clicks Execute, which runs everything in hardware event context.
function Tracker:ShowBankOpsPopup()
    if not ns.UI or not ns.UI.ShowBankPopup then
        -- Fallback: run old auto chain
        Tracker:AutoPullFromBank(function()
            Tracker:AutoWithdrawGold()
            Tracker:AutoDepositGold()
            Tracker:AutoDepositToWarbank(function()
                Tracker:AutoDepositExtraItems()
            end)
        end)
        return
    end

    local charKey = ns:GetCharKey()

    -- Collect pull operations (reuse AutoPullFromBank's logic but don't execute)
    local pullOps = Tracker:BuildPullOps()
    local depositOps = Tracker:BuildDepositOps()
    -- Build exclude set from deposit ops so extras / reagents don't duplicate
    local depositSlots = {}
    for _, op in ipairs(depositOps) do
        depositSlots[op.srcBag .. ":" .. op.srcSlot] = true
    end
    -- (#155) Plan extras and reagents whenever their action mode allows it
    -- (i.e. is not "disabled"). The build functions self-gate on
    -- GetActionMode so an explicit "disabled" returns []. Whether the
    -- planned ops auto-fire on bank open or wait for an Execute click is
    -- decided downstream via per-section auto-fire flags.
    local extraOps = Tracker:BuildExtraDepositOps(depositSlots)
    -- Reagents share the deposit-slot exclusion with extras and to-do
    -- deposits so a single bag slot can't be claimed by two actions.
    local reagentExcludeSlots = {}
    for k, v in pairs(depositSlots) do reagentExcludeSlots[k] = v end
    for _, op in ipairs(extraOps) do
        reagentExcludeSlots[op.srcBag .. ":" .. op.srcSlot] = true
    end
    local reagentOps = Tracker:BuildReagentDepositOps(reagentExcludeSlots)

    -- Calculate gold operations
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
    local goldWithdraw, goldDeposit = 0, 0
    local hasBuyCosts = false

    -- Estimate withdrawal / deposit need. (#155) Plan whenever the action
    -- mode isn't "disabled"; the popup's per-section auto-fire flag
    -- decides whether the op runs on bank open or needs an Execute click.
    -- Warband Miser still hard-blocks gold planning regardless of mode —
    -- WM owns gold management when active and we don't fight it.
    do
        local wmActive = ns.IsWarbandMiserActive and ns:IsWarbandMiserActive()
        local withdrawMode = Tracker:GetActionMode(charKey, "goldWithdraw")
        local depositMode  = Tracker:GetActionMode(charKey, "goldDeposit")
        local planWithdraw = withdrawMode ~= "disabled" and not wmActive
        local planDeposit  = depositMode  ~= "disabled" and not wmActive

        if ns.db and (planWithdraw or planDeposit) then
            local totalFees, _, details = Tracker:CalculateRequiredGold(charKey, currentRealm)
            for _, d in ipairs(details) do
                if d.duration == "buy" then hasBuyCosts = true; break end
            end
            local playerCopper = GetMoney()
            local bufferCopper = (ns.db.settings.goldBuffer or 0) * 10000
            local needed = math.max(bufferCopper, math.ceil(totalFees * 1.1))
            -- Round target up to whole gold so the resulting balance is even
            needed = math.ceil(needed / 10000) * 10000
            if planWithdraw and playerCopper < needed then
                goldWithdraw = needed - playerCopper
            end

            -- Estimate deposit excess
            if planDeposit then
                local keepCopper = needed
                if playerCopper > keepCopper then
                    local excess = playerCopper - keepCopper
                    if excess > 0 then goldDeposit = excess end
                end
            end
        end
    end

    local hasPulls = pullOps and #pullOps > 0
    local hasDeposits = depositOps and #depositOps > 0
    local hasExtras = extraOps and #extraOps > 0
    local hasReagents = reagentOps and #reagentOps > 0
    local hasGold = goldWithdraw > 0 or goldDeposit > 0

    -- FQ-132: if the previous bank session ended with pull failures, suppress
    -- auto-deposit on this open so items the player is reopening to retry
    -- aren't shoveled back to the warbank before they can be pulled again.
    -- One-shot: clear the flag here regardless of whether suppression fires.
    -- (#155) Suppress reagent deposits too — same reasoning as extras.
    if ns.db and ns.db._lastBankFailures and ns.db._lastBankFailures[charKey] then
        local prev = ns.db._lastBankFailures[charKey]
        ns.db._lastBankFailures[charKey] = nil
        if hasDeposits or hasExtras or hasReagents then
            local n = (prev.failedNames and #prev.failedNames) or prev.errorCount or 1
            ns:Print(ns.COLORS.YELLOW .. n ..
                " pull(s) failed last session — auto-deposit suppressed for this open so retries can finish first.|r")
            depositOps = {}
            extraOps = {}
            reagentOps = {}
            hasDeposits = false
            hasExtras = false
            hasReagents = false
        end
    end

    ns:PrintDebug("Bank popup: " .. #pullOps .. " pulls, " .. #depositOps .. " deposits, " ..
        #extraOps .. " extras, " .. #reagentOps .. " reagents, withdraw=" .. goldWithdraw .. " deposit=" .. goldDeposit)

    if not hasPulls and not hasDeposits and not hasExtras and not hasReagents and not hasGold then
        ns:PrintDebug("Bank popup: nothing to do")
        return
    end

    local function ExecuteAllOps()
        -- Phase 1: Pull all items from bank (batched)
        local function DoPulls(callback)
            if not hasPulls or #pullOps == 0 then callback() return end
            if ns.UI then ns.UI:BankOpProgress(0, 0, "Pulling") end
            -- Per-IssueOne optimistic ticks: each successful issuance inside
            -- ProcessSync fires onProgress here so the popup bar advances
            -- move-by-move during long pulls (#127). The final callback
            -- contributes the failure count and the failed-names list.
            -- onWait drives the heartbeat countdown so the player sees
            -- what the addon is waiting for during inter-move pauses.
            if ns.BankQueue then
                ns.BankQueue.onProgress = function(deltaSuccess, _total, deltaNames)
                    if ns.UI then
                        ns.UI:BankOpProgress(deltaSuccess or 0, 0, "Pulling", deltaNames)
                    end
                end
                ns.BankQueue.onWait = function(seconds, reason, kind)
                    if ns.UI and ns.UI.BeginHeartbeat then
                        ns.UI:BeginHeartbeat(seconds, reason, kind)
                    end
                end
                ns.BankQueue.onWaitEnd = function()
                    if ns.UI and ns.UI.EndHeartbeat then
                        ns.UI:EndHeartbeat()
                    end
                end
            end
            ns.BankQueue:ProcessSync(pullOps, "Pulling from bank...", function(successNames, errorCount, failedNames)
                if #successNames > 0 then
                    ns:Print("Pulled: " .. table.concat(successNames, ", "))
                end
                if errorCount > 0 then
                    local detail = (failedNames and #failedNames > 0)
                        and (": " .. table.concat(failedNames, ", ")) or ""
                    ns:Print(ns.COLORS.YELLOW .. errorCount .. " pull(s) failed|r" .. detail)
                    -- FQ-132: persist a per-character flag so the next bank
                    -- reopen suppresses auto-deposit, letting the user retry
                    -- the failed pulls without items going back to warbank.
                    if ns.db then
                        ns.db._lastBankFailures = ns.db._lastBankFailures or {}
                        ns.db._lastBankFailures[charKey] = {
                            errorCount = errorCount,
                            failedNames = failedNames,
                            timestamp = time(),
                        }
                    end
                end
                if ns.UI then ns.UI:BankOpProgress(0, errorCount, "Pulling", nil, failedNames) end
                C_Timer.After(0.3, callback)
            end)
        end

        -- Phase 2: Gold operations
        local function DoGold(callback)
            if not hasGold then callback() return end
            if ns.UI then ns.UI:BankOpProgress(0, 0, "Gold") end
            local goldDetails = {}
            local withdrawnCopper = Tracker:AutoWithdrawGold() or 0
            if withdrawnCopper > 0 then
                local goldStr = ns.FormatGold and ns:FormatGold(withdrawnCopper) or (math.floor(withdrawnCopper / 10000) .. "g")
                table.insert(goldDetails, "Withdrew " .. goldStr)
                if ns.UI then ns.UI:BankOpProgress(1, 0, "Gold", goldDetails) end
            elseif goldWithdraw > 0 then
                if ns.UI then ns.UI:BankOpProgress(0, 1, "Gold") end
            end
            local depositedCopper = Tracker:AutoDepositGold() or 0
            if depositedCopper > 0 then
                local goldStr = ns.FormatGold and ns:FormatGold(depositedCopper) or (math.floor(depositedCopper / 10000) .. "g")
                table.insert(goldDetails, "Deposited " .. goldStr)
                if ns.UI then ns.UI:BankOpProgress(1, 0, "Gold", goldDetails) end
            elseif goldDeposit > 0 then
                if ns.UI then ns.UI:BankOpProgress(0, 1, "Gold") end
            end
            callback()
        end

        -- Phase 3: Deposits to warbank, then extras, then reagents. The
        -- sub-phases must run sequentially (not in parallel or fire-and-
        -- forget) so the progress reports reflect ACTUAL move counts from
        -- each BankQueue:Process callback rather than the optimistic
        -- popup-prebuilt counts. (#155: reagent sub-phase added.)
        local function DoDeposits(callback)
            if not hasDeposits and not hasExtras and not hasReagents then callback() return end
            if ns.UI then ns.UI:BankOpProgress(0, 0, "Depositing") end

            -- Wire heartbeat hooks for deposit-only flows (no pulls).
            -- DoPulls would have set these, but it early-returns when
            -- there's nothing to pull; without re-wiring here a pure
            -- deposit run never shows the wait countdown (#127).
            if ns.BankQueue then
                ns.BankQueue.onWait = function(seconds, reason, kind)
                    if ns.UI and ns.UI.BeginHeartbeat then
                        ns.UI:BeginHeartbeat(seconds, reason, kind)
                    end
                end
                ns.BankQueue.onWaitEnd = function()
                    if ns.UI and ns.UI.EndHeartbeat then
                        ns.UI:EndHeartbeat()
                    end
                end
            end

            -- Wire BankQueue.onProgress to a deposit-phase delta tracker.
            -- BankQueue:Process emits CUMULATIVE successes — both optimistic
            -- per-op (during a batch) and authoritative per-batch (after
            -- VerifyBatch). The wrapper converts cumulative→delta. Negative
            -- deltas are forwarded so a verify failure can decrement the
            -- bar after the optimistic count went too high. The closure
            -- resets per sub-phase since each Process call starts at 0.
            local function MakeDepositDeltaTracker()
                local lastCumulative = 0
                return function(cumulativeSuccess, _total, names)
                    local delta = (cumulativeSuccess or 0) - lastCumulative
                    lastCumulative = cumulativeSuccess or 0
                    if delta ~= 0 and ns.UI then
                        ns.UI:BankOpProgress(delta, 0, "Depositing", names)
                    end
                end
            end

            -- Sub-phase C: reagents (final sub-phase before callback).
            local function DoReagents()
                if not hasReagents then callback() return end
                if ns.BankQueue then
                    ns.BankQueue.onProgress = MakeDepositDeltaTracker()
                end
                Tracker:AutoDepositReagents(function(_reagentSuccessNames, reagentErrorCount)
                    if ns.UI and reagentErrorCount and reagentErrorCount > 0 then
                        ns.UI:BankOpProgress(0, reagentErrorCount, "Depositing")
                    end
                    callback()
                end)
            end

            -- Sub-phase B: extras (chains into reagents).
            local function DoExtras()
                if not hasExtras then DoReagents() return end
                if ns.BankQueue then
                    ns.BankQueue.onProgress = MakeDepositDeltaTracker()
                end
                Tracker:AutoDepositExtraItems(function(_extraSuccessNames, extraErrorCount)
                    if ns.UI and extraErrorCount and extraErrorCount > 0 then
                        ns.UI:BankOpProgress(0, extraErrorCount, "Depositing")
                    end
                    DoReagents()
                end)
            end

            if not hasDeposits then
                DoExtras()
                return
            end

            if ns.BankQueue then
                ns.BankQueue.onProgress = MakeDepositDeltaTracker()
            end
            Tracker:AutoDepositToWarbank(function(_warbankSuccessNames, warbankErrorCount)
                if ns.UI and warbankErrorCount and warbankErrorCount > 0 then
                    ns.UI:BankOpProgress(0, warbankErrorCount, "Depositing")
                end
                DoExtras()
            end)
        end

        -- Chain: pulls → gold → deposits → finish
        DoPulls(function()
            DoGold(function()
                DoDeposits(function()
                    -- Refresh everything
                    if ns.Scanner then
                        ns.Scanner:ScanCurrentCharacter()
                        ns.Scanner:ScanBank()
                    end
                    if ns.TodoList then
                        if ns.TodoList.RefreshLocations then ns.TodoList:RefreshLocations() end
                        if ns.TodoList.RefreshTaskSteps then ns.TodoList:RefreshTaskSteps() end
                    end
                    if ns.UI then
                        if ns.UI.Refresh then ns.UI:Refresh() end
                        if ns.UI.RefreshMini then ns.UI:RefreshMini() end
                        ns.UI:BankPopupComplete()
                    end
                end)
            end)
        end)
    end

    -- Initialize unified progress tracking (total = pulls + deposits + extras + reagents + gold ops)
    local totalOps = #pullOps + #depositOps + #extraOps + #reagentOps
    if goldWithdraw > 0 then totalOps = totalOps + 1 end
    if goldDeposit > 0 then totalOps = totalOps + 1 end
    if not ns.UI:IsBankExecuting() then
        ns.UI:BeginBankExecution(totalOps)
    end

    -- (#155) Per-section auto-fire flags from the action mode model.
    -- A section auto-fires only if every action in it is in "auto" mode
    -- (and has ops to run). Pause Automation collapses "auto" → "manual"
    -- runtime-only via GetActionMode, so a paused player sees the popup
    -- with manual Execute buttons instead of surprise auto-fires.
    local todoMode      = Tracker:GetActionMode(charKey, "todo")
    local extrasMode    = Tracker:GetActionMode(charKey, "extras")
    local reagentsMode  = Tracker:GetActionMode(charKey, "reagents")
    local goldWMode     = Tracker:GetActionMode(charKey, "goldWithdraw")
    local goldDMode     = Tracker:GetActionMode(charKey, "goldDeposit")

    -- Items section auto-fires when every active sub-action is in auto.
    -- An empty sub-action (e.g. no extras pending) does not block auto.
    local itemsAuto =
            (not (hasPulls or hasDeposits) or todoMode == "auto")
        and (not hasExtras                  or extrasMode == "auto")
        and (not hasReagents                or reagentsMode == "auto")
    local goldAuto =
            (goldWithdraw == 0 or goldWMode == "auto")
        and (goldDeposit  == 0 or goldDMode == "auto")
    -- Combined isAuto: every active section is in auto-fire. Otherwise the
    -- popup waits for explicit Execute click. Preserves the all-auto and
    -- all-manual common cases without surprise auto-fires in mixed setups.
    local isAuto = itemsAuto and goldAuto

    ns.UI:ShowBankPopup({
        pulls = pullOps,
        deposits = depositOps,
        reagents = reagentOps,
        extras = extraOps,
        goldWithdraw = goldWithdraw,
        goldDeposit = goldDeposit,
        hasBuyCosts = hasBuyCosts,
        isAuto = isAuto,
        -- Per-section flags — popup may use these for separate Execute
        -- buttons in alpha12. Architectural prep for FQ-129 Phase 3.
        itemsAuto = itemsAuto,
        goldAuto = goldAuto,
    }, ExecuteAllOps)
end

-- Build pull operation list without executing.
-- Returns array of { op="pull", srcBag, srcSlot, name, icon, quantity } or empty table.
function Tracker:BuildPullOps()
    if not ns.db then return {} end

    local charKey = ns:GetCharKey()
    -- (#155) Gate on the to-do action mode. "disabled" → no pull ops
    -- planned. "manual" / "auto" → planner runs as normal; the popup
    -- decides whether ops auto-fire on bank open or wait for an Execute
    -- click. Master-off resolves to "disabled" through GetActionMode.
    if Tracker:GetActionMode(charKey, "todo") == "disabled" then return {} end
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
    local needed = {}

    local taskCount = 0
    if ns.TodoList and ns.TodoList:GetCurrentList() then
        local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(todoTasks) do
            local item = task.item
            taskCount = taskCount + 1
            if item.action ~= "buy" and ns:RealmMatches(item.targetRealm or "", currentRealm) then
                local targetQty = item.quantity or 1
                local inBags = Tracker._CountInBags(item)
                local stillNeeded = targetQty - inBags
                ns:PrintDebug("BuildPull: " .. (item.name or "?") .. " need=" .. targetQty ..
                    " inBags=" .. inBags .. " src=" .. tostring(item.source))
                if stillNeeded > 0 then
                    needed[item] = stillNeeded
                end
            end
        end
    end

    -- Also pull deposit-from items
    if ns.TodoList and ns.TodoList:GetCurrentList() then
        local todoList = ns.TodoList:GetCurrentList()
        if todoList.tasks then
            for _, item in ipairs(todoList.tasks) do
                if item.status == "pending" and item.depositFrom == charKey
                    and item.assignedChar ~= charKey
                    and item.source ~= "warbank" then
                    local inBags = Tracker._CountInBags(item)
                    if inBags <= 0 and not needed[item] then
                        needed[item] = item.quantity or 1
                    end
                end
            end
        end
    end

    ns:PrintDebug("BuildPull: " .. taskCount .. " tasks, " .. (next(needed) and "has needed" or "nothing needed"))
    if not next(needed) then return {} end

    local allBankTabs = {}
    for _, b in ipairs(ns:GetEnabledBankTabs()) do table.insert(allBankTabs, b) end
    for _, b in ipairs(ns:GetEnabledWarbankTabs()) do table.insert(allBankTabs, b) end

    local ops = {}
    for _, bagIndex in ipairs(allBankTabs) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                        local slotName
                        for queueItem, count in pairs(needed) do
                            if count > 0 then
                                local matched = ns:ItemsMatch(key, nil, queueItem, false, false)
                                if not matched then
                                    if slotName == nil then slotName = Tracker._GetNameFromLink(info.hyperlink) or false end
                                    if slotName then
                                        matched = ns:ItemsMatch(key, slotName, queueItem, false, false)
                                    end
                                end
                                if matched then
                                    table.insert(ops, {
                                        op = "pull",
                                        srcBag = bagIndex,
                                        srcSlot = slot,
                                        name = queueItem.name or "?",
                                        icon = info.iconFileID,
                                        quantity = info.stackCount or 1,
                                    })
                                    needed[queueItem] = count - (info.stackCount or 1)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return ops
end

-- Build warbank deposit operation list without executing.
function Tracker:BuildDepositOps()
    if not ns.db then return {} end

    local charKey = ns:GetCharKey()
    -- (#155) Gate on the to-do action mode (pull and deposit-to-do are
    -- paired under one mode). "disabled" → no deposit ops planned.
    if Tracker:GetActionMode(charKey, "todo") == "disabled" then return {} end
    local todoList = ns.TodoList and ns.TodoList:GetCurrentList()
    if not todoList or not todoList.tasks then return {} end

    local depositTasks = {}
    for _, task in ipairs(todoList.tasks) do
        if task.status == "pending" and task.depositFrom == charKey
            and task.assignedChar ~= charKey then
            table.insert(depositTasks, task)
        end
    end

    if #depositTasks == 0 then return {} end

    local myPostingKeys = {}
    local myTasks = ns.TodoList:GetCharacterTasks(charKey)
    for _, task in ipairs(myTasks) do
        if task.item.itemKey then myPostingKeys[task.item.itemKey] = true end
    end

    local ops = {}
    local depositMatched = {}

    for _, bagIndex in ipairs(ns.ALL_PLAYER_BAGS) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    local skipBound = false
                    if info.isBound then
                        local okBind, _, _, _, _, _, _, _, _, _, _, _, _, _, bt =
                            pcall(C_Item.GetItemInfo, info.hyperlink)
                        if not okBind or not bt then
                            skipBound = true
                        elseif bt ~= 7 and bt ~= 8 then
                            skipBound = true
                        end
                    end
                    if not skipBound then
                        local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                        if itemID then
                            local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                            if not myPostingKeys[key] then
                                local slotName
                                for _, task in ipairs(depositTasks) do
                                    if not depositMatched[task] then
                                        local matched = ns:ItemsMatch(key, nil, task, false, false)
                                        if not matched then
                                            if slotName == nil then slotName = Tracker._GetNameFromLink(info.hyperlink) or false end
                                            if slotName then
                                                matched = ns:ItemsMatch(key, slotName, task, false, false)
                                            end
                                        end
                                        if matched then
                                            depositMatched[task] = true
                                            table.insert(ops, {
                                                op = "deposit",
                                                srcBag = bagIndex,
                                                srcSlot = slot,
                                                name = task.name or "?",
                                                icon = info.iconFileID,
                                                quantity = info.stackCount or 1,
                                                destType = "warbank",
                                            })
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return ops
end

-- Build extra deposit operation list (items not needed by current char).
-- excludeSlots: optional table of "bag:slot" keys already claimed by BuildDepositOps
--
-- #148: routes through `Tracker:WalkBagsInScope` so the executor
-- (`AutoDepositExtraItems`) can use the same helper and never disagree about
-- which bags / which filter rules count. The previous mismatch — planner
-- walking ALL_PLAYER_BAGS, executor walking INVENTORY_BAGS — was the
-- FQ-110 toeknee root cause.
function Tracker:BuildExtraDepositOps(excludeSlots)
    if not ns.db then return {} end

    local charKey = ns:GetCharKey()
    -- (#155) Gate on the extras action mode. "disabled" → no extras
    -- planned. The planner builds whether mode is "auto" or "manual";
    -- the popup payload's auto-fire flag decides whether they run on
    -- bank open or wait for an Execute click.
    if Tracker:GetActionMode(charKey, "extras") == "disabled" then return {} end

    local keepKeys = {}
    local keepNames = {}
    if ns.TodoList then
        local myTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(myTasks) do
            local item = task.item
            if item.itemKey then
                keepKeys[item.itemKey] = (keepKeys[item.itemKey] or 0) + (item.quantity or 1)
            end
            if item.name and item.name ~= "" then
                local ln = item.name:lower()
                keepNames[ln] = (keepNames[ln] or 0) + (item.quantity or 1)
            end
        end
    end

    local KEEP_ITEM_IDS = { [6948] = true }
    local ops = {}
    local consumedKeys = {}
    local consumedNames = {}
    excludeSlots = excludeSlots or {}

    Tracker:WalkBagsInScope("extras", function(bagIndex, slot, info, itemID, bonusIDs, modifiers, isSoulbound)
        local slotKey = bagIndex .. ":" .. slot
        if excludeSlots[slotKey] then return end
        -- Skip soulbound items entirely (matches the previous BuildDepositOps
        -- behavior — warbank can't accept BoP items even if everything else
        -- about the candidate is fine).
        if isSoulbound then return end

        local numID = tonumber(itemID) or tonumber((itemID:gsub(";.*", "")))
        if KEEP_ITEM_IDS[numID] then return end

        local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
        local stackCount = info.stackCount or 1
        local shouldKeep = false

        local neededByKey = keepKeys[key] or 0
        local usedByKey = consumedKeys[key] or 0
        if neededByKey > usedByKey then
            consumedKeys[key] = usedByKey + stackCount
            shouldKeep = true
        else
            local itemName = Tracker._GetNameFromLink(info.hyperlink)
            if itemName then
                local ln = itemName:lower()
                local neededByName = keepNames[ln] or 0
                local usedByName = consumedNames[ln] or 0
                if neededByName > usedByName then
                    consumedNames[ln] = usedByName + stackCount
                    shouldKeep = true
                end
            end
        end

        if not shouldKeep then
            local itemName = Tracker._GetNameFromLink(info.hyperlink)
            table.insert(ops, {
                op = "deposit",
                srcBag = bagIndex,
                srcSlot = slot,
                name = itemName or ("Item " .. key),
                icon = info.iconFileID,
                quantity = stackCount,
                destType = "warbank",
            })
        end
    end)

    return ops
end

-- (#155) Build reagent-class deposit operation list. Mirror of
-- `BuildExtraDepositOps` for the reagents action class — walks only the
-- Tradegoods + reagent-bag slots and proposes deposits to warbank.
-- Same task-protection rule: anything keyed to a current to-do task
-- (by itemKey or by name) stays on the character.
function Tracker:BuildReagentDepositOps(excludeSlots)
    if not ns.db then return {} end

    local charKey = ns:GetCharKey()
    if Tracker:GetActionMode(charKey, "reagents") == "disabled" then return {} end

    local keepKeys = {}
    local keepNames = {}
    if ns.TodoList then
        local myTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(myTasks) do
            local item = task.item
            if item.itemKey then
                keepKeys[item.itemKey] = (keepKeys[item.itemKey] or 0) + (item.quantity or 1)
            end
            if item.name and item.name ~= "" then
                local ln = item.name:lower()
                keepNames[ln] = (keepNames[ln] or 0) + (item.quantity or 1)
            end
        end
    end

    local ops = {}
    local consumedKeys = {}
    local consumedNames = {}
    excludeSlots = excludeSlots or {}

    Tracker:WalkBagsInScope("reagents", function(bagIndex, slot, info, itemID, bonusIDs, modifiers, isSoulbound)
        local slotKey = bagIndex .. ":" .. slot
        if excludeSlots[slotKey] then return end
        if isSoulbound then return end

        local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
        local stackCount = info.stackCount or 1
        local shouldKeep = false

        local neededByKey = keepKeys[key] or 0
        local usedByKey = consumedKeys[key] or 0
        if neededByKey > usedByKey then
            consumedKeys[key] = usedByKey + stackCount
            shouldKeep = true
        else
            local itemName = Tracker._GetNameFromLink(info.hyperlink)
            if itemName then
                local ln = itemName:lower()
                local neededByName = keepNames[ln] or 0
                local usedByName = consumedNames[ln] or 0
                if neededByName > usedByName then
                    consumedNames[ln] = usedByName + stackCount
                    shouldKeep = true
                end
            end
        end

        if not shouldKeep then
            local itemName = Tracker._GetNameFromLink(info.hyperlink)
            table.insert(ops, {
                op = "deposit",
                srcBag = bagIndex,
                srcSlot = slot,
                name = itemName or ("Item " .. key),
                icon = info.iconFileID,
                quantity = stackCount,
                destType = "warbank",
            })
        end
    end)

    return ops
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
frame:RegisterEvent("AUCTION_CANCELED")

frame:SetScript("OnEvent", function(self, event)
    if event == "AUCTION_HOUSE_SHOW" then
        isAHOpen = true
        Tracker._isAHOpen = true
        Tracker._pendingCancels = 0

        -- Critical fast-path only: snapshot bags so post-detection works,
        -- and ask the server for owned auctions. Everything else is deferred
        -- so the AH can open without blocking on TSM/task work (FQ-137).
        SnapshotBags()
        if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then
            C_AuctionHouse.QueryOwnedAuctions({})
        end

        -- Defer the heavy chain. Each step is independently guarded by
        -- _isAHOpen so closing the AH while these are pending becomes a no-op.
        C_Timer.After(0.1, function()
            if not Tracker._isAHOpen then return end
            if ns.TodoList and ns.TodoList.RefreshTaskSteps then
                ns.TodoList:RefreshTaskSteps()
            end
            if ns.TodoList and ns.TodoList.HandleTSMRejections then
                ns.TodoList:HandleTSMRejections()
            end
            if ns.TodoList then
                local charKey = ns:GetCharKey()
                local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
                if #todoTasks > 0 then
                    ns:Print(ns.COLORS.GREEN .. #todoTasks .. " items|r ready to post!")
                end
            end
        end)

        C_Timer.After(0.3, function()
            if not Tracker._isAHOpen then return end
            if ns.UI then
                if ns.UI.RefreshMini then ns.UI:RefreshMini() end
                if ns.UI.Refresh then ns.UI:Refresh() end
            end
        end)

        -- Throttle TSM reconcile to once per hour — TSM's sales CSV is only
        -- rewritten on logout, so running it on every AH open would just
        -- re-check the same data. _tsmReconciled per-entry also prevents
        -- redundant work across runs.
        if Tracker.ReconcileWithTSM then
            local last = Tracker._tsmLastReconcile or 0
            if time() - last > 3600 then
                Tracker._tsmLastReconcile = time()
                C_Timer.After(2, function()
                    if Tracker._isAHOpen then
                        Tracker:ReconcileWithTSM(false)
                    end
                end)
            end
        end

    elseif event == "AUCTION_HOUSE_CLOSED" then
        isAHOpen = false
        Tracker._isAHOpen = false
        wipe(preTodoSnapshot)

    elseif event == "BAG_UPDATE_DELAYED" then
        if isAHOpen and next(preTodoSnapshot) then
            C_Timer.After(0.3, CheckForPosts)
        end
        -- Skip refresh during active deposit/pull — FinishDeposit handles it with fresh scans
        if (ns.BankQueue and ns.BankQueue.processing) then return end
        -- Debounce: collapse a burst of bag updates into a single refresh chain.
        -- The Syndicator BagCacheUpdate path (Scanner.lua) handles the actual
        -- inventory projection on its own debounce; we no longer call
        -- Scanner:ScanCurrentCharacter here. Calling it on every BAG_UPDATE_DELAYED
        -- as well doubled the projection cost during TSM Post Scan bursts (FQ-137).
        if Tracker._bagUpdatePending then return end
        Tracker._bagUpdatePending = true
        C_Timer.After(0.5, function()
            Tracker._bagUpdatePending = false
            if (ns.BankQueue and ns.BankQueue.processing) then return end
            if ns.TodoList then
                if ns.TodoList.RefreshLocations then
                    ns.TodoList:RefreshLocations()
                end
                if ns.TodoList.RefreshTaskSteps then
                    ns.TodoList:RefreshTaskSteps()
                end
            end
            if ns.UI then
                if ns.UI.mainFrame and ns.UI.mainFrame:IsShown() then
                    ns.UI:Refresh()
                end
                if ns.UI.RefreshMini then ns.UI:RefreshMini() end
            end
        end)

    elseif event == "BANKFRAME_OPENED" then
        -- Reset the session-withdraw tracker so each bank visit starts with
        -- fresh accounting. Without this, gold the player spent between bank
        -- visits stays in the "already covered" total and suppresses the next
        -- legitimate withdraw (FQ-117).
        if Tracker.ResetSessionWithdrawTracker then
            Tracker:ResetSessionWithdrawTracker()
        end
        C_Timer.After(1, function()
            -- Scanner already scans bags/bank/warbank at 0.5s — refresh task state
            -- with fresh data so depositFrom/source are correct before auto-pull runs
            if ns.TodoList then
                if ns.TodoList.RefreshLocations then ns.TodoList:RefreshLocations() end
                if ns.TodoList.RefreshTaskSteps then ns.TodoList:RefreshTaskSteps() end
            end
            -- Refresh UI immediately so deposit tasks appear even without AH open
            if ns.UI then
                if ns.UI.mainFrame and ns.UI.mainFrame:IsShown() then ns.UI:Refresh() end
                if ns.UI.RefreshMini then ns.UI:RefreshMini() end
            end
            -- Show bank operations popup — user clicks Execute to run all ops
            -- in hardware event context (bypasses warbank taint).
            Tracker:ShowBankOpsPopup()
        end)

    elseif event == "OWNED_AUCTIONS_UPDATED" then
        if isAHOpen then
            -- Debounce. TSM Cancel Scan and rapid posting bursts can fire
            -- OWNED_AUCTIONS_UPDATED many times in a few seconds; CheckOwnedAuctions
            -- walks every owned auction × every todo task per call. Without a
            -- debounce we'd re-do that O(auctions × tasks) work per event (FQ-137).
            -- 0.3s delay also gives AUCTION_CANCELED (which fires after) time to
            -- bump _pendingCancels for the reconciliation check.
            if not Tracker._ownedAuctionsTimer then
                Tracker._ownedAuctionsTimer = C_Timer.NewTimer(0.3, function()
                    Tracker._ownedAuctionsTimer = nil
                    if Tracker._isAHOpen then
                        Tracker:CheckOwnedAuctions()
                        Tracker:UpdateLogExpiry()
                    end
                end)
            end
            -- Fire the shared Cogworks event so sibling cogs (a future
            -- Ledger, etc.) can react to auction state changes.
            if ns.cw and ns.cw.Fire then
                ns.cw:Fire(ns.cw.Events.AuctionsChanged, ns:GetCharKey())
            end
        end

    elseif event == "AUCTION_CANCELED" then
        -- Count pending cancels — consumed by reconciliation in CheckOwnedAuctions
        Tracker._pendingCancels = (Tracker._pendingCancels or 0) + 1
    end
end)

--------------------------
-- AH Purchase Hooks
--------------------------
-- Detect when the player buys an item on the AH (non-commodity and commodity)
-- and advance buy task steps immediately (browse → buy → collect).

if C_AuctionHouse and C_AuctionHouse.PlaceBid then
    hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, bidAmount)
        if not ns.TodoList or not ns.TodoList.OnItemPurchased then return end
        local info = C_AuctionHouse.GetAuctionInfoByID(auctionID)
        local itemID, itemName
        if info and info.itemKey then
            itemID = info.itemKey.itemID
        end
        if itemID then
            local ok, n = pcall(C_Item.GetItemInfo, itemID)
            itemName = ok and n or nil
        end
        ns:PrintDebug("[buy-hook] PlaceBid auc=" .. auctionID ..
            " id=" .. tostring(itemID) .. " name=" .. tostring(itemName))
        if itemID then
            ns.TodoList:OnItemPurchased(itemID, itemName)
        else
            ns:PrintDebug("[buy-hook] PlaceBid — no auction info, will detect via bags")
        end
    end)
end

-- Commodity purchase confirmation
if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
    hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
        if not ns.TodoList or not ns.TodoList.OnItemPurchased then return end
        local itemName
        if itemID then
            local ok, n = pcall(C_Item.GetItemInfo, itemID)
            itemName = ok and n or nil
        end
        ns:PrintDebug("[buy-hook] CommodityPurchase id=" .. tostring(itemID) ..
            " name=" .. tostring(itemName) .. " qty=" .. tostring(quantity))
        ns.TodoList:OnItemPurchased(itemID, itemName)
    end)
end
