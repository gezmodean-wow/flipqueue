-- UI/ToolDrawer.lua
-- Left-extending tools drawer for the mini overlay: one-click summon of
-- mail / AH / bank / warband access items. Replaces the downward-extending
-- ServiceDrawer with a horizontal clip animation that reveals leftward from
-- the mini's left edge.
local addonName, ns = ...

local UI = ns.UI

-- Event-driven service state. More reliable than polling BankFrame:IsShown()
-- which can be wrong if another addon keeps the frame around.
local serviceState = {
    mailOpen = false,
    auctionOpen = false,
    bankOpen = false,
}

-- Export for ContextDrawer and other files that need bank/AH open state.
ns._serviceState = serviceState

--------------------------
-- Data tables
--------------------------

-- Service definitions. Each entry maps to one icon button in the drawer.
-- `summons` is an ordered preference list -- put the best summon at the top.
-- Each entry has:
--   kind = "item" | "spell" | "toy" | "mount"
--   id   = item ID / spell ID / toy item ID / mount ID (journal index)
--   name = display name (also used as the secure-button attribute value --
--          for mounts this MUST be the mount's spell name, e.g.
--          "Mighty Caravan Brutosaur" not "Reins of the...")
local SERVICES = {
    {
        key = "mail",
        label = "Mail",
        iconFallback = "Interface\\Icons\\INV_Letter_15",
        summons = {
            -- Katy's Stampwhistle -- toy, summons a mailbox for 10 min.
            { kind = "toy", id = 156833, name = "Katy's Stampwhistle" },
            -- MOLL-E -- engineer-crafted, summons a mailbox for 10 min.
            { kind = "item", id = 54710, name = "MOLL-E" },
        },
        locations = {
            -- Dornogal (The War Within)
            { map = 2339, x = 0.56, y = 0.45, zoneName = "Dornogal", text = "Mailbox near Earthenfall Hall" },
            -- Valdrakken (Dragonflight)
            { map = 2112, x = 0.58, y = 0.57, zoneName = "Valdrakken", text = "Seat of the Aspects mailbox" },
            -- Oribos (Shadowlands)
            { map = 1670, x = 0.49, y = 0.28, zoneName = "Oribos", text = "Ring of Transference mailbox" },
            -- Stormwind (Alliance)
            { map = 84, x = 0.60, y = 0.65, zoneName = "Stormwind", text = "Trade District mailbox" },
            -- Orgrimmar (Horde)
            { map = 85, x = 0.54, y = 0.55, zoneName = "Orgrimmar", text = "Valley of Strength mailbox" },
        },
        inServiceCheck = function() return serviceState.mailOpen end,
    },
    {
        key = "auctionHouse",
        label = "Auction House",
        iconFallback = "Interface\\Icons\\INV_Misc_Coin_02",
        summons = {
            -- Mighty Caravan Brutosaur -- mount with AH/bank/vendor NPCs.
            -- Mount ID from C_MountJournal (journal index, NOT the item ID of
            -- its teaching item). The secure button casts by spell NAME.
            { kind = "mount", id = 1039, name = "Mighty Caravan Brutosaur" },
            -- Traveler's Anchorite -- TWW expedition mount with an AH NPC.
            -- Mount ID and spell name per the mount journal entry.
            { kind = "mount", id = 2332, name = "Traveler's Anchorite" },
        },
        locations = {
            { map = 2339, x = 0.48, y = 0.52, zoneName = "Dornogal", text = "Auction House" },
            { map = 2112, x = 0.40, y = 0.56, zoneName = "Valdrakken", text = "Auction House" },
            { map = 1670, x = 0.45, y = 0.28, zoneName = "Oribos", text = "Auction House" },
            { map = 84, x = 0.60, y = 0.70, zoneName = "Stormwind", text = "Trade District Auction House" },
            { map = 85, x = 0.54, y = 0.58, zoneName = "Orgrimmar", text = "Valley of Strength Auction House" },
        },
        inServiceCheck = function() return serviceState.auctionOpen end,
    },
    {
        key = "bank",
        label = "Character Bank",
        iconFallback = "Interface\\Icons\\INV_Misc_Bag_10_Green",
        summons = {
            -- Brutosaur covers banker access via the same mount NPCs.
            { kind = "mount", id = 1039, name = "Mighty Caravan Brutosaur" },
        },
        locations = {
            { map = 2339, x = 0.50, y = 0.50, zoneName = "Dornogal", text = "Bank" },
            { map = 2112, x = 0.39, y = 0.55, zoneName = "Valdrakken", text = "Bank" },
            { map = 1670, x = 0.47, y = 0.30, zoneName = "Oribos", text = "Bank" },
            { map = 84, x = 0.60, y = 0.62, zoneName = "Stormwind", text = "Trade District Bank" },
            { map = 85, x = 0.55, y = 0.58, zoneName = "Orgrimmar", text = "Valley of Strength Bank" },
        },
        inServiceCheck = function() return serviceState.bankOpen end,
    },
    {
        key = "warbank",
        label = "Warband Bank",
        iconFallback = "Interface\\Icons\\INV_Misc_Bag_EnchantedRunecloth",
        summons = {
            -- Warband Bank Distance Inhibitor -- quest reward spell from
            -- "Warbands: Spacetime is Money". Once learned, castable from spellbook.
            { kind = "spell", id = 460905, name = "Warband Bank Distance Inhibitor" },
        },
        locations = {
            { map = 2339, x = 0.50, y = 0.50, zoneName = "Dornogal", text = "Warband Bank (bank NPC)" },
            { map = 2112, x = 0.39, y = 0.55, zoneName = "Valdrakken", text = "Warband Bank (bank NPC)" },
        },
        inServiceCheck = function() return serviceState.bankOpen end,
    },
}

