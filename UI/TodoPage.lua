-- UI/TodoPage.lua
-- To-Do page rendering: character tasks, next steps, grouped display, right-click menus
local addonName, ns = ...

local UI = ns.UI

-- ==========================================
-- DATA BUILDERS
-- ==========================================

local function BuildPostNowData()
    if not ns.db then return {} end
    local LookupItemInfo = UI._LookupItemInfo
    local QualityColorName = UI._QualityColorName

    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""
    local tasks = ns.TodoList:GetCharacterTasks(charKey)
    local data = {}

    for _, task in ipairs(tasks) do
        if ns:RealmMatches(task.item.targetRealm, myRealm) then
            local qi = task.item
            local displayName = qi.name ~= "" and qi.name or tostring(qi.itemID)

            local lookupIcon, quality, resolvedID
            pcall(function()
                lookupIcon, quality, resolvedID = LookupItemInfo(qi.itemID, qi.itemKey, qi.name)
            end)

            if quality then
                displayName = QualityColorName(displayName, quality)
            elseif qi.quality and qi.quality ~= "" then
                displayName = QualityColorName(displayName, qi.quality)
            end

            local locParts = {}
            if task.locations then
                for loc, qty in pairs(task.locations) do
                    table.insert(locParts, loc)
                end
            end

            local row = {
                name     = displayName,
                qty      = task.quantity,
                price    = qi.expectedPrice or "",
                realm    = qi.targetRealm or "",
                location = table.concat(locParts, ", "),
                _icon    = task.icon or lookupIcon,
                _tooltipItemID = resolvedID,
                _tooltipText   = qi.name ~= "" and qi.name or tostring(qi.itemID),
                _tooltipExtra  = (qi.targetRealm or "") ~= "" and
                    ("Sell on: " .. qi.targetRealm .. "  @  " .. (qi.expectedPrice or "?")) or nil,
                _taskIndex = task.taskIndex,
                _queueItem  = qi,
                _fuzzy = task.fuzzyMatch,
            }

            -- TSM price data
            if ns.TSM:IsEnabled() then
                local priceSource = ns.db.settings.tsmPriceSource or "DBMinBuyout"
                local copper = ns.TSM:GetPrice(qi.itemKey, priceSource)
                if copper then
                    row.ahPrice = ns.TSM:FormatCopper(copper)
                    row._sortAhPrice = copper

                    local belowThreshold, ahMin, threshold, opName = ns.TSM:IsBelowThreshold(qi.itemKey)
                    if belowThreshold then
                        row.ahPrice = "|cffff4444" .. row.ahPrice .. "|r"
                        row._rowColor = {0.8, 0.2, 0.2, 0.10}
                        row.location = "|cffff4444TSM: SKIP|r"
                        local threshStr = ns.TSM:FormatCopper(threshold) or "?"
                        local opStr = opName and (" [" .. opName .. "]") or ""
                        row._tooltipExtra = (row._tooltipExtra or "")
                            .. "\n|cffff4444TSM will skip this item — AH price below min (" .. threshStr .. ")" .. opStr .. "|r"
                            .. "\n|cffff4444Right-click to skip, or wait for price to recover|r"
                    else
                        row.ahPrice = "|cff00ff00" .. row.ahPrice .. "|r"
                    end

                    -- Auto-update expected price
                    if ns.db.settings.tsmAutoUpdatePrice then
                        local maxAge = ns.db.settings.tsmPriceMaxAge or 3600
                        local priceAge = qi.priceUpdatedAt or qi.addedAt or 0
                        if maxAge == 0 or (time() - priceAge) > maxAge then
                            qi.expectedPrice = ns:FormatGold(copper)
                            qi.priceSource = "TSM"
                            qi.priceUpdatedAt = time()
                            row.price = qi.expectedPrice
                        end
                    end
                else
                    row.ahPrice = "|cff888888" .. "\226\128\148" .. "|r"
                    row._sortAhPrice = 0
                end
            end

            table.insert(data, row)
        end
    end

    return data
end

