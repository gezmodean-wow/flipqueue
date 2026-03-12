# FlipQueue - TODO

## Completed (v0.4.1)

- [x] Sold item tracking via AH mail (#1)
- [x] Dead code cleanup: Rows.lua, Sections.lua, LogPage.lua, UntrackedSection.lua (#2)
- [x] Fix DNT key inconsistency (#3)
- [x] CurseForge/Wago distribution setup (#16)
- [x] Import preview with new/update/duplicate status and dupe reasons (#10 partial)
- [x] Settings redesign with inline descriptions (#17)
- [x] Custom artwork and branding (#18)
- [x] Hide mini view in combat (#19)
- [x] Gold value numeric sorting (#13 partial)
- [x] Realm "..." dedup fix (#9 partial)
- [x] AH fee estimate updated (60% vendor at 48h)
- [x] Credits section in Settings

## High Priority

### Profit Calculation (#22)
- [ ] Store buy price from FP import data
- [ ] Calculate profit: sold price - buy price - AH cut
- [ ] Show profit column in Log page
- [ ] Aggregate profit summary

## Medium Priority

### Consolidate Item Matching (#20)
- [ ] Extract to single `ns:ItemsMatch()` utility
- [ ] Replace 4 duplicated matching implementations

### Junk Item Grouping (#4)
- [ ] Group poor-quality (gray) items in untracked inventory
- [ ] Option to pull junk to bags for vendor selling
- [ ] Option to bulk-ignore junk items

### Guild Bank Scanning (#5)
- [ ] Add guild bank container scanning
- [ ] Show guild bank items as source in Inventory and Queue "Found On"

### Improved Post Detection (#6)
- [ ] Track partial posts (posted 7 of 10 → show 3 remaining)
- [ ] Don't remove queue entry on partial post, reduce quantity instead
- [ ] Better batch detection when posting multiple stacks

### Export / Backup (#7)
- [ ] Export queue to clipboard-compatible text
- [ ] Export log for spreadsheet analysis
- [ ] Import queue from previously exported data

### Visual Polish (#8)
- [ ] Borrow visual elements from FlippingPal website
- [ ] Color coding by item quality in table rows
- [ ] Better visual hierarchy with subtle row grouping

## Low Priority

### Realm Matching (#9)
- [ ] Use GetAutoCompleteRealms for structured connected realm data
- [ ] German realm name normalization

### Import Resilience (#10)
- [ ] Better error feedback when format auto-detection fails
- [ ] Log which parser was used for debugging

### Auctionator Integration (#11)
- [ ] Extract pricing data from Auctionator if available
- [ ] Two-way sync: create Auctionator shopping lists from queue

### TSM Integration (#12)
- [ ] Pull pricing data from TSM for queue items
- [ ] Use TSM item strings for better key matching
- [ ] Show TSM market value alongside FP expected price

### Pricing Analytics (#13)
- [ ] Price trend tracking over time
- [ ] Profit/loss summary dashboard

### UI Polish (#14)
- [ ] Search/filter bar on each table page
- [ ] Right-click context menu
- [ ] Keyboard navigation
- [ ] Resizable main window
- [ ] Row selection highlighting

### Multi-Character Coordination (#15)
- [ ] Show recommended login order (most tasks first)
- [ ] Cross-character progress tracking
- [ ] Notification when logging onto a character with pending tasks

### Code Quality (#20, #21)
- [ ] Consolidate item matching logic
- [ ] Extract gold parsing to shared `ns:ParseGoldValue()` (#21)
- [ ] BuildLogData inventory lookup O(n²) — cache per Refresh
- [ ] Export.lua has both popup frame AND inline tabs (remove popup)
