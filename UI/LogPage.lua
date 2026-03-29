-- UI/LogPage.lua
-- Log page: posted items log with paging to handle large logs
local addonName, ns = ...

local UI = ns.UI

local LOG_PAGE_SIZE = 200
local logPageOffset = 0  -- 0 = most recent page

local function BuildLogData(startIdx, endIdx)
    if not ns.db or not ns.db.log then return {} end
    local LookupItemInfo = UI._LookupItemInfo
    local QualityColorName = UI._QualityColorName
    local data = {}

    -- Iterate newest-first within the page range
    for i = endIdx, startIdx, -1 do
        local entry = ns.db.log[i]
        if not entry then break end

        local dateStr = ""
        if entry.postedAt then
            dateStr = date("%m/%d %H:%M", entry.postedAt)
        end

        local icon, quality, resolvedID
        if LookupItemInfo then
            icon, quality, resolvedID = LookupItemInfo(entry.itemID, entry.itemKey, entry.name)
        end
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
        elseif aStatus == "cancelled" then
            statusStr = ns.COLORS.ORANGE .. "Cancelled" .. "|r"
        elseif aStatus == "expired" then
            statusStr = ns.COLORS.RED .. "Expired" .. "|r"
        elseif aStatus == "collected" then
            if entry.saleOutcome == "sold" then
                statusStr = ns.COLORS.GREEN .. "Sold" .. "|r"
            elseif entry.saleOutcome == "expired" then
                statusStr = ns.COLORS.ORANGE .. "Unsold" .. "|r"
            else
                statusStr = ns.COLORS.GRAY .. "Done" .. "|r"
            end
        elseif aStatus == "skipped" then
            statusStr = ns.COLORS.ORANGE .. "Skipped" .. "|r"
        else
            statusStr = ns.COLORS.YELLOW .. "Active" .. "|r"
        end

        if (entry.postAttempts or 0) > 0 then
            statusStr = statusStr .. ns.COLORS.RED .. " (" .. entry.postAttempts .. "x)" .. "|r"
        end

        -- Price display
        local priceStr
        if (aStatus == "sold" or entry.saleOutcome == "sold") and entry.soldPrice and entry.soldPrice > 0 then
            priceStr = ns.COLORS.GREEN .. ns:FormatGold(entry.soldPrice) .. "|r"
        else
            priceStr = entry.postedPrice or "?"
        end

        if entry.isRecovered then
            statusStr = statusStr .. " *"
        end

        -- Tooltip
        local tooltipExtra = string.format("Posted: %s\nListed for: %s\nFP suggested: %s",
            dateStr, entry.postedPrice or "?", entry.expectedPrice or "?")
        if entry.isRecovered then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.YELLOW .. "Recovered from AH (approx. post time)|r"
        end
        if aStatus == "sold" or entry.saleOutcome == "sold" then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.GREEN .. "Sold for: " ..
                (entry.soldPrice and entry.soldPrice > 0 and ns:FormatGold(entry.soldPrice) or "unknown") .. "|r"
            if entry.soldAt then
                tooltipExtra = tooltipExtra .. "\nSold: " .. date("%m/%d %H:%M", entry.soldAt)
            end
        elseif aStatus == "expired" or entry.saleOutcome == "expired" then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.RED .. "Auction expired (unsold)|r"
        elseif aStatus == "skipped" and entry.failReason then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.ORANGE .. entry.failReason .. "|r"
        end

        if (entry.postAttempts or 0) > 0 then
            tooltipExtra = tooltipExtra .. "\n\n" .. ns.COLORS.RED ..
                "Failed sale attempts: " .. entry.postAttempts .. "|r"
            if (entry.totalFeesSpent or 0) > 0 then
                tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.RED ..
                    "Total AH fees lost: " .. ns:FormatGold(entry.totalFeesSpent) .. "|r"
            end
            if entry.postHistory and #entry.postHistory > 0 then
                tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.GRAY .. "Post history:|r"
                for hi, attempt in ipairs(entry.postHistory) do
                    local attemptDate = attempt.postedAt and date("%m/%d %H:%M", attempt.postedAt) or "?"
                    local attemptStr = "  #" .. hi .. ": " .. attemptDate ..
                        " @ " .. (attempt.postedPrice or "?")
                    if attempt.fee and attempt.fee > 0 then
                        attemptStr = attemptStr .. " (fee: " .. ns:FormatGold(attempt.fee) .. ")"
                    end
                    tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.GRAY .. attemptStr .. "|r"
                    if attempt.tsmMinBuyout or attempt.tsmRegionSaleAvg then
                        local tsmStr = "    TSM:"
                        if attempt.tsmMinBuyout then
                            tsmStr = tsmStr .. " AH min " .. ns:FormatGold(attempt.tsmMinBuyout)
                        end
                        if attempt.tsmRegionSaleAvg then
                            tsmStr = tsmStr .. " | Region avg " .. ns:FormatGold(attempt.tsmRegionSaleAvg)
                        end
                        tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.GRAY .. tsmStr .. "|r"
                    end
                end
            end
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

