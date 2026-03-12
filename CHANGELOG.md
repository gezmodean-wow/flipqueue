# Changelog

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
