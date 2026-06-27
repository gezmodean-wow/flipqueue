-- TSM.lua
-- TradeSkillMaster integration: price lookups, operations reading, key conversion
local addonName, ns = ...

local TSM = {}
ns.TSM = TSM

--------------------------
-- State
--------------------------

local isAvailable       -- cached availability (nil = not checked yet)
local priceCache = {}   -- "fqKey|source" -> {value = copper_or_nil, ts = time()}
local keyCache = {}     -- fqKey -> tsmString
local opCache = {}      -- fqKey -> {minPrice, maxPrice, normalPrice, opName, ts}
local CACHE_TTL = 60    -- seconds
local OP_CACHE_TTL = 300 -- 5 min for operations (they rarely change mid-session)

-- TSM version we last audited our posting logic against. If TSM bumps to a
-- newer version, we still work — everything we read (operation settings,
-- price-expression evaluation via TSM_API.GetCustomPriceValue, group lookup)
-- is supported public-ish surface area that changes rarely. But the decision
-- tree in AuctionPost:ResolvePostPrice mirrors TSM's internal
-- AuctioningOperation.MakePostDecision in:
--   LibTSMSystem/Source/Operation/AuctioningOperation.lua
-- If TSM reworks that function (new settings keys, new branches, renamed
-- fields) our implementation will silently drift. TSM:CheckAuditedVersion
-- compares the running TSM version to this constant and surfaces a one-time
-- warning when a new-enough TSM is detected, so someone (human or agent)
-- knows to re-read MakePostDecision and update the local tree.
--
-- When bumping this constant:
--   1. Read the current MakePostDecision in TSM's source.
--   2. Compare every branch against AuctionPost:ResolvePostPrice.
--   3. Check the :AddCustomStringSetting / :AddStringSetting list in
--      AuctioningOperation.Load for new fields we'd need in
--      GetItemAuctioningOp.
--   4. Update the comment in ResolvePostPrice with the audit date.
--
-- Audited 2026-06-27 against TSM v4.14.69: MakePostDecision (lines 417-512)
-- and IsAuctionFiltered (269-285) are unchanged from v4.14.66 — identical line
-- numbers and branch structure, no new required operation fields in Load. The
-- local port in AuctionPost:ResolvePostPrice remains accurate (FQ-215).
local TSM_AUDITED_VERSION = "v4.14.69"

-- Fields we expect every Auctioning operation record to expose. If TSM
-- renames one, GetItemAuctioningOp returns nil for it and ResolvePostPrice
-- reports "no TSM data" — which is a safer failure than posting at a wrong
-- price. The structural check below surfaces the mismatch to the player.
local EXPECTED_OP_FIELDS = {
    -- Required price expression slots and core branch enums. If any of
    -- these are nil the decision tree can't function, so a missing-field
    -- warning is genuinely useful.
    "minPrice", "maxPrice", "normalPrice",
    "undercut", "priceReset", "aboveMax",
    "postCap", "duration",
}
-- Optional behaviour fields. TSM omits these from saved-vars when set to
-- their defaults, so warning about them produces noise on every default
-- op. ResolvePostPrice / IsAuctionFiltered all treat nil as the safe
-- default (no filter, no override) so missing values are non-fatal.

--------------------------
-- Availability
--------------------------

function TSM:IsAvailable()
    if isAvailable ~= nil then return isAvailable end
    isAvailable = type(TSM_API) == "table"
        and type(TSM_API.GetCustomPriceValue) == "function"
        and type(TSM_API.ToItemString) == "function"
    return isAvailable
end

function TSM:IsEnabled()
    return self:IsAvailable() and ns.db and ns.db.settings.tsmEnabled
end

--------------------------
-- Audit Drift Detection
--------------------------

-- Parse a TSM-style version string ("v4.14.66" or "4.14.66") into a numeric
-- tuple. Returns {major, minor, patch} or nil if the string doesn't look
-- like a dotted version.
local function ParseVersion(v)
    if type(v) ~= "string" then return nil end
    v = v:gsub("^v", "")
    local major, minor, patch = v:match("^(%d+)%.(%d+)%.(%d+)")
    if not major then return nil end
    return { tonumber(major), tonumber(minor), tonumber(patch) }
end

