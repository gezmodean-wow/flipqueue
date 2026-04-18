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

    -- Position: attach to mini frame based on user setting, or standalone.
    -- When anchor mode is "below" (default) and the services drawer is visible,
    -- we anchor under the drawer instead of the mini so the popup doesn't overlap.
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
                -- Anchor below the mini. Shift down by the context drawer
                -- clip height so the popup doesn't cover it.
                local drawerClip = _G["FlipQueueContextClip"]
                local extraOffset = 0
                if drawerClip and drawerClip:IsShown() then
                    extraOffset = drawerClip:GetHeight() + 2
                end
                f:SetPoint("TOPRIGHT", mini, "BOTTOMRIGHT", 0, -4 - extraOffset)
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

    -- Content area: a ScrollFrame holding all rows. The visible window is
    -- clamped to MAX_VISIBLE_ROWS by ResizePopup; anything beyond scrolls
    -- via the mouse wheel.
    local scrollFrame = CreateFrame("ScrollFrame", nil, f)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetClipsChildren(true)
    f.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    f.content = content  -- rows still anchor to f.content

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step = ROW_HEIGHT * 2
        local maxScroll = math.max(0, self:GetVerticalScrollRange())
        local newScroll = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * step))
        self:SetVerticalScroll(newScroll)
    end)

    local function UpdateContentAnchor()
        scrollFrame:ClearAllPoints()
        if progressBar:IsShown() then
            scrollFrame:SetPoint("TOPLEFT", progressBar, "BOTTOMLEFT", 0, -4)
            scrollFrame:SetPoint("TOPRIGHT", progressBar, "BOTTOMRIGHT", 0, -4)
        else
            scrollFrame:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 4, -4)
            scrollFrame:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -4, -4)
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

-- Get current collapse state for a section key (or false if no key / no db).
local function IsCollapsed(sectionKey)
    if not sectionKey then return false end
    if not (ns.db and ns.db.settings.bankPopupCollapsed) then return false end
    return ns.db.settings.bankPopupCollapsed[sectionKey] and true or false
end

