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
local CHUNK_SIZE = 3900     -- BNSendGameData supports ~4078 bytes; leave headroom
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
local sendQueue = {}           -- { {msg, gameAccountID, priority}, ... }
local reassembly = {}          -- chunk reassembly buffers
local fullSyncBuffers = {}     -- [accountUUID] = { chunks = {}, expected = N }
local heartbeatTicker = nil
local retryTicker = nil
local sendTicker = nil
local lastPongRecv = {}        -- [accountUUID] = timestamp
local missedPings = {}         -- [accountUUID] = count
local pendingPairRequests = {} -- [senderGameAccountID] = { uuid, bnetAccountID, charName }

--------------------------
-- Init
--------------------------

function Sync:Init()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("BN_CHAT_MSG_ADDON")
    frame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "BN_CHAT_MSG_ADDON" then
            local prefix, message, _, senderID = ...
            if prefix == PREFIX and message then
                self:OnBNetMessage(message, senderID)
            end
        elseif event == "BN_FRIEND_INFO_CHANGED" then
            self:OnFriendInfoChanged()
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
end

-- Send a probe ping to all stored partners to see who's online
function Sync:ProbePartners()
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return end
    for uuid, partner in pairs(ns.db.sync.partners) do
        if partner.bnetAccountID then
            local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
            if gameAccountID then
                local pingMsg = OP_PING .. SEP .. (ns.db.sync.accountUUID or "")
                self:Enqueue(pingMsg, gameAccountID, PRIORITY[OP_PING])
            end
        end
    end
end

--------------------------
-- BNet Lookup
--------------------------

-- Find a BNet friend by character name. Returns bnetAccountID, gameAccountID or nil.
function Sync:FindBNetByCharName(charName)
    -- Normalize: strip realm if provided for matching
    local nameOnly = charName:match("^([^-]+)") or charName
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo then
            local numGameAccounts = C_BattleNet.GetFriendNumGameAccounts(i)
            for j = 1, numGameAccounts do
                local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameInfo and gameInfo.characterName then
                    if gameInfo.characterName == nameOnly or gameInfo.characterName == charName then
                        return accountInfo.bnetAccountID, gameInfo.gameAccountID
                    end
                end
            end
        end
    end
    return nil, nil
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

-- Find which partner UUID sent a message (by gameAccountID → bnetAccountID → uuid)
function Sync:IdentifySender(senderGameAccountID)
    local bnetAccountID = self:GetBNetAccountFromGameID(senderGameAccountID)
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
function Sync:SendMessage(opcode, payload, gameAccountID)
    if not gameAccountID then return end

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
        self:Enqueue(fullMsg, gameAccountID, PRIORITY[opcode] or 5)
    else
        msgCounter = msgCounter + 1
        local msgID = msgCounter
        local totalChunks = math.ceil(msgLen / CHUNK_SIZE)

        for i = 1, totalChunks do
            local startIdx = (i - 1) * CHUNK_SIZE + 1
            local endIdx = math.min(i * CHUNK_SIZE, msgLen)
            local chunk = "C" .. SEP .. msgID .. SEP .. i .. SEP .. totalChunks .. SEP .. fullMsg:sub(startIdx, endIdx)
            self:Enqueue(chunk, gameAccountID, PRIORITY[opcode] or 5)
        end
    end
end

-- Send a simple opcode-only message (no payload)
function Sync:SendRaw(opcode, gameAccountID)
    if not gameAccountID then return end
    self:Enqueue(opcode, gameAccountID, PRIORITY[opcode] or 5)
end

--------------------------
-- Send Queue
--------------------------

function Sync:Enqueue(msg, gameAccountID, priority)
    priority = priority or 5
    local entry = { msg = msg, gameAccountID = gameAccountID, priority = priority }
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

    local ok, err = pcall(BNSendGameData, entry.gameAccountID, PREFIX, entry.msg)
    if not ok then
        ns:PrintDebug("Sync send failed: " .. tostring(err))
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

