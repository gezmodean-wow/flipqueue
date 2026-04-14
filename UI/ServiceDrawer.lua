-- UI/ServiceDrawer.lua
-- Services drawer for the mini overlay: one-click summon of mail / AH / bank / warband
-- access items, or a "locate nearest" waypoint fallback for the nearest static NPC.
local addonName, ns = ...

local UI = ns.UI

-- Event-driven service state. More reliable than polling BankFrame:IsShown()
-- which can be wrong if another addon keeps the frame around.
local serviceState = {
    mailOpen = false,
    auctionOpen = false,
    bankOpen = false,
}

--------------------------
-- Data tables
--------------------------

-- Service definitions. Each entry maps to one column in the drawer.
-- `summons` is an ordered preference list — put the best summon at the top.
-- Each entry has:
--   kind = "item" or "spell"
--   id   = item ID (for items) or spell ID (for spells)
--   name = display name (also used as the secure-button attribute value)
local SERVICES = {
    {
        key = "mail",
        label = "Mail",
        iconFallback = "Interface\\Icons\\INV_Letter_15",
        summons = {
            -- TODO: fill in known mailbox-summoning items, e.g.
            -- { kind = "item", id = 141605, name = "Courier's Stampwhistle" },
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
            -- TODO: verify item IDs for these mounts / items
            -- { kind = "item", id = 163036, name = "Reins of the Mighty Caravan Brutosaur" },
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
            -- TODO: fill in banker-summoning items, e.g.
            -- { kind = "item", id = ?, name = "Signet of the Restless Ward" },
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
            -- Warband Bank Distance Inhibitor — quest reward spell from
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
    if C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(spellID)
    elseif GetSpellTexture then
        icon = GetSpellTexture(spellID)
    end

    return true, icon, remaining, start, duration
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
        local owned, icon, remaining, cdStart, cdDur
        if summon.kind == "spell" then
            owned, icon, remaining, cdStart, cdDur = CheckSpellSummon(summon.id)
        else
            owned, icon, remaining, cdStart, cdDur = CheckItemSummon(summon.id)
        end

        if owned then
            icon = icon or service.iconFallback
            if inService then
                if not firstOwnedRedundant then
                    firstOwnedRedundant = {
                        kind = summon.kind, id = summon.id, name = summon.name,
                        icon = icon, state = "redundant",
                    }
                end
            elseif remaining and remaining > 0 then
                if not firstOwnedCooldown then
                    firstOwnedCooldown = {
                        kind = summon.kind, id = summon.id, name = summon.name,
                        icon = icon, state = "cooldown",
                        cooldownStart = cdStart, cooldownDuration = cdDur,
                    }
                end
            else
                -- Usability check: for items we use IsUsableItem (returns false for
                -- things like mounts in no-mount zones). For spells we trust the
                -- cooldown+known check and let the secure click handler decide — the
                -- engine-side usability probes can be overly conservative and falsely
                -- mark known off-cooldown spells as unusable.
                local usable = true
                if summon.kind ~= "spell" then
                    local v = IsUsableItem and IsUsableItem(summon.id)
                    if v == false then usable = false end
                end
                if not usable then
                    if not firstOwnedRedundant then
                        firstOwnedRedundant = {
                            kind = summon.kind, id = summon.id, name = summon.name,
                            icon = icon, state = "redundant",
                        }
                    end
                else
                    return {
                        kind = summon.kind, id = summon.id, name = summon.name,
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

local function PickNearestLocation(service)
    if not service.locations or #service.locations == 0 then return nil end
    local curMap = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil

    if curMap then
        -- Same-map match first
        for _, loc in ipairs(service.locations) do
            if loc.map == curMap then return loc end
        end
        -- Same-continent match (walk parent chain)
        local continent = curMap
        local guard = 0
        while continent and guard < 10 do
            local info = C_Map.GetMapInfo(continent)
            if info and info.mapType and info.mapType <= 2 then break end
            if info and info.parentMapID and info.parentMapID > 0 then
                continent = info.parentMapID
            else
                break
            end
            guard = guard + 1
        end
        if continent then
            for _, loc in ipairs(service.locations) do
                local locInfo = C_Map.GetMapInfo(loc.map)
                local locContinent = loc.map
                local g2 = 0
                while locInfo and g2 < 10 do
                    if locInfo.mapType and locInfo.mapType <= 2 then break end
                    if locInfo.parentMapID and locInfo.parentMapID > 0 then
                        locContinent = locInfo.parentMapID
                        locInfo = C_Map.GetMapInfo(locContinent)
                    else
                        break
                    end
                    g2 = g2 + 1
                end
                if locContinent == continent then return loc end
            end
        end
    end

    -- Fallback to first entry
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
    ns:Print(ns.COLORS.CYAN .. "Waypoint:|r " .. loc.zoneName .. " — " .. loc.text)
end

--------------------------
-- Drawer frame construction
--------------------------

local drawer = nil
local serviceCols = {}

local DRAWER_PAD = 4
local ICON_SIZE = 32
local LOCATE_BTN_HEIGHT = 16
local COL_WIDTH = 44
local COL_SPACING = 4

local function CreateServiceColumn(parent, service, index)
    local col = CreateFrame("Frame", nil, parent)
    col:SetSize(COL_WIDTH, ICON_SIZE + 2 + LOCATE_BTN_HEIGHT)
    col:SetPoint("TOPLEFT", parent, "TOPLEFT",
        DRAWER_PAD + (index - 1) * (COL_WIDTH + COL_SPACING),
        -DRAWER_PAD)

    -- Secure summon button (icon row). The "type" attribute is set per-refresh
    -- based on whether the resolved summon is an item or a spell.
    local btn = CreateFrame("Button", "FlipQueueServiceBtn_" .. service.key, col, "SecureActionButtonTemplate, BackdropTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:SetPoint("TOP", col, "TOP", 0, 0)
    btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")

    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.10, 0.10, 0.14, 0.9)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    btn.tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cooldown:SetPoint("TOPLEFT", btn.tex, "TOPLEFT", 0, 0)
    btn.cooldown:SetPoint("BOTTOMRIGHT", btn.tex, "BOTTOMRIGHT", 0, 0)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints(btn.tex)
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)

    btn.service = service
    btn.resolution = nil

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        local res = self.resolution
        if res and res.state == "ready" then
            GameTooltip:SetText("|cff66cc66" .. service.label .. "|r: " .. (res.name or "?"), 1, 1, 1)
            GameTooltip:AddLine("Click to summon.", 0.7, 0.9, 0.7)
        elseif res and res.state == "cooldown" then
            GameTooltip:SetText("|cffffcc66" .. service.label .. "|r: " .. (res.name or "?"), 1, 1, 1)
            GameTooltip:AddLine("On cooldown.", 0.9, 0.7, 0.3)
        elseif res and res.state == "redundant" then
            GameTooltip:SetText("|cffaaaaaa" .. service.label .. "|r: " .. (res.name or "?"), 1, 1, 1)
            GameTooltip:AddLine("Not usable right now (already in service or restricted).", 0.7, 0.7, 0.7)
        else
            GameTooltip:SetText("|cff888888" .. service.label .. "|r", 1, 1, 1)
            GameTooltip:AddLine("No summon available. Use Find below.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Locate Nearest button (text row)
    local locBtn = CreateFrame("Button", nil, col, "BackdropTemplate")
    locBtn:SetSize(COL_WIDTH, LOCATE_BTN_HEIGHT)
    locBtn:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    locBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    locBtn:SetBackdropColor(0.12, 0.14, 0.20, 0.9)
    locBtn:SetBackdropBorderColor(0.3, 0.35, 0.5, 0.8)
    locBtn.text = locBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    locBtn.text:SetPoint("CENTER")
    locBtn.text:SetText("Find")
    locBtn.text:SetTextColor(0.8, 0.85, 1)
    locBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.22, 0.32, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Locate Nearest " .. service.label, 1, 1, 1)
        local maxShown = 3
        local shown = 0
        for _, loc in ipairs(service.locations or {}) do
            if shown >= maxShown then break end
            GameTooltip:AddLine("• " .. loc.zoneName .. " — " .. loc.text, 0.8, 0.8, 0.8)
            shown = shown + 1
        end
        GameTooltip:AddLine("Click to set a map waypoint.", 0.6, 0.8, 0.6)
        GameTooltip:Show()
    end)
    locBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.14, 0.20, 0.9)
        GameTooltip:Hide()
    end)
    locBtn:SetScript("OnClick", function() LocateNearest(service) end)

    col.btn = btn
    col.locBtn = locBtn
    return col
end

local function EnsureDrawer()
    if drawer then return drawer end

    local mini = _G["FlipQueueMiniFrame"]
    if not mini then return nil end

    -- Floating popout: fixed width, anchored TOP-center to mini's BOTTOM-center.
    -- It's a child of the mini so it moves with the mini, but its width is independent.
    drawer = CreateFrame("Frame", "FlipQueueServiceDrawer", mini, "BackdropTemplate")

    local totalW = DRAWER_PAD * 2 + #SERVICES * COL_WIDTH + (#SERVICES - 1) * COL_SPACING
    local totalH = DRAWER_PAD * 2 + ICON_SIZE + 4 + LOCATE_BTN_HEIGHT

    drawer:SetSize(totalW, totalH)
    drawer:ClearAllPoints()
    drawer:SetPoint("TOP", mini, "BOTTOM", 0, -4)
    drawer:SetFrameStrata("MEDIUM")

    drawer:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    drawer:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
    drawer:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.9)

    for i, svc in ipairs(SERVICES) do
        serviceCols[i] = CreateServiceColumn(drawer, svc, i)
    end

    drawer.minContentWidth = totalW
    drawer:Hide()
    return drawer
