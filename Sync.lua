-- Sync.lua
-- Bidirectional real-time sync between two WoW accounts via addon messaging
local addonName, ns = ...

local Sync = {}
ns.Sync = Sync

--------------------------
-- Constants
--------------------------

local PREFIX = "FlpQ"
local SEP = "\001"          -- field separator (ASCII SOH)
local CHUNK_SIZE = 235      -- max bytes per whisper chunk (255 - header overhead)
local SEND_RATE = 0.12      -- seconds between queue drains (~8 msgs/sec)
local HEARTBEAT_INTERVAL = 15
local HEARTBEAT_TIMEOUT = 45  -- 3 missed heartbeats
local MAX_PENDING_DELTAS = 500
local REPLAY_THRESHOLD = 100  -- above this, skip replay and full sync
local RETRY_INTERVAL = 5
local MAX_RETRIES = 3

-- Opcodes
local OP_PAIR = "PAIR"
local OP_PACK = "PACK"
local OP_PDEN = "PDEN"
local OP_PING = "PING"
local OP_PONG = "PONG"
local OP_FSYN = "FSYN"
local OP_FDAT = "FDAT"
local OP_FEND = "FEND"
local OP_DELT = "DELT"
local OP_DACK = "DACK"
local OP_UNLK = "UNLK"

-- Priority for send queue (lower = sent first)
local PRIORITY = {
    [OP_PING] = 1, [OP_PONG] = 1,
    [OP_PAIR] = 2, [OP_PACK] = 2, [OP_PDEN] = 2, [OP_UNLK] = 2,
    [OP_DACK] = 3,
    [OP_DELT] = 4,
    [OP_FSYN] = 5, [OP_FDAT] = 5, [OP_FEND] = 5,
}

--------------------------
-- State
--------------------------

local state = "disconnected"   -- disconnected | handshaking | syncing | connected
local sendQueue = {}           -- { {msg, target, priority}, ... }
local reassembly = {}          -- msgID -> { total, chunks={} }
local lastPingSent = 0
local lastPongRecv = 0
local missedPings = 0
local sendTicker = nil
local heartbeatTicker = nil
local retryTicker = nil
local pendingPairFrom = nil    -- charKey of incoming unaccepted pair request
local fullSyncBuffer = {}      -- accumulates FDAT chunks during full sync
local fullSyncExpected = nil   -- total chunks expected for current full sync
Sync._applying = false         -- re-entrancy guard for delta application

--------------------------
-- Initialization
--------------------------

function Sync:Init()
    if self._initialized then return end
    self._initialized = true

    -- Register addon message prefix
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    -- Event frame
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
        if event == "CHAT_MSG_ADDON" and prefix == PREFIX then
            self:OnAddonMessage(message, sender)
        end
    end)

    -- Suppress "No player named" system errors caused by our addon whispers
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if Sync._suppressErrors and msg then
            -- Match WoW's ERR_CHAT_PLAYER_NOT_FOUND_S in any locale
            -- The error contains the character name we tried to whisper
            if ns.db and ns.db.sync and ns.db.sync.partner then
                local partnerName = ns.db.sync.partner.characterName
                if partnerName and msg:find(partnerName, 1, true) then
                    return true -- suppress
                end
            end
        end
    end)

    -- Start send queue drainer
    sendTicker = C_Timer.NewTicker(SEND_RATE, function()
        self:DrainQueue()
    end)

    -- If we have a stored partner, try ONE probe ping then wait passively
    if ns.db and ns.db.sync and ns.db.sync.partner then
        Sync._suppressErrors = true
        -- Single probe after 3s — if partner is online, they'll respond
        C_Timer.After(3, function()
            if ns.db.sync.partner and state == "disconnected" then
                local pingMsg = OP_PING .. SEP .. (ns.db.sync.accountUUID or "")
                self:Enqueue(pingMsg, ns.db.sync.partner.characterName, PRIORITY[OP_PING])
            end
        end)
        -- No heartbeat until connected — we just listen for incoming PINGs
    end

    -- Start retry ticker for unacknowledged deltas
    retryTicker = C_Timer.NewTicker(RETRY_INTERVAL, function()
        self:RetryUnacked()
    end)
end

--------------------------
-- Serialization
--------------------------

