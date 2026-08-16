-- test/dealfinderpriority_spec.lua
-- Headless coverage for Deal Finder realm prioritization (FQ-252).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/dealfinderpriority_spec.lua
--
-- The reported symptom: a player dragged "no competition" to the top of the
-- priority list and Deal Finder still recommended a realm that had
-- competition. The cause was a scale mismatch rather than a logic error --
-- weights fall 100x per priority level, which only orders the criteria if
-- every criterion contributes a comparable amount, and only noCompetition
-- did. profit contributed gold and population contributed an auction count,
-- both unbounded, so a SECOND-ranked criterion routinely beat a FIRST-ranked
-- binary flag. The tipping point was 101g of profit.
--
-- What these pin: a binary criterion at the top is a hard gate no lower
-- priority can overturn, continuous criteria still rank sensibly, and the
-- tie-breaking order is the one the player configured.

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
ns.db = { settings = {}, characters = {} }
function ns:PrintDebug() end
function ns:Print() end

local chunk = assert(loadfile("DealFinder.lua"))
chunk("FlipQueue", ns)
local DF = ns.DealFinder

local function gold(g) return g * 10000 end

-- Rank a set of realm options and return the name of the auto-selected one.
local function pick(realms, order)
    local group = { realms = realms }
    DF:ApplyPriority({ group }, order)
    return group.realms[group.selectedRealm].realmName
end

print("dealfinderpriority spec")

--------------------------
-- The reported bug
--------------------------

-- "No competition" first, profit second. The quiet realm must win however
-- much more the busy one pays -- that is what putting it first means.
local quiet = { realmName = "Quiet",  noCompetition = true,  numAuctions = 0,   profit = gold(200) }
local busy  = { realmName = "Busy",   noCompetition = false, numAuctions = 40,  profit = gold(5000) }
check("noComp first beats a richer competing realm",
    pick({ quiet, busy }, { "noCompetition", "profit" }), "Quiet")

-- The old tipping point was 101g. Sweep well past it.
for _, g in ipairs({ 101, 500, 5000, 500000 }) do
    local rich = { realmName = "Rich", noCompetition = false, numAuctions = 12, profit = gold(g) }
    local calm = { realmName = "Calm", noCompetition = true,  numAuctions = 0,  profit = 0 }
    check("noComp holds against " .. g .. "g of profit",
        pick({ calm, rich }, { "noCompetition", "profit" }), "Calm")
end

-- Population ranked below noCompetition was the same defect with a different
-- unbounded term: 500 listings scored 5x the flag.
local popular = { realmName = "Popular", noCompetition = false, numAuctions = 500, profit = gold(10) }
local empty   = { realmName = "Empty",   noCompetition = true,  numAuctions = 0,   profit = gold(10) }
check("noComp holds against a busy realm's population",
    pick({ empty, popular }, { "noCompetition", "population" }), "Empty")

-- Sales count likewise.
local sold = { realmName = "Sold", noCompetition = false, numAuctions = 5, personalCount = 40, profit = 0 }
local none = { realmName = "None", noCompetition = true,  numAuctions = 0, personalCount = 0,  profit = 0 }
check("noComp holds against a long sales history",
    pick({ none, sold }, { "noCompetition", "previousSales" }), "None")

--------------------------
-- The default order still behaves
--------------------------

-- Profit first: the richer realm wins even though the other has no
-- competition. Putting profit first has to still mean profit first.
local poorQuiet = { realmName = "PoorQuiet", noCompetition = true,  numAuctions = 0,  profit = gold(100) }
local richBusy  = { realmName = "RichBusy",  noCompetition = false, numAuctions = 30, profit = gold(9000) }
check("profit first still prefers the richer realm",
    pick({ poorQuiet, richBusy }, { "profit", "noCompetition" }), "RichBusy")

-- Tied on profit, competition breaks it.
local aTie = { realmName = "TieBusy",  noCompetition = false, numAuctions = 20, profit = gold(1000) }
local bTie = { realmName = "TieQuiet", noCompetition = true,  numAuctions = 0,  profit = gold(1000) }
check("equal profit falls through to the second criterion",
    pick({ aTie, bTie }, { "profit", "noCompetition" }), "TieQuiet")

