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
    content:SetHeight(800)
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

    settingsWidgets.tsmAutoSkip, h = CreateSettingsCheckbox(content, y,
        "Auto-handle TSM rejections",
        "When you open the AH, automatically skip or reassign to-do items that TSM would reject (below min price). Reassigns to another character on the same realm if available, otherwise skips with reason.",
        "tsmAutoSkipRejected")
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

    local extDesc = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    extDesc:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    extDesc:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    extDesc:SetJustifyH("LEFT")
    extDesc:SetWordWrap(true)
    extDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    extDesc:SetText("Add realms from other WoW accounts that share AH access via connected realms. These realms will be excluded from 'Create char' suggestions in Next Steps.")
    y = y - 32

    -- Label input
    local lblLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblLabel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    lblLabel:SetText("Account label:")
    y = y - 16

    local lblBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    lblBox:SetSize(170, 20)
    lblBox:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    lblBox:SetAutoFocus(false)
    lblBox:SetMaxLetters(30)
    lblBox:SetText("")
    y = y - 24

    -- Realms input
    local rlmLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rlmLabel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    rlmLabel:SetText("Realms (comma-separated):")
    y = y - 16

    local rlmBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    rlmBox:SetSize(280, 20)
    rlmBox:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 4, y)
    rlmBox:SetAutoFocus(false)
    rlmBox:SetMaxLetters(200)
    rlmBox:SetText("")
    y = y - 26

    -- Add button
    local addAcctBtn
    addAcctBtn, h = CreateSettingsButton(content, y, "Add External Account", "", 160, function()
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
    y = y - h - ITEM_SPACING

    -- List existing external accounts
    settingsWidgets.extAccountList = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsWidgets.extAccountList:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    settingsWidgets.extAccountList:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    settingsWidgets.extAccountList:SetJustifyH("LEFT")
    settingsWidgets.extAccountList:SetWordWrap(true)
    y = y - 20

    settingsWidgets.removeExtBtn, h = CreateSettingsButton(content, y,
        "Remove Last Account", "", 160, function()
        if ns.db and #ns.db.accounts.external > 0 then
            local removed = table.remove(ns.db.accounts.external)
            ns:Print("Removed external account: " .. removed.label)
            UI:RefreshSettings()
            UI:Refresh()
        end
    end)
    y = y - h - SECTION_SPACING

    ------------------------------------------------
    -- Credits
    ------------------------------------------------
    y = y - CreateSectionHeader(content, y, "Tutorial")
    y = y - ITEM_SPACING

    local tutorialBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    tutorialBtn:SetSize(180, 26)
    tutorialBtn:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
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

    local tutDesc = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tutDesc:SetPoint("LEFT", tutorialBtn, "RIGHT", 8, 0)
    tutDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    tutDesc:SetText("Walk through the first-time setup again")
    y = y - 30 - SECTION_SPACING

    y = y - CreateSectionHeader(content, y, "Credits")

    -- Banner logo
    local banner = content:CreateTexture(nil, "ARTWORK")
    banner:SetSize(340, 86)
    banner:SetPoint("TOP", content, "TOP", 0, y)
    banner:SetTexture("Interface\\AddOns\\flipqueue\\Art\\flipqueue-banner")
    y = y - 92

    -- Version
    local ver = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ver:SetPoint("TOP", content, "TOP", 0, y)
    ver:SetTextColor(0.8, 0.75, 0.5)
    ver:SetText("v" .. ns.VERSION)
    y = y - 20

    -- Credits text
    local function AddCreditLine(yOff, label, value)
        local line = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOP", content, "TOP", 0, yOff)
        line:SetJustifyH("CENTER")
        line:SetText(ns.COLORS.YELLOW .. label .. "|r  " .. value)
        return 14
    end

    y = y - 4
    y = y - AddCreditLine(y, "Developed by", "Gezmodean & Claude")
    y = y - 4
    y = y - AddCreditLine(y, "Additional support by", "Berick")
    y = y - 4
    y = y - AddCreditLine(y, "Additional testing by", "KittyKiller, Niduin, Artificer Skills")
    y = y - 12

    local thanksLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thanksLabel:SetPoint("TOP", content, "TOP", 0, y)
    thanksLabel:SetJustifyH("CENTER")
    thanksLabel:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    thanksLabel:SetText("Special thanks to")
    y = y - 14

    local thanksNames = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    thanksNames:SetPoint("TOP", content, "TOP", 0, y)
    thanksNames:SetJustifyH("CENTER")
    thanksNames:SetText("FlippingPal  |  TradeSkillMaster  |  Auctionator  |  Epos")
    y = y - 24

    content:SetHeight(math.abs(y) + 10)

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
