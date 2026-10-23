-- test/pullwave_spec.lua
-- Headless coverage for ns:PlanPullWave (FQ-233).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/pullwave_spec.lua
--
-- The reported failure was 304 pull tasks planned against 164 free bag slots:
-- the run filled the bags, hit ERR_INV_FULL, and the reactive backstop dropped
-- every remaining pull with no warning and nothing to tell the player what had
-- happened. Capping is the obvious half. The half that decides whether a capped
-- wave is any use is the ORDER — 164 slots of items spread across every target
-- realm means no realm's posting can be finished, so the player is no further
-- forward than before.

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

-- Core.lua is loaded for the helper alone; everything it touches at load time
-- is table setup.
local ns = {}
assert(loadfile("Core.lua"))("FlipQueue", ns)

check("helper is exposed", type(ns.PlanPullWave), "function")

--------------------------
-- Fixture
--------------------------

-- Emission order is bank-scan order: bag index then slot, which interleaves
-- realms exactly as a real bank does.
local function NewOps()
    local rows = {
        {realm = "Sargeras",  char = "Alt-Sargeras",   name = "Thorium Helm"},
        {realm = "Proudmoore", char = "Main-Proudmoore", name = "Russet Hat"},
        {realm = "Sargeras",  char = "Alt-Sargeras",   name = "Aquamarine"},
        {realm = "Executus",  char = "Flip-Executus",  name = "Frozen Shield"},
        {realm = "Proudmoore", char = "Main-Proudmoore", name = "Blue Overalls"},
        {realm = "Executus",  char = "Flip-Executus",  name = "Jeweled Dagger"},
        {realm = "Proudmoore", char = "Second-Proudmoore", name = "Copper Bar"},
    }
    local ops = {}
    for i, r in ipairs(rows) do
        ops[i] = {op = "pull", name = r.name, srcBag = 6, srcSlot = i,
                  _realm = r.realm, _char = r.char, _seq = i}
    end
    return ops
end

