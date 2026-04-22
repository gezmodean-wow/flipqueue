---
id: FQ-002
cog: flipqueue
status: in-progress
title: Adopt Cogworks gear-border minimap chrome (COG-003/COG-004 canary)
sources:
  - type: internal
    session: 2026-04-21
    note: Brief written in cogworks session for FlipQueue agent to execute. FlipQueue is the canary rollout for the Chronoforge suite-wide minimap branding.
reporters: []
created: 2026-04-21
updated: 2026-04-21
release: null
tags: [minimap, branding, cogworks-migration, canary]
---

## Summary

Adopt Cogworks v0.6.0's new `lib:RegisterCogMinimapButton` wrapper and swap FlipQueue's minimap icon to the new gold-on-purple `FQ` monogram inside the suite-shared brass gear ring. FlipQueue is the canary — its live user base means any regression surfaces fastest and a clean cutover here validates the pattern before Tempo and Maxcraft follow.

## Reproduction

**Why this work exists:**
- Cogworks v0.6.0 (shipped 2026-04-21) adds `lib:RegisterCogMinimapButton(addonName, dataobject, savedvars)` — a wrapper around `LibDBIcon:Register` that also calls `LibDBIcon:SetButtonBorder` to swap the default circular border for the Chronoforge gear ring (`Interface\AddOns\Cogworks\Art\CogBorder`, 50×50).
- All five suite cogs get the same gear border externally; per-cog identity comes from the inner icon (bold monogram on a signature-color disc — see `cogworks/feedback/collection/COG-004-minimap-icon-standard.md`).
- FlipQueue's ship-ready inner icon is already at `Art/fq-inner.tga` (committed as `3d9814d` on master; gold FQ on deep purple, per the standard).

**Current state in FlipQueue:**
- `.pkgmeta` pins Cogworks external to `tag: v0.1.0` — predates the wrapper, needs to bump to `v0.6.0`.
- `UI/MinimapButton.lua` calls `LDBIcon:Register(...)` directly at line 91; `ICON_TEXTURE` at line 8 points at the old detailed `flipqueue-icon` illustration (too busy at 18×18).

## Attempts

- **2026-04-21**: Brief written. Execution pending.

## Notes

### Prereqs already in place (do NOT re-do)
- `Art/fq-inner.tga` exists (30 KB TGA, gold FQ monogram on deep purple, valid TRUEVISION header) — verify with `ls -la Art/fq-inner.tga`.
- Cogworks v0.6.0 tagged and live on CurseForge/Wago.

### The surgical changes (three files)

**1. `UI/MinimapButton.lua` — two edits:**

Line 8 — swap icon texture path:
```lua
-- OLD
local ICON_TEXTURE = "Interface\\AddOns\\flipqueue\\Art\\flipqueue-icon"
-- NEW
local ICON_TEXTURE = "Interface\\AddOns\\flipqueue\\Art\\fq-inner"
```

Lines 90–92 — rewrite the registration block with a soft-degrade fallback so users with an older embedded Cogworks (or running without Cogworks at all somehow) don't lose their minimap icon:
```lua
-- OLD
local broker = LDB:NewDataObject("FlipQueue", dataObject)
LDBIcon:Register("FlipQueue", broker, ns.db.settings.minimapIcon)
registered = true

-- NEW
local broker = LDB:NewDataObject("FlipQueue", dataObject)

local Cogworks = LibStub:GetLibrary("Cogworks-1.0", true)
if Cogworks and Cogworks.RegisterCogMinimapButton then
    Cogworks:RegisterCogMinimapButton("FlipQueue", broker, ns.db.settings.minimapIcon)
else
    -- Soft-degrade: older embedded Cogworks (< v0.6.0) or library absent.
    -- Falls back to LibDBIcon direct registration; player sees the old
    -- circular border, no gear ring, but no regression.
    LDBIcon:Register("FlipQueue", broker, ns.db.settings.minimapIcon)
end
registered = true
```