-- Ranking is strictly lexicographic, and that cuts both ways: with a
-- continuous criterion on top, even a small edge settles it. "Rank by profit"
-- means the most profitable realm, not a blend -- a player who wants
-- competition to carry weight puts competition first.
local hair = { realmName = "HairMore", noCompetition = false, numAuctions = 15, profit = gold(10050) }
local calm2 = { realmName = "Calm2",   noCompetition = true,  numAuctions = 0,  profit = gold(10000) }
check("a small profit edge still wins when profit is first",
    pick({ calm2, hair }, { "profit", "noCompetition" }), "HairMore")

local lots = { realmName = "Lots", noCompetition = false, numAuctions = 15, profit = gold(20000) }
local calm3 = { realmName = "Calm3", noCompetition = true, numAuctions = 0,  profit = gold(10000) }
check("a large profit edge wins at top priority",
    pick({ calm3, lots }, { "profit", "noCompetition" }), "Lots")

-- Three tiers deep: tied on the first two, the third decides. Proves the
-- lower weights are still live rather than being swamped.
local t1 = { realmName = "ThirdA", noCompetition = true, numAuctions = 3,  personalCount = 1, profit = gold(500) }
local t2 = { realmName = "ThirdB", noCompetition = true, numAuctions = 90, personalCount = 1, profit = gold(500) }
check("the third priority decides when the first two tie",
    pick({ t1, t2 }, { "profit", "noCompetition", "population" }), "ThirdB")

--------------------------
-- Population: unknown vs known-zero
--------------------------

-- nil numAuctions is the regional fallback: we do not know this realm's
-- listings. It must sort below a realm we know has none, which is strictly
-- better information.
local unknown = { realmName = "Unknown", numAuctions = nil, profit = gold(100) }
local knownZero = { realmName = "KnownZero", numAuctions = 0, profit = gold(100) }
check("a known-empty realm outranks an unknown one",
    pick({ unknown, knownZero }, { "population" }), "KnownZero")
local knownMany = { realmName = "KnownMany", numAuctions = 80, profit = gold(100) }
check("more listings outrank fewer",
    pick({ knownZero, knownMany }, { "population" }), "KnownMany")

--------------------------
-- Outliers
--------------------------

ns.db.settings.dfIgnoreOutliers = true
local outlier = { realmName = "Outlier", noCompetition = true, numAuctions = 0, profit = gold(99999), isOutlier = true }
local plain   = { realmName = "Plain",   noCompetition = false, numAuctions = 9, profit = gold(100) }
check("an excluded outlier is not auto-selected",
    pick({ outlier, plain }, { "profit" }), "Plain")
check("excluded outliers score below every real score",
    DF:ScoreRealm(outlier, { "profit" }, DF:BuildScoreNorms({ outlier, plain })) < 0, true)

ns.db.settings.dfIgnoreOutliers = false
check("a tolerated outlier is only penalized, not removed",
    pick({ outlier, plain }, { "profit" }), "Outlier")
ns.db.settings.dfIgnoreOutliers = nil

--------------------------
-- Normalization is per item
--------------------------

-- A cheap item's best realm must score as well as an expensive item's best
-- realm; ranking is within one item, never across items.
local cheap = DF:BuildScoreNorms({ { profit = gold(10) }, { profit = gold(5) } })
local dear  = DF:BuildScoreNorms({ { profit = gold(90000) }, { profit = gold(1000) } })
check("cheap item's best scores like the dear item's best",
    DF:ScoreRealm({ profit = gold(10) }, { "profit" }, cheap),
    DF:ScoreRealm({ profit = gold(90000) }, { "profit" }, dear))

-- All-losses item: the least-bad realm still wins rather than everything
-- collapsing to a tie.
local badA = { realmName = "LessBad", profit = -gold(10) }
local badB = { realmName = "MoreBad", profit = -gold(900) }
check("all-negative profits still rank the least-bad first",
    pick({ badB, badA }, { "profit" }), "LessBad")

--------------------------
-- Posted-realm avoidance still layers on top
--------------------------

ns.db.settings.dfAvoidPostedRealms = true
local posted = { realmName = "Posted", noCompetition = true, numAuctions = 0, profit = gold(5000), hasActiveAuction = true }
local clean  = { realmName = "Clean",  noCompetition = true, numAuctions = 0, profit = gold(100) }
check("a realm already posted on is demoted",
    pick({ posted, clean }, { "profit" }), "Clean")

local group = { realms = { posted } }
DF:ApplyPriority({ group }, { "profit" })
check("all-posted falls back rather than dropping the deal",
    group.realms[group.selectedRealm].realmName, "Posted")
check("and the group is flagged as such", group.selectedPosted, true)
ns.db.settings.dfAvoidPostedRealms = nil

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
