-- UI/ScrollTable.lua
-- Reusable sortable table component (TSM-style)
local addonName, ns = ...

local UI = ns.UI or {}
ns.UI = UI

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 22
local COL_PADDING = 4

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

        self.headerButtons[i] = btn
        xOffset = xOffset + col.width
    end
end

function ScrollTableMixin:CreateScrollArea(parent)
    self.scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    self.scrollFrame:SetPoint("TOPLEFT", self.headerFrame, "BOTTOMLEFT", 0, 0)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22, 0)

    self.content = CreateFrame("Frame", nil, self.scrollFrame)
    self.content:SetWidth(self.scrollFrame:GetWidth())
    self.content:SetHeight(1)
    self.scrollFrame:SetScrollChild(self.content)

    -- Update content width when scroll area resizes
    self.scrollFrame:SetScript("OnSizeChanged", function(sf, w)
        self.content:SetWidth(w)
    end)
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

    -- Create cell font strings for each column
    row.cells = {}
    local xOffset = 0
    for i, col in ipairs(self.columns) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cell:SetHeight(ROW_HEIGHT)
        cell:SetWidth(col.width - COL_PADDING * 2)
        cell:SetPoint("LEFT", row, "LEFT", xOffset + COL_PADDING, 0)
        cell:SetJustifyH(col.align or "LEFT")
        cell:SetWordWrap(false)
        row.cells[i] = cell
        xOffset = xOffset + col.width
    end

    -- Icon (optional, placed at start of first column)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
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

        -- Custom row color tint (or reset to default alternating)
        if rowData._rowColor then
            local c = rowData._rowColor
            local baseAlpha = c[4] or 0.15
            row.bg:SetColorTexture(c[1], c[2], c[3], baseAlpha)
            row:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(c[1], c[2], c[3], baseAlpha + 0.08)
                if row._onEnter then row._onEnter(row) end
            end)
            row:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(c[1], c[2], c[3], baseAlpha)
                GameTooltip:Hide()
            end)
        else
            local defaultAlpha = i % 2 == 0 and 0.03 or 0
            row.bg:SetColorTexture(1, 1, 1, defaultAlpha)
            row:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(1, 1, 1, 0.08)
                if row._onEnter then row._onEnter(row) end
            end)
            row:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(1, 1, 1, defaultAlpha)
                GameTooltip:Hide()
            end)
        end

        -- Icon
        if rowData._icon then
            row.icon:SetTexture(rowData._icon)
            row.icon:Show()
            -- Shift first cell text right to make room for icon
            row.cells[1]:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
        else
            row.icon:Hide()
            row.cells[1]:SetPoint("LEFT", row, "LEFT", COL_PADDING, 0)
        end

        -- Tooltip
        if rowData._tooltipItemID or rowData._tooltipText then
            row._onEnter = function()
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                local numID = tonumber(rowData._tooltipItemID)
                if numID and numID > 0 then
                    GameTooltip:SetItemByID(numID)
                elseif rowData._tooltipText then
                    GameTooltip:SetText(rowData._tooltipText, 1, 1, 1)
                    if rowData._tooltipExtra then
                        GameTooltip:AddLine(rowData._tooltipExtra, 0.7, 0.7, 0.7, true)
                    end
                    GameTooltip:Show()
                end
            end
        end

        -- Click handler
        if self.onRowClick then
            local capturedData = rowData
            local capturedIndex = i
            row:SetScript("OnMouseDown", function(_, button)
                self.onRowClick(capturedData, button, capturedIndex)
            end)
        end

        row:Show()
    end

    self.content:SetHeight(math.max(1, #self.data * ROW_HEIGHT))
end

function ScrollTableMixin:SetRowClickHandler(fn)
    self.onRowClick = fn
end

function ScrollTableMixin:SetSort(key, asc)
    self.sortKey = key
    self.sortAsc = asc ~= false
end

function ScrollTableMixin:GetRowHeight()
    return ROW_HEIGHT
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
