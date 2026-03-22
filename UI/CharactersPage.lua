-- UI/CharactersPage.lua
-- Character list: gold, task counts, auction summary, ignore/show toggles
local addonName, ns = ...

local UI = ns.UI

local function BuildCharactersData()
    if not ns.db then return {}, {} end
    local CLASS_COLORS = UI._CLASS_COLORS
    local FormatGoldValue = UI._FormatGoldValue

    local charData = {}

    -- Build AH cluster groups: characters whose realms overlap share an AH
    local clusters = {}  -- array of {realms={}, chars={charKey, ...}}
    for charKey in pairs(ns.db.characters) do
        local realm = charKey:match("%-(.+)$") or ""
        if realm ~= "" then
            local found = nil
            for _, c in ipairs(clusters) do
                for _, cr in ipairs(c.realms) do
                    if ns:RealmsOverlap(realm, cr) then found = c; break end
                end
                if found then break end
            end
            if found then
                table.insert(found.chars, charKey)
                -- Add realm if not already present
                local realmSeen = false
                for _, cr in ipairs(found.realms) do
                    if cr == realm then realmSeen = true; break end
                end
                if not realmSeen then table.insert(found.realms, realm) end
            else
                table.insert(clusters, {realms = {realm}, chars = {charKey}})
            end
        end
    end

    -- Build lookup: charKey -> cluster info (for shared AH detection)
    local charCluster = {}  -- charKey -> {clusterIdx, otherChars}
    for ci, c in ipairs(clusters) do
        if #c.chars > 1 then
            for _, ck in ipairs(c.chars) do
                local others = {}
                for _, ock in ipairs(c.chars) do
                    if ock ~= ck then table.insert(others, ock) end
                end
                charCluster[ck] = {
                    idx = ci,
                    realms = c.realms,
                    others = others,
                }
            end
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
        elseif charCluster[charKey] then
            table.insert(statusParts, "|cffff8800Shared AH|r")
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
        elseif charCluster[charKey] then
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
                isHidden and "Hidden" or (charCluster[charKey] and "Shared AH" or "Active"),
                charCluster[charKey] and ("\nAH Cluster: " .. table.concat(charCluster[charKey].realms, ", ") ..
                    "\nShared with: " .. table.concat(
                        (function()
                            local names = {}
                            for _, ock in ipairs(charCluster[charKey].others) do
                                table.insert(names, ock:match("^(.-)%-") or ock)
                            end
                            return names
                        end)(), ", ")) or "",
                isHidden and "re-enable" or "hide"),
        })
    end

    -- Build "realms needing characters" from to-do list unassigned groups
    -- Merge groups for overlapping connected realm clusters
    local needData = {}
    local charTodoList = ns.TodoList and ns.TodoList:GetCurrentList()
    if charTodoList and charTodoList.tasks then
        local displayGroups = ns.TodoList:BuildDisplayGroups(charTodoList.tasks, "profit")
        local rawNeed = {}
        for _, group in ipairs(displayGroups) do
            if not group.charKey then
                table.insert(rawNeed, {
                    realm     = group.realm ~= "" and group.realm or "unknown",
                    items     = #group.items,
                    gold      = group.totalGold,
                })
            end
        end

        -- Merge overlapping realm clusters (multi-pass for transitive overlaps)
        -- e.g., "Kirin Tor" + "Sentinels" + "Kirin Tor, Steamwheedle Cartel, Sentinels"
        -- all collapse into one entry regardless of processing order
        local merged = {}
        for _, entry in ipairs(rawNeed) do
            table.insert(merged, { realm = entry.realm, items = entry.items, gold = entry.gold })
        end

        local didMerge = true
        while didMerge do
            didMerge = false
            for i = #merged, 2, -1 do
                for j = 1, i - 1 do
                    if ns:RealmsOverlap(merged[j].realm, merged[i].realm) then
                        if #merged[i].realm > #merged[j].realm then
                            merged[j].realm = merged[i].realm
                        end
                        merged[j].items = merged[j].items + merged[i].items
                        merged[j].gold = merged[j].gold + merged[i].gold
                        table.remove(merged, i)
                        didMerge = true
                        break
                    end
                end
            end
        end

        for _, entry in ipairs(merged) do
            table.insert(needData, {
                realm      = entry.realm,
                itemCount  = entry.items,
                totalValue = FormatGoldValue(entry.gold),
                note       = "Create character (flex slot)",
                _sortItems = entry.items,
                _sortValue = entry.gold,
            })
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

        -- Section heading: same style as "Next Steps" on To-Do page
        if not self._needCharsLabel then
            self._needCharsLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        self._needCharsLabel:ClearAllPoints()
        self._needCharsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, -charsHeight - 6)
        self._needCharsLabel:SetPoint("RIGHT", tableContainer, "RIGHT", -4, 0)
        self._needCharsLabel:SetJustifyH("LEFT")
        self._needCharsLabel:SetTextColor(1, 0.4, 0.4)
        self._needCharsLabel:SetText("Realms Needing a Character (" .. #needData .. ")")
        self._needCharsLabel:Show()

        self.needCharsTable.headerFrame:ClearAllPoints()
        self.needCharsTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, -charsHeight - 18)
        self.needCharsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, -charsHeight - 18)

        self.needCharsTable.scrollFrame:ClearAllPoints()
        self.needCharsTable.scrollFrame:SetPoint("TOPLEFT", self.needCharsTable.headerFrame, "BOTTOMLEFT", 0, 0)
        self.needCharsTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)

        UI._ShowTable(self.needCharsTable)
        self.needCharsTable:SetData(needData)

        -- Resize chars scroll to fit above
        self.charsTable.scrollFrame:ClearAllPoints()
        self.charsTable.scrollFrame:SetPoint("TOPLEFT", self.charsTable.headerFrame, "BOTTOMLEFT", 0, 0)
        self.charsTable.scrollFrame:SetPoint("RIGHT", tableContainer, "RIGHT", -22, 0)
        self.charsTable.scrollFrame:SetHeight(charsHeight - 22)
    else
        if self._needCharsLabel then self._needCharsLabel:Hide() end
        -- No "need characters" section: expand chars table to fill available space
        self.charsTable.scrollFrame:ClearAllPoints()
        self.charsTable.scrollFrame:SetPoint("TOPLEFT", self.charsTable.headerFrame, "BOTTOMLEFT", 0, 0)
        self.charsTable.scrollFrame:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)
    end

    -- TSM Detected Characters section (scrollable)
    if not self._tsmDetectedFrame then
        local df = CreateFrame("Frame", nil, tableContainer)
        df.rows = {}
        self._tsmDetectedFrame = df
    end
    if not self._tsmDetectedLabel then
        self._tsmDetectedLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        self._tsmDetectedLabel:SetJustifyH("LEFT")
        self._tsmDetectedLabel:SetTextColor(0.9, 0.8, 0.3)
        UI._tsmDetectedLabel = self._tsmDetectedLabel
    end
    if not self._tsmDetectedScroll then
        local sf = CreateFrame("ScrollFrame", nil, tableContainer, "UIPanelScrollFrameTemplate")
        local sc = CreateFrame("Frame", nil, sf)
        sc:SetWidth(1)
        sc:SetHeight(1)
        sf:SetScrollChild(sc)
        sf:SetScript("OnSizeChanged", function(self, w) sc:SetWidth(w) end)
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local step = 40
            local newScroll = math.max(0, math.min(current - (delta * step), maxScroll))
            self:SetVerticalScroll(newScroll)
        end)
        self._tsmDetectedScroll = sf
        self._tsmDetectedContent = sc
        UI._tsmDetectedScroll = sf
    end
    local tdf = self._tsmDetectedFrame
    local tdfLabel = self._tsmDetectedLabel
    local tdfScroll = self._tsmDetectedScroll
    local tdfContent = self._tsmDetectedContent
    for _, r in ipairs(tdf.rows) do r:Hide() end
    tdfLabel:Hide()
    tdfScroll:Hide()
    tdf:Hide()

    local detectedChars = ns._detectedTSMChars or {}
    if #detectedChars > 0 then
        local CLASS_COLORS = UI._CLASS_COLORS
        local FormatGoldValue = UI._FormatGoldValue
        local ROW_H = 22
        local MAX_VISIBLE_ROWS = 8
        local yOff = 0

        -- Helper: propagate mouse wheel from child frames to scroll parent
        local function PropagateScroll(frame)
            frame:EnableMouseWheel(true)
            frame:SetScript("OnMouseWheel", function(_, delta)
                local current = tdfScroll:GetVerticalScroll()
                local maxScroll = tdfScroll:GetVerticalScrollRange()
                local step = 40
                local newScroll = math.max(0, math.min(current - (delta * step), maxScroll))
                tdfScroll:SetVerticalScroll(newScroll)
            end)
        end

        -- Calculate vertical position (below other tables)
        local tsmSectionTop
        if #needData > 0 then
            local charsHeight = math.max(60, (#charData + 1) * 20 + 22)
            if charsHeight > 250 then charsHeight = 250 end
            local needHeight = math.max(40, (#needData + 1) * 20 + 22)
            tsmSectionTop = -charsHeight - 10 - needHeight - 10
        else
            local charsHeight = math.max(60, (#charData + 1) * 20 + 22)
            if charsHeight > 250 then charsHeight = 250 end
            tsmSectionTop = -charsHeight - 10
        end

        tdfLabel:ClearAllPoints()
        tdfLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, tsmSectionTop)
        tdfLabel:SetText("Detected from TSM (" .. #detectedChars .. ")")
        tdfLabel:Show()

        -- Scroll frame fills remaining space, capped to MAX_VISIBLE_ROWS
        local totalContentH = (#detectedChars + 1) * ROW_H + 10
        tdfScroll:ClearAllPoints()
        tdfScroll:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, tsmSectionTop - 16)
        tdfScroll:SetPoint("BOTTOMRIGHT", tableContainer, "BOTTOMRIGHT", -22, 0)
        tdfScroll:Show()
        tdfContent:SetWidth(tdfScroll:GetWidth() or 500)

        -- "Add All" row
        local addAllRow = tdf.rows[1]
        if not addAllRow then
            addAllRow = CreateFrame("Button", nil, tdfContent)
            addAllRow.bg = addAllRow:CreateTexture(nil, "BACKGROUND")
            addAllRow.bg:SetAllPoints()
            addAllRow.text = addAllRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            addAllRow.text:SetPoint("LEFT", addAllRow, "LEFT", 6, 0)
            tdf.rows[1] = addAllRow
        end
        addAllRow:SetParent(tdfContent)
        addAllRow:SetHeight(ROW_H)
        addAllRow:ClearAllPoints()
        addAllRow:SetPoint("TOPLEFT", tdfContent, "TOPLEFT", 0, 0)
        addAllRow:SetPoint("RIGHT", tdfContent, "RIGHT", 0, 0)
        addAllRow.bg:SetColorTexture(0.1, 0.14, 0.1, 0.5)
        addAllRow.text:SetText(ns.COLORS.GREEN .. "[Add All " .. #detectedChars .. " Characters]|r")
        addAllRow:SetScript("OnClick", function()
            for _, dc in ipairs(detectedChars) do
                ns.db.characters[dc.charKey] = ns.db.characters[dc.charKey] or {
                    class = dc.class,
                    gold = dc.gold,
                    lastLogin = 0,
                    inventory = nil,
                }
            end
            ns._detectedTSMChars = nil
            ns:Print(ns.COLORS.GREEN .. "Added " .. #detectedChars .. " character(s) from TSM.|r")
            UI:Refresh()
        end)
        addAllRow:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.12, 0.2, 0.12, 0.7) end)
        addAllRow:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.1, 0.14, 0.1, 0.5) end)
        PropagateScroll(addAllRow)
        addAllRow:Show()
        yOff = yOff - ROW_H

        for di, dc in ipairs(detectedChars) do
            local rowIdx = di + 1
            local row = tdf.rows[rowIdx]
            if not row then
                row = CreateFrame("Frame", nil, tdfContent)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.nameText:SetJustifyH("LEFT")
                row.realmText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.realmText:SetPoint("LEFT", row, "LEFT", 120, 0)
                row.goldText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.goldText:SetPoint("LEFT", row, "LEFT", 260, 0)
                row.addBtn = CreateFrame("Button", nil, row)
                row.addBtn:SetSize(36, 18)
                row.addBtn:SetPoint("RIGHT", row, "RIGHT", -56, 0)
                row.addBtn.text = row.addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.addBtn.text:SetAllPoints()
                row.addBtn.text:SetJustifyH("CENTER")
                row.dismissBtn = CreateFrame("Button", nil, row)
                row.dismissBtn:SetSize(52, 18)
                row.dismissBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                row.dismissBtn.text = row.dismissBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.dismissBtn.text:SetAllPoints()
                row.dismissBtn.text:SetJustifyH("CENTER")
                tdf.rows[rowIdx] = row
            end
            row:SetParent(tdfContent)
            row:SetHeight(ROW_H)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", tdfContent, "TOPLEFT", 0, yOff)
            row:SetPoint("RIGHT", tdfContent, "RIGHT", 0, 0)
            row.bg:SetColorTexture(di % 2 == 0 and 0.08 or 0.06, di % 2 == 0 and 0.08 or 0.06,
                di % 2 == 0 and 0.12 or 0.1, 0.5)

            local cc = dc.class and (CLASS_COLORS[dc.class] or CLASS_COLORS[dc.class:lower()]) or "888888"
            row.nameText:SetText("|cff" .. cc .. dc.name .. "|r")
            row.realmText:SetText(dc.realm)
            row.goldText:SetText(dc.gold > 0 and ns:FormatGold(dc.gold) or "")
            row.addBtn.text:SetText(ns.COLORS.GREEN .. "[Add]|r")
            row.dismissBtn.text:SetText(ns.COLORS.RED .. "[Dismiss]|r")

            local capturedDc = dc
            local capturedDi = di
            row.addBtn:SetScript("OnClick", function()
                ns.db.characters[capturedDc.charKey] = ns.db.characters[capturedDc.charKey] or {
                    class = capturedDc.class,
                    gold = capturedDc.gold,
                    lastLogin = 0,
                    inventory = nil,
                }
                table.remove(detectedChars, capturedDi)
                if #detectedChars == 0 then ns._detectedTSMChars = nil end
                ns:Print(ns.COLORS.GREEN .. "Added:|r " .. capturedDc.charKey)
                UI:Refresh()
            end)
            row.dismissBtn:SetScript("OnClick", function()
                ns.db.settings.dismissedTSMChars[capturedDc.charKey] = true
                table.remove(detectedChars, capturedDi)
                if #detectedChars == 0 then ns._detectedTSMChars = nil end
                ns:Print(ns.COLORS.GRAY .. "Dismissed:|r " .. capturedDc.charKey)
                UI:Refresh()
            end)
            PropagateScroll(row)
            PropagateScroll(row.addBtn)
            PropagateScroll(row.dismissBtn)
            row:Show()
            yOff = yOff - ROW_H
        end

        tdfContent:SetHeight(math.max(1, math.abs(yOff) + 10))
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