function Sync:RequestPair(targetCharName)
    if not ns.db or not ns.db.sync then return end

    -- Look up BNet friend by character name
    local bnetAccountID, gameAccountID = self:FindBNetByCharName(targetCharName)
    if not bnetAccountID or not gameAccountID then
        ns:Print(ns.COLORS.RED .. "Could not find " .. targetCharName .. " in your BNet friends list.|r Make sure they're online and on your friends list.")
        return
    end

    -- Check if already linked to this BNet account
    local existingUUID = self:FindPartnerByBNet(bnetAccountID)
    if existingUUID then
        -- Already paired — treat as reconnect attempt
        partnerStates[existingUUID] = "connected"
        lastPongRecv[existingUUID] = time()
        missedPings[existingUUID] = 0
        self:StartHeartbeat()
        self:RequestFullSyncWith(existingUUID)
        ns:Print(ns.COLORS.GREEN .. "Already linked to this account. Reconnecting...|r")
        return
    end

    -- Check if there's a pending incoming request from this BNet account
    for senderGAID, req in pairs(pendingPairRequests) do
        if req.bnetAccountID == bnetAccountID then
            self:AcceptPair(senderGAID)
            return
        end
    end

    local myUUID = ns.db.sync.accountUUID
    local myBNetID = select(2, BNGetInfo()) -- our own bnetAccountID
    local payload = myUUID .. SEP .. tostring(myBNetID or 0)
    self:Enqueue(OP_PAIR .. SEP .. payload, gameAccountID, PRIORITY[OP_PAIR])
    ns:Print(ns.COLORS.CYAN .. "Link request sent to " .. targetCharName .. "|r")
end

function Sync:OnPairRequest(payload, senderGameAccountID)
    if not ns.db or not ns.db.sync then return end

    local parts = { strsplit(SEP, payload) }
    local remoteUUID = parts[1]
    local remoteBNetID = tonumber(parts[2])

    -- Also resolve sender's bnetAccountID from the game session
    local senderBNetID = self:GetBNetAccountFromGameID(senderGameAccountID)
    if not senderBNetID and remoteBNetID and remoteBNetID > 0 then
        senderBNetID = remoteBNetID
    end

    -- If already linked to this account, auto-accept (reconnect)
    if ns.db.sync.partners[remoteUUID] then
        -- Update their bnetAccountID if we didn't have it
        if senderBNetID and not ns.db.sync.partners[remoteUUID].bnetAccountID then
            ns.db.sync.partners[remoteUUID].bnetAccountID = senderBNetID
        end
        partnerStates[remoteUUID] = "connected"
        lastPongRecv[remoteUUID] = time()
        missedPings[remoteUUID] = 0
        ns.db.sync.partners[remoteUUID].lastSeen = time()
        -- Send PACK to confirm
        local myUUID = ns.db.sync.accountUUID
        local myBNetID = select(2, BNGetInfo())
        self:Enqueue(OP_PACK .. SEP .. myUUID .. SEP .. tostring(myBNetID or 0), senderGameAccountID, PRIORITY[OP_PACK])
        self:StartHeartbeat()
        self:RequestFullSyncWith(remoteUUID)
        ns:Print(ns.COLORS.GREEN .. "Sync partner reconnected.|r")
        if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
        return
    end

    -- Get sender's character name for display
    local charName = "?"
    local gameAccountInfo = C_BattleNet.GetGameAccountInfoByID(senderGameAccountID)
    if gameAccountInfo then
        charName = gameAccountInfo.characterName or "?"
    end

    -- Store pending request
    pendingPairRequests[senderGameAccountID] = {
        uuid = remoteUUID,
        bnetAccountID = senderBNetID,
        charName = charName,
    }

    ns:Print(ns.COLORS.CYAN .. charName .. " wants to link FlipQueue.|r Open Settings > Multi-Account to accept.")

    if ns.UI and ns.UI.RefreshSettings then
        ns.UI:RefreshSettings()
    end
end

