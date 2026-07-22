-- UI/ScrollTable.lua
-- Reusable sortable table component (TSM-style)
local addonName, ns = ...

local UI = ns.UI or {}
ns.UI = UI

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 22
local COL_PADDING = 4
-- Width reserved at the scroll frame's right edge for the vertical scroll bar.
-- 22px matches UIPanelScrollFrameTemplate's bar (left offset 6 + bar width ~16),
-- so the bar sits flush against the parent's right edge when shown.
local SCROLLBAR_INSET = 22
-- When the bar is hidden there's nothing to reserve room for; reclaim the strip
-- down to a small margin so the rows don't leave a dead gap on the right. (FQ-212)
local SCROLLBAR_HIDDEN_INSET = 2

--------------------------
-- ScrollTable Class
--------------------------

local ScrollTableMixin = {}

function ScrollTableMixin:Init(parent, columns)
    self.columns = columns  -- {{key, label, width, align, sortable, format}, ...}
    self.data = {}
    self.sortKey = nil
    self.sortAsc = true
    self.onRowClick = nil
    self.onRowEnter = nil
    self.rows = {}
    self.headerButtons = {}

    self:CreateHeader(parent)
    self:CreateScrollArea(parent)
end

function ScrollTableMixin:CreateHeader(parent)
    self.headerFrame = CreateFrame("Frame", nil, parent)
    self.headerFrame:SetHeight(HEADER_HEIGHT)
    self.headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    self.headerFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    -- Header background
    local bg = self.headerFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.2, 1)

    -- Bottom border
    local border = self.headerFrame:CreateTexture(nil, "BORDER")
    border:SetHeight(1)
    border:SetPoint("BOTTOMLEFT", self.headerFrame, "BOTTOMLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", self.headerFrame, "BOTTOMRIGHT", 0, 0)
    border:SetColorTexture(0.4, 0.4, 0.5, 1)

    local xOffset = 0
    for i, col in ipairs(self.columns) do
        local btn = CreateFrame("Button", nil, self.headerFrame)
        btn:SetHeight(HEADER_HEIGHT)
        btn:SetWidth(col.width)
        btn:SetPoint("LEFT", self.headerFrame, "LEFT", xOffset, 0)
        -- Last column stretches to fill remaining space
        if i == #self.columns then
            btn:SetPoint("RIGHT", self.headerFrame, "RIGHT", 0, 0)
        end

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetPoint("LEFT", btn, "LEFT", COL_PADDING, 0)
        btn.label:SetPoint("RIGHT", btn, "RIGHT", -COL_PADDING, 0)
        btn.label:SetJustifyH(col.align or "LEFT")
        btn.label:SetText(col.label)
        btn.label:SetTextColor(0.8, 0.8, 0.8)

        btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.arrow:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        btn.arrow:SetText("")

        -- Hover highlight
        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints()
        btn.highlight:SetColorTexture(1, 1, 1, 0.05)

        if col.sortable ~= false then
            local colKey = col.key
            btn:SetScript("OnClick", function()
                if self.sortKey == colKey then
                    self.sortAsc = not self.sortAsc
                else
                    self.sortKey = colKey
                    self.sortAsc = true
                end
                self:RefreshSort()
                self:Render()
            end)
        end

        -- Header tooltip (e.g., legend for Info column)
        if col.headerTooltip then
            local tip = col.headerTooltip
            btn:SetScript("OnEnter", function(s)
                s.highlight:Show()
                GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
                GameTooltip:SetText(tip, nil, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(s)
                s.highlight:Hide()
                GameTooltip:Hide()
            end)
        end

        self.headerButtons[i] = btn
        xOffset = xOffset + col.width
    end

    -- Column resize handles (between headers)
    self.resizeHandles = self.resizeHandles or {}
    for _, handle in ipairs(self.resizeHandles) do handle:Hide() end

    for i = 1, #self.columns - 1 do
        local handle = self.resizeHandles[i]
        if not handle then
            handle = CreateFrame("Button", nil, self.headerFrame)
            handle:SetWidth(6)
            handle.tex = handle:CreateTexture(nil, "OVERLAY")
            handle.tex:SetAllPoints()
            handle.tex:SetColorTexture(0.4, 0.4, 0.5, 0)
            self.resizeHandles[i] = handle
        end
        handle:SetHeight(HEADER_HEIGHT)
        handle:ClearAllPoints()
        handle:SetPoint("LEFT", self.headerButtons[i], "RIGHT", -3, 0)
        handle:SetFrameLevel(self.headerFrame:GetFrameLevel() + 2)
        handle:Show()

        handle:SetScript("OnEnter", function(h)
            h.tex:SetColorTexture(1, 0.82, 0, 0.4)
        end)
        handle:SetScript("OnLeave", function(h)
            if not h._dragging then
                h.tex:SetColorTexture(0.4, 0.4, 0.5, 0)
            end
        end)

        local colIdx = i
        local tbl = self
        handle:SetScript("OnMouseDown", function(h, button)
            if button ~= "LeftButton" then return end
            h._dragging = true
            h._startX = GetCursorPosition() / UIParent:GetEffectiveScale()
            h._startW1 = tbl.columns[colIdx].width
            h._startW2 = tbl.columns[colIdx + 1].width
            h.tex:SetColorTexture(1, 0.82, 0, 0.6)
            h:SetScript("OnUpdate", function()
                local curX = GetCursorPosition() / UIParent:GetEffectiveScale()
                local delta = curX - h._startX
                local newW1 = math.max(30, h._startW1 + delta)
                local newW2 = math.max(30, h._startW2 - delta)
                -- Constrain so total stays constant
                if newW1 >= 30 and newW2 >= 30 then
                    tbl.columns[colIdx].width = newW1
                    tbl.columns[colIdx + 1].width = newW2
                    -- Update header button widths and positions
                    local x = 0
                    for j, col in ipairs(tbl.columns) do
                        tbl.headerButtons[j]:ClearAllPoints()
                        tbl.headerButtons[j]:SetPoint("LEFT", tbl.headerFrame, "LEFT", x, 0)
                        if j == #tbl.columns then
                            -- Last column: anchor to right edge, don't set fixed width
                            tbl.headerButtons[j]:SetPoint("RIGHT", tbl.headerFrame, "RIGHT", 0, 0)
                        else
                            tbl.headerButtons[j]:SetWidth(col.width)
                        end
                        x = x + col.width
                    end
                    -- Update resize handle positions
                    for j = 1, #tbl.columns - 1 do
                        if tbl.resizeHandles[j] then
                            tbl.resizeHandles[j]:ClearAllPoints()
                            tbl.resizeHandles[j]:SetPoint("LEFT", tbl.headerButtons[j], "RIGHT", -3, 0)
                        end
                    end
                end
            end)
        end)
        handle:SetScript("OnMouseUp", function(h)
            h._dragging = false
            h.tex:SetColorTexture(0.4, 0.4, 0.5, 0)
            h:SetScript("OnUpdate", nil)
            -- Re-render rows with new widths
            -- Rebuild rows since cell widths are baked in
            for _, row in ipairs(tbl.rows) do
                row:Hide()
                row:SetParent(nil)
            end
            wipe(tbl.rows)
            tbl:Render()
        end)
    end
end

function ScrollTableMixin:CreateScrollArea(parent)
    self.scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    self._scrollParent = parent
    self.scrollFrame:SetPoint("TOPLEFT", self.headerFrame, "BOTTOMLEFT", 0, 0)
    self:SetScrollbarInset(SCROLLBAR_INSET)

    self.content = CreateFrame("Frame", nil, self.scrollFrame)
    self.content:SetWidth(self.scrollFrame:GetWidth())
    self.content:SetHeight(1)
    self.scrollFrame:SetScrollChild(self.content)

    -- Grab the scroll bar created by UIPanelScrollFrameTemplate
    self.scrollBar = self.scrollFrame.ScrollBar
    if not self.scrollBar then
        -- Fallback: find scroll bar among children
        for _, child in ipairs({self.scrollFrame:GetChildren()}) do
            if child and child.GetObjectType and child:GetObjectType() == "Slider" then
                self.scrollBar = child
                break
            end
        end
    end

    -- Horizontal scroll state
    self._hScroll = 0

    -- Horizontal scroll bar track (thin bar at bottom of parent)
    local hTrack = CreateFrame("Frame", nil, parent)
    hTrack:SetHeight(8)
    hTrack:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    hTrack:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    local hTrackBg = hTrack:CreateTexture(nil, "BACKGROUND")
    hTrackBg:SetAllPoints()
    hTrackBg:SetColorTexture(0.1, 0.1, 0.15, 0.8)
    hTrack:Hide()
    self._hScrollTrack = hTrack

    -- Horizontal scroll thumb
    local hThumb = CreateFrame("Button", nil, hTrack)
    hThumb:SetHeight(6)
    hThumb:SetPoint("TOP", hTrack, "TOP", 0, -1)
    local hThumbTex = hThumb:CreateTexture(nil, "ARTWORK")
    hThumbTex:SetAllPoints()
    hThumbTex:SetColorTexture(0.5, 0.5, 0.6, 0.7)
    hThumb:EnableMouse(true)

    -- Thumb drag for horizontal scroll
    local tblSelf = self
    hThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        self._dragging = true
        self._startX = GetCursorPosition() / UIParent:GetEffectiveScale()
        self._startScroll = tblSelf._hScroll or 0
    end)
    hThumb:SetScript("OnMouseUp", function(self)
        self._dragging = false
        self:SetScript("OnUpdate", nil)
    end)
    hThumb:SetScript("OnEnter", function(self)
        hThumbTex:SetColorTexture(0.7, 0.7, 0.8, 0.9)
    end)
    hThumb:SetScript("OnLeave", function(self)
        if not self._dragging then
            hThumbTex:SetColorTexture(0.5, 0.5, 0.6, 0.7)
        end
    end)
    self._hScrollThumb = hThumb

    -- Shift+MouseWheel for horizontal scrolling
    self.scrollFrame:HookScript("OnMouseWheel", function(sf, delta)
        if IsShiftKeyDown() then
            local totalColW = 0
            for _, col in ipairs(self.columns) do totalColW = totalColW + col.width end
            local visibleW = sf:GetWidth()
            local maxHScroll = math.max(0, totalColW - visibleW)
            if maxHScroll > 0 then
                self._hScroll = math.max(0, math.min(maxHScroll, (self._hScroll or 0) - delta * 40))
                self:ApplyHorizontalScroll()
            end
        end
    end)

    -- Update content width when scroll area resizes
    self.scrollFrame:SetScript("OnSizeChanged", function(sf, w)
        self.content:SetWidth(w)
        self:UpdateScrollBarVisibility()
    end)

    -- Also check after vertical scroll changes
    self.scrollFrame:HookScript("OnScrollRangeChanged", function()
        self:UpdateScrollBarVisibility()
    end)
