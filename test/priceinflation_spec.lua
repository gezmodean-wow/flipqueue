-- test/priceinflation_spec.lua
-- Headless coverage for ns:FPPriceInflation / ns:CountInflatedTasks (FQ-177).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/priceinflation_spec.lua
--
-- Tasks can be priced 100x-1000x above what the item actually fetches, because
-- FlippingPal's Listing column is an aggressive recommendation and that is the
-- default source. The setting to change it has existed since v0.13.0; what was
-- missing was any connection between the wrong number on screen and the
-- setting. These helpers draw that connection, so what they must never do is
-- cry wolf: every case where the comparison can't be made honestly has to come
-- back "no opinion", not "inflated".

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

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "" end })
function ns:Print() end
function ns:PrintDebug() end
function ns:PrintError() end
function ns:MakeItemKey(id) return tostring(id) .. ";;" end
function ns:MakeImportKey(...) return table.concat({...}, "|") end
function ns:RealmsOverlap() return false end
function ns:RealmMatches() return false end

-- ParseGoldValue, copied from DB.lua (the same copy import_spec keeps).
function ns:ParseGoldValue(str)
    if not str or str == "" then return 0 end
    local clean = str:gsub("%s", "")
    local k = clean:match("^([%d,%.]+)[kK]$")
    if k then return tonumber((k:gsub(",", ""))) * 1000 end
    local m = clean:match("^([%d,%.]+)[mM]$")
    if m then return tonumber((m:gsub(",", ""))) * 1000000 end
    local g = clean:match("^([%d,%.]+)g")
    if g then return tonumber((g:gsub("[,%.]", ""))) or 0 end
    return tonumber((clean:gsub("[,%.]", ""))) or 0
end

assert(loadfile("Import.lua"))("FlipQueue", ns)

check("FPPriceInflation is exposed", type(ns.FPPriceInflation), "function")
check("CountInflatedTasks is exposed", type(ns.CountInflatedTasks), "function")

-- A stand-in for TSM: regional averages in copper, keyed by itemKey.
local tsmPrices = {}
local tsmEnabled = true
ns.TSM = {
    IsEnabled = function() return tsmEnabled end,
    GetPrice  = function(_, key, source)
        if source ~= "DBRegionMarketAvg" then return nil end
        return tsmPrices[key]
    end,
}

--------------------------
-- The comparison itself
--------------------------

tsmPrices["1;;"] = 551 * 10000          -- 551g regional average

local ratio, tsmGold = ns:FPPriceInflation("1;;", "113190g")
check("ratio is price / regional average", math.floor(ratio + 0.5), 205)
check("the reference is handed back in gold", tsmGold, 551)

ratio = ns:FPPriceInflation("1;;", "600g")
check("a sane price is barely above 1x", ratio < 2, true)

--------------------------
-- No opinion beats a wrong one
--------------------------

check("no item key -> nil", ns:FPPriceInflation(nil, "113190g"), nil)
check("empty item key -> nil", ns:FPPriceInflation("", "113190g"), nil)
check("no price -> nil", ns:FPPriceInflation("1;;", nil), nil)
check("empty price -> nil", ns:FPPriceInflation("1;;", ""), nil)
check("unparseable price -> nil", ns:FPPriceInflation("1;;", "ask me"), nil)
check("no TSM data for the item -> nil", ns:FPPriceInflation("999;;", "113190g"), nil)

tsmPrices["2;;"] = 0
check("a zero reference is not a reference", ns:FPPriceInflation("2;;", "113190g"), nil)

tsmEnabled = false
check("TSM disabled -> nil", ns:FPPriceInflation("1;;", "113190g"), nil)
tsmEnabled = true

--------------------------
-- Counting over a list
--------------------------

tsmPrices["10;;"] = 551 * 10000
tsmPrices["11;;"] = 500 * 10000
tsmPrices["12;;"] = 2000 * 10000
tsmPrices["13;;"] = 100 * 10000

-- Generator-preview shape: flat item entries.
local previewItems = {
    { itemKey = "10;;", name = "Tarnished Dawnlit Band", expectedPrice = "113190g" },  -- 205x
    { itemKey = "11;;", name = "Sane Item",              expectedPrice = "600g"    },  -- 1.2x
    { itemKey = "12;;", name = "Also Sane",              expectedPrice = "2500g"   },  -- 1.25x
    { itemKey = "13;;", name = "Wild One",               expectedPrice = "5000g"   },  -- 50x
}

local count, worst = ns:CountInflatedTasks(previewItems)
check("two tasks flagged", count, 2)
check("the worst one is kept as the example", worst.name, "Tarnished Dawnlit Band")
check("with its price", worst.price, "113190g")

-- Committed-list shape: each task wraps its item.
local tasks = {
    { item = { itemKey = "10;;", name = "Tarnished Dawnlit Band", expectedPrice = "113190g" } },
    { item = { itemKey = "11;;", name = "Sane Item",              expectedPrice = "600g" } },
}
count = ns:CountInflatedTasks(tasks)
check("the wrapped shape counts the same", count, 1)

-- Buy tasks are priced from the other side of the flip and are not what this
-- warning is about; flagging them would send the player to a setting that
-- cannot affect them.
local buys = {
    { item = { itemKey = "10;;", name = "Bought High", action = "buy",
               expectedPrice = "113190g", buyPrice = "10g" } },
}
count = ns:CountInflatedTasks(buys)
check("buy tasks are not flagged", count, 0)

count = ns:CountInflatedTasks(nil)
check("nil list counts zero", count, 0)

-- Exactly at the threshold is not over it.
tsmPrices["20;;"] = 100 * 10000
count = ns:CountInflatedTasks({ { itemKey = "20;;", expectedPrice = "1000g" } })
check("exactly 10x is not flagged", count, 0)
count = ns:CountInflatedTasks({ { itemKey = "20;;", expectedPrice = "1001g" } })
check("just over 10x is flagged", count, 1)

print(string.format("priceinflation_spec: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
