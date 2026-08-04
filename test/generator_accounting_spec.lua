-- test/generator_accounting_spec.lua
-- Headless coverage for the generator's deal accounting (FQ-228 follow-up).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/generator_accounting_spec.lua
--
-- A player imported 2,000+ deals and got 94 tasks, and neither he nor we could
-- tell a bug from a filter doing its job — because most deals left through
-- exits that were counted nowhere. A deal for a realm you have no character on
-- was simply dropped; a deal for an item you don't own and one for an item
-- whose stock was already claimed landed in the same unlabelled bucket.
--
-- The readout that fixes that is only worth anything if it is complete, so the
-- invariant under test is arithmetic: every deal that goes in leaves through
-- exactly one bucket, and the buckets sum to the total. Every case below
-- asserts that alongside whatever else it is checking.

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

local ns = { TodoList = {} }
ns.COLORS = setmetatable({}, {__index = function() return "" end})
function ns:Print() end
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
-- Realms match on exact name or membership of the same comma-separated cluster.
function ns:RealmMatches(a, b)
    a, b = a or "", b or ""
    if a == b then return true end
    for part in a:gmatch("[^,]+") do
        if part:gsub("^%s+", ""):gsub("%s+$", "") == b then return true end
    end
    return false
end
function ns:RealmsOverlap(a, b) return self:RealmMatches(a, b) end
-- Item matching: exact key, then numeric ID.
function ns:ItemsMatch(poolKey, poolName, deal, resolvedID)
    if deal.itemKey and deal.itemKey ~= "" and deal.itemKey == poolKey then return true end
    local poolID = tonumber((tostring(poolKey):gsub(";.*", "")))
    if resolvedID and poolID and resolvedID == poolID then return true end
    return false
end

assert(loadfile("TodoList.lua"))("FlipQueue", ns)
assert(loadfile("TodoGenerator.lua"))("FlipQueue", ns)
local TodoList = ns.TodoList

--------------------------
-- Fixture
--------------------------

-- One character on Sargeras holding two items. Everything else the deals ask
-- for is either on a realm with no character, or an item that isn't owned.
local function NewDB(deals, settings)
    local db = {
        settings = {
            skipUnassigned = false, sellQtyMode = "none", defaultSellQty = 1,
            tsmSkipOnGenerate = false, debugMessages = false,
        },
        characters = {
            ["Main-Sargeras"] = {
                role = "both",
                inventory = { items = {
                    ["1001;;"] = { itemID = 1001, name = "Thorium Helm", quantity = 2,
                                   locations = { bags = 2 } },
                    ["1002;;"] = { itemID = 1002, name = "Russet Hat", quantity = 1,
                                   locations = { bags = 1 } },
                } },
            },
        },
        warbank = { items = {}, freeSlots = 50 },
        imports = { fpScanner = deals },
        todoLists = { active = nil, upcoming = {} },
    }
    for k, v in pairs(settings or {}) do db.settings[k] = v end
    return db
end

local function D(itemID, name, realm, extra)
    local deal = {
        itemKey = itemID .. ";;", itemID = itemID, name = name,
        targetRealm = realm, expectedPrice = "100g", quantity = 1,
    }
    for k, v in pairs(extra or {}) do deal[k] = v end
    return deal
end

-- Every bucket, summed. The generator computes `other` to close the sum, so
-- this must equal `total` by construction — which is the point: if a branch is
-- added later and forgets to count, `other` absorbs it and stays honest rather
-- than the figures quietly not adding up.
local function SumBuckets(a)
    return a.tasks + a.deposits + a.unassigned + a.noCharacter + a.notOwned
        + a.noStock + a.tsmRejected + a.warbankFull + a.noQuantity
        + a.flipSkipped + a.other
end

local function Generate(deals, settings)
    ns.db = NewDB(deals, settings)
    local preview = TodoList:GenerateTodoList("fpScanner", {"gold"}, {})
    return preview, preview.accounting
end

print("Generator accounting spec")

--------------------------
-- 1. The sum always closes
--------------------------

