-- Core.lua
-- Addon namespace, constants, utilities, saved variables init
local addonName, ns = ...

ns.ADDON_NAME = "FlipQueue"
-- @project-version@ is replaced by CurseForge packager on release
local tocVersion = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
ns.VERSION = tocVersion:find("@") and "dev" or tocVersion

-- Cogworks suite library (fetched via .pkgmeta external at package time from
-- github.com/gezmodean-wow/cogworks tag v0.1.0). Cache the library reference
-- on the namespace so other files don't repeat the LibStub lookup, and
-- register FlipQueue with the shared addon registry so sibling cogs can
-- enumerate us. The `true` second arg to GetLibrary returns nil if missing
-- instead of erroring — staying defensive means a bad install doesn't brick
-- the whole addon, just the Cogworks event fan-out.
--
-- Prefix keeps the legacy "FlipQueue:" yellow format so Phase 2 delegation
-- is invisible to users. The unified "[CogName]" gold prefix is a branding
-- pass (Phase 5) that lands only after Phases 2-4 are stable.
do
    local cw = LibStub and LibStub("Cogworks-1.0", true)
    if cw then
        ns.cw = cw
        if cw.RegisterAddon then
            cw:RegisterAddon("FlipQueue", {
                version = ns.VERSION,
                prefix  = "|cffffff00FlipQueue:|r ",
                website = "https://github.com/gezmodean-wow/flipqueue",
            })
        end
    end
end

-- Bag index constants (TWW 12.0+)
ns.INVENTORY_BAGS = {0, 1, 2, 3, 4}      -- player bags (general use)
ns.REAGENT_BAG = 5                        -- dedicated reagent bag slot
-- ALL_PLAYER_BAGS includes the reagent bag — used when iterating items the
-- player is *carrying* (counting / depositing). Pull destinations still use
-- INVENTORY_BAGS so non-reagent bank items don't get routed to the reagent
-- bag (where the server would reject them).
ns.ALL_PLAYER_BAGS = {0, 1, 2, 3, 4, 5}
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
    CYAN    = "|cff00ccff",
    RESET   = "|r",
}

--------------------------
-- Print Helpers
--------------------------
-- Phase 2 Cogworks refactor: the chat-facing output routes through
-- ns.cw:Print when the library is present so all suite cogs flow through
-- one code path. The local fallback (plain `print()`) runs when Cogworks
-- isn't loaded — defensively, since the library is a packager external
-- and a bad install could leave it missing. The registered prefix
-- ("FlipQueue:" in yellow) matches the legacy format so this delegation
-- is invisible to users; Phase 5 is where the suite-wide branding lands.

function ns:Print(msg)
    if ns.cw and ns.cw.Print then
        ns.cw:Print("FlipQueue", msg)
    else
        print(ns.COLORS.YELLOW .. "FlipQueue:|r " .. msg)
    end
end

function ns:PrintError(msg)
    if ns.cw and ns.cw.PrintError then
        ns.cw:PrintError("FlipQueue", msg)
    else
        print(ns.COLORS.RED .. "FlipQueue:|r " .. msg)
    end
end

-- Ring buffer of recent debug messages, exposed for the in-game debug
-- console (UI/DebugPopup.lua). Always populated regardless of whether
-- debugMessages is on, so the console can show the last N messages even
-- when the user just enabled debug mode.
ns._debugLog = ns._debugLog or {}
ns._debugLogMax = 500

