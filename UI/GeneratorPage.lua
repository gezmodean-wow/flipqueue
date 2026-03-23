-- UI/GeneratorPage.lua
-- To-Do Generator: wizard-based workflow with inventory scan and cross-realm tracks
local addonName, ns = ...

local UI = ns.UI

-- ==========================================
-- SECTION 1: STATE VARIABLES & ACCESSORS
-- ==========================================

-- Generator state (session + persisted)
UI._generatorPreview = UI._generatorPreview or nil
UI._genListCollapsed = UI._genListCollapsed or {}
UI._genFilterMode = UI._genFilterMode or "all"
UI._genFilterValue = UI._genFilterValue or ""
UI._genExcludedItems = UI._genExcludedItems or {}

-- Wizard state: track and step
-- track: nil (not chosen), "inventory", "crossrealm"
-- step: 0 = track selection, 1-3 = wizard steps
UI._wizardTrack = UI._wizardTrack or nil
UI._wizardStep = UI._wizardStep or 0

-- Sync filter state from DB settings (called after InitDB)
function UI:InitGenFilterFromDB()
    if ns.db and ns.db.settings then
        UI._genFilterMode = ns.db.settings.genFilterMode or "all"
        UI._genFilterValue = ns.db.settings.genFilterValue or ""
        -- Restore wizard state
        UI._wizardTrack = ns.db.settings.wizardTrack or nil
        UI._wizardStep = ns.db.settings.wizardStep or 0
    end
end

-- Save filter state to DB settings
local function SaveGenFilter(mode, value)
    UI._genFilterMode = mode
    UI._genFilterValue = value or ""
    if ns.db and ns.db.settings then
        ns.db.settings.genFilterMode = mode
        ns.db.settings.genFilterValue = value or ""
    end
end

-- Save wizard state to DB
local function SaveWizardState(track, step)
    UI._wizardTrack = track
    UI._wizardStep = step
    if ns.db and ns.db.settings then
        ns.db.settings.wizardTrack = track
        ns.db.settings.wizardStep = step
    end
end

-- Auto-generate: build preview from current filter settings
local function AutoGenerate()
    if not ns.TodoList then return end
    local allocationOrder = UI:GetGenAllocationOrder()
    UI._generatorPreview = ns.TodoList:GenerateTodoList("fpScanner", allocationOrder)
end

-- Accessors that read/write DB settings (with fallback defaults for before InitDB runs)
function UI:GetGenAllocationOrder()
    if ns.db and ns.db.settings.genAllocationOrder then
        return ns.db.settings.genAllocationOrder
    end
    return {"gold", "noCompetition", "population"}
end

function UI:GetGenSortMode()
    if ns.db and ns.db.settings.genSortMode then
        return ns.db.settings.genSortMode
    end
    return "profit"
end

function UI:SetGenSortMode(mode)
    if ns.db then
        ns.db.settings.genSortMode = mode
    end
end

-- ==========================================
-- SECTION 2: BuildGeneratorPreviewData
-- ==========================================

local function BuildGeneratorPreviewData(todoList)
    if not todoList or not todoList.items then return {} end
    local data = {}

    local LookupItemInfo = UI._LookupItemInfo
    local QualityColorName = UI._QualityColorName
    local CLASS_COLORS = UI._CLASS_COLORS

    for _, item in ipairs(todoList.items) do
        local displayName = item.name or "?"
        local lookupIcon, quality, resolvedID
        pcall(function()
            lookupIcon, quality, resolvedID = LookupItemInfo(item.itemID, item.itemKey, item.name)
        end)

        if quality then
            displayName = QualityColorName(displayName, quality)
        elseif item.quality and item.quality ~= "" then
            displayName = QualityColorName(displayName, item.quality)
        end

        local isBuyTask = item.action == "buy"

        local statusStr, sortStatus
        if isBuyTask and item.status == "pending" then
            statusStr = ns.COLORS.CYAN .. "Buy" .. "|r"
            sortStatus = 1
        elseif item.status == "pending" then
            statusStr = ns.COLORS.GREEN .. "Ready" .. "|r"
            sortStatus = 1
        elseif item.status == "unassigned" then
            statusStr = ns.COLORS.ORANGE .. "No char" .. "|r"
            sortStatus = 2
        elseif item.status == "missing" then
            statusStr = ns.COLORS.RED .. "Missing" .. "|r"
            sortStatus = 3
        elseif item.status == "posted" then
            statusStr = ns.COLORS.GRAY .. "Posted" .. "|r"
            sortStatus = 4
        elseif item.status == "skipped" then
            statusStr = ns.COLORS.ORANGE .. "Skipped" .. "|r"
            sortStatus = 5
        else
            statusStr = item.status or "?"
            sortStatus = 6
        end

        local charDisplay = ""
        if item.assignedChar then
            local name = item.assignedChar:match("^(.-)%-") or item.assignedChar
            local charData = ns.db.characters and ns.db.characters[item.assignedChar]
            local classColor = charData and (UI._CLASS_COLORS or {})[charData.class] or "888888"
            charDisplay = "|cff" .. classColor .. name .. "|r"
        end

        local sourceStr = item.source or ""
        if isBuyTask then
            sourceStr = ns.COLORS.CYAN .. "buy@" .. (item.buyRealm or "?") .. "|r"
        elseif sourceStr == "warbank" then
            sourceStr = ns.COLORS.YELLOW .. "warbank" .. "|r"
        elseif sourceStr == "bags" then
            sourceStr = ns.COLORS.GREEN .. "bags" .. "|r"
        elseif sourceStr == "bank" then
            sourceStr = ns.COLORS.BLUE .. "bank" .. "|r"
        elseif sourceStr == "guildbank" then
            sourceStr = ns.COLORS.ORANGE .. "guild" .. "|r"
        elseif sourceStr == "unavailable" and item.depositFrom then
            local depName = item.depositFrom:match("^(.-)%-") or item.depositFrom
            sourceStr = ns.COLORS.CYAN .. "via " .. depName .. "|r"
        elseif sourceStr == "unavailable" then
            sourceStr = ns.COLORS.RED .. "unavail" .. "|r"
        end

        local priceDisplay = isBuyTask and item.buyPrice or item.expectedPrice or ""
        local realmDisplay = item.targetRealm or ""
        if isBuyTask and item.buyRealm then
            realmDisplay = ns.COLORS.CYAN .. item.buyRealm .. "|r"
        end

        local rowColor = nil
        if item.status == "missing" then
            rowColor = {0.8, 0.2, 0.2, 0.08}
        elseif item.status == "unassigned" then
            rowColor = {0.8, 0.5, 0.1, 0.08}
        elseif isBuyTask then
            rowColor = {0.1, 0.4, 0.6, 0.08}
        end

        local tooltipExtra = ""
        if isBuyTask then
            tooltipExtra = "Buy on: " .. (item.buyRealm or "?")
                .. "\nBuy price: " .. (item.buyPrice or "?")
                .. "\nSell on: " .. (item.targetRealm or "?")
                .. "\nSell price: " .. (item.expectedPrice or "?")
                .. (item.profitAmount and ("\nProfit: " .. item.profitAmount) or "")
                .. (item.profitPct and (" (" .. item.profitPct .. "%)") or "")
        else
            tooltipExtra = (item.targetRealm and item.targetRealm ~= ""
                    and ("Realm: " .. item.targetRealm) or "")
                .. (item.assignedChar and ("\nCharacter: " .. item.assignedChar) or "")
                .. (item.source and ("\nSource: " .. item.source) or "")
                .. (item.expectedPrice and ("\nPrice: " .. item.expectedPrice) or "")
                .. (item.buyRealm and item.buyRealm ~= ""
                    and ("\nCross-realm: buy on " .. item.buyRealm .. " @ " .. (item.buyPrice or "?")) or "")
        end
        if item.failReason then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.RED .. item.failReason .. "|r"
        end

        table.insert(data, {
            name      = displayName,
            qty       = item.quantity or 1,
            realm     = realmDisplay,
            character = charDisplay,
            source    = sourceStr,
            price     = priceDisplay,
            status    = statusStr,
            _icon     = item.icon or lookupIcon,
            _sortStatus = sortStatus,
            _rowColor = rowColor,
            _tooltipItemID = resolvedID or tonumber(item.itemID),
            _tooltipText = item.name or "?",
            _tooltipExtra = tooltipExtra,
        })
    end

    return data
end

-- ==========================================
-- REUSABLE WIDGET: toggle button
-- ==========================================

local function CreateToggleBtn(parent, label)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(18)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetWidth(btn.text:GetStringWidth() + 14)
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
    return btn
end

local function SetToggleActive(btn, active)
    btn._active = active
    if active then
        btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
    else
        btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    end
end

-- ==========================================
-- REUSABLE WIDGET: small action button
-- ==========================================

local function CreateSmallActionBtn(parent, label, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 16)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.5, 0.5, 0.5)
        GameTooltip:Hide()
    end)
    return btn
end

-- ==========================================
-- REUSABLE WIDGET: styled header button
-- ==========================================

local function CreateHeaderBtn(parent, label, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(18)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetWidth(btn.text:GetStringWidth() + 16)
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.3, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tooltip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        GameTooltip:Hide()
    end)
    return btn
end

-- ==========================================
-- SECTION 3: WIZARD STEP BAR
-- ==========================================

-- Step labels per track
local STEP_LABELS = {
    inventory  = {"Build Inventory", "Import Deals", "Configure & Generate"},
    crossrealm = {"Import Deals", "Filter Deals", "Configure & Generate"},
}

