-- UI/MinimapButton.lua
-- Minimap icon button: left-click opens main window, right-click opens settings
-- Parents to Minimap's parent to avoid clipping by square minimap addons
local addonName, ns = ...

local UI = ns.UI

local ICON_SIZE = 31
local ICON_TEXTURE = "Interface\\AddOns\\flipqueue\\Art\\flipqueue-icon"

--------------------------
-- Square minimap detection
--------------------------

local function IsSquareMinimap()
    if type(GetMinimapShape) == "function" then
        local shape = GetMinimapShape()
        if shape and shape ~= "ROUND" then
            return true
        end
    end
    return false
end

--------------------------
-- Create the minimap button
-- Parent to Minimap's parent to avoid clip masking
--------------------------

local btn = CreateFrame("Button", "FlipQueueMinimapButton", Minimap:GetParent() or Minimap)
btn:SetSize(ICON_SIZE, ICON_SIZE)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(9)
btn:SetClampedToScreen(true)
btn:SetMovable(true)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Icon texture
local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(18, 18)
icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
icon:SetTexture(ICON_TEXTURE)

-- Border overlay — anchored at TOPLEFT like Blizzard's tracking button
local border = btn:CreateTexture(nil, "OVERLAY")
border:SetSize(52, 52)
border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- Background circle behind icon
local bg = btn:CreateTexture(nil, "BACKGROUND")
bg:SetSize(18, 18)
bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
bg:SetColorTexture(0, 0, 0, 0.6)

--------------------------
-- Position on minimap edge
--------------------------

local function UpdatePosition(angle)
    local halfWidth = Minimap:GetWidth() / 2
    local dist = halfWidth

    local x = math.cos(angle) * dist
    local y = math.sin(angle) * dist

    -- For square minimaps, project onto the square perimeter
    if IsSquareMinimap() then
        local absX, absY = math.abs(x), math.abs(y)
        local furthest = math.max(absX, absY)
        if furthest > 0 then
            local scale = dist / furthest
            x = x * scale
            y = y * scale
        end
    end

    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function GetAngleFromCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    return math.atan2(cy - my, cx - mx)
end

-- Dragging
btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local angle = GetAngleFromCursor()
        UpdatePosition(angle)
        if ns.db then
            ns.db.settings.minimapAngle = angle
        end
    end)
end)

btn:SetScript("OnDragStop", function(self)
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
        if ns.db.settings.minimapAngle == nil then
            ns.db.settings.minimapAngle = 3.5
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

-- Reposition when minimap resizes
Minimap:HookScript("OnSizeChanged", function()
    if ns.db and ns.db.settings.minimapAngle then
        UpdatePosition(ns.db.settings.minimapAngle)
    end
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
