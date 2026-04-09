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
local function CountInBags(queueItem)
    local total = 0
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
                    end
                end
            end
        end
    end
    return total
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

    local todoPosted = {}
    for taskIdx, snap in pairs(preTodoSnapshot) do
        if snap.todoItem.status == "pending" or snap.todoItem.status == "skipped" then
            local curQty = CountInBags(snap.todoItem)
            if curQty < snap.qty then
                -- Cap count at task's own quantity to prevent inflation
                -- when multiple tasks share the same item type
                local count = math.min(snap.qty - curQty, snap.todoItem.quantity or 1)
                table.insert(todoPosted, {taskIdx = taskIdx, item = snap.todoItem, count = count})
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
        ns.TodoList:MoveTaskToLog(p.taskIdx, nil, nil, p.count)
    end

    if #todoPosted > 0 then
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    end

    SnapshotBags()
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
    local isAuto = ns.db and ns:GetCharSetting(charKey, "autoPullBank")

    -- Collect pull operations (reuse AutoPullFromBank's logic but don't execute)
    local pullOps = Tracker:BuildPullOps()
    local depositOps = Tracker:BuildDepositOps()
    -- Build exclude set from deposit ops so extras don't duplicate them
    local depositSlots = {}
    for _, op in ipairs(depositOps) do
        depositSlots[op.srcBag .. ":" .. op.srcSlot] = true
    end
    local extraOps = Tracker:BuildExtraDepositOps(depositSlots)

    -- Calculate gold operations
    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
    local goldWithdraw, goldDeposit = 0, 0

    -- Estimate withdrawal need (show in popup regardless of auto setting)
    if ns.db then
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
        if hasTasks then
            local totalFees = Tracker:CalculateRequiredGold(charKey, currentRealm)
            local playerCopper = GetMoney()
            local needed = math.max(10000, math.ceil(totalFees * 1.1))
            if playerCopper < needed then
                goldWithdraw = needed - playerCopper
            end

            -- Estimate deposit excess
            local bufferCopper = (ns.db.settings.goldBuffer or 0) * 10000
            local keepCopper = math.max(10000, math.ceil(totalFees * 1.1)) + bufferCopper
            if playerCopper > keepCopper then
                local excess = math.floor((playerCopper - keepCopper) / 10000) * 10000
                if excess > 0 then goldDeposit = excess end
            end
        end
    end

    local hasPulls = pullOps and #pullOps > 0
    local hasDeposits = depositOps and #depositOps > 0
    local hasExtras = extraOps and #extraOps > 0
    local hasGold = goldWithdraw > 0 or goldDeposit > 0

    ns:PrintDebug("Bank popup: " .. #pullOps .. " pulls, " .. #depositOps .. " deposits, " ..
        #extraOps .. " extras, withdraw=" .. goldWithdraw .. " deposit=" .. goldDeposit)

    if not hasPulls and not hasDeposits and not hasExtras and not hasGold then
        ns:PrintDebug("Bank popup: nothing to do")
        return
    end

    local function ExecuteAllOps()
        -- Phase 1: Pull all items from bank (batched)
        local function DoPulls(callback)
            if not hasPulls or #pullOps == 0 then callback() return end
            if ns.UI then ns.UI:BankOpProgress(0, 0, "Pulling") end
            ns.BankQueue:ProcessSync(pullOps, "Pulling from bank...", function(successNames, errorCount)
                if #successNames > 0 then
                    ns:Print("Pulled: " .. table.concat(successNames, ", "))
                end
                if errorCount > 0 then
                    ns:Print(ns.COLORS.YELLOW .. errorCount .. " pull(s) failed|r")
                end
                if ns.UI then ns.UI:BankOpProgress(#successNames, errorCount, "Pulling", successNames) end
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

        -- Phase 3: Deposits to warbank
        local function DoDeposits(callback)
            if not hasDeposits and not hasExtras then callback() return end
            if ns.UI then ns.UI:BankOpProgress(0, 0, "Depositing") end
            Tracker:AutoDepositToWarbank(function()
                local depCount = #depositOps
                if ns.UI and depCount > 0 then ns.UI:BankOpProgress(depCount, 0, "Depositing") end
                Tracker:AutoDepositExtraItems()
                local extCount = #extraOps
                if ns.UI and extCount > 0 then ns.UI:BankOpProgress(extCount, 0, "Depositing") end
                callback()
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

    -- Initialize unified progress tracking (total = pulls + deposits + extras + gold ops)
    local totalOps = #pullOps + #depositOps + #extraOps
    if goldWithdraw > 0 then totalOps = totalOps + 1 end
    if goldDeposit > 0 then totalOps = totalOps + 1 end
    if not ns.UI:IsBankExecuting() then
        ns.UI:BeginBankExecution(totalOps)
    end

    ns.UI:ShowBankPopup({
        pulls = pullOps,
        deposits = depositOps,
        extras = extraOps,
        goldWithdraw = goldWithdraw,
        goldDeposit = goldDeposit,
        isAuto = isAuto,
    }, ExecuteAllOps)
end

-- Build pull operation list without executing.
-- Returns array of { op="pull", srcBag, srcSlot, name, icon, quantity } or empty table.
function Tracker:BuildPullOps()
    if not ns.db then return {} end

    local charKey = ns:GetCharKey()
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
function Tracker:BuildExtraDepositOps(excludeSlots)
    if not ns.db then return {} end

    local charKey = ns:GetCharKey()
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

    -- Reagents/materials are not tracked for sales or to-dos (not
    -- cross-region), so by default we leave them on the character. The user
    -- can opt in to sweep them into the warbank via depositIncludeReagents.
    local includeReagents = ns.db and ns.db.settings.depositIncludeReagents

    for _, bagIndex in ipairs(ns.ALL_PLAYER_BAGS) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    local slotKey = bagIndex .. ":" .. slot
                    -- Skip soulbound items entirely (matches BuildDepositOps).
                    -- Warbound items (bind types 7 and 8) are still allowed —
                    -- they can go to the warbank.
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
                    -- Skip reagents/materials (class Tradegoods) unless the
                    -- user opted in. Items in the dedicated reagent bag are
                    -- always reagents by definition; items in regular bags
                    -- are checked by item class.
                    local skipReagent = false
                    if not includeReagents then
                        if bagIndex == ns.REAGENT_BAG then
                            skipReagent = true
                        else
                            local _, _, _, _, _, _, _, _, _, _, _, classID =
                                GetItemInfo(info.hyperlink)
                            if classID == Enum.ItemClass.Tradegoods then
                                skipReagent = true
                            end
                        end
                    end
                    if not excludeSlots[slotKey] and not skipBound and not skipReagent then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        local numID = tonumber(itemID) or tonumber((itemID:gsub(";.*", "")))
                        if not KEEP_ITEM_IDS[numID] then
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
                                -- Soulbound items were already filtered out
                                -- by the skipBound check above. Anything that
                                -- reaches here is either unbound or warbound,
                                -- so warbank is always a valid destination.
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
                        end
                    end
                end
                end -- excludeSlots check
            end
        end
    end

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
        SnapshotBags()

        -- Refresh task steps (items pulled from bank may now be ready to post)
        if ns.TodoList and ns.TodoList.RefreshTaskSteps then
            ns.TodoList:RefreshTaskSteps()
        end

        -- TSM threshold check: skip/reassign items that can't be posted
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

        -- Request owned auctions to check for already-listed items
        if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then
            C_AuctionHouse.QueryOwnedAuctions({})
        end

        -- Refresh UI after AH opens (task steps may have changed)
        if ns.UI then
            if ns.UI.RefreshMini then ns.UI:RefreshMini() end
            if ns.UI.Refresh then ns.UI:Refresh() end
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
        -- BAG_UPDATE_DELAYED can fire several times during AH/mailbox activity,
        -- and the chain it kicks off (Scanner + RefreshLocations + RefreshTaskSteps
        -- + UI:Refresh + RefreshMini + Sync delta emit) is expensive enough that
        -- running it 5x in a second was a major source of micro-lag.
        if Tracker._bagUpdatePending then return end
        Tracker._bagUpdatePending = true
        C_Timer.After(0.5, function()
            Tracker._bagUpdatePending = false
            if (ns.BankQueue and ns.BankQueue.processing) then return end
            if ns.Scanner then ns.Scanner:ScanCurrentCharacter() end
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
            -- Delay slightly so AUCTION_CANCELED (which fires after) can set the counter first
            C_Timer.After(0.3, function()
                if Tracker._isAHOpen then
                    Tracker:CheckOwnedAuctions()
                    Tracker:UpdateLogExpiry()
                end
            end)
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

-- Non-commodity buyout: PlaceBid with bidAmount matching buyout = purchase
if C_AuctionHouse and C_AuctionHouse.PlaceBid then
    hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, bidAmount)
        if not ns.TodoList or not ns.TodoList.OnItemPurchased then return end
        -- Look up the auction info to get the item
        local info = C_AuctionHouse.GetAuctionInfoByID(auctionID)
        if info and info.itemKey then
            local itemID = info.itemKey.itemID
            local itemName
            if itemID then
                local ok, n = pcall(C_Item.GetItemInfo, itemID)
                itemName = ok and n or nil
            end
            ns.TodoList:OnItemPurchased(itemID, itemName)
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
        ns.TodoList:OnItemPurchased(itemID, itemName)
    end)
end
