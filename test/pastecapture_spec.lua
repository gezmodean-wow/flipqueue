-- test/pastecapture_spec.lua
-- Headless coverage for UI:AttachPasteCapture (FQ-228).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/pastecapture_spec.lua
--
-- The crash this guards against had two ingredients: the client delivering
-- one paste as a stream of many input events (so a naive handler calls
-- GetText per event and allocates the whole growing text each time), and the
-- EditBox holding several hundred KB while the client lays it out. The
-- invariants below are what make both impossible — the third case, exact
-- newline reconstruction, is what makes draining the widget safe for
-- FlippingPal's line-based formats where an OnChar buffer would not be.

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
-- Frame-driven C_Timer
--------------------------

-- The shim runs C_Timer.After inline, which would recurse forever through a
-- per-frame settle loop. Queue instead, and step frames explicitly.
local queue = {}
C_Timer = { After = function(_, fn) queue[#queue + 1] = fn end }

local function RunFrames(limit)
    local frames = 0
    while #queue > 0 and frames < (limit or 500) do
        local batch = queue
        queue = {}
        for _, fn in ipairs(batch) do fn() end
        frames = frames + 1
    end
    return frames
end

--------------------------
-- Mock EditBox
--------------------------

local function NewEditBox(noNumLetters)
    local box = { _text = "", getTextCalls = 0, bytesRead = 0, maxHeld = 0, scripts = {} }
    function box:SetScript(kind, fn) self.scripts[kind] = fn end
    function box:GetText()
        self.getTextCalls = self.getTextCalls + 1
        self.bytesRead = self.bytesRead + #self._text
        return self._text
    end
    -- The real widget can answer this without building the string, which is
    -- why capture may call it on every input event.
    if not noNumLetters then
        function box:GetNumLetters() return #self._text end
    end
    function box:SetText(t)
        self._text = t or ""
        -- WoW fires OnTextChanged with userInput=false for code-driven sets.
        local fn = self.scripts.OnTextChanged
        if fn then fn(self, false) end
    end
    -- Simulate the client appending text and firing input events. `maxHeld` is
    -- the high-water mark of what the CLIENT has to lay out and render — the
    -- cost that no amount of Lua bookkeeping can avoid, and the one that
    -- killed the client on a full FlippingPal export.
    function box:Type(chunk, viaOnChar)
        self._text = self._text .. chunk
        if #self._text > self.maxHeld then self.maxHeld = #self._text end
        if viaOnChar and self.scripts.OnChar then
            self.scripts.OnChar(self)
        elseif self.scripts.OnTextChanged then
            self.scripts.OnTextChanged(self, true)
        end
    end
    return box
end

local ns = { UI = {} }
assert(loadfile("UI/Shared.lua"))("FlipQueue", ns)
local UI = ns.UI

print("AttachPasteCapture spec")
check("helper is exposed", type(UI.AttachPasteCapture), "function")

--------------------------
-- 1. Streamed paste via OnChar
--------------------------

local FP_EXPORT = {}
for i = 1, 400 do
    FP_EXPORT[#FP_EXPORT + 1] =
        ("%d;Item Name %d;Epic;600;1663:2293;;2"):format(200000 + i, i)
end
FP_EXPORT = "ItemID;Name;Quality;iLvl;BonusIDs;Modifiers;Quantity\n"
    .. table.concat(FP_EXPORT, "\n") .. "\n"

local function streamTest(label, viaOnChar, chunkSize)
    local box = NewEditBox()
    local got, gotPasted, progressCalls = nil, nil, 0
    UI:AttachPasteCapture(box, {
        onProgress = function() progressCalls = progressCalls + 1 end,
        onText = function(text, wasPasted) got = text; gotPasted = wasPasted end,
    })

    local frames = 0
    local pos = 1
    while pos <= #FP_EXPORT do
        box:Type(FP_EXPORT:sub(pos, pos + chunkSize - 1), viaOnChar)
        pos = pos + chunkSize
        -- One frame elapses between input batches.
        local batch = queue
        queue = {}
        for _, fn in ipairs(batch) do fn() end
        frames = frames + 1
    end
    frames = frames + RunFrames()

    check(label .. ": reconstructed exactly", got, FP_EXPORT)
    check(label .. ": reported as a paste", gotPasted, true)
    check(label .. ": newlines preserved",
        got and select(2, got:gsub("\n", "\n")), 401)
    check(label .. ": box left empty", box._text, "")
    -- Two costs, two invariants. Lua side: reads are bounded by FRAMES, not
    -- by input events — 17k events must not mean 17k full-text allocations.
    -- (Two per frame while draining: the read that takes the text and the
    -- read that confirms the widget let go of it, the second of an empty
    -- box.) Client side: the widget never holds more than the threshold plus
    -- one insert, so there is no growing string to re-lay-out (FQ-228).
    check(label .. ": reads bounded by frames",
        box.getTextCalls <= 2 * frames + 8, true)
    check(label .. ": widget never holds the whole paste",
        box.maxHeld <= 4096 + chunkSize, true)
    check(label .. ": progress reported", progressCalls > 0, true)
    return box.getTextCalls, frames, box.maxHeld
end

-- Per-character streaming, the delivery mode that crashed the client.
local reads, frames, held = streamTest("OnChar stream", true, 1)
print(string.format("    (%d GetText calls over %d frames for %d KB / %d events, widget peak %d B)",
    reads, frames, math.floor(#FP_EXPORT / 1024), #FP_EXPORT, held))

-- Same paste delivered as OnTextChanged only — the case the previous
-- OnChar-keyed guard could not arm on at all.
streamTest("OnTextChanged stream", false, 1)

-- And as larger insertions.
streamTest("chunked stream", false, 512)

--------------------------
-- 1b. The actual crash shape: the whole event storm inside ONE frame
--------------------------

-- This is what killed the client, and it is the case no frame-driven drain
-- can help with: every event of the paste lands before the frame ends, so a
-- timer scheduled by the first event does not run until the last event has
-- already been delivered. Whatever the widget accumulates in between, the
-- client lays out on every single insert. Capture must therefore take the
-- text INSIDE the event, and the invariant is the widget's high-water mark.
do
    local burstBox = NewEditBox()
    local burstGot
    UI:AttachPasteCapture(burstBox, { onText = function(t) burstGot = t end })
    for i = 1, #FP_EXPORT do
        burstBox:Type(FP_EXPORT:sub(i, i), true)   -- no frame boundary at all
    end
    local settleFrames = RunFrames()
    check("burst: reconstructed exactly", burstGot, FP_EXPORT)
    check("burst: widget never holds the whole paste", burstBox.maxHeld <= 4096, true)
    check("burst: bytes read stay linear", burstBox.bytesRead <= 2 * #FP_EXPORT, true)
    print(string.format("    (%d events in one frame -> %d GetText calls, %d frames, widget peak %d B)",
        #FP_EXPORT, burstBox.getTextCalls, settleFrames, burstBox.maxHeld))
end

-- The same burst on a client whose EditBox cannot report its length without
-- building the string. Nothing can be taken mid-event there, so the widget
-- does carry the paste — but the capture must still reconstruct it exactly
-- and must still read it a bounded number of times.
do
    local legacyBox = NewEditBox(true)
    local legacyGot
    UI:AttachPasteCapture(legacyBox, { onText = function(t) legacyGot = t end })
    for i = 1, #FP_EXPORT do
        legacyBox:Type(FP_EXPORT:sub(i, i), true)
    end
    RunFrames()
    check("no GetNumLetters: reconstructed exactly", legacyGot, FP_EXPORT)
    check("no GetNumLetters: reads stay in single digits",
        legacyBox.getTextCalls < 10, true)
end

--------------------------
-- 2. Single-shot paste
--------------------------

local box = NewEditBox()
local got
UI:AttachPasteCapture(box, { onText = function(t) got = t end })
box:Type(FP_EXPORT, false)
-- Before a single frame has run: a paste delivered whole must already be out
-- of the widget, or the client lays it out and draws it at the end of the
-- frame it arrived in.
check("single-shot: box drained inside the event", box._text, "")
RunFrames()
check("single-shot: reconstructed exactly", got, FP_EXPORT)
check("single-shot: box drained", box._text, "")
check("single-shot: capture stats recorded",
    UI._lastPasteStats and UI._lastPasteStats.bytes, #FP_EXPORT)

--------------------------
-- 3. Typing must not be disturbed
--------------------------

box = NewEditBox()
local seen = {}
UI:AttachPasteCapture(box, { onText = function(t, p) seen[#seen + 1] = { t, p } end })
for c in ("Flask of Alchemical Chaos"):gmatch(".") do
    box:Type(c, true)
    local batch = queue
    queue = {}
    for _, fn in ipairs(batch) do fn() end
end
RunFrames()
check("typing: text still in the box", box._text, "Flask of Alchemical Chaos")
check("typing: delivered to caller", seen[#seen] and seen[#seen][1],
    "Flask of Alchemical Chaos")
check("typing: not flagged as a paste", seen[#seen] and seen[#seen][2], false)

--------------------------
-- 4. Busy suspends capture
--------------------------

box = NewEditBox()
local fired = false
local busy = true
UI:AttachPasteCapture(box, {
    isBusy = function() return busy end,
    onText = function() fired = true end,
})
box:Type(FP_EXPORT, false)
RunFrames()
check("busy: no callback while parsing", fired, false)
check("busy: box untouched", box._text, FP_EXPORT)

--------------------------
-- 5. Code-driven SetText must not re-arm (no feedback loop)
--------------------------

box = NewEditBox()
local calls = 0
UI:AttachPasteCapture(box, { onText = function() calls = calls + 1 end })
box:SetText("some text set by the addon")
local frameCount = RunFrames()
check("SetText: no capture armed", calls, 0)
check("SetText: no frames scheduled", frameCount, 0)

--------------------------
-- 6. A box that refuses to drain must not loop forever (FQ-242)
--------------------------

-- The whole drain loop assumes SetText("") empties the widget. If it ever
-- doesn't, the old loop re-read the same text every frame, appended it again,
-- and grew the buffer without bound — a busy cursor, climbing memory, and a
-- dead client with no error to show for it.
box = NewEditBox()
function box:SetText(t)
    -- Accept the addon's clear only for non-empty writes; swallow the wipe.
    if t ~= "" then self._text = t end
    local fn = self.scripts.OnTextChanged
    if fn then fn(self, false) end
end

local stuckText = nil
UI:AttachPasteCapture(box, { onText = function(t) stuckText = t end })
box:Type(FP_EXPORT, false)
local stuckFrames = RunFrames()

check("stuck box: loop terminates", #queue, 0)
check("stuck box: gives up on the first frame", stuckFrames <= 1, true)
check("stuck box: text delivered once, not duplicated",
    stuckText == FP_EXPORT, true)

--------------------------
-- 7. An absurd burst is reported, not accumulated (FQ-242)
--------------------------

box = NewEditBox()
local overflowText, overflowReason = nil, nil
UI:AttachPasteCapture(box, {
    onText = function(t) overflowText = t end,
    onError = function(reason) overflowReason = reason end,
})

-- ~1 MB of DIFFERENT text per frame, so this is a genuinely growing burst
-- rather than the un-drainable box of case 6, until the 8 MB cap trips.
for i = 1, 12 do
    if overflowReason then break end   -- stop feeding once the cap has tripped
    box._text = ("chunk%02d:"):format(i) .. string.rep("x", 1024 * 1024)
    if box.scripts.OnTextChanged then box.scripts.OnTextChanged(box, true) end
    local batch = queue
    queue = {}
    for _, fn in ipairs(batch) do fn() end
end
RunFrames()

check("overflow: reported", overflowReason, "too-large")
check("overflow: no partial text handed downstream", overflowText == nil, true)
check("overflow: capture reset", #queue, 0)

-- The cap must not wedge the box permanently.
box = NewEditBox()
local afterText = nil
UI:AttachPasteCapture(box, { onText = function(t) afterText = t end })
box:Type(FP_EXPORT, false)
RunFrames()
check("overflow: a normal paste after it still lands",
    afterText == FP_EXPORT, true)

--------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
