---
id: FQ-003
cog: flipqueue
status: investigating
title: Posting algorithm still doesn't match TSM despite v0.11.0 rewrite
sources:
  - type: internal
    session: 2026-04-21
    note: Relayed from player reports via gezmodean post-v0.11.0
  - type: discord
    thread: https://discord.com/channels/1489375376760373473/1496027121112580178
    date: 2026-04-22
    reporter: gezmodean
    note: Player-originated thread ("ledger doesn't match TSM"), folded in as canonical FQ-003 tracker
reporters: [gezmodean]
created: 2026-04-21
updated: 2026-04-22
release: null
tags: [posting, tsm, auction, critical]
---

## Summary

Despite the v0.11.0 `ResolvePostPrice` rewrite to mirror TSM's `MakePostDecision`, players are still seeing a mismatch. Concrete symptom: "I am consistently cancelling scans and then re-posting with TSM" — meaning FlipQueue posts at a price, then TSM's cancel scan flags those auctions as cancellable, and the player re-posts via TSM at a different (higher, presumably) price.

This is a critical follow-up to FQ-001 / v0.11.0. The whole point of the MakePostDecision mirror was to post at the same price TSM would.

## Reproduction

Needs concrete repro details to investigate:
- Which item(s) is FlipQueue posting at a different price from TSM's Post Scan?
- What does FlipQueue's tooltip show for "Post price:", "AH lowest:", "Your lowest:", "Reason:" for that item?
- What price does TSM's Post Scan want to post the same item at?
- What's the TSM Auctioning operation's `normalPrice`, `minPrice`, `maxPrice`, `undercut`, `priceReset`, `aboveMax`, `postCap` for the group this item belongs to?

## Attempts

- **2026-04-21** (v0.11.0, commit `46f4761`): `ResolvePostPrice` rewritten to implement TSM's `MakePostDecision` branch tree (undercut market / match own / priceReset / aboveMax / clamp min). Uses TSM's stored operation settings as the authority, evaluates every price expression via `TSM_API.GetCustomPriceValue`. Self-match branch added so we don't self-undercut when our own listing is the market lowest. Audit-drift guard pinned to TSM v4.14.66. Result: player still reports divergence with TSM's Post Scan.

## Notes

- Known gaps in the v0.11.0 implementation:
  - **Blacklist/whitelist seller matching** — not implemented. Requires live AH scan data (seller identity), which we don't have. If the player's operation uses blacklist or whitelist, we'll diverge. Check whether the player has these configured.
  - **DBMinBuyout staleness** — we undercut the TSM cached scan value, not a live query result. Between scans the real market can move and our "market lowest" is stale.
  - **Stack size for commodities** — we pass `quantity = totalToPost` to `PostCommodity`, which creates one market listing at that quantity. TSM's `stackSize` setting, when used, might split into multiple stacks. Check if the player's operation has `stackSize` > 1.
  - **Live vs cached identity** — TSM's cancel scan runs against a fresh AH scan and knows the seller of each listing. It may flag our post as "cancellable — you're undercutting yourself" in a way our DBMinBuyout-based code can't anticipate.

- The tooltip in the Context drawer now shows `AH lowest`, `Your lowest`, and `Reason:` for each scanned item. Asking the player to screenshot that tooltip for a divergent item would be the fastest route to identifying the specific decision-tree branch that's wrong.

- `/fq debug` captures `[AuctionPost] ResolvePostPrice: ... -> buyout=X (reason)` on every scan — that line logs every input (`lowest`, `own`, `normal`, `min`, `max`, `uc`) and the resulting buyout. Worth enabling debug and grabbing a few lines during the next scan.

## Next steps

1. Ask for concrete repro: one specific item where FlipQueue's price diverges from TSM's Post Scan, with tooltip values and the operation's full config.
2. Run `/fq debug` to capture the ResolvePostPrice debug line for that item.
3. Compare against TSM's own Post Scan result side-by-side.
4. If the divergence is in the blacklist/whitelist path or live-scan-required data, the fix is the TSM API request (`docs/tsm-api-request.md`) — escalate that.
5. If the divergence is in the `aboveMax` / `priceReset` / `stackSize` handling, patch the decision tree and bump `TSM_AUDITED_VERSION`.

## Priority

**Critical.** This undermines the v0.11.0 posting engine's credibility. Players who see FQ post at the "wrong" price will fall back to TSM entirely, which defeats the point of posting from FQ's drawer.
