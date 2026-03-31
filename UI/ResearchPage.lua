-- UI/ResearchPage.lua
-- Item Research page: two-panel layout with item list (left) and detail (right)
local addonName, ns = ...

local UI = ns.UI
local tableContainer = UI.tableContainer

-- ==========================================
-- STATE
-- ==========================================

local selectedItemKey = nil
local selectedItemName = nil
local currentSearchText = ""
local currentFilter = "all"  -- "all", "inventory", "sales", "deals"
local cachedIndex = nil
local searchTimer = nil

-- ==========================================
-- PAGE FRAME
-- ==========================================

local researchPage = CreateFrame("Frame", nil, tableContainer)
researchPage:SetAllPoints()
researchPage:Hide()

-- ==========================================
-- LEFT PANEL
-- ==========================================

local leftPanel = CreateFrame("Frame", nil, researchPage)

-- Search box
local searchBox = CreateFrame("EditBox", nil, leftPanel, "InputBoxTemplate")
searchBox:SetHeight(20)
searchBox:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 8, -6)
searchBox:SetPoint("RIGHT", leftPanel, "RIGHT", -8, 0)
searchBox:SetAutoFocus(false)
searchBox:SetFontObject("ChatFontSmall")

local searchPlaceholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
searchPlaceholder:SetText("Search items...")
searchPlaceholder:SetTextColor(0.4, 0.4, 0.4)

searchBox:SetScript("OnTextChanged", function(self, userInput)
    local text = self:GetText()
    searchPlaceholder:SetShown(text == "")
    if not userInput then return end
    if searchTimer then searchTimer:Cancel() end
    searchTimer = C_Timer.NewTimer(0.15, function()
        searchTimer = nil
        currentSearchText = text:lower()
        UI:RefreshResearchPage()
    end)
end)
searchBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
searchBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)

-- Filter row
local filterBar = CreateFrame("Frame", nil, leftPanel)
filterBar:SetHeight(22)
filterBar:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -4)
filterBar:SetPoint("RIGHT", leftPanel, "RIGHT", -4, 0)

local function CreateFilterBtn(label, filterKey, parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(18)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetWidth(btn.text:GetStringWidth() + 14)
    btn._filterKey = filterKey
    btn:SetScript("OnEnter", function(self)
        if not self._active then self:SetBackdropColor(0.2, 0.2, 0.3, 1) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self._active then
            self:SetBackdropColor(0.2, 0.4, 0.2, 1)
        else
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        end
    end)
    btn:SetScript("OnClick", function(self)
        currentFilter = filterKey
        UI:RefreshResearchPage()
    end)
    return btn
end

local filterBtns = {}
local filterDefs = {
    { "All",       "all" },
    { "Inventory", "inventory" },
    { "Sales",     "sales" },
    { "Deals",     "deals" },
}
for i, def in ipairs(filterDefs) do
    local btn = CreateFilterBtn(def[1], def[2], filterBar)
    if i == 1 then
        btn:SetPoint("LEFT", filterBar, "LEFT", 4, 0)
    else
        btn:SetPoint("LEFT", filterBtns[i - 1], "RIGHT", 2, 0)
    end
    filterBtns[i] = btn
end

local function UpdateFilterHighlights()
    for _, btn in ipairs(filterBtns) do
        if btn._filterKey == currentFilter then
            btn._active = true
            btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
            btn.text:SetTextColor(1, 1, 1)
        else
            btn._active = false
            btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
            btn.text:SetTextColor(0.6, 0.6, 0.6)
        end
    end
end

-- Item list table
local ITEM_LIST_COLUMNS = {
    { key = "name",    label = "Item",    width = 170, sortable = true },
    { key = "qty",     label = "Qty",     width = 35,  align = "CENTER", sortable = true },
    { key = "sources", label = "Info",    width = 55,  align = "CENTER", sortable = true },
}

local itemListTable = UI:CreateScrollTable(leftPanel, ITEM_LIST_COLUMNS)
UI._researchItemTable = itemListTable

-- ==========================================
-- DIVIDER
-- ==========================================

local divider = researchPage:CreateTexture(nil, "ARTWORK")
divider:SetWidth(1)
divider:SetColorTexture(0.3, 0.3, 0.4, 0.5)

-- ==========================================
-- RIGHT PANEL
-- ==========================================

local rightPanel = CreateFrame("Frame", nil, researchPage)

local detailScroll = CreateFrame("ScrollFrame", nil, rightPanel, "UIPanelScrollFrameTemplate")
detailScroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, 0)
detailScroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -22, 0)

