-- test/escapes_spec.lua
-- Source lint: no invalid escape sequences in string literals.
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/escapes_spec.lua
--
-- Lua 5.1 — which is what WoW runs — does not reject an unknown escape. Its
-- lexer keeps the character and silently drops the backslash, so
-- "Interface\RaidFrame\ReadyCheck" compiles cleanly and evaluates to
-- "InterfaceRaidFrameReadyCheck": a texture path that loads nothing, with no
-- error and no warning at any point. `luac -p` passes it. A code review reads
-- it as correct, because in almost every other language it would be.
--
-- The same hole swallows "\xe2\x86\x92" (hex escapes are 5.2+, and shipped in
-- FQ-187 as the literal text "xe2x86x92" in a player-visible note) and any
-- Windows path written with single separators. Every WoW texture path in this
-- addon needs doubled backslashes, so the failure is one keystroke away and
-- invisible once made.
--
-- This walks every .lua file and re-implements the 5.1 lexer's string scanning
-- closely enough to find them.

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

-- Everything Lua 5.1 actually recognises after a backslash. Anything else is
-- accepted-then-dropped, which is the bug.
local VALID = {
    a = true, b = true, f = true, n = true, r = true, t = true, v = true,
    ["\\"] = true, ['"'] = true, ["'"] = true, ["\n"] = true,
}

-- Scan one line, returning the offending escape or nil. Tracks whether we are
-- inside a quoted string so a backslash in a comment (a Windows path in a
-- run-me header, say) is not reported.
local function BadEscape(line)
    if line:find("%[%[") then return nil end   -- long bracket strings: skipped
    local quote = nil
    local i = 1
    while i <= #line do
        local ch = line:sub(i, i)
        if quote then
            if ch == "\\" then
                local nxt = line:sub(i + 1, i + 1)
                if not (VALID[nxt] or nxt:match("%d")) then
                    return "\\" .. nxt
                end
                i = i + 2
            else
                if ch == quote then quote = nil end
                i = i + 1
            end
        else
            if ch == "-" and line:sub(i + 1, i + 1) == "-" then
                return nil                      -- rest of the line is a comment
            elseif ch == '"' or ch == "'" then
                quote = ch
            end
            i = i + 1
        end
    end
    return nil
end

--------------------------
-- The lint's own tests, so a broken lint cannot pass vacuously
--------------------------

print("Escapes spec")

check("catches a single-backslash texture path",
    BadEscape([[    row.icon:SetTexture("Interface\RaidFrame\ReadyCheck")]]), "\\R")
check("catches a hex escape (5.2+ only)",
    BadEscape([[    local s = "arrow \xe2\x86\x92 here"]]), "\\x")
check("accepts a doubled path",
    BadEscape([[    row.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck")]]), nil)
check("accepts newline and tab",
    BadEscape([[    local s = "a\nb\tc"]]), nil)
check("accepts an escaped quote",
    BadEscape([[    local s = "say \"hi\""]]), nil)
check("accepts a decimal escape",
    BadEscape([[    local s = "\65\66"]]), nil)
check("ignores backslashes in comments",
    BadEscape([[    local x = 1  -- see C:\Program Files\Lua]]), nil)
check("ignores a comment line entirely",
    BadEscape([[--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/x.lua]]), nil)

--------------------------
-- Every source file
--------------------------

-- No filesystem walk in stock Lua, and no shelling out: the .toc is the
-- authoritative list of what actually loads in game, which is exactly the set
-- that matters. Spec files are added explicitly.
local files = {}
do
    local toc = io.open("flipqueue.toc", "r")
    assert(toc, "flipqueue.toc not found — run from the repo root")
    for line in toc:lines() do
        line = line:gsub("%s+$", "")
        if line:match("%.lua$") and not line:match("^#") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    toc:close()
end
check("toc listed some files", #files > 10, true)

local offenders = {}
for _, path in ipairs(files) do
    local f = io.open(path, "r")
    if f then
        local n = 0
        for line in f:lines() do
            n = n + 1
            local bad = BadEscape(line)
            if bad then
                offenders[#offenders + 1] = string.format("%s:%d: %s  in  %s",
                    path, n, bad, line:gsub("^%s+", ""):sub(1, 90))
            end
        end
        f:close()
    end
end

if #offenders > 0 then
    print("\n  Invalid escape sequences — Lua 5.1 drops the backslash silently:")
    for _, o in ipairs(offenders) do print("    " .. o) end
end
check("no invalid escapes in any loaded file", #offenders, 0)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
