-- Export.lua
-- Re-exports inventory in FlippingPalInventoryExport compatible CSV format
-- Produces: itemID;itemName;quality;ilvl;bonusIDs;modifiers;quantity
local addonName, ns = ...

local Export = {}
ns.Export = Export

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

local CSV_HEADER = "itemID;itemName;quality;ilvl;bonusIDs;modifiers;quantity"

-- Bind types that are never AH-tradeable
local UNTRADEABLE_BIND = {
    [1] = true, -- BoP
    [4] = true, -- Quest
    [7] = true, -- BtA
    [8] = true, -- BtW
    [9] = true, -- WuE
}

-- Hidden tooltip for WuE detection
local exportTooltip = CreateFrame("GameTooltip", "FlipQueueExportTooltip", nil, "GameTooltipTemplate")

local function IsWarboundUntilEquipped(bagIndex, slot)
    exportTooltip:ClearLines()
    exportTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    exportTooltip:SetBagItem(bagIndex, slot)
    for i = 2, 5 do
        local line = _G["FlipQueueExportTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and (text:find("Warbound until equipped") or text:find("Binds to Warband until equipped")) then
                exportTooltip:Hide()
                return true
            end
        end
    end
    exportTooltip:Hide()
    return false
end

--------------------------
-- Item Data Extraction
--------------------------

local function GetItemExportData(itemLink, stackCount, containerItemInfo, bagIndex, slot)
    if not itemLink then return nil end

    -- Battle pets: |Hbattlepet:speciesID:level:quality:...|h[Name]|h
    local speciesID, petLevel, petQuality = itemLink:match("|Hbattlepet:(%d+):(%d+):(%d+)")
    if speciesID then
        local petName = itemLink:match("|h%[(.-)%]|h") or "Unknown Pet"
        return {
            itemID    = "pet:" .. speciesID,
            itemName  = petName,
            quality   = QUALITY_NAMES[tonumber(petQuality)] or "Unknown",
            ilvl      = tonumber(petLevel) or 0,
            bonusIDs  = "q" .. petQuality,
            modifiers = "",
            quantity  = stackCount or 1,
        }
    end

    -- Standard items: use container info as primary source, GetItemInfo as supplement
    local itemID = containerItemInfo and containerItemInfo.itemID
    if not itemID or itemID == 0 then
        -- Fallback: parse from link
        local parsedID = ns:ParseItemLink(itemLink)
        itemID = tonumber(parsedID)
        if not itemID or itemID == 0 then return nil end
    end

    -- Get extended item info (may return nil if not cached)
    local okInfo, itemName, _, itemQuality, _, _, _, _, itemStackCount, _, _, _, _, _, bindType =
        pcall(C_Item.GetItemInfo, itemLink)
    if not okInfo then itemName = nil end

    -- Extract name from link as fallback
    if not itemName then
        itemName = itemLink:match("|h%[(.-)%]|h")
    end
    if not itemName then return nil end

    -- Skip commodities (stackable items) — use max stack from GetItemInfo if available
    if itemStackCount and itemStackCount > 1 then return nil end
    -- Also skip if current stack > 1 (definitely stackable)
    if stackCount and stackCount > 1 then return nil end

    -- Skip untradeable bind types (only if GetItemInfo returned data)
    if bindType and UNTRADEABLE_BIND[bindType] then return nil end

    -- For BoE, check if already bound or WuE
    if bindType == 2 and bagIndex and slot then
        if containerItemInfo and containerItemInfo.isBound then return nil end
        if IsWarboundUntilEquipped(bagIndex, slot) then return nil end
    end

    -- Quality from GetItemInfo or container info
    local quality = itemQuality or (containerItemInfo and containerItemInfo.quality) or 0
    local qualityName = QUALITY_NAMES[quality] or "Unknown"

    -- ilvl
    local okIlvl, ilvlResult = false, 0
    if C_Item.GetDetailedItemLevelInfo then
        okIlvl, ilvlResult = pcall(C_Item.GetDetailedItemLevelInfo, itemLink)
    end
    local effectiveILvl = (okIlvl and ilvlResult) or 0
    local ilvl = effectiveILvl or 0

    local _, bonusIDs, modifiers = ns:ParseItemLink(itemLink)

    return {
        itemID    = itemID,
        itemName  = itemName,
        quality   = qualityName,
        ilvl      = ilvl,
        bonusIDs  = bonusIDs or "",
        modifiers = modifiers or "",
        quantity  = stackCount or 1,
    }
end

--------------------------
-- CSV Formatting
--------------------------

local function FormatCSVLine(data)
    local safeName = tostring(data.itemName):gsub(";", ",")
    return string.format("%s;%s;%s;%s;%s;%s;%s",
        tostring(data.itemID), safeName, tostring(data.quality),
        tostring(data.ilvl), data.bonusIDs, data.modifiers, tostring(data.quantity))
end

local function GetAggregateKey(data)
    return string.format("%s;%s;%s", tostring(data.itemID), data.bonusIDs, data.modifiers)
end

local function AggregateItems(itemDataList)
    local keyMap = {}
    local order = {}
    for _, data in ipairs(itemDataList) do
        local key = GetAggregateKey(data)
        if keyMap[key] then
            keyMap[key].quantity = keyMap[key].quantity + data.quantity
        else
            keyMap[key] = {
                itemID    = data.itemID,
                itemName  = data.itemName,
                quality   = data.quality,
                ilvl      = data.ilvl,
                bonusIDs  = data.bonusIDs,
                modifiers = data.modifiers,
                quantity  = data.quantity,
            }
            table.insert(order, key)
        end
    end
    local result = {}
    for _, key in ipairs(order) do
        table.insert(result, keyMap[key])
    end
    return result
end

--------------------------
-- Live Scan + Export
--------------------------

local function ScanAndExport(bagIndices)
    local itemDataList = {}
    local totalSlots = 0
    local totalItems = 0
    local skipped = 0
    for _, bagIndex in ipairs(bagIndices) do
        local okSlots, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if not okSlots or not numSlots then numSlots = 0 end
        totalSlots = totalSlots + numSlots
        for slot = 1, numSlots do
            local okInfo, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
            if not okInfo then info = nil end
            if info and info.hyperlink then
                totalItems = totalItems + 1
                local ok, data = pcall(GetItemExportData, info.hyperlink, info.stackCount, info, bagIndex, slot)
                if ok and data then
                    table.insert(itemDataList, data)
                else
                    skipped = skipped + 1
                end
            end
        end
    end

    if totalItems > 0 and #itemDataList == 0 then
        ns:Print(ns.COLORS.GRAY .. "Export: scanned " .. totalItems ..
            " items across " .. totalSlots .. " slots, " .. skipped ..
            " filtered (commodities/bound/untradeable).|r")
    end

    local aggregated = AggregateItems(itemDataList)
    local lines = {CSV_HEADER}
    for _, data in ipairs(aggregated) do
        table.insert(lines, FormatCSVLine(data))
    end
    return table.concat(lines, "\n"), #aggregated
end

function Export:ExportBags()
    local bags = {}
    for _, b in ipairs(ns.INVENTORY_BAGS) do table.insert(bags, b) end
    table.insert(bags, ns.REAGENT_BAG)
    return ScanAndExport(bags)
end

function Export:ExportBank()
    return ScanAndExport(ns.BANK_TABS)
end

function Export:ExportWarbank()
    local okLock, lockReason = pcall(C_Bank.FetchBankLockedReason, Enum.BankType.Account)
    if not okLock or lockReason ~= nil then
        ns:Print(ns.COLORS.YELLOW .. "Warbank not accessible for export.|r")
        return "", 0
    end
    return ScanAndExport(ns.WARBANK_TABS)
end

function Export:ExportAll()
    local bags = {}
    for _, b in ipairs(ns.INVENTORY_BAGS) do table.insert(bags, b) end
    table.insert(bags, ns.REAGENT_BAG)
    for _, b in ipairs(ns.BANK_TABS) do table.insert(bags, b) end
    for _, b in ipairs(ns.WARBANK_TABS) do table.insert(bags, b) end
    return ScanAndExport(bags)
end

--------------------------
-- Export from Saved Data
--------------------------

function Export:ExportSaved(mode)
    if not ns.db then return CSV_HEADER .. "\n", 0 end

    mode = mode or "all"
    local charKey = ns:GetCharKey()
    local charData = ns.db.inventory[charKey]
    local itemDataList = {}

    local function processItem(itemData, qty)
        if UNTRADEABLE_BIND[itemData.bindType or 0] then return end
        if itemData.isBound then return end

        local itemID = itemData.itemID
        local itemName = itemData.name or "Unknown"
        local quality = "Unknown"
        local ilvl = 0

        -- Battle pets
        local speciesID = tostring(itemID):match("^pet:(%d+)$")
        if speciesID then
            local petQuality = (itemData.bonusIDs or ""):match("q(%d+)")
            table.insert(itemDataList, {
                itemID    = "pet:" .. speciesID,
                itemName  = itemName,
                quality   = QUALITY_NAMES[tonumber(petQuality)] or "Unknown",
                ilvl      = 0,
                bonusIDs  = itemData.bonusIDs or "",
                modifiers = "",
                quantity  = qty,
            })
            return
        end

        -- Regular items: look up quality/ilvl/stackability
        local numID = tonumber(itemID)
        if numID and numID > 0 then
            local ok, name, _, itemQuality, itemLevel, _, _, _, maxStack = pcall(C_Item.GetItemInfo, numID)
            if ok then
                if maxStack and maxStack > 1 then return end -- skip commodities
                if itemQuality then quality = QUALITY_NAMES[itemQuality] or "Unknown" end
                ilvl = itemLevel or 0
            end
        end

        table.insert(itemDataList, {
            itemID    = itemID,
            itemName  = itemName,
            quality   = quality,
            ilvl      = ilvl,
            bonusIDs  = itemData.bonusIDs or "",
            modifiers = itemData.modifiers or "",
            quantity  = qty,
        })
    end

    -- Bags (bags + reagent locations from current character)
    if mode == "bags" or mode == "all" then
        if charData and charData.items then
            for _, itemData in pairs(charData.items) do
                if itemData.locations then
                    local bagQty = (itemData.locations.bags or 0) + (itemData.locations.reagent or 0)
                    if bagQty > 0 then
                        processItem(itemData, bagQty)
                    end
                end
            end
        end
    end

    -- Bank
    if mode == "bank" or mode == "all" then
        if charData and charData.items then
            for _, itemData in pairs(charData.items) do
                if itemData.locations and itemData.locations.bank and itemData.locations.bank > 0 then
                    processItem(itemData, itemData.locations.bank)
                end
            end
        end
    end

    -- Warbank
    if mode == "warbank" or mode == "wb" or mode == "all" then
        if ns.db.warbank and ns.db.warbank.items then
            for _, itemData in pairs(ns.db.warbank.items) do
                processItem(itemData, itemData.quantity or 1)
            end
        end
    end

    local aggregated = AggregateItems(itemDataList)
    local lines = {CSV_HEADER}
    for _, data in ipairs(aggregated) do
        table.insert(lines, FormatCSVLine(data))
    end
    return table.concat(lines, "\n"), #aggregated
end

--------------------------
-- Filter System
--------------------------

-- Filter state
local filterMode = "everything"  -- "everything", "tsmgroup", "auctionator"
local filterValue = ""           -- group path or list name

-- Export format state
local exportFormat = "csv"       -- "csv" or "aaa"
local aaaDiscount = 90           -- default: buy at 10% of market
local aaaPriceSource = "DBMarket"

function Export:GetFilterMode() return filterMode end
function Export:GetFilterValue() return filterValue end
function Export:GetFormat() return exportFormat end
function Export:GetAAADiscount() return aaaDiscount end
function Export:GetAAAPriceSource() return aaaPriceSource end

function Export:SetFilter(mode, value)
    filterMode = mode or "everything"
    filterValue = value or ""
end

function Export:SetFormat(fmt)
    exportFormat = fmt or "csv"
end

function Export:SetAAASettings(discount, priceSource)
    if discount then aaaDiscount = discount end
    if priceSource then aaaPriceSource = priceSource end
end

-- Build lookup table from TSM group
local function GetTSMGroupItems(groupPath)
    if not ns.TSM or not ns.TSM:IsAvailable() then return nil end
    if not groupPath or groupPath == "" then return nil end

    local set = {}

    -- Method 1: TSM_API.GetGroupItems (if it exists)
    local ok, items = pcall(function()
        local result = {}
        if TSM_API.GetGroupItems then
            TSM_API:GetGroupItems(groupPath, true, result)
        end
        return result
    end)
    if ok and items and #items > 0 then
        for _, tsmStr in ipairs(items) do
            local baseID = tsmStr:match("^i:(%d+)")
            if baseID then set[baseID] = true end
            set[tsmStr] = true
        end
    end

    -- Method 2: Read items DB directly (fallback / supplement)
    if not next(set) then
        local profile = ns.TSM:GetSelectedProfile()
        local itemsDB = profile and ns.TSM:GetItemsDB(profile)
        if itemsDB then
            for tsmStr, itemGroupPath in pairs(itemsDB) do
                if type(itemGroupPath) == "string" then
                    if itemGroupPath == groupPath
                        or itemGroupPath:find(groupPath .. "`", 1, true) == 1 then
                        local baseID = tsmStr:match("^i:(%d+)")
                        if baseID then set[baseID] = true end
                        set[tsmStr] = true
                    end
                end
            end
        end
    end

    return next(set) and set or nil
end

-- Build lookup table from Auctionator shopping list
local function GetAuctionatorListItems(listName)
    if not listName or listName == "" then return nil end
    if type(Auctionator) ~= "table" or type(Auctionator.API) ~= "table"
        or type(Auctionator.API.v1) ~= "table" then
        return nil
    end

    local ok, items = pcall(Auctionator.API.v1.GetShoppingListItems, "FlipQueue", listName)
    if ok and items and #items > 0 then
        local set = {}
        for _, searchStr in ipairs(items) do
            -- Extract item name from search string (before first ';')
            local name = searchStr:match("^([^;]+)") or searchStr
            set[name:lower()] = true
        end
        return set
    end
    return nil
end

function Export:ApplyFilter(itemDataList)
    if filterMode == "everything" then return itemDataList end

    local filtered = {}

    if filterMode == "tsmgroup" then
        local groupItems = GetTSMGroupItems(filterValue)
        if not groupItems then return itemDataList end -- fallback if group lookup fails

        for _, data in ipairs(itemDataList) do
            local idStr = tostring(data.itemID)
            local tsmStr = ns.TSM and ns.TSM:ItemKeyToTSMString(
                ns:MakeItemKey(data.itemID, data.bonusIDs, data.modifiers))
            if groupItems[idStr] or (tsmStr and groupItems[tsmStr]) then
                table.insert(filtered, data)
            end
        end

    elseif filterMode == "auctionator" then
        local listItems = GetAuctionatorListItems(filterValue)
        if not listItems then return itemDataList end

        for _, data in ipairs(itemDataList) do
            local name = (data.itemName or ""):lower()
            if listItems[name] then
                table.insert(filtered, data)
            end
        end
    end

    return filtered
end

--------------------------
-- AAA JSON Export
--------------------------

function Export:ExportAAA(itemDataList, discount, priceSource)
    discount = discount or aaaDiscount
    priceSource = priceSource or aaaPriceSource

    local items = {}    -- itemID -> price in gold
    local pets = {}     -- speciesID -> price in gold

    for _, data in ipairs(itemDataList) do
        local idStr = tostring(data.itemID)

        -- Skip pets for items block, handle separately
        local speciesID = idStr:match("^pet:(%d+)$")

        -- Skip items with bonus IDs (AAA uses base item IDs only)
        if not speciesID and (data.bonusIDs and data.bonusIDs ~= "") then
            -- skip — AAA doesn't support bonus ID variants
        else
            -- Get TSM price
            local fqKey = ns:MakeItemKey(data.itemID, data.bonusIDs or "", data.modifiers or "")
            local copper = ns.TSM and ns.TSM:GetPrice(fqKey, priceSource)

            if copper and copper > 0 then
                local goldPrice = (copper / 10000) * ((100 - discount) / 100)
                goldPrice = math.floor(goldPrice * 100 + 0.5) / 100 -- round to 2 decimals

                if speciesID then
                    pets[speciesID] = goldPrice
                else
                    local numID = tostring(tonumber(idStr))
                    if numID then
                        items[numID] = goldPrice
                    end
                end
            end
        end
    end

    -- Format as JSON
    local function formatJSON(tbl)
        local parts = {}
        -- Sort keys for consistent output
        local keys = {}
        for k in pairs(tbl) do table.insert(keys, k) end
        table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)

        for _, k in ipairs(keys) do
            table.insert(parts, string.format('  "%s": %s', k, tostring(tbl[k])))
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, ",\n") .. "\n}"
    end

    return {
        items = formatJSON(items),
        pets = formatJSON(pets),
        itemCount = 0, -- will be set below
        petCount = 0,
    }, function()
        local ic, pc = 0, 0
        for _ in pairs(items) do ic = ic + 1 end
        for _ in pairs(pets) do pc = pc + 1 end
        return ic, pc
    end