-- Clickable section header. If sectionKey is provided, the row toggles
-- the collapse state for that key on click and the popup re-renders.
-- A ▼/▶ marker indicates current state.
local function AddSectionHeader(f, index, text, sectionKey)
    local row = GetOrCreateRow(f, index)
    row.icon:SetTexture(nil)

    -- Use Blizzard's standard plus/minus button textures via inline escapes —
    -- consistent with the settings panel and works in every font.
    local marker = ""
    if sectionKey then
        if IsCollapsed(sectionKey) then
            marker = "|TInterface\\Buttons\\UI-PlusButton-Up:14:14:0:0|t "
        else
            marker = "|TInterface\\Buttons\\UI-MinusButton-Up:14:14:0:0|t "
        end
    end
    row.text:SetText(marker .. ns.COLORS.YELLOW .. text .. "|r")

    if sectionKey then
        row:EnableMouse(true)
        row:SetScript("OnMouseDown", function()
            if not (ns.db and ns.db.settings.bankPopupCollapsed) then return end
            local cur = ns.db.settings.bankPopupCollapsed[sectionKey] and true or false
            ns.db.settings.bankPopupCollapsed[sectionKey] = not cur
            -- Re-render with the cached ops/onExecute.
            if f._lastOps then
                UI:ShowBankPopup(f._lastOps, f._lastOnExecute)
            end
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(IsCollapsed(sectionKey)
                and "Click to expand" or "Click to collapse", 1, 1, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        -- Plain section header — clear any leaked click handler from
        -- a prior reuse of this row index.
        row:EnableMouse(false)
        row:SetScript("OnMouseDown", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
    end

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
    local visibleHeight = math.min(rowCount, MAX_VISIBLE_ROWS) * ROW_HEIGHT
    local fullHeight = math.max(rowCount * ROW_HEIGHT, 1)
    -- Scroll frame: the visible window. Width comes from its left/right anchors.
    f.scrollFrame:SetHeight(visibleHeight)
    -- Scroll child: the full row stack. Width must be set explicitly because
    -- a scroll child has no anchors of its own. Use the scroll frame's
    -- current width (set by its TOPLEFT/TOPRIGHT anchors).
    local childWidth = f.scrollFrame:GetWidth()
    if childWidth and childWidth > 0 then
        f.content:SetWidth(childWidth)
    end
    f.content:SetHeight(fullHeight)
    -- Reset to top whenever the row set changes so users always see the
    -- first section after a refresh.
    f.scrollFrame:SetVerticalScroll(0)

    local bottomHeight = 8
    if hasProgress then bottomHeight = bottomHeight + 20 end
    if hasButton then bottomHeight = bottomHeight + 36 end
    f:SetHeight(24 + 8 + visibleHeight + bottomHeight)
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
    if not execState then
        if ns.PrintDebug then ns:PrintDebug("[bank-popup] ShowCompletionSummary called with nil execState — bailing") end
        return
    end

    -- Defensive: if the running tally drifted from totalOps for any reason
    -- (optimistic reports, missed callbacks, retry races), the user would
    -- see "Operations complete" rows but a partial bar. Force the bar to
    -- show fully complete on transition. The diagnostic line below records
    -- the drift so we can chase any remaining root cause.
    local runningDone = execState.completed + execState.failed
    if runningDone < execState.totalOps then
        if ns.PrintDebug then
            ns:PrintDebug(string.format(
                "[bank-popup] ShowCompletionSummary: tally drift completed=%d failed=%d total=%d — forcing bar full",
                execState.completed, execState.failed, execState.totalOps))
        end
        -- Bring `done` up to total without disturbing the failed count, so
        -- the orange/green color logic in UpdateProgressBar still reflects
        -- whether any failures occurred.
        execState.completed = execState.totalOps - execState.failed
    elseif ns.PrintDebug then
        ns:PrintDebug(string.format(
            "[bank-popup] ShowCompletionSummary: tally OK completed=%d failed=%d total=%d",
            execState.completed, execState.failed, execState.totalOps))
    end

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
    if ns.PrintDebug then
        ns:PrintDebug(string.format("[bank-popup] BeginBankExecution totalOps=%d", totalOps or 0))
    end
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
    if not execState then
        if ns.PrintDebug then
            ns:PrintDebug(string.format(
                "[bank-popup] BankOpProgress(success=%d, fail=%d, phase=%s) IGNORED — execState is nil",
                successCount or 0, failCount or 0, tostring(phase)))
        end
        return
    end
    execState.completed = execState.completed + successCount
    execState.failed = execState.failed + failCount
    if phase then execState.phase = phase end
    if ns.PrintDebug then
        ns:PrintDebug(string.format(
            "[bank-popup] BankOpProgress(success=%d, fail=%d, phase=%s) -> completed=%d failed=%d total=%d",
            successCount or 0, failCount or 0, tostring(phase),
            execState.completed, execState.failed, execState.totalOps))
    end

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
    if ns.PrintDebug then
        local popupShown = popup and popup:IsShown()
        local hasState = execState ~= nil
        ns:PrintDebug(string.format(
            "[bank-popup] BankPopupComplete popupShown=%s execState=%s",
            tostring(popupShown), tostring(hasState)))
    end
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

    -- Cache the latest ops/callback so collapse-toggle click handlers can
    -- re-render via UI:ShowBankPopup(f._lastOps, f._lastOnExecute).
    f._lastOps = ops
    f._lastOnExecute = onExecute

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
        idx = AddSectionHeader(f, idx, "Pull from bank (" .. pullCount .. ")", "pulls")
        if not IsCollapsed("pulls") then
            for _, op in ipairs(ops.pulls) do
                idx = AddItemRow(f, idx, op.icon, op.name, "x" .. (op.quantity or 1))
            end
        end
        totalOps = totalOps + pullCount
    end

    -- Deposit section
    if depositCount > 0 then
        idx = AddSectionHeader(f, idx, "Deposit to warbank (" .. depositCount .. ")", "deposits")
        if not IsCollapsed("deposits") then
            for _, op in ipairs(ops.deposits) do
                idx = AddItemRow(f, idx, op.icon, op.name, "x" .. (op.quantity or 1))
            end
        end
        totalOps = totalOps + depositCount
    end

    -- Gold operations
    local hasGoldWithdraw = ops.goldWithdraw and ops.goldWithdraw > 0
    local hasGoldDeposit = ops.goldDeposit and ops.goldDeposit > 0
    if hasGoldWithdraw or hasGoldDeposit then
        idx = AddSectionHeader(f, idx, "Gold", "gold")
        if not IsCollapsed("gold") then
            if hasGoldWithdraw then
                local goldStr = ns.FormatGold and ns:FormatGold(ops.goldWithdraw) or (math.floor(ops.goldWithdraw / 10000) .. "g")
                local goldLabel = ops.hasBuyCosts and "for fees + purchases" or "for posting fees"
                idx = AddItemRow(f, idx, "Interface\\Icons\\INV_Misc_Coin_01", "Withdraw " .. goldStr, goldLabel)
            end
            if hasGoldDeposit then
                local goldStr = ns.FormatGold and ns:FormatGold(ops.goldDeposit) or (math.floor(ops.goldDeposit / 10000) .. "g")
                idx = AddItemRow(f, idx, "Interface\\Icons\\INV_Misc_Coin_01", "Deposit " .. goldStr, "excess to warbank")
            end
        end
        if hasGoldWithdraw then totalOps = totalOps + 1 end
        if hasGoldDeposit then totalOps = totalOps + 1 end
    end

    -- Deposit extras section
    if extraCount > 0 then
        idx = AddSectionHeader(f, idx, "Deposit extras (" .. extraCount .. ")", "extras")
        if not IsCollapsed("extras") then
            for _, op in ipairs(ops.extras) do
                idx = AddItemRow(f, idx, op.icon, op.name)
            end
        end
        totalOps = totalOps + extraCount
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
