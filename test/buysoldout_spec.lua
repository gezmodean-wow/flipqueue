-- test/buysoldout_spec.lua
-- Headless coverage for "skip buy tasks when the item is sold out" (FQ-278).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/buysoldout_spec.lua
--
-- The request: a buy task for an item that is no longer on the AH had to be
-- deleted by hand, every time. Opt-in: when the AH opens on the buy realm,
-- each outstanding buy task's item is searched once; zero listings moves the
-- task (and the sell half of its flip) to the log as skipped. Pinned here:
--   * off by default, and nothing is searched while off
--   * only this character's browse/buy-step tasks on this realm are searched
--   * zero listings -> skipped to the log with the reason; listings -> kept
--   * a flip's sell task goes with its sold-out buy
--   * a timed-out search removes nothing
--   * one search per task per visit; closing the AH starts a fresh visit
--   * the cache counter sees every key form and ignores stale entries

dofile("test/wow_shim.lua")

local passed, failed = 0, 0
local function check(label, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("  FAIL %s\n       got:  %s\n       want: %s",
            label, tostring(got), tostring(want)))
    end
end

--------------------------
-- Namespace
--------------------------

local printed = {}
local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "" end})
function ns:Print(msg) printed[#printed + 1] = msg end
function ns:PrintDebug() end
function ns:IsDebugEnabled() return false end
function ns:GetCharKey() return "Buyer-Sargeras" end
function ns:MakeItemKey(id, b, m) return tostring(id) .. ";" .. (b or "") .. ";" .. (m or "") end
function ns:ImportRemove() end
function ns:ResolveItemID(deal) return tonumber(deal.itemID) end
function ns:IsPhantomChar() return false end
function ns:IsDoNotTrack() return false end
function ns:IsWarboundUntilEquipped() return false end
function ns:ParseGoldValue(str) return tonumber((tostring(str or ""):gsub("[^%d]", ""))) or 0 end
function ns:ResolveFPPrice(deal) return deal.expectedPrice or "" end
function ns:NormalizeRealmKey(r) return (r or ""):lower() end
function ns:IsCommodity() return false end
function ns:ParseItemLink(link)
    local id, bonus = link:match("item:(%d+):?([%d:]*)")
    return id, bonus or "", ""
end
function ns:RealmMatches(a, b)
    a, b = a or "", b or ""
    if a == "" then return true end
    for part in a:gmatch("[^,]+") do
        if strtrim(part):lower() == b:lower() then return true end
    end
    return false
end
function ns:RealmsOverlap(a, b)
    for part in (b or ""):gmatch("[^,]+") do
        if self:RealmMatches(a, strtrim(part)) then return true end
    end
    return false
end

GetRealmName = function() return "Sargeras" end
GetNormalizedRealmName = function() return "Sargeras" end

assert(loadfile("TodoList.lua"))("FlipQueue", ns)
assert(loadfile("AuctionScanCache.lua"))("FlipQueue", ns)
local TodoList, Cache = ns.TodoList, ns.AuctionScanCache

-- Fake scanner: records what was searched and answers at once.
local scans, scanAnswer = {}, true
ns.AuctionAutoScan = {
    ScanItem = function(_, itemID, isCommodity, callback, fqs, opts)
        scans[#scans + 1] = { itemID = itemID, gate = opts and opts.ignorePostingGate }
        callback(scanAnswer)
    end,
}
-- Fake cache counter: itemID -> listings. Swapped for the real one at the end.
local listingsByID = {}
local realCount = Cache.CountListingsForItemID
Cache.CountListingsForItemID = function(_, itemID) return listingsByID[itemID] or 0 end

ns.Tracker = { _CountInBags = function() return 0 end }
local rebuilds = 0
ns.BuyListSync = { Rebuild = function() rebuilds = rebuilds + 1 end }

assert(loadfile("BuySoldOut.lua"))("FlipQueue", ns)
local SoldOut = ns.BuySoldOut

local soldOutFrame
for _, f in ipairs(__testFrames) do
    if f._events["AUCTION_HOUSE_SHOW"] and f._events["AUCTION_HOUSE_CLOSED"] then soldOutFrame = f end
end
check("module listens for the AH", soldOutFrame ~= nil, true)

--------------------------
-- Fixture
--------------------------

local list
local function Buy(id, name, extra)
    local t = { itemKey = id .. ";;", itemID = id, name = name, action = "buy",
                buyRealm = "Sargeras", targetRealm = "Kazzak", quantity = 1,
                status = "pending", assignedChar = "Buyer-Sargeras", taskUUID = name,
                steps = { { type = "browse", status = "pending" } }, currentStep = 1 }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
local function Sell(id, name, extra)
    local t = { itemKey = id .. ";;", itemID = id, name = name, action = "sell",
                targetRealm = "Kazzak", buyRealm = "Sargeras", quantity = 1,
                status = "pending", assignedChar = "Seller-Kazzak", taskUUID = name }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
local function SetList(tasks)
    list = { tasks = tasks }
    ns.db.todoLists.active = list
end
local function TaskNames()
    local out = {}
    for _, t in ipairs(list.tasks) do out[#out + 1] = t.name end
    table.sort(out)
    return table.concat(out, ",")
end
local function Skipped()
    local out = {}
    for _, e in ipairs(ns.db.log) do
        if e.auctionStatus == "skipped" then out[#out + 1] = e end
    end
    return out
end
local function Reset(settingOn)
    ns.db = { settings = { buyAutoSkipSoldOut = settingOn }, characters = {}, log = {},
              todoLists = { upcoming = {} } }
    scans, printed, rebuilds = {}, {}, 0
    scanAnswer = true
    SoldOut:ResetVisit()
    -- A visit begins with the AH opening; the module only trusts results that
    -- arrive while it is open.
    __testFireEvent(soldOutFrame, "AUCTION_HOUSE_SHOW")
end

print("buysoldout spec")

--------------------------
-- 1. Off by default
--------------------------

Reset(nil)
SetList({ Buy(1001, "Thorium Helm") })
check("setting is not on unless the player turned it on",
    SoldOut:Check("Buyer-Sargeras", "Sargeras"), 0)
check("nothing searched while off", #scans, 0)
check("task kept while off", TaskNames(), "Thorium Helm")

--------------------------
-- 2. Candidates: this character, this realm, still buying
--------------------------

Reset(true)
listingsByID = { [1001] = 0, [1002] = 3, [1003] = 0, [1004] = 0, [1005] = 0 }
SetList({
    Buy(1001, "Thorium Helm"),                                            -- sold out
    Buy(1002, "Russet Hat"),                                              -- listed
    Buy(1003, "Frozen Shield", { buyRealm = "Kazzak" }),                  -- other realm
    Buy(1004, "Copper Bar", { assignedChar = "Alt-Sargeras" }),           -- other character
    Buy(1005, "Aquamarine", { steps = { { type = "collect", status = "pending" } } }), -- bought already
    Sell(1006, "Blue Overalls", { targetRealm = "Sargeras", assignedChar = "Buyer-Sargeras" }),
})
check("two tasks searched", SoldOut:Check("Buyer-Sargeras", "Sargeras"), 2)
check("the searched items are the two buy tasks on this realm",
    scans[1].itemID .. "," .. scans[2].itemID, "1001,1002")
check("buy-side lookups bypass the posting gate", scans[1].gate, true)
check("sold-out task resolved, the rest untouched",
    TaskNames(), "Aquamarine,Blue Overalls,Copper Bar,Frozen Shield,Russet Hat")
local skipped = Skipped()
check("one skipped log entry", #skipped, 1)
check("entry names the item", skipped[1].name, "Thorium Helm")
check("entry carries the reason", skipped[1].failReason, "Sold out on Sargeras")
check("entry is on the buying character", skipped[1].charKey, "Buyer-Sargeras")
check("player is told", #printed, 1)
check("message says sold out", printed[1]:find("sold out on Sargeras", 1, true) ~= nil, true)
check("Auctionator list rebuilt", rebuilds, 1)

--------------------------
-- 3. A flip's sell half goes with its sold-out buy
--------------------------

Reset(true)
listingsByID = { [2001] = 0 }
SetList({
    Buy(2001, "Jeweled Dagger", { dealType = "flip" }),
    Sell(2001, "Jeweled Dagger", { dealType = "flip" }),
    Sell(2001, "Jeweled Dagger", { dealType = "flip", targetRealm = "Proudmoore" }), -- another flip
    Sell(2002, "Other Dagger",   { dealType = "flip" }),
})
SoldOut:Check("Buyer-Sargeras", "Sargeras")
check("buy and its own sell half removed, other flips kept", #list.tasks, 2)
check("the Proudmoore flip's sell survives", list.tasks[1].targetRealm, "Proudmoore")
skipped = Skipped()
check("two skipped entries", #skipped, 2)
local reasons = {}
for _, e in ipairs(skipped) do reasons[#reasons + 1] = e.failReason end
table.sort(reasons)
check("sell half explains why", reasons[1], "Buy skipped: Jeweled Dagger sold out on Sargeras")
check("buy half says sold out", reasons[2], "Sold out on Sargeras")
check("message mentions the linked sell task",
    printed[1]:find("1 linked sell task", 1, true) ~= nil, true)

--------------------------
-- 4. A timed-out search removes nothing
--------------------------

Reset(true)
scanAnswer = false
listingsByID = { [3001] = 0 }
SetList({ Buy(3001, "Arcane Crystal") })
SoldOut:Check("Buyer-Sargeras", "Sargeras")
check("timeout: task kept", TaskNames(), "Arcane Crystal")
check("timeout: no log entry", #Skipped(), 0)
check("timeout: no message", #printed, 0)

--------------------------
-- 5. One search per task per visit
--------------------------

Reset(true)
listingsByID = { [4001] = 5 }
SetList({ Buy(4001, "Mithril Bar") })
check("first pass searches", SoldOut:Check("Buyer-Sargeras", "Sargeras"), 1)
check("second pass in the same visit does not", SoldOut:Check("Buyer-Sargeras", "Sargeras"), 0)
-- Closing starts a fresh visit; opening again runs the check on its own (the
-- shim's C_Timer fires synchronously).
__testFireEvent(soldOutFrame, "AUCTION_HOUSE_CLOSED")
__testFireEvent(soldOutFrame, "AUCTION_HOUSE_SHOW")
check("a new visit searches again, from the AH-open hook", #scans, 2)
check("and only once", SoldOut:Check("Buyer-Sargeras", "Sargeras"), 0)

-- A result that lands after the AH closed is not evidence.
Reset(true)
listingsByID = { [4002] = 0 }
SetList({ Buy(4002, "Truesilver Bar") })
local heldCallback
ns.AuctionAutoScan.ScanItem = function(_, itemID, _, callback)
    scans[#scans + 1] = { itemID = itemID }
    heldCallback = callback
end
SoldOut:Check("Buyer-Sargeras", "Sargeras")
__testFireEvent(soldOutFrame, "AUCTION_HOUSE_CLOSED")
heldCallback(true)
check("late result after close: task kept", TaskNames(), "Truesilver Bar")
check("late result after close: no log entry", #Skipped(), 0)

--------------------------
-- 6. Real cache counter: every key form, fresh entries only
--------------------------

Cache.CountListingsForItemID = realCount

-- Drive the harvester through the event so entries land under the real keys.
local results = {}
C_AuctionHouse = {
    GetNumItemSearchResults = function() return #results end,
    GetItemSearchResultInfo = function(_, i) return results[i] end,
    GetNumCommoditySearchResults = function() return 0 end,
}
local listener
for _, f in ipairs(__testFrames) do
    if f._events["ITEM_SEARCH_RESULTS_UPDATED"] then listener = f end
end
check("scan cache listener found", listener ~= nil, true)

-- Two variants of 5001 plus one listing of 50011 (a longer ID sharing the prefix).
results = {
    { buyoutAmount = 100, quantity = 1, itemLink = "item:5001:1:2" },
    { buyoutAmount = 200, quantity = 1, itemLink = "item:5001:3" },
    { buyoutAmount = 300, quantity = 1, itemLink = "item:5001:3" },
}
__testFireEvent(listener, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 5001 })
results = { { buyoutAmount = 999, quantity = 1, itemLink = "item:50011" } }
__testFireEvent(listener, "ITEM_SEARCH_RESULTS_UPDATED", { itemID = 50011 })

check("counts listings across variants", Cache:CountListingsForItemID(5001), 3)
check("does not bleed into a longer item ID", Cache:CountListingsForItemID(50011), 1)
check("unknown item has none", Cache:CountListingsForItemID(5002), 0)
check("entries older than the scan are ignored",
    Cache:CountListingsForItemID(5001, nil, time() + 60), 0)
check("entries at or after the bound count",
    Cache:CountListingsForItemID(5001, nil, time() - 60), 3)

-- Commodity key form.
C_AuctionHouse.GetNumCommoditySearchResults = function() return 2 end
C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i)
    return { unitPrice = 10 * i, quantity = 20 }
end
__testFireEvent(listener, "COMMODITY_SEARCH_RESULTS_UPDATED", 6001)
check("commodity listings counted", Cache:CountListingsForItemID(6001), 2)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
