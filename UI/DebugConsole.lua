-- UI/DebugConsole.lua
-- Thin wrapper around Cogworks' debug toolkit. Registers FlipQueue's actions
-- with cw:RegisterDebugAction and shows the cw:CreateDebugConsole frame keyed
-- to "FlipQueue". The chrome, log ring, action grid, status row, and toggle
-- button all live in the library — this file owns only FlipQueue-specific
-- action bodies and the slash-command entry points.
--
-- Open with /fq debug or /fq debug console.
local addonName, ns = ...

local UI = ns.UI
local cw = ns.cw

local consoleFrame  -- created lazily on first show

--------------------------
-- Helpers
--------------------------

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
-- Action Registry
--------------------------

-- Register FlipQueue's debug actions with Cogworks. The library's debug
-- console picks them up automatically and renders them in the Actions tab.
local function RegisterFlipQueueActions()
    if not cw or not cw.RegisterDebugAction then return end

    local actions = {
        { "Bank popup ×60", function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({
                    pulls    = FakeOps("Pull",    20),
                    deposits = FakeOps("Deposit", 20),
                    extras   = FakeOps("Extra",   20),
                }, function() ns:Print("Debug popup execute (no-op).") end)
            end
        end },
        { "Bank popup ×6", function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({
                    pulls    = FakeOps("Pull",    2),
                    deposits = FakeOps("Deposit", 2),
                    extras   = FakeOps("Extra",   2),
                }, function() ns:Print("Debug popup execute (no-op).") end)
            end
        end },
        { "Bank popup pulls only", function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({ pulls = FakeOps("Pull", 30) },
                    function() ns:Print("Debug popup execute (no-op).") end)
            end
        end },
        { "Bank popup deposits only", function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({ deposits = FakeOps("Deposit", 30) },
                    function() ns:Print("Debug popup execute (no-op).") end)
            end
        end },
        { "Bank popup extras only", function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({ extras = FakeOps("Extra", 30) },
                    function() ns:Print("Debug popup execute (no-op).") end)
            end
        end },
        { "Bank popup gold only", function()
            if UI.HideBankPopup then UI:HideBankPopup() end
            if UI.ShowBankPopup then
                UI:ShowBankPopup({
                    goldWithdraw = 1234567,
                    goldDeposit  = 9876543,
                }, function() ns:Print("Debug popup execute (no-op).") end)
            end
        end },
        { "Export FQ state", function()
            -- Reuse the existing /fq state pipeline so the format stays in
            -- sync with the slash command (one source of truth).
            if SlashCmdList and SlashCmdList.FLIPQUEUE then
                SlashCmdList.FLIPQUEUE("state")
            end
        end },
        { "Copy debug log", function()
            local log = cw and cw.GetDebugEntries and cw:GetDebugEntries("FlipQueue") or {}
            local versionLine
            if UI and UI.GetVersionLine then
                versionLine = UI:GetVersionLine()
            else
                versionLine = "FlipQueue v" .. (ns.VERSION or "dev")
            end
            local header = string.format(
                "=== %s — debug log ===\ncaptured: %s\n",
                versionLine, date("%Y-%m-%d %H:%M:%S"))
            local body = (#log == 0) and "(debug log empty)" or table.concat(log, "\n")
            local text = header .. "\n" .. body
            if UI.ShowExportPopup then
                UI:ShowExportPopup(text, #log .. " line(s) — Ctrl+A, Ctrl+C to copy")
            end
        end },
        { "Emit test debug log", function()
            for i = 1, 10 do
                ns:PrintDebug("Test debug message #" .. i)
            end
        end },
        { "Clear debug log", function()
            if cw and cw.ClearDebugLog then cw:ClearDebugLog("FlipQueue") end
            ns:Print("Debug log cleared.")
        end },
    }

    for _, entry in ipairs(actions) do
        cw:RegisterDebugAction("FlipQueue", entry[1], entry[2])
    end
end

-- Public registration so other modules can add their own debug actions
-- without editing this file. Backward-compatible with the pre-Cogworks API.
function UI:RegisterDebugAction(label, fn)
    if type(label) ~= "string" or type(fn) ~= "function" then return end
    if cw and cw.RegisterDebugAction then
        cw:RegisterDebugAction("FlipQueue", label, fn)
    end
end

--------------------------
-- Console Lifecycle
--------------------------

local function EnsureConsole()
    if consoleFrame then return consoleFrame end
    if not cw or not cw.CreateDebugConsole then return nil end

    -- Push the persisted debug-echo flag into Cogworks before the console
    -- renders its status row, so the "ON / OFF" label matches the saved
    -- preference on first open.
    if ns.db and ns.db.settings then
        ns:SetDebugEnabled(ns.db.settings.debugMessages and true or false)
    end

    -- Persist console geometry under ns.db.debugConsole.
    if ns.db then
        ns.db.debugConsole = ns.db.debugConsole or {}
    end

    consoleFrame = cw:CreateDebugConsole({
        cog       = "FlipQueue",
        width     = 460,
        height    = 520,
        savedvars = ns.db and ns.db.debugConsole or nil,
    })

    -- Mirror cw's runtime toggle state back to ns.db so the next session
    -- restores whatever the player last left it on. Hook OnHide so the
    -- write happens before SaveVariables fires at logout.
    if consoleFrame and consoleFrame.HookScript then
        consoleFrame:HookScript("OnHide", function()
            if ns.db and ns.db.settings and cw.IsDebugEnabled then
                ns.db.settings.debugMessages = cw:IsDebugEnabled("FlipQueue") and true or false
            end
        end)
    end

    return consoleFrame
end

function UI:ShowDebugConsole()
    local f = EnsureConsole()
    if f then f:Show() end
end

function UI:HideDebugConsole()
    if consoleFrame then consoleFrame:Hide() end
end

function UI:ToggleDebugConsole()
    if consoleFrame and consoleFrame:IsShown() then
        UI:HideDebugConsole()
    else
        UI:ShowDebugConsole()
    end
end

--------------------------
-- Init
--------------------------

RegisterFlipQueueActions()
