-- UI/SettingsFrame.lua
-- Settings page rendered inside the main window content area
local addonName, ns = ...

local UI = ns.UI

local settingsPanel
local settingsWidgets = {}

-- Layout constants
local LEFT_MARGIN = 12
local RIGHT_MARGIN = -12
local SECTION_SPACING = 14
local ITEM_SPACING = 6
local DESC_COLOR = {0.6, 0.6, 0.6}

--------------------------
-- Collapsible Section Header
--------------------------

local sectionContainers = {}  -- sectionKey -> { container, header, content, collapsed, contentHeight }

local function CreateCollapsibleSection(parent, yOffset, sectionKey, title, summary)
    -- Container holds header + content
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    container:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    -- Divider line
    local divider = container:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", container, "TOPLEFT", LEFT_MARGIN, 0)
    divider:SetPoint("RIGHT", container, "RIGHT", RIGHT_MARGIN, 0)
    divider:SetColorTexture(0.35, 0.35, 0.45, 0.6)

    -- Header row (clickable)
    local headerBtn = CreateFrame("Button", nil, container)
    headerBtn:SetHeight(22)
    headerBtn:SetPoint("TOPLEFT", container, "TOPLEFT", LEFT_MARGIN, -4)
    headerBtn:SetPoint("RIGHT", container, "RIGHT", RIGHT_MARGIN, 0)

    local arrow = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetPoint("LEFT", headerBtn, "LEFT", 0, 0)
    arrow:SetTextColor(0.7, 0.7, 0.7)

    local label = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    label:SetTextColor(0.9, 0.8, 0.3)
    label:SetText(title)

    local summaryText = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    summaryText:SetPoint("LEFT", label, "RIGHT", 8, 0)
    summaryText:SetPoint("RIGHT", headerBtn, "RIGHT", 0, 0)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetTextColor(0.5, 0.5, 0.5)
    summaryText:SetText(summary or "")

    -- Highlight on hover
    local hl = headerBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.2, 0.2, 0.3, 0.2)

    -- Content container (holds all settings in this section)
    local sectionContent = CreateFrame("Frame", nil, container)
    sectionContent:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -26)
    sectionContent:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    -- Default to collapsed; user uncollapsing sets collapsed[key] = false explicitly
    local collapsed = not ns.db or ns.db.settings.collapsed[sectionKey] == nil or ns.db.settings.collapsed[sectionKey]

    local section = {
        container = container,
        headerBtn = headerBtn,
        arrow = arrow,
        summaryText = summaryText,
        content = sectionContent,
        collapsed = collapsed,
        contentHeight = 0,
        sectionKey = sectionKey,
    }

    local function UpdateLayout()
        if section.collapsed then
            arrow:SetText("+")
            sectionContent:Hide()
            summaryText:Show()
            container:SetHeight(28)
        else
            arrow:SetText("-")
            sectionContent:Show()
            summaryText:Hide()
            container:SetHeight(26 + section.contentHeight)
        end
    end

    headerBtn:SetScript("OnClick", function()
        section.collapsed = not section.collapsed
        if ns.db then ns.db.settings.collapsed[sectionKey] = section.collapsed end
        UpdateLayout()
        -- Reflow all sections below
        if UI.ReflowSettings then UI:ReflowSettings() end
    end)

    section.UpdateLayout = UpdateLayout
    UpdateLayout()

    sectionContainers[sectionKey] = section
    return section
end

--------------------------
-- Checkbox with inline description
--------------------------

local function CreateSettingsCheckbox(parent, yOffset, title, desc, settingKey)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)

    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

    -- Title text (beside checkbox)
    cb.text:SetText(title)
    cb.text:SetFontObject("GameFontHighlightSmall")

    -- Description text (below, indented to align with title)
    local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    descText:SetPoint("TOPLEFT", cb.text, "BOTTOMLEFT", 0, -1)
    descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    descText:SetText(desc)
    descText:SetSpacing(1)

    cb:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.settings[settingKey] = self:GetChecked()
        end
    end)

    cb.settingKey = settingKey
    cb.descText = descText

    -- Calculate row height dynamically based on description text
    row:SetScript("OnShow", function(self)
        local descH = descText:GetStringHeight() or 12
        self:SetHeight(22 + descH + 4)
    end)

    -- Initial height estimate
    row:SetHeight(38)

    return cb, 42 -- return widget + estimated height consumed
end

--------------------------
-- Button with inline description
--------------------------

local function CreateSettingsButton(parent, yOffset, label, desc, width, onClick)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)

    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
    btn:SetSize(width, 24)
    btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
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

    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.35, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
    end)

    local totalHeight = 28

    -- Optional description beside button
    if desc and desc ~= "" then
        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText(desc)
    end

    row:SetHeight(totalHeight)
    return btn, totalHeight
end

local function CreateSettingsDropdown(parent, yOffset, title, desc, settingKey, options, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(title)

    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
    btn:SetSize(160, 22)
    btn:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("LEFT", btn, "LEFT", 6, 0)

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetText("v")

    if desc and desc ~= "" then
        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText(desc)
    end

    -- Menu frame
    local menu = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(160)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    menu:SetBackdropColor(0.1, 0.1, 0.15, 0.98)
    menu:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)
    menu:Hide()

    local menuBtns = {}
    for i, opt in ipairs(options) do
        local mb = CreateFrame("Button", nil, menu)
        mb:SetHeight(20)
        mb:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 20)
        mb:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
        mb.text = mb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mb.text:SetPoint("LEFT", mb, "LEFT", 4, 0)
        mb.text:SetText(opt.label)
        local hl = mb:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.3, 0.3, 0.5, 0.3)
        mb:SetScript("OnClick", function()
            if ns.db then ns.db.settings[settingKey] = opt.value end
            btn.text:SetText(opt.label)
            menu:Hide()
            if onChange then onChange(opt.value) end
        end)
        menuBtns[i] = mb
    end
    menu:SetHeight(8 + #options * 20)

    btn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide() else menu:Show() end
    end)
    menu:SetScript("OnLeave", function(self)
        C_Timer.After(0.2, function()
            if not self:IsMouseOver() and not btn:IsMouseOver() then
                self:Hide()
            end
        end)
    end)

    function btn:SetValue(value)
        for _, opt in ipairs(options) do
            if opt.value == value then
                btn.text:SetText(opt.label)
                return
            end
        end
        btn.text:SetText(value or "?")
    end

    local totalHeight = 40
    row:SetHeight(totalHeight)
    return btn, totalHeight
end

--------------------------
-- Main Panel
--------------------------

-- Section ordering for reflow
local sectionOrder = { "automation", "bankops", "notifications", "miniview", "data", "multiaccount" }

function UI:ReflowSettings()
    if not settingsWidgets.contentFrame then return end
    local y = -6
    for _, key in ipairs(sectionOrder) do
        local section = sectionContainers[key]
        if section then
            section.container:ClearAllPoints()
            section.container:SetPoint("TOPLEFT", settingsWidgets.contentFrame, "TOPLEFT", 0, y)
            section.container:SetPoint("RIGHT", settingsWidgets.contentFrame, "RIGHT", 0, 0)
            section.UpdateLayout()
            if section.collapsed then
                y = y - 28 - SECTION_SPACING
            else
                y = y - (26 + section.contentHeight) - SECTION_SPACING
            end
        end
    end
    settingsWidgets.contentFrame:SetHeight(math.abs(y) + 40)
