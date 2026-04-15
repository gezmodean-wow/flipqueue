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
local INTER_MOVE_DELAY = 0.1  -- minimum spacing between successive container ops
                              -- inside a batch — Blizzard rate-limits coarsely and
                              -- 5+ ops in one frame trips the "Internal bag error"
                              -- backoff that disables the warbank for ~30s. Same
                              -- spacing Baganator uses.

--------------------------
-- Helpers
--------------------------

-- Determine the bank type for a bag ID. Uses the same numeric ranges as
-- ns.BANK_TABS (6-11) and ns.WARBANK_TABS (12-16) instead of Enum.BagIndex
-- constants — some of those constants (BankBag_1..BankBag_7,
-- AccountBankTab_1..AccountBankTab_5) aren't defined on every client/patch,
-- and a missing constant would crash the comparison with "compare nil with
-- number".
local function GetBankTypeForBag(bagID)
    if type(bagID) ~= "number" then return nil end
    if not Enum or not Enum.BankType then return nil end
    -- Warbank tabs: 12-16 (account bank)
    if bagID >= 12 and bagID <= 16 then
        return Enum.BankType.Account
    end
    -- Character bank: -1 (main bank slot) or 6-11 (character bank bags)
    if bagID == -1 or (bagID >= 6 and bagID <= 11) then
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

-- Exported so non-BankQueue callers (e.g. Tracker:AutoDepositGold which
-- calls C_Bank.DepositMoney directly without going through Process) can
-- ensure the panel is on the right bank type before issuing a Blizzard
-- API call. Without this, C_Bank.CanDepositMoney(Account) returns false
-- when the user's last-active panel was the character bank, and the gold
-- op silently fails with no debug print.
BankQueue.SetBankPanelType = SetBankPanelType

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

--------------------------
-- Bank Tab Filter Cache & Smart Deposit Slot Picker
--------------------------

-- Cache for C_Bank.FetchPurchasedBankTabData results, keyed by bagID.
-- depositFlags is the per-tab item-type filter the player set in Blizzard's
-- bank UI ("Equipment only", "Reagents only", etc.). We honor it strictly.
local tabFilterCache = {}
local tabFilterCacheTs = 0
local TAB_CACHE_TTL = 5

local function RefreshTabFilterCache()
    tabFilterCache = {}
    tabFilterCacheTs = time()
    if not (C_Bank and C_Bank.FetchPurchasedBankTabData and Enum and Enum.BankType) then
        return
    end
    local function ingest(bankType)
        local ok, data = pcall(C_Bank.FetchPurchasedBankTabData, bankType)
        if ok and type(data) == "table" then
            for _, td in ipairs(data) do
                if td.ID then
                    tabFilterCache[td.ID] = td
                end
            end
        end
    end
    ingest(Enum.BankType.Character)
    ingest(Enum.BankType.Account)
end

local function GetTabFilterData(bagID)
    if time() - tabFilterCacheTs > TAB_CACHE_TTL then
        RefreshTabFilterCache()
    end
    return tabFilterCache[bagID]
end

-- Resolve flag constants in a way that survives the ClassXxx → PriorityXxx
-- rename Blizzard did between patches.
local function FlagConst(...)
    if not Enum or not Enum.BagSlotFlags then return nil end
    for i = 1, select("#", ...) do
        local v = Enum.BagSlotFlags[select(i, ...)]
        if v then return v end
    end
    return nil
end

local FLAG_EQUIPMENT   = FlagConst("ClassEquipment",   "PriorityEquipment")
local FLAG_CONSUMABLES = FlagConst("ClassConsumables", "PriorityConsumables")
local FLAG_TRADEGOODS  = FlagConst("ClassTradeGoods",  "PriorityTradeGoods")
local FLAG_JUNK        = FlagConst("ClassJunk",        "PriorityJunk")
local FLAG_QUEST       = FlagConst("ClassQuestItems",  "PriorityQuestItems")
local FLAG_REAGENTS    = FlagConst("ClassReagents",    "PriorityReagents")

