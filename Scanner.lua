-- Scanner.lua
-- Projects Syndicator's per-slot inventory cache into FlipQueue's
-- aggregated `itemKey -> {quantity, locations}` shape so downstream code
-- (TodoGenerator, TrackerBank, UI pages) keeps reading the same structures
-- it always has: `ns.db.characters[charKey].inventory.items` and
-- `ns.db.warbank.items`.
--
-- Phase 6a (v0.11.0): Syndicator is a hard dependency. All bag/bank/warbank
-- scanning routed through Syndicator's API instead of walking C_Container
-- directly. Guild bank stays on the Blizzard API (Syndicator doesn't handle
-- it). Character metadata (gold, class, level, guild, accountUUID) still
-- lives here and still updates on PLAYER_LOGIN / PLAYER_MONEY.

local addonName, ns = ...

local Scanner = {}
ns.Scanner = Scanner

--------------------------
-- Deal enrichment (unchanged from pre-6a)
--------------------------

-- When we scan physical items, backfill import entries that have incomplete
-- data. Imports from FP often arrive with bare item IDs (no bonus IDs, no
-- icon, no quality). The scanned item has the real hyperlink data — use it
-- to fill the gaps.
local function EnrichDealsFromInventory(scannedItems)
    if not ns.db or not ns.db.imports or not ns.db.imports.fpScanner then return end

    for _, queueItem in pairs(ns.db.imports.fpScanner) do
        local queueNumID = tonumber(queueItem.itemID) or tonumber((queueItem.itemKey or ""):match("^(%d+)"))
        local queueName = (queueItem.name or ""):lower()
        local queueHasBonuses = queueItem.itemKey and queueItem.itemKey:match("^[^;]*;([^;]*)") or ""

        if queueHasBonuses == "" and queueNumID then
            for key, itemData in pairs(scannedItems) do
                local scannedNumID = tonumber((key:match("^(%d+)")))
                local scannedBonuses = key:match("^[^;]*;([^;]*)") or ""
                local nameMatch = queueName ~= "" and itemData.name
                    and itemData.name:lower() == queueName

                if (scannedNumID and scannedNumID == queueNumID) or nameMatch then
                    if scannedBonuses ~= "" then
                        queueItem.itemKey = key
                        queueItem.bonusIDs = itemData.bonusIDs
                        queueItem.modifiers = itemData.modifiers
                    end
                    if not queueItem.icon and itemData.icon then
                        queueItem.icon = itemData.icon
                    end
                    if (not queueItem.name or queueItem.name == "") and itemData.name then
                        queueItem.name = itemData.name
                    end
                    if not queueItem.quality or queueItem.quality == "" then
                        local numID = tonumber(itemData.itemID)
                        if numID and numID > 0 then
                            local ok, _, _, q = pcall(C_Item.GetItemInfo, numID)
                            if ok and q then
                                local qualityNames = {[0]="Poor",[1]="Common",[2]="Uncommon",
                                    [3]="Rare",[4]="Epic",[5]="Legendary"}
                                queueItem.quality = qualityNames[q] or ""
                            end
                        end
                    end
                    break
                end
            end
        end
    end
end

--------------------------
-- Syndicator projection helpers
--------------------------

-- Build the FlipQueue Syndicator key for the current character. Syndicator
-- uses "Name-NormalizedRealm" where normalized strips spaces ("Earthen Ring"
-- becomes "EarthenRing"). FlipQueue's own charKey uses the display realm
-- (with spaces), so the two can't be used interchangeably.
local function CurrentSyndicatorKey()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
    if not name or not realm then return nil end
    return name .. "-" .. realm
end

