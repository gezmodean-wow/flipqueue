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
        edit:SetMaxLetters(0)
        edit:SetWidth(scroll:GetWidth() or 450)
        edit:EnableMouse(true)
        edit:SetScript("OnEscapePressed", function() exportPopup:Hide() end)
        scroll:SetScrollChild(edit)
        scroll:SetScript("OnSizeChanged", function(sf, w) edit:SetWidth(w) end)
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

    -- Escape pipe characters (WoW treats | as control char; || = literal pipe)
    local safeText = (text or ""):gsub("|", "||")

    exportPopup._edit:SetText(safeText)
    exportPopup._edit:SetCursorPosition(0)
    exportPopup._edit:HighlightText()
    exportPopup._edit:SetFocus(true)
    exportPopup._status:SetText(statusMsg and (ns.COLORS.GREEN .. statusMsg .. "|r") or "")
    exportPopup:Show()
end

-- ==========================================
-- COPY BLIP (tiny sized-to-content copy dialog)
-- ==========================================
-- A small copy dialog that auto-sizes to its content, anchored to a
-- click source (e.g. a mini-view row or scroll frame). Takes a list
-- of { label, text } entries and renders one labeled edit box per
-- entry so the user can click whichever value they want — clicking
-- an edit box auto-focuses it and highlights the text, making
-- Ctrl+C a single keystroke.
--
-- Typical use: click a next-steps row, blip opens with both the
-- character name and the realm as separate entries, user clicks
-- whichever one they need, copies it, moves on.

local copyBlip
local COPY_ROW_HEIGHT = 22
local COPY_ROW_SPACING = 2
local COPY_PADDING_X = 10
local COPY_PADDING_TOP = 6
local COPY_PADDING_BOTTOM = 8

-- Pool of { rowFrame, label, editBox } tuples — one per entry. Rows
-- are created lazily and reused across invocations so we don't leak
-- frames on repeated opens.
local function GetOrCreateRow(index)
    copyBlip._rows = copyBlip._rows or {}
    local row = copyBlip._rows[index]
    if row then return row end

    row = {}
    row.frame = CreateFrame("Frame", nil, copyBlip)
    row.frame:SetHeight(COPY_ROW_HEIGHT)
    row.frame:EnableMouse(true)

    row.label = row.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.label:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
    row.label:SetJustifyH("LEFT")

    row.edit = CreateFrame("EditBox", nil, row.frame)
    row.edit:SetFontObject("ChatFontNormal")
    row.edit:SetAutoFocus(false)
    row.edit:SetMaxLetters(200)
    row.edit:EnableMouse(true)
    row.edit:SetHeight(16)
    row.edit:SetPoint("TOPLEFT", row.label, "TOPRIGHT", 6, 0)
    row.edit:SetPoint("RIGHT", row.frame, "RIGHT", -4, 0)
    row.edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        copyBlip:Hide()
    end)
    row.edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    -- Re-highlight on focus so clicking the field primes Ctrl+C
    row.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- Clicking the row (anywhere) focuses its edit box
    row.frame:SetScript("OnMouseDown", function()
        row.edit:SetFocus(true)
        row.edit:HighlightText()
    end)

    copyBlip._rows[index] = row
    return row
end

