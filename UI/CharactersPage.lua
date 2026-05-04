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

-- (#155) Format an action-class mode value for column display:
--   nil    = inherited from global (shown in dim color matching the global)
--   "auto"     = green
--   "manual"   = yellow
--   "disabled" = red dash
local function FormatModeColumn(rawValue, globalMode)
    local function color(mode, dim)
        local c, label
        if mode == "auto"     then c, label = "00ff00", "Auto"
        elseif mode == "manual"   then c, label = "ffcc00", "Manual"
        elseif mode == "disabled" then c, label = "ff3333", "Off"
        else                            c, label = "888888", "?"
        end
        if dim then
            -- Halve brightness for inherited-from-global rendering
            c = c:gsub("%w%w", function(hh) return string.format("%02x", math.floor(tonumber(hh, 16) / 2)) end)
        end
        return "|cff" .. c .. label .. "|r"
    end
    if rawValue == "auto" or rawValue == "manual" or rawValue == "disabled" then
        return color(rawValue, false)
    else
        return color(globalMode or "manual", true)
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
    local showHidden = ns.db.settings.showHiddenChars and true or false
    local showDeleted = ns.db.settings.showDeletedChars and true or false
    for charKey, inv in pairs(ns.db.characters) do
        local name = charKey:match("^(.-)%-") or charKey
        local realm = charKey:match("%-(.+)$") or ""
        local charRole = inv.role or "both"
        local isHidden = charRole == "none"
        -- Hide hidden characters from the list unless the user opts in via
        -- the "Show Hidden" toggle. Skipping via a goto-style early continue
        -- isn't available in 5.1, so nest the rest of the block.
        if not (isHidden and not showHidden) then
        local allTasks = ns.TodoList:GetCharacterTasks(charKey)

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

        -- Build status string (showing role + shared AH indicator).
        -- Hidden rows are only in the list when the "Show Hidden" toggle
        -- is on; repurpose the status cell as an [Unhide] action hint —
        -- clicking the row unhides directly (see row click handler).
        local statusParts = {}
        if isHidden then
            table.insert(statusParts, "|cff66ff66[Unhide]|r")
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

        -- (#155) Per-character setting raw values for the action-mode columns.
        -- Each tri-state mode displays as Auto / Manual / Off (or — when no
        -- per-char override is set, defaulting to global).
        local todoRaw     = ns:GetCharSettingRaw(charKey, "todoMode")
        local extrasRaw   = ns:GetCharSettingRaw(charKey, "extrasMode")
        local reagentsRaw = ns:GetCharSettingRaw(charKey, "reagentsMode")

        table.insert(charData, {
            name      = coloredName,
            realm     = realm,
            gold      = goldStr,
            tasks     = isHidden and "-" or tostring(#tasks),
            auctions  = auctionStr ~= "" and auctionStr or "",
            pull      = FormatModeColumn(todoRaw,     ns.db.settings.todoMode),
            dep       = FormatModeColumn(extrasRaw,   ns.db.settings.extrasMode),
            depAll    = FormatModeColumn(reagentsRaw, ns.db.settings.reagentsMode),
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
        end  -- if not (isHidden and not showHidden)
    end

    -- Deleted-character ghost rows. Included only when "Show Deleted" is on.
    -- These rows are minimal (name + realm + status) and clicking them
    -- restores the character. They sit at the bottom of the list via a
    -- sentinel _orderPos.
    if showDeleted then
        local deleted = ns:GetDeletedCharacters()
        for _, entry in ipairs(deleted) do
            local dKey = entry.charKey
            local name = dKey:match("^(.-)%-") or dKey
            local realm = dKey:match("%-(.+)$") or ""
            table.insert(charData, {
                name      = "|cff884444" .. name .. "|r  |cff777777(deleted)|r",
                realm     = realm,
                gold      = "-",
                tasks     = "-",
                auctions  = "",
                pull      = "-",
                dep       = "-",
                depAll    = "-",
                status    = "|cff66ff66[Restore]|r",
                _sortName = name:lower(),
                _sortGold = -1,
                _sortLastLogin = entry.deletedAt or 0,
                _sortAuctions = -1,
                _charKey = dKey,
                _isDeleted = true,
                _rowColor = {0.35, 0.1, 0.1, 0.15},
                _orderPos = 10000,  -- sort deleted rows to the bottom
                _tooltipText = dKey .. " (deleted)",
                _tooltipExtra = "Deleted " .. (ns:FormatRelativeTime(entry.deletedAt or 0)) ..
                    (entry.syndicatorPurged and "\nSyndicator cache was purged" or "") ..
                    "\n\nClick to restore",
            })
        end
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

    -- Section label: FlipQueue manages… (#148 master switches)
    local manageLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    manageLabel:SetPoint("TOPLEFT", div2, "BOTTOMLEFT", 0, -4)
    manageLabel:SetTextColor(0.9, 0.8, 0.3)
    manageLabel:SetText("FlipQueue manages…")

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

    -- Manage masters (per-character override of global manageItems/manageGold)
    local manageItemsRow, manageItemsBtn = Create3StateRow(manageLabel, "Items:", "manageItems")
    configWidgets.manageItemsRow = manageItemsRow
    configWidgets.manageItemsBtn = manageItemsBtn

    local manageGoldRow, manageGoldBtn = Create3StateRow(manageItemsRow, "Gold:", "manageGold")
    configWidgets.manageGoldRow = manageGoldRow
    configWidgets.manageGoldBtn = manageGoldBtn

    -- Divider between master switches and per-action triggers
    local divManage = configPanel:CreateTexture(nil, "ARTWORK")
    divManage:SetHeight(1)
    divManage:SetPoint("TOPLEFT", manageGoldRow, "BOTTOMLEFT", 0, -8)
    divManage:SetPoint("RIGHT", configPanel, "RIGHT", R_MARGIN, 0)
    divManage:SetColorTexture(0.35, 0.35, 0.45, 0.6)

    -- Section label: Automation Overrides (per-action triggers)
    local autoLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoLabel:SetPoint("TOPLEFT", divManage, "BOTTOMLEFT", 0, -4)
    autoLabel:SetTextColor(0.9, 0.8, 0.3)
    autoLabel:SetText("Automation Overrides")

    -- (#155) Action-mode rows. Each cycles through nil (inherit global)
    -- → "auto" → "manual" → "disabled" → nil. The row labels reflect the
    -- new action-class structure (Tasks / Extras / Reagents for items;
    -- Withdraw / Deposit for gold).
    local todoRow, todoBtn = Create3StateRow(autoLabel, "Tasks:", "todoMode")
    configWidgets.pullRow = todoRow
    configWidgets.pullBtn = todoBtn

    local extrasRow, extrasBtn = Create3StateRow(todoRow, "Extras:", "extrasMode")
    configWidgets.depRow = extrasRow
    configWidgets.depBtn = extrasBtn

    local reagentsRow, reagentsBtn = Create3StateRow(extrasRow, "Reagents:", "reagentsMode")
    configWidgets.depAllRow = reagentsRow
    configWidgets.depAllBtn = reagentsBtn

    local wdGoldRow, wdGoldBtn = Create3StateRow(reagentsRow, "Withdraw Gold:", "goldWithdrawMode")
    configWidgets.wdGoldRow = wdGoldRow
    configWidgets.wdGoldBtn = wdGoldBtn

    local depGoldRow, depGoldBtn = Create3StateRow(wdGoldRow, "Deposit Gold:", "goldDepositMode")
    configWidgets.depGoldRow = depGoldRow
    configWidgets.depGoldBtn = depGoldBtn

    -- Divider
    local div3 = configPanel:CreateTexture(nil, "ARTWORK")
    div3:SetHeight(1)
    div3:SetPoint("TOPLEFT", depGoldRow, "BOTTOMLEFT", 0, -6)
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

    -- Divider before the danger zone. Anchored to the warbank label row
    -- rather than an individual tab button so it survives tab count
    -- changes.
    local div5 = configPanel:CreateTexture(nil, "ARTWORK")
    div5:SetHeight(1)
    div5:SetPoint("TOPLEFT", wbLabel, "BOTTOMLEFT", 0, -(TAB_ICON_SIZE + 18))
    div5:SetPoint("RIGHT", configPanel, "RIGHT", R_MARGIN, 0)
    div5:SetColorTexture(0.35, 0.35, 0.45, 0.6)
    configWidgets.div5 = div5

    local dangerLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dangerLabel:SetPoint("TOPLEFT", div5, "BOTTOMLEFT", 0, -4)
    dangerLabel:SetTextColor(1, 0.4, 0.4)
    dangerLabel:SetText("Danger Zone")
    configWidgets.dangerLabel = dangerLabel

    local deleteBtn = CreateFrame("Button", nil, configPanel, "BackdropTemplate")
    deleteBtn:SetHeight(20)
    deleteBtn:SetPoint("TOPLEFT", dangerLabel, "BOTTOMLEFT", 0, -4)
    deleteBtn:SetPoint("RIGHT", configPanel, "RIGHT", R_MARGIN, 0)
    deleteBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = {left = 1, right = 1, top = 1, bottom = 1},
    })
    deleteBtn:SetBackdropColor(0.3, 0.1, 0.1, 1)
    deleteBtn:SetBackdropBorderColor(0.6, 0.2, 0.2, 0.8)
    deleteBtn.text = deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deleteBtn.text:SetPoint("CENTER")
    deleteBtn.text:SetText("|cffff5555Delete Character|r")
    deleteBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.45, 0.15, 0.15, 1)
    end)
    deleteBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.1, 0.1, 1)
    end)
    configWidgets.deleteBtn = deleteBtn
end

-- ==========================================
-- DELETE CHARACTER DIALOG
-- ==========================================
-- StaticPopupDialogs don't compose well with checkboxes, so we build a
-- small dedicated frame. Reused across deletions — populated fresh each
-- time via ShowDeleteDialog(charKey).
local deleteDialog

local function EnsureDeleteDialog()
    if deleteDialog then return end

    deleteDialog = CreateFrame("Frame", "FlipQueueDeleteCharDialog", UIParent, "BackdropTemplate")
    deleteDialog:SetSize(380, 210)
    deleteDialog:SetPoint("CENTER")
    deleteDialog:SetFrameStrata("DIALOG")
    deleteDialog:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11},
    })
    deleteDialog:EnableMouse(true)
    deleteDialog:Hide()

    local title = deleteDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", deleteDialog, "TOP", 0, -14)
    title:SetText("Delete Character")
    title:SetTextColor(1, 0.4, 0.4)

    local body = deleteDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", deleteDialog, "TOPLEFT", 20, -40)
    body:SetPoint("TOPRIGHT", deleteDialog, "TOPRIGHT", -20, -40)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    body:SetHeight(60)
    deleteDialog.body = body

    local synCB = CreateFrame("CheckButton", nil, deleteDialog, "UICheckButtonTemplate")
    synCB:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -4)
    synCB.text:SetText("Also purge Syndicator data for this character")
    synCB.text:SetFontObject("GameFontHighlightSmall")
    deleteDialog.synCB = synCB

    local synHint = deleteDialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    synHint:SetPoint("TOPLEFT", synCB, "BOTTOMLEFT", 26, -2)
    synHint:SetPoint("RIGHT", deleteDialog, "RIGHT", -20, 0)
    synHint:SetJustifyH("LEFT")
    synHint:SetWordWrap(true)
    synHint:SetText("Leave unchecked if other addons (bag views, inventory UIs) still need this character's data.")

    local deleteBtn = CreateFrame("Button", nil, deleteDialog, "UIPanelButtonTemplate")
    deleteBtn:SetSize(110, 22)
    deleteBtn:SetPoint("BOTTOMRIGHT", deleteDialog, "BOTTOM", -4, 16)
    deleteBtn:SetText("Delete")
    deleteDialog.deleteBtn = deleteBtn

    local cancelBtn = CreateFrame("Button", nil, deleteDialog, "UIPanelButtonTemplate")
    cancelBtn:SetSize(110, 22)
    cancelBtn:SetPoint("BOTTOMLEFT", deleteDialog, "BOTTOM", 4, 16)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() deleteDialog:Hide() end)
