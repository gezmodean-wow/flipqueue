-- ItemBindings.lua
-- Detect Warbound / Warbound-until-Equipped status by tooltip scan.
-- C_Item.GetItemInfo's bindType column reports the *intrinsic* binding
-- (BoP/BoE/BoU/BoA/etc.) but doesn't distinguish "Warbound until Equipped"
-- from a regular BoE — both report bindType=2. Syndicator's slot.isBound
-- only flips true once an item is fully soulbound to a character, so
-- warbound gear sitting in bags or warbank slips through downstream
-- "tradeable" filters (FQ-173).
--
-- Mirrors Syndicator's tooltip-scan approach (Search/CheckItem.lua) by
-- reading the localized account-bound tooltip lines. Cache key is the full
-- itemKey since some bonus-ID variants (crafted reagent quality) flip the
-- binding even when the base itemID matches.

local addonName, ns = ...

local Bindings = {}
ns.ItemBindings = Bindings

local cache = {}

local WARBOUND_LINES = {}
do
    local candidates = {
        ITEM_ACCOUNTBOUND,
        ITEM_ACCOUNTBOUND_UNTIL_EQUIP,
        ITEM_BIND_TO_ACCOUNT,
        ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP,
        ITEM_BIND_TO_BNETACCOUNT,
        ITEM_BNETACCOUNTBOUND,
        ITEM_BNETACCOUNTBOUND_UNTIL_EQUIP,
    }
    for _, line in ipairs(candidates) do
        if line and line ~= "" then
            WARBOUND_LINES[line] = true
        end
    end
end

local scanTooltip
local function GetScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "FlipQueueBindingScanTooltip",
            UIParent, "GameTooltipTemplate")
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return scanTooltip
end

-- Returns false (and does NOT cache) when item data isn't loaded yet, so a
-- later scan after GET_ITEM_INFO_RECEIVED can re-evaluate.
function Bindings:IsWarbound(itemKey, itemLink)
    if not itemKey then return false end
    local cached = cache[itemKey]
    if cached ~= nil then return cached end
    if not itemLink or itemLink == "" then return false end

    local tt = GetScanTooltip()
    tt:ClearLines()
    local ok = pcall(tt.SetHyperlink, tt, itemLink)
    if not ok then return false end

    local n = tt:NumLines()
    if n == 0 then return false end

    for i = 1, n do
        local fontstring = _G["FlipQueueBindingScanTooltipTextLeft" .. i]
        local text = fontstring and fontstring:GetText()
        if text and WARBOUND_LINES[text] then
            cache[itemKey] = true
            return true
        end
    end

    cache[itemKey] = false
    return false
end

function Bindings:ClearCache()
    wipe(cache)
end
