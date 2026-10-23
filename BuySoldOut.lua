-- BuySoldOut.lua
-- Opt-in (FQ-278): when the Auction House opens on a realm this character has
-- buy tasks for, search each task's item once. An item with no listings at
-- all is sold out, and its task is moved to the log as skipped so the player
-- does not have to delete it by hand. The sell half of a flip goes with it.
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
--   * One search per task per AH visit, through AuctionAutoScan's queue so the
--     350ms spacing and the shared rate limit are respected.
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

-- Buy tasks for this character on this realm that the market still has to
-- answer for: pending, at the browse/buy step, nothing in bags yet, and not
-- already searched this visit.
function BuySoldOut:CollectCandidates(charKey, realm)
    local current = ns.TodoList and ns.TodoList:GetCurrentList()
    if not (current and current.tasks) then return {} end
    local out = {}
    for _, task in ipairs(current.tasks) do
        if task.status == "pending" and task.action == "buy"
            and task.assignedChar == charKey
            and ns:RealmMatches(task.buyRealm or "", realm)
            and not checkedThisVisit[Ident(task)] then
            local stepType = ns.TodoList.GetCurrentStepType
                and ns.TodoList:GetCurrentStepType(task) or nil
            local stillBuying = (not stepType) or stepType == "browse" or stepType == "buy"
            local inBags = (ns.Tracker and ns.Tracker._CountInBags)
                and ns.Tracker._CountInBags(task) or 0
            if stillBuying and inBags <= 0 then
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

-- Decide one task once its search has settled. Returns true when the task was
-- resolved as sold out. `scanStartedAt` bounds the cache read to this scan's
-- results, so a listing left over from an earlier visit cannot answer for it.
function BuySoldOut:Resolve(task, realm, gotResults, scanStartedAt)
    if not gotResults then
        ns:PrintDebug("[SoldOut] " .. (task.name or "?") .. ": no result, leaving the task alone")
        return false
    end
    local cache = ns.AuctionScanCache
    if not (cache and cache.CountListingsForItemID) then return false end
    local count = cache:CountListingsForItemID(ItemIDOf(task), SpeciesOf(task),
        scanStartedAt and (scanStartedAt - 1) or nil)
    ns:PrintDebug("[SoldOut] " .. (task.name or "?") .. ": " .. count .. " listing(s) on " .. realm)
    if count > 0 then return false end

    local idx = IndexOf(task)
    if not idx then return false end   -- resolved by something else meanwhile
    if not (ns.TodoList and ns.TodoList.SkipBuyTaskSoldOut) then return false end
    return ns.TodoList:SkipBuyTaskSoldOut(idx, realm) > 0
end

-- Search every candidate and resolve the sold-out ones. Returns how many
-- searches were queued; the resolutions land asynchronously as results come in.
function BuySoldOut:Check(charKey, realm)
    if not Enabled() then return 0 end
    local scanner = ns.AuctionAutoScan
    if not (scanner and scanner.ScanItem) then return 0 end
    charKey = charKey or ns:GetCharKey()
    realm = realm or charKey:match("%-(.+)$") or (GetRealmName and GetRealmName()) or ""
    if realm == "" then return 0 end

    local candidates = self:CollectCandidates(charKey, realm)
    if #candidates == 0 then return 0 end

    local startedAt = time()
    local skipped, queued = 0, 0

    -- Count the searches before issuing any: a result that comes back at once
    -- would otherwise see "all settled" after the first task and rebuild the
    -- shopping list once per task.
    local pending = 0
    for _, task in ipairs(candidates) do
        if ItemIDOf(task) then pending = pending + 1 end
    end

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

    for _, task in ipairs(candidates) do
        checkedThisVisit[Ident(task)] = true
        local itemID = ItemIDOf(task)
        if itemID then
            queued = queued + 1
            local isCommodity = ns.IsCommodity and ns:IsCommodity(itemID) == true or false
            local fqs = task.itemKey and { task.itemKey } or nil
            scanner:ScanItem(itemID, isCommodity, function(gotResults)
                -- The AH closed while the search was out: the queue was wiped
                -- and this is the timeout path firing late. Not evidence.
                if not ahOpen then gotResults = false end
                if BuySoldOut:Resolve(task, realm, gotResults, startedAt) then
                    skipped = skipped + 1
                end
                settle()
            end, fqs, { ignorePostingGate = true })
        else
            ns:PrintDebug("[SoldOut] " .. (task.name or "?") .. ": no item ID, cannot search")
        end
    end
    if queued > 0 then
        ns:PrintDebug("[SoldOut] checking " .. queued .. " buy task(s) on " .. realm)
    end
    return queued
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
