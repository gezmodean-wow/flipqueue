-- UI/DealFinderDetail.lua
-- Renders the per-item content for the Deal Finder review phase.
-- Three render functions:
--   RenderDealFinderHeader      – pinned item name + key metrics dashboard
--   RenderDealFinderRealmTable  – fixed realm selection grid (dynamic columns)
--   RenderDealFinderResearch    – scrollable deep-dive data
local addonName, ns = ...

local UI = ns.UI

local REALM_H = 20
local INFO_H  = 16
local HDR_H   = 18

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
    -- Clear stale background from previous render
    if f._bg then f._bg:Hide() end
    -- Hide all stale labels
    for _, lbl in pairs(f._labels) do lbl:Hide() end
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

local function HideLbl(f, key)
    if f._labels and f._labels[key] then f._labels[key]:Hide() end
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
-- Pet detection helper
--------------------------

local function IsPet(group)
    if group.itemID and tostring(group.itemID):match("^pet:") then return true end
    if group.itemKey and tostring(group.itemKey):match("^pet:") then return true end
    return false
end

local function PetSpeciesID(group)
    local id = (group.itemID and tostring(group.itemID):match("^pet:(%d+)"))
        or (group.itemKey and tostring(group.itemKey):match("^pet:(%d+)"))
    return tonumber(id)
end

local function PetQuality(group)
    return tonumber((group.bonusIDs or ""):match("q(%d+)")) or 3
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
    -- Prefer scanner ilvl. Otherwise resolve from the full itemString so
    -- bonus-ID variants don't fall back to base ilvl (e.g. ilvl 253 → 44).
    if not group._ilvl then
        if group.ilvl and group.ilvl > 0 then
            group._ilvl = group.ilvl
        elseif ns.GetItemLevelFromKey then
            group._ilvl = ns:GetItemLevelFromKey(group.itemKey, numID)
        else
            group._ilvl = 0
        end
    end
end

-----------------------------------------------------------------
-- 1.  RENDER ITEM HEADER  (pinned 90px area at top)
-----------------------------------------------------------------

