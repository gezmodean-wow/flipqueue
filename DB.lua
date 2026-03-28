-- DB.lua
-- Saved variables initialization, data cleanup, and utility functions
local addonName, ns = ...

--------------------------
-- Saved Variables Init
--------------------------

function ns:InitDB()
    if not FlipQueueDB then
        FlipQueueDB = {}
    end
    local db = FlipQueueDB

    -- Run schema migrations before anything reads the data
    ns._RunMigrations(db)

    -- Ensure new structure exists (for fresh installs and post-migration)
    db.characters   = db.characters or {}
    db.warbank      = db.warbank or {}
    db.guilds       = db.guilds or {}
    db.imports      = db.imports or { fpScanner = {}, fpCrossRealm = {}, tsm = {} }
    db.imports.fpScanner    = db.imports.fpScanner or {}
    db.imports.fpCrossRealm = db.imports.fpCrossRealm or {}
    db.imports.tsm          = db.imports.tsm or {}
    db.todoLists    = db.todoLists or {}
    db.todoLists.upcoming = db.todoLists.upcoming or {}
    db.log          = db.log or {}
    db.doNotTrack   = db.doNotTrack or {}
    db.accounts     = db.accounts or { external = {} }
    db.accounts.external = db.accounts.external or {}
    db.settings     = db.settings or {
        autoScan         = true,
        autoPullBank     = false,
        autoDepositWarbank = false,
        autoDepositAll = false,
        showLoginMessage = true,
        autoWithdrawGold = false,
        maxWithdrawGold = 0, -- 0 = no limit, otherwise max gold per withdrawal
    }
    db.settings.collapsed = db.settings.collapsed or {}
    db.settings.sortMode  = db.settings.sortMode or "realm"
    -- Migrate old expiryAlertHours to expiryAlertMinutes
    if db.settings.expiryAlertHours and not db.settings.expiryAlertMinutes then
        db.settings.expiryAlertMinutes = db.settings.expiryAlertHours * 60
        db.settings.expiryAlertHours = nil
    end
    db.settings.expiryAlertMinutes = db.settings.expiryAlertMinutes or 15
    if db.settings.showMini == nil then db.settings.showMini = true end
    if db.settings.hideMiniInCombat == nil then db.settings.hideMiniInCombat = true end
    db.settings.pullBatchSize = db.settings.pullBatchSize or 5
    -- TSM integration defaults
    if db.settings.tsmEnabled == nil then db.settings.tsmEnabled = false end
    db.settings.tsmProfile         = db.settings.tsmProfile or ""
    db.settings.tsmMinPriceSource  = db.settings.tsmMinPriceSource or "70% DBMarket"
    db.settings.tsmPriceSource     = db.settings.tsmPriceSource or "DBMinBuyout"
    if db.settings.tsmShowColumns == nil then db.settings.tsmShowColumns = false end
    if db.settings.tsmAutoUpdatePrice == nil then db.settings.tsmAutoUpdatePrice = false end
    db.settings.tsmPriceMaxAge     = db.settings.tsmPriceMaxAge or 3600
    -- Transform page defaults
    db.settings.transformPriceSource  = db.settings.transformPriceSource or "DBMarket"
    db.settings.transformDiscount     = db.settings.transformDiscount or 90
    db.settings.defaultSellQty     = db.settings.defaultSellQty or 1
    db.settings.sellQtyMode        = db.settings.sellQtyMode or "tsm"  -- "fixed" or "tsm"
    -- Character ordering for manual sort
    db.settings.characterOrder = db.settings.characterOrder or {}
    -- Generator settings (persisted across sessions)
    db.settings.genAllocationOrder = db.settings.genAllocationOrder or {"gold", "noCompetition", "population"}
    db.settings.genSortMode = db.settings.genSortMode or "profit"
    -- Import auto-generate and auto-import (off by default)
    if db.settings.importAutoGenerate == nil then db.settings.importAutoGenerate = false end
    if db.settings.importAutoImport == nil then db.settings.importAutoImport = false end
    -- TSM rejection handling (on by default when TSM is enabled)
    if db.settings.tsmAutoSkipRejected == nil then db.settings.tsmAutoSkipRejected = true end
    -- Debug messages (off by default)
    if db.settings.debugMessages == nil then db.settings.debugMessages = false end
    -- Bank tab selection
    if not db.settings.pullTabs then
        db.settings.pullTabs = { mode = "all" }
    end
    -- Generator filter persistence
    db.settings.genFilterMode = db.settings.genFilterMode or "all"
    db.settings.genFilterValue = db.settings.genFilterValue or ""
    -- Generator wizard settings (cross-realm / inventory track)
    db.settings.genWizardTrack = db.settings.genWizardTrack or nil  -- nil/"inventory"/"crossrealm"
    db.settings.genWizardStep = db.settings.genWizardStep or 0  -- 0=track select, 1/2/3=steps
    db.settings.genBuyAllocationOrder = db.settings.genBuyAllocationOrder or {"profit", "population", "lowInventory"}
    db.settings.genCrossRealmListMode = db.settings.genCrossRealmListMode or "separate"  -- "separate"/"integrated"
    db.settings.genIntegratedSortMode = db.settings.genIntegratedSortMode or "mostProfitable"
    db.settings.genCrossRealmRealmFilter = db.settings.genCrossRealmRealmFilter or {}
    -- TSM character detection dismissed list
    db.settings.dismissedTSMChars = db.settings.dismissedTSMChars or {}
    -- Tutorial (first-time interactive walkthrough)
    if db.settings.tutorialDone == nil then db.settings.tutorialDone = false end

    ns.db = db

    -- Run data cleanup
    ns:CleanupLegacyData()
