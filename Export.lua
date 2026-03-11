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
    local itemName, _, itemQuality, _, _, _, _, itemStackCount, _, _, _, _, _, bindType =
        C_Item.GetItemInfo(itemLink)

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
    local effectiveILvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(itemLink) or 0
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
        local numSlots = C_Container.GetContainerNumSlots(bagIndex)
        totalSlots = totalSlots + numSlots
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagIndex, slot)
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
