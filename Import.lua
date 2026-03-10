-- Import.lua
-- Parse pasted data from FlippingPal website results
-- Supports: FP website copy-paste, FP comma CSV, semicolon CSV (FP extractor), tab-delimited (Excel), plain item names
local addonName, ns = ...

local Import = {}
ns.Import = Import

--------------------------
-- Known WoW values
--------------------------

local KNOWN_QUALITIES = {
    Poor = true, Common = true, Uncommon = true, Rare = true,
    Epic = true, Legendary = true, Artifact = true, Heirloom = true,
}

local KNOWN_CATEGORIES = {
    Recipe = true, Pet = true, Armor = true, Profession = true,
    Weapon = true, Consumable = true, Container = true, Gem = true,
    Miscellaneous = true, Mount = true, Toy = true, Toys = true,
    Glyph = true, Reagent = true, Enhancement = true, Quest = true,
    Tradeskill = true, Companions = true,
}

--------------------------
-- Line Classification (tab-independent)
--------------------------

-- Classify a line by its content rather than structure
local function ClassifyLine(line)
    if line == "" then
        return "EMPTY"
    elseif line == "/" then
        return "SEP"
    elseif line:match("^[%d,]+g$") then
        return "GOLD"         -- standalone gold value: "900g", "41,550g"
    elseif line:match("^[%d,]+%%$") then
        return "PCT"          -- standalone percentage: "9999999%"
    elseif line == "No competition" then
        return "NOCOMP"
    elseif line:match("%d+%.%d+") then
        return "DATA"         -- contains decimal sell rate (0.064, 0.431)
    elseif line:match("[%d,]+g") and #line > 5 then
        -- Contains a gold value embedded in other text → realm line
        -- e.g., "Aegwynn, ...    0g    Player Inventor..."
        return "REALM"
    else
        return "NAME"         -- item name, header word, or other text
    end
end

--------------------------
-- Extract fields from a DATA line
--------------------------

local function ParseDataFields(dataLine)
    local sellRate = tonumber(dataLine:match("(%d+%.%d+)")) or 0
    local quality = ""
    local category = ""
    local expansion = ""
    local ilvl = 0

    -- Find quality word
    for q in pairs(KNOWN_QUALITIES) do
        if dataLine:find(q) then
            quality = q
            break
        end
    end

    -- Find category word
    for c in pairs(KNOWN_CATEGORIES) do
        if dataLine:find(c) then
            category = c
            break
        end
    end

    -- ilvl: integer appearing before the sell rate
    local srPos = dataLine:find("%d+%.%d+")
    if srPos then
        local before = dataLine:sub(1, srPos - 1)
        for num in before:gmatch("(%d+)") do
            ilvl = tonumber(num) or 0
        end
    end

    -- Expansion: word after sell rate that isn't a quality
    local srEnd = select(2, dataLine:find("%d+%.%d+"))
    if srEnd then
        local after = dataLine:sub(srEnd + 1)
        for word in after:gmatch("(%S+)") do
            if KNOWN_QUALITIES[word] then
                quality = word
            elseif expansion == "" and word ~= "" then
                expansion = word
            end
        end
    end

    return sellRate, quality, category, ilvl, expansion
end

-- Extract sell realm from a REALM line
local function ParseRealmLine(realmLine)
    -- Remove the gold value and source parts, keep the realm name
    -- Format: "Aegwynn, ..." or "Aegwynn, ...    0g    Player Inventor..."
    -- The realm is the text before the first gold value
    local realm = realmLine:match("^(.-)%s%s+[%d,]+g") -- before 2+ spaces then gold
        or realmLine:match("^(.-)%s+[%d,]+g")          -- before 1+ spaces then gold
        or realmLine:match("^(.-)\t[%d,]+g")            -- before tab then gold
        or realmLine                                      -- fallback: whole line
    return strtrim(realm)
end

