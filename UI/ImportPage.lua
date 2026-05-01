-- UI/ImportPage.lua
-- Import page: paste box, format detection, preview table, commit flow
local addonName, ns = ...

local UI = ns.UI
local tableContainer = UI.tableContainer

-- ==========================================
-- IMPORT PAGE FRAME CREATION
-- ==========================================

local importPage = CreateFrame("Frame", nil, tableContainer)
importPage:SetAllPoints()
importPage:Hide()

local importInstr = importPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
importInstr:SetPoint("TOPLEFT", importPage, "TOPLEFT", 8, -4)
importInstr:SetText("Paste FlippingPal data below, then click Preview:")
importInstr:SetTextColor(0.7, 0.7, 0.7)

-- Edit box area (top 100px)
local importEditBg = CreateFrame("Frame", nil, importPage, "BackdropTemplate")
importEditBg:SetPoint("TOPLEFT", importPage, "TOPLEFT", 4, -20)
importEditBg:SetPoint("TOPRIGHT", importPage, "TOPRIGHT", -4, -20)
importEditBg:SetHeight(80)
importEditBg:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = {left = 2, right = 2, top = 2, bottom = 2},
})
importEditBg:SetBackdropColor(0.05, 0.05, 0.08, 1)
importEditBg:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)

local importScroll = CreateFrame("ScrollFrame", "FlipQueueImportScrollInline", importEditBg, "UIPanelScrollFrameTemplate")
importScroll:SetPoint("TOPLEFT", importEditBg, "TOPLEFT", 6, -4)
importScroll:SetPoint("BOTTOMRIGHT", importEditBg, "BOTTOMRIGHT", -22, 4)

local importEdit = CreateFrame("EditBox", "FlipQueueImportEditInline", importScroll)
importEdit:SetMultiLine(true)
importEdit:SetAutoFocus(false)
importEdit:SetMaxLetters(0)
importEdit:SetFontObject("ChatFontNormal")
importEdit:SetWidth(importScroll:GetWidth() or 500)
importScroll:SetScrollChild(importEdit)
importScroll:SetScript("OnSizeChanged", function(sf, w)
    importEdit:SetWidth(w)
end)

-- Progress bar (shown during async import, hidden otherwise)
local progressBar = CreateFrame("Frame", nil, importPage, "BackdropTemplate")
progressBar:SetHeight(22)
progressBar:SetPoint("TOPLEFT", importEditBg, "BOTTOMLEFT", 0, -2)
progressBar:SetPoint("TOPRIGHT", importEditBg, "BOTTOMRIGHT", 0, -2)
progressBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = {left = 2, right = 2, top = 2, bottom = 2},
})
progressBar:SetBackdropColor(0.05, 0.05, 0.08, 1)
progressBar:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)

progressBar.fill = progressBar:CreateTexture(nil, "ARTWORK")
progressBar.fill:SetColorTexture(0.15, 0.55, 0.15, 0.9)
progressBar.fill:SetPoint("TOPLEFT", progressBar, "TOPLEFT", 3, -3)
progressBar.fill:SetPoint("BOTTOMLEFT", progressBar, "BOTTOMLEFT", 3, 3)
progressBar.fill:SetWidth(1)

progressBar.text = progressBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
progressBar.text:SetPoint("CENTER", progressBar, "CENTER", 0, 0)
progressBar.text:SetTextColor(0.9, 0.9, 0.9)
progressBar:Hide()

local function ShowProgress(processed, total)
    progressBar:Show()
    local pct = total > 0 and (processed / total) or 0
    local barWidth = math.max(1, (progressBar:GetWidth() - 6) * pct)
    progressBar.fill:SetWidth(barWidth)
    progressBar.text:SetText(string.format("Importing... %d / %d  (%d%%)", processed, total, math.floor(pct * 100)))
end

local function HideProgress()
    progressBar:Hide()
end

-- Preview table (below editbox, fills remaining space)
UI.importPreviewTable = UI:CreateScrollTable(importPage, {
    {key = "status",   label = "Status",  width = 52,  align = "CENTER", sortable = true},
    {key = "name",     label = "Item",    width = 160, sortable = true},
    {key = "realm",    label = "Realm",   width = 110, sortable = true},
    {key = "price",    label = "Price",   width = 70,  sortable = true},
    {key = "qty",      label = "Qty",     width = 30,  align = "CENTER", sortable = true},
    {key = "reason",   label = "Reason",  width = 128, sortable = true},
})
UI.importPreviewTable:SetSort("status", true)

