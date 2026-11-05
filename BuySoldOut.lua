-- BuySoldOut.lua
-- Opt-in (FQ-278): when the Auction House opens on a realm with buy tasks,
-- search each task's item once. An item with no listings at all is sold out,
-- and its task is moved to the log as skipped so the player does not have to
-- delete it by hand. The sell half of a flip goes with it.
--
-- Deliberately narrow:
--   * Setting `buyAutoSkipSoldOut` is off by default. A task vanishing because
--     one search came back empty is a surprise unless the player asked for it.
--   * "Sold out" means zero listings of the item on this realm, any variant,
--     any price. Listings above the buy price still count as available; what
--     to do about an overpriced market is the player's call.
--   * A search that times out or fails is not evidence. Nothing is removed.
--   * Only tasks still at the browse/buy step with nothing bought yet. A task
--     that has already advanced is waiting on mail, not on the market.
--   * One search per item per AH visit, through AuctionAutoScan's queue so the
--     350ms spacing and the shared rate limit are respected.
--
-- Realm-wide (FQ-285): the Auction House is shared by every character on the
-- realm, so one empty search answers for every character's buy task of that
-- item here, not just the character standing at the auctioneer. Resolving
-- only the current character's task sent the player to each other character
-- in turn to rediscover the same empty market.
local addonName, ns = ...

local BuySoldOut = {}
ns.BuySoldOut = BuySoldOut

-- Tracker's AH-open chain refreshes task steps at 0.1s; wait past that so a
-- task bags already satisfy is not searched for.
local SETTLE_DELAY = 1.0
local PET_CAGE_ITEM_ID = 82800

local ahOpen = false
local checkedThisVisit = {}   -- taskUUID (or task table) -> true

local function Enabled()
    return ns.db ~= nil and ns.db.settings ~= nil and ns.db.settings.buyAutoSkipSoldOut == true
end

local function Ident(task)
    return task.taskUUID or task
end

local function SpeciesOf(task)
    local key = task.itemKey or ""
    return tonumber(key:match("^pet:(%d+)")) or tonumber(key:match("^pet_(%d+)"))
end

local function ItemIDOf(task)
    if SpeciesOf(task) then return PET_CAGE_ITEM_ID end
    local id = tonumber(task.itemID) or tonumber((task.itemKey or ""):match("^(%d+)"))
    if not id and ns.ResolveItemID then id = tonumber(ns:ResolveItemID(task)) end
    return id
end

-- Whether the assigned character is already known to hold the task's item.
-- The current character's bags are read live; another character's come from
-- the stored inventory scan, which is what we have of their bags while they
-- are logged out. A character who has already bought the item is waiting on
-- mail, not on the market, even if the task's step has not caught up yet.
local function AlreadyHeld(task, currentCharKey)
    if task.assignedChar == currentCharKey or not task.assignedChar then
        local inBags = (ns.Tracker and ns.Tracker._CountInBags)
            and ns.Tracker._CountInBags(task) or 0
        return inBags > 0
    end
    local charData = ns.db and ns.db.characters and ns.db.characters[task.assignedChar]
    local items = charData and charData.inventory and charData.inventory.items
    if not (items and ns.ItemsMatch) then return false end
    local resolvedID = ItemIDOf(task)
    for key, itemData in pairs(items) do
        if (itemData.quantity or 0) > 0
            and ns:ItemsMatch(key, itemData.name, task, resolvedID or false) then
            return true
        end
    end
    return false
end

