-- Transformer.lua
-- Input -> Transform -> Output pipeline for item data conversion
-- Replaces the AAA Transformer tool with an in-addon workflow
local addonName, ns = ...

local Transformer = {}
ns.Transformer = Transformer

-- Quality names matching WoW's Enum.ItemQuality values
local QUALITY_NAMES = {
    [0] = "Poor",
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
    [6] = "Artifact",
    [7] = "Heirloom",
}

-- Bind types that are never AH-tradeable
local UNTRADEABLE_BIND = {
    [1] = true, -- BoP
    [4] = true, -- Quest
    [7] = true, -- BtA
    [8] = true, -- BtW
    [9] = true, -- WuE
}

-- ==========================================
-- NORMALIZED ITEM STRUCTURE
-- ==========================================
-- Each item in the pipeline is:
-- { itemKey, itemID, name, quality, quantity, expectedPrice,
--   targetRealm, isBattlePet, speciesID, category, icon,
--   bonusIDs, modifiers, ilvl }

-- ==========================================
-- INPUT ADAPTERS
-- ==========================================

-- Read items from a TSM group in TradeSkillMasterDB
function Transformer:InputFromTSMGroup(profile, groupPath)
    if not ns.TSM or not ns.TSM:IsAvailable() then return {} end
    if not profile or not groupPath or groupPath == "" then return {} end

    local itemsDB = ns.TSM:GetItemsDB(profile)
    if not itemsDB then return {} end

    -- Single pass: string match + lightweight normalization (no GetItemInfo calls)
    local items = {}
    for tsmStr, itemGroupPath in pairs(itemsDB) do
        if type(itemGroupPath) == "string" then
            if itemGroupPath == groupPath
                or itemGroupPath:find(groupPath .. "`", 1, true) == 1 then
                local item = self:_TSMStringToNormalized(tsmStr)
                if item then
                    table.insert(items, item)
                end
            end
        end
    end

    return items
end

-- Convert a TSM item string ("i:12345", "i:12345::2:1663:2293", "p:1234") to normalized item
-- Lightweight: only uses GetItemInfoInstant (sync/fast). Enrich fills name/quality later.
function Transformer:_TSMStringToNormalized(tsmStr)
    if not tsmStr then return nil end

    -- Battle pet: "p:speciesID"
    local speciesID = tsmStr:match("^p:(%d+)")
    if speciesID then
        local petName = "Pet " .. speciesID
        if C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
            local ok, name = pcall(C_PetJournal.GetPetInfoBySpeciesID, tonumber(speciesID))
            if ok and type(name) == "string" and name ~= "" then petName = name end
        end

        return {
            itemKey    = "pet:" .. speciesID .. ";q0;",
            itemID     = "pet:" .. speciesID,
            name       = petName,
            quality    = "Unknown",
            quantity   = 1,
            isBattlePet = true,
            speciesID  = tonumber(speciesID),
            bonusIDs   = "",
            modifiers  = "",
        }
    end

    -- Standard item: "i:12345" or "i:12345::2:1663:2293"
    local itemID = tsmStr:match("^i:(%d+)")
    if not itemID then return nil end

    -- Parse bonus IDs from TSM format: "i:itemID::numBonuses:b1:b2:..."
    local bonusIDs = ""
    local afterID = tsmStr:match("^i:%d+::(.+)$")
    if afterID then
        local parts = {strsplit(":", afterID)}
        local numBonuses = tonumber(parts[1]) or 0
        local bonusList = {}
        for i = 2, numBonuses + 1 do
            if parts[i] and parts[i] ~= "" then
                table.insert(bonusList, parts[i])
            end
        end
        bonusIDs = table.concat(bonusList, ":")
    end

    -- Only use GetItemInfoInstant (fast, synchronous, no server request)
    -- Enrich will fill in name and quality later via LookupItemInfo
    local numID = tonumber(itemID)
    local icon
    if numID and numID > 0 then
        local ok, _, _, _, _, tex = pcall(C_Item.GetItemInfoInstant, numID)
        if ok and tex then icon = tex end
    end

    local itemKey = ns:MakeItemKey(itemID, bonusIDs, "")
    return {
        itemKey    = itemKey,
        itemID     = itemID,
        name       = "Item " .. itemID,
        quality    = "Unknown",
        quantity   = 1,
        isBattlePet = false,
        bonusIDs   = bonusIDs,
        modifiers  = "",
        icon       = icon,
    }
