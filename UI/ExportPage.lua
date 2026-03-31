-- UI/ExportPage.lua
-- Export page: format/filter toggles, TSM group tree, Auctionator list, edit box
local addonName, ns = ...

local UI = ns.UI
local tableContainer = UI.tableContainer

-- ==========================================
-- EXPORT PAGE FRAME CREATION
-- ==========================================

local exportPage = CreateFrame("Frame", nil, tableContainer)
exportPage:SetAllPoints()
exportPage:Hide()

-- Format toggle row
local exportFormatLabel = exportPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
exportFormatLabel:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -6)
exportFormatLabel:SetText("Format:")
exportFormatLabel:SetTextColor(0.6, 0.6, 0.6)

local function CreateExportToggle(label, parent)
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

local fmtCSVBtn = CreateExportToggle("FP CSV", exportPage)
fmtCSVBtn:SetPoint("LEFT", exportFormatLabel, "RIGHT", 6, 0)

local fmtAAABtn = CreateExportToggle("AAA JSON", exportPage)
fmtAAABtn:SetPoint("LEFT", fmtCSVBtn, "RIGHT", 4, 0)

-- Filter toggle row
local exportFilterLabel = exportPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
exportFilterLabel:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -28)
exportFilterLabel:SetText("Filter:")
exportFilterLabel:SetTextColor(0.6, 0.6, 0.6)

local filterAllBtn = CreateExportToggle("Everything", exportPage)
filterAllBtn:SetPoint("LEFT", exportFilterLabel, "RIGHT", 6, 0)

local filterTSMBtn = CreateExportToggle("TSM Group", exportPage)
filterTSMBtn:SetPoint("LEFT", filterAllBtn, "RIGHT", 4, 0)

local filterAuctBtn = CreateExportToggle("Auctionator List", exportPage)
filterAuctBtn:SetPoint("LEFT", filterTSMBtn, "RIGHT", 4, 0)

-- Filter value input (hidden text box — repositioned dynamically in UpdateFilterButtons)
local filterValueBox = CreateFrame("EditBox", nil, exportPage, "InputBoxTemplate")
filterValueBox:SetSize(200, 20)
filterValueBox:SetAutoFocus(false)
filterValueBox:SetMaxLetters(200)
filterValueBox:Hide()
filterValueBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
filterValueBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    ns.Export:SetFilter(ns.Export:GetFilterMode(), self:GetText())
end)

local filterValueLabel = exportPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
filterValueLabel:SetPoint("LEFT", filterValueBox, "RIGHT", 6, 0)
filterValueLabel:SetText("")

-- TSM Group Tree for export filter
local exportTreeFrame = CreateFrame("Frame", nil, exportPage)
exportTreeFrame:SetPoint("RIGHT", exportPage, "RIGHT", -4, 0)
exportTreeFrame:SetHeight(150)
exportTreeFrame:Hide()

local exportGroupTree
if UI.CreateGroupTree then
    exportGroupTree = UI:CreateGroupTree(exportTreeFrame, function(path)
        filterValueBox:SetText(path or "")
        ns.Export:SetFilter("tsmgroup", path or "")
        if filterValueLabel then
            filterValueLabel:SetText(path and path ~= "" and (ns.COLORS.YELLOW .. path:gsub("`", " > ") .. "|r") or "")
        end
    end)
end

-- Auctionator list picker for export filter
local exportAuctFrame = CreateFrame("Frame", nil, exportPage)
exportAuctFrame:SetPoint("RIGHT", exportPage, "RIGHT", -4, 0)
exportAuctFrame:SetHeight(80)
exportAuctFrame:Hide()

local exportAuctScroll = CreateFrame("ScrollFrame", nil, exportAuctFrame, "UIPanelScrollFrameTemplate")
exportAuctScroll:SetPoint("TOPLEFT", exportAuctFrame, "TOPLEFT", 0, 0)
exportAuctScroll:SetPoint("BOTTOMRIGHT", exportAuctFrame, "BOTTOMRIGHT", -16, 0)

local exportAuctContent = CreateFrame("Frame", nil, exportAuctScroll)
exportAuctContent:SetWidth(1)
exportAuctContent:SetHeight(1)
exportAuctScroll:SetScrollChild(exportAuctContent)
exportAuctScroll:SetScript("OnSizeChanged", function(sf, w)
    exportAuctContent:SetWidth(w)
end)
local exportAuctRows = {}