-- Position the preview table below the editbox
UI.importPreviewTable.headerFrame:SetParent(importPage)
UI.importPreviewTable.headerFrame:ClearAllPoints()
UI.importPreviewTable.headerFrame:SetPoint("TOPLEFT", importEditBg, "BOTTOMLEFT", 0, -4)
UI.importPreviewTable.headerFrame:SetPoint("TOPRIGHT", importEditBg, "BOTTOMRIGHT", 0, -4)

UI.importPreviewTable.scrollFrame:SetParent(importPage)
UI.importPreviewTable.scrollFrame:ClearAllPoints()
UI.importPreviewTable.scrollFrame:SetPoint("TOPLEFT", UI.importPreviewTable.headerFrame, "BOTTOMLEFT", 0, 0)
UI.importPreviewTable.scrollFrame:SetPoint("BOTTOMRIGHT", importPage, "BOTTOMRIGHT", -22, 20)

local importStatus = importPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
importStatus:SetPoint("LEFT", importPage, "BOTTOMLEFT", 8, 10)
importStatus:SetTextColor(0.5, 0.5, 0.5)
importStatus:SetText("")

-- Auto-generate To-Do checkbox
local importAutoGenCheck = CreateFrame("CheckButton", "FlipQueueImportAutoGenCheck", importPage, "UICheckButtonTemplate")
importAutoGenCheck:SetSize(22, 22)
importAutoGenCheck:SetPoint("RIGHT", importPage, "BOTTOMRIGHT", -8, 10)
local importAutoGenLabel = importPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
importAutoGenLabel:SetPoint("RIGHT", importAutoGenCheck, "LEFT", -2, 0)
importAutoGenLabel:SetText("Auto-generate To-Do")
importAutoGenLabel:SetTextColor(0.5, 0.5, 0.5)
importAutoGenCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Auto-generate To-Do List", 1, 1, 1)
    GameTooltip:AddLine("After import, automatically generate and save a\nTo-Do list using your current Generator settings.\n\n|cffff8800Warning:|r This replaces your current To-Do list.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
importAutoGenCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
importAutoGenCheck:SetScript("OnClick", function(self)
    if ns.db then ns.db.settings.importAutoGenerate = self:GetChecked() end
end)

-- Skip-preview checkbox (persisted)
local importSkipCheck = CreateFrame("CheckButton", "FlipQueueImportSkipCheck", importPage, "UICheckButtonTemplate")
importSkipCheck:SetSize(22, 22)
importSkipCheck:SetPoint("RIGHT", importAutoGenLabel, "LEFT", -12, 0)
local importSkipLabel = importPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
importSkipLabel:SetPoint("RIGHT", importSkipCheck, "LEFT", -2, 0)
importSkipLabel:SetText("Auto-import")
importSkipLabel:SetTextColor(0.5, 0.5, 0.5)
importSkipCheck:SetScript("OnClick", function(self)
    if ns.db then ns.db.settings.importAutoImport = self:GetChecked() end
end)

-- Auto-generate To-Do list after import
local function TryAutoGenerateTodo()
    if not importAutoGenCheck:GetChecked() then return end
    if not ns.TodoList then return end
    local allocationOrder = UI:GetGenAllocationOrder()
    local preview = ns.TodoList:GenerateTodoList("fpScanner", allocationOrder)
    if preview and preview.items and #preview.items > 0 then
        local count = #preview.items
        local existingList = ns.TodoList:GetCurrentList()
        if existingList then
            ns.TodoList:CommitList(preview, "upcoming")
        else
            ns.TodoList:CommitList(preview, "replace")
        end
        ns:Print(ns.COLORS.CYAN .. "Auto-generated To-Do list with " .. count .. " tasks (replaced previous list).|r")
    end
end
UI._tryAutoGenerateTodo = TryAutoGenerateTodo

-- Stored preview data
local importPreviewData = nil
local importPreviewResults = nil

-- Auto-detect paste and build preview
local importLastLen = 0
local importBusy = false -- guard against re-entrant pastes during async save

-- Inputs above this many characters route through the async chunked
-- parser to avoid client freezes during the parse stage. The previous
-- chunking only covered the save / preview stages — Parse itself was
-- still O(N) synchronous and froze the client on full-region FP
-- pastes (~700KB / 4500 items, FQ-131).
local PARSE_CHUNK_THRESHOLD = 50000  -- ~50KB ≈ 330 FP-website items

-- Continuation after parse completes, factored out so both the sync
-- and chunked parse paths share it. Routes the parsed item list into
-- the existing save / preview pipeline (which already chunks).
local function HandleParsedItems(items)
    HideProgress()
    if not items or #items == 0 then
        importBusy = false
        importStatus:SetText(ns.COLORS.RED .. "No items found in pasted data.|r")
        return
    end

    if importSkipCheck:GetChecked() then
        -- Auto-import: process async with progress bar
        importBusy = true
        importEdit:SetText("")
        importEdit:ClearFocus()
        importPreviewData = nil
        importPreviewResults = nil
        UI.importPreviewTable:SetData({})
        importLastLen = 0

        local total = #items
        ShowProgress(0, total)
        importStatus:SetText(ns.COLORS.YELLOW .. "Processing " .. total .. " items...|r")

        ns.Import:SaveChunked(items, nil, 50,
            function(processed, t) ShowProgress(processed, t) end,
            function(added)
                HideProgress()
                importBusy = false
                ns:Print("Imported " .. added .. " new items (" .. total .. " parsed, duplicates merged).")
                importStatus:SetText(ns.COLORS.GREEN .. added .. " items imported!|r")
                TryAutoGenerateTodo()
                UI:Refresh()
                UI:RefreshMini()
            end
        )
    else
        local total = #items
        local threshold = ns.Import.LARGE_THRESHOLD or 500
        if total >= threshold then
            importBusy = true
            importPreviewData = items
            importPreviewResults = nil
            UI.importPreviewTable:SetData({})
            ShowProgress(0, total)
            importStatus:SetText(ns.COLORS.YELLOW .. "Scanning " .. total .. " items for duplicates...|r")
            ns.Import:PreviewAddChunked(items, nil, ns.Import.CHUNK_SIZE,
                function(processed, t) ShowProgress(processed, t) end,
                function(results)
                    HideProgress()
                    importBusy = false
                    importPreviewResults = results
                    UI:RefreshImportPreview()
                end
            )
        else
            importBusy = false
            importPreviewData = items
            importPreviewResults = ns.Import:PreviewAdd(items)
            UI:RefreshImportPreview()
        end
    end
end

importEdit:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    if importBusy then return end
    local text = self:GetText()
    local newLen = #text
    if importLastLen < 10 and newLen > 50 and text:find("\n") then
        if newLen > PARSE_CHUNK_THRESHOLD then
            -- Large paste: chunked parse so the parse stage doesn't
            -- freeze the client. Show a status banner immediately so
            -- the player knows we're working and has feedback during
            -- the multi-second parse window.
            importBusy = true
            importStatus:SetText(ns.COLORS.YELLOW ..
                "Parsing large paste... please wait.|r")
            ShowProgress(0, 1)  -- indeterminate until parse reports first chunk
            ns.Import:ParseChunked(text,
                function(processed, total)
                    importStatus:SetText(ns.COLORS.YELLOW ..
                        ("Parsing %d / %d items...|r"):format(processed, total))
                    ShowProgress(processed, total)
                end,
                function(items)
                    importBusy = false  -- HandleParsedItems may flip it back on
                    HandleParsedItems(items)
                end
            )
        else
            -- Small paste: synchronous parse keeps the existing behavior
            -- (preview shows up instantly, no progress bar flash).
            local items = ns.Import:Parse(text)
            HandleParsedItems(items)
        end
    end
    importLastLen = newLen
end)
importEdit:SetScript("OnEscapePressed", function() importEdit:ClearFocus() end)