end

-- Read items from the imports map
function Transformer:InputFromImports(source)
    if not ns.db or not ns.db.imports then return {} end
    source = source or "fpScanner"
    local srcMap = ns.db.imports[source]
    if not srcMap then return {} end

    local items = {}
    for _, importItem in pairs(srcMap) do
        local speciesID = tostring(importItem.itemID or ""):match("^pet:(%d+)")
        table.insert(items, {
            itemKey       = importItem.itemKey or "",
            itemID        = importItem.itemID or "",
            name          = importItem.name or "",
            quality       = importItem.quality or "",
            quantity      = importItem.quantity or 1,
            expectedPrice = importItem.expectedPrice,
            targetRealm   = importItem.targetRealm or "",
            isBattlePet   = speciesID ~= nil,
            speciesID     = speciesID and tonumber(speciesID) or nil,
            category      = importItem.category,
            bonusIDs      = importItem.bonusIDs or "",
            modifiers     = importItem.modifiers or "",
            ilvl          = importItem.ilvl,
        })
    end

    return items
end

-- Read items from saved inventory data
-- filter: "all", "character", "warbank", "bags", "bank"
-- value: charKey for character filter, unused for others
function Transformer:InputFromInventory(filter, value)
    if not ns.db then return {} end
    local items = {}

    local function processInventoryItem(key, itemData, qty, owner)
        if UNTRADEABLE_BIND[itemData.bindType or 0] then return end
        if itemData.isBound then return end

        local idStr = tostring(itemData.itemID or "")
        local speciesID = idStr:match("^pet:(%d+)")

        -- Skip commodities
        if not speciesID then
            local numID = tonumber(itemData.itemID)
            if numID and numID > 0 then
                local ok, _, _, _, _, _, _, _, maxStack = pcall(C_Item.GetItemInfo, numID)
                if ok and maxStack and maxStack > 1 then return end
            end
        end

        table.insert(items, {
            itemKey     = key,
            itemID      = itemData.itemID or "",
            name        = itemData.name or "Unknown",
            quality     = itemData.quality or "",
            quantity    = qty,
            isBattlePet = speciesID ~= nil,
            speciesID   = speciesID and tonumber(speciesID) or nil,
            bonusIDs    = itemData.bonusIDs or "",
            modifiers   = itemData.modifiers or "",
            icon        = itemData.icon,
            _owner      = owner,
        })
    end

    -- Character inventories
    if filter == "all" or filter == "character" or filter == "bags" or filter == "bank" then
        for charKey, charData in pairs(ns.db.characters) do
            if filter ~= "character" or value == charKey then
                if charData.inventory and charData.inventory.items then
                    for key, itemData in pairs(charData.inventory.items) do
                        if itemData.locations then
                            local qty = 0
                            if filter == "bags" then
                                qty = (itemData.locations.bags or 0) + (itemData.locations.reagent or 0)
                            elseif filter == "bank" then
                                qty = itemData.locations.bank or 0
                            else
                                qty = (itemData.locations.bags or 0) + (itemData.locations.reagent or 0)
                                    + (itemData.locations.bank or 0)
                            end
                            if qty > 0 then
                                processInventoryItem(key, itemData, qty, charKey)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Warbank
    if filter == "all" or filter == "warbank" then
        if ns.db.warbank and ns.db.warbank.items then
            for key, itemData in pairs(ns.db.warbank.items) do
                processInventoryItem(key, itemData, itemData.quantity or 1, "Warbank")
            end
        end
    end

    return items
end

