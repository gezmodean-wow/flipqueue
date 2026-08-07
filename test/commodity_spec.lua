-- test/commodity_spec.lua
-- Headless coverage for ns:IsCommodity and ns:FilterPoolCommodities (FQ-235).
--
-- Run from the repo root with stock Lua 5.1:
--   "C:\Program Files (x86)\Lua\5.1\lua.exe" test/commodity_spec.lua
--
-- Deal Finder was offering commodities as cross-realm deals. Commodities trade
-- on a region-wide auction house, so every realm quotes the same price and the
-- "deal" is an invitation to mail ore across the account for nothing.
--
-- The part worth testing is not "does it filter" but WHEN it is allowed to
-- decide. C_AuctionHouse.GetItemCommodityStatus answers Unknown until the
-- client has loaded that item's AH data, which for a player who hasn't opened
-- the auction house this session is every item. A filter that pins an Unknown
-- answer into a session cache hides real deals for the rest of the session and
-- says nothing — the exact failure shape the issue is about, inverted.

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
-- Stubs
--------------------------

Enum = { ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 } }

-- Per-item answers the "client" currently has. Absent = Unknown.
local ahStatus = {}
local stackSize = {}

C_AuctionHouse = {
    GetItemCommodityStatus = function(itemID)
        return ahStatus[itemID] or Enum.ItemCommodityStatus.Unknown
    end,
}

C_Item = {
    GetItemMaxStackSizeByID = function(itemID) return stackSize[itemID] end,
}

local ns = {}
assert(loadfile("Core.lua"))("FlipQueue", ns)

check("IsCommodity is exposed", type(ns.IsCommodity), "function")
check("FilterPoolCommodities is exposed", type(ns.FilterPoolCommodities), "function")

--------------------------
-- The API is the authority
--------------------------

ahStatus[101] = Enum.ItemCommodityStatus.Commodity
stackSize[101] = 1000
check("API Commodity -> true", ns:IsCommodity(101), true)

ahStatus[102] = Enum.ItemCommodityStatus.Item
stackSize[102] = 1
check("API Item -> false", ns:IsCommodity(102), false)

-- A non-stackable commodity would be a contradiction in retail, but the API
-- outranks the proxy either way — the proxy exists only to cover Unknown.
ahStatus[103] = Enum.ItemCommodityStatus.Item
stackSize[103] = 200
check("API Item beats a stackable proxy", ns:IsCommodity(103), false)

check("non-numeric ID is not a commodity", ns:IsCommodity("not an id"), false)
check("nil ID is not a commodity", ns:IsCommodity(nil), false)
check("numeric string ID resolves", ns:IsCommodity("101"), true)

--------------------------
-- Unknown falls back to stack size
--------------------------

stackSize[201] = 200
check("Unknown + stackable -> commodity", ns:IsCommodity(201), true)

stackSize[202] = 1
check("Unknown + non-stackable -> not commodity", ns:IsCommodity(202), false)

--------------------------
-- An Unknown answer is never pinned
--------------------------

-- Item 203 is unknown to both the AH and the item cache: the client simply
-- hasn't loaded it. Answering "not a commodity" keeps it visible, which is the
-- right direction to be wrong in — but caching that answer would keep it wrong
-- for the whole session even after the client learns better.
check("unknown to everything -> not commodity", ns:IsCommodity(203), false)
ahStatus[203] = Enum.ItemCommodityStatus.Commodity
check("...and the answer updates once the client knows", ns:IsCommodity(203), true)

-- The reverse case: a stack-derived guess must yield to a real API answer.
stackSize[204] = 20
check("stack proxy says commodity", ns:IsCommodity(204), true)
ahStatus[204] = Enum.ItemCommodityStatus.Item
check("...API overrides the proxy", ns:IsCommodity(204), false)

-- ...and an API answer is not re-derived from the proxy afterwards.
stackSize[204] = 200
check("API answer is sticky against the proxy", ns:IsCommodity(204), false)

--------------------------
-- Pool filtering
--------------------------

ahStatus[301] = Enum.ItemCommodityStatus.Commodity   -- ore
ahStatus[302] = Enum.ItemCommodityStatus.Item        -- a chest
ahStatus[303] = Enum.ItemCommodityStatus.Commodity   -- herb
ahStatus[304] = Enum.ItemCommodityStatus.Item        -- a recipe

local pool = {
    { itemID = 301, itemKey = "301;;",         name = "Ore" },
    { itemID = 302, itemKey = "302;42;",       name = "Chestguard" },
    { itemID = 303, itemKey = "303;;",         name = "Herb" },
    { itemKey     = "304;;",                   name = "Recipe" },   -- no itemID field
}

local kept, hidden = ns:FilterPoolCommodities(pool)
check("two items kept", #kept, 2)
check("two commodities hidden", hidden, 2)
check("first kept is the chest", kept[1].name, "Chestguard")
check("itemKey is used when itemID is absent", kept[2].name, "Recipe")

-- The input must not be mutated: the caller still holds it for the unfiltered
-- view, and the preview redraws from the same table.
check("input pool untouched", #pool, 4)

local emptyKept, emptyHidden = ns:FilterPoolCommodities({})
check("empty pool -> empty", #emptyKept, 0)
check("empty pool -> nothing hidden", emptyHidden, 0)

local nilKept, nilHidden = ns:FilterPoolCommodities(nil)
check("nil pool passes through", nilKept, nil)
check("nil pool -> nothing hidden", nilHidden, 0)

-- An item with no resolvable ID at all is kept, not silently dropped.
local unresolvable = { { name = "Mystery", itemKey = "not-a-key" } }
local uKept, uHidden = ns:FilterPoolCommodities(unresolvable)
check("unresolvable item kept", #uKept, 1)
check("unresolvable item not counted as hidden", uHidden, 0)

--------------------------

print(string.format("commodity_spec: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