end

--------------------------
-- Data Cleanup
--------------------------

function ns:CleanupLegacyData()
    local db = ns.db
    if not db then return end

    local cleaned = {}

    -- 1) Clean stale settings fields
    if db.settings.expiryAlertHours ~= nil then
        db.settings.expiryAlertHours = nil
        cleaned.staleSettings = (cleaned.staleSettings or 0) + 1
    end
    if db.settings.collapsed and type(db.settings.collapsed) == "table" then
        local hasOld = false
        for k in pairs(db.settings.collapsed) do
            if type(k) == "string" and (k:find("section_") or k == "true" or k == "false") then
                hasOld = true
                break
            end
        end
        if hasOld then
            wipe(db.settings.collapsed)
            cleaned.staleSettings = (cleaned.staleSettings or 0) + 1
        end
    end

    -- 2) Normalize todo list tasks: add new fields with safe defaults
    if db.todoLists and db.todoLists.active and db.todoLists.active.tasks then
        for _, task in ipairs(db.todoLists.active.tasks) do
            task.attempts = task.attempts or 0
            task.status = task.status or "pending"
            task.quantity = task.quantity or 1
            task.currentStep = task.currentStep or 1
            if task.source == "unavailable" and not task.failReason then
                task.failReason = "Item not in accessible inventory — may need depositing to warbank"
            end
        end
    end

    -- 3) Clean up old log entries: remove "collected" entries older than 30 days
    if db.log then
        local now = time()
        local thirtyDays = 30 * 24 * 3600
        local removedLogs = 0
        for i = #db.log, 1, -1 do
            local entry = db.log[i]
            if entry.auctionStatus == "collected" then
                local entryTime = entry.soldAt or entry.postedAt or 0
                if entryTime > 0 and (now - entryTime) > thirtyDays then
                    table.remove(db.log, i)
                    removedLogs = removedLogs + 1
                end
            end
        end
        if removedLogs > 0 then
            cleaned.oldLogs = removedLogs
        end
    end

    -- 4) Normalize warbank data
    if db.warbank and db.warbank.items then
        for key, itemData in pairs(db.warbank.items) do
            itemData.quantity = itemData.quantity or 0
            if itemData.quantity <= 0 then
                db.warbank.items[key] = nil
                cleaned.emptyItems = (cleaned.emptyItems or 0) + 1
            end
        end
    end

    -- 5) Clean character inventory items with zero quantity
    for charKey, charData in pairs(db.characters) do
        if charData.inventory and charData.inventory.items then
            for key, itemData in pairs(charData.inventory.items) do
                if (itemData.quantity or 0) <= 0 then
                    charData.inventory.items[key] = nil
                    cleaned.emptyItems = (cleaned.emptyItems or 0) + 1
                end
            end
        end
    end

    -- 6) Clean guild bank items with zero quantity
    if db.guilds then
        for guildName, guildData in pairs(db.guilds) do
            if guildData.items then
                for key, itemData in pairs(guildData.items) do
                    if (itemData.quantity or 0) <= 0 then
                        guildData.items[key] = nil
                        cleaned.emptyItems = (cleaned.emptyItems or 0) + 1
                    end
                end
            end
        end
    end

    -- 7) Remove orphaned character order entries
    if db.settings.characterOrder then
        local newOrder = {}
        for _, charKey in ipairs(db.settings.characterOrder) do
            if db.characters[charKey] then
                table.insert(newOrder, charKey)
            else
                cleaned.orphanedOrder = (cleaned.orphanedOrder or 0) + 1
            end
        end
        if cleaned.orphanedOrder then
            db.settings.characterOrder = newOrder
        end
    end

    -- Store cleanup version to avoid re-logging on every login
    local currentVersion = 3  -- increment when adding new cleanup steps
    if db._cleanupVersion ~= currentVersion then
        local parts = {}
        if cleaned.staleSettings then table.insert(parts, cleaned.staleSettings .. " stale settings") end
        if cleaned.oldLogs then table.insert(parts, cleaned.oldLogs .. " old log entries pruned") end
        if cleaned.emptyItems then table.insert(parts, cleaned.emptyItems .. " empty items removed") end
        if cleaned.orphanedOrder then table.insert(parts, cleaned.orphanedOrder .. " orphaned order entries") end
        if #parts > 0 then
            db._cleanupSummary = table.concat(parts, ", ")
        end
        db._cleanupVersion = currentVersion
    end
