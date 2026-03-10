# FlipQueue

A World of Warcraft addon for managing cross-realm auction house arbitrage workflows. Designed to work alongside [FlippingPal.com](https://flippingpal.com), TSM, and Auctionator.

## Features

- **Import from FlippingPal** - Paste CSV data directly from FlippingPal's export. Supports website copy-paste, comma CSV (with Item ID), semicolon CSV, tab-delimited, and plain item name formats.
- **Queue management** - Track items to post across multiple realms and characters. Items are matched against your scanned inventory.
- **Character routing** - See which character has which item and where (bags, bank, warbank). Automatically detects items via inventory scanning.
- **Post tracking** - Right-click items to mark as posted. Posted items move to a timestamped log with price comparison against FlippingPal guidance.
- **Untracked inventory** - View items in your bags/warbank not currently in the queue. Excludes soulbound, warbound, and Do Not Track items.
- **Characters & Realms** - Overview of all scanned characters with class, realm, and task counts. Shows realms that need a new character created.
- **Mini overlay** - Compact draggable overlay showing current-character tasks, with quick action icons.
- **Minimap button** - Left-click to toggle the main window, right-click for settings.
- **Auto-pull from bank** - When you open the bank, automatically moves queued items to your bags.
- **Auto-scan** - Scans your bags on login and bank/warbank when the bank frame opens.

## Installation

1. Download and extract to your WoW AddOns folder:
   ```
   World of Warcraft\_retail_\Interface\AddOns\FlipQueue\
   ```
2. Restart WoW or `/reload`
3. Type `/fq` to open the main window

## Usage

### Importing Items

1. Go to [FlippingPal.com](https://flippingpal.com) and find items to flip
2. Copy the results (CSV export or website copy-paste)
3. In-game: `/fq import` or click **Import** in the sidebar
4. Click the text area and press **Ctrl+V** to paste
5. Click **Import**

### Main Window Pages

| Page | Description |
|------|-------------|
| **Post Now** | Items to post on your current character, filtered by matching realm |
| **Queue** | Full queue showing all items across all realms with inventory locations |
| **Log** | History of posted items with price tracking |
| **Inventory** | Untracked items in your bags/warbank (not in queue, not soulbound) |
| **Characters** | All scanned characters and realms needing new characters |
| **Settings** | Configure auto-scan, auto-pull, mini overlay, minimap icon |

### Slash Commands

```
/fq              - Toggle main window
/fq import       - Open import dialog
/fq log          - Show posted items log
/fq queue        - Show full queue
/fq inv          - Show untracked inventory
/fq scan         - Rescan current character's bags
/fq bank         - Scan bank + warbank (must be at bank)
/fq mini         - Toggle mini overlay
/fq settings     - Open settings
/fq clear        - Clear entire queue
/fq clear log    - Clear posted items log
/fq autopull     - Toggle auto-pull from bank
/fq dnt          - Show Do Not Track list
/fq dnt add <n>  - Add item to Do Not Track by name
/fq dnt remove <n> - Remove item from Do Not Track
/fq help         - Show all commands
```

### Interactions

- **Right-click** items in Post Now or Queue to mark as posted (moves to log)
- **Right-click** items in Inventory to add to Do Not Track
- **Shift+Right-click** items in Inventory to add to queue
- **Shift+Right-click** items in Log to remove the entry
- **Click column headers** to sort any table ascending/descending

### Supported Import Formats

- **FlippingPal Comma CSV** - `Item ID,Item Name,Category,...` or `Item Name,Category,...`
- **FlippingPal Website** - Direct copy-paste from FlippingPal results page
- **Semicolon CSV** - `itemID;itemName;quality;ilvl;bonusIDs;modifiers;quantity`
- **Tab-delimited** - Standard Excel/spreadsheet export
- **Auctionator Lists** - Import directly from an Auctionator shopping list
- **Plain text** - One item name per line

## Requirements

- World of Warcraft: The War Within (Interface 120001)
- No library dependencies

## Optional Integrations

- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)** - Import from shopping lists
- **[TradeSkillMaster](https://www.curseforge.com/wow/addons/tradeskill-master)** - Complementary AH tools

## Data Storage

FlipQueue uses `FlipQueueDB` (account-wide SavedVariables) to store:
- Queue and posted items log
- Inventory scans for all characters
- Warbank contents
- Do Not Track list
- Settings and UI preferences

Data persists across characters and sessions.

## License

MIT License - see [LICENSE](LICENSE) for details.