--------------------------
-- FlippingPal Website Copy-Paste Parser
--------------------------
-- Structure per item:
--   NAME:   Full item name
--   DATA:   TruncatedName Category ilvl SellRate Expansion Quality
--   [STATS: Optional "Sockets: 1" etc.]
--   GOLD:   Sale Avg
--   PCT:    Sale Avg pct
--   GOLD:   Sale Avg vs Buy
--   PCT:    Sale Avg vs Buy pct
--   GOLD:   Net revenue
--   GOLD:   Listing price
--   [NOCOMP: "No competition"]
--   REALM:  SellRealm  BuyPrice  BuyRealm

function Import:ParseFPWebsite(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    local items = {}
    local allLines = {}
    local allTypes = {}

    for line in (text .. "\n"):gmatch("(.-)\n") do
        local trimmed = strtrim(line)
        table.insert(allLines, trimmed)
        table.insert(allTypes, ClassifyLine(trimmed))
    end

    -- Skip header: everything up to and including the "/" separator
    local startIdx = 1
    for i, t in ipairs(allTypes) do
        if t == "SEP" then
            startIdx = i + 1
            break
        end
    end
    -- Also skip leading empty lines
    while startIdx <= #allLines and allTypes[startIdx] == "EMPTY" do
        startIdx = startIdx + 1
    end

    -- Find item blocks: a NAME line followed (within 2 lines) by a DATA line
    local itemBlocks = {} -- {nameIdx, dataIdx}
    local i = startIdx
    while i <= #allLines do
        if allTypes[i] == "NAME" then
            -- Look ahead for a DATA line (next 1-3 lines)
            for j = i + 1, math.min(i + 3, #allLines) do
                if allTypes[j] == "DATA" then
                    table.insert(itemBlocks, {nameIdx = i, dataIdx = j})
                    i = j + 1
                    break
                elseif allTypes[j] == "NAME" then
                    -- Next NAME without a DATA → this NAME is not an item, skip
                    break
                end
            end
        end
        i = i + 1
    end

    -- Process each item block
    for idx, block in ipairs(itemBlocks) do
        local fullName = allLines[block.nameIdx]
        local dataLine = allLines[block.dataIdx]
        local sellRate, quality, category, ilvl, expansion = ParseDataFields(dataLine)

        -- Determine block end: everything until the next item block starts
        local blockEnd
        if idx < #itemBlocks then
            blockEnd = itemBlocks[idx + 1].nameIdx - 1
        else
            blockEnd = #allLines
        end

        -- Collect gold values, nocomp, and realm from the block
        local goldValues = {}
        local sellRealm = ""
        local noCompetition = false

        for j = block.dataIdx + 1, blockEnd do
            local lineType = allTypes[j]
            if lineType == "GOLD" then
                table.insert(goldValues, allLines[j])
            elseif lineType == "NOCOMP" then
                noCompetition = true
            elseif lineType == "REALM" then
                sellRealm = ParseRealmLine(allLines[j])
            end
            -- PCT, EMPTY, NAME (stray), STATS → skip
        end

        -- Gold values order: [1] Sale Avg, [2] Sale Avg vs Buy, [3] Net revenue, [4] Listing price
        local sellPrice = goldValues[4] or goldValues[3] or goldValues[1] or "0g"

        table.insert(items, {
            itemKey       = fullName,
            itemID        = "",
            name          = fullName,
            quality       = quality,
            ilvl          = ilvl,
            bonusIDs      = "",
            modifiers     = "",
            quantity      = 1,
            sellRate      = sellRate,
            category      = category,
            expansion     = expansion,
            targetRealm   = sellRealm,
            expectedPrice = sellPrice,
            noCompetition = noCompetition,
        })
    end

    return items
end

--------------------------
-- FlippingPal Semicolon CSV (from extractor addon)
--------------------------
-- Format: itemID;itemName;quality;ilvl;bonusIDs;modifiers;quantity

function Import:ParseFPFormat(text)
    local items = {}
    for line in text:gmatch("([^\n]+)") do
        line = strtrim(line)
        if line == "" or line:find("^itemID") then
            -- skip empty lines and header row
        else
            local parts = {strsplit(";", line)}
            if #parts >= 2 then
                local itemID    = strtrim(parts[1])
                local itemName  = strtrim(parts[2] or "")
                local quality   = strtrim(parts[3] or "")
                local ilvl      = tonumber(strtrim(parts[4] or ""))
                local bonusIDs  = strtrim(parts[5] or "")
                local modifiers = strtrim(parts[6] or "")
                local quantity  = tonumber(strtrim(parts[7] or "")) or 1

                if itemID and itemID ~= "" then
                    local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                    table.insert(items, {
                        itemKey   = key,
                        itemID    = itemID,
                        name      = itemName,
                        quality   = quality,
                        ilvl      = ilvl or 0,
                        bonusIDs  = bonusIDs,
                        modifiers = modifiers,
                        quantity  = quantity,
                    })
                end
            end
        end
    end

    return items
end

--------------------------
-- Tab-Delimited (clean Excel/table export)
--------------------------

function Import:ParseTabFormat(text)
    local items = {}
    local lines = {strsplit("\n", text)}
    if #lines < 2 then return items end

    local header = strtrim(lines[1])
    local cols = {strsplit("\t", header)}
    local colMap = {}
    for i, col in ipairs(cols) do
        col = strtrim(col):lower()
        if col:find("item") and col:find("id") then
            colMap.itemID = i
        elseif col == "name" or (col:find("item") and col:find("name")) then
            colMap.name = i
        elseif col:find("qual") then
            colMap.quality = i
        elseif col:find("ilvl") or (col:find("item") and col:find("level")) then
            colMap.ilvl = i
        elseif col:find("bonus") then
            colMap.bonusIDs = i
        elseif col:find("modifier") then
            colMap.modifiers = i
        elseif col:find("qty") or col:find("quant") then
            colMap.quantity = i
        elseif col:find("price") or col:find("sale") then
            colMap.price = i
        elseif col:find("sell") and col:find("rate") then
            colMap.sellRate = i
        elseif col:find("server") or col:find("realm") then
            colMap.realm = i
        end
    end

    if not colMap.itemID and not colMap.name then
        colMap.name = 1
    end

    for i = 2, #lines do
        local line = strtrim(lines[i])
        if line ~= "" then
            local parts = {strsplit("\t", line)}

            local itemID    = colMap.itemID and strtrim(parts[colMap.itemID] or "") or ""
            local name      = colMap.name and strtrim(parts[colMap.name] or "") or ""
            local quality   = colMap.quality and strtrim(parts[colMap.quality] or "") or ""
            local ilvl      = colMap.ilvl and tonumber(strtrim(parts[colMap.ilvl] or "")) or 0
            local bonusIDs  = colMap.bonusIDs and strtrim(parts[colMap.bonusIDs] or "") or ""
            local modifiers = colMap.modifiers and strtrim(parts[colMap.modifiers] or "") or ""
            local quantity  = colMap.quantity and tonumber(strtrim(parts[colMap.quantity] or "")) or 1
            local price     = colMap.price and strtrim(parts[colMap.price] or "") or nil
            local realm     = colMap.realm and strtrim(parts[colMap.realm] or "") or nil

            if itemID ~= "" or name ~= "" then
                local key = ns:MakeItemKey(itemID ~= "" and itemID or name, bonusIDs, modifiers)
                table.insert(items, {
                    itemKey       = key,
                    itemID        = itemID,
                    name          = name,
                    quality       = quality,
                    ilvl          = ilvl,
                    bonusIDs      = bonusIDs,
                    modifiers     = modifiers,
                    quantity      = quantity or 1,
                    expectedPrice = price,
                    targetRealm   = realm,
                })
            end
        end
    end

    return items
end

--------------------------
-- RFC 4180 CSV Field Parser (handles quoted fields with commas)
--------------------------

local function ParseCSVLine(line)
    local fields = {}
    local pos = 1
    local len = #line

    while pos <= len do
        if line:sub(pos, pos) == '"' then
            -- Quoted field: find matching close quote
            local fieldParts = {}
            pos = pos + 1 -- skip opening quote
            while pos <= len do
                local nextQuote = line:find('"', pos, true)
                if not nextQuote then
                    -- No closing quote found, take rest of line
                    table.insert(fieldParts, line:sub(pos))
                    pos = len + 1
                    break
                end
                if nextQuote < len and line:sub(nextQuote + 1, nextQuote + 1) == '"' then
                    -- Escaped quote (""), include one quote and continue
                    table.insert(fieldParts, line:sub(pos, nextQuote))
                    pos = nextQuote + 2
                else
                    -- End of quoted field
                    table.insert(fieldParts, line:sub(pos, nextQuote - 1))
                    pos = nextQuote + 1
                    -- Skip comma after closing quote
                    if pos <= len and line:sub(pos, pos) == ',' then
                        pos = pos + 1
                    end
                    break
                end
            end
            table.insert(fields, table.concat(fieldParts))
        else
            -- Unquoted field: find next comma
            local nextComma = line:find(',', pos, true)
            if nextComma then
                table.insert(fields, line:sub(pos, nextComma - 1))
                pos = nextComma + 1
            else
                table.insert(fields, line:sub(pos))
                pos = len + 1
            end
        end
    end

    -- Handle trailing comma (empty last field)
    if len > 0 and line:sub(len, len) == ',' then
        table.insert(fields, "")
    end

    return fields
end

--------------------------
-- FlippingPal Comma CSV (from FP team export)
--------------------------
-- Headers: Item Name,Category,ilvl,Sell Rate,Expansion,Quality,Extra Stats,
--          Sale Avg,Sale Avg vs Buy %,Sale Avg vs Buy,Sell vs Buy %,Sell vs Buy,
--          Sell Price,Sell Realm,Buy Price,Buy Realm

function Import:ParseFPCommaCSV(text)
    local items = {}
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local trimmed = strtrim(line)
        if trimmed ~= "" then
            table.insert(lines, trimmed)
        end
    end

    if #lines < 2 then return items end

    -- Parse header to build column map
    local headerFields = ParseCSVLine(lines[1])
    local colMap = {}
    for i, col in ipairs(headerFields) do
        col = strtrim(col):lower()
        if col == "item name" then
            colMap.name = i
        elseif col == "category" then
            colMap.category = i
        elseif col == "ilvl" then
            colMap.ilvl = i
        elseif col == "sell rate" then
            colMap.sellRate = i
        elseif col == "expansion" then
            colMap.expansion = i
        elseif col == "quality" then
            colMap.quality = i
        elseif col == "extra stats" then
            colMap.extraStats = i
        elseif col == "sale avg" then
            colMap.saleAvg = i
        elseif col == "sell price" then
            colMap.sellPrice = i
        elseif col == "sell realm" then
            colMap.sellRealm = i
        elseif col == "buy price" then
            colMap.buyPrice = i
        elseif col == "buy realm" then
            colMap.buyRealm = i
        end
    end

    if not colMap.name then return items end

    for i = 2, #lines do
        local fields = ParseCSVLine(lines[i])
        if #fields >= 2 then
            local name      = colMap.name and strtrim(fields[colMap.name] or "") or ""
            local category  = colMap.category and strtrim(fields[colMap.category] or "") or ""
            local ilvl      = colMap.ilvl and tonumber(strtrim(fields[colMap.ilvl] or "")) or 0
            local sellRate  = colMap.sellRate and tonumber(strtrim(fields[colMap.sellRate] or "")) or 0
            local expansion = colMap.expansion and strtrim(fields[colMap.expansion] or "") or ""
            local quality   = colMap.quality and strtrim(fields[colMap.quality] or "") or ""
            local sellPrice = colMap.sellPrice and strtrim(fields[colMap.sellPrice] or "") or ""
            local sellRealm = colMap.sellRealm and strtrim(fields[colMap.sellRealm] or "") or ""
            local saleAvg   = colMap.saleAvg and strtrim(fields[colMap.saleAvg] or "") or ""

            if name ~= "" then
                table.insert(items, {
                    itemKey       = name,
                    itemID        = "",
                    name          = name,
                    quality       = quality,
                    ilvl          = ilvl or 0,
                    bonusIDs      = "",
                    modifiers     = "",
                    quantity      = 1,
                    sellRate      = sellRate,
                    category      = category,
                    expansion     = expansion,
                    targetRealm   = sellRealm,
                    expectedPrice = sellPrice ~= "" and sellPrice or saleAvg,
                    noCompetition = false,
                })
            end
        end
    end

    return items
end

--------------------------
-- Auto-Detect Format and Parse
--------------------------

function Import:Parse(text)
    if not text or text == "" then return {} end

    -- Normalize line endings
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    -- Detect FlippingPal website format:
    -- Must have gold values on their own lines AND percentage lines
    local hasGoldLine = text:find("\n%d[%d,]*g\n") or text:match("^%d[%d,]*g\n")
    local hasPctLine  = text:find("\n%d[%d,]*%%\n") or text:match("^%d[%d,]*%%\n")
    local hasDecimal  = text:find("%d+%.%d+")  -- sell rate like 0.064

    if hasGoldLine and hasPctLine and hasDecimal then
        return self:ParseFPWebsite(text)
    end

    local firstLine = text:match("^([^\n]+)")

    -- FlippingPal comma CSV: header starts with "Item Name,"
    if firstLine and firstLine:find("^Item Name,") then
        return self:ParseFPCommaCSV(text)
    end

    -- Semicolon-delimited → FlippingPal CSV format (from extractor addon)
    if firstLine and firstLine:find(";") then
        return self:ParseFPFormat(text)
    end

    -- Tab-delimited → clean Excel / table export
    if firstLine and firstLine:find("\t") then
        return self:ParseTabFormat(text)
    end

    -- Generic comma CSV with header containing known column names
    if firstLine and firstLine:find(",") and
       (firstLine:lower():find("sell rate") or firstLine:lower():find("sell realm")
        or firstLine:lower():find("sell price")) then
        return self:ParseFPCommaCSV(text)
    end

    -- Fallback: each line is an item name
    local items = {}
    for line in text:gmatch("([^\n]+)") do
        line = strtrim(line)
        if line ~= "" then
            table.insert(items, {
                itemKey   = line,
                itemID    = "",
                name      = line,
                quality   = "",
                ilvl      = 0,
                bonusIDs  = "",
                modifiers = "",
                quantity  = 1,
            })
        end
    end
    return items
end

--------------------------
-- Auctionator Shopping List Import
--------------------------

function Import:ImportFromAuctionatorList(listName)
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        ns:PrintError("Auctionator not loaded.")
        return {}
    end

    local ok, searchStrings = pcall(function()
        return Auctionator.API.v1.GetShoppingListItems("FlipQueue", listName)
    end)

    if not ok or not searchStrings then
        ns:PrintError("Could not read Auctionator list: " .. tostring(listName))
        return {}
    end

    local items = {}
    for _, searchStr in ipairs(searchStrings) do
        local itemName = searchStr:match('^"([^"]+)"') or searchStr:match("^([^;]+)")
        if itemName then
            table.insert(items, {
                itemKey   = itemName,
                itemID    = "",
                name      = itemName,
                quality   = "",
                ilvl      = 0,
                bonusIDs  = "",
                modifiers = "",
                quantity  = 1,
            })
        end
    end

    return items
end
