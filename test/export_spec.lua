-- test/export_spec.lua
-- Headless coverage for Export:ExportSaved (FQ-238).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/export_spec.lua
--
-- The defect this guards against is not a crash and not missing data — it is
-- WRONG data leaving the addon. The saved inventory projection stores the
-- literal string "Unknown" as the name of anything the client had not cached
-- when the scan ran, and those rows went into the CSV players upload to
-- FlippingPal, where a placeholder is indistinguishable from a real item name.
-- One reporter's export carried it in 22 of the first 99 rows.
--
-- So the invariant is stated as an absolute: no row the export emits may carry
-- a placeholder name, in any column, ever. Everything else here — the skipped
-- count, the IDs handed back to request, the retry landing the row — exists to
-- make that invariant survivable rather than merely true.

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
-- Item cache stub
--------------------------

-- Only what the client has "loaded" answers GetItemInfo; everything else
-- returns nil exactly as an uncached item does in game.
local loaded = {}
local requested = {}

C_Item = {
    GetItemInfo = function(id)
        local e = loaded[id]
        if not e then return nil end
        -- name, link, quality, itemLevel, minLevel, type, subType, stackCount
        return e.name, "|Hitem:" .. tostring(id) .. "|h", e.quality, e.ilvl,
            1, "Armor", "Cloth", e.maxStack or 1
    end,
    RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end,
}

C_PetJournal = {
    GetPetInfoBySpeciesID = function(speciesID)
        if speciesID == 3022 then return "Shimmerbough Hoarder" end
        return nil
    end,
}

-- Export.lua builds its popup widgets at load time. This is a widget stub deep
-- enough to get through that and no deeper — nothing here is a UI assertion.
-- Getters answer 0, anything that creates a child hands back another stub.
local NewWidget
NewWidget = function()
    local w = {}
    setmetatable(w, {__index = function(t, k)
        local fn
        if k:find("^Create") or k:find("Texture") or k:find("Parent")
            or k:find("Region") or k:find("Object") then
            fn = function() return NewWidget() end
        elseif k:find("^Get") then fn = function() return 0 end
        else fn = function() return nil end end
        rawset(t, k, fn)
        return fn
    end})
    return w
end
CreateFrame = function() return NewWidget() end

local ns = { db = false }
function ns:GetCharKey() return "Cramerino-Executus" end
function ns:Print() end
function ns:PrintDebug() end
function ns:ParseItemLink(link) return tonumber(link:match("item:(%d+)")) end
ns.COLORS = setmetatable({}, {__index = function() return "" end})
ns.INVENTORY_BAGS, ns.REAGENT_BAG = {0, 1, 2, 3, 4}, 5
ns.BANK_TABS, ns.WARBANK_TABS = {6, 7}, {12, 13}

assert(loadfile("Export.lua"))("FlipQueue", ns)
local Export = ns.Export

--------------------------
-- Fixture
--------------------------

-- Two resolved items, one commodity, one cold item, one cold pet, one pet the
-- journal can still name. The cold pair is the population an inventory export
-- exists for: warbank and alt-bank contents the client has never loaded.
loaded[204915] = {name = "Deeprock Cape",    quality = 3, ilvl = 415}
loaded[3889]   = {name = "Russet Hat",       quality = 2, ilvl = 25}
loaded[2589]   = {name = "Linen Cloth",      quality = 1, ilvl = 1, maxStack = 200}

local function NewDB()
    return {
        characters = {
            ["Cramerino-Executus"] = {
                inventory = {
                    items = {
                        ["204915;;"]  = {itemID = 204915, name = "Deeprock Cape",
                                         bonusIDs = "", modifiers = "", locations = {bags = 1}},
                        ["3889;;"]    = {itemID = 3889, name = "Russet Hat",
                                         bonusIDs = "", modifiers = "", locations = {bags = 1}},
                        ["2589;;"]    = {itemID = 2589, name = "Linen Cloth",
                                         bonusIDs = "", modifiers = "", locations = {bags = 40}},
                        -- Cold: the projection stored the placeholder.
                        ["17016;;"]   = {itemID = 17016, name = "Unknown",
                                         bonusIDs = "", modifiers = "", locations = {bags = 1}},
                        -- Cold pet, but the journal can still name it.
                        ["pet:3022;;"] = {itemID = "pet:3022", name = "Unknown",
                                          bonusIDs = "q3", modifiers = "", locations = {bags = 1}},
                        -- Cold pet the journal does not know either.
                        ["pet:9999;;"] = {itemID = "pet:9999", name = "Unknown",
                                          bonusIDs = "q2", modifiers = "", locations = {bags = 1}},
                    },
                },
            },
        },
        warbank = {items = {}},
    }
