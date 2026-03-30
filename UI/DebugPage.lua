-- UI/DebugPage.lua
-- Task Debug view: shows deal phases, task relationships, and internal state
-- Helps users understand why tasks are in certain states
local addonName, ns = ...

local UI = ns.UI

-- ==========================================
-- DEBUG TABLE COLUMNS
-- ==========================================

local DEBUG_COLUMNS = {
    {key = "name",      label = "Item",       width = 140, sortable = true},
    {key = "action",    label = "Action",     width = 45,  align = "CENTER", sortable = true},
    {key = "phase",     label = "Phase",      width = 70,  align = "CENTER", sortable = true},
    {key = "status",    label = "Status",     width = 55,  align = "CENTER", sortable = true},
    {key = "source",    label = "Source",     width = 65,  align = "CENTER", sortable = true},
    {key = "assignee",  label = "Assignee",   width = 80,  sortable = true},
    {key = "deposit",   label = "Deposit",    width = 80,  sortable = true},
    {key = "realm",     label = "Realm",      width = 100, sortable = true},
    {key = "chain",     label = "Chain",      width = 45,  align = "CENTER", sortable = true},
}

-- ==========================================
-- PAGE FRAME
-- ==========================================

local debugPage = CreateFrame("Frame", nil, UI.tableContainer)
debugPage:SetAllPoints()
debugPage:Hide()
UI._debugPage = debugPage

-- ==========================================
-- SCROLL TABLE
-- ==========================================

UI.debugTable = UI:CreateScrollTable(debugPage, DEBUG_COLUMNS)
UI.debugTable:SetSort("chain", true)
if UI._RegisterTable then UI._RegisterTable(UI.debugTable) end

-- ==========================================
-- DATA BUILDER
-- ==========================================

