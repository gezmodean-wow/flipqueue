-- test/tooldispatch_spec.lua
-- Headless coverage for TR:ApplySecureDispatch and TR:EvalMethod's dispatch
-- fields (FQ-219).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/tooldispatch_spec.lua
--
-- A mailbox toy was dispatched as type="item" with the toy's NAME, which the
-- secure handler resolves against your bags. A learned toy is in the toy box,
-- not a bag, so the click resolved to nothing and silently did nothing — and
-- because hovering the button had already opened the method rollout, the only
-- visible response to a click was a menu appearing. Hence the report: "clicking
-- opens the method menu instead of triggering the action".
--
-- This spec pins the two halves that have to agree: the attribute set written
-- for each dispatch kind, and the value EvalMethod hands over for a toy (the
-- ID, not the name — the name is for the player, not the secure handler).

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

local ns = { UI = {} }
assert(loadfile("UI/ToolRegistry.lua"))("FlipQueue", ns)
local TR = ns.ToolRegistry

-- A stand-in for a SecureActionButton: records the attributes written to it.
local function FakeButton()
    local b = { attrs = {} }
    function b:SetAttribute(k, v) self.attrs[k] = v end
    return b
end

--------------------------
-- Attribute sets per kind
--------------------------

local btn = FakeButton()
TR:ApplySecureDispatch(btn, "toy", 64488)
check("toy sets type=toy", btn.attrs.type, "toy")
check("toy carries the ID", btn.attrs.toy, 64488)
check("toy does not also set item", btn.attrs.item, nil)
check("toy does not set spell", btn.attrs.spell, nil)

-- The ID may arrive as a string from a stored setting.
btn = FakeButton()
TR:ApplySecureDispatch(btn, "toy", "64488")
check("string toy ID is normalized to a number", btn.attrs.toy, 64488)

btn = FakeButton()
TR:ApplySecureDispatch(btn, "item", "Hearthstone")
check("item sets type=item", btn.attrs.type, "item")
check("item carries the name", btn.attrs.item, "Hearthstone")
check("item does not set toy", btn.attrs.toy, nil)

btn = FakeButton()
TR:ApplySecureDispatch(btn, "spell", "Ritual of Summoning")
check("spell sets type=spell", btn.attrs.type, "spell")
check("spell carries the name", btn.attrs.spell, "Ritual of Summoning")

btn = FakeButton()
TR:ApplySecureDispatch(btn, "macro", "MyMacro")
check("macro sets type=macro", btn.attrs.type, "macro")
check("macro carries the name", btn.attrs.macro, "MyMacro")

btn = FakeButton()
TR:ApplySecureDispatch(btn, "macrotext", "/reload")
check("macrotext sets type=macro", btn.attrs.type, "macro")
check("macrotext carries the body", btn.attrs.macrotext, "/reload")

--------------------------
-- Clearing, and never leaving a stale attribute behind
--------------------------

-- A button is reused across refreshes: a toy that becomes an item must not keep
-- its toy attribute, or the secure handler fires the previous method.
btn = FakeButton()
TR:ApplySecureDispatch(btn, "toy", 64488)
TR:ApplySecureDispatch(btn, "item", "Hearthstone")
check("switching toy -> item clears toy", btn.attrs.toy, nil)
check("...and sets the item", btn.attrs.item, "Hearthstone")

TR:ApplySecureDispatch(btn, nil, nil)
check("clearing drops type", btn.attrs.type, nil)
check("clearing drops item", btn.attrs.item, nil)
check("clearing drops toy", btn.attrs.toy, nil)
check("clearing drops spell", btn.attrs.spell, nil)
check("clearing drops macro", btn.attrs.macro, nil)
check("clearing drops macrotext", btn.attrs.macrotext, nil)

btn = FakeButton()
TR:ApplySecureDispatch(btn, "toy", nil)
check("a kind with no value clears rather than half-arms", btn.attrs.type, nil)

--------------------------
-- EvalMethod hands over the right value
--------------------------

