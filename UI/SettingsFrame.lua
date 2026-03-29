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
-- Section Header
--------------------------

local function CreateSectionHeader(parent, yOffset, text)
    -- Divider line above
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    divider:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)
    divider:SetColorTexture(0.35, 0.35, 0.45, 0.6)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset - 6)
    label:SetTextColor(0.9, 0.8, 0.3)
    label:SetText(text)

    return 22 -- total height consumed
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

--------------------------
-- Main Panel
--------------------------

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

    scroll:SetScript("OnSizeChanged", function(sf, w)
        content:SetWidth(w)
    end)

    local y = -6

    ------------------------------------------------
    -- Section: Scanning & Automation
    ------------------------------------------------
    y = y - CreateSectionHeader(content, y, "Scanning & Automation")

    settingsWidgets.autoScan, h = CreateSettingsCheckbox(content, y,
        "Auto-scan bags on login",
        "Automatically scan your character's bags when you log in so FlipQueue knows what you're carrying.",
        "autoScan")
    y = y - h - ITEM_SPACING

    -- Auto-pull / auto-deposit / auto-deposit-all moved to Characters page
    -- (per-character settings with global defaults)

    settingsWidgets.autoGold, h = CreateSettingsCheckbox(content, y,
        "Auto-withdraw gold for AH fees",
        "When you open the bank, withdraw enough gold from your warband bank to cover estimated AH listing fees and buy task costs.",
        "autoWithdrawGold")
    y = y - h - ITEM_SPACING

    -- Max withdrawal gold input
    do
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
        row:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(52)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Max withdrawal per visit (gold)")

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
        descText:SetText("Maximum gold to withdraw per bank visit. 0 = no limit.")

        settingsWidgets.maxWithdrawBox = box
    end
    y = y - 52 - ITEM_SPACING

    settingsWidgets.autoDepositGold, h = CreateSettingsCheckbox(content, y,
        "Auto-deposit earnings to warbank",
        "When you open the bank, deposit excess gold back to the warbank. Keeps enough for AH fees plus a configurable buffer.",
        "autoDepositGold")
    y = y - h - ITEM_SPACING

    -- Gold buffer input
    do
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
        row:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(52)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Gold buffer to keep on character")

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
        descText:SetText("Extra gold (beyond AH fees) to keep on character. 0 = keep only fees.")

        settingsWidgets.goldBufferBox = box
    end
    y = y - 52 - ITEM_SPACING

    settingsWidgets.tsmAutoSkip, h = CreateSettingsCheckbox(content, y,
        "Auto-handle TSM rejections",
        "When you open the AH, automatically skip or reassign to-do items that TSM would reject (below min price). Reassigns to another character on the same realm if available, otherwise skips with reason.",
        "tsmAutoSkipRejected")
    y = y - h - ITEM_SPACING

    settingsWidgets.skipUnassigned, h = CreateSettingsCheckbox(content, y,
        "Skip deals with no character",
        "When generating a to-do list, skip deals that have no matching character on the required realm instead of creating 'new character' tasks. Useful when you only want tasks for realms you already have characters on.",
        "skipUnassigned")
    y = y - h - ITEM_SPACING

    -- Pull batch size slider
    do
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
        row:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(68)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Bank pull batch size")

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
        descText:SetText("How many items to move per batch when auto-pulling from bank. Lower values are safer but slower.")

        settingsWidgets.batchSizeSlider = slider
        settingsWidgets.batchSizeLabel = valLabel
    end
    y = y - 68 - ITEM_SPACING

    -- Default sell quantity slider
    do
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
        row:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
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
    y = y - 68 - ITEM_SPACING

    -- Sell quantity mode toggle
    do
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
        row:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
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
    y = y - 56 - ITEM_SPACING

    -- Expiry alert timer slider
    do
        local row = CreateFrame("Frame", nil, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
        row:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
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
    y = y - 68 - SECTION_SPACING

    -- Bank Tab Selection moved to Characters page (per-character config panel)

    ------------------------------------------------
    -- Section: Notifications
    ------------------------------------------------
    y = y - CreateSectionHeader(content, y, "Notifications")

    settingsWidgets.loginMsg, h = CreateSettingsCheckbox(content, y,
        "Show login message",
        "Print a chat message on login listing items to post, expired auctions to collect, and other tasks for this character.",
        "showLoginMessage")
    y = y - h - SECTION_SPACING

    ------------------------------------------------
    -- Section: Mini View
    ------------------------------------------------
    y = y - CreateSectionHeader(content, y, "Mini View")

    settingsWidgets.showMini, h = CreateSettingsCheckbox(content, y,
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
    y = y - h - ITEM_SPACING

    settingsWidgets.hideMiniCombat, h = CreateSettingsCheckbox(content, y,
        "Hide mini view in combat",
        "Automatically hide the mini overlay when you enter combat and restore it when combat ends.",
        "hideMiniInCombat")
    y = y - h - ITEM_SPACING

    settingsWidgets.showMinimap, h = CreateSettingsCheckbox(content, y,
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
    y = y - h - ITEM_SPACING

    settingsWidgets.resetMiniPos, h = CreateSettingsButton(content, y,
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
    y = y - h - SECTION_SPACING

    ------------------------------------------------
    -- Section: Data Management
    ------------------------------------------------
    y = y - CreateSectionHeader(content, y, "Data Management")

    settingsWidgets.clearInv, h = CreateSettingsButton(content, y,
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
    y = y - h - ITEM_SPACING

    settingsWidgets.clearQueue, h = CreateSettingsButton(content, y,
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
    y = y - h - ITEM_SPACING

    settingsWidgets.clearLog, h = CreateSettingsButton(content, y,
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
    y = y - h - ITEM_SPACING

    settingsWidgets.clearDNT, h = CreateSettingsButton(content, y,
        "Clear Do Not Track", "Remove all items from the Do Not Track list.", 180, function()
        if ns.db then
            wipe(ns.db.doNotTrack)
            ns:Print("Do Not Track list cleared.")
            UI:Refresh()
        end
    end)
    y = y - h - SECTION_SPACING

    ------------------------------------------------
    -- Section: Multi-Account
    ------------------------------------------------
    y = y - CreateSectionHeader(content, y, "Multi-Account")

    -- Everything in this section uses a lower container
    local lower = CreateFrame("Frame", nil, content)
    lower:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y - SECTION_SPACING)
    lower:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    settingsWidgets.lowerSection = lower
    settingsWidgets.contentFrame = content
    settingsWidgets.baseY = math.abs(y) -- y consumed above this point

    local ly = 0

    -- Real-Time Sync
    local syncLabel = lower:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncLabel:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    syncLabel:SetTextColor(0.9, 0.8, 0.5)
    syncLabel:SetText("Real-Time Sync")
    ly = ly - 18

    -- Sync status display
    settingsWidgets.syncStatusText = lower:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsWidgets.syncStatusText:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    settingsWidgets.syncStatusText:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    settingsWidgets.syncStatusText:SetJustifyH("LEFT")
    settingsWidgets.syncStatusText:SetWordWrap(true)
    ly = ly - 28

    -- Link panel: editbox + button
    local linkLabel = lower:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    linkLabel:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    linkLabel:SetText("Partner character (Name-Realm):")
    ly = ly - 16

    settingsWidgets.linkCharBox = CreateFrame("EditBox", nil, lower, "InputBoxTemplate")
    settingsWidgets.linkCharBox:SetSize(200, 20)
    settingsWidgets.linkCharBox:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN + 4, ly)
    settingsWidgets.linkCharBox:SetAutoFocus(false)
    settingsWidgets.linkCharBox:SetMaxLetters(60)
    settingsWidgets.linkCharBox:SetText("")
    settingsWidgets.linkCharBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    settingsWidgets.linkCharBox:SetScript("OnEnterPressed", function(self)
        local target = self:GetText():match("^%s*(.-)%s*$")
        if target ~= "" and ns.Sync then
            ns.Sync:RequestPair(target)
        end
        self:ClearFocus()
    end)
    ly = ly - 24

    -- Send Link Request button
    do
        local btn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        btn:SetSize(150, 24)
        btn:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
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
        btn.text:SetText("Send Link Request")
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.25, 0.25, 0.35, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.15, 0.2, 1) end)
        btn:SetScript("OnClick", function()
            local target = settingsWidgets.linkCharBox and settingsWidgets.linkCharBox:GetText():match("^%s*(.-)%s*$")
            if target and target ~= "" and ns.Sync then
                ns.Sync:RequestPair(target)
            else
                ns:Print(ns.COLORS.RED .. "Enter a character name first.|r")
            end
        end)
        settingsWidgets.linkBtn = btn
    end
    ly = ly - 28 - ITEM_SPACING

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
                local from = ns.Sync:GetPendingPairFrom()
                if from then ns.Sync:AcceptPair(from) end
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
            if ns.Sync then ns.Sync:DenyPair() end
            UI:RefreshSettings()
        end)
        settingsWidgets.pairDenyBtn = denyBtn
    end
    ly = ly - 26 - ITEM_SPACING

    -- Unlink + Force Re-sync buttons
    do
        local unlinkBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        unlinkBtn:SetSize(90, 22)
        unlinkBtn:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        unlinkBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        unlinkBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        unlinkBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        unlinkBtn.text = unlinkBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        unlinkBtn.text:SetPoint("CENTER")
        unlinkBtn.text:SetText("Unlink")
        unlinkBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.25, 0.25, 0.35, 1) end)
        unlinkBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.15, 0.2, 1) end)
        unlinkBtn:SetScript("OnClick", function()
            if ns.Sync then ns.Sync:Unlink() end
            UI:RefreshSettings()
        end)
        settingsWidgets.unlinkBtn = unlinkBtn

        local resyncBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        resyncBtn:SetSize(110, 22)
        resyncBtn:SetPoint("LEFT", unlinkBtn, "RIGHT", 6, 0)
        resyncBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        resyncBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        resyncBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        resyncBtn.text = resyncBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        resyncBtn.text:SetPoint("CENTER")
        resyncBtn.text:SetText("Force Re-sync")
        resyncBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.25, 0.25, 0.35, 1) end)
        resyncBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.15, 0.2, 1) end)
        resyncBtn:SetScript("OnClick", function()
            if ns.Sync and ns.Sync:IsLinked() then
                ns.Sync:RequestFullSync()
                ns:Print("Full sync requested.")
            end
        end)
        settingsWidgets.resyncBtn = resyncBtn
    end
    ly = ly - 26 - SECTION_SPACING

    -- External Accounts (manual entry)
    local extSubLabel = lower:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    extSubLabel:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    extSubLabel:SetTextColor(0.9, 0.8, 0.5)
    extSubLabel:SetText("External Accounts")
    ly = ly - 18

    local extDesc = lower:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    extDesc:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    extDesc:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    extDesc:SetJustifyH("LEFT")
    extDesc:SetWordWrap(true)
    extDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    extDesc:SetText("Manually add realms from other WoW accounts. These realms will be excluded from 'Create char' suggestions in Next Steps.")
    ly = ly - 32

    -- Label input
    local lblLabel = lower:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblLabel:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    lblLabel:SetText("Account label:")
    ly = ly - 16

    local lblBox = CreateFrame("EditBox", nil, lower, "InputBoxTemplate")
    lblBox:SetSize(170, 20)
    lblBox:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN + 4, ly)
    lblBox:SetAutoFocus(false)
    lblBox:SetMaxLetters(30)
    lblBox:SetText("")
    ly = ly - 24

    -- Realms input
    local rlmLabel = lower:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rlmLabel:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    rlmLabel:SetText("Realms (comma-separated):")
    ly = ly - 16

    local rlmBox = CreateFrame("EditBox", nil, lower, "InputBoxTemplate")
    rlmBox:SetSize(280, 20)
    rlmBox:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN + 4, ly)
    rlmBox:SetAutoFocus(false)
    rlmBox:SetMaxLetters(200)
    rlmBox:SetText("")
    ly = ly - 26

    -- Add button
    do
        local row = CreateFrame("Frame", nil, lower)
        row:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        row:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(28)

        local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
        btn:SetSize(160, 24)
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
        btn.text:SetText("Add External Account")
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.25, 0.25, 0.35, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.15, 0.2, 1) end)
        btn:SetScript("OnClick", function()
            if not ns.db then return end
            local label = lblBox:GetText():match("^%s*(.-)%s*$")
            local realmsStr = rlmBox:GetText():match("^%s*(.-)%s*$")
            if label == "" or realmsStr == "" then
                ns:Print(ns.COLORS.RED .. "Both label and realms are required.|r")
                return
            end
            local realms = {}
            for r in realmsStr:gmatch("([^,]+)") do
                local trimmed = r:match("^%s*(.-)%s*$")
                if trimmed ~= "" then
                    table.insert(realms, trimmed)
                end
            end
            if #realms == 0 then
                ns:Print(ns.COLORS.RED .. "No valid realm names found.|r")
                return
            end
            table.insert(ns.db.accounts.external, {label = label, realms = realms})
            ns:Print(ns.COLORS.GREEN .. "Added external account:|r " .. label .. " (" .. #realms .. " realms)")
            lblBox:SetText("")
            rlmBox:SetText("")
            UI:RefreshSettings()
            UI:Refresh()
        end)
    end
    ly = ly - 28 - ITEM_SPACING

    -- List existing external accounts
    settingsWidgets.extAccountList = lower:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsWidgets.extAccountList:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    settingsWidgets.extAccountList:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    settingsWidgets.extAccountList:SetJustifyH("LEFT")
    settingsWidgets.extAccountList:SetWordWrap(true)
    ly = ly - 20

    do
        local row = CreateFrame("Frame", nil, lower)
        row:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        row:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(28)

        local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
        btn:SetSize(160, 24)
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
        btn.text:SetText("Remove Last Account")
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.25, 0.25, 0.35, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.15, 0.2, 1) end)
        btn:SetScript("OnClick", function()
            if ns.db and #ns.db.accounts.external > 0 then
                local removed = table.remove(ns.db.accounts.external)
                ns:Print("Removed external account: " .. removed.label)
                UI:RefreshSettings()
                UI:Refresh()
            end
        end)
    end
    ly = ly - 28 - SECTION_SPACING

    ------------------------------------------------
    -- Tutorial
    ------------------------------------------------
    -- Divider
    local tutDivider = lower:CreateTexture(nil, "ARTWORK")
    tutDivider:SetHeight(1)
    tutDivider:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    tutDivider:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    tutDivider:SetColorTexture(0.35, 0.35, 0.45, 0.6)
    local tutHeader = lower:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tutHeader:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly - 6)
    tutHeader:SetTextColor(0.9, 0.8, 0.3)
    tutHeader:SetText("Tutorial")
    ly = ly - 22 - ITEM_SPACING

    local tutorialBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
    tutorialBtn:SetSize(180, 26)
    tutorialBtn:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
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

    local tutDesc = lower:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tutDesc:SetPoint("LEFT", tutorialBtn, "RIGHT", 8, 0)
    tutDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    tutDesc:SetText("Walk through the first-time setup again")
    ly = ly - 30 - SECTION_SPACING

    ------------------------------------------------
    -- Credits
    ------------------------------------------------
    local credDivider = lower:CreateTexture(nil, "ARTWORK")
    credDivider:SetHeight(1)
    credDivider:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    credDivider:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    credDivider:SetColorTexture(0.35, 0.35, 0.45, 0.6)
    local credHeader = lower:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    credHeader:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly - 6)
    credHeader:SetTextColor(0.9, 0.8, 0.3)
    credHeader:SetText("Credits")
    ly = ly - 22

    -- Banner logo
    local banner = lower:CreateTexture(nil, "ARTWORK")
    banner:SetSize(340, 86)
    banner:SetPoint("TOP", lower, "TOP", 0, ly)
    banner:SetTexture("Interface\\AddOns\\flipqueue\\Art\\flipqueue-banner")
    ly = ly - 92

    -- Version
    local ver = lower:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ver:SetPoint("TOP", lower, "TOP", 0, ly)
    ver:SetTextColor(0.8, 0.75, 0.5)
    ver:SetText("v" .. ns.VERSION)
    ly = ly - 20

    -- Credits text
    local function AddCreditLine(parent, yOff, label, value)
        local line = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOP", parent, "TOP", 0, yOff)
        line:SetJustifyH("CENTER")
        line:SetText(ns.COLORS.YELLOW .. label .. "|r  " .. value)
        return 14
    end

    ly = ly - 4
    ly = ly - AddCreditLine(lower, ly, "Developed by", "Gezmodean & Claude")
    ly = ly - 4
    ly = ly - AddCreditLine(lower, ly, "Additional support by", "Berick")
    ly = ly - 4
    ly = ly - AddCreditLine(lower, ly, "Additional testing by", "KittyKiller, Niduin, Artificer Skills")
    ly = ly - 12

    local thanksLabel = lower:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thanksLabel:SetPoint("TOP", lower, "TOP", 0, ly)
    thanksLabel:SetJustifyH("CENTER")
    thanksLabel:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    thanksLabel:SetText("Special thanks to")
    ly = ly - 14

    local thanksNames = lower:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    thanksNames:SetPoint("TOP", lower, "TOP", 0, ly)
    thanksNames:SetJustifyH("CENTER")
    thanksNames:SetText("FlippingPal  |  TradeSkillMaster  |  Auctionator  |  Epos")
    ly = ly - 24

    lower:SetHeight(math.abs(ly) + 10)
    settingsWidgets.lowerSectionHeight = math.abs(ly) + 10

    -- Content height: upper fixed section + SECTION_SPACING + lower container
    content:SetHeight(math.abs(y) + SECTION_SPACING + math.abs(ly) + 40)

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
    if settingsWidgets.goldBufferBox then
        local val = ns.db.settings.goldBuffer or 0
        settingsWidgets.goldBufferBox:SetText(tostring(val))
    end
    if settingsWidgets.tsmAutoSkip then
        settingsWidgets.tsmAutoSkip:SetChecked(ns.db.settings.tsmAutoSkipRejected)
    end
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

    -- Sync status
    if settingsWidgets.syncStatusText then
        local syncText
        if ns.Sync and ns.Sync:IsLinked() then
            local partner = ns.db.sync.partner.characterName or "?"
            local statusColor = ns.Sync:IsConnected() and ns.COLORS.GREEN or ns.COLORS.RED
            local statusLabel = ns.Sync:IsConnected() and "Online" or "Offline"
            syncText = "Linked to " .. ns.COLORS.CYAN .. partner .. "|r (" .. statusColor .. statusLabel .. "|r)"
            local pending = ns.Sync:GetPendingCount()
            if pending > 0 then
                syncText = syncText .. "\n" .. ns.COLORS.YELLOW .. pending .. " changes queued|r"
            end
            local lastSync = ns.db.sync.partner.lastFullSync or 0
            if lastSync > 0 then
                syncText = syncText .. "\nLast sync: " .. ns:FormatRelativeTime(lastSync)
            end
        else
            syncText = ns.COLORS.GRAY .. "Not linked. Enter a partner character name to connect.|r"
        end
        settingsWidgets.syncStatusText:SetText(syncText)
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

    -- Show/hide link vs unlink controls
    if settingsWidgets.linkBtn then
        local linked = ns.Sync and ns.Sync:IsLinked()
        settingsWidgets.linkBtn:SetShown(not linked)
        if settingsWidgets.linkCharBox then settingsWidgets.linkCharBox:SetShown(not linked) end
    end
    if settingsWidgets.unlinkBtn then
        settingsWidgets.unlinkBtn:SetShown(ns.Sync and ns.Sync:IsLinked())
    end
    if settingsWidgets.resyncBtn then
        settingsWidgets.resyncBtn:SetShown(ns.Sync and ns.Sync:IsLinked())
    end

    if settingsWidgets.extAccountList then
        if ns.db.accounts.external and #ns.db.accounts.external > 0 then
            local lines = {}
            for i, acct in ipairs(ns.db.accounts.external) do
                table.insert(lines, i .. ". " .. acct.label .. ": " .. table.concat(acct.realms, ", "))
            end
            settingsWidgets.extAccountList:SetText(table.concat(lines, "\n"))
        else
            settingsWidgets.extAccountList:SetText("|cff888888No external accounts configured.|r")
        end
    end
end

-- Legacy ShowSettings opens the main window to settings page
function UI:ShowSettings()
    self.currentPage = "settings"
    self.mainFrame:Show()
    self:Refresh()
end
