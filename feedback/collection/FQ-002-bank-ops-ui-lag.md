---
id: FQ-002
cog: flipqueue
status: investigating
title: Bank operations UI lags behind actual moves; no pause indicator
sources:
  - type: internal
    session: 2026-04-21
    note: Relayed from player reports via gezmodean
  - type: discord
    thread: https://discord.com/channels/1489375376760373473/1496405501704142908
    date: 2026-04-22
    note: Chronoforge tracking thread
reporters: [gezmodean]
created: 2026-04-21
updated: 2026-04-22
release: null
tags: [bank, ui, progress, pause]
---

## Summary

The Bank Operations popup's progress display lags far behind the actual item movements the player sees in their bags/bank. Player deposited 7 items from their bag with no visible update in the popup, paused, then deposited more — the popup stayed stale throughout and gave no indication that a pause was in effect.

## Reproduction

1. Open bank → bank ops popup triggers with deposit/pull ops.
2. Execute a batch that includes multiple deposits (e.g. 7+ items).
3. Observe: items physically move between bag and bank in-game, but the popup's progress bar / row list doesn't reflect those moves promptly.
4. Pause the automation mid-batch.
5. Observe: popup shows no pause indication; still looks like it's "working".

## Notes

- The bank popup's progress reporting was rewritten in v0.10.1-alpha3 and v0.11.0-era work — `BankOpProgress` / `ShowCompletionSummary` / `BankPopupComplete` all emit debug lines to the ring buffer so the execution timeline is captured in `/fq debug`. Grab a copy of those lines during a repro.
- Two related surfaces that might be out of sync:
  1. The popup's row transitions (items marked done) — driven by `BankQueue:ProcessSync`/`Process` callbacks and threaded through `BankOpProgress`.
  2. The progress bar fill — reconciled via `ShowCompletionSummary`'s drift guard, but that only runs on completion. Mid-execution drift isn't corrected.
- Pause: `ns._automationPaused` is the flag. It's consulted at `BuildPullOps` / `BuildDepositOps` time, but once a batch is in flight the popup has no "paused" visual.

## Next steps

1. Reproduce with `/fq debug` console open; capture the `[bank-popup]` debug lines during a stale update and attach them here.
2. Check whether `BankOpProgress` is firing on every real move or only on batch boundaries — if the async path doesn't call back per-move, the popup gets stale.
3. Add an explicit pause visual to the popup: dim the rows + show "Paused — N remaining" in the status line when `ns._automationPaused` flips true mid-execution.
4. Consider pushing incremental progress updates from `BankQueue`'s inter-move wait (every `BAG_UPDATE_DELAYED` that a move actually lands) rather than only per-op-complete.
