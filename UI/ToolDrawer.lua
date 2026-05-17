-- UI/ToolDrawer.lua
-- Left-extending tools drawer for the mini overlay (FQ-005 / issue #115).
--
-- The drawer is an ordered list of tools sourced from ns.ToolRegistry. Each
-- tool is a Service (summon + rollout sub-drawer + find button), an Action
-- (Logout / Reload), or a Macro (a native WoW macro the player picked).
-- This file owns all frames, the open/close animation, the float-out
-- rollout, location learning, and the find-nearest routing. The tool model,
-- summon resolution, and configuration live in UI/ToolRegistry.lua.
local addonName, ns = ...

local UI = ns.UI
local TR = ns.ToolRegistry

-- Event-driven service state. More reliable than polling BankFrame:IsShown()
-- which can be wrong if another addon keeps the frame around. Exported for
-- ContextDrawer and the registry's inServiceCheck closures.
local serviceState = {
    mailOpen = false,
    auctionOpen = false,
    bankOpen = false,
}
ns._serviceState = serviceState

--------------------------
-- Drawer constants
--------------------------

local THUMB_WIDTH    = 14
local ICON_SIZE      = 40
local FIND_WIDTH     = 16
local GAP            = 4    -- icon -> find button
local PAD            = 6
local ICON_SPACING   = 6
local HEADER_HEIGHT  = 18
local CONTENT_WIDTH  = PAD + ICON_SIZE + GAP + FIND_WIDTH + PAD   -- 72
local FULL_WIDTH     = CONTENT_WIDTH + THUMB_WIDTH                 -- 86
local ANIM_DURATION  = 0.15

local function RowYOffset(index)
    return -(HEADER_HEIGHT + (index - 1) * (ICON_SIZE + ICON_SPACING))
end

local function ContentHeightFor(count)
    if count < 1 then count = 1 end
    return HEADER_HEIGHT + count * ICON_SIZE + (count - 1) * ICON_SPACING + PAD
end

local DRAWER_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local BUTTON_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

--------------------------
-- Location learning
--------------------------

-- Timestamp of the last summon click. Used to suppress recording
-- player-spawned temporary mailbox / bank locations as fixed ones.
local lastSummonClickTime = 0
local SUMMON_SUPPRESS_WINDOW = 120  -- seconds

-- Record the player's current position as a known service location.
-- Deduplicates by proximity (within 2% map distance of an existing entry).
local function LearnCurrentLocation(serviceKey)
    if not ns.db then return end
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local px, py = pos:GetXY()
    if not px or px == 0 then return end
    if GetTime() - lastSummonClickTime < SUMMON_SUPPRESS_WINDOW then return end

    ns.db.knownLocations = ns.db.knownLocations or {}
    local db = ns.db.knownLocations
    db[serviceKey] = db[serviceKey] or {}
    db[serviceKey][mapID] = db[serviceKey][mapID] or {}
    local mapLocs = db[serviceKey][mapID]

    local DEDUP = 0.02
    for _, loc in ipairs(mapLocs) do
        local dx, dy = loc.x - px, loc.y - py
        if dx * dx + dy * dy < DEDUP * DEDUP then return end
    end
    if #mapLocs >= 15 then return end

    local mapInfo = C_Map.GetMapInfo(mapID)
    mapLocs[#mapLocs + 1] = { x = px, y = py, zoneName = mapInfo and mapInfo.name or "Unknown" }
end

local function GetLearnedLocations(serviceKey, mapID)
    if not (ns.db and ns.db.knownLocations) then return {} end
    local db = ns.db.knownLocations[serviceKey]
    if not db then return {} end
    local results = {}
    local maps = mapID and { [mapID] = db[mapID] } or db
    for mID, locs in pairs(maps) do
        if type(locs) == "table" then
            for _, loc in ipairs(locs) do
                results[#results + 1] = {
                    map = mID, x = loc.x, y = loc.y,
                    zoneName = loc.zoneName or "Learned",
                    text = "Learned location", learned = true,
                }
            end
        end
    end
    return results
end

--------------------------
-- Find nearest
--------------------------

-- Walk the parentMapID chain to the continent-level map (mapType <= 2).
local function GetContinentMap(mapID)
    if not mapID then return nil end
    local cur, guard = mapID, 0
    while cur and guard < 10 do
        local info = C_Map.GetMapInfo(cur)
        if not info then return cur end
        if info.mapType and info.mapType <= 2 then return cur end
        if info.parentMapID and info.parentMapID > 0 then
            cur = info.parentMapID
        else
            return cur
        end
        guard = guard + 1
    end
    return cur
end

local function MapToWorld(mapID, x, y)
    if not C_Map.GetWorldPosFromMapPos then return nil end
    local ok, _, worldPos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and worldPos then return worldPos:GetXY() end
    return nil
end

-- Merge learned + static locations, then rank by distance from the player.
local function FindNearestService(tool)
    local serviceKey = tool.locationKey
    if not serviceKey then return nil end
    local curMap = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local playerFaction = UnitFactionGroup and UnitFactionGroup("player") or nil

    local allLocs = {}
    if curMap then
        for _, loc in ipairs(GetLearnedLocations(serviceKey, curMap)) do
            allLocs[#allLocs + 1] = loc
        end
    end
    for _, loc in ipairs(tool.locations or {}) do
        if not loc.faction or loc.faction == playerFaction then
            allLocs[#allLocs + 1] = loc
        end
    end
    for _, loc in ipairs(GetLearnedLocations(serviceKey, nil)) do
        if loc.map ~= curMap then allLocs[#allLocs + 1] = loc end
    end

    if #allLocs == 0 then return nil end
    if not curMap then return allLocs[1] end

    local px, py
    if C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(curMap, "player")
        if pos then px, py = pos:GetXY() end
    end

    -- Pass 1: same-map entries by map-space distance.
    local bestLoc, bestDist = nil, math.huge
    for _, loc in ipairs(allLocs) do
        if loc.map == curMap and px and py then
            local dx, dy = (loc.x or 0) - px, (loc.y or 0) - py
            local d = dx * dx + dy * dy
            if d < bestDist then bestDist, bestLoc = d, loc end
        elseif loc.map == curMap and not bestLoc then
            bestLoc = loc
        end
    end
    if bestLoc then return bestLoc end

    -- Pass 2: cross-map by world coordinates within the continent.
    local pwx, pwy = MapToWorld(curMap, px or 0.5, py or 0.5)
    if pwx then
        local curContinent = GetContinentMap(curMap)
        bestLoc, bestDist = nil, math.huge
        for _, loc in ipairs(allLocs) do
            if GetContinentMap(loc.map) == curContinent then
                local lwx, lwy = MapToWorld(loc.map, loc.x or 0.5, loc.y or 0.5)
                if lwx then
                    local dx, dy = lwx - pwx, lwy - pwy
                    local d = dx * dx + dy * dy
                    if d < bestDist then bestDist, bestLoc = d, loc end
                end
            end
        end
        if bestLoc then return bestLoc end
    end

    -- Pass 3: same-continent fallback.
    local curContinent2 = GetContinentMap(curMap)
    if curContinent2 then
        for _, loc in ipairs(allLocs) do
            if GetContinentMap(loc.map) == curContinent2 then return loc end
        end
    end
    return allLocs[1]
end

local function LocateNearest(tool)
    local loc = FindNearestService(tool)
    if not loc then
        ns:Print(ns.COLORS.RED .. "No known locations for " .. tool.label .. ".|r")
        return
    end
    if C_Map and C_Map.SetUserWaypoint and CreateVector2D then
        local ok = pcall(C_Map.SetUserWaypoint, {
            uiMapID = loc.map, position = CreateVector2D(loc.x, loc.y),
        })
        if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    end
    local source = loc.learned and " (learned)" or ""
    ns:Print(ns.COLORS.CYAN .. "Waypoint:|r " .. loc.zoneName .. " -- " .. (loc.text or "") .. source)
end

--------------------------
-- Drawer state
--------------------------

local clipFrame, innerFrame, thumbFrame, headerText
local toolButtons = {}      -- pooled tool rows
local contentHeight = ContentHeightFor(6)

local drawerOpen   = false
local animating    = false
local animProgress = 0
local animTarget   = 0
local thumbCollapsedHeight = 0

local _pendingRefreshAfterCombat = false

local function GetCollapsedThumbHeight()
    local mini = _G["FlipQueueMiniFrame"]
    local miniH = (mini and mini:GetHeight()) or contentHeight
    if miniH <= 0 then miniH = contentHeight end
    return math.min(miniH, contentHeight)
end

local function ApplyAnimProgress(p)
    if not clipFrame then return end
    local w = THUMB_WIDTH + (FULL_WIDTH - THUMB_WIDTH) * p
    local h = thumbCollapsedHeight + (contentHeight - thumbCollapsedHeight) * p
    clipFrame:SetWidth(w)
    clipFrame:SetHeight(h)
    if thumbFrame then thumbFrame:SetHeight(h) end
end

--------------------------
-- Rollout sub-drawer
--------------------------

local rolloutFrame
local rolloutRows = {}
local rolloutTool = nil       -- the service tool the rollout currently shows
local rolloutHideTimer = 0

local ROLLOUT_ROW_H = 30
local ROLLOUT_WIDTH = 210
local ROLLOUT_ICON  = 24

local function HideRollout()
    rolloutTool = nil
    if rolloutFrame then rolloutFrame:Hide() end
end

local function EnsureRollout()
    if rolloutFrame then return end

    rolloutFrame = CreateFrame("Frame", "FlipQueueToolRollout", UIParent, "BackdropTemplate")
    rolloutFrame:SetFrameStrata("DIALOG")
    rolloutFrame:SetWidth(ROLLOUT_WIDTH)
    rolloutFrame:SetBackdrop(DRAWER_BACKDROP)
    rolloutFrame:SetBackdropColor(0.06, 0.06, 0.11, 0.97)
    rolloutFrame:SetBackdropBorderColor(0.35, 0.35, 0.5, 0.9)
    rolloutFrame:Hide()

    local title = rolloutFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", rolloutFrame, "TOPLEFT", 8, -6)
    title:SetTextColor(0.8, 0.85, 1)
    rolloutFrame.title = title

    -- Auto-hide once the mouse leaves both the drawer and the rollout.
    rolloutFrame:SetScript("OnUpdate", function(self, elapsed)
        local overDrawer  = clipFrame and clipFrame:IsMouseOver()
        local overRollout = self:IsMouseOver()
        if overDrawer or overRollout then
            rolloutHideTimer = 0
        else
            rolloutHideTimer = rolloutHideTimer + elapsed
            if rolloutHideTimer > 0.3 then HideRollout() end
        end
    end)
end

-- Get or create a pooled rollout method row. Rows are SecureActionButtons so
-- a click summons the chosen method directly.
local function GetRolloutRow(index)
    if rolloutRows[index] then return rolloutRows[index] end

    local row = CreateFrame("Button", "FlipQueueToolRolloutRow" .. index,
        rolloutFrame, "SecureActionButtonTemplate")
    row:SetSize(ROLLOUT_WIDTH - 12, ROLLOUT_ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.12, 0.12, 0.18, 0.6)

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.12)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROLLOUT_ICON, ROLLOUT_ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.cooldown = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cooldown:SetAllPoints(row.icon)
    row.cooldown:SetHideCountdownNumbers(false)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.state:SetPoint("RIGHT", row, "RIGHT", -6, -8)
    row.state:SetJustifyH("RIGHT")

    row:HookScript("PostClick", function()
        lastSummonClickTime = GetTime()
        HideRollout()
    end)

    rolloutRows[index] = row
    return row
end

-- Populate and show the rollout for a service tool. Returns false (and shows
-- nothing) when the tool has no owned methods -- the caller falls back to a
-- tooltip in that case.
local function OpenRollout(tool, anchorBtn)
    if InCombatLockdown and InCombatLockdown() then return false end
    EnsureRollout()

    local evals = TR:GetOwnedMethodEvals(tool)
    if #evals == 0 then
        HideRollout()
        return false
    end

    rolloutTool = tool
    rolloutFrame.title:SetText(tool.label)

    for _, r in ipairs(rolloutRows) do r:Hide() end

    local y = -22
    for i, e in ipairs(evals) do
        local row = GetRolloutRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rolloutFrame, "TOPLEFT", 6, y)
        row.icon:SetTexture(e.icon or tool.iconFallback)
        row.label:SetText(e.dispatchName)

        -- Per-method state hint + cooldown swipe.
        local cls = TR:ClassifyEval(e)
        if cls == "cooldown" then
            row.state:SetText("|cffffcc66cooldown|r")
            row.cooldown:SetCooldown(e.cdStart or 0, e.cdDur or 0)
            row.icon:SetDesaturated(true)
        else
            row.cooldown:Clear()
            if cls == "active" then
                row.state:SetText("|cff66cc66active|r")
                row.icon:SetDesaturated(false)
            elseif cls == "unavailable" then
                row.state:SetText("|cff888888unavailable|r")
                row.icon:SetDesaturated(true)
            else
                row.state:SetText("|cffaaaaaaready|r")
                row.icon:SetDesaturated(false)
            end
        end

        -- Secure dispatch -- cannot be set during combat lockdown.
        if not (InCombatLockdown and InCombatLockdown()) then
            TR:ApplySecureDispatch(row, e.dispatchKind, e.dispatchName)
        end

        row:Show()
        y = y - ROLLOUT_ROW_H - 2
    end

    rolloutFrame:SetHeight(math.abs(y) + 6)
    rolloutFrame:ClearAllPoints()
    rolloutFrame:SetPoint("TOPRIGHT", anchorBtn, "TOPLEFT", -3, 3)
    rolloutHideTimer = 0
    rolloutFrame:Show()
    return true
end

--------------------------
-- Tool buttons
--------------------------

-- Create a pooled tool row: a secure main button + a find button. All
-- scripts are wired once here and read the tool/resolution off `self`
-- (`_tool` / `_res`), which RefreshToolDrawer reassigns each refresh -- so
-- there is no per-refresh closure churn.
local function CreateToolButton(index)
    local btn = CreateFrame("Button", "FlipQueueToolBtn" .. index,
        innerFrame, "SecureActionButtonTemplate, BackdropTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonUp")

    btn:SetBackdrop(BUTTON_BACKDROP)
    btn:SetBackdropColor(0.10, 0.10, 0.14, 0.9)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    btn.tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cooldown:SetPoint("TOPLEFT", btn.tex, "TOPLEFT", 0, 0)
    btn.cooldown:SetPoint("BOTTOMRIGHT", btn.tex, "BOTTOMRIGHT", 0, 0)
    btn.cooldown:SetHideCountdownNumbers(false)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints(btn.tex)
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)

    -- "Missing macro" marker.
    btn.warn = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    btn.warn:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.warn:SetText("|cffff4444!|r")
    btn.warn:Hide()

    -- Find button: slim vertical button to the right of the icon.
    local find = CreateFrame("Button", "FlipQueueToolFind" .. index, innerFrame, "BackdropTemplate")
    find:SetSize(FIND_WIDTH, ICON_SIZE)
    find:SetBackdrop(BUTTON_BACKDROP)
    find:SetBackdropColor(0.10, 0.12, 0.18, 0.9)
    find:SetBackdropBorderColor(0.3, 0.4, 0.6, 0.8)
    find.pin = find:CreateTexture(nil, "ARTWORK")
    find.pin:SetSize(14, 14)
    find.pin:SetPoint("CENTER", find, "CENTER", 0, 0)
    find.pin:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
    find.pin:SetVertexColor(0.7, 0.85, 1.0)
    find.hl = find:CreateTexture(nil, "HIGHLIGHT")
    find.hl:SetAllPoints()
    find.hl:SetColorTexture(1, 1, 1, 0.18)
    btn.findBtn = find

    btn:SetScript("OnEnter", function(self)
        local tool = self._tool
        if not tool then return end
        if tool.type == "service" then
            -- Hovering a service opens its rollout; with no owned methods
            -- there is nothing to roll out, so fall back to a tooltip.
            if not OpenRollout(tool, self) then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("|cff8888ff" .. tool.label .. "|r", 1, 1, 1)
                GameTooltip:AddLine("No summon owned.", 0.7, 0.7, 0.7)
                if tool.locationKey then
                    local nearest = FindNearestService(tool)
                    if nearest then
                        GameTooltip:AddLine("Click to set a waypoint to the nearest "
                            .. tool.label:lower() .. ".", 0.5, 0.7, 1.0)
                        GameTooltip:AddLine("Nearest: " .. nearest.zoneName .. " - "
                            .. (nearest.text or ""), 0.5, 0.7, 1.0)
                    end
                end
                GameTooltip:Show()
            end
        else
            -- Action / macro: no rollout. Close any open rollout.
            HideRollout()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if tool.type == "macro" and tool.missing then
                GameTooltip:SetText("|cffff6666" .. tool.label .. "|r", 1, 1, 1)
                GameTooltip:AddLine("Macro not found on this character.", 0.9, 0.6, 0.6, true)
                GameTooltip:AddLine("Account-wide macros show on every character; "
                    .. "per-character macros only on the one that has them.", 0.6, 0.6, 0.6, true)
            elseif tool.type == "macro" then
                GameTooltip:SetText("|cff66cc66" .. tool.label .. "|r", 1, 1, 1)
                GameTooltip:AddLine("Run macro.", 0.7, 0.9, 0.7)
            else
                GameTooltip:SetText("|cff66cc66" .. tool.label .. "|r", 1, 1, 1)
                GameTooltip:AddLine(tool.tooltip or "", 0.7, 0.9, 0.7)
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- PostClick handles the non-secure outcomes: locate (find mode), action
    -- tools, and recording summon clicks for location learning.
    btn:SetScript("PostClick", function(self)
        local tool, res = self._tool, self._res
        if not tool then return end
        if tool.type == "action" then
            if tool.onUse then tool.onUse() end
        elseif tool.type == "service" then
            if res and res.state == "unowned" then
                LocateNearest(tool)
            else
                lastSummonClickTime = GetTime()
            end
        end
    end)

    find:SetScript("OnClick", function(self)
        if self._tool then LocateNearest(self._tool) end
    end)
    find:SetScript("OnEnter", function(self)
        local tool = self._tool
        if not tool then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Find nearest " .. tool.label:lower(), 0.6, 0.8, 1.0)
        local nearest = FindNearestService(tool)
        if nearest then
            local tag = nearest.learned and " (learned)" or ""
            GameTooltip:AddLine(nearest.zoneName .. " - " .. (nearest.text or "") .. tag,
                0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine("No known locations yet -- visit one to learn it.",
                0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    find:SetScript("OnLeave", function() GameTooltip:Hide() end)

    toolButtons[index] = btn
    return btn
end

--------------------------
-- Drawer construction
--------------------------

local function EnsureDrawer()
    if clipFrame then return true end
    local mini = _G["FlipQueueMiniFrame"]
    if not mini then return false end

    thumbCollapsedHeight = GetCollapsedThumbHeight()

    clipFrame = CreateFrame("Frame", "FlipQueueToolClip", mini)
    clipFrame:SetClipsChildren(true)
    clipFrame:SetSize(THUMB_WIDTH, thumbCollapsedHeight)
    clipFrame:SetPoint("TOPRIGHT", mini, "TOPLEFT", 3, 0)
    clipFrame:SetFrameStrata("MEDIUM")

    innerFrame = CreateFrame("Frame", "FlipQueueToolContent", clipFrame, "BackdropTemplate")
    innerFrame:SetSize(FULL_WIDTH, contentHeight)
    innerFrame:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, 0)
    innerFrame:SetBackdrop(DRAWER_BACKDROP)
    innerFrame:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
    innerFrame:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    headerText = innerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerText:SetPoint("TOPLEFT", innerFrame, "TOPLEFT", THUMB_WIDTH + PAD, -2)
    headerText:SetWidth(ICON_SIZE)
    headerText:SetJustifyH("CENTER")
    headerText:SetText("Tools")
    headerText:SetTextColor(0.8, 0.85, 1)

    thumbFrame = CreateFrame("Button", "FlipQueueToolTab", innerFrame)
    thumbFrame:SetSize(THUMB_WIDTH, thumbCollapsedHeight)
    thumbFrame:SetPoint("TOPLEFT", innerFrame, "TOPLEFT", 0, 0)
    for j = 1, 3 do
        local grip = thumbFrame:CreateTexture(nil, "ARTWORK")
        grip:SetSize(1, 16)
        grip:SetPoint("CENTER", thumbFrame, "CENTER", (j - 2) * 3, 0)
        grip:SetColorTexture(0.4, 0.4, 0.5, 0.6)
    end
    thumbFrame.highlight = thumbFrame:CreateTexture(nil, "HIGHLIGHT")
    thumbFrame.highlight:SetAllPoints()
    thumbFrame.highlight:SetColorTexture(1, 1, 1, 0.06)
    thumbFrame:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        UI:ToggleToolDrawer()
    end)

    clipFrame:SetScript("OnUpdate", function(_, elapsed)
        if not animating then return end
        local diff = animTarget - animProgress
        local step = elapsed / ANIM_DURATION
        if math.abs(diff) <= step then
            animProgress = animTarget
            animating = false
        else
            animProgress = animProgress + (diff > 0 and step or -step)
        end
        ApplyAnimProgress(animProgress)
    end)

    return true
end

--------------------------
-- Public API
--------------------------

local function SaveDrawerShown(shown)
    if ns.db and ns.db.settings then
        ns.db.settings.toolDrawerShown = shown and true or false
    end
end

function UI:ShowToolDrawer()
    if not EnsureDrawer() then return end
    local mini = _G["FlipQueueMiniFrame"]
    if not mini or not mini:IsShown() then return end
    drawerOpen = true
    thumbCollapsedHeight = GetCollapsedThumbHeight()
    animTarget = 1
    animating = true
    SaveDrawerShown(true)
    if UI.RefreshToolDrawer then UI:RefreshToolDrawer() end
end

function UI:HideToolDrawer()
    if not clipFrame then return end
    drawerOpen = false
    HideRollout()
    thumbCollapsedHeight = GetCollapsedThumbHeight()
    animTarget = 0
    animating = true
    SaveDrawerShown(false)
    if not (InCombatLockdown and InCombatLockdown()) then
        for _, btn in ipairs(toolButtons) do
            btn:SetAttribute("type", nil)
            btn:SetAttribute("item", nil)
            btn:SetAttribute("spell", nil)
            btn:SetAttribute("macro", nil)
        end
    end
end

function UI:ToggleToolDrawer()
    if drawerOpen then UI:HideToolDrawer() else UI:ShowToolDrawer() end
end

function UI:IsToolDrawerShown()
    return drawerOpen
end

function UI:UpdateToolDrawerHeight()
    if not clipFrame then return end
    thumbCollapsedHeight = GetCollapsedThumbHeight()
    if not animating then ApplyAnimProgress(animProgress) end
end

function UI:RefreshToolDrawer()
    if not EnsureDrawer() then return end

    -- Show/Hide/Size/Anchor are protected while combat is active because the
    -- clip frame inherits protection from the mini-view parent. Defer.
    if InCombatLockdown and InCombatLockdown() then
        _pendingRefreshAfterCombat = true
        return
    end

    local mini = _G["FlipQueueMiniFrame"]
    if not mini or not mini:IsShown() then
        if clipFrame then clipFrame:Hide() end
        return
    end
    clipFrame:Show()

    -- Restore saved open/closed state on the first refresh after login.
    if ns.db and ns.db.settings then
        local saved = ns.db.settings.toolDrawerShown
        if saved == true and not drawerOpen and not animating then
            drawerOpen = true
            animProgress, animTarget = 1, 1
        elseif (saved == false or saved == nil) and not drawerOpen and not animating then
            animProgress, animTarget = 0, 0
        end
    end

    -- When the drawer is closed and idle its buttons are clipped out of
    -- sight, so skip the whole rebuild (and its bag scans). The next
    -- ShowToolDrawer flips drawerOpen and triggers a full refresh.
    if not drawerOpen and not animating then
        thumbCollapsedHeight = GetCollapsedThumbHeight()
        ApplyAnimProgress(0)
        return
    end

    -- Open or animating: resolve the tool list and size the drawer to fit.
    local tools = TR:GetTools()
    contentHeight = ContentHeightFor(#tools)
    innerFrame:SetHeight(contentHeight)
    thumbCollapsedHeight = GetCollapsedThumbHeight()
    -- Re-apply progress so a tool-count change (which moved contentHeight)
    -- resizes the clip/thumb even while the drawer sits open.
    if not animating then ApplyAnimProgress(animProgress) end

    -- Build / position one button per visible tool; hide the surplus.
    for i = 1, #tools do
        local btn = toolButtons[i] or CreateToolButton(i)
        local tool = tools[i]
        local yOff = RowYOffset(i)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", innerFrame, "TOPLEFT", THUMB_WIDTH + PAD, yOff)
        btn.findBtn:ClearAllPoints()
        btn.findBtn:SetPoint("TOPLEFT", innerFrame, "TOPLEFT",
            THUMB_WIDTH + PAD + ICON_SIZE + GAP, yOff)
        btn:Show()

        local res = TR:ResolveTool(tool)
        btn._tool, btn._res = tool, res
        btn.findBtn._tool = tool

        -- Find button applies only to services with fixed locations.
        if tool.type == "service" and tool.locationKey then
            btn.findBtn:Show()
        else
            btn.findBtn:Hide()
        end

        btn.tex:SetTexture(res.icon or tool.iconFallback or tool.icon)
        btn.warn:Hide()
        btn.cooldown:Clear()
        btn.tex:SetDesaturated(false)
        btn.tex:SetVertexColor(1, 1, 1)

        if tool.type == "service" then
            if res.state == "ready" then
                btn:SetBackdropBorderColor(0.4, 0.8, 0.4, 0.9)
            elseif res.state == "active" or res.state == "open" then
                btn:SetBackdropBorderColor(0.4, 0.7, 0.9, 0.9)
            elseif res.state == "cooldown" then
                btn:SetBackdropBorderColor(0.9, 0.7, 0.3, 0.9)
                if res.cdStart and res.cdDur then
                    btn.cooldown:SetCooldown(res.cdStart, res.cdDur)
                end
            else  -- unowned
                btn.tex:SetDesaturated(true)
                btn.tex:SetVertexColor(0.4, 0.45, 0.55)
                btn:SetBackdropBorderColor(0.3, 0.4, 0.6, 0.8)
            end
        elseif tool.type == "macro" and tool.missing then
            btn.tex:SetDesaturated(true)
            btn.tex:SetVertexColor(0.5, 0.5, 0.5)
            btn:SetBackdropBorderColor(0.7, 0.3, 0.3, 0.8)
            btn.warn:Show()
        else
            btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        end

        -- Secure dispatch (skipped during combat lockdown). Action tools and
        -- unowned services get a cleared button -- PostClick handles them.
        if not (InCombatLockdown and InCombatLockdown()) then
            if tool.type == "macro" and not tool.missing then
                TR:ApplySecureDispatch(btn, "macro", tool.macroName)
            elseif tool.type == "service"
                   and (res.state == "ready" or res.state == "cooldown") then
                TR:ApplySecureDispatch(btn, res.dispatchKind, res.dispatchName)
            else
                TR:ApplySecureDispatch(btn, nil, nil)
            end
        end
    end
    for i = #tools + 1, #toolButtons do
        toolButtons[i]:Hide()
        toolButtons[i].findBtn:Hide()
    end

    -- The rebuild reassigned pooled buttons, so the rollout's anchor may have
    -- moved. If its service is still visible, re-anchor + repopulate in place
    -- (keeps it open while the player is using it); otherwise close it.
    if rolloutTool then
        local stillVisible = false
        for i = 1, #tools do
            if tools[i] == rolloutTool then
                OpenRollout(tools[i], toolButtons[i])
                stillVisible = true
                break
            end
        end
        if not stillVisible then HideRollout() end
    end
end

--------------------------
-- Event handling
--------------------------

-- Coalesce refreshes. BAG_UPDATE_COOLDOWN / SPELL_UPDATE_COOLDOWN fire many
-- times per second (every cooldown tick in the game, not just the drawer's
-- summons); a burst of BAG_UPDATEs arrives one-per-bag. Debouncing collapses
-- each burst into a single refresh.
local _refreshScheduled = false
local function ScheduleRefresh()
    if _refreshScheduled then return end
    _refreshScheduled = true
    C_Timer.After(0.1, function()
        _refreshScheduled = false
        if UI.RefreshToolDrawer then UI:RefreshToolDrawer() end
    end)
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("BAG_UPDATE")
evt:RegisterEvent("BAG_UPDATE_COOLDOWN")
evt:RegisterEvent("SPELL_UPDATE_COOLDOWN")
evt:RegisterEvent("SPELL_UPDATE_USABLE")
evt:RegisterEvent("SPELLS_CHANGED")
evt:RegisterEvent("PLAYER_REGEN_ENABLED")
evt:RegisterEvent("MAIL_SHOW")
evt:RegisterEvent("MAIL_CLOSED")
evt:RegisterEvent("AUCTION_HOUSE_SHOW")
evt:RegisterEvent("AUCTION_HOUSE_CLOSED")
evt:RegisterEvent("BANKFRAME_OPENED")
evt:RegisterEvent("BANKFRAME_CLOSED")
evt:RegisterEvent("MERCHANT_SHOW")
evt:RegisterEvent("MERCHANT_CLOSED")
evt:RegisterEvent("UPDATE_MACROS")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
        serviceState.mailOpen = true
        LearnCurrentLocation("mail")
    elseif event == "MAIL_CLOSED" then
        serviceState.mailOpen = false
    elseif event == "AUCTION_HOUSE_SHOW" then
        serviceState.auctionOpen = true
        LearnCurrentLocation("auctionHouse")
    elseif event == "AUCTION_HOUSE_CLOSED" then
        serviceState.auctionOpen = false
    elseif event == "BANKFRAME_OPENED" then
        serviceState.bankOpen = true
        LearnCurrentLocation("bank")
    elseif event == "BANKFRAME_CLOSED" then
        serviceState.bankOpen = false
    elseif event == "MERCHANT_SHOW" then
        LearnCurrentLocation("vendor")
    elseif event == "PLAYER_ENTERING_WORLD" then
        serviceState.mailOpen = false
        serviceState.auctionOpen = false
        serviceState.bankOpen = false
    end
    ScheduleRefresh()
end)

-- Combat-end handler: run any refresh deferred during combat lockdown.
local combatEvt = CreateFrame("Frame")
combatEvt:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEvt:SetScript("OnEvent", function()
    if _pendingRefreshAfterCombat and UI.RefreshToolDrawer then
        _pendingRefreshAfterCombat = false
        UI:RefreshToolDrawer()
    end
end)