local detailContent = CreateFrame("Frame", nil, detailScroll)
detailContent:SetWidth(400)
detailContent:SetHeight(1)  -- grows dynamically
detailScroll:SetScrollChild(detailContent)

-- Empty state
local emptyLabel = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
emptyLabel:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
emptyLabel:SetText("|cff888888Select an item from the list|r")

-- ==========================================
-- FRAME POOL for detail rendering
-- ==========================================

local allDetailFrames = {}
local detailFrameIdx = 0

local function ResetDetailFrames()
    for _, f in ipairs(allDetailFrames) do
        f:Hide()
        f:ClearAllPoints()
    end
    detailFrameIdx = 0
end

local function AcquireFrame()
    detailFrameIdx = detailFrameIdx + 1
    local f = allDetailFrames[detailFrameIdx]
    if not f then
        f = CreateFrame("Frame", nil, detailContent)
        allDetailFrames[detailFrameIdx] = f
    end
    f:SetParent(detailContent)
    -- Hide all reusable children from previous render type to prevent bleed-through
    if f._bg then f._bg:Hide() end
    if f._label then f._label:Hide() end
    if f._value then f._value:Hide() end
    if f._icon then f._icon:Hide() end
    if f._name then f._name:Hide() end
    if f._sub then f._sub:Hide() end
    if f._cols then
        for _, col in ipairs(f._cols) do col:Hide() end
    end
    f:Show()
    return f
end

-- FontString pool (reusable labels)
local allFontStrings = {}
local fontStringIdx = 0

local function ResetFontStrings()
    for _, fs in ipairs(allFontStrings) do
        fs:Hide()
    end
    fontStringIdx = 0
end

local function AcquireFontString(parent, template)
    fontStringIdx = fontStringIdx + 1
    local fs = allFontStrings[fontStringIdx]
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
        allFontStrings[fontStringIdx] = fs
    else
        fs:SetParent(parent)
        fs:SetFontObject(template or "GameFontNormalSmall")
    end
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

-- ==========================================
-- SECTION RENDERING
-- ==========================================

local SECTION_HEADER_HEIGHT = 20
local ROW_HEIGHT = 16
local SECTION_PAD = 8
local INNER_PAD = 6

local function RenderSectionHeader(yOffset, title)
    local f = AcquireFrame()
    f:SetHeight(SECTION_HEADER_HEIGHT)
    f:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, yOffset)
    f:SetPoint("RIGHT", detailContent, "RIGHT", 0, 0)

    if not f._bg then
        f._bg = f:CreateTexture(nil, "BACKGROUND")
        f._bg:SetAllPoints()
    end
    f._bg:SetColorTexture(0.15, 0.15, 0.2, 0.8)
    f._bg:Show()

    if not f._label then
        f._label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f._label:SetPoint("LEFT", f, "LEFT", 6, 0)
    end
    f._label:SetText(ns.COLORS.YELLOW .. title .. "|r")
    f._label:Show()

    return yOffset - SECTION_HEADER_HEIGHT
end

local function RenderKeyValue(yOffset, label, value, labelColor, valueColor)
    local f = AcquireFrame()
    f:SetHeight(ROW_HEIGHT)
    f:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, yOffset)
    f:SetPoint("RIGHT", detailContent, "RIGHT", 0, 0)

    if not f._label then
        f._label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f._label:SetPoint("LEFT", f, "LEFT", 12, 0)
        f._label:SetWidth(110)
        f._label:SetJustifyH("LEFT")
    end
    f._label:SetText(labelColor and (labelColor .. label .. "|r") or label)
    f._label:SetTextColor(0.6, 0.6, 0.6)
    f._label:Show()

    if not f._value then
        f._value = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f._value:SetPoint("LEFT", f._label, "RIGHT", 4, 0)
        f._value:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        f._value:SetJustifyH("LEFT")
    end
    f._value:SetText(valueColor and (valueColor .. tostring(value) .. "|r") or tostring(value))
    f._value:SetTextColor(1, 1, 1)
    f._value:Show()

    return yOffset - ROW_HEIGHT
end

