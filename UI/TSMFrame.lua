-- UI/TSMFrame.lua
-- Dedicated TSM integration page rendered inside the main window content area
local addonName, ns = ...

local UI = ns.UI

local tsmPanel
local tsmWidgets = {}

-- Layout constants (match SettingsFrame)
local LEFT_MARGIN = 12
local RIGHT_MARGIN = -12
local SECTION_SPACING = 14
local ITEM_SPACING = 6
local DESC_COLOR = {0.6, 0.6, 0.6}

--------------------------
-- Section Header
--------------------------

local function SectionHeader(parent, yOffset, text)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    divider:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)
    divider:SetColorTexture(0.35, 0.35, 0.45, 0.6)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset - 6)
    label:SetTextColor(0.9, 0.8, 0.3)
    label:SetText(text)
    return 22
end

--------------------------
-- Dropdown helper
--------------------------

local function CreateDropdown(parent, yOffset, title, width, onSelect)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)
    row:SetHeight(44)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(title)

    -- Button that shows selected value and opens dropdown
    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
    btn:SetSize(width, 24)
    btn:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.1, 0.1, 0.15, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.text:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetText("Select...")

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetText("v")
    arrow:SetTextColor(0.6, 0.6, 0.6)

    -- Dropdown menu frame
    local menu = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(width)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    menu:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    menu:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    menu:SetFrameStrata("DIALOG")
    menu:Hide()
    menu.items = {}

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            menu:Show()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.22, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.15, 1)
    end)

    -- Populate dropdown items
    function btn:SetItems(items, selectedValue)
        -- Clear old items
        for _, item in ipairs(menu.items) do
            item:Hide()
            item:SetParent(nil)
        end
        wipe(menu.items)

        local menuY = -4
        for _, entry in ipairs(items) do
            local item = CreateFrame("Button", nil, menu)
            item:SetHeight(20)
            item:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, menuY)
            item:SetPoint("RIGHT", menu, "RIGHT", -4, 0)

            item.bg = item:CreateTexture(nil, "BACKGROUND")
            item.bg:SetAllPoints()
            item.bg:SetColorTexture(1, 1, 1, 0)

            item.text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            item.text:SetPoint("LEFT", item, "LEFT", 6, 0)
            item.text:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            item.text:SetJustifyH("LEFT")
            item.text:SetText(entry.label or entry.value)

            if entry.value == selectedValue then
                item.text:SetTextColor(0.3, 1, 0.3)
            else
                item.text:SetTextColor(0.9, 0.9, 0.9)
            end

            item:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(1, 1, 1, 0.08)
            end)
            item:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(1, 1, 1, 0)
            end)

            local val = entry.value
            item:SetScript("OnClick", function()
                menu:Hide()
                btn.text:SetText(entry.label or val)
                if onSelect then onSelect(val) end
            end)

            menu.items[#menu.items + 1] = item
            menuY = menuY - 20
        end

        menu:SetHeight(math.max(20, math.abs(menuY) + 4))
    end

    return btn, 48
end

--------------------------
-- Checkbox helper
--------------------------

local function CreateCheckbox(parent, yOffset, title, desc, settingKey, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)

    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    cb.text:SetText(title)
    cb.text:SetFontObject("GameFontHighlightSmall")

    local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    descText:SetPoint("TOPLEFT", cb.text, "BOTTOMLEFT", 0, -1)
    descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    descText:SetText(desc)

    cb:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.settings[settingKey] = self:GetChecked()
            if onChange then onChange(self:GetChecked()) end
        end
    end)

    cb.settingKey = settingKey
    row:SetHeight(38)
    return cb, 42
end

--------------------------
-- EditBox helper
--------------------------

local function CreateEditBox(parent, yOffset, title, desc, settingKey, width, validator)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)

    local titleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleText:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    titleText:SetText(title)

    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 4, -4)
    box:SetAutoFocus(false)
    box:SetMaxLetters(200)

    local indicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    indicator:SetPoint("LEFT", box, "RIGHT", 6, 0)
    box._indicator = indicator

    local function SaveAndValidate()
        if not ns.db then return end
        local val = box:GetText():match("^%s*(.-)%s*$")
        ns.db.settings[settingKey] = val
        if validator and val ~= "" then
            indicator:SetText(validator(val) and "|cff00ff00OK|r" or "|cffff4444Invalid|r")
        else
            indicator:SetText("")
        end
    end

    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        SaveAndValidate()
    end)
    box:SetScript("OnEditFocusLost", SaveAndValidate)

    local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    descText:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -2)
    descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    descText:SetText(desc)

    row:SetHeight(54)
    box.settingKey = settingKey
    return box, 58
end

--------------------------
-- Main TSM Panel
--------------------------

