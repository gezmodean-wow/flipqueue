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

    -- Parse "itemID;bonusIDs;modifiers"
    local itemID, bonusStr = fqKey:match("^([^;]*);([^;]*)")
    if not itemID or itemID == "" then return nil end

    if not bonusStr or bonusStr == "" then
        local result = "i:" .. itemID
        keyCache[fqKey] = result
        return result
    end

    -- With bonus IDs: "1663:2293" -> "i:225575::2:1663:2293"
    local bonuses = {}
    for b in bonusStr:gmatch("[^:]+") do
        bonuses[#bonuses + 1] = b
    end
    local result = "i:" .. itemID .. "::" .. #bonuses .. ":" .. table.concat(bonuses, ":")
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
function TSM:GetProfiles()
    if not self:IsAvailable() then return {} end
    local result = {}
    local ok = pcall(TSM_API.GetProfiles, TSM_API, result)
    return ok and result or {}
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
    if not ok or not groupPath then return nil end

    -- Walk group hierarchy to find the effective Auctioning operation
    local groupsDB = self:GetGroupsDB(profile)
    local opsDB = self:GetOperationsDB(profile)
    if not groupsDB or not opsDB or not opsDB["Auctioning"] then return nil end

    local opName = self:ResolveGroupOperation(groupsDB, groupPath, "Auctioning")
    if not opName then return nil end

    local opSettings = opsDB["Auctioning"][opName]
    if not opSettings then return nil end

    local result = {
        opName      = opName,
        minPrice    = opSettings.minPrice,
        maxPrice    = opSettings.maxPrice,
        normalPrice = opSettings.normalPrice,
        postCap     = opSettings.postCap,
        duration    = opSettings.duration,
        ts          = time(),
    }
    opCache[fqKey] = result
    return result
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

    local ok, copper = pcall(TSM_API.GetCustomPriceValue, TSM_API, priceSource, tsmStr)
    local value = ok and copper or nil

    -- Fallback: try base item ID
    if not value then
        local baseStr = BaseItemID(fqKey)
        if baseStr and baseStr ~= tsmStr then
            ok, copper = pcall(TSM_API.GetCustomPriceValue, TSM_API, priceSource, baseStr)
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
    local ok, result = pcall(TSM_API.IsCustomPriceValid, TSM_API, str)
    return ok and result
end

--------------------------
-- Cache Management
--------------------------

function TSM:InvalidateCache()
    wipe(priceCache)
    wipe(opCache)
end
