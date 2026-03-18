# Changelog

## v0.6.1-alpha
- **Deposit subtasks**: tracks which character holds items that need depositing to warbank, shows "via CharName" source tags (#47)
- **Smart character ordering**: Next Steps sorts depositors before receivers so players don't bounce between characters (#47)
- **Auto-generate To-Do on import**: checkbox on Import page to skip the Generator and auto-build a to-do list (#48)
- **Text overflow fix**: ScrollTable cells clipped to column bounds, prevents text overlapping adjacent columns (#49)
- **Guild bank scanning**: auto-scans when guild bank is opened, items appear in inventory and item pool (#52)
- **Character ignore UX**: left-click toggle column in Characters table, visible O/X indicator (#51)
- **Character onboarding**: first-login hint to log into each character, Generator tips for unassigned realms (#50)
- **Legacy data cleanup**: automatic migration/normalization on login — prunes old logs, fixes stale fields, removes zero-qty items
- TSM AH Price columns widened to fit large gold values
- Next Steps Detail column widened for deposit info
- Grouped items view shows `[via CharName]` or `[unavail]` source tags
- Current character tasks show "Deposit: N item(s) to warbank" when relevant
- `/fq gbank` slash command for manual guild bank scan
- `/fq cleanup` slash command for manual data normalization

## v0.5.0
- **Partial post detection**: posting fewer than queued quantity keeps remainder in queue (#6)
- **Mail scan updates**: detects expired/cancelled auction returns, marks as collected (#30)
- **State recovery**: discovers pre-existing AH auctions not tracked by the addon (#31)
- **Live auction expiry timer**: 60s ticker auto-marks expired auctions, chat notifications (#36)
- **Consolidated item matching**: unified 4-tier matching (key → ID → name → fuzzy) across all systems (#20, #33)
- **Shared gold parsing**: single ParseGoldValue utility replaces 3 duplicated implementations (#21)
- **Configurable batch size**: settings slider for warbank auto-pull batch size (#29)
- **Accent-insensitive realm matching**: handles German/EU realm names (#23)
- **Warbank batching rewrite**: event-driven 5-item batches with error detection (#24)
- **Configurable bank tab selection**: choose which bank/warbank tabs to scan and pull from (#26)
- **Error handling hardened**: all C_Item/C_Container calls wrapped in pcall (#28)
- **Release channels**: alpha/beta/release via tag naming convention
- Log page Qty column shows posted quantity per auction
- Recovered log entries marked with * and tooltip indicator
- Next Steps shows estimated gold value instead of countdown in Est. Value column
- Mini view shows countdown timer for expiring auctions
- Visible resize grip with hover highlight
- Redundant "New character needed" detail text removed

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