end

local function ShowDeleteDialog(charKey, onDeleted)
    EnsureDeleteDialog()
    local name = charKey:match("^(.-)%-") or charKey
    deleteDialog.body:SetText("Delete |cffffffff" .. name ..
        "|r from FlipQueue?\n\n" ..
        "Character key: |cffaaaaaa" .. charKey .. "|r\n\n" ..
        "You can restore the character later from " ..
        "Settings → Deleted Characters.")
    deleteDialog.synCB:SetChecked(false)
    deleteDialog.deleteBtn:SetScript("OnClick", function()
        local purge = deleteDialog.synCB:GetChecked() and true or false
        ns:DeleteCharacter(charKey, { purgeSyndicator = purge })
        ns:Print(ns.COLORS.YELLOW .. "Deleted " .. charKey ..
            (purge and " (Syndicator data purged)" or
                " (Syndicator data kept)") .. ".|r")
        deleteDialog:Hide()
        if onDeleted then onDeleted() end
    end)
    deleteDialog:Show()
end

-- Exposed so SettingsFrame can share the same dialog if ever needed.
UI._ShowDeleteCharDialog = ShowDeleteDialog

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

    -- 3-state buttons (master switches: nil/true/false)
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

    -- (#155) 4-state action-mode button: nil (inherit) / auto / manual / disabled.
    local MODE_CYCLE = { [false] = "auto", auto = "manual", manual = "disabled", disabled = nil }
    local function FormatModeLabel(rawVal, globalMode)
        if rawVal == nil then
            local def = globalMode or "manual"
            return "|cff888888Default (" .. def .. ")|r"
        elseif rawVal == "auto" then
            return "|cff00ff00Auto|r"
        elseif rawVal == "manual" then
            return "|cffffcc00Manual|r"
        elseif rawVal == "disabled" then
            return "|cffff3333Off|r"
        end
        return tostring(rawVal)
    end
    local function CycleMode(current)
        if current == nil then return "auto"
        elseif current == "auto" then return "manual"
        elseif current == "manual" then return "disabled"
        else return nil end
    end
    local function SetupModeBtn(btn, settingKey)
        local raw = ns:GetCharSettingRaw(charKey, settingKey)
        btn.text:SetText(FormatModeLabel(raw, ns.db.settings[settingKey]))

        btn:SetScript("OnClick", function()
            local cur = ns:GetCharSettingRaw(charKey, settingKey)
            ns:SetCharSetting(charKey, settingKey, CycleMode(cur))
            local updated = ns:GetCharSettingRaw(charKey, settingKey)
            btn.text:SetText(FormatModeLabel(updated, ns.db.settings[settingKey]))
            RefreshCharactersTable()
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local cur = ns:GetCharSettingRaw(charKey, settingKey)
            if cur == nil then
                GameTooltip:SetText("Inheriting global: " .. (ns.db.settings[settingKey] or "manual"), 0.7, 0.7, 0.7)
                GameTooltip:AddLine("Click to override to Auto", 0.5, 0.5, 0.5)
            elseif cur == "auto" then
                GameTooltip:SetText("Override: Auto", 0, 1, 0)
                GameTooltip:AddLine("Click to override to Manual", 0.5, 0.5, 0.5)
            elseif cur == "manual" then
                GameTooltip:SetText("Override: Manual", 1, 0.8, 0)
                GameTooltip:AddLine("Click to override to Off", 0.5, 0.5, 0.5)
            else
                GameTooltip:SetText("Override: Off", 1, 0.2, 0.2)
                GameTooltip:AddLine("Click to clear override (use global)", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    SetupTriStateBtn(configWidgets.manageItemsBtn, "manageItems")
    SetupTriStateBtn(configWidgets.manageGoldBtn, "manageGold")
    SetupModeBtn(configWidgets.pullBtn,    "todoMode")
    SetupModeBtn(configWidgets.depBtn,     "extrasMode")
    SetupModeBtn(configWidgets.depAllBtn,  "reagentsMode")
    SetupModeBtn(configWidgets.wdGoldBtn,  "goldWithdrawMode")
    SetupModeBtn(configWidgets.depGoldBtn, "goldDepositMode")

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

    -- Delete button: wires to the character-specific dialog
    if configWidgets.deleteBtn then
        configWidgets.deleteBtn:SetScript("OnClick", function()
            ShowDeleteDialog(charKey, function()
                if configPanel and configPanel:IsShown() then
                    configPanel:Hide()
                end
                UI:Refresh()
            end)
        end)
        configWidgets.deleteBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.45, 0.15, 0.15, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Delete Character", 1, 0.4, 0.4)
            GameTooltip:AddLine("Removes this character from FlipQueue and prevents " ..
                "Syndicator/TSM scans from re-adding it.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Restorable from Settings → Deleted Characters.", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        configWidgets.deleteBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.3, 0.1, 0.1, 1)
            GameTooltip:Hide()
        end)
    end

    configPanel._charKey = charKey
    configPanel:Show()
end

-- ==========================================
-- GLOBAL DEFAULTS BAR
-- ==========================================
-- Houses the global Pull/Deposit/Dep. All checkboxes on the LEFT and the
-- Show Hidden / Show Deleted view toggles on the RIGHT. Both toggle labels'
-- right edges are pinned flush to the bar's right edge so they don't
-- overflow the container.

local globalDefaultsBar
local globalDefaultsWidgets = {}
local viewTogglesWidgets = {}

-- Loading banner shown above the Global Defaults bar while Scanner's
-- bulk-project pass is mid-flight (FQ-137 followup). The pass yields
-- one alt per frame so the relog hitch is gone, but during the drain
-- window the Characters page would otherwise show stale or partial alt
-- inventory data with no indication anything was happening. Banner
-- surfaces "Loading inventory data: X / Y characters" and clears when
-- the pass completes.
local loadingBanner
local loadingBannerLabel
local loadingBannerBar
local loadingBannerBarFill

local function EnsureLoadingBanner(tableContainer)
    if loadingBanner then return end

    loadingBanner = CreateFrame("Frame", nil, tableContainer, "BackdropTemplate")
    loadingBanner:SetHeight(24)
    loadingBanner:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
    loadingBanner:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
    loadingBanner:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    })
    loadingBanner:SetBackdropColor(0.18, 0.14, 0.05, 0.9)  -- amber tint
    loadingBanner:Hide()

    loadingBannerLabel = loadingBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    loadingBannerLabel:SetPoint("LEFT", loadingBanner, "LEFT", 8, 0)
    loadingBannerLabel:SetTextColor(1, 0.85, 0.4)
    loadingBannerLabel:SetText("Loading inventory data...")

    -- Slim progress bar pinned to the right side of the banner.
    loadingBannerBar = CreateFrame("Frame", nil, loadingBanner, "BackdropTemplate")
    loadingBannerBar:SetHeight(8)
    loadingBannerBar:SetWidth(160)
    loadingBannerBar:SetPoint("RIGHT", loadingBanner, "RIGHT", -8, 0)
    loadingBannerBar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    loadingBannerBar:SetBackdropColor(0.05, 0.05, 0.05, 1)
    loadingBannerBar:SetBackdropBorderColor(0.4, 0.3, 0.1, 1)

    loadingBannerBarFill = loadingBannerBar:CreateTexture(nil, "ARTWORK")
    loadingBannerBarFill:SetPoint("TOPLEFT", loadingBannerBar, "TOPLEFT", 1, -1)
    loadingBannerBarFill:SetPoint("BOTTOMLEFT", loadingBannerBar, "BOTTOMLEFT", 1, 1)
    loadingBannerBarFill:SetColorTexture(0.9, 0.7, 0.2, 0.95)
    loadingBannerBarFill:SetWidth(0)
