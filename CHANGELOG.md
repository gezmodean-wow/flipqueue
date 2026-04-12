# Changelog

## v0.10.2-alpha1

### New Features
- **PBS (Point Blank Sniper) import + export**: FlipQueue now recognizes and produces the Auctionator shopping-list wire format that PBS exports use. Paste a PBS export into the Transform → Paste textarea and the format auto-detects; select the new **PBS** output button to round-trip back out. PBS lists are stored by Auctionator as `listName^entry^entry^...` where each entry is the 14-field `searchString;categoryKey;minItemLevel;maxItemLevel;minLevel;maxLevel;minCraftedLevel;maxCraftedLevel;minPrice;maxPrice;quality;tier;expansion;quantity` string from `Auctionator.Search.ReconstituteAdvancedSearch`. Every field is preserved in a per-item `_pbs` metadata table so round-tripping is byte-identical for items that came from PBS; items from other sources (TSM groups, to-do lists, FP imports) synthesize their PBS output fields from `name` / `ilvl` / `quality`. The preview table's **Detail** column surfaces the most-useful PBS filter (`ilvl≥279`, `≤5000g`, `R3`, etc.) so imported search constraints are visible at a glance.
  - **Input**: `Import:ParsePBS(text)` in `Import.lua`, auto-detected by a hybrid `LooksLikePBS` probe that fast-paths on the `;;#;;` tier-placeholder substring and falls back to a structural "first entry has ≥13 semicolons after `^`" check for edge-case lists that have a real tier value set on every entry.
  - **Output**: `Transformer:OutputPBS(items, listName)` reconstructs the wire format. List name prefers the imported `_listName` over the default so round-trip preserves the original.
  - **Name → itemID resolution via TSM + PBS caches**: PBS shopping lists are typically filled with items the user does NOT own (rare mounts, high-ilvl crafted gear, snipe targets) — which means WoW's `C_Item.GetItemIDForItemInfo(name)` can't resolve them because they're not in the client item cache, and FlipQueue's own inventory/warbank/imports data sources miss them too. First-pass testing showed ~6 items out of ~100 resolving through the existing name→ID chain. `GetNameToIDMap()` in `TransformPage.lua` now walks two additional data sources:
    - `PointBlankSniper.ItemKeyCache.State.orderedKeys` (plus the in-session `newKeys` staging area): catches PBS files the user generated themselves, since their PBS cache contains every item PBS has seen via AH searches.
    - `_G.TSMItemInfoDB` (LongString-decoded `names` / `itemStrings` parallel arrays with `\002` separator, split into 1000-entry chunks per `LibTSMUtil/BaseType/LongString.lua`): catches PBS files authored by OTHER players, since TSM's persistent item-info database is populated from every auction scan and item lookup TSM has ever done across the user's TSM lifetime — typically tens of thousands of items covering most rare mounts, crafted gear, and niche items that end up on snipe lists even when the user has never personally searched for them.
  - **Per-source resolution breakdown in the preview status line**: shows where each resolved item came from — `(inv=2 pbs=4 tsm=58 cache=30)` — so users can see at a glance which data source is actually contributing. Items that failed to resolve are surfaced as `N unresolved` (previously they were silently dropped from the output, making "paste 100 items, see 64" mysterious). `item._resolvedFrom` metadata powers the breakdown, populated during `ProcessItems` as each item flows through the resolution chain.
  - **Warm Cache button** (new): when the preview detects unresolved items AND either TSM's per-realm pricing data or Auctionator's price database is loaded, a **Warm Cache (N missing)** action button appears next to Preview Source. Clicking it walks every unique item ID from the union of `TSMRealms.realmRaw` (items currently on any tracked realm's AH) *and* `AUCTIONATOR_PRICE_DATABASE` (items Auctionator has ever seen on any realm — historical, persists forever, critical for rare snipe targets like TCG mounts that aren't currently on the AH). Auctionator dbKey formats are parsed per `Auctionator/Source/Utilities/DBKeyFromLink.lua`: bare numeric for most items, `g:id:ilvl` for modern gear, `gr:id:suffix` for legacy gear, `p:speciesID` skipped (pets use a separate resolution path). Typical warming pool is 30-80k unique item IDs. Each ID is proactively forced into WoW's client item cache via batched `C_Item.RequestLoadItemDataByID` calls (250 IDs / 0.05s, well under any realistic rate limit). A listener on `GET_ITEM_INFO_RECEIVED` matches incoming item names against the unresolved PBS names, folds matches into the name map with `source = "cache"`, and re-runs the preview after all responses have had 1.5s to land. Progress is shown live in the status text (`Warming cache: 12000/30000 sent, 14/36 resolved`). This is the fix for the expert-authored PBS list workflow — users take a list from an expert, paste it, warm the cache, and get near-complete coverage even on items they've never personally encountered. New `TSMRealms:CollectAllItemIDs()` public API exposes the TSM ID set; the Auctionator pool is collected inline via `CollectWarmingPool()` in `TransformPage.lua`. The warming session state (listener frame, ticker, progress counts) is cancelled cleanly when the source mode changes or the preview is rebuilt.
  - **Recorded-price fallback for unpriced AAA output**: when an item resolves to an ID but TSM has no price data for it (common for rare mounts, old gear, niche consumables), `OutputAAAJSON` now falls back to the item's *recorded* price — `_pbs.maxPrice` from a PBS import first (the snipe ceiling the user explicitly set), then generic `expectedPrice` from other import sources. **No discount modifier is applied** to recorded prices: the user set them explicitly as their target, and applying the TSM discount would change the meaning. Previously the fallback was `expectedPrice × modifier`, which silently discounted user-entered prices and produced the "why is my 5000g entry showing 4500g in AAA" confusion. Works in both `tsm` and `imported` price modes.
  - **AAA price mode toggle**: new row on the Transform page (visible when AAA JSON is the output format) lets users pick between **TSM discount** (the existing behavior — TSM price × discount modifier) and **Imported** (uses PBS `maxPrice` or `expectedPrice` raw, no discount applied). Imported mode is the useful default for PBS → AAA handoffs where each item's AAA threshold should be exactly the max-price the user pasted from their PBS file. Persists via `db.settings.transformPriceMode`.