-- Shared helper: take a Syndicator container-slot list and fold each slot
-- into the caller's items table, tagging quantities against `location`.
-- The `items` table has the pre-6a shape: `items[key] = { itemID, bonusIDs,
-- modifiers, quantity, icon, ilvl, bindType, isBound, locations = {...} }`.
-- Battle pets are handled via link parsing (Syndicator includes the full
-- caged-pet hyperlink).
local function FoldContainerSlots(slots, items, location)
    if type(slots) ~= "table" then return end
    for _, slot in ipairs(slots) do
        local link = slot and slot.itemLink
        if link and link ~= "" then
            local key = ns.ItemLookup and ns.ItemLookup:GetItemKey(link) or nil
            if key then
                local entry = items[key]
                if not entry then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(link)
                    local itemName
                    local ilvl = 0
                    local bindType = 0
                    if link:find("|Hbattlepet:") then
                        itemName = link:match("|h%[(.-)%]|h")
                    else
                        -- C_Item.GetItemInfo returns (name, link, quality,
                        -- ilvl, reqLevel, class, subclass, stackCount,
                        -- equipLoc, texture, sellPrice, classID, subclassID,
                        -- bindType, expacID, setID, isCraftingReagent).
                        -- bindType is index 14 — downstream code filters on
                        -- it (BoP=1, Quest=4, BtA=7, BtW=8) to exclude
                        -- non-tradeable items from the deal pool.
                        -- Single combined call: previously this fired
                        -- C_Item.GetItemInfo twice per unique slot (once for
                        -- bindType, once for name). Halving the call count
                        -- materially reduces relog projection cost when many
                        -- alts are bulk-projected at PLAYER_LOGIN (FQ-137
                        -- followup).
                        local ok, n, _, _, _, _, _, _, _, _, _, _, _, _, bt =
                            pcall(C_Item.GetItemInfo, link)
                        if ok then
                            itemName = n
                            if bt then bindType = bt end
                        end
                        if GetDetailedItemLevelInfo then
                            local okIlvl, result = pcall(GetDetailedItemLevelInfo, link)
                            if okIlvl and result then ilvl = tonumber(result) or 0 end
                        end
                    end
                    entry = {
                        itemID    = itemID,
                        name      = itemName or "Unknown",
                        bonusIDs  = bonusIDs or "",
                        modifiers = modifiers or "",
                        quantity  = 0,
                        icon      = slot.iconTexture,
                        ilvl      = ilvl,
                        locations = {},
                        bindType  = bindType,
                        isBound   = slot.isBound and true or false,
                    }
                    items[key] = entry
                end
                local count = slot.itemCount or 1
                entry.quantity = entry.quantity + count
                if location then
                    entry.locations[location] = (entry.locations[location] or 0) + count
                end
            end
        end
    end
end

-- Project Syndicator's per-character data into FlipQueue's character.inventory
-- shape. Walks bags → "bags", reagent bag → "reagent", bank tabs → "bank".
-- Syndicator groups bag slots under `charData.bags` (array keyed by bag index).
local function ProjectCharacterInventory(charData)
    local items = {}
    if type(charData) ~= "table" then return items end

    if type(charData.bags) == "table" then
        -- bags[1..4] are the normal backpack slots; bags[5] is the reagent
        -- bag in modern retail. Syndicator keys by the bag index, so a
        -- numeric iteration picks them up.
        for bagIndex, slots in pairs(charData.bags) do
            local loc = (bagIndex == 5) and "reagent" or "bags"
            FoldContainerSlots(slots, items, loc)
        end
    end

    if type(charData.bank) == "table" then
        -- bank is a list of tab slot arrays; we don't care which tab, just
        -- that it's bank-side. If Syndicator exposes it as a flat array of
        -- slots instead, FoldContainerSlots handles that too.
        for _, tab in pairs(charData.bank) do
            if type(tab) == "table" then
                -- Heuristic: if the first entry looks like a slot (has
                -- itemLink or is nil), this tab IS the slot list; otherwise
                -- it's a tab wrapper with its own slot subtable.
                if tab.itemLink or tab.itemCount or #tab == 0 then
                    FoldContainerSlots({tab}, items, "bank")
                else
                    FoldContainerSlots(tab, items, "bank")
                end
            end
        end
    end

    return items
end

-- Project Syndicator's warband data into FlipQueue's ns.db.warbank shape.
-- Returns (items table, totalSlots, freeSlots) — the three fields required
-- by the to-do generator's warbank budget and the TodoPage header readout.
local function ProjectWarband(warbandData)
    local items = {}
    local totalSlots, freeSlots = 0, 0
    if type(warbandData) ~= "table" or type(warbandData.bank) ~= "table" then
        return items, 0, 0
    end

    for _, tab in pairs(warbandData.bank) do
        -- Each tab is { slots = {...}, name, iconTexture, depositFlags, ... }
        -- (or sometimes the slot list directly, depending on version).
        local slots = tab.slots or tab
        if type(slots) == "table" then
            for _, slot in ipairs(slots) do
                totalSlots = totalSlots + 1
                if not (slot and slot.itemLink and slot.itemLink ~= "") then
                    freeSlots = freeSlots + 1
                end
            end
            FoldContainerSlots(slots, items, nil)
        end
    end

    return items, totalSlots, freeSlots
end

