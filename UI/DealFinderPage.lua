-- UI/DealFinderPage.lua
-- Deal Finder: three-phase page.
-- Phase 1 (config): inventory filter + location + live preview + priority + scan.
-- Phase 2 (review): per-item realm selection with pinned table + scrollable research.
-- Phase 3 (preview): generated to-do preview before committing.
local addonName, ns = ...

local UI = ns.UI
local tableContainer = UI.tableContainer

-- ==========================================
-- STATE
-- ==========================================

local itemGroups = nil
local currentIdx = 0          -- 0 = config, 1+ = review
local filterMode, filterValue = "all", ""
local locationFilter = "all"  -- "all", "bags", "warbank", "bank"
local autoGenerate = true
local previewMode = false
local dfPreview = nil

local function G(c)
    if not c then return "-" end
    if type(c) == "string" then return c end  -- already formatted
    return c <= 0 and "-" or ns:FormatGold(c)
end

-- ==========================================
-- PAGE FRAME + BUTTON HELPERS
-- ==========================================

local page = CreateFrame("Frame", nil, tableContainer)
page:SetAllPoints(); page:Hide()

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
-- LOCATION FILTER HELPER
-- ==========================================

local function FilterPoolByLocation(pool, locFilter)
    if locFilter == "all" then return pool end
    local filtered = {}
    for _, item in ipairs(pool) do
        local fSrc = {}
        for _, src in ipairs(item.sources) do
            if src.location == locFilter then table.insert(fSrc, src) end
        end
        if #fSrc > 0 then
            local copy = {}
            for k, v in pairs(item) do copy[k] = v end
            copy.sources = fSrc; copy.totalQuantity = 0
            for _, s in ipairs(fSrc) do copy.totalQuantity = copy.totalQuantity + s.quantity end
            table.insert(filtered, copy)
        end
    end
    return filtered
end

-- ==========================================
-- PHASE 1: CONFIG
-- ==========================================

local configPanel = CreateFrame("Frame", nil, page)
configPanel:SetAllPoints(); configPanel:Hide()

-- Scan bar (very bottom, 36px)
local scanBar = CreateFrame("Frame", nil, configPanel)
scanBar:SetHeight(36)
scanBar:SetPoint("BOTTOMLEFT", configPanel, "BOTTOMLEFT", 0, 0)
scanBar:SetPoint("BOTTOMRIGHT", configPanel, "BOTTOMRIGHT", 0, 0)
local scanBarBg = scanBar:CreateTexture(nil, "BACKGROUND")
scanBarBg:SetAllPoints(); scanBarBg:SetColorTexture(0.08, 0.08, 0.12, 1)

local scanBtn = CreateFrame("Button", nil, scanBar, "UIPanelButtonTemplate")
scanBtn:SetSize(140, 26); scanBtn:SetPoint("CENTER", scanBar, "CENTER", 0, 0)
scanBtn:SetText("Scan for Deals")

local progressBar = CreateFrame("Frame", nil, scanBar, "BackdropTemplate")
progressBar:SetHeight(16)
progressBar:SetPoint("LEFT", scanBar, "LEFT", 20, 0); progressBar:SetPoint("RIGHT", scanBar, "RIGHT", -20, 0)
progressBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
progressBar:SetBackdropColor(0.05, 0.05, 0.08, 1)
progressBar:SetBackdropBorderColor(0.2, 0.2, 0.3, 0.5); progressBar:Hide()
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

-- Inventory preview panel (above scan bar, full width)
local invPreviewPanel = CreateFrame("Frame", nil, configPanel)
invPreviewPanel:SetPoint("LEFT", configPanel, "LEFT", 0, 0)
invPreviewPanel:SetPoint("RIGHT", configPanel, "RIGHT", 0, 0)
invPreviewPanel:SetPoint("BOTTOM", scanBar, "TOP", 0, 0)
invPreviewPanel:SetHeight(100) -- updated in OnSizeChanged

local invHdrBg = invPreviewPanel:CreateTexture(nil, "BACKGROUND")
invHdrBg:SetHeight(18); invHdrBg:SetPoint("TOPLEFT"); invHdrBg:SetPoint("TOPRIGHT")
invHdrBg:SetColorTexture(0.1, 0.1, 0.15, 0.8)
local invSummary = invPreviewPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
invSummary:SetPoint("TOPLEFT", invPreviewPanel, "TOPLEFT", 8, -2)
invSummary:SetText("Inventory Preview"); invSummary:SetTextColor(0.8, 0.8, 0.8)
local invCount = invPreviewPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
invCount:SetPoint("LEFT", invSummary, "RIGHT", 10, 0)