end

function UI:CreateSettingsPanel(parent)
    if settingsPanel then return settingsPanel end

    -- Scrollable settings container
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(scroll:GetWidth())
    content:SetHeight(1200)
    scroll:SetScrollChild(content)
    settingsWidgets.contentFrame = content

    scroll:SetScript("OnSizeChanged", function(sf, w)
        content:SetWidth(w)
    end)

    local y = -6
    local h

    ------------------------------------------------
    -- Section: Scanning & Automation
    ------------------------------------------------
    local secAuto = CreateCollapsibleSection(content, y, "automation",
        "General",
        "Scanning, deal lists, posting quantities, alerts")
    local sc = secAuto.content  -- widgets go here
    local sy = 0  -- y offset within section

    settingsWidgets.autoScan, h = CreateSettingsCheckbox(sc, sy,
        "Auto-scan bags on login",
        "Automatically scan your character's bags when you log in so FlipQueue knows what you're carrying.",
        "autoScan")
    sy = sy - h - ITEM_SPACING

    -- Auto-pull / auto-deposit / auto-deposit-all moved to Characters page
    -- (per-character settings with global defaults).
    -- Bank/warbank/gold settings moved to the dedicated "Bank & Warbank"
    -- section below. TSM behavior toggles moved to the TSM Integration page.

    settingsWidgets.skipUnassigned, h = CreateSettingsCheckbox(sc, sy,
        "Skip deals with no character",
        "When generating a to-do list, skip deals that have no matching character on the required realm instead of creating 'new character' tasks. Useful when you only want tasks for realms you already have characters on.",
        "skipUnassigned")
    sy = sy - h - ITEM_SPACING

    -- Default sell quantity slider
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(68)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Default sell quantity")

        local slider = CreateFrame("Slider", "FlipQueueSellQtySlider", row, "OptionsSliderTemplate")
        slider:SetWidth(180)
        slider:SetHeight(16)
        slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -8)
        slider:SetMinMaxValues(1, 20)
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        slider.Low:SetText("1")
        slider.High:SetText("20")

        local valLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valLabel:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        valLabel:SetTextColor(1, 1, 1)

        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            valLabel:SetText(tostring(value))
            if ns.db then
                ns.db.settings.defaultSellQty = value
            end
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("Baseline quantity per item when posting or pulling from bank.")

        settingsWidgets.sellQtySlider = slider
        settingsWidgets.sellQtyLabel = valLabel
    end
    sy = sy - 68 - ITEM_SPACING

    -- Sell quantity mode toggle
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(56)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Quantity source")

        local function CreateModeBtn(label, parent)
            local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:SetHeight(20)
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
            btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.3, 1) end)
            btn:SetScript("OnLeave", function(self)
                if not self._active then self:SetBackdropColor(0.15, 0.15, 0.2, 1) end
            end)
            return btn
        end

        local fixedBtn = CreateModeBtn("Always fixed", row)
        fixedBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

        local tsmBtn = CreateModeBtn("TSM if available", row)
        tsmBtn:SetPoint("LEFT", fixedBtn, "RIGHT", 4, 0)

        local function UpdateSellQtyMode()
            local mode = ns.db and ns.db.settings.sellQtyMode or "tsm"
            fixedBtn._active = (mode == "fixed")
            tsmBtn._active = (mode == "tsm")
            fixedBtn:SetBackdropColor(mode == "fixed" and 0.2 or 0.15, mode == "fixed" and 0.4 or 0.15, mode == "fixed" and 0.2 or 0.2, 1)
            tsmBtn:SetBackdropColor(mode == "tsm" and 0.2 or 0.15, mode == "tsm" and 0.4 or 0.15, mode == "tsm" and 0.2 or 0.2, 1)
        end

        fixedBtn:SetScript("OnClick", function()
            if ns.db then ns.db.settings.sellQtyMode = "fixed" end
            UpdateSellQtyMode()
        end)
        tsmBtn:SetScript("OnClick", function()
            if ns.db then ns.db.settings.sellQtyMode = "tsm" end
            UpdateSellQtyMode()
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", fixedBtn, "BOTTOMLEFT", 0, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("'Always fixed' uses the slider above. 'TSM if available' uses TSM's Post Cap when the item has an Auctioning operation, otherwise falls back to the fixed value.")

        settingsWidgets.sellQtyModeFixed = fixedBtn
        settingsWidgets.sellQtyModeTSM = tsmBtn
        settingsWidgets.updateSellQtyMode = UpdateSellQtyMode
    end
    sy = sy - 56 - ITEM_SPACING

    -- Expiry alert timer slider
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(68)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Expiry alert timer (minutes)")

        local slider = CreateFrame("Slider", "FlipQueueExpiryAlertSlider", row, "OptionsSliderTemplate")
        slider:SetWidth(180)
        slider:SetHeight(16)
        slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -8)
        slider:SetMinMaxValues(5, 360)
        slider:SetValueStep(5)
        slider:SetObeyStepOnDrag(true)
        slider.Low:SetText("5m")
        slider.High:SetText("6h")

        local valLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valLabel:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        valLabel:SetTextColor(1, 1, 1)

        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value / 5 + 0.5) * 5
            local displayStr = value >= 60 and string.format("%.1fh", value / 60) or (value .. "m")
            valLabel:SetText(displayStr)
            if ns.db then
                ns.db.settings.expiryAlertMinutes = value
            end
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("Show 'expiring soon' alerts for auctions within this many minutes of expiry. Affects login messages, To-Do page, and mini view.")

        settingsWidgets.expiryAlertSlider = slider
        settingsWidgets.expiryAlertLabel = valLabel
    end
    sy = sy - 68 - SECTION_SPACING

    -- Bank Tab Selection moved to Characters page (per-character config panel)

    secAuto.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Bank & Warbank
    ------------------------------------------------
    local secBank = CreateCollapsibleSection(content, y, "bankops",
        "Bank & Warbank",
        "Gold withdrawals, auto-deposits, reagents, overflow, batch size")
    sc = secBank.content
    sy = 0

    -- Warband Miser detection banner. If the addon is loaded, FlipQueue's
    -- auto-gold routines defer to it. Show a note so users know why the
    -- checkboxes below don't appear to do anything, and expose the override.
    if ns.IsWarbandMiserActive and
       C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("WarbandMiser") then
        local banner = CreateFrame("Frame", nil, sc, "BackdropTemplate")
        banner:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        banner:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        banner:SetHeight(48)
        banner:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        banner:SetBackdropColor(0.15, 0.12, 0.05, 0.9)
        banner:SetBackdropBorderColor(0.6, 0.5, 0.2, 0.8)

        local text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", banner, "TOPLEFT", 8, -6)
        text:SetPoint("RIGHT", banner, "RIGHT", -8, 0)
        text:SetJustifyH("LEFT")
        text:SetText(ns.COLORS.YELLOW ..
            "Warband Miser detected.|r FlipQueue's auto-gold settings " ..
            "are disabled while it's running.")

        local overrideCB = CreateFrame("CheckButton", nil, banner, "UICheckButtonTemplate")
        overrideCB:SetSize(18, 18)
        overrideCB:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 6, 4)
        overrideCB:SetChecked(ns.db and ns.db.settings and ns.db.settings.warbandMiserOverride or false)
        overrideCB:SetScript("OnClick", function(self)
            if ns.db then ns.db.settings.warbandMiserOverride = self:GetChecked() and true or false end
        end)
        local cbLabel = banner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cbLabel:SetPoint("LEFT", overrideCB, "RIGHT", 2, 0)
        cbLabel:SetText("Let FlipQueue manage gold anyway")

        settingsWidgets.wmOverride = overrideCB
        sy = sy - 48 - ITEM_SPACING
    end

    -- Withdraw gold for AH fees + purchases
    settingsWidgets.autoGold, h = CreateSettingsCheckbox(sc, sy,
        "Withdraw gold from the warbank for fees and purchases",
        "When you open the bank, take just enough gold from the warbank to pay estimated AH listing fees and any 'buy item' tasks for this character.",
        "autoWithdrawGold")
    sy = sy - h - ITEM_SPACING

    -- Max withdrawal gold input
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(52)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Maximum gold to withdraw per visit")

        local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        box:SetSize(100, 20)
        box:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -4)
        box:SetAutoFocus(false)
        box:SetMaxLetters(10)
        box:SetNumeric(true)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText()) or 0
            if ns.db then ns.db.settings.maxWithdrawGold = val end
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function(self)
            local val = tonumber(self:GetText()) or 0
            if ns.db then ns.db.settings.maxWithdrawGold = val end
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("Cap how much gold is taken in one visit. 0 means no limit.")

        settingsWidgets.maxWithdrawBox = box
    end
    sy = sy - 52 - ITEM_SPACING

    -- Send extra gold back to warbank
    settingsWidgets.autoDepositGold, h = CreateSettingsCheckbox(sc, sy,
        "Send extra gold back to the warbank",
        "When you open the bank, deposit gold beyond what's needed for fees plus your buffer.",
        "autoDepositGold")
    sy = sy - h - ITEM_SPACING

    -- Gold buffer input
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(52)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Gold to keep on the character")

        local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        box:SetSize(100, 20)
        box:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -4)
        box:SetAutoFocus(false)
        box:SetMaxLetters(10)
        box:SetNumeric(true)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText()) or 0
            if ns.db then ns.db.settings.goldBuffer = val end
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function(self)
            local val = tonumber(self:GetText()) or 0
            if ns.db then ns.db.settings.goldBuffer = val end
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("Extra gold to keep beyond AH fees. 0 means keep only fees.")

        settingsWidgets.goldBufferBox = box
    end
    sy = sy - 52 - ITEM_SPACING

    settingsWidgets.depositIncludeReagents, h = CreateSettingsCheckbox(sc, sy,
        "Move reagents to warbank when depositing all",
        "Include reagents when auto-depositing extra items in your bags to the warbank. This is off by default, as reagents are not tracked for sale.",
        "depositIncludeReagents")
    sy = sy - h - ITEM_SPACING

    -- Deposit overflow (nested setting — built by hand instead of via
    -- CreateSettingsCheckbox which only writes to ns.db.settings[key]).
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        cb.text:SetText("Deposit to bank when warbank is full")
        cb.text:SetFontObject("GameFontHighlightSmall")

        local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", cb.text, "BOTTOMLEFT", 0, -1)
        desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        desc:SetText("When trying to deposit to the warbank, automatically deposit to the player bank if the warbank is full.")

        cb:SetScript("OnClick", function(self)
            if not (ns.db and ns.db.settings.depositOverflow) then return end
            ns.db.settings.depositOverflow.enabled = self:GetChecked() and true or false
            -- Refresh the sub-checkbox enabled state.
            if settingsWidgets.depositOverflowCrossStack then
                local sub = settingsWidgets.depositOverflowCrossStack
                if ns.db.settings.depositOverflow.enabled then
                    sub:Enable()
                    sub.text:SetTextColor(1, 1, 1)
                else
                    sub:Disable()
                    sub.text:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end)

        row:SetScript("OnShow", function(self)
            local descH = desc:GetStringHeight() or 12
            self:SetHeight(22 + descH + 4)
        end)
        row:SetHeight(38)
        settingsWidgets.depositOverflow = cb
    end
    sy = sy - 42 - ITEM_SPACING

    -- Sub-setting: combine partial stacks across both banks
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN + 20, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        cb.text:SetText("Combine partial stacks across both banks")
        cb.text:SetFontObject("GameFontHighlightSmall")

        local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", cb.text, "BOTTOMLEFT", 0, -1)
        desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        desc:SetText("When depositing to the player bank because the warbank is full, also top up existing stacks of the same item. Otherwise only empty slots in the bank are used.")

        cb:SetScript("OnClick", function(self)
            if not (ns.db and ns.db.settings.depositOverflow) then return end
            ns.db.settings.depositOverflow.crossStack = self:GetChecked() and true or false
        end)

        row:SetScript("OnShow", function(self)
            local descH = desc:GetStringHeight() or 12
            self:SetHeight(20 + descH + 4)
        end)
        row:SetHeight(36)
        settingsWidgets.depositOverflowCrossStack = cb
    end
    sy = sy - 40 - ITEM_SPACING

    -- Items per batch slider (was "Bank pull batch size")
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(68)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Items moved per batch")

        local slider = CreateFrame("Slider", "FlipQueueBatchSizeSlider", row, "OptionsSliderTemplate")
        slider:SetWidth(180)
        slider:SetHeight(16)
        slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -8)
        slider:SetMinMaxValues(1, 10)
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        slider.Low:SetText("1")
        slider.High:SetText("10")

        local valLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valLabel:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        valLabel:SetTextColor(1, 1, 1)

        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            valLabel:SetText(tostring(value))
            if ns.db then
                ns.db.settings.pullBatchSize = value
            end
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("How many items to withdraw or deposit at once. Lower values are safer but slower.")

        settingsWidgets.batchSizeSlider = slider
        settingsWidgets.batchSizeLabel = valLabel
    end
    sy = sy - 68 - SECTION_SPACING

    secBank.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Auction House
    ------------------------------------------------
    local secAH = CreateCollapsibleSection(content, y, "auctionhouse",
        "Auction House",
        "Posting drawer and AH behavior")
    sc = secAH.content
    sy = 0

    settingsWidgets.ahAutoScan, h = CreateSettingsCheckbox(sc, sy,
        "Auto-scan inventory when the Auction House opens",
        "Automatically run a to-do scan when you open the AH, populating the posting drawer with items ready to post.",
        "ahAutoScanOnOpen")
    sy = sy - h - SECTION_SPACING

    secAH.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Notifications
    ------------------------------------------------
    local secNotif = CreateCollapsibleSection(content, y, "notifications",
        "Notifications",
        "Login messages and alerts")
    sc = secNotif.content
    sy = 0

    settingsWidgets.loginMsg, h = CreateSettingsCheckbox(sc, sy,
        "Show login message",
        "Print a chat message on login listing items to post, expired auctions to collect, and other tasks for this character.",
        "showLoginMessage")
    sy = sy - h - SECTION_SPACING

    secNotif.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Mini View
    ------------------------------------------------
    local secMini = CreateCollapsibleSection(content, y, "miniview",
        "Mini View",
        "Overlay, minimap icon, popup positions")
    sc = secMini.content
    sy = 0

    settingsWidgets.showMini, h = CreateSettingsCheckbox(sc, sy,
        "Show mini overlay",
        "Show a compact floating overlay listing current-character tasks. Drag it anywhere on screen. Persists across sessions.",
        "showMini")
    settingsWidgets.showMini:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.settings.showMini = self:GetChecked()
            if self:GetChecked() then
                UI:ShowMini()
            else
                UI:HideMini()
            end
        end
    end)
    sy = sy - h - ITEM_SPACING

    settingsWidgets.hideMiniCombat, h = CreateSettingsCheckbox(sc, sy,
        "Hide mini view in combat",
        "Automatically hide the mini overlay when you enter combat and restore it when combat ends.",
        "hideMiniInCombat")
    sy = sy - h - ITEM_SPACING

    settingsWidgets.showMinimap, h = CreateSettingsCheckbox(sc, sy,
        "Show minimap icon",
        "Show the FlipQueue icon on the minimap border for quick access. Uses LibDBIcon for compatibility with minimap managers.",
        "showMinimap")
    settingsWidgets.showMinimap:SetScript("OnClick", function(self)
        if self:GetChecked() then
            UI:ShowMinimapButton()
        else
            UI:HideMinimapButton()
        end
    end)
    sy = sy - h - ITEM_SPACING

    local bankAnchorOpts = {
        {value = "below", label = "Below mini"},
        {value = "above", label = "Above mini"},
        {value = "left",  label = "Left of mini"},
        {value = "right", label = "Right of mini"},
    }
    settingsWidgets.bankPopupAnchor, h = CreateSettingsDropdown(sc, sy,
        "Bank popup position", "Where the bank operations popup appears relative to the mini view.",
        "bankPopupAnchor", bankAnchorOpts)
    sy = sy - h - ITEM_SPACING

    local detailAnchorOpts = {
        {value = "left",  label = "Left of mini"},
        {value = "right", label = "Right of mini"},
    }
    settingsWidgets.detailPopupAnchor, h = CreateSettingsDropdown(sc, sy,
        "Item detail position", "Where the item detail popup appears when clicking a task.",
        "detailPopupAnchor", detailAnchorOpts)
    sy = sy - h - ITEM_SPACING

    -- Click-to-copy mode: clicking a row in the Next Steps queue
    -- pops up a small copy dialog with either the realm or the
    -- character name. Realm is the default because most users paste
    -- into the realm filter on the character-select screen.
    local copyModeOpts = {
        {value = "realm", label = "Realm"},
        {value = "name",  label = "Character name"},
    }
    settingsWidgets.copyOnClickMode, h = CreateSettingsDropdown(sc, sy,
        "Click-to-copy", "What a click on a Next Steps row copies — realm (to paste into the character-select realm filter) or character name.",
        "copyOnClickMode", copyModeOpts)
    sy = sy - h - ITEM_SPACING

    settingsWidgets.resetMiniPos, h = CreateSettingsButton(sc, sy,
        "Reset Mini Position", "Move the mini overlay back to its default position.", 160, function()
        if ns.db then
            ns.db.settings.miniPos = nil
            if UI.miniFrame and UI.miniFrame:IsShown() then
                UI.miniFrame:ClearAllPoints()
                UI.miniFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200)
            end
            ns:Print("Mini view position reset.")
        end
    end)
    sy = sy - h - ITEM_SPACING
    secMini.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Data Management
    ------------------------------------------------
    local secData = CreateCollapsibleSection(content, y, "data",
        "Data Management",
        "Clear inventory, imports, logs, do-not-track")
    sc = secData.content
    sy = 0

    settingsWidgets.clearInv, h = CreateSettingsButton(sc, sy,
        "Clear Inventory Data", "Wipe all saved bag/bank/warbank data. You'll need to rescan each character.", 180, function()
        StaticPopupDialogs["FLIPQUEUE_CLEAR_INVENTORY"] = {
            text = "Clear all saved inventory data? You will need to rescan on each character.",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                if ns.db then
                    for ck, charData in pairs(ns.db.characters) do
                        charData.inventory = nil
                    end
                    wipe(ns.db.warbank)
                    ns:Print("All inventory data cleared.")
                    UI:Refresh()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("FLIPQUEUE_CLEAR_INVENTORY")
    end)
    sy = sy - h - ITEM_SPACING

    settingsWidgets.clearQueue, h = CreateSettingsButton(sc, sy,
        "Clear All Imports", "Remove all imported deals.", 180, function()
        StaticPopupDialogs["FLIPQUEUE_CLEAR_ALL_SETTINGS"] = {
            text = "Clear ALL imported deals?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                ns:ImportClear("fpScanner")
                ns:Print("Imports cleared.")
                UI:Refresh()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("FLIPQUEUE_CLEAR_ALL_SETTINGS")
    end)
    sy = sy - h - ITEM_SPACING

    settingsWidgets.clearLog, h = CreateSettingsButton(sc, sy,
        "Clear Posted Log", "Remove all entries from the posted items log.", 180, function()
        StaticPopupDialogs["FLIPQUEUE_CLEAR_LOG_SETTINGS"] = {
            text = "Clear ALL items from the posted log?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                ns:ClearLog()
                ns:Print("Log cleared.")
                UI:Refresh()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("FLIPQUEUE_CLEAR_LOG_SETTINGS")
    end)
    sy = sy - h - ITEM_SPACING

    settingsWidgets.clearDNT, h = CreateSettingsButton(sc, sy,
        "Clear Do Not Track", "Remove all items from the Do Not Track list.", 180, function()
        if ns.db then
            wipe(ns.db.doNotTrack)
            ns:Print("Do Not Track list cleared.")
            UI:Refresh()
        end
    end)
    sy = sy - h - ITEM_SPACING
    secData.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Multi-Account
    ------------------------------------------------
    local secMulti = CreateCollapsibleSection(content, y, "multiaccount",
        "Multi-Account",
        "Sync inventory and to-dos across your accounts via BattleNet")
    sc = secMulti.content
    sy = 0

    -- Everything in this section uses a lower container
    local lower = CreateFrame("Frame", nil, sc)
    lower:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, sy)
    lower:SetPoint("RIGHT", sc, "RIGHT", 0, 0)
    settingsWidgets.lowerSection = lower

    local ly = 0

    -- Linked Accounts section header
    local syncLabel = lower:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncLabel:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    syncLabel:SetTextColor(0.4, 0.95, 0.4)
    syncLabel:SetText("Linked Accounts")
    ly = ly - 18

    -- Brief description
    local syncDesc = lower:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    syncDesc:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    syncDesc:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    syncDesc:SetJustifyH("LEFT")
    syncDesc:SetWordWrap(true)
    syncDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    syncDesc:SetText("Link other WoW accounts to keep their characters, bags, bank, and to-dos in sync with this one. " ..
        "Click |cffffd100Add Linked Account|r to start the guided setup.")
    ly = ly - 32

    -- Add Linked Account button (opens wizard)
    do
        local btn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        btn:SetSize(170, 26)
        btn:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        btn:SetBackdropColor(0.10, 0.22, 0.10, 1)
        btn:SetBackdropBorderColor(0.3, 0.5, 0.3, 0.9)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.text:SetPoint("CENTER")
        btn.text:SetText("+ Add Linked Account")
        btn.text:SetTextColor(0.3, 1, 0.3)
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.14, 0.28, 0.14, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.10, 0.22, 0.10, 1) end)
        btn:SetScript("OnClick", function()
            if UI.ShowLinkWizard then UI:ShowLinkWizard() end
        end)
        settingsWidgets.addLinkedAccountBtn = btn
    end
    ly = ly - 34

    -- Partner rows container — fixed height, supports up to MAX_PARTNER_ROWS visible.
    -- Rows are pooled and assigned in RefreshSettings as partners change.
    local MAX_PARTNER_ROWS = 5
    local PARTNER_ROW_HEIGHT = 32

    local partnerListFrame = CreateFrame("Frame", nil, lower)
    partnerListFrame:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    partnerListFrame:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    partnerListFrame:SetHeight(MAX_PARTNER_ROWS * PARTNER_ROW_HEIGHT + 20)
    settingsWidgets.partnerListFrame = partnerListFrame

    -- Empty state text (shown when no partners)
    settingsWidgets.partnerListEmpty = partnerListFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    settingsWidgets.partnerListEmpty:SetPoint("TOPLEFT", partnerListFrame, "TOPLEFT", 4, -4)
    settingsWidgets.partnerListEmpty:SetTextColor(0.5, 0.5, 0.5)
    settingsWidgets.partnerListEmpty:SetText("No accounts linked yet.")

    -- Build the row widget pool
    local function BuildPartnerRow(parent, rowIdx)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetSize(10, PARTNER_ROW_HEIGHT - 4)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(rowIdx - 1) * PARTNER_ROW_HEIGHT)
        row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
        row:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        row:SetBackdropColor(0.10, 0.10, 0.13, 0.6)
        row:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.6)

        -- Status dot (left)
        row.dot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.dot:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.dot:SetText("\226\151\143")  -- ●

        -- Label (name + transport tag)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.label:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)
        row.label:SetJustifyH("LEFT")

        -- Status / last sync text
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.status:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
        row.status:SetJustifyH("LEFT")
        row.status:SetTextColor(0.7, 0.7, 0.7)

        -- Remove button (right)
        row.removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.removeBtn:SetSize(70, 20)
        row.removeBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.removeBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        row.removeBtn:SetBackdropColor(0.25, 0.1, 0.1, 1)
        row.removeBtn:SetBackdropBorderColor(0.5, 0.2, 0.2, 0.8)
        row.removeBtn.text = row.removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.removeBtn.text:SetPoint("CENTER")
        row.removeBtn.text:SetText("Remove")
        row.removeBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.35, 0.15, 0.15, 1) end)
        row.removeBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.25, 0.1, 0.1, 1) end)

        -- Force Sync button (right of Remove)
        row.syncBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.syncBtn:SetSize(80, 20)
        row.syncBtn:SetPoint("RIGHT", row.removeBtn, "LEFT", -4, 0)
        row.syncBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        row.syncBtn:SetBackdropColor(0.12, 0.18, 0.28, 1)
        row.syncBtn:SetBackdropBorderColor(0.3, 0.4, 0.6, 0.8)
        row.syncBtn.text = row.syncBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.syncBtn.text:SetPoint("CENTER")
        row.syncBtn.text:SetText("Force Sync")
        row.syncBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.18, 0.24, 0.36, 1) end)
        row.syncBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.12, 0.18, 0.28, 1) end)

        return row
    end

    settingsWidgets.partnerRows = {}
    for i = 1, MAX_PARTNER_ROWS do
        local row = BuildPartnerRow(partnerListFrame, i)
        row:Hide()
        settingsWidgets.partnerRows[i] = row
    end

    ly = ly - (MAX_PARTNER_ROWS * PARTNER_ROW_HEIGHT + 28)

    -- Incoming pair request display
    settingsWidgets.pairRequestText = lower:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsWidgets.pairRequestText:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    settingsWidgets.pairRequestText:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    settingsWidgets.pairRequestText:SetJustifyH("LEFT")
    ly = ly - 16

    -- Accept / Deny buttons (shown when there's a pending request)
    do
        local acceptBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        acceptBtn:SetSize(80, 22)
        acceptBtn:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        acceptBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        acceptBtn:SetBackdropColor(0.1, 0.3, 0.1, 1)
        acceptBtn:SetBackdropBorderColor(0.2, 0.5, 0.2, 0.8)
        acceptBtn.text = acceptBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        acceptBtn.text:SetPoint("CENTER")
        acceptBtn.text:SetText("Accept")
        acceptBtn:SetScript("OnClick", function()
            if ns.Sync then
                local _, senderGAID = ns.Sync:GetPendingPairFrom()
                if senderGAID then ns.Sync:AcceptPair(senderGAID) end
            end
            UI:RefreshSettings()
        end)
        settingsWidgets.pairAcceptBtn = acceptBtn

        local denyBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        denyBtn:SetSize(80, 22)
        denyBtn:SetPoint("LEFT", acceptBtn, "RIGHT", 6, 0)
        denyBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        denyBtn:SetBackdropColor(0.3, 0.1, 0.1, 1)
        denyBtn:SetBackdropBorderColor(0.5, 0.2, 0.2, 0.8)
        denyBtn.text = denyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        denyBtn.text:SetPoint("CENTER")
        denyBtn.text:SetText("Deny")
        denyBtn:SetScript("OnClick", function()
            if ns.Sync then
                local _, senderGAID = ns.Sync:GetPendingPairFrom()
                ns.Sync:DenyPair(senderGAID)
            end
            UI:RefreshSettings()
        end)
        settingsWidgets.pairDenyBtn = denyBtn
    end
    ly = ly - 26 - ITEM_SPACING

    -- Sync Debug Log (collapsible)
    do
        local toggleBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        toggleBtn:SetSize(130, 20)
        toggleBtn:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        toggleBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        toggleBtn:SetBackdropColor(0.1, 0.1, 0.15, 1)
        toggleBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        toggleBtn.text = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        toggleBtn.text:SetPoint("CENTER")
        toggleBtn.text:SetText("Show Sync Log")
        toggleBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.25, 1) end)
        toggleBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.1, 0.1, 0.15, 1) end)

        -- Copy button: opens the existing Export popup preloaded with the
        -- sync log in plain text so the user can Ctrl+A / Ctrl+C it. The
        -- inline EditBox in this panel can't reliably hold focus for copy,
        -- so we piggyback on the export popup infrastructure that already
        -- handles selection, focus, and pipe-escaping correctly.
        local copyBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        copyBtn:SetSize(80, 20)
        copyBtn:SetPoint("LEFT", toggleBtn, "RIGHT", 6, 0)
        copyBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        copyBtn:SetBackdropColor(0.1, 0.1, 0.15, 1)
        copyBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        copyBtn.text = copyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        copyBtn.text:SetPoint("CENTER")
        copyBtn.text:SetText("Copy Log")
        copyBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.25, 1) end)
        copyBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.1, 0.1, 0.15, 1) end)
        copyBtn:SetScript("OnClick", function()
            if not (ns.Sync and ns.Sync.GetSyncLog) then return end
            local log = ns.Sync:GetSyncLog()
            if #log == 0 then
                if UI.ShowExportPopup then
                    UI:ShowExportPopup("(no sync events yet)", "Sync log")
                end
                return
            end
            local lines = {}
            for i = 1, #log do
                local entry = log[i]
                if entry and entry.t then
                    local ts = date("%Y-%m-%d %H:%M:%S", entry.t)
                    local ev = entry.event
                    if type(ev) ~= "string" or ev == "" then ev = "?" end
                    local detail = entry.detail
                    if type(detail) ~= "string" then detail = "" end
                    lines[#lines + 1] = ts .. "  " .. ev .. "  " .. detail
                end
            end
            if UI.ShowExportPopup then
                UI:ShowExportPopup(table.concat(lines, "\n"),
                    "Sync log (" .. #log .. " entries)")
            end
        end)
        settingsWidgets.syncLogCopyBtn = copyBtn

        ly = ly - 24

        local logFrame = CreateFrame("Frame", nil, lower, "BackdropTemplate")
        logFrame:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        logFrame:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
        logFrame:SetHeight(180)
        logFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        logFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
        logFrame:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)
        logFrame:Hide()

        -- Scrollable text inside
        local scroll = CreateFrame("ScrollFrame", nil, logFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", -28, 6)

        local logText = CreateFrame("EditBox", nil, scroll)
        logText:SetMultiLine(true)
        logText:SetAutoFocus(false)
        logText:SetFontObject(GameFontHighlightSmall)
        logText:SetWidth(scroll:GetWidth() or 350)
        logText:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        logText:EnableMouse(true)
        logText:SetScript("OnMouseUp", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(logText)

        settingsWidgets.syncLogFrame = logFrame
        settingsWidgets.syncLogText = logText
        settingsWidgets.syncLogScroll = scroll

        local logVisible = false
        toggleBtn:SetScript("OnClick", function()
            logVisible = not logVisible
            if logVisible then
                logFrame:Show()
                toggleBtn.text:SetText("Hide Sync Log")
                UI:RefreshSyncLog()
            else
                logFrame:Hide()
                toggleBtn.text:SetText("Show Sync Log")
            end
        end)
        settingsWidgets.syncLogToggle = toggleBtn

        -- Auto-refresh timer when log is visible
        local logRefreshTicker = nil
        logFrame:SetScript("OnShow", function()
            logRefreshTicker = C_Timer.NewTicker(2, function()
                if logFrame:IsShown() then
                    UI:RefreshSyncLog()
                end
            end)
        end)
        logFrame:SetScript("OnHide", function()
            if logRefreshTicker then logRefreshTicker:Cancel(); logRefreshTicker = nil end
        end)

        ly = ly - 4 -- collapsed height

        -- When sync log toggles, shift everything below it
        local SYNC_LOG_HEIGHT = 180
        local belowSyncBaseY = ly - SECTION_SPACING
        local belowSync = CreateFrame("Frame", nil, lower)
        belowSync:SetPoint("TOPLEFT", lower, "TOPLEFT", 0, belowSyncBaseY)
        belowSync:SetPoint("RIGHT", lower, "RIGHT", 0, 0)
        belowSync:SetHeight(600)
        settingsWidgets.belowSyncFrame = belowSync
        settingsWidgets.belowSyncBaseY = belowSyncBaseY

        local origToggleOnClick = toggleBtn:GetScript("OnClick")
        toggleBtn:SetScript("OnClick", function(self)
            origToggleOnClick(self)
            -- Reposition the content below the sync log
            belowSync:ClearAllPoints()
            if logFrame:IsShown() then
                belowSync:SetPoint("TOPLEFT", lower, "TOPLEFT", 0, belowSyncBaseY - SYNC_LOG_HEIGHT)
            else
                belowSync:SetPoint("TOPLEFT", lower, "TOPLEFT", 0, belowSyncBaseY)
            end
            -- Update total content height
            local extraH = logFrame:IsShown() and SYNC_LOG_HEIGHT or 0
            local bsH = settingsWidgets.belowSyncContentHeight or 300
            lower:SetHeight(math.abs(belowSyncBaseY) + bsH + extraH + 10)
            if sectionContainers.multiaccount then
                sectionContainers.multiaccount.contentHeight = math.abs(belowSyncBaseY) + bsH + extraH + 10
            end
            if UI.ReflowSettings then UI:ReflowSettings() end
        end)
    end

    -- Everything below the sync log goes into belowSync container
    local belowSync = settingsWidgets.belowSyncFrame
    local bsy = 0

    ------------------------------------------------
    -- Tutorial
    ------------------------------------------------
    -- Divider
    local tutDivider = belowSync:CreateTexture(nil, "ARTWORK")
    tutDivider:SetHeight(1)
    tutDivider:SetPoint("TOPLEFT", belowSync, "TOPLEFT", LEFT_MARGIN, bsy)
    tutDivider:SetPoint("RIGHT", belowSync, "RIGHT", RIGHT_MARGIN, 0)
    tutDivider:SetColorTexture(0.35, 0.35, 0.45, 0.6)
    local tutHeader = belowSync:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tutHeader:SetPoint("TOPLEFT", belowSync, "TOPLEFT", LEFT_MARGIN, bsy - 6)
    tutHeader:SetTextColor(0.9, 0.8, 0.3)
    tutHeader:SetText("Tutorial")
    bsy = bsy - 22 - ITEM_SPACING

    local tutorialBtn = CreateFrame("Button", nil, belowSync, "BackdropTemplate")
    tutorialBtn:SetSize(180, 26)
    tutorialBtn:SetPoint("TOPLEFT", belowSync, "TOPLEFT", LEFT_MARGIN, bsy)
    tutorialBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    tutorialBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    tutorialBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    local tutBtnText = tutorialBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tutBtnText:SetPoint("CENTER")
    tutBtnText:SetText("Show Tutorial Again")
    tutorialBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.3, 1)
    end)
    tutorialBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
    end)
    tutorialBtn:SetScript("OnClick", function()
        ns.db.settings.tutorialDone = false
        UI._tutorialActive = true
        UI._tutorialStep = 1
        UI._tutorialCallout = 1
        UI.currentPage = "todo"
        UI:Refresh()
    end)

    local tutDesc = belowSync:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tutDesc:SetPoint("LEFT", tutorialBtn, "RIGHT", 8, 0)
    tutDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    tutDesc:SetText("Walk through the first-time setup again")
    bsy = bsy - 30 - ITEM_SPACING

    -- Setup Wizard button
    local wizardBtn = CreateFrame("Button", nil, belowSync, "BackdropTemplate")
    wizardBtn:SetSize(180, 26)
    wizardBtn:SetPoint("TOPLEFT", belowSync, "TOPLEFT", LEFT_MARGIN, bsy)
    wizardBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    wizardBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    wizardBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    local wizBtnText = wizardBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wizBtnText:SetPoint("CENTER")
    wizBtnText:SetText("Run Setup Wizard")
    wizardBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.3, 1)
    end)
    wizardBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
    end)
    wizardBtn:SetScript("OnClick", function()
        ns.db.settings.setupDone = false
        UI:Refresh()  -- triggers wizard detection with proper page cleanup
    end)

    local wizDesc = belowSync:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wizDesc:SetPoint("LEFT", wizardBtn, "RIGHT", 8, 0)
    wizDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    wizDesc:SetText("Walk through settings step by step")
    bsy = bsy - 30 - SECTION_SPACING

    ------------------------------------------------
    -- Credits
    ------------------------------------------------
    local credDivider = belowSync:CreateTexture(nil, "ARTWORK")
    credDivider:SetHeight(1)
    credDivider:SetPoint("TOPLEFT", belowSync, "TOPLEFT", LEFT_MARGIN, bsy)
    credDivider:SetPoint("RIGHT", belowSync, "RIGHT", RIGHT_MARGIN, 0)
    credDivider:SetColorTexture(0.35, 0.35, 0.45, 0.6)
    local credHeader = belowSync:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    credHeader:SetPoint("TOPLEFT", belowSync, "TOPLEFT", LEFT_MARGIN, bsy - 6)
    credHeader:SetTextColor(0.9, 0.8, 0.3)
    credHeader:SetText("Credits")
    bsy = bsy - 22

    -- Banner logo
    local banner = belowSync:CreateTexture(nil, "ARTWORK")
    banner:SetSize(340, 86)
    banner:SetPoint("TOP", belowSync, "TOP", 0, bsy)
    banner:SetTexture("Interface\\AddOns\\flipqueue\\Art\\flipqueue-banner")
    bsy = bsy - 92

    -- Version
    local ver = belowSync:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ver:SetPoint("TOP", belowSync, "TOP", 0, bsy)
    ver:SetTextColor(0.8, 0.75, 0.5)
    ver:SetText("v" .. ns.VERSION)
    bsy = bsy - 20

    -- Credits text
    local function AddCreditLine(parent, yOff, label, value)
        local line = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOP", parent, "TOP", 0, yOff)
        line:SetJustifyH("CENTER")
        line:SetText(ns.COLORS.YELLOW .. label .. "|r  " .. value)
        return 14
    end

    bsy = bsy - 4
    bsy = bsy - AddCreditLine(belowSync, bsy, "Developed by", "Gezmodean & Claude")
    bsy = bsy - 4
    bsy = bsy - AddCreditLine(belowSync, bsy, "Additional support by", "Berick")
    bsy = bsy - 4
    bsy = bsy - AddCreditLine(belowSync, bsy, "Additional testing by", "KittyKiller, Niduin, Artificer Skills")
    bsy = bsy - 12

    local thanksLabel = belowSync:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thanksLabel:SetPoint("TOP", belowSync, "TOP", 0, bsy)
    thanksLabel:SetJustifyH("CENTER")
    thanksLabel:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    thanksLabel:SetText("Special thanks to")
    bsy = bsy - 14

    local thanksNames = belowSync:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    thanksNames:SetPoint("TOP", belowSync, "TOP", 0, bsy)
    thanksNames:SetJustifyH("CENTER")
    thanksNames:SetText("FlippingPal  |  TradeSkillMaster  |  Auctionator  |  Epos")
    bsy = bsy - 24

    settingsWidgets.belowSyncContentHeight = math.abs(bsy)
    belowSync:SetHeight(math.abs(bsy) + 10)

    local belowSyncBaseY = settingsWidgets.belowSyncBaseY or 0
    lower:SetHeight(math.abs(belowSyncBaseY) + math.abs(bsy) + 10)
    settingsWidgets.lowerSectionHeight = math.abs(belowSyncBaseY) + math.abs(bsy) + 10

    -- Set multi-account section height from the lower container
    secMulti.contentHeight = math.abs(belowSyncBaseY) + math.abs(bsy) + 10

    -- Initial reflow positions all collapsible sections
    UI:ReflowSettings()

    settingsPanel = scroll
    return settingsPanel