-- Read items from a to-do list (active or queued)
-- listIndex: nil = active list, 1..N = queued list index
-- actionFilter: "all" (default), "buy", "sell"
function Transformer:InputFromTodoList(listIndex, actionFilter)
    if not ns.db or not ns.db.todoLists then return {} end
    actionFilter = actionFilter or "all"

    local list
    if not listIndex then
        list = ns.db.todoLists.active
    else
        local q = ns.db.todoLists.upcoming
        if q and q[listIndex] then
            list = q[listIndex]
        end
    end

    if not list or not list.tasks then return {} end

    local items = {}
    for _, task in ipairs(list.tasks) do
        if actionFilter == "all"
            or (actionFilter == "buy" and task.action == "buy")
            or (actionFilter == "sell" and task.action == "sell") then

            local speciesID = tostring(task.itemID or ""):match("^pet:(%d+)")
            table.insert(items, {
                itemKey       = task.itemKey or "",
                itemID        = task.itemID or "",
                name          = task.name or "",
                quality       = task.quality or "",
                quantity      = task.quantity or 1,
                expectedPrice = task.expectedPrice or task.buyPrice or "",
                targetRealm   = task.targetRealm or "",
                isBattlePet   = speciesID ~= nil,
                speciesID     = speciesID and tonumber(speciesID) or nil,
                bonusIDs      = task.bonusIDs or "",
                modifiers     = task.modifiers or "",
                ilvl          = task.ilvl,
                _todoAction   = task.action,
                _todoStatus   = task.status,
            })
        end
    end

    return items
end

-- Read items from an Auctionator shopping list
function Transformer:InputFromAuctionatorList(name)
    if not name or name == "" then return {} end

    local searchStrings
    if type(Auctionator) == "table" and type(Auctionator.API) == "table"
        and type(Auctionator.API.v1) == "table" then
        local ok, result = pcall(Auctionator.API.v1.GetShoppingListItems, "FlipQueue", name)
        if ok and result then
            searchStrings = result
        end
    end

    if not searchStrings or #searchStrings == 0 then return {} end

    -- Reuse Import:ParsePBS so per-item metadata (isExact, quantity, ilvl
    -- filters, quality, tier) flows through to _pbs and survives round-trip
    -- back to OutputAuctionatorList / OutputPBS. The previous name-only
    -- path threw away everything but the search string and produced
    -- output that couldn't be re-imported into Auctionator (FQ-109).
    if ns.Import and ns.Import.ParsePBS then
        local pbsText = name .. "^" .. table.concat(searchStrings, "^")
        return ns.Import:ParsePBS(pbsText)
    end

    -- Fallback: name-only path if Import isn't available (shouldn't happen
    -- in practice — Import loads before Transformer in the .toc).
    local items = {}
    for _, searchStr in ipairs(searchStrings) do
        local itemName = searchStr:match('^"([^"]+)"') or searchStr:match("^([^;]+)")
        if itemName then
            table.insert(items, {
                itemKey     = itemName,
                itemID      = "",
                name        = itemName,
                quality     = "",
                quantity    = 1,
                isBattlePet = false,
                bonusIDs    = "",
                modifiers   = "",
            })
        end
    end

    return items
end