-- AAA settings row
local aaaRow = CreateFrame("Frame", nil, exportPage)
aaaRow:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -48)
aaaRow:SetPoint("RIGHT", exportPage, "RIGHT", -8, 0)
aaaRow:SetHeight(22)
aaaRow:Hide()

local aaaDiscountLabel = aaaRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aaaDiscountLabel:SetPoint("LEFT", aaaRow, "LEFT", 0, 0)
aaaDiscountLabel:SetText("Discount %:")
aaaDiscountLabel:SetTextColor(0.6, 0.6, 0.6)

local aaaDiscountBox = CreateFrame("EditBox", nil, aaaRow, "InputBoxTemplate")
aaaDiscountBox:SetSize(40, 20)
aaaDiscountBox:SetPoint("LEFT", aaaDiscountLabel, "RIGHT", 4, 0)
aaaDiscountBox:SetAutoFocus(false)
aaaDiscountBox:SetMaxLetters(3)
aaaDiscountBox:SetText("90")
aaaDiscountBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
aaaDiscountBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    local val = tonumber(self:GetText())
    if val and val >= 0 and val <= 100 then
        ns.Export:SetAAASettings(val, nil)
    end
end)

local aaaSrcLabel = aaaRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
aaaSrcLabel:SetPoint("LEFT", aaaDiscountBox, "RIGHT", 12, 0)
aaaSrcLabel:SetText("Price source:")
aaaSrcLabel:SetTextColor(0.6, 0.6, 0.6)

local aaaSrcBox = CreateFrame("EditBox", nil, aaaRow, "InputBoxTemplate")
aaaSrcBox:SetSize(120, 20)
aaaSrcBox:SetPoint("LEFT", aaaSrcLabel, "RIGHT", 4, 0)
aaaSrcBox:SetAutoFocus(false)
aaaSrcBox:SetMaxLetters(100)
aaaSrcBox:SetText("DBMarket")
aaaSrcBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
aaaSrcBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    ns.Export:SetAAASettings(nil, self:GetText())
end)

-- Active filter text
local exportFilterStatus = exportPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
exportFilterStatus:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, -70)
exportFilterStatus:SetTextColor(0.5, 0.5, 0.5)
exportFilterStatus:SetText("")

-- Export edit box
local exportScroll = CreateFrame("ScrollFrame", "FlipQueueExportScrollInline", exportPage, "UIPanelScrollFrameTemplate")
exportScroll:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 4, -90)
exportScroll:SetPoint("BOTTOMRIGHT", exportPage, "BOTTOMRIGHT", -24, 34)

local exportEdit = CreateFrame("EditBox", "FlipQueueExportEditInline", exportScroll)
exportEdit:SetMultiLine(true)
exportEdit:SetAutoFocus(false)
exportEdit:SetFontObject("ChatFontNormal")
exportEdit:SetWidth(exportScroll:GetWidth() or 500)
exportScroll:SetScrollChild(exportEdit)
exportScroll:SetScript("OnSizeChanged", function(sf, w)
    exportEdit:SetWidth(w)
end)
exportEdit:SetScript("OnEscapePressed", function() exportEdit:ClearFocus() end)

local exportStatus = exportPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
exportStatus:SetPoint("LEFT", exportPage, "BOTTOMLEFT", 8, 17)
exportStatus:SetTextColor(0.5, 0.5, 0.5)
exportStatus:SetText("")

-- ==========================================
-- TOGGLE STATE UPDATE FUNCTIONS
-- ==========================================

local function UpdateFormatButtons()
    local fmt = ns.Export:GetFormat()
    fmtCSVBtn._active = (fmt == "csv")
    fmtAAABtn._active = (fmt == "aaa")
    fmtCSVBtn:SetBackdropColor(fmt == "csv" and 0.2 or 0.15, fmt == "csv" and 0.4 or 0.15, fmt == "csv" and 0.2 or 0.2, 1)
    fmtAAABtn:SetBackdropColor(fmt == "aaa" and 0.2 or 0.15, fmt == "aaa" and 0.4 or 0.15, fmt == "aaa" and 0.2 or 0.2, 1)

    if fmt == "aaa" then
        aaaRow:Show()
    else
        aaaRow:Hide()
    end
end