The `UI:ShowMinimapButton` / `UI:HideMinimapButton` / `UI:ToggleMinimapButton` / `UI:IsMinimapButtonShown` functions below still call `LDBIcon:Show/Hide/IsRegistered` directly — those are fine, the button is registered with LibDBIcon either way (Cogworks just wraps, doesn't replace).

**2. `.pkgmeta` — bump Cogworks external tag:**
```yaml
# OLD
externals:
  Libs/Cogworks-1.0:
    url: https://github.com/gezmodean-wow/cogworks.git
    tag: v0.1.0
    path: Cogworks-1.0

# NEW
externals:
  Libs/Cogworks-1.0:
    url: https://github.com/gezmodean-wow/cogworks.git
    tag: v0.6.0
    path: Cogworks-1.0
```

**3. In-game verification (BEFORE tagging/pushing):**

Because `.pkgmeta` externals fetch at package time, the local `Libs/Cogworks-1.0/` copy in the working tree is whatever was last packaged. For live in-game testing you need the new library present. Options (pick one):

- **Fastest**: copy the updated `Cogworks-1.0.lua` from `C:/src/cogworks/Cogworks-1.0/Cogworks-1.0.lua` over `C:/src/flipqueue/Libs/Cogworks-1.0/Cogworks-1.0.lua` for the duration of local testing. This is temporary — when the packager next runs, the external fetch overwrites it anyway. Do NOT commit this manual copy in flipqueue; it's just for local `/reload` verification.
- **Cleanest**: run the BigWigsMods packager locally (it fetches the v0.6.0 external and assembles the full zip). Heavier.

### In-game verification checklist (required before tag + push)

After the code changes + local Cogworks-1.0 refresh + `/reload`:

- [ ] Minimap button renders: gear-shaped brass border (not the default circular tracking border).
- [ ] Inner icon: gold **FQ** monogram on deep purple disc visible inside the gear.
- [ ] Left-click toggles the main window (existing behavior).
- [ ] Middle-click toggles mini view (existing behavior).
- [ ] Right-click opens settings (existing behavior).
- [ ] Drag repositions the button (existing behavior).
- [ ] Tooltip shows: title + pending/posted counts if relevant + the Left/Middle/Right/Drag hint lines.
- [ ] `/fq minimap` or equivalent Hide/Show toggle still works via `UI:HideMinimapButton` / `UI:ShowMinimapButton`.
- [ ] Reload UI (`/reload`) — button reappears in the same position.
- [ ] AddonCompartment (if the player uses it): FlipQueue entry shows only the inner icon, no gear ring — expected; compartment doesn't use button borders.
- [ ] Squint test: at default minimap size, the FQ monogram is cleanly readable; distinct from whatever else is near it on the minimap ring.
- [ ] Soft-degrade: temporarily revert the local Cogworks-1.0 to an older copy (or rename it) and `/reload` — the fallback `LDBIcon:Register` path should still register a working (circular-bordered) button with no error. Restore afterward.

### Soft-degrade rationale

FlipQueue has live CurseForge/Wago users. Some may have older Cogworks embedded in conflict — the packager bundles v0.6.0, but runtime LibStub upgrade rules mean the newest-loaded-MINOR wins. If something breaks that logic or Cogworks is absent, the fallback keeps the minimap button working. This is defensive; expected path is that Cogworks v0.6.0 from the bundled external wins and the wrapper fires.

### What NOT to do

- **Do NOT** delete the old `Art/flipqueue-icon.tga`, `Art/flipqueue-banner.tga`, or `Art/flipqueue-logo.tga` files yet. They may still be referenced by CurseForge/Wago project page art or by non-minimap UI code. Retirement of old icons is a separate follow-up commit after confirming no references.
- **Do NOT** tag or push the release without explicit user go-ahead per the suite-wide release policy (see `C:/Users/gezmo/.claude/projects/C--src-cogworks/memory/feedback_human_gate_before_release.md`). In-game verification by the user is a human gate.
- **Do NOT** modify the `UI:ShowMinimapButton` / `UI:HideMinimapButton` / `UI:ToggleMinimapButton` / `UI:IsMinimapButtonShown` helpers — they operate on LibDBIcon and continue to work unchanged.
- **Do NOT** touch `ns.db.settings.minimapIcon` migration logic (lines 74–88) — it's still correct; the saved-variable shape is identical whether Cogworks or LibDBIcon owns the button.
- **Do NOT** commit a local-testing copy of `Libs/Cogworks-1.0/Cogworks-1.0.lua` — that library is packaged from the external, not vendored.

## Next steps

Execute in order. Commit after step 4; pause for user review/verification before step 6 onward.

1. **Verify prereqs**:
   - Confirm `Art/fq-inner.tga` exists (~30 KB, valid TGA).
   - Confirm Cogworks v0.6.0 is tagged: `git -C C:/src/cogworks tag --list v0.6.0`.

2. **Apply the three edits** described in Notes above:
   - `UI/MinimapButton.lua` line 8: swap `ICON_TEXTURE`.
   - `UI/MinimapButton.lua` lines 90–92: rewrite the registration block with soft-degrade.
   - `.pkgmeta`: bump Cogworks external tag `v0.1.0` → `v0.6.0`.

3. **Refresh local Cogworks copy** for in-game testing:
   - `cp C:/src/cogworks/Cogworks-1.0/Cogworks-1.0.lua C:/src/flipqueue/Libs/Cogworks-1.0/Cogworks-1.0.lua`
   - This is a local-only step; do not stage or commit.

4. **Commit the code changes** in flipqueue:
   - Stage: `UI/MinimapButton.lua`, `.pkgmeta`, and the FQ-002 feedback doc update (add Attempts entry).
   - Do NOT stage `Libs/Cogworks-1.0/Cogworks-1.0.lua` (local-test artifact).
   - Message: `feat(FQ-002): adopt Cogworks v0.6.0 gear-border minimap chrome`
   - Include Co-Authored-By trailer.

5. **Hand back to the user for in-game verification.** Print the checklist from Notes. User runs through it at their own pace and reports results. If anything fails, append Attempts entry describing the failure and do NOT proceed to step 6.

6. **Only after user confirms verification passes**: ask for explicit go on tag + push. Version choice depends on FlipQueue's current tag history (check `git tag --sort=-creatordate | head -5`); this is likely an alpha bump of the current track. Per suite convention: `vX.Y.Z-alphaN` → ships to alpha channel on CurseForge/Wago.

7. **Update FQ-002 Attempts** with the final commit SHA and release tag once shipped. `/feedback-promote FQ-002 --to <version>` moves the doc into `releases/<version>/` when ready.

### Related tracked issues (context — do not execute in this session)

- `cogworks/feedback/collection/COG-003-minimap-gear-border.md` — the library-side wrapper (shipped).
- `cogworks/feedback/collection/COG-004-minimap-icon-standard.md` — the inner icon design standard (all five TGAs distributed; FlipQueue is the canary).
- `tempo/feedback/` and `maxcraft/feedback/` — same adoption pattern will land there next, after FlipQueue's canary confirms.