-- Read items from a PBS (Point Blank Sniper) / Auctionator shopping list
-- export string. Thin wrapper over Import:ParsePBS so the Transformer has
-- a first-class input adapter for text-pasted PBS data (the paste-mode UI
-- flow routes through Import:Parse's auto-detector and also works).
function Transformer:InputFromPBSText(text)
    if not text or text == "" then return {} end
    if not ns.Import or not ns.Import.ParsePBS then return {} end
    return ns.Import:ParsePBS(text)
end

-- ==========================================
-- TRANSFORM FUNCTIONS
-- ==========================================

-- Separate battle pets from regular items (needed for AAA format)
function Transformer:SplitPets(items)
    local regular = {}
    local pets = {}
    for _, item in ipairs(items) do
        if item.isBattlePet then
            table.insert(pets, item)
        elseif item._petSpeciesID then
            -- Unresolved item that matched a pet name via C_PetJournal
            -- but kept its original itemID for non-AAA outputs. Promote
            -- to battle pet for AAA (which has a separate pets array).
            local copy = self:_CopyItem(item)
            copy.isBattlePet = true
            copy.speciesID = item._petSpeciesID
            table.insert(pets, copy)
        else
            table.insert(regular, item)
        end
    end
    return { items = regular, pets = pets }
end

-- Apply a price modification using TSM price source
-- source: TSM price source string (e.g., "DBMarket")
-- modifier: multiplier (e.g., 0.8 for 80% of market, or 0.10 for 10%)
function Transformer:PriceModify(items, source, modifier)
    if not ns.TSM or not ns.TSM:IsEnabled() then return items end
    if not source or source == "" then return items end
    modifier = modifier or 1.0

    local result = {}
    for _, item in ipairs(items) do
        local copy = self:_CopyItem(item)
        local fqKey = item.itemKey or ns:MakeItemKey(item.itemID, item.bonusIDs or "", item.modifiers or "")
        local copper = ns.TSM:GetPrice(fqKey, source)

        if copper and copper > 0 then
            local goldPrice = (copper / 10000) * modifier
            goldPrice = math.floor(goldPrice * 100 + 0.5) / 100
            copy.expectedPrice = goldPrice
            copy._priceCopper = math.floor(copper * modifier + 0.5)
        end

        table.insert(result, copy)
    end
    return result
end

-- Rename/reformat fields according to a mapping table
-- mapping: { outputFieldName = inputFieldNameOrFunction, ... }
function Transformer:FieldMap(items, mapping)
    local result = {}
    for _, item in ipairs(items) do
        local mapped = {}
        for outKey, source in pairs(mapping) do
            if type(source) == "function" then
                mapped[outKey] = source(item)
            elseif type(source) == "string" then
                mapped[outKey] = item[source]
            end
        end
        table.insert(result, mapped)
    end
    return result
end

-- Filter items by a predicate function
function Transformer:Filter(items, predicate)
    local result = {}
    for _, item in ipairs(items) do
        if predicate(item) then
            table.insert(result, item)
        end
    end
    return result
end

-- Deduplicate by itemKey, summing quantities
function Transformer:MergeByKey(items)
    local keyMap = {}
    local order = {}
    for _, item in ipairs(items) do
        local key = item.itemKey or item.name or ""
        if keyMap[key] then
            keyMap[key].quantity = (keyMap[key].quantity or 1) + (item.quantity or 1)
        else
            keyMap[key] = self:_CopyItem(item)
            table.insert(order, key)
        end
    end
    local result = {}
    for _, key in ipairs(order) do
        table.insert(result, keyMap[key])
    end
    return result
end

-- Shallow copy an item table
function Transformer:_CopyItem(item)
    local copy = {}
    for k, v in pairs(item) do
        copy[k] = v
    end
    return copy
end

-- ==========================================
-- OUTPUT ADAPTERS
-- ==========================================

-- Produce AAA-compatible JSON
-- Accepts either a flat items array or a {items=..., pets=...} split table
-- AAA format: {"itemID": goldPrice, ...} where goldPrice is gold as a number.
-- AAA multiplies by 10000 internally to compare against copper. Decimals OK.
--
-- priceMode controls where the gold threshold comes from:
--   "tsm"      (default) — TSM price source × discount modifier; falls back
--                           to expectedPrice × modifier when TSM has no data.
--   "imported" — uses the raw imported price directly (no discount applied).
--                 For PBS items, reads `_pbs.maxPrice` (the snipe ceiling).
--                 For other import sources, reads `expectedPrice`. No TSM
--                 lookup; what the user pasted is what AAA sees.
function Transformer:OutputAAAJSON(input, discount, priceSource, priceMode)
    discount = discount or 90
    priceSource = priceSource or "DBMarket"
    priceMode = priceMode or "tsm"
    local modifier = (100 - discount) / 100

    local itemsList, petsList
    if input.items and input.pets then
        itemsList = input.items
        petsList = input.pets
    else
        local split = self:SplitPets(input)
        itemsList = split.items
        petsList = split.pets
    end

    -- TSM API for direct price lookups (bypass IsEnabled gate)
    local tsmAPI = TSM_API and type(TSM_API) == "table"
        and type(TSM_API.GetCustomPriceValue) == "function"
        and TSM_API or nil
    local tsmKeyFn = ns.TSM and ns.TSM.ItemKeyToTSMString and ns.TSM or nil

    local parseGold = ns.ParseGoldValue and function(v) return ns:ParseGoldValue(v) end

    -- Get TSM price in copper for an item, trying full key then base ID
    local function getTSMCopper(item)
        if not tsmAPI then return nil end
        -- Try full TSM string
        if tsmKeyFn and item.itemKey and item.itemKey ~= "" then
            local tsmStr = tsmKeyFn:ItemKeyToTSMString(item.itemKey)
            if tsmStr then
                local ok, val = pcall(tsmAPI.GetCustomPriceValue, priceSource, tsmStr)
                if ok and val and val > 0 then return val end
            end
        end
        -- Fallback: base item ID
        local baseID = item.itemKey and item.itemKey:match("^(%d+)") or tonumber(item.itemID)
        if baseID then
            local ok, val = pcall(tsmAPI.GetCustomPriceValue, priceSource, "i:" .. tostring(baseID))
            if ok and val and val > 0 then return val end
        end
        return nil
    end

    -- Parse a raw "expectedPrice" field into gold. Handles both numeric
    -- values (FP scanner imports) and string values like "5,000g" (hand-
    -- entered data). Returns nil if unparseable.
    local function parseExpectedGold(val)
        if val == nil then return nil end
        local gp = tonumber(val)
        if not gp and parseGold then
            gp = parseGold(tostring(val))
        end
        if gp and gp > 0 then return gp end
        return nil
    end

    -- Read the "recorded" price an item arrived with: PBS maxPrice (the
    -- snipe ceiling) is preferred, falling back to any generic
    -- expectedPrice from other import sources. Returns gold or nil.
    -- No discount is ever applied to recorded prices — the user set them
    -- explicitly as their target, and discounting would change the meaning.
    local function recordedPrice(item)
        local pbs = item._pbs
        if pbs and pbs.maxPrice and pbs.maxPrice > 0 then
            return pbs.maxPrice
        end
        return parseExpectedGold(item.expectedPrice)
    end

    -- Resolve gold price for AAA output.
    -- In "tsm" mode: try TSM price × discount first; if TSM has no data
    --   for this item, fall back to the recorded price (no discount) so
    --   items TSM can't price still make it into AAA with the user's
    --   hand-set threshold instead of 0. Previously the fallback was
    --   expectedPrice × modifier, which silently discounted user-entered
    --   prices — users asking "why is my 5000g entry showing as 4500g in
    --   AAA" were hitting exactly that.
    -- In "imported" mode: recorded price only (no discount, no TSM).
    local function resolveAAPrice(item)
        if priceMode == "imported" then
            local gp = recordedPrice(item)
            if gp then
                return math.floor(gp * 100 + 0.5) / 100
            end
            return nil
        end

        -- "tsm" mode (default): try TSM first, apply discount
        local copper = getTSMCopper(item)
        if copper then
            local gp = (copper / 10000) * modifier
            return math.floor(gp * 100 + 0.5) / 100
        end
        -- Fallback: recorded price (raw, no discount)
        local gp = recordedPrice(item)
        if gp then
            return math.floor(gp * 100 + 0.5) / 100
        end
        return nil
    end

    local function resolveItemID(item)
        local numID = tonumber(item.itemID)
        if numID and numID > 0 then return numID end
        if item.itemKey then
            local keyID = item.itemKey:match("^(%d+);")
            numID = tonumber(keyID)
            if numID and numID > 0 then return numID end
        end
        return nil
    end

    local itemsMap = {} -- numericID -> goldPrice
    local petsMap = {}  -- speciesID -> goldPrice
    local unpricedItems, unpricedPets = 0, 0

    for _, item in ipairs(itemsList) do
        local numID = resolveItemID(item)
        if numID then
            local numIDStr = tostring(numID)
            local goldPrice = resolveAAPrice(item) or 0
            if goldPrice == 0 then unpricedItems = unpricedItems + 1 end
            if not itemsMap[numIDStr] then
                itemsMap[numIDStr] = goldPrice
            elseif goldPrice > 0 and (itemsMap[numIDStr] == 0 or goldPrice < itemsMap[numIDStr]) then
                itemsMap[numIDStr] = goldPrice
            end
        end
    end

    for _, pet in ipairs(petsList) do
        local sid = pet.speciesID and tostring(pet.speciesID)
        if sid then
            local goldPrice = resolveAAPrice(pet) or 0
            if goldPrice == 0 then unpricedPets = unpricedPets + 1 end
            if not petsMap[sid] then
                petsMap[sid] = goldPrice
            elseif goldPrice > 0 and (petsMap[sid] == 0 or goldPrice < petsMap[sid]) then
                petsMap[sid] = goldPrice
            end
        end
    end

    -- Format as JSON
    local function formatJSON(tbl)
        local parts = {}
        local keys = {}
        for k in pairs(tbl) do table.insert(keys, k) end
        table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)

        for _, k in ipairs(keys) do
            table.insert(parts, string.format('  "%s": %s', k, tostring(tbl[k])))
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. "\n}"
    end

    local itemCount, petCount = 0, 0
    for _ in pairs(itemsMap) do itemCount = itemCount + 1 end
    for _ in pairs(petsMap) do petCount = petCount + 1 end

    return formatJSON(itemsMap), formatJSON(petsMap), itemCount, petCount, unpricedItems, unpricedPets
