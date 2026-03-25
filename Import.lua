-- Import.lua
-- Parse pasted data from FlippingPal website results
-- Supports: FP website copy-paste, FP comma CSV, semicolon CSV (FP extractor),
--           tab-delimited (Excel/HTML table), Auctionator shopping list text, plain item names
local addonName, ns = ...

local Import = {}
ns.Import = Import

-- Clean up realm strings: strip trailing "..." from truncated FP website data.
-- "Kirin Tor, ..." → "Kirin Tor", "Aegwynn, ..." → "Aegwynn"
local function CleanRealmString(realm)
    if not realm then return "" end
    -- Remove trailing ", ..." or ",..." or ", …"
    realm = realm:gsub(",?%s*%.%.%.%s*$", "")
    realm = realm:gsub(",?%s*\226\128\166%s*$", "")  -- UTF-8 ellipsis (…)
    return strtrim(realm)
end

-- Known FP source strings that appear in the realm line but are NOT realm names.
-- Used to prevent ParseRealmLine from misidentifying "Player Inventory" as a buyRealm.
local FP_SOURCE_STRINGS = {
    ["player inventory"] = true,
    ["player inventor"]  = true,   -- truncated by FP website
    ["auction house"]    = true,
    ["mail"]             = true,
    ["vendor"]           = true,
}

local function IsFPSourceString(str)
    return FP_SOURCE_STRINGS[str:lower()] or false
