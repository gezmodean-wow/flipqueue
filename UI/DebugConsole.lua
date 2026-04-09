-- UI/DebugConsole.lua
-- In-game debug console: buttons to fire UI tests + live debug log view.
-- Open with /fq debug or /fq debug console.
local addonName, ns = ...

local UI = ns.UI
local console = nil

local CONSOLE_WIDTH  = 460
local CONSOLE_HEIGHT = 520
local LOG_LINE_HEIGHT = 12

--------------------------
-- Helpers
--------------------------

local function MakeButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(150, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

-- Build a fake op array for the bank popup. Each op needs name, icon, quantity.
local function FakeOps(prefix, count)
    local arr = {}
    for i = 1, count do
        arr[i] = {
            op = "fake",
            name = prefix .. " item " .. i,
            icon = "Interface\\Icons\\INV_Misc_QuestionMark",
            quantity = (i % 5) + 1,
        }
    end
    return arr
end

--------------------------
-- Debug Action Registry
--------------------------

-- Each action: { label, run = function() ... end }
-- Add new entries here to surface new debug buttons in the console.
local actions = {
    {
        label = "Bank popup ×60",
        run = function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({
                    pulls    = FakeOps("Pull",    20),
                    deposits = FakeOps("Deposit", 20),
                    extras   = FakeOps("Extra",   20),
                }, function() ns:Print("Debug popup execute (no-op).") end)
            end
        end,
    },
    {
        label = "Bank popup ×6",
        run = function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({
                    pulls    = FakeOps("Pull",    2),
                    deposits = FakeOps("Deposit", 2),
                    extras   = FakeOps("Extra",   2),
                }, function() ns:Print("Debug popup execute (no-op).") end)
            end
        end,
    },
    {
        label = "Bank popup pulls only",
        run = function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({
                    pulls = FakeOps("Pull", 30),
                }, function() ns:Print("Debug popup execute (no-op).") end)
            end
        end,
    },
    {
        label = "Bank popup deposits only",
        run = function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({
                    deposits = FakeOps("Deposit", 30),
                }, function() ns:Print("Debug popup execute (no-op).") end)
            end
        end,
    },
    {
        label = "Bank popup extras only",
        run = function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({
                    extras = FakeOps("Extra", 30),
                }, function() ns:Print("Debug popup execute (no-op).") end)
            end
        end,
    },
    {
        label = "Bank popup gold only",
        run = function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({
                    goldWithdraw = 1234567,
                    goldDeposit  = 9876543,
                }, function() ns:Print("Debug popup execute (no-op).") end)
            end
        end,
    },
    {
        label = "Toggle debug mode",
        run = function()
            if not ns.db then return end
            ns.db.settings.debugMessages = not ns.db.settings.debugMessages
            ns:Print("Debug messages: " .. (ns.db.settings.debugMessages
                and ns.COLORS.GREEN .. "ON" or ns.COLORS.RED .. "OFF") .. "|r")
            -- Refresh the status indicator if the console is open.
            if UI._RefreshDebugStatus then UI:_RefreshDebugStatus() end
        end,
    },
    {
        label = "Export FQ state",
        run = function()
            -- Reuse the existing /fq state pipeline so the format stays
            -- in sync with the slash command (one source of truth).
            if SlashCmdList and SlashCmdList.FLIPQUEUE then
                SlashCmdList.FLIPQUEUE("state")
            end
        end,
    },
    {
        label = "Copy debug log",
        run = function()
            local log = ns._debugLog or {}
            local text
            if #log == 0 then
                text = "(debug log empty)"
            else
                text = table.concat(log, "\n")
            end
            if UI.ShowExportPopup then
                UI:ShowExportPopup(text, #log .. " line(s) — Ctrl+A, Ctrl+C to copy")
            end
        end,
    },
    {
        label = "Emit test debug log",
        run = function()
            for i = 1, 10 do
                ns:PrintDebug("Test debug message #" .. i)
            end
        end,
    },
    {
        label = "Clear debug log",
        run = function()
            wipe(ns._debugLog or {})
            if UI._OnDebugLogAppend then UI:_OnDebugLogAppend() end
            ns:Print("Debug log cleared.")
        end,
    },
}

-- Public registration so other modules can add their own debug actions
-- without editing this file.
function UI:RegisterDebugAction(label, fn)
    if type(label) ~= "string" or type(fn) ~= "function" then return end
    table.insert(actions, { label = label, run = fn })
    if console and console:IsShown() then
        UI:_RebuildDebugButtons()
    end
end

--------------------------
-- Frame Construction
--------------------------

local function GetConsole()
    if console then return console end

    local f = CreateFrame("Frame", "FlipQueueDebugConsole", UIParent, "BackdropTemplate")
    f:SetSize(CONSOLE_WIDTH, CONSOLE_HEIGHT)
    -- Default to top-left so the console doesn't overlap the typical
    -- mini-view position (top-right). The frame is movable so the user
    -- can drag it elsewhere.
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120)
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
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    f:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)

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
    f.title:SetText(ns.COLORS.YELLOW .. "FlipQueue|r Debug Console")

    local closeBtn = CreateFrame("Button", nil, bar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:GetHighlightTexture():SetAlpha(0.3)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Status row: shows whether chat-output debug mode is on or off.
    local statusRow = CreateFrame("Frame", nil, f)
    statusRow:SetHeight(18)
    statusRow:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 4, -4)
    statusRow:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -4, -4)

    f.statusFS = statusRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.statusFS:SetPoint("LEFT", statusRow, "LEFT", 4, 0)

    -- Button area: grid of debug action buttons
    local btnArea = CreateFrame("Frame", nil, f)
    btnArea:SetPoint("TOPLEFT", statusRow, "BOTTOMLEFT", 0, -4)
    btnArea:SetPoint("TOPRIGHT", statusRow, "BOTTOMRIGHT", 0, -4)
    btnArea:SetHeight(180)
    f.btnArea = btnArea

    -- Log area (bottom): scrollable text view of recent debug messages
    local logLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logLabel:SetPoint("TOPLEFT", btnArea, "BOTTOMLEFT", 4, -4)
    logLabel:SetText(ns.COLORS.GRAY .. "Debug Log (live):|r")

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", logLabel, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 12)

    local logContent = CreateFrame("Frame", nil, scroll)
    logContent:SetSize(1, 1)
    scroll:SetScrollChild(logContent)
    f.logScroll = scroll
    f.logContent = logContent

    f.logFS = logContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.logFS:SetPoint("TOPLEFT", logContent, "TOPLEFT", 4, -2)
    f.logFS:SetPoint("TOPRIGHT", logContent, "TOPRIGHT", -4, -2)
    f.logFS:SetJustifyH("LEFT")
    f.logFS:SetJustifyV("TOP")
    f.logFS:SetWordWrap(true)
    f.logFS:SetSpacing(1)

    -- ESC closes
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    f:Hide()
    console = f
    return f