--------------------------
-- Summon availability (items and spells)
--------------------------

-- Returns (owned, icon, onCooldownRemaining, cdStart, cdDuration).
-- owned = true if the item is in bags.
local function CheckItemSummon(itemID)
    if not itemID then return false end
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots then
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID == itemID then
                    local start, duration = C_Container.GetItemCooldown(itemID)
                    local remaining = 0
                    if start and duration and duration > 0 then
                        remaining = math.max(0, (start + duration) - GetTime())
                    end
                    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or nil
                    return true, icon, remaining, start, duration
                end
            end
        end
    end
    return false
end

-- Returns (owned, icon, onCooldownRemaining, cdStart, cdDuration) for a toy.
-- Toys are detected via the toy box (PlayerHasToy) rather than bag scanning
-- because toys don't live in bags after being learned. Cooldown is read via
-- the item cooldown API, which works on learned toys even though the item
-- isn't in bags.
-- Returns (owned, icon, onCooldownRemaining, cdStart, cdDuration, usable, localizedName).
-- localizedName is resolved via GetItemInfo so the secure button works on
-- any client language (the hardcoded English name in SERVICES is a fallback).
local function CheckToySummon(toyID)
    if not toyID then return false end
    if not PlayerHasToy then return false end
    local has = PlayerHasToy(toyID)
    if not has then return false end
    local remaining, start, duration = 0, 0, 0
    if C_Container and C_Container.GetItemCooldown then
        local s, d = C_Container.GetItemCooldown(toyID)
        if s and d and d > 0 then
            start, duration = s, d
            remaining = math.max(0, (s + d) - GetTime())
        end
    end
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(toyID) or nil
    local localName = nil
    if C_Item and C_Item.GetItemInfo then
        local ok, n = pcall(C_Item.GetItemInfo, toyID)
        if ok and n then localName = n end
    end
    return true, icon, remaining, start, duration, true, localName
end