local invScroll = CreateFrame("ScrollFrame", nil, invPreviewPanel, "UIPanelScrollFrameTemplate")
invScroll:SetPoint("TOPLEFT", invPreviewPanel, "TOPLEFT", 0, -18)
invScroll:SetPoint("BOTTOMRIGHT", invPreviewPanel, "BOTTOMRIGHT", -16, 0)
local invContent = CreateFrame("Frame", nil, invScroll)
invContent:SetWidth(1); invContent:SetHeight(1)
invScroll:SetScrollChild(invContent)
invScroll:SetScript("OnSizeChanged", function(_, w) invContent:SetWidth(w) end)

-- Left column (above preview panel)
local leftCol = CreateFrame("Frame", nil, configPanel)
leftCol:SetPoint("TOPLEFT", configPanel, "TOPLEFT", 0, 0)
leftCol:SetPoint("BOTTOMLEFT", invPreviewPanel, "TOPLEFT", 0, 0)

local leftDivider = configPanel:CreateTexture(nil, "ARTWORK")
leftDivider:SetWidth(1); leftDivider:SetColorTexture(0.3, 0.3, 0.4, 0.5)

local rightCol = CreateFrame("Frame", nil, configPanel)

configPanel:SetScript("OnSizeChanged", function(self, w, h)
    local leftW = math.max(200, math.floor(w * 0.48))
    leftCol:SetWidth(leftW)
    leftDivider:ClearAllPoints()
    leftDivider:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 0, 0)
    leftDivider:SetPoint("BOTTOMLEFT", leftCol, "BOTTOMRIGHT", 0, 0)
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 1, 0)
    rightCol:SetPoint("BOTTOMRIGHT", invPreviewPanel, "TOPRIGHT", 0, 0)
    -- Preview panel: 35% of available height, min 80px
    local previewH = math.max(80, math.floor((h - 36) * 0.35))
    invPreviewPanel:SetHeight(previewH)
end)

-- ==========================================
-- CONFIG: LEFT COLUMN (filter + location + TSM/Auctionator)
-- ==========================================

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

-- Location filter (in left column, below source buttons)
local locLabel = leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
locLabel:SetPoint("TOPLEFT", fAll, "BOTTOMLEFT", 0, -6)
locLabel:SetText("Location"); locLabel:SetTextColor(0.8, 0.8, 0.8)

local lAll  = CreateToggleBtn(leftCol, "All")
lAll:SetPoint("TOPLEFT", locLabel, "BOTTOMLEFT", 0, -4)
local lBags = CreateToggleBtn(leftCol, "Bags")
lBags:SetPoint("LEFT", lAll, "RIGHT", 2, 0)
local lWB   = CreateToggleBtn(leftCol, "Warbank")
lWB:SetPoint("LEFT", lBags, "RIGHT", 2, 0)
local lBank = CreateToggleBtn(leftCol, "Bank")
lBank:SetPoint("LEFT", lWB, "RIGHT", 2, 0)

-- Forward declare
local RefreshInventoryPreview

local function SetLocationFilter(mode)
    locationFilter = mode
    SetToggleActive(lAll, mode == "all")
    SetToggleActive(lBags, mode == "bags")
    SetToggleActive(lWB, mode == "warbank")
    SetToggleActive(lBank, mode == "bank")
    if RefreshInventoryPreview then RefreshInventoryPreview() end
end

lAll:SetScript("OnClick",  function() SetLocationFilter("all") end)
lBags:SetScript("OnClick", function() SetLocationFilter("bags") end)
lWB:SetScript("OnClick",   function() SetLocationFilter("warbank") end)
lBank:SetScript("OnClick",  function() SetLocationFilter("bank") end)

-- TSM tree (below location buttons)
local tsmTreeFrame = CreateFrame("Frame", nil, leftCol)
tsmTreeFrame:SetPoint("TOPLEFT", lAll, "BOTTOMLEFT", 0, -4)
tsmTreeFrame:SetPoint("BOTTOMRIGHT", leftCol, "BOTTOMRIGHT", -4, 0)
tsmTreeFrame:Hide()
local tsmTree = nil

