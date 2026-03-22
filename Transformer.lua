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

    local items = {}
    for tsmStr, itemGroupPath in pairs(itemsDB) do
        if type(itemGroupPath) == "string" then
            -- Match exact group or child groups
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
function Transformer:_TSMStringToNormalized(tsmStr)
    if not tsmStr then return nil end

    -- Battle pet: "p:speciesID"
    local speciesID = tsmStr:match("^p:(%d+)")
    if speciesID then
        local petName = "Pet"
        local ok, name = pcall(C_PetJournal.GetPetInfoBySpeciesID, tonumber(speciesID))
        if ok and name then petName = name end

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

    local numID = tonumber(itemID)
    local itemName = "Item " .. itemID
    local icon, quality
    if numID and numID > 0 then
        -- C_Item.GetItemInfo returns: name, link, quality, ilvl, minLevel, type, subType, stackCount, equipLoc, texture, ...
        local ok1, name, _, itemQuality, _, _, _, _, _, _, iconTexture = pcall(C_Item.GetItemInfo, numID)
        if ok1 then
            if name then itemName = name end
            if itemQuality then quality = itemQuality end
            if iconTexture then icon = iconTexture end
        end
        if not icon then
            -- C_Item.GetItemInfoInstant returns: itemID, type, subType, equipLoc, icon, ...
            local ok2, _, _, _, _, tex = pcall(C_Item.GetItemInfoInstant, numID)
            if ok2 and tex then icon = tex end
        end
    end

    local itemKey = ns:MakeItemKey(itemID, bonusIDs, "")
    return {
        itemKey    = itemKey,
        itemID     = itemID,
        name       = itemName,
        quality    = quality and QUALITY_NAMES[quality] or "Unknown",
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

    if not searchStrings then return {} end

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
function Transformer:OutputAAAJSON(input, discount, priceSource)
    discount = discount or 90
    priceSource = priceSource or "DBMarket"

    local itemsList, petsList
    if input.items and input.pets then
        itemsList = input.items
        petsList = input.pets
    else
        local split = self:SplitPets(input)
        itemsList = split.items
        petsList = split.pets
    end

    -- Apply pricing if not already applied
    if ns.TSM and ns.TSM:IsEnabled() then
        local needsPrice = false
        for _, item in ipairs(itemsList) do
            if not item._priceCopper then needsPrice = true; break end
        end
        if needsPrice then
            local modifier = (100 - discount) / 100
            itemsList = self:PriceModify(itemsList, priceSource, modifier)
            petsList = self:PriceModify(petsList, priceSource, modifier)
        end
    end

    local itemsMap = {} -- numericID -> goldPrice
    local petsMap = {}  -- speciesID -> goldPrice

    for _, item in ipairs(itemsList) do
        -- Skip items with bonus IDs (AAA uses base item IDs only)
        if item.bonusIDs and item.bonusIDs ~= "" then
            -- skip
        else
            local numID = tostring(tonumber(tostring(item.itemID)))
            if numID and numID ~= "nil" and item._priceCopper then
                local goldPrice = item._priceCopper / 10000
                goldPrice = math.floor(goldPrice * 100 + 0.5) / 100
                itemsMap[numID] = goldPrice
            elseif numID and numID ~= "nil" and item.expectedPrice then
                local price = tonumber(item.expectedPrice)
                if price and price > 0 then
                    itemsMap[numID] = price
                end
            end
        end
    end

    for _, pet in ipairs(petsList) do
        local sid = tostring(pet.speciesID)
        if sid and pet._priceCopper then
            local goldPrice = pet._priceCopper / 10000
            goldPrice = math.floor(goldPrice * 100 + 0.5) / 100
            petsMap[sid] = goldPrice
        elseif sid and pet.expectedPrice then
            local price = tonumber(pet.expectedPrice)
            if price and price > 0 then
                petsMap[sid] = price
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

    local output = "// Items:\n" .. formatJSON(itemsMap) .. "\n\n// Pets:\n" .. formatJSON(petsMap)
    return output, itemCount, petCount
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

    local terms = {}
    local seen = {}
    for _, item in ipairs(items) do
        local name = item.name or ""
        if name ~= "" and not seen[name:lower()] then
            seen[name:lower()] = true
            -- Auctionator search terms: just the item name, quoted if it has special chars
            if name:find("[,;]") then
                table.insert(terms, '"' .. name .. '"')
            else
                table.insert(terms, name)
            end
        end
    end

    local header = "--- " .. listName
    local output = header .. "\n" .. table.concat(terms, "\n")
    return output, #terms
end

-- ==========================================
-- PRESET PIPELINES
-- ==========================================

-- TSM group -> AAA JSON
function Transformer:PresetTSMToAAA(profile, groupPath, discount, priceSource)
    local items = self:InputFromTSMGroup(profile, groupPath)
    if #items == 0 then return "", 0, 0 end
    return self:OutputAAAJSON(items, discount, priceSource)
end

-- Inventory -> AAA JSON
function Transformer:PresetInventoryToAAA(filter, value, discount, priceSource)
    local items = self:InputFromInventory(filter, value)
    if #items == 0 then return "", 0, 0 end
    return self:OutputAAAJSON(items, discount, priceSource)
end

-- ==========================================
-- ENRICHMENT
-- ==========================================

-- Enrich items with icon and quality data from WoW API / inventory DB
function Transformer:Enrich(items)
    local LookupItemInfo = ns.UI and ns.UI._LookupItemInfo
    if not LookupItemInfo then return items end

    for _, item in ipairs(items) do
        if not item.icon or not item.quality or item.quality == "" or item.quality == "Unknown" then
            local icon, quality, resolvedID = LookupItemInfo(item.itemID, item.itemKey, item.name)
            if icon then item.icon = icon end
            if quality then item.quality = QUALITY_NAMES[quality] or item.quality end
            if resolvedID and (not item.itemID or item.itemID == "") then
                item.itemID = tostring(resolvedID)
            end
        end
    end

    return items
end
