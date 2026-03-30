-- Migration.lua
-- Schema versioning and data migrations
local addonName, ns = ...

--------------------------
-- Schema Versioning & Migration
--------------------------

-- Current schema version
local CURRENT_SCHEMA = 5

-- Schema history:
-- nil/0  = v0.5.0 (stable release): queue array, separate inventory/characters/hiddenCharacters
-- 1      = v0.6.0-alpha.1: added todoLists with current/queue, items array
-- 2      = v0.6.x (this change): consolidated characters, imports map, guilds, steps model
-- 3      = character roles: ignored boolean → role field (both/sell/buy/none)

local function RunMigrations(db)
    db.schemaVersion = db.schemaVersion or 0

    -- Migration 1: v0.5.0 → v0.6.0-alpha (already shipped)
    if db.schemaVersion < 1 then
        db.todoLists = db.todoLists or {}
        db.schemaVersion = 1
    end

    -- Migration 2: → v0.6.x consolidated model
    if db.schemaVersion < 2 then

        -- 1. Characters: merge inventory + characters + hiddenCharacters
        if db.inventory then
            local merged = {}
            for charKey, invData in pairs(db.inventory) do
                local meta = (db.characters or {})[charKey] or {}
                merged[charKey] = {
                    class     = invData.class or meta.class,
                    level     = meta.level,
                    guild     = nil,  -- populated on next login
                    gold      = meta.gold or 0,
                    lastLogin = meta.lastLogin or 0,
                    ignored   = (db.hiddenCharacters or {})[charKey] or false,
                    inventory = {
                        lastScan     = invData.lastScan,
                        lastBankScan = invData.lastBankScan,
                        items        = invData.items or {},
                    },
                }
            end
            db.characters = merged
            db.inventory = nil
            db.hiddenCharacters = nil
        end

        -- 2. Queue → imports.fpScanner (map)
        if db.queue then
            db.imports = db.imports or { fpScanner = {}, fpCrossRealm = {}, tsm = {} }
            for _, item in ipairs(db.queue) do
                local key = ns:MakeImportKey(item.itemKey, item.name, item.targetRealm)
                db.imports.fpScanner[key] = {
                    itemKey = item.itemKey, itemID = item.itemID or "",
                    name = item.name or "", quality = item.quality,
                    ilvl = item.ilvl, bonusIDs = item.bonusIDs,
                    modifiers = item.modifiers, quantity = item.quantity or 1,
                    category = item.category, expansion = item.expansion,
                    sellRate = item.sellRate, targetRealm = item.targetRealm,
                    expectedPrice = item.expectedPrice,
                    noCompetition = item.noCompetition,
                    importedAt = item.addedAt or time(),
                }
            end
            db.queue = nil
        end

        -- 3. Guildbank → guilds
        if db.guildbank then
            db.guilds = {}
            for name, data in pairs(db.guildbank) do
                db.guilds[name] = {
                    enabled = true, members = {},
                    lastScan = data.lastScan, items = data.items or {},
                }
            end
            -- Populate members from character guild fields
            for charKey, charData in pairs(db.characters or {}) do
                if charData.guild and db.guilds[charData.guild] then
                    table.insert(db.guilds[charData.guild].members, charKey)
                end
            end
            db.guildbank = nil
        end

        -- 4. TodoLists: current→active, queue→upcoming
        if db.todoLists then
            if db.todoLists.current then
                db.todoLists.active = db.todoLists.current
                db.todoLists.active.source = db.todoLists.active.source or "fpScanner"
                -- Add steps to existing tasks (migration)
                for _, task in ipairs(db.todoLists.active.tasks or db.todoLists.active.items or {}) do
                    if not task.steps then
                        task.steps = {}
                        local src = task.source or "bags"
                        if src == "bank" or src == "warbank" or src == "guildbank" then
                            table.insert(task.steps, { type = "retrieve", from = src, status = "pending" })
                        end
                        table.insert(task.steps, { type = "post", status = task.status == "posted" and "completed" or "pending" })
                        table.insert(task.steps, { type = "collect", status = "pending" })
                        task.currentStep = 1
                        -- Advance past completed steps
                        for i, step in ipairs(task.steps) do
                            if step.status == "completed" then task.currentStep = i + 1 end
                        end
                    end
                    -- Add import link fields
                    if not task.importSource then
                        task.importSource = "fpScanner"
                        task.importKey = ns:MakeImportKey(task.itemKey, task.name, task.targetRealm)
                    end
                end
                -- Rename items → tasks
                if db.todoLists.active.items then
                    db.todoLists.active.tasks = db.todoLists.active.items
                    db.todoLists.active.items = nil
                end
                db.todoLists.current = nil
            end
            if db.todoLists.queue then
                db.todoLists.upcoming = db.todoLists.queue
                db.todoLists.queue = nil
            end
        end

        -- 5. ExternalAccounts → accounts.external
        if db.externalAccounts then
            db.accounts = { external = db.externalAccounts }
            db.externalAccounts = nil
        end

        db.schemaVersion = 2
    end  -- migration 2

    -- Migration 3: Add character role, migrate ignored → role
    -- Role values: "both" (default), "sell", "buy", "none" (hidden)
    if db.schemaVersion < 3 then
        for charKey, charData in pairs(db.characters or {}) do
            if charData.ignored then
                charData.role = "none"
            end
            -- Characters without .ignored keep role=nil which defaults to "both"
        end
        db.schemaVersion = 3
    end  -- migration 3

    -- Migration 4: Multi-account sync support
    -- Add taskUUID + _syncMeta to existing tasks, accountUUID to characters, db.sync structure
    if db.schemaVersion < 4 then
        -- Generate a persistent account UUID if one doesn't exist
        if not db.sync or not db.sync.accountUUID then
            db.sync = db.sync or {}
            -- Simple UUID: timestamp + random hex
            db.sync.accountUUID = string.format("%x%x", time(), math.random(0, 0xFFFFFF))
        end

        -- Tag existing characters with this account's UUID
        for charKey, charData in pairs(db.characters or {}) do
            if not charData.accountUUID then
                charData.accountUUID = db.sync.accountUUID
            end
        end

        -- Add taskUUID and _syncMeta to existing todo tasks
        local function MigrateTasks(tasks)
            if not tasks then return end
            for _, task in ipairs(tasks) do
                if not task.taskUUID then
                    task.taskUUID = string.format("%x%x%x", time(), math.random(0, 0xFFFF), math.random(0, 0xFFFF))
                end
                if not task._syncMeta then
                    task._syncMeta = {
                        lastModifiedBy = db.sync.accountUUID,
                        lastModifiedAt = time(),
                    }
                end
            end
        end

        if db.todoLists then
            if db.todoLists.active and db.todoLists.active.tasks then
                MigrateTasks(db.todoLists.active.tasks)
            end
            for _, list in ipairs(db.todoLists.upcoming or {}) do
                MigrateTasks(list.tasks)
            end
        end

        db.schemaVersion = 4
    end  -- migration 4

    -- Migration 5: Multi-partner sync (partner → partners, BNet transport)
    -- Converts single db.sync.partner to db.sync.partners[uuid] table,
    -- moves per-partner fields (lastRecvSeq, pendingDeltas) into partner entry.
    if db.schemaVersion < 5 then
        db.sync = db.sync or {}

        if db.sync.partner then
            local partnerUUID = db.sync.partner.accountUUID
            if partnerUUID then
                db.sync.partners = db.sync.partners or {}
                db.sync.partners[partnerUUID] = {
                    bnetAccountID = nil, -- populated on next BNet connect
                    label = db.sync.partner.label or "Linked Account",
                    lastSeen = db.sync.partner.lastSeen or 0,
                    lastFullSync = db.sync.partner.lastFullSync or 0,
                    lastRecvSeq = db.sync.lastRecvSeq or 0,
                    pendingDeltas = db.sync.pendingDeltas or {},
                }
            end
            db.sync.partner = nil
        end

        -- Ensure partners table exists (fresh installs or unlinked users)
        db.sync.partners = db.sync.partners or {}

        -- Remove old global fields (now per-partner)
        db.sync.lastRecvSeq = nil
        db.sync.pendingDeltas = nil

        db.schemaVersion = 5
    end  -- migration 5
end  -- RunMigrations

-- Expose for DB.lua
ns._RunMigrations = RunMigrations
ns._CURRENT_SCHEMA = CURRENT_SCHEMA