function UI:ShowCopyBlip(entries, anchorFrame)
    -- Accept both the new list form { {label, text}, ... } and the
    -- legacy single-entry form (text, anchor, label) so existing
    -- callers don't break immediately. Detect by entries type.
    if type(entries) == "string" then
        entries = { { label = "Copy", text = entries } }
    end
    if type(entries) ~= "table" or #entries == 0 then return end

    if not copyBlip then
        copyBlip = CreateFrame("Frame", "FlipQueueCopyBlip", UIParent, "BackdropTemplate")
        copyBlip:SetFrameStrata("TOOLTIP")
        copyBlip:SetClampedToScreen(true)
        copyBlip:EnableMouse(true)
        copyBlip:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = {left = 3, right = 3, top = 3, bottom = 3},
        })
        copyBlip:SetBackdropColor(0.08, 0.08, 0.12, 0.98)
        copyBlip:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)

        -- Hidden measuring FontString shared across rows for width calc
        local measure = copyBlip:CreateFontString(nil, "BACKGROUND", "ChatFontNormal")
        measure:Hide()
        copyBlip._measure = measure

        local measureLabel = copyBlip:CreateFontString(nil, "BACKGROUND", "GameFontDisableSmall")
        measureLabel:Hide()
        copyBlip._measureLabel = measureLabel

        -- Auto-dismiss on mouse leave with a short grace period so
        -- the user has time to reach an edit box without the popup
        -- evaporating from under them.
        copyBlip:SetScript("OnLeave", function(self)
            C_Timer.After(0.5, function()
                if copyBlip and copyBlip:IsShown() and not copyBlip:IsMouseOver() then
                    copyBlip:Hide()
                end
            end)
        end)
    end

    -- Hide any previously-shown rows from a prior invocation
    if copyBlip._rows then
        for _, r in ipairs(copyBlip._rows) do
            r.frame:Hide()
        end
    end

    -- Populate rows and compute the widest label + text so the blip
    -- ends up sized to exactly its content.
    local maxLabelW, maxTextW = 0, 0
    for i, entry in ipairs(entries) do
        copyBlip._measureLabel:SetText(entry.label or "")
        local lw = copyBlip._measureLabel:GetStringWidth()
        if lw > maxLabelW then maxLabelW = lw end
        copyBlip._measure:SetText(entry.text or "")
        local tw = copyBlip._measure:GetStringWidth()
        if tw > maxTextW then maxTextW = tw end
    end
    -- Edit boxes need a little breathing room beyond the text width so
    -- the caret and the last character aren't clipped by the right edge.
    local editInnerW = maxTextW + 16
    local contentW = maxLabelW + 6 + editInnerW
    local width = math.max(160, math.min(contentW + COPY_PADDING_X * 2, 480))
    local height = COPY_PADDING_TOP + COPY_PADDING_BOTTOM
        + (#entries * COPY_ROW_HEIGHT) + ((#entries - 1) * COPY_ROW_SPACING)

    copyBlip:SetWidth(width)
    copyBlip:SetHeight(height)

    -- Layout the rows
    local y = -COPY_PADDING_TOP
    for i, entry in ipairs(entries) do
        local row = GetOrCreateRow(i)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", copyBlip, "TOPLEFT", COPY_PADDING_X, y)
        row.frame:SetPoint("RIGHT", copyBlip, "RIGHT", -COPY_PADDING_X, 0)

        row.label:SetText(entry.label or "")
        row.label:SetWidth(maxLabelW)
        row.edit:SetText(entry.text or "")
        row.frame:Show()

        y = y - COPY_ROW_HEIGHT - COPY_ROW_SPACING
    end

    -- Anchor to the click source below its bottom-left, fall back to
    -- screen center if no anchor was provided.
    copyBlip:ClearAllPoints()
    if anchorFrame then
        copyBlip:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)
    else
        copyBlip:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    copyBlip:Show()

    -- Auto-focus + highlight the first entry so the most-common path
    -- (copy the character name) is still one keystroke.
    local firstRow = copyBlip._rows and copyBlip._rows[1]
    if firstRow and firstRow.edit then
        firstRow.edit:SetFocus(true)
        firstRow.edit:HighlightText()
    end
end

-- Build the copy-blip entries list for a next-steps row. Returns a
-- list of { label, text } tables suitable for passing into
-- UI:ShowCopyBlip. Rules:
--   - If _charKey is present, include both the character name and
--     the realm as separate entries, name first (most common copy).
--   - If only _tooltipText is present (unassigned "Create char"),
--     include just the realm.
--   - Empty list if neither is available.
function UI:BuildNextStepCopyEntries(rowData)
    local entries = {}
    if not rowData then return entries end
    if rowData._charKey then
        local name  = rowData._charKey:match("^(.-)%-") or rowData._charKey
        local realm = rowData._charKey:match("%-(.+)$") or ""
        table.insert(entries, { label = "Character:", text = name })
        if realm ~= "" then
            table.insert(entries, { label = "Realm:    ", text = realm })
        end
    elseif rowData._tooltipText and rowData._tooltipText ~= "" then
        table.insert(entries, { label = "Realm:    ", text = rowData._tooltipText })
    end
    return entries
end

-- ==========================================
-- DEBUG EXPORT (SimpleHTML — no char limit)
-- ==========================================

local debugPopup

