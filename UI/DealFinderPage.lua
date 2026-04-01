-- UI/DealFinderPage.lua
-- Deal Finder: two-phase page.
-- Phase 1 (config): inventory filter (matching Generator pattern) + priority widget + scan.
-- Phase 2 (review): full-page per-item view. Pinned item preview at top with nav,
--   realm checkboxes in the middle, research data below, generate at bottom.
local addonName, ns = ...

local UI = ns.UI
local tableContainer = UI.tableContainer

-- ==========================================
-- STATE
-- ==========================================

local itemGroups = nil
local currentIdx = 0          -- 0 = config phase, 1+ = review phase
local filterMode, filterValue = "all", ""
local autoGenerate = true     -- auto-select based on priority

-- ==========================================
-- PAGE FRAME
-- ==========================================

local page = CreateFrame("Frame", nil, tableContainer)
page:SetAllPoints()
page:Hide()

-- Shared button helpers (matching GeneratorPage patterns)
local function CreateToggleBtn(parent, label)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(18)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER"); btn.text:SetText(label)
    btn:SetWidth(btn.text:GetStringWidth() + 14)
    btn:SetScript("OnEnter", function(s) if not s._active then s:SetBackdropColor(0.2, 0.2, 0.3, 1) end end)
    btn:SetScript("OnLeave", function(s)
        if s._active then s:SetBackdropColor(0.2, 0.4, 0.2, 1)
        else s:SetBackdropColor(0.15, 0.15, 0.2, 1) end
    end)
    return btn
end

local function SetToggleActive(btn, active)
    btn._active = active
    btn:SetBackdropColor(active and 0.2 or 0.15, active and 0.4 or 0.15, active and 0.2 or 0.2, 1)
    btn.text:SetTextColor(active and 1 or 0.6, active and 1 or 0.6, active and 1 or 0.6)
end

local function NavBtn(parent, label, green)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(90, 26)
    b:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    b:SetBackdropColor(green and 0.15 or 0.15, green and 0.25 or 0.15, green and 0.15 or 0.2, 1)
    b:SetBackdropBorderColor(green and 0.3 or 0.3, green and 0.6 or 0.3, green and 0.3 or 0.4, 0.8)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER"); b.text:SetText(label)
    if green then b.text:SetTextColor(0.3, 1, 0.3) end
    b:SetScript("OnEnter", function(s) s:SetBackdropColor(0.2, 0.2, 0.3, 1) end)
    b:SetScript("OnLeave", function(s)
        s:SetBackdropColor(green and 0.15 or 0.15, green and 0.25 or 0.15, green and 0.15 or 0.2, 1)
    end)
    return b
end

-- ==========================================
-- PHASE 1: CONFIG
-- ==========================================

local configPanel = CreateFrame("Frame", nil, page)
configPanel:SetAllPoints(); configPanel:Hide()

-- ==========================================
-- CONFIG: LEFT COLUMN (filter + group selection)
-- ==========================================

local leftCol = CreateFrame("Frame", nil, configPanel)
leftCol:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 0, 0)
leftCol:SetPoint("BOTTOMLEFT", configPanel, "BOTTOMLEFT", 0, 36)  -- leave room for scan bar

local leftDivider = configPanel:CreateTexture(nil, "ARTWORK")
leftDivider:SetWidth(1)
leftDivider:SetColorTexture(0.3, 0.3, 0.4, 0.5)

local rightCol = CreateFrame("Frame", nil, configPanel)

-- Dynamic column widths
configPanel:SetScript("OnSizeChanged", function(self, w)
    local leftW = math.max(200, math.floor(w * 0.48))
    leftCol:SetWidth(leftW)
    leftDivider:ClearAllPoints()
    leftDivider:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 0, 0)
    leftDivider:SetPoint("BOTTOMLEFT", leftCol, "BOTTOMRIGHT", 0, 0)
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 1, 0)
    rightCol:SetPoint("BOTTOMRIGHT", configPanel, "BOTTOMRIGHT", 0, 36)
end)

-- Filter label + buttons
local fLabel = leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fLabel:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 12, -10)
fLabel:SetText("Inventory Source"); fLabel:SetTextColor(0.8, 0.8, 0.8)

