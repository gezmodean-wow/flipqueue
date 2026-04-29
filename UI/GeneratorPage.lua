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
    UI._generatorPreview = ns.TodoList:GenerateTodoList("fpScanner", allocationOrder, {
        filterMode = UI._genFilterMode,
        filterValue = UI._genFilterValue,
        excludedItems = UI._genExcludedItems,
    })
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
            statusStr = ns.COLORS.GRAY .. "No stock" .. "|r"
            sortStatus = 3
        elseif item.status == "posted" then
            statusStr = ns.COLORS.GRAY .. "Posted" .. "|r"
            sortStatus = 4
        elseif item.status == "skipped" then
            statusStr = ns.COLORS.ORANGE .. (item.failReason or "Skipped") .. "|r"
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
            rowColor = {0.4, 0.4, 0.4, 0.08}
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
            _tooltipItemString = item.itemKey and ns:ItemKeyToItemString(item.itemKey) or nil,
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

local CARD_MAX_WIDTH = 260
local CARD_HEIGHT = 120
local CARD_GAP = 20

local function CreateTrackCard(parent, title, subtitle, iconPath)
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(CARD_MAX_WIDTH, CARD_HEIGHT)
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

        gf.trackSelectPanel.dealFinderCard = CreateTrackCard(
            gf.trackSelectPanel,
            "Deal Finder",
            "Find deals from TSM + personal data",
            "Interface\\Icons\\INV_Misc_Coin_01")
        gf.trackSelectPanel.dealFinderCard:SetScript("OnClick", function()
            UI.currentPage = "deals"
            UI:Refresh()
        end)

        gf.trackSelectPanel.inventoryCard = CreateTrackCard(
            gf.trackSelectPanel,
            "FP: Inventory Scan",
            "Import FlippingPal inventory scan",
            "Interface\\Icons\\INV_Misc_Bag_07")
        gf.trackSelectPanel.inventoryCard:SetScript("OnClick", function()
            SaveWizardState("inventory", 1)
            UI:Refresh()
        end)

        gf.trackSelectPanel.crossrealmCard = CreateTrackCard(
            gf.trackSelectPanel,
            "FP: Cross-Realm",
            "Import FlippingPal cross-realm flips",
            "Interface\\Icons\\INV_Misc_Map_01")
        gf.trackSelectPanel.crossrealmCard:SetScript("OnClick", function()
            SaveWizardState("crossrealm", 1)
            UI:Refresh()
        end)

        -- Responsive card sizing: 3 cards in a row
        gf.trackSelectPanel:SetScript("OnSizeChanged", function(self, w)
            local availW = w - 40
            local cardW = math.min(CARD_MAX_WIDTH, math.floor((availW - CARD_GAP * 2) / 3))
            cardW = math.max(140, cardW)
            self.dealFinderCard:SetWidth(cardW)
            self.inventoryCard:SetWidth(cardW)
            self.crossrealmCard:SetWidth(cardW)

            -- Position cards centered
            local totalW3 = cardW * 3 + CARD_GAP * 2
            local startX = (w - totalW3) / 2
            self.dealFinderCard:ClearAllPoints()
            self.dealFinderCard:SetPoint("LEFT", self, "LEFT", startX, 0)
            self.inventoryCard:ClearAllPoints()
            self.inventoryCard:SetPoint("LEFT", self.dealFinderCard, "RIGHT", CARD_GAP, 0)
            self.crossrealmCard:ClearAllPoints()
            self.crossrealmCard:SetPoint("LEFT", self.inventoryCard, "RIGHT", CARD_GAP, 0)
        end)

        -- ---- NAV BUTTONS (Back / Next) ----
        gf.backBtn = CreateNavButton(gf, "Back")
        gf.backBtn:SetPoint("BOTTOMLEFT", gf, "BOTTOMLEFT", 8, 6)
        gf.backBtn:Hide()

        gf.nextBtn = CreateNavButton(gf, "Next")
        gf.nextBtn:SetPoint("BOTTOMRIGHT", gf, "BOTTOMRIGHT", -8, 6)
        gf.nextBtn:Hide()

        gf.saveBtn = CreateNavButton(gf, "Save")
        gf.saveBtn:SetPoint("BOTTOMRIGHT", gf, "BOTTOMRIGHT", -8, 6)
        gf.saveBtn:Hide()
        gf.saveBtn:SetBackdropColor(0.15, 0.25, 0.15, 1)
        gf.saveBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 0.8)
        gf.saveBtn.text:SetTextColor(0.3, 1, 0.3)

        -- ---- LIST NAME FIELD (inline, near Save button) ----
        gf.nameLabel = gf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gf.nameLabel:SetText("List name:")
        gf.nameLabel:SetTextColor(0.6, 0.6, 0.6)
        gf.nameLabel:SetPoint("RIGHT", gf.saveBtn, "LEFT", -6, 0)
        gf.nameLabel:Hide()

        gf.nameBox = CreateFrame("EditBox", nil, gf, "InputBoxTemplate")
        gf.nameBox:SetSize(180, 20)
        gf.nameBox:SetAutoFocus(false)
        gf.nameBox:SetMaxLetters(60)
        gf.nameBox:SetPoint("RIGHT", gf.nameLabel, "LEFT", -4, 0)
        gf.nameBox:SetFontObject("GameFontHighlightSmall")
        gf.nameBox:Hide()
        gf.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        gf.nameBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            -- Trigger save via the save button click handler
            if gf.saveBtn:IsShown() then
                gf.saveBtn:GetScript("OnClick")(gf.saveBtn)
            end
        end)

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

        s2.premiumNote = s2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s2.premiumNote:SetPoint("TOPLEFT", s2.instrLabel, "BOTTOMLEFT", 0, -2)
        s2.premiumNote:SetText("Requires FlippingPal Premium")
        s2.premiumNote:SetTextColor(0.5, 0.5, 0.5)

        -- Edit box area
        s2.editBg = CreateFrame("Frame", nil, s2, "BackdropTemplate")
        s2.editBg:SetPoint("TOPLEFT", s2, "TOPLEFT", 4, -36)
        s2.editBg:SetPoint("TOPRIGHT", s2, "TOPRIGHT", -4, -36)
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
        -- Click anywhere on the background to focus the EditBox
        s2.editBg:SetScript("OnMouseDown", function() s2.editBox:SetFocus() end)

        -- Grouped preview scroll (replaces flat table)
        s2.previewScroll = CreateFrame("ScrollFrame", "FlipQueueGenImportPreview", s2, "UIPanelScrollFrameTemplate")
        s2.previewScroll:SetPoint("TOPLEFT", s2.editBg, "BOTTOMLEFT", 0, -4)
        s2.previewScroll:SetPoint("BOTTOMRIGHT", s2, "BOTTOMRIGHT", -22, 40)
        s2.previewScroll:Hide()

        s2.previewContent = CreateFrame("Frame", nil, s2.previewScroll)
        s2.previewContent:SetWidth(s2.previewScroll:GetWidth() or 500)
        s2.previewScroll:SetScrollChild(s2.previewContent)
        s2.previewScroll:SetScript("OnSizeChanged", function(sf, w) s2.previewContent:SetWidth(w) end)
        s2.previewRows = {}

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

        -- Import button (hidden — Next button handles import now)
        s2.importBtn = CreateHeaderBtn(s2, "Import", "Import pasted data into deals", function() end)
        s2.importBtn:SetPoint("LEFT", s2.statusLabel, "RIGHT", 10, 0)
        s2.importBtn:Hide()

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
                        local total = #items
                        s2.editBox:SetText("")
                        s2._previewData = nil
                        s2._previewResults = nil
                        s2.previewScroll:Hide()
                        for _, r in ipairs(s2.previewRows) do r:Hide() end
                        s2._lastLen = 0
                        local function Finish(added)
                            ns:Print("Imported " .. added .. " new deals (" .. total .. " parsed, duplicates merged).")
                            s2.statusLabel:SetText(ns.COLORS.GREEN .. added .. " deals imported!|r")
                            -- Auto-advance to step 3 (generate) after auto-import
                            SaveWizardState(UI._wizardTrack, 3)
                            AutoGenerate()
                            UI:Refresh()
                            if UI.RefreshMini then UI:RefreshMini() end
                        end
                        if total >= (ns.Import.LARGE_THRESHOLD or 500) then
                            -- Large paste: chunk to avoid client freeze (FQ-131).
                            s2.statusLabel:SetText(ns.COLORS.YELLOW .. "Importing " .. total .. " deals...|r")
                            ns.Import:SaveChunked(items, nil, ns.Import.CHUNK_SIZE,
                                function(processed, t)
                                    s2.statusLabel:SetText(ns.COLORS.YELLOW
                                        .. string.format("Importing... %d / %d", processed, t) .. "|r")
                                end,
                                Finish)
                        else
                            Finish(ns.Import:Save(items))
                        end
                    else
                        -- Large preview is expensive (O(N^2) dedup + per-row UI render).
                        -- For full-region FP dumps, skip preview and route through the
                        -- chunked save path so the client doesn't freeze (FQ-131).
                        if #items >= (ns.Import.LARGE_THRESHOLD or 500) then
                            s2.statusLabel:SetText(ns.COLORS.YELLOW
                                .. "Large paste (" .. #items .. " deals) — preview skipped. "
                                .. "Enable Auto-Import or click Next to import in chunks.|r")
                            s2._previewData = items
                            s2._previewResults = nil
                            s2.previewScroll:Hide()
                            for _, r in ipairs(s2.previewRows) do r:Hide() end
                            s2._lastLen = newLen
                            UI:Refresh()
                            return
                        end
                        s2._previewData = items
                        s2._previewResults = ns.Import:PreviewAdd(items)

                        -- Group deals by item name, tracking dupe status
                        local itemGroups = {}  -- name -> { deals = {}, dupeCount = 0 }
                        local itemOrder = {}
                        local dealCount, dupeCount = 0, 0
                        for _, result in ipairs(s2._previewResults) do
                            local item = result.item
                            local name = item.name or "?"
                            if not itemGroups[name] then
                                itemGroups[name] = {
                                    deals = {},
                                    dupeCount = 0,
                                    quality = item.quality,
                                    itemID = item.itemID,
                                    itemKey = item.itemKey,
                                    ilvl = item.ilvl,
                                }
                                table.insert(itemOrder, name)
                            end
                            local isDupe = result._importStatus == "duplicate"
                            if isDupe then
                                dupeCount = dupeCount + 1
                                itemGroups[name].dupeCount = itemGroups[name].dupeCount + 1
                            end
                            dealCount = dealCount + 1
                            table.insert(itemGroups[name].deals, {
                                realm = item.targetRealm or "",
                                price = item.expectedPrice or "",
                                isDupe = isDupe,
                                dupeReason = result._dupeReason,
                            })
                        end

                        -- Find filtered inventory items with no deals
                        local pool = ns.TodoList and ns.TodoList:GetFilteredItemPool(
                            UI._genFilterMode, UI._genFilterValue, UI._genExcludedItems) or {}
                        local noDeals = {}
                        for _, p in ipairs(pool) do
                            local pName = (p.name or ""):lower()
                            local found = false
                            for _, item in ipairs(items) do
                                if (item.name or ""):lower() == pName then found = true; break end
                                local pNumID = tonumber(p.itemID)
                                local iNumID = tonumber(item.itemID)
                                if pNumID and pNumID > 0 and pNumID == iNumID then found = true; break end
                            end
                            if not found then
                                table.insert(noDeals, p)
                            end
                        end

                        -- Build grouped scroll content
                        for _, row in ipairs(s2.previewRows) do row:Hide() end
                        local pvRowIdx = 0
                        local pvY = 0
                        local ROW_H = 16
                        local HDR_H = 20

                        local function GetOrCreatePvRow(h)
                            pvRowIdx = pvRowIdx + 1
                            local row = s2.previewRows[pvRowIdx]
                            if not row then
                                row = CreateFrame("Frame", nil, s2.previewContent)
                                row.bg = row:CreateTexture(nil, "BACKGROUND")
                                row.bg:SetAllPoints()
                                row.left = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                                row.left:SetPoint("LEFT", row, "LEFT", 6, 0)
                                row.left:SetJustifyH("LEFT")
                                row.right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                                row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                                row.right:SetJustifyH("RIGHT")
                                row.left:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
                                s2.previewRows[pvRowIdx] = row
                            end
                            row:SetHeight(h)
                            row:ClearAllPoints()
                            row:SetPoint("TOPLEFT", s2.previewContent, "TOPLEFT", 0, -pvY)
                            row:SetPoint("RIGHT", s2.previewContent, "RIGHT", 0, 0)
                            row.left:SetText("")
                            row.right:SetText("")
                            row:Show()
                            return row
                        end

                        -- Render item groups
                        for _, name in ipairs(itemOrder) do
                            local grp = itemGroups[name]
                            -- Find inventory qty for this item
                            local invQty = 0
                            for _, p in ipairs(pool) do
                                if (p.name or ""):lower() == name:lower() then
                                    invQty = invQty + (p.totalQuantity or 1)
                                end
                            end

                            local qColor = grp.quality and IMPORT_QUALITY_COLORS[grp.quality]
                            local coloredName = qColor and ("|cff" .. qColor .. name .. "|r") or name
                            local hdr = GetOrCreatePvRow(HDR_H)
                            hdr.bg:SetColorTexture(0.12, 0.15, 0.2, 0.8)
                            local invStr = invQty > 0 and (ns.COLORS.GREEN .. invQty .. " in stock|r") or (ns.COLORS.RED .. "not in inventory|r")
                            hdr.left:SetText(coloredName)
                            hdr.right:SetText(#grp.deals .. " deal(s)  |  " .. invStr)
                            pvY = pvY + HDR_H

                            -- Sort deals: non-dupe first, then by price (descending)
                            table.sort(grp.deals, function(a, b)
                                if a.isDupe ~= b.isDupe then return not a.isDupe end
                                return (a.price or "") > (b.price or "")
                            end)

                            for di, deal in ipairs(grp.deals) do
                                local row = GetOrCreatePvRow(ROW_H)
                                if deal.isDupe then
                                    row.bg:SetColorTexture(0.06, 0.06, 0.06, 0.4)
                                    row.left:SetText("    " .. ns.COLORS.GRAY .. deal.realm .. "|r")
                                    row.right:SetText(ns.COLORS.GRAY .. deal.price .. "  (dupe: " .. (deal.dupeReason or "") .. ")|r")
                                elseif di <= invQty then
                                    -- Within stock: would be allocated
                                    row.bg:SetColorTexture(0.05, 0.1, 0.05, 0.4)
                                    row.left:SetText("    " .. ns.COLORS.GREEN .. deal.realm .. "|r")
                                    row.right:SetText(ns.COLORS.GREEN .. deal.price .. "|r")
                                else
                                    -- Overflow: more deals than stock
                                    row.bg:SetColorTexture(0.06, 0.06, 0.06, 0.4)
                                    row.left:SetText("    " .. ns.COLORS.GRAY .. deal.realm .. "|r")
                                    row.right:SetText(ns.COLORS.GRAY .. deal.price .. "  (extra)|r")
                                end
                                pvY = pvY + ROW_H
                            end
                            pvY = pvY + 2
                        end

                        -- No-deals section
                        if #noDeals > 0 then
                            pvY = pvY + 4
                            local ndHdr = GetOrCreatePvRow(HDR_H)
                            ndHdr.bg:SetColorTexture(0.12, 0.06, 0.06, 0.8)
                            ndHdr.left:SetText(ns.COLORS.RED .. #noDeals .. " inventory items with no deals|r")
                            ndHdr.right:SetText("")
                            pvY = pvY + HDR_H

                            for ni, nd in ipairs(noDeals) do
                                local row = GetOrCreatePvRow(ROW_H)
                                row.bg:SetColorTexture(0.08, 0.04, 0.04, ni % 2 == 0 and 0.4 or 0.3)
                                row.left:SetText("    " .. ns.COLORS.GRAY .. (nd.name or "?") .. "|r")
                                local qtyStr = (nd.totalQuantity or 1) > 1 and ("x" .. nd.totalQuantity) or ""
                                row.right:SetText(ns.COLORS.GRAY .. qtyStr .. "|r")
                                pvY = pvY + ROW_H
                            end
                        end

                        s2.previewContent:SetHeight(math.max(1, pvY))
                        s2.previewScroll:Show()

                        local uniqueItems = #itemOrder
                        local parts = {}
                        table.insert(parts, ns.COLORS.GREEN .. (dealCount - dupeCount) .. " deals|r")
                        table.insert(parts, uniqueItems .. " items")
                        if dupeCount > 0 then table.insert(parts, ns.COLORS.GRAY .. dupeCount .. " dupes|r") end
                        if #noDeals > 0 then table.insert(parts, ns.COLORS.RED .. #noDeals .. " no deals|r") end
                        s2.statusLabel:SetText(table.concat(parts, "  ") .. "  -- click Import & Next to continue")
                        -- Refresh to show the Next button now that preview data exists
                        UI:Refresh()
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
                AutoGenerate()
                UI:Refresh()
            end)
            s3.sortBtns[mode.key] = btn
        end

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

        -- ===== CROSS-REALM STEP CONTAINERS =====
        gf.crStepContainers = {}
        for i = 1, 3 do
            local sc = CreateFrame("Frame", nil, gf)
            sc:Hide()
            gf.crStepContainers[i] = sc
        end

        -- ===== CR STEP 1: Import Deals =====
        local cr1 = gf.crStepContainers[1]

        cr1.instrLabel = cr1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        cr1.instrLabel:SetPoint("TOPLEFT", cr1, "TOPLEFT", 8, -8)
        cr1.instrLabel:SetText("Paste cross-realm flip data from FlippingPal:")
        cr1.instrLabel:SetTextColor(0.4, 0.8, 0.9)

        cr1.premiumNote = cr1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr1.premiumNote:SetPoint("TOPLEFT", cr1.instrLabel, "BOTTOMLEFT", 0, -2)
        cr1.premiumNote:SetText("Available with FlippingPal Basic")
        cr1.premiumNote:SetTextColor(0.5, 0.5, 0.5)

        cr1.editBg = CreateFrame("Frame", nil, cr1, "BackdropTemplate")
        cr1.editBg:SetPoint("TOPLEFT", cr1, "TOPLEFT", 4, -36)
        cr1.editBg:SetPoint("TOPRIGHT", cr1, "TOPRIGHT", -4, -36)
        cr1.editBg:SetHeight(80)
        cr1.editBg:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        cr1.editBg:SetBackdropColor(0.05, 0.05, 0.08, 1)
        cr1.editBg:SetBackdropBorderColor(0.15, 0.3, 0.35, 0.8)

        cr1.editScroll = CreateFrame("ScrollFrame", "FlipQueueCRImportScroll", cr1.editBg, "UIPanelScrollFrameTemplate")
        cr1.editScroll:SetPoint("TOPLEFT", cr1.editBg, "TOPLEFT", 6, -4)
        cr1.editScroll:SetPoint("BOTTOMRIGHT", cr1.editBg, "BOTTOMRIGHT", -22, 4)

        cr1.editBox = CreateFrame("EditBox", "FlipQueueCRImportEdit", cr1.editScroll)
        cr1.editBox:SetMultiLine(true)
        cr1.editBox:SetAutoFocus(false)
        cr1.editBox:SetMaxLetters(0)
        cr1.editBox:SetFontObject("ChatFontNormal")
        cr1.editBox:SetWidth(cr1.editScroll:GetWidth() or 500)
        cr1.editScroll:SetScrollChild(cr1.editBox)
        cr1.editScroll:SetScript("OnSizeChanged", function(sf, w)
            cr1.editBox:SetWidth(w)
        end)
        -- Click anywhere on the background to focus the EditBox
        cr1.editBg:SetScript("OnMouseDown", function() cr1.editBox:SetFocus() end)

        cr1.previewTable = UI:CreateScrollTable(cr1, {
            {key = "status",    label = "Status",    width = 52,  align = "CENTER", sortable = true},
            {key = "name",      label = "Item",      width = 140, sortable = true},
            {key = "sellRealm", label = "Sell Realm", width = 90,  sortable = true},
            {key = "buyRealm",  label = "Buy Realm",  width = 90,  sortable = true},
            {key = "buyPrice",  label = "Buy Price",  width = 70,  sortable = true},
            {key = "profit",    label = "Profit",     width = 60,  sortable = true},
            {key = "qty",       label = "Qty",        width = 30,  align = "CENTER", sortable = true},
        })
        cr1.previewTable:SetSort("status", true)
        if UI._RegisterTable then UI._RegisterTable(cr1.previewTable) end

        cr1.previewTable.headerFrame:SetParent(cr1)
        cr1.previewTable.headerFrame:ClearAllPoints()
        cr1.previewTable.headerFrame:SetPoint("TOPLEFT", cr1.editBg, "BOTTOMLEFT", 0, -4)
        cr1.previewTable.headerFrame:SetPoint("TOPRIGHT", cr1.editBg, "BOTTOMRIGHT", 0, -4)

        cr1.previewTable.scrollFrame:SetParent(cr1)
        cr1.previewTable.scrollFrame:ClearAllPoints()
        cr1.previewTable.scrollFrame:SetPoint("TOPLEFT", cr1.previewTable.headerFrame, "BOTTOMLEFT", 0, 0)
        cr1.previewTable.scrollFrame:SetPoint("BOTTOMRIGHT", cr1, "BOTTOMRIGHT", -22, 40)

        cr1.statusLabel = cr1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr1.statusLabel:SetPoint("LEFT", cr1, "BOTTOMLEFT", 8, 22)
        cr1.statusLabel:SetTextColor(0.5, 0.5, 0.5)
        cr1.statusLabel:SetText("")


        cr1._lastLen = 0
        cr1._previewData = nil
        cr1._previewResults = nil

        local CR_QUALITY_COLORS = {
            Poor = "9d9d9d", Common = "ffffff", Uncommon = "1eff00",
            Rare = "0070dd", Epic = "a335ee", Legendary = "ff8000",
            Artifact = "e6cc80", Heirloom = "00ccff",
        }

        cr1.editBox:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local text = self:GetText()
            local newLen = #text
            if cr1._lastLen < 10 and newLen > 50 and text:find("\n") then
                local items = ns.Import:Parse(text)
                if #items > 0 then
                    -- Filter to cross-realm deals only
                    local crossItems = {}
                    for _, item in ipairs(items) do
                        if (item.dealType == "flip" or item.dealType == "buy")
                            and item.buyRealm and item.buyRealm ~= "" then
                            table.insert(crossItems, item)
                        else
                            table.insert(crossItems, item) -- include all for visibility
                        end
                    end

                    -- Large preview is expensive (O(N^2) dedup + per-row UI render).
                    -- Skip preview rendering for full-region FP dumps so the client
                    -- doesn't freeze; user can still click Next to import (FQ-131).
                    if #crossItems >= (ns.Import.LARGE_THRESHOLD or 500) then
                        cr1.statusLabel:SetText(ns.COLORS.YELLOW
                            .. "Large paste (" .. #crossItems .. " deals) — preview skipped. "
                            .. "Click Next to import in chunks.|r")
                        cr1._previewData = crossItems
                        cr1._previewResults = nil
                        cr1.previewTable:SetData({})
                        cr1.previewTable.headerFrame:Hide()
                        cr1.previewTable.scrollFrame:Hide()
                        cr1._lastLen = newLen
                        UI:Refresh()
                        return
                    end

                    cr1._previewData = crossItems
                    cr1._previewResults = ns.Import:PreviewAdd(crossItems, "fpCrossRealm")

                    local data = {}
                    local newCount, dupCount, updateCount = 0, 0, 0
                    for _, result in ipairs(cr1._previewResults) do
                        local item = result.item
                        local st = result._importStatus
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
                        local qColor = item.quality and CR_QUALITY_COLORS[item.quality]
                        if qColor then
                            displayName = "|cff" .. qColor .. displayName .. "|r"
                        end

                        local isCrossRealm = (item.dealType == "flip" or item.dealType == "buy")
                            and item.buyRealm and item.buyRealm ~= ""
                        if isCrossRealm then
                            displayName = ns.COLORS.CYAN .. "[XR] " .. "|r" .. displayName
                        end

                        table.insert(data, {
                            status    = statusStr,
                            name      = displayName,
                            sellRealm = item.targetRealm or "",
                            buyRealm  = item.buyRealm or "",
                            buyPrice  = item.buyPrice or "",
                            profit    = item.profitAmount or "",
                            qty       = item.quantity or 1,
                            _sortStatus = statusSort,
                            _tooltipItemString = item.itemKey and ns.ItemKeyToItemString
                                and ns:ItemKeyToItemString(item.itemKey) or nil,
                            _tooltipItemID = tonumber(item.itemID),
                            _tooltipText = item.name,
                            _rowColor = isCrossRealm and {0.1, 0.3, 0.5, 0.08} or nil,
                        })
                    end

                    cr1.previewTable:SetData(data)
                    cr1.previewTable.headerFrame:Show()
                    cr1.previewTable.scrollFrame:Show()

                    local parts = {}
                    if newCount > 0 then table.insert(parts, ns.COLORS.GREEN .. newCount .. " new|r") end
                    if updateCount > 0 then table.insert(parts, ns.COLORS.YELLOW .. updateCount .. " updates|r") end
                    if dupCount > 0 then table.insert(parts, ns.COLORS.GRAY .. dupCount .. " dupes|r") end
                    cr1.statusLabel:SetText(table.concat(parts, "  ") .. "  -- review results, then click Next to filter")
                else
                    cr1.statusLabel:SetText(ns.COLORS.RED .. "No items found in pasted data.|r")
                end
            end
            cr1._lastLen = newLen
        end)
        cr1.editBox:SetScript("OnEscapePressed", function() cr1.editBox:ClearFocus() end)

        -- ===== CR STEP 2: Filter Deals =====
        local cr2 = gf.crStepContainers[2]

        cr2.filterDesc = cr2:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cr2.filterDesc:SetPoint("TOPLEFT", cr2, "TOPLEFT", 6, -4)
        cr2.filterDesc:SetPoint("RIGHT", cr2, "RIGHT", -6, 0)
        cr2.filterDesc:SetJustifyH("LEFT")
        cr2.filterDesc:SetWordWrap(true)
        cr2.filterDesc:SetTextColor(0.45, 0.45, 0.45)
        cr2.filterDesc:SetText("Narrow which cross-realm deals to include in your to-do list.")

        -- Section A: TSM Group Filter
        cr2.tsmHeader = CreateFrame("Button", nil, cr2, "BackdropTemplate")
        cr2.tsmHeader:SetHeight(20)
        cr2.tsmHeader:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        cr2.tsmHeader:SetBackdropColor(0.1, 0.1, 0.15, 1)
        cr2.tsmHeader:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)
        cr2.tsmHeader.text = cr2.tsmHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr2.tsmHeader.text:SetPoint("LEFT", cr2.tsmHeader, "LEFT", 6, 0)
        cr2.tsmHeader.toggle = cr2.tsmHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr2.tsmHeader.toggle:SetPoint("RIGHT", cr2.tsmHeader, "RIGHT", -6, 0)

        cr2.tsmCheck = CreateFrame("CheckButton", "FlipQueueCRTSMCheck", cr2, "UICheckButtonTemplate")
        cr2.tsmCheck:SetSize(20, 20)
        cr2.tsmCheck:SetScript("OnClick", function() UI:Refresh() end)
        cr2.tsmCheckLabel = cr2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr2.tsmCheckLabel:SetText("Filter by TSM Group")
        cr2.tsmCheckLabel:SetTextColor(0.7, 0.7, 0.7)

        cr2.tsmBody = CreateFrame("Frame", nil, cr2)
        cr2.tsmBody:SetHeight(120)
        cr2.tsmBody:Hide()

        cr2.tsmTreeFrame = CreateFrame("Frame", nil, cr2.tsmBody)
        cr2.tsmTreeFrame:SetHeight(100)

        cr2.tsmUnavail = cr2.tsmBody:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cr2.tsmUnavail:SetTextColor(0.5, 0.5, 0.5)
        cr2.tsmUnavail:SetText("TSM not detected")
        cr2.tsmUnavail:Hide()

        if UI.CreateGroupTree then
            cr2.tsmGroupTree = UI:CreateGroupTree(cr2.tsmTreeFrame, function(path)
                UI._crTSMGroupPath = path or ""
                UI:Refresh()
            end)
        end

        cr2._tsmExpanded = false
        cr2.tsmHeader:SetScript("OnClick", function()
            cr2._tsmExpanded = not cr2._tsmExpanded
            UI:Refresh()
        end)
        cr2.tsmHeader:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        end)
        cr2.tsmHeader:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.1, 0.1, 0.15, 1)
        end)

        -- Section B: Auctionator List Filter
        cr2.auctHeader = CreateFrame("Button", nil, cr2, "BackdropTemplate")
        cr2.auctHeader:SetHeight(20)
        cr2.auctHeader:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        cr2.auctHeader:SetBackdropColor(0.1, 0.1, 0.15, 1)
        cr2.auctHeader:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)
        cr2.auctHeader.text = cr2.auctHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr2.auctHeader.text:SetPoint("LEFT", cr2.auctHeader, "LEFT", 6, 0)
        cr2.auctHeader.toggle = cr2.auctHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr2.auctHeader.toggle:SetPoint("RIGHT", cr2.auctHeader, "RIGHT", -6, 0)

        cr2.auctCheck = CreateFrame("CheckButton", "FlipQueueCRAuctCheck", cr2, "UICheckButtonTemplate")
        cr2.auctCheck:SetSize(20, 20)
        cr2.auctCheck:SetScript("OnClick", function() UI:Refresh() end)
        cr2.auctCheckLabel = cr2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr2.auctCheckLabel:SetText("Filter by Auctionator List")
        cr2.auctCheckLabel:SetTextColor(0.7, 0.7, 0.7)

        cr2.auctBody = CreateFrame("Frame", nil, cr2)
        cr2.auctBody:SetHeight(80)
        cr2.auctBody:Hide()

        cr2.auctScroll = CreateFrame("ScrollFrame", nil, cr2.auctBody, "UIPanelScrollFrameTemplate")
        cr2.auctContent = CreateFrame("Frame", nil, cr2.auctScroll)
        cr2.auctContent:SetWidth(1)
        cr2.auctContent:SetHeight(1)
        cr2.auctScroll:SetScrollChild(cr2.auctContent)
        cr2.auctScroll:SetScript("OnSizeChanged", function(sf, w)
            cr2.auctContent:SetWidth(w)
        end)
        cr2.auctRows = {}

        cr2.auctUnavail = cr2.auctBody:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cr2.auctUnavail:SetTextColor(0.5, 0.5, 0.5)
        cr2.auctUnavail:SetText("Auctionator not detected")
        cr2.auctUnavail:Hide()

        cr2._auctExpanded = false
        cr2.auctHeader:SetScript("OnClick", function()
            cr2._auctExpanded = not cr2._auctExpanded
            UI:Refresh()
        end)
        cr2.auctHeader:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        end)
        cr2.auctHeader:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.1, 0.1, 0.15, 1)
        end)

        -- Section C: Realm Filter
        cr2.realmHeader = CreateFrame("Button", nil, cr2, "BackdropTemplate")
        cr2.realmHeader:SetHeight(20)
        cr2.realmHeader:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        cr2.realmHeader:SetBackdropColor(0.1, 0.1, 0.15, 1)
        cr2.realmHeader:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)
        cr2.realmHeader.text = cr2.realmHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr2.realmHeader.text:SetPoint("LEFT", cr2.realmHeader, "LEFT", 6, 0)
        cr2.realmHeader.toggle = cr2.realmHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr2.realmHeader.toggle:SetPoint("RIGHT", cr2.realmHeader, "RIGHT", -6, 0)

        cr2.realmCheck = CreateFrame("CheckButton", "FlipQueueCRRealmCheck", cr2, "UICheckButtonTemplate")
        cr2.realmCheck:SetSize(20, 20)
        cr2.realmCheck:SetScript("OnClick", function() UI:Refresh() end)
        cr2.realmCheckLabel = cr2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr2.realmCheckLabel:SetText("Only show realms with characters")
        cr2.realmCheckLabel:SetTextColor(0.7, 0.7, 0.7)

        cr2.realmBody = CreateFrame("Frame", nil, cr2)
        cr2.realmBody:SetHeight(80)
        cr2.realmBody:Hide()

        cr2.realmScroll = CreateFrame("ScrollFrame", nil, cr2.realmBody, "UIPanelScrollFrameTemplate")
        cr2.realmContent = CreateFrame("Frame", nil, cr2.realmScroll)
        cr2.realmContent:SetWidth(1)
        cr2.realmContent:SetHeight(1)
        cr2.realmScroll:SetScrollChild(cr2.realmContent)
        cr2.realmScroll:SetScript("OnSizeChanged", function(sf, w)
            cr2.realmContent:SetWidth(w)
        end)
        cr2.realmRows = {}

        cr2.realmSelectAll = CreateHeaderBtn(cr2.realmBody, "Select All", nil, function()
            if UI._crRealmFilter then
                for realm in pairs(UI._crRealmFilter) do
                    UI._crRealmFilter[realm] = true
                end
            end
            UI:Refresh()
        end)
        cr2.realmDeselectAll = CreateHeaderBtn(cr2.realmBody, "Deselect All", nil, function()
            if UI._crRealmFilter then
                for realm in pairs(UI._crRealmFilter) do
                    UI._crRealmFilter[realm] = false
                end
            end
            UI:Refresh()
        end)

        cr2._realmExpanded = false
        cr2.realmHeader:SetScript("OnClick", function()
            cr2._realmExpanded = not cr2._realmExpanded
            UI:Refresh()
        end)
        cr2.realmHeader:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        end)
        cr2.realmHeader:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.1, 0.1, 0.15, 1)
        end)

        -- Count label at bottom
        cr2.countLabel = cr2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr2.countLabel:SetTextColor(0.6, 0.6, 0.6)

        -- ===== CR STEP 3: Configure & Generate =====
        local cr3 = gf.crStepContainers[3]

        cr3.buyAllocDesc = cr3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cr3.buyAllocDesc:SetTextColor(0.45, 0.45, 0.45)
        cr3.buyAllocDesc:SetJustifyH("LEFT")
        cr3.buyAllocDesc:SetWordWrap(true)
        cr3.buyAllocDesc:SetText("When two buy deals compete, which deal wins?")

        cr3.buyAllocLabel = cr3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr3.buyAllocLabel:SetText("Buy Priorities:")
        cr3.buyAllocLabel:SetTextColor(0.4, 0.8, 0.9)

        cr3.buyAllocRows = {}

        cr3.sellAllocDesc = cr3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cr3.sellAllocDesc:SetTextColor(0.45, 0.45, 0.45)
        cr3.sellAllocDesc:SetJustifyH("LEFT")
        cr3.sellAllocDesc:SetWordWrap(true)
        cr3.sellAllocDesc:SetText("When two sell deals need the same item, which deal wins?")

        cr3.sellAllocLabel = cr3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr3.sellAllocLabel:SetText("Sell Priorities:")
        cr3.sellAllocLabel:SetTextColor(0.9, 0.8, 0.3)

        cr3.sellAllocRows = {}

        -- List mode toggle
        cr3.listModeLabel = cr3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr3.listModeLabel:SetText("List Mode:")
        cr3.listModeLabel:SetTextColor(0.7, 0.7, 0.7)

        cr3.separateBtn = CreateToggleBtn(cr3, "Separate Lists")
        cr3.integratedBtn = CreateToggleBtn(cr3, "Integrated List")

        cr3.separateBtn:SetScript("OnClick", function()
            if ns.db then ns.db.settings.genCrossRealmListMode = "separate" end
            UI:Refresh()
        end)
        cr3.integratedBtn:SetScript("OnClick", function()
            if ns.db then ns.db.settings.genCrossRealmListMode = "integrated" end
            UI:Refresh()
        end)

        -- Integrated sort mode
        cr3.intSortLabel = cr3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cr3.intSortLabel:SetText("Sort by:")
        cr3.intSortLabel:SetTextColor(0.7, 0.7, 0.7)

        cr3.intSortProfitBtn = CreateToggleBtn(cr3, "Most Profitable")
        cr3.intSortDealBtn = CreateToggleBtn(cr3, "Best Deal")
        cr3.intSortBuysBtn = CreateToggleBtn(cr3, "Prioritize Buys")

        cr3.intSortProfitBtn:SetScript("OnClick", function()
            if ns.db then ns.db.settings.genIntegratedSortMode = "mostProfitable" end
            UI:Refresh()
        end)
        cr3.intSortDealBtn:SetScript("OnClick", function()
            if ns.db then ns.db.settings.genIntegratedSortMode = "bestDeal" end
            UI:Refresh()
        end)
        cr3.intSortBuysBtn:SetScript("OnClick", function()
            if ns.db then ns.db.settings.genIntegratedSortMode = "prioritizeBuys" end
            UI:Refresh()
        end)

        -- Generate button
        cr3.generateBtn = CreateHeaderBtn(cr3, "Generate",
            "Match cross-realm deals against inventory (preview)",
            function()
                -- Actual generation happens in the refresh logic below
                UI._crGenRequested = true
                UI:Refresh()
            end)

        -- Status label
        cr3.statusLabel = cr3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

        -- Separate-mode name inputs (one per column)
        local function CreateInlineNameBox(parent, labelText, labelColor)
            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetText(labelText)
            label:SetTextColor(unpack(labelColor))
            local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
            box:SetSize(120, 18)
            box:SetAutoFocus(false)
            box:SetMaxLetters(60)
            box:SetFontObject("GameFontHighlightSmall")
            box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            box:Hide()
            label:Hide()
            return label, box
        end
        cr3.buyNameLabel, cr3.buyNameBox = CreateInlineNameBox(cr3, "Buy list:", {0.4, 0.8, 0.9})
        cr3.sellNameLabel, cr3.sellNameBox = CreateInlineNameBox(cr3, "Sell list:", {0.9, 0.8, 0.3})

        -- Divider
        cr3.listDivider = cr3:CreateTexture(nil, "ARTWORK")
        cr3.listDivider:SetHeight(1)
        cr3.listDivider:SetColorTexture(0.3, 0.3, 0.4, 0.5)

        -- Generated items scroll area
        cr3.genScroll = CreateFrame("ScrollFrame", nil, cr3, "UIPanelScrollFrameTemplate")
        cr3.genContent = CreateFrame("Frame", nil, cr3.genScroll)
        cr3.genScroll:SetScrollChild(cr3.genContent)
        cr3.genScroll:SetScript("OnSizeChanged", function(sf, w)
            cr3.genContent:SetWidth(w)
        end)
        cr3.genRows = {}

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

    local crPending = ns:ImportGetCount("fpCrossRealm")
    local freshRow = TopRow()
    freshRow.label:SetText(
        ns.COLORS.GRAY .. "Bags:|r " .. bagAge ..
        ns.COLORS.GRAY .. "   Warbank:|r " .. wbAge ..
        ns.COLORS.GRAY .. "   Deals:|r " .. pending ..
        (crPending > 0 and (ns.COLORS.GRAY .. "   XR:|r " .. ns.COLORS.CYAN .. crPending .. "|r") or ""))

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
        gf.crStepContainers[i]:Hide()
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

    if wizStep < 3 then
        -- Step 2 (import): Next is hidden until paste data is ready;
        -- auto-import skips this entirely. Other steps show Next normally.
        local showNext = true
        if wizStep == 2 and wizTrack == "inventory" then
            local s2 = gf.stepContainers[2]
            showNext = s2 and s2._previewData and #s2._previewData > 0
        end

        if showNext then
            gf.nextBtn:Show()
            gf.nextBtn.text:SetText(wizStep == 2 and "Import & Next" or "Next")
            gf.nextBtn:SetScript("OnClick", function()
                -- Cross-realm step 1→2: save parsed deals to DB before advancing.
                -- Use SaveChunked for large pastes to avoid client freeze (FQ-131).
                if wizTrack == "crossrealm" and wizStep == 1 then
                    local cr1 = gf.crStepContainers[1]
                    if cr1._previewData and #cr1._previewData > 0 then
                        local data = cr1._previewData
                        local total = #data
                        cr1._previewData = nil
                        cr1._previewResults = nil
                        if total >= (ns.Import.LARGE_THRESHOLD or 500) then
                            ns:Print(ns.COLORS.YELLOW .. "Importing " .. total .. " cross-realm deals (large paste, please wait)...|r")
                            ns.Import:SaveChunked(data, "fpCrossRealm", ns.Import.CHUNK_SIZE, nil, function(added)
                                ns:Print("Cross-realm import: saved " .. added .. " deals to DB.")
                            end)
                        else
                            local added = ns.Import:Save(data, "fpCrossRealm")
                            ns:PrintDebug("Cross-realm import: saved " .. added .. " deals to DB.")
                        end
                    end
                end
                -- Inventory step 2: import pasted data before advancing.
                -- Use SaveChunked for large pastes to avoid client freeze (FQ-131).
                if wizTrack == "inventory" and wizStep == 2 then
                    local s2 = gf.stepContainers[2]
                    if s2 and s2._previewData and #s2._previewData > 0 then
                        local data = s2._previewData
                        local total = #data
                        s2.editBox:SetText("")
                        s2._previewData = nil
                        s2._previewResults = nil
                        s2._lastLen = 0
                        s2.previewScroll:Hide()
                        for _, r in ipairs(s2.previewRows) do r:Hide() end
                        if total >= (ns.Import.LARGE_THRESHOLD or 500) then
                            ns:Print(ns.COLORS.YELLOW .. "Importing " .. total .. " deals (large paste, please wait)...|r")
                            ns.Import:SaveChunked(data, nil, ns.Import.CHUNK_SIZE, nil, function(added)
                                ns:Print("Imported " .. added .. " new deals (" .. total .. " parsed, duplicates merged).")
                                if UI.Refresh then UI:Refresh() end
                            end)
                        else
                            local added = ns.Import:Save(data)
                            ns:Print("Imported " .. added .. " new deals (" .. total .. " parsed, duplicates merged).")
                        end
                    end
                end
                SaveWizardState(wizTrack, wizStep + 1)
                if wizStep + 1 == 3 and wizTrack ~= "crossrealm" then
                    AutoGenerate()
                end
                UI:Refresh()
            end)
        else
            gf.nextBtn:Hide()
        end
    end

    -- Save button + name field (step 3 only, shown by track-specific logic below)
    gf.nameLabel:Hide()
    gf.nameBox:Hide()
    gf.saveBtn:Hide()

    if wizStep == 3 then
        -- Default list name: "Generated YYYY-MM-DD HH:MM"
        local defaultName = "Generated " .. date("%Y-%m-%d %H:%M")
        if not gf.nameBox._initialized or gf.nameBox:GetText() == "" then
            gf.nameBox:SetText(defaultName)
            gf.nameBox._initialized = true
        end
    end

    -- Position step container for the current step
    local stepPool = wizTrack == "crossrealm" and gf.crStepContainers or gf.stepContainers
    local sc = stepPool[wizStep]
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
        local totalItemQty = 0
        for _, p in ipairs(filteredPool) do totalItemQty = totalItemQty + (p.totalQuantity or 1) end
        s1.countLabel:SetText(ns.COLORS.GRAY .. #filteredPool .. " unique item types, " .. totalItemQty .. " total items|r")

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
        local totalPoolQty = 0
        for _, p in ipairs(filteredPool) do totalPoolQty = totalPoolQty + (p.totalQuantity or 1) end
        local statusParts = {#filteredPool .. " unique item types, " .. totalPoolQty .. " total items"}
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

        -- Show preview if we have data
        if s2._previewData then
            s2.previewScroll:Show()
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

        -- Import FP Data button
        s3.importBtn:Hide()

        -- Auto-generate on step 3 entry (always keep preview up-to-date)
        if not UI._generatorPreview and ns:ImportGetCount("fpScanner") > 0 then
            AutoGenerate()
        end

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
            local actionableCount = 0
            local charGroups = 0
            for _, g in ipairs(displayGroups) do
                if g.charKey then
                    charGroups = charGroups + 1
                    for _, it in ipairs(g.items) do
                        if it.status ~= "missing" then
                            actionableCount = actionableCount + 1
                        end
                    end
                end
            end
            local rejCount = previewSource and previewSource.rejected and #previewSource.rejected or 0
            local ovCount = previewSource and previewSource.overflow and #previewSource.overflow or 0
            local ndCount = previewSource and previewSource.noDeals and #previewSource.noDeals or 0
            local wbHeld = previewSource and previewSource.warbankFull and #previewSource.warbankFull or 0
            local statusText = ns.COLORS.GRAY .. actionableCount .. " tasks across " .. charGroups .. " realm(s)"
            if rejCount > 0 then
                statusText = statusText .. "  |  " .. ns.COLORS.ORANGE .. rejCount .. " TSM rejected|r"
            end
            if ovCount > 0 then
                statusText = statusText .. "  |  " .. ns.COLORS.GRAY .. ovCount .. " extra deals"
            end
            if ndCount > 0 then
                statusText = statusText .. "  |  " .. ns.COLORS.RED .. ndCount .. " no deals|r"
            end
            if wbHeld > 0 then
                statusText = statusText .. "  |  " .. ns.COLORS.ORANGE .. wbHeld ..
                    " held (warbank full)|r"
            end
            statusText = statusText .. "|r"
            s3.statusLabel:SetText(statusText)
        else
            s3.statusLabel:SetText(
                ns.COLORS.GRAY .. "Import deals to generate a preview|r")
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
                    row.rightText:SetText(ns.COLORS.GRAY .. "no stock|r")
                    row.bg:SetColorTexture(0.08, 0.08, 0.08, 0.4)
                else
                    row.rightText:SetText(priceStr)
                end

                local restoreBg
                if isUnassigned then
                    restoreBg = {0.1, 0.06, 0.06, 0.4}
                elseif item.status == "missing" then
                    restoreBg = {0.08, 0.08, 0.08, 0.4}
                else
                    restoreBg = {ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.12 or 0.1, 0.6}
                end

                local capturedItem = item
                local capturedID = resolvedID or tonumber(item.itemID)
                local capturedItemStr = item.itemKey and ns:ItemKeyToItemString(item.itemKey) or nil
                row:SetScript("OnEnter", function(self)
                    self.bg:SetColorTexture(1, 1, 1, 0.08)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if capturedItemStr then
                        GameTooltip:SetHyperlink(capturedItemStr)
                    elseif capturedID and capturedID > 0 then
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

        -- Rejected-by-TSM section (shown below main list)
        local rejectedItems = previewSource and previewSource.rejected
        if rejectedItems and #rejectedItems > 0 then
            genY = genY + 6

            -- Section header
            local rejHdr = GetOrCreateGenRow(HDR_ROW_H)
            rejHdr.bg:SetColorTexture(0.2, 0.12, 0.02, 0.8)
            rejHdr.nameText:ClearAllPoints()
            rejHdr.nameText:SetPoint("LEFT", rejHdr, "LEFT", 6, 0)
            rejHdr.nameText:SetPoint("RIGHT", rejHdr.rightText, "LEFT", -4, 0)
            rejHdr.nameText:SetText(
                ns.COLORS.ORANGE .. "TSM Rejected" .. "|r" ..
                ns.COLORS.GRAY .. "  (" .. #rejectedItems .. " deals — click to keep)" .. "|r")
            rejHdr.rightText:SetText("")
            local rejHdrBg = {0.2, 0.12, 0.02, 0.8}
            rejHdr:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(0.25, 0.15, 0.04, 0.9)
            end)
            rejHdr:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(unpack(rejHdrBg))
            end)
            genY = genY + HDR_ROW_H

            for ri, rejItem in ipairs(rejectedItems) do
                local row = GetOrCreateGenRow(GEN_ROW_H)
                row.bg:SetColorTexture(0.12, 0.08, 0.02, ri % 2 == 0 and 0.5 or 0.35)

                local lookupIcon, quality, resolvedID
                pcall(function()
                    lookupIcon, quality, resolvedID = LookupItemInfo(rejItem.itemID, rejItem.itemKey, rejItem.name)
                end)
                local itemIcon = rejItem.icon or lookupIcon
                if itemIcon then
                    row.icon:SetTexture(itemIcon)
                    row.icon:ClearAllPoints()
                    row.icon:SetPoint("LEFT", row, "LEFT", 14, 0)
                    row.icon:SetDesaturated(true)
                    row.icon:SetAlpha(0.6)
                    row.icon:Show()
                    row.nameText:ClearAllPoints()
                    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
                    row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                else
                    row.nameText:ClearAllPoints()
                    row.nameText:SetPoint("LEFT", row, "LEFT", 16, 0)
                    row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                end

                local displayName = rejItem.name or "?"
                if quality and QualityColorName then
                    displayName = QualityColorName(displayName, quality)
                elseif rejItem.quality and rejItem.quality ~= "" and QualityColorName then
                    displayName = QualityColorName(displayName, rejItem.quality)
                end
                local qtyStr = (rejItem.quantity or 1) > 1 and (" x" .. (rejItem.quantity or 1)) or ""
                row.nameText:SetText(ns.COLORS.ORANGE .. displayName .. qtyStr .. "|r")

                -- Show reason + realm on the right
                local reasonShort = rejItem.failReason or "rejected"
                local realmShort = rejItem.targetRealm or ""
                if #realmShort > 20 then
                    realmShort = realmShort:match("^([^,]+)") or realmShort:sub(1, 20)
                end
                row.rightText:SetText(ns.COLORS.GRAY .. realmShort .. "  " .. ns.COLORS.ORANGE .. reasonShort .. "|r")

                -- Click to keep: move from rejected to items
                local capturedIdx = ri
                local capturedPreview = previewSource
                local restoreBgRej = {0.12, 0.08, 0.02, ri % 2 == 0 and 0.5 or 0.35}
                row:SetScript("OnClick", function()
                    if capturedPreview and capturedPreview.rejected then
                        local kept = table.remove(capturedPreview.rejected, capturedIdx)
                        if kept then
                            kept.status = "pending"
                            kept.failReason = kept.failReason and ("(overridden) " .. kept.failReason) or nil
                            table.insert(capturedPreview.items, kept)
                            UI:Refresh()
                        end
                    end
                end)
                row:SetScript("OnEnter", function(self)
                    self.bg:SetColorTexture(0.2, 0.15, 0.04, 0.7)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local tipID = resolvedID or tonumber(rejItem.itemID)
                    if not ns:SetTooltipItem(GameTooltip, rejItem.itemKey, tipID) then
                        GameTooltip:SetText(rejItem.name or "?", 1, 0.8, 0)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Realm: " .. (rejItem.targetRealm or "?"), 0.7, 0.7, 0.7)
                    if rejItem.expectedPrice then
                        GameTooltip:AddLine("Price: " .. rejItem.expectedPrice, 0.7, 0.7, 0.7)
                    end
                    if rejItem.failReason then
                        GameTooltip:AddLine(rejItem.failReason, 1, 0.5, 0)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Click to keep this deal", 0, 1, 0)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    self.bg:SetColorTexture(unpack(restoreBgRej))
                    GameTooltip:Hide()
                end)

                genY = genY + GEN_ROW_H
            end

            genY = genY + 2
        end

        -- Overflow section: deals that exceeded available stock
        local overflowItems = previewSource and previewSource.overflow
        if overflowItems and #overflowItems > 0 then
            genY = genY + 6
            local ovHdr = GetOrCreateGenRow(HDR_ROW_H)
            ovHdr.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
            ovHdr.nameText:ClearAllPoints()
            ovHdr.nameText:SetPoint("LEFT", ovHdr, "LEFT", 6, 0)
            ovHdr.nameText:SetPoint("RIGHT", ovHdr.rightText, "LEFT", -4, 0)
            ovHdr.nameText:SetText(
                ns.COLORS.GRAY .. #overflowItems .. " extra deals" .. "|r" ..
                ns.COLORS.GRAY .. "  (all stock allocated to higher-priority deals above)" .. "|r")
            ovHdr.rightText:SetText("")
            genY = genY + HDR_ROW_H

            -- Group overflow by item name for compact display
            local ovByName = {}
            local ovOrder = {}
            for _, ov in ipairs(overflowItems) do
                local n = ov.name or "?"
                if not ovByName[n] then
                    ovByName[n] = { count = 0, item = ov }
                    table.insert(ovOrder, n)
                end
                ovByName[n].count = ovByName[n].count + 1
            end
            for oi, name in ipairs(ovOrder) do
                local entry = ovByName[name]
                local row = GetOrCreateGenRow(GEN_ROW_H)
                row.bg:SetColorTexture(0.06, 0.06, 0.06, oi % 2 == 0 and 0.5 or 0.35)
                row.nameText:ClearAllPoints()
                row.nameText:SetPoint("LEFT", row, "LEFT", 16, 0)
                row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                row.nameText:SetText(ns.COLORS.GRAY .. name .. "|r")
                row.rightText:SetText(ns.COLORS.GRAY .. entry.count .. " extra deal(s)|r")
                genY = genY + GEN_ROW_H
            end
            genY = genY + 2
        end

        -- No-deals section: inventory items with zero matching deals
        local noDeals = previewSource and previewSource.noDeals
        if noDeals and #noDeals > 0 then
            genY = genY + 6
            local ndHdr = GetOrCreateGenRow(HDR_ROW_H)
            ndHdr.bg:SetColorTexture(0.12, 0.06, 0.06, 0.8)
            ndHdr.nameText:ClearAllPoints()
            ndHdr.nameText:SetPoint("LEFT", ndHdr, "LEFT", 6, 0)
            ndHdr.nameText:SetPoint("RIGHT", ndHdr.rightText, "LEFT", -4, 0)
            ndHdr.nameText:SetText(
                ns.COLORS.RED .. #noDeals .. " items with no deals" .. "|r" ..
                ns.COLORS.GRAY .. "  (no matching deals found in imported data)" .. "|r")
            ndHdr.rightText:SetText("")
            genY = genY + HDR_ROW_H

            for ni, ndItem in ipairs(noDeals) do
                local row = GetOrCreateGenRow(GEN_ROW_H)
                row.bg:SetColorTexture(0.08, 0.04, 0.04, ni % 2 == 0 and 0.5 or 0.35)

                local lookupIcon, quality
                pcall(function()
                    lookupIcon, quality = LookupItemInfo(ndItem.itemID, ndItem.itemKey, ndItem.name)
                end)
                local itemIcon = ndItem.icon or lookupIcon
                if itemIcon then
                    row.icon:SetTexture(itemIcon)
                    row.icon:ClearAllPoints()
                    row.icon:SetPoint("LEFT", row, "LEFT", 14, 0)
                    row.icon:SetDesaturated(true)
                    row.icon:SetAlpha(0.5)
                    row.icon:Show()
                    row.nameText:ClearAllPoints()
                    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
                    row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                else
                    row.nameText:ClearAllPoints()
                    row.nameText:SetPoint("LEFT", row, "LEFT", 16, 0)
                    row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                end

                local displayName = ndItem.name or "?"
                if quality and QualityColorName then
                    displayName = QualityColorName(displayName, quality)
                end
                row.nameText:SetText(displayName)
                local qtyStr = (ndItem.totalQuantity or 1) > 1 and ("x" .. ndItem.totalQuantity) or ""
                row.rightText:SetText(ns.COLORS.GRAY .. qtyStr .. "|r")
                genY = genY + GEN_ROW_H
            end
            genY = genY + 2
        end

        s3.genContent:SetHeight(math.max(1, genY))

        -- Save button with name field (inventory track)
        if UI._generatorPreview then
            gf.nameLabel:Show()
            gf.nameBox:Show()
            gf.saveBtn:Show()
            gf.saveBtn:SetScript("OnClick", function()
                local listName = gf.nameBox:GetText():match("^%s*(.-)%s*$")
                if not listName or listName == "" then
                    listName = "Generated " .. date("%Y-%m-%d %H:%M")
                end
                UI._generatorPreview.name = listName
                local currentList2 = ns.TodoList:GetCurrentList()
                local count = UI._generatorPreview.items and #UI._generatorPreview.items or 0
                if currentList2 then
                    ns.TodoList:CommitList(UI._generatorPreview, "upcoming")
                    ns:Print(ns.COLORS.GREEN .. "Queued \"" .. listName .. "\" with " .. count .. " tasks.|r")
                else
                    ns.TodoList:CommitList(UI._generatorPreview, "replace")
                    ns:Print(ns.COLORS.GREEN .. "Saved \"" .. listName .. "\" with " .. count .. " tasks.|r")
                end
                UI._generatorPreview = nil
                gf.nameBox._initialized = false
                SaveWizardState(nil, 0)
                UI:Refresh()
                if UI.RefreshMini then UI:RefreshMini() end
            end)
        end

        -- Status bar
        local genStatusParts = {}
        local excludeCount = 0
        for _ in pairs(UI._genExcludedItems) do excludeCount = excludeCount + 1 end

        if UI._generatorPreview then
            local pvItems = UI._generatorPreview.items or UI._generatorPreview.tasks or {}
            local pvRejected = UI._generatorPreview.rejected or {}
            local pvOverflow = UI._generatorPreview.overflow or {}
            local pvNoDeals = UI._generatorPreview.noDeals or {}
            local actionable = 0
            for _, it in ipairs(pvItems) do
                if it.status ~= "missing" and it.status ~= "unassigned" then
                    actionable = actionable + 1
                end
            end
            table.insert(genStatusParts, actionable .. " tasks")
            if #pvRejected > 0 then
                table.insert(genStatusParts, ns.COLORS.ORANGE .. #pvRejected .. " TSM rejected|r")
            end
            if #pvOverflow > 0 then
                table.insert(genStatusParts, ns.COLORS.GRAY .. #pvOverflow .. " extra|r")
            end
            if #pvNoDeals > 0 then
                table.insert(genStatusParts, ns.COLORS.RED .. #pvNoDeals .. " no deals|r")
            end
            table.insert(genStatusParts, "Enter a name and click Save")
        elseif currentList then
            local counts = ns.TodoList:GetStatusCounts()
            table.insert(genStatusParts, counts.pending .. " active")
            if counts.unassigned and counts.unassigned > 0 then
                table.insert(genStatusParts, ns.COLORS.ORANGE .. counts.unassigned .. " need chars|r")
            end
            table.insert(genStatusParts, "Import deals to rebuild")
        else
            table.insert(genStatusParts, pending .. " deals")
            table.insert(genStatusParts, "Import deals to auto-generate")
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

    -- ========================================
    -- CROSS-REALM TRACK: STEP 1 -- Import Deals
    -- ========================================

    if wizTrack == "crossrealm" and wizStep == 1 then
        local cr1 = gf.crStepContainers[1]

        -- Show preview table if we have data
        if cr1._previewData then
            cr1.previewTable.headerFrame:Show()
            cr1.previewTable.scrollFrame:Show()
        end

        cr1.editBox:SetFocus(true)

        local crCount = ns:ImportGetCount("fpCrossRealm")
        mainFrame.statusText:SetText("Step 1 of 3: Paste cross-realm flip data  |  " .. crCount .. " cross-realm deals imported")
        return
    end

    -- ========================================
    -- CROSS-REALM TRACK: STEP 2 -- Filter Deals
    -- ========================================

    if wizTrack == "crossrealm" and wizStep == 2 then
        local cr2 = gf.crStepContainers[2]

        -- Initialize session filter state
        if not UI._crTSMEnabled then UI._crTSMEnabled = false end
        if not UI._crTSMGroupPath then UI._crTSMGroupPath = "" end
        if not UI._crAuctEnabled then UI._crAuctEnabled = false end
        if not UI._crAuctListName then UI._crAuctListName = "" end
        if not UI._crRealmEnabled then
            -- Restore from DB settings
            UI._crRealmEnabled = ns.db.settings.genCrossRealmRealmFilter and true or false
        end
        if not UI._crRealmFilter then
            -- Initialize realm filter from saved settings or build fresh
            UI._crRealmFilter = {}
            local saved = ns.db.settings.genCrossRealmRealmFilter
            local knownRealms = ns.TodoList and ns.TodoList:GetKnownRealms() or {}
            for _, realm in ipairs(knownRealms) do
                if saved and saved[realm] ~= nil then
                    UI._crRealmFilter[realm] = saved[realm]
                else
                    UI._crRealmFilter[realm] = true
                end
            end
        end

        -- Collect all cross-realm deals
        local allDeals = {}
        for _, deal in pairs(ns.db.imports.fpCrossRealm or {}) do
            table.insert(allDeals, deal)
        end
        local totalDeals = #allDeals

        -- Build filter function
        local function DealPassesFilter(deal)
            -- TSM Group Filter
            if cr2.tsmCheck:GetChecked() and UI._crTSMGroupPath ~= "" then
                local matched = false
                if ns.TSM and ns.TSM:IsEnabled() then
                    local profile = ns.TSM:GetSelectedProfile()
                    if profile then
                        local itemsDB = ns.TSM:GetItemsDB(profile)
                        if itemsDB then
                            local tsmStr = ns.TSM:ItemKeyToTSMString(deal.itemKey)
                            local baseID = deal.itemKey and deal.itemKey:match("^(%d+)")
                            local baseStr = baseID and ("i:" .. baseID)
                            local groupPath = (tsmStr and itemsDB[tsmStr])
                                or (baseStr and itemsDB[baseStr])
                            if groupPath then
                                if groupPath == UI._crTSMGroupPath
                                    or groupPath:find(UI._crTSMGroupPath .. "`", 1, true) == 1 then
                                    matched = true
                                end
                            end
                        end
                    end
                end
                if not matched then return false end
            end

            -- Auctionator List Filter
            if cr2.auctCheck:GetChecked() and UI._crAuctListName ~= "" then
                local matched = false
                local listItems = {}

                if type(AUCTIONATOR_SHOPPING_LISTS) == "table" then
                    for _, list in ipairs(AUCTIONATOR_SHOPPING_LISTS) do
                        if type(list) == "table" and list.name == UI._crAuctListName and list.items then
                            for _, searchTerm in ipairs(list.items) do
                                local name = searchTerm:match('^"([^"]+)"') or searchTerm:match("^([^;]+)")
                                if name then listItems[strtrim(name):lower()] = true end
                            end
                            break
                        end
                    end
                end

                if not next(listItems) and type(Auctionator) == "table"
                    and Auctionator.API and Auctionator.API.v1
                    and Auctionator.API.v1.GetShoppingListItems then
                    local ok, items = pcall(Auctionator.API.v1.GetShoppingListItems, "FlipQueue", UI._crAuctListName)
                    if ok and items then
                        for _, searchTerm in ipairs(items) do
                            local name = searchTerm:match('^"([^"]+)"') or searchTerm:match("^([^;]+)")
                            if name then listItems[strtrim(name):lower()] = true end
                        end
                    end
                end

                if next(listItems) then
                    local dealName = (deal.name or ""):lower()
                    if not listItems[dealName] then return false end
                end
            end

            -- Realm Filter: only pass deals where the SELL realm has a character.
            -- Don't match on buyRealm alone — that causes "create char" tasks for the sell realm.
            if cr2.realmCheck:GetChecked() and UI._crRealmFilter and next(UI._crRealmFilter) then
                local matched = false
                for realm, enabled in pairs(UI._crRealmFilter) do
                    if enabled then
                        if ns:RealmMatches(deal.targetRealm, realm) then
                            matched = true
                            break
                        end
                    end
                end
                if not matched then return false end
            end

            return true
        end

        local matchCount = 0
        for _, deal in ipairs(allDeals) do
            if DealPassesFilter(deal) then
                matchCount = matchCount + 1
            end
        end

        -- Store filter function for step 3
        UI._crDealFilter = DealPassesFilter

        -- Layout filter sections
        local filterY = -18

        -- Section A: TSM Group Filter
        cr2.tsmHeader:ClearAllPoints()
        cr2.tsmHeader:SetPoint("TOPLEFT", cr2, "TOPLEFT", 4, filterY)
        cr2.tsmHeader:SetPoint("RIGHT", cr2, "RIGHT", -4, 0)
        cr2.tsmHeader.text:SetText("TSM Group Filter")
        cr2.tsmHeader.toggle:SetText(cr2._tsmExpanded and "|cffffffff\226\150\188|r" or "|cffffffff\226\150\182|r")
        filterY = filterY - 22

        if cr2._tsmExpanded then
            cr2.tsmCheck:ClearAllPoints()
            cr2.tsmCheck:SetPoint("TOPLEFT", cr2, "TOPLEFT", 8, filterY)
            cr2.tsmCheck:Show()
            cr2.tsmCheckLabel:ClearAllPoints()
            cr2.tsmCheckLabel:SetPoint("LEFT", cr2.tsmCheck, "RIGHT", 2, 0)
            cr2.tsmCheckLabel:Show()
            filterY = filterY - 22

            if cr2.tsmCheck:GetChecked() then
                local tsmAvail = ns.TSM and ns.TSM:IsEnabled()
                if tsmAvail and cr2.tsmGroupTree then
                    cr2.tsmBody:ClearAllPoints()
                    cr2.tsmBody:SetPoint("TOPLEFT", cr2, "TOPLEFT", 4, filterY)
                    cr2.tsmBody:SetPoint("RIGHT", cr2, "RIGHT", -4, 0)
                    cr2.tsmBody:SetHeight(100)
                    cr2.tsmBody:Show()

                    cr2.tsmTreeFrame:ClearAllPoints()
                    cr2.tsmTreeFrame:SetPoint("TOPLEFT", cr2.tsmBody, "TOPLEFT", 0, 0)
                    cr2.tsmTreeFrame:SetPoint("RIGHT", cr2.tsmBody, "RIGHT", 0, 0)
                    cr2.tsmTreeFrame:SetHeight(100)
                    cr2.tsmTreeFrame:Show()

                    local profile = ns.TSM:GetSelectedProfile()
                    if profile and cr2.tsmGroupTree._profile ~= profile then
                        cr2.tsmGroupTree:SetProfile(profile)
                    end

                    cr2.tsmUnavail:Hide()
                    filterY = filterY - 104
                else
                    cr2.tsmBody:ClearAllPoints()
                    cr2.tsmBody:SetPoint("TOPLEFT", cr2, "TOPLEFT", 8, filterY)
                    cr2.tsmBody:SetPoint("RIGHT", cr2, "RIGHT", -8, 0)
                    cr2.tsmBody:SetHeight(18)
                    cr2.tsmBody:Show()

                    cr2.tsmTreeFrame:Hide()
                    cr2.tsmUnavail:ClearAllPoints()
                    cr2.tsmUnavail:SetPoint("TOPLEFT", cr2.tsmBody, "TOPLEFT", 0, 0)
                    cr2.tsmUnavail:Show()
                    filterY = filterY - 22
                end
            else
                cr2.tsmBody:Hide()
                cr2.tsmCheck:Show()
                cr2.tsmCheckLabel:Show()
            end
        else
            cr2.tsmCheck:Hide()
            cr2.tsmCheckLabel:Hide()
            cr2.tsmBody:Hide()
        end

        filterY = filterY - 4

        -- Section B: Auctionator List Filter
        cr2.auctHeader:ClearAllPoints()
        cr2.auctHeader:SetPoint("TOPLEFT", cr2, "TOPLEFT", 4, filterY)
        cr2.auctHeader:SetPoint("RIGHT", cr2, "RIGHT", -4, 0)
        cr2.auctHeader.text:SetText("Auctionator List Filter")
        cr2.auctHeader.toggle:SetText(cr2._auctExpanded and "|cffffffff\226\150\188|r" or "|cffffffff\226\150\182|r")
        filterY = filterY - 22

        if cr2._auctExpanded then
            cr2.auctCheck:ClearAllPoints()
            cr2.auctCheck:SetPoint("TOPLEFT", cr2, "TOPLEFT", 8, filterY)
            cr2.auctCheck:Show()
            cr2.auctCheckLabel:ClearAllPoints()
            cr2.auctCheckLabel:SetPoint("LEFT", cr2.auctCheck, "RIGHT", 2, 0)
            cr2.auctCheckLabel:Show()
            filterY = filterY - 22

            if cr2.auctCheck:GetChecked() then
                local listNames = ns:GetAuctionatorListNames()
                local auctAvailable = #listNames > 0 or type(AUCTIONATOR_SHOPPING_LISTS) == "table"

                if auctAvailable and #listNames > 0 then
                    cr2.auctBody:ClearAllPoints()
                    cr2.auctBody:SetPoint("TOPLEFT", cr2, "TOPLEFT", 4, filterY)
                    cr2.auctBody:SetPoint("RIGHT", cr2, "RIGHT", -4, 0)
                    local listHeight = math.min(80, math.max(20, #listNames * 18 + 4))
                    cr2.auctBody:SetHeight(listHeight)
                    cr2.auctBody:Show()

                    cr2.auctScroll:ClearAllPoints()
                    cr2.auctScroll:SetPoint("TOPLEFT", cr2.auctBody, "TOPLEFT", 0, 0)
                    cr2.auctScroll:SetPoint("BOTTOMRIGHT", cr2.auctBody, "BOTTOMRIGHT", -16, 0)
                    cr2.auctContent:SetWidth(cr2.auctScroll:GetWidth() or 150)

                    for _, row in ipairs(cr2.auctRows) do row:Hide() end

                    local auctY = 0
                    for idx, listName in ipairs(listNames) do
                        local row = cr2.auctRows[idx]
                        if not row then
                            row = CreateFrame("Button", nil, cr2.auctContent)
                            row:SetHeight(18)
                            row.bg = row:CreateTexture(nil, "BACKGROUND")
                            row.bg:SetAllPoints()
                            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
                            row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                            row.label:SetJustifyH("LEFT")
                            row:EnableMouse(true)
                            cr2.auctRows[idx] = row
                        end
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", cr2.auctContent, "TOPLEFT", 0, -auctY)
                        row:SetPoint("RIGHT", cr2.auctContent, "RIGHT", 0, 0)

                        local isSelected = (UI._crAuctListName == listName)
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
                            UI._crAuctListName = capturedName
                            UI:Refresh()
                        end)
                        row:SetScript("OnEnter", function(self)
                            if not isSelected then self.bg:SetColorTexture(1, 1, 1, 0.05) end
                        end)
                        row:SetScript("OnLeave", function(self)
                            if not (UI._crAuctListName == capturedName) then self.bg:SetColorTexture(0, 0, 0, 0) end
                        end)

                        row:Show()
                        auctY = auctY + 18
                    end
                    cr2.auctContent:SetHeight(math.max(1, auctY))
                    cr2.auctUnavail:Hide()
                    filterY = filterY - listHeight - 4
                else
                    cr2.auctBody:ClearAllPoints()
                    cr2.auctBody:SetPoint("TOPLEFT", cr2, "TOPLEFT", 8, filterY)
                    cr2.auctBody:SetPoint("RIGHT", cr2, "RIGHT", -8, 0)
                    cr2.auctBody:SetHeight(18)
                    cr2.auctBody:Show()
                    cr2.auctScroll:Hide()
                    cr2.auctUnavail:ClearAllPoints()
                    cr2.auctUnavail:SetPoint("TOPLEFT", cr2.auctBody, "TOPLEFT", 0, 0)
                    cr2.auctUnavail:Show()
                    filterY = filterY - 22
                end
            else
                cr2.auctBody:Hide()
            end
        else
            cr2.auctCheck:Hide()
            cr2.auctCheckLabel:Hide()
            cr2.auctBody:Hide()
        end

        filterY = filterY - 4

        -- Section C: Realm Filter
        cr2.realmHeader:ClearAllPoints()
        cr2.realmHeader:SetPoint("TOPLEFT", cr2, "TOPLEFT", 4, filterY)
        cr2.realmHeader:SetPoint("RIGHT", cr2, "RIGHT", -4, 0)
        cr2.realmHeader.text:SetText("Realm Filter")
        cr2.realmHeader.toggle:SetText(cr2._realmExpanded and "|cffffffff\226\150\188|r" or "|cffffffff\226\150\182|r")
        filterY = filterY - 22

        if cr2._realmExpanded then
            cr2.realmCheck:ClearAllPoints()
            cr2.realmCheck:SetPoint("TOPLEFT", cr2, "TOPLEFT", 8, filterY)
            cr2.realmCheck:Show()
            cr2.realmCheckLabel:ClearAllPoints()
            cr2.realmCheckLabel:SetPoint("LEFT", cr2.realmCheck, "RIGHT", 2, 0)
            cr2.realmCheckLabel:Show()
            filterY = filterY - 22

            if cr2.realmCheck:GetChecked() then
                local knownRealms = ns.TodoList and ns.TodoList:GetKnownRealms() or {}

                -- Ensure all known realms are in the filter map
                for _, realm in ipairs(knownRealms) do
                    if UI._crRealmFilter[realm] == nil then
                        UI._crRealmFilter[realm] = true
                    end
                end

                cr2.realmBody:ClearAllPoints()
                cr2.realmBody:SetPoint("TOPLEFT", cr2, "TOPLEFT", 4, filterY)
                cr2.realmBody:SetPoint("RIGHT", cr2, "RIGHT", -4, 0)

                -- Buttons row
                cr2.realmSelectAll:ClearAllPoints()
                cr2.realmSelectAll:SetPoint("TOPLEFT", cr2.realmBody, "TOPLEFT", 4, 0)
                cr2.realmSelectAll:Show()
                cr2.realmDeselectAll:ClearAllPoints()
                cr2.realmDeselectAll:SetPoint("LEFT", cr2.realmSelectAll, "RIGHT", 4, 0)
                cr2.realmDeselectAll:Show()

                cr2.realmScroll:ClearAllPoints()
                cr2.realmScroll:SetPoint("TOPLEFT", cr2.realmBody, "TOPLEFT", 0, -22)
                cr2.realmScroll:SetPoint("BOTTOMRIGHT", cr2.realmBody, "BOTTOMRIGHT", -16, 0)
                cr2.realmContent:SetWidth(cr2.realmScroll:GetWidth() or 150)

                for _, row in ipairs(cr2.realmRows) do row:Hide() end

                local realmY = 0
                for idx, realm in ipairs(knownRealms) do
                    local row = cr2.realmRows[idx]
                    if not row then
                        row = CreateFrame("Button", nil, cr2.realmContent)
                        row:SetHeight(18)
                        row.check = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        row.check:SetPoint("LEFT", row, "LEFT", 4, 0)
                        row.check:SetWidth(16)
                        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
                        row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                        row.label:SetJustifyH("LEFT")
                        row.bg = row:CreateTexture(nil, "BACKGROUND")
                        row.bg:SetAllPoints()
                        row:EnableMouse(true)
                        cr2.realmRows[idx] = row
                    end
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", cr2.realmContent, "TOPLEFT", 0, -realmY)
                    row:SetPoint("RIGHT", cr2.realmContent, "RIGHT", 0, 0)

                    local enabled = UI._crRealmFilter[realm] ~= false
                    row.check:SetText(enabled and "|cff00ff00\226\156\147|r" or "|cffff0000\226\156\151|r")
                    row.label:SetText(realm)
                    row.label:SetTextColor(enabled and 0.9 or 0.4, enabled and 0.9 or 0.4, enabled and 0.9 or 0.4)
                    row.bg:SetColorTexture(0, 0, 0, 0)

                    local capturedRealm = realm
                    row:SetScript("OnClick", function()
                        UI._crRealmFilter[capturedRealm] = not (UI._crRealmFilter[capturedRealm] ~= false)
                        -- Persist to DB
                        if ns.db then
                            ns.db.settings.genCrossRealmRealmFilter = UI._crRealmFilter
                        end
                        UI:Refresh()
                    end)
                    row:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.05) end)
                    row:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0, 0, 0, 0) end)

                    row:Show()
                    realmY = realmY + 18
                end
                cr2.realmContent:SetHeight(math.max(1, realmY))

                local realmListH = math.min(100, math.max(20, #knownRealms * 18 + 4))
                cr2.realmBody:SetHeight(realmListH + 24)
                cr2.realmBody:Show()
                filterY = filterY - realmListH - 28
            else
                cr2.realmBody:Hide()
            end
        else
            cr2.realmCheck:Hide()
            cr2.realmCheckLabel:Hide()
            cr2.realmBody:Hide()
        end

        -- Count label
        cr2.countLabel:ClearAllPoints()
        cr2.countLabel:SetPoint("BOTTOMLEFT", cr2, "BOTTOMLEFT", 8, 4)
        cr2.countLabel:SetText(ns.COLORS.CYAN .. matchCount .. " deals match filters|r" ..
            ns.COLORS.GRAY .. " (of " .. totalDeals .. " total)|r")

        mainFrame.statusText:SetText("Step 2 of 3: Filter cross-realm deals  |  " ..
            matchCount .. " of " .. totalDeals .. " deals match")
        return
    end

    -- ========================================
    -- CROSS-REALM TRACK: STEP 3 -- Configure & Generate
    -- ========================================

    if wizTrack == "crossrealm" and wizStep == 3 then
        local cr3 = gf.crStepContainers[3]

        local BUY_ALLOC_META = {
            profit        = {label = "Profit",         icon = "Interface\\Icons\\INV_Misc_Coin_17",                      color = {1, 0.82, 0}},
            population    = {label = "Population",     icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", color = {0.4, 0.7, 1}},
            lowInventory  = {label = "Low Inventory",  icon = "Interface\\Icons\\INV_Misc_Bag_07",                        color = {0.2, 0.8, 0.6}},
            highInventory = {label = "High Inventory", icon = "Interface\\Icons\\INV_Misc_Bag_10_Red",                    color = {0.9, 0.6, 0.2}},
            discount      = {label = "Discount",       icon = "Interface\\Icons\\Ability_Rogue_CheapShot",                color = {0.7, 0.4, 1.0}},
        }

        local SELL_ALLOC_META = {
            gold           = {label = "Profit",        icon = "Interface\\Icons\\INV_Misc_Coin_17",                 color = {1, 0.82, 0}},
            noCompetition  = {label = "No Competition", icon = "Interface\\Icons\\Achievement_PVP_H_01",            color = {0.3, 1, 0.3}},
            population     = {label = "Population",     icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", color = {0.4, 0.7, 1}},
        }

        local LIST_ROW_H = 28

        -- Reuse the same RenderAllocList helper (defined in inventory step 3, but we define a local version here)
        -- colMode: nil=full-width, "left"=left half, "right"=right half
        local function RenderAllocListCR(orderTable, allocMeta, rowPool, parent, yStart, onChanged, colMode)
            for _, row in ipairs(rowPool) do row:Hide() end
            local y = yStart
            local ds = gf._dragState

            for idx, key in ipairs(orderTable) do
                local meta = allocMeta[key] or {label = key, color = {0.7, 0.7, 0.7}}
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
                if colMode == "left" then
                    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
                    row:SetPoint("TOPRIGHT", parent, "TOP", -4, y)
                elseif colMode == "right" then
                    row:SetPoint("TOPLEFT", parent, "TOP", 4, y)
                    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
                else
                    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
                    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
                end

                local brightness = 1 - (idx - 1) * 0.15
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

        -- Initialize settings
        if not ns.db.settings.genBuyAllocationOrder then
            ns.db.settings.genBuyAllocationOrder = {"profit", "discount", "lowInventory"}
        end
        local listMode = ns.db.settings.genCrossRealmListMode or "separate"
        local intSortMode = ns.db.settings.genIntegratedSortMode or "mostProfitable"

        local function CRAutoRegenerate()
            UI:Refresh()
        end

        -- Layout: Buy & Sell priorities side by side
        local rightY = -4

        -- Labels above each column
        cr3.buyAllocLabel:ClearAllPoints()
        cr3.buyAllocLabel:SetPoint("TOPLEFT", cr3, "TOPLEFT", 6, rightY)
        cr3.sellAllocLabel:ClearAllPoints()
        cr3.sellAllocLabel:SetPoint("LEFT", cr3, "CENTER", 6, 0)
        cr3.sellAllocLabel:SetPoint("TOP", cr3, "TOP", 0, rightY)
        rightY = rightY - 16

        -- Descriptions (shortened, under each label)
        cr3.buyAllocDesc:ClearAllPoints()
        cr3.buyAllocDesc:SetPoint("TOPLEFT", cr3, "TOPLEFT", 6, rightY)
        cr3.buyAllocDesc:SetPoint("RIGHT", cr3, "CENTER", -6, 0)
        cr3.sellAllocDesc:ClearAllPoints()
        cr3.sellAllocDesc:SetPoint("LEFT", cr3, "CENTER", 6, 0)
        cr3.sellAllocDesc:SetPoint("TOP", cr3, "TOP", 0, rightY)
        cr3.sellAllocDesc:SetPoint("RIGHT", cr3, "RIGHT", -6, 0)
        rightY = rightY - 28

        -- Lists side by side
        local buyEndY = RenderAllocListCR(ns.db.settings.genBuyAllocationOrder, BUY_ALLOC_META,
            cr3.buyAllocRows, cr3, rightY, CRAutoRegenerate, "left")
        local sellEndY = RenderAllocListCR(UI:GetGenAllocationOrder(), SELL_ALLOC_META,
            cr3.sellAllocRows, cr3, rightY, CRAutoRegenerate, "right")
        rightY = math.min(buyEndY, sellEndY) - 8

        -- List Mode Toggle
        cr3.listModeLabel:ClearAllPoints()
        cr3.listModeLabel:SetPoint("TOPLEFT", cr3, "TOPLEFT", 6, rightY)
        rightY = rightY - 16

        cr3.separateBtn:ClearAllPoints()
        cr3.separateBtn:SetPoint("TOPLEFT", cr3, "TOPLEFT", 4, rightY)
        SetToggleActive(cr3.separateBtn, listMode == "separate")
        cr3.separateBtn:Show()

        cr3.integratedBtn:ClearAllPoints()
        cr3.integratedBtn:SetPoint("LEFT", cr3.separateBtn, "RIGHT", 4, 0)
        SetToggleActive(cr3.integratedBtn, listMode == "integrated")
        cr3.integratedBtn:Show()

        rightY = rightY - 22

        -- Integrated Sort Mode (only when integrated)
        if listMode == "integrated" then
            cr3.intSortLabel:ClearAllPoints()
            cr3.intSortLabel:SetPoint("TOPLEFT", cr3, "TOPLEFT", 6, rightY)
            cr3.intSortLabel:Show()
            rightY = rightY - 16

            cr3.intSortProfitBtn:ClearAllPoints()
            cr3.intSortProfitBtn:SetPoint("TOPLEFT", cr3, "TOPLEFT", 4, rightY)
            SetToggleActive(cr3.intSortProfitBtn, intSortMode == "mostProfitable")
            cr3.intSortProfitBtn:Show()

            cr3.intSortDealBtn:ClearAllPoints()
            cr3.intSortDealBtn:SetPoint("LEFT", cr3.intSortProfitBtn, "RIGHT", 4, 0)
            SetToggleActive(cr3.intSortDealBtn, intSortMode == "bestDeal")
            cr3.intSortDealBtn:Show()

            cr3.intSortBuysBtn:ClearAllPoints()
            cr3.intSortBuysBtn:SetPoint("LEFT", cr3.intSortDealBtn, "RIGHT", 4, 0)
            SetToggleActive(cr3.intSortBuysBtn, intSortMode == "prioritizeBuys")
            cr3.intSortBuysBtn:Show()

            rightY = rightY - 22
        else
            cr3.intSortLabel:Hide()
            cr3.intSortProfitBtn:Hide()
            cr3.intSortDealBtn:Hide()
            cr3.intSortBuysBtn:Hide()
        end

        cr3.generateBtn:Hide()

        -- Auto-generate on every config change (always keep preview up-to-date)
        do

            local sellAllocOrder = UI:GetGenAllocationOrder()
            local buyAllocOrder = ns.db.settings.genBuyAllocationOrder or {"profit", "discount", "lowInventory"}

            -- Build filter function from step 2 state
            local dealFilter = UI._crDealFilter
            if not dealFilter then
                dealFilter = function() return true end
            end

            local opts = {
                buyAllocationOrder = buyAllocOrder,
                listMode = listMode,
                integratedSortMode = intSortMode,
                dealFilter = dealFilter,
            }

            UI._generatorPreview = ns.TodoList:GenerateTodoList("fpCrossRealm", sellAllocOrder, opts)
        end

        -- Status label
        cr3.statusLabel:ClearAllPoints()
        cr3.statusLabel:SetPoint("TOPLEFT", cr3, "TOPLEFT", 6, rightY)

        local previewSource = UI._generatorPreview
        local isSeparate = listMode == "separate" and previewSource and previewSource.buy

        if isSeparate then
            local buyItems = previewSource.buy and previewSource.buy.items or {}
            local sellItems = previewSource.sell and previewSource.sell.items or {}
            cr3.statusLabel:SetText(
                ns.COLORS.CYAN .. #buyItems .. " buy tasks|r" ..
                ns.COLORS.GRAY .. "  +  " .. "|r" ..
                ns.COLORS.YELLOW .. #sellItems .. " sell tasks|r")
        elseif previewSource and previewSource.items then
            local taskCount = #previewSource.items
            cr3.statusLabel:SetText(ns.COLORS.GRAY .. taskCount .. " tasks generated|r")
        else
            cr3.statusLabel:SetText(ns.COLORS.GRAY .. "Import deals to generate a preview|r")
        end
        rightY = rightY - 14

        -- Separate-mode name inputs (side by side above columns)
        if isSeparate then
            cr3.buyNameLabel:ClearAllPoints()
            cr3.buyNameLabel:SetPoint("TOPLEFT", cr3, "TOPLEFT", 6, rightY)
            cr3.buyNameLabel:Show()
            cr3.buyNameBox:ClearAllPoints()
            cr3.buyNameBox:SetPoint("LEFT", cr3.buyNameLabel, "RIGHT", 4, 0)
            cr3.buyNameBox:SetPoint("RIGHT", cr3, "CENTER", -6, 0)
            cr3.buyNameBox:Show()
            if not cr3.buyNameBox._initialized then
                cr3.buyNameBox:SetText("Buy " .. date("%m-%d"))
                cr3.buyNameBox._initialized = true
            end

            cr3.sellNameLabel:ClearAllPoints()
            cr3.sellNameLabel:SetPoint("LEFT", cr3, "CENTER", 6, 0)
            cr3.sellNameLabel:SetPoint("TOP", cr3, "TOP", 0, rightY)
            cr3.sellNameLabel:Show()
            cr3.sellNameBox:ClearAllPoints()
            cr3.sellNameBox:SetPoint("LEFT", cr3.sellNameLabel, "RIGHT", 4, 0)
            cr3.sellNameBox:SetPoint("RIGHT", cr3, "RIGHT", -6, 0)
            cr3.sellNameBox:Show()
            if not cr3.sellNameBox._initialized then
                cr3.sellNameBox:SetText("Sell " .. date("%m-%d"))
                cr3.sellNameBox._initialized = true
            end
            rightY = rightY - 22
        else
            cr3.buyNameLabel:Hide()
            cr3.buyNameBox:Hide()
            cr3.sellNameLabel:Hide()
            cr3.sellNameBox:Hide()
        end

        -- Divider
        cr3.listDivider:ClearAllPoints()
        cr3.listDivider:SetPoint("TOPLEFT", cr3, "TOPLEFT", 6, rightY + 2)
        cr3.listDivider:SetPoint("RIGHT", cr3, "RIGHT", -6, 0)
        rightY = rightY - 4

        -- Generated items scroll area
        cr3.genScroll:ClearAllPoints()
        cr3.genScroll:SetPoint("TOPLEFT", cr3, "TOPLEFT", 0, rightY)
        cr3.genScroll:SetPoint("BOTTOMRIGHT", cr3, "BOTTOMRIGHT", -22, 0)

        local genScrollWidth = cr3.genScroll:GetWidth()
        cr3.genContent:SetWidth(genScrollWidth and genScrollWidth > 0 and genScrollWidth or 200)

        -- Render preview groups
        for _, row in ipairs(cr3.genRows) do row:Hide() end

        local LookupItemInfo = UI._LookupItemInfo
        local QualityColorName = UI._QualityColorName
        local GEN_ROW_H = 18
        local HDR_ROW_H = 22
        local genRowIdx = 0

        -- colMode: nil=full-width, "left"=left half, "right"=right half
        local function GetOrCreateCRGenRow(height, yPos, colMode)
            genRowIdx = genRowIdx + 1
            local row = cr3.genRows[genRowIdx]
            if not row then
                row = CreateFrame("Button", nil, cr3.genContent)
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
                cr3.genRows[genRowIdx] = row
            end
            row:SetHeight(height)
            row:ClearAllPoints()
            if colMode == "left" then
                row:SetPoint("TOPLEFT", cr3.genContent, "TOPLEFT", 0, -yPos)
                row:SetPoint("TOPRIGHT", cr3.genContent, "TOP", -4, -yPos)
            elseif colMode == "right" then
                row:SetPoint("TOPLEFT", cr3.genContent, "TOP", 4, -yPos)
                row:SetPoint("TOPRIGHT", cr3.genContent, "TOPRIGHT", 0, -yPos)
            else
                row:SetPoint("TOPLEFT", cr3.genContent, "TOPLEFT", 0, -yPos)
                row:SetPoint("TOPRIGHT", cr3.genContent, "TOPRIGHT", 0, -yPos)
            end
            row.icon:Hide()
            row.nameText:SetText("")
            row.rightText:SetText("")
            row:SetScript("OnClick", nil)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row:Show()
            return row
        end

        -- Returns the ending Y position after rendering
        local function RenderGroupedPreview(items, sortMode, sectionLabel, colMode, startY)
            if not items or #items == 0 then return startY or 0 end
            local y = startY or 0

            local displayGroups, missingCount = ns.TodoList:BuildDisplayGroups(items, sortMode or "profit")

            -- Section header
            if sectionLabel then
                local shdr = GetOrCreateCRGenRow(HDR_ROW_H, y, colMode)
                shdr.bg:SetColorTexture(0.08, 0.12, 0.18, 0.9)
                shdr.nameText:ClearAllPoints()
                shdr.nameText:SetPoint("LEFT", shdr, "LEFT", 6, 0)
                shdr.nameText:SetPoint("RIGHT", shdr.rightText, "LEFT", -4, 0)
                shdr.nameText:SetText(sectionLabel)
                y = y + HDR_ROW_H
            end

            for gi, group in ipairs(displayGroups) do
                local isUnassigned = not group.charKey

                local hdr = GetOrCreateCRGenRow(HDR_ROW_H, y, colMode)

                if isUnassigned then
                    hdr.bg:SetColorTexture(0.15, 0.08, 0.08, 0.7)
                    local realmName = group.realm ~= "" and group.realm or "unknown realm"
                    hdr.nameText:SetText(
                        ns.COLORS.RED .. "Create character on " .. realmName .. "|r" ..
                        ns.COLORS.GRAY .. "  (" .. #group.items .. " items)|r")
                else
                    hdr.bg:SetColorTexture(0.12, 0.15, 0.2, 0.8)
                    local charData = ns.db.characters and ns.db.characters[group.charKey]
                    local cc = charData and (UI._CLASS_COLORS or {})[charData.class] or "888888"
                    local charDisplay = "|cff" .. cc .. group.charName .. "|r"
                    local realmDisplay = group.realm ~= "" and (ns.COLORS.GRAY .. " - " .. group.realm .. "|r") or ""
                    local buyTag = group.hasBuyTasks and (ns.COLORS.CYAN .. " [Buy]|r") or ""
                    hdr.nameText:SetText(charDisplay .. realmDisplay .. buyTag ..
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

                y = y + HDR_ROW_H

                -- Item rows
                for ii, item in ipairs(group.items) do
                    local row = GetOrCreateCRGenRow(GEN_ROW_H, y, colMode)
                    if isUnassigned then
                        row.bg:SetColorTexture(0.1, 0.06, 0.06, 0.4)
                    elseif item.action == "buy" then
                        row.bg:SetColorTexture(0.06, 0.1, 0.14, 0.6)
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
                        displayName = ns.COLORS.GRAY .. displayName .. "|r"
                    elseif quality and QualityColorName then
                        displayName = QualityColorName(displayName, quality)
                    elseif item.quality and item.quality ~= "" and QualityColorName then
                        displayName = QualityColorName(displayName, item.quality)
                    end

                    local actionTag = ""
                    if item.action == "buy" then
                        actionTag = ns.COLORS.CYAN .. "[B] " .. "|r"
                    end
                    local qtyStr = (item.quantity or 1) > 1 and (" x" .. (item.quantity or 1)) or ""
                    row.nameText:SetText(actionTag .. displayName .. qtyStr)

                    if itemIcon and isUnassigned then
                        row.icon:SetDesaturated(true)
                        row.icon:SetAlpha(0.5)
                    elseif itemIcon then
                        row.icon:SetDesaturated(false)
                        row.icon:SetAlpha(1)
                    end

                    local priceStr = item.expectedPrice or ""
                    if item.action == "buy" and item.buyPrice then
                        priceStr = ns.COLORS.CYAN .. item.buyPrice .. "|r"
                    elseif isUnassigned then
                        priceStr = ns.COLORS.GRAY .. priceStr .. "|r"
                    end
                    row.rightText:SetText(priceStr)

                    local restoreBg
                    if isUnassigned then
                        restoreBg = {0.1, 0.06, 0.06, 0.4}
                    elseif item.action == "buy" then
                        restoreBg = {0.06, 0.1, 0.14, 0.6}
                    else
                        restoreBg = {ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.12 or 0.1, 0.6}
                    end

                    local capturedItem = item
                    local capturedID = resolvedID or tonumber(item.itemID)
                    local capturedItemKey = item.itemKey
                    row:SetScript("OnEnter", function(self)
                        self.bg:SetColorTexture(1, 1, 1, 0.08)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        if not ns:SetTooltipItem(GameTooltip, capturedItemKey, capturedID) then
                            GameTooltip:SetText(capturedItem.name or "?", 1, 1, 1)
                        end
                        if capturedItem.action == "buy" then
                            GameTooltip:AddLine("Buy on: " .. (capturedItem.buyRealm or "?"), 0.4, 0.8, 0.9)
                            GameTooltip:AddLine("Buy price: " .. (capturedItem.buyPrice or "?"), 0.4, 0.8, 0.9)
                            GameTooltip:AddLine("Sell on: " .. (capturedItem.targetRealm or "?"), 0.7, 0.7, 0.7)
                        else
                            if capturedItem.targetRealm and capturedItem.targetRealm ~= "" then
                                GameTooltip:AddLine("Sell on: " .. capturedItem.targetRealm, 0.7, 0.7, 0.7)
                            end
                        end
                        if capturedItem.expectedPrice then
                            GameTooltip:AddLine("Sell price: " .. capturedItem.expectedPrice, 0.7, 0.7, 0.7)
                        end
                        if capturedItem.profitAmount then
                            GameTooltip:AddLine("Profit: " .. capturedItem.profitAmount ..
                                (capturedItem.profitPct and (" (" .. capturedItem.profitPct .. "%)") or ""), 0.3, 1, 0.3)
                        end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function(self)
                        self.bg:SetColorTexture(unpack(restoreBg))
                        GameTooltip:Hide()
                    end)

                    y = y + GEN_ROW_H
                end

                y = y + 2
            end
            return y
        end

        -- Render based on mode
        local genY = 0
        if isSeparate then
            local buyItems = previewSource.buy and previewSource.buy.items or {}
            local sellItems = previewSource.sell and previewSource.sell.items or {}
            local buyEndY = RenderGroupedPreview(buyItems, "profit",
                ns.COLORS.CYAN .. "BUY LIST|r" .. ns.COLORS.GRAY .. "  (" .. #buyItems .. " tasks)|r",
                "left", 0)
            local sellEndY = RenderGroupedPreview(sellItems, UI:GetGenSortMode(),
                ns.COLORS.YELLOW .. "SELL LIST|r" .. ns.COLORS.GRAY .. "  (" .. #sellItems .. " tasks)|r",
                "right", 0)
            genY = math.max(buyEndY, sellEndY)
        elseif previewSource and previewSource.items then
            local sortMode = intSortMode or "profit"
            local displaySortMode = sortMode
            genY = RenderGroupedPreview(previewSource.items, displaySortMode, nil, nil, 0)
        end

        cr3.genContent:SetHeight(math.max(1, genY))

        -- Save button logic (cross-realm track)
        if UI._generatorPreview then
            gf.saveBtn:Show()
            if isSeparate then
                -- Separate mode: use per-column name boxes, hide shared one
                gf.nameLabel:Hide()
                gf.nameBox:Hide()
            else
                -- Integrated mode: use shared name box
                gf.nameLabel:Show()
                gf.nameBox:Show()
            end
            gf.saveBtn:SetScript("OnClick", function()
                if isSeparate and previewSource.buy and previewSource.sell then
                    -- Read names from per-column boxes
                    local buyName = cr3.buyNameBox:GetText():match("^%s*(.-)%s*$")
                    if not buyName or buyName == "" then buyName = "Buy " .. date("%m-%d %H:%M") end
                    local sellName = cr3.sellNameBox:GetText():match("^%s*(.-)%s*$")
                    if not sellName or sellName == "" then sellName = "Sell " .. date("%m-%d %H:%M") end

                    local currentList2 = ns.TodoList:GetCurrentList()
                    local buyCount = previewSource.buy.items and #previewSource.buy.items or 0
                    local sellCount = previewSource.sell.items and #previewSource.sell.items or 0

                    if buyCount > 0 then
                        previewSource.buy.name = buyName
                        ns.TodoList:CommitList(previewSource.buy, currentList2 and "upcoming" or "replace")
                    end
                    if sellCount > 0 then
                        previewSource.sell.name = sellName
                        ns.TodoList:CommitList(previewSource.sell, "upcoming")
                    end

                    ns:Print(ns.COLORS.GREEN .. "Saved \"" .. buyName .. "\" (" ..
                        buyCount .. " buy) + \"" .. sellName .. "\" (" .. sellCount .. " sell)|r")
                elseif previewSource and previewSource.items then
                    local listName = gf.nameBox:GetText():match("^%s*(.-)%s*$")
                    if not listName or listName == "" then
                        listName = "Generated " .. date("%Y-%m-%d %H:%M")
                    end
                    local count = #previewSource.items
                    previewSource.name = listName
                    local currentList2 = ns.TodoList:GetCurrentList()
                    if currentList2 then
                        ns.TodoList:CommitList(previewSource, "upcoming")
                        ns:Print(ns.COLORS.GREEN .. "Queued \"" .. listName .. "\" with " .. count .. " tasks.|r")
                    else
                        ns.TodoList:CommitList(previewSource, "replace")
                        ns:Print(ns.COLORS.GREEN .. "Saved \"" .. listName .. "\" with " .. count .. " tasks.|r")
                    end
                end

                UI._generatorPreview = nil
                gf.nameBox._initialized = false
                cr3.buyNameBox._initialized = false
                cr3.sellNameBox._initialized = false
                SaveWizardState(nil, 0)
                UI:Refresh()
                if UI.RefreshMini then UI:RefreshMini() end
            end)
        end

        -- Status bar
        local genStatusParts = {}
        if UI._generatorPreview then
            if isSeparate then
                local buyCount = previewSource.buy and previewSource.buy.items and #previewSource.buy.items or 0
                local sellCount = previewSource.sell and previewSource.sell.items and #previewSource.sell.items or 0
                table.insert(genStatusParts, buyCount .. " buy + " .. sellCount .. " sell tasks")
            else
                local pvItems = UI._generatorPreview.items or {}
                table.insert(genStatusParts, #pvItems .. " tasks")
            end
            table.insert(genStatusParts, "Enter a name and click Save")
        else
            local crCount = ns:ImportGetCount("fpCrossRealm")
            table.insert(genStatusParts, crCount .. " cross-realm deals")
            table.insert(genStatusParts, "Adjusting settings will auto-generate")
        end

        mainFrame.statusText:SetText("Step 3 of 3  |  " .. table.concat(genStatusParts, "  |  "))
        return
    end

    -- Fallback
    mainFrame.statusText:SetText(pending .. " deals  |  To-Do Generator")
end

-- Register layout callback for container resize.
-- The generator frame uses SetAllPoints + internal OnSizeChanged handlers,
-- so we only need to sync scroll child widths that might not have fired yet.
UI:RegisterPageLayout("generator", function()
    local gf = UI._genFrame
    if not gf or not gf:IsShown() then return end
    -- poolScroll, genScroll, etc. have their own OnSizeChanged handlers.
    -- Force a sync on poolContent/genContent widths (defensive).
    local stepPool = UI._wizardTrack == "crossrealm" and gf.crStepContainers or gf.stepContainers
    local sc = stepPool and stepPool[UI._wizardStep or 0]
    if sc then
        if sc.poolScroll and sc.poolContent then
            sc.poolContent:SetWidth(sc.poolScroll:GetWidth())
        end
        if sc.genScroll and sc.genContent then
            sc.genContent:SetWidth(sc.genScroll:GetWidth())
        end
        if sc.editScroll and sc.editBox then
            sc.editBox:SetWidth(sc.editScroll:GetWidth())
        end
    end
end)
