# Phase 2-3: To-Do Generator + To-Do List (core architecture)

## Overview

Replace the queue-driven model with: **Inventory (source of truth) -> Generator (decision engine) -> To-Do Lists (execute) -> Log**

The queue concept is replaced by an **item pool** (all tradeable inventory + FP deal data). The Generator produces To-Do Lists from that pool. To-Do Lists are specific, actionable, per-character task lists.

---

## Data Model Changes

### New: `ns.db.todoLists`

```lua
ns.db.todoLists = {
    current = {          -- active to-do list
        name = "FP Import 2026-03-15",
        createdAt = timestamp,
        items = {        -- array of task items
            {
                itemKey = "258909;1663:2293;",
                itemID = "258909",
                name = "Tarnished Dawnlit Signet",
                targetRealm = "Feathermoon",
                expectedPrice = "500g",
                quantity = 1,        -- how many to post (from TSM postCap or import)
                assignedChar = "Flipbook-Feathermoon",  -- nil = unassigned
                status = "pending",  -- pending | posted | failed | skipped
                failReason = nil,    -- "TSM below threshold", "expired", etc.
                attempts = 0,        -- how many times posted on this realm
                source = "warbank",  -- where the item is (bags, warbank, bank, mail)
            },
        },
    },
    queue = {            -- upcoming to-do lists (FIFO)
        -- array of lists, same structure as current
    },
}
```

### Keep: `ns.db.inventory`, `ns.db.warbank`
These remain the source of truth for what items exist. Scanner populates them.

### Keep: `ns.db.log`
Auction history. Reconciled against AH reality when AH is opened.

### Remove: `ns.db.queue`
Replaced by `ns.db.todoLists`. Migration: convert existing queue items into a to-do list on first load.

---

## Phase 2: Inventory as Source of Truth

### 2a. Scanner enrichment (DONE)
- `EnrichQueueFromInventory()` backfills item keys, bonus IDs, icons, quality from scanned items

### 2b. Item Pool
- Function: `BuildItemPool()` -- collects all tradeable items across all characters + warbank
- Each pool item knows: where it is (character + location), its real item key, vendor price, TSM price, TSM operation details
- This replaces scanning the queue for realm matches

### 2c. FP Deal Data
- FP imports populate a deal list: item + target realm + expected price
- Deals are NOT tasks -- they are opportunities. The generator matches deals against inventory to create tasks.
- Unmatched deals (item not in inventory) show as "missing" -- player needs to acquire them

---

## Phase 3: To-Do Generator

### Generator Page Layout

```
+---------------------------------------------+
| DATA SOURCES                                |
| Bags: 2m ago  Warbank: 5m ago  FP: 1h ago  |
| [Rescan Bags] [Rescan Warbank]              |
+---------------------------------------------+
| CURRENT TO-DO LIST                     [v]  |
|  "FP Import Mar 15" -- 12 items, 3 done    |
| QUEUED LISTS                           [v]  |
|  "Weekend batch" -- 8 items     [Delete]    |
+---------------------------------------------+
| GENERATE NEW LIST                           |
|                                             |
| Priority: [By Gold v]                       |
|                                             |
| Preview Table:                              |
| Item | Qty | Realm | Character | Value | C  |
| ------------------------------------------- |
| Signet | 1 | Feathermoon | Flipbook | 500g |Y|
| Bifocals| 1 | Feathermoon | Flipbook | 200g|Y|
| ...                                         |
|                                             |
| [APPEND to current] [REPLACE current]       |
| [QUEUE UP as next]                          |
+---------------------------------------------+
```

### Generator Logic: `GenerateTodoList(priorityMode, options)`
1. Get item pool (all tradeable inventory)
2. Get FP deals (imported target realm + price data)
3. Match deals against pool items (by key, ID, or name)
4. For each matched deal:
   - Find best character to post (has item, or warbank item + character on realm)
   - Check TSM threshold -- flag if below min
   - Apply postCap from TSM operation
5. Sort by priority mode
6. Return preview list for player review

