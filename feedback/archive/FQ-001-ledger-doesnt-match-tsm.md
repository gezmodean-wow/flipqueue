---
id: FQ-001
cog: flipqueue
status: shipped
title: Ledger doesn't match TSM sales records
sources:
  - type: discord
    thread: https://discord.com/channels/1489375376760373473/1494013727295406161/1496027121112580178
    date: 2026-04-21
    reporter: gezmodean
reporters: [gezmodean]
created: 2026-04-20
updated: 2026-04-21
release: v0.11.0
tags: [ledger, tsm, reconciliation, mail, auctions]
---

## Summary

Two observable symptoms, three underlying bugs. The "N active auctions" character badge drifts out of sync with the actual auction house (e.g. showing 1/3/2 when AH has 0/2/3). The ledger doesn't reliably distinguish sold vs expired over time — many rows end up counted as neither, and sales that TSM recorded never show up in FlipQueue's post history.

## Reproduction

Affects all realms/characters once any of the three contributing bugs fires:

- Post auctions, cancel some, let some expire, let some sell — the "N active" badge drifts relative to the actual AH listing count across sessions.
- Compare FlipQueue's ledger against TSM's Accounting sales export over the same window: sales present in TSM are missing (or classified as `expired` / `collected` without `saleOutcome`) in FlipQueue.

## Attempts

- **2026-04-20** (working-tree on master, uncommitted): Fix for all three contributing bugs. In-game verification in progress before commit + alpha tag. Files touched: `TrackerMail.lua` (removed pre-emptive flip, added post-scan cleanup), `TrackerAuctions.lua:CheckOwnedAuctions` (rewritten as three clean phases), new `TrackerTSMReconcile.lua` (direct `TradeSkillMasterDB` CSV parse with per-entry idempotent upgrade flag), `Tracker.lua` (fires `ReconcileWithTSM(false)` 2s after owned-auction reconcile on AH open, 1h throttle), `flipqueue.toc` (registers new file), `UI/SlashCommands.lua` (`/fq reconcile` + `/fq reconcile reset`). Per project policy, no commit/tag until in-game verification passes. See **Root cause** and **Fix details** in Notes.

- **2026-04-20** (commit `6c62771`): Code committed to master as `fix: reconcile active auction drift and upgrade sold outcomes via TSM`. Not yet tagged — alpha release pending. In-game verification continues; tag + push when ready for testers.

- **2026-04-21** (tag `v0.11.0`, commit `46f4761`): Shipped to stable. TSM reconciliation verified solved in live testing by @gezmodean — ledger entries upgrade to `sold` correctly when TSM has a matching sale, active-auction badge stays aligned with the AH across post / cancel / expire / sell cycles, `/fq reconcile` sweep produces sensible upgrades. Same-item-within-48h cross-match caveat documented for future tester reports; `/fq reconcile reset` escape hatch is in place.

## Notes

### Thread opening — 2026-04-21 by gezmodean

> The ledger doesn't currently match my sales records from TSM

### Root cause (three distinct bugs)

1. **MAIL_SHOW ordering bug** (`TrackerMail.lua`). The `MAIL_SHOW` handler pre-emptively flipped all expired/cancelled entries to `collected` before `ScanMailForSales` ran (1s later). Because the scan built its match set from `auctionStatus == "expired"`, there were no expired entries left to match returned-item mail against. Downstream: `postHistory` / `postAttempts` / `totalFeesSpent` tracking never fired on the normal flow; cancelled→collected transitions didn't set `saleOutcome`, leaving rows counted as neither sold nor failed.

2. **Reconciliation drift** (`TrackerAuctions.lua:CheckOwnedAuctions`). Orphan recovery ran before stale-entry reconciliation; both matched by stripped `itemID` only. A stale "active" log entry coexisting with a newly-posted auction for the same item could conflict between the two phases, producing off-by-one drift in the "N active" badge.

3. **No TSM cross-check**. TSM writes every AH sale to `TradeSkillMasterDB["r@<realm>@internalData@csvSales"]`, but FlipQueue never read it. Any sale where the gold-mail scan failed (missed session, name mismatch, pre-emptive flip swallowing the match) stayed `expired` / `collected-expired` forever with no way to recover ground truth.

### Fix details

- `TrackerMail.lua` — removed the MAIL_SHOW pre-emptive flip. `ScanMailForSales` now includes cancelled entries in its match set and does a post-scan cleanup pass finalizing unmatched expired/cancelled/stale-collected entries with the correct `saleOutcome`.
- `TrackerAuctions.lua:CheckOwnedAuctions` — rewritten as three clean phases: todo match → count-based reconcile per `itemID` (oldest excess entries marked stale) → orphan recovery for unmatched owned auctions. `#owned == 0` folded into the general path. Added `AuctionItemID` / `EntryItemID` helpers.
- `TrackerTSMReconcile.lua` (new file) — parses TSM's `csvSales` CSV directly, indexes by `(charKey, baseItemID)` with whitespace-normalized charKeys. Upgrades eligible log entries (`expired` / `cancelled` / `collected`-without-`saleOutcome`, not yet `_tsmReconciled`) whose TSM sale timestamp falls within `postedAt ± 1h .. postedAt + 49h`. Idempotent per-entry flag, reset on `PLAYER_LOGIN` since TSM rewrites its CSV on logout. Also finalizes unresolvable-but-definitely-closed entries as `saleOutcome = expired`.
- `Tracker.lua` — fires `ReconcileWithTSM(false)` 2s after the owned-auction reconcile on AH open, throttled to once per hour.
- `flipqueue.toc` — registers the new file.
- `UI/SlashCommands.lua` — adds `/fq reconcile` (verbose manual sweep) and `/fq reconcile reset` (clear per-entry `_tsmReconciled` flags — escape hatch for when a bad cross-match gets locked in).

### Known failure mode in the fix

TSM reconcile matches by `charKey + base-itemID + time window`. Two of the same item posted by the same character within 48h could theoretically cross-match — i.e. entry A gets attributed to the sale that actually belonged to entry B. Mitigation: `/fq reconcile reset` clears the `_tsmReconciled` flag per entry for retry. Worth watching for in tester reports.

## Next steps

1. **In-game verification pass** (pre-alpha): post + cancel + expire + sell cycles across multiple characters; verify badge count stabilizes to AH reality; confirm `/fq reconcile` sweep produces sensible upgrades; specifically probe the same-item-within-48h cross-match case.
2. **Commit + tag** once verified. Suggested commit: `fix(FQ-001): reconciliation overhaul — mail ordering, auction counts, TSM cross-check`, followed by a `vX.Y.Z-alphaN` tag. Packager ships to CurseForge/Wago alpha channel.
3. **Post to Discord thread** via `/feedback-ask FQ-001 --ready-to-test` (draft flow — user approves before bot posts). Target audience: alpha-channel testers. Message should ask them to:
   - Before updating: note current "N active" badge vs. AH reality per character; note any log entries they suspect are misclassified.
   - After updating: open AH on each character to trigger reconcile + TSM pass; check badge counts; run `/fq reconcile` manually for a verbose sweep.
   - Report back: before/after deltas, any expired→sold upgrades that look wrong.
   - Escape hatch: `/fq reconcile reset`.
4. **Flip status** `in-progress` → `ready-to-test` when the alpha is live and the Discord post is up. Run `/feedback-promote FQ-001 --to <version>` to move the doc into `releases/`.
5. **On confirmation** from testers, append to Attempts: "Confirmed fixed by <user(s)> in vX.Y.Z". Then `/feedback-promote FQ-001 --ship <version>` moves to archive.