local function realmsOf(ops)
    local seen = {}
    for _, op in ipairs(ops) do seen[#seen + 1] = op._realm end
    return table.concat(seen, ",")
end

--------------------------
-- 1. A capped wave closes out whole realms
--------------------------

print("PlanPullWave spec")

local ops, planned, free = ns:PlanPullWave(NewOps(), 3)
check("planned total is what the list wanted", planned, 7)
check("free slots reported back", free, 3)
check("wave is capped to the bags", #ops, 3)

-- Executus has exactly two pulls; a three-slot wave must finish it rather
-- than take one item from each of three realms.
check("wave finishes a realm instead of sampling all of them",
    realmsOf(ops), "Executus,Executus,Proudmoore")

--------------------------
-- 2. Within a realm, ordering is by character then name
--------------------------

ops = ns:PlanPullWave(NewOps(), 99)
local order = {}
for _, op in ipairs(ops) do order[#order + 1] = op._realm .. "/" .. op._char .. "/" .. op.name end
check("grouped realm, then character, then item",
    table.concat(order, " | "),
    "Executus/Flip-Executus/Frozen Shield | Executus/Flip-Executus/Jeweled Dagger | "
    .. "Proudmoore/Main-Proudmoore/Blue Overalls | Proudmoore/Main-Proudmoore/Russet Hat | "
    .. "Proudmoore/Second-Proudmoore/Copper Bar | "
    .. "Sargeras/Alt-Sargeras/Aquamarine | Sargeras/Alt-Sargeras/Thorium Helm")

--------------------------
-- 3. Ordering is deterministic across calls
--------------------------

-- table.sort is not stable, so ties must be broken explicitly or the popup
-- reshuffles under the player between redraws of the same plan.
local dupes = {}
for i = 1, 12 do
    dupes[i] = {op = "pull", name = "Arcane Crystal", srcBag = 6, srcSlot = i,
                _realm = "Sargeras", _char = "Alt-Sargeras", _seq = i}
end
local first = ns:PlanPullWave(dupes, 12)
local firstSeq = {}
for _, op in ipairs(first) do firstSeq[#firstSeq + 1] = op._seq end

local dupes2 = {}
for i = 1, 12 do
    dupes2[i] = {op = "pull", name = "Arcane Crystal", srcBag = 6, srcSlot = i,
                 _realm = "Sargeras", _char = "Alt-Sargeras", _seq = i}
end
local second = ns:PlanPullWave(dupes2, 12)
local secondSeq = {}
for _, op in ipairs(second) do secondSeq[#secondSeq + 1] = op._seq end
check("identical plans order identically",
    table.concat(firstSeq, ","), table.concat(secondSeq, ","))
check("ties keep emission order", table.concat(firstSeq, ","), "1,2,3,4,5,6,7,8,9,10,11,12")

--------------------------
-- 4. Boundaries
--------------------------

ops, planned = ns:PlanPullWave(NewOps(), 7)
check("exact fit is not truncated", #ops, 7)
check("exact fit still reports the total", planned, 7)

ops, planned = ns:PlanPullWave(NewOps(), 100)
check("more room than work leaves everything", #ops, 7)

-- Full bags: the caller has to be able to tell "nothing to pull" from "nowhere
-- to put it", so an empty wave still reports what was wanted.
ops, planned, free = ns:PlanPullWave(NewOps(), 0)
check("no room means no wave", #ops, 0)
check("but the planned total survives", planned, 7)
check("and free slots are reported", free, 0)

-- Defensive: a nil or negative slot count must not produce a negative loop or
-- leak the uncapped plan through.
ops, planned = ns:PlanPullWave(NewOps(), nil)
check("nil free slots is treated as none", #ops, 0)
check("nil free slots still reports the total", planned, 7)
ops = ns:PlanPullWave(NewOps(), -5)
check("negative free slots is treated as none", #ops, 0)

check("empty plan stays empty", #(ns:PlanPullWave({}, 10)), 0)
local _, emptyPlanned = ns:PlanPullWave({}, 10)
check("empty plan reports nothing planned", emptyPlanned, 0)

--------------------------
-- 5. Partial-stack credit (FQ-254)
--------------------------

-- Shylynce: a few items left behind on the first bank visit, finished on the
-- second. The cap counted empty slots alone, so pulls that would have merged
-- into partial stacks in the bags were cut off by exactly that many.
local function StackOps()
    local rows = {
        {name = "Arcane Crystal", id = 101, qty = 5},   -- merges: 20 room
        {name = "Frozen Shield",  id = 201, qty = 1},   -- needs a slot
        {name = "Jeweled Dagger", id = 202, qty = 1},   -- needs a slot
        {name = "Thorium Bar",    id = 102, qty = 10},  -- merges: 10 room
        {name = "Thorium Ore",    id = 103, qty = 20},  -- 5 room: too big, needs a slot
    }
    local ops = {}
    for i, r in ipairs(rows) do
        ops[i] = {op = "pull", name = r.name, srcBag = 6, srcSlot = i, quantity = r.qty,
                  _realm = "Sargeras", _char = "Alt-Sargeras", _seq = i, _itemID = r.id}
    end
    return ops
end
local ROOM = { [101] = 20, [102] = 10, [103] = 5 }

local function namesOf(ops)
    local out = {}
    for _, op in ipairs(ops) do out[#out + 1] = op.name end
    return table.concat(out, ",")
end

-- Two free slots, five pulls: without the credit the wave is two items; with it
-- the two merges ride along for free and the wave is four.
ops, planned, free = ns:PlanPullWave(StackOps(), 2)
check("no room table: slots alone cap the wave", #ops, 2)

ops, planned, free = ns:PlanPullWave(StackOps(), 2, ROOM)
check("merging pulls take no slot", #ops, 4)
check("the two slots go to the first non-merging pulls, merges ride along",
    namesOf(ops), "Arcane Crystal,Frozen Shield,Jeweled Dagger,Thorium Bar")
check("planned total unchanged", planned, 5)
check("free slots reported as counted", free, 2)

-- Room is consumed: a second stack of the same item only merges if room remains.
local twice = StackOps()
twice[#twice + 1] = {op = "pull", name = "Arcane Crystal", srcBag = 6, srcSlot = 9, quantity = 16,
                     _realm = "Sargeras", _char = "Alt-Sargeras", _seq = 9, _itemID = 101}
ops = ns:PlanPullWave(twice, 0, ROOM)
check("no slots: only merges survive, and room is spent as it goes",
    namesOf(ops), "Arcane Crystal")  -- 5 of 20 used; the x16 would need 16 of the remaining 15

-- Zero slots and plenty of room: merges still go, the wave stops at the first
-- pull that needs a slot (ordering is kept, nothing is skipped over).
ops = ns:PlanPullWave(StackOps(), 0, { [101] = 20, [102] = 10, [103] = 50 })
check("zero slots: wave ends at the first slot-needing pull", namesOf(ops), "Arcane Crystal")

-- Ops without an item ID are never credited.
local anon = StackOps()
for _, op in ipairs(anon) do op._itemID = nil end
ops = ns:PlanPullWave(anon, 2, ROOM)
check("no item ID means no credit", #ops, 2)

-- Enough slots for everything: the room table changes nothing.
ops = ns:PlanPullWave(StackOps(), 5, ROOM)
check("room never shrinks a wave that already fits", #ops, 5)

--------------------------
-- 6. GetBagStackRoom reads the bags
--------------------------

ns.INVENTORY_BAGS = { 0 }
local BAG = {
    [1] = { itemID = 101, stackCount = 15 },   -- max 20 → 5 room
    [2] = { itemID = 101, stackCount = 20 },   -- full
    [3] = { itemID = 201, stackCount = 1 },    -- unstackable
    [4] = { itemID = 102, stackCount = 190 },  -- max 200 → 10 room
    [5] = { itemID = 103, stackCount = 1 },    -- stack size unknown → ignored
}
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 6 or 0 end,
    GetContainerItemInfo = function(bag, slot) return bag == 0 and BAG[slot] or nil end,
}
C_Item = { GetItemMaxStackSizeByID = function(id)
    return ({ [101] = 20, [201] = 1, [102] = 200 })[id]
end }
local room = ns:GetBagStackRoom()
check("partial stack room summed per item", room[101], 5)
check("full stack adds nothing", room[101], 5)
check("unstackable item has no room", room[201], nil)
check("large stacks counted", room[102], 10)
check("unknown stack size is ignored", room[103], nil)
check("empty slots are not room", room[nil], nil)
check("free slots still counted separately", ns:GetFreeBagSlots(), 1)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