### Priority Modes
- **By Gold**: highest expected value first
- **By Population**: high-pop realms first (future: realm pop data)
- **By Opportunity**: uncontested items first (no other auctions)
- **Best per Character**: minimize logins -- group by character
- **Manual**: player drag-reorders

### Commit Actions
- **APPEND**: add preview items to current to-do list
- **REPLACE**: clear current list, set preview as new current
- **QUEUE UP**: save preview as next to-do list in the queue

---

## Phase 3b: To-Do List (execution page)

### To-Do Page Layout
Shows current to-do list for the logged-in character. Tasks have sub-actions.

```
+---------------------------------------------+
| TO-DO -- Flipbook-Feathermoon       [Rescan]|
+---------------------------------------------+
| ! Check Mail: 2 expired in mailbox         |
| ! Check AH: 1 expired auction              |
+---------------------------------------------+
| Post 1 Tarnished Dawnlit Signet    500g     |
|   > Pull from Warbank                      |
| Post 1 Bold Biographer Bifocals    200g     |
|   > In bags (ready)                        |
| Post 1 Pattern: Saddlebag          50g      |
|   > TSM: SKIP (below threshold)            |
+---------------------------------------------+
| Next Steps (other characters):              |
| Log in Gezmodean-Tichondrius (3 items)      |
| Log in Flipsy-Durotan (2 items)             |
+---------------------------------------------+
```

### Task Sub-Actions (computed, not stored)
Based on current state at render time:
- **In bags** -> ready to post
- **Pull from Warbank/Bank** -> needs to be moved first (auto-pull handles this)
- **TSM: SKIP** -> below threshold, will not post
- **In mail** -> needs to be collected first
- **Not found** -> item missing from inventory

### Task Lifecycle
1. Generator creates task: `status = "pending"`
2. Player opens bank -> auto-pull moves item to bags (if needed)
3. Player opens AH -> TSM posts item -> bag qty decreases -> detected as posted
4. `status = "posted"` -> moved to log
5. If auction expires -> item returns to mail -> task goes back to item pool for reassignment
6. Generator can reassign to different realm/character

### What Happens on Failure
- Auction expires -> log entry marked "expired", item goes back to pool
- TSM rejects (below threshold) -> task shows "TSM: SKIP", player can skip or wait
- Player puts item back in warbank -> task stays but will not auto-pull again until regenerated

---

## Migration

On first load after update:
1. Convert `ns.db.queue` items into a to-do list (`ns.db.todoLists.current`)
2. Preserve all existing data (realm, price, quantity, status)
3. Keep `ns.db.queue` as backup for one version, then remove

---

## Files Affected

| File | Changes |
|------|---------|
| `Core.lua` | New `ns.db.todoLists` in InitDB, migration from queue |
| `Scanner.lua` | EnrichQueueFromInventory -> EnrichTodoFromInventory |
| `Queue.lua` | Refactor to TodoList.lua. GetCharacterTasks reads from todoLists |
| `Tracker.lua` | AutoPull/AutoWithdraw read from todoLists. Post detection updates todoList items. Expiry returns items to pool. |
| `UI/MainFrame.lua` | Generator page: data sources, preview table, commit buttons, list queue. To-Do page: sub-actions rendering. |
| `UI/MiniView.lua` | Read from todoLists for current character |
| `Import.lua` | Import creates deal data, not queue items directly |
| `Export.lua` | No major changes (reads inventory) |

---

## Implementation Order

1. Data model: add `ns.db.todoLists`, migration from queue
2. `BuildItemPool()` -- collect all tradeable inventory
3. `GenerateTodoList()` -- match deals against pool, allocate to characters
4. Generator UI: data sources panel, preview table, commit buttons
5. To-Do page: render from todoLists with sub-actions
6. Tracker: AutoPull/AutoWithdraw/PostDetection use todoLists
7. List queue management (APPEND/REPLACE/QUEUE UP, delete, reorder)
8. Priority modes
9. Mini view update
10. Remove old queue code
