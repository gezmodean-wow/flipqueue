---
id: FQ-004
cog: flipqueue
status: triaged
title: Tools drawer icons need service-type labels (AH / Bank / Warbank / Mailbox)
sources:
  - type: internal
    session: 2026-04-21
    note: Relayed from player reports via gezmodean
  - type: discord
    thread: https://discord.com/channels/1489375376760373473/1496405587100041307
    date: 2026-04-22
    note: Chronoforge tracking thread
reporters: [gezmodean]
created: 2026-04-21
updated: 2026-04-22
release: null
tags: [tools-drawer, ui, labels]
---

## Summary

The Tools drawer shows icons for each summon/toy but no textual indication of what service each one opens. Players have to recognize the icon to know whether a row is AH, Bank, Warbank, or Mailbox. A small label above (or next to) each tool would make the drawer self-explanatory.

## Reproduction

Open mini → open Tools drawer. Observe: icons only, no service type hint.

## Notes

- Current layout in `UI/ToolDrawer.lua`: `serviceButtons[i] = CreateServiceButton(innerFrame, svc, i)` — one icon button per enabled service. The service type (`svc.type`) is already known at creation time; it just isn't surfaced visually.
- Straightforward add: short text label above or beside the icon rendering `(AH)`, `(Bank)`, `(Warbank)`, `(Mailbox)`. Dim color to avoid competing with the icon.
- Consider whether the label should be always-visible or only on hover — always-visible is clearer for new users; hover-only is cleaner visually. Default to always-visible since the drawer is opt-open anyway.

## Next steps

1. Add a FontString per service button anchored TOP (above the icon) or LEFT (beside, if horizontal room allows). Text from `svc.type` mapped to a human label.
2. Ensure the label fits the drawer's current 40px icon / 66px frame width without clipping.
3. Verify alignment stays clean when paired with FQ-005's planned map-pin "find" indicator to the right of the icon.