local function CreateStepBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(50)

    bar.circles = {}
    bar.labels = {}
    bar.lines = {}

    for i = 1, 3 do
        -- Circle background
        local circle = CreateFrame("Button", nil, bar)
        circle:SetSize(24, 24)
        circle.bg = circle:CreateTexture(nil, "BACKGROUND")
        circle.bg:SetAllPoints()
        circle.bg:SetColorTexture(0.3, 0.3, 0.3, 1)

        circle.num = circle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        circle.num:SetPoint("CENTER")
        circle.num:SetText(i)
        circle.num:SetTextColor(1, 1, 1)

        bar.circles[i] = circle

        -- Label below circle
        local label = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOP", circle, "BOTTOM", 0, -2)
        label:SetTextColor(0.6, 0.6, 0.6)
        bar.labels[i] = label

        -- Connecting line (between circles, so only 2 lines)
        if i < 3 then
            local line = bar:CreateTexture(nil, "ARTWORK")
            line:SetHeight(2)
            line:SetColorTexture(0.3, 0.3, 0.3, 1)
            bar.lines[i] = line
        end
    end

    function bar:Update(track, currentStep)
        local stepLabels = STEP_LABELS[track] or STEP_LABELS.inventory
        local totalWidth = bar:GetWidth()
        local spacing = totalWidth > 0 and (totalWidth / 4) or 120

        for i = 1, 3 do
            local circle = bar.circles[i]
            local label = bar.labels[i]

            -- Position
            circle:ClearAllPoints()
            circle:SetPoint("TOP", bar, "TOPLEFT", spacing * i, -2)
            label:SetText(stepLabels[i])

            -- Color based on state
            if i < currentStep then
                -- Completed
                circle.bg:SetColorTexture(0.2, 0.7, 0.2, 1)
                circle.num:SetTextColor(1, 1, 1)
                label:SetTextColor(0.5, 0.8, 0.5)
                circle:EnableMouse(true)
                circle:SetScript("OnClick", function()
                    SaveWizardState(track, i)
                    UI:Refresh()
                end)
                circle:SetScript("OnEnter", function(self)
                    self.bg:SetColorTexture(0.3, 0.8, 0.3, 1)
                end)
                circle:SetScript("OnLeave", function(self)
                    self.bg:SetColorTexture(0.2, 0.7, 0.2, 1)
                end)
            elseif i == currentStep then
                -- Active
                circle.bg:SetColorTexture(0.8, 0.6, 0, 1)
                circle.num:SetTextColor(0, 0, 0)
                label:SetTextColor(1, 0.85, 0.3)
                circle:EnableMouse(false)
                circle:SetScript("OnClick", nil)
                circle:SetScript("OnEnter", nil)
                circle:SetScript("OnLeave", nil)
            else
                -- Future
                circle.bg:SetColorTexture(0.3, 0.3, 0.3, 1)
                circle.num:SetTextColor(0.6, 0.6, 0.6)
                label:SetTextColor(0.4, 0.4, 0.4)
                circle:EnableMouse(false)
                circle:SetScript("OnClick", nil)
                circle:SetScript("OnEnter", nil)
                circle:SetScript("OnLeave", nil)
            end
        end

        -- Lines between circles
        for i = 1, 2 do
            local line = bar.lines[i]
            line:ClearAllPoints()
            line:SetPoint("LEFT", bar.circles[i], "RIGHT", 2, 0)
            line:SetPoint("RIGHT", bar.circles[i + 1], "LEFT", -2, 0)

            if i < currentStep then
                line:SetColorTexture(0.2, 0.7, 0.2, 1)
            elseif i == currentStep then
                line:SetColorTexture(0.8, 0.6, 0, 0.5)
            else
                line:SetColorTexture(0.3, 0.3, 0.3, 1)
            end
        end
    end

    return bar
end

-- ==========================================
-- SECTION 4: TRACK SELECTION PANEL
-- ==========================================

local function CreateTrackCard(parent, title, subtitle, iconPath)
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(260, 120)
    card:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    card:SetBackdropColor(0.12, 0.12, 0.15, 1)
    card:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.8)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(40, 40)
    card.icon:SetPoint("TOP", card, "TOP", 0, -16)
    card.icon:SetTexture(iconPath)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOP", card.icon, "BOTTOM", 0, -6)
    card.title:SetText(title)
    card.title:SetTextColor(1, 1, 1)

    card.subtitle = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.subtitle:SetPoint("TOP", card.title, "BOTTOM", 0, -4)
    card.subtitle:SetText(subtitle)
    card.subtitle:SetTextColor(0.6, 0.6, 0.6)

    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.6, 0.6, 0.7, 1)
        self:SetBackdropColor(0.16, 0.16, 0.2, 1)
    end)
    card:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.8)
        self:SetBackdropColor(0.12, 0.12, 0.15, 1)
    end)

    return card
end

-- ==========================================
-- SECTION 5: NAVIGATION BUTTONS
-- ==========================================

local function CreateNavButton(parent, label)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(80, 26)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.3, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
    end)
    return btn
end

-- ==========================================
-- SECTION 9: RefreshGeneratorPage ORCHESTRATOR
-- ==========================================

