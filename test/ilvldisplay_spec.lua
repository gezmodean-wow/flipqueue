-- test/ilvldisplay_spec.lua
-- Item level beside gear names on to-do rows, and the tooltip's explicit
-- item-level line (FQ-258).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/ilvldisplay_spec.lua
--
-- The reporter saw "ilvl 44" on the tooltip of a deal FlippingPal recorded at a
-- much higher level. A FlippingPal website paste carries only a name and an
-- ilvl, so the task's itemKey IS the name: there are no bonus IDs to build a
-- variant link from, the tooltip falls back to the base item by ID, and the
-- client scales that to the viewing character. These checks pin that the
-- recorded import ilvl wins for display, that non-gear shows nothing, that the
-- tooltip says which number is the deal's, and that client calls are memoized.

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
-- Client stubs
--------------------------

-- itemID -> { classID, equipLoc }
local ITEMS = {
    [1001]   = { 4, "INVTYPE_LEGS" },      -- Glorious Legplates (armor)
    [1002]   = { 2, "INVTYPE_2HWEAPON" },  -- weapon
    [2001]   = { 7, "" },                  -- trade goods (commodity)
    [2002]   = { 9, "" },                  -- recipe
    [3001]   = { 1, "INVTYPE_BAG" },       -- container class, bag slot
    [3002]   = { 4, "INVTYPE_BAG" },       -- armor-classed bag slot: still no
    [170112] = { 2, "INVTYPE_POLEARM" },
}
local NAMES = { ["Glorious Legplates"] = 1001 }

local calls = { instant = 0, byName = 0, detailed = 0 }
local lateKnown = {}   -- itemIDs the client "learns" mid-test

C_Item = {
    GetItemInfoInstant = function(id)
        calls.instant = calls.instant + 1
        local e = ITEMS[id] or lateKnown[id]
        if not e then return nil end
        return id, "type", "subtype", e[2], 12345, e[1], 0
    end,
    GetItemIDForItemInfo = function(name)
        calls.byName = calls.byName + 1
        return NAMES[name]
    end,
}
-- The base item as a level-10 alt sees it: 44. The FQ-249 polearm's bonus
-- string: 74.
function GetDetailedItemLevelInfo(info)
    calls.detailed = calls.detailed + 1
    info = tostring(info)
    if info:find("6655") then return 74 end
    if info:find("1001") then return 44 end
    return nil
end

--------------------------
-- Load modules
--------------------------

local ns = { COLORS = { GRAY = "|cff888888", WHITE = "|cffffffff" } }
do
    local src = assert(io.open("Core.lua")):read("*a")
    local body = src:match("(function ns:ItemKeyToItemString%(itemKey%).-\nend)")
    assert(body, "could not locate ns:ItemKeyToItemString in Core.lua")
    assert(loadstring("local ns = ...\n" .. body))(ns)
end
assert(loadfile("ItemLevelDisplay.lua"))("flipqueue", ns)
local D = ns.IlvlDisplay
assert(D, "ItemLevelDisplay.lua did not register ns.IlvlDisplay")

ns.db = { imports = { fp = {} } }