-- Returns (owned, icon, onCooldownRemaining, cdStart, cdDuration, usable,
-- spellName) for a mount. Mounts are driven by the mount journal -- the
-- "id" is a journal mount ID, and the secure button casts by spell name.
local function CheckMountSummon(mountID)
    if not mountID then return false end
    if not (C_MountJournal and C_MountJournal.GetMountInfoByID) then return false end
    local name, spellID, icon, _, isUsable, _, _, _, _, _, isCollected =
        C_MountJournal.GetMountInfoByID(mountID)
    if not isCollected then return false end
    -- Mounted-check: can't resummon the same mount. Treat already-mounted as
    -- usable=false so the button gets the "redundant" greyed-out treatment.
    -- We don't check combat / no-mount zones -- the secure click will fail
    -- gracefully if the cast is invalid, which matches item behavior.
    local usable = isUsable ~= false
    local remaining, start, duration = 0, 0, 0
    if spellID and C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info and info.duration and info.duration > 0 then
            start = info.startTime or 0
            duration = info.duration
            remaining = math.max(0, (start + duration) - GetTime())
        end
    end
    return true, icon, remaining, start, duration, usable, name
end

-- Returns (known, icon, onCooldownRemaining, cdStart, cdDuration).
-- known = true if the spell is in the player's spellbook.
local function CheckSpellSummon(spellID)
    if not spellID then return false end
    local known = false
    if IsPlayerSpell then
        known = IsPlayerSpell(spellID)
    elseif IsSpellKnown then
        known = IsSpellKnown(spellID)
    end
    if not known then return false end

    -- Modern retail: C_Spell.GetSpellCooldown returns a table.
    -- Legacy: GetSpellCooldown returns (start, duration, enabled, modRate).
    local start, duration = 0, 0
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then
            start = info.startTime or 0
            duration = info.duration or 0
        end
    elseif GetSpellCooldown then
        local s, d = GetSpellCooldown(spellID)
        start = s or 0
        duration = d or 0
    end
    local remaining = 0
    if duration and duration > 0 then
        remaining = math.max(0, (start + duration) - GetTime())
    end

    local icon = nil
    local localName = nil
    if C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(spellID)
    elseif GetSpellTexture then
        icon = GetSpellTexture(spellID)
    end
    if C_Spell and C_Spell.GetSpellName then
        localName = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        localName = GetSpellInfo(spellID)
    end

    return true, icon, remaining, start, duration, nil, localName
end

-- Decide which summon (if any) to show for a given service, and in which state.
-- Returns a resolution table:
--   { kind, id, name, icon, state, cooldownStart, cooldownDuration }
-- state is one of: "ready" | "cooldown" | "redundant" | "unowned"
local function ResolveService(service)
    local inService = service.inServiceCheck and service.inServiceCheck()

    local firstOwnedCooldown = nil
    local firstOwnedRedundant = nil

    for _, summon in ipairs(service.summons or {}) do
        local owned, icon, remaining, cdStart, cdDur, srcUsable, resolvedName
        if summon.kind == "spell" then
            owned, icon, remaining, cdStart, cdDur, srcUsable, resolvedName = CheckSpellSummon(summon.id)
        elseif summon.kind == "toy" then
            owned, icon, remaining, cdStart, cdDur, srcUsable, resolvedName = CheckToySummon(summon.id)
        elseif summon.kind == "mount" then
            owned, icon, remaining, cdStart, cdDur, srcUsable, resolvedName =
                CheckMountSummon(summon.id)
        else
            owned, icon, remaining, cdStart, cdDur = CheckItemSummon(summon.id)
        end

        -- For secure-button dispatch, toys act like items (/use <name>) and
        -- mounts act like spells (/cast <spellName>). Normalize the output
        -- kind here so the rest of ResolveService + the button wire-up only
        -- has to care about "item" vs "spell".
        local outKind = summon.kind
        local outName = resolvedName or summon.name
        if summon.kind == "toy" then
            outKind = "item"
        elseif summon.kind == "mount" then
            outKind = "spell"
        end

        if owned then
            icon = icon or service.iconFallback
            if inService then
                if not firstOwnedRedundant then
                    firstOwnedRedundant = {
                        kind = outKind, id = summon.id, name = outName,
                        icon = icon, state = "redundant",
                    }
                end
            elseif remaining and remaining > 0 then
                if not firstOwnedCooldown then
                    firstOwnedCooldown = {
                        kind = outKind, id = summon.id, name = outName,
                        icon = icon, state = "cooldown",
                        cooldownStart = cdStart, cooldownDuration = cdDur,
                    }
                end
            else
                -- Usability check: for plain items, IsUsableItem (returns
                -- false for mount-only zones etc). For toys and mounts the
                -- dedicated Check*Summon functions already reported srcUsable.
                -- For spells we trust the cooldown+known check -- engine-side
                -- usability probes can falsely reject known off-cooldown spells.
                local usable = true
                if summon.kind == "item" then
                    local v = IsUsableItem and IsUsableItem(summon.id)
                    if v == false then usable = false end
                elseif summon.kind == "toy" or summon.kind == "mount" then
                    if srcUsable == false then usable = false end
                end
                if not usable then
                    if not firstOwnedRedundant then
                        firstOwnedRedundant = {
                            kind = outKind, id = summon.id, name = outName,
                            icon = icon, state = "redundant",
                        }
                    end
                else
                    return {
                        kind = outKind, id = summon.id, name = outName,
                        icon = icon, state = "ready",
                    }
                end
            end
        end
    end

    if firstOwnedCooldown then return firstOwnedCooldown end
    if firstOwnedRedundant then return firstOwnedRedundant end
    return { state = "unowned", icon = service.iconFallback }
