# FlipQueue

A FlippingPal-driven workflow assistant for cross-realm auction-house arbitrage in World of Warcraft.

FlipQueue takes the deals you spot on FlippingPal and turns them into a guided, character-by-character to-do list — buy these on this realm, transfer those, post the rest. Inventory tracking, bank-pulling, and AH posting all flow through one frame so you stop hunting through five spreadsheets to figure out which alt should do what next.

> **Note:** the actively-maintained project-page descriptions live in `docs/wago-description.md` and `docs/curseforge-description.md` (4-step funnel format, what gets pasted to the dashboards). This file is a shorter overview and is kept in sync with them.

## What it does

- **Imports FlippingPal deals** and turns them into ordered to-do tasks across all your characters and realms. Knows which character on which realm should pick up each item, when to transfer, and when to post.
- **Tracks inventory across all your characters and realms** via Syndicator (a required dependency). Bags, banks, warband bank, and mail are all visible in one place, no matter which alt you're logged in on.
- **Cross-realm price intelligence** — DealFinder pulls per-realm AH pricing from the TSM AuctionDB across every realm your roster covers, including correct per-variant prices for items with item-level variants (most modern gear).
- **Bank-pull and warbank-deposit automation** — opens the bank, walks the queue, pulls the saleable items into your bags, deposits the rest to the warbank for the next alt. Each action has its own **Auto / Manual / Disabled** setting plus a per-character override; **Manage my items** and **Manage my gold** are global master switches at the top of settings.
- **Reactive task lifecycle** — buy rows in the mini overlay relabel themselves as you progress: `[BUY]` while you still need to click in the AH, `[CHECK MAIL]` the moment the buyout completes, `[DEPOSIT]` when the item is in your bags awaiting the warbank.
- **AH posting decisions follow TSM** — when a TSM operation is configured for an item, FlipQueue uses TSM's price source and undercut logic to decide post price and quantity. Optional integration; FlipQueue works without TSM too.
- **Live Auctionator buy-list sync** — when buy tasks exist, FlipQueue keeps a shopping list called *FlipQueue - Buy* in sync with what your current character still needs, with the right max-price ceiling on every entry. Items drop off automatically the moment you buy them.
- **Multi-account synchronization** — link a second WoW account via BattleNet and both accounts see each other's characters, bags, banks, and to-do lists in real time. Works with trial and paid accounts on the same BattleNet.
- **Activity log + sales reconciliation** — every post, sell, expire, and cancel is logged. Sales reconcile against TSM's CSV exports for accurate fee/profit accounting.

## Required dependencies

- **Syndicator** — provides the cross-character inventory backbone. CurseForge auto-installs this when you install FlipQueue.

## Recommended

- **TradeSkillMaster** — for AH posting decisions and price evaluation. FlipQueue reads TSM operations directly when present.
- **Auctionator** — for live shopping-list sync and search-string round-tripping.

## Quick start

1. Install FlipQueue and Syndicator (Syndicator auto-installs).
2. Log into your main character. The first-run setup wizard walks through linking your characters, realms, and external accounts.
3. Import a FlippingPal CSV via `/fq import` or paste it into the Transform page.
4. Click **Generate** to turn the imports into a routed to-do list.
5. Work the list — log into each character, the mini view shows what they need to do next.

## Slash commands

- `/fq` — open the main window
- `/fq settings` — open settings
- `/fq mini` — toggle the mini view
- `/fq import` — open the import / transform page
- `/fq scan` — manually rescan bags
- `/fq bank` — manually rescan bank and warbank
- `/fq version` — print installed version
- `/fq debug` — open the debug console (advanced)

## Issue reports / feature requests

GitHub: https://github.com/gezmodean-wow/flipqueue/issues

## Source

https://github.com/gezmodean-wow/flipqueue