-- Proportional widths: weights are scaled to fill the available panel width.
-- e.g. weights {3, 2, 2, 2} on a 360px panel → ~120, 80, 80, 80 minus padding.
local function RenderTableRow(yOffset, cols, weights)
    local f = AcquireFrame()
    f:SetHeight(ROW_HEIGHT)
    f:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, yOffset)
    f:SetPoint("RIGHT", detailContent, "RIGHT", 0, 0)

    local availW = detailContent:GetWidth() - 18  -- 12 left pad + 6 right pad
    if availW < 60 then availW = 300 end  -- fallback before first layout
    local totalWeight = 0
    for _, w in ipairs(weights) do totalWeight = totalWeight + (w or 1) end

    if not f._cols then f._cols = {} end
    local xOff = 12
    for i, text in ipairs(cols) do
        if not f._cols[i] then
            f._cols[i] = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f._cols[i]:SetWordWrap(false)
            f._cols[i]:SetNonSpaceWrap(false)
        end
        local colW = math.floor(availW * ((weights[i] or 1) / totalWeight))
        local fs = f._cols[i]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", f, "LEFT", xOff, 0)
        fs:SetWidth(colW)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:Show()
        xOff = xOff + colW
    end
    for i = #cols + 1, #f._cols do
        f._cols[i]:Hide()
    end

    return yOffset - ROW_HEIGHT
end

-- ==========================================
-- DETAIL PANEL SECTIONS
-- ==========================================

local function FormatGold(copper)
    return ns:FormatGold(copper or 0)
end

local function FormatPrice(val)
    if type(val) == "number" then return FormatGold(val) end
    if type(val) == "string" and val ~= "" then return val end
    return "-"
end

local function ClassColorName(charKey, class)
    if not charKey then return "" end
    if class and UI._CLASS_COLORS and UI._CLASS_COLORS[class] then
        return "|cff" .. UI._CLASS_COLORS[class] .. charKey .. "|r"
    end
    return charKey
end

local LOCATION_LABELS = {
    bags = "Bags", bank = "Bank", reagent = "Reagent",
    warbank = "Warbank", guildbank = "Guild Bank",
}

local function LocationStr(locations)
    if not locations then return "" end
    local parts = {}
    for loc, qty in pairs(locations) do
        if qty and qty > 0 then
            table.insert(parts, (LOCATION_LABELS[loc] or loc))
        end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

-- Item Header
local function RenderItemHeader(record, yOffset)
    local f = AcquireFrame()
    f:SetHeight(44)
    f:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, yOffset)
    f:SetPoint("RIGHT", detailContent, "RIGHT", 0, 0)

    -- Icon
    if not f._icon then
        f._icon = f:CreateTexture(nil, "ARTWORK")
        f._icon:SetSize(32, 32)
        f._icon:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
    end
    if record.icon then
        f._icon:SetTexture(record.icon)
        f._icon:Show()
    else
        f._icon:Hide()
    end

    -- Name
    if not f._name then
        f._name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f._name:SetPoint("LEFT", f._icon, "RIGHT", 8, 4)
        f._name:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        f._name:SetJustifyH("LEFT")
    end
    local displayName = record.name or "Unknown"
    if record.quality then
        displayName = UI._QualityColorName(displayName, record.quality)
    end
    f._name:SetText(displayName)
    f._name:Show()

    -- Subtitle (itemID)
    if not f._sub then
        f._sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f._sub:SetPoint("TOPLEFT", f._name, "BOTTOMLEFT", 0, -2)
        f._sub:SetJustifyH("LEFT")
    end
    local subParts = {}
    if record.itemID then table.insert(subParts, "ID: " .. tostring(record.itemID)) end
    f._sub:SetText("|cff888888" .. table.concat(subParts, "  ") .. "|r")
    f._sub:Show()

    return yOffset - 44
end

