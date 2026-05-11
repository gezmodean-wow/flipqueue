-- Core.lua
-- Addon namespace, constants, utilities, saved variables init
local addonName, ns = ...

ns.ADDON_NAME = "FlipQueue"
-- @project-version@ is replaced by the CurseForge / Wago / BigWigs packager
-- on release. The packager normally substitutes the bare version number
-- (e.g. "0.12.0-alpha10") but some toolchains include the leading "v" from
-- the git tag (e.g. "v0.12.0-alpha10") — strip it here so display code
-- always prepends "v" cleanly without producing "vv0.12.0-alpha10".
local tocVersion = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
if tocVersion:find("@") then
    ns.VERSION = "dev"
else
    ns.VERSION = tocVersion:gsub("^v", "")
end

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

-- Debug log + chat-echo gate live in Cogworks (cw:DebugPrint, cw:SetDebugEnabled).
-- ns:PrintDebug forwards through; ns:SetDebugEnabled keeps the persisted
-- ns.db.settings.debugMessages flag and the cw runtime flag in sync so
-- chat-echo gating matches the user's saved preference.

function ns:PrintDebug(msg)
    if ns.cw and ns.cw.DebugPrint then
        ns.cw:DebugPrint("FlipQueue", tostring(msg))
    end
end

function ns:SetDebugEnabled(enabled)
    enabled = enabled and true or false
    if ns.db and ns.db.settings then
        ns.db.settings.debugMessages = enabled
    end
    if ns.cw and ns.cw.SetDebugEnabled then
        ns.cw:SetDebugEnabled("FlipQueue", enabled)
    end
end

--------------------------
-- Item Key Generation
--------------------------

-- Item-key construction + WoW-itemString conversion delegate to Cogworks-1.0
-- (Items.lua) so all suite cogs share one canonical implementation. Format
-- matches FlippingPal's "itemID;bonusIDs;modifiers" shape; Cogworks owns the
-- modifier-9 (item level) handling.
function ns:MakeItemKey(itemID, bonusIDs, modifiers)
    return ns.cw:MakeItemKey(itemID, bonusIDs, modifiers)
end

function ns:ItemKeyToItemString(itemKey)
    return ns.cw:ItemKeyToItemString(itemKey)
end

-- Set up GameTooltip for an item, preferring the bonus-ID-decorated
-- itemString when itemKey is available so the tooltip — and any TSM /
-- Auctionator price lines hooking it — resolves to the actual ilvl
-- variant. Falls back to SetItemByID when only a plain itemID is known
-- (or itemKey is a pet, which uses the battlepet tooltip API instead).
-- Returns true if any tooltip was set.
--
-- Always calls Show() on success: SetItemByID auto-shows in modern WoW
-- but SetHyperlink does NOT, so without an explicit Show the tooltip
-- silently stays hidden when the itemString path is taken. Calling Show
-- on a populated GameTooltip is idempotent so callers that also call it
-- afterward are fine.
function ns:SetTooltipItem(tooltip, itemKey, itemID)
    if itemKey and itemKey ~= "" and not itemKey:find("^pet:") then
        local itemString = ns:ItemKeyToItemString(itemKey)
        if itemString then
            tooltip:SetHyperlink(itemString)
            tooltip:Show()
            return true
        end
    end
    local n = tonumber(itemID)
    if n and n > 0 then
        tooltip:SetItemByID(n)
        tooltip:Show()
        return true
    end
    return false
end

-- Resolve an item's actual ilvl, preferring the bonus-ID-decorated variant
-- value over the base item's ilvl. Returns 0 when nothing resolves yet
-- (item not loaded, or no info available).
--
-- The naive fallback of "GetItemInfo(itemID)" returns BASE ilvl, which for
-- modern gear is wildly wrong — e.g. an ilvl 253 ring with bonus IDs has
-- a base ilvl of 44 because that's the unsocketed/unupgraded baseline.
-- Calling GetItemInfo on the FULL itemString (including bonus IDs)
-- returns the variant's actual ilvl.
function ns:GetItemLevelFromKey(itemKey, fallbackItemID)
    if itemKey and itemKey ~= "" and not itemKey:find("^pet:") then
        local itemString = ns:ItemKeyToItemString(itemKey)
        if itemString then
            local ok, _, _, _, ilvl = pcall(C_Item.GetItemInfo, itemString)
            if ok and ilvl and ilvl > 0 then return ilvl end
        end
    end
    local n = tonumber(fallbackItemID)
    if n and n > 0 then
        local ok, _, _, _, ilvl = pcall(C_Item.GetItemInfo, n)
        if ok and ilvl and ilvl > 0 then return ilvl end
    end
    return 0
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

-- Parse a WoW item link into (itemID, bonusIDs, modifiers) — battle-pet links
-- return ("pet:<speciesID>", "q<quality>", ""). Delegates to Cogworks-1.0.
function ns:ParseItemLink(itemLink)
    return ns.cw:ParseItemLink(itemLink)
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
-- Item ID Resolution + Matching
--------------------------

-- Resolution + matching delegate to Cogworks-1.0 (Items.lua). Cogworks owns the
-- tier algorithm (exact key → numeric ID → exact name → fuzzy substring with
-- recipe-prefix guard) and FQ supplies a name-lookup closure that walks our
-- scanned inventory tables. Reads ns.db lazily so callers run before SV init
-- get nil instead of an indexing error.
local function inventoryLookupByName(searchNameLower)
    if not ns.db then return nil end

    if ns.db.characters then
        for _, charData in pairs(ns.db.characters) do
            if charData.inventory and charData.inventory.items then
                for _, itemData in pairs(charData.inventory.items) do
                    if itemData.name and itemData.name:lower() == searchNameLower then
                        local invID = tonumber(itemData.itemID)
                        if invID and invID > 0 then return invID end
                    end
                end
            end
        end
    end

    if ns.db.warbank and ns.db.warbank.items then
        for _, itemData in pairs(ns.db.warbank.items) do
            if itemData.name and itemData.name:lower() == searchNameLower then
                local invID = tonumber(itemData.itemID)
                if invID and invID > 0 then return invID end
            end
        end
    end

    return nil
end

function ns:ResolveItemID(queueItem)
    return ns.cw:ResolveItemID(queueItem, inventoryLookupByName)
end

function ns:ItemsMatch(itemKey, itemName, queueItem, resolvedID, allowFuzzy)
    return ns.cw:ItemsMatch(itemKey, itemName, queueItem, resolvedID, allowFuzzy, inventoryLookupByName)
end

