-- UI/InventoryPage.lua
-- Full inventory view: item list across all chars, status badges, DNT context menus
local addonName, ns = ...

local UI = ns.UI

local BOUND_TYPES = {
    [1] = true, [4] = true, [7] = true, [8] = true, [9] = true,
}

-- Determine item status with enhanced model:
-- Assigned (green, 1) — item has active to-do task
-- Posted (yellow, 2) — item in log with active auction → show "AH: realm"
-- Check Mail (orange, 3) — item in log with expired auction
-- Unassigned (dim white, 4) — tracked item with known location but no task
-- Unknown (dim gray, 5) — location cannot be determined
-- Ignored (red, 6) — in DNT list
-- Returns: statusKey, statusStr, targetRealm, postedCharKey
local function GetItemStatus(key, itemData, hasKnownLocation)
    -- Check DNT first
    if ns:IsDoNotTrack(itemData.itemID) then
        return "Ignored", ns.COLORS.RED .. "Ignored" .. "|r", nil, nil
    end

    -- Check to-do list for assigned tasks (replaces imports check)
    local currentList = ns.TodoList and ns.TodoList:GetCurrentList()
    if currentList and currentList.tasks then
        local itemName = (itemData.name or ""):lower()
        for _, task in ipairs(currentList.tasks) do
            if task.status == "pending" then
                local item = task.item or task
                if item.itemKey == key then
                    return "Assigned", ns.COLORS.GREEN .. "Assigned" .. "|r", item.targetRealm, nil
                end
                if itemName ~= "" and item.name and item.name:lower() == itemName then
                    return "Assigned", ns.COLORS.GREEN .. "Assigned" .. "|r", item.targetRealm, nil
                end
            end
        end
    end

    -- Check log for posted/expired items
    local itemName = (itemData.name or ""):lower()
    for _, entry in ipairs(ns.db.log) do
        local matched = entry.itemKey == key
        if not matched and itemName ~= "" and entry.name and entry.name:lower() == itemName then
            matched = true
        end
        if matched then
            if entry.auctionStatus == "active" then
                local ahRealm = entry.targetRealm or ""
                return "Posted", ns.COLORS.YELLOW .. "Posted" .. "|r",
                    ahRealm ~= "" and ("AH: " .. ahRealm) or nil, entry.charKey
            elseif entry.auctionStatus == "expired" then
                local ahRealm = entry.targetRealm or ""
                return "Check Mail", ns.COLORS.ORANGE .. "Check Mail" .. "|r",
                    ahRealm ~= "" and ("Mail: " .. ahRealm) or nil, entry.charKey
            end
        end
    end

    -- Tracked with known location but no task = Unassigned
    if hasKnownLocation then
        return "Unassigned", "|cffbbbbbb" .. "Unassigned" .. "|r", nil, nil
    end

    return "Unknown", ns.COLORS.GRAY .. "Unknown" .. "|r", nil, nil
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
            local acctTag = ns:IsRemoteChar(charKey) and "|cff8866cc[2]|r " or ""
            local coloredOwner = acctTag .. "|cff" .. classColor .. charName .. "|r"

            for key, itemData in pairs(charData.inventory.items) do
                -- Filter out bound/untradeable
                if not BOUND_TYPES[itemData.bindType or 0] and not itemData.isBound then
                    local _, invQuality, invResolvedID = LookupItemInfo(itemData.itemID, key, itemData.name)
                    local invDisplayName = itemData.name or "Unknown"
                    if invQuality then
                        invDisplayName = QualityColorName(invDisplayName, invQuality)
                    end

                    -- Build location string
                    local locParts = {}
                    if itemData.locations then
                        for loc, qty in pairs(itemData.locations) do
                            table.insert(locParts, loc)
                        end
                    end
                    local hasKnownLocation = #locParts > 0

                    local statusKey, statusStr, targetRealm, postedCharKey = GetItemStatus(key, itemData, hasKnownLocation)

                    -- For posted/expired items, override owner and location from the log entry
                    local displayOwner = coloredOwner
                    local displayLocation = table.concat(locParts, ", ")
                    if (statusKey == "Posted" or statusKey == "Check Mail") and postedCharKey then
                        local postedName = postedCharKey:match("^(.-)%-") or postedCharKey
                        local postedCharData = ns.db.characters[postedCharKey]
                        local postedClassColor = postedCharData and CLASS_COLORS[postedCharData.class] or "888888"
                        local postedAcctTag = ns:IsRemoteChar(postedCharKey) and "|cff8866cc[2]|r " or ""
                        displayOwner = postedAcctTag .. "|cff" .. postedClassColor .. postedName .. "|r"
                        displayLocation = statusKey == "Posted" and "Auction House" or "Mailbox"
                    end

                    -- Prefer scanner-captured ilvl (accurate). Fallback to a
                    -- variant-aware GetItemInfo on the full itemString so an
                    -- ilvl 253 ring with bonus IDs renders correctly instead
                    -- of falling back to base ilvl 44.
                    local itemIlvl = itemData.ilvl
                    if (not itemIlvl or itemIlvl == 0) and ns.GetItemLevelFromKey then
                        itemIlvl = ns:GetItemLevelFromKey(key, invResolvedID)
                    end

                    table.insert(data, {
                        name        = invDisplayName,
                        ilvl        = (itemIlvl and itemIlvl > 0) and itemIlvl or "",
                        qty         = itemData.quantity,
                        owner       = displayOwner,
                        location    = displayLocation,
                        status      = statusStr,
                        targetRealm = targetRealm or "",
                        _icon       = itemData.icon,
                        _tooltipItemString = ns.ItemKeyToItemString and ns:ItemKeyToItemString(key) or nil,
                        _tooltipItemID = invResolvedID,
                        _itemKey    = key,
                        _itemID     = itemData.itemID,
                        _itemName   = itemData.name,
                        _quantity   = itemData.quantity,
                        _statusKey  = statusKey,
                        _sortStatus = statusKey == "Assigned" and 1 or statusKey == "Posted" and 2
                            or statusKey == "Check Mail" and 3 or statusKey == "Unassigned" and 4
                            or statusKey == "Unknown" and 5 or 6,
                        _sortIlvl   = itemIlvl or 0,
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

                -- Warbank always has a known location
                local statusKey, statusStr, targetRealm, postedCharKey = GetItemStatus(key, itemData, true)

                -- For posted/expired items, override owner and location from the log entry
                local displayOwner = ns.COLORS.YELLOW .. "Warbank" .. "|r"
                local displayLocation = "warbank"
                if (statusKey == "Posted" or statusKey == "Check Mail") and postedCharKey then
                    local postedName = postedCharKey:match("^(.-)%-") or postedCharKey
                    local postedCharData = ns.db.characters[postedCharKey]
                    local postedClassColor = postedCharData and CLASS_COLORS[postedCharData.class] or "888888"
                    local postedAcctTag = ns:IsRemoteChar(postedCharKey) and "|cff8866cc[2]|r " or ""
                    displayOwner = postedAcctTag .. "|cff" .. postedClassColor .. postedName .. "|r"
                    displayLocation = statusKey == "Posted" and "Auction House" or "Mailbox"
                end

                local wbIlvl = itemData.ilvl
                if (not wbIlvl or wbIlvl == 0) and ns.GetItemLevelFromKey then
                    wbIlvl = ns:GetItemLevelFromKey(key, wbResolvedID)
                end

                table.insert(data, {
                    name        = wbDisplayName,
                    ilvl        = (wbIlvl and wbIlvl > 0) and wbIlvl or "",
                    qty         = itemData.quantity,
                    owner       = displayOwner,
                    location    = displayLocation,
                    status      = statusStr,
                    targetRealm = targetRealm or "",
                    _icon       = itemData.icon,
                    _tooltipItemString = ns.ItemKeyToItemString and ns:ItemKeyToItemString(key) or nil,
                    _tooltipItemID = wbResolvedID,
                    _itemKey    = key,
                    _itemID     = itemData.itemID,
                    _itemName   = itemData.name,
                    _quantity   = itemData.quantity,
                    _statusKey  = statusKey,
                    _sortStatus = statusKey == "Assigned" and 1 or statusKey == "Posted" and 2
                        or statusKey == "Check Mail" and 3 or statusKey == "Unassigned" and 4
                        or statusKey == "Unknown" and 5 or 6,
                    _sortIlvl   = wbIlvl or 0,
                    _charKey    = "Warbank",
                })
            end
        end
    end

    -- Guild bank items — disabled: Blizzard API returns unreliable item data
    -- Re-enable when API is fixed.
    if false and ns.db.guilds then
        for guildName, gbData in pairs(ns.db.guilds) do
            if gbData.items then
                for key, itemData in pairs(gbData.items) do
                    local _, gbQuality, gbResolvedID = LookupItemInfo(itemData.itemID, key, itemData.name)
                    local gbDisplayName = itemData.name or "Unknown"
                    if gbQuality then
                        gbDisplayName = QualityColorName(gbDisplayName, gbQuality)
                    end

                    local statusKey, statusStr, targetRealm, postedCharKey = GetItemStatus(key, itemData, true)

                    -- For posted items, override owner and location from the log entry
                    local displayOwner = ns.COLORS.ORANGE .. guildName .. "|r"
                    local displayLocation = "guild bank"
                    if statusKey == "Posted" and postedCharKey then
                        local postedName = postedCharKey:match("^(.-)%-") or postedCharKey
                        local postedCharData = ns.db.characters[postedCharKey]
                        local postedClassColor = postedCharData and CLASS_COLORS[postedCharData.class] or "888888"
                        local postedAcctTag = ns:IsRemoteChar(postedCharKey) and "|cff8866cc[2]|r " or ""
                        displayOwner = postedAcctTag .. "|cff" .. postedClassColor .. postedName .. "|r"
                        displayLocation = "Auction House"
                    end

                    table.insert(data, {
                        name        = gbDisplayName,
                        qty         = itemData.quantity,
                        owner       = displayOwner,
                        location    = displayLocation,
                        status      = statusStr,
                        targetRealm = targetRealm or "",
                        _icon       = itemData.icon,
                        _tooltipItemString = ns.ItemKeyToItemString and ns:ItemKeyToItemString(key) or nil,
                        _tooltipItemID = gbResolvedID,
                        _itemKey    = key,
                        _itemID     = itemData.itemID,
                        _itemName   = itemData.name,
                        _quantity   = itemData.quantity,
                        _statusKey  = statusKey,
                        _sortStatus = statusKey == "Assigned" and 1 or statusKey == "Posted" and 2
                            or statusKey == "Check Mail" and 3 or statusKey == "Unassigned" and 4
                            or statusKey == "Unknown" and 5 or 6,
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

    -- Find and remove the queue (fpScanner import) entry matching this row.
    -- Returns true when an entry was removed — callers toast on failure so
    -- a miss is never silent (FQ-228).
    local function RemoveFromQueue(rowData)
        for importKey, qItem in pairs(ns.db.imports.fpScanner or {}) do
            if ns:ItemsMatch(qItem.itemKey, qItem.name, {itemKey = rowData._itemKey, itemID = tostring(rowData._itemID), name = rowData._itemName}) then
                ns:ImportRemove("fpScanner", importKey)
                return true
            end
        end
        return false
    end

    self.inventoryTable:SetRowClickHandler(function(rowData, button, _, rowFrame)
        if button == "LeftButton" then
            UI._researchTargetItemKey = rowData._itemKey
            UI._researchTargetItemName = rowData._itemName
            UI.currentPage = "research"
            UI:Refresh()
            return
        end
        if button == "RightButton" then
            local statusKey = rowData._statusKey
            local itemLabel = rowData._itemName or rowData.name
            if statusKey == "Unknown" or statusKey == "Unassigned" or statusKey == "Check Mail" then
                if IsShiftKeyDown() then
                    local added = ns.Import:Save({{
                        itemKey  = rowData._itemKey,
                        itemID   = rowData._itemID or "",
                        name     = rowData._itemName or "Unknown",
                        quantity = rowData._quantity or 1,
                    }})
                    if added > 0 then
                        ns.cw:Toast({ severity = "success", text = "Added to queue: " .. itemLabel })
                    else
                        ns.cw:Toast({ severity = "info", text = "Already in queue: " .. itemLabel })
                    end
                else
                    ns:AddDoNotTrack(rowData._itemID, rowData._itemName)
                    ns:Print("Do not track: " .. rowData.name)
                end
                self:Refresh()
            elseif statusKey == "Ignored" then
                ns:RemoveDoNotTrack(tostring(rowData._itemID))
                ns:Print("Removed from Do Not Track: " .. itemLabel)
                self:Refresh()
            elseif statusKey == "Assigned" then
                if IsShiftKeyDown() then
                    -- Quick path: shift skips the menu and removes outright.
                    if RemoveFromQueue(rowData) then
                        ns.cw:Toast({ severity = "info", text = "Removed from queue: " .. itemLabel })
                    else
                        ns.cw:Toast({ severity = "warning", text = "No matching queue entry found for " .. itemLabel })
                    end
                    self:Refresh()
                else
                    -- An assigned item supports two different actions, so a
                    -- plain right-click asks instead of guessing (FQ-228 —
                    -- previously this silently did nothing).
                    MenuUtil.CreateContextMenu(rowFrame or UIParent, function(_, rootDescription)
                        rootDescription:CreateTitle(itemLabel)
                        rootDescription:CreateButton("Remove from queue", function()
                            if RemoveFromQueue(rowData) then
                                ns.cw:Toast({ severity = "info", text = "Removed from queue: " .. itemLabel })
                            else
                                ns.cw:Toast({ severity = "warning", text = "No matching queue entry found for " .. itemLabel })
                            end
                            UI:Refresh()
                        end)
                        rootDescription:CreateButton("Add to Do Not Track", function()
                            ns:AddDoNotTrack(rowData._itemID, rowData._itemName)
                            -- Also drop the queue entry: DNT'd items generate
                            -- no tasks, so a leftover import would sit dead.
                            RemoveFromQueue(rowData)
                            ns.cw:Toast({ severity = "success", text = "Do not track: " .. itemLabel })
                            UI:Refresh()
                        end)
                    end)
                end
            elseif statusKey == "Posted" then
                -- Nothing actionable while the auction is live; say so
                -- instead of eating the click (FQ-228).
                ns.cw:Toast({ severity = "warning", text = itemLabel .. " is posted on the AH — collect or cancel the auction first." })
            end
        end
    end)
    self.inventoryTable:SetData(data)

    -- Count by status
    local statusCounts = {}
    for _, row in ipairs(data) do
        statusCounts[row._statusKey] = (statusCounts[row._statusKey] or 0) + 1
    end
    local statusParts = {#data .. " tradeable items"}
    if (statusCounts.Assigned or 0) > 0 then table.insert(statusParts, ns.COLORS.GREEN .. statusCounts.Assigned .. " assigned|r") end
    if (statusCounts.Posted or 0) > 0 then table.insert(statusParts, ns.COLORS.YELLOW .. statusCounts.Posted .. " posted|r") end
    if (statusCounts["Check Mail"] or 0) > 0 then table.insert(statusParts, ns.COLORS.ORANGE .. statusCounts["Check Mail"] .. " check mail|r") end
    if (statusCounts.Unassigned or 0) > 0 then table.insert(statusParts, "|cffbbbbbb" .. statusCounts.Unassigned .. " unassigned|r") end
    if (statusCounts.Unknown or 0) > 0 then table.insert(statusParts, ns.COLORS.GRAY .. statusCounts.Unknown .. " unknown|r") end
    if (statusCounts.Ignored or 0) > 0 then table.insert(statusParts, ns.COLORS.RED .. statusCounts.Ignored .. " ignored|r") end
    mainFrame.statusText:SetText(table.concat(statusParts, "  |  "))
end
