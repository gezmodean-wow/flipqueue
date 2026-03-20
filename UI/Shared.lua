-- UI/Shared.lua
-- Shared UI utility functions used by multiple page files
local addonName, ns = ...

local UI = ns.UI

-- ==========================================
-- ITEM QUALITY COLORS
-- ==========================================

local QUALITY_COLORS = {
    Poor      = "9d9d9d",
    Common    = "ffffff",
    Uncommon  = "1eff00",
    Rare      = "0070dd",
    Epic      = "a335ee",
    Legendary = "ff8000",
    Artifact  = "e6cc80",
    Heirloom  = "00ccff",
}

-- WoW Enum.ItemQuality numeric -> color
local QUALITY_NUM_COLORS = {
    [0] = "9d9d9d", -- Poor
    [1] = "ffffff", -- Common
    [2] = "1eff00", -- Uncommon
    [3] = "0070dd", -- Rare
    [4] = "a335ee", -- Epic
    [5] = "ff8000", -- Legendary
    [6] = "e6cc80", -- Artifact
    [7] = "00ccff", -- Heirloom
}

-- WoW class colors for display
local CLASS_COLORS = {
    WARRIOR     = "c79c6e", PALADIN     = "f58cba", HUNTER      = "abd473",
    ROGUE       = "fff569", PRIEST      = "ffffff", DEATHKNIGHT = "c41f3b",
    SHAMAN      = "0070de", MAGE        = "69ccf0", WARLOCK     = "9482c9",
    MONK        = "00ff96", DRUID       = "ff7d0a", DEMONHUNTER = "a330c9",
    EVOKER      = "33937f",
}

-- ==========================================
-- UTILITY FUNCTIONS
-- ==========================================

-- Colorize a name by quality (string name like "Rare" or numeric 3)
local function QualityColorName(name, quality)
    local color
    if type(quality) == "number" then
        color = QUALITY_NUM_COLORS[quality]
    elseif type(quality) == "string" and quality ~= "" then
        color = QUALITY_COLORS[quality]
    end
    if color then
        return "|cff" .. color .. name .. "|r"
    end
    return name
end

-- Look up icon, quality, and resolved numeric ID for an item
-- Returns: icon, quality, resolvedNumericID
local function LookupItemInfo(itemID, itemKey, itemName)
    local icon, quality, resolvedID

    -- Try WoW API with numeric ID
    local numID = tonumber(itemID)
    if numID and numID > 0 then
        resolvedID = numID
        local ok1, _, _, _, _, iconTexture = pcall(C_Item.GetItemInfoInstant, numID)
        if ok1 and iconTexture then icon = iconTexture end
        local ok2, _, _, itemQuality = pcall(C_Item.GetItemInfo, numID)
        if ok2 and itemQuality then quality = itemQuality end
    end

    -- If no numeric ID, try resolving by item name via WoW API
    if not resolvedID and itemName and itemName ~= "" then
        local ok, nameID = pcall(function()
            if C_Item.GetItemIDForItemInfo then
                return C_Item.GetItemIDForItemInfo(itemName)
            end
            return nil
        end)
        if ok and nameID and nameID > 0 then
            resolvedID = nameID
            if not icon then
                local ok3, _, _, _, _, iconTexture = pcall(C_Item.GetItemInfoInstant, nameID)
                if ok3 and iconTexture then icon = iconTexture end
            end
            if not quality then
                local ok4, _, _, itemQuality = pcall(C_Item.GetItemInfo, nameID)
                if ok4 and itemQuality then quality = itemQuality end
            end
        end
    end

    -- Fall back to scanned inventory data for icon
    if not icon and ns.db then
        local searchKey = itemKey or ""
        local searchName = itemName and itemName:lower() or ""

        -- Search character inventories
        for _, charData in pairs(ns.db.characters) do
            if charData.inventory and charData.inventory.items then
                for key, data in pairs(charData.inventory.items) do
                    if key == searchKey or (data.name and data.name:lower() == searchName) then
                        if data.icon then icon = data.icon end
                        if not resolvedID then
                            local invNumID = tonumber(data.itemID)
                            if invNumID and invNumID > 0 then resolvedID = invNumID end
                        end
                        break
                    end
                end
                if icon then break end
            end
        end

        -- Search warbank
        if not icon and ns.db.warbank and ns.db.warbank.items then
            for key, data in pairs(ns.db.warbank.items) do
                if key == searchKey or (data.name and data.name:lower() == searchName) then
                    if data.icon then icon = data.icon end
                    if not resolvedID then
                        local wbNumID = tonumber(data.itemID)
                        if wbNumID and wbNumID > 0 then resolvedID = wbNumID end
                    end
                    break
                end
            end
        end
    end

    return icon, quality, resolvedID
