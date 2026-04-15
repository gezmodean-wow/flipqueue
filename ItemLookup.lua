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
    cacheSize = 0
end
