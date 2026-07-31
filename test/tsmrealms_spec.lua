-- test/tsmrealms_spec.lua
-- Headless coverage for TSMRealms' per-realm pricing lookup (FQ-230).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/tsmrealms_spec.lua
--
-- What this pins down: TSM's per-realm AuctionDB stores variant gear ONLY in
-- level form ("i:222::i100"), and the item level it records is whatever the
-- scanning client reported — which the auction house scales to the viewing
-- character. Our locally derived item level is therefore one guess among
-- several recorded buckets, and before FQ-230 a miss dropped the item to the
-- region-wide average on EVERY realm (the "same price on all realms" report).
-- The fixtures below mirror the real AppData shapes verified against a live
-- 40-realm TradeSkillMaster_AppHelper/AppData.lua.

dofile("test/wow_shim.lua")

--------------------------
-- Harness
--------------------------

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

-- GetDetailedItemLevelInfo is what ToLevelForm leans on. Tests drive it
-- directly to model both a correct resolve and the player-scaled miss.
local stubIlvl = nil
function GetDetailedItemLevelInfo(_) return stubIlvl end

local ns = {}
function ns:PrintDebug(_) end

local chunk = assert(loadfile("TSMRealms.lua"))
chunk("FlipQueue", ns)
local TSMRealms = ns.TSMRealms

--------------------------
-- Fixtures
--------------------------

-- Base-32 encoded values, as TSM ships them: A=10, K=20, U=30, 1=1, 2=2.
-- Fields are {itemString, minBuyout, numAuctions, marketValueRecent}, the
-- exact field list AUCTIONDB_NON_COMMODITY_DATA carries in the wild.
local function AppData(entries)
    return 'return {downloadTime=1784604337,fields={"itemString","minBuyout"' ..
        ',"numAuctions","marketValueRecent"},data={' .. entries .. '}}'
end

-- Alpha:   item 222 recorded at ilvl 100 AND 120, plus a base entry
-- Bravo:   item 222 recorded at ilvl 110 only, plus a base entry
-- Charlie: item 222 has a base entry only (no level form at all)
local FIXTURES = {
    { "Alpha",   AppData('{111,A,2,K},{"i:222::i100",A,1,A},{"i:222::i120",K,1,K},{222,U,3,U},{"p:1965",A,1,A}') },
    { "Bravo",   AppData('{111,K,2,K},{"i:222::i110",U,1,U},{222,A,3,A}') },
    { "Charlie", AppData('{111,U,2,U},{222,K,3,K}') },
}

for _, f in ipairs(FIXTURES) do
    TSM_APPHELPER_LOAD_DATA("AUCTIONDB_NON_COMMODITY_DATA", f[1], f[2])
end
-- Region-wide tags must be ignored — commodities are region-wide by design.
TSM_APPHELPER_LOAD_DATA("AUCTIONDB_NON_COMMODITY_DATA", "US", AppData('{999,A,1,A}'))
TSM_APPHELPER_LOAD_DATA("AUCTIONDB_COMMODITY_DATA", "Alpha", AppData('{888,A,1,A}'))

__testFireEvent(__testFrames[1], "PLAYER_LOGIN")