function UI:CreateTSMPanel(parent)
    if tsmPanel then return tsmPanel end

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(scroll:GetWidth())
    content:SetHeight(1000)
    scroll:SetScrollChild(content)

    scroll:SetScript("OnSizeChanged", function(sf, w)
        content:SetWidth(w)
    end)

    local y = -6
    local h

    ------------------------------------------------
    -- Status & Enable
    ------------------------------------------------

    -- Status line
    tsmWidgets.status = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tsmWidgets.status:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    y = y - 20

    -- Enable toggle
    tsmWidgets.enabled, h = CreateCheckbox(content, y,
        "Enable TSM Integration",
        "Use TradeSkillMaster pricing data for sell/skip decisions and optional price columns. Items are matched to their TSM group's Auctioning operation automatically.",
        "tsmEnabled",
        function()
            ns.TSM:InvalidateCache()
            UI:RefreshTSMPage()
            UI:Refresh()
        end)
    y = y - h - SECTION_SPACING

    ------------------------------------------------
    -- Profile Selection
    ------------------------------------------------
    y = y - SectionHeader(content, y, "Profile")

    tsmWidgets.profileDropdown, h = CreateDropdown(content, y,
        "TSM Profile:", 280,
        function(value)
            if ns.db then
                ns.db.settings.tsmProfile = value
                ns.TSM:InvalidateCache()
                UI:RefreshTSMPage()
            end
        end)
    y = y - h - ITEM_SPACING

    -- Active profile note
    tsmWidgets.profileNote = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tsmWidgets.profileNote:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    tsmWidgets.profileNote:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    tsmWidgets.profileNote:SetJustifyH("LEFT")
    tsmWidgets.profileNote:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    y = y - 16

    ------------------------------------------------
    -- Operations Info (read-only)
    ------------------------------------------------
    y = y - SectionHeader(content, y, "Auctioning Operations")

    tsmWidgets.opInfo = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tsmWidgets.opInfo:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    tsmWidgets.opInfo:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    tsmWidgets.opInfo:SetJustifyH("LEFT")
    tsmWidgets.opInfo:SetWordWrap(true)
    tsmWidgets.opInfo:SetSpacing(2)
    y = y - 60

    tsmWidgets.opDesc = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tsmWidgets.opDesc:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    tsmWidgets.opDesc:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    tsmWidgets.opDesc:SetJustifyH("LEFT")
    tsmWidgets.opDesc:SetWordWrap(true)
    tsmWidgets.opDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    tsmWidgets.opDesc:SetText("Each queue item is matched to its TSM group. The group's Auctioning operation minPrice is used as the sell/don't-sell threshold. Items not in any TSM group use the fallback below.")
    y = y - 36 - ITEM_SPACING

    ------------------------------------------------
    -- Fallback & Display Settings
    ------------------------------------------------
    y = y - SectionHeader(content, y, "Price Settings")

    tsmWidgets.fallback, h = CreateEditBox(content, y,
        "Fallback threshold (items not in TSM groups):",
        "TSM price expression for items without an Auctioning operation. Default: 70% DBMarket",
        "tsmMinPriceSource", 220,
        function(val) return ns.TSM:IsValidPriceSource(val) end)
    y = y - h - ITEM_SPACING

    tsmWidgets.priceSource, h = CreateEditBox(content, y,
        "AH Price column shows:",
        "TSM price source for the AH Price column. Default: DBMinBuyout",
        "tsmPriceSource", 220,
        function(val) return ns.TSM:IsValidPriceSource(val) end)
    y = y - h - SECTION_SPACING

    ------------------------------------------------
    -- Display Options
    ------------------------------------------------
    y = y - SectionHeader(content, y, "Display")

    tsmWidgets.showColumns, h = CreateCheckbox(content, y,
        "Show AH Price column",
        "Add an AH Price column to Post Now and Queue tables showing live TSM pricing data.",
        "tsmShowColumns",
        function()
            UI:UpdateTSMColumns()
            UI:Refresh()
        end)
    y = y - h - SECTION_SPACING

    ------------------------------------------------
    -- Price Auto-Update
    ------------------------------------------------
    y = y - SectionHeader(content, y, "Price Updates")

    tsmWidgets.autoUpdate, h = CreateCheckbox(content, y,
        "Auto-update expected price from TSM",
        "Update queue items' expected price from TSM when viewing Post Now. Only overwrites prices older than the threshold below.",
        "tsmAutoUpdatePrice")
    y = y - h - ITEM_SPACING

    -- Price age slider
    do
        local ageRow = CreateFrame("Frame", nil, content)
        ageRow:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
        ageRow:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
        ageRow:SetHeight(52)

        local ageTitle = ageRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ageTitle:SetPoint("TOPLEFT", ageRow, "TOPLEFT", 0, 0)
        ageTitle:SetText("Only update prices older than:")

        local ageSlider = CreateFrame("Slider", "FlipQueueTSMAgeSlider", ageRow, "OptionsSliderTemplate")
        ageSlider:SetWidth(180)
        ageSlider:SetHeight(16)
        ageSlider:SetPoint("TOPLEFT", ageTitle, "BOTTOMLEFT", 4, -8)
        ageSlider:SetMinMaxValues(0, 24)
        ageSlider:SetValueStep(1)
        ageSlider:SetObeyStepOnDrag(true)
        ageSlider.Low:SetText("0h")
        ageSlider.High:SetText("24h")

        local ageLabel = ageRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ageLabel:SetPoint("LEFT", ageSlider, "RIGHT", 8, 0)
        ageLabel:SetTextColor(1, 1, 1)

        ageSlider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            ageLabel:SetText(value == 0 and "Always" or (value .. "h"))
            if ns.db then
                ns.db.settings.tsmPriceMaxAge = value * 3600
            end
        end)

        local ageDesc = ageRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ageDesc:SetPoint("TOPLEFT", ageSlider, "BOTTOMLEFT", -4, -4)
        ageDesc:SetPoint("RIGHT", ageRow, "RIGHT", 0, 0)
        ageDesc:SetJustifyH("LEFT")
        ageDesc:SetWordWrap(true)
        ageDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        ageDesc:SetText("Only overwrite imported prices when the import is older than this. 0 = always update.")

        tsmWidgets.ageSlider = ageSlider
        tsmWidgets.ageLabel = ageLabel
    end
    y = y - 52 - SECTION_SPACING

    content:SetHeight(math.abs(y) + 10)

    tsmPanel = scroll
    return tsmPanel