local fAll  = CreateToggleBtn(leftCol, "All")
fAll:SetPoint("TOPLEFT", fLabel, "BOTTOMLEFT", 0, -4)
local fTSM  = CreateToggleBtn(leftCol, "TSM Group")
fTSM:SetPoint("LEFT", fAll, "RIGHT", 2, 0)
local fAuct = CreateToggleBtn(leftCol, "Auctionator List")
fAuct:SetPoint("LEFT", fTSM, "RIGHT", 2, 0)

local function SetFilter(mode)
    filterMode = mode; filterValue = ""
    SetToggleActive(fAll, mode == "all")
    SetToggleActive(fTSM, mode == "tsm")
    SetToggleActive(fAuct, mode == "auctionator")
end

-- TSM group tree (fills left column below buttons)
local tsmTreeFrame = CreateFrame("Frame", nil, leftCol)
tsmTreeFrame:SetPoint("TOPLEFT", fAll, "BOTTOMLEFT", 0, -4)
tsmTreeFrame:SetPoint("BOTTOMRIGHT", leftCol, "BOTTOMRIGHT", -4, 0)
tsmTreeFrame:Hide()
local tsmTree = nil

-- Auctionator list (fills left column below buttons)
local auctFrame = CreateFrame("Frame", nil, leftCol)
auctFrame:SetPoint("TOPLEFT", fAll, "BOTTOMLEFT", 0, -4)
auctFrame:SetPoint("BOTTOMRIGHT", leftCol, "BOTTOMRIGHT", -4, 0)
auctFrame:Hide()
local auctScroll = CreateFrame("ScrollFrame", nil, auctFrame, "UIPanelScrollFrameTemplate")
auctScroll:SetPoint("TOPLEFT", 0, -14); auctScroll:SetPoint("BOTTOMRIGHT", -16, 0)
local auctContent = CreateFrame("Frame", nil, auctScroll)
auctContent:SetWidth(1); auctContent:SetHeight(1)
auctScroll:SetScrollChild(auctContent)
auctScroll:SetScript("OnSizeChanged", function(_, w) auctContent:SetWidth(w) end)
local auctRows = {}
local auctLabel = auctFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
auctLabel:SetPoint("TOPLEFT", 0, 0); auctLabel:SetText("Select list:")

local function RefreshFilterSubs()
    tsmTreeFrame:Hide(); auctFrame:Hide()
    if filterMode == "tsm" and ns.TSM and ns.TSM:IsEnabled() then
        tsmTreeFrame:Show()
        if not tsmTree and UI.CreateGroupTree then
            tsmTree = UI:CreateGroupTree(tsmTreeFrame, function(path) filterValue = path or "" end)
        end
        if tsmTree then
            local profile = ns.TSM:GetSelectedProfile()
            if profile then tsmTree:SetProfile(profile) end
        end
    elseif filterMode == "auctionator" then
        local names = ns:GetAuctionatorListNames()
        if #names > 0 then
            auctFrame:Show()
            for _, r in ipairs(auctRows) do r:Hide() end
            local y = -14
            for li, name in ipairs(names) do
                local r = auctRows[li]
                if not r then
                    r = CreateFrame("Button", nil, auctContent); r:SetHeight(18)
                    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.text:SetPoint("LEFT", 6, 0)
                    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
                    auctRows[li] = r
                end
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", auctContent, "TOPLEFT", 0, y)
                r:SetPoint("RIGHT", auctContent, "RIGHT", 0, 0)
                r.text:SetText(name)
                local sel = (filterValue == name)
                r.bg:SetColorTexture(sel and 0.2 or 0, sel and 0.4 or 0, sel and 0.2 or 0, sel and 0.3 or 0)
                local cap = name
                r:SetScript("OnClick", function() filterValue = cap; RefreshFilterSubs() end)
                r:Show(); y = y - 18
            end
            auctContent:SetHeight(math.abs(y) + 14)
        end
    end
end

fAll:SetScript("OnClick",  function() SetFilter("all"); RefreshFilterSubs() end)
fTSM:SetScript("OnClick",  function() SetFilter("tsm"); RefreshFilterSubs() end)
fAuct:SetScript("OnClick", function() SetFilter("auctionator"); RefreshFilterSubs() end)

