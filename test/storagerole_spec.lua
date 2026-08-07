-- test/storagerole_spec.lua
-- Headless coverage for the "storage" character role (FQ-245).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/storagerole_spec.lua
--
-- A storage character holds stock and never trades. Before this role the only
-- way to say "don't give this character work" was Hidden, which also took its
-- bags and bank out of the account's inventory — so FlipQueue would report an
-- item as nowhere on your account while it sat in the storage toon's bank.
--
-- The role therefore has to land on exactly one side of two different questions,
-- and getting either backwards reintroduces a bug the other way round:
--   * "does this character's stock count?"  -> YES (that is the whole point)
--   * "may this character be given work?"   -> NO
--
-- Every gate in the codebase is one of those two shapes, so this spec pins the
-- behaviour at the generator, where both questions are asked about every deal.

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

--------------------------
-- Namespace (same shim set the accounting spec uses)
--------------------------

local ns = { TodoList = {} }
ns.COLORS = setmetatable({}, {__index = function() return "" end})
function ns:Print() end
function ns:PrintDebug() end
function ns:GetCharKey() return "Seller-Sargeras" end
function ns:MakeItemKey(id, b, m) return tostring(id) .. ";" .. (b or "") .. ";" .. (m or "") end
function ns:ImportRemove() end
function ns:ResolveItemID(deal) return tonumber(deal.itemID) end
function ns:IsPhantomChar() return false end
function ns:IsDoNotTrack() return false end
function ns:IsWarboundUntilEquipped() return false end
function ns:ParseGoldValue(str) return tonumber((tostring(str or ""):gsub("[^%d]", ""))) or 0 end
function ns:ResolveFPPrice(deal) return deal.expectedPrice or "" end
function ns:NormalizeRealmKey(r) return (r or ""):lower() end
function ns:RealmMatches(a, b) return (a or "") == (b or "") end
function ns:RealmsOverlap(a, b) return self:RealmMatches(a, b) end
function ns:ItemsMatch(poolKey, poolName, deal, resolvedID)
    if deal.itemKey and deal.itemKey ~= "" and deal.itemKey == poolKey then return true end
    local poolID = tonumber((tostring(poolKey):gsub(";.*", "")))
    if resolvedID and poolID and resolvedID == poolID then return true end
    return false
end

assert(loadfile("TodoList.lua"))("FlipQueue", ns)
assert(loadfile("TodoGenerator.lua"))("FlipQueue", ns)
local TodoList = ns.TodoList

--------------------------
-- Fixture: a seller on Sargeras, a vault on Draenor
--------------------------

-- The vault holds the only copy of item 1001. A deal to sell it on Sargeras
-- must find the stock; a deal to sell it on Draenor — where the only character
-- IS the vault — must not become a task for the vault.
local function NewDB(deals, vaultRole)
    return {
        settings = {
            skipUnassigned = false, sellQtyMode = "none", defaultSellQty = 1,
            tsmSkipOnGenerate = false, debugMessages = false,
        },
        characters = {
            ["Seller-Sargeras"] = { role = "both", inventory = { items = {} } },
            ["Vault-Draenor"]   = {
                role = vaultRole,
                inventory = { items = {
                    ["1001;;"] = { itemID = 1001, name = "Thorium Helm", quantity = 3,
                                   locations = { bank = 3 } },
                } },
            },
        },
        warbank = { items = {}, freeSlots = 50 },
        imports = { fpScanner = deals },
        todoLists = { active = nil, upcoming = {} },
    }
end

local function D(itemID, name, realm)
    return { itemKey = itemID .. ";;", itemID = itemID, name = name,
             targetRealm = realm, expectedPrice = "100g", quantity = 1 }
end

local function Generate(deals, vaultRole)
    ns.db = NewDB(deals, vaultRole)
    local preview = TodoList:GenerateTodoList("fpScanner", {"gold"}, {})
    return preview, preview.accounting
end

--------------------------
-- The vault's stock counts
--------------------------