end

function ScrollTableMixin:ApplyHorizontalScroll()
    local offset = -(self._hScroll or 0)

    -- Shift header buttons
    local x = 0
    for i, col in ipairs(self.columns) do
        if self.headerButtons[i] then
            self.headerButtons[i]:ClearAllPoints()
            self.headerButtons[i]:SetPoint("LEFT", self.headerFrame, "LEFT", x + offset, 0)
            self.headerButtons[i]:SetWidth(col.width)
        end
        x = x + col.width
    end

    -- Shift row clip frames
    for _, row in ipairs(self.rows) do
        if row._cellClips then
            local cx = 0
            for j, col in ipairs(self.columns) do
                if row._cellClips[j] then
                    row._cellClips[j]:ClearAllPoints()
                    row._cellClips[j]:SetPoint("LEFT", row, "LEFT", cx + offset, 0)
                    row._cellClips[j]:SetWidth(col.width)
                end
                cx = cx + col.width
            end
        end
    end

    -- Update horizontal thumb position
    self:UpdateHScrollThumb()
end

function ScrollTableMixin:UpdateHScrollThumb()
    local hTrack = self._hScrollTrack
    local hThumb = self._hScrollThumb
    if not hTrack or not hThumb then return end

    local totalColW = 0
    for _, col in ipairs(self.columns) do totalColW = totalColW + col.width end
    local visibleW = self.scrollFrame:GetWidth()
    local maxHScroll = math.max(0, totalColW - visibleW)

    if maxHScroll <= 0 then
        hTrack:Hide()
        return
    end

    hTrack:Show()
    local trackW = hTrack:GetWidth()
    if trackW <= 0 then return end
    local thumbRatio = math.min(1, visibleW / totalColW)
    local thumbW = math.max(20, trackW * thumbRatio)
    hThumb:SetWidth(thumbW)

    local scrollRatio = (self._hScroll or 0) / maxHScroll
    local thumbOffset = scrollRatio * (trackW - thumbW)
    hThumb:ClearAllPoints()
    hThumb:SetPoint("LEFT", hTrack, "LEFT", thumbOffset, 0)
    hThumb:SetPoint("TOP", hTrack, "TOP", 0, -1)

    -- Wire up thumb drag
    local tbl = self
    hThumb:SetScript("OnUpdate", function(self)
        if not self._dragging then return end
        local curX = GetCursorPosition() / UIParent:GetEffectiveScale()
        local delta = curX - self._startX
        local dragRatio = delta / (trackW - thumbW)
        local newScroll = math.max(0, math.min(maxHScroll, self._startScroll + dragRatio * maxHScroll))
        tbl._hScroll = newScroll
        tbl:ApplyHorizontalScroll()
    end)