print("TSMRealms spec")
check("captured 3 realms (US and commodity data ignored)", #TSMRealms:GetRealmList(), 3)
check("is loaded", TSMRealms:IsLoaded(), true)

--------------------------
-- Batch path
--------------------------

local function batch(keys)
    TSMRealms:InvalidateCache()
    return TSMRealms:GetBatchPricing(keys)
end

local function src(res, key, realm)
    local perRealm = res[key]
    local entry = perRealm and perRealm[realm]
    return entry and entry.source or nil
end
local function minBuyout(res, key, realm)
    local perRealm = res[key]
    local entry = perRealm and perRealm[realm]
    return entry and entry.minBuyout or nil
end

-- 1. Plain item: matched by numeric ID on every realm, unchanged behaviour.
local r = batch({ "i:111" })
check("plain/Alpha source", src(r, "i:111", "Alpha"), "exact")
check("plain/Bravo source", src(r, "i:111", "Bravo"), "exact")
check("plain/Charlie value", minBuyout(r, "i:111", "Charlie"), 30)

-- 2. Variant gear, derived ilvl lands exactly on a recorded bucket (100).
--    Alpha matches exactly; Bravo has only ilvl 110 -> nearest; Charlie has
--    no level form at all -> base item. Before FQ-230, Bravo and Charlie
--    both returned nothing and fell to the region-wide average.
stubIlvl = 100
r = batch({ "i:222::2:1663" })
check("variant-exact/Alpha source", src(r, "i:222::2:1663", "Alpha"), "exact")
check("variant-exact/Alpha value", minBuyout(r, "i:222::2:1663", "Alpha"), 10)
check("variant-exact/Bravo source", src(r, "i:222::2:1663", "Bravo"), "nearestIlvl")
check("variant-exact/Bravo value", minBuyout(r, "i:222::2:1663", "Bravo"), 30)
check("variant-exact/Charlie source", src(r, "i:222::2:1663", "Charlie"), "baseItem")
check("variant-exact/Charlie value", minBuyout(r, "i:222::2:1663", "Charlie"), 20)

-- 3. Player-scaled miss: derived ilvl 115 exists on no realm. Alpha must
--    pick 120 (delta 5) over 100 (delta 15) — nearest, not first-seen.
--    (Each case uses its own bonus tail: ToLevelForm memoizes per item
--    string for the session, so reusing one key would reuse its ilvl.)
stubIlvl = 115
r = batch({ "i:222::2:1664" })
check("scaled-miss/Alpha source", src(r, "i:222::2:1664", "Alpha"), "nearestIlvl")
check("scaled-miss/Alpha picks ilvl 120", minBuyout(r, "i:222::2:1664", "Alpha"), 20)
check("scaled-miss/Bravo source", src(r, "i:222::2:1664", "Bravo"), "nearestIlvl")
check("scaled-miss/Charlie source", src(r, "i:222::2:1664", "Charlie"), "baseItem")

-- 4. Item level cannot be derived at all (item not in the client cache).
--    Every rung below "exact" must still produce a per-realm price.
stubIlvl = nil
r = batch({ "i:222::2:1665" })
check("no-ilvl/Alpha resolves", src(r, "i:222::2:1665", "Alpha"), "nearestIlvl")
check("no-ilvl/Bravo resolves", src(r, "i:222::2:1665", "Bravo"), "nearestIlvl")
check("no-ilvl/Charlie resolves", src(r, "i:222::2:1665", "Charlie"), "baseItem")

-- 5. Pets carry no base ID: exact match only, no fallback invented.
stubIlvl = 100
r = batch({ "p:1965" })
check("pet/Alpha source", src(r, "p:1965", "Alpha"), "exact")
check("pet/Bravo no fallback", src(r, "p:1965", "Bravo"), nil)

-- 6. Unknown item stays empty rather than borrowing another item's price.
r = batch({ "i:777::2:1663" })
check("unknown/Alpha empty", src(r, "i:777::2:1663", "Alpha"), nil)
check("unknown returns a table", type(r["i:777::2:1663"]), "table")

-- 7. Mixed pool in one call: every input keeps its own key and ladder.
r = batch({ "i:111", "i:222::2:1663", "p:1965" })
check("mixed/plain", src(r, "i:111", "Bravo"), "exact")
check("mixed/variant", src(r, "i:222::2:1663", "Alpha"), "exact")
check("mixed/pet", src(r, "p:1965", "Alpha"), "exact")

--------------------------
-- Non-batch path (GetAllRealmPricing) must climb the same ladder
--------------------------

stubIlvl = 115
TSMRealms:InvalidateCache()
local all = TSMRealms:GetAllRealmPricing("i:222::2:1666")
check("single/Alpha source", all.Alpha and all.Alpha.source, "nearestIlvl")
check("single/Alpha picks ilvl 120", all.Alpha and all.Alpha.minBuyout, 20)
check("single/Bravo source", all.Bravo and all.Bravo.source, "nearestIlvl")
check("single/Charlie source", all.Charlie and all.Charlie.source, "baseItem")

stubIlvl = 100
TSMRealms:InvalidateCache()
all = TSMRealms:GetAllRealmPricing("i:222::2:1667")
check("single-exact/Alpha source", all.Alpha and all.Alpha.source, "exact")

TSMRealms:InvalidateCache()
all = TSMRealms:GetAllRealmPricing("i:111")
check("single-plain/Charlie value", all.Charlie and all.Charlie.minBuyout, 30)

--------------------------
-- Diagnostic support
--------------------------

local levels = TSMRealms:GetRecordedItemLevels("222")
check("recorded ilvls count", #levels, 3)
check("recorded ilvls sorted", table.concat(levels, ","), "100,110,120")
check("plain item has no recorded ilvls", #TSMRealms:GetRecordedItemLevels("111"), 0)

--------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