-- Compare two parsed version tuples. Returns -1/0/1 for a < b / a == b / a > b.
local function CompareVersions(a, b)
    for i = 1, 3 do
        if a[i] ~= b[i] then
            return a[i] < b[i] and -1 or 1
        end
    end
    return 0
end

-- Read the loaded TSM addon's version via the standard addon metadata API.
function TSM:GetLoadedVersion()
    if not self:IsAvailable() then return nil end
    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if not getMeta then return nil end
    local ok, ver = pcall(getMeta, "TradeSkillMaster", "Version")
    return ok and ver or nil
end

-- The TSM version our posting logic was last audited against. Exposed so the
-- diagnostics blob can report the audited-vs-running delta (FQ-215).
function TSM:GetAuditedVersion()
    return TSM_AUDITED_VERSION
end

-- Returns "ok" | "ahead" | "behind" | "unknown" comparing the running TSM
-- version to what our posting logic was last audited against.
function TSM:GetAuditStatus()
    local running = ParseVersion(self:GetLoadedVersion())
    local audited = ParseVersion(TSM_AUDITED_VERSION)
    if not running or not audited then return "unknown" end
    local cmp = CompareVersions(running, audited)
    if cmp == 0 then return "ok" end
    if cmp > 0 then return "ahead" end
    return "behind"
end

