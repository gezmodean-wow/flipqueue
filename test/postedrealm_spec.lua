-- test/postedrealm_spec.lua
-- Headless coverage for "avoid realms where I already have an auction posted"
-- (FQ-262).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/postedrealm_spec.lua
--
-- Reported: the setting was on, yet the exact items a player already had
-- listed on a realm kept getting pulled out of the bank for that realm. Four
-- holes, each pinned here:
--   1. Deal Finder's quantity-aware re-pick ranked on score alone and undid
--      ApplyPriority's posted-realm avoidance on every scan.
--   2. The to-do generator never consulted the setting, so imports could hand
--      the only copy of an item to a realm it was already listed on.
--   3. The bank pull planner pulled for every task on the realm, posted or not.
--   4. An "active" log entry past its expiry still counted as listed.

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
local ns = { TodoList = {} }
ns.COLORS = setmetatable({}, {__index = function() return "" end})
function ns:Print(msg) printed[#printed + 1] = msg end
function ns:PrintDebug() end
function ns:GetCharKey() return "Main-Sargeras" end
function ns:MakeItemKey(id, b, m) return tostring(id) .. ";" .. (b or "") .. ";" .. (m or "") end
function ns:ImportRemove() end
function ns:ResolveItemID(deal) return tonumber(deal.itemID) end
function ns:IsPhantomChar() return false end
function ns:IsDoNotTrack() return false end
function ns:IsWarboundUntilEquipped() return false end
function ns:ParseGoldValue(str)
    return tonumber((tostring(str or ""):gsub("[^%d]", ""))) or 0
end
function ns:ResolveFPPrice(deal) return deal.expectedPrice or "" end
function ns:NormalizeRealmKey(r) return (r or ""):lower() end
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
function ns:ItemsMatch(poolKey, poolName, deal)
    if deal.itemKey and deal.itemKey ~= "" and deal.itemKey == poolKey then return true end
    local poolID = tonumber((tostring(poolKey):gsub(";.*", "")))
    return poolID ~= nil and poolID == tonumber(deal.itemID)
end

assert(loadfile("SalesIndex.lua"))("FlipQueue", ns)
assert(loadfile("DealFinder.lua"))("FlipQueue", ns)
assert(loadfile("TodoList.lua"))("FlipQueue", ns)
assert(loadfile("TodoGenerator.lua"))("FlipQueue", ns)
local DF, SI, TodoList = ns.DealFinder, ns.SalesIndex, ns.TodoList

local now = os.time()
local function Active(itemKey, realm, extra)
    local e = { itemKey = itemKey, targetRealm = realm, auctionStatus = "active",
                charKey = "Main-Sargeras", postedAt = now - 60 }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

local function SetLog(log)
    ns.db.log = log
    SI:Invalidate()
end

print("postedrealm spec")

ns.db = { settings = { dfAvoidPostedRealms = true }, characters = {}, log = {} }

--------------------------
-- 4. Expired-but-"active" entries don't count
--------------------------

SetLog({
    Active("1001;;", "Sargeras", { expiresAt = now + 3600 }),
    Active("1002;;", "Sargeras", { expiresAt = now - 10 }),
    Active("1003;;", "Sargeras"),  -- no expiry recorded: trust the status
})
check("live auction counts as listed", SI:HasActiveAuction("1001;;", "Sargeras"), true)
check("variant of a listed item counts too", SI:HasActiveAuction("1001;1:2;", "Sargeras"), true)
check("past-expiry entry is not listed", SI:HasActiveAuction("1002;;", "Sargeras"), false)
check("entry with no expiry still counts", SI:HasActiveAuction("1003;;", "Sargeras"), true)
check("other realm is clean", SI:HasActiveAuction("1001;;", "Kazzak"), false)

--------------------------
-- 1. Quantity-aware selection respects the setting
--------------------------

local function names(group)
    local out = {}
    for _, r in ipairs(group.realms) do
        if r._selected then out[#out + 1] = r.realmName end
    end
    table.sort(out)
    return table.concat(out, ",")
end

local function Group(qty, realms)
    local g = { quantity = qty, realms = realms }
    DF:ApplyPriority({ g }, { "profit" })
    DF:ApplyQuantitySelection(g)
    return g
end

-- The reported shape: one copy, the posted realm scores best. ApplyPriority
-- picked Clean; the old quantity pass re-picked Posted.
local g = Group(1, {
    { realmName = "Posted", profit = 5000, hasActiveAuction = true },
    { realmName = "Clean",  profit = 100 },
})
check("qty 1: posted top-scorer is not re-picked", names(g), "Clean")
check("qty 1: group not flagged posted", g.selectedPosted, false)

g = Group(3, {
    { realmName = "Posted", profit = 5000, hasActiveAuction = true },
    { realmName = "A",      profit = 300 },
    { realmName = "B",      profit = 200 },
})
check("qty 3: only clean realms fill the quantity", names(g), "A,B")

g = Group(2, {
    { realmName = "P1", profit = 5000, hasActiveAuction = true },
    { realmName = "P2", profit = 100,  hasActiveAuction = true },
})
check("all posted: best single realm kept, not dropped", names(g), "P1")
check("all posted: group flagged", g.selectedPosted, true)

ns.db.settings.dfAvoidPostedRealms = false
g = Group(1, {
    { realmName = "Posted", profit = 5000, hasActiveAuction = true },
    { realmName = "Clean",  profit = 100 },
})
check("setting off: plain score order", names(g), "Posted")
ns.db.settings.dfAvoidPostedRealms = true

--------------------------
-- 2. Generator demotes posted-realm deals
--------------------------

local function GenDB(settings)
    local db = {
        settings = {
            skipUnassigned = false, sellQtyMode = "none", defaultSellQty = 1,
            tsmSkipOnGenerate = false, debugMessages = false,
            dfAvoidPostedRealms = true,
        },
        characters = {
            ["Main-Sargeras"] = { role = "both", inventory = { items = {
                ["1001;;"] = { itemID = 1001, name = "Thorium Helm", quantity = 1,
                               locations = { bags = 1 } },
            } } },
            ["Alt-Kazzak"] = { role = "both", inventory = { items = {} } },
        },
        warbank = { items = {}, freeSlots = 50 },
        imports = { fpScanner = {
            ["a"] = { itemKey = "1001;;", itemID = 1001, name = "Thorium Helm",
                      targetRealm = "Sargeras", expectedPrice = "900g", quantity = 1 },
            ["b"] = { itemKey = "1001;;", itemID = 1001, name = "Thorium Helm",
                      targetRealm = "Kazzak", expectedPrice = "100g", quantity = 1 },
        } },
        todoLists = { active = nil, upcoming = {} },
        log = { Active("1001;;", "Sargeras", { expiresAt = now + 3600 }) },
    }
    for k, v in pairs(settings or {}) do db.settings[k] = v end
    return db
end

ns.db = GenDB()
SI:Invalidate()
local preview = TodoList:GenerateTodoList("fpScanner", { "gold" })
check("generator: one task for the single copy", #preview.items, 1)
check("generator: the copy goes to the clean realm",
    preview.items[1] and preview.items[1].targetRealm, "Kazzak")

ns.db = GenDB({ dfAvoidPostedRealms = false })
SI:Invalidate()
preview = TodoList:GenerateTodoList("fpScanner", { "gold" })
check("generator, setting off: richest realm wins as before",
    preview.items[1] and preview.items[1].targetRealm, "Sargeras")

--------------------------
-- 3. Bank pull skips items already listed on this realm
--------------------------

-- Bank tab 6 holds a Thorium Helm (1001) and a Russet Hat (1002); the bags
-- are empty. Both have a pending sell task on Sargeras; only the helm is
-- already listed there.
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 6 and 2 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        if bag ~= 6 then return nil end
        local id = slot == 1 and 1001 or 1002
        return { hyperlink = "item:" .. id, stackCount = 1, iconFileID = 1 }
    end,
}
GetRealmName = function() return "Sargeras" end
UnitName = function() return "Main" end
C_Item = { GetItemInfo = function() return nil end }
ns.ALL_PLAYER_BAGS = {}
function ns:GetEnabledBankTabs() return { 6 } end
function ns:GetEnabledWarbankTabs() return {} end
function ns:GetFreeBagSlots() return 20 end
function ns:ParseItemLink(link) return tonumber(link:match("item:(%d+)")), "", "" end
function ns:PlanPullWave(ops) return ops, #ops, 20 end

assert(loadfile("Tracker.lua"))("FlipQueue", ns)
local Tracker = ns.Tracker
function Tracker:GetActionMode() return "manual" end

local helmTask = { itemKey = "1001;;", itemID = 1001, name = "Thorium Helm",
                   targetRealm = "Sargeras", quantity = 1, status = "pending",
                   assignedChar = "Main-Sargeras" }
local hatTask  = { itemKey = "1002;;", itemID = 1002, name = "Russet Hat",
                   targetRealm = "Sargeras", quantity = 1, status = "pending",
                   assignedChar = "Main-Sargeras" }
local list = { tasks = { helmTask, hatTask } }
function ns.TodoList:GetCurrentList() return list end
function ns.TodoList:GetCharacterTasks()
    return { { item = helmTask }, { item = hatTask } }
end

local function PulledNames()
    local ops = Tracker:BuildPullOps()
    local out = {}
    for _, op in ipairs(ops) do out[#out + 1] = op.name end
    table.sort(out)
    return table.concat(out, ",")
end

ns.db = { settings = { dfAvoidPostedRealms = true }, characters = {},
          log = { Active("1001;;", "Sargeras", { expiresAt = now + 3600 }) } }
SI:Invalidate()
printed = {}
check("pull: listed item is skipped, the other still pulled", PulledNames(), "Russet Hat")
check("pull: skip is announced", #printed, 1)
check("pull: announcement names the item",
    printed[1] and printed[1]:find("Thorium Helm", 1, true) ~= nil, true)
PulledNames()
check("pull: announced once per task, not every replan", #printed, 1)

ns.db.settings.dfAvoidPostedRealms = false
check("pull, setting off: both pulled as before", PulledNames(), "Russet Hat,Thorium Helm")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