end

--------------------------
-- Locate Nearest
--------------------------

-- Walk up the parentMapID chain to find the continent-level map (mapType <= 2).
-- Returns the continent map ID, or the starting map if no parent walk resolves.
local function GetContinentMap(mapID)
    if not mapID then return nil end
    local cur = mapID
    local guard = 0
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

-- Pick the location nearest to the player. "Nearest" is measured by
-- euclidean distance in normalized map coords when the player is on the
-- same map as the location; otherwise we fall back to same-continent
-- membership (no distance, since coords from different maps aren't
-- comparable). Last-resort fallback is the first entry.
--
-- Previous implementation picked the FIRST same-map entry regardless of
-- distance, which is why standing next to one Stormwind mailbox often
-- gave a waypoint to a different district's mailbox.
local function PickNearestLocation(service)
    if not service.locations or #service.locations == 0 then return nil end
    local curMap = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    if not curMap then return service.locations[1] end

    -- Player position in the current map (normalized 0..1).
    local px, py
    if C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(curMap, "player")
        if pos then px, py = pos:GetXY() end
    end

    -- Pass 1: same-map entries, pick the one closest to the player.
    local bestLoc, bestDist = nil, math.huge
    for _, loc in ipairs(service.locations) do
        if loc.map == curMap then
            if px and py then
                local dx = (loc.x or 0) - px
                local dy = (loc.y or 0) - py
                local d = dx * dx + dy * dy
                if d < bestDist then
                    bestDist = d
                    bestLoc = loc
                end
            elseif not bestLoc then
                bestLoc = loc -- no player pos, take first same-map
            end
        end
    end
    if bestLoc then return bestLoc end

    -- Pass 2: same-continent membership. No distance calc across maps.
    local curContinent = GetContinentMap(curMap)
    if curContinent then
        for _, loc in ipairs(service.locations) do
            if GetContinentMap(loc.map) == curContinent then
                return loc
            end
        end
    end

    -- Last resort: first entry.
    return service.locations[1]
end

local function LocateNearest(service)
    local loc = PickNearestLocation(service)
    if not loc then
        ns:Print(ns.COLORS.RED .. "No known locations for " .. service.label .. ".|r")
        return
    end
    if C_Map and C_Map.SetUserWaypoint and CreateVector2D then
        local ok = pcall(C_Map.SetUserWaypoint, {
            uiMapID = loc.map,
            position = CreateVector2D(loc.x, loc.y),
        })
        if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    end
    ns:Print(ns.COLORS.CYAN .. "Waypoint:|r " .. loc.zoneName .. " -- " .. loc.text)
end

--------------------------
-- Drawer constants
--------------------------