local preview, acct = Generate({
    d1 = D(1001, "Thorium Helm", "Sargeras"),        -- task
    d2 = D(1002, "Russet Hat", "Sargeras"),          -- task
    d3 = D(9999, "Not Owned", "Sargeras"),           -- notOwned
    d4 = D(1001, "Thorium Helm", "Proudmoore"),      -- no character there
})

check("all four deals counted", acct.total, 4)
check("buckets sum to the total", SumBuckets(acct), acct.total)
check("two tasks", acct.tasks, 2)
check("one item not owned", acct.notOwned, 1)

--------------------------
-- 2. The quiet exit: no character on that realm
--------------------------

-- With the setting off, these become "create a character" tasks.
check("unassigned when the setting is off", acct.unassigned, 1)
check("and not counted as dropped", acct.noCharacter, 0)
check("the realm is named", acct.noCharacterRealms["Proudmoore"], 1)

-- With it on, they are dropped outright — the exit that used to be counted
-- nowhere at all, and the largest one for anyone whose import spans more
-- realms than they have characters.
local _, acct2 = Generate({
    d1 = D(1001, "Thorium Helm", "Sargeras"),
    d2 = D(1001, "Thorium Helm", "Proudmoore"),
    d3 = D(1002, "Russet Hat", "Kel'Thuzad"),
}, { skipUnassigned = true })

check("dropped deals are counted", acct2.noCharacter, 2)
check("not silently vanished", SumBuckets(acct2), acct2.total)
check("no unassigned tasks were made", acct2.unassigned, 0)
check("per-realm breakdown, realm one", acct2.noCharacterRealms["Proudmoore"], 1)
check("per-realm breakdown, realm two", acct2.noCharacterRealms["Kel'Thuzad"], 1)

--------------------------
-- 3. Not owned vs stock already claimed
--------------------------

-- Three deals for an item the player owns two of: two tasks, and the third
-- deal finds the stock gone. That is a different answer from "you don't own
-- this", and the two used to be indistinguishable.
local _, acct3 = Generate({
    d1 = D(1001, "Thorium Helm", "Sargeras", {expectedPrice = "300g"}),
    d2 = D(1001, "Thorium Helm", "Sargeras", {expectedPrice = "200g"}),
    d3 = D(1001, "Thorium Helm", "Sargeras", {expectedPrice = "100g"}),
    d4 = D(7777, "Never Owned", "Sargeras"),
})

check("stock exhaustion is its own bucket", acct3.noStock >= 1, true)
check("and is not confused with not-owned", acct3.notOwned, 1)
check("buckets still sum", SumBuckets(acct3), acct3.total)
check("only the owned quantity became tasks", acct3.tasks, 2)

--------------------------
-- 4. Nothing in, nothing claimed
--------------------------

local _, acct4 = Generate({})
check("an empty import totals zero", acct4.total, 0)
check("and sums", SumBuckets(acct4), 0)

--------------------------
-- 5. A generation where everything works still accounts for everything
--------------------------

local _, acct5 = Generate({
    d1 = D(1001, "Thorium Helm", "Sargeras"),
    d2 = D(1002, "Russet Hat", "Sargeras"),
})
check("two deals, two tasks", acct5.tasks, 2)
check("nothing dropped", acct5.total - acct5.tasks, 0)
check("sum closes on a clean run", SumBuckets(acct5), acct5.total)

--------------------------
-- 6. The split preview keeps the accounting
--------------------------

-- listMode "separate" builds two fresh preview tables; the accounting
-- describes the run that produced both, so it has to survive the split.
ns.db = NewDB({
    d1 = D(1001, "Thorium Helm", "Sargeras"),
    d2 = D(9999, "Not Owned", "Sargeras"),
})
local split = TodoList:GenerateTodoList("fpScanner", {"gold"}, {listMode = "separate"})
check("buy half carries it", split.buy.accounting ~= nil, true)
check("sell half carries it", split.sell.accounting ~= nil, true)
check("and it still sums", SumBuckets(split.sell.accounting), split.sell.accounting.total)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
