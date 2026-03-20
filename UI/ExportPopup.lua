-- UI/ExportPopup.lua
-- Export and import popup dialogs (modal windows over main UI)
local addonName, ns = ...

local UI = ns.UI

-- ==========================================
-- EXPORT POPUP
-- ==========================================

local exportPopup

function UI:ShowExportPopup(text, statusMsg)
    if not exportPopup then
        exportPopup = CreateFrame("Frame", "FlipQueueExportPopup", UIParent, "BackdropTemplate")
        exportPopup:SetSize(500, 350)
        exportPopup:SetPoint("CENTER")
        exportPopup:SetMovable(true)
        exportPopup:EnableMouse(true)
        exportPopup:RegisterForDrag("LeftButton")
        exportPopup:SetScript("OnDragStart", exportPopup.StartMoving)
        exportPopup:SetScript("OnDragStop", exportPopup.StopMovingOrSizing)
        exportPopup:SetFrameStrata("DIALOG")
        exportPopup:SetClampedToScreen(true)
        exportPopup:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4},
        })
        exportPopup:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        exportPopup:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)

        -- Title bar
        local bar = CreateFrame("Frame", nil, exportPopup)
        bar:SetHeight(24)
        bar:SetPoint("TOPLEFT", exportPopup, "TOPLEFT", 4, -4)
        bar:SetPoint("TOPRIGHT", exportPopup, "TOPRIGHT", -4, -4)
        local barBg = bar:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        barBg:SetColorTexture(0.12, 0.12, 0.18, 1)

        local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", bar, "LEFT", 8, 0)
        title:SetText(ns.COLORS.YELLOW .. "Export" .. ns.COLORS.RESET)

        local closeBtn = CreateFrame("Button", nil, bar)
        closeBtn:SetSize(18, 18)
        closeBtn:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
        closeBtn:GetHighlightTexture():SetAlpha(0.3)
        closeBtn:SetScript("OnClick", function() exportPopup:Hide() end)

        -- Edit box
        local scroll = CreateFrame("ScrollFrame", nil, exportPopup, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
        scroll:SetPoint("BOTTOMRIGHT", exportPopup, "BOTTOMRIGHT", -26, 30)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(scroll:GetWidth() or 450)
        scroll:SetScrollChild(edit)
        scroll:SetScript("OnSizeChanged", function(sf, w) edit:SetWidth(w) end)
        edit:SetScript("OnEscapePressed", function() exportPopup:Hide() end)
        exportPopup._edit = edit

        -- Status text
        local status = exportPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        status:SetPoint("LEFT", exportPopup, "BOTTOMLEFT", 8, 17)
        status:SetTextColor(0.5, 0.5, 0.5)
        exportPopup._status = status

        exportPopup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
                self:SetPropagateKeyboardInput(false)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
    end

    exportPopup._edit:SetText(text or "")
    exportPopup._edit:HighlightText()
    exportPopup._edit:SetFocus(true)
    exportPopup._status:SetText(statusMsg and (ns.COLORS.GREEN .. statusMsg .. "|r") or "")
    exportPopup:Show()
end

-- ==========================================
-- IMPORT POPUP (for generator page)
-- ==========================================

local importPopup

function UI:ShowImportPopup(onImportDone)
    if not importPopup then
        importPopup = CreateFrame("Frame", "FlipQueueImportPopup", UIParent, "BackdropTemplate")
        importPopup:SetSize(500, 350)
        importPopup:SetPoint("CENTER")
        importPopup:SetMovable(true)
        importPopup:EnableMouse(true)
        importPopup:RegisterForDrag("LeftButton")
        importPopup:SetScript("OnDragStart", importPopup.StartMoving)
        importPopup:SetScript("OnDragStop", importPopup.StopMovingOrSizing)
        importPopup:SetFrameStrata("DIALOG")
        importPopup:SetClampedToScreen(true)
        importPopup:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4},
        })
        importPopup:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        importPopup:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)

        -- Title bar
        local bar = CreateFrame("Frame", nil, importPopup)
        bar:SetHeight(24)
        bar:SetPoint("TOPLEFT", importPopup, "TOPLEFT", 4, -4)
        bar:SetPoint("TOPRIGHT", importPopup, "TOPRIGHT", -4, -4)
        local barBg = bar:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        barBg:SetColorTexture(0.12, 0.12, 0.18, 1)

        local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", bar, "LEFT", 8, 0)
        title:SetText(ns.COLORS.YELLOW .. "Import FP Data" .. ns.COLORS.RESET)

        local closeBtn = CreateFrame("Button", nil, bar)
        closeBtn:SetSize(18, 18)
        closeBtn:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
        closeBtn:GetHighlightTexture():SetAlpha(0.3)
        closeBtn:SetScript("OnClick", function() importPopup:Hide() end)

        -- Instructions
        local instr = importPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        instr:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 4, -6)
        instr:SetText("Paste FlippingPal data below, then click Import:")
        instr:SetTextColor(0.7, 0.7, 0.7)

        -- Edit box
        local scroll = CreateFrame("ScrollFrame", nil, importPopup, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -22)
        scroll:SetPoint("BOTTOMRIGHT", importPopup, "BOTTOMRIGHT", -26, 36)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(0)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(scroll:GetWidth() or 450)
        scroll:SetScrollChild(edit)
        scroll:SetScript("OnSizeChanged", function(sf, w) edit:SetWidth(w) end)
        edit:SetScript("OnEscapePressed", function() importPopup:Hide() end)
        importPopup._edit = edit

        -- Status text
        local status = importPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        status:SetPoint("LEFT", importPopup, "BOTTOMLEFT", 8, 20)
        status:SetTextColor(0.5, 0.5, 0.5)
        importPopup._status = status

        -- Import button
        local importBtn = CreateFrame("Button", nil, importPopup, "BackdropTemplate")
        importBtn:SetSize(80, 24)
        importBtn:SetPoint("BOTTOMRIGHT", importPopup, "BOTTOMRIGHT", -8, 4)
        importBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        importBtn:SetBackdropColor(0.15, 0.3, 0.15, 1)
        importBtn:SetBackdropBorderColor(0.3, 0.5, 0.3, 0.8)
        local importBtnText = importBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        importBtnText:SetPoint("CENTER")
        importBtnText:SetText("Import")
        importBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
        importBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.3, 0.15, 1) end)
        importPopup._importBtn = importBtn

        importPopup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
                self:SetPropagateKeyboardInput(false)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
    end

    -- Reset state
    importPopup._edit:SetText("")
    importPopup._status:SetText("")
    importPopup._onImportDone = onImportDone

    -- Wire import button
    importPopup._importBtn:SetScript("OnClick", function()
        local text = importPopup._edit:GetText()
        if text and text ~= "" then
            local items = ns.Import:Parse(text)
            if #items > 0 then
                local added = ns.Import:Save(items)
                ns:Print("Imported " .. added .. " new items (" .. #items .. " parsed, duplicates merged).")
                importPopup:Hide()
                if importPopup._onImportDone then
                    importPopup._onImportDone(added)
                end
            else
                importPopup._status:SetText(ns.COLORS.RED .. "No items found in pasted data.|r")
            end
        end
    end)

    importPopup._edit:SetFocus(true)
    importPopup:Show()
end