end

function UI:ShowSettingsPage()
    if not settingsPanel then
        self:CreateSettingsPanel(self.tableContainer)
    end
    settingsPanel:Show()
    self:RefreshSettings()
end

function UI:HideSettingsPage()
    if settingsPanel then
        settingsPanel:Hide()
    end
end

function UI:RefreshSettings()
    if not ns.db then return end
    if settingsWidgets.autoScan then
        settingsWidgets.autoScan:SetChecked(ns.db.settings.autoScan)
    end
    -- autoPull, autoDeposit, autoDepositAll moved to Characters page
    if settingsWidgets.autoGold then
        settingsWidgets.autoGold:SetChecked(ns.db.settings.autoWithdrawGold)
    end
    if settingsWidgets.maxWithdrawBox then
        local val = ns.db.settings.maxWithdrawGold or 0
        settingsWidgets.maxWithdrawBox:SetText(tostring(val))
    end
    if settingsWidgets.autoDepositGold then
        settingsWidgets.autoDepositGold:SetChecked(ns.db.settings.autoDepositGold)
    end
    if settingsWidgets.ahAutoScan then
        settingsWidgets.ahAutoScan:SetChecked(ns.db.settings.ahAutoScanOnOpen)
    end
    if settingsWidgets.goldBufferBox then
        local val = ns.db.settings.goldBuffer or 0
        settingsWidgets.goldBufferBox:SetText(tostring(val))
    end
    if settingsWidgets.depositIncludeReagents then
        settingsWidgets.depositIncludeReagents:SetChecked(ns.db.settings.depositIncludeReagents)
    end
    if settingsWidgets.depositOverflow then
        local ov = ns.db.settings.depositOverflow or {}
        settingsWidgets.depositOverflow:SetChecked(ov.enabled and true or false)
    end
    if settingsWidgets.depositOverflowCrossStack then
        local ov = ns.db.settings.depositOverflow or {}
        local sub = settingsWidgets.depositOverflowCrossStack
        sub:SetChecked(ov.crossStack and true or false)
        if ov.enabled then
            sub:Enable()
            sub.text:SetTextColor(1, 1, 1)
        else
            sub:Disable()
            sub.text:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    -- TSM behavior toggles moved to the TSM Integration page; their populate
    -- logic now lives in UI/TSMFrame.lua RefreshTSMPage().
    if settingsWidgets.loginMsg then
        settingsWidgets.loginMsg:SetChecked(ns.db.settings.showLoginMessage)
    end
    if settingsWidgets.showMini then
        settingsWidgets.showMini:SetChecked(ns.db.settings.showMini)
    end
    if settingsWidgets.hideMiniCombat then
        settingsWidgets.hideMiniCombat:SetChecked(ns.db.settings.hideMiniInCombat)
    end
    if settingsWidgets.showMinimap then
        settingsWidgets.showMinimap:SetChecked(UI:IsMinimapButtonShown())
    end
    if settingsWidgets.bankPopupAnchor then
        settingsWidgets.bankPopupAnchor:SetValue(ns.db.settings.bankPopupAnchor)
    end
    if settingsWidgets.detailPopupAnchor then
        settingsWidgets.detailPopupAnchor:SetValue(ns.db.settings.detailPopupAnchor)
    end
    if settingsWidgets.copyOnClickMode then
        settingsWidgets.copyOnClickMode:SetValue(ns.db.settings.copyOnClickMode or "realm")
    end
    -- Batch size slider
    if settingsWidgets.batchSizeSlider then
        local batchSize = ns.db.settings.pullBatchSize or 5
        settingsWidgets.batchSizeSlider:SetValue(batchSize)
        if settingsWidgets.batchSizeLabel then
            settingsWidgets.batchSizeLabel:SetText(tostring(batchSize))
        end
    end
    -- Default sell quantity slider
    if settingsWidgets.sellQtySlider then
        local sellQty = ns.db.settings.defaultSellQty or 1
        settingsWidgets.sellQtySlider:SetValue(sellQty)
        if settingsWidgets.sellQtyLabel then
            settingsWidgets.sellQtyLabel:SetText(tostring(sellQty))
        end
    end
    -- Sell quantity mode toggle
    if settingsWidgets.updateSellQtyMode then
        settingsWidgets.updateSellQtyMode()
    end
    -- Expiry alert slider
    if settingsWidgets.expiryAlertSlider then
        local mins = ns.db.settings.expiryAlertMinutes or 15
        settingsWidgets.expiryAlertSlider:SetValue(mins)
        if settingsWidgets.expiryAlertLabel then
            local displayStr = mins >= 60 and string.format("%.1fh", mins / 60) or (mins .. "m")
            settingsWidgets.expiryAlertLabel:SetText(displayStr)
        end
    end
    -- Bank tab selection moved to Characters page config panel

    -- Partner list rows (per-partner management)
    if settingsWidgets.partnerRows then
        -- Collect partners into an ordered list so row assignment is stable
        local partnersList = {}
        if ns.Sync and ns.Sync.GetPartners then
            for uuid, partner in pairs(ns.Sync:GetPartners()) do
                partnersList[#partnersList + 1] = { uuid = uuid, partner = partner }
            end
            table.sort(partnersList, function(a, b)
                return (a.partner.label or a.uuid) < (b.partner.label or b.uuid)
            end)
        end

        if settingsWidgets.partnerListEmpty then
            settingsWidgets.partnerListEmpty:SetShown(#partnersList == 0)
        end

        for i, row in ipairs(settingsWidgets.partnerRows) do
            local entry = partnersList[i]
            if entry then
                local uuid = entry.uuid
                local partner = entry.partner
                local pState = ns.Sync:GetPartnerState(uuid)
                local isConnected = (pState == "connected" or pState == "syncing")

                if isConnected then
                    row.dot:SetTextColor(0.3, 1, 0.3)
                else
                    row.dot:SetTextColor(1, 0.3, 0.3)
                end

                local transportTag = ""
                if partner.transport == "whisper" then
                    transportTag = " |cff888888[local]|r"
                else
                    transportTag = " |cff888888[bnet]|r"
                end
                row.label:SetText((partner.label or "Account") .. transportTag)

                local statusBits = {}
                statusBits[#statusBits + 1] = isConnected and "|cff66cc66Online|r" or "|cffcc6666Offline|r"
                local lastSync = partner.lastFullSync or 0
                if lastSync > 0 then
                    statusBits[#statusBits + 1] = "last sync " .. ns:FormatRelativeTime(lastSync)
                else
                    statusBits[#statusBits + 1] = "not yet synced"
                end
                local pending = ns.Sync:GetPendingCount(uuid)
                if pending > 0 then
                    statusBits[#statusBits + 1] = "|cffffcc66" .. pending .. " queued|r"
                end
                row.status:SetText(table.concat(statusBits, "  •  "))

                -- Wire up per-partner button handlers (re-wire each refresh since uuid may change position)
                row.removeBtn:SetScript("OnClick", function()
                    if ns.Sync and ns.Sync.UnlinkByUUID then
                        ns.Sync:UnlinkByUUID(uuid)
                        UI:RefreshSettings()
                    end
                end)
                row.syncBtn:SetScript("OnClick", function()
                    if ns.Sync and ns.Sync.ForceSyncByUUID then
                        ns.Sync:ForceSyncByUUID(uuid)
                    end
                end)
                row.syncBtn:SetEnabled(isConnected)
                if isConnected then
                    row.syncBtn.text:SetTextColor(1, 1, 1)
                else
                    row.syncBtn.text:SetTextColor(0.5, 0.5, 0.5)
                end

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Pair request display
    if settingsWidgets.pairRequestText then
        if ns.Sync and ns.Sync:HasPendingPairRequest() then
            local from = ns.Sync:GetPendingPairFrom()
            settingsWidgets.pairRequestText:SetText(ns.COLORS.CYAN .. (from or "?") .. "|r wants to link.")
            if settingsWidgets.pairAcceptBtn then settingsWidgets.pairAcceptBtn:Show() end
            if settingsWidgets.pairDenyBtn then settingsWidgets.pairDenyBtn:Show() end
        else
            settingsWidgets.pairRequestText:SetText("")
            if settingsWidgets.pairAcceptBtn then settingsWidgets.pairAcceptBtn:Hide() end
            if settingsWidgets.pairDenyBtn then settingsWidgets.pairDenyBtn:Hide() end
        end
    end

end

function UI:RefreshSyncLog()
    if not settingsWidgets.syncLogText then return end
    if not ns.Sync or not ns.Sync.GetSyncLog then return end

    local log = ns.Sync:GetSyncLog()
    if #log == 0 then
        settingsWidgets.syncLogText:SetText("|cff888888No sync events yet.|r")
        return
    end

    local lines = {}
    -- Show most recent entries at the bottom (natural chat order)
    local start = math.max(1, #log - 99) -- last 100 entries
    for i = start, #log do
        local entry = log[i]
        if entry and entry.t then
            local ts = date("%H:%M:%S", entry.t)
            local ev = entry.event
            if type(ev) ~= "string" or ev == "" then ev = "?" end
            local detail = entry.detail
            if type(detail) ~= "string" then detail = "" end
            lines[#lines + 1] = "|cff888888" .. ts .. "|r |cff66aaff" .. ev .. "|r " .. detail
        end
    end
    settingsWidgets.syncLogText:SetText(table.concat(lines, "\n"))

    -- Auto-scroll to bottom
    C_Timer.After(0, function()
        if settingsWidgets.syncLogScroll then
            local max = settingsWidgets.syncLogScroll:GetVerticalScrollRange()
            settingsWidgets.syncLogScroll:SetVerticalScroll(max)
        end
    end)
end

-- Legacy ShowSettings opens the main window to settings page
function UI:ShowSettings()
    self.currentPage = "settings"
    self.mainFrame:Show()
    self:Refresh()
end
