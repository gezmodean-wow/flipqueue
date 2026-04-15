-- UI/CharactersPage.lua
-- Character list: gold, task counts, auction summary, per-char settings, config panel
local addonName, ns = ...

local UI = ns.UI

-- Forward declaration (defined after BuildCharactersData)
local RefreshCharactersTable

-- ==========================================
-- CHARACTER ROLE HELPERS
-- ==========================================

local ROLE_CYCLE = { both = "sell", sell = "buy", buy = "none", none = "both" }

local function CycleRole(current)
    return ROLE_CYCLE[current] or "both"
end

local function FormatRoleLabel(role)
    if role == "sell" then return "|cffffaa00Sell Only|r"
    elseif role == "buy" then return "|cff00aaffBuy Only|r"
    elseif role == "none" then return "|cff666666Hidden|r"
    else return "|cff00ff00Both|r"
    end
end

local function FormatRoleDesc(role)
    if role == "sell" then return "Sell and deposit tasks only"
    elseif role == "buy" then return "Buy and deposit tasks only"
    elseif role == "none" then return "Skipped for task routing"
    else return "Buy, sell, and deposit tasks"
    end
end

-- ==========================================
-- 3-STATE SETTING DISPLAY HELPERS
-- ==========================================

-- Format a 3-state setting value for column display:
--   nil = gray dash (using global default)
--   true = green checkmark
--   false = red X
local function FormatSettingColumn(rawValue, globalDefault)
    if rawValue == true then
        return "|cff00ff00" .. "On" .. "|r"
    elseif rawValue == false then
        return "|cffff3333" .. "Off" .. "|r"
    else
        -- Using global default — show inherited value in dim color
        if globalDefault then
            return "|cff557755" .. "On" .. "|r"
        else
            return "|cff775555" .. "Off" .. "|r"
        end
    end
end

-- Format a 3-state setting for the config panel button label:
--   nil = "Default (On)" or "Default (Off)" in gray
--   true = "On" in green
--   false = "Off" in red
local function FormatSettingLabel(rawValue, globalDefault)
    if rawValue == true then
        return "|cff00ff00On|r"
    elseif rawValue == false then
        return "|cffff3333Off|r"
    else
        local defStr = globalDefault and "On" or "Off"
        return "|cff888888Default (" .. defStr .. ")|r"
    end
end

-- Cycle a 3-state value: nil -> true -> false -> nil
local function CycleTriState(current)
    if current == nil then
        return true
    elseif current == true then
        return false
    else
        return nil
    end
end

-- ==========================================
-- BUILD CHARACTER DATA
-- ==========================================

