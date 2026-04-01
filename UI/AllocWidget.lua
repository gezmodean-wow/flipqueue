-- UI/AllocWidget.lua
-- Reusable drag-to-reorder priority list widget.
-- Used by GeneratorPage and DealFinderPage for allocation order configuration.
local addonName, ns = ...

local UI = ns.UI

local LIST_ROW_H = 28

--------------------------
-- Shared drag state (one ghost/dropline for all instances)
--------------------------

local dragState = nil

local function EnsureDragState()
    if dragState then return dragState end
    dragState = {}

    local ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetSize(180, 26)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetAlpha(0.85)
    ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
    ghost.bg:SetAllPoints()
    ghost.bg:SetColorTexture(0.2, 0.25, 0.4, 0.9)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetSize(16, 16)
    ghost.icon:SetPoint("LEFT", ghost, "LEFT", 6, 0)
    ghost.label = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ghost.label:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
    ghost.label:SetPoint("RIGHT", ghost, "RIGHT", -6, 0)
    ghost.label:SetJustifyH("LEFT")
    ghost.border = ghost:CreateTexture(nil, "BORDER")
    ghost.border:SetPoint("TOPLEFT", -1, 1)
    ghost.border:SetPoint("BOTTOMRIGHT", 1, -1)
    ghost.border:SetColorTexture(0.5, 0.6, 1, 0.6)
    ghost:Hide()
    dragState.ghost = ghost

    local dropLine = UIParent:CreateTexture(nil, "OVERLAY")
    dropLine:SetHeight(2)
    dropLine:SetColorTexture(1, 0.82, 0, 0.9)
    dropLine:Hide()
    dragState.dropLine = dropLine

    return dragState
end

--------------------------
-- Render allocation list
--------------------------