- Paste-mode auto-detect instruction updated to list PBS alongside FP / CSV / TSM / Auctionator / item names.

### Bug Fixes
- **Profession tools (and other high-ilvl crafted gear) silently rejected from to-do generation as "below TSM min price"**: `TodoGenerator.lua:891-894` had a dual-key fallback that fired whenever the first `IsBelowThreshold` call returned `false` — which happens in two distinct cases the code couldn't tell apart: *(a)* the variant's price is genuinely above threshold (correct), and *(b)* TSM has no data for the key (undecided). The fallback then called `IsBelowThreshold(deal.itemKey)` where `deal.itemKey` was typically the base-item key from an FP import (no bonus IDs). For a high-ilvl profession tool variant, this resolved to the base-item `DBMinBuyout` — dramatically lower than the actual variant's market value — and returned `true`, overriding the correct "above threshold" result and causing the to-do item to be silently skipped. When the user manually posted the item, it sold fine at the variant's real price. Fixed by gating the fallback on `not ahMin` (i.e., only fall back when the first call had no TSM data) and reassigning all four return values so the `failReason` message isn't stale. Full audit of the five `IsBelowThreshold` call sites confirms this was the only buggy one — `TSM:GetPrice`, `TSM:ItemKeyToTSMString`, `DealFinder`'s batch + per-item lookups, and `TSMRealms:GetBatchPricing` are all correctly bonus-keyed.

## v0.10.1-alpha3

### Bug Fixes
- **Bank Operations popup showing "Operations complete" with a partial progress bar**: the popup's row content correctly transitioned to the completion summary, but the status bar would land on `0`, `2/N`, or some partial state instead of full. Three independent bugs feeding the same symptom:
  - **Optimistic deposit progress reports**: `Tracker.lua`'s `DoDeposits` reported `depCount = #depositOps` and `extCount = #extraOps` (the *requested* counts) directly to `BankOpProgress`, never threading the actual `successNames`/`errorCount` returned by `BankQueue:Process`. Refactored to await `AutoDepositToWarbank` and `AutoDepositExtraItems` sequentially via callbacks that pass through the real counts. The two sub-phases now run in series instead of fire-and-forget.
  - **`AutoDepositExtraItems` was fire-and-forget** — no `onComplete` callback at all. The popup chain would proceed to `BankPopupComplete` while the extras' `BankQueue:Process` was still mid-batch. Added an `onComplete(successNames, errorCount)` parameter that fires from every early-return path and from the final `Process` callback after Scanner refresh settles, so the chain can actually wait for extras before declaring completion.
  - **Reagent bag silently dropped from `AutoDepositToWarbank`**: `Tracker:BuildDepositOps` (the popup builder) iterates `ALL_PLAYER_BAGS = {0..5}` which includes the reagent bag, but `Tracker:AutoDepositToWarbank` was iterating `INVENTORY_BAGS = {0..4}` which excludes it. So a deposit task whose source item lived in slot 5 would appear in the popup but get silently skipped during execution. Now both call sites iterate `ALL_PLAYER_BAGS` and stay in agreement.
- **Defensive `ShowCompletionSummary`**: even with the three fixes above, any future regression in the running tally would resurface the partial-bar symptom. `ShowCompletionSummary` now reconciles the running `completed` count up to `totalOps - failed` on transition to "Complete" (preserving the failed count so the orange/green color logic still reflects whether anything failed), and emits a `[bank-popup]` debug line whenever drift is detected so the underlying drift remains diagnosable.

### Diagnostics
- **`[bank-popup]` debug log**: `BeginBankExecution`, `BankOpProgress`, `ShowCompletionSummary`, and `BankPopupComplete` now each emit a one-line debug entry into the in-game debug ring buffer (visible regardless of the `debugMessages` print setting). Records the operation, the running `completed`/`failed`/`total`, and any guard hits (popup not shown, execState nil). Use this to diagnose any future "popup state out of sync" reports — the entire execution timeline lives in the debug console after the bank visit.

## v0.10.1-alpha2

### Bug Fixes
- **Deposits overflowing into personal bank with overflow disabled**: `AutoDepositExtraItems` builds non-soulbound deposits with `destType = "any"`, and both `ProcessNextBatch` and `Attempt`'s `IssueOne` handled `"any"` by *merging* warbank+bank into the picker's primary bag list — which silently bypassed the overflow gate inside `PickDepositSlot`. A user with a full warbank, locked bank tabs, and overflow off would still see items land in their bank tabs because the picker never even consulted the overflow flag. Both call sites now treat `"any"` the same as `"warbank"`: warbank as primary, bank as secondary, gated by `overflowEnabled`.
- **Items leaking to personal bank even when warbank tabs had open slots**: `ItemMatchesTabFlags` only knows about a handful of item classes (Weapon/Armor/Consumable/Tradegoods/Recipe/Questitem/Junk). Items in any other class — Gem, ItemEnhancement, Glyph, Miscellaneous, Battlepet, Profession, etc. — get rejected by every tab that has *any* `depositFlags` set, even when those tabs have empty space. Combined with the overflow bug above, the picker would declare warbank "full" and dump the item into the personal bank. `PickDepositSlot` now has a filter-bypass fallback path: if no filter-matching primary tab can take the item, walk every primary tab ignoring filters before falling back to overflow. Tab filters are now treated as a routing *preference*, not a hard wall. (`FindStackTarget` and `FindEmptyAcceptingSlot` gained an `ignoreFilters` parameter.)
- **Warbank getting disabled after bulk deposits / between characters**: `ProcessNextBatch` (the async path used by `AutoDepositExtraItems`) issued every op in a batch (`pullBatchSize`, default 5) inside a single tight Lua loop with no inter-move spacing — only `INTER_BATCH_DELAY = 0.3s` *between* batches. Five container ops in a single frame is exactly what trips Blizzard's per-frame rate limit, and the resulting backoff manifests as the warbank being unresponsive on the next character. The async path now serializes ops the same way `ProcessSync` does — `WaitForBagUpdate(INTER_MOVE_DELAY=0.1, …)` between every real container move, with skip-cases yielding via `C_Timer.After(0, …)` so big batches don't blow the Lua call stack.