function UI:RenderDealFinderHeader(headerFrame, group)
    if not headerFrame._labels then headerFrame._labels = {} end
    for _, lbl in pairs(headerFrame._labels) do lbl:Hide() end
    ResolveItemInfo(group)

    local C = ns.COLORS or {}

    -- Item icon + name + ilvl
    local iconStr = group.icon and ("|T" .. group.icon .. ":16:16:0:0|t ") or ""
    local ilvlStr = (group._ilvl and group._ilvl > 0) and ("  |cff888888iLvl " .. group._ilvl .. "|r") or ""
    local nameLbl = Lbl(headerFrame, "name", "GameFontNormal")
    nameLbl:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 8, -4)
    nameLbl:SetText(iconStr .. QCN(group.name, group.quality) .. ilvlStr)

    -- Item tooltip on hover (pet-aware)
    headerFrame:EnableMouse(true)
    local isPet   = IsPet(group)
    local numID   = not isPet and tonumber(group.itemID) or nil
    local species = PetSpeciesID(group)

    headerFrame:SetScript("OnEnter", function(self)
        if isPet and species and BattlePetToolTip_Show then
            BattlePetToolTip_Show(species, 25, PetQuality(group), 0, 0, 0)
            if BattlePetTooltip then
                BattlePetTooltip:ClearAllPoints()
                BattlePetTooltip:SetPoint("TOPLEFT", self, "BOTTOMRIGHT")
            end
        elseif numID and numID > 0 then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            ns:SetTooltipItem(GameTooltip, group.itemKey, numID)
        end
    end)
    headerFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if BattlePetTooltip and BattlePetTooltip.Hide then BattlePetTooltip:Hide() end
    end)

    -- Denied badge
    local badge = Lbl(headerFrame, "badge", "GameFontNormal")
    badge:SetPoint("LEFT", nameLbl, "RIGHT", 12, 0)
    badge:SetText(group.denied and ((C.RED or "") .. "SKIPPED|r") or "")

    -- Separator
    if not headerFrame._sep then
        headerFrame._sep = headerFrame:CreateTexture(nil, "ARTWORK")
        headerFrame._sep:SetHeight(1)
        headerFrame._sep:SetColorTexture(0.3, 0.3, 0.4, 0.3)
    end
    headerFrame._sep:ClearAllPoints()
    headerFrame._sep:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 8, -22)
    headerFrame._sep:SetPoint("RIGHT", headerFrame, "RIGHT", -8, 0)
    headerFrame._sep:Show()

    -- Key metrics dashboard (2 rows)
    local ps = group.personalSales or {}
    local L1, V1 = -26, -38   -- Row 1: market context
    local L2, V2 = -52, -64   -- Row 2: personal / cost

    -- Helper to place a stat
    local function Stat(key, x, ly, vy, label, value)
        local l = Lbl(headerFrame, key .. "l", "GameFontDisableSmall")
        l:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", x, ly); l:SetText(label)
        local v = Lbl(headerFrame, key .. "v", "GameFontHighlight")
        v:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", x, vy); v:SetText(value)
    end

    -- Row 1: Region Market | Sale Avg | Sale Rate | Sold/Day
    Stat("r1a", 10,  L1, V1, "REGION MARKET", G(group.regionMarketAvg))
    Stat("r1b", 115, L1, V1, "SALE AVG", G(group.regionSaleAvg))

    local rateStr = "-"
    if group.regionSaleRate then
        local pct = group.regionSaleRate * 100
        local col = pct >= 10 and (C.GREEN or "") or pct >= 5 and (C.YELLOW or "") or (C.RED or "")
        rateStr = col .. string.format("%.1f%%", pct) .. "|r"
    end
    Stat("r1c", 210, L1, V1, "SALE RATE", rateStr)

    local soldDayStr = "-"
    if group.regionSoldPerDay and group.regionSoldPerDay > 0 then
        soldDayStr = string.format("%.1f", group.regionSoldPerDay)
    end
    Stat("r1d", 295, L1, V1, "SOLD/DAY", soldDayStr)

    -- Row 2: Avg Buy Cost | My Sell Price | Sold/Failed | Qty
    local buyStr = "|cff666666None|r"
    if group.smartAvgBuy and group.smartAvgBuy > 0 then
        buyStr = G(group.smartAvgBuy)
        -- Show estimated profit next to buy price if we have best realm
        if group.realms and group.realms[1] then
            local best = group.realms[1]
            if best.realProfit then
                local profCol = best.realProfit > 0 and (C.GREEN or "") or (C.RED or "")
                buyStr = buyStr .. " " .. profCol .. "(" .. ns:FormatPctNum(best.realProfitPct or 0) .. "% est)|r"
            end
        end
    end
    Stat("r2a", 10,  L2, V2, "AVG BUY COST", buyStr)

    local sellStr = "|cff666666None|r"
    if ps.avgPrice and ps.avgPrice > 0 then
        local diff = ps.avgPrice - (group.regionMarketAvg or 0)
        local pctDiff = (group.regionMarketAvg and group.regionMarketAvg > 0)
            and math.floor(diff / group.regionMarketAvg * 100) or 0
        local col = pctDiff >= 0 and (C.GREEN or "") or (C.RED or "")
        sellStr = G(ps.avgPrice) .. " " .. col .. "(" .. (pctDiff >= 0 and "+" or "") .. ns:FormatPctNum(pctDiff) .. "%)|r"
    end
    Stat("r2b", 150, L2, V2, "MY SELL PRICE", sellStr)

    local salesStr = "|cff666666None|r"
    local hasAny = (ps.sold or 0) + (ps.failed or 0) + (ps.posted or 0) > 0
    if hasAny then
        local bits = {}
        if (ps.sold or 0) > 0 then table.insert(bits, (C.GREEN or "") .. ps.sold .. "s|r") end
        if (ps.failed or 0) > 0 then table.insert(bits, (C.RED or "") .. ps.failed .. "f|r") end
        if (ps.posted or 0) > 0 then table.insert(bits, (C.YELLOW or "") .. ps.posted .. "p|r") end
        salesStr = table.concat(bits, "/")
    end
    Stat("r2c", 290, L2, V2, "SOLD/FAIL/POST", salesStr)

    local invParts = {}
    if group.sources then
        local byLoc = {}
        for _, src in ipairs(group.sources) do
            byLoc[src.location or "bags"] = (byLoc[src.location or "bags"] or 0) + src.quantity
        end
        for loc, qty in pairs(byLoc) do table.insert(invParts, qty .. " " .. loc) end
    end
    Stat("r2d", 420, L2, V2, "QTY", (group.quantity or 0)
        .. (#invParts > 0 and ("  |cff888888(" .. table.concat(invParts, ", ") .. ")|r") or ""))

    -- Outlier warning
    local warn = Lbl(headerFrame, "outlier", "GameFontDisableSmall")
    warn:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 10, -78)
    local outlierMult = ns.db and ns.db.settings.dfOutlierMultiplier or 1.5
    local hasOutlier = false
    for _, r in ipairs(group.realms) do
        if r.isOutlier then hasOutlier = true; break end
    end
    if hasOutlier then
        warn:SetText((C.RED or "") .. "! Some realms flagged as outliers (>" .. math.floor(outlierMult * 100) .. "% of regional avg)|r")
    else
        warn:SetText("")
    end
end

-----------------------------------------------------------------
-- 2.  RENDER REALM TABLE  (fixed / pinned area, dynamic cols)
--     Returns: total pixel height consumed.
-----------------------------------------------------------------

local SORT_LABELS = {
    profit         = "Spread vs Market",
    noCompetition  = "No Competition",
    previousSales  = "Previous Sales",
    population     = "Population",
}

function UI:RenderDealFinderRealmTable(parent, group, numCols, onToggle)
    local C = ns.COLORS or {}
    numCols = numCols or 2
    local y = 0

    -- Measure parent width for pixel-positioned columns
    local parentW = parent:GetWidth()
    if parentW <= 0 then parentW = 600 end
    local margin, gap = 4, 4
    local colW = math.floor((parentW - margin * 2 - gap * (numCols - 1)) / numCols)

    -- Selection count + over-selection check
    local numSelected, qty = 0, group.quantity or 1
    for _, r in ipairs(group.realms) do
        if r._selected ~= false then numSelected = numSelected + 1 end
    end
    local overSel = numSelected > qty

    -- Section header
    local secHdr = Acquire(parent)
    secHdr:SetHeight(20); secHdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    secHdr:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    Bg(secHdr):SetColorTexture(0.1, 0.1, 0.15, 0.8)
    local selTxt = numSelected .. " of " .. #group.realms .. " selected"
    if overSel then
        selTxt = selTxt .. "  " .. (C.RED or "") .. "OVER-SELECTED (qty " .. qty .. ")|r"
    end
    local secLbl = Lbl(secHdr, "t", "GameFontNormal")
    secLbl:SetPoint("LEFT", 8, 0)
    secLbl:SetText("Target Realms  |cff888888(" .. selTxt .. ")|r")
    y = y - 20

    -- Legend / column field key
    local sortKey = ns.db and ns.db.settings.dfPriorityOrder and ns.db.settings.dfPriorityOrder[1] or "profit"
    local legend = Acquire(parent)
    legend:SetHeight(HDR_H); legend:SetPoint("TOPLEFT", parent, "TOPLEFT", margin, y)
    legend:SetPoint("RIGHT", parent, "RIGHT", -margin, 0)
    Bg(legend):SetColorTexture(0.06, 0.06, 0.1, 0.6)
    local legLbl = Lbl(legend, "t", "GameFontDisableSmall")
    legLbl:SetPoint("LEFT", 4, 0)
    local pctLabel = (group.smartAvgBuy and group.smartAvgBuy > 0) and "Profit" or "vs Market"
    legLbl:SetText("|cff666666Sorted by: " .. (SORT_LABELS[sortKey] or sortKey)
        .. "    Format: [sel] Realm  ·  Price  ·  " .. pctLabel .. "  ·  Flags|r")
    y = y - HDR_H

    -- Realm rows in N-column grid
    local realmStartY = y
    local numRealms = #group.realms
    local numRows   = math.ceil(numRealms / numCols)

    -- Adaptive name truncation based on column width
    local maxNameLen = math.max(8, math.floor(colW / 8) - 16)

    for i, realm in ipairs(group.realms) do
        local col = (i - 1) % numCols
        local row = math.floor((i - 1) / numCols)
        local isSel = (realm._selected ~= false)

        local f = Acquire(parent)
        f:SetHeight(REALM_H)
        f:SetWidth(colW)
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", margin + col * (colW + gap), realmStartY - row * REALM_H)
        f:EnableMouse(true)

        local bg = Bg(f)
        bg:SetColorTexture(isSel and 0.1 or 0.04, isSel and 0.22 or 0.04, isSel and 0.1 or 0.06, isSel and 0.6 or 0.2)

        -- Checkbox
        local chk = Lbl(f, "chk", "GameFontNormal")
        chk:SetPoint("LEFT", f, "LEFT", 4, 0)
        chk:SetText(isSel and ((C.GREEN or "") .. "[x]|r") or "|cff555555[ ]|r")

        -- Compact info
        local rn = realm.realmName or ""
        if #rn > maxNameLen then rn = rn:sub(1, maxNameLen - 2) .. ".." end

        -- Show real profit % if buy cost known, otherwise vs market spread
        local spreadStr = ""
        local sp = realm.realProfitPct or realm.profitPct
        if sp and sp > 0 then
            spreadStr = (C.GREEN or "") .. "+" .. ns:FormatPctNum(sp) .. "%|r"
        elseif sp and sp < 0 then
            spreadStr = (C.RED or "") .. ns:FormatPctNum(sp) .. "%|r"
        end

        local flags = {}
        if realm.isOutlier then table.insert(flags, (C.RED or "") .. "OL|r") end
        if realm.noCompetition then table.insert(flags, (C.GREEN or "") .. "NC|r") end
        if realm.hasPreviousSales then table.insert(flags, (C.YELLOW or "") .. (realm.personalCount or 0) .. "s|r") end

        local lbl = Lbl(f, "t", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", chk, "RIGHT", 4, 0)
        lbl:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        lbl:SetWordWrap(false)
        lbl:SetText(rn .. "  " .. G(realm.blendedPrice) .. "  " .. spreadStr
            .. (#flags > 0 and ("  " .. table.concat(flags, " ")) or ""))

        -- Full-detail tooltip on hover
        local ref = realm
        f:SetScript("OnEnter", function(s)
            Bg(s):SetColorTexture(0.12, 0.12, 0.2, 0.5)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ref.realmName, 1, 1, 1)
            GameTooltip:AddDoubleLine("Blended Price", G(ref.blendedPrice), 0.7,0.7,0.7, 1,1,1)
            GameTooltip:AddDoubleLine("TSM Price", G(ref.tsmPrice), 0.7,0.7,0.7, 1,1,1)
            GameTooltip:AddDoubleLine("AH Listings", tostring(ref.numAuctions or 0), 0.7,0.7,0.7, 1,1,1)
            local baseline = group.regionMarketAvg or 0
            if baseline > 0 then
                GameTooltip:AddDoubleLine("vs Regional Market",
                    G(ref.profit) .. " (" .. ((ref.profitPct or 0) >= 0 and "+" or "") .. ns:FormatPctNum(ref.profitPct or 0) .. "%)",
                    0.7,0.7,0.7, (ref.profit or 0) > 0 and 0.3 or 1, (ref.profit or 0) > 0 and 1 or 0.3, 0.3)
            end
            if ref.hasPreviousSales then
                GameTooltip:AddDoubleLine("Personal Sales", (ref.personalCount or 0) .. " sold", 0.7,0.7,0.7, 1,0.82,0)
            end
            if ref.personalAvg and ref.personalAvg > 0 then
                GameTooltip:AddDoubleLine("My Avg on Realm", G(ref.personalAvg), 0.7,0.7,0.7, 1,1,1)
            end
            if ref.realProfit then
                local rp = ref.realProfit
                GameTooltip:AddDoubleLine("Est. Profit (vs buy cost)",
                    G(rp) .. " (" .. ((ref.realProfitPct or 0) >= 0 and "+" or "") .. ns:FormatPctNum(ref.realProfitPct or 0) .. "%)",
                    0.7,0.7,0.7, rp > 0 and 0.3 or 1, rp > 0 and 1 or 0.3, 0.3)
            end
            GameTooltip:AddDoubleLine("Data Source", ref.dataQuality == "perRealm" and "Per-Realm TSM" or "Regional Fallback",
                0.7,0.7,0.7, 0.6,0.6,0.6)
            if ref.isOutlier then
                GameTooltip:AddLine("OUTLIER - Price exceeds regional threshold", 1, 0.3, 0.3)
            end
            if ref.noCompetition then
                GameTooltip:AddLine("No competition on AH", 0.3, 1, 0.3)
            end
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function(s)
            Bg(s):SetColorTexture(isSel and 0.1 or 0.04, isSel and 0.22 or 0.04, isSel and 0.1 or 0.06, isSel and 0.6 or 0.2)
            GameTooltip:Hide()
        end)

        local idx = i
        f:SetScript("OnClick", function()
            if onToggle then onToggle(idx) end
        end)
    end

    y = realmStartY - numRows * REALM_H

    return math.abs(y) + 4  -- total height with small bottom pad
end

-----------------------------------------------------------------
-- 3.  RENDER RESEARCH  (compact scrollable data)
--     Merges sales + regional into summary lines, then a proper
--     aligned per-realm comparison table, then compact analysis.
--     Sets parent height automatically.
-----------------------------------------------------------------

-- Column layout for per-realm comparison table
local RCOL = {
    {x = 2,   w = 88,  k = "name",   align = "LEFT"},
    {x = 92,  w = 58,  k = "tsm",    align = "RIGHT"},
    {x = 154, w = 58,  k = "blend",  align = "RIGHT"},
    {x = 216, w = 24,  k = "ah",     align = "RIGHT"},
    {x = 244, w = 32,  k = "sold",   align = "RIGHT"},
    {x = 280, w = 36,  k = "src",    align = "LEFT"},
    {x = 320, w = 44,  k = "spread", align = "RIGHT"},
}
local RCOL_LABELS = {name="Realm", tsm="TSM", blend="Blended", ah="AH", sold="Sold", src="Data", spread="vs Mkt"}

function UI:RenderDealFinderResearch(parent, group)
    local C = ns.COLORS or {}
    local y = -4

    -- Helper: text row
    local function Row(text, indent, font)
        local f = Acquire(parent)
        f:SetHeight(INFO_H); f:SetPoint("TOPLEFT", parent, "TOPLEFT", indent or 8, y)
        f:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
        local l = Lbl(f, "t", font or "GameFontHighlightSmall")
        l:SetPoint("LEFT", 0, 0); l:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        l:SetWordWrap(false); l:SetText(text)
        y = y - INFO_H
    end

    -- Helper: section header
    local function SecHdr(title)
        local h = Acquire(parent)
        h:SetHeight(18); h:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        h:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        Bg(h):SetColorTexture(0.1, 0.1, 0.15, 0.8)
        Lbl(h, "t", "GameFontNormal"):SetPoint("LEFT", 8, 0)
        h._labels.t:SetText(title)
        y = y - 20
    end

    -- Helper: table row with positioned columns
    local function TblRow(data, font, bgCol)
        local f = Acquire(parent)
        f:SetHeight(INFO_H); f:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
        f:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
        f:SetClipsChildren(true)
        if bgCol then Bg(f):SetColorTexture(unpack(bgCol)) end
        for _, col in ipairs(RCOL) do
            local l = Lbl(f, col.k, font or "GameFontHighlightSmall")
            l:SetPoint("LEFT", f, "LEFT", col.x, 0); l:SetWidth(col.w)
            l:SetJustifyH(col.align); l:SetWordWrap(false)
            l:SetText(data[col.k] or "")
        end
        y = y - INFO_H
    end

    -- Fetch full research record from ItemResearch (same data as Research page)
    local record
    if ns.ItemResearch and ns.ItemResearch.GetItemResearch then
        local ok, res = pcall(ns.ItemResearch.GetItemResearch, ns.ItemResearch, group.itemKey, group.name)
        if ok and res then record = res end
    end

    -------------------------------------------------------
    -- Summary badges (inventory, active, sold, failed)
    -------------------------------------------------------
    local badges = {}
    if record then
        if (record.totalInventory or 0) > 0 then
            table.insert(badges, (C.GREEN or "") .. record.totalInventory .. " in inventory|r")
        end
        if record.activeAuctions and #record.activeAuctions > 0 then
            table.insert(badges, (C.YELLOW or "") .. #record.activeAuctions .. " active auctions|r")
        end
        if record.salesSummary and record.salesSummary.count > 0 then
            table.insert(badges, (C.CYAN or "") .. record.salesSummary.count .. " sold|r")
        end
        if record.failureSummary then
            local fc = (record.failureSummary.expiredCount or 0) + (record.failureSummary.cancelledCount or 0)
            if fc > 0 then table.insert(badges, (C.RED or "") .. fc .. " failed|r") end
        end
    end
    if #badges > 0 then
        Row(table.concat(badges, "  ·  "))
    end

    -------------------------------------------------------
    -- TSM Regional Data
    -------------------------------------------------------
    local regParts = {}
    if group.regionMarketAvg and group.regionMarketAvg > 0 then table.insert(regParts, "Market: " .. G(group.regionMarketAvg)) end
    if group.regionSaleAvg and group.regionSaleAvg > 0 then table.insert(regParts, "Sale Avg: " .. G(group.regionSaleAvg)) end
    if group.regionSaleRate then
        local pct = group.regionSaleRate * 100
        local col = pct >= 10 and (C.GREEN or "") or pct >= 5 and (C.YELLOW or "") or (C.RED or "")
        table.insert(regParts, "Rate: " .. col .. string.format("%.1f%%", pct) .. "|r")
    end
    if group.regionSoldPerDay and group.regionSoldPerDay > 0 then
        table.insert(regParts, "Sold/Day: " .. string.format("%.1f", group.regionSoldPerDay))
    end
    if group.smartAvgBuy and group.smartAvgBuy > 0 then
        table.insert(regParts, "Buy: " .. G(group.smartAvgBuy))
    end
    if #regParts > 0 then
        Row("|cffaaaaaaRegional:|r " .. table.concat(regParts, "  ·  "))
    end
    y = y - 2

    -------------------------------------------------------
    -- Per-Realm Comparison Table
    -------------------------------------------------------
    SecHdr("Realm Comparison")
    local colHdrF = Acquire(parent)
    colHdrF:SetHeight(INFO_H); colHdrF:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    colHdrF:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    colHdrF:SetClipsChildren(true)
    Bg(colHdrF):SetColorTexture(0.08, 0.08, 0.12, 0.6)
    for _, col in ipairs(RCOL) do
        local l = Lbl(colHdrF, col.k, "GameFontDisableSmall")
        l:SetPoint("LEFT", colHdrF, "LEFT", col.x, 0); l:SetWidth(col.w)
        l:SetJustifyH(col.align); l:SetWordWrap(false)
        l:SetText("|cff888888" .. RCOL_LABELS[col.k] .. "|r")
    end
    y = y - INFO_H

    for ri, realm in ipairs(group.realms) do
        local rn = realm.realmName or "?"
        if #rn > 13 then rn = rn:sub(1, 11) .. ".." end
        local sp = realm.realProfitPct or realm.profitPct
        local spreadStr = ""
        if sp and sp ~= 0 then
            local col = sp > 0 and (C.GREEN or "") or (C.RED or "")
            spreadStr = col .. (sp > 0 and "+" or "") .. ns:FormatPctNum(sp) .. "%|r"
        end
        local soldStr = (realm.personalCount and realm.personalCount > 0)
            and ((C.GREEN or "") .. realm.personalCount .. "|r") or "-"
        TblRow({
            name = rn, tsm = G(realm.tsmPrice), blend = G(realm.blendedPrice),
            ah = tostring(realm.numAuctions or 0), sold = soldStr,
            src = (realm.dataQuality == "perRealm") and "Realm" or "|cffaa6666Rgn|r",
            spread = spreadStr,
        }, nil, ri % 2 == 0 and {0.06, 0.06, 0.08, 0.3} or nil)
    end
    y = y - 4

    -------------------------------------------------------
    -- Inventory (from research record)
    -------------------------------------------------------
    if record and record.inventory and #record.inventory > 0 then
        SecHdr("Inventory (" .. (record.totalInventory or 0) .. ")")
        for i, inv in ipairs(record.inventory) do
            local owner = inv.charKey or inv.owner or "?"
            local name = owner:match("^(.-)%-") or owner
            local loc = inv.location or ""
            local qty = inv.quantity or 0
            Row("  " .. name .. "  |cffaaaaaa" .. loc .. "|r  x" .. qty, 12,
                i % 2 == 0 and "GameFontHighlightSmall" or "GameFontDisableSmall")
        end
        y = y - 2
    end

    -------------------------------------------------------
    -- Active Auctions (from research record)
    -------------------------------------------------------
    if record and record.activeAuctions and #record.activeAuctions > 0 then
        SecHdr("Active Auctions (" .. #record.activeAuctions .. ")")
        for i, aa in ipairs(record.activeAuctions) do
            local realm = aa.targetRealm or "?"
            local price = aa.postedPrice or aa.expectedPrice or ""
            if type(price) == "number" then price = G(price) end
            local seller = aa.charKey and (aa.charKey:match("^(.-)%-") or aa.charKey) or ""
            Row("  " .. realm .. "  " .. tostring(price) .. "  |cffaaaaaa" .. seller .. "|r", 12,
                i % 2 == 0 and "GameFontHighlightSmall" or "GameFontDisableSmall")
        end
        y = y - 2
    end

    -------------------------------------------------------
    -- Failed Sales (from research record)
    -------------------------------------------------------
    if record and record.failures and #record.failures > 0 then
        local fs = record.failureSummary or {}
        local fLabel = (fs.expiredCount or 0) .. " expired"
        if (fs.cancelledCount or 0) > 0 then fLabel = fLabel .. ", " .. fs.cancelledCount .. " cancelled" end
        SecHdr("Failed Sales (" .. fLabel .. ")")
        local shown = math.min(#record.failures, 10)
        for i = 1, shown do
            local fail = record.failures[i]
            local realm = fail.targetRealm or "?"
            local price = fail.postedPrice or ""
            if type(price) == "number" then price = G(price) end
            local status = fail.auctionStatus or fail.saleOutcome or "?"
            local statusCol = status == "expired" and (C.RED or "") or (C.ORANGE or "")
            Row("  " .. realm .. "  " .. tostring(price) .. "  " .. statusCol .. status .. "|r", 12, "GameFontDisableSmall")
        end
        if #record.failures > shown then
            Row("  |cff888888..." .. (#record.failures - shown) .. " more|r", 12, "GameFontDisableSmall")
        end
        y = y - 2
    end

    -------------------------------------------------------
    -- Recent Sales (from research record)
    -------------------------------------------------------
    if record and record.sales and #record.sales > 0 then
        local ss = record.salesSummary or {}
        SecHdr("Sales (" .. (ss.count or #record.sales) .. " total, avg " .. G(ss.avgPrice) .. ")")
        local shown = math.min(#record.sales, 10)
        for i = 1, shown do
            local sale = record.sales[i]
            local realm = sale.targetRealm or "?"
            local price = sale.soldPrice or sale.postedPrice or ""
            if type(price) == "number" then price = G(price) end
            local seller = sale.charKey and (sale.charKey:match("^(.-)%-") or sale.charKey) or ""
            Row("  " .. realm .. "  " .. (C.GREEN or "") .. tostring(price) .. "|r  |cffaaaaaa" .. seller .. "|r", 12, "GameFontDisableSmall")
        end
        y = y - 2
    end

    -------------------------------------------------------
    -- Item details footer
    -------------------------------------------------------
    local detParts = {}
    if group._ilvl and group._ilvl > 0 then table.insert(detParts, "iLvl: " .. group._ilvl) end
    if group.bonusIDs and group.bonusIDs ~= "" then table.insert(detParts, "Bonus: " .. group.bonusIDs) end
    if group.modifiers and group.modifiers ~= "" then table.insert(detParts, "Mods: " .. group.modifiers) end
    if #detParts > 0 then
        table.insert(detParts, 1, "Key: " .. (group.itemKey or "-"))
        Row("|cff888888" .. table.concat(detParts, " · ") .. "|r", 8, "GameFontDisableSmall")
    end

    parent:SetHeight(math.abs(y) + 10)
end