-- True if the tab will accept this item via deposit. depositFlags == 0 (or
-- nil) is a catch-all tab. Otherwise the tab only accepts items that match
-- at least one of its set class flags.
local function ItemMatchesTabFlags(itemLink, depositFlags)
    if not depositFlags or depositFlags == 0 then return true end
    if not itemLink then return true end

    local _, _, quality, _, _, _, _, _, _, _, _, classID = GetItemInfo(itemLink)
    if not classID then return true end  -- can't determine — allow

    local function has(flag)
        return flag and bit.band(depositFlags, flag) ~= 0
    end

    if has(FLAG_EQUIPMENT) and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor) then
        return true
    end
    if has(FLAG_CONSUMABLES) and classID == Enum.ItemClass.Consumable then
        return true
    end
    if has(FLAG_TRADEGOODS) and (classID == Enum.ItemClass.Tradegoods or classID == Enum.ItemClass.Recipe) then
        return true
    end
    if has(FLAG_REAGENTS) and classID == Enum.ItemClass.Tradegoods then
        return true
    end
    if has(FLAG_JUNK) and quality == (Enum.ItemQuality and Enum.ItemQuality.Poor or 0) then
        return true
    end
    if has(FLAG_QUEST) and classID == Enum.ItemClass.Questitem then
        return true
    end
    return false
end

-- Specificity score for picking the most specific matching tab over the
-- catch-all. More set flags = more specific.
local function TabSpecificity(depositFlags)
    if not depositFlags or depositFlags == 0 then return 0 end
    local count, mask = 0, depositFlags
    while mask > 0 do
        if bit.band(mask, 1) == 1 then count = count + 1 end
        mask = bit.rshift(mask, 1)
    end
    return count + 1  -- any specific tab beats catch-all
end

-- Build the list of accepting tabs sorted by specificity (most specific first).
-- Ties broken by original bagList index so tabs with equal specificity walk
-- in the user-configured order (typically ascending bag ID = tab 1 → tab N).
-- Lua's table.sort is NOT stable, so we MUST provide an explicit tiebreaker
-- or equal-spec tabs get reordered non-deterministically — which is how we
-- ended up filling tab 1 → tab 4 → tab 3 → tab 2 when all filters were off.
--
-- If `trace` is a table, append per-tab description strings in the SORTED
-- (walked) order. Rejected tabs are appended after the accepted ones so the
-- user can see both what the picker considered and why each tab got skipped.
local function MatchingTabsSorted(itemLink, bagList, trace)
    local matched = {}
    if not bagList then return matched end
    local rejectedTrace
    if trace then rejectedTrace = {} end
    for idx, bag in ipairs(bagList) do
        local td = GetTabFilterData(bag)
        local flags = td and td.depositFlags or 0
        local spec = TabSpecificity(flags)
        local accepts = ItemMatchesTabFlags(itemLink, flags)
        if accepts then
            table.insert(matched, { bag = bag, spec = spec, order = idx, flags = flags })
        elseif rejectedTrace then
            table.insert(rejectedTrace, string.format("%d(flags=0x%x,spec=%d,reject)",
                bag, flags, spec))
        end
    end
    table.sort(matched, function(a, b)
        if a.spec ~= b.spec then return a.spec > b.spec end
        return a.order < b.order
    end)
    if trace then
        for _, m in ipairs(matched) do
            table.insert(trace, string.format("%d(flags=0x%x,spec=%d,accept)",
                m.bag, m.flags, m.spec))
        end
        for _, s in ipairs(rejectedTrace) do
            table.insert(trace, s)
        end
    end
    return matched
end

-- Helper: is (bag, slot) in the allocation ledger?
local function IsSlotClaimed(allocatedSlots, bag, slot)
    if not allocatedSlots then return false end
    local bagClaims = allocatedSlots[bag]
    return bagClaims and bagClaims[slot] == true
end

-- Build a bag-walk list ignoring tab filters. Used by the filter-bypass
-- fallback path: if no filter-matching tab can take the item we'd rather
-- use a non-preferred warbank tab than spill into the personal bank.
local function UnfilteredBagList(bagList)
    local list = {}
    if not bagList then return list end
    for _, bag in ipairs(bagList) do
        table.insert(list, { bag = bag, spec = 0 })
    end
    return list
