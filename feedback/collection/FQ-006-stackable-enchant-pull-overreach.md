---
id: FQ-006
cog: flipqueue
status: investigating
title: Pulls full stack of stackable items (e.g. weapon enchants) when only N are being sold
sources:
  - type: internal
    session: 2026-04-21
    note: Relayed from player reports via gezmodean
  - type: discord
    thread: https://discord.com/channels/1489375376760373473/1496405746462494770
    date: 2026-04-22
    note: Chronoforge tracking thread
reporters: [gezmodean]
created: 2026-04-21
updated: 2026-04-22
release: null
tags: [bank, pull, deposit, quantity, stackables]
---

## Summary

For stackable items like weapon enchants, FlipQueue pulls the entire bank stack when the task only needs a small quantity (e.g. pulls 20 when the sell task is for 5). The excess triggers spurious deposit tasks to put the rest back. On returning to the warbank, the excess isn't automatically deposited either.

## Reproduction

1. Have a stack of ~20 of a weapon enchant (or other stackable AH-viable item) in the warbank.
2. Have a to-do task to sell 5 of that item from a character.
3. Open bank on that character → auto-pull runs → observe: all 20 get pulled to bags.
4. Open warbank again → observe: the 15 excess are not auto-deposited back.

## Notes

- Related to `#6` (Improved Post Detection) and the pull quantity logic in `Tracker:BuildPullOps`. Likely culprits:
  - `BuildPullOps` computes `stillNeeded = targetQty - inBags`, then matches bank/warbank slots to fulfill. When a slot's `stackCount` > `stillNeeded`, the whole slot's stack still gets moved because `C_Container.UseContainerItem` (or equivalent) doesn't split — it moves the whole slot.
  - Splitting would require `C_Container.SplitContainerItem` pre-move, which adds a new failure surface (cursor state, delayed container updates).
- For the follow-up deposit: `BuildDepositOps` builds ops from `depositFrom` tasks. If the excess wasn't assigned as a deposit task (because it's "extra" not "needed elsewhere"), it won't surface. `BuildExtraDepositOps` covers extras but may be filtering stackables out or treating them as "keep on character".
- Separate but related: when the player posts fewer than pulled (5 of 20), the remaining 15 should auto-deposit on next bank visit. Today that appears not to happen.

## Next steps

1. Trace a concrete case: task for 5 weapon enchants, 20 in bank → run `/fq debug` and capture the `BuildPull: ... inBags=0 need=5` line and the subsequent pull + deposit flow. Confirm which step over-pulls.
2. Decide the split strategy:
   - **Option A — pre-split in bank:** call `C_Container.SplitContainerItem(bank, slot, stillNeeded)` before the move. Cleaner outcome but adds a failure mode (split fails on some containers).
   - **Option B — post-pull deposit of excess:** accept the over-pull, detect the delta after the move, auto-generate a deposit op for the excess. Simpler to implement, leaves a visible round-trip for the player.
   - **Option C — don't pull stackables automatically past `stillNeeded`:** require player to pull manually for the excess. Most conservative but degrades the auto-pull UX for this class of item.
3. Audit `BuildExtraDepositOps` for why the excess isn't getting deposited on the return trip to the warbank.
