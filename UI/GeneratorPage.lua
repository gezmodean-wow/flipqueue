-- UI/GeneratorPage.lua
-- To-Do Generator page: two-column list builder with filter/priority controls
local addonName, ns = ...

local UI = ns.UI

-- Generator state
-- allocationOrder and sortMode are saved to DB; the rest is session-only
UI._generatorPreview = UI._generatorPreview or nil
UI._genListCollapsed = UI._genListCollapsed or {}
-- Filter mode/value: read from DB settings (persisted across sessions)
-- Initialized to DB values when available, fallback to defaults
UI._genFilterMode = UI._genFilterMode or "all"
UI._genFilterValue = UI._genFilterValue or ""

-- Sync filter state from DB settings (called after InitDB)
function UI:InitGenFilterFromDB()
    if ns.db and ns.db.settings then
        UI._genFilterMode = ns.db.settings.genFilterMode or "all"
        UI._genFilterValue = ns.db.settings.genFilterValue or ""
    end
end

-- Save filter state to DB settings
local function SaveGenFilter(mode, value)
    UI._genFilterMode = mode
    UI._genFilterValue = value or ""
    if ns.db and ns.db.settings then
        ns.db.settings.genFilterMode = mode
        ns.db.settings.genFilterValue = value or ""
    end
end

-- Auto-generate: build preview from current filter settings
local function AutoGenerate()
    if not ns.TodoList then return end
    local allocationOrder = UI:GetGenAllocationOrder()
    UI._generatorPreview = ns.TodoList:GenerateTodoList("fpScanner", allocationOrder)
    -- Don't print on auto-generate to avoid spam
end
UI._genExcludedItems = UI._genExcludedItems or {}

-- Accessors that read/write DB settings (with fallback defaults for before InitDB runs)
function UI:GetGenAllocationOrder()
    if ns.db and ns.db.settings.genAllocationOrder then
        return ns.db.settings.genAllocationOrder
    end
    return {"gold", "noCompetition", "population"}
end

function UI:GetGenSortMode()
    if ns.db and ns.db.settings.genSortMode then
        return ns.db.settings.genSortMode
    end
    return "profit"
end

function UI:SetGenSortMode(mode)
    if ns.db then
        ns.db.settings.genSortMode = mode
    end
end

-- ==========================================
-- GENERATOR PREVIEW DATA
-- ==========================================

local function BuildGeneratorPreviewData(todoList)
    if not todoList or not todoList.items then return {} end
    local data = {}

    local LookupItemInfo = UI._LookupItemInfo
    local QualityColorName = UI._QualityColorName
    local CLASS_COLORS = UI._CLASS_COLORS

    for _, item in ipairs(todoList.items) do
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

        local isBuyTask = item.action == "buy"

        local statusStr, sortStatus
        if isBuyTask and item.status == "pending" then
            statusStr = ns.COLORS.CYAN .. "Buy" .. "|r"
            sortStatus = 1
        elseif item.status == "pending" then
            statusStr = ns.COLORS.GREEN .. "Ready" .. "|r"
            sortStatus = 1
        elseif item.status == "unassigned" then
            statusStr = ns.COLORS.ORANGE .. "No char" .. "|r"
            sortStatus = 2
        elseif item.status == "missing" then
            statusStr = ns.COLORS.RED .. "Missing" .. "|r"
            sortStatus = 3
        elseif item.status == "posted" then
            statusStr = ns.COLORS.GRAY .. "Posted" .. "|r"
            sortStatus = 4
        elseif item.status == "skipped" then
            statusStr = ns.COLORS.ORANGE .. "Skipped" .. "|r"
            sortStatus = 5
        else
            statusStr = item.status or "?"
            sortStatus = 6
        end

        local charDisplay = ""
        if item.assignedChar then
            local name = item.assignedChar:match("^(.-)%-") or item.assignedChar
            local charData = ns.db.characters and ns.db.characters[item.assignedChar]
            local classColor = charData and (UI._CLASS_COLORS or {})[charData.class] or "888888"
            charDisplay = "|cff" .. classColor .. name .. "|r"
        end

        local sourceStr = item.source or ""
        if isBuyTask then
            sourceStr = ns.COLORS.CYAN .. "buy@" .. (item.buyRealm or "?") .. "|r"
        elseif sourceStr == "warbank" then
            sourceStr = ns.COLORS.YELLOW .. "warbank" .. "|r"
        elseif sourceStr == "bags" then
            sourceStr = ns.COLORS.GREEN .. "bags" .. "|r"
        elseif sourceStr == "bank" then
            sourceStr = ns.COLORS.BLUE .. "bank" .. "|r"
        elseif sourceStr == "guildbank" then
            sourceStr = ns.COLORS.ORANGE .. "guild" .. "|r"
        elseif sourceStr == "unavailable" and item.depositFrom then
            local depName = item.depositFrom:match("^(.-)%-") or item.depositFrom
            sourceStr = ns.COLORS.CYAN .. "via " .. depName .. "|r"
        elseif sourceStr == "unavailable" then
            sourceStr = ns.COLORS.RED .. "unavail" .. "|r"
        end

        -- Display price: buy tasks show buy price, sell tasks show expected price
        local priceDisplay = isBuyTask and item.buyPrice or item.expectedPrice or ""
        -- Realm display: buy tasks show buyRealm as primary context
        local realmDisplay = item.targetRealm or ""
        if isBuyTask and item.buyRealm then
            realmDisplay = ns.COLORS.CYAN .. item.buyRealm .. "|r"
        end

        local rowColor = nil
        if item.status == "missing" then
            rowColor = {0.8, 0.2, 0.2, 0.08}
        elseif item.status == "unassigned" then
            rowColor = {0.8, 0.5, 0.1, 0.08}
        elseif isBuyTask then
            rowColor = {0.1, 0.4, 0.6, 0.08}
        end

        -- Build tooltip
        local tooltipExtra = ""
        if isBuyTask then
            tooltipExtra = "Buy on: " .. (item.buyRealm or "?")
                .. "\nBuy price: " .. (item.buyPrice or "?")
                .. "\nSell on: " .. (item.targetRealm or "?")
                .. "\nSell price: " .. (item.expectedPrice or "?")
                .. (item.profitAmount and ("\nProfit: " .. item.profitAmount) or "")
                .. (item.profitPct and (" (" .. item.profitPct .. "%)") or "")
        else
            tooltipExtra = (item.targetRealm and item.targetRealm ~= ""
                    and ("Realm: " .. item.targetRealm) or "")
                .. (item.assignedChar and ("\nCharacter: " .. item.assignedChar) or "")
                .. (item.source and ("\nSource: " .. item.source) or "")
                .. (item.expectedPrice and ("\nPrice: " .. item.expectedPrice) or "")
                .. (item.buyRealm and item.buyRealm ~= ""
                    and ("\nCross-realm: buy on " .. item.buyRealm .. " @ " .. (item.buyPrice or "?")) or "")
        end
        if item.failReason then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.RED .. item.failReason .. "|r"
        end

        table.insert(data, {
            name      = displayName,
            qty       = item.quantity or 1,
            realm     = realmDisplay,
            character = charDisplay,
            source    = sourceStr,
            price     = priceDisplay,
            status    = statusStr,
            _icon     = item.icon or lookupIcon,
            _sortStatus = sortStatus,
            _rowColor = rowColor,
            _tooltipItemID = resolvedID or tonumber(item.itemID),
            _tooltipText = item.name or "?",
            _tooltipExtra = tooltipExtra,
        })
    end

    return data
end

-- ==========================================
-- REUSABLE WIDGET: toggle button
-- ==========================================

local function CreateToggleBtn(parent, label)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(18)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetWidth(btn.text:GetStringWidth() + 14)
    btn:SetScript("OnEnter", function(self)
        if not self._active then self:SetBackdropColor(0.2, 0.2, 0.3, 1) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self._active then
            self:SetBackdropColor(0.2, 0.4, 0.2, 1)
        else
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        end
    end)
    return btn
end

local function SetToggleActive(btn, active)
    btn._active = active
    if active then
        btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
    else
        btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    end
end

-- ==========================================
-- REUSABLE WIDGET: small action button
-- ==========================================

local function CreateSmallActionBtn(parent, label, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 16)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.5, 0.5, 0.5)
        GameTooltip:Hide()
    end)
    return btn
end

-- ==========================================
-- GENERATOR PAGE REFRESH
-- ==========================================