-- Quality color map for preview
local IMPORT_QUALITY_COLORS = {
    Poor = "9d9d9d", Common = "ffffff", Uncommon = "1eff00",
    Rare = "0070dd", Epic = "a335ee", Legendary = "ff8000",
    Artifact = "e6cc80", Heirloom = "00ccff",
}

-- Build preview table display data
function UI:RefreshImportPreview()
    if not importPreviewResults then
        UI.importPreviewTable:SetData({})
        return
    end

    local data = {}
    local newCount, dupCount, updateCount = 0, 0, 0

    for _, result in ipairs(importPreviewResults) do
        local item = result.item
        local st = result._importStatus

        local dupeReason = result._dupeReason
        local statusStr, statusSort
        if st == "new" then
            statusStr = ns.COLORS.GREEN .. "New" .. "|r"
            statusSort = "1new"
            newCount = newCount + 1
        elseif st == "update" then
            statusStr = ns.COLORS.YELLOW .. "Update" .. "|r"
            statusSort = "2update"
            updateCount = updateCount + 1
        elseif st == "duplicate" then
            statusStr = ns.COLORS.GRAY .. "Dupe" .. "|r"
            statusSort = "3dupe"
            dupCount = dupCount + 1
        else
            statusStr = st or "?"
            statusSort = "4" .. (st or "")
        end

        local displayName = item.name or "?"
        local qColor = item.quality and IMPORT_QUALITY_COLORS[item.quality]
        if qColor then
            displayName = "|cff" .. qColor .. displayName .. "|r"
        end

        -- Cross-realm flip indicator in name (must also have a buyRealm)
        local isCrossRealm = (item.dealType == "flip" or item.dealType == "buy")
            and item.buyRealm and item.buyRealm ~= ""
        if isCrossRealm then
            displayName = ns.COLORS.CYAN .. "[XR] " .. "|r" .. displayName
        end

        local reasonStr = ""
        if dupeReason then
            if st == "duplicate" then
                reasonStr = ns.COLORS.GRAY .. dupeReason .. "|r"
            elseif st == "update" then
                reasonStr = ns.COLORS.YELLOW .. dupeReason .. "|r"
            end
        end

        -- Show buy realm as reason context for cross-realm flips
        if isCrossRealm and item.buyRealm and reasonStr == "" then
            reasonStr = ns.COLORS.CYAN .. "buy@" .. item.buyRealm .. "|r"
        end

        -- Price display: show buy price for cross-realm flips
        local priceDisplay = item.expectedPrice or ""
        if isCrossRealm and item.buyPrice then
            priceDisplay = item.buyPrice
        end

        -- Realm display
        local realmDisplay = item.targetRealm or ""

        -- Build tooltip
        local tooltipExtra = ""
        if isCrossRealm then
            tooltipExtra = "Cross-realm flip"
                .. "\nBuy on: " .. (item.buyRealm or "?") .. "  @  " .. (item.buyPrice or "?")
                .. "\nSell on: " .. (item.targetRealm or "?") .. "  @  " .. (item.expectedPrice or "?")
                .. (item.profitAmount and ("\nProfit: " .. item.profitAmount) or "")
                .. (item.profitPct and (" (" .. item.profitPct .. "%)") or "")
        else
            tooltipExtra = (item.targetRealm and item.targetRealm ~= "" and ("Sell on: " .. item.targetRealm) or "")
                .. (item.expectedPrice and item.expectedPrice ~= "" and ("\nPrice: " .. item.expectedPrice) or "")
        end
        if st == "duplicate" then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.GRAY .. "Already in queue (" .. (dupeReason or "exact match") .. ") — will be skipped|r"
        elseif st == "update" then
            tooltipExtra = tooltipExtra .. "\n" .. ns.COLORS.YELLOW .. "Will update existing entry (" .. (dupeReason or "match") .. ")|r"
        end

        table.insert(data, {
            status   = statusStr,
            name     = displayName,
            realm    = realmDisplay,
            price    = priceDisplay,
            qty      = item.quantity or 1,
            reason   = reasonStr,
            _sortStatus = statusSort,
            _tooltipText = item.name,
            _tooltipExtra = tooltipExtra,
            _rowColor = isCrossRealm and {0.1, 0.3, 0.5, 0.08} or nil,
        })
    end

    UI.importPreviewTable:SetData(data)

    UI.importPreviewTable.headerFrame:Show()
    UI.importPreviewTable.scrollFrame:Show()

    local parts = {}
    if newCount > 0 then table.insert(parts, ns.COLORS.GREEN .. newCount .. " new|r") end
    if updateCount > 0 then table.insert(parts, ns.COLORS.YELLOW .. updateCount .. " updates|r") end
    if dupCount > 0 then table.insert(parts, ns.COLORS.GRAY .. dupCount .. " dupes|r") end
    importStatus:SetText(table.concat(parts, "  ") .. "  — click Import to confirm")
