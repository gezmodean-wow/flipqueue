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

## High Priority

### Profit Calculation (#22)
- [ ] Store buy price from FP import data
- [ ] Calculate profit: sold price - buy price - AH cut
- [ ] Show profit column in Log page
- [ ] Aggregate profit summary

### Bug: Sales records don't match TSM (#57)
- [ ] Investigate discrepancy between FlipQueue and TSM sales data

### Bug: Inventory quantities not reconciled (#55)
- [ ] Shows more items than actually exist — quantity tracking issue

### Bug: TSM multi-post only logs 1 item (#54)
- [ ] When posting multiple stacks via TSM, only first is logged

### Bug: Battle pets randomly appearing (#44)
- [ ] Investigate pet detection false positives in inventory/queue

### Bug: Schematics incorrect item detection (#45)
- [ ] Schematics have same prefix-matching issue as recipes

## Medium Priority

### Improved Post Detection (#6)
- [x] Track partial posts (posted 7 of 10)
- [x] Reduce quantity on partial post instead of removing
- [ ] Better batch detection when posting multiple stacks

### Export Enhancements (#7, #42)
- [x] Export to clipboard with FP CSV and AAA JSON
- [x] Format and filter toggles
- [ ] Log export for spreadsheet analysis
- [ ] Data freshness indicator
- [ ] Re-import from previously exported data

### Inventory Enhancements (#40)
- [x] Status badges (Queued, Posted, DNT, Untracked)
- [ ] AH location tracking
- [ ] Collapsible DNT section

### TSM Profile Selector (#41)
- [ ] Profile selector not working properly
- [ ] Multi-profile support

### Auctionator Enhancements (#43)
- [x] Shopping list detection and creation
- [ ] Organized UI with categories
- [ ] Preview before creating lists
- [ ] Template system

### TSM Rejection Handling (#38)
- [ ] Handle items TSM skips (below min price)
- [ ] Item reassignment to different character/time

### Unify Data Sources (#59)
- [ ] Different views show inconsistent data — unify underlying queries

### Make Dupe Indicator Clearer (#58)
- [ ] "Dupe" label in character menu needs better explanation/UX

### Junk Item Grouping (#4)
- [ ] Group poor-quality (gray) items in untracked inventory
- [ ] Option to pull junk to bags for vendor selling
- [ ] Option to bulk-ignore junk items

## Low Priority

### Import Resilience (#10)
- [x] Format auto-detection (FP website, CSV, tab, plain names)
- [x] Import preview with status/reasons
- [ ] Log which parser was used for debugging

### Realm Matching (#9)
- [x] Accent normalization for EU realm names
- [ ] Use GetAutoCompleteRealms for structured connected realm data

### UI Polish (#14)
- [x] Resizable main window
- [x] Right-click handlers on table rows
- [ ] Search/filter bar on each table page
- [ ] Keyboard navigation
- [ ] Row selection highlighting

### Multi-Character Coordination (#15)
- [x] Recommended login order (BuildNextStepsData, gold-sorted)
- [x] Cross-character progress (Character page summaries)
- [x] Login notification with pending tasks
- [ ] More explicit ordering UI

### Pricing Analytics (#13)
- [ ] Price trend tracking over time
- [ ] Profit/loss summary dashboard

### Debug Log Export (#34)
- [ ] Export debug data for community bug reports

### New Character Wizard (#35)
- [ ] Guided setup for new characters (default settings, TSM group)

### Configuration Profiles (#27)
- [ ] Import/export settings across accounts

### Internationalization (#25)
- [ ] i18n for addon UI strings

## Future Features

### Cross-Realm Flipping Import (#60)
- [ ] Import FP cross-realm flipping reports
- [ ] Generate "buy" to-do items
- [ ] Auto-convert to "sell" once acquired

### Item Tooltips (#61)
- [ ] Show FlipQueue data on item tooltips in-game

### Shopping List Generation + Sniper Export
- [ ] Generate shopping lists from unmatched deals
- [ ] Export to AAA JSON or sniper addon format

## Code Quality

- [x] Consolidate item matching logic (#20)
- [x] Extract gold parsing to shared utility (#21)
- [x] Remove export popup (ExportPopup.lua kept for Generator quick-export; inline ExportPage.lua is primary)
- [ ] BuildLogData inventory lookup O(n²) — cache per Refresh