local function BuildTodoData()
    if not ns.db or not ns.TodoList then return nil end
    local LookupItemInfo = UI._LookupItemInfo
    local QualityColorName = UI._QualityColorName
    local currentList = ns.TodoList:GetCurrentList()
    if not currentList then return nil end

    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""
    local tasks = ns.TodoList:GetCharacterTasks(charKey)
    local data = {}

    for _, task in ipairs(tasks) do
        local item = task.item
        if ns:RealmMatches(item.targetRealm or "", myRealm) then
            local displayName = item.name or "?"

            local lookupIcon, quality, resolvedID
            pcall(function()
                lookupIcon, quality, resolvedID = LookupItemInfo(item.itemID, item.itemKey, item.name)
            end)

            if quality then
                displayName = QualityColorName(displayName, quality)
            elseif item.quality and item.quality ~= "" then
                displayName = QualityColorName(displayName, item.quality)
            end

            local sourceStr = item.source or ""
            if sourceStr == "warbank" then
                sourceStr = ns.COLORS.YELLOW .. "warbank" .. "|r"
            elseif sourceStr == "bags" then
                sourceStr = ns.COLORS.GREEN .. "in bags" .. "|r"
            elseif sourceStr == "bank" then
                sourceStr = ns.COLORS.BLUE .. "bank" .. "|r"
            elseif sourceStr == "reagent" then
                sourceStr = "reagent"
            elseif sourceStr == "guildbank" then
                sourceStr = ns.COLORS.ORANGE .. "guild bank" .. "|r"
            elseif sourceStr == "unavailable" and item.depositFrom then
                local depName = item.depositFrom:match("^(.-)%-") or item.depositFrom
                sourceStr = ns.COLORS.CYAN .. "via " .. depName .. "|r"
            elseif sourceStr == "unavailable" then
                sourceStr = ns.COLORS.RED .. "unavailable" .. "|r"
            end

            local row = {
                name     = displayName,
                qty      = item.quantity or 1,
                price    = item.expectedPrice or "",
                realm    = item.targetRealm or "",
                location = sourceStr,
                _icon    = item.icon or lookupIcon,
                _tooltipItemID = resolvedID or tonumber(item.itemID),
                _tooltipText   = item.name or "?",
                _tooltipExtra  = (item.targetRealm and item.targetRealm ~= ""
                    and ("Sell on: " .. item.targetRealm .. "  @  " .. (item.expectedPrice or "?")) or nil),
                _taskIndex = task.taskIndex,
                _todoItem  = item,
            }

            -- TSM price data
            if ns.TSM:IsEnabled() then
                local priceSource = ns.db.settings.tsmPriceSource or "DBMinBuyout"
                local copper = ns.TSM:GetPrice(item.itemKey, priceSource)
                if copper then
                    row.ahPrice = ns.TSM:FormatCopper(copper)
                    row._sortAhPrice = copper
                    local belowThreshold, _, threshold, opName = ns.TSM:IsBelowThreshold(item.itemKey)
                    if belowThreshold then
                        row.ahPrice = "|cffff4444" .. row.ahPrice .. "|r"
                        row._rowColor = {0.8, 0.2, 0.2, 0.10}
                        row.location = "|cffff4444TSM: SKIP|r"
                    else
                        row.ahPrice = "|cff00ff00" .. row.ahPrice .. "|r"
                    end
                else
                    row.ahPrice = "|cff888888" .. "\226\128\148" .. "|r"
                    row._sortAhPrice = 0
                end
            end

            table.insert(data, row)
        end
    end

    return data
end

-- ==========================================
-- TODO PAGE REFRESH
-- ==========================================

