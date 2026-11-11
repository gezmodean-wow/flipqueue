-- test/warbanktabs_spec.lua
-- Headless coverage for the Characters-page warbank/bank tab toggles (FQ-290).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/warbanktabs_spec.lua
--
-- Reported: a player unticked every warbank tab but one and FlipQueue still
-- put the whole warbank on the to-do list. Two holes, both pinned here:
--   1. The toggles wrote pullTabs.warbank[i] but every reader bailed out on
--      pullTabs.mode == "all" — a field nothing ever changed — so pulling,
--      depositing and posting ignored the toggles too.
--   2. The to-do generator pooled ns.db.warbank.items without ever asking
--      which tab an item sat in; the Syndicator projection didn't record it.

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

local function join(t)
    local out = {}
    for i, v in ipairs(t) do out[i] = tostring(v) end
    return table.concat(out, ",")
end

--------------------------
-- Namespace
--------------------------

local ns = { TodoList = {} }
ns.COLORS = setmetatable({}, {__index = function() return "" end})
ns.BANK_TABS = {6, 7, 8, 9, 10, 11}
ns.WARBANK_TABS = {12, 13, 14, 15, 16}
function ns:Print() end
function ns:PrintDebug() end

assert(loadfile("DB.lua"))("flipqueue", ns)

-- Core.lua / Import.lua pieces the loaded modules touch, stubbed.
function ns:GetCharKey() return "Main-Sargeras" end
function ns:InvalidateInventoryNameIndex() end
function ns:MakeItemKey(id, b, m) return tostring(id) .. ";" .. (b or "") .. ";" .. (m or "") end
function ns:IsPhantomChar() return false end
function ns:IsDoNotTrack() return false end
function ns:IsWarboundUntilEquipped() return false end
function ns:ResolveItemID(deal) return tonumber(deal.itemID) end
function ns:ParseGoldValue(str) return tonumber((tostring(str or ""):gsub("[^%d]", ""))) or 0 end
function ns:ResolveFPPrice(deal) return deal.expectedPrice or "" end
function ns:NormalizeRealmKey(r) return (r or ""):lower() end
function ns:RealmMatches(a, b) return (a or "") == (b or "") end
function ns:RealmsOverlap(a, b) return self:RealmMatches(a, b) end
function ns:ItemsMatch(poolKey, _, deal, resolvedID)
    if deal.itemKey and deal.itemKey == poolKey then return true end
    local poolID = tonumber((tostring(poolKey):gsub(";.*", "")))
    return resolvedID and poolID and resolvedID == poolID or false
end

-- Item lookup: "item:<id>" links fold to "<id>;;" keys.
ns.ItemLookup = {
    GetItemKey = function(_, link) local id = link:match("item:(%d+)"); return id and (id .. ";;") end,
    GetItemMeta = function(_, key)
        local id = tonumber(key:match("^(%d+)"))
        return { itemID = id, name = "Item " .. id, bonusIDs = "", modifiers = "", ilvl = 0, bindType = 0 }
    end,
}

local function NewDB(pullTabs, warbank)
    ns.db = {
        settings = {
            pullTabs = pullTabs,
            skipUnassigned = false, sellQtyMode = "none", defaultSellQty = 1,
            tsmSkipOnGenerate = false, debugMessages = false,
        },
        characters = {},
        warbank = warbank,
        imports = {},
        todoLists = { active = nil, upcoming = {} },
    }
    return ns.db
end

--------------------------
-- 1. DB helpers honour the toggles even with the shipped mode = "all"
--------------------------
print("1. tab helpers")
do
    -- The exact shape a live install carries after unticking warbank tab 2.
    NewDB({ mode = "all", warbank = { [2] = false } })
    check("warbank: tab 2 untick excludes bag 13", join(ns:GetEnabledWarbankTabs()), "12,14,15,16")
    check("warbank: IsWarbankTabEnabled(2)", ns:IsWarbankTabEnabled(2), false)
    check("warbank: IsWarbankTabEnabled(1)", ns:IsWarbankTabEnabled(1), true)
    check("warbank: unset tab defaults enabled", ns:IsWarbankTabEnabled(5), true)

    NewDB(nil)
    check("warbank: no pullTabs -> every tab", join(ns:GetEnabledWarbankTabs()), "12,13,14,15,16")
    check("bank: no pullTabs -> every tab", join(ns:GetEnabledBankTabs()), "6,7,8,9,10,11")

    NewDB({ mode = "all", bank = { ["Main-Sargeras"] = { [1] = false, [6] = false } } })
    check("bank: per-char unticks exclude bags 6 and 11", join(ns:GetEnabledBankTabs()), "7,8,9,10")

    NewDB({ mode = "all", bank = { ["Other-Realm"] = { [1] = false } } })
    check("bank: another character's unticks don't apply", join(ns:GetEnabledBankTabs()), "6,7,8,9,10,11")
end