### Diagnostics
- **Deposit slot picker debug log**: every call to `PickDepositSlot` now emits one line into the debug ring buffer (visible in the in-game debug console regardless of the `debugMessages` print setting). Each line discloses the item, the picked destination, *which branch picked it* (`stackTarget(primary)`, `emptySlot(primary,filter-bypass)`, `emptySlot(secondary,overflow)`, etc.), and the full candidate list for both primary and secondary bag groups with each tab's `depositFlags`, specificity, and accept/reject decision. Use this to diagnose "wrong tab" reports — it makes it obvious whether the picker chose tab N because of an existing partial stack, a higher-specificity Blizzard filter, or fall-through into the filter-bypass / overflow paths.

## v0.10.1-alpha1

### Bug Fixes
- **Deposits silently swapping items between bag and warbank**: when the client container cache lagged the server — especially for warbank tabs that hadn't been actively viewed — `PickDepositSlot` would target an "empty"-looking slot that was actually occupied, and the resulting `CursorMove` performed a server-side swap: the deposit landed at the destination while an unrelated item was displaced out of the bank. The delta verification, which only tracks the deposited itemID's count, saw `+1` and declared success. The user was left with items in the wrong inventory.
  - **Allocation ledger** (`allocatedSlots`), scoped per sync attempt and per async batch — each deposit claims its destination slot *before* the `CursorMove` is issued, and `FindStackTarget` / `FindEmptyAcceptingSlot` skip claimed slots so two ops in the same sweep can never collide. Same mechanism Baganator's `BankTransferManager` uses.
  - **`BAG_UPDATE_DELAYED` wait between sync moves**: the fixed 100ms spacer was a best-effort guess; the event is the deterministic signal that the container cache reflects the last server response. Still enforces the 100ms minimum for Blizzard's container-op rate limit, with a 600ms hard ceiling if the event never arrives (rejected move).
  - **`C_Item.DoesItemExist` empty-slot probe**: `FindEmptyAcceptingSlot` now prefers the `ItemLocation`-based API over `C_Container.GetContainerItemInfo`, which is more reliable for warbank tabs the player hasn't opened in this session.
  - **Source-item validation (`op._expectedItemID`)**: `IssueOne` records the source item on first issue and compares on retries — if a prior swap or external move replaced the original item at the source slot, the retry aborts instead of moving an impostor.
  - **`CursorMove` destination guard**: rejects place attempts when the destination holds a different itemID than what's on the cursor. Belt-and-suspenders for the fresh-cache case.

## v0.10.0-a3

### Bug Fixes
- **BankQueue crash on some clients**: `GetBankTypeForBag` used `Enum.BagIndex.BankBag_*` constants that don't exist on every client, causing "compare nil with number" — now uses numeric ranges with nil-safety
- **Deposits silently going to character bank instead of warbank**: `UseContainerItem` on inventory slots ignores `BankPanel:SetBankType` and defaults to character bank — pulls keep shift-click, deposits now use cursor moves with explicit destination so warbank-bound items can never silently misroute
- **Deal Finder game lockup**: TSMRealms was doing O(items × realms × stringSize) string scans on multi-megabyte realm pricing data. New `GetBatchPricing` does a single pass per realm; cost drops from gigabytes to megabytes of byte comparisons for typical pools — multi-second freezes now resolve in a single frame
- **Imports growing unbounded**: imports were meant to be ephemeral working state for the import → generate phase but persisted across sessions. Now auto-cleared in `TodoList:CommitList` so the to-do list becomes the single source of truth once a list is committed
- **Chronic micro-lag during AH/mailbox activity**: `BAG_UPDATE_DELAYED` handler is now debounced — collapses bursts of bag updates into a single Scanner+RefreshLocations+RefreshTaskSteps+UI:Refresh+RefreshMini chain instead of running it N times
- **Mini view double-list bug**: when the current character had no tasks, the mini view rendered a duplicate per-character summary above "Next Steps" in a different sort order. Removed the duplicate render — Next Steps is now the single source of truth for that view
- **Single sale hidden in Item Research**: `RenderSaleHistory` required `> 1` sales; now shows even a single transaction so the "yes this thing has sold once, here's what for" data point isn't lost
- **Soulbound items in deposit extras**: `BuildExtraDepositOps` was routing soulbound items to the character bank; now skips them entirely (matches `BuildDepositOps`)
- **Reagent bag invisible to deposits**: `CountInBags`, `BuildDepositOps`, and `BuildExtraDepositOps` weren't iterating bag 5; new `ALL_PLAYER_BAGS = {0..5}` constant covers it
- **Bank tab filter ignored**: Blizzard's per-tab `depositFlags` (Equipment / Reagents / etc. assignment) wasn't honored. New `ItemMatchesTabFlags` checks each tab's filter and `TabSpecificity` ranks accepting tabs so the most-specific match wins over catch-all
- **Bank popup overflow**: long pull/deposit lists overflowed off-screen; now wrapped in a `ScrollFrame` with mouse wheel support
- **"Internal bag error" during multi-item pulls**: `ProcessSync` now issues one move per frame with auto-retry, pre-sets the bank panel with a settle delay, and uses a configurable inter-move delay to stay above Blizzard's container-op rate limit
- **Debug message leaks in live mode**: audited and fixed several `ns:Print` calls that were debug-style: Scanner iLvl logging (also fixed wrong settings field name), ExportPopup SimpleHTML status, CharactersPage character reorder messages, Export scan summary, Import deduplication count