end

--------------------------
-- Per-Character Settings
--------------------------

-- Get effective setting for a character (per-char override or global default).
-- Per-char value of nil means "inherit global."
function ns:GetCharSetting(charKey, settingKey)
    local charData = ns.db.characters and ns.db.characters[charKey]
    if charData and charData.settings and charData.settings[settingKey] ~= nil then
        return charData.settings[settingKey]
    end
    return ns.db.settings[settingKey]
end

-- Set per-character override. Pass nil to clear and inherit global default.
function ns:SetCharSetting(charKey, settingKey, value)
    if not ns.db or not ns.db.characters then return end
    local charData = ns.db.characters[charKey]
    if not charData then return end
    charData.settings = charData.settings or {}
    charData.settings[settingKey] = value
end

-- Get the per-character override value (nil/true/false) without falling back to global.
function ns:GetCharSettingRaw(charKey, settingKey)
    local charData = ns.db.characters and ns.db.characters[charKey]
    if charData and charData.settings then
        return charData.settings[settingKey]
    end
    return nil
end

--------------------------
-- Bank Tab Filtering
--------------------------

-- Returns the list of warbank bag indices (12-16) filtered by settings
function ns:GetEnabledWarbankTabs()
    if not ns.db or not ns.db.settings.pullTabs or ns.db.settings.pullTabs.mode == "all" then
        return ns.WARBANK_TABS
    end
    local cfg = ns.db.settings.pullTabs.warbank
    if not cfg then return ns.WARBANK_TABS end
    local result = {}
    for i, bagIndex in ipairs(ns.WARBANK_TABS) do
        if cfg[i] ~= false then  -- default true if not explicitly disabled
            table.insert(result, bagIndex)
        end
    end
    return result
end

-- Returns the list of bank bag indices (6-11) filtered by settings for current character
function ns:GetEnabledBankTabs()
    if not ns.db or not ns.db.settings.pullTabs or ns.db.settings.pullTabs.mode == "all" then
        return ns.BANK_TABS
    end
    local charKey = ns:GetCharKey()
    local charCfg = ns.db.settings.pullTabs.bank and ns.db.settings.pullTabs.bank[charKey]
    if not charCfg then return ns.BANK_TABS end
    local result = {}
    for i, bagIndex in ipairs(ns.BANK_TABS) do
        if charCfg[i] ~= false then
            table.insert(result, bagIndex)
        end
    end
    return result
end

--------------------------
-- Gold Formatting
--------------------------

function ns:FormatGold(copper)
    if not copper or copper <= 0 then return "0g" end
    local gold = math.floor(copper / 10000)
    if gold >= 1000000 then
        return string.format("%.1fm", gold / 1000000)
    elseif gold >= 1000 then
        return string.format("%.1fk", gold / 1000)
    end
    return tostring(gold) .. "g"
end

-- Parse gold strings like "1,377g", "22.8k", "1.3m" to numeric gold value
-- Handles WoW color-coded strings and abbreviated formats
function ns:ParseGoldValue(str)
    if not str or str == "" then return 0 end
    local clean = str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local m = clean:match("^([%d,.]+)m")
    if m then return (tonumber((m:gsub(",", ""))) or 0) * 1000000 end
    local k = clean:match("^([%d,.]+)k")
    if k then return (tonumber((k:gsub(",", ""))) or 0) * 1000 end
    local g = clean:match("([%d,]+)g")
    if g then return tonumber((g:gsub(",", ""))) or 0 end
    return 0
end

function ns:FormatRelativeTime(timestamp)
    if not timestamp or timestamp <= 0 then return "never" end
    local diff = time() - timestamp
    if diff < 0 then return "now" end
    if diff < 60 then return "just now" end
    if diff < 3600 then return math.floor(diff / 60) .. "m ago" end
    if diff < 86400 then return math.floor(diff / 3600) .. "h ago" end
    return math.floor(diff / 86400) .. "d ago"
