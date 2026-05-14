-- BuyListSync.lua
-- Live sync of FlipQueue buy tasks into Auctionator shopping list(s).
--
-- Single-list mode (default): one list "FlipQueue - Buy" rebuilt to reflect
-- the current character's outstanding buy tasks. Survives empty rebuilds —
-- the empty list is the contract ("I have no buys right now").
--
-- Per-realm mode: one list per buyRealm "FlipQueue - Buy - <Realm>", any
-- realm whose slice goes empty is deleted (auctBuyListAutoDelete).
--
-- A task is "outstanding" while bag count < task.quantity. Once the player
-- has bought enough, the task drops out of the list — that is the purchase
-- detection mechanism. We never mutate task.status here; the to-do list
-- still owns task lifecycle (player is expected to mail/transfer the bought
-- items, then post on the sell character).
--
-- Triggers:
--   * AUCTION_HOUSE_SHOW (0.5s settle, mirrors ProfessionShoppingList)
--   * BAG_UPDATE_DELAYED while the AH is open (debounced 0.5s)
--   * Manual: BuyListSync:Rebuild(true) from a UI button
local addonName, ns = ...

local BuyListSync = {}
ns.BuyListSync = BuyListSync

local CALLER_ID = "FlipQueue"
local SINGLE_LIST_NAME = "FlipQueue - Buy"
local LIST_PREFIX_PER_REALM = "FlipQueue - Buy - "
local SETTLE_DELAY = 0.5

local ahOpen = false
local pendingRebuild = false
local lastPerRealmLists = {}  -- realm -> true, the lists we owned last rebuild

local function IsAuctionatorReady()
    return type(Auctionator) == "table"
        and type(Auctionator.API) == "table"
        and type(Auctionator.API.v1) == "table"
        and type(Auctionator.API.v1.CreateShoppingList) == "function"
end

-- Auctionator's only public delete is via the internal ListManager. PSL
-- uses the same path (ProfessionShoppingList/modules-old/AuctionHouse.lua:125).
local function DeleteListIfExists(name)
    if not Auctionator or not Auctionator.Shopping
        or not Auctionator.Shopping.ListManager then return end
    local mgr = Auctionator.Shopping.ListManager
    if mgr.GetIndexForName and mgr:GetIndexForName(name) and mgr.Delete then
        pcall(mgr.Delete, mgr, name)
    end
end

-- Build the 14-field Auctionator advanced-search string for one buy task.
-- Includes maxPrice (target + 0.9999g headroom so 200g matches 200g 99s 99c
-- listings — Auctionator multiplies by 10000 internally). Quality and tier
-- are opt-in: bonus-IDed gear frequently appears at a higher quality than
-- the FP-imported task records, so forcing them filters out valid listings.
local function BuildSearchString(item, opts)
    opts = opts or {}
    local name = '"' .. (item.name or "") .. '"'

    local priceGold = ns:ParseGoldValue(item.buyPrice or "")
    local priceStr = ""
    if priceGold > 0 then
        priceStr = string.format("%.4f", math.ceil(priceGold) + 0.9999)
    end

    local qualStr = ""
    if opts.includeQuality and item.quality then
        local q = tonumber(item.quality)
        if q and q >= 1 then qualStr = tostring(q) end
    end

    local tierStr = "#"  -- Auctionator's "any tier" placeholder
    if opts.includeTier and item.tier then
        local t = tonumber(item.tier)
        if t and t >= 1 then tierStr = tostring(t) end
    end

    -- Ilvl bounds: when the toggle is on, fill min+max with the task's
    -- ilvl. If the task doesn't have ilvl stored, resolve it lazily via
    -- TodoList:ResolveTaskIlvl (parses importKey :iNNN suffix or asks
    -- WoW directly). Empty fields mean "any ilvl" — legacy behavior
    -- when no ilvl is available (e.g. consumables) or the toggle is off.
    local ilvlMin, ilvlMax = "", ""
    if opts.includeIlvl then
        local iv = tonumber(item.ilvl) or 0
        if iv == 0 and ns.TodoList and ns.TodoList.ResolveTaskIlvl then
            iv = ns.TodoList:ResolveTaskIlvl(item) or 0
        end
        if iv > 0 then
            ilvlMin = tostring(iv)
            ilvlMax = tostring(iv)
        end
    end

    -- Field order: name(1);cat(2);minIlvl(3);maxIlvl(4);minLvl(5);maxLvl(6);
    --              minCLvl(7);maxCLvl(8);minPrice(9);maxPrice(10);quality(11);
    --              tier(12);exp(13);qty(14)
    -- priceStr is the maxPrice ceiling. There must be 6 separators between
    -- maxIlvl and priceStr (4 -> 10), one for each empty field minLvl ..
    -- minPrice. An earlier version dropped one and priceStr landed in
    -- minPrice's slot -- which made Auctionator filter buy >= price
    -- instead of <= price, the exact reverse of what we want.
    return name .. ";;" .. ilvlMin .. ";" .. ilvlMax .. ";;;;;;" .. priceStr .. ";" .. qualStr .. ";" .. tierStr .. ";;"