end

-- Find a partial-stack target for stacking deposits. Walks accepting tabs in
-- specificity order, returns the first slot whose itemID matches and has
-- stack room. The server will merge the picked-up stack onto the target.
--
-- allocatedSlots (optional) — a {[bag]={[slot]=true}} map of destinations
-- already claimed by earlier operations in the current batch. Claimed slots
-- are skipped so two ops never target the same slot when the client cache
-- hasn't yet reflected a prior move.
--
-- ignoreFilters — when true, walks every bag in the list regardless of its
-- Blizzard depositFlags. Stacking onto an existing partial of the same item
-- is always correct regardless of which tab filter the user set.
local function FindStackTarget(itemLink, itemID, bagList, allocatedSlots, ignoreFilters)
    if not itemID then return nil end
    local stackMax
    if itemLink then
        local _, _, _, _, _, _, _, sm = GetItemInfo(itemLink)
        stackMax = sm
    end
    if not stackMax or stackMax <= 1 then return nil end

    local sorted = ignoreFilters and UnfilteredBagList(bagList)
        or MatchingTabsSorted(itemLink, bagList)
    for _, m in ipairs(sorted) do
        local ok, num = pcall(C_Container.GetContainerNumSlots, m.bag)
        if ok and num then
            for slot = 1, num do
                if not IsSlotClaimed(allocatedSlots, m.bag, slot) then
                    local ok2, info = pcall(C_Container.GetContainerItemInfo, m.bag, slot)
                    if ok2 and info and info.itemID == itemID then
                        local count = info.stackCount or 1
                        if count < stackMax then
                            return m.bag, slot
                        end
                    end
                end
            end
        end
    end
end

