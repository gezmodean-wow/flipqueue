-- UI/GuildsPage.lua
-- Guild bank management: enable/disable, per-tab config, scan info, remove
local addonName, ns = ...

local UI = ns.UI

local guildTabWidgets = nil  -- lazily created tab config panel

local function BuildGuildsData()
    if not ns.db then return {} end
    local data = {}

    -- Sort guild names
    local guildNames = {}
    if ns.db.guilds then
        for name in pairs(ns.db.guilds) do
            table.insert(guildNames, name)
        end
    end
    table.sort(guildNames)

    for _, guildName in ipairs(guildNames) do
        local guildData = ns.db.guilds[guildName]
        local isEnabled = guildData.enabled ~= false

        local itemCount = 0
        if guildData.items then
            for _ in pairs(guildData.items) do itemCount = itemCount + 1 end
        end

        local memberCount = guildData.members and #guildData.members or 0
        local memberNames = {}
        if guildData.members then
            for _, ck in ipairs(guildData.members) do
                table.insert(memberNames, ck:match("^(.-)%-") or ck)
            end
        end

        local scanStr = guildData.lastScan and ns:FormatRelativeTime(guildData.lastScan) or "never"
        local toggleIcon = isEnabled and "|cff00ff00O|r" or "|cff666666X|r"

        local statusStr
        if not guildData.lastScan then
            statusStr = "|cff888888Not scanned|r"
        elseif isEnabled then
            statusStr = "|cff00ff00Active|r"
        else
            statusStr = "|cff666666Disabled|r"
        end

        local rowColor = nil
        if not isEnabled then
            rowColor = {0.3, 0.3, 0.3, 0.1}
        elseif not guildData.lastScan then
            rowColor = {0.5, 0.5, 0.3, 0.1}
        end

        table.insert(data, {
            toggle   = toggleIcon,
            name     = isEnabled and (ns.COLORS.ORANGE .. guildName .. "|r") or ("|cff666666" .. guildName .. "|r"),
            members  = memberCount > 0 and table.concat(memberNames, ", ") or "-",
            items    = itemCount > 0 and tostring(itemCount) or "-",
            lastScan = scanStr,
            status   = statusStr,
            _guildName = guildName,
            _isEnabled = isEnabled,
            _rowColor = rowColor,
            _sortName = guildName:lower(),
            _sortItems = itemCount,
            _sortLastScan = guildData.lastScan or 0,
            _tooltipText = guildName,
            _tooltipExtra = string.format(
                "%d item(s) in guild bank\n%d member(s): %s\nLast scan: %s\nStatus: %s\n\nClick to %s\nRight-click for tab config\nShift+Right-click to remove",
                itemCount,
                memberCount,
                memberCount > 0 and table.concat(memberNames, ", ") or "none tracked",
                scanStr,
                isEnabled and "Active" or "Disabled",
                isEnabled and "disable" or "enable"),
        })
    end

    return data
end

-- ==========================================
-- TAB CONFIG PANEL (shown below guilds table)
-- ==========================================

