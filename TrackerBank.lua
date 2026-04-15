-- TrackerBank.lua
-- Bank auto-pull and warbank gold withdrawal for to-do list items
local addonName, ns = ...

local Tracker = ns.Tracker

--------------------------
-- Bank Auto-Pull
--------------------------

function Tracker:AutoPullFromBank(onComplete, fromClick)
    if not ns.db or not ns:GetCharSetting(ns:GetCharKey(), "autoPullBank") then
        if onComplete then onComplete({}, 0) end
        return
    end

    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()

    -- Build needed list from the active to-do list
    local needed = {} -- item -> qty still needed from bank

    if ns.TodoList and ns.TodoList:GetCurrentList() then
        local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(todoTasks) do
            local item = task.item
            if item.action == "buy" then
                -- Buy tasks are purchased from AH, not pulled from bank
            elseif ns:RealmMatches(item.targetRealm or "", currentRealm) then
                -- Use the task's own quantity — it already accounts for TSM postCap
                -- and available inventory from when the to-do list was generated
                local targetQty = item.quantity or 1
                local inBags = Tracker._CountInBags(item)
                local stillNeeded = targetQty - inBags
                if stillNeeded > 0 then
                    needed[item] = stillNeeded
                end
            end
        end
    end

    -- Also pull items that need depositing to warbank for other characters
    -- Only pull from personal bank — skip items already in warbank or with source resolved
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

    if not next(needed) then
        if onComplete then onComplete({}, 0) end
        return
    end

    local allBankTabs = {}
    for _, b in ipairs(ns:GetEnabledBankTabs()) do table.insert(allBankTabs, b) end
    for _, b in ipairs(ns:GetEnabledWarbankTabs()) do table.insert(allBankTabs, b) end

    if not next(needed) then
        if onComplete then onComplete({}, 0) end
        return
    end

    -- Build a list of moves to make — only pull items that match to-do task items
    local moves = {}
    for _, bagIndex in ipairs(allBankTabs) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                -- Don't filter by isBound — BtW/WuE items show as bound but
                -- can move to/from warbank. The game rejects truly invalid moves.
                if ok2 and info and info.hyperlink then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                        local slotName  -- lazy name cache per slot
                        for queueItem, count in pairs(needed) do
                            if count > 0 then
                                -- Use false for resolvedID to prevent wrong ID matches
                                local matched = ns:ItemsMatch(key, nil, queueItem, false, false)
                                if not matched then
                                    if slotName == nil then slotName = Tracker._GetNameFromLink(info.hyperlink) or false end
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

    if #moves == 0 then
        if onComplete then onComplete({}, 0) end
        return
    end

    -- Check free bag space before pulling
    local freeBagSlots = 0
    for _, bagIndex in ipairs(ns.INVENTORY_BAGS) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and not info then
                    freeBagSlots = freeBagSlots + 1
                end
            end
        end
    end

    if freeBagSlots == 0 then
        ns:Print(ns.COLORS.RED .. "Bags are full!|r Cannot pull " .. #moves .. " item(s) from bank.")
        if onComplete then onComplete({}, 0) end
        return
    end

    if freeBagSlots < #moves then
        ns:Print(ns.COLORS.YELLOW .. "Only " .. freeBagSlots .. " free bag slot(s) — pulling " ..
            freeBagSlots .. " of " .. #moves .. " item(s) from bank.|r")
    end

    -- Build operations from the moves list
    local totalMoves = math.min(#moves, freeBagSlots)
    local ops = {}
    local hasWarbankPulls = false
    for i = 1, totalMoves do
        local isWarbank = false
        for _, wb in ipairs(ns.WARBANK_TABS) do
            if moves[i].bag == wb then isWarbank = true; break end
        end
        if isWarbank then hasWarbankPulls = true end
        table.insert(ops, {
            op = "pull",
            srcBag = moves[i].bag,
            srcSlot = moves[i].slot,
            name = moves[i].name,
        })
    end

    local function PullComplete(successNames, errorCount)
        if #successNames > 0 then
            if errorCount == 0 then
                ns:Print("Auto-pulled " .. #successNames .. " item(s) from bank: " .. table.concat(successNames, ", "))
            else
                ns:Print("Auto-pulled " .. #successNames .. " of " .. totalMoves .. " item(s) from bank: " .. table.concat(successNames, ", "))
            end
        end
        if errorCount > 0 then
            ns:Print(ns.COLORS.YELLOW .. errorCount .. " item(s) failed to move. Try opening your bank again.|r")
        end
        C_Timer.After(1, function()
            if ns.Scanner then
                ns.Scanner:ScanCurrentCharacter()
                ns.Scanner:ScanBank()
            end
            if ns.TodoList and ns.TodoList.RefreshLocations then
                ns.TodoList:RefreshLocations()
            end
            if ns.TodoList and ns.TodoList.RefreshTaskSteps then
                ns.TodoList:RefreshTaskSteps()
            end
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
            if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
            if onComplete then onComplete() end
        end)
    end

    if hasWarbankPulls and not fromClick then
        -- Warbank pulls from timer context taint the bank frame, breaking all
        -- subsequent warbank operations (including manual right-clicks).
        -- Show pull button — user click provides hardware event context.
        ns.BankQueue:ShowPullButton(ops, PullComplete)
    elseif fromClick then
        -- User clicked a button — hardware event context bypasses taint
        ns.BankQueue:ProcessSync(ops, "Pulling from bank...", PullComplete)
    else
        -- Personal bank only — fully automatic
        ns.BankQueue:Process(ops, "Pulling from bank...", PullComplete)
    end
end

--------------------------
-- Warbank Gold Withdrawal
--------------------------

-- Track withdrawals per session to avoid re-withdrawing
local sessionWithdrawnCopper = 0
local sessionWithdrawnRealm = nil

local DURATION_MULT = {[1] = 0.15, [2] = 0.30, [3] = 0.60}
local DURATION_LABEL = {[1] = "12h", [2] = "24h", [3] = "48h"}

-- Calculate AH posting deposit fees for a character's tasks on a given realm.
-- Returns: totalCopper, itemCount, details[]
function Tracker:CalculatePostingFees(charKey, currentRealm)
    local goldSellQtyMode = ns.db.settings.sellQtyMode or "tsm"
    local tsmEnabled = goldSellQtyMode == "tsm" and ns.TSM and ns.TSM:IsEnabled()

    local goldTasks = ns.TodoList and ns.TodoList:GetCharacterTasks(charKey) or {}
    local totalDepositCopper = 0
    local itemCount = 0
    local depositDetails = {}

    for _, task in ipairs(goldTasks) do
        if task.item.action == "buy" then
            -- Skip buy tasks — they use CalculatePurchaseCosts
        elseif ns:RealmMatches(task.item.targetRealm or "", currentRealm) then
            local queueItem = task.item
            itemCount = itemCount + 1

            -- Determine post quantity: respects sellQtyMode setting
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
                                local ok4, _, _, _, _, _, _, _, _, _, _, sp =
                                    pcall(C_Item.GetItemInfo, info.hyperlink)
                                if ok4 and sp and type(sp) == "number" and sp > 0 then
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
                    local ok5, _, _, _, _, _, _, _, _, _, _, sp =
                        pcall(C_Item.GetItemInfo, numID)
                    if ok5 and sp and type(sp) == "number" and sp > 0 then
                        sellPrice = sp
                    end
                end

                if sellPrice then
                    vendorPrice = sellPrice
                    itemDeposit = math.ceil(sellPrice * durationMult) * postQty
                else
                    local expectedGold = ns:ParseGoldValue(queueItem.expectedPrice or "")
                    if expectedGold > 0 then
                        vendorPrice = expectedGold * 100 * 0.05
                        itemDeposit = math.ceil(vendorPrice * durationMult) * postQty
                    else
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

    return totalDepositCopper, itemCount, depositDetails
end

-- Calculate purchase costs for buy-type tasks.
-- Returns totalCopper, itemCount, details[]
function Tracker:CalculatePurchaseCosts(charKey, currentRealm)
    local buyTasks = ns.TodoList and ns.TodoList:GetCharacterTasks(charKey) or {}
    local totalCopper = 0
    local itemCount = 0
    local details = {}

    for _, task in ipairs(buyTasks) do
        if task.item.action == "buy"
                and ns:RealmMatches(task.item.buyRealm or "", currentRealm) then
            local buyPriceGold = ns:ParseGoldValue(task.item.buyPrice or "")
            if buyPriceGold > 0 then
                local qty = task.item.quantity or 1
                local costCopper = math.ceil(buyPriceGold * 10000) * qty -- ParseGoldValue returns gold, convert to copper
                totalCopper = totalCopper + costCopper
                itemCount = itemCount + 1
                table.insert(details, {
                    name = task.item.name or tostring(task.item.itemID),
                    vendorCopper = 0,
                    duration = "buy",
                    mult = 1,
                    deposit = costCopper,
                    qty = qty,
                })
            end
        end
    end

    return totalCopper, itemCount, details
end

-- Calculate total gold required: posting fees + purchase costs.
-- Returns: totalCopper, itemCount, combinedDetails[]
function Tracker:CalculateRequiredGold(charKey, currentRealm)
    local postCopper, postCount, postDetails = self:CalculatePostingFees(charKey, currentRealm)
    local buyCopper, buyCount, buyDetails = self:CalculatePurchaseCosts(charKey, currentRealm)

    local totalCopper = postCopper + buyCopper
    local totalCount = postCount + buyCount
    local combinedDetails = {}
    for _, d in ipairs(postDetails) do table.insert(combinedDetails, d) end
    for _, d in ipairs(buyDetails) do table.insert(combinedDetails, d) end

    return totalCopper, totalCount, combinedDetails
end

function Tracker:AutoWithdrawGold()
    if not ns.db or not ns.db.settings.autoWithdrawGold then return end
    if not C_Bank or not C_Bank.WithdrawMoney then return end
    -- Defer to Warband Miser if installed (see DB.lua ns:IsWarbandMiserActive).
    -- WM manages per-character gold policy more granularly than we do, so
    -- when it's loaded we stay out of its way. Users can force us back in
    -- via the warbandMiserOverride setting.
    if ns.IsWarbandMiserActive and ns:IsWarbandMiserActive() then
        ns:PrintDebug("AutoWithdrawGold: deferring to Warband Miser")
        return
    end

    -- Only withdraw if this character actually has tasks on its realm
    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
    local hasTasks = false
    if ns.TodoList then
        local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(todoTasks) do
            local isBuy = task.item.action == "buy"
            local realmToMatch = isBuy and task.item.buyRealm or task.item.targetRealm
            if ns:RealmMatches(realmToMatch or "", currentRealm) then
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

    local totalDepositCopper, itemCount, depositDetails = self:CalculateRequiredGold(charKey, currentRealm)

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

    if effectiveCopper >= estimatedFeesCopper then return end
    if playerCopper >= estimatedFeesCopper then return end

    local shortfallCopper = estimatedFeesCopper - playerCopper
    local shortfallGold = math.ceil(shortfallCopper / 10000)
    local playerGold = math.floor(playerCopper / 10000)

    -- Ensure BankFrame is on the warbank panel before calling C_Bank APIs.
    -- Without this the call returns "permission denied" when the user's
    -- last-active panel was the character bank — Phase 6a removed the
    -- side-effect probe in Scanner that used to keep the panel warm.
    if ns.BankQueue and ns.BankQueue.SetBankPanelType and Enum and Enum.BankType then
        ns.BankQueue.SetBankPanelType(Enum.BankType.Account)
    end

    -- Check permission
    local ok6, canWithdraw = pcall(C_Bank.CanWithdrawMoney, Enum.BankType.Account)
    if not ok6 or not canWithdraw then
        ns:Print(ns.COLORS.YELLOW .. "Cannot withdraw from warbank|r — bank panel may not be on the warband tab. Click the warbank tab and try again.")
        ns:PrintDebug("AutoWithdrawGold: CanWithdrawMoney returned false (ok=" .. tostring(ok6) .. ")")
        return
    end

    -- Check warbank balance
    local ok7, warbankCopper = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    if not ok7 or not warbankCopper then
        ns:Print(ns.COLORS.RED .. "Could not check warbank balance.|r")
        return
    end

    -- Round up to whole gold
    shortfallCopper = shortfallGold * 10000

    -- Enforce max withdrawal cap
    local maxGold = ns.db.settings.maxWithdrawGold or 0
    if maxGold > 0 then
        local maxCopper = maxGold * 10000
        if shortfallCopper > maxCopper then
            shortfallCopper = maxCopper
            shortfallGold = maxGold
            ns:Print(ns.COLORS.YELLOW .. "Capped withdrawal to " .. maxGold .. "g (max setting).|r")
        end
    end

    if warbankCopper < shortfallCopper then
        local warbankGold = math.floor(warbankCopper / 10000)
        ns:Print(ns.COLORS.RED .. "Not enough in warbank.|r Need " .. shortfallGold ..
            "g more, warbank has " .. warbankGold .. "g")
        return
    end

    -- Withdraw
    local ok8, err = pcall(C_Bank.WithdrawMoney, Enum.BankType.Account, shortfallCopper)
    if ok8 then
        sessionWithdrawnCopper = sessionWithdrawnCopper + shortfallCopper
        ns:Print(ns.COLORS.GREEN .. "Withdrew " .. shortfallGold .. "g|r from warbank" ..
            " (est. " .. estimatedFeesGold .. "g fees for " .. itemCount .. " items, had " .. playerGold .. "g)")
        return shortfallCopper
    else
        ns:Print(ns.COLORS.RED .. "Failed to withdraw: " .. tostring(err) .. "|r")
        return 0
    end
end

--------------------------
-- Auto-Deposit Earnings
--------------------------

-- Deposit excess gold to warbank, keeping only AH fees + buffer.
function Tracker:AutoDepositGold()
    if not ns.db or not ns.db.settings.autoDepositGold then return end
    if not C_Bank or not C_Bank.DepositMoney then return end
    -- Defer to Warband Miser (see AutoWithdrawGold above for the rationale).
    if ns.IsWarbandMiserActive and ns:IsWarbandMiserActive() then
        ns:PrintDebug("AutoDepositGold: deferring to Warband Miser")
        return
    end

    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()

    -- Calculate how much gold we need to keep
    local feesCopper = self:CalculateRequiredGold(charKey, currentRealm)
    -- Add 10% buffer for rounding + the user's configured buffer
    local bufferCopper = (ns.db.settings.goldBuffer or 0) * 10000
    local keepCopper = math.max(10000, math.ceil(feesCopper * 1.1)) + bufferCopper

    local playerCopper = GetMoney()
    if playerCopper <= keepCopper then
        ns:PrintDebug("AutoDepositGold: nothing to deposit — playerCopper="
            .. playerCopper .. " <= keepCopper=" .. keepCopper)
        return
    end

    local excessCopper = playerCopper - keepCopper
    -- Round down to whole gold
    excessCopper = math.floor(excessCopper / 10000) * 10000
    if excessCopper <= 0 then
        ns:PrintDebug("AutoDepositGold: excessCopper <= 0 after rounding")
        return
    end

    -- Ensure BankFrame is on the warbank panel before calling C_Bank APIs.
    -- C_Bank.CanDepositMoney(Enum.BankType.Account) returns false when the
    -- active panel is the character bank, even though the warbank itself is
    -- accessible. Phase 6a removed the side-effect probe in Scanner that
    -- used to keep the panel warm, so we explicitly switch here.
    if ns.BankQueue and ns.BankQueue.SetBankPanelType and Enum and Enum.BankType then
        ns.BankQueue.SetBankPanelType(Enum.BankType.Account)
    end

    -- Check permission
    local ok, canDeposit = pcall(C_Bank.CanDepositMoney, Enum.BankType.Account)
    if not ok or not canDeposit then
        ns:Print(ns.COLORS.YELLOW .. "Cannot deposit to warbank|r — bank panel may not be on the warband tab. Click the warbank tab and try again.")
        ns:PrintDebug("AutoDepositGold: CanDepositMoney returned false (ok="
            .. tostring(ok) .. ", canDeposit=" .. tostring(canDeposit) .. ")")
        return 0
    end

    local ok2, err = pcall(C_Bank.DepositMoney, Enum.BankType.Account, excessCopper)
    if ok2 then
        local depositGold = math.floor(excessCopper / 10000)
        local keptGold = math.floor(keepCopper / 10000)
        ns:Print(ns.COLORS.GREEN .. "Deposited " .. depositGold .. "g|r to warbank" ..
            " (kept " .. keptGold .. "g for fees + buffer)")
        return excessCopper
    else
        ns:PrintDebug("Failed to deposit gold: " .. tostring(err))
        return 0
    end
end

--------------------------
-- Warbank Auto-Deposit
--------------------------

function Tracker:AutoDepositToWarbank(onComplete)
    if not ns.db or not ns:GetCharSetting(ns:GetCharKey(), "autoDepositWarbank") then
        if onComplete then onComplete({}, 0) end
        return
    end

    local charKey = ns:GetCharKey()
    local todoList = ns.TodoList and ns.TodoList:GetCurrentList()
    if not todoList or not todoList.tasks then
        if onComplete then onComplete({}, 0) end
        return
    end

    -- Find items this character needs to deposit for other characters
    local depositTasks = {}
    for _, task in ipairs(todoList.tasks) do
        if task.status == "pending" and task.depositFrom == charKey
            and task.assignedChar ~= charKey then
            table.insert(depositTasks, task)
        end
    end

    if #depositTasks == 0 then
        if onComplete then onComplete({}, 0) end
        return
    end

    -- Exclude items the current character also needs for posting
    local myPostingKeys = {}
    local myTasks = ns.TodoList:GetCharacterTasks(charKey)
    for _, task in ipairs(myTasks) do
        if task.item.itemKey then
            myPostingKeys[task.item.itemKey] = true
        end
    end

    -- Find items in bags matching deposit tasks. Iterate ALL_PLAYER_BAGS
    -- (not INVENTORY_BAGS) so reagent-bag items in slot 5 are matched —
    -- BuildDepositOps already iterates ALL_PLAYER_BAGS, so the popup can
    -- list a deposit that lives in the reagent bag, and AutoDepositToWarbank
    -- must scan the same bag set or it will silently skip those moves.
    local moves = {} -- { bag, slot, name }
    local depositMatched = {} -- task -> true

    for _, bagIndex in ipairs(ns.ALL_PLAYER_BAGS) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    -- Skip soulbound items — BoP (1) and Quest (4) can't go to warbank.
                    -- BtW/WuE items show as bound but CAN move; only filter true soulbound.
                    -- If bind type can't be determined (async GetItemInfo), assume soulbound
                    -- to avoid stalling on failed warbank deposits.
                    local skipBound = false
                    if info.isBound then
                        local okBind, _, _, _, _, _, _, _, _, _, _, _, _, _, bt =
                            pcall(C_Item.GetItemInfo, info.hyperlink)
                        if not okBind or not bt then
                            skipBound = true  -- unknown bind type, assume soulbound
                        elseif bt ~= 7 and bt ~= 8 then
                            skipBound = true  -- Only BtA (7) / BtW (8) can move when bound
                        end
                    end
                    if not skipBound then
                        local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                        if itemID then
                            local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                            -- Skip items the current character needs for posting
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
                                            table.insert(moves, { bag = bagIndex, slot = slot, name = task.name or "?" })
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

    if #moves == 0 then
        if onComplete then onComplete({}, 0) end
        return
    end

    -- Build queue operations — destinations found dynamically by the processor
    local ops = {}
    for _, m in ipairs(moves) do
        table.insert(ops, {
            op = "deposit",
            srcBag = m.bag,
            srcSlot = m.slot,
            name = m.name,
            destType = "warbank",
        })
    end

    ns.BankQueue:Process(ops, "Depositing to warbank...", function(successNames, errorCount, deferredNames)
        local deferredCount = deferredNames and #deferredNames or 0
        if #successNames > 0 then
            if errorCount == 0 and deferredCount == 0 then
                ns:Print(ns.COLORS.CYAN .. "Deposited " .. #successNames ..
                    " item(s) to warbank:|r " .. table.concat(successNames, ", "))
            else
                ns:Print(ns.COLORS.CYAN .. "Deposited " .. #successNames ..
                    " of " .. #ops .. " item(s) to warbank:|r " .. table.concat(successNames, ", "))
            end
        end
        if errorCount > 0 then
            ns:Print(ns.COLORS.YELLOW .. errorCount .. " item(s) failed to deposit. Try opening your bank again.|r")
        end
        if deferredCount > 0 then
            ns:Print(ns.COLORS.YELLOW .. deferredCount ..
                " item(s) deferred — warbank has no accepting slot.|r " ..
                "Free up space and try again: " .. table.concat(deferredNames, ", "))
        end
        C_Timer.After(1, function()
            if ns.Scanner then
                ns.Scanner:ScanCurrentCharacter()
                ns.Scanner:ScanBank()
                ns.Scanner:ScanWarbank()
            end
            if ns.TodoList and ns.TodoList.RefreshLocations then
                ns.TodoList:RefreshLocations()
            end
            if ns.TodoList and ns.TodoList.RefreshTaskSteps then
                ns.TodoList:RefreshTaskSteps()
            end
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
            if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
            if onComplete then onComplete(successNames, errorCount) end
        end)
    end)
end

--------------------------
-- Deposit All Extra Items
--------------------------

-- Deposit all bag items NOT needed by the current character's tasks.
-- Prioritizes warbank, falls back to personal bank.
-- Requires autoDepositAll setting enabled.
--
-- onComplete(successNames, errorCount) — fires after the queue settles, even
-- on early-return paths. The popup chain awaits this so progress reports
-- reflect actual moves, not optimistic counts.
function Tracker:AutoDepositExtraItems(onComplete)
    if not ns.db or not ns:GetCharSetting(ns:GetCharKey(), "autoDepositAll") then
        if onComplete then onComplete({}, 0) end
        return
    end

    local charKey = ns:GetCharKey()

    -- Build set of items the current character needs in bags for tasks
    local keepKeys = {}  -- itemKey -> qty needed
    local keepNames = {} -- lowercase name -> qty needed
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

    -- Items to never deposit (keep in bags always)
    local KEEP_ITEM_IDS = { [6948] = true } -- Hearthstone

    -- Scan bags for items to deposit (everything not in keepKeys/keepNames)
    -- Split into warbank-eligible and bank-only (soulbound items can't go to warbank)
    local warbankMoves = {} -- { bag, slot, name } — can go to warbank or bank
    local bankOnlyMoves = {} -- { bag, slot, name } — soulbound, bank only
    local consumedKeys = {}  -- itemKey -> qty consumed by keep
    local consumedNames = {} -- lname -> qty consumed by keep

    for _, bagIndex in ipairs(ns.INVENTORY_BAGS) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        local numID = tonumber(itemID) or tonumber((itemID:gsub(";.*", "")))

                        -- Skip items that should never be deposited
                        if KEEP_ITEM_IDS[numID] then
                            -- Hearthstone etc — always keep in bags
                        else
                            local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                            local stackCount = info.stackCount or 1

                            -- Check if this item should be kept for tasks
                            local shouldKeep = false
                            local neededByKey = keepKeys[key] or 0
                            local usedByKey = consumedKeys[key] or 0
                            if neededByKey > usedByKey then
                                consumedKeys[key] = usedByKey + stackCount
                                shouldKeep = true
                            else
                                -- Name fallback
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
                                local moveEntry = {
                                    bag = bagIndex,
                                    slot = slot,
                                    name = itemName or ("Item " .. key),
                                }
                                -- Check bind type: BoP (1) and Quest (4) can't go to warbank.
                                -- If bind type unknown (async GetItemInfo), assume soulbound.
                                local isSoulbound = false
                                if info.isBound then
                                    local ok3, _, _, _, _, _, _, _, _, _, _, _, _, _, bindType =
                                        pcall(C_Item.GetItemInfo, info.hyperlink)
                                    if not ok3 or not bindType then
                                        isSoulbound = true  -- unknown, assume soulbound
                                    elseif bindType ~= 7 and bindType ~= 8 then
                                        isSoulbound = true  -- Only BtA (7) / BtW (8) can move when bound
                                    end
                                end
                                if isSoulbound then
                                    table.insert(bankOnlyMoves, moveEntry)
                                else
                                    table.insert(warbankMoves, moveEntry)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #warbankMoves == 0 and #bankOnlyMoves == 0 then
        if onComplete then onComplete({}, 0) end
        return
    end

    -- Runtime interrupt: if the known warbank free-slot count can't absorb
    -- what autoDepositAll wants to push into it, trim the warbank portion
    -- of the batch to what fits and warn the user. Bank-only (soulbound)
    -- moves are unaffected. This is the "constrained runtime" escape
    -- hatch the scheduling model requests — autoDepositAll isn't part of
    -- the at-generation-time budget, so we guard it here.
    if ns.db.warbank and type(ns.db.warbank.freeSlots) == "number"
        and #warbankMoves > 0 then
        local freeSlots = ns.db.warbank.freeSlots
        if freeSlots <= 0 then
            ns:Print(ns.COLORS.ORANGE .. "Warbank is full|r — deposit-all skipped for warbank items. " ..
                "Consider pausing Deposit All until space opens up.")
            warbankMoves = {}
        elseif #warbankMoves > freeSlots then
            local skipped = #warbankMoves - freeSlots
            ns:Print(ns.COLORS.ORANGE .. "Warbank nearly full|r — depositing " ..
                freeSlots .. " of " .. (#warbankMoves + skipped) ..
                " extras. " .. skipped .. " held back. " ..
                "Consider pausing Deposit All.")
            -- Keep only the first freeSlots entries; stack-merges may still
            -- succeed for the rest at runtime, but we don't rely on that.
            local trimmed = {}
            for i = 1, freeSlots do trimmed[i] = warbankMoves[i] end
            warbankMoves = trimmed
        end
    end

    if #warbankMoves == 0 and #bankOnlyMoves == 0 then
        if onComplete then onComplete({}, 0) end
        return
    end

    -- Build queue operations with appropriate destination types
    -- Non-soulbound: "any" (warbank first, bank fallback)
    -- Soulbound: "bank" only
    local ops = {}
    for _, m in ipairs(warbankMoves) do
        table.insert(ops, {
            op = "deposit",
            srcBag = m.bag,
            srcSlot = m.slot,
            name = m.name,
            destType = "any",
        })
    end
    for _, m in ipairs(bankOnlyMoves) do
        table.insert(ops, {
            op = "deposit",
            srcBag = m.bag,
            srcSlot = m.slot,
            name = m.name,
            destType = "bank",
        })
    end

    ns.BankQueue:Process(ops, "Depositing extras...", function(successNames, errorCount, deferredNames)
        local deferredCount = deferredNames and #deferredNames or 0
        if #successNames > 0 then
            ns:Print(ns.COLORS.CYAN .. "Deposited " .. #successNames ..
                " extra item(s) to warbank/bank:|r " ..
                table.concat(successNames, ", "))
        end
        if errorCount > 0 then
            ns:Print(ns.COLORS.YELLOW .. errorCount ..
                " item(s) failed to deposit.|r")
        end
        if deferredCount > 0 then
            ns:Print(ns.COLORS.YELLOW .. deferredCount ..
                " item(s) deferred — no accepting slot.|r")
        end
        C_Timer.After(1, function()
            if ns.Scanner then
                ns.Scanner:ScanCurrentCharacter()
                ns.Scanner:ScanBank()
                ns.Scanner:ScanWarbank()
            end
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
            if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
            if onComplete then onComplete(successNames, errorCount) end
        end)
    end)
end