-- Find an empty slot inside an accepting tab, preferring most-specific.
-- Prefers C_Item.DoesItemExist (ItemLocation-based) over
-- C_Container.GetContainerItemInfo because the container cache for warbank
-- tabs that haven't been actively viewed can lag behind the server and
-- briefly report an occupied slot as empty.
--
-- ignoreFilters — when true, walks every bag in the list regardless of its
-- Blizzard depositFlags. The filter-bypass fallback path uses this so that
-- items in unrecognised classes (Gem, Glyph, Profession, etc., which our
-- limited ItemMatchesTabFlags class table doesn't cover) can still find a
-- home in warbank instead of leaking into the personal bank as overflow.
local function FindEmptyAcceptingSlot(itemLink, bagList, allocatedSlots, ignoreFilters)
    local sorted = ignoreFilters and UnfilteredBagList(bagList)
        or MatchingTabsSorted(itemLink, bagList)
    local hasDoesItemExist = C_Item and C_Item.DoesItemExist
    for _, m in ipairs(sorted) do
        local ok, num = pcall(C_Container.GetContainerNumSlots, m.bag)
        if ok and num then
            for slot = 1, num do
                if not IsSlotClaimed(allocatedSlots, m.bag, slot) then
                    local occupied
                    if hasDoesItemExist then
                        local eok, ex = pcall(C_Item.DoesItemExist, {bagID = m.bag, slotIndex = slot})
                        if eok then
                            occupied = ex
                        end
                    end
                    if occupied == nil then
                        local ok2, info = pcall(C_Container.GetContainerItemInfo, m.bag, slot)
                        occupied = ok2 and info ~= nil
                    end
                    if not occupied then
                        return m.bag, slot
                    end
                end
            end
        end
    end
end

-- Pick a deposit destination respecting tab filters, smart stacking, and
-- the user's overflow settings. Returns destBag, destSlot, or nil.
--
-- Strategy:
--   1. Stack into a partial stack inside the primary bag list.
--   2. If overflow is enabled AND crossStack is enabled, try stacking inside
--      the secondary bag list.
--   3. Empty slot in primary (most-specific tab first).
--   4. If overflow is enabled, empty slot in secondary.
--
-- allocatedSlots is forwarded to the finders so prior ops in the same batch
-- don't collide on the same slot.
--
-- opName is just used for the debug log line. Every call emits one line into
-- the debug ring buffer disclosing the candidate list, the picked slot, and
-- which branch picked it — so we can tell stack-target hits apart from
-- specificity-driven empty-slot picks when investigating "wrong tab" reports.
local function PickDepositSlot(info, primaryBags, secondaryBags, overflowEnabled, crossStack, allocatedSlots, opName)
    local link = info.hyperlink
    local id = info.itemID

    -- Build the candidate descriptions up front so the same data is in the
    -- log regardless of which branch ends up picking the slot.
    local primaryTrace, secondaryTrace = {}, {}
    MatchingTabsSorted(link, primaryBags, primaryTrace)
    if secondaryBags and #secondaryBags > 0 then
        MatchingTabsSorted(link, secondaryBags, secondaryTrace)
    end

    local function logResult(reason, b, s)
        if not ns.PrintDebug then return end
        ns:PrintDebug(string.format(
            "[deposit-pick] \"%s\" -> %s bag=%s slot=%s | primary=[%s] secondary=[%s] overflow=%s crossStack=%s",
            tostring(opName or link or "?"),
            reason,
            tostring(b or "nil"), tostring(s or "nil"),
            table.concat(primaryTrace, " "),
            table.concat(secondaryTrace, " "),
            tostring(overflowEnabled), tostring(crossStack)))
    end

    local b, s = FindStackTarget(link, id, primaryBags, allocatedSlots)
    if b then logResult("stackTarget(primary)", b, s); return b, s end

    b, s = FindEmptyAcceptingSlot(link, primaryBags, allocatedSlots)
    if b then logResult("emptySlot(primary)", b, s); return b, s end

    -- Filter-bypass fallback inside primary, BEFORE going to overflow.
    -- ItemMatchesTabFlags only knows about a handful of item classes
    -- (Weapon/Armor/Consumable/Tradegoods/Recipe/Questitem/Junk) — items
    -- in any other class (Gem, ItemEnhancement, Glyph, Miscellaneous,
    -- Battlepet, Profession, …) get rejected by every tab that has *any*
    -- depositFlags set, even when those tabs have empty space. The user's
    -- tab filters are a routing preference, not a hard wall — if no
    -- preferred tab can take the item, we'd rather use a non-preferred
    -- warbank tab than leak the item into the personal bank as overflow.
    b, s = FindStackTarget(link, id, primaryBags, allocatedSlots, true)
    if b then logResult("stackTarget(primary,filter-bypass)", b, s); return b, s end

    b, s = FindEmptyAcceptingSlot(link, primaryBags, allocatedSlots, true)
    if b then logResult("emptySlot(primary,filter-bypass)", b, s); return b, s end

    if overflowEnabled and crossStack then
        b, s = FindStackTarget(link, id, secondaryBags, allocatedSlots)
        if b then logResult("stackTarget(secondary,overflow+crossStack)", b, s); return b, s end
    end

    if overflowEnabled then
        b, s = FindEmptyAcceptingSlot(link, secondaryBags, allocatedSlots)
        if b then logResult("emptySlot(secondary,overflow)", b, s); return b, s end

        -- Filter-bypass on secondary too — same rationale as primary, just
        -- one rung further down the fallback ladder.
        b, s = FindEmptyAcceptingSlot(link, secondaryBags, allocatedSlots, true)
        if b then logResult("emptySlot(secondary,overflow,filter-bypass)", b, s); return b, s end
    end
    logResult("none", nil, nil)
    return nil, nil
end

-- Add a claim to the allocation ledger. Called just before issuing a
-- CursorMove so subsequent ops in the same batch won't target the same slot.
local function ClaimSlot(allocatedSlots, bag, slot)
    if not allocatedSlots then return end
    allocatedSlots[bag] = allocatedSlots[bag] or {}
    allocatedSlots[bag][slot] = true
end

-- Remove a claim. Used when CursorMove rejected the move, so another op can
-- try the slot on its own attempt.
local function UnclaimSlot(allocatedSlots, bag, slot)
    if not allocatedSlots or not allocatedSlots[bag] then return end
    allocatedSlots[bag][slot] = nil
end

-- Execute a cursor-based item move: pick up from src, place at dst.
-- Returns true if the move was issued, false otherwise.
-- Kept as a fallback for cases where ShiftMove can't be used.
--
-- expectedItemID (optional) — the itemID being moved. When provided the
-- function checks the destination slot *before* placing: if the slot is
-- occupied by a *different* itemID the call is aborted (returns false)
-- instead of executing a swap that would silently displace the occupant.
-- Stacking onto a partial stack of the same item is still allowed.
local function CursorMove(srcBag, srcSlot, dstBag, dstSlot, expectedItemID)
    pcall(ClearCursor)
    pcall(C_Container.PickupContainerItem, srcBag, srcSlot)
    if CursorHasItem() then
        -- Guard: verify destination is empty or holds the same item so we
        -- never silently swap an unrelated item out of the bank.
        if expectedItemID then
            local dok, dinfo = pcall(C_Container.GetContainerItemInfo, dstBag, dstSlot)
            if dok and dinfo and dinfo.itemID ~= expectedItemID then
                pcall(ClearCursor)
                return false
            end
        end
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

-- Wait between successive container moves. Two conditions must both be
-- satisfied before `callback` runs:
--
--   1. A minimum delay (`minDelay`) has elapsed — Blizzard rate-limits
--      container ops coarsely, and issuing the next move too quickly
--      throws "Internal bag error". ~100ms is the known-safe spacing.
--
--   2. BAG_UPDATE_DELAYED has fired — this is the deterministic signal
--      that the client container cache has caught up to the server's
--      response to the last move. Without this wait, the next move's
--      slot picker may still see stale "empty" slots and silently swap.
--
-- If BAG_UPDATE_DELAYED never arrives (e.g. the last move was rejected
-- server-side and produced no bag change), a hard-ceiling timer releases
-- the wait after `minDelay + 0.5s` so we don't stall forever.
local function WaitForBagUpdate(minDelay, callback)
    local frame = CreateFrame("Frame")
    local eventFired = false
    local timerDone = false
    local released = false
    local function release()
        if released then return end
        released = true
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
        callback()
    end
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:SetScript("OnEvent", function()
        eventFired = true
        if timerDone then release() end
    end)
    C_Timer.After(minDelay or 0.1, function()
        timerDone = true
        if eventFired then release() end
    end)
    -- Hard ceiling: proceed even if no BAG_UPDATE_DELAYED ever arrives.
    C_Timer.After((minDelay or 0.1) + 0.5, release)
end

--------------------------
-- Queue Processor
--------------------------

local queue = {}             -- ordered operations awaiting processing
-- stats.deferred: deposit ops that couldn't find a slot this batch.
-- Distinct from errors — these are "try again later when warbank has room"
-- and leave the underlying task step untouched so the next run picks it up.
local stats = { successes = {}, errors = 0, deferred = {} }
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
        cb(stats.successes, stats.errors, stats.deferred)
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
    -- Claim ledger for deposit destinations inside this batch, so two ops
    -- never target the same slot — the client cache won't have reflected
    -- the first move's effect yet, but the ledger is authoritative. (Same
    -- mechanism Baganator uses.)
    local allocatedSlots = {}

    -- Issue a single op. Returns true if a real container move was issued
    -- (and the next op should therefore wait for BAG_UPDATE_DELAYED before
    -- being picked, both for slot-cache freshness and Blizzard's per-frame
    -- container-op rate limit).
    local function HandleOp(op)
        local ok, info = pcall(C_Container.GetContainerItemInfo, op.srcBag, op.srcSlot)
        if not ok or not info then
            -- Source empty — already moved or gone
            return false
        elseif op._expectedItemID and info.itemID ~= op._expectedItemID then
            -- Source item has changed since the op was first attempted —
            -- a prior move or user action displaced the original item.
            -- Do not move the impostor.
            return false
        elseif info.isLocked then
            op._lockWaits = (op._lockWaits or 0) + 1
            if op._lockWaits > 10 then
                stats.errors = stats.errors + 1
            else
                table.insert(queue, op)
            end
            return false
        elseif op.op == "pull" then
            if abortPulls then return false end
            if not bankOpen then
                abortPulls = true
                ns:Print(ns.COLORS.RED .. "Bank closed!|r Skipping remaining pulls.")
                return false
            end
            EnsureBankType(op.srcBag)
            op._expectedItemID = op._expectedItemID or info.itemID
            op._itemID = info.itemID
            op._stackBefore = info.stackCount or 1
            ShiftMove(op.srcBag, op.srcSlot)
            table.insert(issuedOps, op)
            return true
        elseif op.op == "deposit" then
            if abortDeposits then return false end
            if not bankOpen then
                abortDeposits = true
                ns:Print(ns.COLORS.RED .. "Bank closed!|r Skipping remaining deposits.")
                return false
            end
            -- CursorMove with an explicit destination, so the user's
            -- per-tab enable settings, Blizzard tab filters, and the
            -- overflow gate are all respected.
            local primary, secondary
            if op.destType == "warbank" then
                primary, secondary = snapshot.warbankBags, snapshot.bankBags
            elseif op.destType == "bank" then
                primary, secondary = snapshot.bankBags, snapshot.warbankBags
            else
                -- "any" — non-soulbound items: prefer warbank, fall back
                -- to personal bank only via the overflow gate. Previously
                -- this branch merged warbank+bank into a single primary
                -- list which silently bypassed the overflow setting.
                primary, secondary = snapshot.warbankBags, snapshot.bankBags
            end

            local overflowEnabled, crossStack = false, false
            if ns.GetDepositOverflow then
                overflowEnabled, crossStack = ns:GetDepositOverflow()
            end

            local destBag, destSlot = PickDepositSlot(
                info, primary, secondary, overflowEnabled, crossStack, allocatedSlots, op.name)
            if not destBag then
                -- No slot available for THIS op. Defer it (not an error)
                -- and keep processing the rest of the batch: stack-merge ops
                -- for other items can still succeed even when a full-slot
                -- new item can't fit. The underlying task step stays
                -- "pending" so the next bank open retries.
                table.insert(stats.deferred, op.name or "?")
                return false
            end
            EnsureBankType(destBag)
            ClaimSlot(allocatedSlots, destBag, destSlot)
            op._expectedItemID = op._expectedItemID or info.itemID
            op._itemID = info.itemID
            op._stackBefore = info.stackCount or 1
            if CursorMove(op.srcBag, op.srcSlot, destBag, destSlot, info.itemID) then
                table.insert(issuedOps, op)
                return true
            else
                -- Move rejected (guard tripped, pickup failed). Release the
                -- claim so another op can try it, and re-queue this op for
                -- a fresh attempt.
                UnclaimSlot(allocatedSlots, destBag, destSlot)
                op._retries = (op._retries or 0) + 1
                if op._retries <= MAX_RETRIES then
                    table.insert(queue, op)
                else
                    stats.errors = stats.errors + 1
                end
                return false
            end
        end
        return false
    end

    local function FinishBatch()
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

    -- Issue ops one at a time, throttling between *real* moves with
    -- WaitForBagUpdate so back-to-back container ops don't trip Blizzard's
    -- per-frame rate limit (the symptom: warbank gets disabled for ~30s
    -- when too many UseContainerItem / PickupContainerItem calls fire in
    -- one tick). Skip-cases (source empty, locked, aborted) yield to the
    -- next frame instead so we don't blow the Lua call stack on big batches.
    local i = 0
    local function NextOp()
        i = i + 1
        if i > #batch then
            FinishBatch()
            return
        end
        local issuedAMove = HandleOp(batch[i])
        if issuedAMove then
            WaitForBagUpdate(INTER_MOVE_DELAY, NextOp)
        else
            C_Timer.After(0, NextOp)
        end
    end
    NextOp()
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
    stats = { successes = {}, errors = 0, deferred = {} }
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
        cb(stats.successes, stats.errors, stats.deferred)
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
        -- Claim ledger scoped to this attempt. Two ops issued back-to-back
        -- in the same attempt must never land on the same slot — the
        -- client container cache won't have caught up with the first op by
        -- the time the second one picks its destination.
        local allocatedSlots = {}

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
            end
            -- Source item validation. The op references a specific (bag, slot)
            -- captured when the op list was built. If something displaced that
            -- item — manual move, another addon, a prior attempt's failure —
            -- the slot now holds a *different* item and we must NOT move it,
            -- or we'll silently send the wrong item to the bank.
            --
            -- _expectedItemID is set on the first successful read and compared
            -- on every subsequent attempt.
            if op._expectedItemID and info.itemID ~= op._expectedItemID then
                return false
            end
            if not op._expectedItemID then
                op._expectedItemID = info.itemID
            end
            if info.isLocked then
                -- Locked from a prior in-flight move. Treat as retryable —
                -- queue it for the next attempt.
                op._itemID = info.itemID
                op._stackBefore = info.stackCount or 1
                table.insert(issuedOps, op)
                return false
            elseif op.op == "pull" then
                if not bankOpen then
                    nonRetryableErrors = nonRetryableErrors + 1
                    return false
                end
                -- Pulls use shift-click: bank → inventory direction is
                -- unambiguous, so UseContainerItem routes correctly.
                op._itemID = info.itemID
                op._stackBefore = info.stackCount or 1
                ShiftMove(op.srcBag, op.srcSlot)
                table.insert(issuedOps, op)
                return true
            elseif op.op == "deposit" then
                if not bankOpen then
                    nonRetryableErrors = nonRetryableErrors + 1
                    return false
                end
                -- CursorMove with an explicit destination slot, so we honour
                -- the user's enabled-tabs settings and each tab's Blizzard
                -- deposit flags. Collisions between back-to-back ops (where
                -- the warbank container cache hasn't caught up to a prior
                -- move and still reports the just-filled slot as empty) are
                -- prevented by the `allocatedSlots` ledger, which is checked
                -- inside FindStackTarget / FindEmptyAcceptingSlot. This is
                -- the same mechanism Baganator's BankTransferManager uses.
                local primary, secondary
                if op.destType == "warbank" then
                    primary, secondary = warbankBags, bankBags
                elseif op.destType == "bank" then
                    primary, secondary = bankBags, warbankBags
                else
                    -- "any" — non-soulbound items: prefer warbank, fall
                    -- back to personal bank only via the overflow gate.
                    -- Previously this branch merged warbank+bank into a
                    -- single primary list which silently bypassed the
                    -- overflow setting.
                    primary, secondary = warbankBags, bankBags
                end

                local overflowEnabled, crossStack = false, false
                if ns.GetDepositOverflow then
                    overflowEnabled, crossStack = ns:GetDepositOverflow()
                end

                local destBag, destSlot = PickDepositSlot(
                    info, primary, secondary, overflowEnabled, crossStack, allocatedSlots, op.name)
                if not destBag then
                    nonRetryableErrors = nonRetryableErrors + 1
                    return false
                end

                -- Claim the slot *before* issuing the move so the next
                -- IssueOne in this attempt can't target it even if the
                -- server hasn't fully processed this move yet.
                ClaimSlot(allocatedSlots, destBag, destSlot)
                op._itemID = info.itemID
                op._stackBefore = info.stackCount or 1
                if CursorMove(op.srcBag, op.srcSlot, destBag, destSlot, info.itemID) then
                    table.insert(issuedOps, op)
                    return true
                else
                    -- Move rejected (guard tripped or pickup failed).
                    -- Release the claim so a follow-up op can retry that
                    -- slot, and leave this op unissued so the next attempt
                    -- re-picks with fresh state.
                    UnclaimSlot(allocatedSlots, destBag, destSlot)
                    op._itemID = nil
                    op._stackBefore = nil
                    return false
                end
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

        -- Issue one move at a time, waiting for BAG_UPDATE_DELAYED between
        -- moves so the client container cache has caught up with the last
        -- move before the next IssueOne picks its destination. The event
        -- fires within a frame or two in the common case; the timeout is a
        -- fallback for moves the server rejected (no event arrives).
        --
        -- If a panel switch is needed (mixed bank/warbank ops in the same
        -- batch) we add a small extra settle delay so the switch propagates
        -- before the next move's container call.
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
                    WaitForBagUpdate(SYNC_INTER_MOVE_DELAY, IssueNext)
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