function Sync:AcceptPair(senderGameAccountID)
    if not ns.db or not ns.db.sync then return end

    local req = pendingPairRequests[senderGameAccountID]
    if not req then return end

    local remoteUUID = req.uuid
    local remoteBNetID = req.bnetAccountID

    -- Store partner
    ns.db.sync.partners[remoteUUID] = {
        bnetAccountID = remoteBNetID,
        label = "Linked Account",
        lastSeen = time(),
        lastFullSync = 0,
        lastRecvSeq = 0,
        pendingDeltas = {},
    }

    pendingPairRequests[senderGameAccountID] = nil
    partnerStates[remoteUUID] = "connected"
    lastPongRecv[remoteUUID] = time()
    missedPings[remoteUUID] = 0

    -- Send acknowledgment
    local myUUID = ns.db.sync.accountUUID
    local myBNetID = select(2, BNGetInfo())
    self:Enqueue(OP_PACK .. SEP .. myUUID .. SEP .. tostring(myBNetID or 0), senderGameAccountID, PRIORITY[OP_PACK])

    ns:Print(ns.COLORS.GREEN .. "Linked to " .. (req.charName or "partner") .. "|r")
    self:StartHeartbeat()
    if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end

    -- Trigger full sync after short delay
    C_Timer.After(1, function()
        self:RequestFullSyncWith(remoteUUID)
    end)
end

function Sync:DenyPair(senderGameAccountID)
    if senderGameAccountID then
        self:Enqueue(OP_PDEN, senderGameAccountID, PRIORITY[OP_PDEN])
        local req = pendingPairRequests[senderGameAccountID]
        ns:Print("Link request from " .. (req and req.charName or "?") .. " denied.")
        pendingPairRequests[senderGameAccountID] = nil
    else
        -- Deny all pending requests
        for gaid, req in pairs(pendingPairRequests) do
            self:Enqueue(OP_PDEN, gaid, PRIORITY[OP_PDEN])
            ns:Print("Link request from " .. (req.charName or "?") .. " denied.")
        end
        wipe(pendingPairRequests)
    end
end

