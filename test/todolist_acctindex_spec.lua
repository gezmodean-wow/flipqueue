-- test/todolist_acctindex_spec.lua
-- Guards the account-index argument contract in TodoList.lua (FQ-240).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/todolist_acctindex_spec.lua
--
-- What this pins down: FQ-223 (v0.13.1-alpha1) hoisted the account-inventory
-- walk out of the per-task helpers and into a single prebuilt index, adding a
-- leading `idx` parameter to IsItemInAccountInventory and FindItemHolder. Three
-- of the four call sites were updated; the one in RefreshTaskSteps' second loop
-- (other characters' tasks) was left on the old two-argument form, so `idx`
-- received a string. Indexing a string field is legal in Lua 5.1 — it resolves
-- through the string metatable to `string.presKey`, i.e. nil — and the error
-- only lands on the NEXT index, which is why this read as a silent no-op rather
-- than an obvious arity mistake.
--
-- The throw killed RefreshTaskSteps partway through, and BANKFRAME_OPENED calls
-- it immediately before Tracker:ShowBankOpsPopup() in the same timer closure —
-- so every bank visit lost pulls, deposits, gold and extras at once.
--
-- These are static checks over the source text rather than a behavioural load of
-- TodoList.lua, which needs far more of the addon than a shim can stand in for.
-- The class of bug is a refactor hazard, so the source text is the right thing
-- to assert on: any future signature change has to update every call site.

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

local scriptPath = arg and arg[0] or "test/todolist_acctindex_spec.lua"
local scriptDir = scriptPath:match("^(.*[/\\])") or "./"
local f = assert(io.open(scriptDir .. ".." .. "/TodoList.lua", "r"))
local src = f:read("*a")
f:close()

--------------------------
-- The helpers still take the index first
--------------------------

-- If either signature loses its leading `idx`, the call-site assertions below
-- would start passing for the wrong reason.
local INDEXED = {
    IsItemInAccountInventory = "local function IsItemInAccountInventory%(idx,",
    FindItemHolder           = "local function FindItemHolder%(idx,",
}
for name, pattern in pairs(INDEXED) do
    check(name .. " declared with leading idx", src:find(pattern) ~= nil, true)
end

--------------------------
-- Every call site passes the index
--------------------------

-- Count calls, then count calls whose first argument is AccountIndex(). The two
-- must agree. Declarations are excluded by requiring no "function " prefix.
for name in pairs(INDEXED) do
    local total, indexed = 0, 0
    for prefix, args in src:gmatch("([%w_]*%s?)" .. name .. "%(([^\n]*)") do
        if not prefix:find("function") then
            total = total + 1
            if args:find("^AccountIndex%(%)") then indexed = indexed + 1 end
        end
    end
    check(name .. " has call sites at all", total > 0, true)
    check(name .. " every call passes AccountIndex() first", indexed, total)
end

--------------------------
-- Why the miss was silent
--------------------------

-- Documents the Lua 5.1 semantics that hid the bug: a string first argument
-- does not fail on `idx.presKey`, only on the index after it. Any assertion
-- about "wrong type errors immediately" would have been wrong here.
local function IsItemInAccountInventory(idx, itemKey, itemNumID)
    if idx.presKey[itemKey] then return true end
    if itemNumID and idx.presID[itemNumID] then return true end
    return false
end

check("string idx resolves presKey to nil, not an error",
    ("12345;;").presKey, nil)
check("string idx throws on the nested index",
    (select(2, pcall(IsItemInAccountInventory, "12345;;", 12345)))
        :find("attempt to index field 'presKey'") ~= nil, true)
check("empty itemKey throws identically (no value dodges it)",
    (select(2, pcall(IsItemInAccountInventory, "", nil)))
        :find("attempt to index field 'presKey'") ~= nil, true)
check("correct arity returns a boolean",
    IsItemInAccountInventory({ presKey = {}, presID = {} }, "12345;;", 12345), false)

--------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
