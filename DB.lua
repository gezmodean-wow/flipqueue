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
    db.imports.dealFinder   = db.imports.dealFinder or {}
    db.todoLists    = db.todoLists or {}
    db.todoLists.upcoming = db.todoLists.upcoming or {}
    db.log          = db.log or {}
    db.doNotTrack   = db.doNotTrack or {}
    db.sync         = db.sync or {}
    db.sync.accountUUID   = db.sync.accountUUID or string.format("%x%x", time(), math.random(0, 0xFFFFFF))
    db.sync.lastSentSeq   = db.sync.lastSentSeq or 0
    db.sync.partners      = db.sync.partners or {}
    db.knownLocations = db.knownLocations or {}
    db.accounts     = db.accounts or {}
    db.accounts.primary  = db.accounts.primary or { syncKey = nil, characters = {} }
    db.accounts.external = db.accounts.external or {}
    db.accounts.linked   = db.accounts.linked or {}
    db.settings     = db.settings or {
        autoScan         = true,
        autoPullBank     = false,
        autoDepositWarbank = false,
        autoDepositAll = false,
        showLoginMessage = true,
        autoWithdrawGold = true,
        maxWithdrawGold = 500,
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
    db.settings.tsmMinPriceSource  = db.settings.tsmMinPriceSource or "70% DBRegionMarketAvg"
    db.settings.tsmPriceSource     = db.settings.tsmPriceSource or "70% DBRegionMarketAvg"
    db.settings.dfPriceSource      = db.settings.dfPriceSource or "deal"  -- deal, DBMinBuyout, DBMarket, DBRegionMarketAvg, DBRegionSaleAvg
    if db.settings.tsmShowColumns == nil then db.settings.tsmShowColumns = false end
    if db.settings.ahAutoScanOnOpen == nil then db.settings.ahAutoScanOnOpen = false end
    db.settings.tsmFallbackOp = db.settings.tsmFallbackOp or ""
    if db.settings.tsmAutoUpdatePrice == nil then db.settings.tsmAutoUpdatePrice = false end
    db.settings.tsmPriceMaxAge     = db.settings.tsmPriceMaxAge or 3600
    -- Transform page defaults
    db.settings.transformPriceSource  = db.settings.transformPriceSource or "45% DBRegionMarketAvg"
    db.settings.transformDiscount     = db.settings.transformDiscount or 100
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
    -- TSM rejection handling
    if db.settings.tsmAutoSkipRejected == nil then db.settings.tsmAutoSkipRejected = true end
    -- TSM generation-time filtering: skip deals below TSM min price during todo generation
    -- Skipped deals still appear in results but don't consume inventory
    if db.settings.tsmSkipOnGenerate == nil then db.settings.tsmSkipOnGenerate = true end
    -- Debug messages (off by default)
    if db.settings.debugMessages == nil then db.settings.debugMessages = false end
    -- Auto-deposit earnings to warbank (off by default — players may want to keep earnings)
    if db.settings.autoDepositGold == nil then db.settings.autoDepositGold = false end
    db.settings.goldBuffer = db.settings.goldBuffer or 50  -- gold to keep on character beyond fees
    -- Warband Miser override: when true, FlipQueue manages gold even if
    -- Warband Miser is loaded. Default off — WM owns gold by default when
    -- installed to avoid fighting it.
    if db.settings.warbandMiserOverride == nil then db.settings.warbandMiserOverride = false end
    -- Bank tab selection
    if not db.settings.pullTabs then
        db.settings.pullTabs = { mode = "all" }
    end
    -- Deposit overflow: when the destination bank type has no accepting/free
    -- slot, optionally fall back to the other bank type. Default OFF — we
    -- never overflow unless the user explicitly opts in.
    --   scope     "global" (one toggle for all chars) or "char" (per-char)
    --   enabled   global default
    --   crossStack  sub-setting: when overflow is enabled, also allow
    --               smart-stacking to merge into partial stacks in the
    --               secondary bank type. Default OFF.
    --   char[ck] = { enabled, crossStack } — per-char overrides
    if not db.settings.depositOverflow then
        db.settings.depositOverflow = {
            scope = "global",
            enabled = false,
            crossStack = false,
            char = {},
        }
    end
    -- Reagents/materials in extras: tradegoods aren't tracked for sales or
    -- to-dos (they're not cross-region), so by default we leave them on the
    -- character instead of sweeping them into the warbank as "extras". Users
    -- who DO want them deposited can opt in.
    if db.settings.depositIncludeReagents == nil then
        db.settings.depositIncludeReagents = false
    end
    -- Bank popup section collapse state — persisted so the user's choices
    -- carry across popups. All sections expanded by default.
    if not db.settings.bankPopupCollapsed then
        db.settings.bankPopupCollapsed = {
            pulls = false, deposits = false, gold = false, extras = false,
        }
    end
    -- Click-to-copy mode for the Next-steps queue. Controls which value
    -- the copy blip exposes when a row is clicked. Default "realm"
    -- because users primarily paste into WoW's realm filter on the
    -- character-select screen rather than a name search.
    db.settings.copyOnClickMode = db.settings.copyOnClickMode or "realm"
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
    -- Deal Finder defaults
    db.settings.dfMinPrice     = db.settings.dfMinPrice or 500000     -- 50g in copper
    db.settings.dfMinSellRate  = db.settings.dfMinSellRate or 0.05    -- 5%
    db.settings.dfMinProfit    = db.settings.dfMinProfit or 100000    -- 10g in copper
    db.settings.dfMinProfitPct = db.settings.dfMinProfitPct or 5      -- 5%
    db.settings.dfOutlierMultiplier = db.settings.dfOutlierMultiplier or 1.5
    if db.settings.dfIgnoreOutliers == nil then db.settings.dfIgnoreOutliers = false end
    db.settings.dfPriorityOrder = db.settings.dfPriorityOrder or {"profit", "noCompetition", "previousSales"}
    -- Skip deals that have no matching character (suppress "create character" tasks)
    if db.settings.skipUnassigned == nil then db.settings.skipUnassigned = false end
    -- TSM character detection dismissed list
    db.settings.dismissedTSMChars = db.settings.dismissedTSMChars or {}
    -- Tutorial (first-time interactive walkthrough)
    if db.settings.tutorialDone == nil then db.settings.tutorialDone = false end
    -- Setup wizard (first-run settings configuration)
    -- Existing users (tutorial done or have character data) skip the wizard
    -- Popup anchor positions (relative to mini frame)
    db.settings.bankPopupAnchor = db.settings.bankPopupAnchor or "below"   -- below, above, left, right
    db.settings.detailPopupAnchor = db.settings.detailPopupAnchor or "left" -- left, right
    if db.settings.setupDone == nil then
        if db.settings.tutorialDone or next(db.characters or {}) then
            db.settings.setupDone = true
        else
            db.settings.setupDone = false
        end
    end

    ns.db = db

    -- Build realm lookup tables from RealmData
    if ns.BuildRealmLookup then
        ns:BuildRealmLookup()
    end

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

-- Returns the effective deposit-overflow settings for the current character.
-- When scope is "char" and the current char has overrides, those win;
-- otherwise the global defaults apply.
-- Returns: enabled (bool), crossStack (bool)
function ns:GetDepositOverflow()
    if not ns.db then return false, false end
    local s = ns.db.settings.depositOverflow
    if not s then return false, false end
    if s.scope == "char" then
        local cfg = s.char and s.char[ns:GetCharKey()]
        if cfg then
            return cfg.enabled and true or false, cfg.crossStack and true or false
        end
    end
    return s.enabled and true or false, s.crossStack and true or false
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
-- Character Roles
--------------------------

-- Role values: "both" (default), "sell", "buy", "none" (hidden)

function ns:GetCharRole(charKey)
    local charData = ns.db and ns.db.characters and ns.db.characters[charKey]
    return charData and charData.role or "both"
end

function ns:SetCharRole(charKey, role)
    if not ns.db or not ns.db.characters then return end
    local charData = ns.db.characters[charKey]
    if not charData then return end
    charData.role = role
    -- Keep .ignored in sync for backward compatibility
    charData.ignored = (role == "none")
end

function ns:CharCanSell(charKey)
    local role = self:GetCharRole(charKey)
    return role == "both" or role == "sell"
end

function ns:CharCanBuy(charKey)
    local role = self:GetCharRole(charKey)
    return role == "both" or role == "buy"
end

function ns:IsCharHidden(charKey)
    return self:GetCharRole(charKey) == "none"
end

-- A "phantom" character has no class and has never logged in with FQ active.
-- These entries come from TSM/Syndicator data for characters the user may not
-- own (deleted characters, other WoW accounts on the same Battle.net).
-- Phantom characters should not receive task assignments.
function ns:IsPhantomChar(charKey)
    if not self.db or not self.db.characters then return false end
    local charData = self.db.characters[charKey]
    if not charData then return false end
    return not charData.class and not charData.lastLogin
end

-- Check if two roles overlap for shared AH detection.
-- Characters with overlapping roles on the same AH cluster are duplicates.
function ns:RolesOverlap(role1, role2)
    if role1 == "none" or role2 == "none" then return false end
    if role1 == "both" or role2 == "both" then return true end
    return role1 == role2  -- sell+sell or buy+buy
end

--------------------------
-- Account Ownership
--------------------------

function ns:GetCharAccountLabel(charKey)
    local charData = ns.db.characters and ns.db.characters[charKey]
    if not charData or not charData.accountUUID then return nil end
    if not ns.db.sync or charData.accountUUID == ns.db.sync.accountUUID then return nil end
    local partners = ns.db.sync.partners
    if partners and partners[charData.accountUUID] then
        return partners[charData.accountUUID].label or "Linked Account"
    end
    return "Other Account"
end

function ns:IsRemoteChar(charKey)
    local charData = ns.db.characters and ns.db.characters[charKey]
    if not charData or not charData.accountUUID then return false end
    if not ns.db.sync then return false end
    return charData.accountUUID ~= ns.db.sync.accountUUID
end

--------------------------
-- Warband Miser integration
--------------------------

-- Warband Miser is a separate addon that manages per-character gold
-- deposit/withdraw against the warband bank. If a user runs it, FlipQueue's
-- own auto-gold routines fight it. This helper is the single source of
-- truth — callers gate their auto-gold behavior on it so WM owns gold
-- management end-to-end. Users can force FlipQueue to manage gold anyway
-- via the `warbandMiserOverride` setting (off by default).
function ns:IsWarbandMiserActive()
    if ns.db and ns.db.settings and ns.db.settings.warbandMiserOverride then
        return false
    end
    -- Modern retail API; fall back to legacy global for older clients.
    local loaded = false
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        loaded = C_AddOns.IsAddOnLoaded("WarbandMiser") or false
    elseif IsAddOnLoaded then
        loaded = IsAddOnLoaded("WarbandMiser") or false
    end
    return loaded
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
    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
        ns.Sync:EmitDelta("DNT+", { itemID = tostring(itemID), name = itemName })
    end
end

function ns:RemoveDoNotTrack(itemID)
    if not ns.db then return end
    ns.db.doNotTrack[tostring(itemID)] = nil
    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
        ns.Sync:EmitDelta("DNT-", { itemID = tostring(itemID) })
    end
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

-- Wipe every import source. Imports are intended to be ephemeral working
-- state that exists only during the import → generate phase of building a
-- to-do list. Once the list is committed, imports have served their purpose
-- and would otherwise grow unbounded across sessions. Called automatically
-- by TodoList:CommitList.
function ns:ImportClearAll()
    if not ns.db or not ns.db.imports then return end
    for src in pairs(ns.db.imports) do
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
