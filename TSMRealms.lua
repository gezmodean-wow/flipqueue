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

-- TSM_AppHelper's AppData.lua fires its TSM_APPHELPER_LOAD_DATA calls the
-- moment that addon loads, which can be before OR after FlipQueue depending
-- on WoW's load order resolution. We need our hook in place either way.
--
-- Two cases:
--   A. TSM has already defined TSM_APPHELPER_LOAD_DATA and AppData hasn't
--      fired yet (FlipQueue loads after TSM but before TSM_AppHelper).
--      We chain on top so each call is captured then forwarded.
--   B. AppData has already fired (TSM_AppHelper loaded before us). The
--      original calls are gone, but the data still lives on disk in
--      TradeSkillMaster_AppHelper/AppData.lua. We can't replay them, so
--      this case is a permanent miss for per-realm pricing — TSM itself
--      retains only current+alt realm and discards the rest. Document the
--      gap so /fq debug realms can report it.
--
-- TSM intentionally drops realm-data for any realm beyond the configured
-- "auctionDBAltRealm" (see LibTSMApp/Source/Service/AppHelper.lua), so
-- without this hook the user gets no per-realm DealFinder pricing for any
-- realm except their login realm.
local hookInstalled = false
if TSM_APPHELPER_LOAD_DATA then
    local originalFn = TSM_APPHELPER_LOAD_DATA
    TSM_APPHELPER_LOAD_DATA = function(tag, realmOrRegion, dataStr)
        OnLoadData(tag, realmOrRegion, dataStr)
        return originalFn(tag, realmOrRegion, dataStr)
    end
    hookInstalled = true
