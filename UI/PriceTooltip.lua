-- UI/PriceTooltip.lua
-- One place that explains where a Deal Finder price came from.
--
-- A price shown against a realm is the end of a chain: TSM downloaded that
-- realm's auction data at some point, we looked this item up in it and may
-- have had to settle for a neighbouring item level, we took either the recent
-- market value or the cheapest current listing, and then we may have blended
-- the player's own sales into it. Any link in that chain can be the reason a
-- number looks wrong, and none of it was visible.
--
-- This module renders the whole chain into a tooltip so a player can work out
-- the cause themselves rather than reporting "the price is wrong". It is
-- shared so the realm cards and the realm comparison table say exactly the
-- same thing about the same number.
local addonName, ns = ...
local UI = ns.UI

local function G(c) return (not c or c <= 0) and "-" or ns:FormatGold(c) end

-- "3 hours ago" / "2 days ago". TSM's AppData is refreshed by the desktop app,
-- so this is the age of the download, not of the auction house itself — an
-- overnight gap here is the single most common reason a price disagrees with
-- what the player is looking at in game.
local function Age(ts)
    if not ts or ts <= 0 then return nil end
    local secs = time() - ts
    if secs < 0 then return "just now" end
    if secs < 60 then return "just now" end
    if secs < 3600 then
        local m = math.floor(secs / 60)
        return m .. (m == 1 and " minute ago" or " minutes ago")
    end
    if secs < 86400 then
        local h = math.floor(secs / 3600)
        return h .. (h == 1 and " hour ago" or " hours ago")
    end
    local d = math.floor(secs / 86400)
    return d .. (d == 1 and " day ago" or " days ago")
end

-- Staleness colouring. TSM's app refreshes roughly hourly when it is running,
-- so a day-old figure means it has not been running and the player should know
-- before they trust the number.
local function AgeColor(ts)
    if not ts or ts <= 0 then return 0.7, 0.7, 0.7 end
    local secs = time() - ts
    if secs > 86400 then return 1.0, 0.4, 0.4 end
    if secs > 21600 then return 0.9, 0.8, 0.4 end
    return 0.6, 0.8, 0.6
end

local SOURCE_TEXT = {
    perRealm = "This realm's own auction data",
    perRealmApprox = "This realm's data, for a close variant",
    regional = "Region-wide average (no data for this realm)",
}

local FIELD_TEXT = {
    marketValueRecent = "Recent market value",
    minBuyout = "Cheapest listing right now",
    DBRegionMarketAvg = "TSM regional market average",
}

