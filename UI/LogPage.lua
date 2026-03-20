-- UI/LogPage.lua
-- Log page: posted items log with filtering and status display
local addonName, ns = ...

local UI = ns.UI

local function BuildLogData()
    if not ns.db then return {} end
    local LookupItemInfo = UI._LookupItemInfo
    local QualityColorName = UI._QualityColorName
    local data = {}

    for i, entry in ipairs(ns.db.log) do
        local dateStr = ""
        if entry.postedAt then
            dateStr = date("%m/%d %H:%M", entry.postedAt)
        end

        local icon, quality, resolvedID = LookupItemInfo(entry.itemID, entry.itemKey, entry.name)
        local displayName = entry.name or "?"
        if quality then
            displayName = QualityColorName(displayName, quality)
        elseif entry.quality and entry.quality ~= "" then
            displayName = QualityColorName(displayName, entry.quality)
        end

        -- Status display
        local aStatus = entry.auctionStatus or "active"
        local statusStr
        if aStatus == "sold" then
            statusStr = ns.COLORS.GREEN .. "Sold" .. "|r"
        elseif aStatus == "expired" then
            statusStr = ns.COLORS.RED .. "Expired" .. "|r"
        elseif aStatus == "collected" then
            statusStr = ns.COLORS.GRAY .. "Done" .. "|r"
        else
            statusStr = ns.COLORS.YELLOW .. "Active" .. "|r"
        end

        -- Price display: show sold price if sold, posted price otherwise
        local priceStr
        if aStatus == "sold" and entry.soldPrice and entry.soldPrice > 0 then
            priceStr = ns.COLORS.GREEN .. ns:FormatGold(entry.soldPrice) .. "|r"
        else
            priceStr = entry.postedPrice or "?"
        end

        -- Recovered entry indicator
        if entry.isRecovered then
            statusStr = statusStr .. " *"
        end

        -- Tooltip with sale info
        local tooltipExtra = string.format("Posted: %s\nListed for: %s\nFP suggested: %s",
            dateStr, entry.postedPrice or "?", entry.expectedPrice or "?")
        if entry.isRecovered then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.YELLOW .. "Recovered from AH (approx. post time)|r"
        end
        if aStatus == "sold" then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.GREEN .. "Sold for: " ..
                (entry.soldPrice and entry.soldPrice > 0 and ns:FormatGold(entry.soldPrice) or "unknown") .. "|r"
            if entry.soldAt then
                tooltipExtra = tooltipExtra .. "\nSold: " .. date("%m/%d %H:%M", entry.soldAt)
            end
        elseif aStatus == "expired" then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.RED .. "Auction expired|r"
        end

        table.insert(data, {
            name      = displayName,
            qty       = entry.postedQuantity or 1,
            status    = statusStr,
            posted    = priceStr,
            guide     = entry.expectedPrice or "?",
            realm     = entry.targetRealm or "",
            character = entry.charKey or "",
            date      = dateStr,
            _icon     = icon,
            _sortDate = entry.postedAt or 0,
            _tooltipItemID = resolvedID,
            _tooltipText   = entry.name,
            _tooltipExtra  = tooltipExtra,
            _logIndex = i,
        })
    end

    return data
end

function UI:RefreshLogPage()
    local mainFrame = UI.mainFrame
    mainFrame.pageTitle:SetText(ns.COLORS.GREEN .. "Posted Items Log" .. "|r")
    UI._LayoutActionBtns(mainFrame.actionBtns.clearLog)
    UI._ShowTable(self.logTable)

    local data = BuildLogData()
    self.logTable:SetRowClickHandler(function(rowData, button)
        if button == "RightButton" and IsShiftKeyDown() and rowData._logIndex then
            table.remove(ns.db.log, rowData._logIndex)
            ns:Print("Removed from log: " .. rowData.name)
            self:Refresh()
        end
    end)
    self.logTable:SetData(data)

    local logCount = #ns.db.log
    local soldCount, activeCount, expiredCount = 0, 0, 0
    for _, entry in ipairs(ns.db.log) do
        if entry.auctionStatus == "sold" then soldCount = soldCount + 1
        elseif entry.auctionStatus == "expired" then expiredCount = expiredCount + 1
        elseif entry.auctionStatus == "active" then activeCount = activeCount + 1
        end
    end
    local logStatus = logCount .. " logged"
    local parts = {}
    if soldCount > 0 then table.insert(parts, ns.COLORS.GREEN .. soldCount .. " sold|r") end
    if activeCount > 0 then table.insert(parts, ns.COLORS.YELLOW .. activeCount .. " active|r") end
    if expiredCount > 0 then table.insert(parts, ns.COLORS.RED .. expiredCount .. " expired|r") end
    if #parts > 0 then logStatus = logStatus .. " (" .. table.concat(parts, ", ") .. ")" end
    logStatus = logStatus .. "  |  Shift+Right-click to remove"
    mainFrame.statusText:SetText(logStatus)
end