--------------------------
-- Refresh entry points
--------------------------

-- Session-local debounce for the bulk-projection pass. The actual projection
-- cost per alt is small (one table walk) but we still cap it at one run per
-- 30s to avoid pounding Syndicator's API on every BagCacheUpdate burst.
local lastBulkProjectAt = 0
local BULK_PROJECT_DEBOUNCE = 30

-- Record a normalized-realm → display-realm alias into the persistent map.
-- This lets alt bulk-projection translate Syndicator's keys ("Jimmy-EarthenRing")
-- back to FlipQueue's display-realm keys ("Jimmy-Earthen Ring") without a
-- realm database lookup. The map only grows — entries are never deleted,
-- and collisions overwrite with the most recent display name.
local function RecordRealmAlias()
    if not ns.db then return end
    ns.db.realmAliases = ns.db.realmAliases or {}
    local display = GetRealmName and GetRealmName() or nil
    local normalized = GetNormalizedRealmName and GetNormalizedRealmName() or nil
    if display and normalized then
        ns.db.realmAliases[normalized] = display
    end
end

-- Given a Syndicator-format key "Name-NormalizedRealm", return the
-- FlipQueue-format key "Name-DisplayRealm" if the realm is in our alias
-- map. Returns nil when the realm is unknown — caller should skip the
-- char rather than guessing, since writing to the wrong key would split
-- the character's data across two records.
local function TranslateSyndicatorKey(synKey)
    if not synKey or not ns.db or not ns.db.realmAliases then return nil end
    local name, normalized = synKey:match("^(.-)%-(.+)$")
    if not name or not normalized then return nil end
    local display = ns.db.realmAliases[normalized]
    if not display then return nil end
    return name .. "-" .. display
end

-- Core projection writer: projects Syndicator's charData into
-- ns.db.characters[fqKey].inventory, stamps the syndicatorBacked flag,
-- emits the sync delta, and fires the shared Cogworks event. Used by
-- both current-character refresh and alt bulk-projection.
-- Cheap signature of an items table: count of unique keys + sum of quantities.
-- Two refreshes that produce the same signature are treated as no-ops for
-- sync-emit purposes — bag moves that net to zero (item picked up and put
-- back, or moved bag-to-bag) don't broadcast a CHAR delta to BNet partners.
local function InventorySignature(items)
    local count, qty = 0, 0
    for _, e in pairs(items) do
        count = count + 1
        qty = qty + (e.quantity or 0)
    end
    return count .. ":" .. qty
end

local function WriteProjectedInventory(fqKey, charData, sourceLabel)
    if not ns.db then return end
    -- Tombstoned characters are intentionally kept out of db.characters;
    -- silently skip rather than re-create them from Syndicator data.
    if ns:IsCharDeleted(fqKey) then return end
    ns.db.characters[fqKey] = ns.db.characters[fqKey] or {}
    local charEntry = ns.db.characters[fqKey]

    local prevInv = charEntry.inventory
    local prevSig = charEntry._invSig
    local items = ProjectCharacterInventory(charData)
    local newSig = InventorySignature(items)

    charEntry.inventory = {
        lastScan     = time(),
        lastBankScan = prevInv and prevInv.lastBankScan or time(),
        items        = items,
    }
    charEntry._invSig = newSig
    -- Migration indicator: this character's inventory came from a
    -- Syndicator projection, not from the old C_Container scanner.
    -- The Characters tab reads this flag to render a "Live" badge.
    charEntry.syndicatorBacked = true

    local count = 0
    for _ in pairs(items) do count = count + 1 end
    ns:PrintDebug("Syndicator refresh (" .. sourceLabel .. "): " .. count
        .. " unique items on " .. fqKey ..
        (prevSig == newSig and " [unchanged]" or ""))

    EnrichDealsFromInventory(items)

    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying
        and prevSig ~= newSig then
        ns.Sync:EmitDelta("CHAR", { charKey = fqKey, charData = charEntry })
    end

    -- Fire the shared Cogworks event so sibling cogs (a future Ledger,
    -- cross-cog dashboards) can react to inventory changes without knowing
    -- FlipQueue exists. Guarded by the nil-check in case Cogworks-1.0
    -- failed to load for any reason.
    if ns.cw and ns.cw.Fire then
        ns.cw:Fire(ns.cw.Events.InventoryChanged, fqKey)
    end
end