### Features
- **TSM Market Data section in Item Research**: surfaces sold/day, sale rate, regional avg sale, historical price, market value, and TSM Accounting cost basis. Computes estimated margin when both cost and a sale reference are available, so players can make "should I keep posting?" decisions even when their personal log has zero sales
- **Smart deposit stacking**: `FindStackTarget` merges deposits into existing partial stacks before opening new slots
- **Deposit overflow setting** (off by default): when the warbank has no room, optionally fall back to the character bank. Sub-toggle for combining partial stacks across both banks. Global default with per-character override support
- **Reagent deposit toggle**: new "Move reagents to warbank when depositing all" setting (off by default — reagents aren't tracked for sale because they're not cross-region)
- **Collapsible bank popup sections**: Pulls / Deposits / Gold / Extras can each be collapsed independently; state persists across popups
- **Mail icon on mini view**: small envelope icon shown on the header only when `HasNewMail()` returns true
- **`/fq debug` console**: in-game debug window with action button grid + live debug log view. Buttons for bank popup overflow tests, FQ state export, copy debug log to clipboard, toggle debug mode. Status indicator shows whether chat-output debug mode is on. Captures the last 500 debug messages to a ring buffer regardless of toggle so the console always has recent context
- **`UI:RegisterDebugAction(label, fn)`**: public API for other modules to register their own debug console buttons without editing `DebugConsole.lua`

### Settings reorganization
- **New "Bank & Warbank" section**: bank, gold, reagent, overflow, and batch-size rows moved here from "Scanning & Automation". The remaining section is renamed "General"
- **TSM behavior moved to TSM Integration page**: `tsmSkipOnGenerate` and `tsmAutoSkipRejected` no longer live in the Settings frame; they're under a new "Behavior" sub-header on the TSM Integration page
- **Multi-Account section framing**: "Real-Time Sync (recommended)" header in green with a clear description of what it does (BattleNet-linked, real-time inventory + task sync, unified to-do list). "External Accounts" relabeled to "External Accounts (legacy — use Real-Time Sync above)" in muted gold with an inline deprecation notice
- **Plain-language labels** throughout: e.g. "Withdraw gold from the warbank to cover listing fees", "Deposit to bank when warbank is full", "Move reagents to warbank when depositing all"

## v0.10.0-a2 — BankQueue reliability rewrite

### Bug Fixes
- **Pull verification false positives**: auto-pull was reporting success for items that never moved. The old verification only checked "is the source slot empty?", which gave false positives when a server-rejected destination placement bounced the item to a different slot. New `CountItemsInBags` snapshots stack counts by itemID before/after each batch; an op only counts as moved when the destination's count of that itemID actually went up. Applied to both `ProcessSync` (popup path) and the async `VerifyBatch`
- **"Internal bag error" during pulls**: replaced the `PickupContainerItem` + `PickupContainerItem` cursor dance with single-call `C_Container.UseContainerItem` (shift-click semantics). Half the rate-limit pressure, no cursor state to leak between back-to-back moves, server picks the destination including auto-stacking onto partial stacks. Gated behind `IsBankOpen()` so it can't fall through to "use the item"
- **Failed moves in `ProcessSync` weren't retried**: added auto-retry up to 4 times, matching what the async `Process` path already did

### Features
- **One move per frame**: each pickup is scheduled via `C_Timer.After(0, IssueNext)` so it lands on its own frame, avoiding the 16ms-too-fast tight loop that tripped Blizzard's container-op rate limit
- **Local bank panel tracking**: `SetBankType` is only called when the type actually changes, with a small settle delay after a switch — eliminates redundant panel rebuilds inside a batch

## v0.10.0-a1 — BankQueue rewrite, unified sales tracking, item detail popup

### Bug Fixes
- **Warbank ops blocked by taint**: removed the previous taint workaround (which was causing taint, not fixing it) and rewrote `BankQueue` with explicit `EnsureBankType` mode-setting before warbank operations
- **Deposit/extra slot overlap**: `BuildExtraDepositOps` now excludes slots already claimed by deposit ops
- **Mini view deposit visibility for non-logged-in characters**: deposit tasks for items not in inventory are now hidden in the mini view to avoid stale rows
- **Warbank source verification**: `RefreshLocations` now properly checks warbank inventory for deposit tasks — clears `depositFrom` and updates `source` to "warbank" when the item is found

### Features
- **Unified sales tracking (`SalesIndex.lua`)**: new module with canonical `IsSold` / `IsFailed` / `IsActive` predicates and a cached index exposing `GetSalesSummary`, `GetSalesForRealm`, `GetLogStats`, and `GetUncollectedForChar`. Single source of truth for all views; removed ~130 lines of duplicate sales indexing in `DealFinder.lua`
- **Item detail popup**: left-click a task in the mini view to open a popup showing location, assignment, pricing, and research summary
- **Bank popup with unified progress bar**: color-coded across all phases (pull / deposit / gold), completion summary persists until the bank closes. Anchors to the mini view with configurable position
- **Bank progress rollout on mini view**: when the popup isn't visible, the mini view shows a compact progress indicator instead
- **Collapsible settings sections**: collapse with summaries shown in the collapsed state, persisted across reloads
- **Deferred tasks hidden from mini view**: reduces visual clutter for tasks that aren't actionable right now
- **Canonical item matcher (`ns:ItemsMatch`) adopted in ItemResearch** and other modules