function UI:ShowDebugExport(text, statusMsg)
    if not debugPopup then
        debugPopup = CreateFrame("Frame", "FlipQueueDebugPopup", UIParent, "BackdropTemplate")
        debugPopup:SetSize(700, 500)
        debugPopup:SetPoint("CENTER")
        debugPopup:SetMovable(true)
        debugPopup:EnableMouse(true)
        debugPopup:RegisterForDrag("LeftButton")
        debugPopup:SetScript("OnDragStart", debugPopup.StartMoving)
        debugPopup:SetScript("OnDragStop", debugPopup.StopMovingOrSizing)
        debugPopup:SetFrameStrata("DIALOG")
        debugPopup:SetClampedToScreen(true)
        debugPopup:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4},
        })
        debugPopup:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
        debugPopup:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)

        -- Title bar
        local bar = CreateFrame("Frame", nil, debugPopup)
        bar:SetHeight(24)
        bar:SetPoint("TOPLEFT", debugPopup, "TOPLEFT", 4, -4)
        bar:SetPoint("TOPRIGHT", debugPopup, "TOPRIGHT", -4, -4)
        local barBg = bar:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        barBg:SetColorTexture(0.12, 0.12, 0.18, 1)

        local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", bar, "LEFT", 8, 0)
        title:SetText(ns.COLORS.YELLOW .. "FQ Debug Export" .. ns.COLORS.RESET)

        local closeBtn = CreateFrame("Button", nil, bar)
        closeBtn:SetSize(18, 18)
        closeBtn:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
        closeBtn:GetHighlightTexture():SetAlpha(0.3)
        closeBtn:SetScript("OnClick", function() debugPopup:Hide() end)

        -- "Save & Reload" button
        local saveBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        saveBtn:SetSize(110, 20)
        saveBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
        saveBtn:SetText("Save & Reload")
        saveBtn:SetScript("OnClick", function()
            if ns.db then
                ns:Print(ns.COLORS.GREEN .. "Saving debug export to disk...|r")
                C_Timer.After(0.2, ReloadUI)
            end
        end)
        saveBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Save to WTF/SavedVariables/flipqueue.lua\nand reload UI to flush to disk", 1, 1, 1)
            GameTooltip:Show()
        end)
        saveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Scroll frame
        local scroll = CreateFrame("ScrollFrame", nil, debugPopup, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
        scroll:SetPoint("BOTTOMRIGHT", debugPopup, "BOTTOMRIGHT", -26, 30)

        -- SimpleHTML child
        local html = CreateFrame("SimpleHTML", nil, scroll)
        html:SetWidth(scroll:GetWidth() or 650)
        html:SetFontObject("p", "GameFontHighlightSmall")
        html:SetHyperlinkFormat("p", "")
        scroll:SetScrollChild(html)
        scroll:SetScript("OnSizeChanged", function(sf, w) html:SetWidth(w) end)

        -- Mouse wheel scrolling
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local step = 40
            local newScroll = math.max(0, math.min(current - (delta * step), maxScroll))
            self:SetVerticalScroll(newScroll)
        end)

        debugPopup._html = html
        debugPopup._scroll = scroll

        -- Status text
        local status = debugPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        status:SetPoint("LEFT", debugPopup, "BOTTOMLEFT", 8, 17)
        status:SetTextColor(0.5, 0.5, 0.5)
        debugPopup._status = status

        debugPopup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
                self:SetPropagateKeyboardInput(false)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
    end

    -- Convert to HTML — replace pipes with semicolons to avoid WoW escape parsing
    local safeText = (text or "")
        :gsub("|", ";")
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub("\n", "<br/>")

    -- Build HTML in chunks to avoid massive single string
    local htmlStr = "<html><body><p>" .. safeText .. "</p></body></html>"

    ns:PrintDebug("ShowDebugExport: htmlLen=" .. #htmlStr)
    local ok, err = pcall(debugPopup._html.SetText, debugPopup._html, htmlStr)
    if not ok then
        ns:PrintError("SimpleHTML error: " .. tostring(err))
        debugPopup._html:SetText("<html><body><p>Error rendering (" .. #htmlStr .. " chars). Use Save &amp; Reload button.</p></body></html>")
    else
        ns:PrintDebug("SimpleHTML SetText OK")
    end
    debugPopup._status:SetText(statusMsg or "")
    debugPopup:Show()

    -- Update dimensions after show — SimpleHTML needs explicit height
    C_Timer.After(0.1, function()
        local w = debugPopup._scroll:GetWidth()
        if w and w > 10 then debugPopup._html:SetWidth(w) end
        -- SimpleHTML doesn't auto-size — estimate height from line count
        local lineCount = select(2, (text or ""):gsub("\n", "\n")) + 1
        debugPopup._html:SetHeight(lineCount * 14 + 20)
    end)
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
