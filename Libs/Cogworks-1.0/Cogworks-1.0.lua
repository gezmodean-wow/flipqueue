-- Cogworks-1.0 | The mainspring of the Cogworks WoW addon suite.
--
-- An embeddable LibStub library providing the primitives shared across every
-- cog: event bus, theme palette, character-key helpers, print utilities, and
-- a Syndicator capability bridge.
--
-- Design notes:
--   * No Ace3 — built on LibStub + CallbackHandler-1.0, matching the rest of
--     the suite. Both dependencies are already loaded by LibDataBroker in
--     every cog, so Cogworks adds no new library cost.
--   * Additive only. MINOR bumps on every API addition; old functions never
--     go away. A breaking change would force every cog to re-release in
--     lockstep, which is exactly what this library exists to avoid.
--   * Syndicator is a hard dependency for inventory-aware cogs (FlipQueue,
--     Ledger). They declare it in their TOC and consume it directly with no
--     fallback scanner. Character keys follow Syndicator's "Name-Realm"
--     convention so all suite data shares one keyspace.

assert(LibStub, "Cogworks-1.0 requires LibStub")
assert(LibStub:GetLibrary("CallbackHandler-1.0", true), "Cogworks-1.0 requires CallbackHandler-1.0")

local MAJOR, MINOR = "Cogworks-1.0", 1
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end  -- already loaded at this version or newer
oldminor = oldminor or 0

-- ============================================================================
-- Version
-- ============================================================================

lib.version      = "0.1.0"   -- human-facing semver of the Cogworks suite
lib.minorVersion = MINOR     -- LibStub minor; bumps on any API addition

-- ============================================================================
-- Event bus
-- ============================================================================
-- A single CallbackHandler-backed registry that any cog can subscribe to.
-- Event names are centralized in lib.Events so typos fail loudly instead of
-- silently registering for an event that never fires.
--
-- Usage:
--   local cw = LibStub("Cogworks-1.0")
--   cw.RegisterCallback(self, cw.Events.SaleLogged, function(event, itemKey, price, qty)
--     -- react to a sale from any other cog
--   end)
--   cw:Fire(cw.Events.SaleLogged, itemKey, price, qty, "FlipQueue")

