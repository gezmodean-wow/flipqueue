-- test/tsmprofile_spec.lua
-- Headless coverage for TSM:GetProfileState / GetSelectedProfile (FQ-217).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/tsmprofile_spec.lua
--
-- FlipQueue lets the player pin a TSM profile. The pin outranked TSM's own
-- active profile unconditionally, and nothing revalidated it — so a profile
-- renamed or deleted inside TSM left FQ reading a table that no longer exists,
-- and the group tree rendered empty with nothing on screen naming the profile.
--
-- The interesting boundary is NOT "is the pin in the list". It's when we are
-- entitled to conclude it isn't: TradeSkillMasterDB is not populated at every
-- point FQ asks, and reading an empty profile list as "your profile is gone"
-- would throw away a perfectly good pin on a load-order accident.

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

local printed = {}
local ns = {
    COLORS = { YELLOW = "", RESET = "" },
    Print  = function(_, msg) printed[#printed + 1] = msg end,
}
assert(loadfile("TSM.lua"))("FlipQueue", ns)
local TSM = ns.TSM

ns.db = { settings = { tsmEnabled = true, tsmProfile = "" } }

-- Stand in for the two things GetProfileState reads out of TSM itself.
local profiles, activeProfile = {}, nil
function TSM:GetProfiles() return profiles end
function TSM:GetActiveProfile() return activeProfile end
function TSM:IsEnabled() return true end

--------------------------
-- No pin: follow TSM
--------------------------

profiles = { "Default", "CR Flipping" }
activeProfile = "CR Flipping"
ns.db.settings.tsmProfile = ""

local s = TSM:GetProfileState()
check("empty pin is no pin", s.pinned, nil)
check("effective is TSM's active profile", s.effective, "CR Flipping")
check("not stale", s.stale, false)
check("not diverged", s.diverged, false)
check("GetSelectedProfile agrees", TSM:GetSelectedProfile(), "CR Flipping")

--------------------------
-- A live pin is honoured, and named as divergent when it isn't TSM's
--------------------------

ns.db.settings.tsmProfile = "Default"
s = TSM:GetProfileState()
check("pin is reported", s.pinned, "Default")
check("pin wins over active", s.effective, "Default")
check("live pin is not stale", s.stale, false)
check("pin differing from active is diverged", s.diverged, true)

ns.db.settings.tsmProfile = "CR Flipping"
s = TSM:GetProfileState()
check("pin matching active is not diverged", s.diverged, false)
check("...and is still the effective profile", s.effective, "CR Flipping")

--------------------------
-- A dead pin falls back, once, loudly
--------------------------

ns.db.settings.tsmProfile = "Renamed Away"
s = TSM:GetProfileState()
check("missing pin is stale", s.stale, true)
check("stale pin falls back to active", s.effective, "CR Flipping")
check("a stale pin is not also 'diverged'", s.diverged, false)

printed = {}
check("GetSelectedProfile returns the fallback", TSM:GetSelectedProfile(), "CR Flipping")
check("and says so", #printed, 1)
check("naming the dead profile", printed[1]:find("Renamed Away", 1, true) ~= nil, true)

TSM:GetSelectedProfile()
check("but only once per session", #printed, 1)

--------------------------
-- An empty profile list proves nothing
--------------------------

-- This is the regression that matters: TSM present but its DB not yet readable.
-- Concluding "stale" here would drop the player's pin for the session.
profiles = {}
TSM._warnedStaleProfile = nil
ns.db.settings.tsmProfile = "CR Flipping"
s = TSM:GetProfileState()
check("no profile list -> no staleness conclusion", s.stale, false)
check("pin survives an unreadable profile list", s.effective, "CR Flipping")

printed = {}
TSM:GetSelectedProfile()
check("and nothing is printed at the player", #printed, 0)

--------------------------
-- No pin and no active profile
--------------------------

profiles = { "Default" }
activeProfile = nil
ns.db.settings.tsmProfile = ""
s = TSM:GetProfileState()
check("nothing to use", s.effective, nil)
check("nothing to diverge from", s.diverged, false)

--------------------------

print(string.format("tsmprofile_spec: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
