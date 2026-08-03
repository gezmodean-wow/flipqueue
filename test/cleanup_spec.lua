-- test/cleanup_spec.lua
-- Headless coverage for TodoList:ClassifyTasks / PurgeTrapped (FQ-226).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/cleanup_spec.lua
--
-- This classifier decides what a player is invited to delete, so the spec is
-- written from the false-positive side first: the cases that must NOT be called
-- trapped matter more than the ones that must. A missed trapped task is a row
-- that stays in a list. A wrong one is a task the player deletes on our word.

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
-- Namespace
--------------------------

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "" end})
function ns:Print() end
function ns:PrintDebug() end
function ns:GetCharKey() return "Main-Sargeras" end
function ns:MakeItemKey(id, b, m) return tostring(id) .. ";" .. (b or "") .. ";" .. (m or "") end
function ns:ImportRemove(src, key) ns._removedImports[src .. "|" .. key] = true end
function ns:RealmsOverlap(a, b) return a == b end
function ns:RealmMatches(a, b) return a == b end
ns._removedImports = {}

-- TodoList.lua builds an event frame at load; the shim's CreateFrame covers it.
assert(loadfile("TodoList.lua"))("FlipQueue", ns)
local TodoList = ns.TodoList

local DAY = 86400
local NOW = os.time()

--------------------------
-- Fixture
--------------------------

-- Two known characters. "Ghost-Sargeras" is deliberately absent: a deleted or
-- renamed character, which is the one unambiguous trapped case.
local function NewDB(tasks)
    return {
        settings = { todoStaleDays = 14 },
        characters = {
            ["Main-Sargeras"] = { inventory = { items = {
                ["1001;;"] = { quantity = 1, locations = { bags = 1 } },
            } } },
            ["Alt-Proudmoore"] = { inventory = { items = {
                ["2002;;"] = { quantity = 3, locations = { bank = 3 } },
            } } },
        },
        warbank = { items = {
            ["3003;;"] = { quantity = 1 },
        } },
        todoLists = {
            active = { name = "Test", createdAt = NOW - (30 * DAY), tasks = tasks },
            upcoming = {},
        },
    }
end

local function T(fields)
    local task = {
        status = "pending", action = "sell", assignedChar = "Main-Sargeras",
        name = "Thing", itemKey = "1001;;", quantity = 1,
        lastProgressAt = NOW,
    }
    for k, v in pairs(fields) do task[k] = v end
    -- `lastProgressAt = nil` in a table constructor is indistinguishable from
    -- "not mentioned", so unstamped tasks need an explicit marker.
    if fields._unstamped then
        task.lastProgressAt, task.createdAt, task._unstamped = nil, nil, nil
    end
    return task
end

print("Cleanup spec")

--------------------------
-- 1. What must never be called trapped
--------------------------

ns.db = NewDB({
    -- Item is right here in the acting character's bags.
    T({}),
    -- Item is on another character, which is the entire point of the deposit
    -- routing. Deferred or not, it exists.
    T({itemKey = "2002;;", deferredAt = NOW - DAY}),
    -- Item is in the warbank.
    T({itemKey = "3003;;", deferredAt = NOW - DAY}),
    -- A buy task is *supposed* to be for an item you do not own yet. Absence
    -- proves nothing, and calling these trapped would purge the entire buy
    -- half of every cross-realm flip.
    T({action = "buy", itemKey = "9999;;", deferredAt = NOW - (10 * DAY)}),
    -- Not pending: already posted to the auction house, waiting on a buyer.
    T({status = "posted", itemKey = "9999;;", deferredAt = NOW - (10 * DAY)}),
    -- Deliberately skipped by the player.
    T({status = "skipped", itemKey = "9999;;", deferredAt = NOW - (10 * DAY)}),
})

local c = TodoList:ClassifyTasks()
check("nothing here is trapped", c.trappedCount, 0)
check("only pending tasks are considered", c.total, 4)

--------------------------
-- 2. What must be called trapped
--------------------------

ns.db = NewDB({
    T({assignedChar = "Ghost-Sargeras"}),                          -- 1 no-character
    T({itemKey = "9999;;", deferredAt = NOW - DAY}),               -- 2 item-gone
    T({itemKey = "8888;;", dealType = "flip"}),                    -- 3 buy-removed
    T({}),                                                          -- 4 fine
})

c = TodoList:ClassifyTasks()
check("three trapped", c.trappedCount, 3)
check("deleted character", c.byIndex[1].trapped, "no-character")
check("item nowhere on the account", c.byIndex[2].trapped, "item-gone")
check("orphaned flip sell", c.byIndex[3].trapped, "buy-removed")
check("the healthy task is untouched", c.byIndex[4], nil)
check("reasons are counted", c.byReason["no-character"], 1)

-- The same orphan, but with its buy task still in the list: not trapped, the
-- buy simply hasn't happened yet.
ns.db = NewDB({
    T({itemKey = "8888;;", dealType = "flip"}),
    T({action = "buy", itemKey = "8888;;", name = "Thing"}),
})
c = TodoList:ClassifyTasks()
check("a flip with its buy intact is not trapped", c.trappedCount, 0)

