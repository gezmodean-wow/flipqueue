# TSM API request: expose auctioning post-decision

Drafted by the FlipQueue team for submission to the TradeSkillMaster upstream (GitHub issue / Discord / direct contact to the TSM maintainers). The core ask is a small, read-only addition to `TSM_API` that lets companion addons post items via Blizzard's AH API using TSM's own operation logic as the authoritative source.

---

## The situation

`TSM_API` today exposes:

- `TSM_API.GetCustomPriceValue(customPriceStr, itemString)` — evaluate a TSM custom price expression for an item.
- `TSM_API.GetGroupPathByItem(itemString)` — find the group an item belongs to.
- Inventory, profile, group, and money-formatting helpers.

It does **not** expose the posting decision that TSM's Auctioning module makes internally. That decision lives in `LibTSMSystem/Source/Operation/AuctioningOperation.lua:MakePostDecision`, which combines:

- The operation's `minPrice` / `normalPrice` / `maxPrice` / `undercut` / `priceReset` / `aboveMax` / `bidPercent` / `postCap` / `duration` / `stackSize` / `blacklist` settings (each of which may be a literal or a TSM price expression).
- The current lowest auction's buyout **and seller identity** from a live AH scan.
- Per-player state (our own active auctions for the item, whitelist entries, blacklist entries).

From an external addon's position that full picture isn't reachable: we can read operation settings out of `TradeSkillMasterDB`, evaluate any single price expression via `GetCustomPriceValue`, and get our own auctions via Blizzard's `C_AuctionHouse.GetOwnedAuctions`. What we can't get is **the decision** — the combined "given these settings, this market, and this player state, here is the price and quantity TSM would post at."

## What this costs players

Any companion addon that wants to post via TSM's rules (FlipQueue, Point Blank Sniper integrations, workflow tools, addon suites bundling sales pipelines) faces a choice:

1. **Reimplement `MakePostDecision`.** Walk TSM's branch tree in our own code. This is what FlipQueue does today. It's fragile — TSM refactors the function across versions, adds branches for new settings, changes defaults — and the reimplementation inevitably drifts. Players see FlipQueue-posted prices that TSM's own cancel scan immediately flags as "undercut" or "cancel and repost higher" because TSM's live logic saw something our static read of the operation missed.
2. **Don't use TSM.** Ship a simpler undercut rule (match `DBMinBuyout`, clamp to a user-configured floor). Then players have two separate pricing systems — TSM's and ours — and the addon can't claim TSM-faithful posting.
3. **Hand off to TSM's UI.** Open TSM's Post Scan tab for each item. This works, but it means the companion addon is a launcher rather than a poster, and the integration is visibly "TSM's UI taking over" rather than a coherent in-place flow.

Option (1) is what most addons end up doing, and it's the reason the same posting-price-drift complaint recurs: companion addons can't stay current with TSM without reading TSM's source every release.

## The ask

One function, read-only, no state changes outside a small cache:

```lua
--- Resolves the price and quantity TSM would post for an item using the
--- operation assigned to it (or a named operation if specified).
--- @param itemString  string     TSM item string ("i:12345", "p:4655", "i:12345::2:1663:2293")
--- @param opts?       table      Optional overrides:
---   opts.operationName  string  Use a specific Auctioning operation by name
---                               instead of resolving via the item's group.
---   opts.numHave       number   Player's available quantity for the item.
---                               Defaults to bag + warbank if omitted.
---   opts.lowestBuyout  number   Override the market reference price.
---                               Defaults to TSM's current scan data
---                               (DBMinBuyout equivalent).
--- @return nil | table          Nil if no applicable operation, no price
---                               data, or the operation refuses to post.
---                               Otherwise:
---   {
---     reason       = string,   -- "normal" | "undercut" | "match_self" |
---                              --   "reset_min" | "reset_max" | "reset_normal" |
---                              --   "above_max_min" | "above_max_max" |
---                              --   "above_max_normal" | "blacklist"
---     skipReason   = nil,
---     buyout       = number,   -- Buyout in copper, silver-rounded.
---     bid          = number?,  -- Bid in copper if operation sets one,
---                              -- else nil (buy-it-now only).
---     quantity     = number,   -- Items per PostItem / PostCommodity call.
---     numAuctions  = number,   -- How many auctions to create in total.
---                              -- For non-commodities this is the API's
---                              -- quantity argument.
---     duration     = number,   -- 1, 2, or 3 (12h/24h/48h).
---     operationName = string,  -- Which Auctioning operation was used.
---   }
---   -- or, when the operation refuses:
---   {
---     reason       = nil,
---     skipReason   = string,   -- "below_min" | "whitelist_no_post" |
---                              --   "above_max_no_post" | "blacklist_alt" |
---                              --   "invalid_seller" | "no_operation"
---     operationName = string?,
---   }
function TSM_API.GetAuctioningPostDecision(itemString, opts)
```

