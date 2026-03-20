-- UI/InventoryPage.lua
-- Full inventory view: item list across all chars, status badges, DNT context menus
local addonName, ns = ...

local UI = ns.UI

local BOUND_TYPES = {
    [1] = true, [4] = true, [7] = true, [8] = true, [9] = true,
}

-- Determine item status: Queued, Posted, DNT, or Untracked
local function GetItemStatus(key, itemData)
    local LookupItemInfo = UI._LookupItemInfo

    -- Check DNT first
    if ns:IsDoNotTrack(itemData.itemID) then
        return "DNT", ns.COLORS.RED .. "DNT" .. "|r"
    end

    -- Check imports (pending items)
    local itemName = (itemData.name or ""):lower()
    for _, qItem in pairs(ns.db.imports.fpScanner or {}) do
        if qItem.status == "pending" then
            if qItem.itemKey == key then
                return "Queued", ns.COLORS.GREEN .. "Queued" .. "|r", qItem.targetRealm
            end
            if itemName ~= "" and qItem.name and qItem.name:lower() == itemName then
                return "Queued", ns.COLORS.GREEN .. "Queued" .. "|r", qItem.targetRealm
            end
        end
    end

    -- Check log (posted items)
    for _, entry in ipairs(ns.db.log) do
        if entry.itemKey == key then
            return "Posted", ns.COLORS.YELLOW .. "Posted" .. "|r"
        end
        if itemName ~= "" and entry.name and entry.name:lower() == itemName then
            return "Posted", ns.COLORS.YELLOW .. "Posted" .. "|r"
        end
    end

    return "Untracked", ns.COLORS.GRAY .. "Untracked" .. "|r"
end

local function BuildFullInventoryData()
    if not ns.db then return {} end
    local LookupItemInfo = UI._LookupItemInfo
    local QualityColorName = UI._QualityColorName
    local CLASS_COLORS = UI._CLASS_COLORS

    local data = {}

    -- Process each character's inventory
    for charKey, charData in pairs(ns.db.characters) do
        if charData.inventory and charData.inventory.items then
            local charName = charKey:match("^(.-)%-") or charKey
            local classColor = CLASS_COLORS[charData.class] or "888888"
            local coloredOwner = "|cff" .. classColor .. charName .. "|r"

            for key, itemData in pairs(charData.inventory.items) do
                -- Filter out bound/untradeable
                if not BOUND_TYPES[itemData.bindType or 0] and not itemData.isBound then
                    local _, invQuality, invResolvedID = LookupItemInfo(itemData.itemID, key, itemData.name)
                    local invDisplayName = itemData.name or "Unknown"
                    if invQuality then
                        invDisplayName = QualityColorName(invDisplayName, invQuality)
                    end

                    local statusKey, statusStr, targetRealm = GetItemStatus(key, itemData)

                    -- Build location string
                    local locParts = {}
                    if itemData.locations then
                        for loc, qty in pairs(itemData.locations) do
                            table.insert(locParts, loc)
                        end
                    end

                    table.insert(data, {
                        name        = invDisplayName,
                        qty         = itemData.quantity,
                        owner       = coloredOwner,
                        location    = table.concat(locParts, ", "),
                        status      = statusStr,
                        targetRealm = targetRealm or "",
                        _icon       = itemData.icon,
                        _tooltipItemID = invResolvedID,
                        _itemKey    = key,
                        _itemID     = itemData.itemID,
                        _itemName   = itemData.name,
                        _quantity   = itemData.quantity,
                        _statusKey  = statusKey,
                        _sortStatus = statusKey == "Queued" and 1 or statusKey == "Posted" and 2
                            or statusKey == "Untracked" and 3 or 4,
                        _charKey    = charKey,
                    })
                end
            end
        end
    end

    -- Warbank items
    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            if not BOUND_TYPES[itemData.bindType or 0] and not itemData.isBound then
                local _, wbQuality, wbResolvedID = LookupItemInfo(itemData.itemID, key, itemData.name)
                local wbDisplayName = itemData.name or "Unknown"
                if wbQuality then
                    wbDisplayName = QualityColorName(wbDisplayName, wbQuality)
                end

                local statusKey, statusStr, targetRealm = GetItemStatus(key, itemData)

                table.insert(data, {
                    name        = wbDisplayName,
                    qty         = itemData.quantity,
                    owner       = ns.COLORS.YELLOW .. "Warbank" .. "|r",
                    location    = "warbank",
                    status      = statusStr,
                    targetRealm = targetRealm or "",
                    _icon       = itemData.icon,
                    _tooltipItemID = wbResolvedID,
                    _itemKey    = key,
                    _itemID     = itemData.itemID,
                    _itemName   = itemData.name,
                    _quantity   = itemData.quantity,
                    _statusKey  = statusKey,
                    _sortStatus = statusKey == "Queued" and 1 or statusKey == "Posted" and 2
                        or statusKey == "Untracked" and 3 or 4,
                    _charKey    = "Warbank",
                })
            end
        end
    end

    -- Guild bank items
    if ns.db.guilds then
        for guildName, gbData in pairs(ns.db.guilds) do
            if gbData.items then
                for key, itemData in pairs(gbData.items) do
                    local _, gbQuality, gbResolvedID = LookupItemInfo(itemData.itemID, key, itemData.name)
                    local gbDisplayName = itemData.name or "Unknown"
                    if gbQuality then
                        gbDisplayName = QualityColorName(gbDisplayName, gbQuality)
                    end

                    local statusKey, statusStr, targetRealm = GetItemStatus(key, itemData)

                    table.insert(data, {
                        name        = gbDisplayName,
                        qty         = itemData.quantity,
                        owner       = ns.COLORS.ORANGE .. guildName .. "|r",
                        location    = "guild bank",
                        status      = statusStr,
                        targetRealm = targetRealm or "",
                        _icon       = itemData.icon,
                        _tooltipItemID = gbResolvedID,
                        _itemKey    = key,
                        _itemID     = itemData.itemID,
                        _itemName   = itemData.name,
                        _quantity   = itemData.quantity,
                        _statusKey  = statusKey,
                        _sortStatus = statusKey == "Queued" and 1 or statusKey == "Posted" and 2
                            or statusKey == "Untracked" and 3 or 4,
                        _charKey    = "Guild:" .. guildName,
                    })
                end
            end
        end
    end

    return data
