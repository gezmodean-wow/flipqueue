-- test/import_dedup_spec.lua
-- Headless coverage for the connected-realm dedup index (FQ-242).
-- Run from the repo root:  lua test/import_dedup_spec.lua
--
-- Loads the REAL Core.lua (RealmsOverlap, MakeImportKey, NormalizeAccents) and
-- the REAL Import.lua against the WoW shim — no copied helpers, so the spec
-- can't drift from the implementation the way a transcribed copy would.
--
-- Two things are pinned here:
--
--   1. SEMANTICS. The pre-fix O(N^2) loop is reproduced verbatim below as
--      ReferenceSave and used as the oracle. The index must classify every
--      item the same way and produce the same stored map.
--   2. COST. The oracle also counts its RealmsOverlap calls, so the
--      complexity assertion is non-vacuous by construction: the same fixture
--      demonstrates the quadratic blow-up it is guarding against.

local scriptPath = arg and arg[0] or "test/import_dedup_spec.lua"
local scriptDir = scriptPath:match("^(.*[/\\])") or "./"
local repoRoot = scriptDir .. ".." .. "/"

dofile(scriptDir .. "wow_shim.lua")

----------------------------------------------------------------------
-- Load the real modules
----------------------------------------------------------------------
local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "" end })
function ns:PrintDebug() end
function ns:Print() end
function ns:PrintError() end

assert(loadfile(repoRoot .. "Core.lua"))("FlipQueue", ns)
assert(type(ns.RealmsOverlap) == "function", "Core.lua did not define RealmsOverlap")
assert(type(ns.MakeImportKey) == "function", "Core.lua did not define MakeImportKey")

assert(loadfile(repoRoot .. "Import.lua"))("FlipQueue", ns)
local Import = ns.Import
assert(Import, "Import namespace not populated")

ns.db = { imports = {}, settings = {} }

----------------------------------------------------------------------
-- Tiny assert harness
----------------------------------------------------------------------
local passed, failed = 0, 0
local function check(label, got, want)
    if got == want then
        passed = passed + 1
        print("  ok   " .. label)
    else
        failed = failed + 1
        print("  FAIL " .. label .. "\n         got:  " .. tostring(got)
            .. "\n         want: " .. tostring(want))
    end
end
local function ok(label, cond) check(label, not not cond, true) end

----------------------------------------------------------------------
-- Realm fixture
--
-- Four non-overlapping connected-realm clusters, shaped like FlippingPal's
-- output. Sargeras is deliberately absent from every multi-realm string so
-- Save's single-realm cluster expansion is a no-op on this fixture and the
-- oracle doesn't have to reproduce it.
----------------------------------------------------------------------
local CLUSTERS = {
    "Aegwynn, Gurubashi, Bonechewer",
    "Eonar, Skullcrusher, Zuluhed, Ursin",
    "Alexstrasza, Terokkar",
    "Sargeras",
}

ns.REALM_LOOKUP = {}
for gid, cluster in ipairs(CLUSTERS) do
    for name in cluster:gmatch("([^,]+)") do
        ns.REALM_LOOKUP[ns:NormalizeRealmKey(strtrim(name))] = gid
    end
end

----------------------------------------------------------------------
-- The pre-fix dedup loop, kept verbatim as the oracle
----------------------------------------------------------------------
local overlapCalls = 0
local realOverlap = ns.RealmsOverlap
function ns:RealmsOverlap(a, b)
    overlapCalls = overlapCalls + 1
    return realOverlap(ns, a, b)
end

-- The quadratic cost was never the RealmsOverlap calls — those sit behind the
-- key/name arm and are comparatively rare. It was the walk itself: one
-- `existItem.name:lower()` allocation for every (new item, stored entry)
-- pair. Counting string.lower is therefore the measurement that actually
-- tracks the defect. `s:lower()` dispatches through the string metatable to
-- this field, so replacing it counts both call styles.
local lowerCalls = 0
local realLower = string.lower
string.lower = function(s)
    lowerCalls = lowerCalls + 1
    return realLower(s)
end

