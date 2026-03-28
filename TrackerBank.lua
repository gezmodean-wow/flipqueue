-- TrackerBank.lua
-- Bank auto-pull and warbank gold withdrawal for to-do list items
local addonName, ns = ...

local Tracker = ns.Tracker

--------------------------
-- Bank Auto-Pull
--------------------------

local PULL_TIMEOUT = 5  -- seconds to wait for locks before giving up on a batch

function Tracker:AutoPullFromBank(onComplete)
    if not ns.db or not ns:GetCharSetting(ns:GetCharKey(), "autoPullBank") then
        if onComplete then onComplete() end
        return
    end

    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
    local sellQtyMode = ns.db.settings.sellQtyMode or "tsm"
    local tsmEnabled = sellQtyMode == "tsm" and ns.TSM and ns.TSM:IsEnabled()
    local defaultQty = ns.db.settings.defaultSellQty or 1

    -- Build needed list from the active to-do list
    local needed = {} -- item -> qty still needed from bank

    if ns.TodoList and ns.TodoList:GetCurrentList() then
        local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(todoTasks) do
            local item = task.item
            if item.action == "buy" then
                -- Buy tasks are purchased from AH, not pulled from bank
            elseif ns:RealmMatches(item.targetRealm or "", currentRealm) then
                local targetQty = math.max(item.quantity or 1, defaultQty)
                if tsmEnabled then
                    local op = ns.TSM:GetItemAuctioningOp(item.itemKey)
                    if op and op.postCap then
                        local tsmQty = tonumber(op.postCap)
                        if tsmQty and tsmQty > 0 then targetQty = tsmQty end
                    end
                end
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
        if onComplete then onComplete() end
        return
    end

    local allBankTabs = {}
    for _, b in ipairs(ns:GetEnabledBankTabs()) do table.insert(allBankTabs, b) end
    for _, b in ipairs(ns:GetEnabledWarbankTabs()) do table.insert(allBankTabs, b) end

    if not next(needed) then
        if onComplete then onComplete() end
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
        if onComplete then onComplete() end
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
        if onComplete then onComplete() end
        return
    end

    if freeBagSlots < #moves then
        ns:Print(ns.COLORS.YELLOW .. "Only " .. freeBagSlots .. " free bag slot(s) — pulling " ..
            freeBagSlots .. " of " .. #moves .. " item(s) from bank.|r")
    end

    -- Event-driven batch execution
    -- Pattern from Baganator: move a small batch, wait for ITEM_LOCK_CHANGED
    -- to signal the server has processed the moves, then continue
    local totalMoves = math.min(#moves, freeBagSlots)
    local moveIndex = 1
    local pulledNames = {}
    local pullErrors = 0
    local aborted = false
    Tracker._pullInProgress = true

    local listener = CreateFrame("Frame")

    local function Cleanup()
        listener:UnregisterAllEvents()
        listener:SetScript("OnEvent", nil)
        Tracker._pullInProgress = false
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
            if ns.TodoList and ns.TodoList.RefreshTaskSteps then
                ns.TodoList:RefreshTaskSteps()
            end
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
            if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
            if onComplete then onComplete() end
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
                local ok3, err = pcall(C_Container.UseContainerItem, move.bag, move.slot)
                if ok3 then
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

    -- Check permission
    local ok6, canWithdraw = pcall(C_Bank.CanWithdrawMoney, Enum.BankType.Account)
    if not ok6 or not canWithdraw then
        ns:Print(ns.COLORS.YELLOW .. "Cannot withdraw from warbank (permission denied).|r")
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
    else
        ns:Print(ns.COLORS.RED .. "Failed to withdraw: " .. tostring(err) .. "|r")
    end
end

--------------------------
-- Warbank Auto-Deposit
--------------------------

function Tracker:AutoDepositToWarbank(onComplete)
    if not ns.db or not ns:GetCharSetting(ns:GetCharKey(), "autoDepositWarbank") then
        if onComplete then onComplete() end
        return
    end

    local charKey = ns:GetCharKey()
    local todoList = ns.TodoList and ns.TodoList:GetCurrentList()
    if not todoList or not todoList.tasks then
        if onComplete then onComplete() end
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
        if onComplete then onComplete() end
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

    -- Find items in bags matching deposit tasks
    local moves = {} -- { bag, slot, name }
    local depositMatched = {} -- task -> true

    for _, bagIndex in ipairs(ns.INVENTORY_BAGS) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    -- Skip soulbound items — BoP (1) and Quest (4) can't go to warbank.
                    -- BtW/WuE items show as bound but CAN move; only filter true soulbound.
                    local skipBound = false
                    if info.isBound then
                        local okBind, _, _, _, _, _, _, _, _, _, _, _, _, _, bt =
                            pcall(C_Item.GetItemInfo, info.hyperlink)
                        if okBind and bt and (bt == 1 or bt == 4) then
                            skipBound = true
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
        if onComplete then onComplete() end
        return
    end

    -- Find empty warbank slots
    local emptySlots = {}
    for _, wbBag in ipairs(ns:GetEnabledWarbankTabs()) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, wbBag)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, wbBag, slot)
                if ok2 and not info then
                    table.insert(emptySlots, { bag = wbBag, slot = slot })
                end
            end
        end
    end

    if #emptySlots == 0 then
        ns:Print(ns.COLORS.RED .. "Warbank is full!|r Cannot deposit " .. #moves .. " item(s).")
        if onComplete then onComplete() end
        return
    end

    if #emptySlots < #moves then
        ns:Print(ns.COLORS.YELLOW .. "Only " .. #emptySlots .. " free warbank slot(s) — depositing " ..
            #emptySlots .. " of " .. #moves .. " item(s).|r")
    end

    -- Event-driven batch execution (same pattern as AutoPullFromBank)
    local totalMoves = math.min(#moves, #emptySlots)
    local depositedNames = {}
    local depositErrors = 0
    local moveIndex = 1
    local aborted = false
    Tracker._depositInProgress = true

    local listener = CreateFrame("Frame")

    local function Cleanup()
        listener:UnregisterAllEvents()
        listener:SetScript("OnEvent", nil)
        Tracker._depositInProgress = false
    end

    local function FinishDeposit()
        Cleanup()
        if #depositedNames > 0 then
            if #depositedNames == totalMoves then
                ns:Print(ns.COLORS.CYAN .. "Deposited " .. #depositedNames ..
                    " item(s) to warbank:|r " .. table.concat(depositedNames, ", "))
            else
                ns:Print(ns.COLORS.CYAN .. "Deposited " .. #depositedNames ..
                    " of " .. totalMoves .. " item(s) to warbank:|r " .. table.concat(depositedNames, ", "))
            end
        end
        if depositErrors > 0 then
            ns:Print(ns.COLORS.YELLOW .. depositErrors .. " item(s) failed to deposit. Try opening your bank again.|r")
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
            if onComplete then onComplete() end
        end)
    end

    local function ExecuteNextBatch()
        if aborted or moveIndex > totalMoves then
            FinishDeposit()
            return
        end

        local batchSize = ns.db and ns.db.settings.pullBatchSize or 5
        local batchEnd = math.min(moveIndex + batchSize - 1, totalMoves)
        local batchMoved = 0

        for i = moveIndex, batchEnd do
            local src = moves[i]
            local dest = emptySlots[i]

            -- Check if source slot is locked before attempting
            local okLock, srcInfo = pcall(C_Container.GetContainerItemInfo, src.bag, src.slot)
            if okLock and srcInfo and srcInfo.isLocked then
                depositErrors = depositErrors + 1
            else
                pcall(ClearCursor)
                local ok1 = pcall(C_Container.PickupContainerItem, src.bag, src.slot)
                if ok1 then
                    local ok2 = pcall(C_Container.PickupContainerItem, dest.bag, dest.slot)
                    if ok2 then
                        table.insert(depositedNames, src.name)
                        batchMoved = batchMoved + 1
                    else
                        pcall(ClearCursor)
                        depositErrors = depositErrors + 1
                    end
                else
                    depositErrors = depositErrors + 1
                end
            end
        end

        moveIndex = batchEnd + 1

        if moveIndex > totalMoves then
            C_Timer.After(0.3, FinishDeposit)
        elseif batchMoved > 0 then
            local waitingForUnlock = true
            listener:RegisterEvent("ITEM_LOCK_CHANGED")
            listener:RegisterEvent("UI_ERROR_MESSAGE")
            listener:SetScript("OnEvent", function(_, event, errorType, message)
                if event == "UI_ERROR_MESSAGE" then
                    if message == ERR_INTERNAL_BAG_ERROR
                        or (message and message:find("Internal Bag Error")) then
                        aborted = true
                        depositErrors = depositErrors + 1
                        listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                        listener:UnregisterEvent("UI_ERROR_MESSAGE")
                        FinishDeposit()
                        return
                    elseif message == ERR_INV_FULL
                        or (message and message:find("Inventory is full")) then
                        aborted = true
                        listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                        listener:UnregisterEvent("UI_ERROR_MESSAGE")
                        FinishDeposit()
                        return
                    end
                elseif event == "ITEM_LOCK_CHANGED" and waitingForUnlock then
                    waitingForUnlock = false
                    listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                    listener:UnregisterEvent("UI_ERROR_MESSAGE")
                    C_Timer.After(0.1, ExecuteNextBatch)
                end
            end)

            C_Timer.After(PULL_TIMEOUT, function()
                if waitingForUnlock then
                    waitingForUnlock = false
                    listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                    listener:UnregisterEvent("UI_ERROR_MESSAGE")
                    ExecuteNextBatch()
                end
            end)
        else
            C_Timer.After(0.5, ExecuteNextBatch)
        end
    end

    ns:PrintDebug("Depositing " .. totalMoves .. " item(s) to warbank...")
    ExecuteNextBatch()
end

--------------------------
-- Deposit All Extra Items
--------------------------

-- Deposit all bag items NOT needed by the current character's tasks.
-- Prioritizes warbank, falls back to personal bank.
-- Requires autoDepositAll setting enabled.
function Tracker:AutoDepositExtraItems()
    if not ns.db or not ns:GetCharSetting(ns:GetCharKey(), "autoDepositAll") then return end

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
                                -- Check bind type: BoP (1) and Quest (4) can't go to warbank
                                local isSoulbound = false
                                if info.isBound then
                                    local ok3, _, _, _, _, _, _, _, _, _, _, _, _, bindType =
                                        pcall(C_Item.GetItemInfo, info.hyperlink)
                                    if ok3 and (bindType == 1 or bindType == 4) then
                                        isSoulbound = true
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

    if #warbankMoves == 0 and #bankOnlyMoves == 0 then return end

    -- Find empty slots: warbank and personal bank separately
    local warbankEmpty = {}
    for _, wbBag in ipairs(ns:GetEnabledWarbankTabs()) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, wbBag)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, wbBag, slot)
                if ok2 and not info then
                    table.insert(warbankEmpty, { bag = wbBag, slot = slot })
                end
            end
        end
    end

    local bankEmpty = {}
    for _, bankBag in ipairs(ns:GetEnabledBankTabs()) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bankBag)
        if ok and numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bankBag, slot)
                if ok2 and not info then
                    table.insert(bankEmpty, { bag = bankBag, slot = slot })
                end
            end
        end
    end

    -- Check for bank access
    if #warbankEmpty == 0 and #bankEmpty == 0 then
        local hasBankAccess = false
        for _, bankBag in ipairs(ns.BANK_TABS) do
            local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bankBag)
            if ok and numSlots and numSlots > 0 then
                hasBankAccess = true
                break
            end
        end
        if not hasBankAccess then
            ns:PrintError("No bank slots available — purchase bank tabs to deposit items.")
        else
            ns:Print(ns.COLORS.YELLOW .. "Warbank and bank are full!|r Cannot deposit " ..
                (#warbankMoves + #bankOnlyMoves) .. " extra item(s).")
        end
        return
    end

    -- Pair moves with destination slots:
    -- Warbank-eligible items → warbank first, overflow to bank
    -- Bank-only items (soulbound) → bank only
    local moves = {}     -- { bag, slot, name }
    local emptySlots = {} -- paired destinations
    local wbIdx, bkIdx = 1, 1

    for _, m in ipairs(warbankMoves) do
        if wbIdx <= #warbankEmpty then
            table.insert(moves, m)
            table.insert(emptySlots, warbankEmpty[wbIdx])
            wbIdx = wbIdx + 1
        elseif bkIdx <= #bankEmpty then
            table.insert(moves, m)
            table.insert(emptySlots, bankEmpty[bkIdx])
            bkIdx = bkIdx + 1
        end
    end
    for _, m in ipairs(bankOnlyMoves) do
        if bkIdx <= #bankEmpty then
            table.insert(moves, m)
            table.insert(emptySlots, bankEmpty[bkIdx])
            bkIdx = bkIdx + 1
        end
    end

    if #moves == 0 then
        local skipped = #warbankMoves + #bankOnlyMoves
        if skipped > 0 then
            ns:Print(ns.COLORS.YELLOW .. "Not enough free slots — " .. skipped .. " item(s) remain in bags.|r")
        end
        return
    end

    local totalRequested = #warbankMoves + #bankOnlyMoves
    if #moves < totalRequested then
        ns:Print(ns.COLORS.YELLOW .. "Only " .. #moves .. " free slot(s) — depositing " ..
            #moves .. " of " .. totalRequested .. " extra item(s).|r")
    end

    -- Execute deposits using same batch pattern as AutoDepositToWarbank
    local totalMoves = math.min(#moves, #emptySlots)
    local depositedNames = {}
    local depositErrors = 0
    local moveIndex = 1
    local aborted = false
    Tracker._depositInProgress = true

    local listener = CreateFrame("Frame")

    local function Cleanup()
        listener:UnregisterAllEvents()
        listener:SetScript("OnEvent", nil)
        Tracker._depositInProgress = false
    end

    local function FinishDeposit()
        Cleanup()
        if #depositedNames > 0 then
            local destLabel = #warbankEmpty > 0 and "warbank/bank" or "bank"
            ns:Print(ns.COLORS.CYAN .. "Deposited " .. #depositedNames ..
                " extra item(s) to " .. destLabel .. ":|r " ..
                table.concat(depositedNames, ", "))
        end
        if depositErrors > 0 then
            ns:Print(ns.COLORS.YELLOW .. depositErrors ..
                " item(s) failed to deposit.|r")
        end
        C_Timer.After(1, function()
            if ns.Scanner then
                ns.Scanner:ScanCurrentCharacter()
                ns.Scanner:ScanBank()
                ns.Scanner:ScanWarbank()
            end
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
            if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
        end)
    end

    local function ExecuteNextBatch()
        if aborted or moveIndex > totalMoves then
            FinishDeposit()
            return
        end

        local batchSize = ns.db and ns.db.settings.pullBatchSize or 5
        local batchEnd = math.min(moveIndex + batchSize - 1, totalMoves)
        local batchMoved = 0

        for i = moveIndex, batchEnd do
            local src = moves[i]
            local dest = emptySlots[i]

            local okLock, srcInfo = pcall(C_Container.GetContainerItemInfo, src.bag, src.slot)
            if okLock and srcInfo and srcInfo.isLocked then
                depositErrors = depositErrors + 1
            else
                pcall(ClearCursor)
                local ok1 = pcall(C_Container.PickupContainerItem, src.bag, src.slot)
                if ok1 then
                    local ok2 = pcall(C_Container.PickupContainerItem, dest.bag, dest.slot)
                    if ok2 then
                        table.insert(depositedNames, src.name)
                        batchMoved = batchMoved + 1
                    else
                        pcall(ClearCursor)
                        depositErrors = depositErrors + 1
                    end
                else
                    depositErrors = depositErrors + 1
                end
            end
        end

        moveIndex = batchEnd + 1

        if moveIndex > totalMoves then
            C_Timer.After(0.3, FinishDeposit)
        elseif batchMoved > 0 then
            local waitingForUnlock = true
            listener:RegisterEvent("ITEM_LOCK_CHANGED")
            listener:RegisterEvent("UI_ERROR_MESSAGE")
            listener:SetScript("OnEvent", function(_, event, errorType, message)
                if event == "UI_ERROR_MESSAGE" then
                    if (message and (message:find("Internal Bag Error") or message == ERR_INTERNAL_BAG_ERROR)) then
                        aborted = true
                        depositErrors = depositErrors + 1
                        listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                        listener:UnregisterEvent("UI_ERROR_MESSAGE")
                        FinishDeposit()
                        return
                    elseif (message and (message:find("Inventory is full") or message == ERR_INV_FULL)) then
                        aborted = true
                        listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                        listener:UnregisterEvent("UI_ERROR_MESSAGE")
                        FinishDeposit()
                        return
                    end
                elseif event == "ITEM_LOCK_CHANGED" and waitingForUnlock then
                    waitingForUnlock = false
                    listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                    listener:UnregisterEvent("UI_ERROR_MESSAGE")
                    C_Timer.After(0.1, ExecuteNextBatch)
                end
            end)

            C_Timer.After(PULL_TIMEOUT, function()
                if waitingForUnlock then
                    waitingForUnlock = false
                    listener:UnregisterEvent("ITEM_LOCK_CHANGED")
                    listener:UnregisterEvent("UI_ERROR_MESSAGE")
                    ExecuteNextBatch()
                end
            end)
        else
            C_Timer.After(0.5, ExecuteNextBatch)
        end
    end

    ns:PrintDebug("Depositing " .. totalMoves .. " extra item(s) to warbank/bank...")
    ExecuteNextBatch()
end
