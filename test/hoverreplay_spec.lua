-- test/hoverreplay_spec.lua
-- Headless coverage for UI.ReplayHover and its use in ScrollTable:Render
-- (FQ-259).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/hoverreplay_spec.lua
--
-- Report: hovering an item on the to-do list showed its tooltip for a moment,
-- then it disappeared. Every refresh (bag update, sync delta, auction event)
-- hides and re-shows the rows. The tooltip hides along with its owner row, and
-- since the mouse never left the row the client fires no new OnEnter. The fake
-- frames below model exactly that: hiding a row that owns GameTooltip hides
-- the tooltip, and nothing re-enters on Show.

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

-- GameTooltip: tracks owner + visibility.
GameTooltip = { owner = nil, shown = false, text = nil }
function GameTooltip:SetOwner(o) self.owner = o; self.text = nil end
function GameTooltip:SetText(t) self.text = t end
function GameTooltip:SetHyperlink(s) self.text = s end
function GameTooltip:SetItemByID(id) self.text = "item:" .. id end
function GameTooltip:AddLine() end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end

local function Noop() end
local function Stub()
    return { SetText = Noop, SetWidth = Noop, SetPoint = Noop, ClearAllPoints = Noop,
             SetColorTexture = Noop, Hide = Noop, Show = Noop, SetTexture = Noop }
end

-- A row frame. mouseOver models IsMouseOver's geometry test only.
local function FakeRow()
    local r = { _scripts = {}, shown = false, mouseOver = false,
                cells = { Stub() }, _cellClips = { Stub() }, icon = Stub() }
    r.bg = { alpha = 0 }
    function r.bg:SetColorTexture(_, _, _, a) self.alpha = a end
    function r:SetScript(k, fn) self._scripts[k] = fn end
    function r:GetScript(k) return self._scripts[k] end
    function r:Show() self.shown = true end
    function r:Hide()
        self.shown = false
        -- Engine behaviour: a tooltip hides with its owner.
        if GameTooltip.owner == self then GameTooltip:Hide() end
    end
    function r:IsVisible() return self.shown end
    function r:IsMouseOver() return self.mouseOver end
    return r
end

local focus = {}
GetMouseFoci = function() return focus end

-- Load ScrollTable.lua, capturing the private mixin when CreateScrollTable
-- builds an instance (Init needs real frames, so it is short-circuited).
local ns = { UI = {} }
assert(loadfile("UI/ScrollTable.lua"))("FlipQueue", ns)
local UI = ns.UI

local mixin
do
    local realSetmetatable = setmetatable
    setmetatable = function(t, mt)
        if mt and mt.__index and mt.__index.Render then mixin = mt.__index end
        return realSetmetatable(t, mt)
    end
    pcall(UI.CreateScrollTable, UI, nil, {})
    setmetatable = realSetmetatable
end
assert(mixin, "could not capture ScrollTableMixin")

local function NewTable(n)
    local tbl = setmetatable({
        rows = {}, columns = { { key = "name", width = 100 } },
        content = { SetHeight = Noop },
    }, { __index = mixin })
    tbl.UpdateHeaderArrows = Noop
    tbl.UpdateScrollBarVisibility = Noop
    local data = {}
    for i = 1, n do
        tbl.rows[i] = FakeRow()
        data[i] = { name = "Item " .. i, _tooltipItemID = 1000 + i }
    end
    return tbl, data
end

--------------------------
-- Refresh while hovering restores the tooltip
--------------------------
do
    local tbl, data = NewTable(3)
    tbl:SetData(data)
    local row = tbl.rows[2]
    row.mouseOver = true
    focus = { row }
    row:GetScript("OnEnter")(row)
    check("hover shows tooltip", GameTooltip.shown, true)
    check("hover owner is row", GameTooltip.owner, row)

    -- A refresh rebuilds the table; the row hides (tooltip dies) and returns.
    tbl:SetData(data)
    check("refresh keeps tooltip shown", GameTooltip.shown, true)
    check("refresh keeps owner on hovered row", GameTooltip.owner, row)
    check("refresh keeps tooltip content", GameTooltip.text, "item:1002")
    check("refresh keeps row highlight", row.bg.alpha, 0.08)
end

--------------------------
-- Refresh that reorders data shows the row's NEW item
--------------------------
do
    local tbl, data = NewTable(2)
    tbl:SetData(data)
    local row = tbl.rows[1]
    row.mouseOver = true
    focus = { row }
    row:GetScript("OnEnter")(row)
    tbl:SetData({ data[2], data[1] })
    check("reordered refresh shows current row item", GameTooltip.text, "item:1002")
end

--------------------------
-- Something layered over the row: no tooltip
--------------------------
do
    GameTooltip:Hide(); GameTooltip.owner = nil
    local tbl, data = NewTable(2)
    tbl:SetData(data)
    local row = tbl.rows[1]
    row.mouseOver = true
    focus = { {} }  -- a popup has the mouse
    tbl:SetData(data)
    check("covered row does not open tooltip", GameTooltip.shown, false)
end

--------------------------
-- Mouse elsewhere: no tooltip
--------------------------
do
    GameTooltip:Hide(); GameTooltip.owner = nil
    local tbl, data = NewTable(2)
    focus = {}
    tbl:SetData(data)
    check("unhovered refresh opens no tooltip", GameTooltip.shown, false)
end

--------------------------
-- ReplayHover edge cases + pre-11.0 GetMouseFocus fallback
--------------------------
do
    local hits = 0
    local r = FakeRow()
    r:SetScript("OnEnter", function() hits = hits + 1 end)
    r.mouseOver = true
    focus = { r }
    UI.ReplayHover(nil)
    UI.ReplayHover(r)  -- hidden
    check("hidden row is not replayed", hits, 0)
    r:Show()
    UI.ReplayHover(r)
    check("visible hovered row is replayed", hits, 1)

    GetMouseFoci = nil
    GetMouseFocus = function() return r end
    UI.ReplayHover(r)
    check("GetMouseFocus fallback replays", hits, 2)
    GetMouseFocus = function() return nil end
    UI.ReplayHover(r)
    check("GetMouseFocus fallback respects focus", hits, 2)
end

print(string.format("hoverreplay_spec: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
