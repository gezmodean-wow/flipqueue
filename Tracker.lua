-- Tracker.lua
-- Detects auction posts by monitoring bag changes while AH is open
-- Auto-pulls queued items from bank when bank frame opens
local addonName, ns = ...

local Tracker = {}
ns.Tracker = Tracker

local isAHOpen = false
local prePostSnapshot = {} -- itemKey -> quantity in bags before posting

--------------------------
-- Bag Snapshot for Post Detection
--------------------------

local function SnapshotBags()
    wipe(prePostSnapshot)
    if not ns.db then return end

    for _, queueItem in ipairs(ns.db.queue) do
        if queueItem.status == "pending" then
            prePostSnapshot[queueItem.itemKey] = 0
        end
    end

    for _, bagIndex in ipairs(ns.INVENTORY_BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bagIndex)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagIndex, slot)
            if info and info.hyperlink then
                local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                if itemID then
                    local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                    if prePostSnapshot[key] ~= nil then
                        prePostSnapshot[key] = prePostSnapshot[key] + (info.stackCount or 1)
                    end
                end
            end
        end
    end
end

local function CheckForPosts()
    if not ns.db then return end

    local currentQty = {}
    for _, bagIndex in ipairs(ns.INVENTORY_BAGS) do
        local numSlots = C_Container.GetContainerNumSlots(bagIndex)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagIndex, slot)
            if info and info.hyperlink then
                local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                if itemID then
                    local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                    if prePostSnapshot[key] ~= nil then
                        currentQty[key] = (currentQty[key] or 0) + (info.stackCount or 1)
                    end
                end
            end
        end
    end

    -- Detect decreases → item was posted
    for key, prevQty in pairs(prePostSnapshot) do
        local curQty = currentQty[key] or 0
        if curQty < prevQty then
            local posted = prevQty - curQty
            for i, queueItem in ipairs(ns.db.queue) do
                if queueItem.itemKey == key and queueItem.status == "pending" then
                    ns:Print(ns.COLORS.GREEN .. "Posted:|r " .. queueItem.name .. " (x" .. posted .. ")")
                    -- Move to log instead of just marking status
                    ns.Queue:MoveToLog(i)
                    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
                    break
                end
            end
        end
    end

    SnapshotBags()
end

--------------------------
-- Bank Auto-Pull
--------------------------

function Tracker:AutoPullFromBank()
    if not ns.db or not ns.db.settings.autoPullBank then return end

    local pulled = 0
    for _, queueItem in ipairs(ns.db.queue) do
        if queueItem.status == "pending" then
            for _, bagIndex in ipairs(ns.BANK_TABS) do
                local numSlots = C_Container.GetContainerNumSlots(bagIndex)
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bagIndex, slot)
                    if info and info.hyperlink then
                        local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                        if itemID then
                            local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                            if key == queueItem.itemKey then
                                C_Container.UseContainerItem(bagIndex, slot)
                                pulled = pulled + 1
                            end
                        end
                    end
                end
            end

            for _, bagIndex in ipairs(ns.WARBANK_TABS) do
                local numSlots = C_Container.GetContainerNumSlots(bagIndex)
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bagIndex, slot)
                    if info and info.hyperlink then
                        local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                        if itemID then
                            local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                            if key == queueItem.itemKey then
                                C_Container.UseContainerItem(bagIndex, slot)
                                pulled = pulled + 1
                            end
                        end
                    end
                end
            end
        end
    end

    if pulled > 0 then
        ns:Print("Auto-pulled " .. pulled .. " items from bank to bags.")
        C_Timer.After(1, function()
            ns.Scanner:ScanCurrentCharacter()
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        end)
    end
end

--------------------------
-- Event Handling
--------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("BANKFRAME_OPENED")

frame:SetScript("OnEvent", function(self, event)
    if event == "AUCTION_HOUSE_SHOW" then
        isAHOpen = true
        SnapshotBags()

        if ns.Queue then
            local tasks = ns.Queue:GetCharacterTasks(ns:GetCharKey())
            if tasks and #tasks > 0 then
                ns:Print(ns.COLORS.GREEN .. #tasks .. " items|r in your queue ready to post!")
            end
        end

    elseif event == "AUCTION_HOUSE_CLOSED" then
        isAHOpen = false
        wipe(prePostSnapshot)

    elseif event == "BAG_UPDATE_DELAYED" then
        if isAHOpen and next(prePostSnapshot) then
            C_Timer.After(0.3, CheckForPosts)
        end

    elseif event == "BANKFRAME_OPENED" then
        C_Timer.After(1, function()
            Tracker:AutoPullFromBank()
        end)
    end
end)