-- Summary badges
local function RenderSummaryBadges(record, yOffset)
    local parts = {}
    if record.totalInventory > 0 then
        table.insert(parts, ns.COLORS.GREEN .. record.totalInventory .. " in inventory|r")
    end
    if #record.activeAuctions > 0 then
        table.insert(parts, ns.COLORS.YELLOW .. #record.activeAuctions .. " active auction(s)|r")
    end
    if record.salesSummary.count > 0 then
        table.insert(parts, ns.COLORS.CYAN .. record.salesSummary.count .. " sold|r")
    end
    if record.failureSummary.expiredCount + record.failureSummary.cancelledCount > 0 then
        local failCount = record.failureSummary.expiredCount + record.failureSummary.cancelledCount
        table.insert(parts, ns.COLORS.RED .. failCount .. " failed|r")
    end
    if #record.fpDeals > 0 then
        table.insert(parts, "|cffff8000" .. #record.fpDeals .. " FP deal(s)|r")
    end
    if #record.purchases > 0 then
        table.insert(parts, "|cff69ccf0" .. #record.purchases .. " purchase(s)|r")
    end

    if #parts == 0 then return yOffset end

    local f = AcquireFrame()
    f:SetHeight(ROW_HEIGHT)
    f:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, yOffset)
    f:SetPoint("RIGHT", detailContent, "RIGHT", 0, 0)
    if not f._label then
        f._label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f._label:SetPoint("LEFT", f, "LEFT", 12, 0)
        f._label:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        f._label:SetJustifyH("LEFT")
    end
    f._label:SetText(table.concat(parts, "  |cff555555·|r  "))
    f._label:Show()

    return yOffset - ROW_HEIGHT - 4
end

-- Price Comparison (hero section) — realm-per-row, source-per-column
local function RenderPriceComparison(record, yOffset)
    -- Collect data per realm from all sources
    local realmMap = {}  -- realm -> { sales, fails, avgSale, fpPrice, fpRate, fpComp, tsmPrice }
    local realmOrder = {}

    local function EnsureRealm(realm)
        if not realm or realm == "" then realm = "Unknown" end
        if not realmMap[realm] then
            realmMap[realm] = {
                sold = 0, failed = 0, avgSale = 0, totalRev = 0,
                fpPrice = nil, fpRate = nil, fpComp = nil,
                tsmMarket = nil, tsmMinBuy = nil,
            }
            table.insert(realmOrder, realm)
        end
        return realmMap[realm]
    end

    -- Sale history per realm
    for realm, data in pairs(record.salesSummary.byRealm) do
        local r = EnsureRealm(realm)
        r.sold = data.count
        r.avgSale = data.avg
        r.totalRev = data.total
    end

    -- Failed sales per realm
    for _, fail in ipairs(record.failures) do
        local r = EnsureRealm(fail.targetRealm)
        r.failed = r.failed + 1
    end

    -- FP deals per realm
    for _, deal in ipairs(record.fpDeals) do
        local r = EnsureRealm(deal.targetRealm)
        r.fpPrice = deal.expectedPrice
        r.fpRate = deal.sellRate
        if deal.noCompetition then
            r.fpComp = ns.COLORS.GREEN .. "None|r"
        else
            r.fpComp = "|cffaaaaaa-|r"
        end
        if deal.source == "fpCrossRealm" and deal.buyPrice then
            r.fpBuyPrice = deal.buyPrice
            r.fpBuyRealm = deal.buyRealm
            r.fpProfit = deal.profitAmount
        end
    end

    -- TSM per-realm data (from hourly AppData downloads for all realms)
    if record.tsmRealms then
        for realm, data in pairs(record.tsmRealms) do
            local r = EnsureRealm(realm)
            r.tsmMarket = r.tsmMarket or data.marketValueRecent
            r.tsmMinBuy = r.tsmMinBuy or data.minBuyout
            r.tsmNumAuctions = data.numAuctions
        end
    end

    -- TSM: current realm (live API data overrides AppData for this realm)
    if record.tsm then
        local currentRealm = GetRealmName and GetRealmName() or "This Realm"
        local r = EnsureRealm(currentRealm)
        if record.tsm.market then r.tsmMarket = record.tsm.market end
        if record.tsm.minBuyout then r.tsmMinBuy = record.tsm.minBuyout end
        r.isCurrentRealm = true
    end

    -- TSM: region row (aggregate)
    if record.tsm and (record.tsm.regionMarketAvg or record.tsm.regionSaleAvg) then
        local r = EnsureRealm("|cff69ccf0Region (All Realms)|r")
        r.tsmMarket = record.tsm.regionMarketAvg
        r.tsmMinBuy = record.tsm.regionMinBuyoutAvg
        if record.tsm.regionSaleRate then
            local pct = record.tsm.regionSaleRate
            if pct > 1 then pct = pct / 100 end
            r.fpRate = string.format("%.1f%%", pct * 100)
        end
    end

    if #realmOrder == 0 then return yOffset end

    yOffset = RenderSectionHeader(yOffset, "Price Comparison by Realm")

    -- Column headers: Realm | Sold | Avg Sale | FP Price | Rate | TSM Market | TSM MinBuy
    local compWeights = { 3, 1, 2, 2, 1.5, 2, 2 }
    yOffset = RenderTableRow(yOffset, {
        "|cffaaaaaaRealm|r",
        "|cffaaaaaaSold|r",
        "|cffaaaaaaAvg Sale|r",
        "|cffaaaaaaFP Price|r",
        "|cffaaaaaaRate|r",
        "|cffaaaaaaTSM Mkt|r",
        "|cffaaaaaaTSM Min|r",
    }, compWeights)

    for _, realm in ipairs(realmOrder) do
        local r = realmMap[realm]
        local soldStr = ""
        if r.sold > 0 then
            soldStr = ns.COLORS.GREEN .. r.sold .. "|r"
            if r.failed > 0 then
                soldStr = soldStr .. "/" .. ns.COLORS.RED .. r.failed .. "|r"
            end
        elseif r.failed > 0 then
            soldStr = ns.COLORS.RED .. "0/" .. r.failed .. "|r"
        end

        local rateStr = ""
        if type(r.fpRate) == "string" then
            rateStr = r.fpRate
        elseif type(r.fpRate) == "number" then
            rateStr = string.format("%.1f%%", r.fpRate * 100)
        end
        if r.fpComp and r.fpComp:find("None") then
            rateStr = rateStr ~= "" and (rateStr .. " " .. r.fpComp) or r.fpComp
        end

        local tsmMinStr = ""
        if r.tsmMinBuy then
            tsmMinStr = FormatGold(r.tsmMinBuy)
            if r.tsmNumAuctions and r.tsmNumAuctions > 0 then
                tsmMinStr = tsmMinStr .. " |cff888888(" .. r.tsmNumAuctions .. ")|r"
            end
        end

        local realmLabel = realm
        if r.isCurrentRealm then
            realmLabel = ns.COLORS.GREEN .. realm .. "|r"
        end

        yOffset = RenderTableRow(yOffset, {
            realmLabel,
            soldStr,
            r.avgSale and r.avgSale > 0 and FormatGold(r.avgSale) or "",
            FormatPrice(r.fpPrice),
            rateStr,
            r.tsmMarket and FormatGold(r.tsmMarket) or "",
            tsmMinStr,
        }, compWeights)

        -- If cross-realm deal, add a sub-row with buy info
        if r.fpBuyPrice then
            yOffset = RenderTableRow(yOffset, {
                "  |cff888888Buy: " .. (r.fpBuyRealm or "?") .. "|r",
                "",
                "",
                FormatPrice(r.fpBuyPrice),
                r.fpProfit and (ns.COLORS.GREEN .. FormatPrice(r.fpProfit) .. " profit|r") or "",
                "",
                "",
            }, compWeights)
        end
    end

    return yOffset - SECTION_PAD
end

-- Current Inventory
local function RenderInventory(record, yOffset)
    if #record.inventory == 0 then return yOffset end

    yOffset = RenderSectionHeader(yOffset, "Current Inventory (" .. record.totalInventory .. " total)")

    local invWeights = { 3, 3, 1, 2 }
    yOffset = RenderTableRow(yOffset, {
        "|cffaaaaaaOwner|r", "|cffaaaaaaLocation|r", "|cffaaaaaaQty|r", "|cffaaaaaaScan|r"
    }, invWeights)

    for _, inv in ipairs(record.inventory) do
        local owner = ClassColorName(inv.charKey, inv.class)
        yOffset = RenderTableRow(yOffset, {
            owner, LocationStr(inv.locations), tostring(inv.quantity),
            ns:FormatRelativeTime(inv.lastScan)
        }, invWeights)
    end

    return yOffset - SECTION_PAD
end

-- FP Deals — extras not already in the comparison table
local function RenderFPDeals(record, yOffset)
    if #record.fpDeals == 0 then return yOffset end

    local hasExtras = false
    for _, deal in ipairs(record.fpDeals) do
        if deal.category or deal.ilvl or deal.saleAvg then
            hasExtras = true
            break
        end
    end
    if not hasExtras then return yOffset end

    yOffset = RenderSectionHeader(yOffset, "FP Deal Details")
    local fpWeights = { 3, 2, 1, 2 }
    yOffset = RenderTableRow(yOffset, {
        "|cffaaaaaaRealm|r", "|cffaaaaaaCategory|r", "|cffaaaaaaiLvl|r", "|cffaaaaaaSale Avg|r"
    }, fpWeights)

    for _, deal in ipairs(record.fpDeals) do
        if deal.category or deal.ilvl or deal.saleAvg then
            yOffset = RenderTableRow(yOffset, {
                deal.targetRealm or "?",
                deal.category or "",
                deal.ilvl and tostring(deal.ilvl) or "",
                deal.saleAvg and FormatPrice(deal.saleAvg) or "",
            }, fpWeights)
        end
    end

    return yOffset - SECTION_PAD
end

-- TSM Auctioning Operation (pricing is in the comparison table; this shows posting rules)
local function RenderTSMOperation(record, yOffset)
    if not record.tsm then return yOffset end
    local op = record.tsm.auctioningOp
    if not op then return yOffset end

    yOffset = RenderSectionHeader(yOffset, "TSM Auctioning Operation")
    yOffset = RenderKeyValue(yOffset, "Operation", op.opName or "-")
    if op.minPrice then
        yOffset = RenderKeyValue(yOffset, "Min Price", tostring(op.minPrice))
    end
    if op.normalPrice then
        yOffset = RenderKeyValue(yOffset, "Normal Price", tostring(op.normalPrice))
    end
    if op.maxPrice then
        yOffset = RenderKeyValue(yOffset, "Max Price", tostring(op.maxPrice))
    end
    if op.postCap then
        yOffset = RenderKeyValue(yOffset, "Post Cap", tostring(op.postCap))
    end

    return yOffset - SECTION_PAD
end

-- Sale History — only recent individual transactions (summary is in comparison table)
local function RenderSaleHistory(record, yOffset)
    if #record.sales == 0 then return yOffset end
    -- Only show if there are recent sales worth detailing
    if #record.sales <= 1 then return yOffset end

    local sorted = {}
    for _, s in ipairs(record.sales) do table.insert(sorted, s) end
    table.sort(sorted, function(a, b) return (a.soldAt or 0) > (b.soldAt or 0) end)

    yOffset = RenderSectionHeader(yOffset, "Recent Sales")

    local saleWeights = { 3, 2, 2, 3 }
    yOffset = RenderTableRow(yOffset, {
        "|cffaaaaaaRealm|r", "|cffaaaaaaPrice|r", "|cffaaaaaaDate|r", "|cffaaaaaaSeller|r"
    }, saleWeights)

    local limit = math.min(#sorted, 10)
    for i = 1, limit do
        local s = sorted[i]
        yOffset = RenderTableRow(yOffset, {
            s.targetRealm,
            FormatGold(s.soldPrice),
            ns:FormatRelativeTime(s.soldAt),
            s.charKey or "",
        }, saleWeights)
    end
    if #sorted > limit then
        yOffset = RenderKeyValue(yOffset, "", "|cff888888... and " .. (#sorted - limit) .. " more|r")
    end

    return yOffset - SECTION_PAD
end

-- Failed Sales
local function RenderFailedSales(record, yOffset)
    if #record.failures == 0 then return yOffset end

    local summary = record.failureSummary
    local countStr = summary.expiredCount .. " expired"
    if summary.cancelledCount > 0 then
        countStr = countStr .. ", " .. summary.cancelledCount .. " cancelled"
    end
    local feeStr = summary.totalFeesLost > 0 and (" | Fees lost: " .. FormatGold(summary.totalFeesLost)) or ""
    yOffset = RenderSectionHeader(yOffset, "Failed Sales (" .. countStr .. feeStr .. ")")

    local failWeights = { 3, 2, 2, 2 }
    yOffset = RenderTableRow(yOffset, {
        "|cffaaaaaaRealm|r", "|cffaaaaaaPrice|r", "|cffaaaaaaDate|r", "|cffaaaaaaStatus|r"
    }, failWeights)

    -- Sort by most recent
    local sorted = {}
    for _, f in ipairs(record.failures) do table.insert(sorted, f) end
    table.sort(sorted, function(a, b) return (a.postedAt or 0) > (b.postedAt or 0) end)

    local limit = math.min(#sorted, 15)
    for i = 1, limit do
        local f = sorted[i]
        -- Show the meaningful outcome, not the raw "collected" status
        local displayStatus = f.saleOutcome or f.auctionStatus or "?"
        if displayStatus == "collected" then displayStatus = "expired" end
        local statusColor = displayStatus == "cancelled" and ns.COLORS.RED or ns.COLORS.ORANGE
        yOffset = RenderTableRow(yOffset, {
            f.targetRealm,
            FormatPrice(f.postedPrice),
            ns:FormatRelativeTime(f.postedAt),
            statusColor .. displayStatus .. "|r",
        }, failWeights)
    end

    return yOffset - SECTION_PAD
end

-- Active Auctions
local function RenderActiveAuctions(record, yOffset)
    if #record.activeAuctions == 0 then return yOffset end

    yOffset = RenderSectionHeader(yOffset, "Active Auctions (" .. #record.activeAuctions .. ")")

    local auctionWeights = { 3, 2, 2, 3 }
    yOffset = RenderTableRow(yOffset, {
        "|cffaaaaaaRealm|r", "|cffaaaaaaPrice|r", "|cffaaaaaaPosted|r", "|cffaaaaaaSeller|r"
    }, auctionWeights)

    for _, a in ipairs(record.activeAuctions) do
        yOffset = RenderTableRow(yOffset, {
            a.targetRealm,
            FormatPrice(a.postedPrice ~= "" and a.postedPrice or a.expectedPrice),
            ns:FormatRelativeTime(a.postedAt),
            a.charKey or "",
        }, auctionWeights)
    end

    return yOffset - SECTION_PAD
end

-- Purchase History
local function RenderPurchases(record, yOffset)
    if #record.purchases == 0 then return yOffset end

    yOffset = RenderSectionHeader(yOffset, "Purchase History (" .. #record.purchases .. ")")

    local purchaseWeights = { 3, 2, 2, 3 }
    yOffset = RenderTableRow(yOffset, {
        "|cffaaaaaaRealm|r", "|cffaaaaaaPrice|r", "|cffaaaaaaDate|r", "|cffaaaaaaBuyer|r"
    }, purchaseWeights)

    for _, p in ipairs(record.purchases) do
        yOffset = RenderTableRow(yOffset, {
            p.realm,
            FormatPrice(p.price > 0 and p.price or p.priceStr),
            ns:FormatRelativeTime(p.timestamp),
            p.charKey or "",
        }, purchaseWeights)
    end

    return yOffset - SECTION_PAD
end

-- ==========================================
-- MASTER RENDER
-- ==========================================

local function RenderDetailPanel(record)
    ResetDetailFrames()
    emptyLabel:Hide()
    detailScroll:Show()

    if not record then
        emptyLabel:Show()
        emptyLabel:SetText("|cff888888Select an item from the list|r")
        detailScroll:Hide()
        detailContent:SetHeight(1)
        return
    end

    local y = -4
    y = RenderItemHeader(record, y)
    y = RenderSummaryBadges(record, y)
    y = y - 4
    y = RenderPriceComparison(record, y)
    y = RenderInventory(record, y)
    y = RenderTSMOperation(record, y)
    y = RenderFPDeals(record, y)
    y = RenderActiveAuctions(record, y)
    y = RenderFailedSales(record, y)
    y = RenderSaleHistory(record, y)
    y = RenderPurchases(record, y)

    -- If nothing rendered beyond header
    if y > -80 and record.totalInventory == 0 and #record.sales == 0
        and #record.fpDeals == 0 and not record.tsm then
        y = y - 8
        local f = AcquireFrame()
        f:SetHeight(20)
        f:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, y)
        f:SetPoint("RIGHT", detailContent, "RIGHT", 0, 0)
        if not f._label then
            f._label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f._label:SetPoint("LEFT", f, "LEFT", 12, 0)
        end
        f._label:SetText("|cff888888No additional data available for this item.|r")
        f._label:Show()
        y = y - 20
    end

    detailContent:SetHeight(math.abs(y) + 20)
end

-- ==========================================
-- LAYOUT
-- ==========================================

local function RepositionLayout()
    local totalW = researchPage:GetWidth()
    local totalH = researchPage:GetHeight()
    if totalW < 10 or totalH < 10 then return end

    local leftW = math.max(200, math.floor(totalW * 0.38))
    local rightW = totalW - leftW - 1

    leftPanel:ClearAllPoints()
    leftPanel:SetPoint("TOPLEFT", researchPage, "TOPLEFT", 0, 0)
    leftPanel:SetSize(leftW, totalH)

    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 0, 0)

    rightPanel:ClearAllPoints()
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 1, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", researchPage, "BOTTOMRIGHT", 0, 0)

    -- Position item list table below filter bar
    local tableTop = -54  -- search(20) + gap(4) + filterBar(22) + gap(8)
    itemListTable.headerFrame:ClearAllPoints()
    itemListTable.headerFrame:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 0, tableTop)
    itemListTable.headerFrame:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", 0, tableTop)
    itemListTable.scrollFrame:ClearAllPoints()
    itemListTable.scrollFrame:SetPoint("TOPLEFT", itemListTable.headerFrame, "BOTTOMLEFT", 0, 0)
    itemListTable.scrollFrame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -22, 0)

    -- Update detail content width
    detailContent:SetWidth(math.max(100, rightW - 28))
end

-- ==========================================
-- REFRESH
-- ==========================================

local function BuildItemListData(index)
    local data = {}
    for _, item in ipairs(index) do
        local passFilter = false
        if currentFilter == "all" then
            passFilter = true
        elseif currentFilter == "inventory" then
            passFilter = item.hasInventory
        elseif currentFilter == "sales" then
            passFilter = item.hasLog
        elseif currentFilter == "deals" then
            passFilter = item.hasDeals
        end

        if passFilter then
            if currentSearchText == "" or
                (item.name and item.name:lower():find(currentSearchText, 1, true)) then
                -- Build sources badge string
                local badges = {}
                if item.hasInventory then table.insert(badges, ns.COLORS.GREEN .. "I|r") end
                if item.hasLog then table.insert(badges, ns.COLORS.CYAN .. "L|r") end
                if item.hasDeals then table.insert(badges, "|cffff8000D|r") end

                local displayName = item.name or "?"
                if item.quality then
                    displayName = UI._QualityColorName(displayName, item.quality)
                end

                local isSelected = (selectedItemKey and item.itemKey == selectedItemKey) or false

                table.insert(data, {
                    name = displayName,
                    qty = item.totalQty > 0 and item.totalQty or "",
                    sources = table.concat(badges, " "),
                    _icon = item.icon,
                    _tooltipItemID = item.itemID,
                    _itemKey = item.itemKey,
                    _itemName = item.name,
                    _sortName = (item.name or ""):lower(),
                    _rowColor = isSelected and { 0.2, 0.4, 0.2, 0.4 } or nil,
                })
            end
        end
    end
    return data
end

function UI:RefreshResearchPage()
    local mainFrame = UI.mainFrame
    mainFrame.pageTitle:SetText("Item Research")

    -- Hide action buttons
    for _, btn in pairs(mainFrame.actionBtns) do btn:Hide() end

    -- Show our page frame
    researchPage:Show()
    itemListTable.headerFrame:Show()
    itemListTable.scrollFrame:Show()

    -- Check for navigation target
    if UI._researchTargetItemKey or UI._researchTargetItemName then
        selectedItemKey = UI._researchTargetItemKey
        selectedItemName = UI._researchTargetItemName
        UI._researchTargetItemKey = nil
        UI._researchTargetItemName = nil
    end

    -- Build index
    cachedIndex = ns.ItemResearch:BuildItemIndex()

    -- Update filter highlights
    UpdateFilterHighlights()

    -- If we have a selected item, try to resolve it in the index
    if selectedItemKey then
        local found = false
        for _, item in ipairs(cachedIndex) do
            if item.itemKey == selectedItemKey then
                selectedItemName = item.name
                found = true
                break
            end
        end
        if not found and selectedItemName then
            -- Try name match
            local lowerName = selectedItemName:lower()
            for _, item in ipairs(cachedIndex) do
                if item.name and item.name:lower() == lowerName then
                    selectedItemKey = item.itemKey
                    found = true
                    break
                end
            end
        end
    end

    -- Build and set list data
    local listData = BuildItemListData(cachedIndex)
    itemListTable:SetRowClickHandler(function(rowData, button)
        if button == "LeftButton" then
            selectedItemKey = rowData._itemKey
            selectedItemName = rowData._itemName
            detailScroll:SetVerticalScroll(0)
            UI:RefreshResearchPage()
        end
    end)
    itemListTable:SetData(listData)

    -- Render detail panel
    if selectedItemKey then
        local record = ns.ItemResearch:GetItemResearch(selectedItemKey, selectedItemName)
        RenderDetailPanel(record)
    else
        RenderDetailPanel(nil)
    end

    -- Status bar
    local statusParts = { #listData .. " items" }
    if selectedItemName and selectedItemName ~= "" then
        table.insert(statusParts, "Viewing: " .. selectedItemName)
    end
    mainFrame.statusText:SetText(table.concat(statusParts, " | "))

    -- Layout
    RepositionLayout()
end

-- ==========================================
-- EXPOSE
-- ==========================================

UI._researchPage = researchPage

UI:RegisterPageLayout("research", function()
    if researchPage:IsShown() then
        RepositionLayout()
    end
end)