-- One-time session warning when TSM has moved past our audited version or
-- when a new operation field has been added that we don't yet read.
-- Structural check runs against the first real Auctioning operation we see;
-- if TSM renamed minPrice/maxPrice/etc, GetItemAuctioningOp returns nil for
-- that field and we point the player at where to look.
local _auditWarned = false
function TSM:CheckAuditedVersion(opSettings)
    if _auditWarned then return end
    if not self:IsAvailable() then return end

    local status = self:GetAuditStatus()
    local running = self:GetLoadedVersion() or "?"
    if status == "ahead" then
        ns:Print(ns.COLORS.YELLOW .. "[FlipQueue] TSM " .. running ..
            " is newer than the version FlipQueue's posting logic was audited against (" ..
            TSM_AUDITED_VERSION .. "). Posts should still work, but the TSM " ..
            "decision tree may have changed. If prices look off, report it — " ..
            "FlipQueue's ResolvePostPrice mirrors TSM's MakePostDecision.|r")
        _auditWarned = true
    end

    if opSettings and type(opSettings) == "table" then
        local missing = {}
        for _, field in ipairs(EXPECTED_OP_FIELDS) do
            if opSettings[field] == nil then
                missing[#missing + 1] = field
            end
        end
        if #missing > 0 and not _auditWarned then
            ns:Print(ns.COLORS.YELLOW .. "[FlipQueue] TSM Auctioning operation " ..
                "is missing field(s) we expect: " .. table.concat(missing, ", ") ..
                ". The schema may have changed in TSM " .. running ..
                ". Post prices may default to fallbacks.|r")
            _auditWarned = true
        end
    end
end

--------------------------
-- Key Conversion
--------------------------

function TSM:ItemKeyToTSMString(fqKey)
    if not fqKey or fqKey == "" then return nil end
    if keyCache[fqKey] then return keyCache[fqKey] end

    -- Battle pet: "pet:speciesID" -> "p:speciesID"
    local petID = fqKey:match("^pet:(%d+)")
    if petID then
        local result = "p:" .. petID
        keyCache[fqKey] = result
        return result
    end

    -- Preferred path: build a WoW item string (via Core.lua, which handles
    -- bonuses AND modifiers) and let TSM canonicalize it. TSM's ToItemString
    -- applies its own bonus-ID filter + modifier sort, so variants like
    -- ilvl-85 and ilvl-87 produce distinct strings — which is the whole
    -- point: without modifiers in the string, TSM returns the base item's
    -- dbmarket/minPrice for every variant and our decision tree evaluates
    -- against the wrong reference.
    if TSM_API and type(TSM_API.ToItemString) == "function" and ns.ItemKeyToItemString then
        local wowStr = ns:ItemKeyToItemString(fqKey)
        if wowStr then
            local ok, tsmStr = pcall(TSM_API.ToItemString, wowStr)
            if ok and type(tsmStr) == "string" and tsmStr ~= "" then
                keyCache[fqKey] = tsmStr
                return tsmStr
            end
        end
    end

    -- Fallback: construct the TSM string by hand. Matches TSM's internal
    -- format i:<id>:<rand>:<numBonus>:<b1>:<b2>...:<numMods>:<t1>:<v1>:...
    local itemID, bonusStr, modStr = fqKey:match("^([^;]*);([^;]*);?(.*)$")
    if not itemID or itemID == "" then return nil end

    local parts = { "i", itemID, "" }

    local bonuses = {}
    if bonusStr and bonusStr ~= "" then
        for b in bonusStr:gmatch("[^:]+") do bonuses[#bonuses + 1] = b end
    end

    local modPairs = {}
    if modStr and modStr ~= "" then
        for m in modStr:gmatch("[^:]+") do
            local k, v = m:match("^(%-?%d+)=(%-?%d+)$")
            if k and v then
                modPairs[#modPairs + 1] = k
                modPairs[#modPairs + 1] = v
            end
        end
    end

    if #bonuses > 0 then
        parts[#parts + 1] = tostring(#bonuses)
        for _, b in ipairs(bonuses) do parts[#parts + 1] = b end
    elseif #modPairs > 0 then
        parts[#parts + 1] = "0"
    end

    if #modPairs > 0 then
        parts[#parts + 1] = tostring(#modPairs / 2)
        for _, p in ipairs(modPairs) do parts[#parts + 1] = p end
    end

    local result = table.concat(parts, ":")
    keyCache[fqKey] = result
    return result
end

local function BaseItemID(fqKey)
    local id = fqKey:match("^(%d+)")
    return id and ("i:" .. id) or nil
end

--------------------------
-- Profile & Operations DB
--------------------------

-- Get list of available TSM profiles
-- Merges TSM_API.GetProfiles with profiles found in TradeSkillMasterDB keys
function TSM:GetProfiles()
    local result = {}
    local seen = {}

    -- Source 1: TSM_API (runtime profiles)
    if self:IsAvailable() and TSM_API.GetProfiles then
        local apiProfiles = {}
        local ok = pcall(TSM_API.GetProfiles, TSM_API, apiProfiles)
        if ok then
            for _, name in ipairs(apiProfiles) do
                if not seen[name] then
                    seen[name] = true
                    result[#result + 1] = name
                end
            end
        end
    end

    -- Source 2: Scan TradeSkillMasterDB keys for "p@<profile>@" patterns
    if type(TradeSkillMasterDB) == "table" then
        for key in pairs(TradeSkillMasterDB) do
            local profile = key:match("^p@(.-)@")
            if profile and profile ~= "" and not seen[profile] then
                seen[profile] = true
                result[#result + 1] = profile
            end
        end
    end

    table.sort(result)
    return result
end

-- Get active TSM profile name
function TSM:GetActiveProfile()
    if not self:IsAvailable() then return nil end
    local ok, profile = pcall(TSM_API.GetActiveProfile, TSM_API)
    return ok and profile or nil
end

-- Get the profile name to use (selected or active)
function TSM:GetSelectedProfile()
    if not self:IsEnabled() then return nil end
    local selected = ns.db.settings.tsmProfile
    if selected and selected ~= "" then
        return selected
    end
    return self:GetActiveProfile()
end

-- Read operations table from TradeSkillMasterDB for a profile
function TSM:GetOperationsDB(profile)
    if not profile or not TradeSkillMasterDB then return nil end

    -- Check if operations are stored globally
    local globalFlag = TradeSkillMasterDB["g@ @coreOptions@globalOperations"]
    if globalFlag then
        return TradeSkillMasterDB["g@ @userData@sharedOperations"]
    end

    return TradeSkillMasterDB["p@" .. profile .. "@userData@operations"]
end

-- Read groups table from TradeSkillMasterDB for a profile
function TSM:GetGroupsDB(profile)
    if not profile or not TradeSkillMasterDB then return nil end
    return TradeSkillMasterDB["p@" .. profile .. "@userData@groups"]
end

-- Read items table from TradeSkillMasterDB for a profile
-- Returns: table of tsmItemString -> groupPath (e.g., ["i:12345"] = "Crafts`Enchanting")
function TSM:GetItemsDB(profile)
    if not profile or not TradeSkillMasterDB then return nil end
    return TradeSkillMasterDB["p@" .. profile .. "@userData@items"]
end

-- Get list of Auctioning operation names for a profile
function TSM:GetAuctioningOperations(profile)
    profile = profile or self:GetSelectedProfile()
    local opsDB = self:GetOperationsDB(profile)
    if not opsDB or not opsDB["Auctioning"] then return {} end

    local names = {}
    for name in pairs(opsDB["Auctioning"]) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- Resolve the Auctioning operation for an item by walking the group hierarchy
function TSM:GetItemAuctioningOp(fqKey)
    if not self:IsEnabled() then return nil end

    -- Check cache
    local cached = opCache[fqKey]
    if cached and (time() - cached.ts) < OP_CACHE_TTL then
        return cached
    end

    local profile = self:GetSelectedProfile()
    if not profile then return nil end

    -- Find which TSM group this item belongs to
    local tsmStr = self:ItemKeyToTSMString(fqKey)
    if not tsmStr then return nil end

    local ok, groupPath = pcall(TSM_API.GetGroupPathByItem, TSM_API, tsmStr)
    if not ok or not groupPath then
        local baseStr = BaseItemID(fqKey)
        if baseStr and baseStr ~= tsmStr then
            ok, groupPath = pcall(TSM_API.GetGroupPathByItem, TSM_API, baseStr)
        end
    end

    -- TSM_API.GetGroupPathByItem doesn't work for battle pets (returns
    -- error / nil), even when the pet IS grouped in TSM's UI. Fall back
    -- to a direct lookup in the per-profile items DB which stores
    -- "<tsmString>" -> "<groupPath>" for every grouped item including
    -- pets. We probe both the canonical tsmStr ("p:<species>") and the
    -- numeric base ID for completeness.
    if not (ok and groupPath) then
        local itemsDB = self:GetItemsDB(profile)
        if itemsDB then
            groupPath = itemsDB[tsmStr]
            if not groupPath then
                local baseStr = BaseItemID(fqKey)
                if baseStr and baseStr ~= tsmStr then
                    groupPath = itemsDB[baseStr]
                end
            end
            if groupPath then ok = true end
        end
    end

    local groupsDB = self:GetGroupsDB(profile)
    local opsDB = self:GetOperationsDB(profile)
    if not opsDB or not opsDB["Auctioning"] then return nil end

    local opName
    if ok and groupPath and groupsDB then
        opName = self:ResolveGroupOperation(groupsDB, groupPath, "Auctioning")
    end

    -- Fallback chain for ungrouped items:
    --  1. TSM's built-in "#Default" Auctioning op — TSM itself uses this
    --     when an item has no explicit group, so following the same
    --     fallback keeps our posting decisions aligned with TSM's.
    --  2. The player's tsmFallbackOp setting — only kicks in when
    --     #Default doesn't exist (rare; some players have deleted it).
    if not opName then
        if opsDB["Auctioning"]["#Default"] then
            opName = "#Default"
        else
            local fallback = ns.db and ns.db.settings.tsmFallbackOp or ""
            if fallback ~= "" and opsDB["Auctioning"][fallback] then
                opName = fallback
            end
        end
    end
    if not opName then return nil end

    local opSettings = opsDB["Auctioning"][opName]
    if not opSettings then return nil end

    -- Evaluate postCap up front. TSM defines it as a "custom string" setting
    -- so it accepts both literal numbers ("5", "1") and expressions
    -- ("max(1, dbmarket/1g)"). The old code used tonumber() on the raw
    -- string which returns nil for expressions — the caller then fell
    -- through to "no cap" and over-grabbed items. Try tonumber first for
    -- the common literal case, then fall back to TSM's evaluator.
    local postCapEval = tonumber(opSettings.postCap)
    if not postCapEval and opSettings.postCap and opSettings.postCap ~= "" then
        postCapEval = self:EvaluateOpPrice(fqKey, opSettings.postCap)
    end

    -- Audit the operation shape against the fields we expect. TSM may add or
    -- rename fields across versions; this surfaces mismatches so we don't
    -- silently fall through to defaults.
    self:CheckAuditedVersion(opSettings)

    local result = {
        opName        = opName,
        -- Price expression strings — evaluate via EvaluateOpPrice.
        minPrice      = opSettings.minPrice,
        maxPrice      = opSettings.maxPrice,
        normalPrice   = opSettings.normalPrice,
        undercut      = opSettings.undercut,
        -- String keys naming which price to use. Valid: "none", "ignore",
        -- "minPrice", "maxPrice", "normalPrice". Consumer looks the key up,
        -- then evaluates the referenced expression.
        priceReset    = opSettings.priceReset,
        aboveMax      = opSettings.aboveMax,
        -- Numeric: bid as a fraction of buyout (default 1.0 = bid equals
        -- buyout in TSM's internal math; we still post buy-it-now only).
        bidPercent    = opSettings.bidPercent,
        -- Pre-evaluated postCap so downstream consumers get a number, not a
        -- string expression. Nil when evaluation failed — callers should
        -- fall back to conservative behavior (post 1) rather than "no cap".
        postCap       = postCapEval,
        postCapRaw    = opSettings.postCap,
        duration      = opSettings.duration,
        -- TSM IsAuctionFiltered inputs: drop short-time-left auctions,
        -- match stack size on commodities, blacklist sellers per-op.
        ignoreLowDuration = opSettings.ignoreLowDuration,
        matchStackSize    = opSettings.matchStackSize,
        stackSize         = opSettings.stackSize,
        stackSizeIsCap    = opSettings.stackSizeIsCap,
        blacklist         = opSettings.blacklist,
        -- Cancel-side knobs we'll read as we add cancel support.
        cancelUndercut         = opSettings.cancelUndercut,
        cancelRepost           = opSettings.cancelRepost,
        cancelRepostThreshold  = opSettings.cancelRepostThreshold,
        ts            = time(),
    }
    opCache[fqKey] = result
    return result
end

--------------------------
-- Global Auctioning Settings (factionrealm-scoped)
--------------------------

-- TSM's whitelist is scoped per faction+realm and stored on the global
-- auctioning settings, not on individual operations. TSM v4.14.66 stores it
-- under the key "f@<faction> - <realm>@auctioningOptions@whitelist" in
-- TradeSkillMasterDB. Returns a set of lowercased seller names, or nil when
-- TSM hasn't initialised the key.
local _whitelistCache
local _whitelistCacheTs = 0
function TSM:GetWhitelist()
    if _whitelistCache and (time() - _whitelistCacheTs) < 60 then
        return _whitelistCache
    end
    if type(TradeSkillMasterDB) ~= "table" then return nil end
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
    local key = "f@" .. faction .. " - " .. realm .. "@auctioningOptions@whitelist"
    local raw = TradeSkillMasterDB[key]
    if type(raw) ~= "table" then
        _whitelistCache = {}
        _whitelistCacheTs = time()
        return _whitelistCache
    end
    local out = {}
    for name in pairs(raw) do
        if type(name) == "string" then
            out[name:lower()] = true
        end
    end
    _whitelistCache = out
    _whitelistCacheTs = time()
    return out
end

-- Whether a seller name appears on the player's blacklist for an operation.
-- Mirrors TSM's AuctioningOperation.IsBlacklisted (case-insensitive CSV
-- substring match against operationSettings.blacklist).
function TSM:IsBlacklisted(opOrBlacklist, sellerName)
    if not sellerName or sellerName == "" then return false end
    local raw
    if type(opOrBlacklist) == "table" then
        raw = opOrBlacklist.blacklist
    else
        raw = opOrBlacklist
    end
    if type(raw) ~= "string" or raw == "" then return false end
    local lower = sellerName:lower()
    -- TSM's String.SeparatedContains is a comma-split exact-segment match.
    -- We replicate that behavior so "alice,bobby" doesn't match "bob".
    for token in raw:lower():gmatch("[^,]+") do
        if token:gsub("^%s+", ""):gsub("%s+$", "") == lower then
            return true
        end
    end
    return false
end

--------------------------
-- Level-form item string
--------------------------

-- TSM's AuctionDB / AuctioningOp* price sources internally call
-- ItemString.ToLevel before lookup, which converts bonus-ID strings into
-- "i:<id>::i<ilvl>" — the level form. Price-data is keyed on the level
-- form, not on the canonicalised bonus-ID form. If we pass the bonus-ID
-- form to TSM_API.GetCustomPriceValue, TSM looks up against the wrong
-- partition and returns ~10% off values vs what TSM's own tooltip shows.
--
-- This helper builds the level form FlipQueue should use for price-source
-- queries. We try a few sources in order:
--   1. The provided itemLink (most accurate — current bag state)
--   2. The wowItemString rebuilt from fqKey
--   3. Base item string (no ilvl) as fallback
local levelStrCache = {}
function TSM:ItemKeyToLevelString(fqKey, itemLink)
    if not fqKey or fqKey == "" then return nil end
    if fqKey:find("^pet:") then return self:ItemKeyToTSMString(fqKey) end

    -- Cache by fqKey + itemLink — the link adds context that affects ilvl.
    local cacheKey = fqKey .. (itemLink or "")
    if levelStrCache[cacheKey] then return levelStrCache[cacheKey] end

    local itemID = fqKey:match("^(%d+)")
    if not itemID then return nil end

    local ilvl
    if itemLink and GetDetailedItemLevelInfo then
        ilvl = GetDetailedItemLevelInfo(itemLink)
    end
    if not ilvl and self.ItemKeyToItemString then
        local wowStr = ns:ItemKeyToItemString(fqKey)
        if wowStr and GetDetailedItemLevelInfo then
            ilvl = GetDetailedItemLevelInfo(wowStr)
        end
    end

    local result
    if ilvl and ilvl > 0 then
        result = "i:" .. itemID .. "::i" .. ilvl
    else
        result = "i:" .. itemID
    end
    levelStrCache[cacheKey] = result
    return result
end

--------------------------
-- Op Price Evaluation
--------------------------

-- Evaluate a TSM price expression for a given FlipQueue item key.
-- Returns the copper value or nil if the expression is empty / unevaluable.
-- Handles the base-ID fallback the same way GetPrice does.
function TSM:EvaluateOpPrice(fqKey, expression)
    if not self:IsAvailable() then return nil end
    if not expression or expression == "" then return nil end
    if not fqKey or fqKey == "" then return nil end

    local tsmStr = self:ItemKeyToTSMString(fqKey)
    if not tsmStr then return nil end

    local ok, copper = pcall(TSM_API.GetCustomPriceValue, expression, tsmStr)
    if ok and copper then return copper end

    -- Base-item fallback (strip bonus IDs)
    local baseStr = BaseItemID(fqKey)
    if baseStr and baseStr ~= tsmStr then
        ok, copper = pcall(TSM_API.GetCustomPriceValue, expression, baseStr)
        if ok and copper then return copper end
    end
    return nil
end

-- Evaluate the player's Auctioning operation normalPrice for an item.
-- Mirrors AuctionPost:ResolvePostPrice's op resolution but skips the
-- live AH state + decision tree -- callers that just need the "what
-- would TSM recommend posting at" copper value should use this.
--
-- Returns: normalCopper, opName  (either may be nil if no op is bound
-- to the item or the expression doesn't evaluate).
function TSM:GetOpNormalPrice(fqKey)
    if not self:IsEnabled() then return nil, nil end
    if not fqKey or fqKey == "" then return nil, nil end

    -- AuctioningOpNormal is TSM's built-in source key that resolves to
    -- the active Auctioning op's normalPrice for the bound item. Try
    -- it first -- avoids a separate group lookup round-trip when TSM
    -- can answer directly.
    local copper = self:EvaluateOpPrice(fqKey, "AuctioningOpNormal")
    local op     = self:GetItemAuctioningOp(fqKey)
    local opName = op and op.opName or nil
    if copper and copper > 0 then
        return copper, opName
    end

    -- Fallback: pull the expression off the op record and evaluate
    -- directly. Covers items where TSM groups the item but the built-
    -- in key fails (rare; usually a stale group cache).
    if op and op.normalPrice then
        copper = self:EvaluateOpPrice(fqKey, op.normalPrice)
        if copper and copper > 0 then
            return copper, opName
        end
    end

    return nil, opName
end

-- Walk group hierarchy to find effective operation (handles inheritance)
function TSM:ResolveGroupOperation(groupsDB, groupPath, moduleName)
    local groupData = groupsDB[groupPath]
    if groupData and groupData[moduleName] then
        local opEntry = groupData[moduleName]
        -- If this group has an override or is root, use its operation
        if opEntry.override or groupPath == "" then
            return opEntry[1] -- first operation name
        end
    end

    -- Walk up the hierarchy (backtick separator)
    if groupPath == "" then return nil end
    local parentPath = groupPath:match("^(.+)`[^`]+$") or ""
    return self:ResolveGroupOperation(groupsDB, parentPath, moduleName)
end

--------------------------
-- Price Lookup
--------------------------

function TSM:GetPrice(fqKey, priceSource)
    if not self:IsEnabled() then return nil end
    if not fqKey or not priceSource then return nil end

    local cacheKey = fqKey .. "|" .. priceSource
    local cached = priceCache[cacheKey]
    if cached and (time() - cached.ts) < CACHE_TTL then
        return cached.value
    end

    local tsmStr = self:ItemKeyToTSMString(fqKey)
    if not tsmStr then return nil end

    local ok, copper = pcall(TSM_API.GetCustomPriceValue, priceSource, tsmStr)
    local value = ok and copper or nil

    -- Fallback: try base item ID
    if not value then
        local baseStr = BaseItemID(fqKey)
        if baseStr and baseStr ~= tsmStr then
            ok, copper = pcall(TSM_API.GetCustomPriceValue, priceSource, baseStr)
            value = ok and copper or nil
        end
    end

    priceCache[cacheKey] = { value = value, ts = time() }
    return value
end

--------------------------
-- Threshold Check (per-item operation)
--------------------------

-- Returns: isBelowThreshold, ahMinCopper, thresholdCopper, opName
function TSM:IsBelowThreshold(fqKey)
    if not self:IsEnabled() then return false, nil, nil, nil end

    local ahMin = self:GetPrice(fqKey, "DBMinBuyout")
    if not ahMin then return false, nil, nil, nil end

    -- Get this item's Auctioning operation minPrice
    local op = self:GetItemAuctioningOp(fqKey)
    if not op or not op.minPrice then
        -- Fallback to manual threshold if no operation found
        local fallback = ns.db.settings.tsmMinPriceSource
        if fallback and fallback ~= "" then
            local threshold = self:GetPrice(fqKey, fallback)
            if threshold then
                return ahMin < threshold, ahMin, threshold, nil
            end
        end
        return false, nil, nil, nil
    end

    -- Evaluate the operation's minPrice expression
    local threshold = self:GetPrice(fqKey, op.minPrice)
    if not threshold then return false, ahMin, nil, op.opName end

    return ahMin < threshold, ahMin, threshold, op.opName
end

--------------------------
-- Formatting
--------------------------

function TSM:FormatCopper(copper)
    if not copper then return nil end
    if self:IsAvailable() and TSM_API.FormatMoneyString then
        local ok, result = pcall(TSM_API.FormatMoneyString, TSM_API, copper)
        if ok and result then return result end
    end
    return ns:FormatGold(copper)
end

--------------------------
-- Validation
--------------------------

function TSM:IsValidPriceSource(str)
    if not self:IsAvailable() or not str or str == "" then return false end
    -- Try without self first (TSM4+ API), fall back to with self
    local ok, result = pcall(TSM_API.IsCustomPriceValid, str)
    if not ok then
        ok, result = pcall(TSM_API.IsCustomPriceValid, TSM_API, str)
    end
    return ok and result
end

--------------------------
-- Character Detection
--------------------------

-- Detect characters from TSM's internal scope data.
-- Returns array of {charKey, name, realm, class, gold} for chars not in ns.db.characters.
function TSM:DetectCharacters()
    if type(TradeSkillMasterDB) ~= "table" then return {} end

    local scopeKeys = TradeSkillMasterDB._scopeKeys
    if not scopeKeys or not scopeKeys.char then return {} end

    local dismissed = ns.db and ns.db.settings.dismissedTSMChars or {}
    local results = {}

    for _, charEntry in ipairs(scopeKeys.char) do
        -- TSM format: "CharName - RealmName"
        local tsmName, tsmRealm = charEntry:match("^(.+) %- (.+)$")
        if tsmName and tsmRealm then
            local charKey = tsmName .. "-" .. tsmRealm
            -- Skip if already known, dismissed, or tombstoned. Tombstoned
            -- chars were explicitly deleted by the user; we must not prompt
            -- to re-add them.
            if not (ns.db.characters and ns.db.characters[charKey])
                and not dismissed[charKey]
                and not ns:IsCharDeleted(charKey) then
                -- Look up class from TSM internal data
                -- Keys: s@CharName - Faction - RealmName@internalData@classKey
                local charClass = nil
                local charGold = 0
                for dbKey, val in pairs(TradeSkillMasterDB) do
                    -- Match any faction variant for this character+realm
                    local matchPattern = "^s@" .. tsmName:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
                        .. " %- .+ %- " .. tsmRealm:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1") .. "@"
                    if dbKey:match(matchPattern) then
                        if dbKey:find("@internalData@classKey$") and type(val) == "string" then
                            charClass = val:upper()
                        elseif dbKey:find("@internalData@money$") and type(val) == "number" then
                            charGold = val
                        end
                    end
                end

                table.insert(results, {
                    charKey = charKey,
                    name    = tsmName,
                    realm   = tsmRealm,
                    class   = charClass,
                    gold    = charGold,
                })
            end
        end
    end

    return results
end

--------------------------
-- Account Detection
--------------------------

-- Detect WoW accounts from TSM's sync data (_syncOwner).
-- Groups characters by the unique account ID extracted from the sync key.
-- Returns: uuidGroups (uuid -> {charKey,...}), primaryUUID (or nil if unavailable)
function TSM:DetectAccounts()
    if type(TradeSkillMasterDB) ~= "table" then return nil, nil end

    local syncOwner = TradeSkillMasterDB._syncOwner
    if not syncOwner then return nil, nil end

    -- Extract UUID from account key: "Faction - Realm - UUID" -> "UUID"
    local function ExtractUUID(accountKey)
        return accountKey:match("^.+ %- (.+)$")
    end

    -- Group characters by account UUID
    local uuidGroups = {} -- uuid -> array of charKeys

    for charEntry, accountKey in pairs(syncOwner) do
        -- charEntry format: "CharName - Faction - RealmName"
        local name, faction, realm = charEntry:match("^(.+) %- (.+) %- (.+)$")
        if name and realm then
            local charKey = name .. "-" .. realm
            local uuid = ExtractUUID(accountKey)
            if uuid then
                if not uuidGroups[uuid] then
                    uuidGroups[uuid] = {}
                end
                table.insert(uuidGroups[uuid], charKey)
            end
        end
    end

    -- Sort character lists for consistent display
    for _, chars in pairs(uuidGroups) do
        table.sort(chars)
    end

    -- Find which UUID the current character belongs to
    local myCharKey = ns:GetCharKey()
    local primaryUUID = nil
    for uuid, chars in pairs(uuidGroups) do
        for _, charKey in ipairs(chars) do
            if charKey == myCharKey then
                primaryUUID = uuid
                break
            end
        end
        if primaryUUID then break end
    end

    return uuidGroups, primaryUUID
end

-- Sync detected accounts into ns.db.accounts.primary and ns.db.accounts.linked.
-- Preserves existing labels on linked accounts.
function TSM:SyncAccounts()
    if not ns.db then return false end

    local groups, primaryUUID = self:DetectAccounts()
    if not groups then return false end

    -- Update primary account
    if primaryUUID then
        ns.db.accounts.primary = {
            syncKey = primaryUUID,
            characters = groups[primaryUUID] or {},
        }
    end

    -- Update linked accounts (preserve user-set labels)
    local oldLinked = ns.db.accounts.linked or {}
    local newLinked = {}
    local idx = 1
    for uuid, chars in pairs(groups) do
        if uuid ~= primaryUUID then
            local existing = oldLinked[uuid]
            newLinked[uuid] = {
                label = existing and existing.label or ("Account " .. (idx + 1)),
                characters = chars,
                lastSync = time(),
            }
            idx = idx + 1
        end
    end
    ns.db.accounts.linked = newLinked

    return true
end

--------------------------
-- Cache Management
--------------------------

function TSM:InvalidateCache()
    wipe(priceCache)
    wipe(opCache)
end