end

--------------------------
-- Public API
--------------------------

function UI:GetServiceDrawer()
    return drawer or EnsureDrawer()
end

function UI:IsServiceDrawerShown()
    return drawer and drawer:IsShown() or false
end

local function SaveDrawerShown(shown)
    if ns.db and ns.db.settings then
        ns.db.settings.serviceDrawerShown = shown and true or false
    end
end

function UI:ShowServiceDrawer()
    local d = EnsureDrawer()
    if not d then return end
    local mini = _G["FlipQueueMiniFrame"]
    if not mini or not mini:IsShown() then return end
    d:Show()
    SaveDrawerShown(true)
    if UI.RefreshServiceDrawer then UI:RefreshServiceDrawer() end
end

function UI:HideServiceDrawer()
    if drawer then drawer:Hide() end
    SaveDrawerShown(false)
end

function UI:ToggleServiceDrawer()
    if UI:IsServiceDrawerShown() then
        UI:HideServiceDrawer()
    else
        UI:ShowServiceDrawer()
    end
end

function UI:RefreshServiceDrawer()
    local d = EnsureDrawer()
    if not d then return end

    local mini = _G["FlipQueueMiniFrame"]
    if not mini or not mini:IsShown() then
        d:Hide()
        return
    end

    -- Restore saved visibility on first refresh after load.
    -- If the user explicitly hid the drawer, stay hidden.
    if ns.db and ns.db.settings and ns.db.settings.serviceDrawerShown == false then
        d:Hide()
        return
    end

    -- Default: if the setting has never been set, drawer stays hidden until the
    -- user clicks the header toggle button.
    if ns.db and ns.db.settings and ns.db.settings.serviceDrawerShown == nil then
        d:Hide()
        return
    end

    d:Show()

    -- Cannot re-assign secure attributes during combat — defer refresh in that case
    local inCombat = InCombatLockdown and InCombatLockdown()

    for i, svc in ipairs(SERVICES) do
        local col = serviceCols[i]
        if col then
            local res = ResolveService(svc)
            local btn = col.btn
            btn.resolution = res

            -- Icon
            btn.tex:SetTexture(res.icon or svc.iconFallback)

            -- Visual state
            if res.state == "ready" then
                btn.tex:SetDesaturated(false)
                btn.tex:SetVertexColor(1, 1, 1)
                btn:SetBackdropBorderColor(0.4, 0.8, 0.4, 0.9)
            elseif res.state == "cooldown" then
                btn.tex:SetDesaturated(false)
                btn.tex:SetVertexColor(1, 1, 1)
                btn:SetBackdropBorderColor(0.9, 0.7, 0.3, 0.9)
            elseif res.state == "redundant" then
                btn.tex:SetDesaturated(true)
                btn.tex:SetVertexColor(0.6, 0.6, 0.6)
                btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
            else
                btn.tex:SetDesaturated(true)
                btn.tex:SetVertexColor(0.45, 0.45, 0.45)
                btn:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.6)
            end

            -- Cooldown swipe
            if res.state == "cooldown" and res.cooldownStart and res.cooldownDuration then
                btn.cooldown:SetCooldown(res.cooldownStart, res.cooldownDuration)
            else
                btn.cooldown:Clear()
            end

            -- Secure attribute (combat-safe). Item vs spell uses different keys.
            if not inCombat then
                -- Clear both possible attribute keys before re-assigning
                btn:SetAttribute("type", nil)
                btn:SetAttribute("item", nil)
                btn:SetAttribute("spell", nil)
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
                -- Non-ready states leave type/item/spell unset (button becomes a no-op on click)
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
        -- All service frames are closed on zone transitions
        serviceState.mailOpen = false
        serviceState.auctionOpen = false
        serviceState.bankOpen = false
    end
    if UI.RefreshServiceDrawer then UI:RefreshServiceDrawer() end
end)