function UI:RefreshGeneratorPage(pending)
    local mainFrame = self.mainFrame
    local tableContainer = self.tableContainer
    local LayoutActionBtns = self._LayoutActionBtns
    local ShowTable = self._ShowTable
    local CLASS_COLORS = self._CLASS_COLORS or {}
    local FormatGoldValue = self._FormatGoldValue

    mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "To-Do Generator" .. "|r")

    -- No action bar buttons — Generate/Save/Export/Import are in the column headers
    local HideAllActionBtns = self._HideAllActionBtns
    HideAllActionBtns()

    local currentList = ns.TodoList and ns.TodoList:GetCurrentList()

    -- ========================================
    -- CREATE PERSISTENT FRAME (once)
    -- ========================================
    if not self._genFrame then
        local gf = CreateFrame("Frame", nil, tableContainer)
        gf:SetAllPoints()

        -- ---- TOP SECTION: list queue ----
        gf.topSection = CreateFrame("Frame", nil, gf)
        gf.topSection:SetPoint("TOPLEFT", gf, "TOPLEFT", 0, 0)
        gf.topSection:SetPoint("TOPRIGHT", gf, "TOPRIGHT", 0, 0)
        gf.topSection:SetHeight(20)

        gf.topSection.bg = gf.topSection:CreateTexture(nil, "BACKGROUND")
        gf.topSection.bg:SetAllPoints()
        gf.topSection.bg:SetColorTexture(0.08, 0.08, 0.12, 0.8)

        gf.topRows = {}
        gf.topActionBtns = {}

        -- ---- DIVIDER between top and columns ----
        gf.midDivider = gf:CreateTexture(nil, "ARTWORK")
        gf.midDivider:SetHeight(1)
        gf.midDivider:SetColorTexture(0.3, 0.3, 0.4, 0.6)

        -- ---- LEFT COLUMN: "What to Sell" ----
        gf.leftCol = CreateFrame("Frame", nil, gf)

        gf.leftCol.headerBg = gf.leftCol:CreateTexture(nil, "BACKGROUND")
        gf.leftCol.headerBg:SetHeight(18)
        gf.leftCol.headerBg:SetPoint("TOPLEFT", gf.leftCol, "TOPLEFT", 0, 0)
        gf.leftCol.headerBg:SetPoint("TOPRIGHT", gf.leftCol, "TOPRIGHT", 0, 0)
        gf.leftCol.headerBg:SetColorTexture(0.12, 0.12, 0.18, 1)

        gf.leftCol.headerText = gf.leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gf.leftCol.headerText:SetPoint("LEFT", gf.leftCol.headerBg, "LEFT", 6, 0)
        gf.leftCol.headerText:SetText("WHAT TO SELL")
        gf.leftCol.headerText:SetTextColor(0.7, 0.7, 0.7)

        -- Styled header button (matches action bar button style)
        local function CreateHeaderBtn(parent, label, tooltip, onClick)
            local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:SetHeight(18)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 10,
                insets = {left = 2, right = 2, top = 2, bottom = 2},
            })
            btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn.text:SetPoint("CENTER")
            btn.text:SetText(label)
            btn:SetWidth(btn.text:GetStringWidth() + 16)
            btn:SetScript("OnClick", onClick)
            btn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.2, 0.2, 0.3, 1)
                if tooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                    GameTooltip:SetText(tooltip, 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.15, 0.15, 0.2, 1)
                GameTooltip:Hide()
            end)
            return btn
        end

        -- Filter label + description
        gf.leftCol.filterDesc = gf.leftCol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gf.leftCol.filterDesc:SetPoint("TOPLEFT", gf.leftCol.headerBg, "BOTTOMLEFT", 6, -4)
        gf.leftCol.filterDesc:SetPoint("RIGHT", gf.leftCol, "RIGHT", -6, 0)
        gf.leftCol.filterDesc:SetJustifyH("LEFT")
        gf.leftCol.filterDesc:SetWordWrap(true)
        gf.leftCol.filterDesc:SetTextColor(0.45, 0.45, 0.45)
        gf.leftCol.filterDesc:SetText("Narrow which inventory items to consider for your to-do list.")

        gf.leftCol.filterLabel = gf.leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gf.leftCol.filterLabel:SetPoint("TOPLEFT", gf.leftCol.filterDesc, "BOTTOMLEFT", 0, -4)
        gf.leftCol.filterLabel:SetText("Only show items in:")
        gf.leftCol.filterLabel:SetTextColor(0.7, 0.7, 0.7)

        gf.leftCol.filterAll = CreateToggleBtn(gf.leftCol, "All")
        gf.leftCol.filterAll:SetPoint("LEFT", gf.leftCol.filterLabel, "RIGHT", 4, 0)
        gf.leftCol.filterAll:SetScript("OnClick", function()
            SaveGenFilter("all", "")
            AutoGenerate()
            UI:Refresh()
        end)

        gf.leftCol.filterTSM = CreateToggleBtn(gf.leftCol, "TSM Group")
        gf.leftCol.filterTSM:SetPoint("LEFT", gf.leftCol.filterAll, "RIGHT", 2, 0)
        gf.leftCol.filterTSM:SetScript("OnClick", function()
            SaveGenFilter("tsm", UI._genFilterValue)
            AutoGenerate()
            UI:Refresh()
        end)

        gf.leftCol.filterAuct = CreateToggleBtn(gf.leftCol, "Auctionator List")
        gf.leftCol.filterAuct:SetPoint("LEFT", gf.leftCol.filterTSM, "RIGHT", 2, 0)
        gf.leftCol.filterAuct:SetScript("OnClick", function()
            SaveGenFilter("auctionator", UI._genFilterValue)
            AutoGenerate()
            UI:Refresh()
        end)

        -- TSM Group Tree container (shown when TSM filter active)
        gf.leftCol.treeFrame = CreateFrame("Frame", nil, gf.leftCol)
        gf.leftCol.treeFrame:SetHeight(100)
        gf.leftCol.treeFrame:Hide()

        -- TSM profile label (shown above group tree)
        gf.leftCol.tsmProfileLabel = gf.leftCol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gf.leftCol.tsmProfileLabel:SetTextColor(0.5, 0.5, 0.5)
        gf.leftCol.tsmProfileLabel:Hide()

        -- TSM selected group label (shown below tree)
        gf.leftCol.tsmSelectedLabel = gf.leftCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gf.leftCol.tsmSelectedLabel:SetTextColor(0.9, 0.8, 0.3)
        gf.leftCol.tsmSelectedLabel:Hide()

        -- TSM "clear selection" button
        gf.leftCol.tsmClearBtn = CreateFrame("Button", nil, gf.leftCol)
        gf.leftCol.tsmClearBtn:SetSize(60, 16)
        gf.leftCol.tsmClearBtn.text = gf.leftCol.tsmClearBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gf.leftCol.tsmClearBtn.text:SetPoint("CENTER")
        gf.leftCol.tsmClearBtn.text:SetText("[show all]")
        gf.leftCol.tsmClearBtn:SetScript("OnClick", function()
            SaveGenFilter("tsm", "")
            if gf.leftCol.groupTree then
                gf.leftCol.groupTree._selectedPath = nil
            end
            AutoGenerate()
            UI:Refresh()
        end)
        gf.leftCol.tsmClearBtn:SetScript("OnEnter", function(self)
            self.text:SetTextColor(1, 1, 1)
        end)
        gf.leftCol.tsmClearBtn:SetScript("OnLeave", function(self)
            self.text:SetTextColor(0.5, 0.5, 0.5)
        end)
        gf.leftCol.tsmClearBtn:Hide()

        -- TSM unavailable message
        gf.leftCol.tsmUnavail = gf.leftCol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gf.leftCol.tsmUnavail:SetTextColor(0.8, 0.4, 0.4)
        gf.leftCol.tsmUnavail:SetText("TSM is not enabled. Enable it on the TSM page.")
        gf.leftCol.tsmUnavail:Hide()

        -- Auctionator list selector (shown when Auctionator filter active)
        gf.leftCol.auctFrame = CreateFrame("Frame", nil, gf.leftCol)
        gf.leftCol.auctFrame:SetHeight(80)
        gf.leftCol.auctFrame:Hide()

        gf.leftCol.auctLabel = gf.leftCol.auctFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gf.leftCol.auctLabel:SetPoint("TOPLEFT", gf.leftCol.auctFrame, "TOPLEFT", 6, 0)
        gf.leftCol.auctLabel:SetText("Shopping List:")
        gf.leftCol.auctLabel:SetTextColor(0.5, 0.5, 0.5)

        -- Auctionator list scroll with clickable names
        gf.leftCol.auctScroll = CreateFrame("ScrollFrame", nil, gf.leftCol.auctFrame, "UIPanelScrollFrameTemplate")
        gf.leftCol.auctScroll:SetPoint("TOPLEFT", gf.leftCol.auctLabel, "BOTTOMLEFT", 0, -4)
        gf.leftCol.auctScroll:SetPoint("BOTTOMRIGHT", gf.leftCol.auctFrame, "BOTTOMRIGHT", -16, 0)

        gf.leftCol.auctContent = CreateFrame("Frame", nil, gf.leftCol.auctScroll)
        gf.leftCol.auctContent:SetWidth(1)
        gf.leftCol.auctContent:SetHeight(1)
        gf.leftCol.auctScroll:SetScrollChild(gf.leftCol.auctContent)
        gf.leftCol.auctScroll:SetScript("OnSizeChanged", function(sf, w)
            gf.leftCol.auctContent:SetWidth(w)
        end)
        gf.leftCol.auctRows = {}

        -- Auctionator unavailable message
        gf.leftCol.auctUnavail = gf.leftCol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gf.leftCol.auctUnavail:SetTextColor(0.8, 0.4, 0.4)
        gf.leftCol.auctUnavail:SetWordWrap(true)
        gf.leftCol.auctUnavail:Hide()

        -- Item pool scroll area
        gf.leftCol.poolScroll = CreateFrame("ScrollFrame", nil, gf.leftCol, "UIPanelScrollFrameTemplate")
        gf.leftCol.poolContent = CreateFrame("Frame", nil, gf.leftCol.poolScroll)
        gf.leftCol.poolScroll:SetScrollChild(gf.leftCol.poolContent)
        gf.leftCol.poolScroll:SetScript("OnSizeChanged", function(sf, w)
            gf.leftCol.poolContent:SetWidth(w)
        end)
        gf.leftCol.poolRows = {}

        -- Divider between filter controls and item pool
        gf.leftCol.poolDivider = gf.leftCol:CreateTexture(nil, "ARTWORK")
        gf.leftCol.poolDivider:SetHeight(1)
        gf.leftCol.poolDivider:SetColorTexture(0.3, 0.3, 0.4, 0.5)

        -- Item count label
        gf.leftCol.countLabel = gf.leftCol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

        -- ---- COLUMN DIVIDER ----
        gf.colDivider = gf:CreateTexture(nil, "ARTWORK")
        gf.colDivider:SetWidth(1)
        gf.colDivider:SetColorTexture(0.3, 0.3, 0.4, 0.6)

        -- ---- RIGHT COLUMN: "To-Do List" ----
        gf.rightCol = CreateFrame("Frame", nil, gf)

        gf.rightCol.headerBg = gf.rightCol:CreateTexture(nil, "BACKGROUND")
        gf.rightCol.headerBg:SetHeight(18)
        gf.rightCol.headerBg:SetPoint("TOPLEFT", gf.rightCol, "TOPLEFT", 0, 0)
        gf.rightCol.headerBg:SetPoint("TOPRIGHT", gf.rightCol, "TOPRIGHT", 0, 0)
        gf.rightCol.headerBg:SetColorTexture(0.12, 0.12, 0.18, 1)

        gf.rightCol.headerText = gf.rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gf.rightCol.headerText:SetPoint("LEFT", gf.rightCol.headerBg, "LEFT", 6, 0)
        gf.rightCol.headerText:SetText("TO-DO LIST")
        gf.rightCol.headerText:SetTextColor(0.7, 0.7, 0.7)

        -- Right header: Save + Generate
        gf.rightCol.saveBtn = CreateHeaderBtn(gf.rightCol, "Save",
            "Commit the current preview as your active to-do list",
            function()
                local btn = UI.mainFrame and UI.mainFrame.actionBtns and UI.mainFrame.actionBtns.commitSave
                if btn then btn:GetScript("OnClick")() end
            end)
        gf.rightCol.saveBtn:SetPoint("RIGHT", gf.rightCol.headerBg, "RIGHT", -4, 0)

        gf.rightCol.generateBtn = CreateHeaderBtn(gf.rightCol, "Generate",
            "Match deals against inventory (preview — click Save to commit)",
            function()
                local btn = UI.mainFrame and UI.mainFrame.actionBtns and UI.mainFrame.actionBtns.generate
                if btn then btn:GetScript("OnClick")() end
            end)
        gf.rightCol.generateBtn:SetPoint("RIGHT", gf.rightCol.saveBtn, "LEFT", -4, 0)

        -- Import FP Data button (opens import popup)
        gf.rightCol.importBtn = CreateHeaderBtn(gf.rightCol, "Import FP Data",
            "Open import popup to paste FlippingPal data",
            function()
                if UI.ShowImportPopup then
                    UI:ShowImportPopup(function(added)
                        -- After import, auto-generate and refresh
                        AutoGenerate()
                        UI:Refresh()
                        if UI.RefreshMini then UI:RefreshMini() end
                    end)
                end
            end)
        gf.rightCol.importBtn:SetPoint("RIGHT", gf.rightCol.generateBtn, "LEFT", -4, 0)

        -- Priority section: label + description
        gf.rightCol.allocDesc = gf.rightCol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gf.rightCol.allocDesc:SetTextColor(0.45, 0.45, 0.45)
        gf.rightCol.allocDesc:SetJustifyH("LEFT")
        gf.rightCol.allocDesc:SetWordWrap(true)
        gf.rightCol.allocDesc:SetText("When two deals need the same item, which deal wins?")

        gf.rightCol.allocLabel = gf.rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gf.rightCol.allocLabel:SetText("Priority:")
        gf.rightCol.allocLabel:SetTextColor(0.9, 0.8, 0.3)

        -- Row pool for allocation ordered list
        gf.rightCol.allocRows = {}

        -- Sort section: label + description
        gf.rightCol.sortDesc = gf.rightCol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        gf.rightCol.sortDesc:SetTextColor(0.45, 0.45, 0.45)
        gf.rightCol.sortDesc:SetJustifyH("LEFT")
        gf.rightCol.sortDesc:SetWordWrap(true)
        gf.rightCol.sortDesc:SetText("Which character do you log into first?")

        gf.rightCol.sortLabel = gf.rightCol:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gf.rightCol.sortLabel:SetText("Order list by:")
        gf.rightCol.sortLabel:SetTextColor(0.9, 0.8, 0.3)

        local SORT_MODES = {
            {key = "profit",        label = "Most Profitable"},
            {key = "character",     label = "Character"},
            {key = "realm",         label = "Realm"},
            {key = "noCompetition", label = "No Competition First"},
        }
        gf.rightCol.sortBtns = {}
        for _, mode in ipairs(SORT_MODES) do
            local btn = CreateToggleBtn(gf.rightCol, mode.label)
            btn._key = mode.key
            btn:SetScript("OnClick", function()
                UI:SetGenSortMode(mode.key)
                UI:Refresh()
            end)
            gf.rightCol.sortBtns[mode.key] = btn
        end

        -- Generated items scroll area
        -- Divider between controls and generated list
        gf.rightCol.listDivider = gf.rightCol:CreateTexture(nil, "ARTWORK")
        gf.rightCol.listDivider:SetHeight(1)
        gf.rightCol.listDivider:SetColorTexture(0.3, 0.3, 0.4, 0.5)

        gf.rightCol.genScroll = CreateFrame("ScrollFrame", nil, gf.rightCol, "UIPanelScrollFrameTemplate")
        gf.rightCol.genContent = CreateFrame("Frame", nil, gf.rightCol.genScroll)
        gf.rightCol.genScroll:SetScrollChild(gf.rightCol.genContent)
        gf.rightCol.genScroll:SetScript("OnSizeChanged", function(sf, w)
            gf.rightCol.genContent:SetWidth(w)
        end)
        gf.rightCol.genRows = {}

        -- Status label at bottom of right column
        gf.rightCol.statusLabel = gf.rightCol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

        -- Inline rename editbox (reusable)
        gf.renameBox = CreateFrame("EditBox", nil, gf, "InputBoxTemplate")
        gf.renameBox:SetSize(150, 18)
        gf.renameBox:SetAutoFocus(false)
        gf.renameBox:SetMaxLetters(60)
        gf.renameBox:Hide()
        gf.renameBox:SetScript("OnEscapePressed", function(self) self:Hide() end)

        -- TSM Group Tree (if available)
        if UI.CreateGroupTree then
            gf.leftCol.groupTree = UI:CreateGroupTree(gf.leftCol.treeFrame, function(path)
                SaveGenFilter("tsm", path or "")
                AutoGenerate()
                UI:Refresh()
            end)
        end

        self._genFrame = gf
    end

    local gf = self._genFrame
    gf:Show()

    -- Initialize filter from DB on first refresh
    if not gf._filterInitialized then
        self:InitGenFilterFromDB()
        gf._filterInitialized = true
    end

    -- ========================================
    -- TOP SECTION: To-Do List Queue
    -- ========================================

    -- Hide all previous top rows
    for _, row in ipairs(gf.topRows) do row:Hide() end
    for _, btn in ipairs(gf.topActionBtns) do btn:Hide() end

    local ROW_H = 20
    local topY = 0
    local topRowIdx = 0
    local topBtnIdx = 0

    local function TopRow()
        topRowIdx = topRowIdx + 1
        local r = gf.topRows[topRowIdx]
        if not r then
            r = CreateFrame("Button", nil, gf.topSection)
            r.bg = r:CreateTexture(nil, "BACKGROUND")
            r.bg:SetAllPoints()
            r.toggle = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.toggle:SetPoint("LEFT", r, "LEFT", 6, 0)
            r.toggle:SetWidth(12)
            r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.label:SetPoint("LEFT", r.toggle, "RIGHT", 2, 0)
            r.label:SetJustifyH("LEFT")
            r:EnableMouse(true)
            gf.topRows[topRowIdx] = r
        end
        r:SetHeight(ROW_H)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", gf.topSection, "TOPLEFT", 0, topY)
        r:SetPoint("RIGHT", gf.topSection, "RIGHT", 0, 0)
        r:SetScript("OnClick", nil)
        r:SetScript("OnEnter", nil)
        r:SetScript("OnLeave", nil)
        r.bg:SetColorTexture(0, 0, 0, 0)
        r.toggle:SetText("")
        r.toggle:Show()
        r.label:SetText("")
        r.label:ClearAllPoints()
        r.label:SetPoint("LEFT", r.toggle, "RIGHT", 2, 0)
        r.label:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.label:Show()
        r:Show()
        topY = topY - ROW_H
        return r
    end

    local function TopSmallBtn(parent, label, tooltip, onClick)
        topBtnIdx = topBtnIdx + 1
        local btn = gf.topActionBtns[topBtnIdx]
        if not btn then
            btn = CreateSmallActionBtn(gf.topSection, label, tooltip, onClick)
            gf.topActionBtns[topBtnIdx] = btn
        end
        btn.text:SetText(label)
        btn.text:SetTextColor(0.5, 0.5, 0.5)
        btn._tooltip = tooltip
        btn:SetScript("OnClick", onClick)
        btn:SetScript("OnEnter", function(self)
            self.text:SetTextColor(1, 1, 1)
            if self._tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self._tooltip, 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end
        end)
        btn:SetParent(parent)
        btn:Show()
        return btn
    end

    -- Data freshness row
    local genCharKey = ns:GetCharKey()
    local genCharData = ns.db.characters and ns.db.characters[genCharKey]
    local genCharInv = genCharData and genCharData.inventory
    local bagAge = genCharInv and genCharInv.lastScan
        and ns:FormatRelativeTime(genCharInv.lastScan) or "never"
    local wbAge = ns.db.warbank and ns.db.warbank.lastScan
        and ns:FormatRelativeTime(ns.db.warbank.lastScan) or "never"

    local freshRow = TopRow()
    freshRow.label:SetText(
        ns.COLORS.GRAY .. "Bags:|r " .. bagAge ..
        ns.COLORS.GRAY .. "   Warbank:|r " .. wbAge ..
        ns.COLORS.GRAY .. "   Deals:|r " .. pending)

    -- Current list
    if currentList then
        local counts = ns.TodoList:GetStatusCounts()
        -- Default to collapsed (nil = collapsed, false = expanded, true = collapsed)
        local isCollapsed = UI._genListCollapsed["current"] ~= false

        local hdr = TopRow()
        hdr.bg:SetColorTexture(0.1, 0.14, 0.1, 0.6)
        hdr.toggle:SetText(isCollapsed and "|cffffffff\226\150\182|r" or "|cffffffff\226\150\188|r")
        hdr.label:SetPoint("RIGHT", hdr, "RIGHT", -72, 0)
        local importTypeTag = currentList.importType
            and ("  " .. ns.COLORS.GRAY .. "[" .. currentList.importType .. "]|r") or ""
        hdr.label:SetText(
            ns.COLORS.GREEN .. "Active:|r " .. (currentList.name or "Unnamed") .. importTypeTag ..
            ns.COLORS.GRAY .. "  (" .. counts.pending .. " pending" ..
            (counts.missing > 0 and (", " .. ns.COLORS.RED .. counts.missing .. " miss|r") or "") ..
            (counts.unassigned > 0 and (", " .. ns.COLORS.ORANGE .. counts.unassigned .. " no char|r") or "") ..
            ")" .. "|r")

        local xBtn = TopSmallBtn(hdr, "x", "Delete list", function()
            ns.TodoList:ClearCurrent()
            UI._generatorPreview = nil
            ns:Print("Current to-do list deleted.")
            UI:Refresh()
            if UI.RefreshMini then UI:RefreshMini() end
        end)
        xBtn:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)

        local rBtn = TopSmallBtn(hdr, "R", "Rename", function()
            gf.renameBox:SetParent(hdr)
            gf.renameBox:ClearAllPoints()
            gf.renameBox:SetPoint("LEFT", hdr.toggle, "RIGHT", 2, 0)
            gf.renameBox:SetPoint("RIGHT", hdr, "RIGHT", -72, 0)
            gf.renameBox:SetText(currentList.name or "")
            gf.renameBox:Show()
            gf.renameBox:SetFocus(true)
            gf.renameBox:SetScript("OnEnterPressed", function(self)
                local name = self:GetText():match("^%s*(.-)%s*$")
                if name ~= "" then ns.TodoList:RenameList(0, name) end
                self:Hide()
                UI:Refresh()
            end)
        end)
        rBtn:SetPoint("RIGHT", xBtn, "LEFT", -2, 0)

        local dBtn = TopSmallBtn(hdr, "D", "Duplicate to queue", function()
            ns.TodoList:DuplicateList(0)
            ns:Print("Duplicated current list.")
            UI:Refresh()
        end)
        dBtn:SetPoint("RIGHT", rBtn, "LEFT", -2, 0)

        hdr:SetScript("OnClick", function()
            UI._genListCollapsed["current"] = not isCollapsed
            UI:Refresh()
        end)
        hdr:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.12, 0.18, 0.12, 0.8) end)
        hdr:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.1, 0.14, 0.1, 0.6) end)

        if not isCollapsed then
            local summary = ns.TodoList:GetCharacterSummary()
            for _, info in ipairs(summary) do
                local sub = TopRow()
                sub.bg:SetColorTexture(0.08, 0.1, 0.08, 0.4)
                local cName = info.charKey:match("^(.-)%-") or info.charKey
                local cRealm = info.charKey:match("%-(.+)$") or ""
                local cData = ns.db.characters and ns.db.characters[info.charKey]
                local cc = cData and CLASS_COLORS[cData.class] or "888888"
                sub.label:SetText(
                    "      |cff" .. cc .. cName .. "|r" ..
                    ns.COLORS.GRAY .. " (" .. cRealm .. ")|r  " ..
                    info.taskCount .. " items" ..
                    (info.totalValue > 0 and ("  ~" .. FormatGoldValue(info.totalValue)) or ""))
            end
        end
    end

    -- Queued lists
    local queued = ns.TodoList and ns.TodoList:GetQueuedLists() or {}
    for qi, qList in ipairs(queued) do
        local key = "queued_" .. qi
        local isCollapsed = UI._genListCollapsed[key] ~= false
        local qPending = 0
        for _, item in ipairs(qList.tasks or {}) do
            if item.status == "pending" then qPending = qPending + 1 end
        end

        local capturedQi = qi
        local hdr = TopRow()
        hdr.bg:SetColorTexture(0.14, 0.12, 0.08, 0.6)
        hdr.toggle:SetText(isCollapsed and "|cffffffff\226\150\182|r" or "|cffffffff\226\150\188|r")
        hdr.label:SetPoint("RIGHT", hdr, "RIGHT", -108, 0)
        local qImportTypeTag = qList.importType
            and ("  " .. ns.COLORS.GRAY .. "[" .. qList.importType .. "]|r") or ""
        hdr.label:SetText(
            ns.COLORS.YELLOW .. "Queued:|r " .. (qList.name or "Unnamed") .. qImportTypeTag ..
            ns.COLORS.GRAY .. "  (" .. qPending .. " items)" .. "|r")

        -- Action buttons
        local xBtn = TopSmallBtn(hdr, "x", "Delete", function()
            ns.TodoList:DeleteQueuedList(capturedQi)
            ns:Print("Deleted: " .. (qList.name or "Unnamed"))
            UI:Refresh()
        end)
        xBtn:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)

        local rBtn = TopSmallBtn(hdr, "R", "Rename", function()
            gf.renameBox:SetParent(hdr)
            gf.renameBox:ClearAllPoints()
            gf.renameBox:SetPoint("LEFT", hdr.toggle, "RIGHT", 2, 0)
            gf.renameBox:SetPoint("RIGHT", hdr, "RIGHT", -108, 0)
            gf.renameBox:SetText(qList.name or "")
            gf.renameBox:Show()
            gf.renameBox:SetFocus(true)
            gf.renameBox:SetScript("OnEnterPressed", function(self)
                local name = self:GetText():match("^%s*(.-)%s*$")
                if name ~= "" then ns.TodoList:RenameList(capturedQi, name) end
                self:Hide()
                UI:Refresh()
            end)
        end)
        rBtn:SetPoint("RIGHT", xBtn, "LEFT", -2, 0)

        local dBtn = TopSmallBtn(hdr, "D", "Duplicate", function()
            ns.TodoList:DuplicateList(capturedQi)
            UI:Refresh()
        end)
        dBtn:SetPoint("RIGHT", rBtn, "LEFT", -2, 0)

        if qi < #queued then
            local vBtn = TopSmallBtn(hdr, "v", "Move down", function()
                ns.TodoList:ReorderQueue(capturedQi, capturedQi + 1)
                UI:Refresh()
            end)
            vBtn:SetPoint("RIGHT", dBtn, "LEFT", -4, 0)
        end

        local upBtn = TopSmallBtn(hdr, "^",
            qi == 1 and "Promote to active" or "Move up",
            function()
                if capturedQi == 1 then
                    ns.TodoList:PromoteToActive(1)
                    ns:Print("Promoted: " .. (qList.name or "Unnamed"))
                else
                    ns.TodoList:ReorderQueue(capturedQi, capturedQi - 1)
                end
                UI:Refresh()
                if UI.RefreshMini then UI:RefreshMini() end
            end)
        if qi < #queued then
            upBtn:SetPoint("RIGHT", dBtn, "LEFT", -22, 0)
        else
            upBtn:SetPoint("RIGHT", dBtn, "LEFT", -4, 0)
        end

        hdr:SetScript("OnClick", function()
            UI._genListCollapsed[key] = not isCollapsed
            UI:Refresh()
        end)
        hdr:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.18, 0.15, 0.1, 0.8) end)
        hdr:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.14, 0.12, 0.08, 0.6) end)
    end

    -- No lists hint
    if not currentList and #queued == 0 then
        local hint = TopRow()
        hint.label:SetText(
            ns.COLORS.GRAY .. "No to-do lists. Import deals, then click " ..
            ns.COLORS.GREEN .. "Generate" .. ns.COLORS.GRAY .. ".|r")
    end

    local topHeight = math.abs(topY) + 2
    gf.topSection:SetHeight(topHeight)

    -- ========================================
    -- POSITION TWO COLUMNS
    -- ========================================

    local columnsTop = -topHeight - 2
    local containerWidth = tableContainer:GetWidth() or 600
    local halfWidth = math.floor((containerWidth - 1) / 2)

    -- Mid divider
    gf.midDivider:ClearAllPoints()
    gf.midDivider:SetPoint("TOPLEFT", gf, "TOPLEFT", 0, columnsTop)
    gf.midDivider:SetPoint("TOPRIGHT", gf, "TOPRIGHT", 0, columnsTop)

    -- Left column
    gf.leftCol:ClearAllPoints()
    gf.leftCol:SetPoint("TOPLEFT", gf, "TOPLEFT", 0, columnsTop - 1)
    gf.leftCol:SetPoint("BOTTOMLEFT", gf, "BOTTOMLEFT", 0, 0)
    gf.leftCol:SetWidth(halfWidth)

    -- Column divider
    gf.colDivider:ClearAllPoints()
    gf.colDivider:SetPoint("TOPLEFT", gf.leftCol, "TOPRIGHT", 0, 0)
    gf.colDivider:SetPoint("BOTTOMLEFT", gf.leftCol, "BOTTOMRIGHT", 0, 0)

    -- Right column
    gf.rightCol:ClearAllPoints()
    gf.rightCol:SetPoint("TOPLEFT", gf.colDivider, "TOPRIGHT", 0, 0)
    gf.rightCol:SetPoint("BOTTOMRIGHT", gf, "BOTTOMRIGHT", 0, 0)

    -- ========================================
    -- LEFT COLUMN: Filter + Item Pool
    -- ========================================

    -- Update filter toggle state
    SetToggleActive(gf.leftCol.filterAll, UI._genFilterMode == "all")
    SetToggleActive(gf.leftCol.filterTSM, UI._genFilterMode == "tsm")
    SetToggleActive(gf.leftCol.filterAuct, UI._genFilterMode == "auctionator")

    -- Hide all filter-mode-specific elements first
    gf.leftCol.treeFrame:Hide()
    gf.leftCol.tsmProfileLabel:Hide()
    gf.leftCol.tsmSelectedLabel:Hide()
    gf.leftCol.tsmClearBtn:Hide()
    gf.leftCol.tsmUnavail:Hide()
    gf.leftCol.auctFrame:Hide()
    gf.leftCol.auctUnavail:Hide()
    for _, row in ipairs(gf.leftCol.auctRows) do row:Hide() end

    local filterControlsBottom = -56  -- below description + label + filter buttons

    -- TSM Group Tree (show when TSM filter active)
    if UI._genFilterMode == "tsm" then
        local tsmEnabled = ns.TSM and ns.TSM:IsEnabled()
        if tsmEnabled and gf.leftCol.groupTree then
            local profile = ns.TSM:GetSelectedProfile()

            -- Show profile label
            gf.leftCol.tsmProfileLabel:ClearAllPoints()
            gf.leftCol.tsmProfileLabel:SetPoint("TOPLEFT", gf.leftCol, "TOPLEFT", 6, filterControlsBottom)
            gf.leftCol.tsmProfileLabel:SetText("Profile: " .. ns.COLORS.WHITE .. (profile or "none") .. "|r")
            gf.leftCol.tsmProfileLabel:Show()
            filterControlsBottom = filterControlsBottom - 16

            -- Show group tree
            gf.leftCol.treeFrame:ClearAllPoints()
            gf.leftCol.treeFrame:SetPoint("TOPLEFT", gf.leftCol, "TOPLEFT", 0, filterControlsBottom)
            gf.leftCol.treeFrame:SetPoint("RIGHT", gf.leftCol, "RIGHT", 0, 0)
            gf.leftCol.treeFrame:SetHeight(140)
            gf.leftCol.treeFrame:Show()

            if profile and gf.leftCol.groupTree._profile ~= profile then
                gf.leftCol.groupTree:SetProfile(profile)
            end
            filterControlsBottom = filterControlsBottom - 142

            -- Show selected group path label + clear button
            if UI._genFilterValue and UI._genFilterValue ~= "" then
                gf.leftCol.tsmSelectedLabel:ClearAllPoints()
                gf.leftCol.tsmSelectedLabel:SetPoint("TOPLEFT", gf.leftCol, "TOPLEFT", 6, filterControlsBottom)
                gf.leftCol.tsmSelectedLabel:SetText("Group: " .. UI._genFilterValue:gsub("`", " > "))
                gf.leftCol.tsmSelectedLabel:Show()

                gf.leftCol.tsmClearBtn:ClearAllPoints()
                gf.leftCol.tsmClearBtn:SetPoint("LEFT", gf.leftCol.tsmSelectedLabel, "RIGHT", 6, 0)
                gf.leftCol.tsmClearBtn:Show()

                filterControlsBottom = filterControlsBottom - 16
            end
        else
            -- TSM not available
            gf.leftCol.tsmUnavail:ClearAllPoints()
            gf.leftCol.tsmUnavail:SetPoint("TOPLEFT", gf.leftCol, "TOPLEFT", 6, filterControlsBottom)
            gf.leftCol.tsmUnavail:Show()
            filterControlsBottom = filterControlsBottom - 16
        end

    -- Auctionator list picker (show when Auctionator filter active)
    elseif UI._genFilterMode == "auctionator" then
        -- Shopping lists come from the SavedVariable, API is only needed for item lookups
        local listNames = ns:GetAuctionatorListNames()
        local auctAvailable = #listNames > 0 or type(AUCTIONATOR_SHOPPING_LISTS) == "table"

        if auctAvailable then

            gf.leftCol.auctFrame:ClearAllPoints()
            gf.leftCol.auctFrame:SetPoint("TOPLEFT", gf.leftCol, "TOPLEFT", 0, filterControlsBottom)
            gf.leftCol.auctFrame:SetPoint("RIGHT", gf.leftCol, "RIGHT", 0, 0)
            local listHeight = math.min(120, math.max(40, #listNames * 18 + 20))
            gf.leftCol.auctFrame:SetHeight(listHeight)
            gf.leftCol.auctFrame:Show()

            gf.leftCol.auctContent:SetWidth(gf.leftCol.auctScroll:GetWidth() or 150)

            -- Render list names as clickable rows
            for idx, row in ipairs(gf.leftCol.auctRows) do row:Hide() end

            local auctY = 0
            for idx, listName in ipairs(listNames) do
                local row = gf.leftCol.auctRows[idx]
                if not row then
                    row = CreateFrame("Button", nil, gf.leftCol.auctContent)
                    row:SetHeight(18)
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
                    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                    row.label:SetJustifyH("LEFT")
                    row:EnableMouse(true)
                    gf.leftCol.auctRows[idx] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", gf.leftCol.auctContent, "TOPLEFT", 0, -auctY)
                row:SetPoint("RIGHT", gf.leftCol.auctContent, "RIGHT", 0, 0)

                local isSelected = (UI._genFilterValue == listName)
                if isSelected then
                    row.bg:SetColorTexture(0.2, 0.35, 0.5, 0.6)
                    row.label:SetText("|cffffffff" .. listName .. "|r")
                else
                    row.bg:SetColorTexture(0, 0, 0, 0)
                    row.label:SetText(listName)
                    row.label:SetTextColor(0.8, 0.8, 0.8)
                end

                local capturedName = listName
                row:SetScript("OnClick", function()
                    SaveGenFilter("auctionator", capturedName)
                    AutoGenerate()
                    UI:Refresh()
                end)
                row:SetScript("OnEnter", function(self)
                    if not isSelected then self.bg:SetColorTexture(1, 1, 1, 0.05) end
                end)
                row:SetScript("OnLeave", function(self)
                    if not (UI._genFilterValue == capturedName) then self.bg:SetColorTexture(0, 0, 0, 0) end
                end)

                row:Show()
                auctY = auctY + 18
            end
            gf.leftCol.auctContent:SetHeight(math.max(1, auctY))

            filterControlsBottom = filterControlsBottom - listHeight - 4
        else
            -- Auctionator not available — show specific message
            gf.leftCol.auctUnavail:ClearAllPoints()
            gf.leftCol.auctUnavail:SetPoint("TOPLEFT", gf.leftCol, "TOPLEFT", 6, filterControlsBottom)
            gf.leftCol.auctUnavail:SetPoint("RIGHT", gf.leftCol, "RIGHT", -6, 0)
            if type(Auctionator) == "table" then
                gf.leftCol.auctUnavail:SetText("Auctionator detected but no shopping lists found. Create one in Auctionator first.")
            else
                gf.leftCol.auctUnavail:SetText("Auctionator is not installed.")
            end
            gf.leftCol.auctUnavail:Show()
            filterControlsBottom = filterControlsBottom - 16
        end
    end

    -- Build filtered item pool
    local filteredPool = ns.TodoList:GetFilteredItemPool(
        UI._genFilterMode, UI._genFilterValue, UI._genExcludedItems)

    -- Divider between filter controls and pool
    gf.leftCol.poolDivider:ClearAllPoints()
    gf.leftCol.poolDivider:SetPoint("TOPLEFT", gf.leftCol, "TOPLEFT", 6, filterControlsBottom + 2)
    gf.leftCol.poolDivider:SetPoint("RIGHT", gf.leftCol, "RIGHT", -6, 0)
    filterControlsBottom = filterControlsBottom - 4

    -- Item count label
    gf.leftCol.countLabel:ClearAllPoints()
    gf.leftCol.countLabel:SetPoint("TOPLEFT", gf.leftCol, "TOPLEFT", 6, filterControlsBottom)
    gf.leftCol.countLabel:SetText(ns.COLORS.GRAY .. #filteredPool .. " items in pool|r")

    -- Pool scroll area (right offset -22 for scrollbar)
    gf.leftCol.poolScroll:ClearAllPoints()
    gf.leftCol.poolScroll:SetPoint("TOPLEFT", gf.leftCol, "TOPLEFT", 0, filterControlsBottom - 14)
    gf.leftCol.poolScroll:SetPoint("BOTTOMRIGHT", gf.leftCol, "BOTTOMRIGHT", -22, 28)

    -- Static footer: Export to FP button
    if not gf.leftCol.footerBar then
        local fb = CreateFrame("Frame", nil, gf.leftCol)
        fb:SetHeight(26)
        fb:SetPoint("BOTTOMLEFT", gf.leftCol, "BOTTOMLEFT", 0, 0)
        fb:SetPoint("BOTTOMRIGHT", gf.leftCol, "BOTTOMRIGHT", 0, 0)
        local fbBg = fb:CreateTexture(nil, "BACKGROUND")
        fbBg:SetAllPoints()
        fbBg:SetColorTexture(0.1, 0.1, 0.15, 1)

        local exportBtn = CreateFrame("Button", nil, fb, "BackdropTemplate")
        exportBtn:SetHeight(20)
        exportBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        exportBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        exportBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        exportBtn.text = exportBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        exportBtn.text:SetPoint("CENTER")
        exportBtn.text:SetText("Export List to FP")
        exportBtn:SetWidth(exportBtn.text:GetStringWidth() + 20)
        exportBtn:SetPoint("CENTER", fb, "CENTER", 0, 0)
        exportBtn:SetScript("OnClick", function()
            local btn = UI.mainFrame and UI.mainFrame.actionBtns and UI.mainFrame.actionBtns.exportPoolToFP
            if btn then btn:GetScript("OnClick")() end
        end)
        exportBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.3, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Export filtered item pool as FP CSV", 1, 1, 1)
            GameTooltip:Show()
        end)
        exportBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
            GameTooltip:Hide()
        end)
        gf.leftCol.footerBar = fb
    end

    local poolScrollWidth = gf.leftCol.poolScroll:GetWidth()
    gf.leftCol.poolContent:SetWidth(poolScrollWidth and poolScrollWidth > 0 and poolScrollWidth or 200)

    -- Render pool items
    for _, row in ipairs(gf.leftCol.poolRows) do row:Hide() end

    local POOL_ROW_H = 18
    local poolY = 0
    for i, poolItem in ipairs(filteredPool) do
        local row = gf.leftCol.poolRows[i]
        if not row then
            row = CreateFrame("Button", nil, gf.leftCol.poolContent)
            row:SetHeight(POOL_ROW_H)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(14, 14)
            row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
            row.nameText:SetJustifyH("LEFT")
            row.qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.qtyText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.qtyText:SetJustifyH("RIGHT")
            row.nameText:SetPoint("RIGHT", row.qtyText, "LEFT", -4, 0)
            row:EnableMouse(true)
            gf.leftCol.poolRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", gf.leftCol.poolContent, "TOPLEFT", 0, -poolY)
        row:SetPoint("RIGHT", gf.leftCol.poolContent, "RIGHT", 0, 0)
        row.bg:SetColorTexture(i % 2 == 0 and 0.1 or 0.08, i % 2 == 0 and 0.1 or 0.08, i % 2 == 0 and 0.14 or 0.12, 0.6)

        if poolItem.icon then
            row.icon:SetTexture(poolItem.icon)
            row.icon:Show()
        else
            row.icon:Hide()
        end

        local displayName = poolItem.name or "?"
        -- Try to get quality color
        local lookupIcon, quality
        pcall(function()
            lookupIcon, quality = UI._LookupItemInfo(poolItem.itemID, poolItem.itemKey, poolItem.name)
        end)
        if quality and UI._QualityColorName then
            displayName = UI._QualityColorName(displayName, quality)
        end
        row.nameText:SetText(displayName)

        -- Show sources summary
        local srcParts = {}
        for _, src in ipairs(poolItem.sources) do
            if src.source == "Warbank" then
                table.insert(srcParts, src.quantity .. " wb")
            else
                local charName = src.source:match("^(.-)%-") or src.source
                table.insert(srcParts, src.quantity .. " " .. charName)
            end
        end
        row.qtyText:SetText(ns.COLORS.GRAY .. table.concat(srcParts, ", ") .. "|r")

        -- Right-click to exclude
        local itemKey = poolItem.itemKey
        row:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                UI._genExcludedItems[itemKey] = true
                UI:Refresh()
            end
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(1, 1, 1, 0.08)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(poolItem.name or "?", 1, 1, 1)
            GameTooltip:AddLine("Total: " .. poolItem.totalQuantity, 0.7, 0.7, 0.7)
            for _, src in ipairs(poolItem.sources) do
                GameTooltip:AddLine("  " .. src.source .. " (" .. src.location .. "): " .. src.quantity, 0.5, 0.5, 0.5)
            end
            GameTooltip:AddLine("\nRight-click to exclude", 0.4, 0.4, 0.4)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(i % 2 == 0 and 0.1 or 0.08, i % 2 == 0 and 0.1 or 0.08, i % 2 == 0 and 0.14 or 0.12, 0.6)
            GameTooltip:Hide()
        end)

        row:Show()
        poolY = poolY + POOL_ROW_H
    end
    gf.leftCol.poolContent:SetHeight(math.max(1, poolY))

    -- ========================================
    -- RIGHT COLUMN: Priority + Sort + Generated Items
    -- ========================================

    -- Show Save only when there's an unsaved preview
    if gf.rightCol.saveBtn then
        if UI._generatorPreview then
            gf.rightCol.saveBtn:Show()
            gf.rightCol.saveBtn:SetBackdropColor(0.15, 0.25, 0.15, 1)
            gf.rightCol.saveBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 0.8)
            gf.rightCol.saveBtn.text:SetTextColor(0.3, 1, 0.3)
        else
            gf.rightCol.saveBtn:Hide()
        end
    end

    local ALLOC_META = {
        gold           = {label = "Profit",        icon = "Interface\\Icons\\INV_Misc_Coin_17",                 color = {1, 0.82, 0}},
        noCompetition  = {label = "No Competition", icon = "Interface\\Icons\\Achievement_PVP_H_01",            color = {0.3, 1, 0.3}},
        population     = {label = "Population",     icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", color = {0.4, 0.7, 1}},
    }

    -- Drag state (shared across rows, persists in the frame)
    if not gf._dragState then
        gf._dragState = {}

        -- Ghost frame: follows cursor during drag
        local ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetSize(180, 26)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetAlpha(0.85)
        ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
        ghost.bg:SetAllPoints()
        ghost.bg:SetColorTexture(0.2, 0.25, 0.4, 0.9)
        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetSize(16, 16)
        ghost.icon:SetPoint("LEFT", ghost, "LEFT", 6, 0)
        ghost.label = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ghost.label:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
        ghost.label:SetPoint("RIGHT", ghost, "RIGHT", -6, 0)
        ghost.label:SetJustifyH("LEFT")
        -- Rounded-ish border
        ghost.border = ghost:CreateTexture(nil, "BORDER")
        ghost.border:SetPoint("TOPLEFT", -1, 1)
        ghost.border:SetPoint("BOTTOMRIGHT", 1, -1)
        ghost.border:SetColorTexture(0.5, 0.6, 1, 0.6)
        ghost:Hide()
        gf._dragState.ghost = ghost

        -- Drop indicator line
        local dropLine = UIParent:CreateTexture(nil, "OVERLAY")
        dropLine:SetHeight(2)
        dropLine:SetColorTexture(1, 0.82, 0, 0.9)
        dropLine:Hide()
        gf._dragState.dropLine = dropLine
    end

    local LIST_ROW_H = 28

    -- Helper: render allocation priority as a draggable ordered list
    local function RenderAllocList(orderTable, rowPool, parent, yStart, onChanged)
        for _, row in ipairs(rowPool) do row:Hide() end
        local y = yStart
        local ds = gf._dragState

        for idx, key in ipairs(orderTable) do
            local meta = ALLOC_META[key] or {label = key, color = {0.7, 0.7, 0.7}}
            local row = rowPool[idx]
            if not row then
                row = CreateFrame("Button", nil, parent, "BackdropTemplate")
                row:SetHeight(LIST_ROW_H)
                row:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 10,
                    insets = {left = 2, right = 2, top = 2, bottom = 2},
                })

                -- Drag grip dots (left side)
                row.grip = row:CreateTexture(nil, "ARTWORK")
                row.grip:SetSize(8, 14)
                row.grip:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.grip:SetColorTexture(0.4, 0.4, 0.5, 0.5)

                -- Rank badge (number in a circle-ish bg)
                row.rankBg = row:CreateTexture(nil, "ARTWORK")
                row.rankBg:SetSize(18, 18)
                row.rankBg:SetPoint("LEFT", row.grip, "RIGHT", 4, 0)
                row.rankBg:SetColorTexture(0.2, 0.2, 0.3, 0.8)

                row.rankNum = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.rankNum:SetPoint("CENTER", row.rankBg, "CENTER", 0, 0)

                -- Icon
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(16, 16)
                row.icon:SetPoint("LEFT", row.rankBg, "RIGHT", 6, 0)

                -- Label
                row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.nameLabel:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.nameLabel:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                row.nameLabel:SetJustifyH("LEFT")

                row:EnableMouse(true)
                rowPool[idx] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
            row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)

            -- Colors: gradient based on rank position (1st = brightest)
            local brightness = 1 - (idx - 1) * 0.2
            local c = meta.color
            row:SetBackdropColor(c[1] * 0.12 * brightness, c[2] * 0.12 * brightness, c[3] * 0.15 * brightness, 0.9)
            row:SetBackdropBorderColor(c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 0.6)

            -- Rank number
            row.rankNum:SetText(idx)
            row.rankNum:SetTextColor(c[1], c[2], c[3])

            -- Icon
            if meta.icon then
                row.icon:SetTexture(meta.icon)
                row.icon:Show()
            else
                row.icon:Hide()
            end

            -- Label
            row.nameLabel:SetText(meta.label)
            row.nameLabel:SetTextColor(c[1] * 0.8 + 0.2, c[2] * 0.8 + 0.2, c[3] * 0.8 + 0.2)

            -- Grip dots: 3 pairs of small squares
            -- (the single texture is fine as a visual hint)
            row.grip:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.6)

            local capturedIdx = idx
            local capturedKey = key

            -- Hover
            row:SetScript("OnEnter", function(self)
                if not ds.dragging then
                    self:SetBackdropBorderColor(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7, 1)
                    self.grip:SetColorTexture(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(meta.label, c[1], c[2], c[3])
                    GameTooltip:AddLine("Drag to reorder, or click to move", 0.5, 0.5, 0.5)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                if not ds.dragging then
                    self:SetBackdropBorderColor(c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 0.6)
                    self.grip:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.6)
                    GameTooltip:Hide()
                end
            end)

            -- Mouse down: record start position, begin tracking on the ghost immediately
            row:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" or ds.dragging then return end
                local cx, cy = GetCursorPosition()
                ds._pendingRow = self
                ds._pendingIdx = capturedIdx
                ds._pendingMeta = meta
                ds._pendingColor = c
                ds._startCX = cx
                ds._startCY = cy
                ds._dragStarted = false

                -- Use ghost's OnUpdate for threshold detection (survives row rebuilds)
                ds.ghost:SetScript("OnUpdate", function(g)
                    if ds._dragStarted then
                        -- Already dragging — track cursor
                        local gcx, gcy = GetCursorPosition()
                        local scale = UIParent:GetEffectiveScale()
                        g:ClearAllPoints()
                        g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", gcx / scale, gcy / scale)

                        local parentTop = parent:GetTop()
                        if not parentTop then return end
                        local cursorY = gcy / scale
                        local listTop = parentTop + yStart
                        local relY = listTop - cursorY
                        local dropIdx = math.floor(relY / LIST_ROW_H) + 1
                        dropIdx = math.max(1, math.min(dropIdx, #orderTable))
                        ds.dropIdx = dropIdx

                        local line = ds.dropLine
                        local lineY = yStart - (dropIdx - 1) * LIST_ROW_H
                        if dropIdx > ds.dragIdx then
                            lineY = yStart - dropIdx * LIST_ROW_H
                        end
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, lineY + 1)
                        line:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
                        line:Show()
                    else
                        -- Check threshold
                        local ncx, ncy = GetCursorPosition()
                        if not ds._startCX then
                            g:SetScript("OnUpdate", nil)
                            return
                        end
                        local dx = math.abs(ncx - ds._startCX)
                        local dy = math.abs(ncy - ds._startCY)
                        if dx + dy > 6 then
                            -- Start drag
                            ds._dragStarted = true
                            ds.dragging = true
                            ds.dragIdx = ds._pendingIdx
                            local m = ds._pendingMeta
                            local pc = ds._pendingColor
                            g.icon:SetTexture(m.icon or "")
                            g.label:SetText(m.label)
                            g.label:SetTextColor(pc[1], pc[2], pc[3])
                            g.bg:SetColorTexture(pc[1] * 0.2, pc[2] * 0.2, pc[3] * 0.25, 0.95)
                            g.border:SetColorTexture(pc[1] * 0.6, pc[2] * 0.6, pc[3] * 0.8, 0.8)
                            g:Show()
                            if ds._pendingRow then ds._pendingRow:SetAlpha(0.3) end
                            GameTooltip:Hide()
                        end
                    end
                end)
            end)

            row:SetScript("OnMouseUp", function(self, button)
                if button ~= "LeftButton" then return end

                if ds.dragging and ds._dragStarted then
                    -- Complete drag
                    ds.dragging = false
                    ds._dragStarted = false
                    if ds._pendingRow then ds._pendingRow:SetAlpha(1) end
                    ds.ghost:Hide()
                    ds.ghost:SetScript("OnUpdate", nil)
                    ds.dropLine:Hide()

                    local from = ds.dragIdx
                    local to = ds.dropIdx or from
                    if from ~= to then
                        local moved = table.remove(orderTable, from)
                        table.insert(orderTable, to, moved)
                        onChanged()
                    end
                else
                    -- Click — cycle position
                    ds.ghost:SetScript("OnUpdate", nil)
                    ds.ghost:Hide()
                    ds.dragging = false
                    ds._dragStarted = false
                    ds._startCX = nil
                    if capturedIdx > 1 then
                        orderTable[capturedIdx], orderTable[capturedIdx - 1] = orderTable[capturedIdx - 1], orderTable[capturedIdx]
                    else
                        local moved = table.remove(orderTable, 1)
                        table.insert(orderTable, moved)
                    end
                    onChanged()
                end
            end)

            row:Show()
            y = y - LIST_ROW_H
        end
        return y
    end

    local function AutoRegenerate()
        if ns.TodoList and ns:ImportGetCount("fpScanner") > 0 then
            UI._generatorPreview = ns.TodoList:GenerateTodoList("fpScanner", UI:GetGenAllocationOrder())
        end
        UI:Refresh()
    end

    -- Priority section
    local rightY = -22
    gf.rightCol.allocDesc:ClearAllPoints()
    gf.rightCol.allocDesc:SetPoint("TOPLEFT", gf.rightCol, "TOPLEFT", 6, rightY)
    gf.rightCol.allocDesc:SetPoint("RIGHT", gf.rightCol, "RIGHT", -6, 0)
    rightY = rightY - 14
    gf.rightCol.allocLabel:ClearAllPoints()
    gf.rightCol.allocLabel:SetPoint("TOPLEFT", gf.rightCol, "TOPLEFT", 6, rightY)
    rightY = rightY - 14
    rightY = RenderAllocList(UI:GetGenAllocationOrder(), gf.rightCol.allocRows, gf.rightCol, rightY, AutoRegenerate)
    rightY = rightY - 8

    -- Sort section
    gf.rightCol.sortDesc:ClearAllPoints()
    gf.rightCol.sortDesc:SetPoint("TOPLEFT", gf.rightCol, "TOPLEFT", 6, rightY)
    gf.rightCol.sortDesc:SetPoint("RIGHT", gf.rightCol, "RIGHT", -6, 0)
    rightY = rightY - 14
    gf.rightCol.sortLabel:ClearAllPoints()
    gf.rightCol.sortLabel:SetPoint("TOPLEFT", gf.rightCol, "TOPLEFT", 6, rightY)
    rightY = rightY - 14

    local sortBtnX = 4
    for _, key in ipairs({"profit", "character", "realm", "noCompetition"}) do
        local btn = gf.rightCol.sortBtns[key]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", gf.rightCol, "TOPLEFT", sortBtnX, rightY)
            SetToggleActive(btn, UI:GetGenSortMode() == key)
            btn:Show()
            sortBtnX = sortBtnX + btn:GetWidth() + 3
        end
    end
    rightY = rightY - 22

    -- Build grouped display data
    local previewSource = UI._generatorPreview or currentList
    -- Preview uses .items, saved lists use .tasks
    local previewItems = previewSource and (previewSource.items or previewSource.tasks)
    local displayGroups = {}
    local missingCount = 0
    if previewItems then
        displayGroups, missingCount = ns.TodoList:BuildDisplayGroups(previewItems, UI:GetGenSortMode())
    end

    -- Status label
    gf.rightCol.statusLabel:ClearAllPoints()
    gf.rightCol.statusLabel:SetPoint("TOPLEFT", gf.rightCol, "TOPLEFT", 6, rightY)
    if previewItems then
        -- Count assigned items only
        local assignedCount = 0
        for _, g in ipairs(displayGroups) do
            if g.charKey then assignedCount = assignedCount + #g.items end
        end
        local statusText = ns.COLORS.GRAY .. assignedCount .. " tasks across " .. #displayGroups .. " group(s)"
        if missingCount > 0 then
            statusText = statusText .. "  |  " .. ns.COLORS.RED .. missingCount .. " not in inventory|r"
        end
        statusText = statusText .. "|r"
        gf.rightCol.statusLabel:SetText(statusText)
    else
        gf.rightCol.statusLabel:SetText(
            ns.COLORS.GRAY .. "Click Generate to build list|r")
    end
    rightY = rightY - 14

    -- Divider between controls and generated list
    gf.rightCol.listDivider:ClearAllPoints()
    gf.rightCol.listDivider:SetPoint("TOPLEFT", gf.rightCol, "TOPLEFT", 6, rightY + 2)
    gf.rightCol.listDivider:SetPoint("RIGHT", gf.rightCol, "RIGHT", -6, 0)
    rightY = rightY - 4

    -- Generated items scroll area (right offset -22 for scrollbar)
    gf.rightCol.genScroll:ClearAllPoints()
    gf.rightCol.genScroll:SetPoint("TOPLEFT", gf.rightCol, "TOPLEFT", 0, rightY)
    gf.rightCol.genScroll:SetPoint("BOTTOMRIGHT", gf.rightCol, "BOTTOMRIGHT", -22, 0)

    local genScrollWidth = gf.rightCol.genScroll:GetWidth()
    gf.rightCol.genContent:SetWidth(genScrollWidth and genScrollWidth > 0 and genScrollWidth or 200)

    -- Render grouped items: headers + sub-items
    for _, row in ipairs(gf.rightCol.genRows) do row:Hide() end

    local LookupItemInfo = UI._LookupItemInfo
    local QualityColorName = UI._QualityColorName
    local GEN_ROW_H = 18
    local HDR_ROW_H = 22
    local genY = 0
    local genRowIdx = 0

    local function GetOrCreateGenRow(height)
        genRowIdx = genRowIdx + 1
        local row = gf.rightCol.genRows[genRowIdx]
        if not row then
            row = CreateFrame("Button", nil, gf.rightCol.genContent)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(14, 14)
            row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
            row.nameText:SetJustifyH("LEFT")
            row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.rightText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.rightText:SetJustifyH("RIGHT")
            row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
            row:EnableMouse(true)
            gf.rightCol.genRows[genRowIdx] = row
        end
        row:SetHeight(height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", gf.rightCol.genContent, "TOPLEFT", 0, -genY)
        row:SetPoint("RIGHT", gf.rightCol.genContent, "RIGHT", 0, 0)
        row.icon:Hide()
        row.nameText:SetText("")
        row.rightText:SetText("")
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:Show()
        return row
    end

    for gi, group in ipairs(displayGroups) do
        local isUnassigned = not group.charKey

        -- Group header row
        local hdr = GetOrCreateGenRow(HDR_ROW_H)

        if isUnassigned then
            -- Unassigned: dimmed header with "Create character" prompt
            hdr.bg:SetColorTexture(0.15, 0.08, 0.08, 0.7)
            local realmName = group.realm ~= "" and group.realm or "unknown realm"
            hdr.nameText:SetText(
                ns.COLORS.RED .. "Create character on " .. realmName .. "|r" ..
                ns.COLORS.GRAY .. "  (" .. #group.items .. " items — not in to-do list)" ..
                "\n  Tip: Log in to a character on this realm once so FlipQueue can find it|r")
        else
            -- Assigned: normal header with class-colored character name
            hdr.bg:SetColorTexture(0.12, 0.15, 0.2, 0.8)
            local charData = ns.db.characters and ns.db.characters[group.charKey]
            local cc = charData and (UI._CLASS_COLORS or {})[charData.class] or "888888"
            local charDisplay = "|cff" .. cc .. group.charName .. "|r"
            local realmDisplay = group.realm ~= "" and (ns.COLORS.GRAY .. " - " .. group.realm .. "|r") or ""
            hdr.nameText:SetText(charDisplay .. realmDisplay ..
                ns.COLORS.GRAY .. "  (" .. #group.items .. " items)|r")
        end

        hdr.nameText:ClearAllPoints()
        hdr.nameText:SetPoint("LEFT", hdr, "LEFT", 6, 0)
        hdr.nameText:SetPoint("RIGHT", hdr.rightText, "LEFT", -4, 0)

        -- Gold total on right
        local goldStr = UI._FormatGoldValue and UI._FormatGoldValue(group.totalGold) or ""
        if goldStr ~= "" then
            local goldColor = isUnassigned and ns.COLORS.GRAY or ns.COLORS.YELLOW
            hdr.rightText:SetText(goldColor .. "~" .. goldStr .. "|r")
        end

        local hdrBgColor = isUnassigned and {0.15, 0.08, 0.08, 0.7} or {0.12, 0.15, 0.2, 0.8}
        local hdrHoverColor = isUnassigned and {0.2, 0.1, 0.1, 0.8} or {0.15, 0.2, 0.28, 0.9}
        hdr:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(unpack(hdrHoverColor))
        end)
        hdr:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(unpack(hdrBgColor))
        end)
        genY = genY + HDR_ROW_H

        -- Item rows under this group
        for ii, item in ipairs(group.items) do
            local row = GetOrCreateGenRow(GEN_ROW_H)
            if isUnassigned then
                -- Dimmed rows for unassigned items
                row.bg:SetColorTexture(0.1, 0.06, 0.06, 0.4)
            else
                row.bg:SetColorTexture(ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.12 or 0.1, 0.6)
            end

            -- Item icon
            local lookupIcon, quality, resolvedID
            pcall(function()
                lookupIcon, quality, resolvedID = LookupItemInfo(item.itemID, item.itemKey, item.name)
            end)
            local itemIcon = item.icon or lookupIcon
            if itemIcon then
                row.icon:SetTexture(itemIcon)
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row, "LEFT", 14, 0)  -- indented under header
                row.icon:Show()
                row.nameText:ClearAllPoints()
                row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
                row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
            else
                row.nameText:ClearAllPoints()
                row.nameText:SetPoint("LEFT", row, "LEFT", 16, 0)
                row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -4, 0)
            end

            -- Item name with quality color
            local displayName = item.name or "?"
            if isUnassigned then
                -- Dim the name for unassigned items
                displayName = ns.COLORS.GRAY .. (item.name or "?") .. "|r"
            elseif quality and QualityColorName then
                displayName = QualityColorName(displayName, quality)
            elseif item.quality and item.quality ~= "" and QualityColorName then
                displayName = QualityColorName(displayName, item.quality)
            end
            local qtyStr = (item.quantity or 1) > 1 and (" x" .. (item.quantity or 1)) or ""
            row.nameText:SetText(displayName .. qtyStr)

            -- Dim icon for unassigned items
            if itemIcon and isUnassigned then
                row.icon:SetDesaturated(true)
                row.icon:SetAlpha(0.5)
            elseif itemIcon then
                row.icon:SetDesaturated(false)
                row.icon:SetAlpha(1)
            end

            -- Price on right
            local priceStr = item.expectedPrice or ""
            if isUnassigned then
                row.rightText:SetText(ns.COLORS.GRAY .. priceStr .. "|r")
            elseif item.status == "missing" then
                row.rightText:SetText(ns.COLORS.RED .. "missing|r")
                row.bg:SetColorTexture(0.15, 0.05, 0.05, 0.4)
            else
                row.rightText:SetText(priceStr)
            end

            -- Row background for OnLeave restore
            local restoreBg
            if isUnassigned then
                restoreBg = {0.1, 0.06, 0.06, 0.4}
            elseif item.status == "missing" then
                restoreBg = {0.15, 0.05, 0.05, 0.4}
            else
                restoreBg = {ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.08 or 0.06, ii % 2 == 0 and 0.12 or 0.1, 0.6}
            end

            -- Tooltip
            local capturedItem = item
            local capturedID = resolvedID or tonumber(item.itemID)
            row:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(1, 1, 1, 0.08)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if capturedID and capturedID > 0 then
                    GameTooltip:SetItemByID(capturedID)
                else
                    GameTooltip:SetText(capturedItem.name or "?", 1, 1, 1)
                end
                if capturedItem.targetRealm and capturedItem.targetRealm ~= "" then
                    GameTooltip:AddLine("Realm: " .. capturedItem.targetRealm, 0.7, 0.7, 0.7)
                end
                if capturedItem.expectedPrice then
                    GameTooltip:AddLine("Price: " .. capturedItem.expectedPrice, 0.7, 0.7, 0.7)
                end
                if isUnassigned then
                    GameTooltip:AddLine("Create a character on this realm to add to your to-do list", 0.8, 0.4, 0.4)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(unpack(restoreBg))
                GameTooltip:Hide()
            end)

            genY = genY + GEN_ROW_H
        end

        -- Small gap between groups
        genY = genY + 2
    end
    gf.rightCol.genContent:SetHeight(math.max(1, genY))

    -- ========================================
    -- STATUS BAR
    -- ========================================

    local genStatusParts = {}
    local excludeCount = 0
    for _ in pairs(UI._genExcludedItems) do excludeCount = excludeCount + 1 end

    if UI._generatorPreview then
        local previewItems = UI._generatorPreview.items or UI._generatorPreview.tasks or {}
        table.insert(genStatusParts, #previewItems .. " tasks")
        table.insert(genStatusParts, "Replace/Append/Queue to commit")
    elseif currentList then
        local counts = ns.TodoList:GetStatusCounts()
        table.insert(genStatusParts, counts.pending .. " active")
        if counts.unassigned and counts.unassigned > 0 then
            table.insert(genStatusParts, ns.COLORS.ORANGE .. counts.unassigned .. " need chars|r")
        end
        table.insert(genStatusParts, "Generate to rebuild")
    else
        table.insert(genStatusParts, pending .. " deals")
        table.insert(genStatusParts, "Generate to match inventory")
    end
    table.insert(genStatusParts, #filteredPool .. " pool items")
    if excludeCount > 0 then
        table.insert(genStatusParts, excludeCount .. " excluded")
    end

    -- Onboarding hint: show if no characters scanned yet
    local charCount = 0
    for _ in pairs(ns.db.characters or {}) do charCount = charCount + 1 end
    if charCount == 0 then
        table.insert(genStatusParts, ns.COLORS.YELLOW .. "Log in to each character once to enable matching|r")
    end

    mainFrame.statusText:SetText(table.concat(genStatusParts, "  |  "))
end