-- Auctionator list (below location buttons)
local auctFrame = CreateFrame("Frame", nil, leftCol)
auctFrame:SetPoint("TOPLEFT", lAll, "BOTTOMLEFT", 0, -4)
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
            tsmTree = UI:CreateGroupTree(tsmTreeFrame, function(path)
                filterValue = path or ""
                if RefreshInventoryPreview then RefreshInventoryPreview() end
            end)
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
                r:SetScript("OnClick", function()
                    filterValue = cap; RefreshFilterSubs()
                end)
                r:Show(); y = y - 18
            end
            auctContent:SetHeight(math.abs(y) + 14)
        end
    end
    if RefreshInventoryPreview then RefreshInventoryPreview() end
end

fAll:SetScript("OnClick",  function() SetFilter("all"); RefreshFilterSubs() end)
fTSM:SetScript("OnClick",  function() SetFilter("tsm"); RefreshFilterSubs() end)
fAuct:SetScript("OnClick", function() SetFilter("auctionator"); RefreshFilterSubs() end)

-- ==========================================
-- CONFIG: RIGHT COLUMN (priority + outlier)
-- ==========================================

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

local outlierLabel = rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormal")
outlierLabel:SetPoint("TOPLEFT", prioFrame, "BOTTOMLEFT", 8, -14)
outlierLabel:SetText("Outlier Detection"); outlierLabel:SetTextColor(0.8, 0.8, 0.8)

local outlierDesc = rightCol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
outlierDesc:SetPoint("TOPLEFT", outlierLabel, "BOTTOMLEFT", 0, -2)
outlierDesc:SetText("Flag realm prices exceeding this multiple of regional average:")

local outlierBox = CreateFrame("EditBox", nil, rightCol, "InputBoxTemplate")
outlierBox:SetHeight(18); outlierBox:SetWidth(40)
outlierBox:SetPoint("TOPLEFT", outlierDesc, "BOTTOMLEFT", 0, -4)
outlierBox:SetAutoFocus(false); outlierBox:SetFontObject("ChatFontSmall"); outlierBox:SetText("1.5")
outlierBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
outlierBox:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
outlierBox:SetScript("OnTextChanged", function(s, userInput)
    if not userInput then return end
    local val = tonumber(s:GetText())
    if val and val >= 1 and ns.db then ns.db.settings.dfOutlierMultiplier = val end
end)
local outlierSuffix = rightCol:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
outlierSuffix:SetPoint("LEFT", outlierBox, "RIGHT", 4, 0); outlierSuffix:SetText("x regional avg")

local ignoreOutlierChk = CreateFrame("CheckButton", nil, rightCol, "UICheckButtonTemplate")
ignoreOutlierChk:SetSize(22, 22); ignoreOutlierChk:SetPoint("TOPLEFT", outlierBox, "BOTTOMLEFT", -2, -6)
local ignoreOutlierLbl = rightCol:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ignoreOutlierLbl:SetPoint("LEFT", ignoreOutlierChk, "RIGHT", 2, 0)
ignoreOutlierLbl:SetText("Exclude outlier realms from auto-selection")
ignoreOutlierChk:SetScript("OnClick", function(self)
    if ns.db then ns.db.settings.dfIgnoreOutliers = self:GetChecked() end
end)

-- ==========================================
-- CONFIG: INVENTORY PREVIEW (2-column item list)
-- ==========================================

local invRows = {}
local ROW_H = 16