function UI:RefreshGeneratorPage(pending)
    local mainFrame = self.mainFrame
    local tableContainer = self.tableContainer
    local HideAllActionBtns = self._HideAllActionBtns
    local CLASS_COLORS = self._CLASS_COLORS or {}
    local FormatGoldValue = self._FormatGoldValue

    mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "To-Do Generator" .. "|r")
    HideAllActionBtns()

    local currentList = ns.TodoList and ns.TodoList:GetCurrentList()

    -- ========================================
    -- CREATE ALL FRAMES (once)
    -- ========================================
    if not self._genFrame then
        local gf = CreateFrame("Frame", nil, tableContainer)
        gf:SetAllPoints()

        -- ---- TOP SECTION: list queue ----
        gf.topSection = CreateFrame("Frame", nil, gf)
        gf.topSection:SetPoint("TOPLEFT", gf, "TOPLEFT", 0, 0)
        gf.topSection:SetPoint("TOPRIGHT", gf, "TOPRIGHT", 0, 0)
        gf.topSection:SetHeight(20)
        gf.topSection.bg = gf.topSection:CreateTexture(nil, "BACKGROUND")
        gf.topSection.bg:SetAllPoints()
        gf.topSection.bg:SetColorTexture(0.08, 0.08, 0.12, 0.8)
        gf.topRows = {}
        gf.topActionBtns = {}

        -- Inline rename editbox (reusable)
        gf.renameBox = CreateFrame("EditBox", nil, gf, "InputBoxTemplate")
        gf.renameBox:SetSize(150, 18)
        gf.renameBox:SetAutoFocus(false)
        gf.renameBox:SetMaxLetters(60)
        gf.renameBox:Hide()
        gf.renameBox:SetScript("OnEscapePressed", function(self) self:Hide() end)

        -- ---- STEP BAR ----
        gf.stepBar = CreateStepBar(gf)
        gf.stepBar:SetPoint("TOPLEFT", gf.topSection, "BOTTOMLEFT", 0, -2)
        gf.stepBar:SetPoint("TOPRIGHT", gf.topSection, "BOTTOMRIGHT", 0, -2)
        gf.stepBar:Hide()

        -- ---- TRACK SELECTION PANEL (step 0) ----
        gf.trackSelectPanel = CreateFrame("Frame", nil, gf)
        gf.trackSelectPanel:Hide()

        gf.trackSelectPanel.title = gf.trackSelectPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        gf.trackSelectPanel.title:SetPoint("TOP", gf.trackSelectPanel, "TOP", 0, -30)
        gf.trackSelectPanel.title:SetText("How would you like to generate your To-Do list?")
        gf.trackSelectPanel.title:SetTextColor(0.9, 0.9, 0.9)

        gf.trackSelectPanel.inventoryCard = CreateTrackCard(
            gf.trackSelectPanel,
            "Inventory Scan",
            "I have items to sell",
            "Interface\\Icons\\INV_Misc_Bag_07")
        gf.trackSelectPanel.inventoryCard:SetPoint("RIGHT", gf.trackSelectPanel, "CENTER", -10, 0)
        gf.trackSelectPanel.inventoryCard:SetScript("OnClick", function()
            SaveWizardState("inventory", 1)
            UI:Refresh()
        end)

        gf.trackSelectPanel.crossrealmCard = CreateTrackCard(
            gf.trackSelectPanel,
            "Cross-Realm Import",
            "I want to buy and flip across realms",
            "Interface\\Icons\\INV_Misc_Map_01")
        gf.trackSelectPanel.crossrealmCard:SetPoint("LEFT", gf.trackSelectPanel, "CENTER", 10, 0)
        gf.trackSelectPanel.crossrealmCard:SetScript("OnClick", function()
            SaveWizardState("crossrealm", 1)
            UI:Refresh()
        end)

        -- ---- NAV BUTTONS (Back / Next) ----
        gf.backBtn = CreateNavButton(gf, "Back")
        gf.backBtn:SetPoint("BOTTOMLEFT", gf, "BOTTOMLEFT", 8, 6)
        gf.backBtn:Hide()

        gf.nextBtn = CreateNavButton(gf, "Next")
        gf.nextBtn:SetPoint("BOTTOMRIGHT", gf, "BOTTOMRIGHT", -8, 6)
        gf.nextBtn:Hide()

        gf.saveBtn = CreateNavButton(gf, "Save")
        gf.saveBtn:SetPoint("RIGHT", gf.nextBtn, "LEFT", -4, 0)
        gf.saveBtn:Hide()
        gf.saveBtn:SetBackdropColor(0.15, 0.25, 0.15, 1)
        gf.saveBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 0.8)
        gf.saveBtn.text:SetTextColor(0.3, 1, 0.3)

        -- ---- STEP CONTAINERS ----
        gf.stepContainers = {}
        for i = 1, 3 do
            local sc = CreateFrame("Frame", nil, gf)
            sc:Hide()
            gf.stepContainers[i] = sc
        end

        -- ===== STEP 1 CONTAINER: Build Inventory =====
        local s1 = gf.stepContainers[1]

        -- Filter description
        s1.filterDesc = s1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        s1.filterDesc:SetPoint("TOPLEFT", s1, "TOPLEFT", 6, -4)
        s1.filterDesc:SetPoint("RIGHT", s1, "RIGHT", -6, 0)
        s1.filterDesc:SetJustifyH("LEFT")
        s1.filterDesc:SetWordWrap(true)
        s1.filterDesc:SetTextColor(0.45, 0.45, 0.45)
        s1.filterDesc:SetText("Narrow which inventory items to consider for your to-do list.")

        s1.filterLabel = s1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s1.filterLabel:SetPoint("TOPLEFT", s1.filterDesc, "BOTTOMLEFT", 0, -4)
        s1.filterLabel:SetText("Only show items in:")
        s1.filterLabel:SetTextColor(0.7, 0.7, 0.7)

        s1.filterAll = CreateToggleBtn(s1, "All")
        s1.filterAll:SetPoint("LEFT", s1.filterLabel, "RIGHT", 4, 0)
        s1.filterAll:SetScript("OnClick", function()
            SaveGenFilter("all", "")
            AutoGenerate()
            UI:Refresh()
        end)

        s1.filterTSM = CreateToggleBtn(s1, "TSM Group")
        s1.filterTSM:SetPoint("LEFT", s1.filterAll, "RIGHT", 2, 0)
        s1.filterTSM:SetScript("OnClick", function()
            SaveGenFilter("tsm", UI._genFilterValue)
            AutoGenerate()
            UI:Refresh()
        end)

        s1.filterAuct = CreateToggleBtn(s1, "Auctionator List")
        s1.filterAuct:SetPoint("LEFT", s1.filterTSM, "RIGHT", 2, 0)
        s1.filterAuct:SetScript("OnClick", function()
            SaveGenFilter("auctionator", UI._genFilterValue)
            AutoGenerate()
            UI:Refresh()
        end)

        -- TSM Group Tree container
        s1.treeFrame = CreateFrame("Frame", nil, s1)
        s1.treeFrame:SetHeight(100)
        s1.treeFrame:Hide()

        s1.tsmProfileLabel = s1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        s1.tsmProfileLabel:SetTextColor(0.5, 0.5, 0.5)
        s1.tsmProfileLabel:Hide()

        s1.tsmSelectedLabel = s1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s1.tsmSelectedLabel:SetTextColor(0.9, 0.8, 0.3)
        s1.tsmSelectedLabel:Hide()

        s1.tsmClearBtn = CreateFrame("Button", nil, s1)
        s1.tsmClearBtn:SetSize(60, 16)
        s1.tsmClearBtn.text = s1.tsmClearBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        s1.tsmClearBtn.text:SetPoint("CENTER")
        s1.tsmClearBtn.text:SetText("[show all]")
        s1.tsmClearBtn:SetScript("OnClick", function()
            SaveGenFilter("tsm", "")
            if s1.groupTree then
                s1.groupTree._selectedPath = nil
            end
            AutoGenerate()
            UI:Refresh()
        end)
        s1.tsmClearBtn:SetScript("OnEnter", function(self)
            self.text:SetTextColor(1, 1, 1)
        end)
        s1.tsmClearBtn:SetScript("OnLeave", function(self)
            self.text:SetTextColor(0.5, 0.5, 0.5)
        end)
        s1.tsmClearBtn:Hide()

        s1.tsmUnavail = s1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        s1.tsmUnavail:SetTextColor(0.8, 0.4, 0.4)
        s1.tsmUnavail:SetText("TSM is not enabled. Enable it on the TSM page.")
        s1.tsmUnavail:Hide()

        -- Auctionator list selector
        s1.auctFrame = CreateFrame("Frame", nil, s1)
        s1.auctFrame:SetHeight(80)
        s1.auctFrame:Hide()

        s1.auctLabel = s1.auctFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        s1.auctLabel:SetPoint("TOPLEFT", s1.auctFrame, "TOPLEFT", 6, 0)
        s1.auctLabel:SetText("Shopping List:")
        s1.auctLabel:SetTextColor(0.5, 0.5, 0.5)

        s1.auctScroll = CreateFrame("ScrollFrame", nil, s1.auctFrame, "UIPanelScrollFrameTemplate")
        s1.auctScroll:SetPoint("TOPLEFT", s1.auctLabel, "BOTTOMLEFT", 0, -4)
        s1.auctScroll:SetPoint("BOTTOMRIGHT", s1.auctFrame, "BOTTOMRIGHT", -16, 0)

        s1.auctContent = CreateFrame("Frame", nil, s1.auctScroll)
        s1.auctContent:SetWidth(1)
        s1.auctContent:SetHeight(1)
        s1.auctScroll:SetScrollChild(s1.auctContent)
        s1.auctScroll:SetScript("OnSizeChanged", function(sf, w)
            s1.auctContent:SetWidth(w)
        end)
        s1.auctRows = {}

        s1.auctUnavail = s1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        s1.auctUnavail:SetTextColor(0.8, 0.4, 0.4)
        s1.auctUnavail:SetWordWrap(true)
        s1.auctUnavail:Hide()

        -- Item pool scroll area
        s1.poolScroll = CreateFrame("ScrollFrame", nil, s1, "UIPanelScrollFrameTemplate")
        s1.poolContent = CreateFrame("Frame", nil, s1.poolScroll)
        s1.poolScroll:SetScrollChild(s1.poolContent)
        s1.poolScroll:SetScript("OnSizeChanged", function(sf, w)
            s1.poolContent:SetWidth(w)
        end)
        s1.poolRows = {}

        s1.poolDivider = s1:CreateTexture(nil, "ARTWORK")
        s1.poolDivider:SetHeight(1)
        s1.poolDivider:SetColorTexture(0.3, 0.3, 0.4, 0.5)

        s1.countLabel = s1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

        -- Footer: Export to FP button
        s1.footerBar = CreateFrame("Frame", nil, s1)
        s1.footerBar:SetHeight(26)
        s1.footerBar:SetPoint("BOTTOMLEFT", s1, "BOTTOMLEFT", 0, 0)
        s1.footerBar:SetPoint("BOTTOMRIGHT", s1, "BOTTOMRIGHT", 0, 0)
        local fbBg = s1.footerBar:CreateTexture(nil, "BACKGROUND")
        fbBg:SetAllPoints()
        fbBg:SetColorTexture(0.1, 0.1, 0.15, 1)

        s1.exportBtn = CreateFrame("Button", nil, s1.footerBar, "BackdropTemplate")
        s1.exportBtn:SetHeight(20)
        s1.exportBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        s1.exportBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        s1.exportBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        s1.exportBtn.text = s1.exportBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s1.exportBtn.text:SetPoint("CENTER")
        s1.exportBtn.text:SetText("Export List to FP")
        s1.exportBtn:SetWidth(s1.exportBtn.text:GetStringWidth() + 20)
        s1.exportBtn:SetPoint("CENTER", s1.footerBar, "CENTER", 0, 0)
        s1.exportBtn:SetScript("OnClick", function()
            local btn = UI.mainFrame and UI.mainFrame.actionBtns and UI.mainFrame.actionBtns.exportPoolToFP
            if btn then btn:GetScript("OnClick")() end
        end)
        s1.exportBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.3, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Export filtered item pool as FP CSV", 1, 1, 1)
            GameTooltip:Show()
        end)
        s1.exportBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
            GameTooltip:Hide()
        end)

        -- TSM Group Tree (if available)
        if UI.CreateGroupTree then
            s1.groupTree = UI:CreateGroupTree(s1.treeFrame, function(path)
                SaveGenFilter("tsm", path or "")
                AutoGenerate()
                UI:Refresh()
            end)
        end

        -- ===== STEP 2 CONTAINER: Import Deals =====
        local s2 = gf.stepContainers[2]

        s2.instrLabel = s2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        s2.instrLabel:SetPoint("TOPLEFT", s2, "TOPLEFT", 8, -8)
        s2.instrLabel:SetText("Paste FlippingPal scan results below:")
        s2.instrLabel:SetTextColor(0.7, 0.7, 0.7)

        -- Edit box area
        s2.editBg = CreateFrame("Frame", nil, s2, "BackdropTemplate")
        s2.editBg:SetPoint("TOPLEFT", s2, "TOPLEFT", 4, -26)
        s2.editBg:SetPoint("TOPRIGHT", s2, "TOPRIGHT", -4, -26)
        s2.editBg:SetHeight(80)
        s2.editBg:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        s2.editBg:SetBackdropColor(0.05, 0.05, 0.08, 1)
        s2.editBg:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)

        s2.editScroll = CreateFrame("ScrollFrame", "FlipQueueGenImportScroll", s2.editBg, "UIPanelScrollFrameTemplate")
        s2.editScroll:SetPoint("TOPLEFT", s2.editBg, "TOPLEFT", 6, -4)
        s2.editScroll:SetPoint("BOTTOMRIGHT", s2.editBg, "BOTTOMRIGHT", -22, 4)

        s2.editBox = CreateFrame("EditBox", "FlipQueueGenImportEdit", s2.editScroll)
        s2.editBox:SetMultiLine(true)
        s2.editBox:SetAutoFocus(false)
        s2.editBox:SetMaxLetters(0)
        s2.editBox:SetFontObject("ChatFontNormal")
        s2.editBox:SetWidth(s2.editScroll:GetWidth() or 500)
        s2.editScroll:SetScrollChild(s2.editBox)
        s2.editScroll:SetScript("OnSizeChanged", function(sf, w)
            s2.editBox:SetWidth(w)
        end)

        -- Preview table
        s2.previewTable = UI:CreateScrollTable(s2, {
            {key = "status",   label = "Status",  width = 52,  align = "CENTER", sortable = true},
            {key = "name",     label = "Item",    width = 160, sortable = true},
            {key = "realm",    label = "Realm",   width = 110, sortable = true},
            {key = "price",    label = "Price",   width = 70,  sortable = true},
            {key = "qty",      label = "Qty",     width = 30,  align = "CENTER", sortable = true},
            {key = "reason",   label = "Reason",  width = 128, sortable = true},
        })
        s2.previewTable:SetSort("status", true)
        if UI._RegisterTable then UI._RegisterTable(s2.previewTable) end

        s2.previewTable.headerFrame:SetParent(s2)
        s2.previewTable.headerFrame:ClearAllPoints()
        s2.previewTable.headerFrame:SetPoint("TOPLEFT", s2.editBg, "BOTTOMLEFT", 0, -4)
        s2.previewTable.headerFrame:SetPoint("TOPRIGHT", s2.editBg, "BOTTOMRIGHT", 0, -4)

        s2.previewTable.scrollFrame:SetParent(s2)
        s2.previewTable.scrollFrame:ClearAllPoints()
        s2.previewTable.scrollFrame:SetPoint("TOPLEFT", s2.previewTable.headerFrame, "BOTTOMLEFT", 0, 0)
        s2.previewTable.scrollFrame:SetPoint("BOTTOMRIGHT", s2, "BOTTOMRIGHT", -22, 40)

        s2.statusLabel = s2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s2.statusLabel:SetPoint("LEFT", s2, "BOTTOMLEFT", 8, 22)
        s2.statusLabel:SetTextColor(0.5, 0.5, 0.5)
        s2.statusLabel:SetText("")

        -- Auto-import checkbox
        s2.autoImportCheck = CreateFrame("CheckButton", "FlipQueueGenAutoImportCheck", s2, "UICheckButtonTemplate")
        s2.autoImportCheck:SetSize(22, 22)
        s2.autoImportCheck:SetPoint("RIGHT", s2, "BOTTOMRIGHT", -8, 22)
        s2.autoImportLabel = s2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s2.autoImportLabel:SetPoint("RIGHT", s2.autoImportCheck, "LEFT", -2, 0)
        s2.autoImportLabel:SetText("Auto-import")
        s2.autoImportLabel:SetTextColor(0.5, 0.5, 0.5)
        s2.autoImportCheck:SetScript("OnClick", function(self)
            if ns.db then ns.db.settings.importAutoImport = self:GetChecked() end
        end)

        -- Import button
        s2.importBtn = CreateHeaderBtn(s2, "Import", "Import pasted data into deals", function()
            if s2._previewData and #s2._previewData > 0 then
                local added = ns.Import:Save(s2._previewData)
                ns:Print("Imported " .. added .. " new items (" .. #s2._previewData .. " parsed, duplicates merged).")
                s2.editBox:SetText("")
                s2._previewData = nil
                s2._previewResults = nil
                s2._lastLen = 0
                s2.previewTable:SetData({})
                s2.statusLabel:SetText(ns.COLORS.GREEN .. added .. " items imported!|r")
                UI:Refresh()
                if UI.RefreshMini then UI:RefreshMini() end
            end
        end)
        s2.importBtn:SetPoint("LEFT", s2.statusLabel, "RIGHT", 10, 0)

        -- State for paste detection
        s2._lastLen = 0
        s2._previewData = nil
        s2._previewResults = nil

        -- Quality color map for preview
        local IMPORT_QUALITY_COLORS = {
            Poor = "9d9d9d", Common = "ffffff", Uncommon = "1eff00",
            Rare = "0070dd", Epic = "a335ee", Legendary = "ff8000",
            Artifact = "e6cc80", Heirloom = "00ccff",
        }

        -- Auto-detect paste and build preview
        s2.editBox:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local text = self:GetText()
            local newLen = #text
            if s2._lastLen < 10 and newLen > 50 and text:find("\n") then
                local items = ns.Import:Parse(text)
                if #items > 0 then
                    if s2.autoImportCheck:GetChecked() then
                        local added = ns.Import:Save(items)
                        ns:Print("Imported " .. added .. " new items (" .. #items .. " parsed, duplicates merged).")
                        s2.editBox:SetText("")
                        s2._previewData = nil
                        s2._previewResults = nil
                        s2.previewTable:SetData({})
                        s2.statusLabel:SetText(ns.COLORS.GREEN .. added .. " items imported!|r")
                        s2._lastLen = 0
                        UI:Refresh()
                        if UI.RefreshMini then UI:RefreshMini() end
                    else
                        s2._previewData = items
                        s2._previewResults = ns.Import:PreviewAdd(items)

                        -- Build preview table data
                        local data = {}
                        local newCount, dupCount, updateCount = 0, 0, 0
                        for _, result in ipairs(s2._previewResults) do
                            local item = result.item
                            local st = result._importStatus
                            local dupeReason = result._dupeReason
                            local statusStr, statusSort
                            if st == "new" then
                                statusStr = ns.COLORS.GREEN .. "New" .. "|r"
                                statusSort = "1new"
                                newCount = newCount + 1
                            elseif st == "update" then
                                statusStr = ns.COLORS.YELLOW .. "Update" .. "|r"
                                statusSort = "2update"
                                updateCount = updateCount + 1
                            elseif st == "duplicate" then
                                statusStr = ns.COLORS.GRAY .. "Dupe" .. "|r"
                                statusSort = "3dupe"
                                dupCount = dupCount + 1
                            else
                                statusStr = st or "?"
                                statusSort = "4" .. (st or "")
                            end

                            local displayName = item.name or "?"
                            local qColor = item.quality and IMPORT_QUALITY_COLORS[item.quality]
                            if qColor then
                                displayName = "|cff" .. qColor .. displayName .. "|r"
                            end

                            local isCrossRealm = item.dealType == "flip" or item.dealType == "buy"
                            if isCrossRealm then
                                displayName = ns.COLORS.CYAN .. "[XR] " .. "|r" .. displayName
                            end

                            local reasonStr = ""
                            if dupeReason then
                                if st == "duplicate" then
                                    reasonStr = ns.COLORS.GRAY .. dupeReason .. "|r"
                                elseif st == "update" then
                                    reasonStr = ns.COLORS.YELLOW .. dupeReason .. "|r"
                                end
                            end
                            if isCrossRealm and item.buyRealm and reasonStr == "" then
                                reasonStr = ns.COLORS.CYAN .. "buy@" .. item.buyRealm .. "|r"
                            end

                            local priceDisplay = item.expectedPrice or ""
                            if isCrossRealm and item.buyPrice then
                                priceDisplay = item.buyPrice
                            end

                            table.insert(data, {
                                status   = statusStr,
                                name     = displayName,
                                realm    = item.targetRealm or "",
                                price    = priceDisplay,
                                qty      = item.quantity or 1,
                                reason   = reasonStr,
                                _sortStatus = statusSort,
                                _tooltipText = item.name,
                                _rowColor = isCrossRealm and {0.1, 0.3, 0.5, 0.08} or nil,
                            })
                        end

                        s2.previewTable:SetData(data)
                        s2.previewTable.headerFrame:Show()
                        s2.previewTable.scrollFrame:Show()

                        local parts = {}
                        if newCount > 0 then table.insert(parts, ns.COLORS.GREEN .. newCount .. " new|r") end
                        if updateCount > 0 then table.insert(parts, ns.COLORS.YELLOW .. updateCount .. " updates|r") end
                        if dupCount > 0 then table.insert(parts, ns.COLORS.GRAY .. dupCount .. " dupes|r") end
                        s2.statusLabel:SetText(table.concat(parts, "  ") .. "  -- click Import to confirm")
                    end
                else
                    s2.statusLabel:SetText(ns.COLORS.RED .. "No items found in pasted data.|r")
                end
            end
            s2._lastLen = newLen
        end)
        s2.editBox:SetScript("OnEscapePressed", function() s2.editBox:ClearFocus() end)

        -- ===== STEP 3 CONTAINER: Configure & Generate =====
        local s3 = gf.stepContainers[3]

        -- Priority section
        s3.allocDesc = s3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        s3.allocDesc:SetTextColor(0.45, 0.45, 0.45)
        s3.allocDesc:SetJustifyH("LEFT")
        s3.allocDesc:SetWordWrap(true)
        s3.allocDesc:SetText("When two deals need the same item, which deal wins?")

        s3.allocLabel = s3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s3.allocLabel:SetText("Priority:")
        s3.allocLabel:SetTextColor(0.9, 0.8, 0.3)

        s3.allocRows = {}

        -- Sort section
        s3.sortDesc = s3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        s3.sortDesc:SetTextColor(0.45, 0.45, 0.45)
        s3.sortDesc:SetJustifyH("LEFT")
        s3.sortDesc:SetWordWrap(true)
        s3.sortDesc:SetText("Which character do you log into first?")

        s3.sortLabel = s3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s3.sortLabel:SetText("Order list by:")
        s3.sortLabel:SetTextColor(0.9, 0.8, 0.3)

        local SORT_MODES = {
            {key = "profit",        label = "Most Profitable"},
            {key = "character",     label = "Character"},
            {key = "realm",         label = "Realm"},
            {key = "noCompetition", label = "No Competition First"},
        }
        s3.sortBtns = {}
        for _, mode in ipairs(SORT_MODES) do
            local btn = CreateToggleBtn(s3, mode.label)
            btn._key = mode.key
            btn:SetScript("OnClick", function()
                UI:SetGenSortMode(mode.key)
                UI:Refresh()
            end)
            s3.sortBtns[mode.key] = btn
        end

        -- Generate button (inline, in the step 3 area)
        s3.generateBtn = CreateHeaderBtn(s3, "Generate",
            "Match deals against inventory (preview -- click Save to commit)",
            function()
                local btn = UI.mainFrame and UI.mainFrame.actionBtns and UI.mainFrame.actionBtns.generate
                if btn then btn:GetScript("OnClick")() end
            end)

        -- Import FP Data button (opens import popup)
        s3.importBtn = CreateHeaderBtn(s3, "Import FP Data",
            "Open import popup to paste FlippingPal data",
            function()
                if UI.ShowImportPopup then
                    UI:ShowImportPopup(function(added)
                        AutoGenerate()
                        UI:Refresh()
                        if UI.RefreshMini then UI:RefreshMini() end
                    end)
                end
            end)

        -- Status label
        s3.statusLabel = s3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

        -- Divider between controls and generated list
        s3.listDivider = s3:CreateTexture(nil, "ARTWORK")
        s3.listDivider:SetHeight(1)
        s3.listDivider:SetColorTexture(0.3, 0.3, 0.4, 0.5)

        -- Generated items scroll area
        s3.genScroll = CreateFrame("ScrollFrame", nil, s3, "UIPanelScrollFrameTemplate")
        s3.genContent = CreateFrame("Frame", nil, s3.genScroll)
        s3.genScroll:SetScrollChild(s3.genContent)
        s3.genScroll:SetScript("OnSizeChanged", function(sf, w)
            s3.genContent:SetWidth(w)
        end)
        s3.genRows = {}

        -- Drag state (shared across rows, persists in the frame)
        if not gf._dragState then
            gf._dragState = {}

            local ghost = CreateFrame("Frame", nil, UIParent)
            ghost:SetSize(180, 26)
            ghost:SetFrameStrata("TOOLTIP")
            ghost:SetAlpha(0.85)
            ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
            ghost.bg:SetAllPoints()
            ghost.bg:SetColorTexture(0.2, 0.25, 0.4, 0.9)
            ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
            ghost.icon:SetSize(16, 16)
            ghost.icon:SetPoint("LEFT", ghost, "LEFT", 6, 0)
            ghost.label = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            ghost.label:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
            ghost.label:SetPoint("RIGHT", ghost, "RIGHT", -6, 0)
            ghost.label:SetJustifyH("LEFT")
            ghost.border = ghost:CreateTexture(nil, "BORDER")
            ghost.border:SetPoint("TOPLEFT", -1, 1)
            ghost.border:SetPoint("BOTTOMRIGHT", 1, -1)
            ghost.border:SetColorTexture(0.5, 0.6, 1, 0.6)
            ghost:Hide()
            gf._dragState.ghost = ghost

            local dropLine = UIParent:CreateTexture(nil, "OVERLAY")
            dropLine:SetHeight(2)
            dropLine:SetColorTexture(1, 0.82, 0, 0.9)
            dropLine:Hide()
            gf._dragState.dropLine = dropLine
        end

        self._genFrame = gf
    end

    local gf = self._genFrame
    gf:Show()

    -- Initialize filter from DB on first refresh
    if not gf._filterInitialized then
        self:InitGenFilterFromDB()
        gf._filterInitialized = true
    end

    -- Sync wizard state
    local wizTrack = UI._wizardTrack
    local wizStep = UI._wizardStep or 0

    -- ========================================
    -- TOP SECTION: To-Do List Queue
    -- ========================================

    for _, row in ipairs(gf.topRows) do row:Hide() end
    for _, btn in ipairs(gf.topActionBtns) do btn:Hide() end

    local ROW_H = 20
    local topY = 0
    local topRowIdx = 0
    local topBtnIdx = 0

    local function TopRow()
        topRowIdx = topRowIdx + 1
        local r = gf.topRows[topRowIdx]
        if not r then
            r = CreateFrame("Button", nil, gf.topSection)
            r.bg = r:CreateTexture(nil, "BACKGROUND")
            r.bg:SetAllPoints()
            r.toggle = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.toggle:SetPoint("LEFT", r, "LEFT", 6, 0)
            r.toggle:SetWidth(12)
            r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.label:SetPoint("LEFT", r.toggle, "RIGHT", 2, 0)
            r.label:SetJustifyH("LEFT")
            r:EnableMouse(true)
            gf.topRows[topRowIdx] = r
        end
        r:SetHeight(ROW_H)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", gf.topSection, "TOPLEFT", 0, topY)
        r:SetPoint("RIGHT", gf.topSection, "RIGHT", 0, 0)
        r:SetScript("OnClick", nil)
        r:SetScript("OnEnter", nil)
        r:SetScript("OnLeave", nil)
        r.bg:SetColorTexture(0, 0, 0, 0)
        r.toggle:SetText("")
        r.toggle:Show()
        r.label:SetText("")
        r.label:ClearAllPoints()
        r.label:SetPoint("LEFT", r.toggle, "RIGHT", 2, 0)
        r.label:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.label:Show()
        r:Show()
        topY = topY - ROW_H
        return r
    end

    local function TopSmallBtn(parent, label, tooltip, onClick)
        topBtnIdx = topBtnIdx + 1
        local btn = gf.topActionBtns[topBtnIdx]
        if not btn then
            btn = CreateSmallActionBtn(gf.topSection, label, tooltip, onClick)
            gf.topActionBtns[topBtnIdx] = btn
        end
        btn.text:SetText(label)
        btn.text:SetTextColor(0.5, 0.5, 0.5)
        btn._tooltip = tooltip
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            self.text:SetTextColor(1, 1, 1)
            if self._tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self._tooltip, 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end
        end)
        btn:SetParent(parent)
        btn:Show()
        return btn
    end

    -- Data freshness row
    local genCharKey = ns:GetCharKey()
    local genCharData = ns.db.characters and ns.db.characters[genCharKey]
    local genCharInv = genCharData and genCharData.inventory
    local bagAge = genCharInv and genCharInv.lastScan
        and ns:FormatRelativeTime(genCharInv.lastScan) or "never"
    local wbAge = ns.db.warbank and ns.db.warbank.lastScan
        and ns:FormatRelativeTime(ns.db.warbank.lastScan) or "never"

    local freshRow = TopRow()
    freshRow.label:SetText(
        ns.COLORS.GRAY .. "Bags:|r " .. bagAge ..
        ns.COLORS.GRAY .. "   Warbank:|r " .. wbAge ..
        ns.COLORS.GRAY .. "   Deals:|r " .. pending)

    -- Current list
    if currentList then
        local counts = ns.TodoList:GetStatusCounts()
        local isCollapsed = UI._genListCollapsed["current"] ~= false

        local hdr = TopRow()
        hdr.bg:SetColorTexture(0.1, 0.14, 0.1, 0.6)
        hdr.toggle:SetText(isCollapsed and "|cffffffff\226\150\182|r" or "|cffffffff\226\150\188|r")
        hdr.label:SetPoint("RIGHT", hdr, "RIGHT", -72, 0)
        local importTypeTag = currentList.importType
            and ("  " .. ns.COLORS.GRAY .. "[" .. currentList.importType .. "]|r") or ""
        hdr.label:SetText(
            ns.COLORS.GREEN .. "Active:|r " .. (currentList.name or "Unnamed") .. importTypeTag ..
            ns.COLORS.GRAY .. "  (" .. counts.pending .. " pending" ..
            (counts.missing > 0 and (", " .. ns.COLORS.RED .. counts.missing .. " miss|r") or "") ..
            (counts.unassigned > 0 and (", " .. ns.COLORS.ORANGE .. counts.unassigned .. " no char|r") or "") ..
            ")" .. "|r")

        local xBtn = TopSmallBtn(hdr, "x", "Delete list", function()
            ns.TodoList:ClearCurrent()
            UI._generatorPreview = nil
            ns:Print("Current to-do list deleted.")
            UI:Refresh()
            if UI.RefreshMini then UI:RefreshMini() end
        end)
        xBtn:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)

        local rBtn = TopSmallBtn(hdr, "R", "Rename", function()
            gf.renameBox:SetParent(hdr)
            gf.renameBox:ClearAllPoints()
            gf.renameBox:SetPoint("LEFT", hdr.toggle, "RIGHT", 2, 0)
            gf.renameBox:SetPoint("RIGHT", hdr, "RIGHT", -72, 0)
            gf.renameBox:SetText(currentList.name or "")
            gf.renameBox:Show()
            gf.renameBox:SetFocus(true)
            gf.renameBox:SetScript("OnEnterPressed", function(self)
                local name = self:GetText():match("^%s*(.-)%s*$")
                if name ~= "" then ns.TodoList:RenameList(0, name) end
                self:Hide()
                UI:Refresh()
            end)
        end)
        rBtn:SetPoint("RIGHT", xBtn, "LEFT", -2, 0)

        local dBtn = TopSmallBtn(hdr, "D", "Duplicate to queue", function()
            ns.TodoList:DuplicateList(0)
            ns:Print("Duplicated current list.")
            UI:Refresh()
        end)
        dBtn:SetPoint("RIGHT", rBtn, "LEFT", -2, 0)

        hdr:SetScript("OnClick", function()
            UI._genListCollapsed["current"] = not isCollapsed
            UI:Refresh()
        end)
        hdr:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.12, 0.18, 0.12, 0.8) end)
        hdr:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.1, 0.14, 0.1, 0.6) end)

        if not isCollapsed then
            local summary = ns.TodoList:GetCharacterSummary()
            for _, info in ipairs(summary) do
                local sub = TopRow()
                sub.bg:SetColorTexture(0.08, 0.1, 0.08, 0.4)
                local cName = info.charKey:match("^(.-)%-") or info.charKey
                local cRealm = info.charKey:match("%-(.+)$") or ""
                local cData = ns.db.characters and ns.db.characters[info.charKey]
                local cc = cData and CLASS_COLORS[cData.class] or "888888"
                sub.label:SetText(
                    "      |cff" .. cc .. cName .. "|r" ..
                    ns.COLORS.GRAY .. " (" .. cRealm .. ")|r  " ..
                    info.taskCount .. " items" ..
                    (info.totalValue > 0 and ("  ~" .. FormatGoldValue(info.totalValue)) or ""))
            end
        end
    end

    -- Queued lists
    local queued = ns.TodoList and ns.TodoList:GetQueuedLists() or {}
    for qi, qList in ipairs(queued) do
        local key = "queued_" .. qi
        local isCollapsed = UI._genListCollapsed[key] ~= false
        local qPending = 0
        for _, item in ipairs(qList.tasks or {}) do
            if item.status == "pending" then qPending = qPending + 1 end
        end

        local capturedQi = qi
        local hdr = TopRow()
        hdr.bg:SetColorTexture(0.14, 0.12, 0.08, 0.6)
        hdr.toggle:SetText(isCollapsed and "|cffffffff\226\150\182|r" or "|cffffffff\226\150\188|r")
        hdr.label:SetPoint("RIGHT", hdr, "RIGHT", -108, 0)
        local qImportTypeTag = qList.importType
            and ("  " .. ns.COLORS.GRAY .. "[" .. qList.importType .. "]|r") or ""
        hdr.label:SetText(
            ns.COLORS.YELLOW .. "Queued:|r " .. (qList.name or "Unnamed") .. qImportTypeTag ..
            ns.COLORS.GRAY .. "  (" .. qPending .. " items)" .. "|r")

        local xBtn = TopSmallBtn(hdr, "x", "Delete", function()
            ns.TodoList:DeleteQueuedList(capturedQi)
            ns:Print("Deleted: " .. (qList.name or "Unnamed"))
            UI:Refresh()
        end)
        xBtn:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)

        local rBtn = TopSmallBtn(hdr, "R", "Rename", function()
            gf.renameBox:SetParent(hdr)
            gf.renameBox:ClearAllPoints()
            gf.renameBox:SetPoint("LEFT", hdr.toggle, "RIGHT", 2, 0)
            gf.renameBox:SetPoint("RIGHT", hdr, "RIGHT", -108, 0)
            gf.renameBox:SetText(qList.name or "")
            gf.renameBox:Show()
            gf.renameBox:SetFocus(true)
            gf.renameBox:SetScript("OnEnterPressed", function(self)
                local name = self:GetText():match("^%s*(.-)%s*$")
                if name ~= "" then ns.TodoList:RenameList(capturedQi, name) end
                self:Hide()
                UI:Refresh()
            end)
        end)
        rBtn:SetPoint("RIGHT", xBtn, "LEFT", -2, 0)

        local dBtn = TopSmallBtn(hdr, "D", "Duplicate", function()
            ns.TodoList:DuplicateList(capturedQi)
            UI:Refresh()
        end)
        dBtn:SetPoint("RIGHT", rBtn, "LEFT", -2, 0)

        if qi < #queued then
            local vBtn = TopSmallBtn(hdr, "v", "Move down", function()
                ns.TodoList:ReorderQueue(capturedQi, capturedQi + 1)
                UI:Refresh()
            end)
            vBtn:SetPoint("RIGHT", dBtn, "LEFT", -4, 0)
        end

        local upBtn = TopSmallBtn(hdr, "^",
            qi == 1 and "Promote to active" or "Move up",
            function()
                if capturedQi == 1 then
                    ns.TodoList:PromoteToActive(1)
                    ns:Print("Promoted: " .. (qList.name or "Unnamed"))
                else
                    ns.TodoList:ReorderQueue(capturedQi, capturedQi - 1)
                end
                UI:Refresh()
                if UI.RefreshMini then UI:RefreshMini() end
            end)
        if qi < #queued then
            upBtn:SetPoint("RIGHT", dBtn, "LEFT", -22, 0)
        else
            upBtn:SetPoint("RIGHT", dBtn, "LEFT", -4, 0)
        end

        hdr:SetScript("OnClick", function()
            UI._genListCollapsed[key] = not isCollapsed
            UI:Refresh()
        end)
        hdr:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.18, 0.15, 0.1, 0.8) end)
        hdr:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.14, 0.12, 0.08, 0.6) end)
    end

    -- No lists hint
    if not currentList and #queued == 0 then
        local hint = TopRow()
        hint.label:SetText(
            ns.COLORS.GRAY .. "No to-do lists. Choose a track below to get started.|r")
    end

    local topHeight = math.abs(topY) + 2
    gf.topSection:SetHeight(topHeight)

    -- ========================================
    -- HIDE ALL STEP CONTAINERS + OVERLAYS
    -- ========================================

    gf.stepBar:Hide()
    gf.trackSelectPanel:Hide()
    gf.backBtn:Hide()
    gf.nextBtn:Hide()
    gf.saveBtn:Hide()
    for i = 1, 3 do
        gf.stepContainers[i]:Hide()
    end

    -- Content area starts below topSection
    local contentTop = -topHeight - 4

    -- ========================================
    -- STEP 0: TRACK SELECTION
    -- ========================================

    if wizStep == 0 then
        gf.trackSelectPanel:ClearAllPoints()
        gf.trackSelectPanel:SetPoint("TOPLEFT", gf, "TOPLEFT", 0, contentTop)
        gf.trackSelectPanel:SetPoint("BOTTOMRIGHT", gf, "BOTTOMRIGHT", 0, 0)
        gf.trackSelectPanel:Show()

        mainFrame.statusText:SetText(pending .. " deals imported  |  Choose a workflow to generate your to-do list")
        return
    end

    -- ========================================
    -- STEPS 1-3: SHOW STEP BAR + NAV + CONTENT
    -- ========================================

    gf.stepBar:ClearAllPoints()
    gf.stepBar:SetPoint("TOPLEFT", gf, "TOPLEFT", 0, contentTop)
    gf.stepBar:SetPoint("TOPRIGHT", gf, "TOPRIGHT", 0, contentTop)
    gf.stepBar:Show()
    gf.stepBar:Update(wizTrack, wizStep)

    local stepContentTop = contentTop - 54  -- below step bar

    -- Nav buttons
    gf.backBtn:Show()
    gf.backBtn:SetScript("OnClick", function()
        if wizStep <= 1 then
            SaveWizardState(nil, 0)
        else
            SaveWizardState(wizTrack, wizStep - 1)
        end
        UI:Refresh()
    end)

    gf.nextBtn:Show()
    if wizStep >= 3 then
        gf.nextBtn.text:SetText("Generate")
    else
        gf.nextBtn.text:SetText("Next")
    end
    gf.nextBtn:SetScript("OnClick", function()
        if wizStep < 3 then
            SaveWizardState(wizTrack, wizStep + 1)
            UI:Refresh()
        else
            -- Generate
            local btn = UI.mainFrame and UI.mainFrame.actionBtns and UI.mainFrame.actionBtns.generate
            if btn then btn:GetScript("OnClick")() end
        end
    end)

    -- Save button (only on step 3 with preview)
    if wizStep == 3 and UI._generatorPreview then
        gf.saveBtn:Show()
        gf.saveBtn:SetScript("OnClick", function()
            local btn = UI.mainFrame and UI.mainFrame.actionBtns and UI.mainFrame.actionBtns.commitSave
            if btn then btn:GetScript("OnClick")() end
        end)
    end

    -- Position step container for the current step
    local sc = gf.stepContainers[wizStep]
    if sc then
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", gf, "TOPLEFT", 0, stepContentTop)
        sc:SetPoint("BOTTOMRIGHT", gf, "BOTTOMRIGHT", 0, 36)  -- leave room for nav buttons
        sc:Show()
    end

    -- ========================================
    -- INVENTORY TRACK: STEP 1 -- Build Inventory
    -- ========================================

    if wizTrack == "inventory" and wizStep == 1 then
        local s1 = gf.stepContainers[1]

        -- Update filter toggle state
        SetToggleActive(s1.filterAll, UI._genFilterMode == "all")
        SetToggleActive(s1.filterTSM, UI._genFilterMode == "tsm")
        SetToggleActive(s1.filterAuct, UI._genFilterMode == "auctionator")

        -- Hide all filter-mode-specific elements
        s1.treeFrame:Hide()
        s1.tsmProfileLabel:Hide()
        s1.tsmSelectedLabel:Hide()
        s1.tsmClearBtn:Hide()
        s1.tsmUnavail:Hide()
        s1.auctFrame:Hide()
        s1.auctUnavail:Hide()
        for _, row in ipairs(s1.auctRows) do row:Hide() end

        local filterControlsBottom = -56  -- below description + label + filter buttons

        -- TSM Group Tree
        if UI._genFilterMode == "tsm" then
            local tsmEnabled = ns.TSM and ns.TSM:IsEnabled()
            if tsmEnabled and s1.groupTree then
                local profile = ns.TSM:GetSelectedProfile()

                s1.tsmProfileLabel:ClearAllPoints()
                s1.tsmProfileLabel:SetPoint("TOPLEFT", s1, "TOPLEFT", 6, filterControlsBottom)
                s1.tsmProfileLabel:SetText("Profile: " .. ns.COLORS.WHITE .. (profile or "none") .. "|r")
                s1.tsmProfileLabel:Show()
                filterControlsBottom = filterControlsBottom - 16

                s1.treeFrame:ClearAllPoints()
                s1.treeFrame:SetPoint("TOPLEFT", s1, "TOPLEFT", 0, filterControlsBottom)
                s1.treeFrame:SetPoint("RIGHT", s1, "RIGHT", 0, 0)
                s1.treeFrame:SetHeight(140)
                s1.treeFrame:Show()

                if profile and s1.groupTree._profile ~= profile then
                    s1.groupTree:SetProfile(profile)
                end
                filterControlsBottom = filterControlsBottom - 142

                if UI._genFilterValue and UI._genFilterValue ~= "" then
                    s1.tsmSelectedLabel:ClearAllPoints()
                    s1.tsmSelectedLabel:SetPoint("TOPLEFT", s1, "TOPLEFT", 6, filterControlsBottom)
                    s1.tsmSelectedLabel:SetText("Group: " .. UI._genFilterValue:gsub("`", " > "))
                    s1.tsmSelectedLabel:Show()

                    s1.tsmClearBtn:ClearAllPoints()
                    s1.tsmClearBtn:SetPoint("LEFT", s1.tsmSelectedLabel, "RIGHT", 6, 0)
                    s1.tsmClearBtn:Show()

                    filterControlsBottom = filterControlsBottom - 16
                end
            else
                s1.tsmUnavail:ClearAllPoints()
                s1.tsmUnavail:SetPoint("TOPLEFT", s1, "TOPLEFT", 6, filterControlsBottom)
                s1.tsmUnavail:Show()
                filterControlsBottom = filterControlsBottom - 16
            end

        elseif UI._genFilterMode == "auctionator" then
            local listNames = ns:GetAuctionatorListNames()
            local auctAvailable = #listNames > 0 or type(AUCTIONATOR_SHOPPING_LISTS) == "table"

            if auctAvailable then
                s1.auctFrame:ClearAllPoints()
                s1.auctFrame:SetPoint("TOPLEFT", s1, "TOPLEFT", 0, filterControlsBottom)
                s1.auctFrame:SetPoint("RIGHT", s1, "RIGHT", 0, 0)
                local listHeight = math.min(120, math.max(40, #listNames * 18 + 20))
                s1.auctFrame:SetHeight(listHeight)
                s1.auctFrame:Show()

                s1.auctContent:SetWidth(s1.auctScroll:GetWidth() or 150)

                for _, row in ipairs(s1.auctRows) do row:Hide() end

                local auctY = 0
                for idx, listName in ipairs(listNames) do
                    local row = s1.auctRows[idx]
                    if not row then
                        row = CreateFrame("Button", nil, s1.auctContent)
                        row:SetHeight(18)
                        row.bg = row:CreateTexture(nil, "BACKGROUND")
                        row.bg:SetAllPoints()
                        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
                        row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                        row.label:SetJustifyH("LEFT")
                        row:EnableMouse(true)
                        s1.auctRows[idx] = row
                    end
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", s1.auctContent, "TOPLEFT", 0, -auctY)
                    row:SetPoint("RIGHT", s1.auctContent, "RIGHT", 0, 0)

                    local isSelected = (UI._genFilterValue == listName)
                    if isSelected then
                        row.bg:SetColorTexture(0.2, 0.35, 0.5, 0.6)
                        row.label:SetText("|cffffffff" .. listName .. "|r")
                    else
                        row.bg:SetColorTexture(0, 0, 0, 0)
                        row.label:SetText(listName)
                        row.label:SetTextColor(0.8, 0.8, 0.8)
                    end

                    local capturedName = listName
                    row:SetScript("OnClick", function()
                        SaveGenFilter("auctionator", capturedName)
                        AutoGenerate()
                        UI:Refresh()
                    end)
                    row:SetScript("OnEnter", function(self)
                        if not isSelected then self.bg:SetColorTexture(1, 1, 1, 0.05) end
                    end)
                    row:SetScript("OnLeave", function(self)
                        if not (UI._genFilterValue == capturedName) then self.bg:SetColorTexture(0, 0, 0, 0) end
                    end)

                    row:Show()
                    auctY = auctY + 18
                end
                s1.auctContent:SetHeight(math.max(1, auctY))

                filterControlsBottom = filterControlsBottom - listHeight - 4
            else
                s1.auctUnavail:ClearAllPoints()
                s1.auctUnavail:SetPoint("TOPLEFT", s1, "TOPLEFT", 6, filterControlsBottom)
                s1.auctUnavail:SetPoint("RIGHT", s1, "RIGHT", -6, 0)
                if type(Auctionator) == "table" then
                    s1.auctUnavail:SetText("Auctionator detected but no shopping lists found. Create one in Auctionator first.")
                else
                    s1.auctUnavail:SetText("Auctionator is not installed.")
                end
                s1.auctUnavail:Show()
                filterControlsBottom = filterControlsBottom - 16
            end
        end

        -- Build filtered item pool
        local filteredPool = ns.TodoList:GetFilteredItemPool(
            UI._genFilterMode, UI._genFilterValue, UI._genExcludedItems)

        -- Divider between filter controls and pool
        s1.poolDivider:ClearAllPoints()
        s1.poolDivider:SetPoint("TOPLEFT", s1, "TOPLEFT", 6, filterControlsBottom + 2)
        s1.poolDivider:SetPoint("RIGHT", s1, "RIGHT", -6, 0)
        filterControlsBottom = filterControlsBottom - 4

        -- Item count label
        s1.countLabel:ClearAllPoints()
        s1.countLabel:SetPoint("TOPLEFT", s1, "TOPLEFT", 6, filterControlsBottom)
        s1.countLabel:SetText(ns.COLORS.GRAY .. #filteredPool .. " items in pool|r")

        -- Pool scroll area
        s1.poolScroll:ClearAllPoints()
        s1.poolScroll:SetPoint("TOPLEFT", s1, "TOPLEFT", 0, filterControlsBottom - 14)
        s1.poolScroll:SetPoint("BOTTOMRIGHT", s1, "BOTTOMRIGHT", -22, 28)

        local poolScrollWidth = s1.poolScroll:GetWidth()
        s1.poolContent:SetWidth(poolScrollWidth and poolScrollWidth > 0 and poolScrollWidth or 200)

        -- Render pool items
        for _, row in ipairs(s1.poolRows) do row:Hide() end

        local POOL_ROW_H = 18
        local poolY = 0
        for i, poolItem in ipairs(filteredPool) do
            local row = s1.poolRows[i]
            if not row then
                row = CreateFrame("Button", nil, s1.poolContent)
                row:SetHeight(POOL_ROW_H)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(14, 14)
                row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
                row.nameText:SetJustifyH("LEFT")
                row.qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.qtyText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row.qtyText:SetJustifyH("RIGHT")
                row.nameText:SetPoint("RIGHT", row.qtyText, "LEFT", -4, 0)
                row:EnableMouse(true)
                s1.poolRows[i] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", s1.poolContent, "TOPLEFT", 0, -poolY)
            row:SetPoint("RIGHT", s1.poolContent, "RIGHT", 0, 0)
            row.bg:SetColorTexture(i % 2 == 0 and 0.1 or 0.08, i % 2 == 0 and 0.1 or 0.08, i % 2 == 0 and 0.14 or 0.12, 0.6)

            if poolItem.icon then
                row.icon:SetTexture(poolItem.icon)
                row.icon:Show()
            else
                row.icon:Hide()
            end

            local displayName = poolItem.name or "?"
            local lookupIcon, quality
            pcall(function()
                lookupIcon, quality = UI._LookupItemInfo(poolItem.itemID, poolItem.itemKey, poolItem.name)
            end)
            if quality and UI._QualityColorName then
                displayName = UI._QualityColorName(displayName, quality)
            end
            row.nameText:SetText(displayName)

            local srcParts = {}
            for _, src in ipairs(poolItem.sources) do
                if src.source == "Warbank" then
                    table.insert(srcParts, src.quantity .. " wb")
                else
                    local charName = src.source:match("^(.-)%-") or src.source
                    table.insert(srcParts, src.quantity .. " " .. charName)
                end
            end
            row.qtyText:SetText(ns.COLORS.GRAY .. table.concat(srcParts, ", ") .. "|r")

            local itemKey = poolItem.itemKey
            row:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    UI._genExcludedItems[itemKey] = true
                    UI:Refresh()
                end
            end)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(1, 1, 1, 0.08)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(poolItem.name or "?", 1, 1, 1)
                GameTooltip:AddLine("Total: " .. poolItem.totalQuantity, 0.7, 0.7, 0.7)
                for _, src in ipairs(poolItem.sources) do
                    GameTooltip:AddLine("  " .. src.source .. " (" .. src.location .. "): " .. src.quantity, 0.5, 0.5, 0.5)
                end
                GameTooltip:AddLine("\nRight-click to exclude", 0.4, 0.4, 0.4)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(i % 2 == 0 and 0.1 or 0.08, i % 2 == 0 and 0.1 or 0.08, i % 2 == 0 and 0.14 or 0.12, 0.6)
                GameTooltip:Hide()
            end)

            row:Show()
            poolY = poolY + POOL_ROW_H
        end
        s1.poolContent:SetHeight(math.max(1, poolY))

        -- Status bar
        local excludeCount = 0
        for _ in pairs(UI._genExcludedItems) do excludeCount = excludeCount + 1 end
        local statusParts = {#filteredPool .. " pool items"}
        if excludeCount > 0 then
            table.insert(statusParts, excludeCount .. " excluded")
        end
        mainFrame.statusText:SetText(table.concat(statusParts, "  |  ") .. "  |  Step 1 of 3: Review your inventory pool")
        return
    end

    -- ========================================
    -- INVENTORY TRACK: STEP 2 -- Import Deals
    -- ========================================

    if wizTrack == "inventory" and wizStep == 2 then
        local s2 = gf.stepContainers[2]

        -- Restore checkbox state
        s2.autoImportCheck:SetChecked(ns.db.settings.importAutoImport or false)

        -- Show preview table if we have data
        if s2._previewData then
            s2.previewTable.headerFrame:Show()
            s2.previewTable.scrollFrame:Show()
        end

        s2.editBox:SetFocus(true)

        mainFrame.statusText:SetText("Step 2 of 3: Paste FlippingPal scan data  |  " .. pending .. " deals imported")
        return
    end

    -- ========================================
    -- INVENTORY TRACK: STEP 3 -- Configure & Generate
    -- ========================================

    if wizTrack == "inventory" and wizStep == 3 then
        local s3 = gf.stepContainers[3]

        local ALLOC_META = {
            gold           = {label = "Profit",        icon = "Interface\\Icons\\INV_Misc_Coin_17",                 color = {1, 0.82, 0}},
            noCompetition  = {label = "No Competition", icon = "Interface\\Icons\\Achievement_PVP_H_01",            color = {0.3, 1, 0.3}},
            population     = {label = "Population",     icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", color = {0.4, 0.7, 1}},
        }

        local LIST_ROW_H = 28

        -- Helper: render allocation priority as a draggable ordered list
        local function RenderAllocList(orderTable, rowPool, parent, yStart, onChanged)
            for _, row in ipairs(rowPool) do row:Hide() end
            local y = yStart
            local ds = gf._dragState

            for idx, key in ipairs(orderTable) do
                local meta = ALLOC_META[key] or {label = key, color = {0.7, 0.7, 0.7}}
                local row = rowPool[idx]
                if not row then
                    row = CreateFrame("Button", nil, parent, "BackdropTemplate")
                    row:SetHeight(LIST_ROW_H)
                    row:SetBackdrop({
                        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        edgeSize = 10,
                        insets = {left = 2, right = 2, top = 2, bottom = 2},
                    })

                    row.grip = row:CreateTexture(nil, "ARTWORK")
                    row.grip:SetSize(8, 14)
                    row.grip:SetPoint("LEFT", row, "LEFT", 6, 0)
                    row.grip:SetColorTexture(0.4, 0.4, 0.5, 0.5)

                    row.rankBg = row:CreateTexture(nil, "ARTWORK")
                    row.rankBg:SetSize(18, 18)
                    row.rankBg:SetPoint("LEFT", row.grip, "RIGHT", 4, 0)
                    row.rankBg:SetColorTexture(0.2, 0.2, 0.3, 0.8)

                    row.rankNum = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    row.rankNum:SetPoint("CENTER", row.rankBg, "CENTER", 0, 0)

                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(16, 16)
                    row.icon:SetPoint("LEFT", row.rankBg, "RIGHT", 6, 0)

                    row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    row.nameLabel:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                    row.nameLabel:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                    row.nameLabel:SetJustifyH("LEFT")

                    row:EnableMouse(true)
                    rowPool[idx] = row
                end

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
                row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)

                local brightness = 1 - (idx - 1) * 0.2
                local c = meta.color
                row:SetBackdropColor(c[1] * 0.12 * brightness, c[2] * 0.12 * brightness, c[3] * 0.15 * brightness, 0.9)
                row:SetBackdropBorderColor(c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 0.6)

                row.rankNum:SetText(idx)
                row.rankNum:SetTextColor(c[1], c[2], c[3])

                if meta.icon then
                    row.icon:SetTexture(meta.icon)
                    row.icon:Show()
                else
                    row.icon:Hide()
                end

                row.nameLabel:SetText(meta.label)
                row.nameLabel:SetTextColor(c[1] * 0.8 + 0.2, c[2] * 0.8 + 0.2, c[3] * 0.8 + 0.2)

                row.grip:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.6)

                local capturedIdx = idx
                local capturedKey = key

                row:SetScript("OnEnter", function(self)
                    if not ds.dragging then
                        self:SetBackdropBorderColor(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7, 1)
                        self.grip:SetColorTexture(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(meta.label, c[1], c[2], c[3])
                        GameTooltip:AddLine("Drag to reorder, or click to move", 0.5, 0.5, 0.5)
                        GameTooltip:Show()
                    end
                end)
                row:SetScript("OnLeave", function(self)
                    if not ds.dragging then
                        self:SetBackdropBorderColor(c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 0.6)
                        self.grip:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.6)
                        GameTooltip:Hide()
                    end
                end)

                row:SetScript("OnMouseDown", function(self, button)
                    if button ~= "LeftButton" or ds.dragging then return end
                    local cx, cy = GetCursorPosition()
                    ds._pendingRow = self
                    ds._pendingIdx = capturedIdx
                    ds._pendingMeta = meta
                    ds._pendingColor = c
                    ds._startCX = cx
                    ds._startCY = cy
                    ds._dragStarted = false

                    ds.ghost:SetScript("OnUpdate", function(g)
                        if ds._dragStarted then
                            local gcx, gcy = GetCursorPosition()
                            local scale = UIParent:GetEffectiveScale()
                            g:ClearAllPoints()
                            g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", gcx / scale, gcy / scale)

                            local parentTop = parent:GetTop()
                            if not parentTop then return end
                            local cursorY = gcy / scale
                            local listTop = parentTop + yStart
                            local relY = listTop - cursorY
                            local dropIdx = math.floor(relY / LIST_ROW_H) + 1
                            dropIdx = math.max(1, math.min(dropIdx, #orderTable))
                            ds.dropIdx = dropIdx

                            local line = ds.dropLine
                            local lineY = yStart - (dropIdx - 1) * LIST_ROW_H
                            if dropIdx > ds.dragIdx then
                                lineY = yStart - dropIdx * LIST_ROW_H
                            end
                            line:ClearAllPoints()
                            line:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, lineY + 1)
                            line:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
                            line:Show()
                        else
                            local ncx, ncy = GetCursorPosition()
                            if not ds._startCX then
                                g:SetScript("OnUpdate", nil)
                                return
                            end
                            local dx = math.abs(ncx - ds._startCX)
                            local dy = math.abs(ncy - ds._startCY)
                            if dx + dy > 6 then
                                ds._dragStarted = true
                                ds.dragging = true
                                ds.dragIdx = ds._pendingIdx
                                local m = ds._pendingMeta
                                local pc = ds._pendingColor
                                g.icon:SetTexture(m.icon or "")
                                g.label:SetText(m.label)
                                g.label:SetTextColor(pc[1], pc[2], pc[3])
                                g.bg:SetColorTexture(pc[1] * 0.2, pc[2] * 0.2, pc[3] * 0.25, 0.95)
                                g.border:SetColorTexture(pc[1] * 0.6, pc[2] * 0.6, pc[3] * 0.8, 0.8)
                                g:Show()
                                if ds._pendingRow then ds._pendingRow:SetAlpha(0.3) end
                                GameTooltip:Hide()
                            end
                        end
                    end)
                end)

                row:SetScript("OnMouseUp", function(self, button)
                    if button ~= "LeftButton" then return end

                    if ds.dragging and ds._dragStarted then
                        ds.dragging = false
                        ds._dragStarted = false
                        if ds._pendingRow then ds._pendingRow:SetAlpha(1) end
                        ds.ghost:Hide()
                        ds.ghost:SetScript("OnUpdate", nil)
                        ds.dropLine:Hide()

                        local from = ds.dragIdx
                        local to = ds.dropIdx or from
                        if from ~= to then
                            local moved = table.remove(orderTable, from)
                            table.insert(orderTable, to, moved)
                            onChanged()
                        end
                    else
                        ds.ghost:SetScript("OnUpdate", nil)
                        ds.ghost:Hide()
                        ds.dragging = false
                        ds._dragStarted = false
                        ds._startCX = nil
                        if capturedIdx > 1 then
                            orderTable[capturedIdx], orderTable[capturedIdx - 1] = orderTable[capturedIdx - 1], orderTable[capturedIdx]
                        else
                            local moved = table.remove(orderTable, 1)
                            table.insert(orderTable, moved)
                        end
                        onChanged()
                    end
                end)

                row:Show()
                y = y - LIST_ROW_H
            end
            return y
        end

        local function AutoRegenerate()
            if ns.TodoList and ns:ImportGetCount("fpScanner") > 0 then
                UI._generatorPreview = ns.TodoList:GenerateTodoList("fpScanner", UI:GetGenAllocationOrder())
            end
            UI:Refresh()
        end

        -- Layout: priority section
        local rightY = -4
        s3.allocDesc:ClearAllPoints()
        s3.allocDesc:SetPoint("TOPLEFT", s3, "TOPLEFT", 6, rightY)
        s3.allocDesc:SetPoint("RIGHT", s3, "RIGHT", -6, 0)
        rightY = rightY - 14
        s3.allocLabel:ClearAllPoints()
        s3.allocLabel:SetPoint("TOPLEFT", s3, "TOPLEFT", 6, rightY)
        rightY = rightY - 14
        rightY = RenderAllocList(UI:GetGenAllocationOrder(), s3.allocRows, s3, rightY, AutoRegenerate)
        rightY = rightY - 8

        -- Sort section
        s3.sortDesc:ClearAllPoints()
        s3.sortDesc:SetPoint("TOPLEFT", s3, "TOPLEFT", 6, rightY)
        s3.sortDesc:SetPoint("RIGHT", s3, "RIGHT", -6, 0)
        rightY = rightY - 14
        s3.sortLabel:ClearAllPoints()
        s3.sortLabel:SetPoint("TOPLEFT", s3, "TOPLEFT", 6, rightY)
        rightY = rightY - 14

        local sortBtnX = 4
        for _, key in ipairs({"profit", "character", "realm", "noCompetition"}) do
            local btn = s3.sortBtns[key]
            if btn then
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", s3, "TOPLEFT", sortBtnX, rightY)
                SetToggleActive(btn, UI:GetGenSortMode() == key)
                btn:Show()
                sortBtnX = sortBtnX + btn:GetWidth() + 3
            end
        end
        rightY = rightY - 22

        -- Generate + Import buttons
        s3.generateBtn:ClearAllPoints()
        s3.generateBtn:SetPoint("TOPLEFT", s3, "TOPLEFT", sortBtnX + 10, rightY + 22)
        s3.generateBtn:Show()

        s3.importBtn:ClearAllPoints()
        s3.importBtn:SetPoint("LEFT", s3.generateBtn, "RIGHT", 4, 0)
        s3.importBtn:Show()

        -- Build grouped display data
        local previewSource = UI._generatorPreview or currentList
        local previewItems = previewSource and (previewSource.items or previewSource.tasks)
        local displayGroups = {}
        local missingCount = 0
        if previewItems then
            displayGroups, missingCount = ns.TodoList:BuildDisplayGroups(previewItems, UI:GetGenSortMode())
        end

        -- Status label
        s3.statusLabel:ClearAllPoints()
        s3.statusLabel:SetPoint("TOPLEFT", s3, "TOPLEFT", 6, rightY)
        if previewItems then
            local assignedCount = 0
            for _, g in ipairs(displayGroups) do
                if g.charKey then assignedCount = assignedCount + #g.items end
            end
            local statusText = ns.COLORS.GRAY .. assignedCount .. " tasks across " .. #displayGroups .. " group(s)"
            if missingCount > 0 then
                statusText = statusText .. "  |  " .. ns.COLORS.RED .. missingCount .. " not in inventory|r"
            end
            statusText = statusText .. "|r"
            s3.statusLabel:SetText(statusText)
        else
            s3.statusLabel:SetText(
                ns.COLORS.GRAY .. "Click Generate to build list|r")
        end
        rightY = rightY - 14

        -- Divider
        s3.listDivider:ClearAllPoints()
        s3.listDivider:SetPoint("TOPLEFT", s3, "TOPLEFT", 6, rightY + 2)
        s3.listDivider:SetPoint("RIGHT", s3, "RIGHT", -6, 0)
        rightY = rightY - 4

        -- Generated items scroll area
        s3.genScroll:ClearAllPoints()
        s3.genScroll:SetPoint("TOPLEFT", s3, "TOPLEFT", 0, rightY)
        s3.genScroll:SetPoint("BOTTOMRIGHT", s3, "BOTTOMRIGHT", -22, 0)

        local genScrollWidth = s3.genScroll:GetWidth()
        s3.genContent:SetWidth(genScrollWidth and genScrollWidth > 0 and genScrollWidth or 200)

        -- Render grouped items: headers + sub-items
        for _, row in ipairs(s3.genRows) do row:Hide() end

        local LookupItemInfo = UI._LookupItemInfo
        local QualityColorName = UI._QualityColorName
        local GEN_ROW_H = 18
        local HDR_ROW_H = 22
        local genY = 0
        local genRowIdx = 0

        local function GetOrCreateGenRow(height)
            genRowIdx = genRowIdx + 1
            local row = s3.genRows[genRowIdx]
            if not row then
                row = CreateFrame("Button", nil, s3.genContent)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(14, 14)
                row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
                row.nameText:SetJustifyH("LEFT")
                row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.rightText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row.rightText:SetJustifyH("RIGHT")
                row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                row:EnableMouse(true)
                s3.genRows[genRowIdx] = row
            end
            row:SetHeight(height)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", s3.genContent, "TOPLEFT", 0, -genY)
            row:SetPoint("RIGHT", s3.genContent, "RIGHT", 0, 0)
            row.icon:Hide()
            row.nameText:SetText("")
            row.rightText:SetText("")
            row:SetScript("OnClick", nil)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row:Show()
            return row
        end

        for gi, group in ipairs(displayGroups) do
            local isUnassigned = not group.charKey

            local hdr = GetOrCreateGenRow(HDR_ROW_H)

            if isUnassigned then
                hdr.bg:SetColorTexture(0.15, 0.08, 0.08, 0.7)
                local realmName = group.realm ~= "" and group.realm or "unknown realm"
                hdr.nameText:SetText(
                    ns.COLORS.RED .. "Create character on " .. realmName .. "|r" ..
                    ns.COLORS.GRAY .. "  (" .. #group.items .. " items -- not in to-do list)" ..
                    "\n  Tip: Log in to a character on this realm once so FlipQueue can find it|r")
            else
                hdr.bg:SetColorTexture(0.12, 0.15, 0.2, 0.8)
                local charData = ns.db.characters and ns.db.characters[group.charKey]
                local cc = charData and (UI._CLASS_COLORS or {})[charData.class] or "888888"
                local charDisplay = "|cff" .. cc .. group.charName .. "|r"
                local realmDisplay = group.realm ~= "" and (ns.COLORS.GRAY .. " - " .. group.realm .. "|r") or ""
                hdr.nameText:SetText(charDisplay .. realmDisplay ..
                    ns.COLORS.GRAY .. "  (" .. #group.items .. " items)|r")
            end

            hdr.nameText:ClearAllPoints()
            hdr.nameText:SetPoint("LEFT", hdr, "LEFT", 6, 0)
            hdr.nameText:SetPoint("RIGHT", hdr.rightText, "LEFT", -4, 0)

            local goldStr = UI._FormatGoldValue and UI._FormatGoldValue(group.totalGold) or ""
            if goldStr ~= "" then
                local goldColor = isUnassigned and ns.COLORS.GRAY or ns.COLORS.YELLOW
                hdr.rightText:SetText(goldColor .. "~" .. goldStr .. "|r")
            end

            local hdrBgColor = isUnassigned and {0.15, 0.08, 0.08, 0.7} or {0.12, 0.15, 0.2, 0.8}
            local hdrHoverColor = isUnassigned and {0.2, 0.1, 0.1, 0.8} or {0.15, 0.2, 0.28, 0.9}
            hdr:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(unpack(hdrHoverColor))
            end)
            hdr:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(unpack(hdrBgColor))
            end)
            genY = genY + HDR_ROW_H

            -- Item rows under this group
            for ii, item in ipairs(group.items) do
                local row = GetOrCreateGenRow(GEN_ROW_H)
                if isUnassigned then
                    row.bg:SetColorTexture(0.1, 0.06, 0.06, 0.4)
                else
                    row.bg:SetColorTexture(ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.12 or 0.1, 0.6)
                end

                local lookupIcon, quality, resolvedID
                pcall(function()
                    lookupIcon, quality, resolvedID = LookupItemInfo(item.itemID, item.itemKey, item.name)
                end)
                local itemIcon = item.icon or lookupIcon
                if itemIcon then
                    row.icon:SetTexture(itemIcon)
                    row.icon:ClearAllPoints()
                    row.icon:SetPoint("LEFT", row, "LEFT", 14, 0)
                    row.icon:Show()
                    row.nameText:ClearAllPoints()
                    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
                    row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                else
                    row.nameText:ClearAllPoints()
                    row.nameText:SetPoint("LEFT", row, "LEFT", 16, 0)
                    row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                end

                local displayName = item.name or "?"
                if isUnassigned then
                    displayName = ns.COLORS.GRAY .. (item.name or "?") .. "|r"
                elseif quality and QualityColorName then
                    displayName = QualityColorName(displayName, quality)
                elseif item.quality and item.quality ~= "" and QualityColorName then
                    displayName = QualityColorName(displayName, item.quality)
                end
                local qtyStr = (item.quantity or 1) > 1 and (" x" .. (item.quantity or 1)) or ""
                row.nameText:SetText(displayName .. qtyStr)

                if itemIcon and isUnassigned then
                    row.icon:SetDesaturated(true)
                    row.icon:SetAlpha(0.5)
                elseif itemIcon then
                    row.icon:SetDesaturated(false)
                    row.icon:SetAlpha(1)
                end

                local priceStr = item.expectedPrice or ""
                if isUnassigned then
                    row.rightText:SetText(ns.COLORS.GRAY .. priceStr .. "|r")
                elseif item.status == "missing" then
                    row.rightText:SetText(ns.COLORS.RED .. "missing|r")
                    row.bg:SetColorTexture(0.15, 0.05, 0.05, 0.4)
                else
                    row.rightText:SetText(priceStr)
                end

                local restoreBg
                if isUnassigned then
                    restoreBg = {0.1, 0.06, 0.06, 0.4}
                elseif item.status == "missing" then
                    restoreBg = {0.15, 0.05, 0.05, 0.4}
                else
                    restoreBg = {ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.12 or 0.1, 0.6}
                end

                local capturedItem = item
                local capturedID = resolvedID or tonumber(item.itemID)
                row:SetScript("OnEnter", function(self)
                    self.bg:SetColorTexture(1, 1, 1, 0.08)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if capturedID and capturedID > 0 then
                        GameTooltip:SetItemByID(capturedID)
                    else
                        GameTooltip:SetText(capturedItem.name or "?", 1, 1, 1)
                    end
                    if capturedItem.targetRealm and capturedItem.targetRealm ~= "" then
                        GameTooltip:AddLine("Realm: " .. capturedItem.targetRealm, 0.7, 0.7, 0.7)
                    end
                    if capturedItem.expectedPrice then
                        GameTooltip:AddLine("Price: " .. capturedItem.expectedPrice, 0.7, 0.7, 0.7)
                    end
                    if isUnassigned then
                        GameTooltip:AddLine("Create a character on this realm to add to your to-do list", 0.8, 0.4, 0.4)
                    end
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    self.bg:SetColorTexture(unpack(restoreBg))
                    GameTooltip:Hide()
                end)

                genY = genY + GEN_ROW_H
            end

            genY = genY + 2
        end
        s3.genContent:SetHeight(math.max(1, genY))

        -- Status bar
        local genStatusParts = {}
        local excludeCount = 0
        for _ in pairs(UI._genExcludedItems) do excludeCount = excludeCount + 1 end

        if UI._generatorPreview then
            local pvItems = UI._generatorPreview.items or UI._generatorPreview.tasks or {}
            table.insert(genStatusParts, #pvItems .. " tasks")
            table.insert(genStatusParts, "Replace/Append/Queue to commit")
        elseif currentList then
            local counts = ns.TodoList:GetStatusCounts()
            table.insert(genStatusParts, counts.pending .. " active")
            if counts.unassigned and counts.unassigned > 0 then
                table.insert(genStatusParts, ns.COLORS.ORANGE .. counts.unassigned .. " need chars|r")
            end
            table.insert(genStatusParts, "Generate to rebuild")
        else
            table.insert(genStatusParts, pending .. " deals")
            table.insert(genStatusParts, "Generate to match inventory")
        end
        if excludeCount > 0 then
            table.insert(genStatusParts, excludeCount .. " excluded")
        end

        local charCount = 0
        for _ in pairs(ns.db.characters or {}) do charCount = charCount + 1 end
        if charCount == 0 then
            table.insert(genStatusParts, ns.COLORS.YELLOW .. "Log in to each character once to enable matching|r")
        end

        mainFrame.statusText:SetText("Step 3 of 3  |  " .. table.concat(genStatusParts, "  |  "))
        return
    end

    -- ========================================
    -- CROSS-REALM TRACK: STEPS 1-3
    -- ========================================

    if wizTrack == "crossrealm" and wizStep == 1 then
        -- TODO: Cross-realm track step 1 -- Import Deals
        mainFrame.statusText:SetText("Cross-realm Step 1: Import Deals (coming soon)")
        return
    end

    if wizTrack == "crossrealm" and wizStep == 2 then
        -- TODO: Cross-realm track step 2 -- Filter Deals
        mainFrame.statusText:SetText("Cross-realm Step 2: Filter Deals (coming soon)")
        return
    end

    if wizTrack == "crossrealm" and wizStep == 3 then
        -- TODO: Cross-realm track step 3 -- Configure & Generate
        mainFrame.statusText:SetText("Cross-realm Step 3: Configure & Generate (coming soon)")
        return
    end

    -- Fallback
    mainFrame.statusText:SetText(pending .. " deals  |  To-Do Generator")
end
