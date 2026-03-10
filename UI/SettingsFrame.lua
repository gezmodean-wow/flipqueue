-- UI/SettingsFrame.lua
-- Settings page rendered inside the main window content area
local addonName, ns = ...

local UI = ns.UI

local settingsPanel
local settingsWidgets = {}

-- Create a styled checkbox that matches the dark theme
local function CreateSettingsCheckbox(parent, yOffset, label, settingKey, tooltip)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(26)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", -8, 0)

    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)
    cb.text:SetText(label)
    cb.text:SetFontObject("GameFontNormalSmall")
    cb:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.settings[settingKey] = self:GetChecked()
        end
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    cb.settingKey = settingKey
    return cb
end

local function CreateSectionLabel(parent, yOffset, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOffset)
    label:SetTextColor(0.9, 0.8, 0.3)
    label:SetText(text)
    return label
end

local function CreateSettingsButton(parent, yOffset, label, width, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
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
        self:SetBackdropColor(0.2, 0.2, 0.3, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
    end)
    return btn
end

function UI:CreateSettingsPanel(parent)
    if settingsPanel then return settingsPanel end

    -- Scrollable settings container
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(scroll:GetWidth())
    content:SetHeight(500)
    scroll:SetScrollChild(content)

    scroll:SetScript("OnSizeChanged", function(sf, w)
        content:SetWidth(w)
    end)

    local y = -10

    -- Section: Scanning
    CreateSectionLabel(content, y, "Scanning")
    y = y - 22

    settingsWidgets.autoScan = CreateSettingsCheckbox(content, y,
        "Auto-scan bags on login", "autoScan",
        "Automatically scan your character's bags when you log in.")
    y = y - 26

    settingsWidgets.autoPull = CreateSettingsCheckbox(content, y,
        "Auto-pull queued items from bank", "autoPullBank",
        "When you open the bank, automatically move queued items to your bags.")
    y = y - 36

    -- Section: Notifications
    CreateSectionLabel(content, y, "Notifications")
    y = y - 22

    settingsWidgets.loginMsg = CreateSettingsCheckbox(content, y,
        "Show login message", "showLoginMessage",
        "Show a chat message on login if there are items to post on this character.")
    y = y - 36

    -- Section: Mini View
    CreateSectionLabel(content, y, "Mini View")
    y = y - 22

    settingsWidgets.showMini = CreateSettingsCheckbox(content, y,
        "Show mini overlay", "showMini",
        "Show a compact overlay with current-character tasks. Persists across sessions.")
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
    y = y - 28

    settingsWidgets.showMinimap = CreateSettingsCheckbox(content, y,
        "Show minimap icon", "showMinimap",
        "Show the FlipQueue icon on the minimap border.")
    settingsWidgets.showMinimap:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.settings.showMinimap = self:GetChecked()
            if self:GetChecked() then
                UI:ShowMinimapButton()
            else
                UI:HideMinimapButton()
            end
        end
    end)
    y = y - 28

    settingsWidgets.resetMiniPos = CreateSettingsButton(content, y, "Reset Mini Position", 160, function()
        if ns.db then
            ns.db.settings.miniPos = nil
            if UI.miniFrame and UI.miniFrame:IsShown() then
                UI.miniFrame:ClearAllPoints()
                UI.miniFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200)
            end
            ns:Print("Mini view position reset.")
        end
    end)
    y = y - 38

    -- Section: Data Management
    CreateSectionLabel(content, y, "Data Management")
    y = y - 24

    settingsWidgets.clearInv = CreateSettingsButton(content, y, "Clear All Inventory Data", 190, function()
        StaticPopupDialogs["FLIPQUEUE_CLEAR_INVENTORY"] = {
            text = "Clear all saved inventory data? You will need to rescan on each character.",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                if ns.db then
                    wipe(ns.db.inventory)
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
    y = y - 28

    settingsWidgets.clearQueue = CreateSettingsButton(content, y, "Clear Entire Queue", 190, function()
        StaticPopupDialogs["FLIPQUEUE_CLEAR_ALL_SETTINGS"] = {
            text = "Clear ALL items from the FlipQueue?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                ns.Queue:Clear()
                ns:Print("Queue cleared.")
                UI:Refresh()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("FLIPQUEUE_CLEAR_ALL_SETTINGS")
    end)
    y = y - 28

    settingsWidgets.clearLog = CreateSettingsButton(content, y, "Clear Posted Items Log", 190, function()
        StaticPopupDialogs["FLIPQUEUE_CLEAR_LOG_SETTINGS"] = {
            text = "Clear ALL items from the posted log?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                ns.Queue:ClearLog()
                ns:Print("Log cleared.")
                UI:Refresh()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("FLIPQUEUE_CLEAR_LOG_SETTINGS")
    end)
    y = y - 28

    settingsWidgets.clearDNT = CreateSettingsButton(content, y, "Clear Do Not Track List", 190, function()
        if ns.db then
            wipe(ns.db.doNotTrack)
            ns:Print("Do Not Track list cleared.")
            UI:Refresh()
        end
    end)
    y = y - 40

    -- Version
    local ver = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y)
    ver:SetText("FlipQueue v" .. ns.VERSION)

    content:SetHeight(math.abs(y) + 20)

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
    if settingsWidgets.autoPull then
        settingsWidgets.autoPull:SetChecked(ns.db.settings.autoPullBank)
    end
    if settingsWidgets.loginMsg then
        settingsWidgets.loginMsg:SetChecked(ns.db.settings.showLoginMessage)
    end
    if settingsWidgets.showMini then
        settingsWidgets.showMini:SetChecked(ns.db.settings.showMini)
    end
    if settingsWidgets.showMinimap then
        settingsWidgets.showMinimap:SetChecked(ns.db.settings.showMinimap ~= false)
    end
end

-- Legacy ShowSettings opens the main window to settings page
function UI:ShowSettings()
    self.currentPage = "settings"
    self.mainFrame:Show()
    self:Refresh()
end
