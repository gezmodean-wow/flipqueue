-- UI/CharactersPage.lua
-- Character list: gold, task counts, auction summary, ignore/show toggles
local addonName, ns = ...

local UI = ns.UI

local function BuildCharactersData()
    if not ns.db then return {}, {} end
    local CLASS_COLORS = UI._CLASS_COLORS
    local FormatGoldValue = UI._FormatGoldValue

    local charData = {}

    -- First pass: count characters per realm for duplicate detection
    local realmCharCount = {}
    local realmAllChars = {}
    for charKey, _ in pairs(ns.db.characters) do
        local realm = charKey:match("%-(.+)$") or ""
        if realm ~= "" then
            realmAllChars[realm] = realmAllChars[realm] or {}
            table.insert(realmAllChars[realm], charKey)
            realmCharCount[realm] = (realmCharCount[realm] or 0) + 1
        end
    end

    -- Identify duplicate realms (2+ characters on same realm)
    local duplicateRealms = {}
    for realm, count in pairs(realmCharCount) do
        if count > 1 then
            duplicateRealms[realm] = count
        end
    end

    -- Get auction summary grouped by character
    local auctionsByChar = ns.Tracker and ns.Tracker.GetAuctionSummaryByCharacter
        and ns.Tracker:GetAuctionSummaryByCharacter() or {}

    -- Build character list
    for charKey, inv in pairs(ns.db.characters) do
        local name = charKey:match("^(.-)%-") or charKey
        local realm = charKey:match("%-(.+)$") or ""
        local allTasks = ns.TodoList:GetCharacterTasks(charKey)
        local isHidden = inv.ignored

        -- Filter tasks by character's realm
        local tasks = {}
        for _, task in ipairs(allTasks) do
            if ns:RealmMatches(task.item.targetRealm, realm) then
                table.insert(tasks, task)
            end
        end

        local classColor = CLASS_COLORS[inv.class] or "888888"
        local coloredName = "|cff" .. classColor .. name .. "|r"
        if isHidden then
            coloredName = "|cff666666" .. name .. "|r"
        end

        local goldCopper = inv.gold or 0
        local goldStr = ns:FormatGold(goldCopper)
        local lastLoginTime = inv.lastLogin or 0
        local lastLoginStr = ns:FormatRelativeTime(lastLoginTime)

        -- Auction summary
        local auctionInfo = auctionsByChar[charKey]
        local auctionStr = ""
        if auctionInfo then
            local parts = {}
            if auctionInfo.active > 0 then
                if auctionInfo.soonest and auctionInfo.soonest < 7200 then
                    table.insert(parts, ns.COLORS.RED .. auctionInfo.active .. " live|r")
                else
                    table.insert(parts, ns.COLORS.ORANGE .. auctionInfo.active .. " live|r")
                end
            end
            if auctionInfo.done > 0 then
                table.insert(parts, ns.COLORS.GREEN .. auctionInfo.done .. " done|r")
            end
            auctionStr = table.concat(parts, " / ")
        end

        -- Build status string
        local statusParts = {}
        if isHidden then
            table.insert(statusParts, "|cff666666Hidden|r")
        elseif duplicateRealms[realm] then
            table.insert(statusParts, "|cffff8800Dupe|r")
        else
            table.insert(statusParts, "|cff00ff00Active|r")
        end
        local statusStr = table.concat(statusParts, " ")

        -- Row color
        local rowColor = nil
        if isHidden then
            rowColor = {0.3, 0.3, 0.3, 0.1}
        elseif auctionInfo and auctionInfo.done > 0 then
            rowColor = {0.3, 1.0, 0.3, 0.1}
        elseif auctionInfo and auctionInfo.soonest and auctionInfo.soonest < 7200 then
            rowColor = {1.0, 0.3, 0.3, 0.1}
        elseif duplicateRealms[realm] then
            rowColor = {0.8, 0.5, 0.1, 0.1}
        end

        -- Manual character order position
        local charOrder = ns.db.settings.characterOrder or {}
        local orderPos = 999
        for oi, oKey in ipairs(charOrder) do
            if oKey == charKey then orderPos = oi; break end
        end

        local toggleIcon = isHidden and "|cff666666X|r" or "|cff00ff00O|r"
        table.insert(charData, {
            toggle    = toggleIcon,
            name      = coloredName,
            realm     = realm,
            gold      = goldStr,
            tasks     = isHidden and "-" or tostring(#tasks),
            auctions  = auctionStr ~= "" and auctionStr or "",
            lastLogin = lastLoginStr,
            status    = statusStr,
            _sortName = name:lower(),
            _sortGold = goldCopper,
            _sortLastLogin = lastLoginTime,
            _sortAuctions = auctionInfo and (auctionInfo.done * 1000 + auctionInfo.active) or 0,
            _charKey = charKey,
            _isHidden = isHidden,
            _rowColor = rowColor,
            _orderPos = orderPos,
            _tooltipText = charKey,
            _tooltipExtra = string.format(
                "Gold: %s\n%d queue tasks%s\nLast login: %s\nStatus: %s%s\n\nClick to %s\nShift+Right-click: move up\nCtrl+Right-click: move down",
                goldStr, #tasks,
                auctionInfo and ("\n" .. auctionInfo.active .. " active, " .. auctionInfo.done .. " done auction(s)") or "",
                lastLoginStr,
                isHidden and "Hidden" or "Active",
                duplicateRealms[realm] and ("\nDuplicate realm: " .. duplicateRealms[realm] .. " chars on " .. realm) or "",
                isHidden and "re-enable" or "hide"),
        })
    end

    -- Build "realms needing characters" from to-do list unassigned groups
    local needData = {}
    local charTodoList = ns.TodoList and ns.TodoList:GetCurrentList()
    if charTodoList and charTodoList.tasks then
        local displayGroups = ns.TodoList:BuildDisplayGroups(charTodoList.tasks, "profit")
        for _, group in ipairs(displayGroups) do
            if not group.charKey then
                table.insert(needData, {
                    realm      = group.realm ~= "" and group.realm or "unknown",
                    itemCount  = #group.items,
                    totalValue = FormatGoldValue(group.totalGold),
                    note       = "Create character (flex slot)",
                })
            end
        end
    end

    return charData, needData
end

function UI:RefreshCharactersPage()
    local mainFrame = UI.mainFrame
    local tableContainer = UI.tableContainer
    mainFrame.pageTitle:SetText("Characters & Realms")
    UI._HideAllActionBtns()

    local charData, needData = BuildCharactersData()

    -- Show known characters table
    UI._ShowTable(self.charsTable)
    self.charsTable:SetRowClickHandler(function(rowData, button, rowIndex)
        if button == "LeftButton" and rowData._charKey then
            local charRecord = ns.db.characters[rowData._charKey]
            if charRecord and charRecord.ignored then
                charRecord.ignored = false
                ns:Print("Re-enabled character: " .. rowData._charKey)
            elseif charRecord then
                charRecord.ignored = true
                ns:Print("Hidden character: " .. rowData._charKey .. " (will be skipped for task routing)")
            end
            self:Refresh()
        elseif button == "RightButton" and rowData._charKey then
            if IsShiftKeyDown() then
                local order = ns.db.settings.characterOrder
                local seen = {}
                for _, k in ipairs(order) do seen[k] = true end
                for ck in pairs(ns.db.characters) do
                    if not seen[ck] then table.insert(order, ck) end
                end
                for idx, ck in ipairs(order) do
                    if ck == rowData._charKey and idx > 1 then
                        order[idx], order[idx - 1] = order[idx - 1], order[idx]
                        ns:Print("Moved up: " .. rowData._charKey)
                        break
                    end
                end
                self:Refresh()
            elseif IsControlKeyDown() then
                local order = ns.db.settings.characterOrder
                local seen = {}
                for _, k in ipairs(order) do seen[k] = true end
                for ck in pairs(ns.db.characters) do
                    if not seen[ck] then table.insert(order, ck) end
                end
                for idx, ck in ipairs(order) do
                    if ck == rowData._charKey and idx < #order then
                        order[idx], order[idx + 1] = order[idx + 1], order[idx]
                        ns:Print("Moved down: " .. rowData._charKey)
                        break
                    end
                end
                self:Refresh()
            else
                local charRecord2 = ns.db.characters[rowData._charKey]
                if charRecord2 and charRecord2.ignored then
                    charRecord2.ignored = false
                    ns:Print("Re-enabled character: " .. rowData._charKey)
                elseif charRecord2 then
                    charRecord2.ignored = true
                    ns:Print("Hidden character: " .. rowData._charKey .. " (will be skipped for task routing)")
                end
                self:Refresh()
            end
        end
    end)
    self.charsTable:SetData(charData)

    -- Show "need characters" table below if there are entries
    if #needData > 0 then
        local charsHeight = math.max(60, (#charData + 1) * 20 + 22)
        if charsHeight > 250 then charsHeight = 250 end

        self.needCharsTable.headerFrame:ClearAllPoints()
        self.needCharsTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, -charsHeight - 10)
        self.needCharsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, -charsHeight - 10)

        self.needCharsTable.scrollFrame:ClearAllPoints()
        self.needCharsTable.scrollFrame:SetPoint("TOPLEFT", self.needCharsTable.headerFrame, "BOTTOMLEFT", 0, 0)
        self.needCharsTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)

        if not self._needCharsLabel then
            self._needCharsLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        self._needCharsLabel:ClearAllPoints()
        self._needCharsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, -charsHeight - 2)
        self._needCharsLabel:SetTextColor(1, 0.4, 0.4)
        self._needCharsLabel:SetText("Realms Needing a Character (" .. #needData .. ")")
        self._needCharsLabel:Show()

        UI._ShowTable(self.needCharsTable)
        self.needCharsTable:SetData(needData)

        -- Resize chars scroll to fit above
        self.charsTable.scrollFrame:ClearAllPoints()
        self.charsTable.scrollFrame:SetPoint("TOPLEFT", self.charsTable.headerFrame, "BOTTOMLEFT", 0, 0)
        self.charsTable.scrollFrame:SetPoint("RIGHT", tableContainer, "RIGHT", -22, 0)
        self.charsTable.scrollFrame:SetHeight(charsHeight - 22)
    else
        if self._needCharsLabel then self._needCharsLabel:Hide() end
    end

    local charCount = 0
    local hiddenCount = 0
    local totalGold = 0
    for ck, ckData in pairs(ns.db.characters) do
        charCount = charCount + 1
        if ckData.ignored then hiddenCount = hiddenCount + 1 end
        if ckData.gold then totalGold = totalGold + ckData.gold end
    end
    local statusParts = {charCount .. " characters"}
    if totalGold > 0 then
        table.insert(statusParts, ns:FormatGold(totalGold) .. " total")
    end
    if hiddenCount > 0 then
        table.insert(statusParts, hiddenCount .. " hidden")
    end
    table.insert(statusParts, #needData .. " realms need chars")
    table.insert(statusParts, ns.COLORS.GRAY .. "Click to hide/show" .. "|r")
    mainFrame.statusText:SetText(table.concat(statusParts, "  |  "))
end
