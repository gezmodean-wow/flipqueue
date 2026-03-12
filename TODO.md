# FlipQueue - TODO

## High Priority

### Sold Item Tracking
- [x] Monitor AH mail results to detect if posted items actually sold
- [x] Update log entries with `soldAt` timestamp and `soldPrice` when sale confirmed
- [x] Show sold/expired/active status in Log page
- [x] Detect sold items from owned auctions (missing from AH list = sold)
- [x] Mark expired as "collected" when user opens AH (clears "Check AH" next step)
- [x] Login alert for expired auctions on current character
- [ ] Profit calculation: sold price minus buy price from FP data (needs buy price tracking)

### Dead Code Cleanup
- [x] Remove `UI/Sections.lua` (deleted)
- [x] Remove `UI/LogPage.lua` (already gone)
- [x] Remove `UI/Rows.lua` from .toc (deleted, superseded by ScrollTable)
- [x] Remove `UI/UntrackedSection.lua` render functions (only kept DNT frame)

### Fix DNT Key Inconsistency
- [x] `/fq dnt add <name>` now resolves itemID from inventory before storing

## Medium Priority

### Junk Item Grouping
- [ ] Group poor-quality (gray) items in untracked inventory
- [ ] Option to pull junk to bags for vendor selling
- [ ] Option to bulk-ignore junk items

### Guild Bank Scanning
- [ ] Add guild bank container scanning (guild bank tab indices)
- [ ] Show guild bank items as a source in Inventory and Queue "Found On"

### Improved Post Detection
- [ ] Track partial posts (posted 7 of 10 → show 3 remaining)
- [ ] Don't remove queue entry on partial post, reduce quantity instead
- [ ] Better batch detection when posting multiple stacks

### Export / Backup
- [ ] Export queue to clipboard-compatible text (EditBox copy)
- [ ] Export log for spreadsheet analysis
- [ ] Import queue from previously exported data

### FlippingPal Website Styling
- [ ] Borrow visual elements from FlippingPal website for cleaner look
- [ ] Color coding by item quality (WoW rarity colors in table rows)
- [ ] Better visual hierarchy with subtle row grouping

## Low Priority

### Realm Matching Improvements
- [ ] Handle linked realm clusters more precisely (avoid false substring matches)
- [ ] Store connected realm mappings from WoW API (`GetAutoCompleteRealms`)
- [ ] Consider German realm name normalization

### Import Resilience
- [ ] Better error feedback when format auto-detection fails
- [ ] Show preview of parsed items before importing (count, sample names)
- [ ] Handle edge cases in FP website format changes gracefully

### Auctionator Integration
- [ ] Extract pricing data from Auctionator if available (not just item names)
- [ ] Two-way sync: create Auctionator shopping lists from queue

### TSM Integration
- [ ] Pull pricing data from TSM for queue items
- [ ] Use TSM item strings for better key matching
- [ ] Show TSM market value alongside FP expected price

### Pricing & Analytics
- [ ] Normalize gold strings for proper numeric sorting (parse "1,250g" → 1250)
- [ ] Price trend tracking over time
- [ ] Profit/loss summary dashboard
- [ ] "No competition" pattern analysis

### UI Polish
- [ ] Keyboard navigation (arrow keys, enter to act)
- [ ] Search/filter bar on each table page
- [ ] Right-click context menu instead of modifier-click actions
- [ ] Resizable main window with saved dimensions
- [ ] Row selection highlighting (multi-select for bulk actions)
- [ ] Item quality color in item name cells

### Multi-Character Coordination
- [ ] Show recommended login order (most tasks first)
- [ ] Cross-character progress tracking (items posted across all chars)
- [ ] Notification when logging onto a character with pending tasks

### CurseForge Distribution
- [x] Create CurseForge project (project ID in .toc)
- [x] Add `X-Curse-Project-ID` to .toc
- [x] Set up GitHub Actions for automatic packaging on tag push
- [x] First alpha release
