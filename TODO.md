# FlipQueue - TODO

## Completed

- [x] Sold item tracking via AH mail (#1)
- [x] Dead code cleanup (#2)
- [x] Fix DNT key inconsistency (#3)
- [x] CurseForge/Wago distribution setup (#16)
- [x] Import preview with new/update/duplicate status (#10 partial)
- [x] Settings redesign with inline descriptions (#17)
- [x] Custom artwork and branding (#18)
- [x] Hide mini view in combat (#19)
- [x] Gold value numeric sorting (#13 partial)
- [x] Realm "..." dedup fix (#9 partial)
- [x] AH fee estimate updated (60% vendor at 48h)
- [x] Credits section in Settings
- [x] Consolidate item matching — `ns:ItemsMatch()` unified 4-tier matcher (#20)
- [x] Extract gold parsing — `ns:ParseGoldValue()` in DB.lua (#21)
- [x] Guild bank scanning — async tab-by-tab via QueryGuildBankTab (#5)
- [x] TSM integration — pricing, columns, profile selection, threshold warnings (#12)
- [x] Auctionator integration — shopping list create/import, list detection (#11)
- [x] Resizable sidebar and main window (#37)
- [x] To-Do Generator queue management — append/replace/queue up (#39)
- [x] Task sub-actions (steps model: retrieve/post/collect) (#46)
- [x] Bank pull quantity setting — fixed vs TSM mode (#56)
- [x] Quality color coding in all tables (#8 partial)
- [x] Realm accent normalization for EU realm names (#9 partial)
- [x] AAA Transformer JSON export (#32 partial)
- [x] File refactoring — 19 files → 31 files, largest reduced from 3567 to 1806 lines
- [x] Generator UX — persistent filter settings, auto-generate, import popup, export footer

### Resolved in v0.11.0

- [x] Sales records don't match TSM (#57) — three-bug reconciliation overhaul (FQ-001), `/fq reconcile` cross-checks against TSM's csvSales
- [x] Inventory quantities not reconciled (#55)
- [x] TSM multi-post only logs 1 item (#54) — postCap evaluation now goes through TSM's price engine, non-commodity PostItem honors the cap
- [x] Battle pets randomly appearing (#44)
- [x] Schematics incorrect item detection (#45)
- [x] Phantom character tasks in mini view
- [x] Dupe indicator clearer (#58)
- [x] Debug log export (#34) — `/fq debug` console with ring-buffered 500-message log + action button for copy-to-clipboard

## High Priority

### Deposit task noise
- [ ] Suppress deposit tasks for items actively being posted (currently surfaces noise for items in flight)

### Brutosaur mount summon
- [ ] Trader's Gilded Brutosaur (mount ID 2265) still not working per player report — need in-game mount journal ID verification

### TSM rejection handling (#38)
- [ ] When TSM skips an item (below min / above max), offer reassignment to another character or defer to a later time
- [ ] Scaffolding exists in `TodoList:HandleTSMRejections` — needs finishing

## Medium Priority

### Unify data sources (#59)
- [ ] Different views (Log, Research, Inventory, Deal Finder) occasionally show inconsistent numbers
- [ ] `SalesIndex.lua` is the canonical query layer — find and route any remaining bypasses through it

### Auctionator enhancements (#43)
- [x] Shopping list detection and creation
- [ ] Organized UI with categories
- [ ] Preview before creating lists
- [ ] Template system

### Junk item grouping (#4)
- [ ] Group poor-quality (gray) items in untracked inventory
- [ ] Option to pull junk to bags for vendor selling
- [ ] Option to bulk-ignore junk items

### TSM Profile Selector (#41) — validation needed
- [x] Read/write/consume chain audited — dropdown writes `db.settings.tsmProfile`, `GetSelectedProfile` reads it with fallback to active, cache invalidates on change. Appears functional.
- [ ] Needs concrete repro before pursuing as a bug
- [ ] Per-character profile selection (if "multi-profile support" means this) is a new feature, not a fix

### Re-import from previously exported (#42)
- [ ] Existing round-trip works through AAA / PBS; treat as low-risk maintenance

## Low Priority

### AH location tracking on inventory (#40)
- [ ] Keep tracking; not urgent

### Import resilience (#10)
- [x] Format auto-detection
- [x] Import preview with status/reasons
- [ ] Log which parser was used for debugging

### Realm matching (#9)
- [x] Accent normalization
- [ ] Use GetAutoCompleteRealms for structured connected realm data

### UI polish (#14)
- [x] Resizable main window
- [x] Right-click handlers on table rows
- [ ] Search/filter bar on each table page
- [ ] Keyboard navigation
- [ ] Row selection highlighting

### Multi-character coordination (#15)
- [x] Recommended login order (BuildNextStepsData, gold-sorted)
- [x] Cross-character progress (Character page summaries)
- [x] Login notification with pending tasks
- [ ] More explicit ordering UI

### Pricing analytics (#13)
- [ ] Price trend tracking over time
- [ ] Profit/loss summary dashboard — see Tally ownership note below

### New character wizard (#35)
- [ ] Guided setup for new characters (default settings, TSM group)

### Configuration profiles (#27)
- [ ] Import/export settings across accounts

### Internationalization (#25)
- [ ] i18n for addon UI strings

## Quality & Performance

- [ ] `BuildLogData` inventory lookup O(n²) — cache per Refresh
- [ ] TSM audit-drift guard (`TSM_AUDITED_VERSION` in `TSM.lua`) — re-verify `MakePostDecision` and operation schema on each TSM minor-version bump; bump the constant when confirmed

## Upcoming Architectural Work

### Cogworks UI framework refactor
- [ ] Rebuild FlipQueue widgets on top of the shared Cogworks UI framework (lives in `C:\src\cogworks\`) instead of hand-rolled Blizzard template widgets. Goal: consistent look, shared scroll/dropdown/backdrop behavior across the cog suite, less local UI code to maintain.
- [ ] Migrate page-by-page rather than big-bang; start with a low-risk page (Settings? TSM Integration?) to validate the framework fits FQ's needs.

### Break functionality into sibling cogs
- [ ] **Tally** (sibling cog) owns the sales ledger. FlipQueue's `ns.db.log` + SalesIndex move to Tally, which exposes a canonical read API for Log page rendering and any future profit/loss analytics. Removes ledger concerns from FlipQueue's scope entirely.
- [ ] **Tempo** (sibling cog) owns the to-do list structure. FlipQueue's TodoList module becomes a consumer of Tempo's task engine rather than the source of truth. Lets Tempo power similar task flows for other cogs.
- [ ] FlipQueue's remaining scope: AH posting engine, reconciliation (mail scan + TSM cross-check), character routing, import pipeline. Becomes the workflow orchestrator on top of Tally (ledger) + Tempo (tasks).

### TSM API requests
- [x] Drafted: `docs/tsm-api-request.md` — `TSM_API.GetAuctioningPostDecision` + `GetAuctioningCancelDecision`. Would collapse ~200 lines of `ResolvePostPrice` and the audit-drift scaffolding.
- [ ] Submit to TSM upstream (GitHub issue / Discord `#api-requests`)
- [ ] Track additional API gaps as they surface during refactors — e.g. live-scan result subscriptions for blacklist/whitelist matching, post-hook notifications for cross-cog ledger sync

## Future Features

### Cross-realm flipping import (#60)
- [x] Import FP cross-realm flipping reports
- [x] Generate "buy" to-do items
- [x] Auto-convert to "sell" once acquired

### Item tooltips (#61)
- [ ] Show FlipQueue data on item tooltips in-game

### Shopping list generation + sniper export
- [ ] Generate shopping lists from unmatched deals
- [ ] Export to AAA JSON or sniper addon format

## Removed from scope

- Profit calculation (#22) — not pursuing as a FlipQueue feature. Any profit analytics would live in Tally once the ledger moves there.
- Log export for spreadsheet analysis — candidate for Tally once the ledger split lands