local function BuildCharactersData()
    if not ns.db then return {}, {} end
    local CLASS_COLORS = UI._CLASS_COLORS
    local FormatGoldValue = UI._FormatGoldValue

    local charData = {}

    -- Build AH cluster groups: characters whose realms overlap share an AH
    -- Exclude hidden characters so they don't cause others to show "Shared AH"
    local clusters = {}  -- array of {realms={}, chars={charKey, ...}}
    for charKey, inv in pairs(ns.db.characters) do
        local realm = charKey:match("%-(.+)$") or ""
        if realm ~= "" and (inv.role or "both") ~= "none" then
            local found = nil
            for _, c in ipairs(clusters) do
                for _, cr in ipairs(c.realms) do
                    if ns:RealmsOverlap(realm, cr) then found = c; break end
                end
                if found then break end
            end
            if found then
                table.insert(found.chars, charKey)
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
    -- Only flag characters as "Shared AH" when another in the cluster has an overlapping role
    local charCluster = {}  -- charKey -> {clusterIdx, otherChars}
    for ci, c in ipairs(clusters) do
        if #c.chars > 1 then
            for _, ck in ipairs(c.chars) do
                local ckRole = (ns.db.characters[ck] or {}).role or "both"
                local overlappingOthers = {}
                for _, ock in ipairs(c.chars) do
                    if ock ~= ck then
                        local ockRole = (ns.db.characters[ock] or {}).role or "both"
                        if ns:RolesOverlap(ckRole, ockRole) then
                            table.insert(overlappingOthers, ock)
                        end
                    end
                end
                if #overlappingOthers > 0 then
                    charCluster[ck] = {
                        idx = ci,
                        realms = c.realms,
                        others = overlappingOthers,
                    }
                end
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
        local charRole = inv.role or "both"
        local isHidden = charRole == "none"

        -- Filter tasks by character's realm
        local tasks = {}
        for _, task in ipairs(allTasks) do
            if ns:RealmMatches(task.item.targetRealm, realm) then
                table.insert(tasks, task)
            end
        end

        local classColor = CLASS_COLORS[inv.class] or "888888"
        local isRemote = ns.IsRemoteChar and ns:IsRemoteChar(charKey)
        local coloredName = "|cff" .. classColor .. name .. "|r"
        if isHidden then
            coloredName = "|cff666666" .. name .. "|r"
        end
        -- Linked-account tag: simple (local)/(remote) indicator instead of
        -- the partner's full label. "local" = same Battle.net account (whisper
        -- transport), "remote" = different Battle.net account (bnet transport).
        if isRemote then
            local linkTag = "|cff8866cc(remote)|r"
            local charData = ns.db.characters[charKey]
            if charData and charData.accountUUID and ns.db.sync and ns.db.sync.partners then
                local partner = ns.db.sync.partners[charData.accountUUID]
                if partner and partner.transport == "whisper" then
                    linkTag = "|cff66cc88(local)|r"
                end
            end
            coloredName = linkTag .. " " .. coloredName
        end

        -- Phase 6a migration indicator. Tells the user whether this char's
        -- inventory is flowing through Syndicator yet, or whether they still
        -- need to log in once to seed it. Remote chars get the existing
        -- (remote)/(local) tag above and aren't tagged here.
        --   Live    — Syndicator projection has run for this char at least
        --             once since the migration (green)
        --   Ready   — Syndicator has data cached but FlipQueue hasn't
        --             projected it yet. Will happen automatically on next
        --             login (or next bulk-project pass if the realm alias
        --             is known) (blue)
        --   Pending — Syndicator doesn't have data either. The user needs
        --             to log in on that character once while Syndicator is
        --             running (yellow)
        if not isRemote and not isHidden then
            local charData = ns.db.characters[charKey]
            local badge
            if charData and charData.syndicatorBacked then
                badge = "|cff44dd44[Live]|r"
            else
                -- Fast existence check against Syndicator's known-chars
                -- list. The list is cached by Syndicator so the pcall is
                -- cheap. Match by name + normalized-realm translation
                -- when we have an alias, otherwise by name alone (safe
                -- because WoW character names are unique per server and
                -- the Characters tab is grouped by realm anyway).
                local isReady = false
                if Syndicator and Syndicator.API and Syndicator.API.GetAllCharacters then
                    local ok, allChars = pcall(Syndicator.API.GetAllCharacters)
                    if ok and type(allChars) == "table" then
                        for _, synKey in ipairs(allChars) do
                            local synName = synKey:match("^(.-)%-")
                            if synName == name then isReady = true; break end
                        end
                    end
                end
                if isReady then
                    badge = "|cff66aaff[Ready]|r"
                else
                    badge = "|cffddcc44[Pending]|r"
                end
            end
            coloredName = coloredName .. "  " .. badge
        end

        local goldCopper = inv.gold or 0
        local goldStr = ns:FormatGold(goldCopper)
        local lastLoginTime = inv.lastLogin or 0

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

        -- Build status string (showing role + shared AH indicator)
        local statusParts = {}
        if isHidden then
            table.insert(statusParts, "|cff666666Hidden|r")
        elseif charCluster[charKey] then
            if charRole == "sell" then
                table.insert(statusParts, "|cffff8800Sell*|r")
            elseif charRole == "buy" then
                table.insert(statusParts, "|cffff8800Buy*|r")
            else
                table.insert(statusParts, "|cffff8800Both*|r")
            end
        elseif charRole == "sell" then
            table.insert(statusParts, "|cffffaa00Sell|r")
        elseif charRole == "buy" then
            table.insert(statusParts, "|cff00aaffBuy|r")
        else
            table.insert(statusParts, "|cff00ff00Both|r")
        end
        local statusStr = table.concat(statusParts, " ")

        -- Row color
        local rowColor = nil
        if isRemote then
            rowColor = {0.4, 0.3, 0.6, 0.1}
        elseif isHidden then
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

        -- Per-character setting raw values for Pull/Dep/All columns
        local pullRaw = ns:GetCharSettingRaw(charKey, "autoPullBank")
        local depRaw = ns:GetCharSettingRaw(charKey, "autoDepositWarbank")
        local depAllRaw = ns:GetCharSettingRaw(charKey, "autoDepositAll")

        table.insert(charData, {
            name      = coloredName,
            realm     = realm,
            gold      = goldStr,
            tasks     = isHidden and "-" or tostring(#tasks),
            auctions  = auctionStr ~= "" and auctionStr or "",
            pull      = FormatSettingColumn(pullRaw, ns.db.settings.autoPullBank),
            dep       = FormatSettingColumn(depRaw, ns.db.settings.autoDepositWarbank),
            depAll    = FormatSettingColumn(depAllRaw, ns.db.settings.autoDepositAll),
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
                "Gold: %s\nRole: %s\n%d queue tasks%s\nStatus: %s%s\n\nClick to configure\nShift+Right-click: move up\nCtrl+Right-click: move down",
                goldStr,
                charRole == "sell" and "Sell Only" or (charRole == "buy" and "Buy Only" or (isHidden and "Hidden" or "Both")),
                #tasks,
                auctionInfo and ("\n" .. auctionInfo.active .. " active, " .. auctionInfo.done .. " done auction(s)") or "",
                isHidden and "Hidden" or (charCluster[charKey] and "Shared AH" or "Active"),
                charCluster[charKey] and ("\nAH Cluster: " .. table.concat(charCluster[charKey].realms, ", ") ..
                    "\nShared with: " .. table.concat(
                        (function()
                            local names = {}
                            for _, ock in ipairs(charCluster[charKey].others) do
                                table.insert(names, ock:match("^(.-)%-") or ock)
                            end
                            return names
                        end)(), ", ")) or ""),
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

-- ==========================================
-- CONFIG PANEL (right-side detail panel)
-- ==========================================

local configPanel       -- the Frame itself
local configWidgets = {}  -- named references to sub-widgets

local TAB_ICON_SIZE = 26
local TAB_SPACING = 4

local function EnsureConfigPanel(tableContainer)
    if configPanel then return end

    local PANEL_WIDTH = 210

    configPanel = CreateFrame("Frame", nil, tableContainer, "BackdropTemplate")
    configPanel:SetWidth(PANEL_WIDTH)
    configPanel:SetPoint("TOPLEFT", tableContainer, "TOPRIGHT", 2, 0)
    configPanel:SetPoint("BOTTOMLEFT", tableContainer, "BOTTOMRIGHT", 2, 0)
    configPanel:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = {left = 2, right = 2, top = 2, bottom = 2},
    })
    configPanel:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
    configPanel:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    configPanel:SetFrameLevel(tableContainer:GetFrameLevel() + 5)
    configPanel:Hide()
    UI._charConfigPanel = configPanel

    local L_MARGIN = 8
    local R_MARGIN = -8

    -- Close button (top-right)
    local closeBtn = CreateFrame("Button", nil, configPanel)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", configPanel, "TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:SetScript("OnClick", function() configPanel:Hide() end)
    configWidgets.closeBtn = closeBtn

    -- Character name + realm
    local nameLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", configPanel, "TOPLEFT", L_MARGIN, -8)
    nameLabel:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetWordWrap(true)
    configWidgets.nameLabel = nameLabel

    local realmLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    realmLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -2)
    realmLabel:SetJustifyH("LEFT")
    configWidgets.realmLabel = realmLabel

    -- Divider
    local div1 = configPanel:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(1)
    div1:SetPoint("TOPLEFT", realmLabel, "BOTTOMLEFT", 0, -6)
    div1:SetPoint("RIGHT", configPanel, "RIGHT", R_MARGIN, 0)
    div1:SetColorTexture(0.35, 0.35, 0.45, 0.6)

    -- Character Role selector
    local roleRow = CreateFrame("Frame", nil, configPanel)
    roleRow:SetPoint("TOPLEFT", div1, "BOTTOMLEFT", 0, -6)
    roleRow:SetPoint("RIGHT", configPanel, "RIGHT", R_MARGIN, 0)
    roleRow:SetHeight(20)

    local roleLbl = roleRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    roleLbl:SetPoint("LEFT", roleRow, "LEFT", 0, 0)
    roleLbl:SetText("Role:")

    local roleBtn = CreateFrame("Button", nil, roleRow, "BackdropTemplate")
    roleBtn:SetSize(110, 18)
    roleBtn:SetPoint("RIGHT", roleRow, "RIGHT", 0, 0)
    roleBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = {left = 1, right = 1, top = 1, bottom = 1},
    })
    roleBtn:SetBackdropColor(0.12, 0.12, 0.15, 1)
    roleBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    roleBtn.text = roleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleBtn.text:SetPoint("CENTER")
    configWidgets.roleBtn = roleBtn

    local roleDesc = configPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    roleDesc:SetPoint("TOPLEFT", roleRow, "BOTTOMLEFT", 0, -1)
    roleDesc:SetPoint("RIGHT", configPanel, "RIGHT", R_MARGIN, 0)
    roleDesc:SetJustifyH("LEFT")
    roleDesc:SetWordWrap(true)
    roleDesc:SetTextColor(0.5, 0.5, 0.5)
    configWidgets.roleDesc = roleDesc

    -- Divider
    local div2 = configPanel:CreateTexture(nil, "ARTWORK")
    div2:SetHeight(1)
    div2:SetPoint("TOPLEFT", roleDesc, "BOTTOMLEFT", 0, -6)
    div2:SetPoint("RIGHT", configPanel, "RIGHT", R_MARGIN, 0)
    div2:SetColorTexture(0.35, 0.35, 0.45, 0.6)

    -- Section label: Automation Overrides
    local autoLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoLabel:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -4)
    autoLabel:SetTextColor(0.9, 0.8, 0.3)
    autoLabel:SetText("Automation Overrides")

    -- Helper to create a 3-state toggle row
    local function Create3StateRow(anchorBelow, labelText, settingKey)
        local row = CreateFrame("Frame", nil, configPanel)
        row:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -4)
        row:SetPoint("RIGHT", configPanel, "RIGHT", R_MARGIN, 0)
        row:SetHeight(20)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
        lbl:SetText(labelText)

        local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
        btn:SetSize(110, 18)
        btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        btn:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = {left = 1, right = 1, top = 1, bottom = 1},
        })
        btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")

        btn._settingKey = settingKey
        return row, btn
    end

    -- Auto-Pull
    local pullRow, pullBtn = Create3StateRow(autoLabel, "Pull:", "autoPullBank")
    configWidgets.pullRow = pullRow
    configWidgets.pullBtn = pullBtn

    -- Auto-Deposit
    local depRow, depBtn = Create3StateRow(pullRow, "Deposit:", "autoDepositWarbank")
    configWidgets.depRow = depRow
    configWidgets.depBtn = depBtn

    -- Auto-Deposit All
    local depAllRow, depAllBtn = Create3StateRow(depRow, "Dep. All:", "autoDepositAll")
    configWidgets.depAllRow = depAllRow
    configWidgets.depAllBtn = depAllBtn

    -- Divider
    local div3 = configPanel:CreateTexture(nil, "ARTWORK")
    div3:SetHeight(1)
    div3:SetPoint("TOPLEFT", depAllRow, "BOTTOMLEFT", 0, -6)
    div3:SetPoint("RIGHT", configPanel, "RIGHT", R_MARGIN, 0)
    div3:SetColorTexture(0.35, 0.35, 0.45, 0.6)

    -- Bank tab selection: personal bank (6 tabs)
    local bankLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bankLabel:SetPoint("TOPLEFT", div3, "BOTTOMLEFT", 0, -4)
    bankLabel:SetTextColor(0.9, 0.8, 0.3)
    bankLabel:SetText("Bank Tabs")
    configWidgets.bankLabel = bankLabel

    configWidgets.bankTabBtns = {}
    for i = 1, 6 do
        local tabBtn = CreateFrame("CheckButton", nil, configPanel)
        tabBtn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
        tabBtn:SetPoint("TOPLEFT", bankLabel, "BOTTOMLEFT", (i - 1) * (TAB_ICON_SIZE + TAB_SPACING), -4)

        tabBtn.icon = tabBtn:CreateTexture(nil, "ARTWORK")
        tabBtn.icon:SetSize(TAB_ICON_SIZE - 2, TAB_ICON_SIZE - 2)
        tabBtn.icon:SetPoint("CENTER")
        tabBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_29")

        tabBtn.border = tabBtn:CreateTexture(nil, "OVERLAY")
        tabBtn.border:SetAllPoints()
        tabBtn.border:SetColorTexture(0.3, 0.8, 0.3, 0.4)
        tabBtn.border:Hide()

        tabBtn.uncheckedBorder = tabBtn:CreateTexture(nil, "OVERLAY")
        tabBtn.uncheckedBorder:SetAllPoints()
        tabBtn.uncheckedBorder:SetColorTexture(0.5, 0.1, 0.1, 0.4)
        tabBtn.uncheckedBorder:Hide()

        tabBtn.label = tabBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tabBtn.label:SetPoint("TOP", tabBtn, "BOTTOM", 0, -1)
        tabBtn.label:SetText(tostring(i))
        tabBtn.label:SetTextColor(0.7, 0.7, 0.7)

        tabBtn.tabIndex = i
        configWidgets.bankTabBtns[i] = tabBtn
    end

    -- Divider before warbank
    local div4 = configPanel:CreateTexture(nil, "ARTWORK")
    div4:SetHeight(1)
    -- Position dynamically below bank tabs: bankLabel + 4 + TAB_ICON_SIZE + label height + gap
    div4:SetPoint("TOPLEFT", bankLabel, "BOTTOMLEFT", 0, -(TAB_ICON_SIZE + 18))
    div4:SetPoint("RIGHT", configPanel, "RIGHT", R_MARGIN, 0)
    div4:SetColorTexture(0.35, 0.35, 0.45, 0.6)
    configWidgets.div4 = div4

    -- Warbank tab selection (5 tabs, global/shared)
    local wbLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wbLabel:SetPoint("TOPLEFT", div4, "BOTTOMLEFT", 0, -4)
    wbLabel:SetTextColor(0.9, 0.8, 0.3)
    wbLabel:SetText("Warbank Tabs (shared)")
    configWidgets.wbLabel = wbLabel

    configWidgets.warbankTabBtns = {}
    for i = 1, 5 do
        local tabBtn = CreateFrame("CheckButton", nil, configPanel)
        tabBtn:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
        tabBtn:SetPoint("TOPLEFT", wbLabel, "BOTTOMLEFT", (i - 1) * (TAB_ICON_SIZE + TAB_SPACING), -4)

        tabBtn.icon = tabBtn:CreateTexture(nil, "ARTWORK")
        tabBtn.icon:SetSize(TAB_ICON_SIZE - 2, TAB_ICON_SIZE - 2)
        tabBtn.icon:SetPoint("CENTER")
        tabBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_29")

        tabBtn.border = tabBtn:CreateTexture(nil, "OVERLAY")
        tabBtn.border:SetAllPoints()
        tabBtn.border:SetColorTexture(0.3, 0.8, 0.3, 0.4)
        tabBtn.border:Hide()

        tabBtn.uncheckedBorder = tabBtn:CreateTexture(nil, "OVERLAY")
        tabBtn.uncheckedBorder:SetAllPoints()
        tabBtn.uncheckedBorder:SetColorTexture(0.5, 0.1, 0.1, 0.4)
        tabBtn.uncheckedBorder:Hide()

        tabBtn.label = tabBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tabBtn.label:SetPoint("TOP", tabBtn, "BOTTOM", 0, -1)
        tabBtn.label:SetText(tostring(i))
        tabBtn.label:SetTextColor(0.7, 0.7, 0.7)

        tabBtn.tabIndex = i
        configWidgets.warbankTabBtns[i] = tabBtn
    end
