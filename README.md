# FlipQueue

A World of Warcraft addon that turns FlippingPal deals into a step-by-step to-do list across your characters. Import deals, generate tasks, and FlipQueue tells you exactly what to post, from where, on which character — with full TSM and Auctionator integration.

Designed to work alongside [FlippingPal.com](https://flippingpal.com), [TradeSkillMaster](https://www.curseforge.com/wow/addons/tradeskill-master), and [Auctionator](https://www.curseforge.com/wow/addons/auctionator).

## How It Works

1. **Import** deals from FlippingPal (paste CSV or copy from website)
2. **Generate** a to-do list — FlipQueue matches deals against your inventory across all characters and assigns each item to the best character
3. **Follow** the to-do list — log into each character, and FlipQueue shows exactly what to pull from bank/warbank and post on the AH
4. **Track** — auctions are logged automatically, expired items flagged, gold withdrawn from warbank for posting fees

## Features

### To-Do System
- **To-Do Generator** — two-column page: filter your item pool (All / TSM Group / Auctionator List), set allocation priority, and generate a task list
- **To-Do List** — the single source of truth for what to post, where, and in what order. Tasks track steps (retrieve → post → collect) and advance based on game events
- **Task deferral** — items not accessible on the current character sort to the bottom. Deposit subtasks show which character needs to send items via warbank
- **Import type tags** — lists show their data source (Inventory Scan, Cross-Realm Flip, TSM Import, Auctionator Import)

### TSM Integration
- **Per-item operations** — reads your Auctioning operations for postCap, duration, and minPrice threshold
- **Group filtering** — Generator filters items by TSM group tree
- **Price columns** — AH Price shown in To-Do and Generator tables with optional auto-update
- **Threshold skip** — items below TSM minPrice are auto-skipped with reason
- **Character detection** — auto-detects characters from TSM data on login

### Auctionator Integration
- **Shopping list filtering** — Generator filters items by Auctionator shopping list
- **List import** — import items directly from Auctionator lists

### Inventory & Scanning
- **Full inventory view** — all tradeable items across all characters with status badges (Assigned / Posted / Check AH / Unknown / Ignored)
- **Live tracking** — inventory updates in real-time on item movement
- **Auto-scan** — bags scanned on login, bank/warbank when bank frame opens
- **Smart filtering** — excludes soulbound and warbound items, respects Do Not Track list

### Export
- **Live scan export** — scan Bags, Bank, Warbank, or All and export immediately
- **Saved data export** — export from the inventory database without visiting bank
- **Filters** — export Everything, a specific TSM Group, or an Auctionator List
- **Formats** — FlippingPal CSV and AAA JSON

### Characters & Realms
- **AH cluster grouping** — characters on connected realms show "Shared AH" with the full cluster in tooltip
- **Realms needing characters** — shows unassigned task realms with item counts and gold value
- **Character management** — hide/show characters, manual sort order, TSM character detection with Add/Dismiss
- **Gold overview** — per-character gold, total across account

### Automation
- **Auto-pull from bank** — when you open bank, queued items move to bags automatically
- **Auto-deposit to warbank** — deposits items needed by other characters
- **Gold withdrawal** — auto-withdraws posting fees from warbank (configurable)
- **Bank tab selection** — choose which tabs to scan and pull from

### UI
- **Sidebar navigation** — TSM-style dark theme with section headers
- **Sortable tables** — click column headers to sort
- **Mini overlay** — compact draggable panel with current tasks, deposit details, expiring auction timers
- **Minimap button** — left-click to toggle, right-click for settings
- **Custom artwork** — addon icon, banner, and logo

## Installation

1. Download from [CurseForge](https://www.curseforge.com/wow/addons/flipqueue) or [Wago](https://addons.wago.io/addons/flipqueue)
2. Extract to your AddOns folder:
   ```
   World of Warcraft\_retail_\Interface\AddOns\FlipQueue\
   ```
3. Restart WoW or `/reload`
4. Type `/fq` to open the main window

## Pages

| Page | Description |
|------|-------------|
| **To-Do** | Items to post on your current character — pull from bank/warbank and post |
| **To-Do Generator** | Build task lists from imported deals with filter and priority controls |
| **Inventory** | All tradeable items across characters with status badges |
| **Characters** | Character overview with gold, tasks, auctions, AH cluster info |
| **Import** | Paste FlippingPal data or import from Auctionator lists |
| **Export** | Scan and export inventory in FP CSV or AAA JSON format |
| **TSM** | TSM profile selection and integration settings |
| **Auctionator** | Auctionator shopping list viewer |
| **Log** | Auction history — posted, sold, expired, collected |
| **Settings** | Automation, display, bank tabs, credits |

## Slash Commands

```
/fq              Toggle main window
/fq import       Open import page
/fq log          Show auction log
/fq inv          Show full inventory
/fq scan         Rescan current character's bags
/fq bank         Scan bank + warbank (at bank)
/fq gbank        Scan guild bank (at guild bank)
/fq mini         Toggle mini overlay
/fq settings     Open settings
/fq sort <mode>  Set generator sort mode
/fq clear        Clear imports
/fq clear log    Clear auction log
/fq dnt          Show Do Not Track list
/fq dnt add <n>  Add item to DNT by name
/fq dnt remove <n>  Remove from DNT
/fq gold         Show gold across characters
/fq state        Export diagnostic data
/fq help         Show all commands
```

## Mouse Interactions

- **Right-click** items in To-Do to mark as posted (moves to log)
- **Shift+Right-click** in To-Do to skip an item
- **Right-click** items in Inventory to add to Do Not Track
- **Shift+Right-click** in Inventory to add to imports
- **Click** characters to hide/show from task routing
- **Click column headers** to sort tables

## Supported Import Formats

- **FlippingPal CSV** — with or without Item ID column
- **FlippingPal Website** — direct copy-paste from results page
- **Semicolon CSV** — `itemID;name;quality;ilvl;bonusIDs;modifiers;qty`
- **Tab-delimited** — spreadsheet export
- **Auctionator Lists** — import from shopping lists
- **Plain text** — one item name per line

## Requirements

- World of Warcraft: The War Within (Interface 120001)

## Optional Integrations

- **[TradeSkillMaster](https://www.curseforge.com/wow/addons/tradeskill-master)** — price data, per-item operations, group filtering, character detection
- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)** — shopping list import and filtering

## Data Storage

FlipQueue uses `FlipQueueDB` (account-wide SavedVariables) to store:
- Character inventories and metadata
- Warbank contents
- Imported deals and to-do lists
- Auction log
- Do Not Track list
- Settings and UI preferences

Data persists across characters and sessions. Schema migrations run automatically on updates.

## License

MIT License - see [LICENSE](LICENSE) for details.
