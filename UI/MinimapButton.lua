-- UI/MinimapButton.lua
-- Minimap icon registered via Cogworks-1.0's RegisterCogMinimapButton, which
-- wraps LibDBIcon-1.0 and adds the suite-shared brass gear-ring border.
-- Per-cog identity comes from the inner glyph (Art/fq-inner.tga — gold FQ on
-- deep purple).
local addonName, ns = ...

local UI = ns.UI

local ICON_TEXTURE = "Interface\\AddOns\\flipqueue\\Art\\fq-inner"

--------------------------
-- LibDataBroker data object
--------------------------

local dataObject = {
    type = "data source",
    text = "FlipQueue",
    label = "FlipQueue",
    icon = ICON_TEXTURE,

    OnClick = function(self, button)
        if button == "MiddleButton" then
            UI:ToggleMini()
        elseif button == "RightButton" then
            UI.currentPage = "settings"
            UI.mainFrame:Show()
            UI:Refresh()
        else
            if UI.mainFrame:IsShown() then
                UI.mainFrame:Hide()
            else
                UI.mainFrame:Show()
                UI:Refresh()
            end
        end
    end,

    OnTooltipShow = function(tooltip)
        tooltip:SetText("FlipQueue", 1, 0.82, 0)
        local pending = ns:ImportGetCount("fpScanner")
        local logCount = ns.db and #ns.db.log or 0
        if pending > 0 then
            tooltip:AddLine(pending .. " imported deals", 1, 1, 0)
        end
        if logCount > 0 then
            tooltip:AddLine(logCount .. " posted", 0, 1, 0)
        end
        tooltip:AddLine(" ")
        tooltip:AddLine("Left-click: Toggle window", 0.7, 0.7, 0.7)
        tooltip:AddLine("Middle-click: Toggle mini view", 0.7, 0.7, 0.7)
        tooltip:AddLine("Right-click: Settings", 0.7, 0.7, 0.7)
        tooltip:AddLine("Drag: Move icon", 0.7, 0.7, 0.7)
    end,
}

--------------------------
-- Registration
--------------------------

local registered = false

local function RegisterIcon()
    if registered then return end

    local LibStub = _G.LibStub
    if not LibStub then return end

    local LDB = LibStub:GetLibrary("LibDataBroker-1.1", true)
    local LDBIcon = LibStub:GetLibrary("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return end

    -- Ensure DB is ready
    ns:InitDB()

    -- Migrate old settings to LibDBIcon format
    if not ns.db.settings.minimapIcon then
        ns.db.settings.minimapIcon = {}

        -- Migrate from old angle-based position
        if ns.db.settings.minimapAngle then
            -- Convert radians to degrees (LibDBIcon uses 0-360)
            ns.db.settings.minimapIcon.minimapPos = math.deg(ns.db.settings.minimapAngle) % 360
        end

        -- Migrate hide setting
        if ns.db.settings.showMinimap == false then
            ns.db.settings.minimapIcon.hide = true
        end
    end

    local broker = LDB:NewDataObject("FlipQueue", dataObject)

    local Cogworks = LibStub:GetLibrary("Cogworks-1.0", true)
    Cogworks:RegisterCogMinimapButton("FlipQueue", broker, ns.db.settings.minimapIcon)
    registered = true
end

--------------------------
-- Init on login
--------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(1, RegisterIcon)
end)

--------------------------
-- API (used by SettingsFrame and SlashCommands)
--------------------------

function UI:ShowMinimapButton()
    if not registered then return end
    local LDBIcon = _G.LibStub and _G.LibStub:GetLibrary("LibDBIcon-1.0", true)
    if LDBIcon then
        LDBIcon:Show("FlipQueue")
        if ns.db then ns.db.settings.minimapIcon.hide = false end
    end
end

function UI:HideMinimapButton()
    if not registered then return end
    local LDBIcon = _G.LibStub and _G.LibStub:GetLibrary("LibDBIcon-1.0", true)
    if LDBIcon then
        LDBIcon:Hide("FlipQueue")
        if ns.db then ns.db.settings.minimapIcon.hide = true end
    end
end

function UI:ToggleMinimapButton()
    if not registered then return end
    local LDBIcon = _G.LibStub and _G.LibStub:GetLibrary("LibDBIcon-1.0", true)
    if not LDBIcon then return end
    if LDBIcon:IsRegistered("FlipQueue") and ns.db then
        if ns.db.settings.minimapIcon.hide then
            self:ShowMinimapButton()
        else
            self:HideMinimapButton()
        end
    end
end

function UI:IsMinimapButtonShown()
    return ns.db and ns.db.settings.minimapIcon and not ns.db.settings.minimapIcon.hide
end