end

-- Update the banner from Scanner's bulk-project status. Returns the
-- height the banner occupies (0 when hidden) so callers can adjust the
-- global-defaults bar's anchor.
local function RefreshLoadingBanner()
    if not loadingBanner then return 0 end
    local status = ns.Scanner and ns.Scanner._bulkProjectStatus
    if not status or not status.active or status.total == 0 then
        loadingBanner:Hide()
        return 0
    end
    loadingBanner:Show()
    local frac = status.done / status.total
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    loadingBannerLabel:SetFormattedText("Loading inventory data: %d / %d characters",
        status.done, status.total)
    local barInner = loadingBannerBar:GetWidth() - 2
    if barInner < 0 then barInner = 0 end
    loadingBannerBarFill:SetWidth(barInner * frac)
    return loadingBanner:GetHeight()
end

-- Lightweight per-alt refresh hook: the bulk-project pass calls this
-- after each alt projection so the banner ticks down without us having
-- to rebuild the whole Characters table. Safe to call when the page
-- isn't current — the EnsureLoadingBanner / RefreshLoadingBanner pair
-- noop until the page has been built once.
function UI:RefreshCharactersLoadingBanner()
    if not loadingBanner then return end
    local bannerH = RefreshLoadingBanner()
    if globalDefaultsBar then
        globalDefaultsBar:ClearAllPoints()
        if bannerH > 0 then
            globalDefaultsBar:SetPoint("TOPLEFT", loadingBanner, "BOTTOMLEFT", 0, -1)
            globalDefaultsBar:SetPoint("TOPRIGHT", loadingBanner, "BOTTOMRIGHT", 0, -1)
        else
            local tableContainer = UI.tableContainer
            if tableContainer then
                globalDefaultsBar:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
                globalDefaultsBar:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
            end
        end
    end
