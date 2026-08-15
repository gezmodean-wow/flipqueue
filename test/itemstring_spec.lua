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

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