end

--------------------------
-- Export UI Frame
--------------------------

local exportFrame = CreateFrame("Frame", "FlipQueueExportFrame", UIParent, "BackdropTemplate")
exportFrame:SetSize(600, 400)
exportFrame:SetPoint("CENTER")
exportFrame:SetMovable(true)
exportFrame:EnableMouse(true)
exportFrame:RegisterForDrag("LeftButton")
exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
exportFrame:SetFrameStrata("DIALOG")
exportFrame:SetClampedToScreen(true)
exportFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4},
})
exportFrame:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
exportFrame:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)

-- Title bar
local titleBar = CreateFrame("Frame", nil, exportFrame)
titleBar:SetHeight(28)
titleBar:SetPoint("TOPLEFT", 4, -4)
titleBar:SetPoint("TOPRIGHT", -4, -4)
local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
titleBg:SetAllPoints()
titleBg:SetColorTexture(0.12, 0.12, 0.18, 1)

local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("LEFT", 8, 0)
titleText:SetText(ns.COLORS.YELLOW .. "FlipQueue Export" .. ns.COLORS.RESET)

local closeBtn = CreateFrame("Button", nil, titleBar)
closeBtn:SetSize(18, 18)
closeBtn:SetPoint("RIGHT", -4, 0)
closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
closeBtn:GetHighlightTexture():SetAlpha(0.3)
closeBtn:SetScript("OnClick", function() exportFrame:Hide() end)