end

-- Format gold value for display
local function FormatGoldValue(totalGold)
    if totalGold <= 0 then return "" end
    if totalGold >= 1000 then
        return string.format("%.1fk gold", totalGold / 1000)
    end
    return tostring(totalGold) .. " gold"
end

-- ==========================================
-- CURRENT CHARACTER TASKS
-- ==========================================

-- Build "Check AH" / "Check Mail" / expiring task list for current character
local function BuildCurrentCharTasks()
    if not ns.db then return {} end
    local tasks = {}
    local myCharKey = ns:GetCharKey()

    -- Auction summary for current character
    local auctionsByChar = ns.Tracker and ns.Tracker.GetAuctionSummaryByCharacter
        and ns.Tracker:GetAuctionSummaryByCharacter() or {}
    local myAuctions = auctionsByChar[myCharKey]

    -- Check AH: expired auctions to collect
    if myAuctions and myAuctions.done > 0 then
        table.insert(tasks, {
            icon   = "Interface\\Icons\\INV_Misc_Coin_02",
            text   = ns.COLORS.GREEN .. "Check AH:|r " .. myAuctions.done .. " auction(s) expired — collect at AH",
            sort   = 1,
        })
    end

    -- Check Mail: expired items waiting to be collected
    local expiredInMail = 0
    for _, entry in ipairs(ns.db.log) do
        if entry.charKey == myCharKey and entry.auctionStatus == "expired" then
            expiredInMail = expiredInMail + 1
        end
    end
    if expiredInMail > 0 then
        table.insert(tasks, {
            icon   = "Interface\\Icons\\INV_Letter_15",
            text   = ns.COLORS.YELLOW .. "Check Mail:|r " .. expiredInMail .. " expired auction(s) to collect",
            sort   = 2,
        })
    end

    -- Expiring soon on this character
    if myAuctions and myAuctions.active > 0 and myAuctions.soonest then
        local alertMinutes = ns.db.settings.expiryAlertMinutes or 15
        if myAuctions.soonest < (alertMinutes * 60) then
            local h = math.floor(myAuctions.soonest / 3600)
            local m = math.floor((myAuctions.soonest % 3600) / 60)
            local countdown = h > 0 and (h .. "h " .. m .. "m") or (m .. "m")
            table.insert(tasks, {
                icon   = "Interface\\Icons\\Spell_Holy_BorrowedTime",
                text   = ns.COLORS.ORANGE .. "Expiring:|r " .. myAuctions.active .. " auction(s) — soonest in " .. countdown,
                sort   = 3,
            })
        end
    end

    -- Active auctions info (not urgent, just informational)
    if myAuctions and myAuctions.active > 0 and #tasks == 0 then
        table.insert(tasks, {
            icon   = "Interface\\Icons\\INV_Misc_Coin_17",
            text   = ns.COLORS.GRAY .. myAuctions.active .. " active auction(s) on this character|r",
            sort   = 10,
        })
    end

    -- Deposit to warbank: items on this character that another character needs
    local todoList = ns.TodoList and ns.TodoList:GetCurrentList()
    if todoList and todoList.tasks then
        local depositCount = 0
        for _, item in ipairs(todoList.tasks) do
            if item.source == "unavailable" and item.depositFrom == myCharKey then
                depositCount = depositCount + 1
            end
        end
        if depositCount > 0 then
            table.insert(tasks, {
                icon   = "Interface\\Icons\\INV_Misc_Bag_10",
                text   = ns.COLORS.CYAN .. "Deposit:|r " .. depositCount .. " item(s) to warbank for other characters",
                sort   = 0,  -- highest priority
            })
        end
    end

    table.sort(tasks, function(a, b) return a.sort < b.sort end)
    return tasks