-- ==========================================
-- CONFIG: RIGHT COLUMN (priority + outlier config)
-- ==========================================

-- Priority widget
local prioLabel = rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
prioLabel:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 12, -10)
prioLabel:SetText("Deal Priority (drag to reorder)"); prioLabel:SetTextColor(0.8, 0.8, 0.8)

local DF_ALLOC_META = {
    profit         = {label = "Most Profit",     icon = "Interface\\Icons\\INV_Misc_Coin_17", color = {1, 0.82, 0}},
    noCompetition  = {label = "No Competition",  icon = "Interface\\Icons\\Achievement_PVP_H_01", color = {0.3, 1, 0.3}},
    previousSales  = {label = "Previous Sales",  icon = "Interface\\Icons\\INV_Misc_Book_09", color = {0.4, 0.8, 1}},
    population     = {label = "High Population", icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", color = {0.7, 0.5, 1}},
}

local prioFrame = CreateFrame("Frame", nil, rightCol)
prioFrame:SetHeight(120)
prioFrame:SetPoint("TOPLEFT", prioLabel, "BOTTOMLEFT", -8, -4)
prioFrame:SetPoint("RIGHT", rightCol, "RIGHT", -12, 0)

local prioAllocRows = {}

local function RenderPriority()
    if not ns.db then return end
    UI:RenderAllocList(ns.db.settings.dfPriorityOrder, DF_ALLOC_META, prioAllocRows, prioFrame, -2, RenderPriority)
end

-- Outlier configuration
local outlierLabel = rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
outlierLabel:SetPoint("TOPLEFT", prioFrame, "BOTTOMLEFT", 8, -14)
outlierLabel:SetText("Outlier Detection"); outlierLabel:SetTextColor(0.8, 0.8, 0.8)

local outlierDesc = rightCol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
outlierDesc:SetPoint("TOPLEFT", outlierLabel, "BOTTOMLEFT", 0, -2)
outlierDesc:SetText("Flag realm prices exceeding this multiple of regional average:")

local outlierBox = CreateFrame("EditBox", nil, rightCol, "InputBoxTemplate")
outlierBox:SetHeight(18); outlierBox:SetWidth(40)
outlierBox:SetPoint("TOPLEFT", outlierDesc, "BOTTOMLEFT", 0, -4)
outlierBox:SetAutoFocus(false)
outlierBox:SetFontObject("ChatFontSmall")
outlierBox:SetText("1.5")
outlierBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
outlierBox:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
outlierBox:SetScript("OnTextChanged", function(s, userInput)
    if not userInput then return end
    local val = tonumber(s:GetText())
    if val and val >= 1 and ns.db then
        ns.db.settings.dfOutlierMultiplier = val
    end
end)

local outlierSuffix = rightCol:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
outlierSuffix:SetPoint("LEFT", outlierBox, "RIGHT", 4, 0)
outlierSuffix:SetText("x regional avg")

-- Ignore outliers checkbox
local ignoreOutlierChk = CreateFrame("CheckButton", nil, rightCol, "UICheckButtonTemplate")
ignoreOutlierChk:SetSize(22, 22)
ignoreOutlierChk:SetPoint("TOPLEFT", outlierBox, "BOTTOMLEFT", -2, -6)

local ignoreOutlierLabel = rightCol:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ignoreOutlierLabel:SetPoint("LEFT", ignoreOutlierChk, "RIGHT", 2, 0)
ignoreOutlierLabel:SetText("Exclude outlier realms from auto-selection")

ignoreOutlierChk:SetScript("OnClick", function(self)
    if ns.db then ns.db.settings.dfIgnoreOutliers = self:GetChecked() end
end)

-- ==========================================
-- CONFIG: BOTTOM (scan button + progress)
-- ==========================================

local scanBar = CreateFrame("Frame", nil, configPanel)
scanBar:SetHeight(36)
scanBar:SetPoint("BOTTOMLEFT", configPanel, "BOTTOMLEFT", 0, 0)
scanBar:SetPoint("BOTTOMRIGHT", configPanel, "BOTTOMRIGHT", 0, 0)
local scanBarBg = scanBar:CreateTexture(nil, "BACKGROUND")
scanBarBg:SetAllPoints(); scanBarBg:SetColorTexture(0.08, 0.08, 0.12, 1)

local scanBtn = CreateFrame("Button", nil, scanBar, "UIPanelButtonTemplate")
scanBtn:SetSize(140, 26)
scanBtn:SetPoint("CENTER", scanBar, "CENTER", 0, 0)
scanBtn:SetText("Scan for Deals")

local progressBar = CreateFrame("Frame", nil, scanBar, "BackdropTemplate")
progressBar:SetHeight(16)
progressBar:SetPoint("LEFT", scanBar, "LEFT", 20, 0)
progressBar:SetPoint("RIGHT", scanBar, "RIGHT", -20, 0)
progressBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
progressBar:SetBackdropColor(0.05, 0.05, 0.08, 1)
progressBar:SetBackdropBorderColor(0.2, 0.2, 0.3, 0.5)
progressBar:Hide()
progressBar.fill = progressBar:CreateTexture(nil, "ARTWORK")
progressBar.fill:SetPoint("LEFT", 3, 0); progressBar.fill:SetHeight(10); progressBar.fill:SetWidth(1)
progressBar.fill:SetColorTexture(0.2, 0.6, 0.3, 0.8)
progressBar.text = progressBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
progressBar.text:SetPoint("CENTER")

local function ShowProgress(p, t)
    progressBar:Show(); scanBtn:Hide()
    local pct = t > 0 and (p / t) or 0
    progressBar.fill:SetWidth(math.max(1, (progressBar:GetWidth() - 6) * pct))
    progressBar.text:SetText(string.format("Scanning... %d / %d", p, t))
end
local function HideProgress() progressBar:Hide(); scanBtn:Show() end

-- ==========================================
-- PHASE 2: PER-ITEM REVIEW
-- ==========================================

local reviewPanel = CreateFrame("Frame", nil, page)
reviewPanel:SetAllPoints(); reviewPanel:Hide()

-- Pinned item header (top ~90px)
local itemHeader = CreateFrame("Frame", nil, reviewPanel)
itemHeader:SetHeight(90)
itemHeader:SetPoint("TOPLEFT", reviewPanel, "TOPLEFT", 0, 0)
itemHeader:SetPoint("TOPRIGHT", reviewPanel, "TOPRIGHT", 0, 0)
local headerBg = itemHeader:CreateTexture(nil, "BACKGROUND")
headerBg:SetAllPoints(); headerBg:SetColorTexture(0.08, 0.08, 0.12, 1)

-- Nav at top-right of header
local prevBtn = NavBtn(itemHeader, "< Previous")
prevBtn:SetPoint("TOPRIGHT", itemHeader, "TOPRIGHT", -100, -4)
local nextBtn = NavBtn(itemHeader, "Next >")
nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
local skipBtn = NavBtn(itemHeader, "Skip")
skipBtn:SetPoint("TOPRIGHT", prevBtn, "TOPLEFT", -4, 0)

local itemCounter = itemHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
itemCounter:SetPoint("TOPRIGHT", skipBtn, "TOPLEFT", -8, -6)

-- Scrollable content (realm checkboxes + research data)
local scroll = CreateFrame("ScrollFrame", nil, reviewPanel, "UIPanelScrollFrameTemplate")
local scrollContent = CreateFrame("Frame", nil, scroll)
scrollContent:SetWidth(1); scrollContent:SetHeight(1)
scroll:SetScrollChild(scrollContent)
scroll:SetScript("OnSizeChanged", function(_, w) scrollContent:SetWidth(w) end)

-- Bottom bar
local bottomBar = CreateFrame("Frame", nil, reviewPanel)
bottomBar:SetHeight(32)
bottomBar:SetPoint("BOTTOMLEFT", reviewPanel, "BOTTOMLEFT", 0, 0)
bottomBar:SetPoint("BOTTOMRIGHT", reviewPanel, "BOTTOMRIGHT", 0, 0)
local bottomBg = bottomBar:CreateTexture(nil, "BACKGROUND")
bottomBg:SetAllPoints(); bottomBg:SetColorTexture(0.08, 0.08, 0.12, 1)

-- Anchor scroll between header and bottom
scroll:SetPoint("TOPLEFT", itemHeader, "BOTTOMLEFT", 0, 0)
scroll:SetPoint("BOTTOMRIGHT", bottomBar, "TOPRIGHT", -24, 0)

-- Generate button (centered)
local genBtn = NavBtn(bottomBar, "Generate To-Do", true)
genBtn:SetSize(140, 24)
genBtn:SetPoint("CENTER", bottomBar, "CENTER", 0, 0)

-- Auto-generate checkbox
local autoChk = CreateFrame("CheckButton", nil, bottomBar, "UICheckButtonTemplate")
autoChk:SetSize(22, 22)
autoChk:SetPoint("LEFT", genBtn, "RIGHT", 8, 0)
autoChk:SetChecked(true)
local autoLabel = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
autoLabel:SetPoint("LEFT", autoChk, "RIGHT", 2, 0)
autoLabel:SetText("Auto-select by priority")

autoChk:SetScript("OnClick", function(self)
    autoGenerate = self:GetChecked()
    if autoGenerate and itemGroups and ns.DealFinder then
        ns.DealFinder:ApplyPriority(itemGroups, ns.db.settings.dfPriorityOrder)
        -- Expand selections to match quantity
        for _, group in ipairs(itemGroups) do
            ApplyQuantitySelection(group)
        end
        if currentIdx >= 1 then ShowItem(currentIdx) end
    end
end)

-- ==========================================
-- QUANTITY-AWARE SELECTION
-- ==========================================

-- For an item with quantity N, select the top N realms by score.
local function ApplyQuantitySelectionFn(group)
    local qty = group.quantity or 1
    if #group.realms <= 1 then return end
    local sorted = {}
    for i, r in ipairs(group.realms) do sorted[i] = {idx = i, score = r.score or 0} end
    table.sort(sorted, function(a, b) return a.score > b.score end)
    for _, r in ipairs(group.realms) do r._selected = false end
    for rank = 1, math.min(qty, #sorted) do
        group.realms[sorted[rank].idx]._selected = true
    end
end
-- Make accessible before first use
ApplyQuantitySelection = ApplyQuantitySelectionFn

-- ==========================================
-- SHOW ITEM
-- ==========================================

local function ShowItem(idx)
    if not itemGroups or idx < 1 or idx > #itemGroups then return end
    currentIdx = idx
    local group = itemGroups[idx]

    -- Render pinned header
    UI:RenderDealFinderHeader(itemHeader, group)
    itemCounter:SetText("Item " .. idx .. " / " .. #itemGroups)

    -- Nav visibility
    prevBtn:SetShown(idx > 1)
    nextBtn:SetShown(idx < #itemGroups)

    -- Render scrollable content: realm checkboxes + research
    UI:RenderDealFinderRealms(scrollContent, group, function(realmIdx)
        local realm = group.realms[realmIdx]
        if realm then
            realm._selected = not (realm._selected ~= false)
            ShowItem(idx)  -- refresh
        end
    end)

    scroll:SetVerticalScroll(0)
end

-- ==========================================
-- NAV HANDLERS
-- ==========================================

prevBtn:SetScript("OnClick", function()
    if currentIdx > 1 then ShowItem(currentIdx - 1) end
end)

nextBtn:SetScript("OnClick", function()
    if itemGroups and currentIdx < #itemGroups then ShowItem(currentIdx + 1) end
end)

skipBtn:SetScript("OnClick", function()
    if not itemGroups or not itemGroups[currentIdx] then return end
    itemGroups[currentIdx].denied = true
    -- Clear all realm selections
    for _, r in ipairs(itemGroups[currentIdx].realms) do r._selected = false end
    if currentIdx < #itemGroups then
        ShowItem(currentIdx + 1)
    else
        ShowItem(currentIdx)
    end
end)

-- ==========================================
-- SCAN
-- ==========================================

scanBtn:SetScript("OnClick", function()
    if not ns.DealFinder then return end
    if ns.DealFinder:IsScanning() then
        ns.DealFinder:CancelScan(); HideProgress(); return
    end
    local ready, reason = ns.DealFinder:IsReady()
    if not ready then
        ns:Print((ns.COLORS and ns.COLORS.RED or "") .. (reason or "Not ready") .. "|r"); return
    end

    local pool = ns.TodoList:GetFilteredItemPool(filterMode, filterValue)
    if not pool or #pool == 0 then
        ns:Print("No tradeable items" .. (filterMode ~= "all" and " (try All)" or "")); return
    end

    itemGroups = nil; currentIdx = 0
    ShowProgress(0, #pool)

    ns.DealFinder:ScanChunked(pool,
        function(p, t) ShowProgress(p, t) end,
        function(result)
            HideProgress()
            if not result then return end

            itemGroups = result.itemGroups

            -- Apply quantity-aware selection
            for _, group in ipairs(itemGroups) do
                ApplyQuantitySelectionFn(group)
            end

            if #itemGroups > 0 then
                currentIdx = 1
                local s = result.stats
                ns:Print(string.format("%s%d items|r with deals from %d scanned (%.1fs)",
                    ns.COLORS and ns.COLORS.GREEN or "", s.itemsWithDeals, s.itemsScanned, s.elapsed or 0))
            else
                ns:Print("No deals found.")
            end
            UI:RefreshDealFinderPage()
        end
    )
end)

-- ==========================================
-- GENERATE
-- ==========================================

genBtn:SetScript("OnClick", function()
    if not itemGroups then return end
    local count = ns.DealFinder:SaveSelectedToImports(itemGroups)
    if count == 0 then ns:Print("No deals selected."); return end

    -- Use Deal Finder priority order mapped to generator allocation keys
    local dfOrder = ns.db and ns.db.settings.dfPriorityOrder or {"profit"}
    -- Map DF keys to generator keys: profit→gold, noCompetition→noCompetition, etc.
    local genOrder = {}
    for _, k in ipairs(dfOrder) do
        if k == "profit" then table.insert(genOrder, "gold")
        else table.insert(genOrder, k) end
    end
    if #genOrder == 0 then genOrder = {"gold"} end

    local preview = ns.TodoList:GenerateTodoList("dealFinder", genOrder)
    local taskCount = preview and (preview.items and #preview.items or preview.tasks and #preview.tasks or 0) or 0
    if taskCount > 0 then
        preview.name = "Deal Finder " .. date("%Y-%m-%d %H:%M")
        ns.TodoList:CommitList(preview, "replace")
        ns:Print(string.format("%s%d tasks|r generated.", ns.COLORS and ns.COLORS.GREEN or "", taskCount))
        UI.currentPage = "todo"
        UI:Refresh()
    else
        ns:Print("No tasks generated. Check character assignments.")
    end
end)

-- ==========================================
-- REFRESH
-- ==========================================

function UI:RefreshDealFinderPage()
    local mainFrame = UI.mainFrame
    mainFrame.pageTitle:SetText("Deal Finder")
    for _, btn in pairs(mainFrame.actionBtns) do btn:Hide() end
    page:Show()

    if itemGroups and #itemGroups > 0 and currentIdx >= 1 then
        configPanel:Hide()
        reviewPanel:Show()
        ShowItem(currentIdx)

        local totalSel = 0
        for _, g in ipairs(itemGroups) do
            if not g.denied then
                for _, r in ipairs(g.realms) do
                    if r._selected ~= false then totalSel = totalSel + 1 end
                end
            end
        end
        mainFrame.statusText:SetText(#itemGroups .. " items  |  " .. totalSel .. " deals selected")
    else
        reviewPanel:Hide()
        configPanel:Show()
        SetFilter(filterMode)
        RefreshFilterSubs()
        RenderPriority()

        -- Load outlier settings into UI
        if ns.db then
            outlierBox:SetText(tostring(ns.db.settings.dfOutlierMultiplier or 1.5))
            ignoreOutlierChk:SetChecked(ns.db.settings.dfIgnoreOutliers or false)
        end

        local ready = ns.DealFinder and ns.DealFinder:IsReady()
        if not ready then scanBtn:Disable() else scanBtn:Enable() end
        mainFrame.statusText:SetText("Configure and scan for deals")
    end
end

-- ==========================================
-- EXPOSE
-- ==========================================

UI._dealFinderPage = page
