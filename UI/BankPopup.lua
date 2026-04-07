-- UI/BankPopup.lua
-- Bank operations popup — shows pending pulls, deposits, and gold ops
-- with a single Execute button (hardware event context for warbank taint bypass).
-- Unified progress bar tracks ALL operations across the full execution lifecycle.
local addonName, ns = ...

local UI = ns.UI
local popup = nil

local ROW_HEIGHT = 20
local ICON_SIZE = 16
local MAX_VISIBLE_ROWS = 12

-- Persistent execution state (survives popup rebuilds during pull iteration)
local execState = nil  -- { totalOps, completed, failed, phase }

--------------------------
-- Frame Construction
--------------------------

local function GetPopup()
    if popup then return popup end

    local f = CreateFrame("Frame", "FlipQueueBankPopup", UIParent, "BackdropTemplate")
    f:SetSize(320, 200)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    f:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    f:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)

    -- Position: attach to mini frame based on user setting, or standalone
    local function AttachToMini()
        f:ClearAllPoints()
        local mini = _G["FlipQueueMiniFrame"]
        if mini and mini:IsShown() then
            local anchor = ns.db and ns.db.settings.bankPopupAnchor or "below"
            if anchor == "above" then
                f:SetPoint("BOTTOMRIGHT", mini, "TOPRIGHT", 0, 4)
            elseif anchor == "left" then
                f:SetPoint("TOPRIGHT", mini, "TOPLEFT", -4, 0)
            elseif anchor == "right" then
                f:SetPoint("TOPLEFT", mini, "TOPRIGHT", 4, 0)
            else
                f:SetPoint("TOPRIGHT", mini, "BOTTOMRIGHT", 0, -4)
            end
        else
            f:SetPoint("TOP", UIParent, "TOP", 0, -100)
        end
    end
    f.AttachToMini = AttachToMini
    AttachToMini()

    -- Title bar
    local bar = CreateFrame("Frame", nil, f)
    bar:SetHeight(24)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.12, 0.12, 0.18, 1)

    f.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", bar, "LEFT", 8, 0)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, bar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:GetHighlightTexture():SetAlpha(0.3)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Progress bar (always under header, shows during execution and completion)
    local progressBar = CreateFrame("StatusBar", nil, f)
    progressBar:SetHeight(14)
    progressBar:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 4, -4)
    progressBar:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -4, -4)
    progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progressBar:SetStatusBarColor(0.26, 0.6, 1)
    progressBar:SetMinMaxValues(0, 1)
    progressBar:SetValue(0)
    progressBar:Hide()
    f.progressBar = progressBar

    local progressBg = progressBar:CreateTexture(nil, "BACKGROUND")
    progressBg:SetAllPoints()
    progressBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    f.progressText = progressBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.progressText:SetPoint("CENTER", progressBar, "CENTER")

    -- Content area (below progress bar when visible, else below header)
    local content = CreateFrame("Frame", nil, f)
    f.content = content

    local function UpdateContentAnchor()
        content:ClearAllPoints()
        if progressBar:IsShown() then
            content:SetPoint("TOPLEFT", progressBar, "BOTTOMLEFT", 0, -4)
            content:SetPoint("TOPRIGHT", progressBar, "BOTTOMRIGHT", 0, -4)
        else
            content:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 4, -4)
            content:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -4, -4)
        end
    end
    f.UpdateContentAnchor = UpdateContentAnchor
    UpdateContentAnchor()

    -- Row pool
    f.rows = {}

    -- Execute button
    local execBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    execBtn:SetHeight(26)
    execBtn:SetWidth(200)
    execBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    execBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    execBtn:SetBackdropColor(0.15, 0.3, 0.15, 1)
    execBtn:SetBackdropBorderColor(0.3, 0.5, 0.3, 0.8)

    execBtn.text = execBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    execBtn.text:SetPoint("CENTER")

    execBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
    execBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.3, 0.15, 1) end)
    f.execBtn = execBtn

    -- ESC to close
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    f:Hide()
    popup = f
    return f
end