local THUMB_WIDTH    = 14
local ICON_SIZE      = 40
local ICON_SPACING   = 6
local PAD            = 6
local CONTENT_WIDTH  = PAD + ICON_SIZE + PAD          -- 52
local FULL_WIDTH     = CONTENT_WIDTH + THUMB_WIDTH     -- 66
local HEADER_HEIGHT  = 18
local CONTENT_HEIGHT = HEADER_HEIGHT + 4 * ICON_SIZE + 3 * ICON_SPACING  -- 196
local ANIM_DURATION  = 0.15

local DRAWER_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

--------------------------
-- Drawer frame construction
--------------------------

local serviceButtons = {}
local clipFrame   = nil
local innerFrame  = nil
local thumbFrame  = nil

local drawerOpen = false
local animating  = false
local animTarget = THUMB_WIDTH

-- Create a service button. Always shows the service category icon (mail
-- envelope, coin, bag, etc). When a summon is available, left-click uses it
-- via SecureActionButton. When no summon is available, the icon gets a
-- small waypoint arrow overlay and left-click calls LocateNearest.
local function CreateServiceButton(parent, service, index)
    local yOff = -(HEADER_HEIGHT + (index - 1) * (ICON_SIZE + ICON_SPACING))

    local btn = CreateFrame("Button", "FlipQueueToolBtn_" .. service.key,
        parent, "SecureActionButtonTemplate, BackdropTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", THUMB_WIDTH + PAD, yOff)
    btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")

    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.10, 0.10, 0.14, 0.9)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    btn.tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.tex:SetTexture(service.iconFallback)

    btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cooldown:SetPoint("TOPLEFT", btn.tex, "TOPLEFT", 0, 0)
    btn.cooldown:SetPoint("BOTTOMRIGHT", btn.tex, "BOTTOMRIGHT", 0, 0)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints(btn.tex)
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)

    -- Waypoint arrow overlay (shown when no summon, centered above Find text)
    btn.findArrow = btn:CreateTexture(nil, "OVERLAY")
    btn.findArrow:SetSize(20, 20)
    btn.findArrow:SetPoint("CENTER", btn, "CENTER", 0, 5)
    btn.findArrow:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
    btn.findArrow:SetVertexColor(0.8, 0.9, 1.0)
    btn.findArrow:Hide()

    -- "Find" label (shown when no summon available, centered below arrow)
    btn.findLabel = btn:CreateFontString(nil, "OVERLAY")
    btn.findLabel:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    btn.findLabel:SetPoint("CENTER", btn, "CENTER", 0, -10)
    btn.findLabel:SetText("FIND")
    btn.findLabel:SetTextColor(1, 1, 1)
    btn.findLabel:Hide()

    btn.service = service
    btn.resolution = nil
    btn._isFindMode = false

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local res = self.resolution
        if res and res.state == "ready" then
            GameTooltip:SetText("|cff66cc66" .. service.label .. "|r: " .. (res.name or "?"), 1, 1, 1)
            GameTooltip:AddLine("Click to summon.", 0.7, 0.9, 0.7)
        elseif res and res.state == "cooldown" then
            GameTooltip:SetText("|cffffcc66" .. service.label .. "|r: " .. (res.name or "?"), 1, 1, 1)
            GameTooltip:AddLine("On cooldown.", 0.9, 0.7, 0.3)
        elseif res and res.state == "redundant" then
            GameTooltip:SetText("|cffaaaaaa" .. service.label .. "|r: " .. (res.name or "?"), 1, 1, 1)
            GameTooltip:AddLine("Not usable right now.", 0.7, 0.7, 0.7)
        else
            GameTooltip:SetText("|cff8888ff" .. service.label .. "|r", 1, 1, 1)
            GameTooltip:AddLine("Click to set a waypoint to the nearest " .. service.label:lower() .. ".", 0.5, 0.7, 1.0)
        end
        local nearest = PickNearestLocation(service)
        if nearest then
            GameTooltip:AddLine("Nearest: " .. nearest.zoneName .. " - " .. nearest.text, 0.5, 0.7, 1.0)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- PostClick fires after the secure action. If no secure type is set
    -- (find mode), we handle the click as a locate action here.
    btn:HookScript("PostClick", function(self)
        if self._isFindMode then
            LocateNearest(service)
        end
    end)

    return btn