-- Buy tasks on this realm, any character, that the market still has to
-- answer for: pending, at the browse/buy step, nothing bought yet, and not
-- already searched this visit.
function BuySoldOut:CollectCandidates(charKey, realm)
    local current = ns.TodoList and ns.TodoList:GetCurrentList()
    if not (current and current.tasks) then return {} end
    local out = {}
    for _, task in ipairs(current.tasks) do
        if task.status == "pending" and task.action == "buy"
            and ns:RealmMatches(task.buyRealm or "", realm)
            and not checkedThisVisit[Ident(task)] then
            local stepType = ns.TodoList.GetCurrentStepType
                and ns.TodoList:GetCurrentStepType(task) or nil
            local stillBuying = (not stepType) or stepType == "browse" or stepType == "buy"
            if stillBuying and not AlreadyHeld(task, charKey) then
                out[#out + 1] = task
            end
        end
    end
    return out
end

local function IndexOf(task)
    local current = ns.TodoList and ns.TodoList:GetCurrentList()
    if not (current and current.tasks) then return nil end
    for i, t in ipairs(current.tasks) do
        if t == task then return i end
    end
    return nil
end

local function CharName(charKey)
    return (charKey or "?"):match("^([^%-]+)") or charKey or "?"
end

-- Decide one item's tasks once its search has settled. Returns how many
-- tasks were resolved as sold out. `scanStartedAt` bounds the cache read to
-- this scan's results, so a listing left over from an earlier visit cannot
-- answer for it.
function BuySoldOut:ResolveGroup(group, realm, gotResults, scanStartedAt)
    local first = group.tasks[1]
    local label = first and first.name or "?"
    if not gotResults then
        ns:PrintDebug("[SoldOut] " .. label .. ": no result, leaving the task(s) alone")
        return 0
    end
    local cache = ns.AuctionScanCache
    if not (cache and cache.CountListingsForItemID) then return 0 end
    local count = cache:CountListingsForItemID(group.itemID, group.species,
        scanStartedAt and (scanStartedAt - 1) or nil)
    ns:PrintDebug("[SoldOut] " .. label .. ": " .. count .. " listing(s) on " .. realm
        .. " (" .. #group.tasks .. " task(s))")
    if count > 0 then return 0 end
    if not (ns.TodoList and ns.TodoList.SkipBuyTaskSoldOut) then return 0 end

    -- Several characters' tasks for the same item: one chat line for all of
    -- them rather than the same "sold out" message once per character.
    local silent = #group.tasks > 1
    local resolved, linkedSells = 0, 0
    local chars = {}
    for _, task in ipairs(group.tasks) do
        local idx = IndexOf(task)   -- nil: resolved by something else meanwhile
        if idx then
            local removed, partners = ns.TodoList:SkipBuyTaskSoldOut(idx, realm, silent)
            if (removed or 0) > 0 then
                resolved = resolved + 1
                linkedSells = linkedSells + (partners or 0)
                chars[#chars + 1] = CharName(task.assignedChar)
            end
        end
    end
    if silent and resolved > 0 then
        local tail = linkedSells > 0
            and (", " .. linkedSells .. " linked sell task" .. (linkedSells > 1 and "s" or "")) or ""
        ns:Print((ns.COLORS and ns.COLORS.ORANGE or "") .. "Skipped:|r " .. label ..
            " — sold out on " .. realm .. ", none listed (" .. resolved .. " characters: "
            .. table.concat(chars, ", ") .. tail .. ")")
    end
    return resolved
end

-- Decide a single task. Returns true when it was resolved as sold out.
function BuySoldOut:Resolve(task, realm, gotResults, scanStartedAt)
    local group = { itemID = ItemIDOf(task), species = SpeciesOf(task), tasks = { task } }
    return self:ResolveGroup(group, realm, gotResults, scanStartedAt) > 0
end

-- Search every candidate item once and resolve the sold-out tasks. Returns
-- how many searches were queued; the resolutions land asynchronously as
-- results come in.
function BuySoldOut:Check(charKey, realm)
    if not Enabled() then return 0 end
    local scanner = ns.AuctionAutoScan
    if not (scanner and scanner.ScanItem) then return 0 end
    charKey = charKey or ns:GetCharKey()
    realm = realm or charKey:match("%-(.+)$") or (GetRealmName and GetRealmName()) or ""
    if realm == "" then return 0 end

    local candidates = self:CollectCandidates(charKey, realm)
    if #candidates == 0 then return 0 end

    -- One search per item: tasks for the same item, whichever character owns
    -- them, share a group and are decided by the same result.
    local groups, order = {}, {}
    for _, task in ipairs(candidates) do
        checkedThisVisit[Ident(task)] = true
        local itemID = ItemIDOf(task)
        if itemID then
            local species = SpeciesOf(task)
            local gkey = tostring(itemID) .. ":" .. tostring(species or "")
            local g = groups[gkey]
            if not g then
                g = { itemID = itemID, species = species, tasks = {}, itemKey = task.itemKey }
                groups[gkey] = g
                order[#order + 1] = g
            end
            g.tasks[#g.tasks + 1] = task
        else
            ns:PrintDebug("[SoldOut] " .. (task.name or "?") .. ": no item ID, cannot search")
        end
    end
    if #order == 0 then return 0 end

    local startedAt = time()
    local skipped = 0

    -- Count the searches before issuing any: a result that comes back at once
    -- would otherwise see "all settled" after the first item and rebuild the
    -- shopping list once per item.
    local pending = #order

    local function settle()
        pending = pending - 1
        if pending > 0 then return end
        if skipped > 0 then
            if ns.BuyListSync and ns.BuyListSync.Rebuild then ns.BuyListSync:Rebuild(false) end
            if ns.UI then
                if ns.UI.Refresh then ns.UI:Refresh() end
                if ns.UI.RefreshMini then ns.UI:RefreshMini() end
            end
        end
    end

    for _, group in ipairs(order) do
        local isCommodity = ns.IsCommodity and ns:IsCommodity(group.itemID) == true or false
        local fqs = group.itemKey and { group.itemKey } or nil
        scanner:ScanItem(group.itemID, isCommodity, function(gotResults)
            -- The AH closed while the search was out: the queue was wiped
            -- and this is the timeout path firing late. Not evidence.
            if not ahOpen then gotResults = false end
            skipped = skipped + BuySoldOut:ResolveGroup(group, realm, gotResults, startedAt)
            settle()
        end, fqs, { ignorePostingGate = true })
    end
    ns:PrintDebug("[SoldOut] checking " .. #order .. " item(s) for " .. #candidates
        .. " buy task(s) on " .. realm)
    return #order
end

-- Exposed so a test (or /fq) can start a fresh visit without the event.
function BuySoldOut:ResetVisit()
    wipe(checkedThisVisit)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        ahOpen = true
        if not Enabled() then return end
        C_Timer.After(SETTLE_DELAY, function()
            if ahOpen then BuySoldOut:Check() end
        end)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
        BuySoldOut:ResetVisit()
    end
end)