function Sync:OnPairAck(payload, senderGameAccountID)
    if not ns.db or not ns.db.sync then return end

    local parts = { strsplit(SEP, payload) }
    local remoteUUID = parts[1]
    local remoteBNetID = tonumber(parts[2])

    -- Also resolve from game session
    local senderBNetID = self:GetBNetAccountFromGameID(senderGameAccountID)
    if not senderBNetID and remoteBNetID and remoteBNetID > 0 then
        senderBNetID = remoteBNetID
    end

    -- If already exists, just update
    if ns.db.sync.partners[remoteUUID] then
        if senderBNetID then
            ns.db.sync.partners[remoteUUID].bnetAccountID = senderBNetID
        end
    else
        ns.db.sync.partners[remoteUUID] = {
            bnetAccountID = senderBNetID,
            label = "Linked Account",
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

    ns:Print(ns.COLORS.GREEN .. "Linked successfully.|r")
    self:StartHeartbeat()
    if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end

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

    -- Send UNLK if online
    if partner.bnetAccountID then
        local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
        if gameAccountID then
            self:SendRaw(OP_UNLK, gameAccountID)
        end
    end

    ns:Print("Unlinked from " .. (partner.label or "account"))

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

    if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
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
    if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
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
                -- Send PING
                if partner.bnetAccountID then
                    local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
                    if gameAccountID then
                        local pingMsg = OP_PING .. SEP .. (ns.db.sync.accountUUID or "")
                        self:Enqueue(pingMsg, gameAccountID, PRIORITY[OP_PING])

                        -- Check for timeout
                        local lastPong = lastPongRecv[uuid] or 0
                        if time() - lastPong > HEARTBEAT_TIMEOUT then
                            missedPings[uuid] = (missedPings[uuid] or 0) + 1
                            if missedPings[uuid] >= 3 then
                                partnerStates[uuid] = "disconnected"
                                ns:PrintDebug("Partner " .. (partner.label or uuid) .. " timed out.")
                                if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
                            end
                        end
                    else
                        -- Can't find gameAccountID — they went offline
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

function Sync:OnPing(senderGameAccountID, payload)
    -- Respond with PONG including our UUID
    self:Enqueue(OP_PONG .. SEP .. (ns.db.sync.accountUUID or ""), senderGameAccountID, PRIORITY[OP_PONG])

    -- Extract sender's UUID from payload
    local senderUUID = (payload and payload ~= "") and payload or nil

    if not senderUUID or not ns.db or not ns.db.sync then return end

    local partner = ns.db.sync.partners[senderUUID]
    if not partner then return end

    -- Update bnetAccountID if missing
    if not partner.bnetAccountID then
        partner.bnetAccountID = self:GetBNetAccountFromGameID(senderGameAccountID)
    end

    partner.lastSeen = time()
    lastPongRecv[senderUUID] = time()
    missedPings[senderUUID] = 0

    if partnerStates[senderUUID] == "disconnected" or not partnerStates[senderUUID] then
        partnerStates[senderUUID] = "connected"
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

        if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
    end
end

function Sync:OnPong(senderGameAccountID, payload)
    local senderUUID = (payload and payload ~= "") and payload or nil
    if not senderUUID or not ns.db or not ns.db.sync then return end

    local partner = ns.db.sync.partners[senderUUID]
    if not partner then return end

    -- Update bnetAccountID if missing
    if not partner.bnetAccountID then
        partner.bnetAccountID = self:GetBNetAccountFromGameID(senderGameAccountID)
    end

    partner.lastSeen = time()
    lastPongRecv[senderUUID] = time()
    missedPings[senderUUID] = 0

    if partnerStates[senderUUID] == "disconnected" or not partnerStates[senderUUID] then
        partnerStates[senderUUID] = "connected"
        ns:Print(ns.COLORS.GREEN .. (partner.label or "Partner") .. " reconnected.|r")
        self:StartHeartbeat()
        self:RequestFullSyncWith(senderUUID)
        if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
    end
end

--------------------------
-- BNet Friend Status
--------------------------

function Sync:OnFriendInfoChanged()
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return end

    for uuid, partner in pairs(ns.db.sync.partners) do
        if partner.bnetAccountID then
            local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
            local pState = partnerStates[uuid] or "disconnected"

            if gameAccountID and pState == "disconnected" then
                -- Partner just came online — auto-reconnect
                partnerStates[uuid] = "connected"
                lastPongRecv[uuid] = time()
                missedPings[uuid] = 0
                partner.lastSeen = time()

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

                if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end

            elseif not gameAccountID and (pState == "connected" or pState == "syncing") then
                -- Partner went offline
                partnerStates[uuid] = "disconnected"
                ns:PrintDebug((partner.label or "Partner") .. " went offline.")
                if ns.UI and ns.UI.RefreshSettings then ns.UI:RefreshSettings() end
            end
        end
    end
end

--------------------------
-- Full Sync
--------------------------

function Sync:RequestFullSyncWith(partnerUUID)
    if not ns.db or not ns.db.sync then return end
    local partner = ns.db.sync.partners[partnerUUID]
    if not partner or not partner.bnetAccountID then return end

    local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
    if not gameAccountID then return end

    partnerStates[partnerUUID] = "syncing"
    self:SendRaw(OP_FSYN, gameAccountID)
    self:SendFullSyncTo(gameAccountID)
end

-- Legacy wrapper: request full sync with all partners
function Sync:RequestFullSync()
    if not ns.db or not ns.db.sync or not ns.db.sync.partners then return end
    for uuid in pairs(ns.db.sync.partners) do
        self:RequestFullSyncWith(uuid)
    end
end

function Sync:OnFullSyncRequest(senderGameAccountID)
    if not self:IsLinked() then return end
    local senderUUID = self:IdentifySender(senderGameAccountID)
    if senderUUID then
        partnerStates[senderUUID] = "syncing"
    end
    self:SendFullSyncTo(senderGameAccountID)
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

function Sync:SendFullSyncTo(gameAccountID)
    if not gameAccountID then return end

    local payload = self:BuildFullSyncPayload()
    local serialized = self:Serialize(payload)

    local totalChunks = math.ceil(#serialized / CHUNK_SIZE)
    for i = 1, totalChunks do
        local startIdx = (i - 1) * CHUNK_SIZE + 1
        local endIdx = math.min(i * CHUNK_SIZE, #serialized)
        local chunk = serialized:sub(startIdx, endIdx)
        local msg = OP_FDAT .. SEP .. i .. SEP .. totalChunks .. SEP .. chunk
        self:Enqueue(msg, gameAccountID, PRIORITY[OP_FDAT])
    end

    self:Enqueue(OP_FEND, gameAccountID, PRIORITY[OP_FEND])
end

function Sync:OnFullSyncData(payload, senderGameAccountID)
    local sepPos1 = payload:find(SEP, 1, true)
    if not sepPos1 then return end
    local sepPos2 = payload:find(SEP, sepPos1 + 1, true)
    if not sepPos2 then return end

    local chunkIdx = tonumber(payload:sub(1, sepPos1 - 1))
    local totalChunks = tonumber(payload:sub(sepPos1 + 1, sepPos2 - 1))
    local data = payload:sub(sepPos2 + 1)

    if not chunkIdx or not totalChunks then return end

    -- Buffer per sender
    local senderUUID = self:IdentifySender(senderGameAccountID)
    local bufferKey = senderUUID or tostring(senderGameAccountID)

    if not fullSyncBuffers[bufferKey] then
        fullSyncBuffers[bufferKey] = { expected = totalChunks, chunks = {} }
    end
    fullSyncBuffers[bufferKey].expected = totalChunks
    fullSyncBuffers[bufferKey].chunks[chunkIdx] = data
end

function Sync:OnFullSyncEnd(senderGameAccountID)
    local senderUUID = self:IdentifySender(senderGameAccountID)
    local bufferKey = senderUUID or tostring(senderGameAccountID)

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

    local myUUID = ns.db.sync.accountUUID

    for charKey, charData in pairs(remoteChars) do
        local charOwner = charData.accountUUID or remoteUUID
        -- Don't overwrite characters we own
        if charOwner ~= myUUID then
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

        if (pState == "connected" or pState == "syncing") and partner.bnetAccountID then
            local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
            if gameAccountID then
                self:SendMessage(OP_DELT, delta, gameAccountID)
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

function Sync:OnDelta(payload, senderGameAccountID)
    if not ns.db or not ns.db.sync then return end

    local senderUUID = self:IdentifySender(senderGameAccountID)
    if not senderUUID or not ns.db.sync.partners[senderUUID] then return end

    local delta = self:Deserialize(payload)
    if not delta or type(delta) ~= "table" then return end

    -- Send ACK
    local ackPayload = tostring(delta.seq or 0)
    self:Enqueue(OP_DACK .. SEP .. ackPayload, senderGameAccountID, PRIORITY[OP_DACK])

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
            data.charData.accountUUID = delta.accountUUID
            ns.db.characters[data.charKey] = data.charData
        end
    elseif deltaType == "WB" then
        if data then
            local localScan = ns.db.warbank and ns.db.warbank.lastScan or 0
            local remoteScan = data.lastScan or 0
            if remoteScan > localScan then
                ns.db.warbank = data
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
        elseif partner.pendingDeltas and partner.bnetAccountID then
            local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
            if gameAccountID then
                for i = #partner.pendingDeltas, 1, -1 do
                    local entry = partner.pendingDeltas[i]
                    if entry.sentAt > 0 and (now - entry.sentAt) > RETRY_INTERVAL then
                        if entry.retries >= MAX_RETRIES then
                            table.remove(partner.pendingDeltas, i)
                        else
                            entry.retries = entry.retries + 1
                            entry.sentAt = now
                            self:SendMessage(OP_DELT, entry.delta, gameAccountID)
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
    if not partner.bnetAccountID then return end

    local gameAccountID = self:GetGameAccountID(partner.bnetAccountID)
    if not gameAccountID then return end

    ns:PrintDebug("Replaying " .. #partner.pendingDeltas .. " queued changes to " .. (partner.label or partnerUUID))
    for _, entry in ipairs(partner.pendingDeltas) do
        entry.sentAt = time()
        entry.retries = 0
        self:SendMessage(OP_DELT, entry.delta, gameAccountID)
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
        return req.charName or "?", gaid
    end
    return nil
end

function Sync:GenerateUUID()
    return string.format("%x%x", time(), math.random(0, 0xFFFFFF))
end
