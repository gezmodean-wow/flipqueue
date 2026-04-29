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
                -- Anchor below the context drawer if visible, otherwise
                -- below the mini directly.
                local drawerClip = _G["FlipQueueContextClip"]
                if drawerClip and drawerClip:IsShown() and drawerClip:GetHeight() > 1 then
                    f:SetPoint("TOPRIGHT", drawerClip, "BOTTOMRIGHT", 0, -4)
                else
                    f:SetPoint("TOPRIGHT", mini, "BOTTOMRIGHT", 0, -4)
                end
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

    -- Render-side smoothing (#127). UpdateProgressBar sets _targetValue from
    -- the data flow (onProgress ticks). OnUpdate lerps _currentValue toward
    -- _targetValue at a fixed rate so the visible fill keeps moving during
    -- the BAG_UPDATE_DELAYED gaps between ticks instead of stuttering. Tuned
    -- so each tick's worth of width change completes in ~200ms.
    progressBar._currentValue = 0
    progressBar._targetValue = 0
    progressBar._maxValue = 1
    -- Approach: exponential lerp toward target. Per-second smoothing factor
    -- chosen so we cover ~95% of the distance in 200ms (1 - 0.05^(dt/0.2)).
    local LERP_HALFLIFE = 0.06  -- seconds; lower = snappier, higher = smoother
    progressBar:SetScript("OnUpdate", function(self, delta)
        local cur = self._currentValue or 0
        local tgt = self._targetValue or 0
        if math.abs(cur - tgt) < 0.001 then
            if cur ~= tgt then
                self._currentValue = tgt
                self:SetValue(tgt)
            end
            return
        end
        -- Frame-rate independent exponential decay toward target.
        local alpha = 1 - math.exp(-delta / LERP_HALFLIFE)
        local newCur = cur + (tgt - cur) * alpha
        self._currentValue = newCur
        self:SetValue(newCur)
    end)

    local progressBg = progressBar:CreateTexture(nil, "BACKGROUND")
    progressBg:SetAllPoints()
    progressBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    f.progressText = progressBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.progressText:SetPoint("CENTER", progressBar, "CENTER")

    -- Heartbeat sub-bar overlaid on the bottom edge of the main bar. Now
    -- driven by BankQueue.onWait (#127): each timed wait inside ProcessSync
    -- (inter-move, verify, retry, panel-settle) fires the callback with its
    -- duration and a human-readable reason. The popup renders the heartbeat
    -- as a fill 0 → 100% over that duration and appends the reason to the
    -- progress text, so the player sees both how long the pause will be
    -- and what we're waiting for. Hidden when no wait is active.
    local heartbeat = CreateFrame("StatusBar", nil, progressBar)
    heartbeat:SetHeight(2)
    heartbeat:SetPoint("BOTTOMLEFT", progressBar, "BOTTOMLEFT", 0, 0)
    heartbeat:SetPoint("BOTTOMRIGHT", progressBar, "BOTTOMRIGHT", 0, 0)
    heartbeat:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    heartbeat:SetStatusBarColor(1, 1, 1, 0.55)
    heartbeat:SetMinMaxValues(0, 1)
    heartbeat:SetValue(0)
    heartbeat:Hide()
    heartbeat._duration = nil
    heartbeat._elapsed = 0
    heartbeat:SetScript("OnUpdate", function(self, delta)
        if not self._duration then return end
        self._elapsed = self._elapsed + delta
        local pct = math.min(1, self._elapsed / self._duration)
        self:SetValue(pct)
    end)
    f.heartbeat = heartbeat

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
    -- Drive the lerp target rather than the immediate fill value (#127). The
    -- progressBar's OnUpdate handler animates _currentValue → _targetValue so
    -- the bar keeps moving smoothly during BAG_UPDATE_DELAYED gaps between
    -- progress ticks. SetValue is still called on the same frame so the
    -- initial render isn't blank, but subsequent frames are driven by the
    -- lerp.
    if f.progressBar._maxValue ~= total then
        f.progressBar:SetMinMaxValues(0, total)
        f.progressBar._maxValue = total
        -- Clamp current to new range so a shrinking total doesn't strand the
        -- visible fill past the new max.
        if f.progressBar._currentValue > total then
            f.progressBar._currentValue = total
        end
    end
    f.progressBar._targetValue = done
    -- On the very first tick (current still at 0) snap immediately so we
    -- don't visibly crawl from 0 — the lerp is for between-tick smoothing,
    -- not for a slow start.
    if f.progressBar._currentValue == 0 and done == 0 then
        f.progressBar:SetValue(0)
    end

    local phase = execState.phase or ""
    if phase ~= "" then phase = phase .. "  " end
    local text = phase .. done .. " / " .. total
    -- Append the current wait reason if BeginHeartbeat has set one. Lets
    -- the player tell e.g. "we're verifying moves" from "we're between
    -- container ops" when otherwise the bar would just say "Pulling 97/97".
    if execState._waitLabel and execState._waitLabel ~= "" then
        text = text .. "  |cffaaaaaa(" .. execState._waitLabel .. ")|r"
    end
    f.progressText:SetText(text)

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

    -- Hide the heartbeat outright on completion regardless of any pending
    -- wait state — once the operation settles, the countdown is irrelevant.
    if f.heartbeat and execState.phase == "Complete" then
        f.heartbeat._duration = nil
        f.heartbeat:Hide()
        execState._waitLabel = nil
    end

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
            execState.failed .. " operation(s) failed",
            "reopen the bank to retry")
        -- Render each failed item by name so the player can see exactly
        -- which moves didn't go through (#127). Without this they only
        -- get the count and have to read chat to learn what's missing.
        if execState._failedNames then
            for _, name in ipairs(execState._failedNames) do
                idx = AddItemRow(f, idx, "Interface\\RaidFrame\\ReadyCheck-NotReady",
                    ns.COLORS.RED .. name .. "|r", "failed")
            end
        end
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
        _failedNames = {},
    }
    -- Reset the lerp bookkeeping so a new execution starts from an empty
    -- bar even if the previous one ended at full (#127).
    if popup and popup.progressBar then
        popup.progressBar._currentValue = 0
        popup.progressBar._targetValue = 0
        popup.progressBar._maxValue = totalOps
        popup.progressBar:SetMinMaxValues(0, totalOps)
        popup.progressBar:SetValue(0)
    end
end

-- Record progress during execution (called by Tracker after each sub-operation).
-- successCount may be negative — ProcessSync emits a compensation tick at the
-- end for ops that issued optimistically but failed verification (#127).
-- failedDetails is an optional list of failed item names; rendered as red
-- rows in the completion summary.
function UI:BankOpProgress(successCount, failCount, phase, details, failedDetails)
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

    if failedDetails then
        for _, name in ipairs(failedDetails) do
            table.insert(execState._failedNames, name)
        end
    end

    if popup then UpdateProgressBar(popup) end
end

-- Begin a definite-duration heartbeat. Called from BankQueue.onWait
-- subscribers each time ProcessSync enters a known timed wait (#127).
-- Resets the fill so consecutive short waits produce visible pulses.
function UI:BeginHeartbeat(duration, label)
    if not popup or not popup.heartbeat then return end
    if not duration or duration <= 0 then return end
    local hb = popup.heartbeat
    hb._duration = duration
    hb._elapsed = 0
    hb:SetValue(0)
    -- Don't show the heartbeat on the completion summary (phase=Complete
    -- means execution has settled and any further wait events are stragglers).
    if execState and execState.phase ~= "Complete" then
        hb:Show()
        execState._waitLabel = label or ""
        UpdateProgressBar(popup)
    end
end

-- Stop the heartbeat and clear its label. Called when BankPopupComplete
-- fires or the popup is hidden, so the bar doesn't keep ticking after the
-- operation settles.
function UI:EndHeartbeat()
    if popup and popup.heartbeat then
        popup.heartbeat._duration = nil
        popup.heartbeat:Hide()
    end
    if execState then
        execState._waitLabel = nil
        if popup then UpdateProgressBar(popup) end
    end
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
    -- Stop the wait countdown explicitly so the heartbeat doesn't keep
    -- ticking through any straggling wait events that fire after the final
    -- callback (verify-then-callback timing leaves a small window).
    UI:EndHeartbeat()
    ns.BankQueue.onWait = nil
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
    UI:EndHeartbeat()
    ns.BankQueue.onProgress = nil
    ns.BankQueue.onWait = nil
    execState = nil
    if popup then popup:Hide() end
    if UI.HideMiniProgress then UI:HideMiniProgress() end
end

-- Check if execution is in progress (prevents re-initializing execState)
function UI:IsBankExecuting()
    return execState and execState.phase ~= "" and execState.phase ~= "Complete"
end
