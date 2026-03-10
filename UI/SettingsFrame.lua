-- UI/SettingsFrame.lua
-- Settings panel for FlipQueue
local addonName, ns = ...

local UI = ns.UI

local settingsFrame

local function CreateCheckbox(parent, yOffset, label, settingKey, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    cb.text:SetText(label)
    cb.text:SetFontObject("GameFontNormal")
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

function UI:ShowSettings()
    if not settingsFrame then
        settingsFrame = CreateFrame("Frame", "FlipQueueSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
        settingsFrame:SetSize(380, 380)
        settingsFrame:SetPoint("CENTER")
        settingsFrame:SetMovable(true)
        settingsFrame:EnableMouse(true)
        settingsFrame:RegisterForDrag("LeftButton")
        settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
        settingsFrame:SetScript("OnDragStop", settingsFrame.StopMovingOrSizing)
        settingsFrame:SetFrameStrata("DIALOG")

        settingsFrame.title = settingsFrame:CreateFontString(nil, "OVERLAY")
        settingsFrame.title:SetFontObject("GameFontHighlight")
        settingsFrame.title:SetPoint("LEFT", settingsFrame.TitleBg, "LEFT", 5, 0)
        settingsFrame.title:SetText("FlipQueue - Settings")

        -- Section: Scanning
        local scanHeader = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        scanHeader:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 15, -35)
        scanHeader:SetText("Scanning")

        settingsFrame.autoScanCB = CreateCheckbox(settingsFrame, -55,
            "Auto-scan bags on login",
            "autoScan",
            "Automatically scan your character's bags when you log in.")

        settingsFrame.autoPullCB = CreateCheckbox(settingsFrame, -80,
            "Auto-pull queued items from bank",
            "autoPullBank",
            "When you open the bank, automatically move queued items to your bags.")

        -- Section: Notifications
        local notifHeader = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        notifHeader:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 15, -115)
        notifHeader:SetText("Notifications")

        settingsFrame.loginMsgCB = CreateCheckbox(settingsFrame, -135,
            "Show login message",
            "showLoginMessage",
            "Show a chat message on login if there are items to post on this character.")

        -- Section: Mini View
        local miniHeader = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        miniHeader:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 15, -170)
        miniHeader:SetText("Mini View")

        settingsFrame.showMiniCB = CreateCheckbox(settingsFrame, -190,
            "Show mini overlay",
            "showMini",
            "Show a compact overlay with current-character tasks. Persists across sessions.")

        settingsFrame.showMiniCB:SetScript("OnClick", function(self)
            if ns.db then
                ns.db.settings.showMini = self:GetChecked()
                if self:GetChecked() then
                    UI:ShowMini()
                else
                    UI:HideMini()
                end
            end
        end)

        -- Section: Display
        local displayHeader = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        displayHeader:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 15, -225)
        displayHeader:SetText("Display")

        -- Sort mode dropdown (simple toggle button)
        local sortLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sortLabel:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 15, -250)
        sortLabel:SetText("Default sort mode:")

        settingsFrame.sortBtn = CreateFrame("Button", nil, settingsFrame, "GameMenuButtonTemplate")
        settingsFrame.sortBtn:SetSize(100, 22)
        settingsFrame.sortBtn:SetPoint("LEFT", sortLabel, "RIGHT", 8, 0)
        settingsFrame.sortBtn:SetNormalFontObject("GameFontNormalSmall")
        settingsFrame.sortBtn:SetScript("OnClick", function()
            if ns.db then
                ns.db.settings.sortMode = ns.db.settings.sortMode == "realm" and "name" or "realm"
                UI:RefreshSettings()
                UI:Refresh()
            end
        end)

        -- Reset mini position button
        local resetPosBtn = CreateFrame("Button", nil, settingsFrame, "GameMenuButtonTemplate")
        resetPosBtn:SetSize(160, 24)
        resetPosBtn:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 15, -285)
        resetPosBtn:SetText("Reset Mini Position")
        resetPosBtn:SetNormalFontObject("GameFontNormalSmall")
        resetPosBtn:SetScript("OnClick", function()
            if ns.db then
                ns.db.settings.miniPos = nil
                if UI.miniFrame:IsShown() then
                    UI.miniFrame:ClearAllPoints()
                    UI.miniFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200)
                end
                ns:Print("Mini view position reset.")
            end
        end)

        -- Clear inventory data button
        local clearInvBtn = CreateFrame("Button", nil, settingsFrame, "GameMenuButtonTemplate")
        clearInvBtn:SetSize(160, 24)
        clearInvBtn:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 15, -315)
        clearInvBtn:SetText("Clear All Inventory Data")
        clearInvBtn:SetNormalFontObject("GameFontNormalSmall")
        clearInvBtn:SetScript("OnClick", function()
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

        -- Version info
        local versionText = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        versionText:SetPoint("BOTTOMRIGHT", settingsFrame, "BOTTOMRIGHT", -10, 10)
        versionText:SetText("FlipQueue v" .. ns.VERSION)
    end

    settingsFrame:Show()
    self:RefreshSettings()
end

function UI:RefreshSettings()
    if not settingsFrame or not settingsFrame:IsShown() then return end
    if not ns.db then return end

    settingsFrame.autoScanCB:SetChecked(ns.db.settings.autoScan)
    settingsFrame.autoPullCB:SetChecked(ns.db.settings.autoPullBank)
    settingsFrame.loginMsgCB:SetChecked(ns.db.settings.showLoginMessage)
    settingsFrame.showMiniCB:SetChecked(ns.db.settings.showMini)
    settingsFrame.sortBtn:SetText(ns.db.settings.sortMode == "realm" and "By Realm" or "By Name")
end
