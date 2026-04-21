---
id: FQ-007
cog: flipqueue
status: investigating
title: ADDON_ACTION_BLOCKED on Hide() of FlipQueueToolClip during combat
sources:
  - type: internal
    session: 2026-04-21
    note: Relayed from player reports via gezmodean with BugGrabber trace
reporters: [gezmodean]
created: 2026-04-21
updated: 2026-04-21
release: null
tags: [combat, taint, tool-drawer, addon-action-blocked]
---

## Summary

When the UI tries to hide during combat (likely the `hideInCombat` mini-view setting or a related visibility toggle), the Tool drawer's clip frame `:Hide()` call is blocked by WoW's combat lockdown. Fires 3x per hide attempt (error message reads `3x [ADDON_ACTION_BLOCKED]`).

## Reproduction

1. Enter combat.
2. Trigger whatever condition causes the mini view to hide (combat-hide setting, user toggle, etc.) and propagates to `RefreshToolDrawer`.
3. Observe `[ADDON_ACTION_BLOCKED]` error popup.

## Error trace (BugGrabber)

```
3x [ADDON_ACTION_BLOCKED] AddOn 'flipqueue' tried to call the protected function 'FlipQueueToolClip:Hide()'.
[!BugGrabber/BugGrabber.lua]:540: in function '?'
[!BugGrabber/BugGrabber.lua]:524: in function <!BugGrabber/BugGrabber.lua:524>
[C]: in function 'Hide'
[flipqueue/UI/ToolDrawer.lua]:890: in function 'RefreshToolDrawer'
[flipqueue/UI/ToolDrawer.lua]:1022: in function <flipqueue/UI/ToolDrawer.lua:1001>

Locals:
  event="ADDON_ACTION_BLOCKED"
  addonName="flipqueue"
  addonFunc="FlipQueueToolClip:Hide()"
```

## Root cause (initial read)

`FlipQueueToolClip` is our clip frame (`UI/ToolDrawer.lua:EnsureDrawer`, clipFrame = `CreateFrame("Frame", "FlipQueueToolClip", mini)`). It's parented to `FlipQueueMiniFrame`. Under combat lockdown, frames that are descendants of protected UI (or that Blizzard has begun treating as protected through any taint chain — e.g. via `SetParent` onto a secure parent, or via being referenced from a secure OnClick) cannot have their `:Show()` / `:Hide()` called from non-secure code.

The stack shows `RefreshToolDrawer` at `ToolDrawer.lua:890` is the caller — needs investigation of that line to see what condition triggered the hide and whether it should be gated on `InCombatLockdown()`.

## Notes

- This is a classic WoW combat-taint issue, not a logic bug. The fix pattern is:
  1. Gate the `:Hide()` call on `not InCombatLockdown()`.
  2. If combat is active, register for `PLAYER_REGEN_ENABLED` and perform the hide then.
  3. Or mark the drawer non-secure / detach it from any secure ancestor (usually not applicable; the mini view is intentionally parented to a combat-safe frame).
- Similar pattern may affect the Context drawer (`FlipQueueContextClip`) — audit both drawers in one pass.
- Also affects: any `:SetShown`, `:SetSize`, `:ClearAllPoints`, `:SetPoint` calls that cascade from the refresh path. Combat lockdown is broad.

## Next steps

1. Read `UI/ToolDrawer.lua:890` and surrounding `RefreshToolDrawer` to see what branch leads to the `:Hide()` call.
2. Wrap the hide + any related size/position updates in `if InCombatLockdown() then ... else ... end`; defer the deferred path to `PLAYER_REGEN_ENABLED`.
3. Audit `UI/ContextDrawer.lua` for the same pattern.
4. Repro after fix: enter combat, trigger hide, verify no `ADDON_ACTION_BLOCKED` fires; leave combat, verify drawer state catches up to whatever it should be.