end

-- Walk active buy tasks for the current character, filter to "still needed",
-- group by realm. Returns { [realm] = { item, ... } }.
local function CollectOutstandingBuys()
    if not ns.db or not ns.TodoList then return {} end
    local charKey = ns:GetCharKey()
    local todoTasks = ns.TodoList:GetCharacterTasks(charKey) or {}

    local byRealm = {}
    local seenPerRealm = {}  -- realm -> { lowerName -> true } for de-dup within a list

    for _, task in ipairs(todoTasks) do
        local item = task.item
        if item and item.action == "buy" and (item.name or "") ~= "" then
            -- Skip tasks past the "buy" step. The AH purchase hooks in
            -- Tracker.lua advance the task to "collect" the moment the
            -- player clicks Buy, even for bid-won items that won't show
            -- up in bags until mail collection. Bag-count filtering alone
            -- would keep those in the shopping list indefinitely.
            local stepType = ns.TodoList.GetCurrentStepType
                and ns.TodoList:GetCurrentStepType(item) or nil
            local stillBuying = (not stepType) or stepType == "browse" or stepType == "buy"

            local needed = item.quantity or 1
            local inBags = (ns.Tracker and ns.Tracker._CountInBags)
                and ns.Tracker._CountInBags(item) or 0
            if stillBuying and needed - inBags > 0 then
                local realm = item.buyRealm or "Unknown"
                if not byRealm[realm] then
                    byRealm[realm] = {}
                    seenPerRealm[realm] = {}
                end
                local lname = item.name:lower()
                if not seenPerRealm[realm][lname] then
                    seenPerRealm[realm][lname] = true
                    table.insert(byRealm[realm], item)
                end
            end
        end
    end
    return byRealm
end

-- Build search-string lists keyed by Auctionator list name, per current mode.
local function BuildListPlan()
    local mode = (ns.db and ns.db.settings and ns.db.settings.auctBuyListMode) or "single"
    local opts = {
        includeQuality = ns.db and ns.db.settings and ns.db.settings.auctBuyListIncludeQuality,
        includeTier    = ns.db and ns.db.settings and ns.db.settings.auctBuyListIncludeTier,
        includeIlvl    = ns.db and ns.db.settings and ns.db.settings.auctBuyListIncludeIlvl,
    }

    local byRealm = CollectOutstandingBuys()
    local plan = {}  -- listName -> { searchStrings, realmTag }

    if mode == "perRealm" then
        for realm, items in pairs(byRealm) do
            local listName = LIST_PREFIX_PER_REALM .. realm
            local strings = {}
            for _, item in ipairs(items) do
                table.insert(strings, BuildSearchString(item, opts))
            end
            plan[listName] = { searchStrings = strings, realmTag = realm }
        end
    else
        -- single: flatten all realms into one list, but de-dup across realms
        -- by lower-name so the same item isn't repeated when the buy task
        -- group spans connected realms.
        local strings = {}
        local seen = {}
        for _, items in pairs(byRealm) do
            for _, item in ipairs(items) do
                local lname = (item.name or ""):lower()
                if not seen[lname] then
                    seen[lname] = true
                    table.insert(strings, BuildSearchString(item, opts))
                end
            end
        end
        plan[SINGLE_LIST_NAME] = { searchStrings = strings, realmTag = nil }
    end

    return plan, mode
