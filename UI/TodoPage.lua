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
                _tooltipItemString = qi.itemKey and ns.ItemKeyToItemString
                    and ns:ItemKeyToItemString(qi.itemKey) or nil,
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
                local priceSource = ns.db.settings.tsmPriceSource or "70% DBRegionMarketAvg"
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
        local isBuyTask = item.action == "buy"

        -- Buy tasks match on buyRealm, sell tasks match on targetRealm
        local realmToMatch = isBuyTask and item.buyRealm or item.targetRealm
        if ns:RealmMatches(realmToMatch or "", myRealm) then
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
            if isBuyTask then
                -- Buy task: show step-based status. Mirrors the MiniView
                -- prefix mapping so the two surfaces agree on what action
                -- the player needs to take next:
                --   browse / buy → AH         "browse AH" / "buy item"
                --   collect      → mailbox    "check mail"
                --   deposit      → warbank    "deposit to wb"
                local stepType = ns.TodoList:GetCurrentStepType(item) or "browse"
                if stepType == "browse" then
                    sourceStr = ns.COLORS.CYAN .. "browse AH" .. "|r"
                elseif stepType == "buy" then
                    sourceStr = ns.COLORS.CYAN .. "buy item" .. "|r"
                elseif stepType == "collect" then
                    sourceStr = ns.COLORS.YELLOW .. "check mail" .. "|r"
                elseif stepType == "deposit" then
                    sourceStr = ns.COLORS.ORANGE .. "deposit to wb" .. "|r"
                end
            elseif sourceStr == "warbank" then
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

            -- Price display: buy tasks show buy price
            local priceDisplay = isBuyTask and item.buyPrice or item.expectedPrice or ""

            -- Tooltip
            local tooltipExtra
            if isBuyTask then
                tooltipExtra = "BUY on: " .. (item.buyRealm or "?") .. "  @  " .. (item.buyPrice or "?")
                    .. "\nSell on: " .. (item.targetRealm or "?") .. "  @  " .. (item.expectedPrice or "?")
                    .. (item.profitAmount and ("\nProfit: " .. item.profitAmount) or "")
                    .. (item.profitPct and (" (" .. item.profitPct .. "%)") or "")
            else
                tooltipExtra = (item.targetRealm and item.targetRealm ~= ""
                    and ("Sell on: " .. item.targetRealm .. "  @  " .. (item.expectedPrice or "?")) or nil)
            end

            -- Buy-task name prefix tracks the lifecycle step so the row
            -- tells the player what to do next (AH / mailbox / warbank).
            -- Mirrors UI/MiniView.lua's prefix mapping.
            local namePrefix = ""
            if isBuyTask then
                local s = ns.TodoList:GetCurrentStepType(item)
                if s == "collect" then
                    namePrefix = ns.COLORS.YELLOW .. "[CHECK MAIL] " .. "|r"
                elseif s == "deposit" then
                    namePrefix = ns.COLORS.ORANGE .. "[DEPOSIT] " .. "|r"
                else
                    namePrefix = ns.COLORS.CYAN .. "[BUY] " .. "|r"
                end
            end

            local row = {
                name     = namePrefix .. displayName,
                qty      = item.quantity or 1,
                price    = priceDisplay,
                realm    = isBuyTask and (item.buyRealm or "") or (item.targetRealm or ""),
                location = sourceStr,
                _icon    = item.icon or lookupIcon,
                _tooltipItemString = item.itemKey and ns.ItemKeyToItemString
                    and ns:ItemKeyToItemString(item.itemKey) or nil,
                _tooltipItemID = resolvedID or tonumber(item.itemID),
                _tooltipText   = item.name or "?",
                _tooltipExtra  = tooltipExtra,
                _taskIndex = task.taskIndex,
                _todoItem  = item,
            }

            if isBuyTask then
                row._rowColor = {0.1, 0.3, 0.5, 0.10}
            end

            -- TSM price data
            if ns.TSM:IsEnabled() and not isBuyTask then
                local priceSource = ns.db.settings.tsmPriceSource or "70% DBRegionMarketAvg"
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
    -- Show Auctionator buy list button if buy tasks exist and Auctionator is installed
    local hasBuyTasks = false
    if ns.TodoList and ns.TodoList.GetBuyTaskNames then
        hasBuyTasks = #ns.TodoList:GetBuyTaskNames() > 0
    end
    local hasAuctionator = type(Auctionator) == "table" and type(Auctionator.API) == "table"
        and type(Auctionator.API.v1) == "table"
    if hasBuyTasks and hasAuctionator then
        UI._LayoutActionBtns(mainFrame.actionBtns.clearAllTodoLists, mainFrame.actionBtns.clearTodoList,
            mainFrame.actionBtns.rescan, mainFrame.actionBtns.pullBank, mainFrame.actionBtns.auctBuyList)
    else
        UI._LayoutActionBtns(mainFrame.actionBtns.clearAllTodoLists, mainFrame.actionBtns.clearTodoList,
            mainFrame.actionBtns.rescan, mainFrame.actionBtns.pullBank)
    end

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

    -- ==========================================
    -- TO-DO LIST SELECTOR BAR
    -- ==========================================
    local listBarHeight = 0
    local queued = ns.TodoList and ns.TodoList:GetQueuedLists() or {}

    if currentTodoList or #queued > 0 then
        if not self._listSelectorBar then
            local bar = CreateFrame("Frame", nil, tableContainer, "BackdropTemplate")
            bar:SetHeight(24)
            bar:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 10,
                insets = {left = 2, right = 2, top = 2, bottom = 2},
            })
            bar:SetBackdropColor(0.08, 0.08, 0.12, 0.9)
            bar:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.7)

            bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            bar.label:SetPoint("LEFT", bar, "LEFT", 8, 0)
            bar.label:SetJustifyH("LEFT")

            -- Dropdown toggle button
            bar.dropBtn = CreateFrame("Button", nil, bar)
            bar.dropBtn:SetSize(16, 16)
            bar.dropBtn:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
            bar.dropBtn.tex = bar.dropBtn:CreateTexture(nil, "ARTWORK")
            bar.dropBtn.tex:SetAllPoints()
            bar.dropBtn.tex:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
            bar.dropBtn.highlight = bar.dropBtn:CreateTexture(nil, "HIGHLIGHT")
            bar.dropBtn.highlight:SetAllPoints()
            bar.dropBtn.highlight:SetColorTexture(1, 1, 1, 0.15)

            -- Dropdown frame
            bar.dropdown = CreateFrame("Frame", nil, bar, "BackdropTemplate")
            bar.dropdown:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 10,
                insets = {left = 2, right = 2, top = 2, bottom = 2},
            })
            bar.dropdown:SetBackdropColor(0.06, 0.06, 0.1, 0.95)
            bar.dropdown:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
            bar.dropdown:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
            bar.dropdown:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
            bar.dropdown:SetFrameStrata("DIALOG")
            bar.dropdown:Hide()
            bar.dropdown.rows = {}

            bar.dropBtn:SetScript("OnClick", function()
                if bar.dropdown:IsShown() then bar.dropdown:Hide() else bar.dropdown:Show() end
            end)

            -- Close dropdown when clicking outside
            bar.dropdown:SetScript("OnShow", function(self)
                self:SetPropagateKeyboardInput(true)
            end)
            bar:SetScript("OnHide", function() bar.dropdown:Hide() end)

            self._listSelectorBar = bar
        end

        local bar = self._listSelectorBar
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
        bar:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
        bar:Show()
        bar.dropdown:Hide()

        -- Label: active list name + task count
        local activeName = currentTodoList and (currentTodoList.name or "Unnamed") or "(no active list)"
        local pendingStr = totalTodoTasks > 0 and ("  " .. ns.COLORS.GREEN .. totalTodoTasks .. " tasks|r") or ""
        local queueStr = #queued > 0 and ("  " .. ns.COLORS.GRAY .. "+" .. #queued .. " queued|r") or ""
        bar.label:SetText(ns.COLORS.YELLOW .. activeName .. "|r" .. pendingStr .. queueStr)

        -- Populate dropdown rows
        for _, r in ipairs(bar.dropdown.rows) do r:Hide() end
        local ddY = -4
        local ddIdx = 0
        local DDR_H = 20

        local function GetDDRow()
            ddIdx = ddIdx + 1
            local row = bar.dropdown.rows[ddIdx]
            if not row then
                row = CreateFrame("Button", nil, bar.dropdown)
                row:SetHeight(DDR_H)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                row:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.15, 0.15, 0.25, 0.8) end)
                row:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0, 0, 0, 0) end)
                bar.dropdown.rows[ddIdx] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", bar.dropdown, "TOPLEFT", 2, ddY)
            row:SetPoint("RIGHT", bar.dropdown, "RIGHT", -2, 0)
            row.bg:SetColorTexture(0, 0, 0, 0)
            row:SetScript("OnClick", nil)
            row:Show()
            ddY = ddY - DDR_H
            return row
        end

        -- Active list entry
        if currentTodoList then
            local aRow = GetDDRow()
            local aCnt = 0
            for _, t in ipairs(currentTodoList.tasks or {}) do
                if t.status == "pending" then aCnt = aCnt + 1 end
            end
            aRow.text:SetText(ns.COLORS.GREEN .. "> " .. "|r" ..
                ns.COLORS.YELLOW .. (currentTodoList.name or "Unnamed") .. "|r" ..
                ns.COLORS.GRAY .. "  (" .. aCnt .. " tasks) [active]|r")
        end

        -- Queued lists
        for qi, qList in ipairs(queued) do
            local qRow = GetDDRow()
            local qCnt = 0
            for _, t in ipairs(qList.tasks or {}) do
                if t.status == "pending" then qCnt = qCnt + 1 end
            end
            qRow.text:SetText(ns.COLORS.GRAY .. "  " .. qi .. ". " .. "|r" ..
                (qList.name or "Unnamed") ..
                ns.COLORS.GRAY .. "  (" .. qCnt .. " tasks)|r")
            qRow:SetScript("OnClick", function()
                ns.TodoList:PromoteToActive(qi)
                bar.dropdown:Hide()
                self:Refresh()
                if self.RefreshMini then self:RefreshMini() end
            end)
        end

        bar.dropdown:SetHeight(math.abs(ddY) + 4)
        listBarHeight = 28 -- bar height + gap
    else
        if self._listSelectorBar then self._listSelectorBar:Hide() end
    end

    -- Current character tasks frame (Check Mail, Expiring)
    if not self._charTasksFrame then
        local ctf = CreateFrame("Frame", nil, tableContainer)
        ctf:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
        ctf:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
        ctf:SetHeight(1)
        ctf.rows = {}
        self._charTasksFrame = ctf
    end
    self._charTasksFrame:ClearAllPoints()
    self._charTasksFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, -listBarHeight)
    self._charTasksFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, -listBarHeight)

    -- Hide old task rows
    for _, row in ipairs(self._charTasksFrame.rows) do
        row:Hide()
    end

    local MAX_CHAR_TASKS_HEIGHT = 200 -- ~9 rows before scrolling
    local charTaskHeight = 0
    if #myTasks > 0 then
        self._charTasksFrame:Show()

        -- Create scroll frame for tasks if not already present
        if not self._charTasksScroll then
            local scroll = CreateFrame("ScrollFrame", nil, self._charTasksFrame, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", self._charTasksFrame, "TOPLEFT", 0, 0)
            scroll:SetPoint("BOTTOMRIGHT", self._charTasksFrame, "BOTTOMRIGHT", -16, 0)
            local scrollChild = CreateFrame("Frame", nil, scroll)
            scrollChild:SetWidth(scroll:GetWidth())
            scroll:SetScrollChild(scrollChild)
            scroll:SetScript("OnSizeChanged", function(sf, w)
                scrollChild:SetWidth(w)
            end)
            self._charTasksScroll = scroll
            self._charTasksScrollChild = scrollChild
            -- Style the scrollbar to be subtle
            if scroll.ScrollBar then
                scroll.ScrollBar:SetAlpha(0.6)
            end
        end

        local scrollChild = self._charTasksScrollChild
        -- Move rows to scroll child parent
        for _, row in ipairs(self._charTasksFrame.rows) do
            row:Hide()
        end

        for i, task in ipairs(myTasks) do
            local row = self._charTasksFrame.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, scrollChild)
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
            -- Re-parent to scroll child if needed
            if row:GetParent() ~= scrollChild then
                row:SetParent(scrollChild)
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * 22)
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            row.bg:SetColorTexture(0.12, 0.15, 0.12, 0.6)
            row.icon:SetTexture(task.icon)
            row.text:SetText(task.text)
            row:EnableMouse(true)
            if task._dismissible and task._onDismiss then
                row:SetScript("OnMouseDown", function(_, button)
                    if button == "RightButton" then
                        task._onDismiss()
                        self:Refresh()
                        if self.RefreshMini then self:RefreshMini() end
                    end
                end)
                row:SetScript("OnEnter", function(self)
                    self.bg:SetColorTexture(0.18, 0.2, 0.18, 0.8)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Right-click to dismiss", 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    self.bg:SetColorTexture(0.12, 0.15, 0.12, 0.6)
                    GameTooltip:Hide()
                end)
            else
                row:SetScript("OnMouseDown", nil)
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)
            end
            row:Show()
        end

        local fullContentHeight = #myTasks * 22 + 4
        scrollChild:SetHeight(fullContentHeight)
        scrollChild:SetWidth(self._charTasksScroll:GetWidth())

        charTaskHeight = math.min(fullContentHeight, MAX_CHAR_TASKS_HEIGHT)
        self._charTasksFrame:SetHeight(charTaskHeight)

        -- Show/hide scrollbar based on need
        local needsScroll = fullContentHeight > MAX_CHAR_TASKS_HEIGHT
        if self._charTasksScroll.ScrollBar then
            self._charTasksScroll.ScrollBar:SetShown(needsScroll)
        end
        self._charTasksScroll:Show()
    else
        self._charTasksFrame:Hide()
        if self._charTasksScroll then self._charTasksScroll:Hide() end
        charTaskHeight = 0
    end

    local contentOffset = -charTaskHeight - listBarHeight

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

            for _, row in ipairs(todoRows) do
                row:Hide()
                UI.HideTaskActionBtns(row)
            end

            -- Annotate tasks with their array index so action buttons can target them
            for i, task in ipairs(currentTodoList.tasks) do
                task._taskIndex = i
            end

            local displayGroups, missingCount = ns.TodoList:BuildDisplayGroups(
                currentTodoList.tasks, UI:GetGenSortMode())

            -- Running warbank balance simulation. Walk all groups in display
            -- order and tag any task whose deposit step would push the
            -- cumulative usage past the known capacity as _warbankAtRisk.
            -- This is a soft warning — the UI renders a red icon but the
            -- user can still click through, matching the soft ordering
            -- the scheduling model uses elsewhere.
            if ns.db.warbank and type(ns.db.warbank.freeSlots) == "number" then
                local balance = ns.db.warbank.freeSlots
                for _, group in ipairs(displayGroups) do
                    for _, item in ipairs(group.items) do
                        item._warbankAtRisk = nil
                        if item.steps then
                            local consumes, frees = 0, 0
                            for _, step in ipairs(item.steps) do
                                if step.status ~= "done" and step.status ~= "completed" then
                                    if step.type == "deposit" and step.to == "warbank" then
                                        consumes = consumes + 1
                                    elseif step.type == "retrieve" and step.from == "warbank" then
                                        frees = frees + 1
                                    end
                                end
                            end
                            -- Apply retrieves first (they run earlier in the
                            -- sort order), then deposits. A task is at risk
                            -- when the deposit would drop balance below zero.
                            balance = balance + frees
                            if consumes > 0 and balance - consumes < 0 then
                                item._warbankAtRisk = true
                            end
                            balance = balance - consumes
                        end
                    end
                end
            end

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
                    row.rightText:SetPoint("RIGHT", row, "RIGHT", -52, 0)
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
                -- Clear mouseover state (action buttons set per item, not headers)
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)
                UI.HideTaskActionBtns(row)
                row:Show()
                return row
            end

            for gi, group in ipairs(displayGroups) do
                local isUnassigned = not group.charKey
                local isCurrentChar = group.charKey == charKey
                local hasBuys = group.hasBuyTasks

                -- Build "X to post, Y to buy" count string for header
                local grpBuys, grpPosts = 0, 0
                for _, gi2 in ipairs(group.items) do
                    if gi2.action == "buy" then grpBuys = grpBuys + 1 else grpPosts = grpPosts + 1 end
                end
                local cntParts = {}
                if grpPosts > 0 then table.insert(cntParts, grpPosts .. " to post") end
                if grpBuys > 0 then table.insert(cntParts, grpBuys .. " to buy") end
                local countStr = #cntParts > 0 and table.concat(cntParts, ", ") or (#group.items .. " items")

                -- Group header
                local hdr = GetRow(HDR_H)
                if isUnassigned then
                    hdr.bg:SetColorTexture(0.15, 0.08, 0.08, 0.7)
                    local realmName = group.realm ~= "" and group.realm or "unknown realm"
                    hdr.text:SetText(ns.COLORS.RED .. "Create character on " .. realmName .. "|r" ..
                        ns.COLORS.GRAY .. "  (" .. #group.items .. " items)|r")
                elseif isCurrentChar then
                    local buyTag = hasBuys and (ns.COLORS.CYAN .. " [BUY]" .. "|r") or ""
                    hdr.bg:SetColorTexture(hasBuys and 0.08 or 0.1, hasBuys and 0.15 or 0.2, hasBuys and 0.2 or 0.1, 0.8)
                    local cc = CLASS_COLORS[ns.db.characters[group.charKey] and ns.db.characters[group.charKey].class] or "888888"
                    hdr.text:SetText("|cff" .. cc .. group.charName .. "|r" ..
                        ns.COLORS.GRAY .. " - " .. group.realm .. "|r" ..
                        ns.COLORS.GREEN .. "  (YOU — " .. countStr .. ")|r" .. buyTag)
                else
                    local charInv = ns.db.characters and ns.db.characters[group.charKey]
                    local cc = charInv and CLASS_COLORS[charInv.class] or "888888"
                    local buyTag = hasBuys and (ns.COLORS.CYAN .. " [BUY]" .. "|r") or ""
                    local rp = ns.IsRemoteChar and ns:IsRemoteChar(group.charKey) and "|cff8866cc*|r " or ""
                    if group._allDeferred then
                        hdr.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
                        hdr.text:SetText(rp .. "|cff" .. cc .. group.charName .. "|r" ..
                            ns.COLORS.GRAY .. " - " .. group.realm .. "  (" .. countStr .. ")" ..
                            ns.COLORS.RED .. " [no inventory]" .. "|r" .. buyTag)
                    else
                        hdr.bg:SetColorTexture(hasBuys and 0.08 or 0.12, hasBuys and 0.12 or 0.15, hasBuys and 0.18 or 0.2, 0.8)
                        hdr.text:SetText(rp .. "|cff" .. cc .. group.charName .. "|r" ..
                            ns.COLORS.GRAY .. " - " .. group.realm .. "  (" .. countStr .. ")|r" .. buyTag)
                    end
                end

                local goldStr = FormatGoldValue(group.totalGold)
                local goldColor = isUnassigned and ns.COLORS.GRAY or ns.COLORS.YELLOW
                hdr.rightText:SetText(goldColor .. "~" .. goldStr .. "|r")

                -- Group-level action buttons (complete/skip/delete all items in group)
                local groupIndices = {}
                for _, item in ipairs(group.items) do
                    if item._taskIndex then table.insert(groupIndices, item._taskIndex) end
                end
                if #groupIndices > 0 then
                    UI.SetupTaskActionBtns(hdr)
                    local groupRefresh = function()
                        self:Refresh()
                        if self.RefreshMini then self:RefreshMini() end
                    end
                    local btns = hdr._taskActionBtns
                    btns.complete:SetScript("OnClick", function()
                        ns.TodoList:BulkComplete(groupIndices)
                        groupRefresh()
                    end)
                    btns.skip:SetScript("OnClick", function()
                        ns.TodoList:BulkSkip(groupIndices, "bulk skip")
                        groupRefresh()
                    end)
                    btns.delete:SetScript("OnClick", function()
                        ns.TodoList:BulkDelete(groupIndices)
                        groupRefresh()
                    end)
                    UI.HideTaskActionBtns(hdr)

                    local hdrBgR, hdrBgG, hdrBgB, hdrBgA
                    if isUnassigned then
                        hdrBgR, hdrBgG, hdrBgB, hdrBgA = 0.15, 0.08, 0.08, 0.7
                    elseif isCurrentChar then
                        hdrBgR = hasBuys and 0.08 or 0.1
                        hdrBgG = hasBuys and 0.15 or 0.2
                        hdrBgB = hasBuys and 0.2 or 0.1
                        hdrBgA = 0.8
                    elseif group._allDeferred then
                        hdrBgR, hdrBgG, hdrBgB, hdrBgA = 0.1, 0.1, 0.1, 0.5
                    else
                        hdrBgR = hasBuys and 0.08 or 0.12
                        hdrBgG = hasBuys and 0.12 or 0.15
                        hdrBgB = hasBuys and 0.18 or 0.2
                        hdrBgA = 0.8
                    end
                    hdr:EnableMouse(true)
                    hdr:SetScript("OnEnter", function(self)
                        self.bg:SetColorTexture(hdrBgR + 0.06, hdrBgG + 0.06, hdrBgB + 0.06, hdrBgA + 0.1)
                        UI.ShowTaskActionBtns(self)
                    end)
                    hdr:SetScript("OnLeave", function(self)
                        self._actionBtnHovered = false
                        C_Timer.After(0.1, function()
                            if not self._actionBtnHovered and not self:IsMouseOver() then
                                self.bg:SetColorTexture(hdrBgR, hdrBgG, hdrBgB, hdrBgA)
                                UI.HideTaskActionBtns(self)
                            end
                        end)
                    end)
                end

                y = y + HDR_H

                -- Item rows
                for ii, item in ipairs(group.items) do
                    local isBuyItem = item.action == "buy"
                    local row = GetRow(ITEM_H)
                    if isUnassigned then
                        row.bg:SetColorTexture(0.1, 0.06, 0.06, 0.4)
                    elseif isBuyItem then
                        row.bg:SetColorTexture(0.06, 0.1, 0.15, 0.5)
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
                    -- Prefix buy tasks with the lifecycle-aware tag — [BUY]
                    -- before purchase, [CHECK MAIL] after AH confirmation,
                    -- [DEPOSIT] once the item is in bags awaiting warbank.
                    if isBuyItem then
                        local s = ns.TodoList:GetCurrentStepType(item)
                        if s == "collect" then
                            displayName = ns.COLORS.YELLOW .. "[CHECK MAIL] " .. "|r" .. displayName
                        elseif s == "deposit" then
                            displayName = ns.COLORS.ORANGE .. "[DEPOSIT] " .. "|r" .. displayName
                        else
                            displayName = ns.COLORS.CYAN .. "[BUY] " .. "|r" .. displayName
                        end
                    end
                    -- Warbank overfill warning: soft indicator only. Running
                    -- balance simulation flags this task because its deposit
                    -- step would push cumulative usage past capacity.
                    if item._warbankAtRisk then
                        displayName = ns.COLORS.RED .. "[!] |r" .. displayName
                    end
                    local qtyStr = (item.quantity or 1) > 1 and (" x" .. (item.quantity or 1)) or ""
                    row.text:SetText(displayName .. qtyStr)

                    -- Right side: price + source status
                    local priceStr
                    local sourceTag = ""
                    if isBuyItem then
                        -- Buy tasks show buy price and step-based status
                        priceStr = item.buyPrice or ""
                        local stepType = ns.TodoList:GetCurrentStepType(item) or "browse"
                        if stepType == "browse" then
                            sourceTag = ns.COLORS.CYAN .. " [browse]" .. "|r"
                        elseif stepType == "buy" then
                            sourceTag = ns.COLORS.CYAN .. " [buy]" .. "|r"
                        elseif stepType == "deposit" then
                            sourceTag = ns.COLORS.YELLOW .. " [deposit]" .. "|r"
                        end
                        -- Show profit if available
                        if item.profitAmount then
                            sourceTag = sourceTag .. ns.COLORS.GREEN .. " +" .. item.profitAmount .. "|r"
                        end
                    else
                        priceStr = item.expectedPrice or ""
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
                    end
                    row.rightText:SetText(priceStr .. sourceTag)

                    -- Mouseover: highlight + action buttons (complete/skip/delete)
                    row:EnableMouse(true)
                    local taskIdx = item._taskIndex
                    if taskIdx then
                        UI.SetupTaskActionBtns(row)
                        UI.WireTaskActionBtns(row, taskIdx, function()
                            self:Refresh()
                            if self.RefreshMini then self:RefreshMini() end
                        end)
                        UI.HideTaskActionBtns(row)

                        local bgR, bgG, bgB, bgA
                        if isUnassigned then
                            bgR, bgG, bgB, bgA = 0.1, 0.06, 0.06, 0.4
                        elseif isBuyItem then
                            bgR, bgG, bgB, bgA = 0.06, 0.1, 0.15, 0.5
                        else
                            bgR = ii % 2 == 0 and 0.08 or 0.06
                            bgG = bgR
                            bgB = ii % 2 == 0 and 0.12 or 0.1
                            bgA = 0.5
                        end
                        row:SetScript("OnEnter", function(self)
                            self.bg:SetColorTexture(bgR + 0.06, bgG + 0.06, bgB + 0.06, bgA + 0.15)
                            UI.ShowTaskActionBtns(self)
                        end)
                        row:SetScript("OnLeave", function(self)
                            self._actionBtnHovered = false
                            C_Timer.After(0.1, function()
                                if not self._actionBtnHovered and not self:IsMouseOver() then
                                    self.bg:SetColorTexture(bgR, bgG, bgB, bgA)
                                    UI.HideTaskActionBtns(self)
                                end
                            end)
                        end)
                    else
                        row:SetScript("OnEnter", nil)
                        row:SetScript("OnLeave", nil)
                        UI.HideTaskActionBtns(row)
                    end

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

            -- Warbank balance readout. Shows used/total free slots and the
            -- count of pending deposit-to-warbank steps across all tasks so
            -- users can see capacity pressure without opening the bank. The
            -- at-risk indicator matches the per-task [!] badge: orange when
            -- pending deposits exceed free slots, yellow when tight.
            local warbankReadout = ""
            if ns.db.warbank and type(ns.db.warbank.freeSlots) == "number" then
                local freeSlots = ns.db.warbank.freeSlots
                local totalSlots = ns.db.warbank.totalSlots or 0
                local pendingDeposits = 0
                local pendingRetrieves = 0
                for _, g in ipairs(displayGroups) do
                    for _, item in ipairs(g.items) do
                        if item.steps then
                            for _, step in ipairs(item.steps) do
                                if step.status ~= "done" and step.status ~= "completed" then
                                    if step.type == "deposit" and step.to == "warbank" then
                                        pendingDeposits = pendingDeposits + 1
                                    elseif step.type == "retrieve" and step.from == "warbank" then
                                        pendingRetrieves = pendingRetrieves + 1
                                    end
                                end
                            end
                        end
                    end
                end
                local netDemand = pendingDeposits - pendingRetrieves
                local color
                if netDemand > freeSlots then
                    color = ns.COLORS.ORANGE
                elseif netDemand > 0 and netDemand >= freeSlots * 0.8 then
                    color = ns.COLORS.YELLOW
                else
                    color = ns.COLORS.GRAY
                end
                warbankReadout = "  |  " .. color .. "Warbank " .. freeSlots ..
                    "/" .. totalSlots .. " free"
                if pendingDeposits > 0 or pendingRetrieves > 0 then
                    warbankReadout = warbankReadout ..
                        ", " .. pendingDeposits .. "↓"
                    if pendingRetrieves > 0 then
                        warbankReadout = warbankReadout .. " " .. pendingRetrieves .. "↑"
                    end
                end
                warbankReadout = warbankReadout .. "|r"
            end

            mainFrame.statusText:SetText(
                "No tasks on " .. charKey:match("^(.-)%-") ..
                "  |  " .. assignedCount .. " tasks across " .. #displayGroups .. " groups" ..
                (missingCount > 0 and ("  |  " .. missingCount .. " not in inventory") or "") ..
                warbankReadout)
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

                -- Anchor header below label, scroll frame below header
                self.nextStepsTable.headerFrame:ClearAllPoints()
                self.nextStepsTable.headerFrame:SetPoint("TOPLEFT", self._nextStepsLabel, "BOTTOMLEFT", -4, -2)
                self.nextStepsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
                self.nextStepsTable.headerFrame:SetFrameLevel(tableContainer:GetFrameLevel() + 10)
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

        local actionRefresh = function()
            self:Refresh()
            if self.RefreshMini then self:RefreshMini() end
        end
        self.postNowTable:SetRowClickHandler(function(rowData, button)
            if button == "RightButton" then
                if rowData._taskIndex and ns.TodoList then
                    if IsShiftKeyDown() then
                        ns.TodoList:SkipTask(rowData._taskIndex, "manual skip")
                        ns:Print(ns.COLORS.ORANGE .. "Skipped:|r " .. rowData.name)
                    else
                        ns.TodoList:MoveTaskToLog(rowData._taskIndex)
                        ns.cw:Toast({ severity = "success", text = "Posted: " .. rowData.name .. " — moved to log" })
                    end
                    actionRefresh()
                end
            end
        end)
        self.postNowTable:EnableRowActions(actionRefresh)
        self.postNowTable:SetData(data)

        if #nextData > 0 then
            local postNowHeight = math.max(60, (#data + 1) * 20 + 22) + charTaskHeight + listBarHeight
            if postNowHeight > 250 + charTaskHeight + listBarHeight then postNowHeight = 250 + charTaskHeight + listBarHeight end

            if not self._nextStepsLabel then
                self._nextStepsLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            end
            self._nextStepsLabel:ClearAllPoints()
            self._nextStepsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, -postNowHeight + 2)
            self._nextStepsLabel:SetTextColor(0.6, 0.8, 1.0)
            self._nextStepsLabel:SetText("Next Steps (" .. #nextData .. ")")
            self._nextStepsLabel:Show()

            -- Anchor header below label
            self.nextStepsTable.headerFrame:ClearAllPoints()
            self.nextStepsTable.headerFrame:SetPoint("TOPLEFT", self._nextStepsLabel, "BOTTOMLEFT", -4, -2)
            self.nextStepsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)

            self.nextStepsTable.scrollFrame:ClearAllPoints()
            self.nextStepsTable.scrollFrame:SetPoint("TOPLEFT", self.nextStepsTable.headerFrame, "BOTTOMLEFT", 0, 0)
            self.nextStepsTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)

            -- Raise next steps header above postNow scroll content so it doesn't get overlapped
            self.nextStepsTable.headerFrame:SetFrameLevel(tableContainer:GetFrameLevel() + 10)

            UI._ShowTable(self.nextStepsTable)
            self.nextStepsTable:SetData(nextData)

            -- Constrain postNow scroll to end at the next steps label
            self.postNowTable.scrollFrame:ClearAllPoints()
            self.postNowTable.scrollFrame:SetPoint("TOPLEFT", self.postNowTable.headerFrame, "BOTTOMLEFT", 0, 0)
            self.postNowTable.scrollFrame:SetPoint("RIGHT", tableContainer, "RIGHT", -22, 0)
            self.postNowTable.scrollFrame:SetPoint("BOTTOM", self._nextStepsLabel, "TOP", 0, 2)
        else
            if self._nextStepsLabel then self._nextStepsLabel:Hide() end
            self.postNowTable.scrollFrame:ClearAllPoints()
            self.postNowTable.scrollFrame:SetPoint("TOPLEFT", self.postNowTable.headerFrame, "BOTTOMLEFT", 0, 0)
            self.postNowTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)
        end

        -- Count buy vs sell items for accurate status text
        local statusBuys, statusPosts = 0, 0
        for _, row in ipairs(data) do
            if row._todoItem and row._todoItem.action == "buy" then
                statusBuys = statusBuys + 1
            else
                statusPosts = statusPosts + 1
            end
        end
        local statusParts = {}
        if statusPosts > 0 then table.insert(statusParts, statusPosts .. " to post") end
        if statusBuys > 0 then table.insert(statusParts, statusBuys .. " to buy") end
        local statusStr = #statusParts > 0 and table.concat(statusParts, ", ") or (postCount .. " items")
        mainFrame.statusText:SetText(statusStr .. "  |  " .. #nextData .. " next steps  |  Hover for actions")
    end
end

-- Register layout callback for container resize
UI:RegisterPageLayout("todo", function()
    -- The todoOverviewScroll and postSummaryFrame have their own OnSizeChanged handlers.
    -- Just sync the charTasksScrollChild width if it exists.
    if UI._charTasksScrollChild and UI._charTasksScroll then
        UI._charTasksScrollChild:SetWidth(UI._charTasksScroll:GetWidth())
    end
end)