local function ReferenceSave(items)
    local srcMap, added, deduped = {}, 0, 0
    for _, item in ipairs(items) do
        local key = ns:MakeImportKey(item.itemKey, item.name, item.targetRealm, item.ilvl)
        local existing = srcMap[key]
        if existing then
            if item.expectedPrice and item.expectedPrice ~= "" then
                existing.expectedPrice = item.expectedPrice
            end
            if #(item.targetRealm or "") > #(existing.targetRealm or "") then
                existing.targetRealm = item.targetRealm
            end
            deduped = deduped + 1
        else
            local isDuplicate = false
            local itemName = (item.name or ""):lower()
            for _, existItem in pairs(srcMap) do
                local keyMatch = existItem.itemKey == item.itemKey
                local nameMatch = itemName ~= "" and existItem.name
                    and existItem.name:lower() == itemName
                local ilvlConflict = (item.ilvl or 0) > 0 and (existItem.ilvl or 0) > 0
                    and item.ilvl ~= existItem.ilvl
                if (keyMatch or nameMatch) and not ilvlConflict
                    and ns:RealmsOverlap(existItem.targetRealm, item.targetRealm) then
                    if item.expectedPrice and item.expectedPrice ~= "" then
                        existItem.expectedPrice = item.expectedPrice
                    end
                    if #(item.targetRealm or "") > #(existItem.targetRealm or "") then
                        existItem.targetRealm = item.targetRealm
                    end
                    isDuplicate = true
                    deduped = deduped + 1
                    break
                end
            end
            if not isDuplicate then
                srcMap[key] = {
                    itemKey = item.itemKey,
                    name = item.name or "",
                    ilvl = item.ilvl or 0,
                    targetRealm = item.targetRealm,
                    expectedPrice = item.expectedPrice,
                }
                added = added + 1
            end
        end
    end
    return srcMap, added, deduped
end

----------------------------------------------------------------------
-- Fixture generator — FlippingPal-shaped: the same item repeated across
-- clusters, which is exactly the population that arms the name comparison.
----------------------------------------------------------------------
local function BuildBatch(itemCount)
    local items = {}
    for i = 1, itemCount do
        local id = 1000 + i
        for c = 1, #CLUSTERS do
            items[#items + 1] = {
                itemKey = id .. ";;",
                itemID = tostring(id),
                name = "Fixture Item " .. i,
                ilvl = 0,
                targetRealm = CLUSTERS[c],
                expectedPrice = tostring(100 * i + c) .. "g",
            }
        end
    end
    return items
end

local function Copy(items)
    local out = {}
    for i, item in ipairs(items) do
        local t = {}
        for k, v in pairs(item) do t[k] = v end
        out[i] = t
    end
    return out
end