-- Owned toy, with the client able to name it.
PlayerHasToy = function(id) return id == 64488 end
C_Container = { GetItemCooldown = function() return 0, 0 end }
C_Item = {
    GetItemIconByID = function() return 12345 end,
    GetItemInfo = function() return "Der Wirtstochter" end,   -- localized name
}

local e = TR:EvalMethod({ kind = "toy", id = 64488, name = "The Innkeeper's Daughter" })
check("toy is owned", e.owned, true)
check("toy dispatches as a toy", e.dispatchKind, "toy")
check("toy dispatch value is the ID", e.dispatchValue, 64488)
check("toy label is the localized name", e.dispatchName, "Der Wirtstochter")

-- An unowned toy must not arm anything.
local unowned = TR:EvalMethod({ kind = "toy", id = 99999, name = "Not Learned" })
check("unowned toy is not owned", unowned.owned, false)

--------------------------
-- Clean Up Trapped drawer tool (FQ-264)
--------------------------

local function has(list, id)
    for _, d in ipairs(list) do if d.id == id then return true end end
    return false
end

-- An install seeded before the tool existed: eight tools in the saved order,
-- mailbox shown again by the player, no knownBuiltins yet.
ns.db = { settings = { toolbox = {
    order = { "logout", "reload", "ah", "vendor", "warbank", "hearthstone", "mailbox", "bank" },
    hidden = { bank = true },
} } }
check("existing install: cleanup is listed for settings",
    has(TR:GetAllTools(), "cleanup"), true)
check("existing install: cleanup starts hidden in the drawer",
    has(TR:GetTools(), "cleanup"), false)
check("existing install: the player's unhidden mailbox stays visible",
    has(TR:GetTools(), "mailbox"), true)
check("existing install: bank stays hidden", has(TR:GetTools(), "bank"), false)

-- The player turns it on; a later load must not hide it again.
ns.db.settings.toolbox.hidden.cleanup = nil
check("after enabling: cleanup shows in the drawer",
    has(TR:GetTools(), "cleanup"), true)

-- A fresh install gets the shipped defaults, cleanup included and hidden.
ns.db = { settings = {} }
check("fresh install: default order ends with cleanup",
    TR.DEFAULT_ORDER[#TR.DEFAULT_ORDER], "cleanup")
check("fresh install: cleanup hidden by default", has(TR:GetTools(), "cleanup"), false)
check("fresh install: cleanup in the settings list",
    has(TR:GetAllTools(), "cleanup"), true)

-- The tool itself: previews and asks, never removes without the confirm.
local cleanupTool
for _, d in ipairs(TR:GetAllTools()) do if d.id == "cleanup" then cleanupTool = d end end
check("cleanup tool is an action", cleanupTool and cleanupTool.type, "action")
local prints, purged, dialog = {}, 0, nil
ns.COLORS = setmetatable({}, { __index = function() return "" end })
function ns:Print(msg) prints[#prints + 1] = msg end
ns.TodoList = {
    TRAPPED_LABELS = { ["item-gone"] = "item is not on any character, bank or warbank" },
    ClassifyTasks = function() return { trappedCount = 2, byReason = { ["item-gone"] = 2 } } end,
    PurgeTrappedAndReport = function() purged = purged + 1 return 2 end,
}
ns.cw = { ShowConfirmDialog = function(_, title, message, onConfirm) dialog = { title = title, message = message, onConfirm = onConfirm } end }
cleanupTool.onUse()
check("click opens a confirm dialog", dialog ~= nil, true)
check("dialog counts the tasks", dialog and dialog.message:find("Remove 2 trapped task", 1, true) ~= nil, true)
check("dialog lists the reason", dialog and dialog.message:find("2 × item is not on any character", 1, true) ~= nil, true)
check("nothing removed before confirming", purged, 0)
dialog.onConfirm()
check("confirm removes", purged, 1)

-- Nothing trapped: say so, no dialog.
dialog = nil
ns.TodoList.ClassifyTasks = function() return { trappedCount = 0, byReason = {} } end
cleanupTool.onUse()
check("nothing trapped: no dialog", dialog, nil)
check("nothing trapped: player told", prints[#prints]:find("No trapped tasks", 1, true) ~= nil, true)

print(string.format("tooldispatch_spec: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
