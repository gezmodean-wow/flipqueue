-- UI/DealFinderDetail.lua
-- Renders the per-item content for the Deal Finder review phase.
-- Provides: item header rendering, realm checkbox rows, research data.
local addonName, ns = ...

local UI = ns.UI

local REALM_H = 22
local INFO_H  = 16

--------------------------
-- Frame Pool
--------------------------

local pool = {}
local poolIdx = 0

local function Acquire(parent)
    poolIdx = poolIdx + 1
    local f = pool[poolIdx]
    if not f then
        f = CreateFrame("Button", nil, parent)
        f._labels = {}
        pool[poolIdx] = f
    end
    f:SetParent(parent)
    f:ClearAllPoints()
    f:SetScript("OnClick", nil)
    f:SetScript("OnEnter", nil)
    f:SetScript("OnLeave", nil)
    f:EnableMouse(false)
    f:Show()
    return f
end

function UI:ResetDealFinderPool()
    for i = 1, poolIdx do pool[i]:Hide(); pool[i]:ClearAllPoints() end
    poolIdx = 0
end

local function Lbl(f, key, font)
    if not f._labels[key] then
        f._labels[key] = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    end
    f._labels[key]:Show()
    return f._labels[key]
end

local function Bg(f)
    if not f._bg then f._bg = f:CreateTexture(nil, "BACKGROUND"); f._bg:SetAllPoints() end
    f._bg:Show()
    return f._bg
end

local function G(c) return (not c or c <= 0) and "-" or ns:FormatGold(c) end

local function QCN(name, quality)
    return UI._QualityColorName and UI._QualityColorName(name, quality) or name or "?"
end

--------------------------
-- Resolve item info
--------------------------

local function ResolveItemInfo(group)
    local numID = tonumber(group.itemID)
    if numID and numID > 0 then
        if not group.icon then
            local ok, _, _, _, _, tex = pcall(C_Item.GetItemInfoInstant, numID)
            if ok and tex then group.icon = tex end
        end
        if not group.quality or group.quality == "" then
            local ok, _, _, q = pcall(C_Item.GetItemInfo, numID)
            if ok and q then group.quality = q end
        end
    end
end

--------------------------
-- Render Item Header (pinned area at top)
--------------------------

function UI:RenderDealFinderHeader(headerFrame, group)
    if not headerFrame._labels then headerFrame._labels = {} end
    ResolveItemInfo(group)

    local C = ns.COLORS or {}

    -- Large item icon + name (with tooltip on hover)
    local iconStr = group.icon and ("|T" .. group.icon .. ":20:20:0:0|t ") or ""
    local nameLbl = Lbl(headerFrame, "name", "GameFontNormalLarge")
    nameLbl:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 8, -6)
    nameLbl:SetText(iconStr .. QCN(group.name, group.quality))

    -- Item tooltip on hover
    headerFrame:EnableMouse(true)
    local numID = tonumber(group.itemID)
    headerFrame:SetScript("OnEnter", function(self)
        if numID and numID > 0 then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:SetItemByID(numID)
        end
    end)
    headerFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Denied badge
    local badge = Lbl(headerFrame, "badge", "GameFontNormal")
    badge:SetPoint("LEFT", nameLbl, "RIGHT", 12, 0)
    badge:SetText(group.denied and ((C.RED or "") .. "SKIPPED|r") or "")

    -- Summary stats row 1: Inventory + Sales
    local ps = group.personalSales or {}
    local invParts = {}
    if group.sources then
        local byLoc = {}
        for _, src in ipairs(group.sources) do
            byLoc[src.location or "bags"] = (byLoc[src.location or "bags"] or 0) + src.quantity
        end
        for loc, qty in pairs(byLoc) do table.insert(invParts, qty .. " " .. loc) end
    end

    local line1 = Lbl(headerFrame, "line1", "GameFontHighlightSmall")
    line1:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 10, -32)

    local salesStr
    if ps.sold and ps.sold > 0 then
        local rate = string.format("%.0f%%", ps.successRate * 100)
        salesStr = ps.sold .. " sold / " .. (ps.sold + ps.failed) .. " attempts (" .. (C.GREEN or "") .. rate .. "|r)"
    else
        salesStr = "|cff666666No sales history|r"
    end

    line1:SetText("|cffaaaaaaQty:|r " .. (group.quantity or 0)
        .. (#invParts > 0 and (" (" .. table.concat(invParts, ", ") .. ")") or "")
        .. "     |cffaaaaaaSales:|r " .. salesStr)

    -- Summary stats row 2: Market + Rate + My price vs market
    local line2 = Lbl(headerFrame, "line2", "GameFontHighlightSmall")
    line2:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 10, -48)

    local parts = {}
    if group.regionMarketAvg and group.regionMarketAvg > 0 then
        table.insert(parts, "|cffaaaaaaMarket:|r " .. G(group.regionMarketAvg))
    end
    if group.regionSaleRate then
        table.insert(parts, "|cffaaaaaaRate:|r " .. string.format("%.0f%%", group.regionSaleRate * 100))
    end
    if ps.avgPrice and ps.avgPrice > 0 and group.regionMarketAvg and group.regionMarketAvg > 0 then
        local diff = ps.avgPrice - group.regionMarketAvg
        local pct = math.floor(diff / group.regionMarketAvg * 100)
        local col = pct >= 0 and (C.GREEN or "") or (C.RED or "")
        table.insert(parts, "|cffaaaaaaMy Avg:|r " .. G(ps.avgPrice) .. " (" .. col .. (pct >= 0 and "+" or "") .. pct .. "%|r)")
    end

    line2:SetText(table.concat(parts, "     "))

    -- Row 3: Outlier threshold info
    local line3 = Lbl(headerFrame, "line3", "GameFontDisableSmall")
    line3:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 10, -64)
    local outlierMult = ns.db and ns.db.settings.dfOutlierMultiplier or 1.5
    local hasOutlier = false
    for _, r in ipairs(group.realms) do
        if r.isOutlier then hasOutlier = true; break end
    end
    if hasOutlier then
        line3:SetText((C.RED or "") .. "! Some realms flagged as outliers (>" .. math.floor(outlierMult * 100) .. "% of regional avg)|r")
    else
        line3:SetText("")
    end
