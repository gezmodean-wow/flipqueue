-- test/taskonlydeposit_spec.lua
-- Headless coverage for "deposit only task items" (FQ-260).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/taskonlydeposit_spec.lua
--
-- The report: with tasks queued for the warbank, Execute also swept every
-- other sellable item out of the player's bags. The off switch already existed
-- (extrasMode = "disabled") but only on the Characters page; Settings now
-- carries it too. These checks pin the planner behaviour the switch relies on:
--   * Off       -> the extras planner proposes nothing (tasks-only)
--   * Manual    -> extras are planned (they land in the Execute batch)
--   * a per-character override beats the global value, both ways
--   * task items are never proposed as extras

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
-- WoW API stubs for the bag walk
--------------------------

-- Bag 0 holds: a task item (1001), a flask the player keeps using (2002),
-- and a trade good (3003, a reagent — never an extra).
local BAG = {
    [1] = { hyperlink = "|Hitem:1001::::::::|h[Task Sword]|h", stackCount = 1, iconFileID = 1 },
    [2] = { hyperlink = "|Hitem:2002::::::::|h[Flask]|h",      stackCount = 5, iconFileID = 2 },
    [3] = { hyperlink = "|Hitem:3003::::::::|h[Ore]|h",        stackCount = 20, iconFileID = 3 },
}
local CLASS = { [1001] = 2, [2002] = 0, [3003] = 7 }

Enum = { ItemClass = { Tradegoods = 7 } }
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 3 or 0 end,
    GetContainerItemInfo = function(bag, slot) return bag == 0 and BAG[slot] or nil end,
}
local function idOf(link) return tonumber(link:match("item:(%d+)")) end
-- No global GetItemInfo: the live client (Interface 120005) removed it, and a
-- bare call is what broke every deposit in FQ-272. Only C_Item exists here.
C_Item = { GetItemInfo = function(link)
    return link:match("%[(.-)%]"), nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, CLASS[idOf(link)]
end }

--------------------------
-- Namespace
--------------------------

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "" end})
ns.ALL_PLAYER_BAGS = { 0 }
ns.REAGENT_BAG = 5
function ns:Print() end
function ns:PrintDebug() end
function ns:GetCharKey() return "Main-Sargeras" end
function ns:MakeItemKey(id, b, m) return tostring(id) .. ";" .. (b or "") .. ";" .. (m or "") end
function ns:ParseItemLink(link) return tostring(idOf(link)), "", "" end
function ns:GetCharSetting(charKey, key)
    local c = self.db.characters[charKey]
    if c and c.settings and c.settings[key] ~= nil then return c.settings[key] end
    return self.db.settings[key]
end
ns.TodoList = {
    GetCharacterTasks = function()
        return { { item = { itemKey = "1001;;", name = "Task Sword", quantity = 1 } } }
    end,
}

assert(loadfile("Tracker.lua"))("FlipQueue", ns)
local Tracker = ns.Tracker

local function Plan(globalMode, charMode)
    ns.db = {
        settings = { manageItems = true, extrasMode = globalMode },
        characters = { ["Main-Sargeras"] = { settings = { extrasMode = charMode } } },
    }
    return Tracker:BuildExtraDepositOps({})
end

local function names(ops)
    local t = {}
    for _, op in ipairs(ops) do t[#t + 1] = op.name end
    return table.concat(t, ",")
end

-- Off = tasks only: the planner proposes nothing.
check("global Off plans no extras", #Plan("disabled", nil), 0)

-- Manual = extras planned for the Execute batch; the task item and the
-- reagent are not among them.
check("global Manual plans the non-task, non-reagent item", names(Plan("manual", nil)), "Flask")
check("global Auto plans the same set", names(Plan("auto", nil)), "Flask")

-- Per-character override wins over the global value, in both directions.
check("char Off beats global Manual", #Plan("manual", "disabled"), 0)
check("char Manual beats global Off", names(Plan("disabled", "manual")), "Flask")

-- Master switch off silences extras whatever the mode says.
ns.db = {
    settings = { manageItems = false, extrasMode = "auto" },
    characters = { ["Main-Sargeras"] = {} },
}
check("manageItems off plans no extras", #Tracker:BuildExtraDepositOps({}), 0)

-- Off is reported as "disabled" so the popup, drawer and auto-deposit all
-- agree with the planner.
Plan("disabled", nil)
check("action mode reads disabled", Tracker:GetActionMode("Main-Sargeras", "extras"), "disabled")

print(string.format("taskonlydeposit_spec: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