-- The deal lands in `deposits` rather than `tasks`: the stock is on another
-- character, so the generated work is "vault hands it over, seller posts it".
-- That routing is exactly what a storage character is for.
local preview, acct = Generate({ D(1001, "Thorium Helm", "Sargeras") }, "storage")
check("a deal for the seller's realm becomes work", acct.tasks + acct.deposits, 1)
check("...not 'you don't own it'", acct.notOwned, 0)
check("...and the vault's stock is what backs it", #preview.items, 1)
check("...with the SELLER assigned, not the vault",
    preview.items[1] and preview.items[1].assignedChar, "Seller-Sargeras")

-- The same fixture with the vault Hidden is the bug this role exists to fix:
-- the item is on the account, and FlipQueue can't see it.
local _, hiddenAcct = Generate({ D(1001, "Thorium Helm", "Sargeras") }, "none")
check("a hidden vault's stock does not count", hiddenAcct.notOwned, 1)
check("...so no task is made", hiddenAcct.tasks, 0)

-- And with the vault trading normally, nothing about the above changes.
local _, bothAcct = Generate({ D(1001, "Thorium Helm", "Sargeras") }, "both")
check("a trading vault backs the work too", bothAcct.tasks + bothAcct.deposits, 1)

--------------------------
-- The vault is never given work
--------------------------

-- Draenor's only character is the vault. A deal that wants a seller there has
-- no seller, and must be counted as such rather than assigned to the vault.
local _, drAcct = Generate({ D(1001, "Thorium Helm", "Draenor") }, "storage")
check("no seller on the vault's realm", drAcct.noCharacter + drAcct.unassigned, 1)
check("...so the vault gets no task", drAcct.tasks, 0)

-- Sanity: the same deal with the vault trading DOES produce a task, so the
-- assertion above is about the role and not about the fixture.
local _, drBoth = Generate({ D(1001, "Thorium Helm", "Draenor") }, "both")
check("a trading character on that realm does get the task", drBoth.tasks, 1)

-- A buy-only character is not a seller either — the same shape, already true
-- before this change, kept honest here because storage rides the same gate.
local _, drBuy = Generate({ D(1001, "Thorium Helm", "Draenor") }, "buy")
check("a buy-only character is not given a sell task", drBuy.tasks, 0)

--------------------------
-- "No character there" vs "nobody there may sell" (FQ-248)
--------------------------

-- A player whose bank alts are all Buy Only gets no tasks at all, and the only
-- explanation FlipQueue had was "no character on that realm" — about realms he
-- is standing on. That reads as a broken addon rather than a role to change.

local _, buyOnly = Generate({ D(1001, "Thorium Helm", "Draenor") }, "buy")
check("a buy-only character on the realm is flagged as noSeller", buyOnly.noSeller, 1)
check("...and the realm is named", buyOnly.noSellerRealms["Draenor"], 1)

local _, storageOnly = Generate({ D(1001, "Thorium Helm", "Draenor") }, "storage")
check("a storage character counts as noSeller too", storageOnly.noSeller, 1)

-- Hidden is different: the player has said to ignore that character, so
-- "no character on that realm" is the honest answer and noSeller must stay 0.
local _, hidden = Generate({ D(1001, "Thorium Helm", "Draenor") }, "none")
check("a hidden character does not make it a role problem", hidden.noSeller, 0)

-- A realm with nobody on it at all is likewise not a role problem.
local _, elsewhere = Generate({ D(1001, "Thorium Helm", "Ravencrest") }, "storage")
check("an unknown realm is not noSeller", elsewhere.noSeller, 0)
check("...and no realm is named", next(elsewhere.noSellerRealms), nil)

-- And a seller on the realm produces no flag at all.
local _, seller = Generate({ D(1001, "Thorium Helm", "Draenor") }, "both")
check("a seller on the realm clears the flag", seller.noSeller, 0)

--------------------------
-- Arithmetic still closes
--------------------------

local function SumBuckets(a)
    return a.tasks + a.deposits + a.unassigned + a.noCharacter + a.notOwned
        + a.noStock + a.tsmRejected + a.warbankFull + a.noQuantity
        + a.flipSkipped + a.other
end

local _, mixed = Generate({
    D(1001, "Thorium Helm", "Sargeras"),
    D(1001, "Thorium Helm", "Draenor"),
    D(2002, "Unowned Thing", "Sargeras"),
}, "storage")
check("every deal is accounted for", SumBuckets(mixed), mixed.total)
check("three deals in", mixed.total, 3)

-- noSeller re-describes deals the sum already counts, so it must NOT be added
-- to it. This is the assertion that stops someone "completing" the bucket list
-- later and quietly making the arithmetic lie.
local _, roleMixed = Generate({
    D(1001, "Thorium Helm", "Sargeras"),
    D(1001, "Thorium Helm", "Draenor"),
}, "buy")
check("noSeller is a breakdown, not a bucket", SumBuckets(roleMixed), roleMixed.total)
check("...and it still counted the role case", roleMixed.noSeller, 1)

print(string.format("storagerole_spec: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
