-- Migration.lua
-- Schema versioning and data migrations
local addonName, ns = ...

--------------------------
-- Schema Versioning & Migration
--------------------------

-- Current schema version
local CURRENT_SCHEMA = 12

-- Schema history:
-- nil/0  = v0.5.0 (stable release): queue array, separate inventory/characters/hiddenCharacters
-- 1      = v0.6.0-alpha.1: added todoLists with current/queue, items array
-- 2      = v0.6.x (this change): consolidated characters, imports map, guilds, steps model
-- 3      = character roles: ignored boolean → role field (both/sell/buy/none)
-- 4      = ItemResearch refactor
-- 5      = Multi-partner sync (partner → partners[uuid])
-- 6      = Dual transport (bnet / whisper)
-- 7      = v0.11.0: Syndicator becomes hard dep; old inventory caches wiped
--          and re-populated from Syndicator on next scan.
-- 8      = Character tombstones: db.deletedCharacters table. Tombstoned
--          chars are kept out of db.characters despite TSM/Syndicator/sync
--          re-detection, until the user explicitly restores.
-- 9      = ahAutoScanOnOpen smart default: when TSM or Auctionator is
--          loaded, force the setting to false so FlipQueue doesn't compete
--          with their scans (FQ-137 root cause). One-shot — players can
--          re-enable from Settings if they prefer the old behavior.
-- 10     = #148: manageItems / manageGold authority masters with scope-vs-
--          trigger split. Derives initial values from the existing per-
--          action `auto*` flags so behavior is preserved across the upgrade.
--          One-shot; player can flip the masters from Settings afterward.
-- 11     = #155: action-class tri-state modes ("auto" / "manual" / "disabled").
--          Replaces per-action boolean trigger flags with mode strings so
--          scope and automation can be expressed independently. The bool
--          model conflated "is FlipQueue allowed?" with "should it auto-fire?",
--          which left off-trigger settings unable to run manually and
--          Pause Automation cutting manual access entirely. Migrates per-
--          char overrides too. Old keys are dropped post-derive so legacy
--          reads return nil rather than stale conflicting state.
-- 12     = FQ-227: auctBuyListIncludeIlvl forced off. The exact ilvl bound
--          from FQ-195 compares against player-level-scaled AH browse ilvls
--          and hid most gear listings on low-level buyer alts. One-shot;
--          players can re-enable from the Auctionator settings page.

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

    -- Migration 6: Dual transport (bnet / whisper). Tag all existing partners as bnet transport.
    -- Same-BNet-account multiboxing now supported via whisper transport as a fallback when
    -- BNet friend lookup fails (you cannot BNet-friend your own account).
    if db.schemaVersion < 6 then
        db.sync = db.sync or {}
        db.sync.partners = db.sync.partners or {}
        for _, partner in pairs(db.sync.partners) do
            if not partner.transport then
                partner.transport = "bnet"
            end
        end
        db.schemaVersion = 6
    end  -- migration 6

    -- Migration 7: v0.11.0 Syndicator migration. Wipe per-character inventory
    -- blobs and the warbank cache. Syndicator is now the source of truth and
    -- will re-populate on next scan. Character metadata (gold, class, level,
    -- role, accountUUID, guild) is preserved — we only drop the items cache.
    -- Partner-sourced characters that we haven't re-synced yet lose their
    -- items too, but Sync.lua will replay via full-sync on next reconnect.
    if db.schemaVersion < 7 then
        local wipedChars = 0
        if db.characters then
            for charKey, charData in pairs(db.characters) do
                if type(charData) == "table" and charData.inventory then
                    charData.inventory = nil
                    wipedChars = wipedChars + 1
                end
            end
        end
        db.warbank = {}  -- fresh table, no items, no freeSlots — Scanner repopulates
        -- Stash in a distinct slot so CleanupLegacyData in DB.lua (which
        -- runs immediately after migrations and sometimes overwrites
        -- _cleanupSummary) can't clobber the Phase 6a message. Scanner's
        -- PLAYER_LOGIN handler prints this separately.
        db._phase6aMessage = "Phase 6a: reset " .. wipedChars ..
            " character inventor" .. (wipedChars == 1 and "y" or "ies") ..
            " and the warbank cache. Syndicator is now the inventory source."
        db.schemaVersion = 7
    end  -- migration 7

    -- Migration 8: Character deletion tombstones. Adds db.deletedCharacters,
    -- a table keyed by charKey whose presence blocks re-detection from
    -- TSM/Syndicator/sync. No data migration needed — empty table suffices
    -- since no prior deletions could have been recorded.
    if db.schemaVersion < 8 then
        db.deletedCharacters = db.deletedCharacters or {}
        db.schemaVersion = 8
    end  -- migration 8

    -- Migration 9: ahAutoScanOnOpen smart default (FQ-137 root cause).
    -- Players running TSM or Auctionator alongside FlipQueue had three
    -- addons issuing SendSearchQuery calls in parallel, all queueing
    -- behind Blizzard's global AH rate limit. With auto-scan-on-open
    -- enabled, FQ added 350ms × bag-item-count to the cumulative wait.
    -- Force-flip to off when either of those addons is loaded; the
    -- player can re-enable from Settings if they prefer the old behavior.
    -- One-shot, so players who explicitly turn it back on don't get
    -- repeatedly reset on subsequent migrations.
    if db.schemaVersion < 9 then
        db.settings = db.settings or {}
        local hasTSM, hasAuctionator
        if C_AddOns and C_AddOns.IsAddOnLoaded then
            hasTSM = C_AddOns.IsAddOnLoaded("TradeSkillMaster")
            hasAuctionator = C_AddOns.IsAddOnLoaded("Auctionator")
        elseif IsAddOnLoaded then
            hasTSM = IsAddOnLoaded("TradeSkillMaster")
            hasAuctionator = IsAddOnLoaded("Auctionator")
        end
        if hasTSM or hasAuctionator then
            local wasOn = db.settings.ahAutoScanOnOpen == true
            db.settings.ahAutoScanOnOpen = false
            if wasOn then
                -- Surface the change so a player who explicitly enabled it
                -- isn't surprised when their setting flipped. Stashed for
                -- Scanner.lua's PLAYER_LOGIN handler to print alongside
                -- the existing _cleanupSummary / _phase6aMessage path.
                local who = (hasTSM and hasAuctionator) and "TradeSkillMaster and Auctionator"
                    or (hasTSM and "TradeSkillMaster" or "Auctionator")
                db._autoScanMigrationMessage =
                    "FlipQueue: " .. who .. " detected — auto-scan-on-AH-open turned off " ..
                    "to avoid competing with their scans. Use the Scan To-Do button in " ..
                    "the AH drawer when you want fresh prices, or re-enable in /fq settings."
            end
        end
        db.schemaVersion = 9
    end  -- migration 9

    -- Migration 10: #148 authority masters.
    --
    -- The legacy model conflated "is FQ allowed to manage X?" with "should
    -- FQ auto-fire on bank open?" — every gating bug we've patched
    -- (FQ-117 alpha3, FQ-110 alpha10, FQ-110 toeknee branch) was a symptom
    -- of that conflation. The new model splits the two axes: master switches
    -- (manageItems / manageGold) own scope; per-action flags (autoPullBank,
    -- autoDepositWarbank, autoDepositAll, autoWithdrawGold, autoDepositGold)
    -- become trigger toggles under their parent master.
    --
    -- Derivation: a master defaults ON if ANY of its child auto-flags was
    -- on at migration time, OFF only if all child flags were off. This
    -- preserves behavior — a player who had auto-pull-on and auto-deposit-
    -- off keeps that exact behavior because manageItems is ON and the per-
    -- action triggers carry their existing values forward.
    if db.schemaVersion < 10 then
        db.settings = db.settings or {}
        if db.settings.manageItems == nil then
            db.settings.manageItems = (
                db.settings.autoPullBank
                or db.settings.autoDepositWarbank
                or db.settings.autoDepositAll
            ) and true or false
            -- Fresh installs (where all autos default false) still want the
            -- master ON by default — otherwise the masters appear "off" on a
            -- new install and the player can't see the rest of the settings.
            -- The migration only sees install state on first run; if every
            -- auto-flag is false at this exact moment we default ON, then
            -- the player can opt out from Settings.
            if db.settings.manageItems == false then
                db.settings.manageItems = true
            end
        end
        if db.settings.manageGold == nil then
            db.settings.manageGold = (
                db.settings.autoWithdrawGold
                or db.settings.autoDepositGold
            ) and true or false
            if db.settings.manageGold == false then
                db.settings.manageGold = true
            end
        end
        -- Surface the layout change so the player isn't surprised by the
        -- new top-level masters in Settings. Re-uses the migration-message
        -- pattern Scanner.lua's PLAYER_LOGIN handler already drains.
        db._mastersMigrationMessage =
            "FlipQueue: settings reorganized. New top-level toggles control whether " ..
            "FlipQueue manages your items / gold per character. " ..
            "See /fq settings or /fq about for details — your existing behavior is unchanged."
        db.schemaVersion = 10
    end  -- migration 10

    -- Migration 11: #155 action-class tri-state modes.
    --
    -- Replaces per-action booleans with mode strings ("auto" / "manual" /
    -- "disabled") so the action's *availability* and its *auto-fire*
    -- behavior are stored together as a single tri-state. Closes the
    -- architectural seam #148 partially fixed: planner / executor /
    -- pause-automation logic can now read one source of truth per action.
    --
    -- Pairings + mapping:
    --   autoPullBank, autoDepositWarbank        → todoMode (paired)
    --   autoDepositAll                          → extrasMode
    --   depositIncludeReagents, autoDepositAll  → reagentsMode
    --   autoWithdrawGold                        → goldWithdrawMode
    --   autoDepositGold                         → goldDepositMode
    --
    -- Migration policy:
    --   bool true  → "auto"
    --   bool false → "manual"   (preserves the action's manual availability;
    --                            players who explicitly want the action to
    --                            disappear flip to "disabled" post-upgrade)
    --   reagents=false → "disabled"  (explicit exclusion was the prior
    --                                  intent; preserve it directly)
    --
    -- Old keys are dropped so any legacy code reading them gets nil rather
    -- than a stale value that disagrees with the new mode.
    if db.schemaVersion < 11 then
        db.settings = db.settings or {}

        local function deriveTodo(pull, dep)
            return (pull or dep) and "auto" or "manual"
        end
        local function deriveExtras(autoAll)
            return autoAll and "auto" or "manual"
        end
        local function deriveReagents(reag, autoAll)
            if reag == false then return "disabled" end
            return autoAll and "auto" or "manual"
        end
        local function deriveBoolMode(b)
            return b and "auto" or "manual"
        end

        -- Globals
        do
            local s = db.settings
            s.todoMode         = s.todoMode         or deriveTodo(s.autoPullBank, s.autoDepositWarbank)
            s.extrasMode       = s.extrasMode       or deriveExtras(s.autoDepositAll)
            s.reagentsMode     = s.reagentsMode     or deriveReagents(s.depositIncludeReagents, s.autoDepositAll)
            s.goldWithdrawMode = s.goldWithdrawMode or deriveBoolMode(s.autoWithdrawGold)
            s.goldDepositMode  = s.goldDepositMode  or deriveBoolMode(s.autoDepositGold)
            -- Drop the old keys.
            s.autoPullBank          = nil
            s.autoDepositWarbank    = nil
            s.autoDepositAll        = nil
            s.depositIncludeReagents = nil
            s.autoWithdrawGold      = nil
            s.autoDepositGold       = nil
        end

        -- Per-character overrides. Only carry forward to the new keys when
        -- the player had an explicit per-char override on one of the old
        -- keys; chars that purely inherited global continue to inherit on
        -- the new keys (no per-char value set).
        if db.characters then
            for _, charData in pairs(db.characters) do
                if charData.settings then
                    local cs = charData.settings

                    -- todoMode (paired pull + deposit)
                    if cs.autoPullBank ~= nil or cs.autoDepositWarbank ~= nil then
                        local pull = (cs.autoPullBank ~= nil)       and cs.autoPullBank       or false
                        local dep  = (cs.autoDepositWarbank ~= nil) and cs.autoDepositWarbank or false
                        if cs.todoMode == nil then
                            cs.todoMode = deriveTodo(pull, dep)
                        end
                    end

                    -- extrasMode
                    if cs.autoDepositAll ~= nil then
                        if cs.extrasMode == nil then
                            cs.extrasMode = deriveExtras(cs.autoDepositAll)
                        end
                    end

                    -- reagentsMode (reads both depositIncludeReagents
                    -- override AND autoDepositAll override since the new
                    -- mode is derived from both)
                    if cs.depositIncludeReagents ~= nil or cs.autoDepositAll ~= nil then
                        local reag    = cs.depositIncludeReagents
                        local autoAll = (cs.autoDepositAll ~= nil) and cs.autoDepositAll or false
                        if cs.reagentsMode == nil then
                            cs.reagentsMode = deriveReagents(reag, autoAll)
                        end
                    end

                    -- goldWithdrawMode / goldDepositMode
                    if cs.autoWithdrawGold ~= nil then
                        if cs.goldWithdrawMode == nil then
                            cs.goldWithdrawMode = deriveBoolMode(cs.autoWithdrawGold)
                        end
                    end
                    if cs.autoDepositGold ~= nil then
                        if cs.goldDepositMode == nil then
                            cs.goldDepositMode = deriveBoolMode(cs.autoDepositGold)
                        end
                    end

                    -- Drop legacy per-char keys.
                    cs.autoPullBank          = nil
                    cs.autoDepositWarbank    = nil
                    cs.autoDepositAll        = nil
                    cs.depositIncludeReagents = nil
                    cs.autoWithdrawGold      = nil
                    cs.autoDepositGold       = nil
                end
            end
        end

        db._modesMigrationMessage =
            "FlipQueue: settings updated to a clearer model. Each managed action " ..
            "(Tasks / Extras / Reagents / Gold withdraw / Gold deposit) now has " ..
            "Auto / Manual / Disabled options. Your existing behavior is preserved — " ..
            "anything that was auto-firing stays auto, anything that was off becomes " ..
            "Manual (button still works, just no auto-fire on bank open). " ..
            "See /fq settings or /fq about for details."
        db.schemaVersion = 11
    end  -- migration 11

    -- Migration 12: FQ-227 — switch off exact ilvl bounds on Auctionator
    -- buy lists. The min=max ilvl constraint added in v0.13.0 (FQ-195)
    -- filters against the browse result's itemKey.itemLevel, which the
    -- client scales to the viewing character's level for level-scaling
    -- gear. On low-level buyer alts (the standard FP cross-realm setup)
    -- nearly every gear listing failed the exact match, so imported deals
    -- looked like they'd vanished from the AH even though a manual search
    -- found them. One-shot flip back to the pre-0.13 "any ilvl" behavior;
    -- players who want variant-exact matching can re-enable it from the
    -- Auctionator settings page.
    if db.schemaVersion < 12 then
        db.settings = db.settings or {}
        if db.settings.auctBuyListIncludeIlvl == true then
            db.settings.auctBuyListIncludeIlvl = false
            db._ilvlBoundsMigrationMessage =
                "Auctionator buy lists: the exact item-level match introduced in " ..
                "v0.13.0 could hide real listings on low-level characters (the AH " ..
                "shows scaled item levels), so it has been switched off. Re-enable " ..
                "it under Settings > Auctionator if you relied on it."
        end
        db.schemaVersion = 12
    end  -- migration 12
end  -- RunMigrations

-- Expose for DB.lua
ns._RunMigrations = RunMigrations
ns._CURRENT_SCHEMA = CURRENT_SCHEMA