local function GetOrCreateRow(parent, index)
    if parent.rows[index] then return parent.rows[index] end

    local row = CreateFrame("Frame", nil, parent.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent.content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", parent.content, "RIGHT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")

    parent.rows[index] = row
    return row
end

local function AddSectionHeader(f, index, text)
    local row = GetOrCreateRow(f, index)
    row.icon:SetTexture(nil)
    row.text:SetText(ns.COLORS.YELLOW .. text .. "|r")
    row:Show()
    return index + 1
end

local function AddItemRow(f, index, icon, name, detail)
    local row = GetOrCreateRow(f, index)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.text:SetText((name or "?") .. (detail and ("  " .. ns.COLORS.GRAY .. detail .. "|r") or ""))
    row:Show()
    return index + 1
end

local function ResizePopup(f, rowCount, hasButton, hasProgress)
    local contentHeight = math.min(rowCount, MAX_VISIBLE_ROWS) * ROW_HEIGHT
    f.content:SetHeight(contentHeight)
    local bottomHeight = 8
    if hasProgress then bottomHeight = bottomHeight + 20 end
    if hasButton then bottomHeight = bottomHeight + 36 end
    f:SetHeight(24 + 8 + contentHeight + bottomHeight)
end

--------------------------
-- Unified Progress Tracking
--------------------------

local function UpdateProgressBar(f)
    if not execState then return end
    local done = execState.completed + execState.failed
    local total = execState.totalOps
    f.progressBar:SetMinMaxValues(0, total)
    f.progressBar:SetValue(done)

    local phase = execState.phase or ""
    if phase ~= "" then phase = phase .. "  " end
    f.progressText:SetText(phase .. done .. " / " .. total)

    -- Color based on current phase
    if execState.phase == "Pulling" then
        f.progressBar:SetStatusBarColor(0.26, 0.6, 1)      -- blue
    elseif execState.phase == "Depositing" then
        f.progressBar:SetStatusBarColor(0.2, 0.8, 0.4)      -- green
    elseif execState.phase == "Gold" then
        f.progressBar:SetStatusBarColor(0.9, 0.75, 0.2)     -- gold
    elseif execState.phase == "Complete" then
        if execState.failed > 0 then
            f.progressBar:SetStatusBarColor(0.9, 0.5, 0.2)  -- orange
        else
            f.progressBar:SetStatusBarColor(0.2, 0.8, 0.4)  -- green
        end
    else
        f.progressBar:SetStatusBarColor(0.26, 0.6, 1)
    end

    f.progressBar:Show()
    f.UpdateContentAnchor()

    -- Mini rollout (only if popup not visible)
    if UI.ShowMiniProgress and not f:IsShown() then
        UI:ShowMiniProgress(done, total, phase)
    end
end

local function ShowCompletionSummary(f)
    if not execState then return end
    execState.phase = "Complete"
    UpdateProgressBar(f)

    -- Build summary in title
    local parts = {}
    if execState.completed > 0 then
        table.insert(parts, ns.COLORS.GREEN .. execState.completed .. " done|r")
    end
    if execState.failed > 0 then
        table.insert(parts, ns.COLORS.RED .. execState.failed .. " failed|r")
    end
    f.title:SetText(ns.COLORS.YELLOW .. "FlipQueue|r " .. table.concat(parts, ", "))

    -- Replace item rows with summary
    for _, row in pairs(f.rows) do row:Hide() end
    local idx = 1
    idx = AddSectionHeader(f, idx, "Operations complete")

    if execState._pulledNames then
        for _, name in ipairs(execState._pulledNames) do
            idx = AddItemRow(f, idx, "Interface\\RaidFrame\\ReadyCheck-Ready", name, "pulled")
        end
    end
    if execState._depositedCount and execState._depositedCount > 0 then
        idx = AddItemRow(f, idx, "Interface\\RaidFrame\\ReadyCheck-Ready",
            execState._depositedCount .. " item(s) deposited")
    end
    if execState._goldOps then
        for _, desc in ipairs(execState._goldOps) do
            idx = AddItemRow(f, idx, "Interface\\Icons\\INV_Misc_Coin_01", desc)
        end
    end
    if execState.failed > 0 then
        idx = AddItemRow(f, idx, "Interface\\RaidFrame\\ReadyCheck-NotReady",
            execState.failed .. " operation(s) failed", "check chat for details")
    end

    ResizePopup(f, idx - 1, false, true)
    -- Stays visible until bank closes (BANKFRAME_CLOSED calls HideBankPopup)
end

--------------------------
-- Public API
--------------------------

-- Begin tracking a new execution session with the total operation count.
-- Called once before the first ShowBankPopup during an execution cycle.
function UI:BeginBankExecution(totalOps)
    execState = {
        totalOps = totalOps,
        completed = 0,
        failed = 0,
        phase = "",
        _pulledNames = {},
        _depositedCount = 0,
        _goldOps = {},
    }
end

-- Record progress during execution (called by Tracker after each sub-operation)
function UI:BankOpProgress(successCount, failCount, phase, details)
    if not execState then return end
    execState.completed = execState.completed + successCount
    execState.failed = execState.failed + failCount
    if phase then execState.phase = phase end

    -- Track details for summary
    if phase == "Pulling" and details then
        for _, name in ipairs(details) do
            table.insert(execState._pulledNames, name)
        end
    elseif phase == "Depositing" then
        execState._depositedCount = execState._depositedCount + successCount
    elseif phase == "Gold" and details then
        for _, desc in ipairs(details) do
            table.insert(execState._goldOps, desc)
        end
    end

    if popup then UpdateProgressBar(popup) end
end

-- Show final completion summary
function UI:BankPopupComplete()
    if popup and popup:IsShown() and execState then
        ShowCompletionSummary(popup)
    else
        execState = nil
    end
    ns.BankQueue.onProgress = nil
    if UI.HideMiniProgress then UI:HideMiniProgress() end
end

function UI:ShowBankPopup(ops, onExecute)
    local f = GetPopup()
    f.AttachToMini()

    -- Hide all existing rows
    for _, row in pairs(f.rows) do row:Hide() end
    f.title:SetText(ns.COLORS.YELLOW .. "FlipQueue|r Bank Operations")

    -- If we're mid-execution, keep the progress bar showing
    local isExecuting = execState and execState.phase ~= "" and execState.phase ~= "Complete"
    if not isExecuting then
        f.progressBar:Hide()
    end

    local idx = 1
    local totalOps = 0
    local pullCount = ops.pulls and #ops.pulls or 0
    local depositCount = ops.deposits and #ops.deposits or 0
    local extraCount = ops.extras and #ops.extras or 0
    local goldCount = 0
    if ops.goldWithdraw and ops.goldWithdraw > 0 then goldCount = goldCount + 1 end
    if ops.goldDeposit and ops.goldDeposit > 0 then goldCount = goldCount + 1 end

    -- Pull section
    if pullCount > 0 then
        idx = AddSectionHeader(f, idx, "Pull from bank (" .. pullCount .. ")")
        for _, op in ipairs(ops.pulls) do
            idx = AddItemRow(f, idx, op.icon, op.name, "x" .. (op.quantity or 1))
            totalOps = totalOps + 1
        end
    end

    -- Deposit section
    if depositCount > 0 then
        idx = AddSectionHeader(f, idx, "Deposit to warbank (" .. depositCount .. ")")
        for _, op in ipairs(ops.deposits) do
            idx = AddItemRow(f, idx, op.icon, op.name, "x" .. (op.quantity or 1))
            totalOps = totalOps + 1
        end
    end

    -- Gold operations
    if ops.goldWithdraw and ops.goldWithdraw > 0 then
        idx = AddSectionHeader(f, idx, "Gold")
        local goldStr = ns.FormatGold and ns:FormatGold(ops.goldWithdraw) or (math.floor(ops.goldWithdraw / 10000) .. "g")
        idx = AddItemRow(f, idx, "Interface\\Icons\\INV_Misc_Coin_01", "Withdraw " .. goldStr, "for posting fees")
        totalOps = totalOps + 1
    end
    if ops.goldDeposit and ops.goldDeposit > 0 then
        if not (ops.goldWithdraw and ops.goldWithdraw > 0) then
            idx = AddSectionHeader(f, idx, "Gold")
        end
        local goldStr = ns.FormatGold and ns:FormatGold(ops.goldDeposit) or (math.floor(ops.goldDeposit / 10000) .. "g")
        idx = AddItemRow(f, idx, "Interface\\Icons\\INV_Misc_Coin_01", "Deposit " .. goldStr, "excess to warbank")
        totalOps = totalOps + 1
    end

    -- Deposit extras section
    if extraCount > 0 then
        idx = AddSectionHeader(f, idx, "Deposit extras (" .. extraCount .. ")")
        for _, op in ipairs(ops.extras) do
            idx = AddItemRow(f, idx, op.icon, op.name)
            totalOps = totalOps + 1
        end
    end

    if totalOps == 0 and not isExecuting then
        idx = AddSectionHeader(f, idx, "No pending operations")
    end

    -- If mid-execution, just update the progress bar and show
    if isExecuting then
        f.execBtn:Hide()
        UpdateProgressBar(f)
        ResizePopup(f, idx - 1, false, true)
        f:Show()
        return
    end

    -- Auto mode: execute immediately
    if ops.isAuto and totalOps > 0 then
        f.execBtn:Hide()
        execState.phase = "Starting"
        UpdateProgressBar(f)
        ResizePopup(f, idx - 1, false, true)
        f:Show()
        if onExecute then onExecute() end
    elseif totalOps > 0 then
        -- Manual mode: show button
        f.execBtn:Show()
        f.execBtn.text:SetText("Execute " .. totalOps .. " Operation(s)")
        f.execBtn:SetScript("OnClick", function()
            f.execBtn:Hide()
            if not execState then UI:BeginBankExecution(totalOps) end
            execState.phase = "Starting"
            UpdateProgressBar(f)
            ResizePopup(f, idx - 1, false, true)
            if onExecute then onExecute() end
        end)
        ResizePopup(f, idx - 1, true, isExecuting)
        f:Show()
    else
        f.execBtn:Hide()
        ResizePopup(f, idx - 1, false, isExecuting)
        f:Show()
    end
end

function UI:HideBankPopup()
    ns.BankQueue.onProgress = nil
    execState = nil
    if popup then popup:Hide() end
    if UI.HideMiniProgress then UI:HideMiniProgress() end
end

-- Check if execution is in progress (prevents re-initializing execState)
function UI:IsBankExecuting()
    return execState and execState.phase ~= "" and execState.phase ~= "Complete"
end