end

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
    -- Renamed from "Global Defaults" to "Character Defaults" so the bar
    -- isn't conflated with the global settings page (#148 maintainer ask).
    lbl:SetText("Character Defaults:")

    -- Helper: create a small checkbox. The optional `bold` flag draws the
    -- label in the gold accent color used for master toggles, so the master
    -- visually outranks its child triggers.
    local function MakeGlobalCB(anchorTo, label, settingKey, tooltipDesc, bold)
        local cb = CreateFrame("CheckButton", nil, globalDefaultsBar, "UICheckButtonTemplate")
        cb:SetSize(18, 18)
        cb:SetPoint("LEFT", anchorTo, "RIGHT", 8, 0)
        cb.text:SetText(label)
        cb.text:SetFontObject(bold and "GameFontNormalSmall" or "GameFontHighlightSmall")
        if bold then cb.text:SetTextColor(0.9, 0.8, 0.3) end

        cb:SetScript("OnClick", function(self)
            if ns.db then
                -- (#155) Mode keys ("xxxMode") store strings auto/manual/disabled.
                -- The defaults-bar checkbox toggles auto ↔ manual; the
                -- third state (disabled) is reachable from the per-char
                -- drilldown only.
                if settingKey:sub(-4) == "Mode" then
                    ns.db.settings[settingKey] = self:GetChecked() and "auto" or "manual"
                else
                    ns.db.settings[settingKey] = self:GetChecked()
                end
                RefreshCharactersTable()
                if UI.RefreshContextDrawer then UI:RefreshContextDrawer() end
                if UI.RefreshSettings then UI:RefreshSettings() end
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

    -- Group backdrops — built up-front so they paint underneath the
    -- checkboxes that anchor to them. Items group uses a soft blue tint;
    -- gold group uses a soft gold tint. Both span from the master checkbox
    -- to the last child trigger's label, with a small inset for visual
    -- breathing room.
    -- Items group: deeper blue with a light blue top border for definition.
    local itemsBg = globalDefaultsBar:CreateTexture(nil, "BACKGROUND")
    itemsBg:SetColorTexture(0.10, 0.20, 0.45, 0.75)
    globalDefaultsWidgets.itemsBg = itemsBg

    local itemsBorder = globalDefaultsBar:CreateTexture(nil, "BORDER")
    itemsBorder:SetColorTexture(0.40, 0.55, 0.85, 0.9)
    itemsBorder:SetHeight(1)
    globalDefaultsWidgets.itemsBorder = itemsBorder

    -- Gold group: deeper gold with a brass top border.
    local goldBg = globalDefaultsBar:CreateTexture(nil, "BACKGROUND")
    goldBg:SetColorTexture(0.45, 0.32, 0.05, 0.85)
    globalDefaultsWidgets.goldBg = goldBg

    local goldBorder = globalDefaultsBar:CreateTexture(nil, "BORDER")
    goldBorder:SetColorTexture(0.95, 0.78, 0.30, 0.9)
    goldBorder:SetHeight(1)
    globalDefaultsWidgets.goldBorder = goldBorder

    -- Vertical separator between the two groups for unmistakable division.
    local groupSep = globalDefaultsBar:CreateTexture(nil, "OVERLAY")
    groupSep:SetColorTexture(0.7, 0.7, 0.75, 0.6)
    groupSep:SetWidth(2)
    globalDefaultsWidgets.groupSep = groupSep

    -- #148: Items master + child triggers
    globalDefaultsWidgets.itemsCB = MakeGlobalCB(lbl, "Items",
        "manageItems",
        "Master switch for item movement. Off: FlipQueue won't pull / deposit items by default. " ..
        "Per-character overrides on the table to the right take precedence.",
        true)

    -- (#155) The defaults-bar checkboxes are now mode shortcuts: checked = "auto",
    -- unchecked = "manual". The third state (disabled) is reachable via the
    -- per-character config drilldown (click a row).
    globalDefaultsWidgets.pullCB = MakeGlobalCB(globalDefaultsWidgets.itemsCB.text, "Tasks",
        "todoMode", "Auto-pull / auto-deposit task items on bank open. Manual: button works, no auto-fire. Click a character row for full Off control.")

    globalDefaultsWidgets.depCB = MakeGlobalCB(globalDefaultsWidgets.pullCB.text, "Extras",
        "extrasMode", "Auto-deposit extra items not needed by current character. Manual: button works, no auto-fire.")

    globalDefaultsWidgets.depAllCB = MakeGlobalCB(globalDefaultsWidgets.depCB.text, "Reagents",
        "reagentsMode", "Auto-deposit reagents (Tradegoods). Manual: button works, no auto-fire.")

    -- Anchor the items backdrop now that all four item-group widgets exist.
    -- Anchors resolve dynamically so the backdrop tracks layout shifts.
    itemsBg:SetPoint("TOPLEFT",     globalDefaultsWidgets.itemsCB,        "TOPLEFT",     -6, 3)
    itemsBg:SetPoint("BOTTOMRIGHT", globalDefaultsWidgets.depAllCB.text,  "BOTTOMRIGHT", 6, -3)
    itemsBorder:SetPoint("TOPLEFT",     itemsBg, "TOPLEFT",  0, 0)
    itemsBorder:SetPoint("TOPRIGHT",    itemsBg, "TOPRIGHT", 0, 0)

    -- "disabled" overlay shown when the master is off (sub-checkboxes hide,
    -- the colored space remains as a visible group affordance).
    local itemsOff = globalDefaultsBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemsOff:SetPoint("LEFT",  globalDefaultsWidgets.pullCB,       "LEFT",  -2, 0)
    itemsOff:SetPoint("RIGHT", globalDefaultsWidgets.depAllCB.text, "RIGHT", 2, 0)
    itemsOff:SetJustifyH("CENTER")
    itemsOff:SetText("(disabled)")
    itemsOff:Hide()
    globalDefaultsWidgets.itemsOff = itemsOff

    -- #148: Gold master + child triggers. Re-anchored with extra spacing so
    -- the items / gold backdrops have a clear gap between them for the
    -- vertical separator.
    globalDefaultsWidgets.goldCB = MakeGlobalCB(globalDefaultsWidgets.depAllCB.text, "Gold",
        "manageGold",
        "Master switch for gold movement. Off: FlipQueue won't withdraw / deposit gold by default.",
        true)
    globalDefaultsWidgets.goldCB:ClearAllPoints()
    globalDefaultsWidgets.goldCB:SetPoint("LEFT", globalDefaultsWidgets.depAllCB.text, "RIGHT", 22, 0)

    globalDefaultsWidgets.wdGoldCB = MakeGlobalCB(globalDefaultsWidgets.goldCB.text, "Withdraw",
        "goldWithdrawMode", "Auto-withdraw gold from warbank for fees + purchases. Manual: button works, no auto-fire.")

    globalDefaultsWidgets.depGoldCB = MakeGlobalCB(globalDefaultsWidgets.wdGoldCB.text, "Deposit",
        "goldDepositMode", "Auto-deposit excess gold back to warbank. Manual: button works, no auto-fire.")

    goldBg:SetPoint("TOPLEFT",     globalDefaultsWidgets.goldCB,           "TOPLEFT",     -6, 3)
    goldBg:SetPoint("BOTTOMRIGHT", globalDefaultsWidgets.depGoldCB.text,   "BOTTOMRIGHT", 6, -3)
    goldBorder:SetPoint("TOPLEFT",     goldBg, "TOPLEFT",  0, 0)
    goldBorder:SetPoint("TOPRIGHT",    goldBg, "TOPRIGHT", 0, 0)

    -- Vertical separator sits in the gap between the two backdrops.
    groupSep:SetPoint("TOP",    itemsBg, "TOPRIGHT",    3, 0)
    groupSep:SetPoint("BOTTOM", itemsBg, "BOTTOMRIGHT", 3, 0)

    local goldOff = globalDefaultsBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    goldOff:SetPoint("LEFT",  globalDefaultsWidgets.wdGoldCB,        "LEFT",  -2, 0)
    goldOff:SetPoint("RIGHT", globalDefaultsWidgets.depGoldCB.text,  "RIGHT", 2, 0)
    goldOff:SetJustifyH("CENTER")
    goldOff:SetText("(disabled)")
    goldOff:Hide()
    globalDefaultsWidgets.goldOff = goldOff

    -- Right-justified view toggles. We pin each checkbox's LABEL to the
    -- bar's right edge (not the checkbox), so the label's right edge —
    -- not the checkbox itself — is what sits flush with the bar. The
    -- checkbox is then anchored to the LEFT of its own label.
    local function MakeRightToggle(rightAnchor, label, settingKey, tooltipDesc)
        local cb = CreateFrame("CheckButton", nil, globalDefaultsBar, "UICheckButtonTemplate")
        cb:SetSize(18, 18)

        cb.text:SetText(label)
        cb.text:SetFontObject("GameFontHighlightSmall")
        cb.text:ClearAllPoints()
        if type(rightAnchor) == "table" and rightAnchor.frame then
            -- Anchor to the LEFT of the previous toggle's CHECKBOX (which
            -- is itself left of its own label), with padding.
            cb.text:SetPoint("RIGHT", rightAnchor.frame, "LEFT", -10, 0)
        else
            cb.text:SetPoint("RIGHT", globalDefaultsBar, "RIGHT", -8, 0)
        end

        cb:ClearAllPoints()
        cb:SetPoint("RIGHT", cb.text, "LEFT", -2, 1)

        cb:SetScript("OnClick", function(self)
            if ns.db then
                ns.db.settings[settingKey] = self:GetChecked() and true or false
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

    viewTogglesWidgets.deletedCB = MakeRightToggle(nil, "Show Deleted",
        "showDeletedChars",
        "Include deleted characters in the list. Click a deleted row to restore.")

    viewTogglesWidgets.hiddenCB = MakeRightToggle({frame = viewTogglesWidgets.deletedCB},
        "Show Hidden", "showHiddenChars",
        "Include hidden characters (role=Hidden) in the list. Click a hidden row to unhide.")
end

local function RefreshGlobalDefaultsBar()
    if not globalDefaultsBar or not ns.db then return end

    -- #148: master switches
    local itemsOn = ns.db.settings.manageItems ~= false
    local goldOn  = ns.db.settings.manageGold  ~= false

    if globalDefaultsWidgets.itemsCB then
        globalDefaultsWidgets.itemsCB:SetChecked(itemsOn)
    end
    if globalDefaultsWidgets.goldCB then
        globalDefaultsWidgets.goldCB:SetChecked(goldOn)
    end

    -- (#155) Sub-checkboxes track whether the action mode is "auto".
    -- "manual" and "disabled" both render as unchecked since this UI
    -- doesn't have a third state — players who want disabled use the
    -- per-char drilldown.
    globalDefaultsWidgets.pullCB:SetChecked(ns.db.settings.todoMode == "auto")
    globalDefaultsWidgets.depCB:SetChecked(ns.db.settings.extrasMode == "auto")
    globalDefaultsWidgets.depAllCB:SetChecked(ns.db.settings.reagentsMode == "auto")
    if globalDefaultsWidgets.wdGoldCB then
        globalDefaultsWidgets.wdGoldCB:SetChecked(ns.db.settings.goldWithdrawMode == "auto")
    end
    if globalDefaultsWidgets.depGoldCB then
        globalDefaultsWidgets.depGoldCB:SetChecked(ns.db.settings.goldDepositMode == "auto")
    end

    if itemsOn then
        globalDefaultsWidgets.pullCB:Show()
        globalDefaultsWidgets.depCB:Show()
        globalDefaultsWidgets.depAllCB:Show()
        if globalDefaultsWidgets.itemsOff then globalDefaultsWidgets.itemsOff:Hide() end
    else
        globalDefaultsWidgets.pullCB:Hide()
        globalDefaultsWidgets.depCB:Hide()
        globalDefaultsWidgets.depAllCB:Hide()
        if globalDefaultsWidgets.itemsOff then globalDefaultsWidgets.itemsOff:Show() end
    end

    if goldOn then
        if globalDefaultsWidgets.wdGoldCB  then globalDefaultsWidgets.wdGoldCB:Show()  end
        if globalDefaultsWidgets.depGoldCB then globalDefaultsWidgets.depGoldCB:Show() end
        if globalDefaultsWidgets.goldOff   then globalDefaultsWidgets.goldOff:Hide()   end
    else
        if globalDefaultsWidgets.wdGoldCB  then globalDefaultsWidgets.wdGoldCB:Hide()  end
        if globalDefaultsWidgets.depGoldCB then globalDefaultsWidgets.depGoldCB:Hide() end
        if globalDefaultsWidgets.goldOff   then globalDefaultsWidgets.goldOff:Show()   end
    end

    if viewTogglesWidgets.hiddenCB then
        viewTogglesWidgets.hiddenCB:SetChecked(ns.db.settings.showHiddenChars and true or false)
    end
    if viewTogglesWidgets.deletedCB then
        viewTogglesWidgets.deletedCB:SetChecked(ns.db.settings.showDeletedChars and true or false)
    end
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
        local deletedCount = 0
        for _ in pairs(ns.db.deletedCharacters or {}) do deletedCount = deletedCount + 1 end
        local parts = { charCount .. " characters" }
        if totalGold > 0 then table.insert(parts, ns:FormatGold(totalGold) .. " total") end
        if hiddenCount > 0 then table.insert(parts, hiddenCount .. " hidden") end
        if deletedCount > 0 then table.insert(parts, deletedCount .. " deleted") end
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

    EnsureLoadingBanner(tableContainer)
    EnsureGlobalDefaultsBar(tableContainer)
    EnsureConfigPanel(tableContainer)

    -- Re-anchor the Global Defaults bar below the loading banner if
    -- the banner is showing, otherwise back to the container top.
    -- Banner sits topmost; defaults bar tucks under it; the chars table
    -- header anchors to the defaults bar (further down in this fn).
    local bannerH = RefreshLoadingBanner()
    globalDefaultsBar:ClearAllPoints()
    if bannerH > 0 then
        globalDefaultsBar:SetPoint("TOPLEFT", loadingBanner, "BOTTOMLEFT", 0, -1)
        globalDefaultsBar:SetPoint("TOPRIGHT", loadingBanner, "BOTTOMRIGHT", 0, -1)
    else
        globalDefaultsBar:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, 0)
        globalDefaultsBar:SetPoint("TOPRIGHT", tableContainer, "TOPRIGHT", 0, 0)
    end

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
            -- Deleted ghost row: restore directly, don't try to open config.
            if rowData._isDeleted then
                ns:RestoreCharacter(rowData._charKey)
                ns:Print(ns.COLORS.GREEN .. "Restored " .. rowData._charKey ..
                    ". It will reappear on the next scan.|r")
                UI:Refresh()
                return
            end
            -- Hidden row (visible because "Show Hidden" is on): unhide
            -- directly. User can re-hide via the config panel's Role cycle.
            if rowData._isHidden then
                ns:SetCharRole(rowData._charKey, "both")
                ns:Print(ns.COLORS.GREEN .. "Unhidden " .. rowData._charKey ..
                    " (role set to Both).|r")
                UI:Refresh()
                return
            end
            -- Normal row: open config panel
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
    local deletedCount = 0
    for _ in pairs(ns.db.deletedCharacters or {}) do deletedCount = deletedCount + 1 end
    local statusParts = {charCount .. " characters"}
    if totalGold > 0 then
        table.insert(statusParts, ns:FormatGold(totalGold) .. " total")
    end
    if hiddenCount > 0 then
        table.insert(statusParts, hiddenCount .. " hidden")
    end
    if deletedCount > 0 then
        table.insert(statusParts, deletedCount .. " deleted")
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