-- Build debug data showing all tasks with internal state
local function BuildDebugData()
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then return {} end

    local LookupItemInfo = UI._LookupItemInfo
    local QualityColorName = UI._QualityColorName
    local CLASS_COLORS = UI._CLASS_COLORS or {}
    local current = ns.db.todoLists.active
    if not current.tasks then return {} end

    -- Build deal chains: group buy+sell tasks by item+realm
    local chains = {} -- "itemkey|realm" -> chain_id
    local chainCounter = 0
    for _, task in ipairs(current.tasks) do
        local key = ((task.itemKey or task.name or ""):lower()) .. "|" .. (task.targetRealm or ""):lower()
        if not chains[key] then
            chainCounter = chainCounter + 1
            chains[key] = chainCounter
        end
    end

    local data = {}
    for taskIdx, task in ipairs(current.tasks) do
        local displayName = task.name or "?"
        local lookupIcon, quality
        pcall(function()
            lookupIcon, quality = LookupItemInfo(task.itemID, task.itemKey, task.name)
        end)
        if quality then
            displayName = QualityColorName(displayName, quality)
        elseif task.quality and task.quality ~= "" then
            displayName = QualityColorName(displayName, task.quality)
        end

        -- Action type
        local actionStr
        if task.action == "buy" then
            actionStr = ns.COLORS.CYAN .. "Buy" .. "|r"
        else
            actionStr = ns.COLORS.GREEN .. "Sell" .. "|r"
        end

        -- Current phase from steps
        local phaseStr = ns.COLORS.GRAY .. "?" .. "|r"
        local stepType = nil
        if task.steps and task.currentStep then
            local step = task.steps[task.currentStep]
            if step then
                stepType = step.type
                if step.type == "retrieve" then
                    phaseStr = ns.COLORS.YELLOW .. "Retrieve" .. "|r"
                elseif step.type == "post" then
                    phaseStr = ns.COLORS.GREEN .. "Post" .. "|r"
                elseif step.type == "collect" then
                    phaseStr = ns.COLORS.ORANGE .. "Collect" .. "|r"
                elseif step.type == "browse" then
                    phaseStr = ns.COLORS.CYAN .. "Browse" .. "|r"
                elseif step.type == "buy" then
                    phaseStr = ns.COLORS.CYAN .. "Buy" .. "|r"
                elseif step.type == "deposit" then
                    phaseStr = ns.COLORS.BLUE .. "Deposit" .. "|r"
                else
                    phaseStr = step.type
                end
            end
            if task.currentStep > #task.steps then
                phaseStr = ns.COLORS.GRAY .. "Done" .. "|r"
            end
        end

        -- Status
        local statusStr
        if task.status == "pending" then
            if task.deferredAt then
                statusStr = ns.COLORS.ORANGE .. "Wait" .. "|r"
            else
                statusStr = ns.COLORS.GREEN .. "Ready" .. "|r"
            end
        elseif task.status == "posted" then
            statusStr = ns.COLORS.GRAY .. "Posted" .. "|r"
        elseif task.status == "skipped" then
            statusStr = ns.COLORS.RED .. "Skip" .. "|r"
        else
            statusStr = task.status or "?"
        end

        -- Source
        local sourceStr
        local src = task.source or ""
        if src == "warbank" then
            sourceStr = ns.COLORS.YELLOW .. "warbank" .. "|r"
        elseif src == "bags" then
            sourceStr = ns.COLORS.GREEN .. "bags" .. "|r"
        elseif src == "bank" then
            sourceStr = ns.COLORS.BLUE .. "bank" .. "|r"
        elseif src == "reagent" then
            sourceStr = ns.COLORS.BLUE .. "reagent" .. "|r"
        elseif src == "unavailable" then
            sourceStr = ns.COLORS.RED .. "n/a" .. "|r"
        else
            sourceStr = src ~= "" and src or ns.COLORS.GRAY .. "-" .. "|r"
        end

        -- Assignee (colored by class)
        local assignStr = ""
        if task.assignedChar then
            local name = task.assignedChar:match("^(.-)%-") or task.assignedChar
            local charData = ns.db.characters and ns.db.characters[task.assignedChar]
            local classColor = charData and CLASS_COLORS[charData.class] or "888888"
            assignStr = "|cff" .. classColor .. name .. "|r"
        end

        -- Deposit info
        local depositStr = ""
        if task.depositFrom and task.depositFrom ~= "" then
            local depName = task.depositFrom:match("^(.-)%-") or task.depositFrom
            local depData = ns.db.characters and ns.db.characters[task.depositFrom]
            local depColor = depData and CLASS_COLORS[depData.class] or "888888"
            depositStr = ns.COLORS.ORANGE .. "from " .. "|cff" .. depColor .. depName .. "|r"
        end
        if task.blockedBy and task.blockedBy ~= "" and task.blockedBy ~= task.depositFrom then
            local blkName = task.blockedBy:match("^(.-)%-") or task.blockedBy
            depositStr = depositStr .. (depositStr ~= "" and " " or "")
                .. ns.COLORS.RED .. "blk:" .. blkName .. "|r"
        end

        -- Chain ID
        local chainKey = ((task.itemKey or task.name or ""):lower()) .. "|" .. (task.targetRealm or ""):lower()
        local chainID = chains[chainKey] or 0

        -- Tooltip with full internal state
        local tooltipLines = {
            "Task #" .. taskIdx,
            "Item Key: " .. (task.itemKey or "nil"),
            "Item ID: " .. (task.itemID or "nil"),
            "Action: " .. (task.action or "sell"),
            "Deal Type: " .. (task.dealType or "n/a"),
            "Status: " .. (task.status or "nil"),
            "Source: " .. (task.source or "nil"),
            "Quantity: " .. (task.quantity or 1),
            "",
            "Assigned: " .. (task.assignedChar or "nil"),
            "Target Realm: " .. (task.targetRealm or "nil"),
            "Buy Realm: " .. (task.buyRealm or "n/a"),
            "",
            "depositFrom: " .. (task.depositFrom or "nil"),
            "depositLocation: " .. (task.depositLocation or "nil"),
            "blockedBy: " .. (task.blockedBy or "nil"),
            "deferredAt: " .. (task.deferredAt and date("%m/%d %H:%M", task.deferredAt) or "nil"),
            "failReason: " .. (task.failReason or "nil"),
            "",
            "Current Step: " .. (task.currentStep or "nil") .. "/" .. (task.steps and #task.steps or "?"),
        }
        if task.steps then
            for si, step in ipairs(task.steps) do
                local marker = si == task.currentStep and " >>>" or "    "
                table.insert(tooltipLines, marker .. " " .. si .. ". " .. step.type
                    .. " [" .. (step.status or "?") .. "]"
                    .. (step.from and (" from:" .. step.from) or "")
                    .. (step.to and (" to:" .. step.to) or ""))
            end
        end
        table.insert(tooltipLines, "")
        table.insert(tooltipLines, "Import: " .. (task.importSource or "nil") .. " / " .. (task.importKey or "nil"))
        table.insert(tooltipLines, "Chain #" .. chainID)

        table.insert(data, {
            name     = displayName,
            action   = actionStr,
            phase    = phaseStr,
            status   = statusStr,
            source   = sourceStr,
            assignee = assignStr,
            deposit  = depositStr,
            realm    = task.targetRealm or "",
            chain    = tostring(chainID),
            _icon    = lookupIcon,
            _sortStatus = task.status == "pending" and (task.deferredAt and 2 or 1) or 3,
            _sortChain = chainID,
            _tooltipText = task.name or "?",
            _tooltipExtra = table.concat(tooltipLines, "\n"),
            _tooltipItemID = task.itemID and tonumber(task.itemID) or nil,
        })
    end

    return data
end

-- ==========================================
-- REFRESH
-- ==========================================

function UI:RefreshDebugPage()
    local mainFrame = self.mainFrame
    mainFrame.pageTitle:SetText(ns.COLORS.YELLOW .. "Task Debug" .. "|r")
    self._HideAllActionBtns()

    debugPage:Show()
    self._ShowTable(self.debugTable)

    local data = BuildDebugData()
    self.debugTable:SetData(data)

    -- Summary stats
    local total = #data
    local ready, waiting, posted, other = 0, 0, 0, 0
    local depositCount, blockedCount = 0, 0
    if ns.db and ns.db.todoLists and ns.db.todoLists.active and ns.db.todoLists.active.tasks then
        for _, task in ipairs(ns.db.todoLists.active.tasks) do
            if task.status == "pending" then
                if task.deferredAt then waiting = waiting + 1
                else ready = ready + 1 end
            elseif task.status == "posted" then
                posted = posted + 1
            else
                other = other + 1
            end
            if task.depositFrom and task.depositFrom ~= "" then depositCount = depositCount + 1 end
            if task.blockedBy and task.blockedBy ~= "" then blockedCount = blockedCount + 1 end
        end
    end

    local parts = {total .. " tasks"}
    if ready > 0 then table.insert(parts, ns.COLORS.GREEN .. ready .. " ready|r") end
    if waiting > 0 then table.insert(parts, ns.COLORS.ORANGE .. waiting .. " waiting|r") end
    if posted > 0 then table.insert(parts, ns.COLORS.GRAY .. posted .. " posted|r") end
    if depositCount > 0 then table.insert(parts, ns.COLORS.CYAN .. depositCount .. " deposits|r") end
    if blockedCount > 0 then table.insert(parts, ns.COLORS.RED .. blockedCount .. " blocked|r") end
    mainFrame.statusText:SetText(table.concat(parts, "  |  ") .. "  |  Hover for full state")
end
