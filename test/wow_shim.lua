-- test/wow_shim.lua
-- Minimal stubs for the WoW global API surface that FlipQueue's parsing path
-- touches, so modules can be loaded and exercised headless under stock
-- Lua 5.1 (lua.exe). This is a TEST-ONLY shim — it implements just enough of
-- each global to be behaviourally faithful for parser/classification tests,
-- not the full Blizzard API. Load this before any FQ module.

-- strtrim(s[, chars]) — trims leading/trailing whitespace (default) or any
-- char in `chars`. WoW's default trims " \t\r\n".
function strtrim(s, chars)
    if s == nil then return "" end
    if chars then
        local pat = "^[" .. chars:gsub("(%W)", "%%%1") .. "]*(.-)[" ..
            chars:gsub("(%W)", "%%%1") .. "]*$"
        return (s:gsub(pat, "%1"))
    end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- strsplit(delimiter, str[, limit]) — returns the pieces as multiple return
-- values. WoW treats every char in `delimiter` as a separator; our callers
-- only ever pass a single-char delimiter, which this handles faithfully
-- (including leading/empty/trailing fields).
function strsplit(delim, str, limit)
    if delim == "" then return str end
    local result = {}
    local escaped = delim:gsub("(%W)", "%%%1")   -- safe inside a [..] set
    local pat = "(.-)[" .. escaped .. "]"
    local lastEnd = 1
    local s, e, cap = str:find(pat, 1)
    while s do
        table.insert(result, cap)
        lastEnd = e + 1
        s, e, cap = str:find(pat, lastEnd)
    end
    table.insert(result, str:sub(lastEnd))
    return unpack(result)
end

-- time() / date() — back onto the host os library.
time = os.time
date = os.date

-- C_Timer.After(delay, fn) — run synchronously so chunked code paths complete
-- inline in a test (no frame loop to yield to).
C_Timer = { After = function(_, fn) if fn then fn() end end }

-- wipe(t) — empty a table in place.
function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end