end

--------------------------
-- Button Grid + Log Updater
--------------------------

function UI:_RebuildDebugButtons()
    if not console then return end
    local area = console.btnArea
    if not area._buttons then area._buttons = {} end
    -- Hide existing buttons
    for _, b in ipairs(area._buttons) do b:Hide() end

    local cols = 2
    local btnW, btnH = 215, 22
    local padX, padY = 8, 6
    for i, action in ipairs(actions) do
        local b = area._buttons[i]
        if not b then
            b = MakeButton(area, action.label, action.run)
            area._buttons[i] = b
        else
            b:SetText(action.label)
            b:SetScript("OnClick", action.run)
        end
        b:SetSize(btnW, btnH)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", area, "TOPLEFT", col * (btnW + padX), -row * (btnH + padY))
        b:Show()
    end

    -- Resize the button area to fit the actual rows so the log scroll
    -- below has the right starting Y, regardless of how many actions
    -- have been registered.
    local rowCount = math.ceil(#actions / cols)
    local neededHeight = math.max(1, rowCount * (btnH + padY) + 4)
    area:SetHeight(neededHeight)
end

function UI:_RefreshDebugStatus()
    if not console then return end
    local on = ns.db and ns.db.settings.debugMessages
    local label
    if on then
        label = "Debug Mode: " .. ns.COLORS.GREEN .. "ON|r"
            .. ns.COLORS.GRAY .. "  (chat output enabled)|r"
    else
        label = "Debug Mode: " .. ns.COLORS.RED .. "OFF|r"
            .. ns.COLORS.GRAY .. "  (chat output suppressed; log still captured)|r"
    end
    console.statusFS:SetText(label)
end

local function FormatLogText()
    local log = ns._debugLog or {}
    -- Show the last N lines that fit roughly in the window
    local maxLines = 200
    local startIdx = math.max(1, #log - maxLines + 1)
    local lines = {}
    for i = startIdx, #log do
        lines[#lines + 1] = log[i]
    end
    return table.concat(lines, "\n")
end

function UI:_OnDebugLogAppend()
    if not (console and console:IsShown()) then return end
    console.logFS:SetText(FormatLogText())
    -- Resize the scroll child to fit the text
    local h = console.logFS:GetStringHeight() + 8
    console.logContent:SetHeight(math.max(h, console.logScroll:GetHeight()))
    console.logContent:SetWidth(console.logScroll:GetWidth())
    -- Auto-scroll to bottom
    local maxScroll = console.logScroll:GetVerticalScrollRange()
    console.logScroll:SetVerticalScroll(maxScroll)
end

--------------------------
-- Public API
--------------------------

function UI:ShowDebugConsole()
    local f = GetConsole()
    UI:_RebuildDebugButtons()
    UI:_RefreshDebugStatus()
    UI:_OnDebugLogAppend()
    f:Show()
    -- Initial scroll-to-bottom on next frame so the layout is settled.
    C_Timer.After(0, function()
        if console and console:IsShown() then UI:_OnDebugLogAppend() end
    end)
end

function UI:HideDebugConsole()
    if console then console:Hide() end
end

function UI:ToggleDebugConsole()
    if console and console:IsShown() then
        UI:HideDebugConsole()
    else
        UI:ShowDebugConsole()
    end
end
