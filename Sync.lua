-- Sync.lua
-- Multi-account real-time sync via BNet addon messaging
-- Supports N linked accounts with per-partner state, offline delta queuing,
-- and automatic reconnect via BN_FRIEND_INFO_CHANGED.
local addonName, ns = ...

local Sync = {}
ns.Sync = Sync

--------------------------
-- Constants
--------------------------

local PREFIX = "FlpQ"
local SEP = "\001"          -- field separator (ASCII SOH)
local CHUNK_SIZE_BNET = 3900      -- BNSendGameData supports ~4078 bytes; leave headroom
local CHUNK_SIZE_WHISPER = 235    -- SendAddonMessage WHISPER max ~255 bytes
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

local partnerStates = {}       -- [accountUUID] = "disconnected" | "connected" | "syncing"
-- Per-priority send buckets. Each bucket is a ring-style array with
-- head/tail indices so enqueue and dequeue are both O(1). The previous
-- single-sorted-array approach did a linear insert (O(N) scan + O(N)
-- shift) on every Enqueue, which became O(N²) during a full sync and
-- tripped WoW's "script ran too long" watchdog once the payload was
-- chunked into a few thousand messages.
local sendQueues = {}          -- [priority] = { head, tail, [head..tail] = entry }
local sendQueueCount = 0       -- total pending messages across all buckets
local reassembly = {}          -- chunk reassembly buffers
local fullSyncBuffers = {}     -- [accountUUID] = { chunks = {}, expected = N }
local heartbeatTicker = nil
local retryTicker = nil
local sendTicker = nil
local lastPongRecv = {}        -- [accountUUID] = timestamp
local missedPings = {}         -- [accountUUID] = count
local pendingPairRequests = {} -- [senderGameAccountID] = { uuid, bnetAccountID, charName }
local friendRetryTimer = nil   -- delayed retry for BN_FRIEND_INFO_CHANGED timing
local reconnectTicker = nil    -- periodic probe for disconnected partners
local syncLog = {}             -- ring buffer of recent sync events for debugging
local SYNC_LOG_MAX = 200

--------------------------
-- Init
--------------------------

function Sync:Init()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("BN_CHAT_MSG_ADDON")
    frame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "BN_CHAT_MSG_ADDON" then
            local prefix, message, _, senderID = ...
            if prefix == PREFIX and message then
                self:OnBNetMessage(message, senderID)
            end
        elseif event == "CHAT_MSG_ADDON" then
            local prefix, message, channel, sender = ...
            if prefix == PREFIX and channel == "WHISPER" and message then
                self:OnWhisperMessage(message, sender)
            end
        elseif event == "BN_FRIEND_INFO_CHANGED" then
            self:OnFriendInfoChanged()
        end
    end)

    -- Suppress "No player named X" system errors caused by whisper transport probes
    -- when a whisper partner is offline. Only suppresses for names we recognize.
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if not msg or not self:HasWhisperPartners() then return end
        for _, partner in pairs(ns.db.sync.partners) do
            if partner.transport == "whisper" and partner.charName then
                -- charName is "Name-Realm"; match either the full string or just "Name"
                local nameOnly = partner.charName:match("^([^-]+)") or partner.charName
                if msg:find(nameOnly, 1, true) then
                    return true -- suppress
                end
            end
        end
    end)

    -- Register BNet addon prefix
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    -- Start send queue ticker
    sendTicker = C_Timer.NewTicker(SEND_RATE, function()
        self:DrainQueue()
    end)

    -- Probe existing partners on login
    if ns.db and ns.db.sync and ns.db.sync.partners then
        C_Timer.After(3, function()
            self:ProbePartners()
        end)
    end

    -- Start retry ticker for unacknowledged deltas
    retryTicker = C_Timer.NewTicker(RETRY_INTERVAL, function()
        self:RetryUnacked()
    end)

    -- Periodic reconnect probe for disconnected partners (every 30s)
    reconnectTicker = C_Timer.NewTicker(30, function()
        self:ProbeDisconnectedPartners()
    end)
end

-- Append an entry to the sync debug log (ring buffer). Defensive
-- against nil/empty event names so the renderer never produces
-- invisible rows (the SettingsFrame sync log view wraps the event
-- in color codes and an empty event disappears visually).
function Sync:Log(event, detail)
    if type(event) ~= "string" or event == "" then
        event = "?"
    end
    syncLog[#syncLog + 1] = {
        t = time(),
        event = event,
        detail = detail or "",
    }
    while #syncLog > SYNC_LOG_MAX do
        table.remove(syncLog, 1)
    end
end

-- Return the sync debug log for the UI.
function Sync:GetSyncLog()
    return syncLog
end

-- Send a probe ping to all stored partners to see who's online
function Sync:ProbePartners()
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return end
    for uuid, partner in pairs(ns.db.sync.partners) do
        local target, transport = self:ResolveTarget(uuid)
        if target then
            self:Log("PROBE", (partner.label or uuid) .. " → " .. transport .. ":" .. tostring(target))
            local pingMsg = OP_PING .. SEP .. (ns.db.sync.accountUUID or "")
            self:Enqueue(pingMsg, target, PRIORITY[OP_PING], transport)
        else
            self:Log("PROBE", (partner.label or uuid) .. " → not reachable")
        end
    end
end

-- Probe only disconnected partners — called periodically to catch missed events.
function Sync:ProbeDisconnectedPartners()
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return end
    for uuid, partner in pairs(ns.db.sync.partners) do
        local pState = partnerStates[uuid] or "disconnected"
        if pState == "disconnected" then
            local target, transport = self:ResolveTarget(uuid)
            if target then
                self:Log("RECONNECT_PROBE", (partner.label or uuid) .. " probing via " .. transport)
                local pingMsg = OP_PING .. SEP .. (ns.db.sync.accountUUID or "")
                self:Enqueue(pingMsg, target, PRIORITY[OP_PING], transport)
            end
        end
    end
end

--------------------------
-- BNet Lookup
--------------------------

-- Normalize a realm name for comparison: lowercase, strip spaces/hyphens.
local function NormalizeRealm(realm)
    if not realm or realm == "" then return "" end
    return realm:lower():gsub("[%s%-]", "")
end

-- Normalize a sender identifier from a receive handler into (target, transport).
-- Whisper senders arrive as strings prefixed with "W:" (e.g. "W:Foo-Realm").
-- BNet senders are numeric gameAccountID values.
local function SenderToTarget(senderID)
    if type(senderID) == "string" and senderID:sub(1, 2) == "W:" then
        return senderID:sub(3), "whisper"
    end
    return senderID, "bnet"
end

