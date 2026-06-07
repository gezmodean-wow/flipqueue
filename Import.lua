-- Import.lua
-- Parse pasted data from FlippingPal website results
-- Supports: FP website copy-paste, FP comma CSV, semicolon CSV (FP extractor),
--           tab-delimited (Excel/HTML table), Auctionator shopping list text, plain item names
local addonName, ns = ...

local Import = {}
ns.Import = Import

-- Imports above this many parsed items use the async chunked path
-- (PreviewAddChunked / SaveChunked) to avoid client freezes on full-region
-- FlippingPal dumps. See FQ-131.
Import.LARGE_THRESHOLD = 500
Import.CHUNK_SIZE = 100

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

-- FlippingPal reuses the cross-realm CSV column layout for its inventory
-- sell-deal export, padding the buy side with a "Realm 0" / "0g" placeholder
-- (the item came from the player's own inventory, so there's nothing to buy).
-- A buy side only counts as a real cross-realm flip when the realm names an
-- actual realm and the price parses to positive gold — otherwise the row is a
-- plain sell deal and must not be tagged dealType="flip". Shared by every
-- parser that detects cross-realm deals (FP comma CSV, tab-delimited, FP
-- website). See FQ-208.
local FP_PLACEHOLDER_BUY_REALM = "realm 0"

local function IsRealBuySide(buyRealm, buyPrice)
    if not buyRealm or buyRealm == "" then return false end
    if buyRealm:lower() == FP_PLACEHOLDER_BUY_REALM then return false end
    if IsFPSourceString(buyRealm) then return false end
    if not buyPrice or buyPrice == "" then return false end
    return (ns:ParseGoldValue(buyPrice) or 0) > 0
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

        -- Cross-realm only when the buy side is a real realm with positive
        -- gold — not FP's "Realm 0" / "0g" inventory-sell placeholder (FQ-208).
        if IsRealBuySide(buyRealm, buyPricePart) then
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

-- FP website header words that can be misidentified as item names by the
-- block-finder; filtered out at the end of FPWebsiteScan / its chunked twin.
local FP_HEADER_WORDS = { ["Name"] = true, ["Item"] = true, ["Item Name"] = true }

-- Lines processed per yield in the chunked scan. Each line costs ~5-6
-- regex matches in ClassifyLine; 500 lines per chunk lands at ~3000 regex
-- ops per yield (sub-frame).
local SCAN_CHUNK_SIZE = 500

