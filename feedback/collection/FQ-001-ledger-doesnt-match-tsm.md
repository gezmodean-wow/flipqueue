---
id: FQ-001
cog: flipqueue
status: investigating
title: Ledger doesn't match TSM sales records
sources:
  - type: discord
    thread: https://discord.com/channels/1489375376760373473/1494013727295406161/1496027121112580178
    date: 2026-04-21
    reporter: gezmodean
reporters: [gezmodean]
created: 2026-04-20
updated: 2026-04-20
release: null
tags: [ledger, tsm]
---

## Summary

FlipQueue's ledger view is reporting sales figures that don't line up with the equivalent TSM sales records. Reporter flagged it as an observable discrepancy but didn't specify magnitude, timeframe, or which ledger view is affected.

## Reproduction

Needs more info. No repro steps supplied in the opening post.

Open questions to resolve:
- Which ledger screen / tab? (Lifetime, per-character, per-item, date-range filter?)
- What TSM export/report was used as the comparison? (TSM Accounting sales CSV? Ledger tab in-game? `/tsm sales`?)
- Timeframe of the mismatch (e.g. "last 7 days", "all time").
- Sample: one item where the delta is clearest (itemID, FlipQueue's number, TSM's number, expected).
- Does it affect cross-realm sales, cross-character, connected-realm aggregation, or all of them?

## Attempts

<None yet.>

## Notes

### Thread opening — 2026-04-21 by gezmodean

> The ledger doesn't currently match my sales records from TSM

## Next steps

1. In-thread: ask the above reproduction questions so we have a concrete delta to investigate.
2. Once we have a sample mismatch, check:
   - `SalesIndex.lua` — is the sales aggregation correctly collapsing per itemKey?
   - `TrackerMail.lua` / `TrackerAuctions.lua` — is anything being double-counted or dropped when mail expires / auctions settle?
   - Cross-realm / connected-realm logic in `RealmData.lua` / `TSMRealms.lua`.
   - The itemKey format (`itemID;bonusIDs;modifiers`) — could be that TSM's key shape differs on certain items (e.g. warbound-until-equipped, crafted rank items) and the ledger is splitting or merging rows differently.
3. If the gap is consistent and directional (FlipQueue always lower/higher than TSM), suspect a single missing source (e.g. COD mail, cross-realm trade, auction cancellations). If it's random, suspect a key-matching bug.