end

-- Re-anchor the scroll frame's right edge. Guarded so the OnSizeChanged ->
-- UpdateScrollBarVisibility -> SetScrollbarInset path can't re-fire SetPoint and
-- recurse: once the inset is applied the early return breaks the loop.
function ScrollTableMixin:SetScrollbarInset(inset)
    if self._appliedInset == inset then return end
    self._appliedInset = inset
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self._scrollParent, "BOTTOMRIGHT", -inset, 0)
end

function ScrollTableMixin:UpdateScrollBarVisibility()
    local scrollBar = self.scrollBar
    if not scrollBar then return end

    local range = self.scrollFrame:GetVerticalScrollRange()

    -- Determine if horizontal scroll is needed
    local totalColW = 0
    for _, col in ipairs(self.columns) do totalColW = totalColW + col.width end
    local visibleW = self.scrollFrame:GetWidth()
    local hasHScroll = totalColW > visibleW + 1

    if range and range <= 0.5 then
        -- Nothing to scroll vertically: hide scroll bar (thumb + track) and
        -- reclaim the reserved strip so the rows extend flush to the edge.
        scrollBar:SetAlpha(0)
        scrollBar:EnableMouse(false)
        self:SetScrollbarInset(SCROLLBAR_HIDDEN_INSET)
    else
        -- Content overflows: show scroll bar and reserve room so it sits flush.
        scrollBar:SetAlpha(1)
        scrollBar:EnableMouse(true)
        self:SetScrollbarInset(SCROLLBAR_INSET)
    end

    -- Update horizontal scroll bar visibility
    if hasHScroll then
        self:UpdateHScrollThumb()
    elseif self._hScrollTrack then
        self._hScrollTrack:Hide()
        -- Reset horizontal scroll position
        if (self._hScroll or 0) > 0 then
            self._hScroll = 0
            self:ApplyHorizontalScroll()
        end
    end