-- Matched by name when the keys differ, the same way DeleteTask's cascade
-- correlates them — otherwise a variant key orphans its own sell.
ns.db = NewDB({
    T({itemKey = "8888;;", name = "Spidersilk Boots", dealType = "flip"}),
    T({action = "buy", itemKey = "8888;1234;", name = "Spidersilk Boots"}),
})
c = TodoList:ClassifyTasks()
check("buy correlates by name as well as key", c.trappedCount, 0)

-- An item that is missing but NOT deferred is not trapped: the tracker has not
-- looked yet, and "we haven't checked" is not "it cannot resolve".
ns.db = NewDB({ T({itemKey = "9999;;"}) })
c = TodoList:ClassifyTasks()
check("missing but not yet deferred is not trapped", c.trappedCount, 0)

--------------------------
-- 3. Stale is time since progress, not time since the list was built
--------------------------

ns.db = NewDB({
    T({lastProgressAt = NOW - (20 * DAY)}),   -- 1 stale
    T({lastProgressAt = NOW - (2 * DAY)}),    -- 2 fresh
    -- No stamps at all: falls back to the list's createdAt, 30 days ago.
    T({_unstamped = true}),                   -- 3 stale, falls back to the list
    -- Created long ago but worked on today. The list is old; the task is not.
    T({createdAt = NOW - (60 * DAY), lastProgressAt = NOW}), -- 4 fresh
})

c = TodoList:ClassifyTasks()
check("stale counted", c.staleCount, 2)
check("stale reports whole days", c.byIndex[1].stale, 20)
check("recent progress is not stale", c.byIndex[2], nil)
check("falls back to the list's own age", c.byIndex[3].stale, 30)
check("an old task worked on today is not stale", c.byIndex[4], nil)
check("stale tasks are never also trapped", c.trappedCount, 0)

-- 0 disables the flag. Guarded explicitly because 0 is truthy in Lua, so a
-- naive threshold would mark every task in the list stale.
ns.db.settings.todoStaleDays = 0
c = TodoList:ClassifyTasks()
check("0 days disables staleness entirely", c.staleCount, 0)

--------------------------
-- 4. Unscanned characters are reported, not silently ignored
--------------------------

-- "The item is nowhere" is decided from stored inventory. A character that has
-- never been scanned looks empty, so its items look missing — the count has to
-- travel with the result or a surface will assert a deletion is safe when it
-- is not.
ns.db = NewDB({ T({itemKey = "9999;;", deferredAt = NOW - DAY}) })
ns.db.characters["Fresh-Alt"] = { inventory = { items = {} } }
ns.db.characters["Never-Logged"] = {}
c = TodoList:ClassifyTasks()
check("unscanned characters are counted", c.unscannedChars, 2)
check("classification still runs", c.trappedCount, 1)

--------------------------
-- 5. Purge removes exactly the trapped tasks
--------------------------

ns._removedImports = {}
ns.db = NewDB({
    T({name = "Keep 1"}),
    T({name = "Trapped A", assignedChar = "Ghost-Sargeras",
       importSource = "fpScanner", importKey = "ik-a", taskUUID = "uuid-a"}),
    T({name = "Keep 2"}),
    T({name = "Trapped B", itemKey = "9999;;", deferredAt = NOW - DAY,
       importSource = "fpScanner", importKey = "ik-b"}),
    T({name = "Keep 3"}),
})

local removed, byReason = TodoList:PurgeTrapped()
local tasks = ns.db.todoLists.active.tasks
check("removed count", removed, 2)
check("survivors remain", #tasks, 3)
check("and they are the right ones",
    tasks[1].name .. "," .. tasks[2].name .. "," .. tasks[3].name,
    "Keep 1,Keep 2,Keep 3")
check("reasons reported back", byReason["no-character"], 1)
check("import links cleaned up for A", ns._removedImports["fpScanner|ik-a"], true)
check("import links cleaned up for B", ns._removedImports["fpScanner|ik-b"], true)

-- Descending removal is the only reason the survivors above are intact; a
-- forward pass would shift indices under itself. Prove it at a size where a
-- shift cannot hide: every other task trapped.
local many = {}
for i = 1, 20 do
    if i % 2 == 0 then
        many[i] = T({name = "T" .. i, assignedChar = "Ghost-Sargeras"})
    else
        many[i] = T({name = "K" .. i})
    end
end
ns.db = NewDB(many)
removed = TodoList:PurgeTrapped()
tasks = ns.db.todoLists.active.tasks
check("ten removed from twenty", removed, 10)
check("ten survive", #tasks, 10)
local allKeepers = true
for _, task in ipairs(tasks) do
    if task.name:sub(1, 1) ~= "K" then allKeepers = false end
end
check("every survivor is a keeper", allKeepers, true)

-- Nothing trapped: a no-op, not a wipe.
ns.db = NewDB({ T({name = "Fine"}) })
removed = TodoList:PurgeTrapped()
check("no trapped tasks removes nothing", removed, 0)
check("list intact", #ns.db.todoLists.active.tasks, 1)

--------------------------
-- 6. Progress stamping
--------------------------

ns.db = NewDB({ T({lastProgressAt = NOW - (40 * DAY)}) })
c = TodoList:ClassifyTasks()
check("stale before progress", c.staleCount, 1)
TodoList:StampProgress(ns.db.todoLists.active.tasks[1])
c = TodoList:ClassifyTasks()
check("stamping clears the flag", c.staleCount, 0)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