-- Append the full provenance for one realm option to `tt`.
--
-- `ref` is a realm option from DealFinder:ScanChunked; `group` is the item
-- group it belongs to (used for the item ID behind the per-level breakdown).
-- Safe to call with partial data — every section is independently guarded, so
-- an older cached scan result renders whatever it has rather than erroring.
function UI:AddPriceProvenance(tt, ref, group)
    if not tt or not ref then return end

    tt:AddLine(" ")
    tt:AddLine("Where this price comes from", 1, 0.82, 0)

    -- 1. Which pool of data answered.
    local srcLabel = SOURCE_TEXT[ref.dataQuality] or SOURCE_TEXT.regional
    if ref.dataQuality == "perRealm" and ref.spreadTight then
        srcLabel = "This realm's data, from a close item level"
    end
    tt:AddDoubleLine("Source", srcLabel, 0.7, 0.7, 0.7, 0.85, 0.85, 0.85)

    -- 2. Which TSM column the number actually is. marketValueRecent and
    --    minBuyout can disagree by a wide margin on a thin item, and knowing
    --    which one answered is often the whole explanation.
    if ref.priceField then
        tt:AddDoubleLine("Figure used", FIELD_TEXT[ref.priceField] or ref.priceField,
            0.7, 0.7, 0.7, 0.85, 0.85, 0.85)
    end
    -- Show the column we did NOT use, when we have it. A big gap between the
    -- two is the signal that the item is thinly traded.
    if ref.rawRecent and ref.rawMinBuyout and ref.rawRecent > 0 and ref.rawMinBuyout > 0 then
        tt:AddDoubleLine("  Recent market / cheapest listing",
            G(ref.rawRecent) .. "  /  " .. G(ref.rawMinBuyout),
            0.55, 0.55, 0.55, 0.7, 0.7, 0.7)
    end
    if ref.numAuctions ~= nil then
        tt:AddDoubleLine("  Listed on this realm", tostring(ref.numAuctions),
            0.55, 0.55, 0.55, 0.7, 0.7, 0.7)
    end

    -- 3. How old the data is.
    local age = Age(ref.updateTime)
    if age then
        local r, g, b = AgeColor(ref.updateTime)
        tt:AddDoubleLine("Data age", age, 0.7, 0.7, 0.7, r, g, b)
        if ref.updateTime and (time() - ref.updateTime) > 86400 then
            tt:AddLine("TSM's desktop app hasn't refreshed this in over a day.", 1, 0.4, 0.4)
        end
    elseif ref.dataQuality ~= "regional" then
        tt:AddDoubleLine("Data age", "unknown", 0.7, 0.7, 0.7, 0.6, 0.6, 0.6)
    end

    -- 4. The item-level substitution, if there was one.
    if ref.dataQuality == "perRealmApprox" then
        if ref.approxSource == "baseItem" then
            tt:AddLine("No price for your exact item level, so this is the item's", 0.9, 0.75, 0.4)
            tt:AddLine("general price on this realm - usually the cheapest one listed.", 0.9, 0.75, 0.4)
        elseif ref.approxIlvl then
            tt:AddLine("Borrowed from item level " .. ref.approxIlvl ..
                " - your exact level isn't priced here.", 0.9, 0.75, 0.4)
        else
            tt:AddLine("Borrowed from a nearby item level.", 0.9, 0.75, 0.4)
        end
    elseif ref.spreadTight and ref.approxIlvl then
        tt:AddLine("Borrowed from item level " .. ref.approxIlvl ..
            ", which prices the same here.", 0.5, 0.8, 0.5)
    end

    -- 5. The item-level spread, and the per-level breakdown behind it. This is
    --    the evidence for whether the borrow above was reasonable, and it is
    --    worth showing even on an exact match: a wide spread means the
    --    neighbouring levels are not interchangeable.
    if ref.ilvlSpread and ref.ilvlBuckets then
        local threshold = (ns.TSMRealms and ns.TSMRealms.SpreadThreshold
            and ns.TSMRealms:SpreadThreshold()) or 2
        local tight = ref.ilvlSpread <= threshold
        tt:AddDoubleLine("Item level spread",
            string.format("%.1fx across %d levels", ref.ilvlSpread, ref.ilvlBuckets),
            0.7, 0.7, 0.7,
            tight and 0.5 or 0.9, tight and 0.8 or 0.7, tight and 0.5 or 0.4)
        if ref.ilvlPriceLow and ref.ilvlPriceHigh then
            tt:AddLine("  " .. G(ref.ilvlPriceLow) .. "  to  " .. G(ref.ilvlPriceHigh),
                0.6, 0.6, 0.6)
        end
        tt:AddLine(tight
            and "  Item level barely moves this item's price here."
            or  "  Item level matters a lot for this item here.",
            0.6, 0.6, 0.6)

        local baseID = group and group.itemKey and tostring(group.itemKey):match("^(%d+)")
        if baseID and ns.TSMRealms and ns.TSMRealms.GetIlvlBuckets then
            local buckets = ns.TSMRealms:GetIlvlBuckets(baseID, ref.realmName)
            local shown = 0
            for _, b in ipairs(buckets or {}) do
                if b.price and shown < 8 then
                    shown = shown + 1
                    local mark = (ref.approxIlvl and b.ilvl == ref.approxIlvl) and "  <-- used" or ""
                    tt:AddDoubleLine("    ilvl " .. b.ilvl,
                        G(b.price) .. " (" .. (b.numAuctions or 0) .. " listed)" .. mark,
                        0.5, 0.5, 0.5, 0.7, 0.7, 0.7)
                end
            end
            if buckets and #buckets > shown then
                tt:AddLine("    ... and " .. (#buckets - shown) .. " more", 0.5, 0.5, 0.5)
            end
        end
    end

    -- 6. What we did to the TSM figure afterwards. When the player has sold
    --    this item on this realm before, their own average is blended in, so
    --    the number on screen is not the TSM number and the difference should
    --    not be a mystery.
    if ref.tsmPriceRaw and ref.blendedPrice and ref.personalCount and ref.personalCount >= 2
        and ref.personalAvg and ref.personalAvg > 0 and ref.blendedPrice ~= ref.tsmPriceRaw then
        tt:AddLine(" ")
        tt:AddDoubleLine("TSM figure", G(ref.tsmPriceRaw), 0.7, 0.7, 0.7, 0.85, 0.85, 0.85)
        tt:AddDoubleLine("Your average here (" .. ref.personalCount .. " sold)",
            G(ref.personalAvg), 0.7, 0.7, 0.7, 1, 0.82, 0)
        tt:AddDoubleLine("Blended, which is what's shown", G(ref.blendedPrice),
            0.7, 0.7, 0.7, 1, 1, 1)
    end

    -- 7. Why it might not be the recommended realm.
    if ref.isOutlier then
        tt:AddLine(" ")
        tt:AddLine("Flagged as an outlier - well above the regional average.", 1, 0.4, 0.4)
        if ns.db and ns.db.settings and ns.db.settings.dfIgnoreOutliers then
            tt:AddLine("Outliers are set to be skipped when picking a realm.", 0.7, 0.7, 0.7)
        end
    end
    if ref.dataQuality == "regional" then
        tt:AddLine(" ")
        tt:AddLine("TSM has no data for this realm, so this is the region-wide", 0.9, 0.6, 0.6)
        tt:AddLine("average - it will read the same on every realm lacking data.", 0.9, 0.6, 0.6)
    end
end
