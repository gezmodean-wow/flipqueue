# FlipQueue - TODO

## High Priority

### Sold Item Tracking
- [ ] Monitor AH mail results to detect if posted items actually sold
- [ ] Update log entries with `soldAt` timestamp and `soldPrice` when sale confirmed
- [ ] Show sold/expired/active status in Log page
- [ ] Profit calculation: sold price minus buy price from FP data
- Fields already exist in log entries (`soldAt`, `soldPrice`) but nothing populates them

### Dead Code Cleanup
- [ ] Remove `UI/Sections.lua` from .toc (superseded by MainFrame page renderers)
- [ ] Remove `UI/LogPage.lua` from .toc (superseded by MainFrame BuildLogData)
- [ ] Remove `UI/Rows.lua` from .toc (superseded by ScrollTable) - check MiniView dependency first
- [ ] Remove backward-compat stubs `HideAllRows()` / `GetOrCreateRow()` once confirmed unused
- [ ] Remove `UI/UntrackedSection.lua` render functions (only keep DNT frame)

### Fix DNT Key Inconsistency
- [ ] `/fq dnt add <name>` stores name as key instead of itemID - should lookup itemID from inventory
- [ ] Normalize all DNT entries to use itemID as key consistently

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
- [ ] Create CurseForge project (get project ID)
- [ ] Add `X-Curse-Project-ID` to .toc
- [ ] Set up GitHub Actions for automatic packaging on tag push
- [ ] First alpha release
