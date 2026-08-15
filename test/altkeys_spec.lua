-- test/altkeys_spec.lua
-- Pins Syndicator -> FlipQueue character-key translation (FQ-251).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/altkeys_spec.lua
--
-- Syndicator keys characters by normalized realm ("Jimmy-EarthenRing");
-- FlipQueue keys by display realm ("Jimmy-Earthen Ring"). The alias map that
-- bridged them only ever learned the realm the player was logged into, so any
-- character on a realm not visited since that feature shipped was skipped by
-- the bulk projection — silently, which is why a quarter of one reporter's
-- inventory never updated. These checks pin the fallback that resolves such a
-- character against the records FlipQueue already holds.

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

-- Scanner.lua pulls in Syndicator and the client frame API at load; the
-- translation block is self-contained, so lift just it.
local ns = {}
local src = assert(io.open("Scanner.lua")):read("*a")
local block = src:match("(local function SyndicatorRealmForm.-\nend)\n\n%-%- Core projection writer")
    or src:match("(local function SyndicatorRealmForm.-return fqKey\nend)")
assert(block, "could not locate the key-translation block in Scanner.lua")

-- Accent folding + lowercasing, matching Core.lua's NormalizeAccents contract.
local ACCENTS = { ["é"]="e", ["è"]="e", ["ê"]="e", ["ë"]="e", ["á"]="a",
                  ["à"]="a", ["â"]="a", ["ä"]="a", ["ö"]="o", ["ü"]="u", ["ß"]="ss" }
function ns:NormalizeRealmKey(s)
    if not s then return "" end
    local out = s
    for k, v in pairs(ACCENTS) do out = out:gsub(k, v) end
    return out:lower()
end

local chunk = assert(loadstring("local ns = ...\n" .. block .. "\nreturn SyndicatorRealmForm, TranslateSyndicatorKey"))
local RealmForm, Translate = chunk(ns)

print("altkeys spec")

--------------------------
-- Realm folding
--------------------------

check("space removed",      RealmForm("Earthen Ring"),   "earthenring")
check("already compact",    RealmForm("EarthenRing"),    "earthenring")
check("apostrophe removed", RealmForm("Zul'jin"),        "zuljin")
check("accents folded",     RealmForm("Confrérie du Thorium"), "confrerieduthorium")
check("parens removed",     RealmForm("Aggra (Português)"),   "aggraportugues")
check("empty realm",        RealmForm(""),               nil)
check("nil realm",          RealmForm(nil),              nil)

--------------------------
-- Translation
--------------------------

ns.db = {
    realmAliases = { Stormrage = "Stormrage" },
    characters = {
        ["Lissandrya-Illidan"]     = {},
        ["Jimmy-Earthen Ring"]     = {},
        ["Fritz-Die Silberne Hand"]= {},
        ["Zed-Zul'jin"]            = {},
    },
}

-- 1. Alias map hit: the pre-existing fast path is untouched.
check("alias-map hit", Translate("Bob-Stormrage"), "Bob-Stormrage")

-- 2. The FQ-251 fallback: realm absent from the alias map, but FlipQueue
--    already holds a record for the character.
check("fallback: spaced realm",    Translate("Jimmy-EarthenRing"),      "Jimmy-Earthen Ring")
check("fallback: compact realm",   Translate("Lissandrya-Illidan"),     "Lissandrya-Illidan")
check("fallback: multiword realm", Translate("Fritz-DieSilberneHand"),  "Fritz-Die Silberne Hand")
check("fallback: apostrophe",      Translate("Zed-Zuljin"),             "Zed-Zul'jin")

-- 3. Resolving heals the alias map, so the next character on that realm
--    takes the fast path without needing its own record.
check("alias healed", ns.db.realmAliases.EarthenRing, "Earthen Ring")

-- 4. Unknown character on an unknown realm must still be skipped rather than
--    guessed: writing to a guessed key splits that character's data.
check("unknown stays nil", Translate("Ghost-NeverSeenRealm"), nil)
check("malformed key",     Translate("NoRealmHere"),          nil)
check("nil key",           Translate(nil),                    nil)

-- 5. A newly appearing character is picked up (index rebuilds on size change).
ns.db.characters["Nova-Twisting Nether"] = {}
check("new character resolves", Translate("Nova-TwistingNether"), "Nova-Twisting Nether")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