function UI:RefreshTodoPage()
    local mainFrame = UI.mainFrame
    local tableContainer = UI.tableContainer
    local LookupItemInfo = UI._LookupItemInfo
    local QualityColorName = UI._QualityColorName
    local CLASS_COLORS = UI._CLASS_COLORS
    local FormatGoldValue = UI._FormatGoldValue

    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""

    local todoPageTitle = ns.COLORS.GREEN .. "To-Do" .. "|r" ..
        ns.COLORS.GRAY .. " - " .. charKey .. "|r"
    local currentTodoListForTitle = ns.TodoList and ns.TodoList:GetCurrentList()
    if currentTodoListForTitle and currentTodoListForTitle.importType then
        todoPageTitle = todoPageTitle .. "  " .. ns.COLORS.GRAY .. "[" .. currentTodoListForTitle.importType .. "]" .. "|r"
    end
    mainFrame.pageTitle:SetText(todoPageTitle)
    UI._LayoutActionBtns(mainFrame.actionBtns.clearTodoList, mainFrame.actionBtns.rescan, mainFrame.actionBtns.pullBank)

    -- Try TodoList first, fall back to queue-based data
    local todoData = BuildTodoData()
    local data = todoData or BuildPostNowData()

    local currentTodoList = ns.TodoList and ns.TodoList:GetCurrentList()
    local totalTodoTasks = currentTodoList and ns.TodoList:GetPendingCount() or 0
    local thisCharTasks = #data
    local nextData = UI.BuildNextStepsData()
    local myTasks = UI.BuildCurrentCharTasks()

    -- Count post items for status
    local postCount = 0
    if ns.TodoList and ns.TodoList:GetCurrentList() then
        local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(todoTasks) do
            if ns:RealmMatches(task.item.targetRealm or "", myRealm) then
                postCount = postCount + 1
            end
        end
    end

    -- Current character tasks frame (Check AH, Check Mail, Expiring)
    if not self._charTasksFrame then
        local ctf = CreateFrame("Frame", nil, tableContainer)
        ctf:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
        ctf:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
        ctf:SetHeight(1)
        ctf.rows = {}
        self._charTasksFrame = ctf
    end

    -- Hide old task rows
    for _, row in ipairs(self._charTasksFrame.rows) do
        row:Hide()
    end

    local charTaskHeight = 0
    if #myTasks > 0 then
        self._charTasksFrame:Show()
        for i, task in ipairs(myTasks) do
            local row = self._charTasksFrame.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, self._charTasksFrame)
                row:SetHeight(22)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(16, 16)
                row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                row.text:SetJustifyH("LEFT")
                self._charTasksFrame.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self._charTasksFrame, "TOPLEFT", 0, -(i - 1) * 22)
            row:SetPoint("RIGHT", self._charTasksFrame, "RIGHT", 0, 0)
            row.bg:SetColorTexture(0.12, 0.15, 0.12, 0.6)
            row.icon:SetTexture(task.icon)
            row.text:SetText(task.text)
            row:Show()
        end
        charTaskHeight = #myTasks * 22 + 4
        self._charTasksFrame:SetHeight(charTaskHeight)
    else
        self._charTasksFrame:Hide()
        charTaskHeight = 0
    end

    local contentOffset = -charTaskHeight

    -- Create summary banner (reused across refreshes)
    if not self._postSummaryFrame then
        local sf = CreateFrame("Frame", nil, tableContainer)
        sf:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
        sf:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
        sf:SetHeight(60)
        self._postSummaryFrame = sf

        sf.title = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        sf.title:SetPoint("TOP", sf, "TOP", 0, -10)

        sf.sub = sf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sf.sub:SetPoint("TOP", sf.title, "BOTTOM", 0, -6)
        sf.sub:SetWidth(sf:GetWidth() - 40)
        sf.sub:SetJustifyH("CENTER")

        -- "Open Generator" button for empty states
        local genBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
        genBtn:SetSize(160, 28)
        genBtn:SetPoint("TOP", sf.sub, "BOTTOM", 0, -10)
        genBtn:SetText("Open To-Do Generator")
        genBtn:SetScript("OnClick", function()
            UI.currentPage = "generator"
            UI:Refresh()
        end)
        sf.genBtn = genBtn

        sf:SetScript("OnSizeChanged", function(self, w)
            sf.sub:SetWidth(w - 40)
        end)
    end

    if #data == 0 then
        -- Nothing to post on this character
        self._postSummaryFrame:Hide()
        self._postSummaryFrame.genBtn:Hide()

        if totalTodoTasks == 0 and #nextData == 0 and #myTasks == 0 and ns:ImportGetCount("fpScanner") == 0 then
            -- Everything is done!
            self._postSummaryFrame:Show()
            self._postSummaryFrame:ClearAllPoints()
            self._postSummaryFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, contentOffset)
            self._postSummaryFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", 0, 0)
            local doneMessages = {
                {title = "All done!", sub = "Time to go shopping on FlippingPal!"},
                {title = "Queue empty!", sub = "Hit the AH browser or import more flips."},
                {title = "Everything posted!", sub = "Now sit back and wait for the gold to roll in."},
                {title = "Nothing to do!", sub = "Browse FlippingPal.com for your next deals."},
            }
            local msg = doneMessages[math.random(#doneMessages)]
            self._postSummaryFrame.title:ClearAllPoints()
            self._postSummaryFrame.title:SetPoint("CENTER", self._postSummaryFrame, "CENTER", 0, 20)
            self._postSummaryFrame.title:SetText(ns.COLORS.GREEN .. msg.title .. "|r")
            self._postSummaryFrame.sub:SetText(ns.COLORS.GRAY .. msg.sub .. "|r")
            self._postSummaryFrame.genBtn:Show()
            mainFrame.statusText:SetText("Queue empty  |  Import items from FlippingPal to get started")

        elseif totalTodoTasks > 0 and currentTodoList then
            -- Show the FULL to-do list grouped by character
            if not self._todoOverviewScroll then
                local s = CreateFrame("ScrollFrame", nil, tableContainer, "UIPanelScrollFrameTemplate")
                local c = CreateFrame("Frame", nil, s)
                c:SetWidth(1)
                c:SetHeight(1)
                s:SetScrollChild(c)
                s:SetScript("OnSizeChanged", function(sf, w) c:SetWidth(w) end)
                -- Explicit mouse wheel handling (belt-and-suspenders for TWW template compat)
                s:EnableMouseWheel(true)
                s:SetScript("OnMouseWheel", function(self, delta)
                    local current = self:GetVerticalScroll()
                    local maxScroll = self:GetVerticalScrollRange()
                    local step = 40
                    local newScroll = math.max(0, math.min(current - (delta * step), maxScroll))
                    self:SetVerticalScroll(newScroll)
                end)

                -- Find and stash scroll bar for auto-hide
                local sBar = s.ScrollBar
                if not sBar then
                    for _, child in ipairs({s:GetChildren()}) do
                        if child and child.GetObjectType and child:GetObjectType() == "Slider" then
                            sBar = child; break
                        end
                    end
                end
                s._scrollBar = sBar

                -- Auto-hide scroll bar when nothing to scroll
                s:HookScript("OnScrollRangeChanged", function(sf)
                    local bar = sf._scrollBar
                    if not bar then return end
                    local range = sf:GetVerticalScrollRange()
                    if range and range <= 0.5 then
                        bar:SetAlpha(0)
                        bar:EnableMouse(false)
                    else
                        bar:SetAlpha(1)
                        bar:EnableMouse(true)
                    end
                end)

                self._todoOverviewScroll = s
                self._todoOverviewContent = c
                self._todoOverviewRows = {}
            end

            local todoScroll = self._todoOverviewScroll
            local todoContent = self._todoOverviewContent
            local todoRows = self._todoOverviewRows

            todoScroll:ClearAllPoints()
            todoScroll:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, contentOffset)
            todoScroll:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)
            todoScroll:Show()
            todoContent:SetWidth(todoScroll:GetWidth() or 500)

            for _, row in ipairs(todoRows) do row:Hide() end

            local displayGroups, missingCount = ns.TodoList:BuildDisplayGroups(
                currentTodoList.tasks, UI:GetGenSortMode())

            local HDR_H = 22
            local ITEM_H = 18
            local y = 0
            local rowIdx = 0

            local function GetRow(height)
                rowIdx = rowIdx + 1
                local row = todoRows[rowIdx]
                if not row then
                    row = CreateFrame("Frame", nil, todoContent)
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(14, 14)
                    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                    row.icon:Hide()
                    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                    row.text:SetJustifyH("LEFT")
                    row.text:SetWordWrap(false)
                    row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    row.rightText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                    row.rightText:SetJustifyH("RIGHT")
                    row.rightText:SetWordWrap(false)
                    row.rightText:SetMaxLines(1)
                    row.text:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                    todoRows[rowIdx] = row
                end
                row:SetHeight(height)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", todoContent, "TOPLEFT", 0, -y)
                row:SetPoint("RIGHT", todoContent, "RIGHT", 0, 0)
                row.icon:Hide()
                row.text:SetText("")
                row.rightText:SetText("")
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.text:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                row:Show()
                return row
            end

            for gi, group in ipairs(displayGroups) do
                local isUnassigned = not group.charKey
                local isCurrentChar = group.charKey == charKey

                -- Group header
                local hdr = GetRow(HDR_H)
                if isUnassigned then
                    hdr.bg:SetColorTexture(0.15, 0.08, 0.08, 0.7)
                    local realmName = group.realm ~= "" and group.realm or "unknown realm"
                    hdr.text:SetText(ns.COLORS.RED .. "Create character on " .. realmName .. "|r" ..
                        ns.COLORS.GRAY .. "  (" .. #group.items .. " items)|r")
                elseif isCurrentChar then
                    hdr.bg:SetColorTexture(0.1, 0.2, 0.1, 0.8)
                    local cc = CLASS_COLORS[ns.db.characters[group.charKey] and ns.db.characters[group.charKey].class] or "888888"
                    hdr.text:SetText("|cff" .. cc .. group.charName .. "|r" ..
                        ns.COLORS.GRAY .. " - " .. group.realm .. "|r" ..
                        ns.COLORS.GREEN .. "  (YOU — " .. #group.items .. " items)|r")
                else
                    local charInv = ns.db.characters and ns.db.characters[group.charKey]
                    local cc = charInv and CLASS_COLORS[charInv.class] or "888888"
                    if group._allDeferred then
                        hdr.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
                        hdr.text:SetText("|cff" .. cc .. group.charName .. "|r" ..
                            ns.COLORS.GRAY .. " - " .. group.realm .. "  (" .. #group.items .. " items)" ..
                            ns.COLORS.RED .. " [no inventory]" .. "|r")
                    else
                        hdr.bg:SetColorTexture(0.12, 0.15, 0.2, 0.8)
                        hdr.text:SetText("|cff" .. cc .. group.charName .. "|r" ..
                            ns.COLORS.GRAY .. " - " .. group.realm .. "  (" .. #group.items .. " items)|r")
                    end
                end

                local goldStr = FormatGoldValue(group.totalGold)
                local goldColor = isUnassigned and ns.COLORS.GRAY or ns.COLORS.YELLOW
                hdr.rightText:SetText(goldColor .. "~" .. goldStr .. "|r")
                y = y + HDR_H

                -- Item rows
                for ii, item in ipairs(group.items) do
                    local row = GetRow(ITEM_H)
                    if isUnassigned then
                        row.bg:SetColorTexture(0.1, 0.06, 0.06, 0.4)
                    else
                        row.bg:SetColorTexture(ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.12 or 0.1, 0.5)
                    end

                    local lookupIcon, quality
                    pcall(function()
                        lookupIcon, quality = LookupItemInfo(item.itemID, item.itemKey, item.name)
                    end)
                    local itemIcon = item.icon or lookupIcon
                    if itemIcon then
                        row.icon:SetTexture(itemIcon)
                        row.icon:ClearAllPoints()
                        row.icon:SetPoint("LEFT", row, "LEFT", 14, 0)
                        row.icon:SetDesaturated(isUnassigned)
                        row.icon:SetAlpha(isUnassigned and 0.5 or 1)
                        row.icon:Show()
                        row.text:ClearAllPoints()
                        row.text:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
                        row.text:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                    else
                        row.text:ClearAllPoints()
                        row.text:SetPoint("LEFT", row, "LEFT", 16, 0)
                        row.text:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
                    end

                    local displayName = item.name or "?"
                    if isUnassigned then
                        displayName = ns.COLORS.GRAY .. displayName .. "|r"
                    elseif quality then
                        displayName = QualityColorName(displayName, quality)
                    elseif item.quality and item.quality ~= "" then
                        displayName = QualityColorName(displayName, item.quality)
                    end
                    local qtyStr = (item.quantity or 1) > 1 and (" x" .. (item.quantity or 1)) or ""
                    row.text:SetText(displayName .. qtyStr)

                    -- Right side: price + source status
                    local priceStr = item.expectedPrice or ""
                    local sourceTag = ""
                    if isUnassigned then
                        priceStr = ns.COLORS.GRAY .. priceStr .. "|r"
                    elseif isCurrentChar then
                        local inBags = false
                        pcall(function()
                            for _, bagIdx in ipairs(ns.INVENTORY_BAGS) do
                                local numSlots = C_Container.GetContainerNumSlots(bagIdx)
                                for slot = 1, numSlots do
                                    local info = C_Container.GetContainerItemInfo(bagIdx, slot)
                                    if info and info.hyperlink then
                                        local slotID = tonumber((ns:ParseItemLink(info.hyperlink)))
                                        local itemNumID = tonumber(item.itemID) or tonumber(item.itemKey and item.itemKey:match("^(%d+)"))
                                        if slotID and itemNumID and slotID == itemNumID then
                                            inBags = true
                                            return
                                        end
                                    end
                                end
                            end
                        end)
                        if inBags then
                            sourceTag = ns.COLORS.GREEN .. " [in bags]" .. "|r"
                        elseif item.source == "warbank" then
                            sourceTag = ns.COLORS.YELLOW .. " [warbank]" .. "|r"
                        elseif item.source == "bank" then
                            sourceTag = ns.COLORS.BLUE .. " [bank]" .. "|r"
                        else
                            sourceTag = ns.COLORS.RED .. " [not found]" .. "|r"
                        end
                    else
                        if item.source == "bags" then
                            sourceTag = ns.COLORS.GREEN .. " [bags]" .. "|r"
                        elseif item.source == "warbank" then
                            sourceTag = ns.COLORS.YELLOW .. " [wb]" .. "|r"
                        elseif item.source == "bank" then
                            sourceTag = ns.COLORS.BLUE .. " [bank]" .. "|r"
                        elseif item.source == "guildbank" then
                            sourceTag = ns.COLORS.ORANGE .. " [guild]" .. "|r"
                        elseif item.source == "unavailable" and item.depositFrom then
                            local depName = item.depositFrom:match("^(.-)%-") or item.depositFrom
                            sourceTag = ns.COLORS.CYAN .. " [via " .. depName .. "]" .. "|r"
                        elseif item.source == "unavailable" then
                            sourceTag = ns.COLORS.RED .. " [unavail]" .. "|r"
                        end
                    end
                    -- TSM rejection reassignment indicator
                    if item.tsmRejectedFrom then
                        local fromName = item.tsmRejectedFrom:match("^(.-)%-") or item.tsmRejectedFrom
                        sourceTag = sourceTag .. ns.COLORS.ORANGE .. " [TSM skip " .. fromName .. "]" .. "|r"
                    end
                    row.rightText:SetText(priceStr .. sourceTag)

                    y = y + ITEM_H
                end
                y = y + 2 -- gap between groups
            end

            todoContent:SetHeight(math.max(1, y))

            -- Status bar
            local assignedCount = 0
            for _, g in ipairs(displayGroups) do
                if g.charKey then assignedCount = assignedCount + #g.items end
            end
            mainFrame.statusText:SetText(
                "Nothing to post on " .. charKey:match("^(.-)%-") ..
                "  |  " .. assignedCount .. " tasks across " .. #displayGroups .. " groups" ..
                (missingCount > 0 and ("  |  " .. missingCount .. " not in inventory") or ""))
        else
            -- No to-do list, but there are next steps or queue items
            self._postSummaryFrame:Show()
            local bannerHeight = 80
            self._postSummaryFrame:ClearAllPoints()
            self._postSummaryFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, contentOffset)
            self._postSummaryFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, contentOffset)
            self._postSummaryFrame:SetHeight(bannerHeight)
            self._postSummaryFrame.title:ClearAllPoints()
            self._postSummaryFrame.title:SetPoint("TOP", self._postSummaryFrame, "TOP", 0, -10)
            self._postSummaryFrame.title:SetText(ns.COLORS.GREEN .. "No to-do list generated yet|r")
            self._postSummaryFrame.sub:SetText(
                ns.COLORS.GRAY .. "Go to the To-Do Generator to build your task list.|r")
            self._postSummaryFrame.genBtn:Show()

            local belowBanner = contentOffset - bannerHeight
            if #nextData > 0 then
                if not self._nextStepsLabel then
                    self._nextStepsLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                end
                self._nextStepsLabel:ClearAllPoints()
                self._nextStepsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, belowBanner + 2)
                self._nextStepsLabel:SetTextColor(0.6, 0.8, 1.0)
                self._nextStepsLabel:SetText("Next Steps (" .. #nextData .. ")")
                self._nextStepsLabel:Show()

                self.nextStepsTable.headerFrame:ClearAllPoints()
                self.nextStepsTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, belowBanner - 10)
                self.nextStepsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, belowBanner - 10)
                self.nextStepsTable.scrollFrame:ClearAllPoints()
                self.nextStepsTable.scrollFrame:SetPoint("TOPLEFT", self.nextStepsTable.headerFrame, "BOTTOMLEFT", 0, 0)
                self.nextStepsTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)
                UI._ShowTable(self.nextStepsTable)
                self.nextStepsTable:SetData(nextData)
            end

            mainFrame.statusText:SetText("No to-do list  |  Use the Generator to create one")
        end
    else
        -- Has items to post
        self._postSummaryFrame:Hide()
        self._postSummaryFrame.genBtn:Hide()

        self.postNowTable.headerFrame:ClearAllPoints()
        self.postNowTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, contentOffset)
        self.postNowTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, contentOffset)

        UI._ShowTable(self.postNowTable)

        self.postNowTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" then
                if rowData._taskIndex and ns.TodoList then
                    if IsShiftKeyDown() then
                        ns.TodoList:SkipTask(rowData._taskIndex, "manual skip")
                        ns:Print(ns.COLORS.ORANGE .. "Skipped:|r " .. rowData.name)
                    else
                        ns.TodoList:MoveTaskToLog(rowData._taskIndex)
                        ns:Print("Posted: " .. rowData.name .. " -> moved to log")
                    end
                    self:Refresh()
                    if self.RefreshMini then self:RefreshMini() end
                end
            end
        end)
        self.postNowTable:SetData(data)

        if #nextData > 0 then
            local postNowHeight = math.max(60, (#data + 1) * 20 + 22) + charTaskHeight
            if postNowHeight > 250 + charTaskHeight then postNowHeight = 250 + charTaskHeight end

            if not self._nextStepsLabel then
                self._nextStepsLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            end
            self._nextStepsLabel:ClearAllPoints()
            self._nextStepsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, -postNowHeight + 2)
            self._nextStepsLabel:SetTextColor(0.6, 0.8, 1.0)
            self._nextStepsLabel:SetText("Next Steps (" .. #nextData .. ")")
            self._nextStepsLabel:Show()

            self.nextStepsTable.headerFrame:ClearAllPoints()
            self.nextStepsTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, -postNowHeight - 10)
            self.nextStepsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, -postNowHeight - 10)

            self.nextStepsTable.scrollFrame:ClearAllPoints()
            self.nextStepsTable.scrollFrame:SetPoint("TOPLEFT", self.nextStepsTable.headerFrame, "BOTTOMLEFT", 0, 0)
            self.nextStepsTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)

            UI._ShowTable(self.nextStepsTable)
            self.nextStepsTable:SetData(nextData)

            self.postNowTable.scrollFrame:ClearAllPoints()
            self.postNowTable.scrollFrame:SetPoint("TOPLEFT", self.postNowTable.headerFrame, "BOTTOMLEFT", 0, 0)
            self.postNowTable.scrollFrame:SetPoint("RIGHT", tableContainer, "RIGHT", -22, 0)
            self.postNowTable.scrollFrame:SetHeight(postNowHeight - charTaskHeight - 22)
        else
            if self._nextStepsLabel then self._nextStepsLabel:Hide() end
            self.postNowTable.scrollFrame:ClearAllPoints()
            self.postNowTable.scrollFrame:SetPoint("TOPLEFT", self.postNowTable.headerFrame, "BOTTOMLEFT", 0, 0)
            self.postNowTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)
        end

        mainFrame.statusText:SetText(postCount .. " items to post  |  " .. #nextData .. " next steps  |  Right-click: posted  |  Shift+Right: skip")
    end
end