RefreshInventoryPreview = function()
    if not ns.TodoList or not ns.TodoList.GetFilteredItemPool then return end
    local ok, pool = pcall(function() return ns.TodoList:GetFilteredItemPool(filterMode, filterValue) end)
    if not ok or not pool then pool = {} end
    pool = FilterPoolByLocation(pool, locationFilter)

    local totalQty = 0
    for _, item in ipairs(pool) do totalQty = totalQty + (item.totalQuantity or 0) end
    invCount:SetText("|cffaaaaaa" .. #pool .. " items  ·  " .. totalQty .. " total qty|r")

    for _, r in ipairs(invRows) do r:Hide() end

    local contentW = invContent:GetWidth()
    if contentW <= 0 then contentW = 400 end
    local numCols = math.max(1, math.min(3, math.floor(contentW / 200)))
    local colW = math.floor((contentW - 4) / numCols)
    local numRows = math.ceil(#pool / numCols)

    for i, item in ipairs(pool) do
        local r = invRows[i]
        if not r then
            r = CreateFrame("Frame", nil, invContent); r:SetHeight(ROW_H)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 2, 0); r.text:SetPoint("RIGHT", r, "RIGHT", -2, 0)
            r.text:SetWordWrap(false)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
            invRows[i] = r
        end
        local col = (i - 1) % numCols
        local row = math.floor((i - 1) / numCols)
        r:ClearAllPoints()
        r:SetWidth(colW - 2)
        r:SetPoint("TOPLEFT", invContent, "TOPLEFT", 2 + col * colW, -(row * ROW_H))

        local iconStr = item.icon and ("|T" .. item.icon .. ":14:14:0:0|t ") or ""
        local locParts = {}
        for _, src in ipairs(item.sources or {}) do
            local sl = src.location == "warbank" and "wb" or src.location == "reagent" and "rg" or src.location
            table.insert(locParts, src.quantity .. " " .. sl)
        end
        r.text:SetText(iconStr .. (item.name or "?") .. "  |cffaaaaaa" .. (item.totalQuantity or 0) .. " (" .. table.concat(locParts, ", ") .. ")|r")
        r.bg:SetColorTexture(row % 2 == 0 and 0.06 or 0.04, row % 2 == 0 and 0.06 or 0.04, row % 2 == 0 and 0.08 or 0.06, 0.3)
        r:Show()
    end
    invContent:SetHeight(numRows * ROW_H + 4)
end

-- ==========================================
-- PHASE 2: PER-ITEM REVIEW
-- ==========================================

local reviewPanel = CreateFrame("Frame", nil, page)
reviewPanel:SetAllPoints(); reviewPanel:Hide()

local itemHeader = CreateFrame("Frame", nil, reviewPanel)
itemHeader:SetHeight(108)
itemHeader:SetPoint("TOPLEFT", reviewPanel, "TOPLEFT", 0, 0)
itemHeader:SetPoint("TOPRIGHT", reviewPanel, "TOPRIGHT", 0, 0)
local headerBg = itemHeader:CreateTexture(nil, "BACKGROUND")
headerBg:SetAllPoints(); headerBg:SetColorTexture(0.08, 0.08, 0.12, 1)

local prevBtn = NavBtn(itemHeader, "< Previous")
prevBtn:SetPoint("TOPRIGHT", itemHeader, "TOPRIGHT", -100, -4)
local nextBtn = NavBtn(itemHeader, "Next >")
nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
local skipBtn = NavBtn(itemHeader, "Skip")
skipBtn:SetPoint("TOPRIGHT", prevBtn, "TOPLEFT", -4, 0)
local itemCounter = itemHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
itemCounter:SetPoint("TOPRIGHT", skipBtn, "TOPLEFT", -8, -6)

-- Fixed realm table (clips children to prevent overflow during resize)
local realmFrame = CreateFrame("Frame", nil, reviewPanel)
realmFrame:SetHeight(100)
realmFrame:SetPoint("TOPLEFT", itemHeader, "BOTTOMLEFT", 0, 0)
realmFrame:SetPoint("RIGHT", reviewPanel, "RIGHT", 0, 0)
realmFrame:SetClipsChildren(true)

-- Research scroll
local researchScroll = CreateFrame("ScrollFrame", nil, reviewPanel, "UIPanelScrollFrameTemplate")
local researchContent = CreateFrame("Frame", nil, researchScroll)
researchContent:SetWidth(1); researchContent:SetHeight(1)
researchScroll:SetScrollChild(researchContent)
researchScroll:SetScript("OnSizeChanged", function(_, w) researchContent:SetWidth(w) end)

local realmResSep = reviewPanel:CreateTexture(nil, "ARTWORK")
realmResSep:SetHeight(1); realmResSep:SetColorTexture(0.3, 0.3, 0.4, 0.3)
realmResSep:SetPoint("TOPLEFT", realmFrame, "BOTTOMLEFT", 4, 0)
realmResSep:SetPoint("RIGHT", realmFrame, "RIGHT", -4, 0)

local bottomBar = CreateFrame("Frame", nil, reviewPanel)
bottomBar:SetHeight(32)
bottomBar:SetPoint("BOTTOMLEFT", reviewPanel, "BOTTOMLEFT", 0, 0)
bottomBar:SetPoint("BOTTOMRIGHT", reviewPanel, "BOTTOMRIGHT", 0, 0)
local bottomBg = bottomBar:CreateTexture(nil, "BACKGROUND")
bottomBg:SetAllPoints(); bottomBg:SetColorTexture(0.08, 0.08, 0.12, 1)

researchScroll:SetPoint("TOPLEFT", realmFrame, "BOTTOMLEFT", 0, -1)
researchScroll:SetPoint("BOTTOMRIGHT", bottomBar, "TOPRIGHT", -24, 0)

local backBtn = NavBtn(bottomBar, "< Back")
backBtn:SetPoint("LEFT", bottomBar, "LEFT", 8, 0)
local genBtn = NavBtn(bottomBar, "Generate To-Do", true)
genBtn:SetSize(140, 24); genBtn:SetPoint("CENTER", bottomBar, "CENTER", 0, 0)

local autoChk = CreateFrame("CheckButton", nil, bottomBar, "UICheckButtonTemplate")
autoChk:SetSize(22, 22); autoChk:SetPoint("LEFT", genBtn, "RIGHT", 8, 0); autoChk:SetChecked(true)
local autoLabel = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
autoLabel:SetPoint("LEFT", autoChk, "RIGHT", 2, 0); autoLabel:SetText("Auto-select by priority")
autoChk:SetScript("OnClick", function(self)
    autoGenerate = self:GetChecked()
    if autoGenerate and itemGroups and ns.DealFinder then
        ns.DealFinder:ApplyPriority(itemGroups, ns.db.settings.dfPriorityOrder)
        for _, group in ipairs(itemGroups) do ApplyQuantitySelection(group) end
        if currentIdx >= 1 then ShowItem(currentIdx) end
    end
end)

-- ==========================================
-- PHASE 3: TO-DO PREVIEW
-- ==========================================

local previewPanel = CreateFrame("Frame", nil, page)
previewPanel:SetAllPoints(); previewPanel:Hide()

-- Resolve price using the global dfPriceSource setting
local function ResolvePvPrice(item)
    local src = ns.db and ns.db.settings.dfPriceSource or "deal"
    if src == "deal" then
        if item.expectedPrice then
            return type(item.expectedPrice) == "number" and G(item.expectedPrice) or tostring(item.expectedPrice)
        end
        return ""
    end
    -- Live TSM lookup
    if ns.TSM and item.itemKey then
        local copper = ns.TSM:GetPrice(item.itemKey, src)
        if copper and copper > 0 then return G(copper) end
    end
    return "?"
end

local PRICE_LABELS = {
    deal = "Deal Price", DBMinBuyout = "Min Buyout", DBMarket = "Market",
    DBRegionMarketAvg = "Regional Mkt", DBRegionSaleAvg = "Sale Avg",
}

local pvHeader = CreateFrame("Frame", nil, previewPanel)
pvHeader:SetHeight(36)
pvHeader:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 0, 0)
pvHeader:SetPoint("RIGHT", previewPanel, "RIGHT", 0, 0)
local pvHeaderBg = pvHeader:CreateTexture(nil, "BACKGROUND")
pvHeaderBg:SetAllPoints(); pvHeaderBg:SetColorTexture(0.08, 0.08, 0.12, 1)
pvHeader.title = pvHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pvHeader.title:SetPoint("TOPLEFT", 10, -4); pvHeader.title:SetText("To-Do Preview")
pvHeader.summary = pvHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
pvHeader.summary:SetPoint("TOPLEFT", 10, -20)