end

function ScrollTableMixin:UpdateHeaderArrows()
    for i, col in ipairs(self.columns) do
        local btn = self.headerButtons[i]
        if col.key == self.sortKey then
            btn.arrow:SetText(self.sortAsc and "  v" or "  ^")
            btn.label:SetTextColor(1, 1, 1)
        else
            btn.arrow:SetText("")
            btn.label:SetTextColor(0.8, 0.8, 0.8)
        end
    end
end

-- Gold parsing now uses ns:ParseGoldValue() from Core.lua

function ScrollTableMixin:RefreshSort()
    if not self.sortKey then return end

    local key = self.sortKey
    local asc = self.sortAsc
    -- Check for a dedicated sort key (e.g., _sortStatus for status column)
    local sortOverride = "_sort" .. key:sub(1,1):upper() .. key:sub(2)

    table.sort(self.data, function(a, b)
        -- Use sort override key if present
        local va = a[sortOverride] or a[key]
        local vb = b[sortOverride] or b[key]
        if va == nil then va = "" end
        if vb == nil then vb = "" end

        -- Try numeric comparison
        local na, nb = tonumber(va), tonumber(vb)
        if na and nb then
            return asc and na < nb or (not asc and na > nb)
        end

        -- Try gold string comparison (handles "1,377g", "22.8k", etc.)
        if type(va) == "string" and type(vb) == "string" then
            local ga, gb = ns:ParseGoldValue(va), ns:ParseGoldValue(vb)
            if ga > 0 and gb > 0 then
                return asc and ga < gb or (not asc and ga > gb)
            end
        end

        -- String comparison
        va = tostring(va):lower()
        vb = tostring(vb):lower()
        if asc then return va < vb else return va > vb end
    end)