local function UpdateFilterButtons()
    local mode = ns.Export:GetFilterMode()
    filterAllBtn._active = (mode == "everything")
    filterTSMBtn._active = (mode == "tsmgroup")
    filterAuctBtn._active = (mode == "auctionator")
    filterAllBtn:SetBackdropColor(mode == "everything" and 0.2 or 0.15, mode == "everything" and 0.4 or 0.15, mode == "everything" and 0.2 or 0.2, 1)
    filterTSMBtn:SetBackdropColor(mode == "tsmgroup" and 0.2 or 0.15, mode == "tsmgroup" and 0.4 or 0.15, mode == "tsmgroup" and 0.2 or 0.2, 1)
    filterAuctBtn:SetBackdropColor(mode == "auctionator" and 0.2 or 0.15, mode == "auctionator" and 0.4 or 0.15, mode == "auctionator" and 0.2 or 0.2, 1)

    filterValueBox:Hide()
    filterValueLabel:SetText("")
    exportTreeFrame:Hide()
    exportAuctFrame:Hide()
    for _, row in ipairs(exportAuctRows) do row:Hide() end

    -- Filter config area starts below AAA row if shown, else below filter row
    local filterConfigY = aaaRow:IsShown() and -70 or -48

    if mode == "tsmgroup" then
        if exportGroupTree and ns.TSM and ns.TSM:IsEnabled() then
            local profile = ns.TSM:GetSelectedProfile()
            exportTreeFrame:ClearAllPoints()
            exportTreeFrame:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 4, filterConfigY)
            exportTreeFrame:SetPoint("RIGHT", exportPage, "RIGHT", -4, 0)
            exportTreeFrame:Show()
            if profile and exportGroupTree._profile ~= profile then
                exportGroupTree:SetProfile(profile)
            end
            local val = ns.Export:GetFilterValue()
            if val and val ~= "" then
                filterValueLabel:SetPoint("TOPLEFT", exportTreeFrame, "BOTTOMLEFT", 6, -2)
                filterValueLabel:SetText(ns.COLORS.YELLOW .. "Group: " .. val:gsub("`", " > ") .. "|r")
            end
        else
            filterValueBox:ClearAllPoints()
            filterValueBox:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 52, filterConfigY)
            filterValueBox:Show()
            filterValueBox:SetText(ns.Export:GetFilterValue())
            filterValueLabel:SetText("TSM group path")
        end
    elseif mode == "auctionator" then
        local listNames = ns:GetAuctionatorListNames()
        local auctAvailable = #listNames > 0 or type(AUCTIONATOR_SHOPPING_LISTS) == "table"

        if auctAvailable then
            exportAuctFrame:ClearAllPoints()
            exportAuctFrame:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 4, filterConfigY)
            exportAuctFrame:SetPoint("RIGHT", exportPage, "RIGHT", -4, 0)
            exportAuctFrame:Show()
            local listHeight = math.min(80, math.max(20, #listNames * 18 + 4))
            exportAuctFrame:SetHeight(listHeight)
            exportAuctContent:SetWidth(exportAuctScroll:GetWidth() or 200)

            local currentVal = ns.Export:GetFilterValue()
            local auctY = 0
            for idx, listName in ipairs(listNames) do
                local row = exportAuctRows[idx]
                if not row then
                    row = CreateFrame("Button", nil, exportAuctContent)
                    row:SetHeight(18)
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
                    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                    row.label:SetJustifyH("LEFT")
                    row:EnableMouse(true)
                    exportAuctRows[idx] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", exportAuctContent, "TOPLEFT", 0, -auctY)
                row:SetPoint("RIGHT", exportAuctContent, "RIGHT", 0, 0)

                local isSelected = (currentVal == listName)
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
                    ns.Export:SetFilter("auctionator", capturedName)
                    UpdateFilterButtons()
                end)
                row:SetScript("OnEnter", function(self)
                    if not isSelected then self.bg:SetColorTexture(1, 1, 1, 0.05) end
                end)
                row:SetScript("OnLeave", function(self)
                    if not (ns.Export:GetFilterValue() == capturedName) then self.bg:SetColorTexture(0, 0, 0, 0) end
                end)

                row:Show()
                auctY = auctY + 18
            end
            exportAuctContent:SetHeight(math.max(1, auctY))
        else
            filterValueBox:ClearAllPoints()
            filterValueBox:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 52, filterConfigY)
            filterValueBox:Show()
            filterValueBox:SetText(ns.Export:GetFilterValue())
            filterValueLabel:SetText("Shopping list name")
        end
    end

    -- Status text
    if mode == "everything" then
        exportFilterStatus:SetText("")
    else
        local val = ns.Export:GetFilterValue()
        if mode == "tsmgroup" then
            exportFilterStatus:SetText(val ~= "" and (ns.COLORS.YELLOW .. "Group: " .. val:gsub("`", " > ") .. "|r") or "")
        elseif mode == "auctionator" then
            exportFilterStatus:SetText(val ~= "" and (ns.COLORS.YELLOW .. "List: " .. val .. "|r") or "")
        else
            exportFilterStatus:SetText(ns.COLORS.YELLOW .. "Filter: " .. mode .. (val ~= "" and (" = " .. val) or "") .. "|r")
        end
    end

    -- Reposition export scroll dynamically based on visible controls
    local controlsBottom = filterConfigY
    if mode == "tsmgroup" and exportTreeFrame:IsShown() then
        controlsBottom = controlsBottom - exportTreeFrame:GetHeight() - 4
        if filterValueLabel:GetText() and filterValueLabel:GetText() ~= "" then
            controlsBottom = controlsBottom - 16
        end
    elseif mode == "auctionator" and exportAuctFrame:IsShown() then
        controlsBottom = controlsBottom - exportAuctFrame:GetHeight() - 4
    end
    -- Ensure minimum gap below the filter row
    controlsBottom = math.min(controlsBottom, -72)

    exportFilterStatus:ClearAllPoints()
    exportFilterStatus:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 8, controlsBottom)

    local scrollTop = controlsBottom - 16
    exportScroll:ClearAllPoints()
    exportScroll:SetPoint("TOPLEFT", exportPage, "TOPLEFT", 4, scrollTop)
    exportScroll:SetPoint("BOTTOMRIGHT", exportPage, "BOTTOMRIGHT", -24, 34)
