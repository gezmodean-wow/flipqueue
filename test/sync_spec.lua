-- test/sync_spec.lua
-- FQ-256: full sync over a throttled whisper link.
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/sync_spec.lua
--
-- SendAddonMessage does not raise when the server throttles it. It returns
-- Enum.SendAddonMessageResult.AddonMessageThrottle (3) and drops the message.
-- The send queue used to treat any clean pcall as "sent", so on a whisper
-- link most full-sync chunks vanished and the receiver discarded the whole
-- transfer at FEND with a debug-only print. To the player that looked like a
-- sync that never finished.
--
-- This loads two copies of Sync.lua (accounts A and B), wires them together
-- through a fake wire with a token-bucket throttle (10-message burst, 1/sec
-- refill), and drives both send queues on a fake clock.

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
-- Fake clock + wire
--------------------------

local now = 1000
function GetTime() return now end

-- Timers fire on the fake clock, not inline as in wow_shim: RequestFullSyncWith
-- waits for the partner's FSYN before sending, and that ordering is under test.
local timers = {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function() return { Cancel = function() end } end,
}
-- time() on the same fake clock, so delta retry timing is really exercised.
local timeBase = os.time()
time = function() return timeBase + math.floor(now) end
local function RunTimers()
    local i = 1
    while i <= #timers do
        if timers[i].at <= now then
            local t = table.remove(timers, i)
            t.fn()
        else
            i = i + 1
        end
    end
end

local accounts = {}     -- [charName] = instance
local sending           -- instance currently draining
local wireDrop          -- optional fn(msg) -> true to lose a message in transit

local function NewBucket() return { tokens = 10, at = now } end

