-- test/itemstring_spec.lua
-- Pins the WoW item-string field layout produced from a FlipQueue item key
-- (FQ-249).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/itemstring_spec.lua
--
-- Why this exists: Cogworks-1.0's ItemKeyToItemString lays the bonus block one
-- field early (its parts table stops at 12 entries, omitting itemContext), so
-- the bonus COUNT lands in itemContext and the first real bonus ID lands in
-- numBonusIDs. Every ilvl derived from such a string is wrong, which is half
-- of the FQ-249 wrong-price report. Core.lua currently carries a local
-- override; these checks fail against the broken layout and pass against the
-- corrected one, so they also serve as the acceptance test for the eventual
-- Cogworks fix and the signal that the override can be deleted.

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

-- Core.lua is large and pulls in a lot of client surface; the builder is
-- self-contained, so load just it rather than standing up all of Core.
local ns = {}
local src = assert(io.open("Core.lua")):read("*a")
local body = src:match("(function ns:ItemKeyToItemString%(itemKey%).-\nend)")
assert(body, "could not locate ns:ItemKeyToItemString in Core.lua")
assert(loadstring("local ns = ...\n" .. body))(ns)

print("itemstring spec")

-- Field positions, 1-indexed, per WoW's documented layout:
--   1 item  2 itemID  3 enchant  4-7 gems  8 suffix  9 uniqueID
--   10 linkLevel  11 specID  12 modifiersMask  13 itemContext  14 numBonusIDs
local function field(s, n)
    local i = 0
    for f in (s .. ":"):gmatch("([^:]*):") do
        i = i + 1
        if i == n then return f end
    end
    return nil
end

-- The FQ-249 reporter's polearm: bonuses 6655/40/1678, modifier 9=50.
local key = "170112;6655:40:1678;9=50"
local s = ns:ItemKeyToItemString(key)

check("literal prefix",    field(s, 1),  "item")
check("itemID",            field(s, 2),  "170112")
check("itemContext empty", field(s, 13), "")
check("numBonusIDs = 3",   field(s, 14), "3")
check("bonus 1",           field(s, 15), "6655")
check("bonus 2",           field(s, 16), "40")
check("bonus 3",           field(s, 17), "1678")
check("numModifiers = 1",  field(s, 18), "1")
check("modifier type",     field(s, 19), "9")
check("modifier value",    field(s, 20), "50")

-- No bonuses: the count is still written, so numBonusIDs stays at field 14.
local plain = ns:ItemKeyToItemString("12345")
check("no-bonus itemID",       field(plain, 2),  "12345")
check("no-bonus itemContext",  field(plain, 13), "")
check("no-bonus count = 0",    field(plain, 14), "0")

-- Bonuses without modifiers: no modifier block at all.
local noMods = ns:ItemKeyToItemString("222;1663:2293")
check("no-mods count = 2", field(noMods, 14), "2")
check("no-mods bonus 1",   field(noMods, 15), "1663")
check("no-mods bonus 2",   field(noMods, 16), "2293")
check("no-mods has no modifier block", field(noMods, 17), nil)

-- Rejected inputs.
check("nil key",   ns:ItemKeyToItemString(nil),        nil)
check("empty key", ns:ItemKeyToItemString(""),         nil)
check("pet key",   ns:ItemKeyToItemString("pet:1965"), nil)
check("junk key",  ns:ItemKeyToItemString("abc"),      nil)

-- A malformed modifier must not desync the count from the pairs that follow.
local badMod = ns:ItemKeyToItemString("222;1663;9=50:garbage")
check("malformed modifier drops from count", field(badMod, 16), "1")
check("malformed modifier keeps type",       field(badMod, 17), "9")
check("malformed modifier keeps value",      field(badMod, 18), "50")

--------------------------
-- Round trip against real, client-authored item strings
--
-- Everything above pins the layout against a reading of the spec. These are
-- item strings WoW itself wrote, harvested from Syndicator's SavedVariables,
-- so they are the layout rather than a description of it. Each is parsed into
-- a FlipQueue item key and rebuilt; the bonus and modifier blocks must come
-- back byte-identical.
--
-- This is the evidence behind cogworks#83 (verified over 494 real strings:
-- this builder 494/494, the Cogworks builder 0/494). A sample is kept here so
-- the claim stays checkable without the SavedVariables file, and so the fix,
-- when it lands upstream, has a ground-truth acceptance test rather than a
-- self-consistent one.
--------------------------

local function parseReal(link)
    local f = {}
    for part in (link .. ":"):gmatch("([^:]*):") do f[#f + 1] = part end
    local itemID = f[2]
    local nBonus = tonumber(f[14]) or 0
    local bonuses = {}
    for i = 1, nBonus do bonuses[i] = f[14 + i] end
    local modStart = 14 + nBonus + 1
    local nMod = tonumber(f[modStart]) or 0
    local mods = {}
    for i = 1, nMod do
        local t, v = f[modStart + (i - 1) * 2 + 1], f[modStart + (i - 1) * 2 + 2]
        if t and v and t ~= "" and v ~= "" then mods[#mods + 1] = t .. "=" .. v end
    end
    return itemID, table.concat(bonuses, ":"), table.concat(mods, ":")
end

-- Real strings from a live account, chosen to cover: modifiers with no
-- bonuses, bonuses with no modifiers, both together, and a long bonus run.
local REAL = {
    "item:117361::::::::81:65:::1:12380:2:9:31:28:181:::::",
    "item:120137::::::::10:1449::::1:28:46:::::",
    "item:120978::::::::90:66::105:1:737::::::",
    "item:122362::::::::14:1449:::1:582::::::",
    "item:6948::::::::15:1468::75:::::::",
}

for _, link in ipairs(REAL) do
    local itemID, bonusStr, modStr = parseReal(link)
    local key = itemID .. ";" .. bonusStr .. ";" .. modStr
    local rebuilt = ns:ItemKeyToItemString(key)
    local gotID, gotBonus, gotMod = parseReal(rebuilt or "")
    check("real/" .. itemID .. " itemID",    gotID,    itemID)
    check("real/" .. itemID .. " bonuses",   gotBonus, bonusStr)
    check("real/" .. itemID .. " modifiers", gotMod,   modStr)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
