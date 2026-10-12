-- ItemLevelDisplay.lua
-- Item level next to gear names on to-do rows, plus an explicit item-level
-- line on their tooltips (FQ-258).
--
-- Why the tooltip alone can't be trusted: deals imported from the FlippingPal
-- website copy-paste (and Auctionator/PBS lists) carry only an item NAME and a
-- recorded ilvl — no bonus IDs, no modifiers. The task's itemKey is the name,
-- so there is no variant to build a link from and the tooltip falls back to
-- the base item by ID. For level-scaling gear the client then renders that
-- base item scaled to the VIEWING character's level (FP buyers shop on
-- low-level alts), which is how a 233 deal shows up as "Item Level 44". The
-- recorded ilvl from the import is the only ground truth, so it goes on the
-- row and on the tooltip as its own line.
--
-- Rows refresh often (MiniView on every bag event, TodoPage on every
-- refresh), so every client call here is memoized: gear class per itemID,
-- name -> itemID, and the computed ilvl per itemKey. The import-side lookups
-- are plain table reads and are not cached, so a re-import is seen at once.
local addonName, ns = ...

local IlvlDisplay = {}
ns.IlvlDisplay = IlvlDisplay

-- Enum.ItemClass: Weapon = 2, Armor = 4, Profession (tools/accessories) = 19.
local GEAR_CLASSES = { [2] = true, [4] = true, [19] = true }

-- Equip slots whose item level means nothing to a buyer. An empty equipLoc
-- is non-equippable armor/weapon-class junk (e.g. some cosmetic tokens).
local NO_ILVL_EQUIPLOC = {
    [""]                       = true,
    INVTYPE_NON_EQUIP_IGNORE   = true,
    INVTYPE_BAG                = true,
    INVTYPE_QUIVER             = true,
    INVTYPE_TABARD             = true,
    INVTYPE_BODY               = true,   -- shirts
}

local gearByID     = {}   -- itemID -> true/false (only resolved answers)
local idByName     = {}   -- lower(name) -> itemID (positive hits only)
local computedByKey = {}  -- itemKey -> ilvl (positive hits only)

local function DetailedIlvl(itemInfo)
    local fn = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if not fn or not itemInfo then return nil end
    local ok, ilvl = pcall(fn, itemInfo)
    if ok and type(ilvl) == "number" and ilvl > 0 then return ilvl end
    return nil
end