-- Stages 2-4 of the FP website scan, all O(allLines) in cheap operations
-- (no regex). Pulled out so the sync and chunked variants both call into
-- the same back-end after stage 1 (line classification) completes.
local function FPWebsiteFindBlocks(allLines, allTypes)
    -- Skip header: everything up to and including the "/" separator
    local startIdx = 1
    for i, t in ipairs(allTypes) do
        if t == "SEP" then
            startIdx = i + 1
            break
        end
    end
    while startIdx <= #allLines and allTypes[startIdx] == "EMPTY" do
        startIdx = startIdx + 1
    end

    -- Find item blocks: a NAME line followed (within 2 lines) by a DATA line
    local itemBlocks = {}
    local i = startIdx
    while i <= #allLines do
        if allTypes[i] == "NAME" then
            for j = i + 1, math.min(i + 3, #allLines) do
                if allTypes[j] == "DATA" then
                    table.insert(itemBlocks, {nameIdx = i, dataIdx = j})
                    i = j + 1
                    break
                elseif allTypes[j] == "NAME" then
                    break
                end
            end
        end
        i = i + 1
    end

    -- Filter out FP website header words that can be misidentified as item names
    local filtered = {}
    for _, block in ipairs(itemBlocks) do
        if not FP_HEADER_WORDS[allLines[block.nameIdx]] then
            table.insert(filtered, block)
        end
    end
    return filtered
end

-- Internal: line classification + block finding for FP website format.
-- Stages 1-2 of the parse — cheap relative to the per-block processing
-- on smallish inputs, but stage 1 (~6 regexes per line) dominates total
-- parse time on multi-thousand-item full-region pastes.
-- Returns (itemBlocks, allLines, allTypes) so both the synchronous and
-- chunked entry points share this work.
local function FPWebsiteScan(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local allLines = {}
    local allTypes = {}

    for line in (text .. "\n"):gmatch("(.-)\n") do
        local trimmed = strtrim(line)
        table.insert(allLines, trimmed)
        table.insert(allTypes, ClassifyLine(trimmed))
    end

    return FPWebsiteFindBlocks(allLines, allTypes), allLines, allTypes
end

-- Async variant of FPWebsiteScan. Stage 1 (the ~6-regex-per-line classify
-- loop) is the dominant cost on big pastes — ~270k regex calls for a
-- 45k-line / 4500-item full-region dump. Chunking it across frames keeps
-- the client responsive during the multi-second pre-roll before
-- per-block processing starts. Stages 2-4 (FPWebsiteFindBlocks) run sync
-- after stage 1 — they're O(n) over allLines in cheap pure-Lua loops with
-- no regex, so they don't contribute meaningfully to the freeze. See FQ-131.
local function FPWebsiteScanChunked(text, onComplete)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    -- Phase 1a: split into raw lines (sync — gmatch is C-implemented and
    -- linear; not the bottleneck even at 45k lines).
    local rawLines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        rawLines[#rawLines + 1] = line
    end

    local total = #rawLines
    local allLines = {}
    local allTypes = {}

    if total == 0 then
        onComplete({}, allLines, allTypes)
        return
    end

    -- Phase 1b: classify each line in chunks. This is the regex-heavy
    -- stage; each chunk yields via C_Timer.After(0).
    local idx = 1
    local function ClassifyChunk()
        local chunkEnd = math.min(idx + SCAN_CHUNK_SIZE - 1, total)
        for li = idx, chunkEnd do
            local trimmed = strtrim(rawLines[li])
            allLines[li] = trimmed
            allTypes[li] = ClassifyLine(trimmed)
        end
        idx = chunkEnd + 1
        if idx > total then
            -- Stages 2-4 sync (fast, no regex)
            onComplete(FPWebsiteFindBlocks(allLines, allTypes), allLines, allTypes)
        else
            C_Timer.After(0, ClassifyChunk)
        end
    end
    ClassifyChunk()
end

-- Internal: process one FP website item block into a parsed item record.
-- Stage 3 of the parse — the heaviest stage, called per-block. Both the
-- synchronous and chunked entry points loop over this; the chunked
-- variant just yields between batches.
local function ProcessFPWebsiteBlock(allLines, allTypes, itemBlocks, idx)
    local block = itemBlocks[idx]
    local fullName = allLines[block.nameIdx]
    local dataLine = allLines[block.dataIdx]
    local sellRate, quality, category, ilvl, expansion = ParseDataFields(dataLine)

    local blockEnd
    if idx < #itemBlocks then
        blockEnd = itemBlocks[idx + 1].nameIdx - 1
    else
        blockEnd = #allLines
    end

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
    end

    -- Gold values order: [1] Sale Avg, [2] Sale Avg vs Buy, [3] Net revenue, [4] Listing price
    local sellPrice = goldValues[4] or goldValues[3] or goldValues[1] or "0g"
    local saleAvg = goldValues[1] or ""

    local dealType = "sell"
    local profitAmount = nil
    local profitPct = nil
    if buyRealm and buyRealm ~= "" and buyPrice and buyPrice ~= "" then
        dealType = "flip"
        local sellGold = ns:ParseGoldValue(goldValues[3] or sellPrice)
        local buyGold = ns:ParseGoldValue(buyPrice)
        if sellGold > 0 and buyGold > 0 then
            profitAmount = tostring(sellGold - buyGold) .. "g"
            profitPct = math.floor((sellGold - buyGold) / buyGold * 100)
        end
    end

    return {
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
    }
end

function Import:ParseFPWebsite(text)
    local itemBlocks, allLines, allTypes = FPWebsiteScan(text)
    local items = {}
    for idx = 1, #itemBlocks do
        items[#items + 1] = ProcessFPWebsiteBlock(allLines, allTypes, itemBlocks, idx)
    end
    return items
end

-- Async variant of ParseFPWebsite. Yields across both stages so a 4500-item
-- full-region paste doesn't freeze the client during parse (FQ-131):
--   - Stage 1 (line classification, regex-heavy) runs via FPWebsiteScanChunked
--   - Stage 3 (per-block field extraction) runs in chunks of `chunkSize` items
-- Stages 2 + 4 (block-finding + header-word filter) are O(n) cheap loops
-- and run synchronously between the two chunked stages.
function Import:ParseFPWebsiteChunked(text, chunkSize, onProgress, onComplete)
    chunkSize = chunkSize or Import.CHUNK_SIZE

    FPWebsiteScanChunked(text, function(itemBlocks, allLines, allTypes)
        local total = #itemBlocks
        local items = {}

        if total == 0 then
            if onComplete then onComplete(items) end
            return
        end

        local idx = 1
        local function ProcessNextChunk()
            local chunkEnd = math.min(idx + chunkSize - 1, total)
            for blockIdx = idx, chunkEnd do
                items[#items + 1] = ProcessFPWebsiteBlock(allLines, allTypes, itemBlocks, blockIdx)
            end
            idx = chunkEnd + 1
            if onProgress then onProgress(math.min(idx - 1, total), total) end
            if idx > total then
                if onComplete then onComplete(items) end
            else
                C_Timer.After(0, ProcessNextChunk)
            end
        end
        ProcessNextChunk()
    end)
end

--------------------------
-- FlippingPal Semicolon CSV (from extractor addon)
--------------------------
-- Format: itemID;itemName;quality;ilvl;bonusIDs;modifiers;quantity

-- Internal: parse one FP-extractor semicolon line into an item. Header
-- lines and empty lines return nil so callers can skip them.
local function ProcessFPSemicolonRow(line)
    line = strtrim(line)
    if line == "" or line:find("^itemID") then return nil end

    local parts = {strsplit(";", line)}
    if #parts < 2 then return nil end

    local itemID = strtrim(parts[1])
    if not itemID or itemID == "" then return nil end

    local itemName  = strtrim(parts[2] or "")
    local quality   = strtrim(parts[3] or "")
    local ilvl      = tonumber(strtrim(parts[4] or ""))
    local bonusIDs  = strtrim(parts[5] or "")
    local modifiers = strtrim(parts[6] or "")
    local quantity  = tonumber(strtrim(parts[7] or "")) or 1

    local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
    return {
        itemKey   = key,
        itemID    = itemID,
        name      = itemName,
        quality   = quality,
        ilvl      = ilvl or 0,
        bonusIDs  = bonusIDs,
        modifiers = modifiers,
        quantity  = quantity,
    }
end

function Import:ParseFPFormat(text)
    local items = {}
    for line in text:gmatch("([^\n]+)") do
        local item = ProcessFPSemicolonRow(line)
        if item then table.insert(items, item) end
    end
    return items
end

-- Async variant of ParseFPFormat. Splits the text into lines synchronously
-- (fast, O(n) string scan), then runs the per-line parse in chunks so a
-- multi-thousand-row extractor dump doesn't freeze the client. See FQ-131.
function Import:ParseFPFormatChunked(text, chunkSize, onProgress, onComplete)
    chunkSize = chunkSize or Import.CHUNK_SIZE
    local items = {}

    local lines = {}
    for line in text:gmatch("([^\n]+)") do
        table.insert(lines, line)
    end

    local total = #lines
    if total == 0 then
        if onComplete then onComplete(items) end
        return
    end

    local idx = 1
    local function ProcessNextChunk()
        local chunkEnd = math.min(idx + chunkSize - 1, total)
        for li = idx, chunkEnd do
            local item = ProcessFPSemicolonRow(lines[li])
            if item then items[#items + 1] = item end
        end
        idx = chunkEnd + 1
        if onProgress then onProgress(math.min(idx - 1, total), total) end
        if idx > total then
            if onComplete then onComplete(items) end
        else
            C_Timer.After(0, ProcessNextChunk)
        end
    end
    ProcessNextChunk()
end

--------------------------
-- Tab-Delimited (clean Excel/table export)
--------------------------

-- Internal helpers shared by the sync and chunked tab-delimited parsers.
local function BuildTabColMap(cols)
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
    return colMap
end

local function ProcessTabRow(line, colMap, hasCrossRealm)
    line = strtrim(line)
    if line == "" then return nil end

    local parts = {strsplit("\t", line)}

    local itemID    = colMap.itemID and strtrim(parts[colMap.itemID] or "") or ""
    local name      = colMap.name and strtrim(parts[colMap.name] or "") or ""
    if itemID == "" and name == "" then return nil end

    local quality   = colMap.quality and strtrim(parts[colMap.quality] or "") or ""
    local ilvl      = colMap.ilvl and tonumber(strtrim(parts[colMap.ilvl] or "")) or 0
    local bonusIDs  = colMap.bonusIDs and strtrim(parts[colMap.bonusIDs] or "") or ""
    local modifiers = colMap.modifiers and strtrim(parts[colMap.modifiers] or "") or ""
    local quantity  = colMap.quantity and tonumber(strtrim(parts[colMap.quantity] or "")) or 1

    local sellRealm = colMap.sellRealm and strtrim(parts[colMap.sellRealm] or "")
        or colMap.realm and strtrim(parts[colMap.realm] or "")
        or nil

    local sellPrice = colMap.sellPrice and strtrim(parts[colMap.sellPrice] or "")
        or colMap.price and strtrim(parts[colMap.price] or "")
        or nil

    local buyPriceVal = hasCrossRealm and strtrim(parts[colMap.buyPrice] or "") or ""
    local buyRealmVal = hasCrossRealm and strtrim(parts[colMap.buyRealm] or "") or ""

    local key = ns:MakeItemKey(itemID ~= "" and itemID or name, bonusIDs, modifiers)

    local isCrossRealm = IsRealBuySide(buyRealmVal, buyPriceVal)
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

    return {
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
    }
end

function Import:ParseTabFormat(text)
    local items = {}
    local lines = {strsplit("\n", text)}
    if #lines < 2 then return items end

    local colMap = BuildTabColMap({strsplit("\t", strtrim(lines[1]))})
    local hasCrossRealm = colMap.buyPrice and colMap.buyRealm

    for i = 2, #lines do
        local item = ProcessTabRow(lines[i], colMap, hasCrossRealm)
        if item then table.insert(items, item) end
    end

    return items
end

-- Async variant of ParseTabFormat. Header parsing runs sync (cheap); per-row
-- iteration is chunked so multi-thousand-row tab-delimited exports don't
-- freeze the client during parse. See FQ-131.
function Import:ParseTabFormatChunked(text, chunkSize, onProgress, onComplete)
    chunkSize = chunkSize or Import.CHUNK_SIZE
    local items = {}

    local lines = {strsplit("\n", text)}
    if #lines < 2 then
        if onComplete then onComplete(items) end
        return
    end

    local colMap = BuildTabColMap({strsplit("\t", strtrim(lines[1]))})
    local hasCrossRealm = colMap.buyPrice and colMap.buyRealm
    local total = #lines - 1
    local idx = 2

    local function ProcessNextChunk()
        local chunkEnd = math.min(idx + chunkSize - 1, #lines)
        for li = idx, chunkEnd do
            local item = ProcessTabRow(lines[li], colMap, hasCrossRealm)
            if item then items[#items + 1] = item end
        end
        idx = chunkEnd + 1
        if onProgress then onProgress(math.min(idx - 2, total), total) end
        if idx > #lines then
            if onComplete then onComplete(items) end
        else
            C_Timer.After(0, ProcessNextChunk)
        end
    end
    ProcessNextChunk()
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

-- Internal helpers shared by the sync and chunked FP comma CSV parsers.
-- Phase 1 (BuildFPCommaColMap) runs once per parse and is cheap; phase 2
-- (ProcessFPCommaCSVRow) is the per-line hot path that the chunked
-- variant batches across frames.
local function BuildFPCommaColMap(headerFields)
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
    return colMap
end

local function ProcessFPCommaCSVRow(line, colMap, hasCrossRealm)
    local fields = ParseCSVLine(line)
    if #fields < 2 then return nil end

    local name = colMap.name and strtrim(fields[colMap.name] or "") or ""
    if name == "" then return nil end

    local itemID    = colMap.itemID and strtrim(fields[colMap.itemID] or "") or ""
    local category  = colMap.category and strtrim(fields[colMap.category] or "") or ""
    local ilvl      = colMap.ilvl and tonumber(strtrim(fields[colMap.ilvl] or "")) or 0
    local sellRate  = colMap.sellRate and tonumber(strtrim(fields[colMap.sellRate] or "")) or 0
    local expansion = colMap.expansion and strtrim(fields[colMap.expansion] or "") or ""
    local quality   = colMap.quality and strtrim(fields[colMap.quality] or "") or ""
    local sellPrice = colMap.sellPrice and strtrim(fields[colMap.sellPrice] or "") or ""
    local sellRealm = colMap.sellRealm and strtrim(fields[colMap.sellRealm] or "") or ""
    local saleAvg   = colMap.saleAvg and strtrim(fields[colMap.saleAvg] or "") or ""

    local buyPriceVal = hasCrossRealm and strtrim(fields[colMap.buyPrice] or "") or ""
    local buyRealmVal = hasCrossRealm and strtrim(fields[colMap.buyRealm] or "") or ""

    local key = itemID ~= "" and ns:MakeItemKey(itemID, "", "") or name

    local isCrossRealm = IsRealBuySide(buyRealmVal, buyPriceVal)
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

    return {
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
    }
end

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

    local colMap = BuildFPCommaColMap(ParseCSVLine(lines[1]))
    if not colMap.name then return items end

    local hasCrossRealm = colMap.buyPrice and colMap.buyRealm

    for i = 2, #lines do
        local item = ProcessFPCommaCSVRow(lines[i], colMap, hasCrossRealm)
        if item then table.insert(items, item) end
    end

    return items
end

-- Async variant of ParseFPCommaCSV — yields between batches so multi-thousand-
-- row CSV pastes (FP "Download CSV" full-region exports) don't freeze the
-- client during parse. See FQ-131. Header parsing runs sync (cheap, O(1));
-- only the per-row loop is chunked.
function Import:ParseFPCommaCSVChunked(text, chunkSize, onProgress, onComplete)
    chunkSize = chunkSize or Import.CHUNK_SIZE
    local items = {}

    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local trimmed = strtrim(line)
        if trimmed ~= "" then
            table.insert(lines, trimmed)
        end
    end

    if #lines < 2 then
        if onComplete then onComplete(items) end
        return
    end

    local colMap = BuildFPCommaColMap(ParseCSVLine(lines[1]))
    if not colMap.name then
        if onComplete then onComplete(items) end
        return
    end

    local hasCrossRealm = colMap.buyPrice and colMap.buyRealm
    local total = #lines - 1
    local idx = 2

    local function ProcessNextChunk()
        local chunkEnd = math.min(idx + chunkSize - 1, #lines)
        for li = idx, chunkEnd do
            local item = ProcessFPCommaCSVRow(lines[li], colMap, hasCrossRealm)
            if item then items[#items + 1] = item end
        end
        idx = chunkEnd + 1
        if onProgress then onProgress(math.min(idx - 2, total), total) end
        if idx > #lines then
            if onComplete then onComplete(items) end
        else
            C_Timer.After(0, ProcessNextChunk)
        end
    end
    ProcessNextChunk()
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
-- Auctionator Shopping List / Point Blank Sniper
--------------------------
-- PBS (Point Blank Sniper) stores its lists in Auctionator's shopping-list
-- system, so a "PBS export" is actually an Auctionator shopping list export
-- string. The wire format is produced by:
--
--   Auctionator/Source/Shopping/ImportExport.lua:1
--     listName ^ entry1 ^ entry2 ^ ...
--
-- Each entry is an Auctionator "advanced search string" reconstituted by
-- Auctionator/Source/Search/Advanced.lua:397 as 14 semicolon-delimited
-- fields:
--
--   searchString ; categoryKey ; minItemLevel ; maxItemLevel ;
--   minLevel ; maxLevel ; minCraftedLevel ; maxCraftedLevel ;
--   minPrice ; maxPrice ; quality ; tier ; expansion ; quantity
--
-- Fields are written as empty strings when unset, except `tier` which
-- defaults to the literal "#" placeholder. `minPrice`/`maxPrice` are
-- stored in gold (Auctionator divides copper by 10000 before writing).
-- `searchString` is wrapped in double quotes for exact-match searches.
--
-- The `_pbs` metadata table preserves every field so we can round-trip
-- PBS → normalized → PBS with zero data loss via `Transformer:OutputPBS`.

function Import:ParsePBS(text)
    if not text or text == "" then return {} end

    -- Normalize line endings and strip any trailing whitespace so a
    -- pasted file with a trailing newline doesn't produce an empty tail
    -- segment.
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("%s+$", "")

    -- Split on ^ — listName is segment 1, entries are segments 2..N.
    local segments = { strsplit("^", text) }
    if #segments == 0 then return {} end

    -- If segment 1 doesn't look like an entry (no semicolons), it's the
    -- list name. Otherwise the caller pasted just the entries with no
    -- leading name, so we treat segment 1 as the first entry.
    local listName = ""
    local startIdx = 1
    if segments[1] and not segments[1]:find(";", 1, true) then
        listName = strtrim(segments[1])
        startIdx = 2
    end

    local items = {}
    for i = startIdx, #segments do
        local entry = segments[i]
        if entry and entry ~= "" then
            -- Auctionator's strsplit(";", entry) returns exactly 14 fields
            -- when the string is well-formed. We allow trailing empty fields
            -- to be missing (some exporters truncate them).
            local searchString, categoryKey, minIlvl, maxIlvl,
                  minLevel, maxLevel, minCraftedLevel, maxCraftedLevel,
                  minPrice, maxPrice, quality, tier, expansion, quantity =
                strsplit(";", entry)

            -- Unquote exact-match searches. Auctionator wraps them in ""
            -- in ReconstituteAdvancedSearch, and strips them on parse.
            local isExact = false
            local name = searchString or ""
            local exactInner = name:match('^"(.*)"$')
            if exactInner then
                name = exactInner
                isExact = true
            end
            name = strtrim(name)

            if name ~= "" then
                -- Parse numeric fields; empty string and "0" both mean
                -- "unset" for the ranges. Preserve tier "#" as nil so
                -- OutputPBS can round-trip the placeholder.
                local function numOrNil(s)
                    if not s or s == "" then return nil end
                    local n = tonumber(s)
                    if not n or n == 0 then return nil end
                    return n
                end

                local tierNum
                if tier and tier ~= "" and tier ~= "#" then
                    tierNum = tonumber(tier)
                end

                local pbsMeta = {
                    isExact         = isExact,
                    categoryKey     = (categoryKey ~= nil and categoryKey ~= "") and categoryKey or nil,
                    minItemLevel    = numOrNil(minIlvl),
                    maxItemLevel    = numOrNil(maxIlvl),
                    minLevel        = numOrNil(minLevel),
                    maxLevel        = numOrNil(maxLevel),
                    minCraftedLevel = numOrNil(minCraftedLevel),
                    maxCraftedLevel = numOrNil(maxCraftedLevel),
                    minPrice        = numOrNil(minPrice),
                    maxPrice        = numOrNil(maxPrice),
                    quality         = numOrNil(quality),
                    tier            = tierNum,
                    expansion       = numOrNil(expansion),
                    quantity        = numOrNil(quantity),
                }

                -- Map the quality enum to FlipQueue's text representation
                -- when set. Advanced.lua uses Enum.ItemQuality values
                -- (0=Poor..7=Heirloom), matching FlipQueue.
                local QUALITY_NAMES = {
                    [0] = "Poor", [1] = "Common", [2] = "Uncommon",
                    [3] = "Rare", [4] = "Epic", [5] = "Legendary",
                    [6] = "Artifact", [7] = "Heirloom",
                }
                local qualityText = pbsMeta.quality and QUALITY_NAMES[pbsMeta.quality] or ""

                table.insert(items, {
                    itemKey   = "",                     -- filled by Enrich via name lookup
                    itemID    = "",
                    name      = name,
                    quality   = qualityText,
                    ilvl      = pbsMeta.minItemLevel or 0,
                    bonusIDs  = "",
                    modifiers = "",
                    quantity  = 1,
                    _listName = listName,
                    _pbs      = pbsMeta,
                })
            end
        end
    end

    return items
end

--------------------------
-- Auto-Detect Format and Parse
--------------------------

-- Hybrid PBS detector. Fast-path on the ";;#;;" tier-placeholder substring
-- (catches >99% of real exports, zero allocations on negative matches);
-- structural fallback for the edge case where every entry in a list has a
-- real tier value set (e.g. an all-R3-crafted snipe list).
local function LooksLikePBS(text)
    if text:find(";;#;;", 1, true) then return true end

    -- Structural check: requires a ^ separator AND the first entry segment
    -- to contain at least 13 semicolons (the 14-field Auctionator
    -- advanced-search shape).
    local caretPos = text:find("^", 1, true)
    if not caretPos then return false end
    local segments = { strsplit("^", text) }
    if #segments < 2 then return false end
    -- Segment 1 is the list name, segment 2 is the first entry
    local firstEntry = segments[2]
    if not firstEntry or firstEntry == "" then return false end
    local _, semiCount = firstEntry:gsub(";", "")
    return semiCount >= 13
end

function Import:Parse(text)
    if not text or text == "" then return {} end

    -- Normalize line endings
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    -- PBS / Auctionator shopping list: detected BEFORE the generic ";"
    -- fallback because PBS entries contain semicolons that would otherwise
    -- route to ParseFPFormat.
    if LooksLikePBS(text) then
        return self:ParsePBS(text)
    end

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

-- Async parse entry point — detects format and dispatches to a chunked
-- parser. The format-detection logic mirrors Parse() exactly; the only
-- difference is that the per-row formats (FP website, FP comma CSV, FP
-- semicolon, tab-delimited) route to chunked variants that yield between
-- batches via C_Timer.After(0). This avoids client freezes on multi-
-- thousand-row pastes (FQ-131).
--
-- Smaller / less common formats (PBS, Auctionator text/inline, plain
-- name fallback) still parse synchronously since they're either cheap or
-- naturally bounded — but we still surface a uniform progress / complete
-- callback so callers don't need to special-case format.
--
-- Calls onComplete(items) once parsing finishes. onProgress(done, total)
-- fires per chunk on the chunked paths; for sync formats it fires once
-- at the end with (total, total).
function Import:ParseChunked(text, onProgress, onComplete)
    if not text or text == "" then
        if onComplete then onComplete({}) end
        return
    end

    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    local function CompleteSync(items)
        local total = #items
        if onProgress then onProgress(total, total) end
        if onComplete then onComplete(items) end
    end

    -- PBS / Auctionator advanced-search list — checked first (PBS entries
    -- contain semicolons that would otherwise route to ParseFPFormat).
    if LooksLikePBS(text) then
        CompleteSync(self:ParsePBS(text))
        return
    end

    -- FP website (chunked)
    local hasGoldLine = text:find("\n%d[%d,]*g\n") or text:match("^%d[%d,]*g\n")
    local hasPctLine  = text:find("\n%d[%d,]*%%\n") or text:match("^%d[%d,]*%%\n")
    local hasDecimal  = text:find("%d+%.%d+")
    if hasGoldLine and hasPctLine and hasDecimal then
        self:ParseFPWebsiteChunked(text, Import.CHUNK_SIZE, onProgress, onComplete)
        return
    end

    local firstLine = text:match("^%s*([^\n]+)")

    -- Auctionator shopping list text export ("--- List Name ---")
    if firstLine and strtrim(firstLine):match("^%-%-%-.*%-%-%-$") then
        CompleteSync(self:ParseAuctionatorText(text))
        return
    end

    -- FP comma CSV (chunked)
    if firstLine and (firstLine:find("^Item Name,") or firstLine:find("^Item ID,")) then
        self:ParseFPCommaCSVChunked(text, Import.CHUNK_SIZE, onProgress, onComplete)
        return
    end

    -- Auctionator inline (FP Buy - Realm^...)
    if firstLine and firstLine:find("^FP Buy %-") and firstLine:find("%^") then
        CompleteSync(self:ParseAuctionatorInline(text))
        return
    end

    -- FP semicolon CSV (chunked)
    if firstLine and firstLine:find(";") then
        self:ParseFPFormatChunked(text, Import.CHUNK_SIZE, onProgress, onComplete)
        return
    end

    -- Tab-delimited (chunked)
    if firstLine and firstLine:find("\t") then
        self:ParseTabFormatChunked(text, Import.CHUNK_SIZE, onProgress, onComplete)
        return
    end

    -- Generic comma CSV with known column names (chunked via FP comma CSV path)
    if firstLine and firstLine:find(",") and
       (firstLine:lower():find("sell rate") or firstLine:lower():find("sell realm")
        or firstLine:lower():find("sell price")) then
        self:ParseFPCommaCSVChunked(text, Import.CHUNK_SIZE, onProgress, onComplete)
        return
    end

    -- Plain name fallback — typically small, parses sync.
    CompleteSync(self:Parse(text))
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
-- Save() replaces the entire source, so we only check for duplicates
-- within the current paste batch — not against previously saved data.
-- Returns items annotated with _importStatus: "new", "duplicate"
function Import:PreviewAdd(items, source)
    if not ns.db or not ns.db.imports then return {} end

    local results = {}
    local batchMap = {} -- normalized key -> item (simulates Save's dedup)

    for _, item in ipairs(items) do
        local status = "new"
        local dupeReason = nil
        local key = ns:MakeImportKey(item.itemKey, item.name, item.targetRealm, item.ilvl)

        -- Exact key match within this batch
        if batchMap[key] then
            status = "duplicate"
            dupeReason = "same item & realm in paste"
        else
            -- Connected realm match within this batch
            local itemName = (item.name or ""):lower()
            for existKey, existItem in pairs(batchMap) do
                local keyMatch = existItem.itemKey == item.itemKey
                local nameMatch = itemName ~= "" and existItem.name
                    and existItem.name:lower() == itemName
                local ilvlConflict = (item.ilvl or 0) > 0 and (existItem.ilvl or 0) > 0
                    and item.ilvl ~= existItem.ilvl
                if (keyMatch or nameMatch) and not ilvlConflict and ns:RealmsOverlap(existItem.targetRealm, item.targetRealm) then
                    status = "duplicate"
                    dupeReason = "connected realm: " .. (existItem.targetRealm or "?")
                    break
                end
            end
        end

        if status == "new" then
            batchMap[key] = item
        end

        table.insert(results, {
            item = item,
            _importStatus = status,
            _dupeReason = dupeReason,
        })
    end

    return results
end

-- Async chunked version of PreviewAdd — yields between batches via C_Timer
-- so a multi-thousand-item paste doesn't freeze the client. See FQ-131.
-- onProgress(processed, total) is called after each chunk.
-- onComplete(results) is called when scanning is done.
function Import:PreviewAddChunked(items, source, chunkSize, onProgress, onComplete)
    if not ns.db or not ns.db.imports then
        if onComplete then onComplete({}) end
        return
    end

    chunkSize = chunkSize or Import.CHUNK_SIZE
    local total = #items
    local results = {}
    local batchMap = {}
    local idx = 1

    local function ProcessChunk()
        local chunkEnd = math.min(idx + chunkSize - 1, total)
        for i = idx, chunkEnd do
            local item = items[i]
            local status = "new"
            local dupeReason = nil
            local key = ns:MakeImportKey(item.itemKey, item.name, item.targetRealm, item.ilvl)

            if batchMap[key] then
                status = "duplicate"
                dupeReason = "same item & realm in paste"
            else
                local itemName = (item.name or ""):lower()
                for existKey, existItem in pairs(batchMap) do
                    local keyMatch = existItem.itemKey == item.itemKey
                    local nameMatch = itemName ~= "" and existItem.name
                        and existItem.name:lower() == itemName
                    local ilvlConflict = (item.ilvl or 0) > 0 and (existItem.ilvl or 0) > 0
                        and item.ilvl ~= existItem.ilvl
                    if (keyMatch or nameMatch) and not ilvlConflict and ns:RealmsOverlap(existItem.targetRealm, item.targetRealm) then
                        status = "duplicate"
                        dupeReason = "connected realm: " .. (existItem.targetRealm or "?")
                        break
                    end
                end
            end

            if status == "new" then
                batchMap[key] = item
            end

            results[#results + 1] = {
                item = item,
                _importStatus = status,
                _dupeReason = dupeReason,
            }
        end

        idx = chunkEnd + 1
        if onProgress then onProgress(math.min(idx - 1, total), total) end

        if idx <= total then
            C_Timer.After(0, ProcessChunk)
        else
            if onComplete then onComplete(results) end
        end
    end

    ProcessChunk()
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
        local key = ns:MakeImportKey(item.itemKey, item.name, item.targetRealm, item.ilvl)
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
                -- Different ilvl = different variant, not a duplicate
                local ilvlConflict = (item.ilvl or 0) > 0 and (existItem.ilvl or 0) > 0
                    and item.ilvl ~= existItem.ilvl
                if (keyMatch or nameMatch) and not ilvlConflict and ns:RealmsOverlap(existItem.targetRealm, item.targetRealm) then
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
        ns:PrintDebug("Merged " .. deduped .. " connected-realm duplicates.")
    end

    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
        ns.Sync:EmitDelta("IMP", { source = source, deals = srcMap })
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
            local key = ns:MakeImportKey(item.itemKey, item.name, item.targetRealm, item.ilvl)
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
                    local ilvlConflict = (item.ilvl or 0) > 0 and (existItem.ilvl or 0) > 0
                        and item.ilvl ~= existItem.ilvl
                    if (keyMatch or nameMatch) and not ilvlConflict and ns:RealmsOverlap(existItem.targetRealm, item.targetRealm) then
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
                ns:PrintDebug("Merged " .. deduped .. " connected-realm duplicates.")
            end
            if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
                ns.Sync:EmitDelta("IMP", { source = source, deals = srcMap })
            end
            if onComplete then onComplete(added) end
        end
    end

    ProcessChunk()
end

--------------------------
-- FP price-source resolution (FQ-177)
--------------------------
-- FlippingPal records carry both a "Listing price" (deal.expectedPrice — the
-- aggressive recommendation FP suggests posting AT) and a "Sale Avg"
-- (deal.saleAvg — the conservative historical median). On thin or volatile
-- items the Listing price can run 50–150× above the realm's actual market,
-- triggering blanket TSM-skip storms when posting. ResolveFPPrice picks the
-- price string to feed into the task's expectedPrice based on the user's
-- fpPriceSource setting (Settings → Imports). Falls back to Listing whenever
-- the chosen path is missing data so tasks are never priceless.
function ns:ResolveFPPrice(deal)
    if not deal then return "" end
    local listing = deal.expectedPrice or ""
    local saleAvg = deal.saleAvg or ""

    local mode = (ns.db and ns.db.settings and ns.db.settings.fpPriceSource) or "listing"

    if mode == "saleavg" then
        if saleAvg ~= "" then return saleAvg end
        return listing
    elseif mode == "auto" then
        -- TSM-clamped: keep Listing unless it's >10× DBRegionMarketAvg, in
        -- which case prefer Sale Avg. Requires TSM + a numeric Listing + a
        -- non-empty saleAvg + a usable itemKey; any miss falls through to
        -- Listing (no regression from "listing" mode).
        if saleAvg == "" then return listing end
        if not (ns.TSM and ns.TSM.IsEnabled and ns.TSM:IsEnabled() and ns.TSM.GetPrice) then
            return listing
        end
        local listingGold = ns:ParseGoldValue(listing)
        if listingGold <= 0 then return listing end
        local itemKey = deal.itemKey
        if not itemKey or itemKey == "" then return listing end
        local tsmCopper = ns.TSM:GetPrice(itemKey, "DBRegionMarketAvg")
        if not tsmCopper or tsmCopper <= 0 then return listing end
        if listingGold > 10 * (tsmCopper / 10000) then
            return saleAvg
        end
        return listing
    end

    return listing
end