function ns:PrintDebug(msg)
    -- Push to the ring buffer regardless of the debugMessages setting so the
    -- in-game debug console always has recent context. This side effect is
    -- FlipQueue-specific and stays local — Cogworks doesn't own debug logs.
    local ts = date("%H:%M:%S")
    ns._debugLog[#ns._debugLog + 1] = ts .. "  " .. tostring(msg)
    if #ns._debugLog > ns._debugLogMax then
        table.remove(ns._debugLog, 1)
    end
    -- Notify the debug popup if it's open so it can append the new line live.
    if ns.UI and ns.UI._OnDebugLogAppend then
        ns.UI:_OnDebugLogAppend()
    end

    if ns.db and ns.db.settings.debugMessages then
        -- Debug prints stay on the local print() path even when Cogworks
        -- is loaded — the "[debug]" suffix and gray coloring are custom
        -- enough that routing through cw:Print would require a dedicated
        -- Cogworks API. Not worth the API surface right now.
        print(ns.COLORS.GRAY .. "FlipQueue [debug]:|r " .. msg)
    end
end

--------------------------
-- Item Key Generation
--------------------------

-- Matches FlippingPal's GetItemKey format: "itemID;bonusIDs;modifiers"
function ns:MakeItemKey(itemID, bonusIDs, modifiers)
    return string.format("%s;%s;%s", tostring(itemID), bonusIDs or "", modifiers or "")
end

-- Convert an itemKey ("itemID;bonusIDs;modifiers") to a WoW item string
-- suitable for GameTooltip:SetHyperlink(). Returns nil for pets or invalid keys.
function ns:ItemKeyToItemString(itemKey)
    if not itemKey or itemKey == "" then return nil end
    if itemKey:find("^pet:") then return nil end -- pets use battlepet: links

    local idStr, bonusStr, modStr = strsplit(";", itemKey)
    local numID = tonumber(idStr)
    if not numID or numID <= 0 then return nil end

    -- Build item:id::::::::::::[numBonuses:b1:b2:...][::modType:modValue]
    -- WoW item string positions: item:id:enchant:gem1:gem2:gem3:gem4:suffix:uniqueID:level:specID:modType:numBonuses:bonus1:bonus2:...
    local parts = {"item", idStr, "", "", "", "", "", "", "", "", "", ""}
    -- Bonus IDs
    if bonusStr and bonusStr ~= "" then
        local bonuses = {strsplit(":", bonusStr)}
        table.insert(parts, tostring(#bonuses))
        for _, b in ipairs(bonuses) do
            table.insert(parts, b)
        end
    else
        table.insert(parts, "0")
    end
    -- Modifiers (e.g., "9=85" → modifier type 9, value 85)
    if modStr and modStr ~= "" then
        local mods = {strsplit(":", modStr)}
        table.insert(parts, tostring(#mods))
        for _, m in ipairs(mods) do
            local k, v = m:match("^(%d+)=(%d+)$")
            if k and v then
                table.insert(parts, k)
                table.insert(parts, v)
            end
        end
    end
    return table.concat(parts, ":")
end

-- Normalize key for imports map: "itemKey:iLvl|realm" or "name|realm"
-- ilvl is included so that same-item variants with different ilvls (different
-- bonus tiers) are treated as independent deals when FP doesn't export bonusIDs.
function ns:MakeImportKey(itemKey, itemName, targetRealm, ilvl)
    local base = itemKey or itemName or ""
    local realm = ns:NormalizeRealmKey(targetRealm or "")
    local ilvlSuffix = (ilvl and ilvl > 0) and (":i" .. ilvl) or ""
    return base:lower() .. ilvlSuffix .. "|" .. realm
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
    -- Latin Extended-A (U+0100–U+017F, \196 and \197 prefixes)
    ["\196\128"] = "a", ["\196\129"] = "a",   -- Ā ā
    ["\196\130"] = "a", ["\196\131"] = "a",   -- Ă ă
    ["\196\132"] = "a", ["\196\133"] = "a",   -- Ą ą
    ["\196\134"] = "c", ["\196\135"] = "c",   -- Ć ć
    ["\196\140"] = "c", ["\196\141"] = "c",   -- Č č
    ["\196\142"] = "d", ["\196\143"] = "d",   -- Ď ď
    ["\196\146"] = "e", ["\196\147"] = "e",   -- Ē ē
    ["\196\152"] = "e", ["\196\153"] = "e",   -- Ę ę
    ["\196\154"] = "e", ["\196\155"] = "e",   -- Ě ě
    ["\196\168"] = "i", ["\196\169"] = "i",   -- Ĩ ĩ
    ["\196\170"] = "i", ["\196\171"] = "i",   -- Ī ī
    ["\196\185"] = "l", ["\196\186"] = "l",   -- Ĺ ĺ
    ["\196\187"] = "l", ["\196\188"] = "l",   -- Ļ ļ
    ["\197\129"] = "l", ["\197\130"] = "l",   -- Ł ł
    ["\197\131"] = "n", ["\197\132"] = "n",   -- Ń ń
    ["\197\135"] = "n", ["\197\136"] = "n",   -- Ň ň
    ["\197\140"] = "o", ["\197\141"] = "o",   -- Ō ō
    ["\197\144"] = "o", ["\197\145"] = "o",   -- Ő ő
    ["\197\146"] = "oe", ["\197\147"] = "oe", -- Œ œ
    ["\197\152"] = "r", ["\197\153"] = "r",   -- Ř ř
    ["\197\154"] = "s", ["\197\155"] = "s",   -- Ś ś
    ["\197\158"] = "s", ["\197\159"] = "s",   -- Ş ş
    ["\197\160"] = "s", ["\197\161"] = "s",   -- Š š
    ["\197\164"] = "t", ["\197\165"] = "t",   -- Ť ť
    ["\197\168"] = "u", ["\197\169"] = "u",   -- Ũ ũ
    ["\197\170"] = "u", ["\197\171"] = "u",   -- Ū ū
    ["\197\174"] = "u", ["\197\175"] = "u",   -- Ů ů
    ["\197\176"] = "u", ["\197\177"] = "u",   -- Ű ű
    ["\197\185"] = "z", ["\197\186"] = "z",   -- Ź ź
    ["\197\187"] = "z", ["\197\188"] = "z",   -- Ż ż
    ["\197\189"] = "z", ["\197\190"] = "z",   -- Ž ž
}

-- Normalize a string for accent-insensitive comparison
-- Strips diacritics and lowercases
function ns:NormalizeAccents(str)
    if not str then return "" end
    return str:gsub("[\195-\197][\128-\191]", ACCENT_MAP):lower()
end

-- Check if a target realm string matches a given realm name
-- Uses connected realm group table for exact matching (no substring matching)
-- Supports comma-separated connected realm lists from FlippingPal
-- Accent-insensitive: "Confrérie du Thorium" matches "Confrerie du Thorium"
function ns:RealmMatches(targetRealm, realmName)
    if not targetRealm or targetRealm == "" then return true end
    if not realmName or realmName == "" then return false end

    local rNorm = ns:NormalizeRealmKey(realmName)
    local rGroup = ns.REALM_LOOKUP and ns.REALM_LOOKUP[rNorm]

    -- Check each realm name in the target (may be comma-separated)
    for name in targetRealm:gmatch("([^,]+)") do
        name = strtrim(name)
        if #name >= 3 and not name:find("^%.+$") then
            local tNorm = ns:NormalizeRealmKey(name)
            -- Exact normalized name match
            if tNorm == rNorm then return true end
            -- Connected realm group match (same AH)
            if rGroup then
                local tGroup = ns.REALM_LOOKUP[tNorm]
                if tGroup and tGroup == rGroup then return true end
            end
        end
    end

    return false
end

-- Check if two realm strings refer to the same connected AH
-- e.g., "Kalecgos, Lightninghoof, Maelstrom" overlaps with "Lightninghoof"
-- Uses connected realm group table for exact matching
function ns:RealmsOverlap(realm1, realm2)
    local r1 = realm1 or ""
    local r2 = realm2 or ""
    if r1 == "" and r2 == "" then return true end
    if r1 == "" or r2 == "" then return false end

    -- Split r2 into individual names and collect their group IDs
    local r2names = {} -- normalized name -> true
    local r2groups = {} -- groupID -> true
    for name in r2:gmatch("([^,]+)") do
        name = strtrim(name)
        if #name >= 3 and not name:find("^%.+$") then
            local norm = ns:NormalizeRealmKey(name)
            r2names[norm] = true
            if ns.REALM_LOOKUP then
                local gid = ns.REALM_LOOKUP[norm]
                if gid then r2groups[gid] = true end
            end
        end
    end

    -- Check each name in r1 against r2's names and groups
    for name in r1:gmatch("([^,]+)") do
        name = strtrim(name)
        if #name >= 3 and not name:find("^%.+$") then
            local norm = ns:NormalizeRealmKey(name)
            -- Exact name match
            if r2names[norm] then return true end
            -- Group match
            if ns.REALM_LOOKUP then
                local gid = ns.REALM_LOOKUP[norm]
                if gid and r2groups[gid] then return true end
            end
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

    for _, charData in pairs(ns.db.characters) do
        if charData.inventory and charData.inventory.items then
            for key, itemData in pairs(charData.inventory.items) do
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
-- Item Matching
--------------------------

-- Unified item matching: compares an inventory/auction item against a queue/log item
-- Returns: (matched: bool, fuzzy: bool)
-- fuzzy=true for any name-based match (exact or substring)
-- resolvedID: pre-computed resolved ID for queue item (avoids re-resolving)
-- allowFuzzy: enable substring name matching (default true, pass false to disable)
function ns:ItemsMatch(itemKey, itemName, queueItem, resolvedID, allowFuzzy)
    -- Tier 1: Exact key match
    if itemKey == queueItem.itemKey then
        return true, false
    end

    -- Tier 2: Numeric ID match
    local scannedID = itemKey and itemKey:match("^(%d+);")
    local scannedNumID = tonumber(scannedID)
    if scannedNumID and scannedNumID > 0 then
        local queueNumID = tonumber(queueItem.itemID)
        if queueNumID and queueNumID > 0 and scannedNumID == queueNumID then
            return true, false
        end
        -- resolvedID: number=use it, false=already checked (skip), nil=resolve now
        local rid = resolvedID
        if rid == nil then rid = ns:ResolveItemID(queueItem) end
        if rid and scannedNumID == rid then
            return true, false
        end
    end

    -- Tier 3 & 4: Name-based matching
    if itemName and queueItem.name and queueItem.name ~= "" then
        local sName = itemName:lower()
        local qName = queueItem.name:lower()
        -- Tier 3: Exact name match
        if sName == qName then
            return true, true
        end
        -- Tier 4: Fuzzy substring match (min 8 chars, opt-in)
        -- Prevent recipe/pattern/design items from fuzzy-matching their base items
        if allowFuzzy ~= false and #queueItem.name >= 8 then
            local sBase = sName:match("^%w+:%s*(.+)$") or sName
            local qBase = qName:match("^%w+:%s*(.+)$") or qName
            -- Only match if the base names (after stripping prefix) match,
            -- or one base is a substring of the other
            if sBase == qBase then
                return true, true
            end
            if sBase:find(qBase, 1, true) or qBase:find(sBase, 1, true) then
                -- Reject if one has a prefix and the other doesn't (recipe vs item)
                local sHasPrefix = sName:find("^%w+:%s") ~= nil
                local qHasPrefix = qName:find("^%w+:%s") ~= nil
                if sHasPrefix == qHasPrefix then
                    return true, true
                end
            end
        end
    end

    return false, false
end