end

-- ==========================================
-- NEXT STEPS (other characters)
-- ==========================================

local function BuildNextStepsData()
    if not ns.db then return {} end

    local data = {}
    local myCharKey = ns:GetCharKey()

    -- 1) Build "Log in" entries from the to-do list (primary source)
    local todoList = ns.TodoList and ns.TodoList:GetCurrentList()
    local depositsByChar = {}  -- charKey -> { count, items }
    local receiverOf = {}      -- receiverCharKey -> { depositorCharKey = true }

    if todoList and todoList.tasks then
        -- Collect deposit dependencies
        for _, item in ipairs(todoList.tasks) do
            if item.source == "unavailable" and item.depositFrom then
                if not depositsByChar[item.depositFrom] then
                    depositsByChar[item.depositFrom] = { count = 0, gold = 0 }
                end
                depositsByChar[item.depositFrom].count = depositsByChar[item.depositFrom].count + 1
                depositsByChar[item.depositFrom].gold = depositsByChar[item.depositFrom].gold
                    + (ns:ParseGoldValue(item.expectedPrice or "") or 0)

                -- Track dependency: receiver depends on depositor
                if item.assignedChar and item.depositFrom ~= item.assignedChar then
                    if not receiverOf[item.assignedChar] then
                        receiverOf[item.assignedChar] = {}
                    end
                    receiverOf[item.assignedChar][item.depositFrom] = true
                end
            end
        end

        local sortMode = (UI.GetGenSortMode and UI:GetGenSortMode()) or "profit"
        local displayGroups = ns.TodoList:BuildDisplayGroups(todoList.tasks, sortMode)

        for _, group in ipairs(displayGroups) do
            if group.charKey and group.charKey ~= myCharKey then
                local name = group.charName or "?"
                local realm = group.realm or ""
                local charInv = ns.db.characters and ns.db.characters[group.charKey]
                local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
                local coloredName = "|cff" .. classColor .. name .. "|r"

                -- Check if this character also has deposit tasks
                local depInfo = depositsByChar[group.charKey]
                local detailStr = #group.items .. " items to post"
                if depInfo then
                    detailStr = detailStr .. " + " .. depInfo.count .. " to deposit"
                    depositsByChar[group.charKey] = nil  -- merged, don't create standalone
                end

                table.insert(data, {
                    action    = ns.COLORS.YELLOW .. "Log in" .. "|r",
                    target    = coloredName .. "  (" .. realm .. ")",
                    itemCount = #group.items + (depInfo and depInfo.count or 0),
                    value     = FormatGoldValue(group.totalGold),
                    detail    = detailStr,
                    _sortValue = group.totalGold,
                    _charKey   = group.charKey,
                    _tooltipText = group.charKey,
                    _tooltipExtra = string.format("Log in to %s to post %d items\nEstimated value: %s",
                        group.charKey, #group.items, FormatGoldValue(group.totalGold)),
                })
            elseif not group.charKey then
                -- Unassigned group = "Create char" entry
                local realmName = group.realm ~= "" and group.realm or "unknown realm"
                table.insert(data, {
                    action    = "|cffff6666" .. "Create char" .. "|r",
                    target    = realmName,
                    itemCount = #group.items,
                    value     = FormatGoldValue(group.totalGold),
                    detail    = "",
                    _sortValue = -1,  -- always sort last
                    _tooltipText = realmName,
                    _tooltipExtra = string.format("Create a character on %s\n%d items worth ~%s waiting",
                        realmName, #group.items, FormatGoldValue(group.totalGold)),
                })
            end
        end
    end

    -- 2) Standalone deposit entries (depositors not already merged with "Log in")
    for charKey, depInfo in pairs(depositsByChar) do
        if charKey ~= myCharKey then
            local name = charKey:match("^(.-)%-") or charKey
            local realm = charKey:match("%-(.+)$") or ""
            local charInv = ns.db.characters and ns.db.characters[charKey]
            local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
            local coloredName = "|cff" .. classColor .. name .. "|r"

            table.insert(data, {
                action    = ns.COLORS.CYAN .. "Deposit" .. "|r",
                target    = coloredName .. "  (" .. realm .. ")",
                itemCount = depInfo.count,
                value     = FormatGoldValue(depInfo.gold),
                detail    = depInfo.count .. " to warbank",
                _sortValue = depInfo.gold,
                _charKey   = charKey,
                _tooltipText = charKey,
                _tooltipExtra = string.format("Log in to %s to deposit %d item(s) to warbank",
                    charKey, depInfo.count),
            })
        end
    end

    -- 3) Other characters with done (expired) auctions to check
    local auctionsByChar = ns.Tracker and ns.Tracker.GetAuctionSummaryByCharacter
        and ns.Tracker:GetAuctionSummaryByCharacter() or {}

    for charKey, info in pairs(auctionsByChar) do
        if info.done > 0 and charKey ~= myCharKey then
            local name = charKey:match("^(.-)%-") or charKey
            local realm = charKey:match("%-(.+)$") or ""
            local charInv = ns.db.characters[charKey]
            local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
            local coloredName = "|cff" .. classColor .. name .. "|r"

            table.insert(data, {
                action    = ns.COLORS.GREEN .. "Check AH" .. "|r",
                target    = coloredName .. "  (" .. realm .. ")",
                itemCount = info.done,
                value     = FormatGoldValue(info.totalValue or 0),
                detail    = info.done .. " auction(s) done",
                _sortValue = -2,
                _tooltipText = charKey,
                _tooltipExtra = string.format("Log in to %s to collect %d expired auction(s)%s",
                    charKey, info.done,
                    info.active > 0 and ("\n" .. info.active .. " still active") or ""),
            })
        end
    end

    -- 4) Other characters with auctions expiring soon
    local alertMinutes = ns.db.settings.expiryAlertMinutes or 15
    local alertThreshold = alertMinutes * 60
    for charKey, info in pairs(auctionsByChar) do
        if charKey ~= myCharKey and info.active > 0 and info.soonest and info.soonest < alertThreshold then
            if not (info.done > 0) then
                local name = charKey:match("^(.-)%-") or charKey
                local realm = charKey:match("%-(.+)$") or ""
                local charInv = ns.db.characters[charKey]
                local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
                local coloredName = "|cff" .. classColor .. name .. "|r"

                local h = math.floor(info.soonest / 3600)
                local m = math.floor((info.soonest % 3600) / 60)
                local countdown = h > 0 and (h .. "h " .. m .. "m") or (m .. "m")

                table.insert(data, {
                    action    = ns.COLORS.ORANGE .. "Expiring" .. "|r",
                    target    = coloredName .. "  (" .. realm .. ")",
                    itemCount = info.active,
                    value     = FormatGoldValue(info.totalValue or 0),
                    detail    = ns.COLORS.ORANGE .. countdown .. "|r",
                    _sortValue = 0,
                    _tooltipText = charKey,
                    _tooltipExtra = string.format("%d active auction(s)\nSoonest expires in %s",
                        info.active, countdown),
                })
            end
        end
    end

    -- Dependency-aware sort: depositors before their receivers, then by gold value
    table.sort(data, function(a, b)
        local aKey = a._charKey
        local bKey = b._charKey

        -- If B depends on A (A deposits for B), A comes first
        if aKey and bKey and receiverOf[bKey] and receiverOf[bKey][aKey] then
            return true
        end
        if aKey and bKey and receiverOf[aKey] and receiverOf[aKey][bKey] then
            return false
        end

        return (a._sortValue or 0) > (b._sortValue or 0)
    end)

    return data
end

-- ==========================================
-- EXPOSE ON UI TABLE
-- ==========================================

UI._LookupItemInfo = LookupItemInfo
UI._QualityColorName = QualityColorName
UI._CLASS_COLORS = CLASS_COLORS
UI._FormatGoldValue = FormatGoldValue
UI.BuildNextStepsData = BuildNextStepsData
UI.BuildCurrentCharTasks = BuildCurrentCharTasks