local pvScroll = CreateFrame("ScrollFrame", nil, previewPanel, "UIPanelScrollFrameTemplate")
local pvContent = CreateFrame("Frame", nil, pvScroll)
pvContent:SetWidth(1); pvContent:SetHeight(1)
pvScroll:SetScrollChild(pvContent)
pvScroll:SetScript("OnSizeChanged", function(_, w) pvContent:SetWidth(w) end)

local pvBottom = CreateFrame("Frame", nil, previewPanel)
pvBottom:SetHeight(32)
pvBottom:SetPoint("BOTTOMLEFT", previewPanel, "BOTTOMLEFT", 0, 0)
pvBottom:SetPoint("BOTTOMRIGHT", previewPanel, "BOTTOMRIGHT", 0, 0)
local pvBottomBg = pvBottom:CreateTexture(nil, "BACKGROUND")
pvBottomBg:SetAllPoints(); pvBottomBg:SetColorTexture(0.08, 0.08, 0.12, 1)
pvScroll:SetPoint("TOPLEFT", pvHeader, "BOTTOMLEFT", 0, 0)
pvScroll:SetPoint("BOTTOMRIGHT", pvBottom, "TOPRIGHT", -24, 0)

local pvBackBtn = NavBtn(pvBottom, "< Back")
pvBackBtn:SetPoint("LEFT", pvBottom, "LEFT", 8, 0)
local pvSaveBtn = NavBtn(pvBottom, "Save To-Do", true)
pvSaveBtn:SetSize(120, 24); pvSaveBtn:SetPoint("CENTER", pvBottom, "CENTER", 0, 0)