-- Serialize a Lua value to a compact string representation
function Sync:Serialize(val)
    local t = type(val)
    if val == nil then return "N"
    elseif t == "boolean" then return val and "t" or "f"
    elseif t == "number" then return "n" .. tostring(val)
    elseif t == "string" then return "s" .. #val .. ":" .. val
    elseif t == "table" then
        -- Detect array vs dict
        local n = #val
        local isArray = n > 0
        if isArray then
            -- Verify no holes and no non-integer keys beyond array portion
            local count = 0
            for _ in pairs(val) do count = count + 1 end
            isArray = (count == n)
        end
        if isArray then
            local parts = { "A" .. n .. "{" }
            for i = 1, n do
                parts[#parts + 1] = self:Serialize(val[i])
            end
            parts[#parts + 1] = "}"
            return table.concat(parts)
        else
            local count = 0
            for _ in pairs(val) do count = count + 1 end
            local parts = { "T" .. count .. "{" }
            for k, v in pairs(val) do
                parts[#parts + 1] = self:Serialize(k)
                parts[#parts + 1] = self:Serialize(v)
            end
            parts[#parts + 1] = "}"
            return table.concat(parts)
        end
    end
    return "N"
end

-- Deserialize a string back to a Lua value
-- Returns: value, nextPosition
function Sync:Deserialize(str, pos)
    pos = pos or 1
    if pos > #str then return nil, pos end

    local ch = str:sub(pos, pos)

    if ch == "N" then
        return nil, pos + 1
    elseif ch == "t" then
        return true, pos + 1
    elseif ch == "f" then
        return false, pos + 1
    elseif ch == "n" then
        -- Number: find end (next non-numeric/non-dot/non-minus/non-e char)
        local numEnd = pos + 1
        while numEnd <= #str do
            local c = str:byte(numEnd)
            -- digits, dot, minus, e, E, +
            if (c >= 48 and c <= 57) or c == 46 or c == 45 or c == 101 or c == 69 or c == 43 then
                numEnd = numEnd + 1
            else
                break
            end
        end
        local num = tonumber(str:sub(pos + 1, numEnd - 1))
        return num, numEnd
    elseif ch == "s" then
        -- String: s<len>:<content>
        local colonPos = str:find(":", pos + 1, true)
        if not colonPos then return nil, pos end
        local len = tonumber(str:sub(pos + 1, colonPos - 1))
        if not len then return nil, pos end
        local content = str:sub(colonPos + 1, colonPos + len)
        return content, colonPos + len + 1
    elseif ch == "A" then
        -- Array: A<count>{...}
        local bracePos = str:find("{", pos + 1, true)
        if not bracePos then return nil, pos end
        local count = tonumber(str:sub(pos + 1, bracePos - 1))
        if not count then return nil, pos end
        local arr = {}
        local nextPos = bracePos + 1
        for i = 1, count do
            local val
            val, nextPos = self:Deserialize(str, nextPos)
            arr[i] = val
        end
        -- Skip closing }
        if str:sub(nextPos, nextPos) == "}" then nextPos = nextPos + 1 end
        return arr, nextPos
    elseif ch == "T" then
        -- Table: T<count>{k1v1k2v2...}
        local bracePos = str:find("{", pos + 1, true)
        if not bracePos then return nil, pos end
        local count = tonumber(str:sub(pos + 1, bracePos - 1))
        if not count then return nil, pos end
        local tbl = {}
        local nextPos = bracePos + 1
        for i = 1, count do
            local key, val
            key, nextPos = self:Deserialize(str, nextPos)
            val, nextPos = self:Deserialize(str, nextPos)
            if key ~= nil then
                tbl[key] = val
            end
        end
        -- Skip closing }
        if str:sub(nextPos, nextPos) == "}" then nextPos = nextPos + 1 end
        return tbl, nextPos
    end

    return nil, pos + 1
end

--------------------------
-- Chunking
--------------------------

local msgCounter = 0

-- Send a structured message, chunking if necessary
function Sync:SendMessage(opcode, payload, target)
    if not target then return end

    local data
    if type(payload) == "table" then
        data = self:Serialize(payload)
    elseif payload then
        data = tostring(payload)
    else
        data = ""
    end

    local fullMsg = opcode .. SEP .. data
    local msgLen = #fullMsg

    if msgLen <= CHUNK_SIZE then
        self:Enqueue(fullMsg, target, PRIORITY[opcode] or 5)
    else
        -- Chunk the message
        msgCounter = msgCounter + 1
        local msgID = msgCounter
        local totalChunks = math.ceil(msgLen / CHUNK_SIZE)

        for i = 1, totalChunks do
            local startIdx = (i - 1) * CHUNK_SIZE + 1
            local endIdx = math.min(i * CHUNK_SIZE, msgLen)
            local chunk = "C" .. SEP .. msgID .. SEP .. i .. SEP .. totalChunks .. SEP .. fullMsg:sub(startIdx, endIdx)
            self:Enqueue(chunk, target, PRIORITY[opcode] or 5)
        end
    end
end

-- Send a simple opcode-only message (no payload)
function Sync:SendRaw(opcode, target)
    if not target then return end
    self:Enqueue(opcode, target, PRIORITY[opcode] or 5)
end

--------------------------
-- Send Queue
--------------------------

function Sync:Enqueue(msg, target, priority)
    priority = priority or 5
    local entry = { msg = msg, target = target, priority = priority }
    -- Stable priority insert: find first item with lower priority (higher number)
    -- Same-priority items maintain FIFO insertion order
    local pos = #sendQueue + 1
    for i = 1, #sendQueue do
        if sendQueue[i].priority > priority then
            pos = i
            break
        end
    end
    table.insert(sendQueue, pos, entry)
end

function Sync:DrainQueue()
    if #sendQueue == 0 then return end

    local entry = table.remove(sendQueue, 1)
    if not entry then return end

    local ok, err = pcall(C_ChatInfo.SendAddonMessage, PREFIX, entry.msg, "WHISPER", entry.target)
    if not ok then
        ns:PrintDebug("Sync send failed: " .. tostring(err))
    end
end

--------------------------
-- Receive & Dispatch
--------------------------

function Sync:OnAddonMessage(message, sender)
    if not message or message == "" then return end

    -- Strip realm from sender if present (WoW appends "-Realm" to whisper senders)
    -- But our partner characterName includes realm, so normalize both
    local senderNorm = sender

    -- Check if this is a chunk
    if message:sub(1, 2) == "C" .. SEP then
        self:OnChunkReceived(message, senderNorm)
        return
    end

    -- Parse opcode
    local sepPos = message:find(SEP, 1, true)
    local opcode, payload
    if sepPos then
        opcode = message:sub(1, sepPos - 1)
        payload = message:sub(sepPos + 1)
    else
        opcode = message
        payload = ""
    end

    self:Dispatch(opcode, payload, senderNorm)
end

function Sync:OnChunkReceived(message, sender)
    -- Format: C\1msgID\1chunkIdx\1totalChunks\1data
    local parts = {}
    for part in message:gmatch("[^" .. SEP .. "]+") do
        parts[#parts + 1] = part
    end
    -- parts[1]="C", parts[2]=msgID, parts[3]=chunkIdx, parts[4]=totalChunks, parts[5+]=data
    if #parts < 5 then return end

    local msgID = tonumber(parts[2])
    local chunkIdx = tonumber(parts[3])
    local totalChunks = tonumber(parts[4])
    if not msgID or not chunkIdx or not totalChunks then return end

    -- Reconstruct data (may contain SEP chars, so rejoin from part 5 onward)
    local dataStart = #parts[1] + #parts[2] + #parts[3] + #parts[4] + 5  -- 4 SEP chars + 1 for C
    local data = message:sub(dataStart)

    if not reassembly[msgID] then
        reassembly[msgID] = { total = totalChunks, chunks = {}, receivedAt = time() }
    end

    reassembly[msgID].chunks[chunkIdx] = data

    -- Check if complete
    local entry = reassembly[msgID]
    local complete = true
    for i = 1, entry.total do
        if not entry.chunks[i] then
            complete = false
            break
        end
    end

    if complete then
        local fullMsg = table.concat(entry.chunks)
        reassembly[msgID] = nil
        -- Parse and dispatch
        local sepPos = fullMsg:find(SEP, 1, true)
        local opcode, payload
        if sepPos then
            opcode = fullMsg:sub(1, sepPos - 1)
            payload = fullMsg:sub(sepPos + 1)
        else
            opcode = fullMsg
            payload = ""
        end
        self:Dispatch(opcode, payload, sender)
    end

    -- Cleanup stale reassembly buffers (older than 60 seconds)
    local now = time()
    for id, buf in pairs(reassembly) do
        if now - buf.receivedAt > 60 then
            reassembly[id] = nil
        end
    end
end

function Sync:Dispatch(opcode, payload, sender)
    if opcode == OP_PAIR then
        self:OnPairRequest(payload, sender)
    elseif opcode == OP_PACK then
        self:OnPairAck(payload, sender)
    elseif opcode == OP_PDEN then
        self:OnPairDeny(sender)
    elseif opcode == OP_PING then
        self:OnPing(sender, payload)
    elseif opcode == OP_PONG then
        self:OnPong(sender, payload)
    elseif opcode == OP_FSYN then
        self:OnFullSyncRequest(sender)
    elseif opcode == OP_FDAT then
        self:OnFullSyncData(payload, sender)
    elseif opcode == OP_FEND then
        self:OnFullSyncEnd(sender)
    elseif opcode == OP_DELT then
        self:OnDelta(payload, sender)
    elseif opcode == OP_DACK then
        self:OnDeltaAck(payload, sender)
    elseif opcode == OP_UNLK then
        self:OnUnlink(sender)
    end
end

--------------------------
-- Pairing
--------------------------

function Sync:RequestPair(targetCharKey)
    if not ns.db or not ns.db.sync then return end

    local myCharKey = ns:GetCharKey()
    local myUUID = ns.db.sync.accountUUID

    -- If we have a pending incoming request from this character, accept it
    if pendingPairFrom and pendingPairFrom == targetCharKey then
        self:AcceptPair(targetCharKey)
        return
    end

    state = "handshaking"
    local payload = myUUID .. SEP .. myCharKey
    self:Enqueue(OP_PAIR .. SEP .. payload, targetCharKey, PRIORITY[OP_PAIR])
    ns:Print(ns.COLORS.CYAN .. "Link request sent to " .. targetCharKey .. "|r")
end

function Sync:OnPairRequest(payload, sender)
    if not ns.db or not ns.db.sync then return end

    local parts = { strsplit(SEP, payload) }
    local remoteUUID = parts[1]
    local remoteChar = parts[2] or sender

    -- If we already have a partner and it's not this one, deny
    if ns.db.sync.partner and ns.db.sync.partner.accountUUID ~= remoteUUID then
        self:Enqueue(OP_PDEN, sender, PRIORITY[OP_PDEN])
        ns:Print(ns.COLORS.YELLOW .. sender .. " wants to link, but you're already linked.|r")
        return
    end

    -- Store pending request for UI to show
    pendingPairFrom = sender
    Sync._pendingPairUUID = remoteUUID
    Sync._pendingPairChar = remoteChar

    ns:Print(ns.COLORS.CYAN .. sender .. " wants to link FlipQueue.|r Open Settings > Multi-Account to accept.")

    -- If settings page is showing, refresh it
    if ns.UI and ns.UI.RefreshSettings then
        ns.UI:RefreshSettings()
    end
end

function Sync:AcceptPair(targetCharKey)
    if not ns.db or not ns.db.sync then return end

    local remoteUUID = Sync._pendingPairUUID
    local remoteChar = Sync._pendingPairChar or targetCharKey

    -- Store partner
    ns.db.sync.partner = {
        characterName = targetCharKey,
        accountUUID = remoteUUID,
        label = "Linked Account",
        lastSeen = time(),
        lastFullSync = 0,
    }

    pendingPairFrom = nil
    Sync._pendingPairUUID = nil
    Sync._pendingPairChar = nil
    state = "connected"

    -- Send acknowledgment
    local myUUID = ns.db.sync.accountUUID
    local myChar = ns:GetCharKey()
    self:Enqueue(OP_PACK .. SEP .. myUUID .. SEP .. myChar, targetCharKey, PRIORITY[OP_PACK])

    ns:Print(ns.COLORS.GREEN .. "Linked to " .. targetCharKey .. "|r")
    self:StartHeartbeat()
    if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end

    -- Trigger full sync
    C_Timer.After(1, function()
        self:RequestFullSync()
    end)
end

function Sync:DenyPair()
    if pendingPairFrom then
        self:Enqueue(OP_PDEN, pendingPairFrom, PRIORITY[OP_PDEN])
        ns:Print("Link request from " .. pendingPairFrom .. " denied.")
        pendingPairFrom = nil
        Sync._pendingPairUUID = nil
        Sync._pendingPairChar = nil
    end
end

function Sync:OnPairAck(payload, sender)
    if not ns.db or not ns.db.sync then return end

    local parts = { strsplit(SEP, payload) }
    local remoteUUID = parts[1]
    local remoteChar = parts[2] or sender

    ns.db.sync.partner = {
        characterName = sender,
        accountUUID = remoteUUID,
        label = "Linked Account",
        lastSeen = time(),
        lastFullSync = 0,
    }

    state = "connected"
    ns:Print(ns.COLORS.GREEN .. "Linked to " .. sender .. "|r")
    self:StartHeartbeat()
    if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end

    -- Trigger full sync
    C_Timer.After(1, function()
        self:RequestFullSync()
    end)
end

function Sync:OnPairDeny(sender)
    state = "disconnected"
    ns:Print(ns.COLORS.RED .. sender .. " denied the link request.|r")
end

function Sync:Unlink()
    if not ns.db or not ns.db.sync then return end

    if ns.db.sync.partner then
        self:SendRaw(OP_UNLK, ns.db.sync.partner.characterName)
        ns:Print("Unlinked from " .. ns.db.sync.partner.characterName)
    end

    ns.db.sync.partner = nil
    wipe(ns.db.sync.pendingDeltas)
    ns.db.sync.lastSentSeq = 0
    ns.db.sync.lastRecvSeq = 0
    state = "disconnected"
    self:StopHeartbeat()

    if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
end

function Sync:OnUnlink(sender)
    if not ns.db or not ns.db.sync then return end
    if ns.db.sync.partner and ns.db.sync.partner.characterName == sender then
        ns.db.sync.partner = nil
        wipe(ns.db.sync.pendingDeltas)
        state = "disconnected"
        self:StopHeartbeat()
        ns:Print(ns.COLORS.YELLOW .. sender .. " unlinked FlipQueue sync.|r")
        if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
    end
end

--------------------------
-- Heartbeat
--------------------------

function Sync:StartHeartbeat()
    self:StopHeartbeat()
    lastPongRecv = time()
    missedPings = 0
    Sync._suppressErrors = true

    heartbeatTicker = C_Timer.NewTicker(HEARTBEAT_INTERVAL, function()
        if not ns.db or not ns.db.sync or not ns.db.sync.partner then return end

        -- Only send PINGs when connected — don't spam offline partners
        if state == "connected" then
            local pingMsg = OP_PING .. SEP .. (ns.db.sync.accountUUID or "")
            self:Enqueue(pingMsg, ns.db.sync.partner.characterName, PRIORITY[OP_PING])
            lastPingSent = time()

            -- Check for timeout
            if time() - lastPongRecv > HEARTBEAT_TIMEOUT then
                missedPings = missedPings + 1
                if missedPings >= 3 then
                    state = "disconnected"
                    ns:Print(ns.COLORS.YELLOW .. "Sync partner offline.|r Waiting for reconnect.")
                    if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
                end
            end
        end
        -- When disconnected: just listen, don't ping
    end)
end

function Sync:StopHeartbeat()
    if heartbeatTicker then
        heartbeatTicker:Cancel()
        heartbeatTicker = nil
    end
end

-- Check if a sender matches our partner (by character name or account UUID)
function Sync:IsPartner(sender, uuid)
    if not ns.db or not ns.db.sync or not ns.db.sync.partner then return false end
    if uuid and ns.db.sync.partner.accountUUID == uuid then return true end
    if sender and ns.db.sync.partner.characterName == sender then return true end
    return false
end

-- Update partner's current character name (they may have logged onto a different char)
function Sync:UpdatePartnerChar(sender)
    if ns.db and ns.db.sync and ns.db.sync.partner and sender then
        ns.db.sync.partner.characterName = sender
    end
end

function Sync:OnPing(sender, payload)
    -- Respond with PONG including our UUID
    self:Enqueue(OP_PONG .. SEP .. (ns.db.sync.accountUUID or ""), sender, PRIORITY[OP_PONG])

    -- Extract sender's UUID from payload
    local senderUUID = (payload and payload ~= "") and payload or nil

    -- If this is from our partner, reconnect
    if ns.db and ns.db.sync and ns.db.sync.partner
        and self:IsPartner(sender, senderUUID)
        and state == "disconnected" then
        self:UpdatePartnerChar(sender)
        state = "connected"
        lastPongRecv = time()
        missedPings = 0
        ns.db.sync.partner.lastSeen = time()
        ns:Print(ns.COLORS.GREEN .. "Sync partner reconnected.|r")

        -- Replay or full sync
        local pending = ns.db.sync.pendingDeltas
        if #pending > REPLAY_THRESHOLD then
            wipe(pending)
            self:RequestFullSync()
        elseif #pending > 0 then
            self:ReplayPendingDeltas()
            C_Timer.After(2, function()
                self:RequestFullSync()
            end)
        else
            self:RequestFullSync()
        end

        if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
    end
end

function Sync:OnPong(sender, payload)
    -- Extract sender's UUID from payload
    local senderUUID = (payload and payload ~= "") and payload or nil

    if ns.db and ns.db.sync and ns.db.sync.partner
        and self:IsPartner(sender, senderUUID) then
        self:UpdatePartnerChar(sender)
        lastPongRecv = time()
        missedPings = 0
        ns.db.sync.partner.lastSeen = time()

        if state == "disconnected" then
            state = "connected"
            ns:Print(ns.COLORS.GREEN .. "Sync partner reconnected.|r")
            self:RequestFullSync()
            if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
        end
    end
end

--------------------------
-- Full Sync
--------------------------

function Sync:RequestFullSync()
    if not self:IsLinked() then return end
    state = "syncing"
    self:SendRaw(OP_FSYN, ns.db.sync.partner.characterName)
    -- Also send our own data
    self:SendFullSync()
end

function Sync:OnFullSyncRequest(sender)
    if not self:IsLinked() then return end
    state = "syncing"
    self:SendFullSync()
end

function Sync:BuildFullSyncPayload()
    if not ns.db then return {} end

    local payload = {
        accountUUID = ns.db.sync.accountUUID,
        ownedCharacters = {},
        characters = {},
        warbank = ns.db.warbank,
        todoLists = ns.db.todoLists,
        log = ns.db.log,
        imports = ns.db.imports,
        doNotTrack = ns.db.doNotTrack,
        guilds = ns.db.guilds,
    }

    -- Only send characters owned by this account
    local myUUID = ns.db.sync.accountUUID
    for charKey, charData in pairs(ns.db.characters or {}) do
        if not charData.accountUUID or charData.accountUUID == myUUID then
            payload.characters[charKey] = charData
            table.insert(payload.ownedCharacters, charKey)
        end
    end

    return payload
end

function Sync:SendFullSync()
    if not self:IsLinked() then return end

    local payload = self:BuildFullSyncPayload()
    local serialized = self:Serialize(payload)

    -- Send as chunked FDAT messages
    local totalChunks = math.ceil(#serialized / CHUNK_SIZE)
    for i = 1, totalChunks do
        local startIdx = (i - 1) * CHUNK_SIZE + 1
        local endIdx = math.min(i * CHUNK_SIZE, #serialized)
        local chunk = serialized:sub(startIdx, endIdx)
        local msg = OP_FDAT .. SEP .. i .. SEP .. totalChunks .. SEP .. chunk
        self:Enqueue(msg, ns.db.sync.partner.characterName, PRIORITY[OP_FDAT])
    end

    -- Send end marker
    self:Enqueue(OP_FEND, ns.db.sync.partner.characterName, PRIORITY[OP_FEND])
end

function Sync:OnFullSyncData(payload, sender)
    -- Format: chunkIdx\1totalChunks\1data
    local sepPos1 = payload:find(SEP, 1, true)
    if not sepPos1 then return end
    local sepPos2 = payload:find(SEP, sepPos1 + 1, true)
    if not sepPos2 then return end

    local chunkIdx = tonumber(payload:sub(1, sepPos1 - 1))
    local totalChunks = tonumber(payload:sub(sepPos1 + 1, sepPos2 - 1))
    local data = payload:sub(sepPos2 + 1)

    if not chunkIdx or not totalChunks then return end

    fullSyncExpected = totalChunks
    fullSyncBuffer[chunkIdx] = data
end

function Sync:OnFullSyncEnd(sender)
    if not fullSyncExpected then return end

    -- Reassemble
    local complete = true
    for i = 1, fullSyncExpected do
        if not fullSyncBuffer[i] then
            complete = false
            break
        end
    end

    if not complete then
        ns:PrintDebug("Full sync incomplete — missing chunks")
        wipe(fullSyncBuffer)
        fullSyncExpected = nil
        return
    end

    local serialized = ""
    for i = 1, fullSyncExpected do
        serialized = serialized .. fullSyncBuffer[i]
    end
    wipe(fullSyncBuffer)
    fullSyncExpected = nil

    local remoteData = self:Deserialize(serialized)
    if not remoteData or type(remoteData) ~= "table" then
        ns:PrintDebug("Full sync: deserialization failed")
        return
    end

    self:MergeFullSync(remoteData)
    state = "connected"
    if ns.db.sync.partner then
        ns.db.sync.partner.lastFullSync = time()
    end
    ns:Print(ns.COLORS.GREEN .. "Sync complete.|r")

    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
    if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
end

--------------------------
-- Merge Algorithms
--------------------------

function Sync:MergeFullSync(remote)
    if not ns.db or not remote then return end

    self._applying = true

    self:MergeCharacters(remote.characters, remote.ownedCharacters, remote.accountUUID)
    self:MergeWarbank(remote.warbank)
    self:MergeTodoLists(remote.todoLists)
    self:MergeLog(remote.log)
    self:MergeImports(remote.imports)
    self:MergeDoNotTrack(remote.doNotTrack)

    self._applying = false
end

function Sync:MergeCharacters(remoteChars, ownedChars, remoteUUID)
    if not remoteChars then return end

    local owned = {}
    for _, ck in ipairs(ownedChars or {}) do
        owned[ck] = true
    end

    for charKey, charData in pairs(remoteChars) do
        if owned[charKey] then
            -- Remote owns this character — authoritative replace
            charData.accountUUID = remoteUUID
            ns.db.characters[charKey] = charData
        end
    end
end

function Sync:MergeWarbank(remoteWarbank)
    if not remoteWarbank then return end

    local localScan = ns.db.warbank and ns.db.warbank.lastScan or 0
    local remoteScan = remoteWarbank.lastScan or 0

    if remoteScan > localScan then
        ns.db.warbank = remoteWarbank
    end
end

function Sync:MergeTodoLists(remoteTodo)
    if not remoteTodo then return end

    -- Merge active list tasks by taskUUID (LWW per task)
    if remoteTodo.active and remoteTodo.active.tasks then
        if not ns.db.todoLists.active then
            ns.db.todoLists.active = remoteTodo.active
        else
            self:MergeTasks(ns.db.todoLists.active.tasks, remoteTodo.active.tasks)
        end
    end

    -- Merge upcoming lists by name+createdAt
    if remoteTodo.upcoming then
        local localByKey = {}
        for i, list in ipairs(ns.db.todoLists.upcoming or {}) do
            local key = (list.name or "") .. "|" .. (list.createdAt or 0)
            localByKey[key] = i
        end
        for _, remoteList in ipairs(remoteTodo.upcoming) do
            local key = (remoteList.name or "") .. "|" .. (remoteList.createdAt or 0)
            if not localByKey[key] then
                table.insert(ns.db.todoLists.upcoming, remoteList)
            end
        end
    end
end

function Sync:MergeTasks(localTasks, remoteTasks)
    if not localTasks or not remoteTasks then return end

    -- Index local tasks by UUID
    local localByUUID = {}
    for i, task in ipairs(localTasks) do
        if task.taskUUID then
            localByUUID[task.taskUUID] = i
        end
    end

    for _, remoteTask in ipairs(remoteTasks) do
        if remoteTask.taskUUID then
            local localIdx = localByUUID[remoteTask.taskUUID]
            if localIdx then
                -- Both have this task — LWW
                local localTask = localTasks[localIdx]
                local localTS = localTask._syncMeta and localTask._syncMeta.lastModifiedAt or 0
                local remoteTS = remoteTask._syncMeta and remoteTask._syncMeta.lastModifiedAt or 0
                if remoteTS > localTS then
                    localTasks[localIdx] = remoteTask
                elseif remoteTS == localTS then
                    -- Tiebreaker: higher UUID wins
                    local localBy = localTask._syncMeta and localTask._syncMeta.lastModifiedBy or ""
                    local remoteBy = remoteTask._syncMeta and remoteTask._syncMeta.lastModifiedBy or ""
                    if remoteBy > localBy then
                        localTasks[localIdx] = remoteTask
                    end
                end
            else
                -- Remote has a task we don't — add it
                table.insert(localTasks, remoteTask)
                localByUUID[remoteTask.taskUUID] = #localTasks
            end
        end
    end
end

function Sync:MergeLog(remoteLog)
    if not remoteLog then return end

    -- Build dedup set from local log
    local seen = {}
    for _, entry in ipairs(ns.db.log or {}) do
        local key = (entry.itemKey or "") .. "|" .. (entry.charKey or "") .. "|" .. (entry.postedAt or 0)
        seen[key] = true
    end

    -- Add new remote entries
    for _, entry in ipairs(remoteLog) do
        local key = (entry.itemKey or "") .. "|" .. (entry.charKey or "") .. "|" .. (entry.postedAt or 0)
        if not seen[key] then
            table.insert(ns.db.log, entry)
            seen[key] = true
        end
    end
end

function Sync:MergeImports(remoteImports)
    if not remoteImports then return end

    for source, deals in pairs(remoteImports) do
        ns.db.imports[source] = ns.db.imports[source] or {}
        for key, deal in pairs(deals) do
            if not ns.db.imports[source][key] then
                ns.db.imports[source][key] = deal
            end
        end
    end
end

function Sync:MergeDoNotTrack(remoteDNT)
    if not remoteDNT then return end
    for itemID, val in pairs(remoteDNT) do
        if not ns.db.doNotTrack[itemID] then
            ns.db.doNotTrack[itemID] = val
        end
    end
end

--------------------------
-- Delta Sync
--------------------------

function Sync:EmitDelta(deltaType, data)
    if self._applying then return end
    if not ns.db or not ns.db.sync then return end

    ns.db.sync.lastSentSeq = ns.db.sync.lastSentSeq + 1
    local seq = ns.db.sync.lastSentSeq

    local delta = {
        seq = seq,
        type = deltaType,
        data = data,
        ts = time(),
        accountUUID = ns.db.sync.accountUUID,
    }

    if state == "connected" and ns.db.sync.partner then
        -- Send immediately
        self:SendMessage(OP_DELT, delta, ns.db.sync.partner.characterName)
        -- Track for ACK
        ns.db.sync.pendingDeltas[#ns.db.sync.pendingDeltas + 1] = {
            seq = seq, sentAt = time(), retries = 0, delta = delta,
        }
    else
        -- Queue for later delivery
        table.insert(ns.db.sync.pendingDeltas, {
            seq = seq, sentAt = 0, retries = 0, delta = delta,
        })
    end

    -- Enforce cap
    while #ns.db.sync.pendingDeltas > MAX_PENDING_DELTAS do
        table.remove(ns.db.sync.pendingDeltas, 1)
    end
end

function Sync:OnDelta(payload, sender)
    if not ns.db or not ns.db.sync then return end
    if not ns.db.sync.partner then return end

    local delta = self:Deserialize(payload)
    if not delta or type(delta) ~= "table" then return end

    -- Send ACK
    local ackPayload = tostring(delta.seq or 0)
    self:Enqueue(OP_DACK .. SEP .. ackPayload, sender, PRIORITY[OP_DACK])

    -- Deduplicate
    if delta.seq and delta.seq <= ns.db.sync.lastRecvSeq then
        return -- already seen
    end
    if delta.seq then
        ns.db.sync.lastRecvSeq = delta.seq
    end

    -- Apply the delta
    self:ApplyDelta(delta)
end

function Sync:ApplyDelta(delta)
    if not delta or not delta.type then return end

    self._applying = true

    local deltaType = delta.type
    local data = delta.data

    if deltaType == "CHAR" then
        -- Character data update
        if data and data.charKey and data.charData then
            data.charData.accountUUID = delta.accountUUID
            ns.db.characters[data.charKey] = data.charData
        end
    elseif deltaType == "WB" then
        -- Warbank update
        if data then
            local localScan = ns.db.warbank and ns.db.warbank.lastScan or 0
            local remoteScan = data.lastScan or 0
            if remoteScan > localScan then
                ns.db.warbank = data
            end
        end
    elseif deltaType == "CMETA" then
        -- Character metadata (gold, lastLogin)
        if data and data.charKey then
            local charData = ns.db.characters[data.charKey]
            if charData then
                if data.gold then charData.gold = data.gold end
                if data.lastLogin then charData.lastLogin = data.lastLogin end
                if data.level then charData.level = data.level end
            end
        end
    elseif deltaType == "TDCOMMIT" then
        -- Todo list committed
        if data and data.mode and data.list then
            if ns.TodoList and ns.TodoList.CommitList then
                ns.TodoList:CommitList(data.list, data.mode)
            end
        end
    elseif deltaType == "TDSTATUS" then
        -- Task status update
        if data and data.taskUUID then
            local task = self:FindTaskByUUID(data.taskUUID)
            if task then
                local localTS = task._syncMeta and task._syncMeta.lastModifiedAt or 0
                local remoteTS = delta.ts or 0
                if remoteTS >= localTS then
                    task.status = data.status or task.status
                    task.failReason = data.failReason
                    task._syncMeta = {
                        lastModifiedBy = delta.accountUUID,
                        lastModifiedAt = delta.ts,
                    }
                end
            end
        end
    elseif deltaType == "TDLOG" then
        -- Task moved to log
        if data and data.logEntry then
            local key = (data.logEntry.itemKey or "") .. "|" ..
                        (data.logEntry.charKey or "") .. "|" ..
                        (data.logEntry.postedAt or 0)
            local exists = false
            for _, entry in ipairs(ns.db.log) do
                local ek = (entry.itemKey or "") .. "|" .. (entry.charKey or "") .. "|" .. (entry.postedAt or 0)
                if ek == key then exists = true; break end
            end
            if not exists then
                table.insert(ns.db.log, data.logEntry)
            end
            -- Remove task from active list
            if data.taskUUID then
                self:RemoveTaskByUUID(data.taskUUID)
            end
        end
    elseif deltaType == "TDSKIP" then
        if data and data.taskUUID then
            local task = self:FindTaskByUUID(data.taskUUID)
            if task then
                task.status = "skipped"
                task.failReason = data.reason
                task._syncMeta = {
                    lastModifiedBy = delta.accountUUID,
                    lastModifiedAt = delta.ts,
                }
            end
        end
    elseif deltaType == "TDDEL" then
        if data and data.taskUUID then
            self:RemoveTaskByUUID(data.taskUUID)
        end
    elseif deltaType == "TDCLEAR" then
        if ns.db.todoLists.active then
            ns.db.todoLists.active = nil
        end
    elseif deltaType == "IMP" then
        if data and data.source and data.deals then
            ns.db.imports[data.source] = ns.db.imports[data.source] or {}
            for key, deal in pairs(data.deals) do
                ns.db.imports[data.source][key] = deal
            end
        end
    elseif deltaType == "DNT+" then
        if data and data.itemID then
            ns.db.doNotTrack[data.itemID] = data.name or true
        end
    elseif deltaType == "DNT-" then
        if data and data.itemID then
            ns.db.doNotTrack[data.itemID] = nil
        end
    end

    self._applying = false

    -- Refresh UI
    if ns.UI and ns.UI.mainFrame and ns.UI.mainFrame:IsShown() then
        ns.UI:Refresh()
    end
    if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
end

-- Find a task in active todo list by UUID
function Sync:FindTaskByUUID(uuid)
    if not uuid or not ns.db.todoLists or not ns.db.todoLists.active then return nil end
    for _, task in ipairs(ns.db.todoLists.active.tasks or {}) do
        if task.taskUUID == uuid then return task end
    end
    return nil
end

-- Remove a task from active todo list by UUID
function Sync:RemoveTaskByUUID(uuid)
    if not uuid or not ns.db.todoLists or not ns.db.todoLists.active then return end
    local tasks = ns.db.todoLists.active.tasks
    if not tasks then return end
    for i = #tasks, 1, -1 do
        if tasks[i].taskUUID == uuid then
            table.remove(tasks, i)
            return
        end
    end
end

--------------------------
-- Delta ACK & Retry
--------------------------

function Sync:OnDeltaAck(payload, sender)
    local seq = tonumber(payload)
    if not seq then return end

    -- Remove from pending
    local pending = ns.db and ns.db.sync and ns.db.sync.pendingDeltas
    if not pending then return end
    for i = #pending, 1, -1 do
        if pending[i].seq == seq then
            table.remove(pending, i)
            break
        end
    end
end

function Sync:RetryUnacked()
    if not self:IsLinked() or state ~= "connected" then return end

    local now = time()
    local pending = ns.db.sync.pendingDeltas
    if not pending then return end

    for i = #pending, 1, -1 do
        local entry = pending[i]
        if entry.sentAt > 0 and (now - entry.sentAt) > RETRY_INTERVAL then
            if entry.retries >= MAX_RETRIES then
                -- Give up on this delta
                table.remove(pending, i)
            else
                -- Retry
                entry.retries = entry.retries + 1
                entry.sentAt = now
                self:SendMessage(OP_DELT, entry.delta, ns.db.sync.partner.characterName)
            end
        end
    end
end

function Sync:ReplayPendingDeltas()
    if not self:IsLinked() then return end

    local pending = ns.db.sync.pendingDeltas
    if not pending or #pending == 0 then return end

    ns:PrintDebug("Replaying " .. #pending .. " queued changes...")
    for _, entry in ipairs(pending) do
        entry.sentAt = time()
        entry.retries = 0
        self:SendMessage(OP_DELT, entry.delta, ns.db.sync.partner.characterName)
    end
end

--------------------------
-- Public API
--------------------------

function Sync:IsLinked()
    return ns.db and ns.db.sync and ns.db.sync.partner ~= nil
end

function Sync:IsConnected()
    return self:IsLinked() and state == "connected"
end

function Sync:GetState()
    return state
end

function Sync:GetPartnerName()
    if ns.db and ns.db.sync and ns.db.sync.partner then
        return ns.db.sync.partner.characterName
    end
    return nil
end

function Sync:GetPendingCount()
    if ns.db and ns.db.sync and ns.db.sync.pendingDeltas then
        return #ns.db.sync.pendingDeltas
    end
    return 0
end

function Sync:HasPendingPairRequest()
    return pendingPairFrom ~= nil
end

function Sync:GetPendingPairFrom()
    return pendingPairFrom
end

function Sync:GenerateUUID()
    return string.format("%x%x", time(), math.random(0, 0xFFFFFF))
end
