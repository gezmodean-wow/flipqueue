-- UI/ToolRegistry.lua
-- Tool model for the redesigned tools drawer (FQ-005 / issue #115).
--
-- The drawer is an ordered list of *tools*, not a hardcoded service table.
-- A tool is one of three types:
--   * "service" -- summonable, multiple methods, gets a rollout sub-drawer
--                  and a find button. (AH, Vendor, Warbank, Bank, Mailbox,
--                  Hearthstone)
--   * "action"  -- single click, no rollout, no find. (Logout, Reload)
--   * "macro"   -- references one of the player's native WoW macros by name;
--                  single click, inherits the macro's name + icon.
--
-- This file owns the static definitions, the live summon-availability
-- checks, the smart-default resolution, native-macro enumeration, and the
-- account-wide configuration (tool order / hidden set / per-service method
-- priority / macro list). UI/ToolDrawer.lua consumes all of it; this file
-- creates no frames.
local addonName, ns = ...

local TR = {}
ns.ToolRegistry = TR

--------------------------
-- Static tool definitions
--------------------------

-- A method is one summon option inside a Service tool. Fields:
--   kind = "item" | "toy" | "mount" | "spell"
--   id   = item ID / toy item ID / mount journal ID / spell ID
--   name = English display + secure-attribute fallback. For mounts this MUST
--          be the mount's spell name; the live check re-resolves a localized
--          name where the API allows.
-- The method key (kind..":"..id) is the stable identifier used by the
-- per-service priority list in saved config.

-- Mounts shared across several services -- declared once, referenced below.
local M_CARAVAN  = { kind = "mount", id = 1039, name = "Mighty Caravan Brutosaur" }
local M_GILDED   = { kind = "mount", id = 2265, name = "Trader's Gilded Brutosaur" }
local M_ANCHOR   = { kind = "mount", id = 2332, name = "Traveler's Anchorite" }

-- The eight built-in tools. `order` here is the shipped default order; the
-- default-hidden set is mailbox + bank (see DEFAULT_HIDDEN).
local BUILTIN_TOOLS = {
    --------------------------------------------------------------------
    -- Action tools
    --------------------------------------------------------------------
    {
        -- Logout() is a protected function (ADDON_ACTION_FORBIDDEN from
        -- insecure code, FQ-221), so this dispatches "/logout" through the
        -- button's secure macrotext attribute instead of an onUse handler.
        id = "logout", type = "action", label = "Log Out",
        icon = "Interface\\Icons\\INV_Misc_Bell_01",
        macrotext = "/logout",
        tooltip = "Log out to the character-select screen.",
    },
    {
        id = "reload", type = "action", label = "Reload UI",
        icon = "Interface\\Icons\\INV_Misc_GroupLooking",
        onUse = function()
            if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
        end,
        tooltip = "Reload the user interface.",
    },

    --------------------------------------------------------------------
    -- Service tools
    --------------------------------------------------------------------
    {
        id = "ah", type = "service", label = "Auction House",
        iconFallback = "Interface\\Icons\\INV_Misc_Coin_02",
        locationKey = "auctionHouse",
        inServiceCheck = function()
            return ns._serviceState and ns._serviceState.auctionOpen
        end,
        methods = { M_CARAVAN, M_GILDED, M_ANCHOR },
        locations = {
            { map = 2339, x = 0.48, y = 0.52, zoneName = "Dornogal", text = "Auction House" },
            { map = 2112, x = 0.40, y = 0.56, zoneName = "Valdrakken", text = "Auction House" },
            { map = 1670, x = 0.45, y = 0.28, zoneName = "Oribos", text = "Auction House" },
            { map = 1161, x = 0.73, y = 0.10, zoneName = "Boralus", text = "Tradewinds Market Auction House", faction = "Alliance" },
            { map = 1165, x = 0.53, y = 0.88, zoneName = "Dazar'alor", text = "The Great Seal Auction House", faction = "Horde" },
            { map = 84,   x = 0.60, y = 0.70, zoneName = "Stormwind", text = "Trade District Auction House", faction = "Alliance" },
            { map = 85,   x = 0.54, y = 0.58, zoneName = "Orgrimmar", text = "Valley of Strength Auction House", faction = "Horde" },
            { map = 87,   x = 0.25, y = 0.07, zoneName = "Ironforge", text = "The Commons Auction House", faction = "Alliance" },
            { map = 88,   x = 0.46, y = 0.58, zoneName = "Thunder Bluff", text = "Lower Rise Auction House", faction = "Horde" },
        },
    },
    {
        id = "vendor", type = "service", label = "Vendor",
        iconFallback = "Interface\\Icons\\INV_Misc_Coin_01",
        locationKey = "vendor",
        -- Selling vendorable / junk items -- one-click merchant NPC access.
        -- Methods are summons that bring a merchant with them.
        methods = {
            M_CARAVAN,
            { kind = "spell", id = 69046, name = "Pack Hobgoblin" },  -- Goblin racial
            { kind = "item",  id = 49040, name = "Jeeves" },          -- engineer gadget
        },
        locations = {},  -- vendors are everywhere; rely on learned locations
    },
    {
        id = "warbank", type = "service", label = "Warband Bank",
        iconFallback = "Interface\\Icons\\INV_Misc_Bag_EnchantedRunecloth",
        locationKey = "bank",  -- shares bank NPC locations
        inServiceCheck = function()
            return ns._serviceState and ns._serviceState.bankOpen
        end,
        methods = {
            { kind = "spell", id = 460905, name = "Warband Bank Distance Inhibitor" },
            M_CARAVAN,
        },
        locations = {
            { map = 2339, x = 0.50, y = 0.50, zoneName = "Dornogal", text = "Warband Bank (bank NPC)" },
            { map = 2112, x = 0.39, y = 0.55, zoneName = "Valdrakken", text = "Warband Bank (bank NPC)" },
            { map = 1670, x = 0.47, y = 0.30, zoneName = "Oribos", text = "Warband Bank (bank NPC)" },
            { map = 627,  x = 0.36, y = 0.44, zoneName = "Dalaran", text = "Warband Bank (Dalaran Bank)" },
            { map = 1161, x = 0.73, y = 0.12, zoneName = "Boralus", text = "Warband Bank (Tradewinds Market)", faction = "Alliance" },
            { map = 1165, x = 0.53, y = 0.88, zoneName = "Dazar'alor", text = "Warband Bank (Great Seal)", faction = "Horde" },
            { map = 84,   x = 0.60, y = 0.62, zoneName = "Stormwind", text = "Warband Bank (Trade District)", faction = "Alliance" },
            { map = 85,   x = 0.55, y = 0.58, zoneName = "Orgrimmar", text = "Warband Bank (Valley of Strength)", faction = "Horde" },
            { map = 87,   x = 0.36, y = 0.60, zoneName = "Ironforge", text = "Warband Bank (The Vault)", faction = "Alliance" },
            { map = 88,   x = 0.45, y = 0.50, zoneName = "Thunder Bluff", text = "Warband Bank (High Rise)", faction = "Horde" },
        },
    },
    {
        id = "hearthstone", type = "service", label = "Hearthstone",
        iconFallback = "Interface\\Icons\\INV_Misc_Rune_01",
        -- No locationKey: a hearthstone has no fixed location to find.
        methods = {
            { kind = "item", id = 6948,   name = "Hearthstone" },
            { kind = "item", id = 140192, name = "Dalaran Hearthstone" },
            { kind = "item", id = 110560, name = "Garrison Hearthstone" },
            { kind = "toy",  id = 64488,  name = "The Innkeeper's Daughter" },
            { kind = "toy",  id = 142543, name = "Hearthstone of the Flame" },
            { kind = "toy",  id = 163045, name = "Headless Horseman's Hearthstone" },
            { kind = "toy",  id = 165669, name = "Lunar Elder's Hearthstone" },
            { kind = "toy",  id = 165670, name = "Peddlefeet's Lovely Hearthstone" },
            { kind = "toy",  id = 165802, name = "Noble Gardener's Hearthstone" },
            { kind = "toy",  id = 166746, name = "Fire Eater's Hearthstone" },
            { kind = "toy",  id = 166747, name = "Brewfest Reveler's Hearthstone" },
            { kind = "toy",  id = 168907, name = "Holographic Digitalization Hearthstone" },
            { kind = "toy",  id = 172179, name = "Eternal Traveler's Hearthstone" },
            { kind = "toy",  id = 184353, name = "Kyrian Hearthstone" },
            { kind = "toy",  id = 188952, name = "Dominated Hearthstone" },
            { kind = "toy",  id = 190196, name = "Enlightened Hearthstone" },
            { kind = "toy",  id = 193588, name = "Timewalker's Hearthstone" },
            { kind = "toy",  id = 200630, name = "Ohn'ir Windsage's Hearthstone" },
            { kind = "toy",  id = 206195, name = "Path of the Naaru" },
            { kind = "toy",  id = 212337, name = "Stone of the Hearth" },
        },
        locations = {},
    },
    {
        id = "mailbox", type = "service", label = "Mailbox",
        iconFallback = "Interface\\Icons\\INV_Letter_15",
        locationKey = "mail",
        inServiceCheck = function()
            return ns._serviceState and ns._serviceState.mailOpen
        end,
        methods = {
            M_GILDED,
            { kind = "toy",  id = 156833, name = "Katy's Stampwhistle" },
            { kind = "item", id = 54710,  name = "MOLL-E" },
        },
        locations = {
            { map = 2339, x = 0.56, y = 0.45, zoneName = "Dornogal", text = "Mailbox near Earthenfall Hall" },
            { map = 2112, x = 0.58, y = 0.57, zoneName = "Valdrakken", text = "Seat of the Aspects mailbox" },
            { map = 1670, x = 0.49, y = 0.28, zoneName = "Oribos", text = "Ring of Transference mailbox" },
            { map = 627,  x = 0.50, y = 0.50, zoneName = "Dalaran", text = "Magus Commerce Exchange mailbox" },
            { map = 1161, x = 0.73, y = 0.12, zoneName = "Boralus", text = "Tradewinds Market mailbox", faction = "Alliance" },
            { map = 1165, x = 0.53, y = 0.88, zoneName = "Dazar'alor", text = "The Great Seal mailbox", faction = "Horde" },
            { map = 84,   x = 0.60, y = 0.65, zoneName = "Stormwind", text = "Trade District mailbox", faction = "Alliance" },
            { map = 85,   x = 0.54, y = 0.55, zoneName = "Orgrimmar", text = "Valley of Strength mailbox", faction = "Horde" },
            { map = 87,   x = 0.27, y = 0.07, zoneName = "Ironforge", text = "The Commons mailbox", faction = "Alliance" },
            { map = 88,   x = 0.46, y = 0.58, zoneName = "Thunder Bluff", text = "Lower Rise mailbox", faction = "Horde" },
        },
    },
    {
        id = "bank", type = "service", label = "Character Bank",
        iconFallback = "Interface\\Icons\\INV_Misc_Bag_10_Green",
        locationKey = "bank",
        inServiceCheck = function()
            return ns._serviceState and ns._serviceState.bankOpen
        end,
        methods = {
            M_CARAVAN,
            { kind = "item", id = 49040, name = "Jeeves" },
        },
        locations = {
            { map = 2339, x = 0.50, y = 0.50, zoneName = "Dornogal", text = "Bank" },
            { map = 2112, x = 0.39, y = 0.55, zoneName = "Valdrakken", text = "Bank" },
            { map = 1670, x = 0.47, y = 0.30, zoneName = "Oribos", text = "Bank" },
            { map = 627,  x = 0.36, y = 0.44, zoneName = "Dalaran", text = "Dalaran Bank" },
            { map = 1161, x = 0.73, y = 0.12, zoneName = "Boralus", text = "Tradewinds Market Bank", faction = "Alliance" },
            { map = 1165, x = 0.53, y = 0.88, zoneName = "Dazar'alor", text = "The Great Seal Bank", faction = "Horde" },
            { map = 84,   x = 0.60, y = 0.62, zoneName = "Stormwind", text = "Trade District Bank", faction = "Alliance" },
            { map = 85,   x = 0.55, y = 0.58, zoneName = "Orgrimmar", text = "Valley of Strength Bank", faction = "Horde" },
            { map = 87,   x = 0.36, y = 0.60, zoneName = "Ironforge", text = "The Vault Bank", faction = "Alliance" },
            { map = 88,   x = 0.45, y = 0.50, zoneName = "Thunder Bluff", text = "High Rise Bank", faction = "Horde" },
        },
    },
}

-- Shipped default order + the tools hidden until the player enables them.
local DEFAULT_ORDER  = { "logout", "reload", "ah", "vendor", "warbank", "hearthstone", "mailbox", "bank" }
local DEFAULT_HIDDEN = { mailbox = true, bank = true }

local MISSING_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
TR.MISSING_ICON = MISSING_ICON

-- Shipped defaults, exported so DB.lua can seed them without restating the
-- list (single source of truth for the built-in tool set).
TR.DEFAULT_ORDER  = DEFAULT_ORDER
TR.DEFAULT_HIDDEN = DEFAULT_HIDDEN

--------------------------
-- Config (account-wide)
--------------------------

-- Lazily initialise db.settings.toolbox. DB.lua also seeds this on login;
-- this guard keeps the registry safe if called before that runs.
local function Config()
    if not (ns.db and ns.db.settings) then return nil end
    local tb = ns.db.settings.toolbox
    if not tb then
        tb = {}
        ns.db.settings.toolbox = tb
    end
    if type(tb.order) ~= "table" then
        tb.order = {}
        for _, id in ipairs(DEFAULT_ORDER) do tb.order[#tb.order + 1] = id end
    end
    if type(tb.hidden) ~= "table" then
        tb.hidden = {}
        for id in pairs(DEFAULT_HIDDEN) do tb.hidden[id] = true end
    end
    if type(tb.methodPriority) ~= "table" then tb.methodPriority = {} end
    if type(tb.macros) ~= "table" then tb.macros = {} end
    return tb
end
TR.EnsureConfig = Config

local function MethodKey(method)
    return method.kind .. ":" .. method.id
end
TR.MethodKey = MethodKey

--------------------------
-- Macro tools
--------------------------

-- Build a live macro-tool definition for a stored macro name. WoW macros are
-- referenced by name (not index -- indexes shift); if the macro no longer
-- exists the tool is flagged `missing` instead of vanishing.
local function BuildMacroTool(name)
    local tool = {
        id = "macro:" .. name, type = "macro", label = name, macroName = name,
    }
    local idx = GetMacroIndexByName and GetMacroIndexByName(name) or 0
    if idx and idx > 0 then
        local mName, mIcon = GetMacroInfo(idx)
        tool.label = mName or name
        tool.icon = mIcon or MISSING_ICON
        tool.missing = false
    else
        tool.icon = MISSING_ICON
        tool.missing = true
    end
    return tool
end
TR.BuildMacroTool = BuildMacroTool

-- Enumerate the player's native WoW macros (account-wide + per-character).
-- Returns an array of { name, icon, perChar } for the macro picker UI.
function TR:ListWoWMacros()
    local out = {}
    if not (GetNumMacros and GetMacroInfo) then return out end
    local globalCount, charCount = GetNumMacros()
    globalCount = globalCount or 0
    charCount = charCount or 0
    for i = 1, globalCount do
        local name, icon = GetMacroInfo(i)
        if name and name ~= "" then
            out[#out + 1] = { name = name, icon = icon, perChar = false }
        end
    end
    -- Per-character macros occupy indices 121..120+charCount.
    for i = 121, 120 + charCount do
        local name, icon = GetMacroInfo(i)
        if name and name ~= "" then
            out[#out + 1] = { name = name, icon = icon, perChar = true }
        end
    end
    return out
end

--------------------------
-- Tool list assembly
--------------------------

local function BuiltinById()
    local t = {}
    for _, d in ipairs(BUILTIN_TOOLS) do t[d.id] = d end
    return t
end

-- Build the ordered tool list. `includeHidden` true returns every tool
-- (for the settings show/hide list); false returns only visible tools
-- (for the drawer). Macro tools are resolved live from saved names.
local function BuildOrderedTools(includeHidden)
    local tb = Config()
    local byId = BuiltinById()
    local macroById = {}
    if tb then
        for _, name in ipairs(tb.macros) do
            local d = BuildMacroTool(name)
            macroById[d.id] = d
        end
    end

    local result, seen = {}, {}
    local function consider(d)
        if not d or seen[d.id] then return end
        seen[d.id] = true
        if includeHidden or not (tb and tb.hidden[d.id]) then
            result[#result + 1] = d
        end
    end

    if tb then
        for _, id in ipairs(tb.order) do
            consider(byId[id] or macroById[id])
        end
    end
    -- Append anything not covered by the saved order (new builtins after an
    -- update, or macros added without an order entry yet).
    for _, d in ipairs(BUILTIN_TOOLS) do consider(d) end
    for _, name in ipairs((tb and tb.macros) or {}) do
        consider(macroById["macro:" .. name])
    end
    return result
end

-- Visible, ordered tools for the drawer.
function TR:GetTools()
    return BuildOrderedTools(false)
end

-- Every tool (visible + hidden), ordered, for the settings list.
function TR:GetAllTools()
    return BuildOrderedTools(true)
end

function TR:IsHidden(id)
    local tb = Config()
    return tb and tb.hidden[id] and true or false
end

function TR:SetHidden(id, hidden)
    local tb = Config()
    if not tb then return end
    tb.hidden[id] = hidden and true or nil
end

-- Move a tool one slot up (dir -1) or down (dir +1) in the saved order.
-- The order array is normalised first so it always lists every tool exactly
-- once before the swap.
function TR:MoveTool(id, dir)
    local tb = Config()
    if not tb then return end
    -- Normalise: rebuild order from the current full tool list.
    local norm, seen = {}, {}
    for _, existing in ipairs(tb.order) do
        if not seen[existing] then seen[existing] = true; norm[#norm + 1] = existing end
    end
    for _, d in ipairs(self:GetAllTools()) do
        if not seen[d.id] then seen[d.id] = true; norm[#norm + 1] = d.id end
    end
    local idx
    for i, v in ipairs(norm) do if v == id then idx = i break end end
    if not idx then return end
    local swap = idx + dir
    if swap < 1 or swap > #norm then return end
    norm[idx], norm[swap] = norm[swap], norm[idx]
    tb.order = norm
end

-- Add a native WoW macro as a macro tool (by name). Appends it to the saved
-- order so it shows up in the drawer immediately. No-op if already added.
function TR:AddMacro(name)
    local tb = Config()
    if not (tb and name and name ~= "") then return end
    for _, n in ipairs(tb.macros) do
        if n == name then return end
    end
    tb.macros[#tb.macros + 1] = name
    tb.order[#tb.order + 1] = "macro:" .. name
end

-- Remove a macro tool (by name) from the saved config entirely.
function TR:RemoveMacro(name)
    local tb = Config()
    if not (tb and name) then return end
    local id = "macro:" .. name
    for i = #tb.macros, 1, -1 do
        if tb.macros[i] == name then table.remove(tb.macros, i) end
    end
    for i = #tb.order, 1, -1 do
        if tb.order[i] == id then table.remove(tb.order, i) end
    end
    tb.hidden[id] = nil
end

--------------------------
-- Method priority
--------------------------

-- Return a service tool's methods ordered by the player's saved priority,
-- with any methods not in the saved list appended in definition order.
function TR:GetOrderedMethods(tool)
    if not (tool and tool.methods) then return {} end
    local tb = Config()
    local pri = tb and tb.methodPriority[tool.id]
    if not pri or #pri == 0 then
        local copy = {}
        for _, m in ipairs(tool.methods) do copy[#copy + 1] = m end
        return copy
    end
    local rank, origIndex = {}, {}
    for i, key in ipairs(pri) do rank[key] = i end
    local ordered = {}
    for i, m in ipairs(tool.methods) do
        ordered[i] = m
        origIndex[m] = i
    end
    -- table.sort is not stable in Lua, so methods sharing a rank (e.g. all
    -- the unranked ones) need an explicit definition-order tiebreaker.
    table.sort(ordered, function(a, b)
        local ra = rank[MethodKey(a)] or math.huge
        local rb = rank[MethodKey(b)] or math.huge
        if ra ~= rb then return ra < rb end
        return origIndex[a] < origIndex[b]
    end)
    return ordered
end

function TR:GetMethodPriority(toolId)
    local tb = Config()
    return tb and tb.methodPriority[toolId]
end

-- Move a method one slot up/down within a service tool's priority list.
function TR:MoveMethod(tool, methodKey, dir)
    local tb = Config()
    if not (tb and tool and tool.methods) then return end
    -- Seed the priority list from the current ordered methods if absent.
    local pri = tb.methodPriority[tool.id]
    if not pri or #pri == 0 then
        pri = {}
        for _, m in ipairs(self:GetOrderedMethods(tool)) do
            pri[#pri + 1] = MethodKey(m)
        end
    end
    local idx
    for i, v in ipairs(pri) do if v == methodKey then idx = i break end end
    if not idx then return end
    local swap = idx + dir
    if swap < 1 or swap > #pri then return end
    pri[idx], pri[swap] = pri[swap], pri[idx]
    tb.methodPriority[tool.id] = pri
end

--------------------------
-- Summon availability checks
--------------------------

-- Each returns a normalised eval table:
--   { owned, icon, name, remaining, cdStart, cdDur, usable, isActive }
-- `owned` false means the player can't use this method at all.

local function CooldownRemaining(start, duration)
    if start and duration and duration > 0 then
        return math.max(0, (start + duration) - GetTime()), start, duration
    end
    return 0, 0, 0
end

-- Bag-contents cache. GetTime() is constant within a frame, so this rebuilds
-- at most once per frame -- every EvalItem in one drawer refresh shares the
-- single scan instead of re-walking all five bags per item method.
local bagSet, bagSetStamp
local function GetBagSet()
    local now = GetTime()
    if bagSet and bagSetStamp == now then return bagSet end
    bagSet, bagSetStamp = {}, now
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, (numSlots or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then bagSet[info.itemID] = true end
        end
    end
    return bagSet
end

local function EvalItem(itemID)
    -- Owned == present in bags. Cooldown via the item cooldown API.
    if not GetBagSet()[itemID] then return { owned = false } end
    local s, d = C_Container.GetItemCooldown(itemID)
    local remaining, cdStart, cdDur = CooldownRemaining(s, d)
    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or nil
    local usable = true
    if IsUsableItem then
        local v = IsUsableItem(itemID)
        if v == false then usable = false end
    end
    return { owned = true, icon = icon,
             remaining = remaining, cdStart = cdStart, cdDur = cdDur, usable = usable }
end

local function EvalToy(toyID)
    -- Toys live in the toy box, not bags. PlayerHasToy gates ownership;
    -- the item cooldown API still works on a learned toy.
    if not PlayerHasToy or not PlayerHasToy(toyID) then return { owned = false } end
    local remaining, cdStart, cdDur = 0, 0, 0
    if C_Container and C_Container.GetItemCooldown then
        local s, d = C_Container.GetItemCooldown(toyID)
        remaining, cdStart, cdDur = CooldownRemaining(s, d)
    end
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(toyID) or nil
    local name
    if C_Item and C_Item.GetItemInfo then
        local ok, n = pcall(C_Item.GetItemInfo, toyID)
        if ok and n then name = n end
    end
    return { owned = true, icon = icon, name = name,
             remaining = remaining, cdStart = cdStart, cdDur = cdDur, usable = true }
end

local function EvalMount(mountID)
    if not (C_MountJournal and C_MountJournal.GetMountInfoByID) then return { owned = false } end
    local name, spellID, icon, isActive, isUsable, _, _, _, _, _, isCollected =
        C_MountJournal.GetMountInfoByID(mountID)
    if not isCollected then return { owned = false } end
    local remaining, cdStart, cdDur = 0, 0, 0
    if spellID and C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info and info.duration and info.duration > 0 then
            remaining, cdStart, cdDur =
                CooldownRemaining(info.startTime, info.duration)
        end
    end
    return { owned = true, icon = icon, name = name,
             remaining = remaining, cdStart = cdStart, cdDur = cdDur,
             usable = isUsable ~= false, isActive = isActive == true }
end

local function EvalSpell(spellID)
    local known = false
    if IsPlayerSpell then known = IsPlayerSpell(spellID)
    elseif IsSpellKnown then known = IsSpellKnown(spellID) end
    if not known then return { owned = false } end

    local start, duration = 0, 0
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then start = info.startTime or 0; duration = info.duration or 0 end
    elseif GetSpellCooldown then
        local s, d = GetSpellCooldown(spellID)
        start, duration = s or 0, d or 0
    end
    local remaining, cdStart, cdDur = CooldownRemaining(start, duration)

    local icon
    if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(spellID)
    elseif GetSpellTexture then icon = GetSpellTexture(spellID) end
    local name
    if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then name = GetSpellInfo(spellID) end

    return { owned = true, icon = icon, name = name,
             remaining = remaining, cdStart = cdStart, cdDur = cdDur, usable = true }
end

-- Evaluate one method. The returned table also carries `dispatchKind`
-- ("item"|"spell") and `dispatchName` -- toys dispatch like items, mounts
-- like spells, so the secure button only ever sees "item" vs "spell".
function TR:EvalMethod(method)
    local e
    if method.kind == "toy" then
        e = EvalToy(method.id)
        e.dispatchKind = "item"
    elseif method.kind == "mount" then
        e = EvalMount(method.id)
        e.dispatchKind = "spell"
    elseif method.kind == "spell" then
        e = EvalSpell(method.id)
        e.dispatchKind = "spell"
    else
        e = EvalItem(method.id)
        e.dispatchKind = "item"
    end
    e.dispatchName = e.name or method.name
    e.method = method
    return e
end

-- Classify an owned method eval into a single state string. Shared by the
-- drawer's smart default, the rollout rows, and the settings priority list
-- so the three never drift apart.
function TR:ClassifyEval(e)
    if e.isActive then return "active" end
    if e.remaining and e.remaining > 0 then return "cooldown" end
    if e.usable == false then return "unavailable" end
    return "ready"
end

-- Apply (or clear) a button's secure click attributes. `kind` is
-- "item" | "spell" | "macro" | "macrotext"; pass nil to clear. The caller
-- must guard against combat lockdown -- SetAttribute is protected mid-combat.
function TR:ApplySecureDispatch(button, kind, name)
    button:SetAttribute("type", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("macro", nil)
    button:SetAttribute("macrotext", nil)
    if not (kind and name) then return end
    if kind == "spell" then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", name)
    elseif kind == "macro" then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macro", name)
    elseif kind == "macrotext" then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", name)
    else
        button:SetAttribute("type", "item")
        button:SetAttribute("item", name)
    end
end

--------------------------
-- Smart-default resolution
--------------------------

-- Resolve the state to show on a tool's main drawer button.
-- Returns a table with `state` and type-appropriate extras:
--   service: state = "open" | "active" | "ready" | "cooldown" | "unowned"
--            plus icon, and for ready/active/cooldown: dispatchKind,
--            dispatchName, methodLabel; cooldown adds cdStart/cdDur.
--   action:  state = "ready", icon, onUse.
--   macro:   state = "ready" | "missing", icon, macroName.
function TR:ResolveTool(tool)
    if tool.type == "action" then
        return { state = "ready", icon = tool.icon, onUse = tool.onUse }
    end
    if tool.type == "macro" then
        return {
            state = tool.missing and "missing" or "ready",
            icon = tool.icon, macroName = tool.macroName,
        }
    end

    -- Service tool.
    local fallback = tool.iconFallback
    if tool.inServiceCheck and tool.inServiceCheck() then
        return { state = "open", icon = fallback }
    end

    local methods = self:GetOrderedMethods(tool)
    local active, ready, soonestCd
    for _, m in ipairs(methods) do
        local e = self:EvalMethod(m)
        if e.owned then
            local cls = self:ClassifyEval(e)
            if cls == "active" and not active then active = e end
            if cls == "ready" and not ready then ready = e end
            if cls == "cooldown"
               and (not soonestCd or e.remaining < soonestCd.remaining) then
                soonestCd = e
            end
        end
    end

    local function pack(e, state)
        return {
            state = state, icon = e.icon or fallback,
            dispatchKind = e.dispatchKind, dispatchName = e.dispatchName,
            methodLabel = e.method.name,
            cdStart = e.cdStart, cdDur = e.cdDur,
        }
    end

    -- Already mounted on a method-mount wins: merchants are right there.
    if active then return pack(active, "active") end
    if ready then return pack(ready, "ready") end
    if soonestCd then return pack(soonestCd, "cooldown") end
    return { state = "unowned", icon = fallback }
end

-- Owned methods for a service tool, priority-ordered, each with its eval.
-- Drives the rollout sub-drawer (which lists every *owned* method).
function TR:GetOwnedMethodEvals(tool)
    local out = {}
    if not (tool and tool.type == "service") then return out end
    for _, m in ipairs(self:GetOrderedMethods(tool)) do
        local e = self:EvalMethod(m)
        if e.owned then out[#out + 1] = e end
    end
    return out
end
