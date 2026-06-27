-- test/import_spec.lua
-- Headless tests for FlipQueue's import classification (FQ-208).
-- Run from the repo root:  lua test/import_spec.lua
--
-- Loads the REAL Import.lua against a minimal WoW-API shim plus faithful
-- copies of the few ns helpers the parse path needs (ParseGoldValue and
-- MakeItemKey — the two functions the cross-realm-vs-inventory decision
-- actually depends on). Everything else is stubbed.

-- Resolve paths relative to this script so it runs from any cwd.
local scriptPath = arg and arg[0] or "test/import_spec.lua"
local scriptDir = scriptPath:match("^(.*[/\\])") or "./"
local repoRoot = scriptDir .. ".." .. "/"

dofile(scriptDir .. "wow_shim.lua")

----------------------------------------------------------------------
-- Build a minimal `ns` with real-enough helpers
----------------------------------------------------------------------
local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "" end })
function ns:PrintDebug() end
function ns:Print() end
function ns:PrintError() end

-- ParseGoldValue — copied verbatim from DB.lua so "0g" → 0, "1,000g" → 1000,
-- "13.6k" → 13600, etc. This is the function IsRealBuySide leans on.
function ns:ParseGoldValue(str)
    if not str or str == "" then return 0 end
    local clean = str
        :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("%s", "")
        :gsub("\194\160", ""):gsub("\226\128\175", "")
        :gsub("\226\128[\139\140\141\142\143]", ""):gsub("\239\187\191", "")
    local m = clean:match("^([%d,.]+)m")
    if m then return (tonumber((m:gsub(",", "."))) or 0) * 1000000 end
    local k = clean:match("^([%d,.]+)k")
    if k then return (tonumber((k:gsub(",", "."))) or 0) * 1000 end
    local g = clean:match("([%d,.]+)g")
    if g then return tonumber((g:gsub("[,.]", ""))) or 0 end
    return 0
end

-- MakeItemKey — Cogworks-1.0 Items.lua impl.
function ns:MakeItemKey(itemID, bonusIDs, modifiers)
    return string.format("%s;%s;%s", tostring(itemID), bonusIDs or "", modifiers or "")
end
function ns:FormatGold(copper) return tostring(copper) .. "g" end

----------------------------------------------------------------------
-- Load the real Import.lua with the addon vararg contract
----------------------------------------------------------------------
local chunk, err = loadfile(repoRoot .. "Import.lua")
if not chunk then error("could not load Import.lua: " .. tostring(err)) end
chunk("FlipQueue", ns)
local Import = ns.Import
assert(Import, "Import namespace not populated")

----------------------------------------------------------------------
-- Tiny assert harness
----------------------------------------------------------------------
local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then
        pass = pass + 1
        print("  ok   " .. name)
    else
        fail = fail + 1
        print("  FAIL " .. name .. (detail and ("  -> " .. detail) or ""))
    end
end

----------------------------------------------------------------------
-- Fixtures
----------------------------------------------------------------------
local HEADER = "Item ID,Item Name,Category,ilvl,Sell Rate,Expansion,Quality,Extra Stats,Sale Avg,Sale Avg vs Buy %,Sale Avg vs Buy,Sell vs Buy %,Sell vs Buy,Sell Price,Sell Realm,Buy Price,Buy Realm"

-- Real FP inventory-export rows: every buy side is the "0g / Realm 0"
-- placeholder. Post-FQ-208 these must classify as sell, not flip.
local PLACEHOLDER_CSV = HEADER .. "\n" ..
    '15604,Ancient Defender of the Fireflash,Armor,13,0.01,,uncommon,,707g,707369900.0%,707g,11076315900.0%,"11,076g","11,659g",Stormrage,0g,Realm 0\n' ..
    'pet_2947,Luminous Webspinner,Pet,,0.013,,,,"4,750g",4749999900.0%,"4,749g",10449049900.0%,"10,449g","10,999g",Tichondrius,0g,Realm 0\n' ..
    '14794,Protector Ankleguards,Armor,13,0.005,,uncommon,,"1,140g",1140066400.0%,"1,140g",30291291400.0%,"30,291g","31,885g","Aegwynn, Gurubashi, Bonechewer, Hakkar, Garrosh, Daggerspine",0g,Realm 0'

-- Synthetic genuine cross-realm flip: real buy realm + positive buy price.
-- Must still classify as flip so we don't regress real X-realm imports.
local REAL_FLIP_CSV = HEADER .. "\n" ..
    '15604,Ancient Defender of the Fireflash,Armor,13,0.01,,uncommon,,707g,707369900.0%,707g,1107.0%,"11,076g","11,659g",Stormrage,"1,000g",Area 52'

----------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------
print("FQ-208 import classification")

local items = Import:Parse(PLACEHOLDER_CSV)
check("placeholder CSV parses all 3 rows", #items == 3, "#items=" .. #items)
local allSell, anyBuyRealm = true, false
for _, it in ipairs(items) do
    if it.dealType ~= "sell" then allSell = false end
    if it.buyRealm and it.buyRealm ~= "" then anyBuyRealm = true end
end
check("Realm 0 / 0g rows -> dealType 'sell'", allSell)
check("Realm 0 / 0g rows -> no buyRealm carried", not anyBuyRealm)

local flips = Import:Parse(REAL_FLIP_CSV)
check("real X-realm CSV parses 1 row", #flips == 1, "#flips=" .. #flips)
check("real buy realm + price -> dealType 'flip'", flips[1] and flips[1].dealType == "flip",
    flips[1] and tostring(flips[1].dealType))
check("real X-realm -> buyRealm = Area 52", flips[1] and flips[1].buyRealm == "Area 52",
    flips[1] and tostring(flips[1].buyRealm))

-- Direct ParseGoldValue sanity (the guard's pivot)
check("ParseGoldValue('0g') == 0", ns:ParseGoldValue("0g") == 0)
check("ParseGoldValue('1,000g') == 1000", ns:ParseGoldValue("1,000g") == 1000)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
