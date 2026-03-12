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

-- UTF-8 accent normalization for realm name comparison
-- Maps accented characters (multi-byte UTF-8) to their ASCII equivalents
-- Covers Latin diacritics used in EU WoW realm names (French, German, Spanish, etc.)
local ACCENT_MAP = {
    -- French: à â æ ç é è ê ë î ï ô œ ù û ü ÿ
    ["\195\160"] = "a", ["\195\161"] = "a", ["\195\162"] = "a", ["\195\163"] = "a",
    ["\195\164"] = "a", ["\195\165"] = "a", -- à á â ã ä å
    ["\195\166"] = "ae",                     -- æ
    ["\195\167"] = "c",                      -- ç
    ["\195\168"] = "e", ["\195\169"] = "e", ["\195\170"] = "e", ["\195\171"] = "e", -- è é ê ë
    ["\195\172"] = "i", ["\195\173"] = "i", ["\195\174"] = "i", ["\195\175"] = "i", -- ì í î ï
    ["\195\176"] = "d",                      -- ð
    ["\195\177"] = "n",                      -- ñ
    ["\195\178"] = "o", ["\195\179"] = "o", ["\195\180"] = "o", ["\195\181"] = "o",
    ["\195\182"] = "o",                      -- ò ó ô õ ö
    ["\195\184"] = "o",                      -- ø
    ["\195\185"] = "u", ["\195\186"] = "u", ["\195\187"] = "u", ["\195\188"] = "u", -- ù ú û ü
    ["\195\189"] = "y", ["\195\190"] = "th", ["\195\191"] = "y", -- ý þ ÿ
    -- Uppercase variants (lowered)
    ["\195\128"] = "a", ["\195\129"] = "a", ["\195\130"] = "a", ["\195\131"] = "a",
    ["\195\132"] = "a", ["\195\133"] = "a", -- À Á Â Ã Ä Å
    ["\195\134"] = "ae",                     -- Æ
    ["\195\135"] = "c",                      -- Ç
    ["\195\136"] = "e", ["\195\137"] = "e", ["\195\138"] = "e", ["\195\139"] = "e", -- È É Ê Ë
    ["\195\140"] = "i", ["\195\141"] = "i", ["\195\142"] = "i", ["\195\143"] = "i", -- Ì Í Î Ï
    ["\195\144"] = "d",                      -- Ð
    ["\195\145"] = "n",                      -- Ñ
    ["\195\146"] = "o", ["\195\147"] = "o", ["\195\148"] = "o", ["\195\149"] = "o",
    ["\195\150"] = "o",                      -- Ò Ó Ô Õ Ö
    ["\195\152"] = "o",                      -- Ø
    ["\195\153"] = "u", ["\195\154"] = "u", ["\195\155"] = "u", ["\195\156"] = "u", -- Ù Ú Û Ü
    ["\195\157"] = "y", ["\195\158"] = "th", ["\195\159"] = "ss", -- Ý Þ ß
}

-- Normalize a string for accent-insensitive comparison
-- Strips diacritics and lowercases
function ns:NormalizeAccents(str)
    if not str then return "" end
    return str:gsub("[\195][\128-\191]", ACCENT_MAP):lower()
end

-- Check if a target realm string matches a given realm name
-- Supports linked realm clusters like "Aegwynn, Lightninghoof, Maelstrom"
-- Accent-insensitive: "Confrérie du Thorium" matches "Confrerie du Thorium"
function ns:RealmMatches(targetRealm, realmName)
    if not targetRealm or targetRealm == "" then return true end
    if not realmName or realmName == "" then return false end
    return ns:NormalizeAccents(targetRealm):find(ns:NormalizeAccents(realmName), 1, true) ~= nil
end

-- Check if two realm strings refer to the same connected AH
-- e.g., "Kalecgos, Lightninghoof, Maelstrom" overlaps with "Lightninghoof"
-- Accent-insensitive for EU realm names
function ns:RealmsOverlap(realm1, realm2)
    local r1 = realm1 or ""
    local r2 = realm2 or ""
    if r1 == "" and r2 == "" then return true end
    if r1 == "" or r2 == "" then return false end
    local r2norm = ns:NormalizeAccents(r2)
    for name in r1:gmatch("([^,]+)") do
        name = strtrim(name)
        -- Skip short fragments (e.g., "..." from FP website formatting)
        if #name >= 3 and not name:find("^%.+$") and r2norm:find(ns:NormalizeAccents(name), 1, true) then
            return true
        end
    end
    return false
end

-- Normalize a realm string for use as a grouping/map key
-- Strips accents and lowercases so "Confrérie du Thorium" and "Confrerie du Thorium" group together
function ns:NormalizeRealmKey(realm)
    return ns:NormalizeAccents(realm or "")
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
    if db.settings.hideMiniInCombat == nil then db.settings.hideMiniInCombat = true end
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