-- Build summary stats from full log (counting only, no API calls — fast even for 8000+)
local function BuildLogStats()
    if not ns.db or not ns.db.log then return 0, "" end
    local logCount = #ns.db.log
    local soldCount, activeCount, expiredCount, skippedCount, unsoldCount = 0, 0, 0, 0, 0
    local totalFeesLost = 0
    for _, entry in ipairs(ns.db.log) do
        if entry.auctionStatus == "sold" then
            soldCount = soldCount + 1
        elseif entry.auctionStatus == "expired" then
            expiredCount = expiredCount + 1
        elseif entry.auctionStatus == "active" then
            activeCount = activeCount + 1
        elseif entry.auctionStatus == "skipped" then
            skippedCount = skippedCount + 1
        elseif entry.auctionStatus == "collected" and entry.saleOutcome == "sold" then
            soldCount = soldCount + 1
        elseif entry.auctionStatus == "collected" and entry.saleOutcome == "expired" then
            unsoldCount = unsoldCount + 1
        end
        if (entry.totalFeesSpent or 0) > 0 then
            totalFeesLost = totalFeesLost + entry.totalFeesSpent
        end
    end
    local parts = {}
    if soldCount > 0 then table.insert(parts, ns.COLORS.GREEN .. soldCount .. " sold|r") end
    if activeCount > 0 then table.insert(parts, ns.COLORS.YELLOW .. activeCount .. " active|r") end
    if expiredCount > 0 then table.insert(parts, ns.COLORS.RED .. expiredCount .. " expired|r") end
    if unsoldCount > 0 then table.insert(parts, ns.COLORS.ORANGE .. unsoldCount .. " unsold|r") end
    if skippedCount > 0 then table.insert(parts, ns.COLORS.ORANGE .. skippedCount .. " skipped|r") end
    local statsStr = logCount .. " logged"
    if #parts > 0 then statsStr = statsStr .. " (" .. table.concat(parts, ", ") .. ")" end
    if totalFeesLost > 0 then
        statsStr = statsStr .. "  |  " .. ns.COLORS.RED .. "Fees lost: " .. ns:FormatGold(totalFeesLost) .. "|r"
    end
    return logCount, statsStr
end

function UI:RefreshLogPage()
    local mainFrame = UI.mainFrame
    mainFrame.pageTitle:SetText(ns.COLORS.GREEN .. "Posted Items Log" .. "|r")
    UI._LayoutActionBtns(mainFrame.actionBtns.clearLog)
    UI._ShowTable(self.logTable)

    local total = ns.db and ns.db.log and #ns.db.log or 0
    local totalPages = math.max(1, math.ceil(total / LOG_PAGE_SIZE))

    -- Clamp page offset
    if logPageOffset >= totalPages then logPageOffset = totalPages - 1 end
    if logPageOffset < 0 then logPageOffset = 0 end

    -- Page range: most recent entries first
    local endIdx = total - logPageOffset * LOG_PAGE_SIZE
    local startIdx = math.max(1, endIdx - LOG_PAGE_SIZE + 1)
    if endIdx < 1 then endIdx = 0; startIdx = 1 end

    local data = BuildLogData(startIdx, endIdx)

    self.logTable:SetRowClickHandler(function(rowData, button)
        if button == "RightButton" and IsShiftKeyDown() and rowData._logIndex then
            table.remove(ns.db.log, rowData._logIndex)
            ns:Print("Removed from log: " .. rowData.name)
            self:Refresh()
        end
    end)
    self.logTable:SetData(data)

    -- Status: stats + page nav
    local logCount, statsStr = BuildLogStats()

    local pageStr = ""
    if totalPages > 1 then
        local curPage = logPageOffset + 1
        pageStr = "  |  Page " .. curPage .. "/" .. totalPages
            .. "  (Ctrl+Left/Right to navigate)"
    end
    statsStr = statsStr .. pageStr
    statsStr = statsStr .. "  |  Shift+Right-click to remove"
    mainFrame.statusText:SetText(statsStr)

    -- Register page navigation keys while log is shown
    if not self._logPageKeyFrame then
        local kf = CreateFrame("Frame", nil, mainFrame)
        kf:EnableKeyboard(true)
        kf:SetPropagateKeyboardInput(true)
        kf:SetScript("OnKeyDown", function(_, key)
            if not IsControlKeyDown() then return end
            if key == "LEFT" then
                if logPageOffset < totalPages - 1 then
                    logPageOffset = logPageOffset + 1
                    kf:SetPropagateKeyboardInput(false)
                    C_Timer.After(0, function()
                        kf:SetPropagateKeyboardInput(true)
                        UI:RefreshLogPage()
                    end)
                end
            elseif key == "RIGHT" then
                if logPageOffset > 0 then
                    logPageOffset = logPageOffset - 1
                    kf:SetPropagateKeyboardInput(false)
                    C_Timer.After(0, function()
                        kf:SetPropagateKeyboardInput(true)
                        UI:RefreshLogPage()
                    end)
                end
            end
        end)
        self._logPageKeyFrame = kf
    end
    self._logPageKeyFrame:Show()
end

-- Hide page nav keys when leaving log page
local origHideAllActionBtns = UI._HideAllActionBtns
if origHideAllActionBtns then
    UI._HideAllActionBtns = function(...)
        if UI._logPageKeyFrame then UI._logPageKeyFrame:Hide() end
        return origHideAllActionBtns(...)
    end
end