--------------------------
-- 2. Free-slot and quantity helpers sum enabled tabs, fall back without them
--------------------------
print("2. free slots / quantities")
do
    NewDB({ warbank = { [2] = false } }, {
        freeSlots = 65, totalSlots = 294,
        tabs = { [1] = { total = 98, free = 10 }, [2] = { total = 98, free = 50 }, [3] = { total = 98, free = 5 } },
    })
    local free, total = ns:GetWarbankFreeSlots()
    check("free: enabled tabs only", free, 15)
    check("total: enabled tabs only", total, 196)

    NewDB(nil, { freeSlots = 42, totalSlots = 200 })  -- pre-FQ-290 scan: no tabs
    free, total = ns:GetWarbankFreeSlots()
    check("free: falls back to whole-warbank figure", free, 42)
    check("total: falls back to whole-warbank figure", total, 200)

    NewDB(nil, { freeSlots = 42, tabs = {} })  -- empty tabs table = no per-tab data
    check("free: empty tabs table falls back", (ns:GetWarbankFreeSlots()), 42)

    NewDB(nil, nil)
    check("free: no scan -> nil", ns:GetWarbankFreeSlots(), nil)

    NewDB({ warbank = { [2] = false } })
    check("qty: tabs split honours toggles", ns:GetWarbankEnabledQuantity({ quantity = 10, tabs = { [1] = 3, [2] = 7 } }), 3)
    check("qty: no tabs -> whole quantity", ns:GetWarbankEnabledQuantity({ quantity = 5 }), 5)
    check("qty: nil item -> 0", ns:GetWarbankEnabledQuantity(nil), 0)
end

--------------------------
-- 3. Syndicator projection records the per-tab split
--------------------------
print("3. projection")
assert(loadfile("Scanner.lua"))("flipqueue", ns)
do
    Syndicator = { API = {} }
    function Syndicator.API.GetWarband()
        return { bank = {
            [1] = { name = "Flips", slots = {
                { itemLink = "item:1001", itemCount = 3 }, {}, {},
            } },
            [2] = { name = "Keep", slots = {
                { itemLink = "item:1001", itemCount = 7 },
                { itemLink = "item:1002", itemCount = 1 }, {},
            } },
        } }
    end

    NewDB({ warbank = { [2] = false } }, nil)
    ns.Scanner:RefreshWarbankFromSyndicator()
    local wb = ns.db.warbank
    check("projection: whole-warbank free", wb.freeSlots, 3)
    check("projection: whole-warbank total", wb.totalSlots, 6)
    check("projection: tab 1 stats", wb.tabs[1].total .. "/" .. wb.tabs[1].free, "3/2")
    check("projection: tab 2 stats", wb.tabs[2].total .. "/" .. wb.tabs[2].free, "3/1")
    check("projection: 1001 total quantity", wb.items["1001;;"].quantity, 10)
    check("projection: 1001 tab 1 share", wb.items["1001;;"].tabs[1], 3)
    check("projection: 1001 tab 2 share", wb.items["1001;;"].tabs[2], 7)
    check("projection: 1002 only in tab 2", wb.items["1002;;"].tabs[2], 1)
    check("projection: 1002 no tab 1 share", wb.items["1002;;"].tabs[1], nil)

    local free, total = ns:GetWarbankFreeSlots()
    check("projection: enabled free after untick", free, 2)
    check("projection: enabled total after untick", total, 3)
    check("projection: enabled quantity after untick", ns:GetWarbankEnabledQuantity(wb.items["1001;;"]), 3)
end

--------------------------
-- 4. The generator's pool only sees stock in enabled tabs
--------------------------
print("4. item pool")
assert(loadfile("TodoList.lua"))("flipqueue", ns)
assert(loadfile("TodoGenerator.lua"))("flipqueue", ns)
do
    local function PoolByKey()
        local byKey = {}
        for _, entry in ipairs(ns.TodoList:BuildItemPool()) do byKey[entry.itemKey] = entry end
        return byKey
    end

    -- Re-project with every tab enabled, then flip tab 2 off without
    -- rescanning: the pool must follow the toggle, not the last scan.
    NewDB({ mode = "all" }, nil)
    ns.Scanner:RefreshWarbankFromSyndicator()
    local pool = PoolByKey()
    check("pool: all tabs -> 1001 x10", pool["1001;;"] and pool["1001;;"].totalQuantity, 10)
    check("pool: all tabs -> 1002 x1", pool["1002;;"] and pool["1002;;"].totalQuantity, 1)
    check("pool: warbank source labelled", pool["1001;;"].sources[1].source .. "/" .. pool["1001;;"].sources[1].location, "Warbank/warbank")

    ns.db.settings.pullTabs.warbank = { [2] = false }
    pool = PoolByKey()
    check("pool: tab 2 off -> 1001 x3", pool["1001;;"] and pool["1001;;"].totalQuantity, 3)
    check("pool: tab 2 off -> 1002 gone", pool["1002;;"], nil)

    ns.db.settings.pullTabs.warbank = { [1] = false, [2] = false }
    pool = PoolByKey()
    check("pool: every tab off -> empty", next(pool), nil)

    -- Partner data synced from a pre-FQ-290 build carries no tabs split and
    -- still counts in full rather than vanishing.
    NewDB({ warbank = { [2] = false } }, { items = {
        ["1003;;"] = { itemID = 1003, name = "Legacy", quantity = 4, bindType = 0 },
    }, freeSlots = 10, totalSlots = 98 })
    pool = PoolByKey()
    check("pool: legacy entry without tabs counts in full", pool["1003;;"] and pool["1003;;"].totalQuantity, 4)
end

print(string.format("warbanktabs_spec: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