end

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
-- Also detects cross-realm flip data: SellRealm\tBuyPrice\tBuyRealm
-- Returns: sellRealm, buyPrice (or nil), buyRealm (or nil)
local function ParseRealmLine(realmLine)
    -- Try tab-separated cross-realm format first: "SellRealm\tBuyPrice\tBuyRealm"
    -- Also try multi-space separated (browser copy-paste uses spaces, not tabs)
    local tabParts = {strsplit("\t", realmLine)}
    if #tabParts < 3 then
        -- Fallback: split by 2+ consecutive whitespace (browser copy-paste)
        local spaceParts = {}
        for part in realmLine:gmatch("([^%s]+[^%s]-)%s%s+") do
            table.insert(spaceParts, part)
        end
        -- Capture trailing part after last multi-space gap
        local trailing = realmLine:match(".*%s%s+(.+)$")
        if trailing then table.insert(spaceParts, trailing) end
        if #spaceParts >= 3 then tabParts = spaceParts end
    end

    if #tabParts >= 3 then
        local sellPart = strtrim(tabParts[1])
        local buyPricePart = strtrim(tabParts[2])
        local buyRealmPart = strtrim(tabParts[3])

        -- sellPart might contain gold+source: "Aegwynn, ...    0g    Player Inventor..."
        -- Clean it: take text before first gold value
        local sellRealm = sellPart:match("^(.-)%s%s+[%d,]+g")
            or sellPart:match("^(.-)%s+[%d,]+g")
            or sellPart
        sellRealm = CleanRealmString(strtrim(sellRealm))

        -- buyRealmPart might also have trailing source info
        local buyRealm = buyRealmPart:match("^(.-)%s%s+") or buyRealmPart
        buyRealm = CleanRealmString(strtrim(buyRealm))

        -- Check if buyPrice looks like a gold value and buyRealm is a real realm (not a source string)
        if buyPricePart:match("[%d,]+g") and buyRealm ~= "" and not IsFPSourceString(buyRealm) then
            return sellRealm, buyPricePart, buyRealm
        end
    end

    -- Fallback: standard single-realm format
    -- Remove the gold value and source parts, keep the realm name
    -- Format: "Aegwynn, ..." or "Aegwynn, ...    0g    Player Inventor..."
    -- The realm is the text before the first gold value
    local realm = realmLine:match("^(.-)%s%s+[%d,]+g") -- before 2+ spaces then gold
        or realmLine:match("^(.-)%s+[%d,]+g")          -- before 1+ spaces then gold
        or realmLine:match("^(.-)\t[%d,]+g")            -- before tab then gold
        or realmLine                                      -- fallback: whole line
    realm = strtrim(realm)
    -- Strip FP website ", ..." suffix (means "and connected realms" — not a real name)
    realm = realm:gsub(",%s*%.%.%.$", "")
    return strtrim(realm), nil, nil
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
        local buyPrice = nil
        local buyRealm = nil
        local noCompetition = false

        for j = block.dataIdx + 1, blockEnd do
            local lineType = allTypes[j]
            if lineType == "GOLD" then
                table.insert(goldValues, allLines[j])
            elseif lineType == "NOCOMP" then
                noCompetition = true
            elseif lineType == "REALM" then
                local sr, bp, br = ParseRealmLine(allLines[j])
                sellRealm = sr
                if bp then
                    buyPrice = bp
                    buyRealm = br
                end
            end
            -- PCT, EMPTY, NAME (stray), STATS → skip
        end

        -- Gold values order: [1] Sale Avg, [2] Sale Avg vs Buy, [3] Net revenue, [4] Listing price
        local sellPrice = goldValues[4] or goldValues[3] or goldValues[1] or "0g"
        local saleAvg = goldValues[1] or ""

        -- Determine deal type and profit
        local dealType = "sell"
        local profitAmount = nil
        local profitPct = nil
        if buyRealm and buyRealm ~= "" and buyPrice and buyPrice ~= "" then
            dealType = "flip"
            -- Net revenue is goldValues[3], buy price is buyPrice
            -- Profit = net revenue - buy price (approximate)
            local sellGold = ns:ParseGoldValue(goldValues[3] or sellPrice)
            local buyGold = ns:ParseGoldValue(buyPrice)
            if sellGold > 0 and buyGold > 0 then
                profitAmount = tostring(sellGold - buyGold) .. "g"
                profitPct = math.floor((sellGold - buyGold) / buyGold * 100)
            end
        end

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
            dealType      = dealType,
            buyRealm      = buyRealm,
            buyPrice      = buyPrice,
            profitAmount  = profitAmount,
            profitPct     = profitPct,
            saleAvg       = saleAvg,
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
        elseif col:find("sell") and col:find("rate") then
            colMap.sellRate = i
        -- Cross-realm columns: match specific "buy/sell realm/price" before generic
        elseif col:find("buy") and col:find("realm") then
            colMap.buyRealm = i
        elseif col:find("buy") and col:find("price") then
            colMap.buyPrice = i
        elseif col:find("sell") and col:find("realm") then
            colMap.sellRealm = i
        elseif col:find("sell") and col:find("price") then
            colMap.sellPrice = i
        -- Generic fallbacks for single-realm formats
        elseif col:find("price") or col:find("sale") then
            colMap.price = i
        elseif col:find("server") or col:find("realm") then
            colMap.realm = i
        end
    end

    if not colMap.itemID and not colMap.name then
        colMap.name = 1
    end

    -- Detect cross-realm columns
    local hasCrossRealm = colMap.buyPrice and colMap.buyRealm

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

            -- Resolve sell realm: prefer explicit "Sell Realm" column, fall back to generic "Realm"
            local sellRealm = colMap.sellRealm and strtrim(parts[colMap.sellRealm] or "")
                or colMap.realm and strtrim(parts[colMap.realm] or "")
                or nil

            -- Resolve sell price: prefer explicit "Sell Price", fall back to generic "Price"
            local sellPrice = colMap.sellPrice and strtrim(parts[colMap.sellPrice] or "")
                or colMap.price and strtrim(parts[colMap.price] or "")
                or nil

            -- Cross-realm fields
            local buyPriceVal = hasCrossRealm and strtrim(parts[colMap.buyPrice] or "") or ""
            local buyRealmVal = hasCrossRealm and strtrim(parts[colMap.buyRealm] or "") or ""

            if itemID ~= "" or name ~= "" then
                local key = ns:MakeItemKey(itemID ~= "" and itemID or name, bonusIDs, modifiers)

                -- Determine deal type and profit
                -- Filter out FP source strings (Player Inventory, Auction House, etc.)
                local isCrossRealm = buyRealmVal ~= "" and buyPriceVal ~= ""
                    and not IsFPSourceString(buyRealmVal)
                local dealType = nil
                local profitAmount = nil
                local profitPct = nil
                if isCrossRealm then
                    dealType = "flip"
                    local sellGold = ns:ParseGoldValue(sellPrice or "")
                    local buyGold = ns:ParseGoldValue(buyPriceVal)
                    if sellGold > 0 and buyGold > 0 then
                        profitAmount = tostring(sellGold - buyGold) .. "g"
                        profitPct = math.floor((sellGold - buyGold) / buyGold * 100)
                    end
                end

                table.insert(items, {
                    itemKey       = key,
                    itemID        = itemID,
                    name          = name,
                    quality       = quality,
                    ilvl          = ilvl,
                    bonusIDs      = bonusIDs,
                    modifiers     = modifiers,
                    quantity      = quantity or 1,
                    expectedPrice = sellPrice,
                    targetRealm   = sellRealm,
                    dealType      = dealType,
                    buyRealm      = isCrossRealm and buyRealmVal or nil,
                    buyPrice      = isCrossRealm and buyPriceVal or nil,
                    profitAmount  = profitAmount,
                    profitPct     = profitPct,
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
        elseif col == "item id" or col == "itemid" or col == "item_id" then
            colMap.itemID = i
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

    -- Detect cross-realm columns
    local hasCrossRealm = colMap.buyPrice and colMap.buyRealm

    for i = 2, #lines do
        local fields = ParseCSVLine(lines[i])
        if #fields >= 2 then
            local name      = colMap.name and strtrim(fields[colMap.name] or "") or ""
            local itemID    = colMap.itemID and strtrim(fields[colMap.itemID] or "") or ""
            local category  = colMap.category and strtrim(fields[colMap.category] or "") or ""
            local ilvl      = colMap.ilvl and tonumber(strtrim(fields[colMap.ilvl] or "")) or 0
            local sellRate  = colMap.sellRate and tonumber(strtrim(fields[colMap.sellRate] or "")) or 0
            local expansion = colMap.expansion and strtrim(fields[colMap.expansion] or "") or ""
            local quality   = colMap.quality and strtrim(fields[colMap.quality] or "") or ""
            local sellPrice = colMap.sellPrice and strtrim(fields[colMap.sellPrice] or "") or ""
            local sellRealm = colMap.sellRealm and strtrim(fields[colMap.sellRealm] or "") or ""
            local saleAvg   = colMap.saleAvg and strtrim(fields[colMap.saleAvg] or "") or ""

            -- Cross-realm fields
            local buyPriceVal = hasCrossRealm and strtrim(fields[colMap.buyPrice] or "") or ""
            local buyRealmVal = hasCrossRealm and strtrim(fields[colMap.buyRealm] or "") or ""

            if name ~= "" then
                -- Use itemID for key if available, fall back to name
                local key = itemID ~= "" and ns:MakeItemKey(itemID, "", "") or name

                -- Determine deal type and profit
                -- Filter out FP source strings (Player Inventory, Auction House, etc.)
                local isCrossRealm = buyRealmVal ~= "" and buyPriceVal ~= ""
                    and not IsFPSourceString(buyRealmVal)
                local dealType = isCrossRealm and "flip" or "sell"
                local profitAmount = nil
                local profitPct = nil
                if isCrossRealm then
                    local sellGold = ns:ParseGoldValue(sellPrice ~= "" and sellPrice or saleAvg)
                    local buyGold = ns:ParseGoldValue(buyPriceVal)
                    if sellGold > 0 and buyGold > 0 then
                        profitAmount = tostring(sellGold - buyGold) .. "g"
                        profitPct = math.floor((sellGold - buyGold) / buyGold * 100)
                    end
                end

                table.insert(items, {
                    itemKey       = key,
                    itemID        = itemID,
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
                    dealType      = dealType,
                    buyRealm      = isCrossRealm and buyRealmVal or nil,
                    buyPrice      = isCrossRealm and buyPriceVal or nil,
                    profitAmount  = profitAmount,
                    profitPct     = profitPct,
                    saleAvg       = saleAvg,
                })
            end
        end
    end

    return items
end

--------------------------
-- Auctionator Shopping List Text Parser (pasted export)
--------------------------
-- Format:
--   --- List Name ---
--   "Item Name 1"
--   "Item Name 2";;;maxPrice
-- Detects "FP Buy - RealmName" in list name for cross-realm buy deals.

function Import:ParseAuctionatorText(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    local items = {}
    local listName = nil

    for line in (text .. "\n"):gmatch("(.-)\n") do
        local trimmed = strtrim(line)
        if trimmed == "" then
            -- skip
        elseif not listName then
            -- First non-empty line should be the header: "--- List Name ---"
            listName = trimmed:match("^%-+%s*(.-)%s*%-+$")
            if not listName or listName == "" then
                -- Not a valid header; treat the line itself as the list name
                listName = trimmed
            end
        else
            -- Parse Auctionator search string: "Name";;;maxPrice or Name;;;maxPrice
            local itemName = trimmed:match('^"([^"]+)"') or trimmed:match("^([^;]+)")
            if itemName and strtrim(itemName) ~= "" then
                itemName = strtrim(itemName)

                -- Extract price from search string if present
                local price = nil
                local pricePart = trimmed:match('^"[^"]+";[^;]*;[^;]*;([^;]+)')
                    or trimmed:match("^[^;]+;[^;]*;[^;]*;([^;]+)")
                if pricePart and tonumber(pricePart) then
                    -- Auctionator prices are in copper
                    price = ns:FormatGold(tonumber(pricePart))
                end

                -- Detect "FP Buy - RealmName" pattern for cross-realm buys
                local buyRealm = listName and listName:match("^FP Buy %- (.+)$")

                table.insert(items, {
                    itemKey       = itemName,
                    itemID        = "",
                    name          = itemName,
                    quality       = "",
                    ilvl          = 0,
                    bonusIDs      = "",
                    modifiers     = "",
                    quantity      = 1,
                    dealType      = buyRealm and "buy" or nil,
                    buyRealm      = buyRealm,
                    buyPrice      = price,
                    targetRealm   = buyRealm or "",
                })
            end
        end
    end

    return items
end

--------------------------
-- Auctionator Inline Format (from FP copy-paste)
--------------------------
-- Format: "FP Buy - RealmName^"Item1";;ilvlMin;ilvlMax;;;;;;price;quality;#;;^"Item2";;..."
-- Each line is a different realm. Items separated by ^ within the line.

function Import:ParseAuctionatorInline(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    local items = {}

    for line in (text .. "\n"):gmatch("(.-)\n") do
        local trimmed = strtrim(line)
        if trimmed == "" then
            -- skip
        else
            -- Split by ^ to get header + items
            local parts = {strsplit("^", trimmed)}
            if #parts >= 1 then
                -- First part is the header: "FP Buy - RealmName"
                local header = strtrim(parts[1])
                local buyRealm = header:match("^FP Buy %- (.+)$")

                -- Remaining parts are item search strings: "ItemName";;ilvl;ilvl;;;;;;price;quality;#;;
                for pi = 2, #parts do
                    local itemStr = strtrim(parts[pi])
                    if itemStr ~= "" then
                        local itemName = itemStr:match('^"([^"]+)"') or itemStr:match("^([^;]+)")
                        if itemName and strtrim(itemName) ~= "" then
                            itemName = strtrim(itemName)

                            -- Extract price (field index 10 in Auctionator format: after 9 semicolons)
                            local fields = {strsplit(";", itemStr)}
                            local price = nil
                            if fields[10] and tonumber(strtrim(fields[10])) then
                                local copper = tonumber(strtrim(fields[10]))
                                if copper > 0 then
                                    price = ns:FormatGold(copper)
                                end
                            end

                            table.insert(items, {
                                itemKey       = itemName,
                                itemID        = "",
                                name          = itemName,
                                quality       = "",
                                ilvl          = 0,
                                bonusIDs      = "",
                                modifiers     = "",
                                quantity      = 1,
                                dealType      = buyRealm and "buy" or nil,
                                buyRealm      = buyRealm,
                                buyPrice      = price,
                                targetRealm   = buyRealm or "",
                            })
                        end
                    end
                end
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

    -- Get first non-empty line for format detection
    local firstLine = text:match("^%s*([^\n]+)")

    -- Auctionator shopping list text export: starts with "--- List Name ---"
    if firstLine and strtrim(firstLine):match("^%-%-%-.*%-%-%-$") then
        return self:ParseAuctionatorText(text)
    end

    -- FlippingPal comma CSV: header starts with "Item Name," or "Item ID,"
    if firstLine and (firstLine:find("^Item Name,") or firstLine:find("^Item ID,")) then
        return self:ParseFPCommaCSV(text)
    end

    -- Auctionator shopping list internal format: "FP Buy - Realm^"Item";;...^"Item";;..."
    -- Multiple lines, each starting with "FP Buy - RealmName^" followed by ^-separated items
    if firstLine and firstLine:find("^FP Buy %-") and firstLine:find("%^") then
        return self:ParseAuctionatorInline(text)
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

    -- Detect "FP Buy - RealmName" pattern for buy to-dos
    local buyRealm = listName:match("^FP Buy %- (.+)$")

    local items = {}
    for _, searchStr in ipairs(searchStrings) do
        local itemName = searchStr:match('^"([^"]+)"') or searchStr:match("^([^;]+)")
        if itemName then
            -- Extract price from Auctionator search string if present
            -- Format: "Name";;;maxPrice;...
            local price = nil
            local pricePart = searchStr:match('^"[^"]+";[^;]*;[^;]*;([^;]+)')
                or searchStr:match("^[^;]+;[^;]*;[^;]*;([^;]+)")
            if pricePart and tonumber(pricePart) then
                -- Auctionator prices are in copper
                price = ns:FormatGold(tonumber(pricePart))
            end

            table.insert(items, {
                itemKey       = itemName,
                itemID        = "",
                name          = itemName,
                quality       = "",
                ilvl          = 0,
                bonusIDs      = "",
                modifiers     = "",
                quantity      = 1,
                dealType      = buyRealm and "buy" or nil,
                buyRealm      = buyRealm,
                buyPrice      = price,
                targetRealm   = buyRealm or "",
            })
        end
    end

    return items
end

--------------------------
-- Deal Classification
--------------------------

-- Returns true if a deal is a cross-realm flip/buy (has a buyRealm).
function Import:IsCrossRealmDeal(deal)
    return (deal.dealType == "flip" or deal.dealType == "buy")
        and deal.buyRealm and deal.buyRealm ~= ""
end

--------------------------
-- Import Management (replaces Queue operations)
--------------------------

-- Preview what ImportSave would do without modifying the imports.
-- Returns items annotated with _importStatus: "new", "duplicate", "update"
function Import:PreviewAdd(items, source)
    if not ns.db or not ns.db.imports then return {} end

    source = source or "fpScanner"
    local srcMap = ns.db.imports[source] or {}

    local results = {}
    local batchAdded = {} -- normalized key -> true

    for _, item in ipairs(items) do
        local status = "new"
        local dupeReason = nil
        local key = ns:MakeImportKey(item.itemKey, item.name, item.targetRealm)

        local existing = srcMap[key]
        if existing then
            -- Check if import would update any fields
            local wouldUpdate = false
            if item.expectedPrice and item.expectedPrice ~= "" then
                if (not existing.expectedPrice or existing.expectedPrice == "") then
                    wouldUpdate = true
                elseif existing.expectedPrice ~= item.expectedPrice then
                    wouldUpdate = true
                end
            end
            status = wouldUpdate and "update" or "duplicate"
            dupeReason = "same realm"
        else
            -- Check connected realms in existing imports
            local itemName = (item.name or ""):lower()
            for existKey, existItem in pairs(srcMap) do
                local keyMatch = existItem.itemKey == item.itemKey
                local nameMatch = itemName ~= "" and existItem.name
                    and existItem.name:lower() == itemName
                if (keyMatch or nameMatch) and ns:RealmsOverlap(existItem.targetRealm, item.targetRealm) then
                    local wouldUpdate = false
                    if item.expectedPrice and item.expectedPrice ~= "" then
                        if (not existItem.expectedPrice or existItem.expectedPrice == "") then
                            wouldUpdate = true
                        elseif existItem.expectedPrice ~= item.expectedPrice then
                            wouldUpdate = true
                        end
                    end
                    status = wouldUpdate and "update" or "duplicate"
                    dupeReason = "connected realm: " .. (existItem.targetRealm or "?")
                    break
                end
            end
        end

        -- Check within this batch
        if status == "new" then
            if batchAdded[key] then
                status = "duplicate"
                dupeReason = "duplicate in paste"
            else
                batchAdded[key] = true
            end
        end

        table.insert(results, {
            item = item,
            _importStatus = status,
            _dupeReason = dupeReason,
        })
    end

    return results
end

-- Save parsed items to the imports map. Always replaces existing imports
-- for this source — deals are ephemeral and only persist via to-do lists.
-- Returns count of items saved.
function Import:Save(items, source)
    if not ns.db or not ns.db.imports then return 0 end

    source = source or "fpScanner"

    -- Clean realm strings: strip "..." truncation from FP website
    for _, item in ipairs(items) do
        item.targetRealm = CleanRealmString(item.targetRealm or "")
    end

    -- Build cluster lookup from multi-realm strings in this batch.
    -- If "Kirin Tor, Steamwheedle Cartel, Sentinels" appears anywhere,
    -- then a single "Sentinels" or "Kirin Tor" entry expands to the full cluster.
    local clusterMap = {}
    for _, item in ipairs(items) do
        local realm = item.targetRealm
        if realm and realm:find(",") then
            for name in realm:gmatch("([^,]+)") do
                name = strtrim(name)
                if name ~= "" and #name >= 3 then
                    local key = name:lower()
                    if not clusterMap[key] or #realm > #clusterMap[key] then
                        clusterMap[key] = realm
                    end
                end
            end
        end
    end

    -- Expand single-realm entries to full cluster if the cluster is known from this batch
    local expanded = 0
    for _, item in ipairs(items) do
        local realm = item.targetRealm
        if realm and realm ~= "" and not realm:find(",") then
            local full = clusterMap[realm:lower()]
            if full then
                item.targetRealm = full
                expanded = expanded + 1
            end
        end
    end
    if expanded > 0 then
        ns:PrintDebug("Expanded " .. expanded .. " single-realm entries to full cluster names.")
    end

    -- Clear existing imports for this source — each import is a full replacement
    ns.db.imports[source] = {}
    local srcMap = ns.db.imports[source]

    local added = 0
    local deduped = 0

    for _, item in ipairs(items) do
        local key = ns:MakeImportKey(item.itemKey, item.name, item.targetRealm)
        local existing = srcMap[key]

        if existing then
            -- Same key already in this batch — update price, keep longer realm
            if item.expectedPrice and item.expectedPrice ~= "" then
                existing.expectedPrice = item.expectedPrice
            end
            if #(item.targetRealm or "") > #(existing.targetRealm or "") then
                existing.targetRealm = item.targetRealm
            end
            deduped = deduped + 1
        else
            -- Check connected realm dedup within this batch
            local isDuplicate = false
            local itemName = (item.name or ""):lower()
            for existKey, existItem in pairs(srcMap) do
                local keyMatch = existItem.itemKey == item.itemKey
                local nameMatch = itemName ~= "" and existItem.name
                    and existItem.name:lower() == itemName
                if (keyMatch or nameMatch) and ns:RealmsOverlap(existItem.targetRealm, item.targetRealm) then
                    if item.expectedPrice and item.expectedPrice ~= "" then
                        existItem.expectedPrice = item.expectedPrice
                    end
                    if #(item.targetRealm or "") > #(existItem.targetRealm or "") then
                        existItem.targetRealm = item.targetRealm
                    end
                    isDuplicate = true
                    deduped = deduped + 1
                    break
                end
            end

            if not isDuplicate then
                srcMap[key] = {
                    itemKey       = item.itemKey,
                    itemID        = item.itemID or "",
                    name          = item.name or "",
                    quality       = item.quality or "",
                    ilvl          = item.ilvl or 0,
                    bonusIDs      = item.bonusIDs or "",
                    modifiers     = item.modifiers or "",
                    quantity      = item.quantity or 1,
                    category      = item.category,
                    expansion     = item.expansion,
                    sellRate      = item.sellRate,
                    targetRealm   = item.targetRealm,
                    expectedPrice = item.expectedPrice,
                    noCompetition = item.noCompetition,
                    importedAt    = time(),
                    -- Cross-realm flip fields
                    dealType      = item.dealType,
                    buyRealm      = item.buyRealm,
                    buyPrice      = item.buyPrice,
                    profitAmount  = item.profitAmount,
                    profitPct     = item.profitPct,
                    saleAvg       = item.saleAvg,
                }
                added = added + 1
            end
        end
    end

    if deduped > 0 then
        ns:Print(ns.COLORS.GRAY .. "Merged " .. deduped .. " connected-realm duplicates.|r")
    end

    return added
end

-- Async chunked version of Save — processes items in batches via C_Timer
-- to keep the UI responsive during large imports.
-- onProgress(processed, total): called after each chunk
-- onComplete(added): called when all items are saved
function Import:SaveChunked(items, source, chunkSize, onProgress, onComplete)
    if not ns.db or not ns.db.imports then
        if onComplete then onComplete(0) end
        return
    end

    source = source or "fpScanner"
    chunkSize = chunkSize or 50

    -- Phase 1: synchronous prep (fast, O(n))
    for _, item in ipairs(items) do
        item.targetRealm = CleanRealmString(item.targetRealm or "")
    end

    local clusterMap = {}
    for _, item in ipairs(items) do
        local realm = item.targetRealm
        if realm and realm:find(",") then
            for name in realm:gmatch("([^,]+)") do
                name = strtrim(name)
                if name ~= "" and #name >= 3 then
                    local key = name:lower()
                    if not clusterMap[key] or #realm > #clusterMap[key] then
                        clusterMap[key] = realm
                    end
                end
            end
        end
    end

    for _, item in ipairs(items) do
        local realm = item.targetRealm
        if realm and realm ~= "" and not realm:find(",") then
            local full = clusterMap[realm:lower()]
            if full then item.targetRealm = full end
        end
    end

    -- Clear existing imports and start chunked insert
    ns.db.imports[source] = {}
    local srcMap = ns.db.imports[source]

    local idx = 1
    local added = 0
    local deduped = 0
    local total = #items

    local function ProcessChunk()
        local chunkEnd = math.min(idx + chunkSize - 1, total)
        for i = idx, chunkEnd do
            local item = items[i]
            local key = ns:MakeImportKey(item.itemKey, item.name, item.targetRealm)
            local existing = srcMap[key]

            if existing then
                if item.expectedPrice and item.expectedPrice ~= "" then
                    existing.expectedPrice = item.expectedPrice
                end
                if #(item.targetRealm or "") > #(existing.targetRealm or "") then
                    existing.targetRealm = item.targetRealm
                end
                deduped = deduped + 1
            else
                local isDuplicate = false
                local itemName = (item.name or ""):lower()
                for existKey, existItem in pairs(srcMap) do
                    local keyMatch = existItem.itemKey == item.itemKey
                    local nameMatch = itemName ~= "" and existItem.name
                        and existItem.name:lower() == itemName
                    if (keyMatch or nameMatch) and ns:RealmsOverlap(existItem.targetRealm, item.targetRealm) then
                        if item.expectedPrice and item.expectedPrice ~= "" then
                            existItem.expectedPrice = item.expectedPrice
                        end
                        if #(item.targetRealm or "") > #(existItem.targetRealm or "") then
                            existItem.targetRealm = item.targetRealm
                        end
                        isDuplicate = true
                        deduped = deduped + 1
                        break
                    end
                end

                if not isDuplicate then
                    srcMap[key] = {
                        itemKey       = item.itemKey,
                        itemID        = item.itemID or "",
                        name          = item.name or "",
                        quality       = item.quality or "",
                        ilvl          = item.ilvl or 0,
                        bonusIDs      = item.bonusIDs or "",
                        modifiers     = item.modifiers or "",
                        quantity      = item.quantity or 1,
                        category      = item.category,
                        expansion     = item.expansion,
                        sellRate      = item.sellRate,
                        targetRealm   = item.targetRealm,
                        expectedPrice = item.expectedPrice,
                        noCompetition = item.noCompetition,
                        importedAt    = time(),
                        dealType      = item.dealType,
                        buyRealm      = item.buyRealm,
                        buyPrice      = item.buyPrice,
                        profitAmount  = item.profitAmount,
                        profitPct     = item.profitPct,
                        saleAvg       = item.saleAvg,
                    }
                    added = added + 1
                end
            end
        end

        idx = chunkEnd + 1
        if onProgress then onProgress(math.min(idx - 1, total), total) end

        if idx <= total then
            C_Timer.After(0, ProcessChunk)
        else
            if deduped > 0 then
                ns:Print(ns.COLORS.GRAY .. "Merged " .. deduped .. " connected-realm duplicates.|r")
            end
            if onComplete then onComplete(added) end
        end
    end

    ProcessChunk()
end
