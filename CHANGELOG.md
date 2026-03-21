# Changelog

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