-- Numeric itemID for a task, or nil. hintID wins when the caller already
-- resolved one (TodoPage's LookupItemInfo). Name-keyed imports fall back to
-- a memoized C_Item.GetItemIDForItemInfo, which only answers for items the
-- client has cached — a miss is not cached so a later refresh can retry.
function IlvlDisplay:ResolveItemID(task, hintID)
    local n = tonumber(hintID)
    if n and n > 0 then return n end
    if not task then return nil end
    n = tonumber(task.itemID)
    if n and n > 0 then return n end
    local key = task.itemKey
    if type(key) == "string" then
        if key:find("^pet") then return nil end
        n = tonumber(key:match("^(%d+)"))
        if n and n > 0 then return n end
    end
    local name = task.name
    if type(name) ~= "string" or name == "" then return nil end
    local lname = name:lower()
    local cached = idByName[lname]
    if cached then return cached end
    if C_Item and C_Item.GetItemIDForItemInfo then
        local ok, id = pcall(C_Item.GetItemIDForItemInfo, name)
        if ok and type(id) == "number" and id > 0 then
            idByName[lname] = id
            return id
        end
    end
    return nil
end

-- True for equippable gear whose item level is meaningful. Commodities,
-- pets, recipes, reagents, bags and shirts all return false.
function IlvlDisplay:IsGear(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end
    local cached = gearByID[itemID]
    if cached ~= nil then return cached end
    if not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local ok, id, _, _, equipLoc, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
    if not ok or not id then return false end   -- unknown to the client: retry later
    local isGear = GEAR_CLASSES[classID] == true
        and not NO_ILVL_EQUIPLOC[equipLoc or ""]
    gearByID[itemID] = isGear
    return isGear
end

-- Best-known item level for a task. Returns ilvl (0 on miss) and its source:
--   "import"   the live import record, or the importKey ":iNNN" suffix —
--              what FlippingPal recorded, i.e. what the player buys against
--   "task"     the ilvl stored on the task (normally copied from the deal at
--              generate time; can also be a regenerate-time backfill)
--   "computed" derived from the item key's bonus IDs via the client, which
--              is scaled to the viewing character for level-scaling gear
-- Differs from TodoList:ResolveTaskIlvl only in putting the import first;
-- that function stays as-is for its existing callers.
function IlvlDisplay:GetTaskIlvl(task)
    if not task then return 0 end

    if task.importSource and task.importKey and ns.db and ns.db.imports then
        local src = ns.db.imports[task.importSource]
        local deal = src and src[task.importKey]
        if deal and type(deal.ilvl) == "number" and deal.ilvl > 0 then
            return deal.ilvl, "import"
        end
    end

    if type(task.importKey) == "string" and task.importKey ~= "" then
        local iv = tonumber(task.importKey:match(":i(%d+)"))
        if iv and iv > 0 then return iv, "import" end
    end

    if type(task.ilvl) == "number" and task.ilvl > 0 then
        return task.ilvl, "task"
    end

    local key = task.itemKey
    if type(key) == "string" and key ~= "" and not key:find("^pet")
       and ns.ItemKeyToItemString then
        local cached = computedByKey[key]
        if cached then return cached, "computed" end
        local wowStr = ns:ItemKeyToItemString(key)
        local iv = wowStr and DetailedIlvl(wowStr)
        if iv then
            computedByKey[key] = iv
            return iv, "computed"
        end
    end

    return 0
end

-- Item level to show for a task row, or nil when the item isn't gear or no
-- ilvl is known. Second return is the source (see GetTaskIlvl).
function IlvlDisplay:GetDisplayIlvl(task, hintID)
    if not task then return nil end
    if type(task.itemKey) == "string" and task.itemKey:find("^pet") then return nil end
    local itemID = self:ResolveItemID(task, hintID)
    if not itemID or not self:IsGear(itemID) then return nil end
    local ilvl, source = self:GetTaskIlvl(task)
    if ilvl and ilvl > 0 then return ilvl, source end
    return nil
end

-- " (233)" in gray, Auctionator-style, ready to append to a name. resumeColor
-- re-opens the caller's color after the suffix when the name sits inside a
-- larger colored run (MiniView); otherwise the suffix closes with |r.
function IlvlDisplay:Suffix(task, hintID, resumeColor)
    local ilvl = self:GetDisplayIlvl(task, hintID)
    if not ilvl then return "" end
    local gray = (ns.COLORS and ns.COLORS.GRAY) or "|cff888888"
    return gray .. " (" .. ilvl .. ")" .. (resumeColor or "|r")
end

-- Append the deal's item level to an already-populated item tooltip. When the
-- tooltip itself renders a different level (base item / scaled to this
-- character), say so explicitly rather than leave two conflicting numbers.
-- Returns true when a line was added.
function IlvlDisplay:AddTooltipLines(tooltip, task, hintID)
    if not tooltip or not task then return false end
    local ilvl, source = self:GetDisplayIlvl(task, hintID)
    if not ilvl or source == "computed" then return false end

    local label = (source == "import") and "Item level from import: " or "Item level: "
    tooltip:AddLine(label .. ilvl, 1, 0.82, 0)

    local shown
    if tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok and link then shown = DetailedIlvl(link) end
    end
    if shown and shown ~= ilvl then
        tooltip:AddLine(string.format(
            "The tooltip shows item level %d, scaled for this character; "
            .. "the deal was recorded at item level %d.", shown, ilvl),
            0.6, 0.6, 0.6, true)
    end
    return true
end

function IlvlDisplay:ClearCache()
    wipe(gearByID)
    wipe(idByName)
    wipe(computedByKey)
end
