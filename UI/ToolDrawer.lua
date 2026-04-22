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
            -- Trader's Gilded Brutosaur -- shop mount with AH + mailbox NPCs.
            { kind = "mount", id = 2265, name = "Trader's Gilded Brutosaur" },
            -- Katy's Stampwhistle -- toy, summons a mailbox for 10 min.
            { kind = "toy", id = 156833, name = "Katy's Stampwhistle" },
            -- MOLL-E -- engineer-crafted, summons a mailbox for 10 min.
            { kind = "item", id = 54710, name = "MOLL-E" },
        },
        locations = {
            { map = 2339, x = 0.56, y = 0.45, zoneName = "Dornogal", text = "Mailbox near Earthenfall Hall" },
            { map = 2112, x = 0.58, y = 0.57, zoneName = "Valdrakken", text = "Seat of the Aspects mailbox" },
            { map = 1670, x = 0.49, y = 0.28, zoneName = "Oribos", text = "Ring of Transference mailbox" },
            { map = 627,  x = 0.50, y = 0.50, zoneName = "Dalaran", text = "Magus Commerce Exchange mailbox" },
            { map = 1161, x = 0.73, y = 0.12, zoneName = "Boralus", text = "Tradewinds Market mailbox", faction = "Alliance" },
            { map = 1165, x = 0.53, y = 0.88, zoneName = "Dazar'alor", text = "The Great Seal mailbox", faction = "Horde" },
            { map = 84,   x = 0.60, y = 0.65, zoneName = "Stormwind", text = "Trade District mailbox", faction = "Alliance" },
            { map = 85,   x = 0.54, y = 0.55, zoneName = "Orgrimmar", text = "Valley of Strength mailbox", faction = "Horde" },
            { map = 87,   x = 0.27, y = 0.07, zoneName = "Ironforge", text = "The Commons mailbox", faction = "Alliance" },
            { map = 88,   x = 0.46, y = 0.58, zoneName = "Thunder Bluff", text = "Lower Rise mailbox", faction = "Horde" },
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
            -- Trader's Gilded Brutosaur -- shop mount with AH + mailbox NPCs.
            { kind = "mount", id = 2265, name = "Trader's Gilded Brutosaur" },
            -- Traveler's Anchorite -- TWW expedition mount with an AH NPC.
            -- Mount ID and spell name per the mount journal entry.
            { kind = "mount", id = 2332, name = "Traveler's Anchorite" },
        },
        locations = {
            { map = 2339, x = 0.48, y = 0.52, zoneName = "Dornogal", text = "Auction House" },
            { map = 2112, x = 0.40, y = 0.56, zoneName = "Valdrakken", text = "Auction House" },
            { map = 1670, x = 0.45, y = 0.28, zoneName = "Oribos", text = "Auction House" },
            { map = 1161, x = 0.73, y = 0.10, zoneName = "Boralus", text = "Tradewinds Market Auction House", faction = "Alliance" },
            { map = 1165, x = 0.53, y = 0.88, zoneName = "Dazar'alor", text = "The Great Seal Auction House", faction = "Horde" },
            { map = 84,   x = 0.60, y = 0.70, zoneName = "Stormwind", text = "Trade District Auction House", faction = "Alliance" },
            { map = 85,   x = 0.54, y = 0.58, zoneName = "Orgrimmar", text = "Valley of Strength Auction House", faction = "Horde" },
            { map = 87,   x = 0.25, y = 0.07, zoneName = "Ironforge", text = "The Commons Auction House", faction = "Alliance" },
            { map = 88,   x = 0.46, y = 0.58, zoneName = "Thunder Bluff", text = "Lower Rise Auction House", faction = "Horde" },
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
            { map = 627,  x = 0.36, y = 0.44, zoneName = "Dalaran", text = "Dalaran Bank" },
            { map = 1161, x = 0.73, y = 0.12, zoneName = "Boralus", text = "Tradewinds Market Bank", faction = "Alliance" },
            { map = 1165, x = 0.53, y = 0.88, zoneName = "Dazar'alor", text = "The Great Seal Bank", faction = "Horde" },
            { map = 84,   x = 0.60, y = 0.62, zoneName = "Stormwind", text = "Trade District Bank", faction = "Alliance" },
            { map = 85,   x = 0.55, y = 0.58, zoneName = "Orgrimmar", text = "Valley of Strength Bank", faction = "Horde" },
            { map = 87,   x = 0.36, y = 0.60, zoneName = "Ironforge", text = "The Vault Bank", faction = "Alliance" },
            { map = 88,   x = 0.45, y = 0.50, zoneName = "Thunder Bluff", text = "High Rise Bank", faction = "Horde" },
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
            { map = 1670, x = 0.47, y = 0.30, zoneName = "Oribos", text = "Warband Bank (bank NPC)" },
            { map = 627,  x = 0.36, y = 0.44, zoneName = "Dalaran", text = "Warband Bank (Dalaran Bank)" },
            { map = 1161, x = 0.73, y = 0.12, zoneName = "Boralus", text = "Warband Bank (Tradewinds Market)", faction = "Alliance" },
            { map = 1165, x = 0.53, y = 0.88, zoneName = "Dazar'alor", text = "Warband Bank (Great Seal)", faction = "Horde" },
            { map = 84,   x = 0.60, y = 0.62, zoneName = "Stormwind", text = "Warband Bank (Trade District)", faction = "Alliance" },
            { map = 85,   x = 0.55, y = 0.58, zoneName = "Orgrimmar", text = "Warband Bank (Valley of Strength)", faction = "Horde" },
            { map = 87,   x = 0.36, y = 0.60, zoneName = "Ironforge", text = "Warband Bank (The Vault)", faction = "Alliance" },
            { map = 88,   x = 0.45, y = 0.50, zoneName = "Thunder Bluff", text = "Warband Bank (High Rise)", faction = "Horde" },
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

-- Translate a map-local position to world coordinates (yards). Returns
-- wx, wy or nil if the API is unavailable or the map has no world frame.
local function MapToWorld(mapID, x, y)
    if not C_Map.GetWorldPosFromMapPos then return nil end
    local ok, _, worldPos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and worldPos then return worldPos:GetXY() end
    return nil
end

--------------------------
-- Location Learning
--------------------------

-- Service key → the service type names we care about in learned locations.
local SERVICE_LEARN_KEY = {
    mail         = "mail",
    auctionHouse = "auctionHouse",
    bank         = "bank",
    warbank      = "bank",  -- warbank uses the same bank NPCs
}

-- Timestamp of the last time a summon item/toy/mount button was clicked.
-- Used to suppress recording player-spawned temporary locations.
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

    -- Suppress if a summon was used recently (temporary mailbox/bank)
    if GetTime() - lastSummonClickTime < SUMMON_SUPPRESS_WINDOW then return end

    local db = ns.db.knownLocations
    db[serviceKey] = db[serviceKey] or {}
    db[serviceKey][mapID] = db[serviceKey][mapID] or {}
    local mapLocs = db[serviceKey][mapID]

    -- Deduplicate: skip if within 2% of an existing entry
    local DEDUP = 0.02
    for _, loc in ipairs(mapLocs) do
        local dx = loc.x - px
        local dy = loc.y - py
        if dx * dx + dy * dy < DEDUP * DEDUP then return end
    end

    -- Cap at 15 entries per map per service
    if #mapLocs >= 15 then return end

    local mapInfo = C_Map.GetMapInfo(mapID)
    local zoneName = mapInfo and mapInfo.name or "Unknown"
    mapLocs[#mapLocs + 1] = { x = px, y = py, zoneName = zoneName }
end

-- Query learned locations for a service on a given map.
-- Returns array of {map, x, y, zoneName, text} matching the static format.
local function GetLearnedLocations(serviceKey, mapID)
    if not ns.db or not ns.db.knownLocations then return {} end
    local db = ns.db.knownLocations[serviceKey]
    if not db then return {} end

    local results = {}
    -- If a specific map is requested, return only that map's entries.
    -- If mapID is nil, return all learned locations.
    local maps = mapID and { [mapID] = db[mapID] } or db
    for mID, locs in pairs(maps) do
        if type(locs) == "table" then
            for _, loc in ipairs(locs) do
                results[#results + 1] = {
                    map = mID,
                    x = loc.x,
                    y = loc.y,
                    zoneName = loc.zoneName or "Learned",
                    text = "Learned location",
                    learned = true,
                }
            end
        end
    end
    return results
end

-- Unified location picker: merges learned locations with static locations,
-- then applies faction filtering and distance ranking.
local function FindNearestService(service)
    local serviceKey = SERVICE_LEARN_KEY[service.key] or service.key
    local curMap = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local playerFaction = UnitFactionGroup and UnitFactionGroup("player") or nil

    -- Merge: learned locations for the current map first, then all learned,
    -- then static locations. Learned same-map entries get priority.
    local allLocs = {}

    -- Tier 1: learned locations on the current map
    if curMap then
        for _, loc in ipairs(GetLearnedLocations(serviceKey, curMap)) do
            allLocs[#allLocs + 1] = loc
        end
    end

    -- Tier 2: static locations (faction-filtered)
    for _, loc in ipairs(service.locations or {}) do
        if not loc.faction or loc.faction == playerFaction then
            allLocs[#allLocs + 1] = loc
        end
    end

    -- Tier 3: learned locations on other maps (for cross-map fallback)
    for _, loc in ipairs(GetLearnedLocations(serviceKey, nil)) do
        if loc.map ~= curMap then
            allLocs[#allLocs + 1] = loc
        end
    end

    if #allLocs == 0 then return nil end
    if not curMap then return allLocs[1] end

    -- Player position
    local px, py
    if C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(curMap, "player")
        if pos then px, py = pos:GetXY() end
    end

    -- Pass 1: same-map entries by map-space distance
    local bestLoc, bestDist = nil, math.huge
    for _, loc in ipairs(allLocs) do
        if loc.map == curMap and px and py then
            local dx = (loc.x or 0) - px
            local dy = (loc.y or 0) - py
            local d = dx * dx + dy * dy
            if d < bestDist then
                bestDist = d
                bestLoc = loc
            end
        elseif loc.map == curMap and not bestLoc then
            bestLoc = loc
        end
    end
    if bestLoc then return bestLoc end

    -- Pass 2: cross-map by world coordinates
    local pwx, pwy = MapToWorld(curMap, px or 0.5, py or 0.5)
    if pwx then
        local curContinent = GetContinentMap(curMap)
        bestLoc, bestDist = nil, math.huge
        for _, loc in ipairs(allLocs) do
            if GetContinentMap(loc.map) == curContinent then
                local lwx, lwy = MapToWorld(loc.map, loc.x or 0.5, loc.y or 0.5)
                if lwx then
                    local dx = lwx - pwx
                    local dy = lwy - pwy
                    local d = dx * dx + dy * dy
                    if d < bestDist then
                        bestDist = d
                        bestLoc = loc
                    end
                end
            end
        end
        if bestLoc then return bestLoc end
    end

    -- Pass 3: same-continent fallback
    local curContinent2 = GetContinentMap(curMap)
    if curContinent2 then
        for _, loc in ipairs(allLocs) do
            if GetContinentMap(loc.map) == curContinent2 then
                return loc
            end
        end
    end

    return allLocs[1]
end

local function LocateNearest(service)
    local loc = FindNearestService(service)
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
    local source = loc.learned and " (learned)" or ""
    ns:Print(ns.COLORS.CYAN .. "Waypoint:|r " .. loc.zoneName .. " -- " .. loc.text .. source)
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
local CONTENT_HEIGHT = HEADER_HEIGHT + 4 * ICON_SIZE + 3 * ICON_SPACING + PAD  -- 202
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

local drawerOpen   = false
local animating    = false
local animProgress = 0   -- 0 = fully closed, 1 = fully open
local animTarget   = 0   -- target value for animProgress

-- Height the thumb/clip collapses to when closed. Tracks the mini's current
-- height (capped at CONTENT_HEIGHT) so the thumb visually aligns with the
-- mini when the drawer is taller than the mini.
local thumbCollapsedHeight = 0

local function GetCollapsedThumbHeight()
    local mini = _G["FlipQueueMiniFrame"]
    local miniH = (mini and mini:GetHeight()) or CONTENT_HEIGHT
    if miniH <= 0 then miniH = CONTENT_HEIGHT end
    return math.min(miniH, CONTENT_HEIGHT)
end

-- Apply animation progress to clip width/height and thumb height.
-- Inner frame height stays at CONTENT_HEIGHT so button positions are stable
-- and the clip reveals them by growing downward.
local function ApplyAnimProgress(p)
    if not clipFrame then return end
    local w = THUMB_WIDTH + (FULL_WIDTH - THUMB_WIDTH) * p
    local h = thumbCollapsedHeight + (CONTENT_HEIGHT - thumbCollapsedHeight) * p
    clipFrame:SetWidth(w)
    clipFrame:SetHeight(h)
    if thumbFrame then thumbFrame:SetHeight(h) end
end

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
        local nearest = FindNearestService(service)
        if nearest then
            local tag = nearest.learned and " (learned)" or ""
            GameTooltip:AddLine("Nearest: " .. nearest.zoneName .. " - " .. nearest.text .. tag, 0.5, 0.7, 1.0)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- PostClick fires after the secure action. If no secure type is set
    -- (find mode), we handle the click as a locate action here. If a
    -- summon was used, record the time so LearnCurrentLocation can
    -- suppress recording player-spawned temporary services.
    btn:HookScript("PostClick", function(self)
        if self._isFindMode then
            LocateNearest(service)
        else
            lastSummonClickTime = GetTime()
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
    -- Height collapses to the mini's height when closed so the thumb doesn't
    -- extend past the mini; expands to CONTENT_HEIGHT when open.
    thumbCollapsedHeight = GetCollapsedThumbHeight()
    clipFrame = CreateFrame("Frame", "FlipQueueToolClip", mini)
    clipFrame:SetClipsChildren(true)
    clipFrame:SetSize(THUMB_WIDTH, thumbCollapsedHeight)
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

    -- Thumb grip at the top-left of inner (closest to mini, always visible).
    -- Height is animated: matches mini height when closed, grows to full
    -- drawer height when open.
    thumbFrame = CreateFrame("Button", "FlipQueueToolTab", innerFrame)
    thumbFrame:SetSize(THUMB_WIDTH, thumbCollapsedHeight)
    thumbFrame:SetPoint("TOPLEFT", innerFrame, "TOPLEFT", 0, 0)

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

    -- Unified progress animation: drives clip width, clip height, and thumb
    -- height together. Progress runs from 0 (closed) to 1 (open).
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
    -- Capture mini height so closing animates back to the right target.
    thumbCollapsedHeight = GetCollapsedThumbHeight()
    animTarget = 1
    animating = true

    SaveDrawerShown(true)
    if UI.RefreshToolDrawer then UI:RefreshToolDrawer() end
end

function UI:HideToolDrawer()
    if not clipFrame then return end
    drawerOpen = false
    -- Re-capture in case the mini was resized while drawer was open.
    thumbCollapsedHeight = GetCollapsedThumbHeight()
    animTarget = 0
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
    -- Called when mini height changes. Inner stays at CONTENT_HEIGHT so
    -- buttons remain positioned correctly; only the collapsed thumb target
    -- follows the mini height.
    if not clipFrame then return end
    innerFrame:SetHeight(CONTENT_HEIGHT)
    thumbCollapsedHeight = GetCollapsedThumbHeight()
    -- Re-apply so a mini resize while closed (or mid-animation) takes effect.
    if not animating then ApplyAnimProgress(animProgress) end
end

-- Pending-refresh flag: set when a refresh was requested during combat
-- lockdown. PLAYER_REGEN_ENABLED below re-runs the refresh once combat ends.
-- Needed because Show/Hide/SetSize on the drawer's clip frame are treated as
-- protected calls during combat — FlipQueueToolClip inherits protection from
-- its mini-view parent, so touching it fires ADDON_ACTION_BLOCKED.
local _pendingRefreshAfterCombat = false

function UI:RefreshToolDrawer()
    if not EnsureDrawer() then return end

    -- Any Show/Hide/Size/Anchor we'd do below is protected while combat is
    -- active. Skip the refresh and queue one for when combat ends.
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

    -- Restore saved state on first refresh after login.
    if ns.db and ns.db.settings then
        local saved = ns.db.settings.toolDrawerShown
        if saved == true and not drawerOpen and not animating then
            drawerOpen = true
            animProgress = 1
            animTarget = 1
            ApplyAnimProgress(1)
        elseif (saved == false or saved == nil) and not drawerOpen and not animating then
            thumbCollapsedHeight = GetCollapsedThumbHeight()
            animProgress = 0
            animTarget = 0
            ApplyAnimProgress(0)
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        serviceState.mailOpen = false
        serviceState.auctionOpen = false
        serviceState.bankOpen = false
    end
    if UI.RefreshToolDrawer then UI:RefreshToolDrawer() end
end)

-- Combat-end handler: if a refresh was queued during combat (the drawer
-- couldn't Show/Hide/resize due to the mini-view's protection chain), run it
-- now that PLAYER_REGEN_ENABLED has fired.
local combatEvt = CreateFrame("Frame")
combatEvt:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEvt:SetScript("OnEvent", function()
    if _pendingRefreshAfterCombat and UI.RefreshToolDrawer then
        _pendingRefreshAfterCombat = false
        UI:RefreshToolDrawer()
    end
end)