end

-- Wire button clicks
fmtCSVBtn:SetScript("OnClick", function()
    ns.Export:SetFormat("csv")
    UpdateFormatButtons()
end)
fmtAAABtn:SetScript("OnClick", function()
    ns.Export:SetFormat("aaa")
    UpdateFormatButtons()
end)

filterAllBtn:SetScript("OnClick", function()
    ns.Export:SetFilter("everything", "")
    UpdateFilterButtons()
end)
filterTSMBtn:SetScript("OnClick", function()
    ns.Export:SetFilter("tsmgroup", filterValueBox:GetText())
    UpdateFilterButtons()
end)
filterAuctBtn:SetScript("OnClick", function()
    ns.Export:SetFilter("auctionator", filterValueBox:GetText())
    UpdateFilterButtons()
end)

-- ==========================================
-- EXPOSE REFERENCES
-- ==========================================

UI._exportPage = exportPage
UI._exportEdit = exportEdit
UI._exportStatus = exportStatus
UI._updateExportToggles = function()
    UpdateFormatButtons()
    UpdateFilterButtons()
end

-- Register layout callback for container resize
UI:RegisterPageLayout("export", function()
    if exportPage:IsShown() then
        UpdateFilterButtons()
    end
end)

-- ==========================================
-- REFRESH
-- ==========================================

function UI:RefreshExportPage()
    local mainFrame = UI.mainFrame
    mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Export" .. "|r")
    UI._LayoutActionBtns(mainFrame.actionBtns.exportSaved, mainFrame.actionBtns.exportAll,
        mainFrame.actionBtns.exportWarbank, mainFrame.actionBtns.exportBank, mainFrame.actionBtns.exportBags)
    exportPage:Show()
    if UI._updateExportToggles then UI._updateExportToggles() end

    -- Check for pending export from Generator's "Export to FP"
    if UI._pendingExportCSV then
        UI._exportEdit:SetText(UI._pendingExportCSV)
        UI._exportEdit:HighlightText()
        UI._exportEdit:SetFocus(true)
        UI._exportStatus:SetText(ns.COLORS.GREEN .. (UI._pendingExportCount or 0) .. " items|r exported from item pool  |  Ctrl+A then Ctrl+C to copy")
        mainFrame.statusText:SetText("Item pool export  |  Ctrl+A then Ctrl+C to copy")
        UI._pendingExportCSV = nil
        UI._pendingExportCount = nil
    else
        local fmtName = ns.Export:GetFormat() == "aaa" and "AAA JSON" or "FP CSV"
        mainFrame.statusText:SetText(fmtName .. " export  |  Ctrl+A then Ctrl+C to copy")
    end
end