-- Info label
local infoLabel = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
infoLabel:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 8, -6)
infoLabel:SetTextColor(0.7, 0.7, 0.7)
exportFrame.infoLabel = infoLabel

-- Scroll frame + edit box for CSV output
local scrollFrame = CreateFrame("ScrollFrame", "FlipQueueExportScrollFrame", exportFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 4, -24)
scrollFrame:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", -26, 40)

local editBox = CreateFrame("EditBox", "FlipQueueExportEditBox", scrollFrame)
editBox:SetMultiLine(true)
editBox:SetAutoFocus(false)
editBox:SetFontObject("ChatFontNormal")
editBox:SetWidth(scrollFrame:GetWidth())
editBox:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
scrollFrame:SetScrollChild(editBox)

-- Button bar at bottom
local function CreateExportBtn(label, parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(24)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetWidth(btn.text:GetStringWidth() + 20)
    btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.3, 1) end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.15, 0.2, 1) end)
    return btn
end

local function ShowExportResult(csvText, count, source)
    editBox:SetText(csvText)
    editBox:SetWidth(scrollFrame:GetWidth())
    exportFrame.infoLabel:SetText(string.format(
        "%s%d|r items exported from %s — press Ctrl+A then Ctrl+C to copy",
        ns.COLORS.GREEN, count, source))
    exportFrame:Show()
    editBox:SetFocus(true)
    editBox:HighlightText()