else
    -- TSM hasn't loaded yet. Predefine the global as a buffering stub so
    -- AppData.lua's calls are captured. When TSM later overwrites the
    -- global (during TSM's own module load), our stub is replaced — but
    -- by then we've already buffered everything.
    --
    -- A trampoline wraps TSM's later definition: we re-detect it on the
    -- next event cycle and chain on top.
    TSM_APPHELPER_LOAD_DATA = function(tag, realmOrRegion, dataStr)
        OnLoadData(tag, realmOrRegion, dataStr)
        -- No upstream to forward to yet; TSM's real handler will be
        -- installed shortly and re-receive nothing if we don't replay.
        -- Replay is impossible (we only get the data once), so the
        -- current-realm data is lost from TSM's perspective. Mitigation:
        -- TSM also reads from TradeSkillMaster_AppHelperDB on its own
        -- modules' load, separate from AppData.lua, so this only affects
        -- realms TSM would have ignored anyway.
    end
    hookInstalled = true
end

ns._tsmRealmsHookInstalled = hookInstalled

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function(self, event)
    -- If TSM defined its own TSM_APPHELPER_LOAD_DATA after our pre-emptive
    -- stub, chain it now so any post-login calls (rare) still flow through.
    if TSM_APPHELPER_LOAD_DATA and not _G._fqTSMRealmsChained then
        local originalFn = TSM_APPHELPER_LOAD_DATA
        TSM_APPHELPER_LOAD_DATA = function(tag, realmOrRegion, dataStr)
            OnLoadData(tag, realmOrRegion, dataStr)
            return originalFn(tag, realmOrRegion, dataStr)
        end
        _G._fqTSMRealmsChained = true
    end
    ProcessPendingData()
    if isLoaded and #realmList > 0 then
        ns:PrintDebug("TSMRealms: loaded pricing for " .. #realmList .. " realms")
    else
        ns:PrintDebug("TSMRealms: no per-realm pricing captured. " ..
            "TSM_AppHelper may have loaded before FlipQueue — DealFinder " ..
            "will fall back to region-wide TSM data.")
    end
    self:UnregisterAllEvents()
end)

--------------------------
-- Level-form conversion
--------------------------

-- TSM's per-realm AuctionDB stores variant items keyed by the LEVEL FORM
-- ("i:itemID::iLEVEL"), not the bonus-filtered form ("i:itemID::1:6652")
-- that TSM_API.ToItemString produces. The two are different canonical
-- representations: bonus form is TSM's item-identity form, level form is
-- the AuctionDB-storage form keyed solely on the resolved item level.
--
-- Without this conversion, every bonus-decorated lookup misses every realm
-- and DealFinder falls back to region-wide pricing, producing identical
-- prices across realms for variant gear.
--
-- Cache to avoid repeated GetDetailedItemLevelInfo calls.
local levelFormCache = {}

local function ToLevelForm(tsmItemStr)
    if not tsmItemStr then return nil end
    if levelFormCache[tsmItemStr] then return levelFormCache[tsmItemStr] end

    -- Already a level form: i:NNNN::iLEVEL
    if tsmItemStr:match("^i:%d+::i%d+$") then
        levelFormCache[tsmItemStr] = tsmItemStr
        return tsmItemStr
    end
    -- Base form (no bonus IDs, no modifiers): no conversion needed.
    if tsmItemStr:match("^i:%d+$") then
        levelFormCache[tsmItemStr] = tsmItemStr
        return tsmItemStr
    end

    -- Bonus form: extract the rest after "i:NNNN::" and rebuild as a WoW
    -- item string so GetDetailedItemLevelInfo can compute the actual ilvl.
    local baseID = tsmItemStr:match("^i:(%d+)")
    if not baseID then return nil end
    local rest = tsmItemStr:match("^i:%d+::?(.*)$") or ""
    if rest == "" then return nil end

    -- Build "item:NNNN:::::::::::::numBonus:b1:b2:..." (12 empty fields
    -- between itemID and numBonusIDs — matches Core.lua's ItemKeyToItemString
    -- format that TSM_API.ToItemString accepts).
    local wowStr = "item:" .. baseID .. string.rep(":", 12) .. rest

    if not GetDetailedItemLevelInfo then return nil end
    local ok, ilvl = pcall(GetDetailedItemLevelInfo, wowStr)
    if ok and ilvl and ilvl > 0 then
        local levelStr = "i:" .. baseID .. "::i" .. ilvl
        levelFormCache[tsmItemStr] = levelStr
        return levelStr
    end
    return nil
end

--------------------------
-- On-demand item lookup
--------------------------

-- Search a realm's raw item-data string for a specific item. Tries the given
-- form, then the level form, then (for variant gear) the nearest recorded
-- item level, then the base item — see the resolution ladder documented on
-- GetBatchPricing.
-- Returns decoded field values plus the match source, or nil.
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
    local source = otherData and "exact" or nil

    local baseID = tsmItemStr:match("^i:(%d+)")
    local wantIlvl, matchedIlvl
    if not otherData then
        -- Try the level form before giving up.
        local levelStr = ToLevelForm(tsmItemStr)
        if levelStr and levelStr ~= tsmItemStr then
            wantIlvl = tonumber(levelStr:match("::i(%d+)$"))
            local escapedLevel = levelStr:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
            otherData = rawEntry.str:match('{"' .. escapedLevel .. '",([^}]+)}')
            if otherData then source = "exact" end
        end
    end
    if not otherData and baseID then
        -- Nearest recorded item level for this base item. TSM's per-realm
        -- AuctionDB records whatever ilvl each scanner's client reported, so
        -- one item routinely occupies several level-form keys and our single
        -- computed ilvl need not be among them.
        local bestDelta
        for ilvlStr, values in rawEntry.str:gmatch('{"i:' .. baseID .. '::i(%d+)",([^}]+)}') do
            local ilvl = tonumber(ilvlStr)
            if ilvl then
                local delta = wantIlvl and math.abs(ilvl - wantIlvl) or 0
                if not bestDelta or delta < bestDelta then
                    bestDelta = delta
                    otherData = values
                    matchedIlvl = ilvl
                end
            end
        end
        if otherData then source = "nearestIlvl" end
    end
    if not otherData and baseID then
        -- Base item. Coarser than the variant, but it is this realm's own
        -- pricing rather than a region-wide average across every realm.
        otherData = rawEntry.str:match("{" .. baseID .. ",([^}]+)}")
        if otherData then source = "baseItem" end
    end
    if not otherData then return nil end

    -- Decode the values
    local parts = { strsplit(",", otherData) }
    local result = {}
    for i = 1, #parts do
        result[i] = DecodeValue(parts[i])
    end
    return result, source, matchedIlvl
end

--------------------------
-- Public API
--------------------------

function TSMRealms:IsLoaded()
    return isLoaded and next(realmRaw) ~= nil
end

-- Public accessor for the level-form converter so /fq debug pricing can
-- display what variant key we'd use for AuctionDB matching alongside the
-- bonus-form input. Returns nil if conversion isn't possible.
function TSMRealms:ToLevelForm(tsmItemStr)
    return ToLevelForm(tsmItemStr)
end

function TSMRealms:GetRealmList()
    return realmList
end

-- Every distinct item level this base item is recorded under, across all
-- captured realms, sorted ascending. Diagnostic support for /fq debug
-- pricing: our derived level form is a single guess, and TSM's data can hold
-- many buckets for one item, so a lookup miss needs to be readable as "wrong
-- bucket" rather than "no data". Returns an empty table when the item is
-- stored by plain ID only.
function TSMRealms:GetRecordedItemLevels(baseID)
    local seen, out = {}, {}
    if not isLoaded or not baseID then return out end
    for _, realm in ipairs(realmList) do
        local rawEntry = realmRaw[realm]
        if rawEntry and rawEntry.str then
            for ilvlStr in rawEntry.str:gmatch('{"i:' .. baseID .. '::i(%d+)"') do
                local ilvl = tonumber(ilvlStr)
                if ilvl and not seen[ilvl] then
                    seen[ilvl] = true
                    out[#out + 1] = ilvl
                end
            end
        end
    end
    table.sort(out)
    return out
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
        local values, source, matchedIlvl = FindItemInRaw(rawEntry, itemString)
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
                    source = source,
                    matchedIlvl = matchedIlvl,
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

-- Collect every unique numeric itemID referenced in any realm's raw
-- pricing data. Used by the Transform page's Warm Cache button to
-- proactively warm WoW's client item cache for all items currently on
-- any tracked realm's auction house — the union typically covers the
-- overwhelming majority of "pasted from an expert" PBS file entries,
-- since those lists are sourced from live AH activity.
--
-- Returns a map { [numericID] = true }. Iterating via `for id in pairs`
-- is stable since Lua guarantees key enumeration for integer keys.
-- Skips pet entries ("p:speciesID") — those don't need cache warming
-- and are resolved via the pet-name map instead.
function TSMRealms:CollectAllItemIDs()
    local seen = {}
    if not isLoaded then return seen end
    for _, realm in ipairs(realmList) do
        local rawEntry = realmRaw[realm]
        if rawEntry and rawEntry.str then
            -- Plain numeric entries: {NNNN,val,val,...}
            for id in rawEntry.str:gmatch("{(%d+),") do
                local n = tonumber(id)
                if n and n > 0 then seen[n] = true end
            end
            -- Quoted bonus-keyed entries: {"i:NNNN::K:b1:b2:...",val,...}
            for id in rawEntry.str:gmatch('{"i:(%d+)') do
                local n = tonumber(id)
                if n and n > 0 then seen[n] = true end
            end
        end
    end
    return seen
end

--------------------------
-- Batch Lookup (single pass per realm)
--------------------------

-- For a list of TSM item strings, return per-item-per-realm pricing in a single
-- pass over each realm's raw data. The previous per-item API does an O(N)
-- string.match for *every* item × realm combination, which scales as
--   items × realms × stringSize  (gigabytes of byte comparisons for typical
--   Deal Finder pools — that's the source of the Deal Finder lockup).
-- This batch path collapses that to
--   realms × stringSize  (one gmatch walk per realm, with a hash-set lookup
--   at every item match).
--
-- Returns: { [tsmItemString] = { [realmName] = { minBuyout, numAuctions,
--             marketValueRecent, updateTime, source } } }
--
-- `source` records which rung of the resolution ladder produced the price:
-- "exact" (the variant we asked for), "nearestIlvl" (another recorded item
-- level of the same item) or "baseItem" (the base item's own listings).
--
-- The ladder exists because TSM's per-realm AuctionDB stores variant gear
-- ONLY in level form ("i:258955::i171") — there is not a single bonus-form
-- key in the dataset. Worse, the item level TSM records is whatever the
-- scanning client reported, and the auction house reports item levels SCALED
-- TO THE VIEWING CHARACTER, so one item routinely occupies many level-form
-- keys (item 258955 appears at ilvl 133/139/152/158/165/171/192/198/220 on a
-- single realm; 45% of gear items carry more than one). Our locally computed
-- ilvl is therefore one guess against up to nine buckets, and a miss used to
-- drop the item all the way to the region-wide average on EVERY realm —
-- which is exactly the "same price on all realms" report in FQ-230.
-- Measured on a live 40-realm AppData: every gear item that appears in level
-- form also has a plain base-item entry, so rung 3 always has something.
function TSMRealms:GetBatchPricing(itemStrings)
    local result = {}
    if not isLoaded or not itemStrings or #itemStrings == 0 then return result end

    -- Lookup sets: numeric IDs (for "i:NNNN" plain items), the full quoted
    -- form (for items with bonus/modifier tails like "i:225575::2:1663:2293"),
    -- and — for variant gear — the base item ID, which drives the nearest-ilvl
    -- and base-item rungs of the ladder below.
    local wantedIDs = {}             -- numericID string -> tsmItemString
    local wantedQuoted = {}          -- exact/level form -> caller's input string
    local wantedBase = {}            -- baseID string -> array of caller input strings
    local variantBase = {}           -- caller input string -> baseID string
    local targetIlvl = {}            -- caller input string -> ilvl we computed
    local anyVariant = false
    local emptyResult = {}           -- shared empty default for items with no hits
    for _, str in ipairs(itemStrings) do
        if str then
            local id = str:match("^i:(%d+)$")
            if id then
                wantedIDs[id] = str
            else
                wantedQuoted[str] = str
                local levelStr = ToLevelForm(str)
                if levelStr and levelStr ~= str then
                    wantedQuoted[levelStr] = str
                    targetIlvl[str] = tonumber(levelStr:match("::i(%d+)$"))
                end
                -- Pets ("p:1965") have no base ID here by design — they are
                -- matched only in exact form, exactly as before.
                local baseID = str:match("^i:(%d+)")
                if baseID and not variantBase[str] then
                    variantBase[str] = baseID
                    local list = wantedBase[baseID]
                    if not list then
                        list = {}
                        wantedBase[baseID] = list
                    end
                    list[#list + 1] = str
                    anyVariant = true
                end
            end
            result[str] = nil  -- placeholder so callers can distinguish
        end
    end

    for _, realm in ipairs(realmList) do
        local rawEntry = realmRaw[realm]
        if rawEntry and rawEntry.str then
            local fl = rawEntry.fieldLookup
            local fMin = fl.minBuyout
            local fNum = fl.numAuctions
            local fRecent = fl.marketValueRecent
            local downloadTime = rawEntry.downloadTime

            -- Decode just the values we care about (minBuyout, numAuctions,
            -- marketValueRecent). Avoid the cost of decoding every column.
            -- Returns nil when the entry carries no usable price.
            local function Decode(valuesPart)
                local parts = { strsplit(",", valuesPart) }
                local minBuyout   = fMin and parts[fMin] and DecodeValue(parts[fMin]) or nil
                local numAuctions = fNum and parts[fNum] and DecodeValue(parts[fNum]) or nil
                local recent      = fRecent and parts[fRecent] and DecodeValue(parts[fRecent]) or nil
                if (minBuyout and minBuyout > 0) or (recent and recent > 0) then
                    return minBuyout, numAuctions, recent
                end
                return nil
            end

            -- Per-realm accumulators for the fallback rungs. Only the exact
            -- rung writes straight through; the others need the whole realm
            -- walked before the best candidate is known.
            local lvlMin, lvlNum, lvlRecent, lvlDelta, lvlAt = {}, {}, {}, {}, {}
            local baseMin, baseNum, baseRecent = {}, {}, {}

            -- Walk every item entry in the realm string exactly once.
            -- Format is `{itemPart,values}` where itemPart is either a numeric
            -- itemID or a quoted "itemString". Values are comma-separated
            -- base-32 encoded numbers; brace nesting doesn't occur in values.
            for itemPart, valuesPart in rawEntry.str:gmatch("{([^,]+),([^}]+)}") do
                if itemPart:sub(1, 1) == '"' then
                    -- Quoted item string variant. wantedQuoted maps both the
                    -- bonus form and the level form back to the caller's key.
                    local stripped = itemPart:sub(2, -2)
                    local key = wantedQuoted[stripped]
                    if key then
                        local minBuyout, numAuctions, recent = Decode(valuesPart)
                        if minBuyout or recent then
                            local entry = result[key]
                            if not entry then
                                entry = {}
                                result[key] = entry
                            end
                            entry[realm] = {
                                minBuyout = (minBuyout and minBuyout > 0) and minBuyout or nil,
                                numAuctions = (numAuctions and numAuctions > 0) and numAuctions or nil,
                                marketValueRecent = (recent and recent > 0) and recent or nil,
                                updateTime = downloadTime,
                                source = "exact",
                            }
                        end
                    elseif anyVariant then
                        -- Not the exact key we computed, but possibly another
                        -- recorded item level of an item we want.
                        local bid, ilvlStr = stripped:match("^i:(%d+)::i(%d+)$")
                        local wanters = bid and wantedBase[bid]
                        if wanters then
                            local ilvl = tonumber(ilvlStr)
                            local minBuyout, numAuctions, recent = Decode(valuesPart)
                            if ilvl and (minBuyout or recent) then
                                for i = 1, #wanters do
                                    local k = wanters[i]
                                    local want = targetIlvl[k]
                                    local delta = want and math.abs(ilvl - want) or 0
                                    if lvlDelta[k] == nil or delta < lvlDelta[k] then
                                        lvlDelta[k] = delta
                                        lvlMin[k] = minBuyout
                                        lvlNum[k] = numAuctions
                                        lvlRecent[k] = recent
                                        lvlAt[k] = ilvl
                                    end
                                end
                            end
                        end
                    end
                else
                    -- Plain numeric ID: serves both plain inputs (exact) and
                    -- variant inputs (base-item fallback).
                    local key = wantedIDs[itemPart]
                    local wanters = anyVariant and wantedBase[itemPart] or nil
                    if key or wanters then
                        local minBuyout, numAuctions, recent = Decode(valuesPart)
                        if minBuyout or recent then
                            if key then
                                local entry = result[key]
                                if not entry then
                                    entry = {}
                                    result[key] = entry
                                end
                                entry[realm] = {
                                    minBuyout = (minBuyout and minBuyout > 0) and minBuyout or nil,
                                    numAuctions = (numAuctions and numAuctions > 0) and numAuctions or nil,
                                    marketValueRecent = (recent and recent > 0) and recent or nil,
                                    updateTime = downloadTime,
                                    source = "exact",
                                }
                            end
                            if wanters then
                                baseMin[itemPart] = minBuyout
                                baseNum[itemPart] = numAuctions
                                baseRecent[itemPart] = recent
                            end
                        end
                    end
                end
            end

            -- Resolution ladder for variant gear on this realm, best first:
            --   1. exact      — already written above
            --   2. nearestIlvl — another recorded item level of the same item
            --   3. baseItem    — the base item's own listings on this realm
            -- Anything still unresolved falls to DealFinder's region-wide
            -- average, which is what made every realm show one price.
            for key, baseID in pairs(variantBase) do
                local entry = result[key]
                if not (entry and entry[realm]) then
                    local minBuyout, numAuctions, recent, source, matchedIlvl
                    if lvlDelta[key] ~= nil then
                        minBuyout, numAuctions, recent = lvlMin[key], lvlNum[key], lvlRecent[key]
                        source = "nearestIlvl"
                        matchedIlvl = lvlAt[key]
                    elseif baseMin[baseID] ~= nil or baseRecent[baseID] ~= nil then
                        minBuyout, numAuctions, recent = baseMin[baseID], baseNum[baseID], baseRecent[baseID]
                        source = "baseItem"
                    end
                    if source then
                        if not entry then
                            entry = {}
                            result[key] = entry
                        end
                        entry[realm] = {
                            minBuyout = (minBuyout and minBuyout > 0) and minBuyout or nil,
                            numAuctions = (numAuctions and numAuctions > 0) and numAuctions or nil,
                            marketValueRecent = (recent and recent > 0) and recent or nil,
                            updateTime = downloadTime,
                            source = source,
                            matchedIlvl = matchedIlvl,
                        }
                    end
                end
            end
        end
    end

    -- Fill in empty tables for items that had no hits anywhere, so callers
    -- get a deterministic shape.
    for _, str in ipairs(itemStrings) do
        if str and result[str] == nil then result[str] = emptyResult end
    end

    return result
end