end

function ScrollTableMixin:GetOrCreateRow(index)
    if self.rows[index] then return self.rows[index] end

    local row = CreateFrame("Frame", nil, self.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
    row:EnableMouse(true)

    -- Alternating row background
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)

    -- Hover
    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.08)
        if row._onEnter then row._onEnter(row) end
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
        GameTooltip:Hide()
    end)

    -- Create cell font strings for each column (with clipping frames to prevent overflow)
    row.cells = {}
    row._cellClips = {}
    local xOffset = 0
    for i, col in ipairs(self.columns) do
        -- Clipping frame constrains text to column bounds
        local clip = CreateFrame("Frame", nil, row)
        clip:SetHeight(ROW_HEIGHT)
        clip:SetWidth(col.width)
        clip:SetPoint("LEFT", row, "LEFT", xOffset, 0)
        -- Last column stretches to fill remaining space
        if i == #self.columns then
            clip:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        end
        clip:SetClipsChildren(true)

        local cell = clip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cell:SetHeight(ROW_HEIGHT)
        cell:SetPoint("LEFT", clip, "LEFT", COL_PADDING, 0)
        cell:SetPoint("RIGHT", clip, "RIGHT", -COL_PADDING, 0)
        cell:SetJustifyH(col.align or "LEFT")
        cell:SetWordWrap(false)
        row.cells[i] = cell
        row._cellClips[i] = clip
        xOffset = xOffset + col.width
    end

    -- Icon (optional, placed at start of first column's clip frame)
    row.icon = row._cellClips[1]:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", row._cellClips[1], "LEFT", 2, 0)
    row.icon:Hide()

    self.rows[index] = row
    return row
end

function ScrollTableMixin:SetData(data)
    self.data = data
    if self.sortKey then
        self:RefreshSort()
    end
    self:Render()
end

function ScrollTableMixin:Render()
    self:UpdateHeaderArrows()

    -- Hide all existing rows
    for _, row in ipairs(self.rows) do
        row:Hide()
        row._onEnter = nil
        row:SetScript("OnMouseDown", nil)
    end

    for i, rowData in ipairs(self.data) do
        local row = self:GetOrCreateRow(i)

        -- Set cell values
        for j, col in ipairs(self.columns) do
            local value = rowData[col.key]
            if col.format then
                value = col.format(value, rowData)
            end
            row.cells[j]:SetText(value or "")
        end

        -- Action buttons setup (before OnEnter/OnLeave so closures capture state)
        local hasActions = self._rowActionsEnabled and rowData._taskIndex
        if hasActions then
            UI.SetupTaskActionBtns(row)
            UI.WireTaskActionBtns(row, rowData._taskIndex, self._actionRefreshFn)
            UI.HideTaskActionBtns(row)
        elseif row._taskActionBtns then
            UI.HideTaskActionBtns(row)
        end

        -- Custom row color tint (or reset to default alternating)
        if rowData._rowColor then
            local c = rowData._rowColor
            local baseAlpha = c[4] or 0.15
            row.bg:SetColorTexture(c[1], c[2], c[3], baseAlpha)
            row:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(c[1], c[2], c[3], baseAlpha + 0.08)
                if row._onEnter then row._onEnter(row) end
                if hasActions then UI.ShowTaskActionBtns(self) end
            end)
            row:SetScript("OnLeave", function(self)
                if hasActions then
                    self._actionBtnHovered = false
                    C_Timer.After(0.1, function()
                        if not self._actionBtnHovered and not self:IsMouseOver() then
                            self.bg:SetColorTexture(c[1], c[2], c[3], baseAlpha)
                            GameTooltip:Hide(); if BattlePetTooltip then BattlePetTooltip:Hide() end
                            UI.HideTaskActionBtns(self)
                        end
                    end)
                else
                    self.bg:SetColorTexture(c[1], c[2], c[3], baseAlpha)
                    GameTooltip:Hide(); if BattlePetTooltip then BattlePetTooltip:Hide() end
                end
            end)
        else
            local defaultAlpha = i % 2 == 0 and 0.03 or 0
            row.bg:SetColorTexture(1, 1, 1, defaultAlpha)
            row:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(1, 1, 1, 0.08)
                if row._onEnter then row._onEnter(row) end
                if hasActions then UI.ShowTaskActionBtns(self) end
            end)
            row:SetScript("OnLeave", function(self)
                if hasActions then
                    self._actionBtnHovered = false
                    C_Timer.After(0.1, function()
                        if not self._actionBtnHovered and not self:IsMouseOver() then
                            self.bg:SetColorTexture(1, 1, 1, defaultAlpha)
                            GameTooltip:Hide(); if BattlePetTooltip then BattlePetTooltip:Hide() end
                            UI.HideTaskActionBtns(self)
                        end
                    end)
                else
                    self.bg:SetColorTexture(1, 1, 1, defaultAlpha)
                    GameTooltip:Hide(); if BattlePetTooltip then BattlePetTooltip:Hide() end
                end
            end)
        end

        -- Update clip frame widths (in case columns were resized)
        local cx = 0
        for j, col in ipairs(self.columns) do
            if row._cellClips and row._cellClips[j] then
                row._cellClips[j]:SetWidth(col.width)
                row._cellClips[j]:ClearAllPoints()
                row._cellClips[j]:SetPoint("LEFT", row, "LEFT", cx, 0)
                if j == #self.columns then
                    row._cellClips[j]:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                end
                row.cells[j]:SetWidth(col.width - COL_PADDING * 2)
            end
            cx = cx + col.width
        end

        -- Icon
        if rowData._icon then
            row.icon:SetTexture(rowData._icon)
            row.icon:Show()
            -- Shift first cell text right to make room for icon
            row.cells[1]:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
        else
            row.icon:Hide()
            row.cells[1]:SetPoint("LEFT", row._cellClips[1], "LEFT", COL_PADDING, 0)
        end

        -- Tooltip (with battle pet support)
        if rowData._tooltipPetSpecies or rowData._tooltipItemID or rowData._tooltipItemString or rowData._tooltipText then
            row._onEnter = function()
                local usedGameTooltip = false
                if rowData._tooltipPetSpecies and BattlePetToolTip_Show then
                    BattlePetToolTip_Show(rowData._tooltipPetSpecies, 25, rowData._tooltipPetQuality or 3, 0, 0, 0)
                    if BattlePetTooltip then
                        BattlePetTooltip:ClearAllPoints()
                        BattlePetTooltip:SetPoint("TOPLEFT", row, "TOPRIGHT")
                    end
                elseif rowData._tooltipItemString then
                    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(rowData._tooltipItemString)
                    usedGameTooltip = true
                elseif tonumber(rowData._tooltipItemID) and tonumber(rowData._tooltipItemID) > 0 then
                    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(tonumber(rowData._tooltipItemID))
                    usedGameTooltip = true
                elseif rowData._tooltipText then
                    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                    GameTooltip:SetText(rowData._tooltipText, 1, 1, 1)
                    usedGameTooltip = true
                end
                -- Append per-row metadata (realm, price, character, etc.)
                -- to whichever tooltip backend rendered the item — previously
                -- the extra was dropped on item/itemString rows because the
                -- AddLine + Show call lived inside the text-only branch.
                if usedGameTooltip and rowData._tooltipExtra and rowData._tooltipExtra ~= "" then
                    GameTooltip:AddLine(rowData._tooltipExtra, 0.7, 0.7, 0.7, true)
                end
                if usedGameTooltip then
                    GameTooltip:Show()
                end
            end
        end

        -- Click handler
        if self.onRowClick then
            local capturedData = rowData
            local capturedIndex = i
            -- The row frame rides along as a 4th arg so handlers can anchor
            -- context menus to the clicked row (UI/InventoryPage.lua).
            row:SetScript("OnMouseDown", function(_, button)
                self.onRowClick(capturedData, button, capturedIndex, row)
            end)
        end

        row:Show()
    end

    self.content:SetHeight(math.max(1, #self.data * ROW_HEIGHT))
    self:UpdateScrollBarVisibility()
end

function ScrollTableMixin:SetRowClickHandler(fn)
    self.onRowClick = fn
end

-- Enable mouseover action buttons (complete/skip/delete) on rows that have _taskIndex.
function ScrollTableMixin:EnableRowActions(refreshFn)
    self._rowActionsEnabled = true
    self._actionRefreshFn = refreshFn
end

function ScrollTableMixin:SetSort(key, asc)
    self.sortKey = key
    self.sortAsc = asc ~= false
end

function ScrollTableMixin:GetRowHeight()
    return ROW_HEIGHT
end

function ScrollTableMixin:SetColumns(newColumns)
    local parent = self.headerFrame:GetParent()
    local wasVisible = self.headerFrame:IsShown()

    -- Hide and release old header frame entirely
    self.headerFrame:Hide()
    self.headerFrame:SetParent(nil)
    wipe(self.headerButtons)

    -- Hide and release old rows (cell count tied to old column count)
    for _, row in ipairs(self.rows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(self.rows)

    -- Update columns and rebuild header
    self.columns = newColumns
    self.data = {}
    self._hScroll = 0

    -- Validate sort key still exists in new columns
    if self.sortKey then
        local found = false
        for _, col in ipairs(newColumns) do
            if col.key == self.sortKey then found = true; break end
        end
        if not found then
            self.sortKey = newColumns[1] and newColumns[1].key or nil
            self.sortAsc = true
        end
    end

    -- Create new header and re-anchor scroll frame to it
    self:CreateHeader(parent)
    self.scrollFrame:SetPoint("TOPLEFT", self.headerFrame, "BOTTOMLEFT", 0, 0)

    if not wasVisible then
        self.headerFrame:Hide()
    end
end

--------------------------
-- Constructor
--------------------------

function UI:CreateScrollTable(parent, columns)
    local tbl = setmetatable({}, {__index = ScrollTableMixin})
    tbl:Init(parent, columns)
    return tbl
end

UI.ROW_HEIGHT = ROW_HEIGHT