C_ChatInfo = {
    SendAddonMessage = function(_, msg, _, target)
        local b = sending.bucket
        b.tokens = math.min(10, b.tokens + (now - b.at))
        b.at = now
        if b.tokens < 1 then return 3 end   -- AddonMessageThrottle
        b.tokens = b.tokens - 1
        sending.sentCount = sending.sentCount + 1
        sending.sent[#sending.sent + 1] = msg
        local dest = accounts[target]
        if dest and not (wireDrop and wireDrop(msg)) then
            dest.inbox[#dest.inbox + 1] = { msg = msg, from = sending.charName }
        end
        return 0
    end,
}
function BNSendGameData() return 0 end

local function NewAccount(charName, uuid, partnerChar, partnerUUID)
    local ns = {
        COLORS = setmetatable({}, { __index = function() return "" end }),
        prints = {},
    }
    function ns:Print(msg) self.prints[#self.prints + 1] = msg end
    function ns:PrintDebug() end
    function ns:IsCharDeleted() return false end
    function ns:InvalidateInventoryNameIndex() end
    ns.db = {
        characters = {},
        log = {},
        todoLists = { upcoming = {}, archive = {} },
        sync = {
            accountUUID = uuid,
            lastSentSeq = 0,
            partners = { [partnerUUID] = { transport = "whisper", charName = partnerChar, label = partnerChar } },
        },
    }
    assert(loadfile("Sync.lua"))("flipqueue", ns)
    local inst = { ns = ns, Sync = ns.Sync, charName = charName, inbox = {},
                   bucket = NewBucket(), sentCount = 0, sent = {} }
    accounts[charName] = inst
    return inst
end

local function Deliver(inst)
    local box = inst.inbox
    inst.inbox = {}
    for _, m in ipairs(box) do inst.Sync:OnWhisperMessage(m.msg, m.from) end
end

local function LogHas(inst, event)
    local n = 0
    for _, e in ipairs(inst.Sync:GetSyncLog()) do
        if e.event == event then n = n + 1 end
    end
    return n
end

local function Fresh()
    accounts = {}
    wireDrop = nil
    timers = {}
    now = now + 100
    local a = NewAccount("Alice-Realm", "UA", "Bob-Realm", "UB")
    local b = NewAccount("Bob-Realm", "UB", "Alice-Realm", "UA")
    -- A owns enough character data for ~100 whisper chunks.
    local items = {}
    for i = 1, 400 do items["2000" .. i .. ";;"] = { count = i, name = "Item number " .. i } end
    a.ns.db.characters["Alice-Realm"] = { accountUUID = "UA", items = items }
    return a, b
end

-- Run until the queue counts stop changing (both sides drained, nothing in flight).
local function RunToIdle(a, b)
    local quiet = 0
    for _ = 1, 200000 do
        local before = a.sentCount + b.sentCount
        now = now + 0.12
        sending = a; a.Sync:DrainQueue()
        sending = b; b.Sync:DrainQueue()
        Deliver(a); Deliver(b)
        RunTimers()
        if math.floor(now) % 5 == 0 then a.Sync:RetryUnacked(); b.Sync:RetryUnacked() end
        if a.sentCount + b.sentCount == before and #timers == 0
            and a.Sync:GetFullSyncProgress("UB") == nil and b.Sync:GetFullSyncProgress("UA") == nil then
            quiet = quiet + 1
            if quiet > 20 then return end   -- > 2s of no traffic covers a throttle backoff
        else
            quiet = 0
        end
    end
end

--------------------------
-- 1. A full sync survives the throttle
--------------------------
do
    local a, b = Fresh()
    a.Sync:RequestFullSyncWith("UB")
    RunToIdle(a, b)

    local got = b.ns.db.characters["Alice-Realm"]
    check("throttled: B received A's character", got ~= nil, true)
    check("throttled: all 400 items arrived", got and got.items and got.items["2000400;;"] and got.items["2000400;;"].count, 400)
    check("throttled: B logged FULL_SYNC_DONE", LogHas(b, "FULL_SYNC_DONE"), 1)
    check("throttled: B logged no FULL_SYNC_INCOMPLETE", LogHas(b, "FULL_SYNC_INCOMPLETE"), 0)
    check("throttled: the throttle was actually hit", LogHas(a, "THROTTLED") >= 1, true)
    check("throttled: A logged FULL_SYNC_SENT", LogHas(a, "FULL_SYNC_SENT"), 1)
    check("throttled: A's outbound state cleared", a.Sync:GetFullSyncProgress("UB"), nil)
    check("throttled: B back to connected", b.Sync:GetPartnerState("UA"), "connected")
    -- B was asked (FSYN) and sent its own copy back.
    check("throttled: A logged FULL_SYNC_DONE from B", LogHas(a, "FULL_SYNC_DONE"), 1)
end

--------------------------
-- 2. Repeat requests don't queue extra copies
--------------------------
do
    local a, b = Fresh()
    check("dedupe: first request starts", a.Sync:RequestFullSyncWith("UB"), true)
    check("dedupe: repeat while awaiting reply is skipped", a.Sync:RequestFullSyncWith("UB"), false)
    check("dedupe: progress text while awaiting reply", a.Sync:GetFullSyncProgressText("UB"), "Syncing")
    -- B answers with its own FSYN; that starts A's send.
    for _ = 1, 30 do
        now = now + 0.12
        sending = a; a.Sync:DrainQueue(); sending = b; b.Sync:DrainQueue()
        Deliver(a); Deliver(b); RunTimers()
        if a.Sync:GetFullSyncProgress("UB") then break end
    end
    local out = a.Sync:GetFullSyncProgress("UB")
    check("dedupe: send started on B's reply, before the fallback timer", out ~= nil, true)
    check("dedupe: repeat while sending is skipped", a.Sync:RequestFullSyncWith("UB"), false)
    check("dedupe: progress text while sending", (a.Sync:GetFullSyncProgressText("UB") or ""):match("^Syncing %d+%%$") ~= nil, true)
    RunToIdle(a, b)
    check("dedupe: FULL_SYNC_SEND logged once", LogHas(a, "FULL_SYNC_SEND"), 1)
    check("dedupe: B merged exactly one transfer", LogHas(b, "FULL_SYNC_DONE"), 1)
    check("dedupe: B never restarted a transfer", LogHas(b, "FULL_SYNC_RESTART"), 0)
    check("dedupe: progress text clears when done", a.Sync:GetFullSyncProgressText("UB"), nil)
    -- After completion a new request is allowed again.
    check("dedupe: request after completion starts", a.Sync:RequestFullSyncWith("UB"), true)
end

--------------------------
-- 3. The receiver's own characters are not sent back to it
--------------------------
do
    local a = Fresh()
    a.ns.db.characters["Bob-Realm"] = { accountUUID = "UB", items = { x = 1 } }
    a.ns.db.characters["Carol-Realm"] = { accountUUID = "UC", items = { x = 1 } }
    local p = a.Sync:BuildFullSyncPayload("UB")
    check("exclude: B's character skipped", p.characters["Bob-Realm"], nil)
    check("exclude: third-party character still relayed", p.characters["Carol-Realm"] ~= nil, true)
    check("exclude: A's own character kept", p.characters["Alice-Realm"] ~= nil, true)
    local all = a.Sync:BuildFullSyncPayload()
    check("exclude: no filter keeps everyone", all.characters["Bob-Realm"] ~= nil, true)
end

--------------------------
-- 4. A lost chunk is reported, not silently swallowed
--------------------------
do
    local a, b = Fresh()
    local dropped = false
    wireDrop = function(msg)
        if not dropped and msg:find("^FDAT\0013\001") then dropped = true return true end
    end
    a.Sync:RequestFullSyncWith("UB")
    RunToIdle(a, b)
    check("loss: chunk 3 was dropped on the wire", dropped, true)
    check("loss: B logged FULL_SYNC_INCOMPLETE", LogHas(b, "FULL_SYNC_INCOMPLETE"), 1)
    check("loss: B did not merge", b.ns.db.characters["Alice-Realm"], nil)
    check("loss: B is not left in 'syncing'", b.Sync:GetPartnerState("UA"), "connected")
    local printed = false
    for _, m in ipairs(b.ns.prints) do if m:find("lost data in transit", 1, true) then printed = true end end
    check("loss: player was told", printed, true)
end

--------------------------
-- 5. A new transfer starting mid-buffer replaces the old one
--------------------------
do
    local a, b = Fresh()
    local S = "\001"
    -- Half of a stale transfer (5 of 9 chunks), then a complete good one.
    for i = 1, 5 do b.Sync:OnWhisperMessage("FDAT" .. S .. i .. S .. "9" .. S .. "junk", "Alice-Realm") end
    local good = a.Sync:Serialize({ accountUUID = "UA", characters = { ["Dan-Realm"] = { accountUUID = "UA" } },
                                    ownedCharacters = { "Dan-Realm" } })
    local n = math.ceil(#good / 50)
    for i = 1, n do
        b.Sync:OnWhisperMessage("FDAT" .. S .. i .. S .. n .. S .. good:sub((i - 1) * 50 + 1, i * 50), "Alice-Realm")
    end
    b.Sync:OnWhisperMessage("FEND", "Alice-Realm")
    check("restart: stale buffer dropped", LogHas(b, "FULL_SYNC_RESTART"), 1)
    check("restart: good transfer merged", b.ns.db.characters["Dan-Realm"] ~= nil, true)
    check("restart: no deserialize failure", LogHas(b, "FULL_SYNC_BAD_DATA"), 0)
end

--------------------------
-- 6. A hard send error on FEND still clears the in-flight state
--------------------------
do
    local a, b = Fresh()
    local real = C_ChatInfo.SendAddonMessage
    C_ChatInfo.SendAddonMessage = function(p, msg, c, t)
        if msg == "FEND" then return 9 end   -- GeneralError
        return real(p, msg, c, t)
    end
    a.Sync:RequestFullSyncWith("UB")
    RunToIdle(a, b)
    C_ChatInfo.SendAddonMessage = real
    check("send error: A logged SEND_ERR", LogHas(a, "SEND_ERR") >= 1, true)
    check("send error: A's outbound state cleared", a.Sync:GetFullSyncProgress("UB"), nil)
    check("send error: a later request is not skipped", a.Sync:RequestFullSyncWith("UB"), true)
end

--------------------------
-- 7. Both sides reconnect at once: each sends one copy, not two
--------------------------
-- The player's logs: A sends FSYN on PING_RECONNECT while B sends FSYN on
-- PONG_RECONNECT. Each side then gets the other's FSYN and, before the
-- fix, queued a second full copy of its own payload behind the first.
do
    local a, b = Fresh()
    a.Sync:RequestFullSyncWith("UB")
    b.Sync:RequestFullSyncWith("UA")
    RunToIdle(a, b)
    check("mutual: A built its payload once", LogHas(a, "FULL_SYNC_SEND"), 1)
    check("mutual: B built its payload once", LogHas(b, "FULL_SYNC_SEND"), 1)
    check("mutual: neither side answered the other's FSYN with another", LogHas(a, "SEND FSYN") + LogHas(b, "SEND FSYN"), 2)
    check("mutual: B merged A's data once", LogHas(b, "FULL_SYNC_DONE"), 1)
    check("mutual: A merged B's data once", LogHas(a, "FULL_SYNC_DONE"), 1)
end

--------------------------
-- 8. A payload build error is logged, not silent
--------------------------
do
    local a = Fresh()
    local real = a.Sync.Serialize
    a.Sync.Serialize = function() error("script ran too long") end
    a.Sync:RequestFullSyncWith("UB")
    now = now + 11; RunTimers()          -- B never answers; the fallback timer builds
    a.Sync.Serialize = real
    check("build error: FULL_SYNC_ERROR logged", LogHas(a, "FULL_SYNC_ERROR"), 1)
    check("build error: nothing left in flight", a.Sync:GetFullSyncProgress("UB"), nil)
end

local function LastDetail(inst, event)
    local d
    for _, e in ipairs(inst.Sync:GetSyncLog()) do
        if e.event == event then d = e.detail end
    end
    return d
end

local function MakeLog(n, base)
    local log = {}
    for i = 1, n do
        log[i] = { itemKey = "3000" .. i .. ";;", charKey = "Alice-Realm", postedAt = base + i,
                   auctionStatus = "sold", name = "Logged item " .. i }
    end
    return log
end

--------------------------
-- 9. The sales log is sent incrementally once a watermark exists
--------------------------
do
    local a, b = Fresh()
    local old = time() - 10 * 86400
    a.ns.db.log = MakeLog(200, old)
    a.Sync:RequestFullSyncWith("UB")
    RunToIdle(a, b)
    check("incremental: first sync is a full log", LastDetail(a, "FULL_SYNC_LOG"):find("200/200 log entries (full)", 1, true) ~= nil, true)
    check("incremental: B holds all 200", #b.ns.db.log, 200)
    check("incremental: B stored A's build time", type(b.ns.db.sync.partners.UA.logBuiltAt), "number")

    -- Five new sales, then the next sync.
    for i = 1, 5 do
        a.ns.db.log[#a.ns.db.log + 1] = { itemKey = "4000" .. i .. ";;", charKey = "Alice-Realm",
            postedAt = time(), auctionStatus = "active", name = "New item " .. i }
    end
    a.Sync:RequestFullSyncWith("UB")
    RunToIdle(a, b)
    check("incremental: second sync sends only the 5 new entries", LastDetail(a, "FULL_SYNC_LOG"):find("5/205 log entries since", 1, true) ~= nil, true)
    check("incremental: B now holds 205", #b.ns.db.log, 205)
    check("incremental: no gap re-request", LogHas(b, "FULL_SYNC_LOG_GAP"), 0)
    check("incremental: B did not echo A's entries back", (LastDetail(b, "FULL_SYNC_LOG") or ""):find("| 0/200 log entries since", 1, true) ~= nil, true)
end

--------------------------
-- 10. An older partner (FSYN with no watermark) gets the whole log
--------------------------
do
    local a = Fresh()
    a.ns.db.log = MakeLog(50, time() - 86400)
    a.ns.db.sync.partners.UB.peerLogSince = time()   -- stale value from a newer session
    a.Sync:OnWhisperMessage("FSYN", "Bob-Realm")         -- what v0.13.3-alpha1 and older send
    check("old partner: watermark cleared", a.ns.db.sync.partners.UB.peerLogSince, nil)
    check("old partner: full log sent", LastDetail(a, "FULL_SYNC_LOG"):find("50/50 log entries (full)", 1, true) ~= nil, true)
    check("old partner: no FSYN reply to an old client", LogHas(a, "SEND FSYN"), 0)
end

--------------------------
-- 11. Archive and templates stay home
--------------------------
do
    local a = Fresh()
    a.ns.db.todoLists.archive = { { list = { tasks = { 1, 2, 3 } } } }
    a.ns.db.todoLists.templates = { x = 1 }
    a.ns.db.todoLists.active = { name = "L", createdAt = 1, tasks = {} }
    local p = a.Sync:BuildFullSyncPayload("UB")
    check("payload: archive not sent", p.todoLists.archive, nil)
    check("payload: templates not sent", p.todoLists.templates, nil)
    check("payload: active list still sent", p.todoLists.active and p.todoLists.active.name, "L")
end

--------------------------
-- 12. A large delta arrives once, intact, over a slow link
--------------------------
-- ~60 KB at the spec's 1 msg/s refill takes minutes. Before the fix the
-- retry clock started at enqueue, so it was re-queued three times while the
-- first copy drained, and the receiver's reassembly buffer expired 60s after
-- its first chunk, so it never completed.
do
    local a, b = Fresh()
    local committed = {}
    b.ns.TodoList = { CommitList = function(_, list, mode) committed[#committed + 1] = { list = list, mode = mode } end }
    a.Sync:OnWhisperMessage("PING" .. "\001" .. "UB", "Bob-Realm")   -- mark B connected
    a.inbox, b.inbox = {}, {}
    local tasks = {}
    for i = 1, 250 do tasks[i] = { taskUUID = "t" .. i, itemKey = "5000" .. i .. ";;", note = string.rep("x", 200) } end
    a.Sync:EmitDelta("TDCOMMIT", { mode = "replace", list = { name = "Big", createdAt = 7, tasks = tasks } })
    local started = now
    RunToIdle(a, b)
    local copies = 0
    for _, m in ipairs(a.sent) do
        if m:find("^C\001%d+\0011\001") then copies = copies + 1 end
    end
    check("big delta: took longer than 60s to arrive", now - started > 60, true)
    check("big delta: sent exactly once", copies, 1)
    check("big delta: applied once", #committed, 1)
    check("big delta: arrived intact", committed[1] and #committed[1].list.tasks, 250)
    check("big delta: acked and cleared", #a.ns.db.sync.partners.UB.pendingDeltas, 0)
end

--------------------------
-- 13. Different active lists: newer wins, tasks never mix
--------------------------
do
    local a = Fresh()
    local archived = {}
    a.ns.TodoList = { ArchiveList = function(_, list, reason) archived[#archived + 1] = reason end }
    a.ns.db.todoLists.active = { name = "Mine", createdAt = 10, tasks = { { taskUUID = "m1" } } }
    a.Sync:MergeTodoLists({ active = { name = "Theirs", createdAt = 20, tasks = { { taskUUID = "t1" } } } })
    check("lists: newer remote list becomes active", a.ns.db.todoLists.active.name, "Theirs")
    check("lists: tasks not mixed", #a.ns.db.todoLists.active.tasks, 1)
    check("lists: replaced list archived", archived[1], "replaced")
    a.Sync:MergeTodoLists({ active = { name = "Older", createdAt = 5, tasks = { { taskUUID = "o1" } } } })
    check("lists: older remote list ignored", a.ns.db.todoLists.active.name, "Theirs")
    a.Sync:MergeTodoLists({ active = { name = "Theirs", createdAt = 20, tasks = { { taskUUID = "t2" } } } })
    check("lists: same list merges tasks", #a.ns.db.todoLists.active.tasks, 2)
end

print(string.format("sync_spec: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