local function ShowTabConfig(guildName)
    local tableContainer = UI.tableContainer
    if not ns.db or not ns.db.guilds or not ns.db.guilds[guildName] then return end
    local guildData = ns.db.guilds[guildName]

    -- Create or reuse tab config panel
    if not guildTabWidgets then
        guildTabWidgets = {}
        local panel = CreateFrame("Frame", nil, tableContainer)
        panel:SetHeight(80)
        guildTabWidgets.panel = panel

        panel.bg = panel:CreateTexture(nil, "BACKGROUND")
        panel.bg:SetAllPoints()
        panel.bg:SetColorTexture(0.08, 0.08, 0.12, 0.8)

        panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)

        panel.desc = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        panel.desc:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
        panel.desc:SetText("Select which guild bank tabs to include in scanning and item pool.")

        guildTabWidgets.tabButtons = {}
        local TAB_SIZE = 28
        local TAB_GAP = 6
        for i = 1, 8 do
            local btn = CreateFrame("CheckButton", nil, panel)
            btn:SetSize(TAB_SIZE, TAB_SIZE)
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + (i - 1) * (TAB_SIZE + TAB_GAP), -40)

            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(TAB_SIZE - 2, TAB_SIZE - 2)
            btn.icon:SetPoint("CENTER")
            btn.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_29")

            btn.border = btn:CreateTexture(nil, "OVERLAY")
            btn.border:SetAllPoints()
            btn.border:SetColorTexture(0.3, 0.8, 0.3, 0.4)
            btn.border:Hide()

            btn.uncheckedBorder = btn:CreateTexture(nil, "OVERLAY")
            btn.uncheckedBorder:SetAllPoints()
            btn.uncheckedBorder:SetColorTexture(0.5, 0.1, 0.1, 0.4)
            btn.uncheckedBorder:Hide()

            btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn.label:SetPoint("TOP", btn, "BOTTOM", 0, -1)
            btn.label:SetText("Tab " .. i)
            btn.label:SetTextColor(0.7, 0.7, 0.7)

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Tab " .. i, 1, 1, 1)
                local enabled = not guildData.disabledTabs or not guildData.disabledTabs[i]
                GameTooltip:AddLine(enabled and "Enabled — click to disable" or "Disabled — click to enable", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            guildTabWidgets.tabButtons[i] = btn
        end
    end

    local panel = guildTabWidgets.panel
    panel:ClearAllPoints()

    -- Position below the guilds table
    local guildsHeight = math.max(60, (#(UI.guildsTable._data or {}) + 1) * 20 + 22)
    if guildsHeight > 250 then guildsHeight = 250 end
    panel:SetPoint("TOPLEFT", tableContainer, "TOPLEFT", 0, -guildsHeight - 10)
    panel:SetPoint("RIGHT", tableContainer, "RIGHT", 0, 0)

    panel.title:SetText(ns.COLORS.ORANGE .. guildName .. "|r" .. " — Tab Configuration")
    guildTabWidgets._currentGuild = guildName

    -- Update tab button states
    for i = 1, 8 do
        local btn = guildTabWidgets.tabButtons[i]
        local enabled = not guildData.disabledTabs or not guildData.disabledTabs[i]

        btn:SetScript("OnClick", function()
            if not guildData.disabledTabs then guildData.disabledTabs = {} end
            guildData.disabledTabs[i] = enabled or nil  -- toggle: set true to disable, nil to enable
            ShowTabConfig(guildName)  -- refresh
        end)

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
    end

    panel:Show()
end

local function HideTabConfig()
    if guildTabWidgets and guildTabWidgets.panel then
        guildTabWidgets.panel:Hide()
    end
end

-- ==========================================
-- GUILDS PAGE REFRESH
-- ==========================================

function UI:RefreshGuildsPage()
    local mainFrame = UI.mainFrame
    local tableContainer = UI.tableContainer
    mainFrame.pageTitle:SetText("Guild Banks")
    UI._HideAllActionBtns()
    HideTabConfig()

    local data = BuildGuildsData()

    UI._ShowTable(self.guildsTable)
    self.guildsTable._data = data  -- store for tab config positioning

    self.guildsTable:SetRowClickHandler(function(rowData, button)
        if not rowData._guildName then return end
        local guildData = ns.db.guilds[rowData._guildName]
        if not guildData then return end

        if button == "LeftButton" then
            -- Toggle enable/disable
            guildData.enabled = not (guildData.enabled ~= false)
            if guildData.enabled then
                ns:Print("Enabled guild bank: " .. rowData._guildName)
            else
                ns:Print("Disabled guild bank: " .. rowData._guildName .. " (excluded from item pool)")
            end
            self:Refresh()
        elseif button == "RightButton" then
            if IsShiftKeyDown() then
                -- Remove guild
                StaticPopupDialogs["FLIPQUEUE_REMOVE_GUILD"] = {
                    text = "Remove guild bank data for |cffff8800" .. rowData._guildName .. "|r?\n\nThis will delete all stored items. You can re-scan by opening the guild bank.",
                    button1 = "Remove",
                    button2 = "Cancel",
                    OnAccept = function()
                        ns.db.guilds[rowData._guildName] = nil
                        ns:Print(ns.COLORS.ORANGE .. "Removed guild bank:|r " .. rowData._guildName)
                        HideTabConfig()
                        self:Refresh()
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    preferredIndex = 3,
                }
                StaticPopup_Show("FLIPQUEUE_REMOVE_GUILD")
            else
                -- Show/toggle tab config
                if guildTabWidgets and guildTabWidgets._currentGuild == rowData._guildName
                    and guildTabWidgets.panel:IsShown() then
                    HideTabConfig()
                else
                    ShowTabConfig(rowData._guildName)
                end
            end
        end
    end)

    self.guildsTable:SetData(data)

    -- Status bar
    local guildCount = 0
    local enabledCount = 0
    local totalItems = 0
    if ns.db.guilds then
        for _, gd in pairs(ns.db.guilds) do
            guildCount = guildCount + 1
            if gd.enabled ~= false then enabledCount = enabledCount + 1 end
            if gd.items then
                for _ in pairs(gd.items) do totalItems = totalItems + 1 end
            end
        end
    end

    local statusParts = {guildCount .. " guild(s)"}
    if enabledCount < guildCount then
        table.insert(statusParts, enabledCount .. " enabled")
    end
    table.insert(statusParts, totalItems .. " items")
    table.insert(statusParts, ns.COLORS.GRAY .. "Click: enable/disable  |  Right-click: tab config  |  Shift+Right: remove" .. "|r")
    mainFrame.statusText:SetText(table.concat(statusParts, "  |  "))
end