end

function UI:RefreshInventoryPage()
    local mainFrame = UI.mainFrame
    mainFrame.pageTitle:SetText("Inventory")
    UI._LayoutActionBtns(mainFrame.actionBtns.dnt)
    UI._ShowTable(self.inventoryTable)

    local data = BuildFullInventoryData()
    self.inventoryTable:SetRowClickHandler(function(rowData, button)
        if button == "RightButton" then
            local statusKey = rowData._statusKey
            if statusKey == "Untracked" then
                if IsShiftKeyDown() then
                    local added = ns.Import:Save({{
                        itemKey  = rowData._itemKey,
                        itemID   = rowData._itemID or "",
                        name     = rowData._itemName or "Unknown",
                        quantity = rowData._quantity or 1,
                    }})
                    if added > 0 then
                        ns:Print(ns.COLORS.GREEN .. "Added to queue:|r " .. (rowData._itemName or rowData.name))
                    else
                        ns:Print(ns.COLORS.GRAY .. "Already in queue:|r " .. (rowData._itemName or rowData.name))
                    end
                else
                    ns:AddDoNotTrack(rowData._itemID, rowData._itemName)
                    ns:Print("Do not track: " .. rowData.name)
                end
            elseif statusKey == "DNT" then
                ns:RemoveDoNotTrack(tostring(rowData._itemID))
                ns:Print("Removed from Do Not Track: " .. (rowData._itemName or rowData.name))
            elseif statusKey == "Queued" then
                if IsShiftKeyDown() then
                    for importKey, qItem in pairs(ns.db.imports.fpScanner or {}) do
                        if ns:ItemsMatch(qItem.itemKey, qItem.name, {itemKey = rowData._itemKey, itemID = tostring(rowData._itemID), name = rowData._itemName}) then
                            ns:ImportRemove("fpScanner", importKey)
                            ns:Print(ns.COLORS.RED .. "Removed from queue:|r " .. (rowData._itemName or rowData.name))
                            break
                        end
                    end
                end
            end
            self:Refresh()
        end
    end)
    self.inventoryTable:SetData(data)

    -- Count by status
    local statusCounts = {Queued = 0, Posted = 0, Untracked = 0, DNT = 0}
    for _, row in ipairs(data) do
        statusCounts[row._statusKey] = (statusCounts[row._statusKey] or 0) + 1
    end
    local statusParts = {#data .. " tradeable items"}
    if statusCounts.Queued > 0 then table.insert(statusParts, ns.COLORS.GREEN .. statusCounts.Queued .. " queued|r") end
    if statusCounts.Posted > 0 then table.insert(statusParts, ns.COLORS.YELLOW .. statusCounts.Posted .. " posted|r") end
    if statusCounts.Untracked > 0 then table.insert(statusParts, ns.COLORS.GRAY .. statusCounts.Untracked .. " untracked|r") end
    if statusCounts.DNT > 0 then table.insert(statusParts, ns.COLORS.RED .. statusCounts.DNT .. " DNT|r") end
    mainFrame.statusText:SetText(table.concat(statusParts, "  |  "))
end