end

-- Populate and show the config panel for a given character
local function ShowConfigPanel(charKey)
    if not configPanel then return end
    if not ns.db or not ns.db.characters then return end

    local charData = ns.db.characters[charKey]
    if not charData then return end

    local CLASS_COLORS = UI._CLASS_COLORS
    local name = charKey:match("^(.-)%-") or charKey
    local realm = charKey:match("%-(.+)$") or ""
    local classColor = CLASS_COLORS[charData.class] or "888888"

    configWidgets.nameLabel:SetText("|cff" .. classColor .. name .. "|r")
    configWidgets.realmLabel:SetText(realm)

    -- Role button
    local role = charData.role or "both"
    configWidgets.roleBtn.text:SetText(FormatRoleLabel(role))
    configWidgets.roleDesc:SetText(FormatRoleDesc(role))
    configWidgets.roleBtn:SetScript("OnClick", function()
        local currentRole = charData.role or "both"
        local newRole = CycleRole(currentRole)
        ns:SetCharRole(charKey, newRole)
        configWidgets.roleBtn.text:SetText(FormatRoleLabel(newRole))
        configWidgets.roleDesc:SetText(FormatRoleDesc(newRole))
        if newRole == "none" then
            ns:Print("Hidden character: " .. charKey .. " (will be skipped for task routing)")
        else
            local roleNames = { both = "Both", sell = "Sell Only", buy = "Buy Only" }
            ns:Print("Set role for " .. charKey .. ": " .. (roleNames[newRole] or newRole))
        end
        RefreshCharactersTable()
    end)
    configWidgets.roleBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Character Role", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Both|r - Gets buy, sell, and deposit tasks", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffaa00Sell|r - Gets sell and deposit tasks only", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cff00aaffBuy|r - Gets buy and deposit tasks only", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cff666666Hidden|r - Skipped for all task routing", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to cycle", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    configWidgets.roleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 3-state buttons
    local function SetupTriStateBtn(btn, settingKey)
        local rawVal = ns:GetCharSettingRaw(charKey, settingKey)
        local globalDefault = ns.db.settings[settingKey]
        btn.text:SetText(FormatSettingLabel(rawVal, globalDefault))

        btn:SetScript("OnClick", function()
            local current = ns:GetCharSettingRaw(charKey, settingKey)
            local newVal = CycleTriState(current)
            ns:SetCharSetting(charKey, settingKey, newVal)
            -- Update button label
            local updated = ns:GetCharSettingRaw(charKey, settingKey)
            btn.text:SetText(FormatSettingLabel(updated, ns.db.settings[settingKey]))
            RefreshCharactersTable()
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local current = ns:GetCharSettingRaw(charKey, settingKey)
            if current == nil then
                GameTooltip:SetText("Using global default", 0.7, 0.7, 0.7)
                GameTooltip:AddLine("Click to override to On", 0.5, 0.5, 0.5)
            elseif current == true then
                GameTooltip:SetText("Override: On", 0, 1, 0)
                GameTooltip:AddLine("Click to override to Off", 0.5, 0.5, 0.5)
            else
                GameTooltip:SetText("Override: Off", 1, 0.2, 0.2)
                GameTooltip:AddLine("Click to clear override (use global)", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    SetupTriStateBtn(configWidgets.pullBtn, "autoPullBank")
    SetupTriStateBtn(configWidgets.depBtn, "autoDepositWarbank")
    SetupTriStateBtn(configWidgets.depAllBtn, "autoDepositAll")

    -- Bank tab buttons (per-character)
    local pt = ns.db.settings.pullTabs or {}

    -- Try to get tab data from C_Bank API
    local bankTabData, warbankTabData
    if C_Bank and C_Bank.FetchPurchasedBankTabData then
        local ok1, data1 = pcall(C_Bank.FetchPurchasedBankTabData, Enum.BankType.Character)
        if ok1 and data1 then bankTabData = data1 end
        local ok2, data2 = pcall(C_Bank.FetchPurchasedBankTabData, Enum.BankType.Account)
        if ok2 and data2 then warbankTabData = data2 end
    end

    for i = 1, 6 do
        local btn = configWidgets.bankTabBtns[i]
        local charCfg = pt.bank and pt.bank[charKey]
        local enabled = not charCfg or charCfg[i] ~= false

        -- Update icon/label from API data if available
        if bankTabData and bankTabData[i] then
            local td = bankTabData[i]
            if td.icon then btn.icon:SetTexture(td.icon) end
            if td.name and td.name ~= "" then
                btn.label:SetText(td.name)
            else
                btn.label:SetText(tostring(i))
            end
        end

        if enabled then
            btn.icon:SetDesaturated(false)
            btn.icon:SetAlpha(1)
            btn.border:Show()
            btn.uncheckedBorder:Hide()
            btn.label:SetTextColor(0.7, 0.9, 0.7)
        else
            btn.icon:SetDesaturated(true)
            btn.icon:SetAlpha(0.5)
            btn.border:Hide()
            btn.uncheckedBorder:Show()
            btn.label:SetTextColor(0.5, 0.4, 0.4)
        end

        btn:SetScript("OnClick", function()
            if not ns.db then return end
            local pullTabs = ns.db.settings.pullTabs
            if not pullTabs.bank then pullTabs.bank = {} end
            if not pullTabs.bank[charKey] then pullTabs.bank[charKey] = {} end
            local isEnabled = pullTabs.bank[charKey][i] ~= false
            pullTabs.bank[charKey][i] = not isEnabled
            ShowConfigPanel(charKey)
            RefreshCharactersTable()
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.label:GetText() or ("Bank Tab " .. i), 1, 1, 1)
            local cfg = pt.bank and pt.bank[charKey]
            local isOn = not cfg or cfg[i] ~= false
            GameTooltip:AddLine(isOn and "Enabled (click to disable)" or "Disabled (click to enable)", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Warbank tab buttons (global/shared)
    for i = 1, 5 do
        local btn = configWidgets.warbankTabBtns[i]
        local enabled = not pt.warbank or pt.warbank[i] ~= false

        if warbankTabData and warbankTabData[i] then
            local td = warbankTabData[i]
            if td.icon then btn.icon:SetTexture(td.icon) end
            if td.name and td.name ~= "" then
                btn.label:SetText(td.name)
            else
                btn.label:SetText(tostring(i))
            end
        end

        if enabled then
            btn.icon:SetDesaturated(false)
            btn.icon:SetAlpha(1)
            btn.border:Show()
            btn.uncheckedBorder:Hide()
            btn.label:SetTextColor(0.7, 0.9, 0.7)
        else
            btn.icon:SetDesaturated(true)
            btn.icon:SetAlpha(0.5)
            btn.border:Hide()
            btn.uncheckedBorder:Show()
            btn.label:SetTextColor(0.5, 0.4, 0.4)
        end

        btn:SetScript("OnClick", function()
            if not ns.db then return end
            local pullTabs = ns.db.settings.pullTabs
            if not pullTabs.warbank then pullTabs.warbank = {} end
            local isEnabled = pullTabs.warbank[i] ~= false
            pullTabs.warbank[i] = not isEnabled
            ShowConfigPanel(charKey)
            RefreshCharactersTable()
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.label:GetText() or ("Warbank Tab " .. i), 1, 1, 1)
            local isOn = not pt.warbank or pt.warbank[i] ~= false
            GameTooltip:AddLine(isOn and "Enabled (click to disable)" or "Disabled (click to enable)", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    configPanel._charKey = charKey
    configPanel:Show()
end

-- ==========================================
-- GLOBAL DEFAULTS BAR
-- ==========================================

local globalDefaultsBar
local globalDefaultsWidgets = {}

local function EnsureGlobalDefaultsBar(tableContainer)
    if globalDefaultsBar then return end

    globalDefaultsBar = CreateFrame("Frame", nil, tableContainer, "BackdropTemplate")
    globalDefaultsBar:SetHeight(24)
    globalDefaultsBar:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
    globalDefaultsBar:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
    globalDefaultsBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    })
    globalDefaultsBar:SetBackdropColor(0.1, 0.1, 0.14, 0.8)
    UI._globalDefaultsBar = globalDefaultsBar

    local lbl = globalDefaultsBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", globalDefaultsBar, "LEFT", 6, 0)
    lbl:SetTextColor(0.9, 0.8, 0.3)
    lbl:SetText("Global Defaults:")

    -- Helper: create a small checkbox
    local function MakeGlobalCB(anchorTo, label, settingKey, tooltipDesc)
        local cb = CreateFrame("CheckButton", nil, globalDefaultsBar, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        cb:SetPoint("LEFT", anchorTo, "RIGHT", 8, 0)
        cb.text:SetText(label)
        cb.text:SetFontObject("GameFontHighlightSmall")

        cb:SetScript("OnClick", function(self)
            if ns.db then
                ns.db.settings[settingKey] = self:GetChecked()
                RefreshCharactersTable()
            end
        end)

        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltipDesc, 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

        return cb
    end

    globalDefaultsWidgets.pullCB = MakeGlobalCB(lbl, "Pull",
        "autoPullBank", "Auto-pull queued items from bank when opening bank")

    globalDefaultsWidgets.depCB = MakeGlobalCB(globalDefaultsWidgets.pullCB.text, "Deposit",
        "autoDepositWarbank", "Auto-deposit items to warbank for other characters")

    globalDefaultsWidgets.depAllCB = MakeGlobalCB(globalDefaultsWidgets.depCB.text, "Dep. All",
        "autoDepositAll", "Auto-deposit ALL extra items to bank/warbank")
end

local function RefreshGlobalDefaultsBar()
    if not globalDefaultsBar or not ns.db then return end
    globalDefaultsWidgets.pullCB:SetChecked(ns.db.settings.autoPullBank)
    globalDefaultsWidgets.depCB:SetChecked(ns.db.settings.autoDepositWarbank)
    globalDefaultsWidgets.depAllCB:SetChecked(ns.db.settings.autoDepositAll)
    globalDefaultsBar:Show()
end

-- Lightweight refresh: update table data + global defaults bar without rebuilding config panel.
-- Call this instead of UI:Refresh() when changing settings inside the config panel.
function RefreshCharactersTable()
    local charData = BuildCharactersData()
    if UI.charsTable then
        UI.charsTable:SetData(charData)
    end
    RefreshGlobalDefaultsBar()
    if UI.mainFrame and UI.mainFrame.statusText then
        local charCount, hiddenCount, totalGold = 0, 0, 0
        for ck, ckData in pairs(ns.db.characters or {}) do
            charCount = charCount + 1
            if (ckData.role or "both") == "none" then hiddenCount = hiddenCount + 1 end
            if ckData.gold then totalGold = totalGold + ckData.gold end
        end
        local parts = { charCount .. " characters" }
        if totalGold > 0 then table.insert(parts, ns:FormatGold(totalGold) .. " total") end
        if hiddenCount > 0 then table.insert(parts, hiddenCount .. " hidden") end
        table.insert(parts, ns.COLORS.GRAY .. "Click character to configure" .. "|r")
        UI.mainFrame.statusText:SetText(table.concat(parts, "  |  "))
    end
end

-- ==========================================
-- REFRESH PAGE
-- ==========================================

function UI:RefreshCharactersPage()
    local mainFrame = UI.mainFrame
    local tableContainer = UI.tableContainer
    mainFrame.pageTitle:SetText("Characters & Realms")
    UI._HideAllActionBtns()

    -- Ensure global defaults bar and config panel are created
    EnsureGlobalDefaultsBar(tableContainer)
    EnsureConfigPanel(tableContainer)

    RefreshGlobalDefaultsBar()

    local charData, needData = BuildCharactersData()

    -- Position charsTable header below the global defaults bar
    self.charsTable.headerFrame:ClearAllPoints()
    self.charsTable.headerFrame:SetPoint("TOPLEFT", globalDefaultsBar, "BOTTOMLEFT", 0, -1)
    self.charsTable.headerFrame:SetPoint("TOPRIGHT", globalDefaultsBar, "BOTTOMRIGHT", 0, -1)

    -- Show known characters table
    UI._ShowTable(self.charsTable)
    self.charsTable:SetRowClickHandler(function(rowData, button, rowIndex)
        if button == "LeftButton" and rowData._charKey then
            -- Left-click opens config panel
            ShowConfigPanel(rowData._charKey)
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
                        ns:PrintDebug("Moved up: " .. rowData._charKey)
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
                        ns:PrintDebug("Moved down: " .. rowData._charKey)
                        break
                    end
                end
                self:Refresh()
            end
        end
    end)
    self.charsTable:SetData(charData)

    -- Show "need characters" table below if there are entries
    if #needData > 0 then
        local GLOBALS_H = 25  -- height of global defaults bar + gap
        local charsHeight = math.max(60, (#charData + 1) * 20 + 22)
        if charsHeight > 250 then charsHeight = 250 end

        -- Section heading: same style as "Next Steps" on To-Do page
        if not self._needCharsLabel then
            self._needCharsLabel = tableContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        self._needCharsLabel:ClearAllPoints()
        self._needCharsLabel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 4, -(GLOBALS_H + charsHeight + 6))
        self._needCharsLabel:SetPoint("RIGHT", tableContainer, "RIGHT", -4, 0)
        self._needCharsLabel:SetJustifyH("LEFT")
        self._needCharsLabel:SetTextColor(1, 0.4, 0.4)
        self._needCharsLabel:SetText("Realms Needing a Character (" .. #needData .. ")")
        self._needCharsLabel:Show()

        self.needCharsTable.headerFrame:ClearAllPoints()
        self.needCharsTable.headerFrame:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, -(GLOBALS_H + charsHeight + 18))
        self.needCharsTable.headerFrame:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, -(GLOBALS_H + charsHeight + 18))

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
        local GLOBALS_H = 25

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

        -- Anchor TSM section from the container BOTTOM to prevent overflow.
        -- The scroll area is capped to MAX_VISIBLE_ROWS and the label sits above it.
        local totalContentH = (#detectedChars + 1) * ROW_H + 10
        local maxScrollH = MAX_VISIBLE_ROWS * ROW_H + 10
        local tsmScrollH = math.min(totalContentH, maxScrollH)

        tdfLabel:ClearAllPoints()
        tdfLabel:SetPoint("BOTTOMLEFT", tableContainer, "BOTTOMLEFT", 4, tsmScrollH + 2)
        tdfLabel:SetText("Detected from TSM (" .. #detectedChars .. ")")
        tdfLabel:Show()

        -- Clamp tables above the TSM section so they don't overflow into it
        if #needData > 0 then
            self.needCharsTable.scrollFrame:ClearAllPoints()
            self.needCharsTable.scrollFrame:SetPoint("TOPLEFT", self.needCharsTable.headerFrame, "BOTTOMLEFT", 0, 0)
            self.needCharsTable.scrollFrame:SetPoint("RIGHT", tableContainer, "RIGHT", -22, 0)
            self.needCharsTable.scrollFrame:SetPoint("BOTTOM", tdfLabel, "TOP", 0, 4)
        else
            self.charsTable.scrollFrame:ClearAllPoints()
            self.charsTable.scrollFrame:SetPoint("TOPLEFT", self.charsTable.headerFrame, "BOTTOMLEFT", 0, 0)
            self.charsTable.scrollFrame:SetPoint("RIGHT", tableContainer, "RIGHT", -22, 0)
            self.charsTable.scrollFrame:SetPoint("BOTTOM", tdfLabel, "TOP", 0, 4)
        end

        -- Scroll frame fills from label bottom to container bottom
        tdfScroll:ClearAllPoints()
        tdfScroll:SetPoint("TOPLEFT", tdfLabel, "BOTTOMLEFT", -4, -2)
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
            if ns.TodoList and ns.TodoList.ReassignUnassignedTasks then
                local reassigned = ns.TodoList:ReassignUnassignedTasks()
                if reassigned > 0 then
                    ns:Print(ns.COLORS.GREEN .. reassigned .. " task(s)|r auto-assigned to new characters.")
                end
            end
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
                if ns.TodoList and ns.TodoList.ReassignUnassignedTasks then
                    local reassigned = ns.TodoList:ReassignUnassignedTasks()
                    if reassigned > 0 then
                        ns:Print(ns.COLORS.GREEN .. reassigned .. " task(s)|r auto-assigned to " .. capturedDc.charKey)
                    end
                end
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

    -- Status bar
    local charCount = 0
    local hiddenCount = 0
    local totalGold = 0
    for ck, ckData in pairs(ns.db.characters) do
        charCount = charCount + 1
        if (ckData.role or "both") == "none" then hiddenCount = hiddenCount + 1 end
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
    table.insert(statusParts, ns.COLORS.GRAY .. "Click character to configure" .. "|r")
    mainFrame.statusText:SetText(table.concat(statusParts, "  |  "))

    -- If config panel is showing, refresh it to stay in sync
    if configPanel and configPanel:IsShown() and configPanel._charKey then
        ShowConfigPanel(configPanel._charKey)
    end
end

-- Register layout callback for container resize
UI:RegisterPageLayout("characters", function()
    -- The tsmDetectedScroll has OnSizeChanged, but sync content width defensively
    if UI._tsmDetectedScroll and UI._tsmDetectedContent then
        UI._tsmDetectedContent:SetWidth(UI._tsmDetectedScroll:GetWidth())
    end
end)