local function MapSignature(srcMap)
    local keys = {}
    for k, v in pairs(srcMap) do
        keys[#keys + 1] = k .. "|" .. (v.targetRealm or "") .. "|" .. (v.expectedPrice or "")
    end
    table.sort(keys)
    return table.concat(keys, "\n"), #keys
end

----------------------------------------------------------------------
print("Import dedup index spec (FQ-242)")

----------------------------------------------------------------------
print("\n-- matches the pre-fix loop, item for item")
----------------------------------------------------------------------
do
    local batch = BuildBatch(40)

    overlapCalls = 0
    local refMap, refAdded, refDeduped = ReferenceSave(Copy(batch))
    local refCalls = overlapCalls
    local refSig, refCount = MapSignature(refMap)

    ns.db.imports = {}
    overlapCalls = 0
    local added = Import:Save(Copy(batch), "spec")
    local newCalls = overlapCalls
    local newSig, newCount = MapSignature(ns.db.imports.spec)

    check("added count matches the oracle", added, refAdded)
    check("stored deal count matches the oracle", newCount, refCount)
    check("stored map matches the oracle exactly", newSig, refSig)
    check("every cluster survived as its own deal", refAdded, 40 * #CLUSTERS)
    check("nothing was merged away on non-overlapping clusters", refDeduped, 0)
    print(("    (%d RealmsOverlap calls before, %d after)"):format(refCalls, newCalls))
end

----------------------------------------------------------------------
print("\n-- merges connected-realm duplicates the same way")
----------------------------------------------------------------------
do
    -- Each item appears twice per cluster: once naming the whole cluster,
    -- once naming a single realm inside it. The second must merge into the
    -- first. (Both spellings are present in real FlippingPal exports.)
    local batch = {}
    for i = 1, 25 do
        for c = 1, #CLUSTERS do
            local first = CLUSTERS[c]:match("^([^,]+)")
            batch[#batch + 1] = {
                itemKey = (2000 + i) .. ";;", name = "Dupe Item " .. i, ilvl = 0,
                targetRealm = CLUSTERS[c], expectedPrice = "500g",
            }
            batch[#batch + 1] = {
                itemKey = (2000 + i) .. ";;", name = "Dupe Item " .. i, ilvl = 0,
                targetRealm = first, expectedPrice = "600g",
            }
        end
    end

    local refMap, refAdded, refDeduped = ReferenceSave(Copy(batch))
    local refSig = MapSignature(refMap)

    ns.db.imports = {}
    local added = Import:Save(Copy(batch), "spec")
    local newSig = MapSignature(ns.db.imports.spec)

    check("merged-batch added count matches", added, refAdded)
    check("merged-batch map matches", newSig, refSig)
    check("half the rows merged away", refDeduped, 25 * #CLUSTERS)
    ok("freshest price won the merge", newSig:find("600g", 1, true) ~= nil)
end

----------------------------------------------------------------------
print("\n-- item level still separates variants")
----------------------------------------------------------------------
do
    local batch = {}
    for _, ilvl in ipairs({ 30, 52, 0 }) do
        batch[#batch + 1] = {
            itemKey = "3000;;", name = "Variant Gear", ilvl = ilvl,
            targetRealm = CLUSTERS[1], expectedPrice = "900g",
        }
    end

    local _, refAdded = ReferenceSave(Copy(batch))
    ns.db.imports = {}
    local added = Import:Save(Copy(batch), "spec")

    check("two graded variants stay distinct", refAdded, 2)
    check("index agrees on variant separation", added, refAdded)
end

----------------------------------------------------------------------
print("\n-- differently-keyed rows still dedup by name")
----------------------------------------------------------------------
do
    -- FlippingPal exports the same item under different bonus-ID keys; the
    -- name arm is what merges those.
    local batch = {
        { itemKey = "4000;;",     name = "Renamed Thing", ilvl = 0, targetRealm = CLUSTERS[2], expectedPrice = "4g" },
        { itemKey = "4000;6652;", name = "Renamed Thing", ilvl = 0, targetRealm = "Ursin",     expectedPrice = "5g" },
        { itemKey = "4001;;",     name = "Other Thing",   ilvl = 0, targetRealm = CLUSTERS[2], expectedPrice = "6g" },
    }

    local refMap, refAdded = ReferenceSave(Copy(batch))
    local refSig = MapSignature(refMap)

    ns.db.imports = {}
    local added = Import:Save(Copy(batch), "spec")
    local newSig = MapSignature(ns.db.imports.spec)

    check("name-matched rows merge across bonus keys", added, refAdded)
    check("renamed-key map matches the oracle", newSig, refSig)
    check("two distinct deals survive", refAdded, 2)
end

----------------------------------------------------------------------
print("\n-- keyless rows no longer collapse into each other (FQ-243)")
----------------------------------------------------------------------
do
    -- DELIBERATE DIVERGENCE from the oracle. The old loop read `nil == nil`
    -- and `"" == ""` as "same item", so two unrelated keyless deals on
    -- overlapping realms merged and one was lost. Name is the only evidence
    -- of identity these rows carry, so name alone is what may merge them.
    local batch = {
        { itemKey = nil, name = "Elekk Plushie", ilvl = 0, targetRealm = CLUSTERS[1], expectedPrice = "1g" },
        { itemKey = nil, name = "Elekk Plushie", ilvl = 0, targetRealm = "Gurubashi",  expectedPrice = "2g" },
        { itemKey = nil, name = "Worg Pup",      ilvl = 0, targetRealm = CLUSTERS[1], expectedPrice = "3g" },
        { itemKey = "",  name = "Copper Bar",    ilvl = 0, targetRealm = CLUSTERS[1], expectedPrice = "4g" },
    }

    local refMap, refAdded = ReferenceSave(Copy(batch))
    local refSig = MapSignature(refMap)

    ns.db.imports = {}
    local added = Import:Save(Copy(batch), "spec")
    local newSig = MapSignature(ns.db.imports.spec)

    check("the old loop lost one of the four rows", refAdded, 2)
    ok("Worg Pup was the casualty — merged into Elekk Plushie",
        refSig:find("worg pup", 1, true) == nil)
    check("each distinct keyless item now survives", added, 3)
    ok("Worg Pup survives the index", newSig:find("worg pup", 1, true) ~= nil)
    ok("the repeated keyless item still merged by name", added < 4)
end

----------------------------------------------------------------------
print("\n-- MakeImportKey falls back to the name on an empty key (FQ-243)")
----------------------------------------------------------------------
do
    -- `"" or itemName` yields "" in Lua, so every keyless row derived the
    -- same key and Save's exact-key branch merged them before the dedup
    -- loop was ever consulted.
    local a = ns:MakeImportKey("", "Copper Bar", "", 0)
    local b = ns:MakeImportKey("", "Silver Bar", "", 0)
    local c = ns:MakeImportKey(nil, "Copper Bar", "", 0)

    ok("an empty key does not produce a nameless key", a ~= "|")
    ok("two different keyless items get different keys", a ~= b)
    check("empty and nil keys agree", a, c)
    check("a real key still wins over the name",
        ns:MakeImportKey("1234;;", "Copper Bar", "", 0), "1234;;|")
end

----------------------------------------------------------------------
print("\n-- a PBS/Auctionator list survives import intact (FQ-243)")
----------------------------------------------------------------------
do
    -- ParsePBS emits itemKey = "" and no targetRealm for every row, and
    -- RealmsOverlap("", "") is true, so every row looked like every other
    -- row. The oracle below runs the old dedup loop against today's fixed
    -- MakeImportKey and still collapses the list; before the key fix it
    -- collapsed at the exact-key branch instead, one deal per item level.
    local batch = {}
    for i = 1, 30 do
        batch[#batch + 1] = {
            itemKey = "", itemID = "", name = "Snipe Target " .. i,
            ilvl = (i % 3) * 10, quantity = 1,
        }
    end

    local _, refAdded = ReferenceSave(Copy(batch))
    ns.db.imports = {}
    local added = Import:Save(Copy(batch), "spec")

    check("the old loop kept 2 of the 30 rows", refAdded, 2)
    check("the whole list now survives", added, 30)
end

----------------------------------------------------------------------
print("\n-- PreviewAdd classifies identically to Save")
----------------------------------------------------------------------
do
    local batch = BuildBatch(15)
    -- Append an exact repeat of the first row and a connected-realm repeat
    batch[#batch + 1] = { itemKey = "1001;;", name = "Fixture Item 1", ilvl = 0,
        targetRealm = CLUSTERS[1], expectedPrice = "1g" }
    batch[#batch + 1] = { itemKey = "1001;;", name = "Fixture Item 1", ilvl = 0,
        targetRealm = "Bonechewer", expectedPrice = "2g" }

    local results = Import:PreviewAdd(Copy(batch))
    local newCount, dupeCount = 0, 0
    for _, r in ipairs(results) do
        if r._importStatus == "duplicate" then dupeCount = dupeCount + 1 else newCount = newCount + 1 end
    end

    ns.db.imports = {}
    local added = Import:Save(Copy(batch), "spec")

    check("preview result count == input count", #results, #batch)
    check("preview 'new' count == Save's added count", newCount, added)
    check("preview flagged both repeats as duplicates", dupeCount, 2)
    ok("exact repeat reports the same-realm reason",
        results[#results - 1]._dupeReason == "same item & realm in paste")
    ok("connected repeat reports the connected-realm reason",
        (results[#results]._dupeReason or ""):find("connected realm", 1, true) ~= nil)
end

----------------------------------------------------------------------
print("\n-- chunked paths agree with their synchronous twins")
----------------------------------------------------------------------
do
    -- The shim runs C_Timer.After inline, so the chunked walk completes
    -- before these calls return.
    local batch = BuildBatch(20)

    ns.db.imports = {}
    local syncAdded = Import:Save(Copy(batch), "spec")
    local syncSig = MapSignature(ns.db.imports.spec)

    ns.db.imports = {}
    local chunkedAdded, chunkedDone = nil, false
    Import:SaveChunked(Copy(batch), "spec", 7, nil, function(n)
        chunkedAdded = n
        chunkedDone = true
    end)
    local chunkedSig = MapSignature(ns.db.imports.spec)

    ok("SaveChunked completed", chunkedDone)
    check("SaveChunked added count == Save", chunkedAdded, syncAdded)
    check("SaveChunked map == Save", chunkedSig, syncSig)

    local syncPreview = Import:PreviewAdd(Copy(batch))
    local chunkedPreview
    Import:PreviewAddChunked(Copy(batch), nil, 7, nil, function(r) chunkedPreview = r end)
    check("PreviewAddChunked result count == PreviewAdd", #(chunkedPreview or {}), #syncPreview)

    local mismatched = 0
    for i, r in ipairs(syncPreview) do
        if (chunkedPreview[i] or {})._importStatus ~= r._importStatus then
            mismatched = mismatched + 1
        end
    end
    check("PreviewAddChunked statuses match item for item", mismatched, 0)
end

----------------------------------------------------------------------
print("\n-- dedup cost is linear, not quadratic")
----------------------------------------------------------------------
do
    -- The oracle's call counts in the same run are what make this
    -- non-vacuous: if the index regressed to a full scan, the "after"
    -- numbers would track the "before" ones instead of staying flat.
    local function Measure(itemCount)
        local batch = BuildBatch(itemCount)

        lowerCalls, overlapCalls = 0, 0
        ReferenceSave(Copy(batch))
        local before, beforeOverlap = lowerCalls, overlapCalls

        ns.db.imports = {}
        lowerCalls, overlapCalls = 0, 0
        Import:Save(Copy(batch), "spec")
        local after, afterOverlap = lowerCalls, overlapCalls

        return before, after, #batch, beforeOverlap, afterOverlap
    end

    local before1, after1, rows1 = Measure(100)
    local before2, after2, rows2, beforeOverlap2, afterOverlap2 = Measure(200)

    print(("    %d rows: %d -> %d string comparisons"):format(rows1, before1, after1))
    print(("    %d rows: %d -> %d string comparisons"):format(rows2, before2, after2))
    print(("    %d rows: %d -> %d RealmsOverlap calls")
        :format(rows2, beforeOverlap2, afterOverlap2))

    -- Each row can only collide with the clusters already stored for its own
    -- item, so the index does a bounded number of tests per row.
    ok("index stays within #CLUSTERS overlap tests per row",
        afterOverlap2 <= rows2 * #CLUSTERS)
    ok("doubling the input roughly doubles the index's work",
        after2 <= after1 * 3)
    ok("the old loop was superlinear on the same fixture",
        before2 >= before1 * 3)
    ok("index does an order of magnitude less work at 800 rows",
        after2 * 10 <= before2)
end

----------------------------------------------------------------------
print("\n-- RealmsOverlap caching preserves its answers")
----------------------------------------------------------------------
do
    local cases = {
        { "Aegwynn, Gurubashi, Bonechewer", "Gurubashi",                      true  },
        { "Gurubashi",                      "Aegwynn, Gurubashi, Bonechewer", true  },
        { "Aegwynn, Gurubashi",             "Eonar, Ursin",                   false },
        { "Sargeras",                       "Sargeras",                       true  },
        { "",                               "",                               true  },
        { "",                               "Sargeras",                       false },
        { "Sargeras",                       "",                               false },
        -- Degenerate strings yield no usable names, so they match nothing —
        -- including themselves. The identical-string fast path must not
        -- shortcut past that.
        { "ab",                             "ab",                             false },
        { "...",                            "...",                            false },
        { "ab",                             "Sargeras",                       false },
    }
    for _, case in ipairs(cases) do
        local r1, r2, want = case[1], case[2], case[3]
        local label = ("overlap(%q, %q)"):format(r1, r2)
        check(label, realOverlap(ns, r1, r2), want)
        -- Second call comes off the cache and must agree
        check(label .. " [cached]", realOverlap(ns, r1, r2), want)
    end

    -- Accent-insensitive matching still works through the normalization cache
    check("accented realm matches its ASCII spelling",
        realOverlap(ns, "Confr\195\169rie du Thorium", "Confrerie du Thorium"), true)

    -- Swapping REALM_LOOKUP (RealmData.lua does this once the region resolves)
    -- must drop cached group IDs.
    local saved = ns.REALM_LOOKUP
    ns.REALM_LOOKUP = { ["realmone"] = 99, ["realmtwo"] = 99 }
    check("group match via the fresh lookup", realOverlap(ns, "RealmOne", "RealmTwo"), true)
    ns.REALM_LOOKUP = {}
    check("group match gone after the lookup is swapped",
        realOverlap(ns, "RealmOne", "RealmTwo"), false)
    ns.REALM_LOOKUP = saved
end

----------------------------------------------------------------------
print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
