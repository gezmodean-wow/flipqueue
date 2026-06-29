-- ItemLookup.lua
-- Lazy cache mapping Syndicator item hyperlinks to FlipQueue's item-key format.
--
-- Phase 6a: Syndicator stores per-slot data with full item hyperlinks (which
-- carry bonus IDs, enchants, etc.). FlipQueue keys inventory by the compact
-- "itemID;bonusIDs;modifiers" string — we call ns:ParseItemLink + ns:MakeItemKey
-- to convert. Re-parsing every hyperlink on every projection pass would be
-- wasteful, so this small cache memoizes the conversion. It's cleared
-- periodically to stay bounded.
local addonName, ns = ...

local ItemLookup = {}
ns.ItemLookup = ItemLookup

local cache = {}
local cacheSize = 0
local MAX_CACHE = 1000

-- Static per-item metadata cache, keyed by FlipQueue itemKey. The fields here
-- (name, ilvl, bindType, plus the parsed itemID/bonusIDs/modifiers) are stable
-- for a given itemKey, but resolving them costs a ns:ParseItemLink plus a
-- C_Item.GetItemInfo and a GetDetailedItemLevelInfo call. Before FQ-222 the
-- projection rebuilt every item entry from scratch on every BagCacheUpdate, so
-- a TSM post scan — which fires that path ~every 0.3s — re-ran those API calls
-- for the whole bag+bank set each tick. Memoizing here makes re-projection a
-- cheap table read once an item has resolved once.
local metaCache = {}

-- Resolve the stable metadata for an item link. Returns a table shaped
-- { itemID, bonusIDs, modifiers, name, ilvl, bindType }. The result is cached
-- by itemKey ONLY once item data has loaded (a real name came back) — a cold
-- "Unknown"/ilvl=0 placeholder is returned but not cached, so a later pass
-- after GET_ITEM_INFO_RECEIVED re-resolves it. Mirrors ItemBindings:IsWarbound.
function ItemLookup:GetItemMeta(itemKey, itemLink)
    if not itemKey or not itemLink or itemLink == "" then return nil end
    local cached = metaCache[itemKey]
    if cached then return cached end

    local itemID, bonusIDs, modifiers = ns:ParseItemLink(itemLink)
    local name, ilvl, bindType = nil, 0, 0
    local resolved = false

    if itemLink:find("|Hbattlepet:") then
        -- Caged-pet links carry the localized name inline; no item-cache wait.
        name = itemLink:match("|h%[(.-)%]|h")
        resolved = name ~= nil
    else
        -- Single combined GetItemInfo call — name + bindType (index 14).
        local ok, n, _, _, _, _, _, _, _, _, _, _, _, _, bt =
            pcall(C_Item.GetItemInfo, itemLink)
        if ok and n then
            name = n
            if bt then bindType = bt end
            resolved = true
        end
        if GetDetailedItemLevelInfo then
            local okIlvl, result = pcall(GetDetailedItemLevelInfo, itemLink)
            if okIlvl and result then ilvl = tonumber(result) or 0 end
        end
    end

    local meta = {
        itemID    = itemID,
        bonusIDs  = bonusIDs or "",
        modifiers = modifiers or "",
        name      = name or "Unknown",
        ilvl      = ilvl,
        bindType  = bindType,
    }
    if resolved then
        metaCache[itemKey] = meta
    end
    return meta
end

function ItemLookup:GetItemKey(itemLink)
    if not itemLink or itemLink == "" then return nil end
    local cached = cache[itemLink]
    if cached then return cached end

    local itemID, bonusIDs, modifiers = ns:ParseItemLink(itemLink)
    if not itemID then return nil end
    local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
    cache[itemLink] = key
    cacheSize = cacheSize + 1
    if cacheSize > MAX_CACHE then
        self:ClearCache()
    end
    return key
end

function ItemLookup:ClearCache()
    wipe(cache)
    wipe(metaCache)
    cacheSize = 0
end