local function Tooltip(link)
    local tt = { lines = {} }
    function tt:AddLine(text) self.lines[#self.lines + 1] = text end
    function tt:GetItem() return "name", link end
    return tt
end

print("ilvldisplay spec")

--------------------------
-- The reporter's case: name-keyed FlippingPal website deal
--------------------------

local fpTask = {
    itemKey      = "Glorious Legplates",   -- ProcessFPWebsiteBlock: itemKey = fullName
    itemID       = "",
    name         = "Glorious Legplates",
    ilvl         = 233,
    action       = "buy",
    importSource = "fp",
    importKey    = "glorious legplates:i233|realm",
}

check("name-keyed deal resolves an itemID by name", D:ResolveItemID(fpTask), 1001)
local iv, src = D:GetDisplayIlvl(fpTask)
check("display ilvl is the FlippingPal one", iv, 233)
check("...sourced from the import", src, "import")
check("row suffix", D:Suffix(fpTask), "|cff888888 (233)|r")
check("MiniView suffix resumes the row color", D:Suffix(fpTask, nil, "|cffffffff"),
    "|cff888888 (233)|cffffffff")

local tt = Tooltip("item:1001")
check("tooltip line added", D:AddTooltipLines(tt, fpTask), true)
check("tooltip names the import ilvl", tt.lines[1], "Item level from import: 233")
check("tooltip explains the scaled 44",
    tt.lines[2] ~= nil and tt.lines[2]:find("44", 1, true) ~= nil
        and tt.lines[2]:find("233", 1, true) ~= nil, true)

-- When the tooltip already agrees, no explanatory note.
local tt2 = Tooltip(nil)
D:AddTooltipLines(tt2, fpTask)
check("no scale note when tooltip has no item link", #tt2.lines, 1)

--------------------------
-- Source priority
--------------------------

-- A live import record beats the task's stored copy (re-imports update it).
ns.db.imports.fp["glorious legplates:i233|realm"] = { ilvl = 236 }
iv, src = D:GetTaskIlvl(fpTask)
check("live deal record wins", iv, 236)
check("...as import", src, "import")
ns.db.imports.fp["glorious legplates:i233|realm"] = nil

-- importKey suffix beats task.ilvl (a regenerate backfill could be scaled).
iv = D:GetTaskIlvl({ ilvl = 50, importKey = "x:i233|r", itemKey = "1001" })
check("importKey suffix beats stored task ilvl", iv, 233)

-- Stored task ilvl when there is no import trail.
iv, src = D:GetTaskIlvl({ ilvl = 210, itemKey = "1002" })
check("stored task ilvl", iv, 210)
check("...as task", src, "task")

--------------------------
-- Computed fallback, memoized
--------------------------

local polearm = { itemKey = "170112;6655:40:1678;9=50", itemID = "170112", name = "Polearm" }
local before = calls.detailed
iv, src = D:GetDisplayIlvl(polearm)
check("computed from the item key's bonus IDs", iv, 74)
check("...as computed", src, "computed")
D:GetDisplayIlvl(polearm); D:GetDisplayIlvl(polearm)
check("computed ilvl memoized per itemKey", calls.detailed - before, 1)

local tt3 = Tooltip("item:170112")
check("no tooltip line for a computed ilvl (tooltip already shows it)",
    D:AddTooltipLines(tt3, polearm), false)
check("...and nothing appended", #tt3.lines, 0)

--------------------------
-- Not gear: nothing shown
--------------------------

check("commodity: no suffix",
    D:Suffix({ itemKey = "2001", itemID = "2001", ilvl = 80, name = "Ore" }), "")
check("recipe: no suffix",
    D:Suffix({ itemKey = "2002", itemID = "2002", ilvl = 80, name = "Recipe" }), "")
check("bag: no suffix",
    D:Suffix({ itemKey = "3001", itemID = "3001", ilvl = 80, name = "Bag" }), "")
check("armor-class bag slot: no suffix",
    D:Suffix({ itemKey = "3002", itemID = "3002", ilvl = 80, name = "Bag" }), "")
check("battle pet: no suffix",
    D:Suffix({ itemKey = "pet:1965", itemID = "pet:1965", ilvl = 25, name = "Pet" }), "")
check("gear with no known ilvl: no suffix",
    D:Suffix({ itemKey = "1002", itemID = "1002", name = "Sword" }), "")
check("nil task: no suffix", D:Suffix(nil), "")
check("unresolvable name: no suffix",
    D:Suffix({ itemKey = "Unknown Thing", itemID = "", ilvl = 200, name = "Unknown Thing" }), "")

--------------------------
-- Gear-class lookups memoized; client misses retried
--------------------------

local instantBefore = calls.instant
for _ = 1, 5 do D:IsGear(1001); D:IsGear(2001) end
check("gear class memoized per itemID", calls.instant - instantBefore, 0)

check("unknown item is not gear", D:IsGear(4242), false)
lateKnown[4242] = { 4, "INVTYPE_HEAD" }
check("unknown item not cached: retried once the client knows it", D:IsGear(4242), true)

local byNameBefore = calls.byName
for _ = 1, 5 do D:ResolveItemID(fpTask) end
check("name -> itemID memoized", calls.byName - byNameBefore, 0)

-- hintID (TodoPage's LookupItemInfo result) short-circuits name resolution.
check("hintID wins", D:ResolveItemID({ name = "Whatever" }, 1002), 1002)

print(string.format("ilvldisplay spec: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
