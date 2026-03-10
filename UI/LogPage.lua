-- UI/LogPage.lua
-- Completed items log tab
local addonName, ns = ...

local UI = ns.UI

--------------------------
-- Log Page Rendering
--------------------------

function UI:RenderLog(startRowIndex)
    local rowIndex = startRowIndex or 0

    if not ns.db or #ns.db.log == 0 then
        rowIndex = rowIndex + 1
        local row = self:GetOrCreateRow(rowIndex)
        row.icon:SetTexture(nil)
        row.text:SetText(ns.COLORS.GRAY .. "No posted items yet. Right-click queue items to mark as posted." .. ns.COLORS.RESET)
        row:Show()
        return rowIndex
    end

    -- Header with clear button hint
    rowIndex = rowIndex + 1
    local headerRow = self:GetOrCreateRow(rowIndex)
    headerRow.icon:SetTexture(nil)
    headerRow.text:SetText(ns.COLORS.YELLOW .. #ns.db.log .. " posted items" .. ns.COLORS.RESET ..
        ns.COLORS.GRAY .. "  (Shift+Right-click to remove from log)" .. ns.COLORS.RESET)
    headerRow:Show()

    -- Column headers
    rowIndex = rowIndex + 1
    local colRow = self:GetOrCreateRow(rowIndex)
    colRow.icon:SetTexture(nil)
    colRow.text:SetText(ns.COLORS.GRAY ..
        "  Item                          Posted For    FP Guide      Realm             Character" ..
        ns.COLORS.RESET)
    colRow:Show()

    -- Sort log by postedAt descending (newest first)
    local sorted = {}
    for i, entry in ipairs(ns.db.log) do
        table.insert(sorted, {index = i, entry = entry})
    end
    table.sort(sorted, function(a, b) return (a.entry.postedAt or 0) > (b.entry.postedAt or 0) end)

    for _, data in ipairs(sorted) do
        local entry = data.entry
        rowIndex = rowIndex + 1
        local row = self:GetOrCreateRow(rowIndex)

        -- Format posted date
        local dateStr = ""
        if entry.postedAt then
            dateStr = date("%m/%d %H:%M", entry.postedAt)
        end

        -- Format prices with comparison
        local postedPrice = entry.postedPrice or "?"
        local expectedPrice = entry.expectedPrice or "?"

        local priceColor = ns.COLORS.WHITE
        -- Simple comparison: if both are gold strings, compare
        -- (Just visual, not a precise comparison)

        local realmStr = ""
        if entry.targetRealm and entry.targetRealm ~= "" then
            -- Truncate long realm strings
            local realm = entry.targetRealm
            if #realm > 18 then
                realm = realm:sub(1, 16) .. ".."
            end
            realmStr = realm
        end

        local charStr = entry.charKey or ""

        -- Status indicator
        local statusStr = ""
        if entry.soldAt then
            statusStr = ns.COLORS.GREEN .. " SOLD" .. ns.COLORS.RESET
        end

        row.icon:SetTexture(nil)
        row.tooltipItemID = entry.itemID
        row.tooltipItemName = entry.name
        row.tooltipExtra = string.format("Posted: %s\nPosted for: %s\nFP suggested: %s\nRealm: %s\nCharacter: %s",
            dateStr, postedPrice, expectedPrice, entry.targetRealm or "?", charStr)

        row.text:SetText(string.format("  %s%s|r  %s%s|r  %s%s|r  %s%s|r  %s%s|r%s",
            ns.COLORS.WHITE, entry.name or "?",
            ns.COLORS.GREEN, postedPrice,
            ns.COLORS.YELLOW, expectedPrice,
            ns.COLORS.BLUE, realmStr,
            ns.COLORS.GRAY, charStr,
            statusStr
        ))

        -- Shift+Right-click to remove from log
        local capturedIndex = data.index
        row:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and IsShiftKeyDown() then
                table.remove(ns.db.log, capturedIndex)
                ns:Print("Removed from log: " .. (entry.name or "?"))
                UI:Refresh()
            end
        end)

        row:Show()
    end

    return rowIndex
end