Optional companion call, since a cancel-scan integration has the same problem:

```lua
--- Returns whether TSM would cancel an already-posted auction under the
--- operation assigned to the item, and the reason.
--- @param itemString    string
--- @param listedBuyout  number   The buyout on the existing auction.
--- @param listedQuantity number  The stack size on the existing auction.
--- @return table  { cancel = bool, reason = string, operationName = string? }
function TSM_API.GetAuctioningCancelDecision(itemString, listedBuyout, listedQuantity)
```

No writes. No modifications to TSM's own queue. No dependency on whether TSM's UI is open.

## Why this is a good fit for the TSM API

- **Low surface area.** Two functions, thin wrappers around what `AuctioningOperation.MakePostDecision` and `AuctioningOperation.MakeCancelDecision` already compute. The expensive work — parsing operation settings, evaluating custom price expressions, walking the group tree — is code TSM already runs on every Post Scan.
- **Stable contract.** The return shape reflects the *result* of the decision, not how it was computed. TSM is free to refactor the internals (new settings, new branches, new thresholds) without breaking callers, because the caller reads `reason` and `buyout` rather than reconstructing the logic.
- **Aligns with the existing philosophy of `TSM_API`.** The current API exposes read-only, non-UI helpers: price evaluation, group lookup, inventory counts. A post-decision helper fits the same shape.
- **Widens TSM's reach.** Every companion addon that currently reimplements this is a future support ticket that says "TSM says cancel and repost higher but the other addon keeps posting low." Exposing the decision lets those addons become TSM-faithful in one call, which makes TSM's Auctioning module the single source of truth across the ecosystem.
- **Predictable performance.** The decision call doesn't need a live AH scan — it uses whatever scan data TSM already has (same source `DBMinBuyout` reads from). Companion addons that need live data can pass `opts.lowestBuyout` from their own recent queries.
- **No new security surface.** Both functions are pure reads. They don't invoke `C_AuctionHouse.PostItem` or `PostCommodity`; the caller does that with the returned price, which means the hardware-event constraint still applies to the *caller's* post code and TSM isn't exposed to being called from tainted code paths.

## How FlipQueue would use it

Current flow (simplified):

```
ScanBags → ResolvePostPrice → walk MakePostDecision ourselves → PostItem
                               ^ this is what drifts from TSM
```

With the proposed API:

```
ScanBags → TSM_API.GetAuctioningPostDecision(itemString) → PostItem
                                                            using the returned price/qty
```

The ~200 lines of reimplemented decision logic in `AuctionPost.lua:ResolvePostPrice` collapse to a single TSM_API call. Updates to TSM's Auctioning module automatically flow through to FlipQueue with no audit or code change on our side. The audit-drift scaffolding we currently maintain (`TSM_AUDITED_VERSION`, structural field checks, per-session warnings) goes away.

---

**Where to submit:** the TSM team accepts API requests via their GitHub issue tracker (`TradeSkillMaster/TradeSkillMaster`, if the repository is still the active one) and via their Discord `#api-requests` channel. A linked design doc plus a concrete consumer (FlipQueue) demonstrating the need is usually enough to get a serious look.