lib.Events = lib.Events or {
  -- Lifecycle
  Ready            = "Ready",            -- fired once at PLAYER_LOGIN
  AddonRegistered  = "AddonRegistered",  -- (addonName) — a new cog clicked in

  -- Character / account state
  CharacterChanged = "CharacterChanged", -- (charKey)
  GoldChanged      = "GoldChanged",      -- (charKey, newGold, delta)

  -- Inventory signals (typically bridged from Syndicator or FlipQueue's scanner)
  InventoryChanged = "InventoryChanged", -- (charKey, updates)
  MailChanged      = "MailChanged",      -- (charKey)
  AuctionsChanged  = "AuctionsChanged",  -- (charKey)

  -- Suite domain events (cross-cog signalling)
  SaleLogged       = "SaleLogged",       -- (itemKey, price, qty, source)
  CraftCompleted   = "CraftCompleted",   -- (recipeID, charKey)
  ResetDue         = "ResetDue",         -- (period)  -- "daily" / "weekly" / ...
  PriceUpdated     = "PriceUpdated",     -- (itemKey, source, price)
}

if not lib.callbacks then
  local CallbackHandler = LibStub("CallbackHandler-1.0")
  lib.callbacks = CallbackHandler:New(lib, "RegisterCallback", "UnregisterCallback", "UnregisterAllCallbacks")
end

function lib:Fire(event, ...)
  self.callbacks:Fire(event, ...)
end

-- ============================================================================
-- Registered addons (cogs)
-- ============================================================================
-- Each cog registers itself with Cogworks on load. The registry lets any cog
-- enumerate its siblings — useful for an "About" panel or for cross-promotion
-- without any hard dependency between cogs.

lib.addons = lib.addons or {}  -- [name] = { prefix, version, icon, website }

function lib:RegisterAddon(name, info)
  assert(type(name) == "string" and name ~= "", "RegisterAddon: name required")
  info = info or {}
  self.addons[name] = {
    prefix  = info.prefix  or ("|cffffd100[" .. name .. "]|r "),
    version = info.version or "unknown",
    icon    = info.icon,
    website = info.website,
  }
  self:Fire(self.Events.AddonRegistered, name)
end

function lib:GetAddon(name)
  return self.addons[name]
end

function lib:GetRegisteredAddons()
  local list = {}
  for name in pairs(self.addons) do
    list[#list + 1] = name
  end
  table.sort(list)
  return list
end

-- ============================================================================
-- Print helpers
-- ============================================================================

local function joinArgs(...)
  local n = select("#", ...)
  if n == 0 then return "" end
  local parts = {}
  for i = 1, n do
    parts[i] = tostring((select(i, ...)))
  end
  return table.concat(parts, " ")
end

function lib:Print(addonName, ...)
  local info = self.addons[addonName]
  local prefix = (info and info.prefix) or ("|cffffd100[" .. (addonName or "Cogworks") .. "]|r ")
  DEFAULT_CHAT_FRAME:AddMessage(prefix .. joinArgs(...))
end

function lib:PrintError(addonName, ...)
  self:Print(addonName, "|cffff4040" .. joinArgs(...) .. "|r")
end

-- ============================================================================
-- Theme constants
-- ============================================================================
-- The shared visual palette across the suite: dark TSM-style base, gold
-- primary accent, and a subtle arcane-purple highlight reserved for
-- "time magic" moments (reset-soon warnings, profit-surge callouts, etc.).

lib.Theme = lib.Theme or {
  -- Backgrounds
  bg        = { 0.08, 0.08, 0.12, 0.95 },   -- primary dark bg
  bgLight   = { 0.12, 0.12, 0.16, 0.95 },   -- panel bg
  bgDark    = { 0.04, 0.04, 0.07, 1.00 },   -- inset / header bg
  border    = { 0.30, 0.30, 0.40, 1.00 },

  -- Accents
  gold      = { 1.00, 0.82, 0.00, 1.00 },   -- primary accent
  arcane    = { 0.55, 0.36, 0.96, 1.00 },   -- "time magic" highlight (#8b5cf6)
  brass     = { 0.83, 0.63, 0.09, 1.00 },   -- clockwork trim

  -- Status
  success   = { 0.30, 0.85, 0.30, 1.00 },
  warning   = { 1.00, 0.78, 0.10, 1.00 },
  error     = { 1.00, 0.25, 0.25, 1.00 },
  muted     = { 0.55, 0.55, 0.60, 1.00 },
  text      = { 0.90, 0.90, 0.92, 1.00 },

  -- WoW item quality colors (for reference / shared widgets)
  quality = {
    [0] = { 0.62, 0.62, 0.62 },  -- Poor
    [1] = { 1.00, 1.00, 1.00 },  -- Common
    [2] = { 0.12, 1.00, 0.00 },  -- Uncommon
    [3] = { 0.00, 0.44, 0.87 },  -- Rare
    [4] = { 0.64, 0.21, 0.93 },  -- Epic
    [5] = { 1.00, 0.50, 0.00 },  -- Legendary
    [6] = { 0.90, 0.80, 0.50 },  -- Artifact
    [7] = { 0.00, 0.80, 1.00 },  -- Heirloom
    [8] = { 0.00, 0.80, 1.00 },  -- WoW Token
  },
}

-- ============================================================================
-- Character key utilities
-- ============================================================================
-- Canonical "Name-RealmNormalized" keys, matching Syndicator's convention
-- so Cogworks and Syndicator data can be cross-referenced without a
-- translation layer.

local function currentRealm()
  if GetNormalizedRealmName then
    local nr = GetNormalizedRealmName()
    if nr and nr ~= "" then return nr end
  end
  return GetRealmName()
end

function lib:GetCharacterKey(name, realm)
  name  = name  or UnitName("player")
  realm = realm or currentRealm()
  return name .. "-" .. realm
end

-- ============================================================================
-- Syndicator bridge
-- ============================================================================
-- Cogworks itself does not require Syndicator. Inventory-aware cogs (FlipQueue,
-- the planned Ledger) declare it as a HARD dependency in their TOC and consume
-- it directly with no fallback scanner.
--
-- This helper exists for cogs that want to OPPORTUNISTICALLY enrich their data
-- when Syndicator happens to be present, without making it a hard requirement
-- (e.g. Maxcraft showing reagent counts from alts if it can).
--
-- See docs/PLAN.md in the cogworks repo for the suite's Syndicator strategy.

function lib:HasSyndicator()
  return _G.Syndicator ~= nil
    and _G.Syndicator.API ~= nil
    and _G.Syndicator.API.IsReady ~= nil
    and _G.Syndicator.API.IsReady() == true
end

-- ============================================================================
-- Initialization hook
-- ============================================================================
-- Cogworks fires its Ready event once at PLAYER_LOGIN. Cogs that need to wait
-- for the full login sequence before touching Cogworks state can listen on it.

if not lib._readyFrame then
  lib._readyFrame = CreateFrame("Frame")
  lib._readyFrame:RegisterEvent("PLAYER_LOGIN")
  lib._readyFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
      lib:Fire(lib.Events.Ready)
    end
  end)
end