-- Find a BNet friend by character name (and optional realm).
-- Returns bnetAccountID, gameAccountID, status, extra.
-- On success: bnetAccountID, gameAccountID, "found", { battleTag, charName, realmName }
-- On failure: nil, nil, status, extra
--   "offline"      – name (and realm if given) matched a BNet friend but they're not in WoW
--   "ambiguous"    – multiple online friends share that name; extra = list of Name-Realm strings
--   "not_found"    – no BNet friend has that character name
function Sync:FindBNetByCharName(charName)
    local nameOnly, realmInput = charName:match("^([^-]+)-(.+)$")
    if not nameOnly then
        nameOnly = charName:match("^%s*(.-)%s*$")  -- trim whitespace
        realmInput = nil
    end
    local normRealm = realmInput and NormalizeRealm(realmInput) or nil

    local matches = {}       -- { {bnetAccountID, gameAccountID, realmName}, ... }
    local offlineMatches = 0 -- count of BNet friends whose battleTag/note we can't check by char, but are offline
    local numFriends = BNGetNumFriends()

    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo then
            local numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(i)
            if numGameAccounts == 0 then
                -- Friend is offline or not in a game — can't check character names
                offlineMatches = offlineMatches + 1
            end
            for j = 1, numGameAccounts do
                local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameInfo and gameInfo.characterName and gameInfo.characterName == nameOnly then
                    if normRealm then
                        -- Realm was specified — must match
                        if NormalizeRealm(gameInfo.realmName or "") == normRealm then
                            return accountInfo.bnetAccountID, gameInfo.gameAccountID, "found", {
                                battleTag = accountInfo.battleTag,
                                charName  = gameInfo.characterName,
                                realmName = gameInfo.realmName,
                            }
                        end
                    else
                        matches[#matches + 1] = {
                            bnetAccountID = accountInfo.bnetAccountID,
                            gameAccountID = gameInfo.gameAccountID,
                            battleTag     = accountInfo.battleTag,
                            charName      = gameInfo.characterName,
                            realmName     = gameInfo.realmName or "?",
                        }
                    end
                end
            end
        end
    end

    -- Realm was specified but no exact match found
    if normRealm then
        return nil, nil, (offlineMatches > 0) and "offline" or "not_found"
    end

    -- No realm specified — check matches
    if #matches == 1 then
        return matches[1].bnetAccountID, matches[1].gameAccountID, "found", {
            battleTag = matches[1].battleTag,
            charName  = matches[1].charName,
            realmName = matches[1].realmName,
        }
    elseif #matches > 1 then
        -- Build a list of realms for the error message
        local realms = {}
        for _, m in ipairs(matches) do
            realms[#realms + 1] = nameOnly .. "-" .. m.realmName
        end
        return nil, nil, "ambiguous", realms
    end

    -- No matches at all
    return nil, nil, (offlineMatches > 0) and "offline" or "not_found"
end

-- Look up the current session gameAccountID for a stored bnetAccountID.
-- Returns gameAccountID or nil if offline / not in WoW.
function Sync:GetGameAccountID(bnetAccountID)
    if not bnetAccountID then return nil end
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.bnetAccountID == bnetAccountID then
            local numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(i)
            for j = 1, numGameAccounts do
                local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameInfo and gameInfo.clientProgram == BNET_CLIENT_WOW then
                    return gameInfo.gameAccountID
                end
            end
            return nil -- friend found but not in WoW
        end
    end
    return nil
end

-- Look up the BattleTag for a given gameAccountID by walking the BNet friends list.
function Sync:GetBattleTagFromGameID(gameAccountID)
    if not gameAccountID then return nil end
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo then
            local numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(i)
            for j = 1, numGameAccounts do
                local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameInfo and gameInfo.gameAccountID == gameAccountID then
                    return accountInfo.battleTag
                end
            end
        end
    end
    return nil
end

-- Look up the BattleTag for a stored bnetAccountID.
function Sync:GetBattleTagFromBNetID(bnetAccountID)
    if not bnetAccountID then return nil end
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.bnetAccountID == bnetAccountID then
            return accountInfo.battleTag
        end
    end
    return nil
end

-- Reverse lookup: given a gameAccountID (from BN_CHAT_MSG_ADDON sender),
-- find the bnetAccountID it belongs to.
function Sync:GetBNetAccountFromGameID(gameAccountID)
    if not gameAccountID then return nil end
    local gameAccountInfo = C_BattleNet.GetGameAccountInfoByID(gameAccountID)
    if gameAccountInfo then
        -- Walk friends to find the bnetAccountID that owns this game account
        local numFriends = BNGetNumFriends()
        for i = 1, numFriends do
            local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
            if accountInfo then
                local numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(i)
                for j = 1, numGameAccounts do
                    local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                    if gameInfo and gameInfo.gameAccountID == gameAccountID then
                        return accountInfo.bnetAccountID
                    end
                end
            end
        end
    end
    return nil
end

-- Find which partner UUID corresponds to a given bnetAccountID
function Sync:FindPartnerByBNet(bnetAccountID)
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return nil end
    for uuid, partner in pairs(ns.db.sync.partners) do
        if partner.bnetAccountID == bnetAccountID then
            return uuid
        end
    end
    return nil
end

-- Find which partner UUID corresponds to a whisper-transport character name.
function Sync:FindPartnerByCharName(charName)
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return nil end
    for uuid, partner in pairs(ns.db.sync.partners) do
        if partner.transport == "whisper" and partner.charName == charName then
            return uuid
        end
    end
    return nil
end

-- True if any linked partner uses the whisper transport.
function Sync:HasWhisperPartners()
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return false end
    for _, partner in pairs(ns.db.sync.partners) do
        if partner.transport == "whisper" then return true end
    end
    return false
end

-- Resolve "how to reach this partner right now". Returns (target, transport, chunkSize)
-- or nil if the partner can't be reached (e.g. BNet friend offline).
--   target    — gameAccountID (number) for bnet, charName (string) for whisper
--   transport — "bnet" or "whisper"
--   chunkSize — appropriate CHUNK_SIZE_* for this transport
function Sync:ResolveTarget(partnerUUID)
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return nil end
    local partner = ns.db.sync.partners[partnerUUID]
    if not partner then return nil end

    if partner.transport == "whisper" then
        if partner.charName then
            return partner.charName, "whisper", CHUNK_SIZE_WHISPER
        end
        return nil
    end

    -- Default / "bnet" transport
    if not partner.bnetAccountID then return nil end
    local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
    if not gameAccountID then return nil end
    return gameAccountID, "bnet", CHUNK_SIZE_BNET
end

-- Find which partner UUID sent a message.
-- senderID may be a numeric gameAccountID (bnet) or "W:Name-Realm" (whisper).
function Sync:IdentifySender(senderID)
    if type(senderID) == "string" and senderID:sub(1, 2) == "W:" then
        local uuid = self:FindPartnerByCharName(senderID:sub(3))
        return uuid, nil
    end
    local bnetAccountID = self:GetBNetAccountFromGameID(senderID)
    if not bnetAccountID then return nil, nil end
    local uuid = self:FindPartnerByBNet(bnetAccountID)
    return uuid, bnetAccountID
end

-- Get list of all partners with their current gameAccountID (online only)
function Sync:GetOnlinePartners()
    local result = {}
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return result end
    for uuid, partner in pairs(ns.db.sync.partners) do
        if partner.bnetAccountID then
            local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
            if gameAccountID then
                result[uuid] = gameAccountID
            end
        end
    end
    return result
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
        local numEnd = pos + 1
        while numEnd <= #str do
            local c = str:byte(numEnd)
            if (c >= 48 and c <= 57) or c == 46 or c == 45 or c == 101 or c == 69 or c == 43 then
                numEnd = numEnd + 1
            else
                break
            end
        end
        local num = tonumber(str:sub(pos + 1, numEnd - 1))
        return num, numEnd
    elseif ch == "s" then
        local colonPos = str:find(":", pos + 1, true)
        if not colonPos then return nil, pos end
        local len = tonumber(str:sub(pos + 1, colonPos - 1))
        if not len then return nil, pos end
        local content = str:sub(colonPos + 1, colonPos + len)
        return content, colonPos + len + 1
    elseif ch == "A" then
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
        if str:sub(nextPos, nextPos) == "}" then nextPos = nextPos + 1 end
        return arr, nextPos
    elseif ch == "T" then
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
function Sync:SendMessage(opcode, payload, target, transport, chunkSize)
    if not target then return end
    transport = transport or "bnet"
    chunkSize = chunkSize or CHUNK_SIZE_BNET

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

    if msgLen <= chunkSize then
        self:Enqueue(fullMsg, target, PRIORITY[opcode] or 5, transport)
    else
        msgCounter = msgCounter + 1
        local msgID = msgCounter
        local totalChunks = math.ceil(msgLen / chunkSize)

        for i = 1, totalChunks do
            local startIdx = (i - 1) * chunkSize + 1
            local endIdx = math.min(i * chunkSize, msgLen)
            local chunk = "C" .. SEP .. msgID .. SEP .. i .. SEP .. totalChunks .. SEP .. fullMsg:sub(startIdx, endIdx)
            self:Enqueue(chunk, target, PRIORITY[opcode] or 5, transport)
        end
    end
end

-- Send a simple opcode-only message (no payload)
function Sync:SendRaw(opcode, target, transport)
    if not target then return end
    self:Enqueue(opcode, target, PRIORITY[opcode] or 5, transport or "bnet")
end

--------------------------
-- Send Queue
--------------------------

-- Get-or-create a send bucket for the given priority. Buckets are
-- lazy so we don't allocate empty tables we never use.
local function GetSendBucket(priority)
    local q = sendQueues[priority]
    if not q then
        q = { head = 1, tail = 0 }
        sendQueues[priority] = q
    end
    return q
end

function Sync:Enqueue(msg, target, priority, transport)
    priority = priority or 5
    transport = transport or "bnet"
    local q = GetSendBucket(priority)
    q.tail = q.tail + 1
    q[q.tail] = { msg = msg, target = target, priority = priority, transport = transport }
    sendQueueCount = sendQueueCount + 1
end

function Sync:DrainQueue()
    if sendQueueCount == 0 then return end

    -- Pop the highest-urgency entry (lowest priority number) first.
    -- PRIORITY values are all 1..5 per the opcode table at the top
    -- of the file, so the fixed range is safe.
    local entry
    for p = 1, 5 do
        local q = sendQueues[p]
        if q and q.head <= q.tail then
            entry = q[q.head]
            q[q.head] = nil
            q.head = q.head + 1
            -- Reset indices once the bucket drains so they can't
            -- grow unbounded over a long session.
            if q.head > q.tail then
                q.head, q.tail = 1, 0
            end
            sendQueueCount = sendQueueCount - 1
            break
        end
    end
    if not entry then return end

    local ok, err
    if entry.transport == "whisper" then
        ok, err = pcall(C_ChatInfo.SendAddonMessage, PREFIX, entry.msg, "WHISPER", entry.target)
    else
        ok, err = pcall(BNSendGameData, entry.target, PREFIX, entry.msg)
    end
    if not ok then
        self:Log("SEND_ERR", tostring(err) .. " → " .. tostring(entry.transport) .. ":" .. tostring(entry.target))
        ns:PrintDebug("Sync send failed: " .. tostring(err))
    else
        -- Log successful sends (skip FDAT chunks to reduce noise, same rule as RECV)
        local firstSep = entry.msg:find(SEP, 1, true)
        local opcode = firstSep and entry.msg:sub(1, firstSep - 1) or entry.msg
        -- Chunked messages start with "C" — peel back to the inner opcode for readability
        if opcode == "C" then
            opcode = "CHUNK"
        end
        if opcode ~= OP_FDAT then
            local detail = entry.transport .. ":" .. tostring(entry.target)
            self:Log("SEND " .. opcode, detail)
        end
    end
end

--------------------------
-- Receive & Dispatch
--------------------------

function Sync:OnBNetMessage(message, senderGameAccountID)
    if not message or message == "" then return end

    -- Check if this is a chunk
    if message:sub(1, 2) == "C" .. SEP then
        self:OnChunkReceived(message, senderGameAccountID)
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

    self:Dispatch(opcode, payload, senderGameAccountID)
end

-- Whisper transport receive path. sender is "Name-Realm" from CHAT_MSG_ADDON WHISPER.
-- We prefix with "W:" to distinguish from numeric BNet gameAccountIDs throughout the pipeline.
function Sync:OnWhisperMessage(message, sender)
    if not message or message == "" or not sender then return end
    local senderKey = "W:" .. sender

    -- Check if this is a chunk
    if message:sub(1, 2) == "C" .. SEP then
        self:OnChunkReceived(message, senderKey)
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

    self:Dispatch(opcode, payload, senderKey)
end

function Sync:OnChunkReceived(message, senderGameAccountID)
    -- Format: C\1msgID\1chunkIdx\1totalChunks\1data
    local parts = {}
    for part in message:gmatch("[^" .. SEP .. "]+") do
        parts[#parts + 1] = part
    end
    if #parts < 5 then return end

    local msgID = tonumber(parts[2])
    local chunkIdx = tonumber(parts[3])
    local totalChunks = tonumber(parts[4])
    if not msgID or not chunkIdx or not totalChunks then return end

    -- Reconstruct data (may contain SEP chars, so rejoin from part 5 onward)
    local dataStart = #parts[1] + #parts[2] + #parts[3] + #parts[4] + 5
    local data = message:sub(dataStart)

    -- Key reassembly by sender + msgID to prevent cross-partner confusion
    local reassemblyKey = tostring(senderGameAccountID) .. ":" .. msgID
    if not reassembly[reassemblyKey] then
        reassembly[reassemblyKey] = { total = totalChunks, chunks = {}, receivedAt = time() }
    end

    reassembly[reassemblyKey].chunks[chunkIdx] = data

    local entry = reassembly[reassemblyKey]
    local complete = true
    for i = 1, entry.total do
        if not entry.chunks[i] then
            complete = false
            break
        end
    end

    if complete then
        local fullMsg = table.concat(entry.chunks)
        reassembly[reassemblyKey] = nil
        local sepPos = fullMsg:find(SEP, 1, true)
        local opcode, payload
        if sepPos then
            opcode = fullMsg:sub(1, sepPos - 1)
            payload = fullMsg:sub(sepPos + 1)
        else
            opcode = fullMsg
            payload = ""
        end
        self:Dispatch(opcode, payload, senderGameAccountID)
    end

    -- Cleanup stale reassembly buffers (older than 60 seconds)
    local now = time()
    for id, buf in pairs(reassembly) do
        if now - buf.receivedAt > 60 then
            reassembly[id] = nil
        end
    end
end

function Sync:Dispatch(opcode, payload, senderGameAccountID)
    -- Log all incoming traffic (skip FDAT chunks to reduce noise)
    if opcode ~= OP_FDAT then
        local detail = "from " .. tostring(senderGameAccountID)
        if payload and payload ~= "" and #payload < 80 then
            detail = detail .. " | " .. payload
        end
        self:Log("RECV " .. opcode, detail)
    end

    -- SECURITY: Only allow PAIR/PACK/PDEN from anyone (pairing flow).
    -- All other opcodes require the sender to be a known linked partner.
    if opcode ~= OP_PAIR and opcode ~= OP_PACK and opcode ~= OP_PDEN then
        local senderUUID = self:IdentifySender(senderGameAccountID)
        if not senderUUID or not (ns.db and ns.db.sync and ns.db.sync.partners and ns.db.sync.partners[senderUUID]) then
            self:Log("REJECT " .. opcode, "from non-partner " .. tostring(senderGameAccountID))
            return
        end
    end

    if opcode == OP_PAIR then
        self:OnPairRequest(payload, senderGameAccountID)
    elseif opcode == OP_PACK then
        self:OnPairAck(payload, senderGameAccountID)
    elseif opcode == OP_PDEN then
        self:OnPairDeny(senderGameAccountID)
    elseif opcode == OP_PING then
        self:OnPing(senderGameAccountID, payload)
    elseif opcode == OP_PONG then
        self:OnPong(senderGameAccountID, payload)
    elseif opcode == OP_FSYN then
        self:OnFullSyncRequest(senderGameAccountID)
    elseif opcode == OP_FDAT then
        self:OnFullSyncData(payload, senderGameAccountID)
    elseif opcode == OP_FEND then
        self:OnFullSyncEnd(senderGameAccountID)
    elseif opcode == OP_DELT then
        self:OnDelta(payload, senderGameAccountID)
    elseif opcode == OP_DACK then
        self:OnDeltaAck(payload, senderGameAccountID)
    elseif opcode == OP_UNLK then
        self:OnUnlink(senderGameAccountID)
    end
end

--------------------------
-- Pairing
--------------------------

-- transportHint: "bnet" (BNet friend, cross-realm, survives char switches) or
--                "whisper" (same BNet account, same realm, both must be online).
-- Defaults to "bnet" when unspecified.
function Sync:RequestPair(targetCharName, transportHint)
    if not ns.db or not ns.db.sync then return end
    transportHint = transportHint or "bnet"

    -- Whisper path: same BNet account, same-realm whisper
    if transportHint == "whisper" then
        local qualifiedName = targetCharName
        if not qualifiedName:find("-", 1, true) then
            qualifiedName = qualifiedName .. "-" .. GetNormalizedRealmName()
        end

        -- Already linked? Treat as reconnect.
        local existingUUID = self:FindPartnerByCharName(qualifiedName)
        if existingUUID then
            partnerStates[existingUUID] = "connected"
            lastPongRecv[existingUUID] = time()
            missedPings[existingUUID] = 0
            self:StartHeartbeat()
            self:RequestFullSyncWith(existingUUID)
            ns:Print(ns.COLORS.GREEN .. "Already linked to " .. qualifiedName .. ". Reconnecting...|r")
            return
        end

        -- Pending whisper request from this character?
        for sid, req in pairs(pendingPairRequests) do
            if req.transport == "whisper" and req.charName == qualifiedName then
                self:AcceptPair(sid)
                return
            end
        end

        -- Send PAIR via whisper. bnetAccountID = 0 indicates same-account / whisper pairing.
        local myUUID = ns.db.sync.accountUUID
        local payload = myUUID .. SEP .. "0"
        self:Enqueue(OP_PAIR .. SEP .. payload, qualifiedName, PRIORITY[OP_PAIR], "whisper")
        ns:Print(ns.COLORS.CYAN .. "Link request sent to " .. qualifiedName .. "|r " ..
                 ns.COLORS.GRAY .. "(they must be online on this realm)|r")
        return
    end

    -- BNet path: BNet friend lookup, cross-realm, survives char switches
    if transportHint ~= "bnet" then
        ns:Print(ns.COLORS.RED .. "Unknown transport: " .. tostring(transportHint) .. "|r")
        return
    end

    local bnetAccountID, gameAccountID, status, extra = self:FindBNetByCharName(targetCharName)

    if not bnetAccountID then
        if status == "ambiguous" and extra then
            ns:Print(ns.COLORS.RED .. "Multiple BNet friends have a character named \"" .. targetCharName .. "\". Use Name-Realm to be specific:|r")
            for _, qualified in ipairs(extra) do
                ns:Print("  " .. ns.COLORS.CYAN .. qualified .. "|r")
            end
        elseif status == "offline" then
            ns:Print(ns.COLORS.RED .. "No online BNet friend found with a character named \"" .. targetCharName .. "\".|r They must be logged into WoW.")
        else
            ns:Print(ns.COLORS.RED .. "Could not find \"" .. targetCharName .. "\" among your BNet friends.|r Make sure they are on your BNet friends list and online in WoW.")
        end
        return
    end

    -- Already linked to this BNet account? Treat as reconnect.
    local existingUUID = self:FindPartnerByBNet(bnetAccountID)
    if existingUUID then
        partnerStates[existingUUID] = "connected"
        lastPongRecv[existingUUID] = time()
        missedPings[existingUUID] = 0
        self:StartHeartbeat()
        self:RequestFullSyncWith(existingUUID)
        ns:Print(ns.COLORS.GREEN .. "Already linked to this account. Reconnecting...|r")
        return
    end

    -- Pending incoming request from this BNet account?
    for senderGAID, req in pairs(pendingPairRequests) do
        if req.bnetAccountID == bnetAccountID then
            self:AcceptPair(senderGAID)
            return
        end
    end

    local myUUID = ns.db.sync.accountUUID
    local myBNetID = select(2, BNGetInfo()) -- our own bnetAccountID
    local payload = myUUID .. SEP .. tostring(myBNetID or 0)
    self:Enqueue(OP_PAIR .. SEP .. payload, gameAccountID, PRIORITY[OP_PAIR], "bnet")
    local displayName = targetCharName
    if extra and extra.battleTag then
        displayName = extra.battleTag .. " (" .. (extra.charName or "?") .. "-" .. (extra.realmName or "?") .. ")"
    end
    ns:Print(ns.COLORS.CYAN .. "Link request sent to " .. displayName .. "|r")
end

function Sync:OnPairRequest(payload, senderID)
    if not ns.db or not ns.db.sync then return end

    local parts = { strsplit(SEP, payload) }
    local remoteUUID = parts[1]
    local remoteBNetID = tonumber(parts[2])

    -- Detect transport from senderID (whisper arrives as "W:Name-Realm")
    local isWhisper = (type(senderID) == "string" and senderID:sub(1, 2) == "W:")
    local replyTarget, replyTransport = SenderToTarget(senderID)

    -- Resolve sender identity (different paths for whisper vs bnet)
    local senderBNetID, charName, realmName, battleTag
    if isWhisper then
        -- Whisper sender: senderID is "W:Name-Realm"
        local senderName = senderID:sub(3)
        charName = senderName:match("^([^-]+)") or senderName
        realmName = senderName:match("^[^-]+-(.+)$")
    else
        senderBNetID = self:GetBNetAccountFromGameID(senderID)
        if not senderBNetID and remoteBNetID and remoteBNetID > 0 then
            senderBNetID = remoteBNetID
        end
        local gameAccountInfo = C_BattleNet.GetGameAccountInfoByID(senderID)
        if gameAccountInfo then
            charName = gameAccountInfo.characterName or "?"
            realmName = gameAccountInfo.realmName
        else
            charName = "?"
        end
        battleTag = self:GetBattleTagFromGameID(senderID)
    end

    -- If already linked to this account, auto-accept (reconnect)
    if ns.db.sync.partners[remoteUUID] then
        local partner = ns.db.sync.partners[remoteUUID]
        if isWhisper then
            -- Whisper reconnect: the character name may have changed (alt character
            -- on same account). Update the stored charName so replies route correctly.
            partner.transport = "whisper"
            partner.charName = senderID:sub(3)
        else
            if senderBNetID and not partner.bnetAccountID then
                partner.bnetAccountID = senderBNetID
            end
        end
        partnerStates[remoteUUID] = "connected"
        lastPongRecv[remoteUUID] = time()
        missedPings[remoteUUID] = 0
        partner.lastSeen = time()
        -- Send PACK to confirm via same transport
        local myUUID = ns.db.sync.accountUUID
        local myBNetID = select(2, BNGetInfo())
        self:Enqueue(OP_PACK .. SEP .. myUUID .. SEP .. tostring(myBNetID or 0), replyTarget, PRIORITY[OP_PACK], replyTransport)
        self:StartHeartbeat()
        self:RequestFullSyncWith(remoteUUID)
        ns:Print(ns.COLORS.GREEN .. "Sync partner reconnected.|r")
        self:NotifyPartnerStateChanged()
        return
    end

    local displayName = charName or "?"
    if realmName then displayName = displayName .. "-" .. realmName end
    if battleTag then displayName = battleTag .. " (" .. displayName .. ")" end
    if isWhisper then displayName = displayName .. " [whisper]" end

    -- Store pending request
    pendingPairRequests[senderID] = {
        uuid = remoteUUID,
        transport = isWhisper and "whisper" or "bnet",
        bnetAccountID = senderBNetID,
        charName = isWhisper and senderID:sub(3) or charName,
        realmName = realmName,
        battleTag = battleTag,
        displayName = displayName,
    }

    ns:Print(ns.COLORS.CYAN .. displayName .. " wants to link FlipQueue.|r Open Settings > Multi-Account to accept.")

    self:NotifyPartnerStateChanged()
end

function Sync:AcceptPair(senderID)
    if not ns.db or not ns.db.sync then return end

    local req = pendingPairRequests[senderID]
    if not req then return end

    local remoteUUID = req.uuid
    local transport = req.transport or "bnet"

    -- Build a label from the best available identity
    local label = req.displayName or req.battleTag or req.charName or "Linked Account"

    -- For whisper pairs, record which of OUR characters was used to establish
    -- the pair. The pair only functions from that specific character (whisper
    -- addon messages are character-level and same-realm-only).
    local myCharName = nil
    if transport == "whisper" then
        local name = UnitName and UnitName("player") or nil
        local realm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
        if name and realm then
            myCharName = name .. "-" .. realm
        elseif name then
            myCharName = name
        end
    end

    -- Store partner (transport-dependent identity fields)
    ns.db.sync.partners[remoteUUID] = {
        transport = transport,
        bnetAccountID = (transport == "bnet") and req.bnetAccountID or nil,
        charName = (transport == "whisper") and req.charName or nil,
        myCharName = myCharName,
        label = label,
        lastSeen = time(),
        lastFullSync = 0,
        lastRecvSeq = 0,
        pendingDeltas = {},
    }

    pendingPairRequests[senderID] = nil
    partnerStates[remoteUUID] = "connected"
    lastPongRecv[remoteUUID] = time()
    missedPings[remoteUUID] = 0

    -- Send acknowledgment via same transport
    local replyTarget, replyTransport = SenderToTarget(senderID)
    local myUUID = ns.db.sync.accountUUID
    local myBNetID = select(2, BNGetInfo())
    self:Enqueue(OP_PACK .. SEP .. myUUID .. SEP .. tostring(myBNetID or 0), replyTarget, PRIORITY[OP_PACK], replyTransport)

    ns.cw:Toast({ severity = "success", text = "Linked to " .. label })
    self:StartHeartbeat()
    self:NotifyPartnerStateChanged()

    -- Trigger full sync after short delay
    C_Timer.After(1, function()
        self:RequestFullSyncWith(remoteUUID)
    end)
end

function Sync:DenyPair(senderID)
    if senderID then
        local replyTarget, replyTransport = SenderToTarget(senderID)
        self:Enqueue(OP_PDEN, replyTarget, PRIORITY[OP_PDEN], replyTransport)
        local req = pendingPairRequests[senderID]
        ns:Print("Link request from " .. (req and req.displayName or "?") .. " denied.")
        pendingPairRequests[senderID] = nil
    else
        -- Deny all pending requests
        for sid, req in pairs(pendingPairRequests) do
            local replyTarget, replyTransport = SenderToTarget(sid)
            self:Enqueue(OP_PDEN, replyTarget, PRIORITY[OP_PDEN], replyTransport)
            ns:Print("Link request from " .. (req.displayName or req.charName or "?") .. " denied.")
        end
        wipe(pendingPairRequests)
    end
end

function Sync:OnPairAck(payload, senderID)
    if not ns.db or not ns.db.sync then return end

    local parts = { strsplit(SEP, payload) }
    local remoteUUID = parts[1]
    local remoteBNetID = tonumber(parts[2])

    local isWhisper = (type(senderID) == "string" and senderID:sub(1, 2) == "W:")

    -- Resolve identity for display and storage
    local senderBNetID, charName, realmName, battleTag
    if isWhisper then
        local senderName = senderID:sub(3)
        charName = senderName:match("^([^-]+)") or senderName
        realmName = senderName:match("^[^-]+-(.+)$")
    else
        senderBNetID = self:GetBNetAccountFromGameID(senderID)
        if not senderBNetID and remoteBNetID and remoteBNetID > 0 then
            senderBNetID = remoteBNetID
        end
        local gameAccountInfo = C_BattleNet.GetGameAccountInfoByID(senderID)
        if gameAccountInfo then
            charName = gameAccountInfo.characterName or "?"
            realmName = gameAccountInfo.realmName
        else
            charName = "?"
        end
        battleTag = self:GetBattleTagFromGameID(senderID)
    end

    local label = charName or "?"
    if realmName then label = label .. "-" .. realmName end
    if battleTag then label = battleTag .. " (" .. label .. ")" end
    if isWhisper then label = label .. " [whisper]" end

    -- For whisper pairs, record which of OUR characters established the pair.
    local myCharName = nil
    if isWhisper then
        local myName = UnitName and UnitName("player") or nil
        local myRealm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
        if myName and myRealm then
            myCharName = myName .. "-" .. myRealm
        elseif myName then
            myCharName = myName
        end
    end

    -- If already exists, just update
    if ns.db.sync.partners[remoteUUID] then
        local partner = ns.db.sync.partners[remoteUUID]
        if isWhisper then
            partner.transport = "whisper"
            partner.charName = senderID:sub(3)
            if myCharName then partner.myCharName = myCharName end
        elseif senderBNetID then
            partner.bnetAccountID = senderBNetID
        end
        partner.label = label
    else
        ns.db.sync.partners[remoteUUID] = {
            transport = isWhisper and "whisper" or "bnet",
            bnetAccountID = (not isWhisper) and senderBNetID or nil,
            charName = isWhisper and senderID:sub(3) or nil,
            myCharName = myCharName,
            label = label,
            lastSeen = time(),
            lastFullSync = 0,
            lastRecvSeq = 0,
            pendingDeltas = {},
        }
    end

    partnerStates[remoteUUID] = "connected"
    lastPongRecv[remoteUUID] = time()
    missedPings[remoteUUID] = 0
    ns.db.sync.partners[remoteUUID].lastSeen = time()

    ns.cw:Toast({ severity = "success", text = "Linked to " .. label })
    self:StartHeartbeat()
    self:NotifyPartnerStateChanged()

    C_Timer.After(1, function()
        self:RequestFullSyncWith(remoteUUID)
    end)
end

function Sync:OnPairDeny(senderGameAccountID)
    ns:Print(ns.COLORS.RED .. "Link request was denied.|r")
end

function Sync:Unlink(accountUUID)
    if not ns.db or not ns.db.sync then return end

    if not accountUUID then
        -- If no UUID specified and only one partner, unlink that one
        local count = 0
        local onlyUUID
        for uuid in pairs(ns.db.sync.partners) do
            count = count + 1
            onlyUUID = uuid
        end
        if count == 1 then
            accountUUID = onlyUUID
        elseif count == 0 then
            ns:Print("No linked accounts.")
            return
        else
            ns:Print(ns.COLORS.RED .. "Multiple accounts linked. Specify which to unlink.|r")
            return
        end
    end

    local partner = ns.db.sync.partners[accountUUID]
    if not partner then
        ns:Print(ns.COLORS.RED .. "Account not found.|r")
        return
    end

    -- Send UNLK if reachable
    local target, transport = self:ResolveTarget(accountUUID)
    if target then
        self:SendRaw(OP_UNLK, target, transport)
    end

    ns.cw:Toast({ severity = "info", text = "Unlinked from " .. (partner.label or "account") })

    -- Remove characters owned by this account
    for charKey, charData in pairs(ns.db.characters) do
        if charData.accountUUID == accountUUID then
            ns.db.characters[charKey] = nil
        end
    end

    -- Remove partner
    ns.db.sync.partners[accountUUID] = nil
    partnerStates[accountUUID] = nil
    lastPongRecv[accountUUID] = nil
    missedPings[accountUUID] = nil
    fullSyncBuffers[accountUUID] = nil

    -- Stop heartbeat if no more partners
    if not next(ns.db.sync.partners) then
        self:StopHeartbeat()
    end

    self:NotifyPartnerStateChanged()
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
end

function Sync:OnUnlink(senderGameAccountID)
    if not ns.db or not ns.db.sync then return end

    local senderUUID, _ = self:IdentifySender(senderGameAccountID)
    if not senderUUID or not ns.db.sync.partners[senderUUID] then return end

    local label = ns.db.sync.partners[senderUUID].label or "partner"

    -- Remove characters owned by this account
    for charKey, charData in pairs(ns.db.characters) do
        if charData.accountUUID == senderUUID then
            ns.db.characters[charKey] = nil
        end
    end

    ns.db.sync.partners[senderUUID] = nil
    partnerStates[senderUUID] = nil
    lastPongRecv[senderUUID] = nil
    missedPings[senderUUID] = nil
    fullSyncBuffers[senderUUID] = nil

    if not next(ns.db.sync.partners) then
        self:StopHeartbeat()
    end

    ns:Print(ns.COLORS.YELLOW .. label .. " unlinked FlipQueue sync.|r")
    self:NotifyPartnerStateChanged()
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
end

--------------------------
-- Heartbeat
--------------------------

function Sync:StartHeartbeat()
    self:StopHeartbeat()

    heartbeatTicker = C_Timer.NewTicker(HEARTBEAT_INTERVAL, function()
        if not ns.db or not ns.db.sync or not ns.db.sync.partners then return end

        for uuid, partner in pairs(ns.db.sync.partners) do
            local pState = partnerStates[uuid] or "disconnected"
            if pState == "connected" or pState == "syncing" then
                local target, transport = self:ResolveTarget(uuid)
                if target then
                    local pingMsg = OP_PING .. SEP .. (ns.db.sync.accountUUID or "")
                    self:Enqueue(pingMsg, target, PRIORITY[OP_PING], transport)

                    -- Check for timeout
                    local lastPong = lastPongRecv[uuid] or 0
                    if time() - lastPong > HEARTBEAT_TIMEOUT then
                        missedPings[uuid] = (missedPings[uuid] or 0) + 1
                        if missedPings[uuid] >= 3 then
                            partnerStates[uuid] = "disconnected"
                            ns:PrintDebug("Partner " .. (partner.label or uuid) .. " timed out.")
                            self:NotifyPartnerStateChanged()
                        end
                    end
                else
                    -- Can't resolve target (bnet friend went offline, or whisper partner unavailable)
                    -- For bnet we mark as disconnected; for whisper we keep trying since we can't tell
                    if partner.transport ~= "whisper" then
                        partnerStates[uuid] = "disconnected"
                    end
                end
            end
            -- Disconnected partners: just listen, don't ping
        end
    end)
end

function Sync:StopHeartbeat()
    if heartbeatTicker then
        heartbeatTicker:Cancel()
        heartbeatTicker = nil
    end
end

function Sync:OnPing(senderID, payload)
    -- Respond with PONG including our UUID (on the same transport as the incoming ping)
    local replyTarget, replyTransport = SenderToTarget(senderID)
    self:Enqueue(OP_PONG .. SEP .. (ns.db.sync.accountUUID or ""), replyTarget, PRIORITY[OP_PONG], replyTransport)

    -- Extract sender's UUID from payload
    local senderUUID = (payload and payload ~= "") and payload or nil

    if not senderUUID or not ns.db or not ns.db.sync then return end

    local partner = ns.db.sync.partners[senderUUID]
    if not partner then return end

    -- Update bnetAccountID if missing (only relevant for bnet transport)
    if partner.transport ~= "whisper" and not partner.bnetAccountID then
        partner.bnetAccountID = self:GetBNetAccountFromGameID(senderID)
    end

    partner.lastSeen = time()
    lastPongRecv[senderUUID] = time()
    missedPings[senderUUID] = 0

    if partnerStates[senderUUID] == "disconnected" or not partnerStates[senderUUID] then
        partnerStates[senderUUID] = "connected"
        self:Log("PING_RECONNECT", (partner.label or senderUUID) .. " reconnected via ping")
        ns:Print(ns.COLORS.GREEN .. (partner.label or "Partner") .. " reconnected.|r")
        self:StartHeartbeat()

        -- Replay or full sync
        local pending = partner.pendingDeltas or {}
        if #pending > REPLAY_THRESHOLD then
            wipe(pending)
            self:RequestFullSyncWith(senderUUID)
        elseif #pending > 0 then
            self:ReplayPendingDeltas(senderUUID)
            C_Timer.After(2, function()
                self:RequestFullSyncWith(senderUUID)
            end)
        else
            self:RequestFullSyncWith(senderUUID)
        end

        self:NotifyPartnerStateChanged()
    end
end

function Sync:OnPong(senderID, payload)
    local senderUUID = (payload and payload ~= "") and payload or nil
    if not senderUUID or not ns.db or not ns.db.sync then return end

    local partner = ns.db.sync.partners[senderUUID]
    if not partner then return end

    -- Update bnetAccountID if missing (only relevant for bnet transport)
    if partner.transport ~= "whisper" and not partner.bnetAccountID then
        partner.bnetAccountID = self:GetBNetAccountFromGameID(senderID)
    end

    partner.lastSeen = time()
    lastPongRecv[senderUUID] = time()
    missedPings[senderUUID] = 0

    if partnerStates[senderUUID] == "disconnected" or not partnerStates[senderUUID] then
        partnerStates[senderUUID] = "connected"
        self:Log("PONG_RECONNECT", (partner.label or senderUUID) .. " reconnected via pong")
        ns:Print(ns.COLORS.GREEN .. (partner.label or "Partner") .. " reconnected.|r")
        self:StartHeartbeat()
        self:RequestFullSyncWith(senderUUID)
        self:NotifyPartnerStateChanged()
    end
end

--------------------------
-- UI refresh helper
--------------------------

-- Call this whenever partnerStates changes so every widget showing partner
-- status stays in sync. Before this existed, only RefreshSettings was called
-- and the MiniView partner strip would show stale "Offline" until the user
-- manually reopened it.
function Sync:NotifyPartnerStateChanged()
    if not ns.UI then return end
    if ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
    if ns.UI.RefreshMini then ns.UI:RefreshMini() end
    if ns.UI.RefreshToolDrawer then ns.UI:RefreshToolDrawer() end
end

--------------------------
-- BNet Friend Status
--------------------------

function Sync:OnFriendInfoChanged()
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return end

    local hasUnresolvedDisconnected = false

    for uuid, partner in pairs(ns.db.sync.partners) do
        -- Whisper partners don't use BNet friend events; skip
        if partner.transport == "whisper" then
            -- no-op
        elseif partner.bnetAccountID then
            local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
            local pState = partnerStates[uuid] or "disconnected"

            if gameAccountID and pState == "disconnected" then
                -- Partner just came online — auto-reconnect
                partnerStates[uuid] = "connected"
                lastPongRecv[uuid] = time()
                missedPings[uuid] = 0
                partner.lastSeen = time()

                self:Log("FRIEND_ONLINE", (partner.label or uuid) .. " → gameAccountID " .. gameAccountID)
                ns:Print(ns.COLORS.GREEN .. (partner.label or "Partner") .. " came online.|r")
                self:StartHeartbeat()

                -- Replay or full sync
                local pending = partner.pendingDeltas or {}
                if #pending > REPLAY_THRESHOLD then
                    wipe(pending)
                    self:RequestFullSyncWith(uuid)
                elseif #pending > 0 then
                    self:ReplayPendingDeltas(uuid)
                    C_Timer.After(2, function()
                        self:RequestFullSyncWith(uuid)
                    end)
                else
                    self:RequestFullSyncWith(uuid)
                end

                self:NotifyPartnerStateChanged()

            elseif not gameAccountID and (pState == "connected" or pState == "syncing") then
                -- Partner went offline
                partnerStates[uuid] = "disconnected"
                self:Log("FRIEND_OFFLINE", (partner.label or uuid))
                ns:PrintDebug((partner.label or "Partner") .. " went offline.")
                self:NotifyPartnerStateChanged()

            elseif not gameAccountID and pState == "disconnected" then
                -- Still disconnected and can't resolve — may need a retry
                hasUnresolvedDisconnected = true
            end
        end
    end

    -- BN_FRIEND_INFO_CHANGED often fires before game account data is populated.
    -- Schedule a delayed retry to catch partners whose data wasn't ready yet.
    if hasUnresolvedDisconnected then
        if friendRetryTimer then friendRetryTimer:Cancel() end
        friendRetryTimer = C_Timer.NewTimer(5, function()
            friendRetryTimer = nil
            self:Log("FRIEND_RETRY", "Delayed re-check for disconnected partners")
            self:ProbeDisconnectedPartners()
        end)
    end
end

--------------------------
-- Full Sync
--------------------------

function Sync:RequestFullSyncWith(partnerUUID)
    if not ns.db or not ns.db.sync then return end
    local partner = ns.db.sync.partners[partnerUUID]
    if not partner then return end

    local target, transport, chunkSize = self:ResolveTarget(partnerUUID)
    if not target then return end

    partnerStates[partnerUUID] = "syncing"
    self:SendRaw(OP_FSYN, target, transport)
    self:SendFullSyncTo(target, transport, chunkSize)
end

-- Legacy wrapper: request full sync with all partners
function Sync:RequestFullSync()
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return end
    for uuid in pairs(ns.db.sync.partners) do
        self:RequestFullSyncWith(uuid)
    end
end

function Sync:OnFullSyncRequest(senderID)
    if not self:IsLinked() then return end
    local senderUUID = self:IdentifySender(senderID)
    if not senderUUID or not ns.db.sync.partners[senderUUID] then return end
    partnerStates[senderUUID] = "syncing"
    -- Resolve target via partner record so we use the stored transport + chunk size
    local target, transport, chunkSize = self:ResolveTarget(senderUUID)
    if target then
        self:SendFullSyncTo(target, transport, chunkSize)
    end
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
        deletedCharacters = ns.db.deletedCharacters,
    }

    -- Send ALL known characters (not just our own) for gossip relay
    -- Each character is tagged with its accountUUID so the receiver knows ownership
    for charKey, charData in pairs(ns.db.characters or {}) do
        payload.characters[charKey] = charData
        if not charData.accountUUID or charData.accountUUID == ns.db.sync.accountUUID then
            table.insert(payload.ownedCharacters, charKey)
        end
    end

    return payload
end

function Sync:SendFullSyncTo(target, transport, chunkSize)
    if not target then return end
    transport = transport or "bnet"
    chunkSize = chunkSize or CHUNK_SIZE_BNET

    local payload = self:BuildFullSyncPayload()
    local serialized = self:Serialize(payload)

    local totalChunks = math.ceil(#serialized / chunkSize)
    for i = 1, totalChunks do
        local startIdx = (i - 1) * chunkSize + 1
        local endIdx = math.min(i * chunkSize, #serialized)
        local chunk = serialized:sub(startIdx, endIdx)
        local msg = OP_FDAT .. SEP .. i .. SEP .. totalChunks .. SEP .. chunk
        self:Enqueue(msg, target, PRIORITY[OP_FDAT], transport)
    end

    self:Enqueue(OP_FEND, target, PRIORITY[OP_FEND], transport)
end

function Sync:OnFullSyncData(payload, senderGameAccountID)
    -- Reject data from non-partners
    local senderUUID = self:IdentifySender(senderGameAccountID)
    if not senderUUID or not (ns.db and ns.db.sync and ns.db.sync.partners and ns.db.sync.partners[senderUUID]) then
        return
    end

    local sepPos1 = payload:find(SEP, 1, true)
    if not sepPos1 then return end
    local sepPos2 = payload:find(SEP, sepPos1 + 1, true)
    if not sepPos2 then return end

    local chunkIdx = tonumber(payload:sub(1, sepPos1 - 1))
    local totalChunks = tonumber(payload:sub(sepPos1 + 1, sepPos2 - 1))
    local data = payload:sub(sepPos2 + 1)

    if not chunkIdx or not totalChunks then return end

    local bufferKey = senderUUID

    if not fullSyncBuffers[bufferKey] then
        fullSyncBuffers[bufferKey] = { expected = totalChunks, chunks = {} }
    end
    fullSyncBuffers[bufferKey].expected = totalChunks
    fullSyncBuffers[bufferKey].chunks[chunkIdx] = data
end

function Sync:OnFullSyncEnd(senderGameAccountID)
    -- Reject from non-partners
    local senderUUID = self:IdentifySender(senderGameAccountID)
    if not senderUUID or not (ns.db and ns.db.sync and ns.db.sync.partners and ns.db.sync.partners[senderUUID]) then
        return
    end
    local bufferKey = senderUUID

    local buffer = fullSyncBuffers[bufferKey]
    if not buffer or not buffer.expected then return end

    -- Reassemble
    local complete = true
    for i = 1, buffer.expected do
        if not buffer.chunks[i] then
            complete = false
            break
        end
    end

    if not complete then
        ns:PrintDebug("Full sync incomplete — missing chunks")
        fullSyncBuffers[bufferKey] = nil
        return
    end

    local serialized = ""
    for i = 1, buffer.expected do
        serialized = serialized .. buffer.chunks[i]
    end
    fullSyncBuffers[bufferKey] = nil

    local remoteData = self:Deserialize(serialized)
    if not remoteData or type(remoteData) ~= "table" then
        ns:PrintDebug("Full sync: deserialization failed")
        return
    end

    self:MergeFullSync(remoteData)

    if senderUUID then
        partnerStates[senderUUID] = "connected"
        if ns.db.sync.partners[senderUUID] then
            ns.db.sync.partners[senderUUID].lastFullSync = time()
        end
    end

    local charCount = 0
    if remoteData.characters then
        for _ in pairs(remoteData.characters) do charCount = charCount + 1 end
    end
    self:Log("FULL_SYNC_DONE", "from " .. (senderUUID or "?") .. " | " .. charCount .. " chars received")
    ns:Print(ns.COLORS.GREEN .. "Sync complete.|r")

    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
    if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    self:NotifyPartnerStateChanged()
end

--------------------------
-- Merge Algorithms
--------------------------

function Sync:MergeFullSync(remote)
    if not ns.db or not remote then return end

    self._applying = true

    -- Merge tombstones before characters so MergeCharacters can honor them.
    self:MergeDeletedCharacters(remote.deletedCharacters)
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

    local myUUID = ns.db.sync.accountUUID

    for charKey, charData in pairs(remoteChars) do
        local charOwner = charData.accountUUID or remoteUUID
        -- Don't overwrite characters we own, and don't resurrect characters
        -- we've tombstoned — even if the partner still has them, our delete
        -- is authoritative until the user explicitly restores.
        if charOwner ~= myUUID and not ns:IsCharDeleted(charKey) then
            ns.db.characters[charKey] = charData
            -- Synced characters bring item names the name -> itemID index
            -- hasn't seen (FQ-223). The index memoizes on first use, which can
            -- easily happen before BNet sync delivers the partner account.
            ns:InvalidateInventoryNameIndex()
        end
    end
end

-- Tombstones are union-merged: a delete from either side wins and we keep
-- the earliest deletedAt timestamp. Restoring is explicit (user clicks
-- Restore in either client); there's no "un-delete" implicit in a remote
-- entry being absent, since a partner running an older version wouldn't
-- send the table at all.
function Sync:MergeDeletedCharacters(remoteDeleted)
    if not remoteDeleted then return end
    ns.db.deletedCharacters = ns.db.deletedCharacters or {}
    for charKey, entry in pairs(remoteDeleted) do
        if type(entry) == "table" then
            local local_ = ns.db.deletedCharacters[charKey]
            if not local_ then
                ns.db.deletedCharacters[charKey] = {
                    deletedAt = entry.deletedAt or time(),
                    syndicatorPurged = entry.syndicatorPurged and true or false,
                    accountUUID = entry.accountUUID,
                }
                -- Drop the live row if the partner's delete reaches us
                -- before we'd purged it locally.
                if ns.db.characters then
                    ns.db.characters[charKey] = nil
                end
            elseif (entry.deletedAt or 0) < (local_.deletedAt or 0) then
                local_.deletedAt = entry.deletedAt
            end
        end
    end
end

function Sync:MergeWarbank(remoteWarbank)
    if not remoteWarbank then return end

    local localScan = ns.db.warbank and ns.db.warbank.lastScan or 0
    local remoteScan = remoteWarbank.lastScan or 0

    if remoteScan > localScan then
        ns.db.warbank = remoteWarbank
        ns:InvalidateInventoryNameIndex()
    end
end

function Sync:MergeTodoLists(remoteTodo)
    if not remoteTodo then return end

    if remoteTodo.active and remoteTodo.active.tasks then
        if not ns.db.todoLists.active then
            ns.db.todoLists.active = remoteTodo.active
        else
            self:MergeTasks(ns.db.todoLists.active.tasks, remoteTodo.active.tasks)
        end
    end

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
                local localTask = localTasks[localIdx]
                local localTS = localTask._syncMeta and localTask._syncMeta.lastModifiedAt or 0
                local remoteTS = remoteTask._syncMeta and remoteTask._syncMeta.lastModifiedAt or 0
                if remoteTS > localTS then
                    localTasks[localIdx] = remoteTask
                elseif remoteTS == localTS then
                    local localBy = localTask._syncMeta and localTask._syncMeta.lastModifiedBy or ""
                    local remoteBy = remoteTask._syncMeta and remoteTask._syncMeta.lastModifiedBy or ""
                    if remoteBy > localBy then
                        localTasks[localIdx] = remoteTask
                    end
                end
            else
                table.insert(localTasks, remoteTask)
                localByUUID[remoteTask.taskUUID] = #localTasks
            end
        end
    end
end

function Sync:MergeLog(remoteLog)
    if not remoteLog then return end

    local seen = {}
    for _, entry in ipairs(ns.db.log or {}) do
        local key = (entry.itemKey or "") .. "|" .. (entry.charKey or "") .. "|" .. (entry.postedAt or 0)
        seen[key] = true
    end

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

    -- Fan out to ALL partners
    for uuid, partner in pairs(ns.db.sync.partners) do
        partner.pendingDeltas = partner.pendingDeltas or {}
        local pState = partnerStates[uuid] or "disconnected"

        if pState == "connected" or pState == "syncing" then
            local target, transport, chunkSize = self:ResolveTarget(uuid)
            if target then
                self:SendMessage(OP_DELT, delta, target, transport, chunkSize)
                partner.pendingDeltas[#partner.pendingDeltas + 1] = {
                    seq = seq, sentAt = time(), retries = 0, delta = delta,
                }
            else
                -- Can't reach them — queue for later
                table.insert(partner.pendingDeltas, {
                    seq = seq, sentAt = 0, retries = 0, delta = delta,
                })
            end
        else
            -- Offline — queue for later delivery
            table.insert(partner.pendingDeltas, {
                seq = seq, sentAt = 0, retries = 0, delta = delta,
            })
        end

        -- Enforce per-partner cap
        while #partner.pendingDeltas > MAX_PENDING_DELTAS do
            table.remove(partner.pendingDeltas, 1)
        end
    end
end

function Sync:OnDelta(payload, senderID)
    if not ns.db or not ns.db.sync then return end

    local senderUUID = self:IdentifySender(senderID)
    if not senderUUID or not ns.db.sync.partners[senderUUID] then return end

    local delta = self:Deserialize(payload)
    if not delta or type(delta) ~= "table" then return end

    -- Send ACK on the same transport as the incoming delta
    local ackPayload = tostring(delta.seq or 0)
    local replyTarget, replyTransport = SenderToTarget(senderID)
    self:Enqueue(OP_DACK .. SEP .. ackPayload, replyTarget, PRIORITY[OP_DACK], replyTransport)

    -- Deduplicate against this partner's lastRecvSeq
    local partner = ns.db.sync.partners[senderUUID]
    if delta.seq and delta.seq <= (partner.lastRecvSeq or 0) then
        return -- already seen
    end
    if delta.seq then
        partner.lastRecvSeq = delta.seq
    end

    self:ApplyDelta(delta)
end

function Sync:ApplyDelta(delta)
    if not delta or not delta.type then return end

    self._applying = true

    local deltaType = delta.type
    local data = delta.data

    if deltaType == "CHAR" then
        if data and data.charKey and data.charData then
            -- Honor local tombstones: a resurrecting CHAR from the partner
            -- should be dropped on the floor, not applied.
            if not ns:IsCharDeleted(data.charKey) then
                data.charData.accountUUID = delta.accountUUID
                ns.db.characters[data.charKey] = data.charData
                ns:InvalidateInventoryNameIndex()
            end
        end
    elseif deltaType == "CDEL" then
        -- Partner deleted a character. Add the tombstone and drop the live
        -- row; skip any further action (they already emitted this for us).
        if data and data.charKey then
            ns.db.deletedCharacters = ns.db.deletedCharacters or {}
            local t = data.tombstone or {}
            ns.db.deletedCharacters[data.charKey] = {
                deletedAt = t.deletedAt or delta.ts or time(),
                syndicatorPurged = t.syndicatorPurged and true or false,
                accountUUID = t.accountUUID,
            }
            if ns.db.characters then
                ns.db.characters[data.charKey] = nil
            end
        end
    elseif deltaType == "CUND" then
        -- Partner restored a character. Clear the tombstone locally; the
        -- live character row will reappear on next Syndicator projection
        -- or full sync from whichever client owns the char.
        if data and data.charKey and ns.db.deletedCharacters then
            ns.db.deletedCharacters[data.charKey] = nil
        end
    elseif deltaType == "WB" then
        if data then
            local localScan = ns.db.warbank and ns.db.warbank.lastScan or 0
            local remoteScan = data.lastScan or 0
            if remoteScan > localScan then
                ns.db.warbank = data
                ns:InvalidateInventoryNameIndex()
            end
        end
    elseif deltaType == "CMETA" then
        if data and data.charKey then
            local charData = ns.db.characters[data.charKey]
            if charData then
                if data.gold then charData.gold = data.gold end
                if data.lastLogin then charData.lastLogin = data.lastLogin end
                if data.level then charData.level = data.level end
            end
        end
    elseif deltaType == "TDCOMMIT" then
        if data and data.mode and data.list then
            if ns.TodoList and ns.TodoList.CommitList then
                ns.TodoList:CommitList(data.list, data.mode)
            end
        end
    elseif deltaType == "TDSTATUS" then
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

function Sync:OnDeltaAck(payload, senderGameAccountID)
    local seq = tonumber(payload)
    if not seq then return end

    local senderUUID = self:IdentifySender(senderGameAccountID)
    if not senderUUID then return end

    local partner = ns.db and ns.db.sync and ns.db.sync.partners and ns.db.sync.partners[senderUUID]
    if not partner or not partner.pendingDeltas then return end

    for i = #partner.pendingDeltas, 1, -1 do
        if partner.pendingDeltas[i].seq == seq then
            table.remove(partner.pendingDeltas, i)
            break
        end
    end
end

function Sync:RetryUnacked()
    if not self:IsLinked() then return end

    local now = time()
    for uuid, partner in pairs(ns.db.sync.partners) do
        local pState = partnerStates[uuid] or "disconnected"
        if pState ~= "connected" and pState ~= "syncing" then
            -- Skip offline partners (their deltas stay queued)
        elseif partner.pendingDeltas then
            local target, transport, chunkSize = self:ResolveTarget(uuid)
            if target then
                for i = #partner.pendingDeltas, 1, -1 do
                    local entry = partner.pendingDeltas[i]
                    if entry.sentAt > 0 and (now - entry.sentAt) > RETRY_INTERVAL then
                        if entry.retries >= MAX_RETRIES then
                            table.remove(partner.pendingDeltas, i)
                        else
                            entry.retries = entry.retries + 1
                            entry.sentAt = now
                            self:SendMessage(OP_DELT, entry.delta, target, transport, chunkSize)
                        end
                    end
                end
            end
        end
    end
end

function Sync:ReplayPendingDeltas(partnerUUID)
    if not ns.db or not ns.db.sync then return end
    local partner = ns.db.sync.partners[partnerUUID]
    if not partner or not partner.pendingDeltas or #partner.pendingDeltas == 0 then return end

    local target, transport, chunkSize = self:ResolveTarget(partnerUUID)
    if not target then return end

    ns:PrintDebug("Replaying " .. #partner.pendingDeltas .. " queued changes to " .. (partner.label or partnerUUID))
    for _, entry in ipairs(partner.pendingDeltas) do
        entry.sentAt = time()
        entry.retries = 0
        self:SendMessage(OP_DELT, entry.delta, target, transport, chunkSize)
    end
end

--------------------------
-- Public API
--------------------------

function Sync:IsLinked()
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return false end
    return next(ns.db.sync.partners) ~= nil
end

function Sync:IsConnected()
    if not self:IsLinked() then return false end
    for uuid in pairs(ns.db.sync.partners) do
        if partnerStates[uuid] == "connected" or partnerStates[uuid] == "syncing" then
            return true
        end
    end
    return false
end

function Sync:GetState()
    -- Return aggregate state: connected if any partner is connected
    if self:IsConnected() then return "connected" end
    if self:IsLinked() then return "disconnected" end
    return "disconnected"
end

function Sync:GetPartners()
    if ns.db and ns.db.sync then
        return ns.db.sync.partners or {}
    end
    return {}
end

function Sync:GetPartnerState(uuid)
    return partnerStates[uuid] or "disconnected"
end

function Sync:GetPartnerLabel(uuid)
    local partner = ns.db and ns.db.sync and ns.db.sync.partners and ns.db.sync.partners[uuid]
    return partner and partner.label or "Unknown"
end

function Sync:SetPartnerLabel(uuid, label)
    if ns.db and ns.db.sync and ns.db.sync.partners and ns.db.sync.partners[uuid] then
        ns.db.sync.partners[uuid].label = label
    end
end

-- Unlink a specific partner by UUID. Sends UNLK if reachable, then wipes local state.
function Sync:UnlinkByUUID(accountUUID)
    if not accountUUID then return end
    self:Unlink(accountUUID)
end

-- Force a full resync with a specific partner by UUID. No-op if the partner can't be reached.
function Sync:ForceSyncByUUID(accountUUID)
    if not accountUUID then return end
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return end
    local partner = ns.db.sync.partners[accountUUID]
    if not partner then return end
    local target = self:ResolveTarget(accountUUID)
    if not target then
        ns:Print(ns.COLORS.RED .. (partner.label or "Partner") .. " is not currently reachable.|r")
        return
    end
    self:RequestFullSyncWith(accountUUID)
    ns:Print(ns.COLORS.CYAN .. "Full resync requested with " .. (partner.label or "partner") .. ".|r")
end

function Sync:GetPendingCount(partnerUUID)
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return 0 end
    if partnerUUID then
        local partner = ns.db.sync.partners[partnerUUID]
        return partner and partner.pendingDeltas and #partner.pendingDeltas or 0
    end
    -- Total across all partners
    local total = 0
    for _, partner in pairs(ns.db.sync.partners) do
        total = total + (partner.pendingDeltas and #partner.pendingDeltas or 0)
    end
    return total
end

function Sync:HasPendingPairRequest()
    return next(pendingPairRequests) ~= nil
end

function Sync:GetPendingPairRequests()
    return pendingPairRequests
end

-- Legacy compat: return first pending request sender
function Sync:GetPendingPairFrom()
    for gaid, req in pairs(pendingPairRequests) do
        return req.displayName or req.charName or "?", gaid
    end
    return nil
end

function Sync:GenerateUUID()
    return string.format("%x%x", time(), math.random(0, 0xFFFFFF))
end
