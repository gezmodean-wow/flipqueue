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

    local todoPosted = {}
    for taskIdx, snap in pairs(preTodoSnapshot) do
        if snap.todoItem.status == "pending" then
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

        -- Mark expired/cancelled auctions as collected (user is at the AH)
        if ns.db then
            local charKey = ns:GetCharKey()
            local cleared = 0
            for _, entry in ipairs(ns.db.log) do
                if (entry.auctionStatus == "expired" or entry.auctionStatus == "cancelled")
                        and entry.charKey == charKey then
                    entry.auctionStatus = "collected"
                    cleared = cleared + 1
                end
            end
            if cleared > 0 then
                ns:Print(ns.COLORS.GREEN .. "Collected " .. cleared .. " expired/cancelled auction(s).|r")
            end
        end

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

        -- Refresh UI to clear "Check Mail" tasks
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
        if Tracker._depositInProgress or Tracker._pullInProgress then return end
        -- Rescan inventory and refresh todo locations/steps on every item movement
        C_Timer.After(0.5, function()
            if Tracker._depositInProgress or Tracker._pullInProgress then return end
            if ns.Scanner then ns.Scanner:ScanCurrentCharacter() end
            if ns.TodoList then
                if ns.TodoList.RefreshLocations then
                    ns.TodoList:RefreshLocations()
                end
                if ns.TodoList.RefreshTaskSteps then
                    ns.TodoList:RefreshTaskSteps()
                end
            end
            if ns.UI and ns.UI.mainFrame and ns.UI.mainFrame:IsShown() then
                if ns.UI.currentPage == "todo" or ns.UI.currentPage == "generator" then
                    ns.UI:Refresh()
                end
            end
        end)

    elseif event == "BANKFRAME_OPENED" then
        C_Timer.After(1, function()
            -- Scanner already scans bags/bank/warbank at 0.5s — refresh locations first
            -- so deposit tasks are resolved before auto-pull runs
            if ns.TodoList and ns.TodoList.RefreshLocations then
                ns.TodoList:RefreshLocations()
            end
            -- Pull completes async, then chain deposit + gold + task refresh
            Tracker:AutoPullFromBank(function()
                Tracker:AutoDepositToWarbank()
                -- Deposit extra non-task items (after task deposits complete)
                Tracker:AutoDepositExtraItems()
                Tracker:AutoWithdrawGold()
                -- Refresh task steps (items may now be in bags after pull/deposit)
                if ns.TodoList and ns.TodoList.RefreshTaskSteps then
                    ns.TodoList:RefreshTaskSteps()
                end
            end)
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