end

--------------------------
-- Render Realm Checkboxes + Research (scrollable content)
--------------------------

function UI:RenderDealFinderRealms(scrollContent, group, onToggle)
    UI:ResetDealFinderPool()

    local C = ns.COLORS or {}
    local y = -6

    -- Section: Target Realms
    local secHdr = Acquire(scrollContent)
    secHdr:SetHeight(20)
    secHdr:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, y)
    secHdr:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
    Bg(secHdr):SetColorTexture(0.1, 0.1, 0.15, 0.8)
    Lbl(secHdr, "t", "GameFontNormal"):SetPoint("LEFT", 8, 0)
    secHdr._labels.t:SetText("Target Realms")
    y = y - 22

    -- Realm rows with checkboxes
    for i, realm in ipairs(group.realms) do
        local isSel = (realm._selected ~= false)

        local f = Acquire(scrollContent)
        f:SetHeight(REALM_H)
        f:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 4, y)
        f:SetPoint("RIGHT", scrollContent, "RIGHT", -4, 0)
        f:EnableMouse(true)

        local bg = Bg(f)
        bg:SetColorTexture(isSel and 0.1 or 0.04, isSel and 0.22 or 0.04, isSel and 0.1 or 0.06, isSel and 0.6 or 0.2)

        f:SetScript("OnEnter", function(s) Bg(s):SetColorTexture(0.12, 0.12, 0.2, 0.5) end)
        f:SetScript("OnLeave", function(s)
            Bg(s):SetColorTexture(isSel and 0.1 or 0.04, isSel and 0.22 or 0.04, isSel and 0.1 or 0.06, isSel and 0.6 or 0.2)
        end)

        -- Checkbox indicator
        local chk = Lbl(f, "chk", "GameFontNormal")
        chk:SetPoint("LEFT", f, "LEFT", 8, 0)
        chk:SetText(isSel and ((C.GREEN or "") .. "[x]|r") or "|cff555555[ ]|r")

        -- Realm name
        local realmName = realm.realmName or ""
        local price = G(realm.blendedPrice)
        local tsmPrice = G(realm.tsmPrice)
        local ahStr = realm.noCompetition and ((C.GREEN or "") .. "No comp|r") or (realm.numAuctions .. " AH")
        local profitStr = realm.profit > 0 and (G(realm.profit) .. " (" .. (realm.profitPct > 0 and "+" or "") .. realm.profitPct .. "%)") or ""

        local flags = {}
        if realm.isOutlier then table.insert(flags, (C.RED or "") .. "OUTLIER|r") end
        if realm.noCompetition then table.insert(flags, (C.GREEN or "") .. "NC|r") end
        if realm.hasPreviousSales then table.insert(flags, (C.YELLOW or "") .. realm.personalCount .. " sold|r") end

        local lbl = Lbl(f, "t", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", chk, "RIGHT", 6, 0)
        lbl:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        lbl:SetText(string.format("%-18s  %8s  TSM: %8s  %s  %s  %s",
            realmName, price, tsmPrice, ahStr, profitStr, table.concat(flags, " ")))

        local idx = i
        f:SetScript("OnClick", function()
            if onToggle then onToggle(idx) end
        end)

        y = y - REALM_H
    end

    y = y - 10

    -- Section: Research Data
    local resHdr = Acquire(scrollContent)
    resHdr:SetHeight(20)
    resHdr:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, y)
    resHdr:SetPoint("RIGHT", scrollContent, "RIGHT", 0, 0)
    Bg(resHdr):SetColorTexture(0.1, 0.1, 0.15, 0.8)
    Lbl(resHdr, "t", "GameFontNormal"):SetPoint("LEFT", 8, 0)
    resHdr._labels.t:SetText("Research Data")
    y = y - 22

    -- Personal sales by realm
    local ps = group.personalSales
    if ps and ps.sold and ps.sold > 0 then
        local sf = Acquire(scrollContent)
        sf:SetHeight(INFO_H)
        sf:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 8, y)
        sf:SetPoint("RIGHT", scrollContent, "RIGHT", -8, 0)
        local sfl = Lbl(sf, "t", "GameFontHighlightSmall")
        sfl:SetPoint("LEFT", 0, 0)
        sfl:SetText("|cffaaaaaaSales Summary:|r " .. ps.sold .. " sold, " .. ps.failed .. " expired/cancelled, avg " .. G(ps.avgPrice))
        y = y - INFO_H

        for realmNorm, rd in pairs(ps.byRealm or {}) do
            local rf = Acquire(scrollContent)
            rf:SetHeight(INFO_H)
            rf:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 20, y)
            rf:SetPoint("RIGHT", scrollContent, "RIGHT", -8, 0)
            local rfl = Lbl(rf, "t", "GameFontDisableSmall")
            rfl:SetPoint("LEFT", 0, 0)
            local failStr = rd.failed and rd.failed > 0 and (" (" .. rd.failed .. " failed)") or ""
            rfl:SetText(realmNorm .. ": " .. rd.count .. " sold, avg " .. G(rd.avg) .. failStr)
            y = y - INFO_H
        end
    else
        local nf = Acquire(scrollContent)
        nf:SetHeight(INFO_H)
        nf:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 8, y)
        nf:SetPoint("RIGHT", scrollContent, "RIGHT", -8, 0)
        Lbl(nf, "t", "GameFontDisableSmall"):SetPoint("LEFT", 0, 0)
        nf._labels.t:SetText("|cff666666No personal sales history for this item|r")
        y = y - INFO_H
    end

    y = y - 6

    -- Regional TSM data
    local regionF = Acquire(scrollContent)
    regionF:SetHeight(INFO_H)
    regionF:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 8, y)
    regionF:SetPoint("RIGHT", scrollContent, "RIGHT", -8, 0)
    local rParts = {}
    if group.regionMarketAvg then table.insert(rParts, "Market: " .. G(group.regionMarketAvg)) end
    if group.regionSaleAvg then table.insert(rParts, "Sale Avg: " .. G(group.regionSaleAvg)) end
    if group.regionSaleRate then table.insert(rParts, "Sale Rate: " .. string.format("%.1f%%", group.regionSaleRate * 100)) end
    Lbl(regionF, "t", "GameFontHighlightSmall"):SetPoint("LEFT", 0, 0)
    regionF._labels.t:SetText("|cffaaaaaaRegional:|r " .. (#rParts > 0 and table.concat(rParts, "  |  ") or "|cff666666No data|r"))
    y = y - INFO_H

    -- Outlier details
    for _, realm in ipairs(group.realms) do
        if realm.isOutlier and group.regionMarketAvg and group.regionMarketAvg > 0 then
            local of = Acquire(scrollContent)
            of:SetHeight(INFO_H)
            of:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 8, y)
            of:SetPoint("RIGHT", scrollContent, "RIGHT", -8, 0)
            local pct = math.floor(realm.blendedPrice / group.regionMarketAvg * 100)
            Lbl(of, "t", "GameFontDisableSmall"):SetPoint("LEFT", 0, 0)
            of._labels.t:SetText((C.RED or "") .. "! " .. realm.realmName .. "|r: price " .. G(realm.blendedPrice)
                .. " is " .. pct .. "% of regional avg (" .. G(group.regionMarketAvg) .. ")")
            y = y - INFO_H
        end
    end

    scrollContent:SetHeight(math.abs(y) + 20)
end