end

--------------------------
-- Show / Hide / Refresh
--------------------------

function UI:ShowTSMPage()
    if not tsmPanel then
        self:CreateTSMPanel(self.tableContainer)
    end
    tsmPanel:Show()
    self:RefreshTSMPage()
end

function UI:HideTSMPage()
    if tsmPanel then
        tsmPanel:Hide()
    end
end

function UI:RefreshTSMPage()
    if not ns.db then return end

    -- Status
    if tsmWidgets.status then
        if ns.TSM:IsAvailable() then
            tsmWidgets.status:SetText("|cff00ff00TSM detected|r  -  " ..
                (ns.TSM:GetActiveProfile() and ("Active profile: |cffffffff" .. ns.TSM:GetActiveProfile() .. "|r") or ""))
        else
            tsmWidgets.status:SetText("|cffff4444TSM is not installed or not loaded.|r")
        end
    end

    -- Enable
    if tsmWidgets.enabled then
        tsmWidgets.enabled:SetChecked(ns.db.settings.tsmEnabled)
    end

    -- Profile dropdown
    if tsmWidgets.profileDropdown and ns.TSM:IsAvailable() then
        local profiles = ns.TSM:GetProfiles()
        local activeProfile = ns.TSM:GetActiveProfile()
        local selectedProfile = ns.db.settings.tsmProfile
        local effectiveProfile = (selectedProfile and selectedProfile ~= "") and selectedProfile or activeProfile

        local items = {
            {value = "", label = "(Use active profile)"},
        }
        for _, name in ipairs(profiles) do
            local label = name
            if name == activeProfile then
                label = name .. "  (active)"
            end
            items[#items + 1] = {value = name, label = label}
        end

        tsmWidgets.profileDropdown:SetItems(items, selectedProfile or "")

        -- Update button text
        if selectedProfile and selectedProfile ~= "" then
            tsmWidgets.profileDropdown.text:SetText(selectedProfile)
        else
            tsmWidgets.profileDropdown.text:SetText("(Use active profile)")
        end

        -- Profile note
        if tsmWidgets.profileNote then
            tsmWidgets.profileNote:SetText("Using: |cffffffff" .. (effectiveProfile or "none") .. "|r")
        end
    end

    -- Operations info
    if tsmWidgets.opInfo then
        local profile = ns.TSM:GetSelectedProfile()
        if profile and ns.TSM:IsAvailable() then
            local ops = ns.TSM:GetAuctioningOperations(profile)
            if #ops > 0 then
                local lines = {}
                for _, name in ipairs(ops) do
                    lines[#lines + 1] = "|cff00ff00>|r " .. name
                end
                tsmWidgets.opInfo:SetText(table.concat(lines, "\n"))
            else
                tsmWidgets.opInfo:SetText("|cffff8800No Auctioning operations found in this profile.|r")
            end
        else
            tsmWidgets.opInfo:SetText("|cff888888Enable TSM and select a profile to see operations.|r")
        end
    end

    -- EditBoxes
    if tsmWidgets.fallback then
        tsmWidgets.fallback:SetText(ns.db.settings.tsmMinPriceSource or "")
    end
    if tsmWidgets.priceSource then
        tsmWidgets.priceSource:SetText(ns.db.settings.tsmPriceSource or "")
    end

    -- Checkboxes
    if tsmWidgets.showColumns then
        tsmWidgets.showColumns:SetChecked(ns.db.settings.tsmShowColumns)
    end
    if tsmWidgets.autoUpdate then
        tsmWidgets.autoUpdate:SetChecked(ns.db.settings.tsmAutoUpdatePrice)
    end

    -- Age slider
    if tsmWidgets.ageSlider then
        local hours = math.floor((ns.db.settings.tsmPriceMaxAge or 3600) / 3600 + 0.5)
        tsmWidgets.ageSlider:SetValue(hours)
        if tsmWidgets.ageLabel then
            tsmWidgets.ageLabel:SetText(hours == 0 and "Always" or (hours .. "h"))
        end
    end
end