end

ns.db = NewDB()

--------------------------
-- 1. No placeholder reaches the CSV
--------------------------

print("Export spec")

local csv, count, skipped, unresolved = Export:ExportSaved("bags")

check("no placeholder name in the CSV", csv:find("Unknown", 1, true), nil)
check("resolved items are exported", count, 3)   -- cape, hat, named pet
check("cold rows are counted as skipped", skipped, 2)  -- cold item + unnamed pet
check("cold item's ID is handed back to request", unresolved[1], 17016)
check("only the requestable ID is handed back", #unresolved, 1)

-- The commodity is excluded because GetItemInfo says maxStack > 1. Before the
-- fix an UNCACHED commodity slipped through this same check, since a nil
-- maxStack fails "> 1" just as a stack of one does.
check("commodity excluded", csv:find("Linen Cloth", 1, true), nil)
check("named-by-journal pet exported",
    csv:find("Shimmerbough Hoarder", 1, true) ~= nil, true)
check("cold item excluded from the file", csv:find("17016", 1, true), nil)

--------------------------
-- 2. Every emitted row is complete
--------------------------

-- ilvl 0 and an empty quality are the same defect wearing different clothes:
-- the row looks like data and is not. Nothing that survives the export may
-- carry either.
local rows, header = {}, true
for line in csv:gmatch("[^\n]+") do
    if header then header = false else rows[#rows + 1] = line end
end
check("row count matches reported count", #rows, count)

local allComplete = true
for _, line in ipairs(rows) do
    local id, name, quality, ilvl = line:match("([^;]*);([^;]*);([^;]*);([^;]*)")
    local isPet = id:find("^pet:") ~= nil
    if name == "" or name == "Unknown" or quality == "" or quality == "Unknown" then
        allComplete = false
    end
    -- Pets legitimately have no item level; items must have a real one.
    if not isPet and (tonumber(ilvl) or 0) <= 0 then allComplete = false end
end
check("every emitted row has name, quality and ilvl", allComplete, true)

--------------------------
-- 3. Requesting the data and exporting again lands the row
--------------------------

check("nothing requested yet", #requested, 0)
local n = Export:RequestItemData(unresolved)
check("request issued for the cold item", n, 1)
check("the right ID was requested", requested[1], 17016)

-- The client answers the request.
loaded[17016] = {name = "Dark Iron Destroyer", quality = 3, ilvl = 68}

local csv2, count2, skipped2, unresolved2 = Export:ExportSaved("bags")
check("retry exports the newly loaded item",
    csv2:find("Dark Iron Destroyer", 1, true) ~= nil, true)
check("retry count grows by one", count2, count + 1)
check("only the unnameable pet is still skipped", skipped2, 1)
check("nothing left to request", #unresolved2, 0)
check("still no placeholder after the retry", csv2:find("Unknown", 1, true), nil)

--------------------------
-- 4. A stored name is never trusted over the client's
--------------------------

-- The projection's stored name can be stale (a renamed item, or a placeholder
-- written before the client caught up). The client's answer is authoritative
-- when it has one, and the stored name is only a fallback.
ns.db.characters["Cramerino-Executus"].inventory.items["3889;;"].name = "Unknown"
local csv3 = Export:ExportSaved("bags")
check("placeholder is replaced by the client's name",
    csv3:find("Russet Hat", 1, true) ~= nil, true)
check("no placeholder survives a stale stored name",
    csv3:find("Unknown", 1, true), nil)

--------------------------
-- 5. Bound and untradeable items stay out, as before
--------------------------

local items = ns.db.characters["Cramerino-Executus"].inventory.items
items["204915;;"].bindType = 1      -- BoP
items["3889;;"].isBound = true
local csv4, count4 = Export:ExportSaved("bags")
check("BoP excluded", csv4:find("Deeprock Cape", 1, true), nil)
check("already-bound excluded", csv4:find("Russet Hat", 1, true), nil)
check("the rest still export", count4, 2)   -- pet + newly loaded item

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
