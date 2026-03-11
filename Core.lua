-- Core.lua
-- Addon namespace, constants, utilities, saved variables init
local addonName, ns = ...

ns.ADDON_NAME = "FlipQueue"
-- @project-version@ is replaced by CurseForge packager on release
local tocVersion = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
ns.VERSION = tocVersion:find("@") and "dev" or tocVersion

-- Bag index constants (TWW 12.0+)
ns.INVENTORY_BAGS = {0, 1, 2, 3, 4}
ns.REAGENT_BAG = 5
ns.BANK_TABS = {6, 7, 8, 9, 10, 11}
ns.WARBANK_TABS = {12, 13, 14, 15, 16}

-- Colors
ns.COLORS = {
    YELLOW  = "|cffffff00",
    RED     = "|cffff0000",
    GREEN   = "|cff00ff00",
    BLUE    = "|cff3399ff",
    ORANGE  = "|cffff8800",
    WHITE   = "|cffffffff",
    GRAY    = "|cff888888",
    RESET   = "|r",
}

--------------------------
-- Print Helpers
--------------------------

function ns:Print(msg)
    print(ns.COLORS.YELLOW .. "FlipQueue:|r " .. msg)
end

function ns:PrintError(msg)
    print(ns.COLORS.RED .. "FlipQueue:|r " .. msg)
end

--------------------------
-- Item Key Generation
--------------------------

-- Matches FlippingPal's GetItemKey format: "itemID;bonusIDs;modifiers"
function ns:MakeItemKey(itemID, bonusIDs, modifiers)
    return string.format("%s;%s;%s", tostring(itemID), bonusIDs or "", modifiers or "")
end

-- Parse item link to extract itemID, bonusIDs, modifiers
-- Replicates FlippingPal's ParseItemLink logic for compatibility
function ns:ParseItemLink(itemLink)
    if not itemLink then return nil end

    -- Handle battle pets: |Hbattlepet:speciesID:level:quality:...|h[Name]|h
    local speciesID = itemLink:match("|Hbattlepet:(%d+)")
    if speciesID then
        local petQuality = itemLink:match("|Hbattlepet:%d+:%d+:(%d+)")
        return "pet:" .. speciesID, "q" .. (petQuality or "0"), ""
    end

    -- Standard items
    local itemString = itemLink:match("item[%-?%d:]+")
    if not itemString then return nil end

    local parts = {strsplit(":", itemString)}
    local itemID = parts[2]
    if not itemID or itemID == "" then return nil end

    local bonusIDs = ""
    local modifiers = ""

    if #parts >= 14 then
        local numBonusIDs = tonumber(parts[14]) or 0
        local bonusList = {}
        for i = 1, numBonusIDs do
            local bid = parts[14 + i]
            if bid and bid ~= "" then
                table.insert(bonusList, bid)
            end
        end
        bonusIDs = table.concat(bonusList, ":")

        local modStart = 14 + numBonusIDs + 1
        if #parts >= modStart then
            local numMods = tonumber(parts[modStart]) or 0
            local modList = {}
            for i = 1, numMods do
                local mType = parts[modStart + (i * 2) - 1]
                local mVal  = parts[modStart + (i * 2)]
                if mType and mVal and mType ~= "" and mVal ~= "" and mType == "9" then
                    table.insert(modList, mType .. "=" .. mVal)
                end
            end
            modifiers = table.concat(modList, ":")
        end
    end

    return itemID, bonusIDs, modifiers
end

--------------------------
-- Realm Matching
--------------------------

-- Check if a target realm string matches a given realm name
-- Supports linked realm clusters like "Aegwynn, Lightninghoof, Maelstrom"
function ns:RealmMatches(targetRealm, realmName)
    if not targetRealm or targetRealm == "" then return true end
    if not realmName or realmName == "" then return false end
    return targetRealm:lower():find(realmName:lower(), 1, true) ~= nil
end

-- Check if two realm strings refer to the same connected AH
-- e.g., "Kalecgos, Lightninghoof, Maelstrom" overlaps with "Lightninghoof"
function ns:RealmsOverlap(realm1, realm2)
    local r1 = realm1 or ""
    local r2 = realm2 or ""
    if r1 == "" and r2 == "" then return true end
    if r1 == "" or r2 == "" then return false end
    for name in r1:gmatch("([^,]+)") do
        name = strtrim(name)
        if name ~= "" and r2:lower():find(name:lower(), 1, true) then
            return true
        end
    end
    return false
end

--------------------------
-- Item ID Resolution
--------------------------

-- Resolve a queue item's numeric ID from scanned inventory data
function ns:ResolveItemID(queueItem)
    local numID = tonumber(queueItem.itemID)
    if numID and numID > 0 then return numID end

    if not ns.db or not queueItem.name or queueItem.name == "" then return nil end
    local searchName = queueItem.name:lower()

    for _, charData in pairs(ns.db.inventory) do
        if charData.items then
            for key, itemData in pairs(charData.items) do
                if itemData.name and itemData.name:lower() == searchName then
                    local invID = tonumber(itemData.itemID)
                    if invID and invID > 0 then return invID end
                end
            end
        end
    end

    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            if itemData.name and itemData.name:lower() == searchName then
                local invID = tonumber(itemData.itemID)
                if invID and invID > 0 then return invID end
            end
        end
    end

    return nil
end

--------------------------
-- Saved Variables Init
--------------------------

function ns:InitDB()
    if not FlipQueueDB then
        FlipQueueDB = {}
    end
    local db = FlipQueueDB
    db.inventory  = db.inventory or {}
    db.warbank    = db.warbank or {}
    db.queue      = db.queue or {}
    db.log        = db.log or {}
    db.doNotTrack = db.doNotTrack or {}
    db.hiddenCharacters = db.hiddenCharacters or {}
    db.settings   = db.settings or {
        autoScan         = true,
        autoPullBank     = false,
        showLoginMessage = true,
        autoWithdrawGold = false,
    }
    db.characters = db.characters or {}
    db.externalAccounts = db.externalAccounts or {}
    db.settings.collapsed = db.settings.collapsed or {}
    db.settings.sortMode  = db.settings.sortMode or "realm"
    db.settings.expiryAlertHours = db.settings.expiryAlertHours or 6
    ns.db = db
end

--------------------------
-- Gold Formatting
--------------------------

function ns:FormatGold(copper)
    if not copper or copper <= 0 then return "0g" end
    local gold = math.floor(copper / 10000)
    if gold >= 1000000 then
        return string.format("%.1fm", gold / 1000000)
    elseif gold >= 1000 then
        return string.format("%.1fk", gold / 1000)
    end
    return tostring(gold) .. "g"
end

function ns:FormatRelativeTime(timestamp)
    if not timestamp or timestamp <= 0 then return "never" end
    local diff = time() - timestamp
    if diff < 0 then return "now" end
    if diff < 60 then return "just now" end
    if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
    if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
    return math.floor(diff / 86400) .. "d ago"
end

--------------------------
-- Character Key
--------------------------

function ns:GetCharKey()
    local name  = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end
