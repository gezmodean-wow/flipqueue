-- Migration.lua
-- Schema versioning and data migrations
local addonName, ns = ...

--------------------------
-- Schema Versioning & Migration
--------------------------

-- Current schema version
local CURRENT_SCHEMA = 2

-- Schema history:
-- nil/0  = v0.5.0 (stable release): queue array, separate inventory/characters/hiddenCharacters
-- 1      = v0.6.0-alpha.1: added todoLists with current/queue, items array
-- 2      = v0.6.x (this change): consolidated characters, imports map, guilds, steps model

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
end  -- RunMigrations

-- Expose for DB.lua
ns._RunMigrations = RunMigrations
ns._CURRENT_SCHEMA = CURRENT_SCHEMA
