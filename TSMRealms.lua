-- TSMRealms.lua
-- Reads per-realm AuctionDB pricing data from TSM's AppData.
-- TSM downloads hourly pricing for every realm you have characters on,
-- but TSM_API only exposes the current realm. This module captures the
-- raw data strings and searches them on demand — no upfront parsing of
-- individual items, keeping memory usage minimal.
local addonName, ns = ...

local TSMRealms = {}
ns.TSMRealms = TSMRealms

--------------------------
-- State
--------------------------

-- Per-realm raw data: realmRaw[realmName] = { str, fieldLookup, downloadTime }
-- The str is the item-data portion of the AppData string (not parsed into items).
local realmRaw = {}
local realmList = {}         -- sorted array of realm names
local isLoaded = false

-- Small per-item result cache: cache[itemString] = { [realmName] = {values}, ts }
local queryCache = {}
local QUERY_CACHE_TTL = 60   -- seconds

--------------------------
-- Base-32 Decoding
-- (matches TSM's private.UnpackData encoding)
--------------------------

local function DecodeValue(val)
    if not val or val == "" then return 0 end
    if #val > 6 then
        local lo = tonumber(val:sub(-6), 32) or 0
        local hi = tonumber(val:sub(1, -7), 32) or 0
        return lo + hi * (2 ^ 30)
    else
        return tonumber(val, 32) or 0
    end
end

--------------------------
-- Hook: capture raw data
--------------------------

local pendingData = {}

local function OnLoadData(tag, realmOrRegion, dataStr)
    -- Only per-realm non-commodity data (has minBuyout, numAuctions, marketValueRecent)
    if tag ~= "AUCTIONDB_NON_COMMODITY_DATA" then return end
    if realmOrRegion == "US" or realmOrRegion == "EU" or realmOrRegion == "Global" then
        return
    end
    table.insert(pendingData, { realm = realmOrRegion, data = dataStr })
end

local function ProcessPendingData()
    for _, entry in ipairs(pendingData) do
        local dataStr = entry.data
        -- Extract metadata and item-data portion
        local metaEnd, dataStart = dataStr:find(",data={")
        if metaEnd then
            local metaStr = dataStr:sub(1, metaEnd - 1) .. "}"
            local metaFn = loadstring(metaStr)
            if metaFn then
                local ok, metadata = pcall(metaFn)
                if ok and metadata then
                    -- Build field index (skip "itemString" at position 1)
                    local fieldLookup = {}
                    for i = 2, #metadata.fields do
                        fieldLookup[metadata.fields[i]] = i - 1
                    end
                    -- Store only the item-data substring and metadata — NOT parsed items
                    local itemStr = dataStr:sub(dataStart + 1, -3)
                    local realm = entry.realm
                    if not realmRaw[realm] then
                        table.insert(realmList, realm)
                    end
                    realmRaw[realm] = {
                        str = itemStr,
                        fieldLookup = fieldLookup,
                        downloadTime = metadata.downloadTime,
                    }
                end
            end
        end
    end
    table.sort(realmList)
    wipe(pendingData)
    isLoaded = true
end

-- ==========================================
-- HOOK INSTALLATION (at file load time)
-- ==========================================

if TSM_APPHELPER_LOAD_DATA then
    local originalFn = TSM_APPHELPER_LOAD_DATA
    TSM_APPHELPER_LOAD_DATA = function(tag, realmOrRegion, dataStr)
        OnLoadData(tag, realmOrRegion, dataStr)
        return originalFn(tag, realmOrRegion, dataStr)
    end
end

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function(self, event)
    ProcessPendingData()
    if isLoaded and #realmList > 0 then
        ns:PrintDebug("TSMRealms: loaded pricing for " .. #realmList .. " realms")
    end
    self:UnregisterAllEvents()
end)

--------------------------
-- On-demand item lookup
--------------------------

-- Search a realm's raw item-data string for a specific item.
-- Returns decoded field values or nil.
local function FindItemInRaw(rawEntry, tsmItemStr)
    if not rawEntry or not rawEntry.str then return nil end

    -- Items stored as: {itemID,val1,val2,...} or {"i:itemID::...",val1,val2,...}
    -- Try numeric ID first (most items)
    local numID = tsmItemStr:match("^i:(%d+)$")

    local otherData
    if numID then
        -- Fast path: search for {numericID,
        otherData = rawEntry.str:match("{" .. numID .. ",([^}]+)}")
    end
    if not otherData then
        -- Quoted item string: {"i:12345::2:1663:2293",val,...}
        local escaped = tsmItemStr:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
        otherData = rawEntry.str:match('{"' .. escaped .. '",([^}]+)}')
    end
    if not otherData then return nil end

    -- Decode the values
    local parts = { strsplit(",", otherData) }
    local result = {}
    for i = 1, #parts do
        result[i] = DecodeValue(parts[i])
    end
    return result
end

--------------------------
-- Public API
--------------------------

function TSMRealms:IsLoaded()
    return isLoaded and next(realmRaw) ~= nil
end

function TSMRealms:GetRealmList()
    return realmList
end

function TSMRealms:GetRealmUpdateTime(realmName)
    local r = realmRaw[realmName]
    return r and r.downloadTime
end

-- Get all pricing for an item across all realms.
-- Returns: { realmName = { minBuyout, numAuctions, marketValueRecent, updateTime } }
function TSMRealms:GetAllRealmPricing(itemString)
    if not isLoaded then return {} end

    -- Check cache
    local cached = queryCache[itemString]
    if cached and (time() - cached.ts) < QUERY_CACHE_TTL then
        return cached.result
    end

    local result = {}
    for _, realm in ipairs(realmList) do
        local rawEntry = realmRaw[realm]
        local values = FindItemInRaw(rawEntry, itemString)
        if values then
            local fl = rawEntry.fieldLookup
            local minBuyout = fl.minBuyout and values[fl.minBuyout]
            local numAuctions = fl.numAuctions and values[fl.numAuctions]
            local recent = fl.marketValueRecent and values[fl.marketValueRecent]

            if (minBuyout and minBuyout > 0) or (recent and recent > 0) then
                result[realm] = {
                    minBuyout = (minBuyout and minBuyout > 0) and minBuyout or nil,
                    numAuctions = (numAuctions and numAuctions > 0) and numAuctions or nil,
                    marketValueRecent = (recent and recent > 0) and recent or nil,
                    updateTime = rawEntry.downloadTime,
                }
            end
        end
    end

    -- Cache the result
    queryCache[itemString] = { result = result, ts = time() }
    return result
end

function TSMRealms:InvalidateCache()
    wipe(queryCache)
end
