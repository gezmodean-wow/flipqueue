-- test/migration_fpsource_spec.lua
-- Headless coverage for schema migration 14 (FQ-177): the FlippingPal
-- price-source default flips from "listing" to "auto".
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/migration_fpsource_spec.lua
--
-- This one runs against every existing install exactly once and visibly
-- changes prices players have grown used to, so the things it must not do are
-- as important as the thing it must: it must not touch a player who
-- deliberately chose Sale Avg, must not re-fire on a DB that has already been
-- migrated, and must not flip silently. It also has to leave the earlier
-- migrations' work intact, since a fresh install runs the whole chain.

dofile("test/wow_shim.lua")

local passed, failed = 0, 0
local function check(label, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("  FAIL %s\n       got:  %s\n       want: %s",
            label, tostring(got), tostring(want)))
    end
end

local ns = {}
function ns:Print() end
function ns:PrintDebug() end
function ns:PrintError() end

local chunk = assert(loadfile("Migration.lua"))
chunk("FlipQueue", ns)
local RunMigrations = ns._RunMigrations

print("migration_fpsource spec")

check("schema constant is 14", ns._CURRENT_SCHEMA, 14)

--------------------------
-- The flip
--------------------------

-- An install sitting on the old default. This is the population the issue is
-- about: the setting existed since v0.13.0 but the default meant almost
-- nobody had it on anything else.
local db = { schemaVersion = 13, settings = { fpPriceSource = "listing" } }
RunMigrations(db)
check("listing is flipped to auto", db.settings.fpPriceSource, "auto")
check("schema advances to 14", db.schemaVersion, 14)
check("the flip announces itself", type(db._fpPriceSourceMigrationMessage), "string")
check("the notice names the way back",
    db._fpPriceSourceMigrationMessage:find("Settings > Imports", 1, true) ~= nil, true)

-- A setting that was never written at all reads the same as the old default,
-- because that is what DB.lua would have put there.
db = { schemaVersion = 13, settings = {} }
RunMigrations(db)
check("absent setting becomes auto", db.settings.fpPriceSource, "auto")
check("absent setting is announced too", type(db._fpPriceSourceMigrationMessage), "string")

-- Missing settings table entirely — a DB shape earlier migrations can produce.
db = { schemaVersion = 13 }
RunMigrations(db)
check("missing settings table is created", db.settings.fpPriceSource, "auto")

--------------------------
-- What it must leave alone
--------------------------

-- A deliberate choice. Sale Avg is the conservative column; someone who picked
-- it picked it, and overwriting that would be the addon second-guessing a
-- player who already solved this for themselves.
db = { schemaVersion = 13, settings = { fpPriceSource = "saleavg" } }
RunMigrations(db)
check("saleavg is preserved", db.settings.fpPriceSource, "saleavg")
check("preserved choice is not announced", db._fpPriceSourceMigrationMessage, nil)

-- Already on auto: nothing to say.
db = { schemaVersion = 13, settings = { fpPriceSource = "auto" } }
RunMigrations(db)
check("auto is left as-is", db.settings.fpPriceSource, "auto")
check("no notice when nothing changed", db._fpPriceSourceMigrationMessage, nil)

--------------------------
-- Idempotence
--------------------------

-- A player who switches back to Listing after the migration must keep that
-- choice. This is the failure that would make the setting useless: a migration
-- that re-fires overrides the player every login.
db = { schemaVersion = 14, settings = { fpPriceSource = "listing" } }
RunMigrations(db)
check("post-migration listing choice survives", db.settings.fpPriceSource, "listing")
check("no notice on an already-migrated db", db._fpPriceSourceMigrationMessage, nil)

-- Running the chain twice changes nothing the second time.
db = { schemaVersion = 13, settings = { fpPriceSource = "listing" } }
RunMigrations(db)
db._fpPriceSourceMigrationMessage = nil
RunMigrations(db)
check("second run is a no-op", db.settings.fpPriceSource, "auto")
check("second run stays quiet", db._fpPriceSourceMigrationMessage, nil)

--------------------------
-- Fresh install runs the whole chain
--------------------------

db = {}
RunMigrations(db)
check("fresh db lands on 14", db.schemaVersion, 14)
check("fresh db gets auto", db.settings.fpPriceSource, "auto")

-- Migration 12's flip still fires alongside 14 — the chain runs in order and
-- later entries must not shadow earlier ones.
db = { schemaVersion = 11, settings = { auctBuyListIncludeIlvl = true, fpPriceSource = "listing" } }
RunMigrations(db)
check("earlier migration still applies", db.settings.auctBuyListIncludeIlvl, false)
check("and 14 applies in the same pass", db.settings.fpPriceSource, "auto")
check("both notices are queued",
    (db._ilvlBoundsMigrationMessage ~= nil) and (db._fpPriceSourceMigrationMessage ~= nil), true)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