local pvRows = {}
local ShowPreview
ShowPreview = function()
    if not dfPreview then return end
    for _, r in ipairs(pvRows) do r:Hide() end

    local y, ri = 0, 0
    local C = ns.COLORS or {}

    local function PvRow(text, indent, font, bgCol)
        ri = ri + 1
        local r = pvRows[ri]
        if not r then
            r = CreateFrame("Frame", nil, pvContent); r:SetHeight(18)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 4, 0); r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
            r.text:SetWordWrap(false)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
            pvRows[ri] = r
        end
        r.text:SetFontObject(font or "GameFontHighlightSmall")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", pvContent, "TOPLEFT", indent or 0, y)
        r:SetPoint("RIGHT", pvContent, "RIGHT", 0, 0)
        r.text:SetText(text); r.bg:SetShown(bgCol ~= nil)
        if bgCol then r.bg:SetColorTexture(unpack(bgCol)) end
        r:Show(); y = y - 18
    end

    -- Accept both .items and .tasks (different code paths use different names)
    local items    = dfPreview.items or dfPreview.tasks or {}
    local rejected = dfPreview.rejected or {}
    local overflow = dfPreview.overflow or {}
    local noDeals  = dfPreview.noDeals or {}

    local priceSrc = ns.db and ns.db.settings.dfPriceSource or "deal"
    local priceLabel = PRICE_LABELS[priceSrc] or priceSrc
    pvHeader.summary:SetText(#items .. " tasks  ·  " .. #rejected .. " excluded  ·  "
        .. #overflow .. " overflow  ·  " .. #noDeals .. " no deals  ·  Price: " .. priceLabel)

    -- Empty state
    if #items == 0 and #rejected == 0 and #overflow == 0 and #noDeals == 0 then
        PvRow("|cff888888No tasks could be generated. Check that characters have sell roles " ..
            "on the target realms and that inventory items match the selected deals.|r", 8)
        pvContent:SetHeight(40)
        return
    end

    -- Group items by assigned character
    local byChar, charOrder = {}, {}
    for _, item in ipairs(items) do
        local ck = item.assignedChar or "Unassigned"
        if not byChar[ck] then byChar[ck] = {}; table.insert(charOrder, ck) end
        table.insert(byChar[ck], item)
    end

    if #items == 0 and (#rejected > 0 or #overflow > 0 or #noDeals > 0) then
        PvRow("|cffaa6666No tasks assigned — all deals were excluded, overflow, or had no matches. See below.|r", 8)
        y = y - 4
    end

    for _, ck in ipairs(charOrder) do
        PvRow(ck, 0, "GameFontNormal", {0.1, 0.1, 0.15, 0.8})
        for _, item in ipairs(byChar[ck]) do
            local icon = item.icon and ("|T" .. item.icon .. ":14:14:0:0|t ") or ""
            local realm = item.targetRealm and ("  →  " .. item.targetRealm) or ""
            local priceStr = ResolvePvPrice(item)
            if priceStr ~= "" then priceStr = "  " .. priceStr end
            PvRow("  " .. icon .. (item.name or "?") .. "  x" .. (item.quantity or 1) .. realm .. priceStr, 8)
        end
        y = y - 4
    end

    if #rejected > 0 then
        y = y - 4
        PvRow("Excluded (" .. #rejected .. ")  |cff666666click to restore|r", 0, "GameFontNormal", {0.15, 0.1, 0.1, 0.8})
        for rejIdx, item in ipairs(rejected) do
            local icon = item.icon and ("|T" .. item.icon .. ":14:14:0:0|t ") or ""
            PvRow("  " .. icon .. "|cffaa8866" .. (item.name or "?") .. "|r  |cff888888" .. (item.failReason or "") .. "|r", 8, "GameFontDisableSmall")
            -- Make clickable to restore to items list
            local row = pvRows[ri]
            if row then
                local capturedIdx = rejIdx
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(s) if s.bg then s.bg:SetColorTexture(0.2, 0.15, 0.1, 0.5); s.bg:Show() end end)
                row:SetScript("OnLeave", function(s) if s.bg then s.bg:Hide() end end)
                row:SetScript("OnMouseDown", function()
                    if dfPreview and dfPreview.rejected then
                        local restored = table.remove(dfPreview.rejected, capturedIdx)
                        if restored then
                            restored.status = "pending"
                            restored.failReason = restored.failReason and ("(restored) " .. restored.failReason) or nil
                            local dest = dfPreview.items or dfPreview.tasks
                            if dest then table.insert(dest, restored) end
                            ShowPreview()
                        end
                    end
                end)
            end
        end
    end

    if #overflow > 0 then
        y = y - 4
        PvRow("Overflow Deals (" .. #overflow .. ")", 0, "GameFontNormal", {0.1, 0.1, 0.15, 0.8})
        for _, item in ipairs(overflow) do
            local icon = item.icon and ("|T" .. item.icon .. ":14:14:0:0|t ") or ""
            local realm = item.targetRealm and (" → " .. item.targetRealm) or ""
            PvRow("  " .. icon .. "|cff888888" .. (item.name or "?") .. realm .. "|r", 8, "GameFontDisableSmall")
        end
    end

    if #noDeals > 0 then
        y = y - 4
        PvRow("No Deals (" .. #noDeals .. ")", 0, "GameFontNormal", {0.15, 0.1, 0.1, 0.8})
        for _, item in ipairs(noDeals) do
            local icon = item.icon and ("|T" .. item.icon .. ":14:14:0:0|t ") or ""
            PvRow("  " .. icon .. "|cff666666" .. (item.name or "?") .. "|r  qty " .. (item.totalQuantity or 0), 8, "GameFontDisableSmall")
        end
    end

    pvContent:SetHeight(math.abs(y) + 20)
end

-- ==========================================
-- DYNAMIC COLUMNS + RESIZE
-- ==========================================

local MIN_COL_W = 200
local function GetRealmCols(w)
    if not w or w <= 0 then w = 600 end
    return math.max(1, math.min(5, math.floor(w / MIN_COL_W)))
end

-- Forward declare ShowItem (defined below) so resize handler can reference it
local ShowItem

-- Fast debounce (10ms) for review panel resize during drag
local resizeTimer
reviewPanel:SetScript("OnSizeChanged", function()
    if resizeTimer then resizeTimer:Cancel() end
    if currentIdx >= 1 and itemGroups and ShowItem then
        resizeTimer = C_Timer.NewTimer(0.01, function()
            resizeTimer = nil
            if currentIdx >= 1 and itemGroups and ShowItem then ShowItem(currentIdx) end
        end)
    end
end)

-- ==========================================
-- QUANTITY-AWARE SELECTION
-- ==========================================

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
ApplyQuantitySelection = ApplyQuantitySelectionFn

local function CountSelections(group)
    local n = 0
    for _, r in ipairs(group.realms) do
        if r._selected ~= false then n = n + 1 end
    end
    return n
end

-- ==========================================
-- SHOW ITEM
-- ==========================================

ShowItem = function(idx)
    if not itemGroups or idx < 1 or idx > #itemGroups then return end
    currentIdx = idx
    local group = itemGroups[idx]

    UI:RenderDealFinderHeader(itemHeader, group)
    itemCounter:SetText("Item " .. idx .. " / " .. #itemGroups)
    prevBtn:SetShown(idx > 1)
    nextBtn:SetShown(idx < #itemGroups)

    UI:ResetDealFinderPool()

    local availW = realmFrame:GetWidth()
    if availW <= 0 then availW = reviewPanel:GetWidth() or 600 end
    if availW <= 0 then availW = 600 end

    local realmH = UI:RenderDealFinderRealmTable(realmFrame, group, GetRealmCols(availW), function(realmIdx)
        local realm = group.realms[realmIdx]
        if realm then
            realm._selected = not (realm._selected ~= false)
            ShowItem(idx)
        end
    end)
    realmFrame:SetHeight(realmH)

    UI:RenderDealFinderResearch(researchContent, group)
    researchScroll:SetVerticalScroll(0)
end

-- ==========================================
-- NAV HANDLERS
-- ==========================================

prevBtn:SetScript("OnClick", function()
    if currentIdx > 1 then ShowItem(currentIdx - 1) end
end)

nextBtn:SetScript("OnClick", function()
    if not itemGroups or currentIdx >= #itemGroups then return end
    local group = itemGroups[currentIdx]
    if group then
        local sel = CountSelections(group)
        local qty = group.quantity or 1
        if sel > qty then
            ns:Print((ns.COLORS and ns.COLORS.RED or "")
                .. "Too many realms selected (" .. sel .. ") for qty " .. qty
                .. ". Deselect some before proceeding.|r")
            return
        end
    end
    ShowItem(currentIdx + 1)
end)

skipBtn:SetScript("OnClick", function()
    if not itemGroups or not itemGroups[currentIdx] then return end
    itemGroups[currentIdx].denied = true
    for _, r in ipairs(itemGroups[currentIdx].realms) do r._selected = false end
    if currentIdx < #itemGroups then ShowItem(currentIdx + 1)
    else ShowItem(currentIdx) end
end)

backBtn:SetScript("OnClick", function()
    itemGroups = nil; currentIdx = 0
    previewMode = false; dfPreview = nil
    UI:ResetDealFinderPool()
    UI:RefreshDealFinderPage()
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
    pool = FilterPoolByLocation(pool, locationFilter)
    if not pool or #pool == 0 then
        ns:Print("No tradeable items" .. (filterMode ~= "all" and " (try All)" or "")); return
    end

    itemGroups = nil; currentIdx = 0; previewMode = false; dfPreview = nil
    ShowProgress(0, #pool)

    ns.DealFinder:ScanChunked(pool,
        function(p, t) ShowProgress(p, t) end,
        function(result)
            HideProgress()
            if not result then return end
            itemGroups = result.itemGroups
            for _, group in ipairs(itemGroups) do ApplyQuantitySelectionFn(group) end
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
-- GENERATE (transitions to preview)
-- ==========================================

genBtn:SetScript("OnClick", function()
    if not itemGroups then return end

    for _, g in ipairs(itemGroups) do
        if not g.denied then
            local sel = CountSelections(g)
            if sel > (g.quantity or 1) then
                ns:Print((ns.COLORS and ns.COLORS.RED or "")
                    .. "\"" .. (g.name or "?") .. "\" has " .. sel
                    .. " realms but only " .. (g.quantity or 1)
                    .. " available. Fix before generating.|r")
                return
            end
        end
    end

    local count = ns.DealFinder:SaveSelectedToImports(itemGroups)
    if count == 0 then ns:Print("No deals selected."); return end

    local dfOrder = ns.db and ns.db.settings.dfPriorityOrder or {"profit"}
    local genOrder = {}
    for _, k in ipairs(dfOrder) do
        if k == "profit" then table.insert(genOrder, "gold")
        else table.insert(genOrder, k) end
    end
    if #genOrder == 0 then genOrder = {"gold"} end

    dfPreview = ns.TodoList:GenerateTodoList("dealFinder", genOrder)
    if dfPreview then
        dfPreview.name = "Deal Finder " .. date("%Y-%m-%d %H:%M")
        previewMode = true
        UI:RefreshDealFinderPage()
    else
        ns:Print("Failed to generate preview.")
    end
end)

-- ==========================================
-- PREVIEW HANDLERS
-- ==========================================

pvSaveBtn:SetScript("OnClick", function()
    if not dfPreview then return end
    ns.TodoList:CommitList(dfPreview, "replace")
    local tc = (dfPreview.items or dfPreview.tasks)
    local taskCount = tc and #tc or 0
    ns:Print(string.format("%s%d tasks|r generated.", ns.COLORS and ns.COLORS.GREEN or "", taskCount))
    previewMode = false; dfPreview = nil; itemGroups = nil; currentIdx = 0
    UI.currentPage = "todo"; UI:Refresh()
end)

pvBackBtn:SetScript("OnClick", function()
    previewMode = false; dfPreview = nil
    UI:RefreshDealFinderPage()
end)

-- ==========================================
-- REFRESH
-- ==========================================

function UI:RefreshDealFinderPage()
    local mainFrame = UI.mainFrame
    mainFrame.pageTitle:SetText("Deal Finder")
    for _, btn in pairs(mainFrame.actionBtns) do btn:Hide() end
    page:Show()

    if previewMode and dfPreview then
        configPanel:Hide(); reviewPanel:Hide(); previewPanel:Show()
        ShowPreview()
        local tc = (dfPreview.items or dfPreview.tasks)
        mainFrame.statusText:SetText("Preview: " .. (tc and #tc or 0) .. " tasks  |  Save or go back to adjust")
    elseif itemGroups and #itemGroups > 0 and currentIdx >= 1 then
        configPanel:Hide(); previewPanel:Hide(); reviewPanel:Show()
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
        reviewPanel:Hide(); previewPanel:Hide(); configPanel:Show()
        SetFilter(filterMode); SetLocationFilter(locationFilter)
        RefreshFilterSubs(); RenderPriority()
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
-- RESIZE CALLBACK (handles main frame + sidebar drag)
-- ==========================================

UI:RegisterPageLayout("deals", function()
    if not page or not page:IsShown() then return end
    if previewMode and dfPreview then
        ShowPreview()
    elseif currentIdx >= 1 and itemGroups then
        ShowItem(currentIdx)
    elseif configPanel:IsShown() then
        RefreshInventoryPreview()
    end
end)

-- ==========================================
-- EXPOSE
-- ==========================================

UI._dealFinderPage = page
