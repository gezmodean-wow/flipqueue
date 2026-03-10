-- UI/Rows.lua
-- Shared row pool for scrollable content
local addonName, ns = ...

local UI = ns.UI or {}
ns.UI = UI

UI.ROW_HEIGHT = 22
UI.contentRows = {}
UI.content = nil -- set by MainFrame after creation

function UI:CreateRow(parent, index)
    local ROW_HEIGHT = self.ROW_HEIGHT
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.tooltipItemID = nil
    row.tooltipItemName = nil
    row.tooltipExtra = nil

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.1)
        if self.tooltipItemID or self.tooltipItemName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local numID = tonumber(self.tooltipItemID)
            if numID and numID > 0 then
                GameTooltip:SetItemByID(numID)
            elseif self.tooltipItemName and self.tooltipItemName ~= "" then
                GameTooltip:SetText(self.tooltipItemName, 1, 1, 1)
                if self.tooltipExtra then
                    GameTooltip:AddLine(self.tooltipExtra, 0.7, 0.7, 0.7, true)
                end
                GameTooltip:Show()
            end
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
        GameTooltip:Hide()
    end)

    return row
end

function UI:GetOrCreateRow(index)
    if not self.contentRows[index] then
        self.contentRows[index] = self:CreateRow(self.content, index)
    end
    return self.contentRows[index]
end

function UI:HideAllRows()
    for _, row in ipairs(self.contentRows) do
        row:Hide()
        row:SetScript("OnMouseUp", nil)
        row.tooltipItemID = nil
        row.tooltipItemName = nil
        row.tooltipExtra = nil
    end
end

-- Create a collapsible section header
-- Returns true if collapsed (caller should skip content rows)
function UI:CreateSectionHeader(rowIndex, sectionKey, label, color, itemCount)
    local row = self:GetOrCreateRow(rowIndex)
    local isCollapsed = ns.db and ns.db.settings.collapsed[sectionKey]
    local arrow = isCollapsed and "[+] " or "[-] "
    local countStr = itemCount and (" (" .. itemCount .. ")") or ""

    row.icon:SetTexture(nil)
    row.text:SetText((color or "") .. arrow .. label .. countStr .. ns.COLORS.RESET)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            ns.db.settings.collapsed[sectionKey] = not ns.db.settings.collapsed[sectionKey]
            ns.UI:Refresh()
        end
    end)
    row:Show()
    return isCollapsed
end