## v0.9.8 — Setup wizard, bank progress, soulbound/warbound fixes

### Features
- **First-run setup wizard**: step-by-step interactive wizard with a "Use Recommended Defaults" fast path. Steps: Welcome, Gold, Bank Automation, TSM (if detected), Pricing, Posting, Display. Steps are dynamic based on TSM/Auctionator detection. Auto-triggers for new installs; existing users skip. Re-runnable from Settings via the "Run Setup Wizard" button
- **Bank progress bar**: status bar overlay during pull/deposit operations showing X / Y progress, updated per batch, hides on completion
- **Pricing model split**: separated "Deal Price" (imported) from "Blended" (TSM + personal sales history) as distinct options across Deal Finder, the TSM page, and the wizard. New `blendedPrice` field on Deal Finder imports

### Bug Fixes
- **Soulbound deposit filter**: deposit allowlist now only includes BtA / BtW items when `isBound=true` (was letting equipped BoE through to the deposit list)
- **Warbank pool builder included untradeable items**: BtW / BtA items were being added to the sell pool; now filtered out
- **Character inventory tradeable check**: also excludes Quest / BtA / BtW bind types

### Default Changes (fresh installs only)
- `autoWithdrawGold`: false → true
- `maxWithdrawGold`: 0 → 500
- `goldBuffer`: 0 → 50
- `autoDepositGold` remains off (players keep earnings by default)

### Settings & Tutorial cleanup
- Sync log toggle now reflows the content below it using a container frame
- Tutorial: removed Export step (page no longer in nav); generator step uses banners instead of anchor-dependent callouts; fixed text overlap on center-type callouts; reduced from 5 to 4 steps

## v0.9.7

### Bug Fixes
- **FP website "Name" header parsed as item**: When FP paste lacks a "/" separator, the column header "Name" was misidentified as an item — now filtered out along with other known header words
- **TSM skip blocks post detection**: Items marked "skipped" by TSM threshold on AH open were invisible to post detection and owned auction matching — posts for skipped items are now detected and the skip is cleaned up automatically
- **Bank over-pull**: Auto-pull recalculated quantity from TSM postCap independently of the task, pulling e.g. 6 when the task needed 1 — now uses the task's own quantity directly
- **Deal Finder quantity set to total inventory**: Per-realm deals stored the full inventory count as quantity, causing over-allocation for items without TSM groups (especially pets) — now stores 1 as baseline, with actual post qty determined by TSM postCap / defaultSellQty during generation
- **Mini view missing quantity**: Mini view task rows now show "x3" etc. when quantity > 1, matching the To-Do page display

### Debug
- **Generation debug logging**: When debug messages are enabled, the to-do generator now logs reasons for dropped deals: no pool match, no character assignment, pool exhausted, and TSM threshold skip
- **Deal Finder debug logging**: Logs items skipped during scan (no TSM key, no market data, below min price)

## v0.7.0

### Bug Fixes
- **Deposit refresh race condition**: BAG_UPDATE_DELAYED no longer runs stale RefreshLocations during active pull/deposit operations — prevents to-do list from flickering or showing incorrect state
- **Mini view action buttons persist**: Action buttons, OnEnter/OnLeave scripts now explicitly cleaned up during row refresh

## v0.7.0-alpha.7

### Bug Fixes
- **Auction cancellation detection**: New `AUCTION_CANCELED` event tracking distinguishes cancelled vs sold auctions — cancelled shows "collect items" (orange), sold is detected via mail invoice data only. Fixes false "collect gold" messages on cancel.
- **Stale reconciliation**: Auction entries no longer on AH are silently marked "collected" instead of falsely "sold". Actual sales detected only by `ScanMailForSales`.
- **TSM false rejection removed**: No longer skips items when TSM has no AH price data — TSM posts using normalPrice, so missing `DBMinBuyout` is not a rejection.
- **Skipped tasks un-skip**: Items returning to bags now un-skip ALL skipped tasks (removed TSM-skip exception that prevented recovery).
- **Mail clears sold entries**: Opening mailbox now sets `collectedAt` on sold entries and clears cancelled/expired, so "Check Mail" tasks resolve immediately.
- **Mini view task indices**: Grouped summary now annotates `_taskIndex` before building display groups, fixing bulk actions on character/create-char groups.

### Features
- **Bulk group actions**: Complete/skip/delete all tasks in a character group — hover action buttons on group headers in both To-Do page and Mini View, including "Create character" groups.
- **Dismissible mail tasks**: Right-click "Check Mail" rows in To-Do page or Mini View to dismiss stuck entries.
- **Gold text offset**: Price/gold text on to-do item rows moved left to avoid overlap with action buttons.
- **Log: Cancelled status**: Log page shows "Cancelled" (orange) for cancelled auctions.
- **Sidebar cleanup**: Removed Export and Import from sidebar, renamed "FlippingPal" section to "Tools", updated Transform icon.

## v0.7.0-alpha.6