end

local function EnsureDrawer()
    if clipFrame then return true end

    local mini = _G["FlipQueueMiniFrame"]
    if not mini then return false end

    -- Clip frame: anchored TOPRIGHT to mini's TOPLEFT with 3px overlap.
    -- Width starts at THUMB_WIDTH (collapsed) and animates to FULL_WIDTH.
    clipFrame = CreateFrame("Frame", "FlipQueueToolClip", mini)
    clipFrame:SetClipsChildren(true)
    clipFrame:SetSize(THUMB_WIDTH, CONTENT_HEIGHT)
    clipFrame:SetPoint("TOPRIGHT", mini, "TOPLEFT", 3, 0)
    clipFrame:SetFrameStrata("MEDIUM")

    -- Inner content frame: fixed width = FULL_WIDTH, anchored RIGHT to
    -- clip's RIGHT so it extends leftward. As clip width grows, the left
    -- portion of inner is revealed.
    innerFrame = CreateFrame("Frame", "FlipQueueToolContent", clipFrame, "BackdropTemplate")
    innerFrame:SetSize(FULL_WIDTH, CONTENT_HEIGHT)
    innerFrame:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, 0)
    innerFrame:SetBackdrop(DRAWER_BACKDROP)
    innerFrame:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
    innerFrame:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    -- Header label at the top of the content area.
    local header = innerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", innerFrame, "TOPLEFT", THUMB_WIDTH + PAD, -2)
    header:SetWidth(ICON_SIZE)
    header:SetJustifyH("CENTER")
    header:SetText("Tools")
    header:SetTextColor(0.8, 0.85, 1)

    -- Service icon buttons stacked vertically in the content area.
    for i, svc in ipairs(SERVICES) do
        serviceButtons[i] = CreateServiceButton(innerFrame, svc, i)
    end

    -- Thumb grip on the RIGHT edge of inner (closest to mini, always visible).
    thumbFrame = CreateFrame("Button", "FlipQueueToolTab", innerFrame)
    thumbFrame:SetWidth(THUMB_WIDTH)
    thumbFrame:SetPoint("TOPLEFT", innerFrame, "TOPLEFT", 0, 0)
    thumbFrame:SetPoint("BOTTOMLEFT", innerFrame, "BOTTOMLEFT", 0, 0)

    -- Grip lines: 3 vertical bars (1px wide, 16px tall, 3px apart).
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

    -- Width animation: interpolates clip width between THUMB_WIDTH and FULL_WIDTH.
    local animSpeed = CONTENT_WIDTH / ANIM_DURATION
    clipFrame:SetScript("OnUpdate", function(self, elapsed)
        if not animating then return end
        local cur = self:GetWidth()
        local diff = animTarget - cur
        local step = animSpeed * elapsed
        if math.abs(diff) <= step then
            self:SetWidth(animTarget)
            animating = false
        else
            self:SetWidth(cur + (diff > 0 and step or -step))
        end
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
    animTarget = FULL_WIDTH
    animating = true

    SaveDrawerShown(true)
    if UI.RefreshToolDrawer then UI:RefreshToolDrawer() end
end

function UI:HideToolDrawer()
    if not clipFrame then return end
    drawerOpen = false
    animTarget = THUMB_WIDTH
    animating = true

    SaveDrawerShown(false)
    if not (InCombatLockdown and InCombatLockdown()) then
        for _, btn in ipairs(serviceButtons) do
            if btn then
                btn:SetAttribute("type", nil)
                btn:SetAttribute("item", nil)
                btn:SetAttribute("spell", nil)
            end
        end
    end
end

function UI:ToggleToolDrawer()
    if drawerOpen then
        UI:HideToolDrawer()
    else
        UI:ShowToolDrawer()
    end
end

function UI:IsToolDrawerShown()
    return drawerOpen
end

function UI:UpdateToolDrawerHeight()
    -- Called when mini height changes. Update clip height to match content.
    if not clipFrame then return end
    clipFrame:SetHeight(CONTENT_HEIGHT)
    innerFrame:SetHeight(CONTENT_HEIGHT)
end

function UI:RefreshToolDrawer()
    if not EnsureDrawer() then return end

    local mini = _G["FlipQueueMiniFrame"]
    if not mini or not mini:IsShown() then
        if clipFrame then clipFrame:Hide() end
        return
    end

    clipFrame:Show()

    -- Restore saved state on first refresh after login.
    if ns.db and ns.db.settings then
        local saved = ns.db.settings.toolDrawerShown
        if saved == true and not drawerOpen and not animating then
            drawerOpen = true
            clipFrame:SetWidth(FULL_WIDTH)
            animTarget = FULL_WIDTH
        elseif (saved == false or saved == nil) and not drawerOpen then
            clipFrame:SetWidth(THUMB_WIDTH)
        end
    end

    if not drawerOpen then return end

    -- Cannot re-assign secure attributes during combat.
    local inCombat = InCombatLockdown and InCombatLockdown()

    for i, svc in ipairs(SERVICES) do
        local btn = serviceButtons[i]
        if btn then
            local res = ResolveService(svc)
            btn.resolution = res

            -- Show the resolved summon's icon if available, otherwise the
            -- category fallback (mail envelope, coin, bag, etc.)
            btn.tex:SetTexture(res.icon or svc.iconFallback)

            local isFindMode = (res.state == "unowned")
            btn._isFindMode = isFindMode

            if res.state == "ready" then
                btn.tex:SetDesaturated(false)
                btn.tex:SetVertexColor(1, 1, 1)
                btn:SetBackdropBorderColor(0.4, 0.8, 0.4, 0.9)
                btn.findArrow:Hide()
                btn.findLabel:Hide()
            elseif res.state == "cooldown" then
                btn.tex:SetDesaturated(false)
                btn.tex:SetVertexColor(1, 1, 1)
                btn:SetBackdropBorderColor(0.9, 0.7, 0.3, 0.9)
                btn.findArrow:Hide()
                btn.findLabel:Hide()
            elseif res.state == "redundant" then
                btn.tex:SetDesaturated(true)
                btn.tex:SetVertexColor(0.6, 0.6, 0.6)
                btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
                btn.findArrow:Hide()
                btn.findLabel:Hide()
            else
                -- No summon available — show as "Find" mode with dimmed icon
                btn.tex:SetDesaturated(true)
                btn.tex:SetVertexColor(0.3, 0.3, 0.4)
                btn:SetBackdropBorderColor(0.3, 0.4, 0.6, 0.8)
                btn.findArrow:Show()
                btn.findLabel:Show()
            end

            if res.state == "cooldown" and res.cooldownStart and res.cooldownDuration then
                btn.cooldown:SetCooldown(res.cooldownStart, res.cooldownDuration)
            else
                btn.cooldown:Clear()
            end

            if not inCombat then
                btn:SetAttribute("type", nil)
                btn:SetAttribute("item", nil)
                btn:SetAttribute("spell", nil)
                btn._isFindMode = isFindMode
                if res.state == "ready" and res.name then
                    if res.kind == "spell" then
                        btn:SetAttribute("type", "spell")
                        btn:SetAttribute("spell", res.name)
                    else
                        btn:SetAttribute("type", "item")
                        btn:SetAttribute("item", res.name)
                    end
                    btn:Enable()
                end
            end
        end
    end
end

--------------------------
-- Event handling
--------------------------

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
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
        serviceState.mailOpen = true
    elseif event == "MAIL_CLOSED" then
        serviceState.mailOpen = false
    elseif event == "AUCTION_HOUSE_SHOW" then
        serviceState.auctionOpen = true
    elseif event == "AUCTION_HOUSE_CLOSED" then
        serviceState.auctionOpen = false
    elseif event == "BANKFRAME_OPENED" then
        serviceState.bankOpen = true
    elseif event == "BANKFRAME_CLOSED" then
        serviceState.bankOpen = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        serviceState.mailOpen = false
        serviceState.auctionOpen = false
        serviceState.bankOpen = false
    end
    if UI.RefreshToolDrawer then UI:RefreshToolDrawer() end
end)