end

-- Push the plan into Auctionator. Destructive — CreateShoppingList replaces
-- same-named lists (Auctionator/Source/API/v1/ShoppingLists.lua:86-89).
-- Returns (totalItems, listsCreated, listsDeleted, errors).
function BuyListSync:ApplyPlan(plan, mode)
    local totalItems = 0
    local listsCreated = 0
    local listsDeleted = 0
    local errors = {}

    local autoDelete = ns.db and ns.db.settings and ns.db.settings.auctBuyListAutoDelete

    if mode == "single" then
        local entry = plan[SINGLE_LIST_NAME]
        local strings = entry and entry.searchStrings or {}
        -- Always rebuild the contract list, even when empty. Empty list =
        -- "you have no buys" — that is meaningful state, not stale state.
        -- Per spec, single-mode auto-delete is off (the list itself is the
        -- player's persistent target); the empty list stays around.
        local ok, err = pcall(Auctionator.API.v1.CreateShoppingList,
            CALLER_ID, SINGLE_LIST_NAME, strings)
        if ok then
            listsCreated = 1
            totalItems = #strings
        else
            table.insert(errors, SINGLE_LIST_NAME .. ": " .. tostring(err))
        end

        -- Clean up any per-realm lists left over from a prior mode toggle.
        for realm in pairs(lastPerRealmLists) do
            DeleteListIfExists(LIST_PREFIX_PER_REALM .. realm)
            listsDeleted = listsDeleted + 1
        end
        wipe(lastPerRealmLists)
    else  -- perRealm
        local thisRebuild = {}
        for listName, entry in pairs(plan) do
            local strings = entry.searchStrings
            if #strings > 0 then
                local ok, err = pcall(Auctionator.API.v1.CreateShoppingList,
                    CALLER_ID, listName, strings)
                if ok then
                    listsCreated = listsCreated + 1
                    totalItems = totalItems + #strings
                    if entry.realmTag then thisRebuild[entry.realmTag] = true end
                else
                    table.insert(errors, listName .. ": " .. tostring(err))
                end
            end
        end

        if autoDelete then
            -- Delete prior-rebuild lists no longer present.
            for realm in pairs(lastPerRealmLists) do
                if not thisRebuild[realm] then
                    DeleteListIfExists(LIST_PREFIX_PER_REALM .. realm)
                    listsDeleted = listsDeleted + 1
                end
            end
            -- Also delete the single-mode list if we toggled out of single.
            DeleteListIfExists(SINGLE_LIST_NAME)
        end

        lastPerRealmLists = thisRebuild
    end

    return totalItems, listsCreated, listsDeleted, errors
end

-- Main rebuild entry point.
--   force=true bypasses the auctBuyListEnabled / auctBuyListAutoUpdate gates
--   (a manual button should always work even with auto-update off).
-- Returns (totalItems, listsCreated, listsDeleted, errOrNil).
function BuyListSync:Rebuild(force)
    if not IsAuctionatorReady() then
        return nil, nil, nil, "Auctionator is not installed"
    end
    if not ns.db or not ns.db.settings then return nil, nil, nil, "DB not ready" end

    if not force then
        if not ns.db.settings.auctBuyListEnabled then return end
        if not ns.db.settings.auctBuyListAutoUpdate then return end
    end

    local plan, mode = BuildListPlan()
    local total, created, deleted, errors = self:ApplyPlan(plan, mode)
    if errors and #errors > 0 then
        return total, created, deleted, table.concat(errors, "; ")
    end
    return total, created, deleted, nil
end

local function ScheduleRebuild()
    if pendingRebuild then return end
    pendingRebuild = true
    C_Timer.After(SETTLE_DELAY, function()
        pendingRebuild = false
        BuyListSync:Rebuild(false)
    end)
end

--------------------------
-- Event hookup
--------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        ahOpen = true
        ScheduleRebuild()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Only react to bag changes while the AH is open. Outside the AH
        -- session, BAG_UPDATE_DELAYED fires constantly during normal play
        -- (loot, mail, swaps) — the next AH open will re-sync anyway.
        if ahOpen then ScheduleRebuild() end
    end
end)
