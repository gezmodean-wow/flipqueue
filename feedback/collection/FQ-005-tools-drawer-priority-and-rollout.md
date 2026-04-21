---
id: FQ-005
cog: flipqueue
status: design
title: Tools drawer — rollout sub-drawers, priority config, smart default, separate find button, profession + racial inclusion
sources:
  - type: internal
    session: 2026-04-21
    note: Relayed from player reports via gezmodean — substantial redesign, multiple threads
reporters: [gezmodean]
created: 2026-04-21
updated: 2026-04-21
release: null
tags: [tools-drawer, ui, design, summons, profession, racial]
---

## Summary

Tools drawer redesign covering how players pick which summon/toy to use for each service (AH, Bank, Warbank, Mailbox), with smart defaults based on current state, configurable priorities, and explicit separation of "use it" vs "find the nearest one". Also expands the pool to include engineer profession options and racial abilities.

## Requirements

### 1. Roll-out sub-drawers per service

Each service row in the main Tools drawer should be expandable into a sub-drawer listing **every option the player has** for that service — not just the one FlipQueue picked. Players who own multiple ways to summon a bank (mount, toy, item, engineering gadget, etc.) want to see all of them and choose.

### 2. Priority configuration in settings

Settings gets a new section where the player orders their preferred options per service. FlipQueue defaults surface the top-priority usable option; the sub-drawer presents the full ordered list.

### 3. Smart default selection

The widget's default should present the option that **allows immediate use right now**, not a fixed favorite. Rules in priority order:

1. **Already-summoned matters.** If the player has a Brutosaur currently out, the merchants on that Brutosaur are the best answer — no cast time, no cooldown spend, just use it. Surface that.
2. **If priority-1 option is on cooldown,** check priority-2. If that's immediately usable, surface it instead. Continue down the list.
3. **Otherwise (everything on cooldown),** surface the option that will come off cooldown soonest, with the remaining cooldown visible so the player can decide to wait vs walk to a fixed location.

### 4. Separate "find" button

To the right of the icon, show a distinct icon that clearly signals "location" — map pin, waypoint marker, or similar. **This is the find button** (currently `FindNearestService`). Clicking the main icon uses the summon/toy; clicking the find icon routes to the closest fixed service location.

Today the drawer conflates the two; players who want to walk/fly to a physical AH aren't getting a clean affordance for that.

### 5. Include engineer profession options

If the player has Engineering, include profession gadgets in the option pool:
- **Jeeves** (Bank, Mailbox, Repair) — if crafted/available
- **MOLL-E** / **MOLE Machine** (Mailbox) — if applicable
- **Wormhole Generators** (transport — likely not in scope for these four services)
- **Reaves module** variants

Detection via `C_TradeSkillUI` / profession flag plus the player actually owning the gadget.

### 6. Include racial abilities

Race-specific summons/abilities when they match a service:
- **Every Man for Himself** / **Escape Artist** etc. aren't service-related.
- **Goblins** have a Rocket Barrage / Pack Hobgoblin (mobile vendor) — Vendor, not one of the four services, but consider whether Repair/Vendor becomes a fifth service.
- **Pandaren** — Double Jump isn't service-related.
- **Dark Iron Dwarves** — Mole Machine (transport).
- **Mag'har Orc** — Ancestral Call (combat).
- **Void Elf** — Spatial Rift (transport).

Services we likely care about: any racial that opens a mailbox, bank, AH, or repair/vendor. Needs an audit of current racials per race.

## Notes

- The existing `FindNearestService` and location-learning infrastructure already exists — the find button would surface it more cleanly rather than replacing it.
- Priority ordering persists per-character (common) or globally (simpler). Probably global with per-character override, matching `goldBuffer` / role settings.
- "Immediate use" detection needs live cooldown queries — `GetItemCooldown(itemID)`, `GetSpellCooldown(spellID)`, and a query for "is the player currently mounted on X". For Brutosaur specifically: `IsMounted()` + `C_MountJournal.GetMountFromItem()` or equivalent to confirm it's the Brutosaur that's active.
- Mobile-vendor mounts (Brutosaur, Katy's Stampwhistle) have merchants that follow the mount — dismissing breaks access. Sub-drawer should reflect that.

## Design open questions

1. Does the sub-drawer open inline (pushing the rest down) or float over? Inline keeps the drawer self-contained; float avoids shifting other rows.
2. Where does the priority UI live? Standalone "Tools" page in the main UI? Or inline in the sub-drawer itself (drag-to-reorder)?
3. Do we fold "Repair/Vendor" in as a fifth service? Player value is clear; scope creep risk.

## Next steps

1. Audit current `UI/ToolDrawer.lua` + summon-item lookup to see which of the six requirements can be slotted onto the existing structure vs. needing a rewrite.
2. Inventory the full set of WoW items/toys/spells per service (AH, Bank, Warbank, Mailbox) — start from what's already in FQ's service table, add missing ones (Jeeves, racials, engineering gadgets).
3. Prototype the sub-drawer rollout on one service first to validate the interaction pattern before applying to all four.
4. Priority-config UI: sketch in a design doc before implementing — several options, want to pick well once.