-- orderTable: array of key strings (e.g. {"profit", "noCompetition"})
-- allocMeta: { key = {label, icon, color={r,g,b}} }
-- rowPool: reusable table of row frames
-- parent: container frame
-- yStart: top Y position for first row
-- onChanged: callback after reorder
-- Returns: yOffset after last row
function UI:RenderAllocList(orderTable, allocMeta, rowPool, parent, yStart, onChanged)
    for _, row in ipairs(rowPool) do row:Hide() end
    local y = yStart
    local ds = EnsureDragState()

    for idx, key in ipairs(orderTable) do
        local meta = allocMeta[key] or {label = key, color = {0.7, 0.7, 0.7}}
        local row = rowPool[idx]

        if not row then
            row = CreateFrame("Button", nil, parent, "BackdropTemplate")
            row:SetHeight(LIST_ROW_H)
            row:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 10,
                insets = {left = 2, right = 2, top = 2, bottom = 2},
            })

            row.grip = row:CreateTexture(nil, "ARTWORK")
            row.grip:SetSize(8, 14)
            row.grip:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.grip:SetColorTexture(0.4, 0.4, 0.5, 0.5)

            row.rankBg = row:CreateTexture(nil, "ARTWORK")
            row.rankBg:SetSize(18, 18)
            row.rankBg:SetPoint("LEFT", row.grip, "RIGHT", 4, 0)
            row.rankBg:SetColorTexture(0.2, 0.2, 0.3, 0.8)

            row.rankNum = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.rankNum:SetPoint("CENTER", row.rankBg, "CENTER", 0, 0)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", row.rankBg, "RIGHT", 6, 0)

            row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.nameLabel:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.nameLabel:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.nameLabel:SetJustifyH("LEFT")

            row:EnableMouse(true)
            rowPool[idx] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
        row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)

        local brightness = 1 - (idx - 1) * 0.2
        local c = meta.color
        row:SetBackdropColor(c[1] * 0.12 * brightness, c[2] * 0.12 * brightness, c[3] * 0.15 * brightness, 0.9)
        row:SetBackdropBorderColor(c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 0.6)

        row.rankNum:SetText(idx)
        row.rankNum:SetTextColor(c[1], c[2], c[3])

        if meta.icon then
            row.icon:SetTexture(meta.icon)
            row.icon:Show()
        else
            row.icon:Hide()
        end

        row.nameLabel:SetText(meta.label)
        row.nameLabel:SetTextColor(c[1] * 0.8 + 0.2, c[2] * 0.8 + 0.2, c[3] * 0.8 + 0.2)
        row.grip:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.6)

        local capturedIdx = idx

        row:SetScript("OnEnter", function(self)
            if not ds.dragging then
                self:SetBackdropBorderColor(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7, 1)
                self.grip:SetColorTexture(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(meta.label, c[1], c[2], c[3])
                GameTooltip:AddLine("Drag to reorder, or click to move", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end
        end)

        row:SetScript("OnLeave", function(self)
            if not ds.dragging then
                self:SetBackdropBorderColor(c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 0.6)
                self.grip:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.6)
                GameTooltip:Hide()
            end
        end)

        row:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" or ds.dragging then return end
            local cx, cy = GetCursorPosition()
            ds._pendingRow = self
            ds._pendingIdx = capturedIdx
            ds._pendingMeta = meta
            ds._pendingColor = c
            ds._startCX = cx
            ds._startCY = cy
            ds._dragStarted = false

            ds.ghost:SetScript("OnUpdate", function(g)
                if ds._dragStarted then
                    local gcx, gcy = GetCursorPosition()
                    local scale = UIParent:GetEffectiveScale()
                    g:ClearAllPoints()
                    g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", gcx / scale, gcy / scale)

                    local parentTop = parent:GetTop()
                    if not parentTop then return end
                    local cursorY = gcy / scale
                    local listTop = parentTop + yStart
                    local relY = listTop - cursorY
                    local dropIdx = math.floor(relY / LIST_ROW_H) + 1
                    dropIdx = math.max(1, math.min(dropIdx, #orderTable))
                    ds.dropIdx = dropIdx

                    local line = ds.dropLine
                    local lineY = yStart - (dropIdx - 1) * LIST_ROW_H
                    if dropIdx > ds.dragIdx then
                        lineY = yStart - dropIdx * LIST_ROW_H
                    end
                    line:ClearAllPoints()
                    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, lineY + 1)
                    line:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
                    line:Show()
                else
                    local ncx, ncy = GetCursorPosition()
                    if not ds._startCX then
                        g:SetScript("OnUpdate", nil)
                        return
                    end
                    local dx = math.abs(ncx - ds._startCX)
                    local dy = math.abs(ncy - ds._startCY)
                    if dx + dy > 6 then
                        ds._dragStarted = true
                        ds.dragging = true
                        ds.dragIdx = ds._pendingIdx
                        local m = ds._pendingMeta
                        local pc = ds._pendingColor
                        g.icon:SetTexture(m.icon or "")
                        g.label:SetText(m.label)
                        g.label:SetTextColor(pc[1], pc[2], pc[3])
                        g.bg:SetColorTexture(pc[1] * 0.2, pc[2] * 0.2, pc[3] * 0.25, 0.95)
                        g.border:SetColorTexture(pc[1] * 0.6, pc[2] * 0.6, pc[3] * 0.8, 0.8)
                        g:Show()
                        if ds._pendingRow then ds._pendingRow:SetAlpha(0.3) end
                        GameTooltip:Hide()
                    end
                end
            end)
        end)

        row:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end

            if ds.dragging and ds._dragStarted then
                ds.dragging = false
                ds._dragStarted = false
                if ds._pendingRow then ds._pendingRow:SetAlpha(1) end
                ds.ghost:Hide()
                ds.ghost:SetScript("OnUpdate", nil)
                ds.dropLine:Hide()

                local from = ds.dragIdx
                local to = ds.dropIdx or from
                if from ~= to then
                    local moved = table.remove(orderTable, from)
                    table.insert(orderTable, to, moved)
                    onChanged()
                end
            else
                ds.ghost:SetScript("OnUpdate", nil)
                ds.ghost:Hide()
                ds.dragging = false
                ds._dragStarted = false
                ds._startCX = nil
                if capturedIdx > 1 then
                    orderTable[capturedIdx], orderTable[capturedIdx - 1] = orderTable[capturedIdx - 1], orderTable[capturedIdx]
                else
                    local moved = table.remove(orderTable, 1)
                    table.insert(orderTable, moved)
                end
                onChanged()
            end
        end)

        row:Show()
        y = y - LIST_ROW_H
    end

    return y
end