end

-- ==========================================
-- EXPOSE REFERENCES
-- ==========================================

-- Register with MainFrame's table hide system
if UI._RegisterTable then UI._RegisterTable(UI.importPreviewTable) end

UI._importPage = importPage
UI._importEdit = importEdit
UI._importStatus = importStatus
UI._importPreviewData = function() return importPreviewData end
UI._importPreviewClear = function()
    importPreviewData = nil
    importPreviewResults = nil
    importLastLen = 0
end
UI._importSetPreview = function(items, results)
    importPreviewData = items
    importPreviewResults = results
end

-- ==========================================
-- REFRESH
-- ==========================================

function UI:RefreshImportPage()
    local mainFrame = UI.mainFrame
    mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Import" .. "|r")
    UI._LayoutActionBtns(mainFrame.actionBtns.importClear, mainFrame.actionBtns.importDo, mainFrame.actionBtns.importPreview)
    importPage:Show()
    -- Restore checkbox states from settings
    importAutoGenCheck:SetChecked(ns.db.settings.importAutoGenerate or false)
    importSkipCheck:SetChecked(ns.db.settings.importAutoImport or false)
    -- Show preview table if we have data
    if UI._importPreviewData() then
        UI.importPreviewTable.headerFrame:Show()
        UI.importPreviewTable.scrollFrame:Show()
    end
    UI._importEdit:SetFocus(true)
    mainFrame.statusText:SetText("Paste FlippingPal website, CSV, or tab-delimited data")
end