end

local bagsBtn = CreateExportBtn("Bags", exportFrame)
bagsBtn:SetPoint("BOTTOMLEFT", exportFrame, "BOTTOMLEFT", 8, 8)
bagsBtn:SetScript("OnClick", function()
    local csv, count = Export:ExportBags()
    ShowExportResult(csv, count, "bags")
end)

local bankBtn = CreateExportBtn("Bank", exportFrame)
bankBtn:SetPoint("LEFT", bagsBtn, "RIGHT", 4, 0)
bankBtn:SetScript("OnClick", function()
    local csv, count = Export:ExportBank()
    ShowExportResult(csv, count, "bank")
end)

local warbankBtn = CreateExportBtn("Warbank", exportFrame)
warbankBtn:SetPoint("LEFT", bankBtn, "RIGHT", 4, 0)
warbankBtn:SetScript("OnClick", function()
    local csv, count = Export:ExportWarbank()
    ShowExportResult(csv, count, "warbank")
end)

local allBtn = CreateExportBtn("All", exportFrame)
allBtn:SetPoint("LEFT", warbankBtn, "RIGHT", 4, 0)
allBtn:SetScript("OnClick", function()
    local csv, count = Export:ExportAll()
    ShowExportResult(csv, count, "all containers")
end)

local closeBottomBtn = CreateExportBtn("Close", exportFrame)
closeBottomBtn:SetPoint("BOTTOMRIGHT", exportFrame, "BOTTOMRIGHT", -8, 8)
closeBottomBtn:SetScript("OnClick", function() exportFrame:Hide() end)

exportFrame:Hide()

--------------------------
-- Public API
--------------------------

function Export:ShowExportFrame(mode)
    mode = mode or "bags"
    local csv, count
    if mode == "bank" then
        csv, count = self:ExportBank()
        ShowExportResult(csv, count, "bank")
    elseif mode == "warbank" then
        csv, count = self:ExportWarbank()
        ShowExportResult(csv, count, "warbank")
    elseif mode == "all" then
        csv, count = self:ExportAll()
        ShowExportResult(csv, count, "all containers")
    else
        csv, count = self:ExportBags()
        ShowExportResult(csv, count, "bags")
    end
end