-- Walk Syndicator's known characters and project any whose normalized
-- realm is already in our alias map (meaning the user has logged into
-- that realm at least once). Skips the current character (already
-- refreshed) and any char outside the alias coverage. Debounced.
--
-- Yielded across frames: a player with many alts pays a multi-second
-- frame hitch on PLAYER_LOGIN if all projections run synchronously
-- (each alt walks its full bag/bank slot list, calls C_Item.GetItemInfo
-- per unique item, runs EnrichDealsFromInventory, emits a Sync delta).
-- Spreading one alt per frame via C_Timer.After(0) keeps the relog
-- snappy at the cost of seeing the full alt picture a fraction of a
-- second later (FQ-137 followup).
local bulkProjectInflight = false
local function BulkProjectKnownAlts()
    if bulkProjectInflight then return end
    if not (Syndicator and Syndicator.API and Syndicator.API.GetAllCharacters
        and Syndicator.API.GetByCharacterFullName) then
        return
    end
    local now = time()
    if now - lastBulkProjectAt < BULK_PROJECT_DEBOUNCE then return end
    lastBulkProjectAt = now

    local ok, allChars = pcall(Syndicator.API.GetAllCharacters)
    if not ok or type(allChars) ~= "table" then return end

    -- Build the work list synchronously, then drain it across frames.
    local currentSyn = CurrentSyndicatorKey()
    local todo = {}
    local skipped = 0
    for _, synKey in ipairs(allChars) do
        if synKey ~= currentSyn then
            local fqKey = TranslateSyndicatorKey(synKey)
            if fqKey then
                todo[#todo + 1] = { synKey = synKey, fqKey = fqKey }
            else
                skipped = skipped + 1
            end
        end
    end

    if #todo == 0 then
        if skipped > 0 then
            ns:PrintDebug("Bulk-project: 0 alt(s) refreshed, " .. skipped
                .. " skipped (realm not in alias map)")
        end
        return
    end

    bulkProjectInflight = true
    local projected = 0
    local function ProjectNext()
        local item = table.remove(todo, 1)
        if not item then
            bulkProjectInflight = false
            ns:PrintDebug("Bulk-project: " .. projected .. " alt(s) refreshed, "
                .. skipped .. " skipped (realm not in alias map)")
            return
        end
        local okChar, charData = pcall(Syndicator.API.GetByCharacterFullName, item.synKey)
        if okChar and type(charData) == "table" then
            WriteProjectedInventory(item.fqKey, charData, "alt")
            projected = projected + 1
        end
        C_Timer.After(0, ProjectNext)
    end
    C_Timer.After(0, ProjectNext)
end

function Scanner:RefreshCurrentCharacterFromSyndicator()
    if not ns.db then return end
    if not (Syndicator and Syndicator.API and Syndicator.API.GetByCharacterFullName) then
        return
    end

    -- Refresh the alias map every time we successfully read for the
    -- current char. Cheap, and ensures the map reflects realm renames
    -- or connected-realm promotions.
    RecordRealmAlias()

    local synKey = CurrentSyndicatorKey()
    if not synKey then return end

    local ok, charData = pcall(Syndicator.API.GetByCharacterFullName, synKey)
    if not ok or type(charData) ~= "table" then return end

    local fqKey = ns:GetCharKey()
    -- Tombstoned current character: skip the direct table access below
    -- (which would resurrect the row) and the projection. The bulk alt
    -- pass further down still runs, honoring its own tombstone checks.
    if ns:IsCharDeleted(fqKey) then
        BulkProjectKnownAlts()
        return
    end
    ns.db.characters[fqKey] = ns.db.characters[fqKey] or {}
    ns.db.characters[fqKey].class = select(2, UnitClass("player"))

    WriteProjectedInventory(fqKey, charData, "current")

    -- Opportunistic pass over Syndicator's other known characters. Only
    -- touches alts whose realm we've already got a display-name alias for,
    -- so the first login after migration projects current char's alts and
    -- subsequent logins reach further as the alias map grows.
    BulkProjectKnownAlts()
end

function Scanner:RefreshWarbankFromSyndicator()
    if not ns.db then return end
    if not (Syndicator and Syndicator.API and Syndicator.API.GetWarband) then return end

    local ok, warbandData = pcall(Syndicator.API.GetWarband, 1)
    if not ok or type(warbandData) ~= "table" then return end

    local items, totalSlots, freeSlots = ProjectWarband(warbandData)
    ns.db.warbank = {
        lastScan   = time(),
        items      = items,
        totalSlots = totalSlots,
        freeSlots  = freeSlots,
    }

    local count = 0
    for _ in pairs(items) do count = count + 1 end
    ns:PrintDebug("Warbank refresh: " .. count .. " unique items, "
        .. freeSlots .. "/" .. totalSlots .. " free.")

    EnrichDealsFromInventory(items)

    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
        ns.Sync:EmitDelta("WB", ns.db.warbank)
    end
end

-- Back-compat shims: older code throughout the addon still calls
-- Scanner:ScanCurrentCharacter / ScanBank / ScanWarbank on events like
-- PLAYERBANKSLOTS_CHANGED or from slash commands. Route those to the
-- Syndicator refresh so callers don't have to know the plumbing changed.
function Scanner:ScanCurrentCharacter() self:RefreshCurrentCharacterFromSyndicator() end
function Scanner:ScanBank() self:RefreshCurrentCharacterFromSyndicator() end
function Scanner:ScanWarbank() self:RefreshWarbankFromSyndicator() end

--------------------------
-- Guild Bank Scanning (unchanged — Syndicator doesn't handle guild banks)
--------------------------

local guildBankOpen = false
local guildBankScanning = false
local guildScanQueue = {}
local guildScanData = {}

local function ScanGuildBankTab(tab)
    local items = {}
    for slot = 1, 98 do
        local ok, texture, itemCount, locked = pcall(GetGuildBankItemInfo, tab, slot)
        if ok and texture and itemCount and itemCount > 0 then
            local okLink, link = pcall(GetGuildBankItemLink, tab, slot)
            if okLink and link then
                local itemID, bonusIDs, modifiers = ns:ParseItemLink(link)
                if itemID then
                    local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                    if not items[key] then
                        local itemName
                        if link:find("|Hbattlepet:") then
                            itemName = link:match("|h%[(.-)%]|h")
                        else
                            local okName, n = pcall(C_Item.GetItemInfo, link)
                            itemName = okName and n or nil
                        end
                        items[key] = {
                            itemID    = itemID,
                            name      = itemName or "Unknown",
                            bonusIDs  = bonusIDs,
                            modifiers = modifiers,
                            quantity  = 0,
                            icon      = texture,
                        }
                    end
                    items[key].quantity = items[key].quantity + itemCount
                end
            end
        end
    end
    return items
end

local function ProcessNextGuildTab()
    if #guildScanQueue == 0 then
        guildBankScanning = false
        if not ns.db then return end
        local guildName = GetGuildInfo("player") or "Unknown Guild"
        ns.db.guilds = ns.db.guilds or {}
        if not ns.db.guilds[guildName] then
            ns.db.guilds[guildName] = { enabled = true, members = {} }
        end
        ns.db.guilds[guildName].enabled = true
        ns.db.guilds[guildName].lastScan = time()
        ns.db.guilds[guildName].items = guildScanData
        local count = 0
        for _ in pairs(guildScanData) do count = count + 1 end
        ns:Print(ns.COLORS.CYAN .. "Guild bank scanned: " .. count .. " unique items (" .. guildName .. ")|r")
        guildScanData = {}
        return
    end

    local tab = table.remove(guildScanQueue, 1)
    QueryGuildBankTab(tab)
end

local function OnGuildBankSlotsChanged()
    if not guildBankOpen or not guildBankScanning then return end

    local currentTab = GetCurrentGuildBankTab()
    if currentTab then
        local tabItems = ScanGuildBankTab(currentTab)
        for key, data in pairs(tabItems) do
            if not guildScanData[key] then
                guildScanData[key] = {
                    itemID    = data.itemID,
                    name      = data.name,
                    bonusIDs  = data.bonusIDs,
                    modifiers = data.modifiers,
                    quantity  = 0,
                    icon      = data.icon,
                }
            end
            guildScanData[key].quantity = guildScanData[key].quantity + data.quantity
        end
    end

    C_Timer.After(0.3, ProcessNextGuildTab)
end

function Scanner:ScanGuildBank()
    if not ns.db then return end
    if not guildBankOpen then
        ns:PrintError("Guild bank must be open to scan.")
        return
    end

    local numTabs = GetNumGuildBankTabs()
    if numTabs == 0 then
        ns:PrintError("No guild bank tabs available.")
        return
    end

    guildScanData = {}
    guildScanQueue = {}

    local guildName = GetGuildInfo("player")
    local disabledTabs = guildName and ns.db.guilds and ns.db.guilds[guildName]
        and ns.db.guilds[guildName].disabledTabs or {}

    for tab = 1, numTabs do
        local ok, name, icon, isViewable = pcall(GetGuildBankTabInfo, tab)
        if ok and isViewable and not disabledTabs[tab] then
            table.insert(guildScanQueue, tab)
        end
    end

    if #guildScanQueue == 0 then
        ns:PrintError("No viewable guild bank tabs.")
        return
    end

    guildBankScanning = true
    ns:PrintDebug("Scanning " .. #guildScanQueue .. " guild bank tab(s)...")
    ProcessNextGuildTab()
end

--------------------------
-- Character metadata
--------------------------

local function UpdateCharacterMeta()
    if not ns.db then return end
    local charKey = ns:GetCharKey()
    -- Current character was deleted and the user chose "keep deleted" at
    -- the login prompt. Don't re-seed metadata for this session.
    if ns:IsCharDeleted(charKey) then return end
    ns.db.characters[charKey] = ns.db.characters[charKey] or {}
    local char = ns.db.characters[charKey]
    char.gold = GetMoney()
    char.lastLogin = time()
    char.class = select(2, UnitClass("player"))
    char.level = UnitLevel("player")
    char.guild = GetGuildInfo("player")
    if ns.db.sync and ns.db.sync.accountUUID then
        char.accountUUID = ns.db.sync.accountUUID
    end
    if char.guild then
        ns.db.guilds = ns.db.guilds or {}
        if not ns.db.guilds[char.guild] then
            ns.db.guilds[char.guild] = { enabled = false, members = {} }
        end
        local guild = ns.db.guilds[char.guild]
        guild.members = guild.members or {}
        local found = false
        for _, ck in ipairs(guild.members) do
            if ck == charKey then found = true; break end
        end
        if not found then
            table.insert(guild.members, charKey)
        end
    end
end

--------------------------
-- Hard-dep check
--------------------------

-- Syndicator is a hard dependency as of v0.11.0 (Phase 6a). The .toc file
-- declares the dependency, so Blizzard's addon loader refuses to load
-- FlipQueue without it — but if someone has disabled Syndicator mid-session
-- or is running a corrupted install, we want a clear print rather than
-- silent failure when the refresh functions no-op.
local function WarnIfSyndicatorMissing()
    if Syndicator and Syndicator.API and Syndicator.API.GetByCharacterFullName then
        return false
    end
    ns:Print(ns.COLORS.RED ..
        "Syndicator missing or not loaded.|r FlipQueue requires Syndicator " ..
        "as of v0.11.0 for inventory tracking. Install it from CurseForge/Wago.")
    return true
end

--------------------------
-- Event handling
--------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BANKFRAME_CLOSED")
frame:RegisterEvent("PLAYER_MONEY")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
frame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")

local syndicatorReady = false

-- Coalesce BagCacheUpdate / WarbandBankCacheUpdate bursts into one refresh.
-- TSM Post Scans post many auctions in rapid succession; each post fires a
-- BAG_UPDATE which Syndicator processes on its next OnUpdate tick and emits
-- a BagCacheUpdate. Without a debounce on our side, we'd re-walk the full
-- bag/bank/projection + emit a Sync delta per Syndicator tick. 0.3s collapses
-- a typical posting burst to one projection.
local refreshBagsTimer, refreshWarbankTimer
local function ScheduleBagRefresh()
    if refreshBagsTimer then return end
    refreshBagsTimer = C_Timer.NewTimer(0.3, function()
        refreshBagsTimer = nil
        Scanner:RefreshCurrentCharacterFromSyndicator()
    end)
end
local function ScheduleWarbankRefresh()
    if refreshWarbankTimer then return end
    refreshWarbankTimer = C_Timer.NewTimer(0.3, function()
        refreshWarbankTimer = nil
        Scanner:RefreshWarbankFromSyndicator()
    end)
end

-- Register Syndicator callbacks once. The refresh functions are no-ops if
-- Syndicator isn't ready yet, so re-invoking them on the Ready callback
-- backfills the initial state.
local function RegisterSyndicatorCallbacks()
    if not (Syndicator and Syndicator.CallbackRegistry) then return end

    Syndicator.CallbackRegistry:RegisterCallback("BagCacheUpdate",
        function(_, characterName)
            -- Only refresh when the update is for THIS character. Syndicator
            -- may also emit for alt characters on this BNet account; we
            -- don't touch those (Sync.lua handles partner data).
            local synKey = CurrentSyndicatorKey()
            if characterName == synKey then
                ScheduleBagRefresh()
            end
        end, Scanner)

    Syndicator.CallbackRegistry:RegisterCallback("WarbandBankCacheUpdate",
        function()
            ScheduleWarbankRefresh()
        end, Scanner)
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        ns:InitDB()
        UpdateCharacterMeta()

        -- Print cleanup summary if migration ran
        if ns.db._cleanupSummary then
            ns:Print(ns.COLORS.GRAY .. "Data cleanup: " .. ns.db._cleanupSummary .. "|r")
            ns.db._cleanupSummary = nil
        end
        if ns.db._phase6aMessage then
            ns:Print(ns.COLORS.YELLOW .. ns.db._phase6aMessage .. "|r")
            ns.db._phase6aMessage = nil
        end

        -- Deleted-character login prompt. When the user logs in on a char
        -- they previously deleted from FlipQueue, give them a chance to
        -- restore it. If they don't, the guards in UpdateCharacterMeta and
        -- WriteProjectedInventory keep FQ from re-creating the char's data
        -- this session — they can still open the UI and restore from the
        -- Settings > Deleted Characters section at any time.
        local currentCharKey = ns:GetCharKey()
        if ns:IsCharDeleted(currentCharKey) then
            StaticPopupDialogs["FLIPQUEUE_DELETED_CHAR_LOGIN"] = {
                text = "This character (" .. currentCharKey ..
                    ") was deleted from FlipQueue.\n\n" ..
                    "Restore it, or keep it deleted for this session?",
                button1 = "Restore",
                button2 = "Keep deleted",
                OnAccept = function()
                    ns:RestoreCharacter(currentCharKey)
                    ns:Print(ns.COLORS.GREEN .. "Restored " .. currentCharKey ..
                        ". Reloading UI to rescan.|r")
                    -- A fresh login is the cleanest way to re-seed the
                    -- character's inventory + metadata; reload rather than
                    -- trying to replay init here.
                    C_Timer.After(0.5, function() ReloadUI() end)
                end,
                OnCancel = function()
                    ns:Print(ns.COLORS.GRAY ..
                        "FlipQueue is not tracking this character. " ..
                        "Restore it from Settings → Deleted Characters.|r")
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            C_Timer.After(2, function()
                -- Re-check: the user may have restored via /reload between
                -- InitDB and the timer firing.
                if ns:IsCharDeleted(currentCharKey) then
                    StaticPopup_Show("FLIPQUEUE_DELETED_CHAR_LOGIN")
                end
            end)
        end

        if ns.Tracker and ns.Tracker.StartExpiryTicker then
            ns.Tracker:StartExpiryTicker()
        end

        if ns.Sync and ns.Sync.Init then
            ns.Sync:Init()
        end

        -- Hard dep check + Syndicator wiring. If Syndicator is missing,
        -- warn the user and bail on the initial scan — event callbacks
        -- won't fire but the UI will still load.
        if WarnIfSyndicatorMissing() then return end

        RegisterSyndicatorCallbacks()

        if ns.db.settings.autoScan then
            local function RunInitialScan()
                syndicatorReady = true
                Scanner:RefreshCurrentCharacterFromSyndicator()
                Scanner:RefreshWarbankFromSyndicator()

                if ns.TodoList and ns.TodoList.RefreshTaskSteps then
                    ns.TodoList:RefreshTaskSteps()
                end
                if ns.TodoList and ns.TodoList.ResolveUnknownNames then
                    ns.TodoList:ResolveUnknownNames()
                end
                if ns.TodoList and ns.TodoList.ReassignUnassignedTasks then
                    local reassigned = ns.TodoList:ReassignUnassignedTasks()
                    if reassigned > 0 then
                        ns:Print(ns.COLORS.GREEN .. reassigned .. " task(s)|r assigned to characters on this realm.")
                    end
                end
                -- Auto-hide phantom characters (no class + never logged in)
                if ns.db and ns.db.characters then
                    local hidden = 0
                    for charKey, charData in pairs(ns.db.characters) do
                        if ns:IsPhantomChar(charKey) and (charData.role or "both") ~= "none" then
                            charData.role = "none"
                            hidden = hidden + 1
                        end
                    end
                    if hidden > 0 then
                        ns:Print(ns.COLORS.GRAY .. "Hid " .. hidden .. " phantom character(s) (no class, never logged in).|r")
                    end
                end

                if ns.TSM and ns.TSM.DetectCharacters then
                    local detected = ns.TSM:DetectCharacters()
                    if #detected > 0 then
                        ns._detectedTSMChars = detected
                        ns:Print(ns.COLORS.YELLOW .. #detected .. " character(s) detected from TSM.|r Open Characters page to add them.")
                    end
                end
                if ns.db.settings.showLoginMessage and ns.TodoList then
                    local charKey = ns:GetCharKey()
                    local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
                    if #todoTasks > 0 then
                        ns:Print(ns.COLORS.GREEN .. #todoTasks .. " items|r to post on this character! Type /fq to see details.")
                    end
                end

                -- Finalize log entries past the 30-day mail window before
                -- computing the uncollected counts, so phantom "expired
                -- auction(s) to collect" notifications don't fire for mail
                -- that's gone server-side or was collected externally (#122).
                if ns.Tracker and ns.Tracker.FinalizeStaleExpired then
                    ns.Tracker:FinalizeStaleExpired()
                end

                local currentCharKey = ns:GetCharKey()
                local uncollected = ns.SalesIndex:GetUncollectedForChar(currentCharKey)
                if uncollected.sold > 0 then
                    ns:Print(ns.COLORS.GREEN .. uncollected.sold .. " auction(s) sold — check mail to collect gold!|r")
                end
                if uncollected.expired > 0 then
                    ns:Print(ns.COLORS.ORANGE .. uncollected.expired .. " expired auction(s) to collect — check mail!|r")
                end

                if ns.Tracker and ns.Tracker.CheckExpiringAuctions then
                    local expiring = ns.Tracker:CheckExpiringAuctions()
                    if #expiring > 0 then
                        local byChar = {}
                        for _, entry in ipairs(expiring) do
                            local ck = entry.charKey or "Unknown"
                            byChar[ck] = (byChar[ck] or 0) + 1
                        end
                        for ck, count in pairs(byChar) do
                            ns:Print(ns.COLORS.ORANGE .. count .. " auction(s) expiring soon on " .. ck .. "!|r")
                        end
                    end
                end
            end

            -- If Syndicator is already ready, run immediately; otherwise
            -- wait for its Ready callback (fires once after PLAYER_LOGIN).
            if Syndicator.API.IsReady and Syndicator.API.IsReady() then
                C_Timer.After(0.5, RunInitialScan)
            elseif Syndicator.CallbackRegistry then
                Syndicator.CallbackRegistry:RegisterCallback("Ready",
                    function()
                        if not syndicatorReady then
                            C_Timer.After(0.2, RunInitialScan)
                        end
                    end, Scanner)
                -- Safety fallback: run anyway after 5s even if Ready didn't fire
                C_Timer.After(5, function()
                    if not syndicatorReady then RunInitialScan() end
                end)
            else
                C_Timer.After(1, RunInitialScan)
            end
        end

    elseif event == "BANKFRAME_OPENED" then
        -- Syndicator will emit BagCacheUpdate / WarbandBankCacheUpdate as
        -- it scans the freshly-opened bank, which our callbacks pick up.
        -- We still kick off an immediate refresh in case Syndicator hasn't
        -- processed the event yet.
        C_Timer.After(0.5, function()
            Scanner:RefreshCurrentCharacterFromSyndicator()
            Scanner:RefreshWarbankFromSyndicator()
        end)

    elseif event == "BANKFRAME_CLOSED" then
        if BankPanel then
            BankPanel:Hide()
        end
        if ns.UI and ns.UI.HideBankPopup then ns.UI:HideBankPopup() end
        if ns.BankQueue then ns.BankQueue:Abort() end

    elseif event == "PLAYER_MONEY" then
        if ns.db then
            local charKey = ns:GetCharKey()
            local charEntry = ns.db.characters[charKey]
            if charEntry then
                local oldGold = charEntry.gold or 0
                local newGold = GetMoney()
                charEntry.gold = newGold
                if ns.cw and ns.cw.Fire and newGold ~= oldGold then
                    ns.cw:Fire(ns.cw.Events.GoldChanged, charKey, newGold, newGold - oldGold)
                end
            end
        end

    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if interactionType == 10 or (Enum.PlayerInteractionType and interactionType == Enum.PlayerInteractionType.GuildBanker) then
            guildBankOpen = true
        end

    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        if interactionType == 10 or (Enum.PlayerInteractionType and interactionType == Enum.PlayerInteractionType.GuildBanker) then
            guildBankOpen = false
            guildBankScanning = false
            guildScanQueue = {}
        end

    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        if guildBankOpen then
            OnGuildBankSlotsChanged()
        end
    end
end)