end

-- Produce FlippingPal-compatible semicolon CSV
function Transformer:OutputFPCSV(items)
    local lines = {"itemID;itemName;quality;ilvl;bonusIDs;modifiers;quantity"}

    -- Aggregate by key first
    local keyMap = {}
    local order = {}
    for _, item in ipairs(items) do
        local key = string.format("%s;%s;%s",
            tostring(item.itemID or ""), item.bonusIDs or "", item.modifiers or "")
        if keyMap[key] then
            keyMap[key].quantity = (keyMap[key].quantity or 1) + (item.quantity or 1)
        else
            keyMap[key] = self:_CopyItem(item)
            table.insert(order, key)
        end
    end

    for _, key in ipairs(order) do
        local item = keyMap[key]
        local safeName = tostring(item.name or "Unknown"):gsub(";", ",")
        table.insert(lines, string.format("%s;%s;%s;%s;%s;%s;%s",
            tostring(item.itemID or ""),
            safeName,
            tostring(item.quality or ""),
            tostring(item.ilvl or 0),
            item.bonusIDs or "",
            item.modifiers or "",
            tostring(item.quantity or 1)))
    end

    return table.concat(lines, "\n"), #order
end

-- Produce TSM group string: "i:12345,i:67890,p:1234"
function Transformer:OutputTSMGroupString(items)
    local parts = {}
    local seen = {}

    for _, item in ipairs(items) do
        local tsmStr
        if item.isBattlePet and item.speciesID then
            tsmStr = "p:" .. item.speciesID
        else
            local numID = tonumber(tostring(item.itemID))
            if numID and numID > 0 then
                if item.bonusIDs and item.bonusIDs ~= "" then
                    -- Full TSM string with bonus IDs
                    local bonuses = {}
                    for b in (item.bonusIDs):gmatch("[^:]+") do
                        bonuses[#bonuses + 1] = b
                    end
                    tsmStr = "i:" .. numID .. "::" .. #bonuses .. ":" .. table.concat(bonuses, ":")
                else
                    tsmStr = "i:" .. numID
                end
            end
        end

        if tsmStr and not seen[tsmStr] then
            seen[tsmStr] = true
            table.insert(parts, tsmStr)
        end
    end

    local count = #parts
    return table.concat(parts, ","), count
end

-- Produce Auctionator shopping list format
function Transformer:OutputAuctionatorList(items, listName)
    listName = listName or "FlipQueue Export"

    -- Produce Auctionator's actual import wire format:
    --     listName^entry^entry^...
    -- where each entry is the 14-field semicolon-separated search string
    --     name;cat;minIlvl;maxIlvl;minLvl;maxLvl;minCraftLvl;maxCraftLvl;
    --     minPrice;maxPrice;quality;tier;expansion;quantity
    -- The previous "--- listName\nname\nname" format was plain text and
    -- not importable into Auctionator at all (FQ-109). For the simple
    -- list case we drop all per-item constraints (just name + quantity);
    -- callers wanting full constraint round-trip should use OutputPBS.
    local parts = { listName }
    local seen = {}
    local written = 0

    for _, item in ipairs(items) do
        local name = item.name or ""
        if name ~= "" and not seen[name:lower()] then
            seen[name:lower()] = true

            -- Quote when the source flagged exact-match (preserved from
            -- ParsePBS via _pbs.isExact) OR when the name contains the
            -- separator characters Auctionator uses (`;` `^`) so the
            -- field stays intact.
            local pbs = item._pbs
            local isExact = (pbs and pbs.isExact) or name:find("[;^]") ~= nil
            local searchStr = isExact and ('"' .. name .. '"') or name

            -- Quantity: prefer PBS round-trip value, fall back to item.quantity
            -- when explicitly > 1 (1 is the default for sourced items and
            -- shouldn't pin the search to a single-result constraint).
            local qty = (pbs and pbs.quantity) or item.quantity
            local qtyField = ""
            local qNum = tonumber(qty)
            if qNum and qNum > 1 then qtyField = tostring(qNum) end

            -- 13 empty separators between name and quantity (= 14 fields)
            parts[#parts + 1] = searchStr .. ";;;;;;;;;;;;;" .. qtyField
            written = written + 1
        end
    end

    return table.concat(parts, "^"), written
end

-- Produce PBS / Auctionator shopping list export format. Reconstructs the
-- 14-field advanced-search wire format that Auctionator's
-- ReconstituteAdvancedSearch emits
-- (Auctionator/Source/Search/Advanced.lua:397), wrapped by the outer
-- `listName ^ entry ^ entry` format from
-- Auctionator/Source/Shopping/ImportExport.lua:1.
--
-- Round-trip guarantee: items that carry `_pbs` metadata (i.e., came from
-- Import:ParsePBS) reconstruct byte-for-byte identical to the input.
-- Items from other sources (TSM groups, to-do lists, FP imports)
-- synthesize search constraints from the item's `name`, `ilvl`, and
-- `quality` fields — the resulting PBS string represents "item at ilvl N+"
-- which is the most useful default for a shopping list.
function Transformer:OutputPBS(items, listName)
    listName = listName or (items[1] and items[1]._listName) or "FlipQueue Export"

    -- Numeric field emitter. Returns "" for nil / 0 / "" so round-trip
    -- matches Auctionator's `tostring(x or "")` pattern where x is already
    -- nil when unset.
    local function numField(n)
        if n == nil then return "" end
        local v = tonumber(n)
        if not v or v == 0 then return "" end
        return tostring(v)
    end

    -- Quality field. Accepts either a PBS numeric quality (0..7) or the
    -- text form Scanner/Import uses ("Epic", "Rare", ...). Maps text back
    -- to the numeric enum so the PBS output stays machine-readable.
    local QUALITY_TO_NUM = {
        Poor = 0, Common = 1, Uncommon = 2, Rare = 3,
        Epic = 4, Legendary = 5, Artifact = 6, Heirloom = 7,
    }
    local function qualityField(pbs, item)
        if pbs and pbs.quality then return tostring(pbs.quality) end
        if item.quality and item.quality ~= "" then
            local q = QUALITY_TO_NUM[item.quality]
            if q then return tostring(q) end
        end
        return ""
    end

    local parts = { listName }
    local written = 0
    for _, item in ipairs(items) do
        local pbs = item._pbs or {}
        local name = item.name or ""
        if name ~= "" then
            -- Wrap in double quotes if Auctionator had this marked as an
            -- exact-match search (stored in _pbs.isExact at parse time).
            local searchStr = pbs.isExact and ('"' .. name .. '"') or name

            -- minItemLevel defaults to item.ilvl when _pbs metadata is
            -- absent, so non-PBS sources produce a useful "item at ilvl N+"
            -- shopping list entry.
            local minIlvl = pbs.minItemLevel
            if minIlvl == nil and item.ilvl and item.ilvl > 0 then
                minIlvl = item.ilvl
            end

            local entry = table.concat({
                searchStr,
                pbs.categoryKey or "",
                numField(minIlvl),
                numField(pbs.maxItemLevel),
                numField(pbs.minLevel),
                numField(pbs.maxLevel),
                numField(pbs.minCraftedLevel),
                numField(pbs.maxCraftedLevel),
                numField(pbs.minPrice),
                numField(pbs.maxPrice),
                qualityField(pbs, item),
                tostring(pbs.tier or "#"),  -- Auctionator default placeholder
                numField(pbs.expansion),
                numField(pbs.quantity),
            }, ";")
            parts[#parts + 1] = entry
            written = written + 1
        end
    end

    return table.concat(parts, "^"), written
end

-- ==========================================
-- PRESET PIPELINES
-- ==========================================

-- TSM group -> AAA JSON
function Transformer:PresetTSMToAAA(profile, groupPath, discount, priceSource)
    local items = self:InputFromTSMGroup(profile, groupPath)
    if #items == 0 then return "", "", 0, 0 end
    return self:OutputAAAJSON(items, discount, priceSource)
end

-- Inventory -> AAA JSON
function Transformer:PresetInventoryToAAA(filter, value, discount, priceSource)
    local items = self:InputFromInventory(filter, value)
    if #items == 0 then return "", "", 0, 0 end
    return self:OutputAAAJSON(items, discount, priceSource)
end

-- ==========================================
-- ENRICHMENT
-- ==========================================

-- Import categories that indicate battle pets
local PET_CATEGORIES = { pet = true, companions = true }

-- Pet name -> speciesID map (built lazily from C_PetJournal)
local petNameMap

local function GetPetNameMap()
    if petNameMap then return petNameMap end
    petNameMap = {}
    if not C_PetJournal or not C_PetJournal.GetPetInfoBySpeciesID then return petNameMap end
    for speciesID = 1, 5000 do
        local ok, name = pcall(C_PetJournal.GetPetInfoBySpeciesID, speciesID)
        if ok and type(name) == "string" and name ~= "" then
            petNameMap[name:lower()] = speciesID
        end
    end
    return petNameMap
end

function Transformer:_GetPetNameMap() return GetPetNameMap() end

-- Per-item enrichment: resolve IDs, detect pets, fill icon/quality
local function EnrichItem(item, LookupItemInfo, pMap)
    local numID = tonumber(item.itemID)
    local needsID = not item.isBattlePet and (not numID or numID <= 0)
    local needsVisuals = not item.icon or not item.quality
        or item.quality == "" or item.quality == "Unknown"

    -- 1. Detect battle pets by category + pet name map
    if not item.isBattlePet and item.category then
        local cat = item.category:lower()
        if PET_CATEGORIES[cat] then
            local sid = pMap[(item.name or ""):lower()]
            if sid then
                item.isBattlePet = true
                item.speciesID = sid
                item.itemID = "pet:" .. sid
                item.itemKey = "pet:" .. sid .. ";q0;"
                needsID = false
                needsVisuals = false
            end
        end
    end

    -- 2. Try extracting itemID from itemKey format "12345;bonusIDs;modifiers"
    if needsID and item.itemKey then
        local keyID = item.itemKey:match("^(%d+);")
        if keyID then
            numID = tonumber(keyID)
            if numID and numID > 0 then
                item.itemID = tostring(numID)
                needsID = false
            end
        end
    end

    -- 3. Use LookupItemInfo for remaining ID / icon / quality
    if (needsID or needsVisuals) and LookupItemInfo then
        local icon, quality, resolvedID = LookupItemInfo(
            item.itemID, item.itemKey, item.name)
        if resolvedID and needsID then
            item.itemID = tostring(resolvedID)
        end
        if icon and not item.icon then item.icon = icon end
        if quality and (not item.quality or item.quality == ""
                or item.quality == "Unknown") then
            item.quality = QUALITY_NAMES[quality] or item.quality
        end
    end

    -- 4. Ensure itemKey is populated
    if not item.itemKey or item.itemKey == "" then
        if item.isBattlePet and item.speciesID then
            item.itemKey = "pet:" .. item.speciesID .. ";q0;"
        elseif item.itemID and item.itemID ~= "" then
            item.itemKey = ns:MakeItemKey(
                item.itemID, item.bonusIDs or "", item.modifiers or "")
        end
    end
end

-- Synchronous enrich (for small item sets)
function Transformer:Enrich(items)
    local LookupItemInfo = ns.UI and ns.UI._LookupItemInfo
    local pMap = GetPetNameMap()
    for _, item in ipairs(items) do
        EnrichItem(item, LookupItemInfo, pMap)
    end
    return items
end

-- Chunked async enrich (for large item sets, keeps UI responsive)
-- shouldCancel(): return true to abort
-- onProgress(processed, total): called after each chunk
-- onComplete(): called when all items are enriched
function Transformer:EnrichChunked(items, chunkSize, shouldCancel, onProgress, onComplete)
    local LookupItemInfo = ns.UI and ns.UI._LookupItemInfo
    local pMap = GetPetNameMap()
    chunkSize = chunkSize or 50
    local idx = 1
    local total = #items

    local function processChunk()
        if shouldCancel and shouldCancel() then return end
        local endIdx = math.min(idx + chunkSize - 1, total)
        for i = idx, endIdx do
            EnrichItem(items[i], LookupItemInfo, pMap)
        end
        idx = endIdx + 1
        if idx <= total then
            if onProgress then onProgress(idx - 1, total) end
            C_Timer.After(0, processChunk)
        else
            if onComplete then onComplete() end
        end
    end

    processChunk()
end