### Bug Fixes
- **Warbank deposit scan** (#101): After depositing items to warbank, the addon now scans warbank (not just personal bank) so deposit tasks are properly resolved
- **Buy tasks say "to post"** (#102): Mini view and to-do page now correctly label buy tasks as "to buy" instead of "to post" everywhere — title, group headers, next steps, status bar
- **TSM detected chars overflow** (#66): Detected characters section now caps at 8 visible rows with scroll instead of overflowing the window
- **Auto-pull grabs just-deposited items**: Bank open now runs RefreshLocations before auto-pull, preventing items just deposited to warbank from being pulled back out
- **Auto-pull ignores buy tasks**: Buy tasks are no longer pulled from bank — they need to be purchased from the AH
- **Deposit tasks stuck after warbank deposit**: RefreshLocations now checks warbank inventory for deposit tasks — clears depositFrom and updates source to "warbank" when item is found
- **Buy task browse step stuck**: Browse step now auto-advances when item appears in bags (bought from AH + collected from mail), double-advancing through buy step
- **Gold auto-withdraw for buy tasks**: hasTasks check now matches buy tasks on buyRealm; CalculatePostingFees skips buy tasks; CalculatePurchaseCosts implemented with actual buy prices

### Features
- **Auctionator shopping lists from buy tasks** (#103): Creates per-realm shopping lists ("FQ Buy - RealmName") in Auctionator search format with price filters — button on To-Do page and Mini View when Auctionator is installed
- **To-Do list selector** (#104): Compact bar at top of To-Do page showing active list name + task count; dropdown to switch between active and queued lists
- **Mini view: auto-width**: Frame automatically stretches to fit content text (200-500px range)
- **Mini view: resizable**: Drag grip in bottom-right corner to set preferred width (persisted)
- **Mini view: collapsible**: Collapse/expand button in header — collapsed shows first 2 rows only
- **Mini view: buy task display**: Buy tasks shown with [BUY] prefix, correct price/realm, waiting icon
- **Mini view: deferred task filtering**: Deposit tasks for items not in inventory are hidden
- **Max withdrawal setting**: New "Max withdrawal per visit" gold input in Settings — caps auto-withdraw amount per bank visit (0 = no limit)

### Closed Issues
- #69 (To-Do scroll), #68 (auto-import reset), #67 (hidden char tasks), #38 (TSM rejection), #105 (generator save nav) — all previously fixed

## v0.7.0-alpha.4

### Bug Fixes
- **Deposit task stuck**: Buy task deposit step no longer gets stuck when item is posted on AH instead of deposited — fixed race condition where RefreshLocations clobbered task.source before RefreshTaskSteps could check it
- **Hidden character shared AH**: Hidden/ignored characters no longer cause other characters on the same realm to show "Shared AH" status
- **TSM/Auctionator/Realm filter checkboxes**: Checking a filter checkbox now immediately refreshes the UI to show the filter content (was requiring a page navigation first)
- **Realm filter "create char" tasks**: "Only show realms with characters" now correctly filters by sell realm — no longer passes deals where only the buy realm has a character
- **Save returns to track selection**: Saving a generated list now returns to the track selection screen instead of step 1 of the same track

### Task Management
- **Mouseover action buttons**: Hover over any task row in the To-Do page or Mini View to see complete/skip/delete buttons on the right side
- **DeleteTask**: New function to remove a task entirely without logging

### Import Performance
- **Async chunked import**: Large imports now process in batches of 50 with a progress bar — UI no longer freezes during import
- **Progress bar**: Shows "Importing... X / Y (Z%)" with a green fill bar during processing

### Generator Improvements
- **Side-by-side buy/sell lists**: Separate mode now renders buy and sell preview lists in left/right columns instead of vertical stacking
- **Side-by-side priorities**: Buy and Sell priority lists shown horizontally in Step 3
- **Per-list naming**: Separate mode has individual name inputs for buy and sell lists above each column
- **Sell list includes planned buys**: Cross-realm flips not yet purchased now generate both a buy task and a deferred sell task
- **Removed import button**: Superfluous Import button on Generator cross-realm Step 1 removed — use Import tab instead

## v0.7.0-alpha.1

### Generator Wizard (#84)
- **Two-track wizard**: Generator page redesigned as a step-by-step wizard with track selection
- **Inventory Scan track**: Build Inventory → Import FP Deals → Configure & Generate (3 steps)
- **Cross-Realm Import track**: Import Deals → Filter Deals → Configure & Generate (3 steps)
- **Buy priorities**: New priority system for cross-realm buys — profit, population, low inventory, high inventory, discount
- **List modes**: Generate separate buy/sell lists or a single integrated list (most profitable / best deal / prioritize buys)
- **Realm filter**: Filter cross-realm deals by realms where you have characters
- **Auto-generate**: Preview auto-updates on every config change — no more Generate button
- **Save with name**: Prompt for list name when saving; wizard returns to step 1 after save
- **FP Premium note**: Import steps indicate FlippingPal Premium requirement

### Transformer Pipeline (#32)
- **New Transform page**: Input → Transform → Output pipeline for item data conversion
- **4 input adapters**: TSM groups, imports, inventory, Auctionator lists
- **5 transforms**: SplitPets, PriceModify, FieldMap, Filter, MergeByKey
- **4 output adapters**: AAA JSON, FP CSV, TSM group string, Auctionator list

### Cross-Realm Import (#60)
- **Cross-realm flipping**: Import FP cross-realm flip data (website, CSV, Auctionator formats)
- **Buy to-dos**: Generate "buy" tasks with browse → buy → deposit steps
- **Format support**: FP website copy-paste, FP comma CSV, Auctionator inline (^-separated), Auctionator text export, tab-delimited with buy/sell columns

### Sale vs Expiry Tracking (#70, #71)
- **Sold vs expired**: Mail scan distinguishes sold (gold received) from expired (item returned)
- **Failed sale tracking**: Tracks post attempts, total fees spent, per-attempt history with TSM price data
- **Login message**: Splits sold vs expired counts with distinct colors
- **Log page**: Shows Sold (green) vs Unsold (orange), failed sale count, per-attempt tooltip, total fees lost

### QoL Improvements
- **Characters page**: Heading style fix (#72), auto-expand table when no "create" section (#76), overflow into TSM section fixed (#92)
- **Inventory page**: AH-posted items show correct owner/location (#73), "Unassigned" replaces "Unknown" for tracked items (#74)
- **Scroll tables**: Horizontal scroll bars (#77), auto-hide when nothing to scroll (#78)
- **Empty states**: Generator button on empty To-Do page (#75) and Mini view (#79)
- **Sidebar**: Wider default width (#80)

### Bug Fixes
- **New character auto-assign**: Unassigned tasks automatically assigned when a new character logs in (#83)
- **Warbank deposit batching**: Uses event-driven batch system instead of one-at-a-time timer
- **Bank/warbank transfers**: Now trigger to-do step refresh in both directions (#91)
- **Expired auction cycle-back**: Collected expired items cycle task back to "post" step (#94)
- **TSM rejection step check**: Only checks tasks on "post" step, not retrieve/collect (#95)
- **Battle pet detection**: 4-tier matching (key/ID/species/name) across all inventory lookups and mini view (#82)
- **No more auto-skip**: Tasks defer instead of skip when item not found in stale inventory DB
- **Auto un-skip**: Skipped tasks re-check and un-skip when item reappears
- **Auto-complete lists**: Lists auto-archive when all tasks are done/skipped (#88)
- **Active list auto-promote**: Deleting active list promotes next queued list (#88)
- **Import [XR] prefix**: Fixed inventory imports incorrectly showing cross-realm indicators (#85)
- **Cross-realm CSV parsing**: FP source strings (Player Inventory) no longer trigger cross-realm detection
- **EditBox focus**: Click anywhere on paste area background to focus (#93)

## v0.6.2

### TSM Rejection Handling (#38)
- **Auto-skip below threshold**: When opening the AH, items below TSM's min price are automatically detected and handled
- **Realm-mate reassignment**: Below-threshold items are reassigned to another character on the same realm when available, based on priority settings
- **Skip + log**: When no alternate character exists, items are skipped with full TSM reason (price, threshold, operation name) and logged
- **Log entries for rejections**: Skipped items appear in the Log page with "Skipped" status and TSM reason in tooltip
- **Setting**: "Auto-handle TSM rejections" checkbox in Settings (on by default)

### Bug Fixes
- **Multi-post quantity inflation**: Fixed CheckForPosts logging inflated posted quantities when multiple to-do tasks share the same item type (#54)

## v0.6.2-alpha.4

### Bug Fixes
- **TSM detected characters overflow**: section now scrollable with max height — no longer spills below the window (#66)
- **TSM detected characters persist between tabs**: properly hidden on tab switch; TSM profile dropdown menu also cleaned up (#66)
- **Hidden characters still get to-do tasks**: Generator now skips ignored characters in both item pool building and task assignment (#67)
- **Auto-pull fails for shared AH realm-mate**: tasks route to the visible character instead of the hidden one, so auto-pull works correctly (#67)
- **Auto-import checkbox resets after logout**: setting now persisted to SavedVariables like Auto-generate (#68)
- **To-Do overview cannot scroll**: added explicit mouse wheel handling for TWW compatibility (#69)

## v0.6.1

### To-Do System (replaces Queue)
- **To-Do Generator**: two-column page — left column shows your item pool with filters (All, TSM Group, Auctionator List), right column builds your task list with priority controls and sort modes
- **To-Do List**: replaces the old Queue as the single source of truth for what to post, where, and in what order — tasks track steps (retrieve → post → collect) and advance automatically based on game events
- **Task deferral**: items not currently accessible (e.g., on another character's bank) are deprioritized — deferred groups sort to the bottom so you stop cycling through characters with nothing to do
- **Deposit subtasks**: tracks which character holds items that need depositing to warbank, shows "via CharName" source tags
- **Smart character ordering**: Next Steps sorts depositors before receivers
- **Auto-generate on import**: option to skip the Generator and auto-build a to-do list when importing deals
- **Import type tags**: to-do lists show their data source (Inventory Scan, Cross-Realm Flip, TSM Import, Auctionator Import) in headers

### TSM Integration
- **TSM settings page**: profile selector, per-item Auctioning operation resolution (postCap, duration, minPrice threshold)
- **TSM group filtering**: Generator "What to Sell" column filters items by TSM group tree with profile selection
- **TSM price columns**: AH Price column in To-Do and Generator tables with auto-update option
- **TSM threshold skip**: items below TSM minPrice are auto-skipped with reason shown in red
- **TSM character detection**: auto-detects characters from TSM data on login — add or dismiss on the Characters page

### Auctionator Integration
- **Auctionator settings page**: shopping list viewer with item counts
- **Auctionator list filtering**: Generator filters items by Auctionator shopping list

### Inventory & Scanning
- **Enhanced statuses**: Assigned (green) / Posted (yellow, shows "AH: realm") / Check AH (orange, expired) / Unknown (gray) / Ignored (red) — replaces old Queued/Posted/Untracked/DNT labels
- **Live inventory tracking**: inventory DB updates in real-time on every item movement
- **Bank quantity reconciliation**: fixes inflated item counts from stale location data
- **Battle pet detection**: proper handling via |Hbattlepet: pattern and C_PetJournal lookup

### Export
- **Export page**: inline tab with live scan (Bags/Bank/Warbank/All) and Saved All from DB
- **Export filters**: filter by Everything, TSM Group, or Auctionator List
- **Export formats**: FlippingPal CSV and AAA JSON output

### Characters & Realms
- **AH cluster grouping**: characters on connected realms show "Shared AH" with tooltip listing the full cluster and other characters — replaces the old "Dupe" label
- **Character ignore**: click to hide characters from task routing — visible O/X toggle
- **Manual sort order**: Shift+Right-click and Ctrl+Right-click to reorder
- **TSM character detection**: "Detected from TSM" section with Add/Dismiss/Add All buttons

### Automation
- **Auto-deposit to warbank**: new setting — when opening bank, deposits items needed by other characters
- **Gold withdrawal refactor**: fee calculation extracted into reusable functions (CalculatePostingFees, CalculateRequiredGold) for future buy-task support
- **Configurable bank tabs**: choose which bank/warbank tabs to scan and pull from

### UI & Polish
- **Sidebar navigation**: TSM-style dark theme with section headers (To-Do, Tools, Integrations, System)
- **Sortable scroll tables**: click column headers to sort ascending/descending
- **Mini overlay**: compact draggable overlay with deposit/mail detail, expiring auction timers
- **Custom artwork**: addon icon, banner, and logo
- **Import preview**: shows new/update/duplicate with reasons (same realm, connected realm, duplicate in paste)
- **Text overflow fix**: table cells clipped to column bounds

### Under the Hood
- **Consolidated item matching**: unified 4-tier matching (key → ID → name → fuzzy) across all systems
- **Schema versioning**: migration framework for SavedVariables upgrades
- **Error handling**: all C_Item/C_Container calls wrapped in pcall
- **Accent-insensitive realm matching**: handles German/EU realm names
- **Diagnostic export**: `/fq state` for support conversations

---

## v0.5.0
- Partial post detection: posting fewer than queued quantity keeps remainder in queue
- Mail scan updates: detects expired/cancelled auction returns, marks as collected
- State recovery: discovers pre-existing AH auctions not tracked by the addon
- Live auction expiry timer: 60s ticker auto-marks expired auctions, chat notifications
- Consolidated item matching: unified 4-tier matching (key → ID → name → fuzzy)
- Configurable batch size: settings slider for warbank auto-pull batch size
- Accent-insensitive realm matching: handles German/EU realm names
- Warbank batching rewrite: event-driven 5-item batches with error detection
- Configurable bank tab selection: choose which bank/warbank tabs to scan and pull from
- Error handling hardened: all C_Item/C_Container calls wrapped in pcall
- Release channels: alpha/beta/release via tag naming convention

## v0.4.1
- Custom addon icon and banner artwork
- Credits section in Settings page
- Settings redesigned: inline descriptions below each setting, section dividers, improved spacing
- Import preview shows dupe reason (same realm, connected realm, duplicate in paste)
- Import preview detects price changes as "update" instead of "duplicate"
- Queue:Add now applies updated prices on re-import
- Sold item tracking via AH mail scanning (invoice-based, no false positives from cancels)
- Log table Status column: Active, Sold, Expired, Done with color coding
- "Check AH" next step clears when AH is opened on that character
- Login message shows expired auction alerts
- Next Steps gold values match "realms needing a character" counts (warbank-backed only)
- Realm "..." suffix from FP website no longer causes false dedup
- Gold values sort numerically (1.3k, 22.8k, 1.3m handled correctly)
- Hide mini view in combat (toggle in Settings, on by default)
- Mini view shows FQ icon in header
- Minimap button uses custom FQ icon
- AH fee estimate updated: 60% of vendor price (48h post), cap raised to 200g
- Dead code cleanup: removed Rows.lua, Sections.lua, LogPage.lua, trimmed UntrackedSection.lua
- DNT key fix: /fq dnt add now resolves item IDs from inventory

## v0.4.0
- Skip/unskip queue items: Shift+Right-click to skip items where AH price is too low (auto-unskips after 24h)
- Character tracking: gold, last login, class/level per character
- Auction expiry tracking with login alerts for soon-expiring auctions
- Characters page redesigned: Gold, Tasks, Auctions, Last Login, Status columns
- Multi-account support: add external realm coverage in Settings to exclude from "Create char" suggestions
- Mini view shows next steps (top 3 + "more" link)
- Post Now summary view with next steps when done posting
- Do Not Track dialog restyled to match dark theme
- Auto-pull from bank now prints which items were pulled
- Warbank rescanned on bank open for accurate task counts
- Gold withdrawal capped at 100g max (was overestimating AH fees)
- Click handlers use OnMouseDown for reliable modifier key detection
- CurseForge/Wago automated releases via GitHub Actions
- Version auto-detected from .toc (dev builds show "dev", releases show tag version)

## v0.3.0
- TSM-style UI overhaul: dark theme, side navigation, sortable scroll tables
- New pages: Post Now, Queue, Log, Inventory, Characters, Settings
- Characters page with scanned character overview and "realms needing characters"
- Settings integrated as in-window page (consistent styling)
- Minimap button with left-click (toggle) and right-click (settings)
- Queue table "Found On" column shows storage locations (bags, bank, warbank)
- Class-colored character names in Characters page

## v0.2.0
- Collapsible sections in queue view
- Posted items log with price comparison
- Do Not Track list for excluding inventory items
- Untracked inventory section (excludes soulbound/warbound)
- Mini view compact overlay with action icons
- FlippingPal comma CSV parser with RFC 4180 quoted field support
- Item ID column support for FP CSV exports
- Battle pet detection (name extraction, warbank scanning)
- Bind-type detection via tooltip scanning (Warbound Until Equipped)
- Sort by realm or item name
- Auctionator shopping list import
- Auto-pull queued items from bank
- Auto-scan bags on login

## v0.1.0
- Initial release
- Import from FlippingPal website copy-paste
- Import from semicolon CSV and tab-delimited formats
- Queue management with character routing
- Inventory scanning (bags, bank, reagent bag, warbank)
- Automatic post detection via AH bag monitoring
