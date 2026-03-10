-- UI/MinimapButton.lua
-- Minimap icon button: left-click opens main window, right-click opens settings
local addonName, ns = ...

local UI = ns.UI

local ICON_SIZE = 32
local ICON_TEXTURE = "Interface\\Icons\\INV_Misc_Coin_02"

-- Create the minimap button
local btn = CreateFrame("Button", "FlipQueueMinimapButton", Minimap)
btn:SetSize(ICON_SIZE, ICON_SIZE)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:SetClampedToScreen(true)
btn:SetMovable(true)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Icon texture
local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 0)
icon:SetTexture(ICON_TEXTURE)

-- Border overlay (looks like other minimap buttons)
local border = btn:CreateTexture(nil, "OVERLAY")
border:SetSize(54, 54)
border:SetPoint("CENTER", 0, 0)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- Background
local bg = btn:CreateTexture(nil, "BACKGROUND")
bg:SetSize(24, 24)
bg:SetPoint("CENTER", 0, 0)
bg:SetColorTexture(0, 0, 0, 0.6)

--------------------------
-- Position on minimap edge
--------------------------

local function UpdatePosition(angle)
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function GetAngleFromPosition()
    local cx, cy = Minimap:GetCenter()
    local bx, by = btn:GetCenter()
    if not cx or not bx then return 3.5 end -- default angle
    return math.atan2(by - cy, bx - cx)
end

-- Dragging
local isDragging = false

btn:SetScript("OnDragStart", function(self)
    isDragging = true
    self:SetScript("OnUpdate", function(self)
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.atan2(cy - my, cx - mx)
        UpdatePosition(angle)
        if ns.db then
            ns.db.settings.minimapAngle = angle
        end
    end)
end)

btn:SetScript("OnDragStop", function(self)
    isDragging = false
    self:SetScript("OnUpdate", nil)
end)

-- Click handlers
btn:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
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
end)

-- Tooltip
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("FlipQueue", 1, 0.82, 0)
    local pending = ns.Queue and ns.Queue:GetPendingCount() or 0
    local logCount = ns.db and #ns.db.log or 0
    if pending > 0 then
        GameTooltip:AddLine(pending .. " items in queue", 1, 1, 0)
    end
    if logCount > 0 then
        GameTooltip:AddLine(logCount .. " posted", 0, 1, 0)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: Toggle window", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: Settings", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: Move icon", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

--------------------------
-- Init position on login
--------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(1, function()
        ns:InitDB()
        -- Default settings
        if ns.db.settings.minimapAngle == nil then
            ns.db.settings.minimapAngle = 3.5 -- ~200 degrees, top-right area
        end
        if ns.db.settings.showMinimap == nil then
            ns.db.settings.showMinimap = true
        end

        UpdatePosition(ns.db.settings.minimapAngle)

        if ns.db.settings.showMinimap then
            btn:Show()
        else
            btn:Hide()
        end
    end)
end)

-- API for hiding/showing
function UI:ShowMinimapButton()
    btn:Show()
    if ns.db then ns.db.settings.showMinimap = true end
end

function UI:HideMinimapButton()
    btn:Hide()
    if ns.db then ns.db.settings.showMinimap = false end
end

function UI:ToggleMinimapButton()
    if btn:IsShown() then
        self:HideMinimapButton()
    else
        self:ShowMinimapButton()
    end
end
