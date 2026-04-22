---
id: FQ-003
cog: flipqueue
status: fixed-awaiting-verification
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
release: v0.11.1-candidate
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

### 2026-04-22 — ilvl-variant divergence: three distinct bugs

Concrete repro: Tarnished Dawnlit Signet (itemID 258909) with ilvl-85 and ilvl-87 variants in bags. TSM posts at 120g (ilvl-85, undercutting the market low) and 819g (ilvl-87, normalPrice for that variant). FlipQueue posted both at `normalCopper = 17,093g` or skipped as "below min (no reset)" — evaluating the same per-base-item numbers for both variants. Debug log showed both variants resolving to `normal=170934381 min=77697446` — a dead giveaway that the ilvl modifier wasn't reaching TSM.

Root cause: three independent bugs along the same path.

1. **`TSM:ItemKeyToTSMString` dropped the modifier segment.** It parsed `itemID;bonusIDs` and threw away the third `;` segment (the modifier list, where modifier 9 = ilvl lives). Both `258909;13729:13668;9=85` and `...;9=87` produced `i:258909::2:13729:13668` — indistinguishable. TSM's `GetCustomPriceValue` returned the base item's dbmarket for every variant, so `normalPrice`, `minPrice`, and `maxPrice` collapsed.
   **Fix:** route through `ns:ItemKeyToItemString` (which already handles modifiers correctly) + `TSM_API.ToItemString` so TSM canonicalizes the WoW item string itself. Fallback to manual construction matching TSM's internal `i:<id>:<rand>:<numBonus>:<bonuses...>:<numMods>:<type>:<val>:...` format when the API path fails.

2. **`GetOwnLowestBuyout` matched only on `itemID`.** If we owned a low-ilvl listing of the same base item, the match-own branch triggered against the wrong variant's price — ratcheting the high-ilvl post down to whatever the low-ilvl listing sits at. That's the self-undercut.
   **Fix:** extract the modifier-9 ilvl from the fqKey and filter `auction.itemKey.itemLevel == targetIlvl` on the owned-auction scan. Blizzard groups AH listings by exactly that quartet.

3. **Context drawer tooltip displayed `normalCopper` as "Post price" when the decision was `skip`.** `buyoutCopper` was nil in the below-min-no-reset branch, so the old `buyoutCopper or normalCopper` fallback showed the 17.1k baseline — looked like a post intention but wasn't. Same bug on the row's inline `Post:` label.
   **Fix:** show explicit "skip (below min)" / "skip (above max)" in both the tooltip headline and the inline row label. Normal price stays as a secondary "Normal:" row so the baseline is still visible without pretending to be the post price.

Files touched: `TSM.lua:ItemKeyToTSMString`, `AuctionPost.lua:GetOwnLowestBuyout` + call site in `ResolvePostPrice`, `UI/ContextDrawer.lua` row + tooltip. Awaiting in-game verification: same item, same TSM op, expect FlipQueue's `AH lowest` / `Normal` / decided post price to match TSM's Post Scan per variant.

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