end

--------------------------
-- Auctionator Shopping Lists
--------------------------

-- Get Auctionator shopping list names.
-- Auctionator has no public API for this, so we read the SavedVariable directly.
function ns:GetAuctionatorListNames()
    if type(AUCTIONATOR_SHOPPING_LISTS) ~= "table" then return {} end
    local names = {}
    for _, list in ipairs(AUCTIONATOR_SHOPPING_LISTS) do
        if type(list) == "table" and list.name and not list.isTemporary then
            names[#names + 1] = list.name
        end
    end
    return names
end

--------------------------
-- Character Key
--------------------------

function ns:GetCharKey()
    local name  = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

--------------------------
-- Do Not Track
--------------------------

function ns:IsDoNotTrack(itemID)
    if not ns.db then return false end
    return ns.db.doNotTrack[tostring(itemID)] == true
        or type(ns.db.doNotTrack[tostring(itemID)]) == "string"
end

function ns:AddDoNotTrack(itemID, itemName)
    if not ns.db then return end
    ns.db.doNotTrack[tostring(itemID)] = itemName or true
end

function ns:RemoveDoNotTrack(itemID)
    if not ns.db then return end
    ns.db.doNotTrack[tostring(itemID)] = nil
end

--------------------------
-- Log Operations
--------------------------

function ns:ClearLog()
    if ns.db then
        wipe(ns.db.log)
    end
end

--------------------------
-- Import Utilities
--------------------------

function ns:ImportGetCount(source)
    if not ns.db or not ns.db.imports then return 0 end
    local src = ns.db.imports[source or "fpScanner"]
    if not src then return 0 end
    local count = 0
    for _ in pairs(src) do
        count = count + 1
    end
    return count
end

function ns:ImportClear(source)
    if not ns.db or not ns.db.imports then return end
    local src = source or "fpScanner"
    if ns.db.imports[src] then
        wipe(ns.db.imports[src])
    end
end

function ns:ImportRemove(source, key)
    if not ns.db or not ns.db.imports then return end
    local src = ns.db.imports[source or "fpScanner"]
    if src then
        src[key] = nil
    end
end

--------------------------
-- Inventory Search
--------------------------

function ns:FindItemLocations(itemKey, itemName)
    if not ns.db then return {} end

    local locations = {}
    local resolvedID
    local numID = tonumber(itemKey and itemKey:match("^(%d+);"))
    if numID and numID > 0 then
        resolvedID = numID
    elseif itemName and itemName ~= "" then
        resolvedID = ns:ResolveItemID({itemID = "", name = itemName})
    end

    for charKey, charData in pairs(ns.db.characters) do
        if charData.inventory and charData.inventory.items then
            for key, itemData in pairs(charData.inventory.items) do
                local matched = (key == itemKey)
                if not matched and resolvedID then
                    local invNumID = tonumber(key:match("^(%d+);"))
                    if invNumID and invNumID == resolvedID then matched = true end
                end
                if matched then
                    table.insert(locations, {
                        charKey   = charKey,
                        class     = charData.class,
                        quantity  = itemData.quantity,
                        locations = itemData.locations,
                        lastScan  = charData.inventory.lastScan,
                    })
                end
            end
        end
    end

    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            local matched = (key == itemKey)
            if not matched and resolvedID then
                local invNumID = tonumber(key:match("^(%d+);"))
                if invNumID and invNumID == resolvedID then matched = true end
            end
            if matched then
                table.insert(locations, {
                    charKey   = "Warbank",
                    quantity  = itemData.quantity,
                    locations = {warbank = itemData.quantity},
                    lastScan  = ns.db.warbank.lastScan,
                })
            end
        end
    end

    return locations
end

function ns:FindItemByName(itemName)
    if not ns.db or not itemName then return {} end
    itemName = itemName:lower()

    local locations = {}

    for charKey, charData in pairs(ns.db.characters) do
        if charData.inventory and charData.inventory.items then
            for key, itemData in pairs(charData.inventory.items) do
                if itemData.name and itemData.name:lower():find(itemName, 1, true) then
                    table.insert(locations, {
                        charKey   = charKey,
                        class     = charData.class,
                        itemKey   = key,
                        name      = itemData.name,
                        quantity  = itemData.quantity,
                        locations = itemData.locations,
                    })
                end
            end
        end
    end

    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            if itemData.name and itemData.name:lower():find(itemName, 1, true) then
                table.insert(locations, {
                    charKey   = "Warbank",
                    itemKey   = key,
                    name      = itemData.name,
                    quantity  = itemData.quantity,
                    locations = {warbank = itemData.quantity},
                })
            end
        end
    end

    return locations
end
