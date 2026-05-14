-- TodoList.lua
-- To-Do list management, task access, and task operations
-- Generator/allocation functions are in TodoGenerator.lua
local addonName, ns = ...

local TodoList = {}
ns.TodoList = TodoList

--------------------------
-- List Management
--------------------------

-- Commit a generated preview as the active or upcoming todo list.
-- mode: "replace" (default) | "append" | "upcoming"
function TodoList:CommitList(preview, mode)
    if not ns.db or not ns.db.todoLists or not preview then return end

    mode = mode or "replace"

    -- Convert preview .items to .tasks for storage
    if preview.items then
        preview.tasks = preview.items
        preview.items = nil
    end

    if mode == "replace" then
        ns.db.todoLists.active = preview
    elseif mode == "append" then
        if not ns.db.todoLists.active or not ns.db.todoLists.active.tasks then
            ns.db.todoLists.active = preview
        else
            for _, task in ipairs(preview.tasks) do
                table.insert(ns.db.todoLists.active.tasks, task)
            end
        end
    elseif mode == "queue" or mode == "upcoming" then
        table.insert(ns.db.todoLists.upcoming, preview)
    end

    -- Imports are ephemeral working state for the import → generate phase.
    -- Once a list has been committed they've served their purpose, and the
    -- to-do list itself becomes the source of truth for what's "active".
    -- Clearing here prevents the imports table from growing across sessions.
    if ns.ImportClearAll then ns:ImportClearAll() end
end

-- Promote next upcoming list to active. Returns true if promoted.
function TodoList:AdvanceQueue()
    if not ns.db or not ns.db.todoLists then return false end

    if #ns.db.todoLists.upcoming > 0 then
        ns.db.todoLists.active = table.remove(ns.db.todoLists.upcoming, 1)
        return true
    end
    return false
end

-- Delete an upcoming list by index
function TodoList:DeleteQueuedList(index)
    if not ns.db or not ns.db.todoLists then return end
    if ns.db.todoLists.upcoming[index] then
        table.remove(ns.db.todoLists.upcoming, index)
    end
end

-- Clear the active list and auto-promote the next queued list
function TodoList:ClearCurrent()
    if not ns.db or not ns.db.todoLists then return end
    ns.db.todoLists.active = nil

    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
        ns.Sync:EmitDelta("TDCLEAR", {})
    end

    -- Auto-promote next queued list if available
    if self:AdvanceQueue() then
        local promoted = ns.db.todoLists.active
        local name = promoted and promoted.name or "Unnamed"
        if ns.Print then
            ns:Print(ns.COLORS.GREEN .. "Promoted queued list: " .. name .. "|r")
        end
    end
end

-- Duplicate a list by index. Returns new index or nil.
function TodoList:DuplicateList(idx)
    if not ns.db or not ns.db.todoLists then return nil end

    local src
    if idx == 0 then
        src = ns.db.todoLists.active
    else
        src = ns.db.todoLists.upcoming[idx]
    end
    if not src then return nil end

    -- Deep copy tasks
    local newTasks = {}
    for _, task in ipairs(src.tasks or {}) do
        local copy = {}
        for k, v in pairs(task) do copy[k] = v end
        copy.status = "pending"
        copy.failReason = nil
        table.insert(newTasks, copy)
    end

    local newList = {
        name      = (src.name or "Copy") .. " (copy)",
        createdAt = time(),
        tasks     = newTasks,
    }
    table.insert(ns.db.todoLists.upcoming, newList)
    return #ns.db.todoLists.upcoming
end

-- Rename a list. idx=0 for active, 1+ for upcoming.
function TodoList:RenameList(idx, name)
    if not ns.db or not ns.db.todoLists or not name or name == "" then return end

    if idx == 0 then
        if ns.db.todoLists.active then
            ns.db.todoLists.active.name = name
        end
    else
        if ns.db.todoLists.upcoming[idx] then
            ns.db.todoLists.upcoming[idx].name = name
        end
    end
end

-- Reorder upcoming lists. Moves upcoming[from] to upcoming[to].
function TodoList:ReorderQueue(from, to)
    if not ns.db or not ns.db.todoLists then return end
    local q = ns.db.todoLists.upcoming
    if not q[from] then return end
    to = math.max(1, math.min(to, #q))
    if from == to then return end

    local item = table.remove(q, from)
    table.insert(q, to, item)
end

-- Promote an upcoming list to be the active list.
-- The old active list (if any) goes to the front of upcoming.
function TodoList:PromoteToActive(qIdx)
    if not ns.db or not ns.db.todoLists then return end
    local q = ns.db.todoLists.upcoming
    if not q[qIdx] then return end

    local promoted = table.remove(q, qIdx)
    if ns.db.todoLists.active then
        table.insert(q, 1, ns.db.todoLists.active)
    end
    ns.db.todoLists.active = promoted
end

--------------------------
-- Task Access
--------------------------

-- Get the active to-do list (or nil)
function TodoList:GetCurrentList()
    if not ns.db or not ns.db.todoLists then return nil end
    return ns.db.todoLists.active
end

-- Get upcoming lists array
function TodoList:GetQueuedLists()
    if not ns.db or not ns.db.todoLists then return {} end
    return ns.db.todoLists.upcoming
end

-- Get favorited templates map (name -> list snapshot).
function TodoList:GetTemplates()
    if not ns.db or not ns.db.todoLists then return {} end
    return ns.db.todoLists.templates or {}
end

-- Sources for the Regenerate track: a flat array of { kind, label, list }
-- entries the wizard can present in step 1. Kinds: "active", "queued",
-- "template". Caller treats list read-only; regeneration produces a NEW
-- list via CommitList.
function TodoList:GetRegenSources()
    local sources = {}
    if not ns.db or not ns.db.todoLists then return sources end

    if ns.db.todoLists.active then
        sources[#sources + 1] = {
            kind  = "active",
            label = ns.db.todoLists.active.name or "Active list",
            list  = ns.db.todoLists.active,
        }
    end
    for i, list in ipairs(ns.db.todoLists.upcoming or {}) do
        sources[#sources + 1] = {
            kind     = "queued",
            label    = list.name or ("Queued #" .. i),
            list     = list,
            queueIdx = i,
        }
    end
    for name, snapshot in pairs(ns.db.todoLists.templates or {}) do
        sources[#sources + 1] = {
            kind  = "template",
            label = name,
            list  = snapshot,
        }
    end
    return sources
end

-- Build a fresh list snapshot from an existing list, optionally dropping
-- tasks by itemKey, with prices refreshed via the chosen mode.
--
--   sourceList   the list to base on (read-only; not mutated)
--   refreshMode  "fpsaved" - re-resolve expectedPrice via ns:ResolveFPPrice
--                            against the original import bucket. Picks up
--                            the user's current fpPriceSource setting.
--                "tsmlive" - use TSM live DBRegionMarketAvg as expectedPrice
--                            (falls through to the original stored price
--                            when TSM is disabled or has no data).
--   removedKeys  optional set of itemKey -> true for tasks to drop.
--                Snapshots store one entry per task, so removal is by
--                exact itemKey+assignedChar match if provided.
--   newName      optional name for the new list snapshot.
--
-- Returns a NEW preview snapshot ready to feed into CommitList.
function TodoList:RegenerateList(sourceList, refreshMode, removedKeys, newName)
    if not sourceList or not sourceList.tasks then
        return { name = newName or "Regenerated", tasks = {}, items = {} }
    end
    refreshMode = refreshMode or "fpsaved"
    removedKeys = removedKeys or {}

    local out = {}
    local tsmEnabled = refreshMode == "tsmlive"
        and ns.TSM and ns.TSM.IsEnabled and ns.TSM:IsEnabled()
        and ns.TSM.GetPrice and true

    for _, task in ipairs(sourceList.tasks) do
        -- Removal key combines itemKey + assignedChar so the same item on
        -- different chars can be dropped independently.
        local removalKey = (task.itemKey or "") .. "|" .. (task.assignedChar or "")
        if not removedKeys[removalKey] then
            local copy = {}
            for k, v in pairs(task) do copy[k] = v end
            copy.status = "pending"
            copy.failReason = nil
            copy.completedAt = nil
            copy.attempts = 0

            -- Reset step states for the chosen action.
            if copy.action == "buy" then
                copy.steps = {
                    browse = "pending", buy = "pending",
                    collect = "pending", deposit = "pending",
                }
            else
                copy.steps = {
                    retrieve = "pending", post = "pending", collect = "pending",
                }
            end

            if refreshMode == "fpsaved" then
                local importSource = task.importSource
                local importKey    = task.importKey
                local bucket = importSource and ns.db
                    and ns.db.imports and ns.db.imports[importSource]
                local deal = bucket and importKey and bucket[importKey]
                if deal and ns.ResolveFPPrice then
                    copy.expectedPrice = ns:ResolveFPPrice(deal)
                end
                -- If no import record survives, keep the stored price.
            elseif tsmEnabled and copy.itemKey then
                local tsmCopper = ns.TSM:GetPrice(copy.itemKey, "DBRegionMarketAvg")
                if not tsmCopper or tsmCopper <= 0 then
                    tsmCopper = ns.TSM:GetPrice(copy.itemKey, "DBMinBuyout")
                end
                if tsmCopper and tsmCopper > 0 and ns.FormatGold then
                    copy.expectedPrice = ns:FormatGold(tsmCopper)
                    copy.priceSource   = "TSM live"
                    copy.priceUpdatedAt = time()
                end
            end

            out[#out + 1] = copy
        end
    end

    return {
        name       = newName or ("Regenerated " .. date("%Y-%m-%d %H:%M")),
        tasks      = out,
        items      = out, -- match CommitList's preview-shape expectation
        importType = sourceList.importType,
    }
end

-- Get pending tasks for a specific character from the active list.
-- Returns array of { taskIndex, item }.
function TodoList:GetCharacterTasks(charKey)
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return {}
    end

    local tasks = {}
    for i, item in ipairs(ns.db.todoLists.active.tasks) do
        if item.status == "pending" and item.assignedChar == charKey then
            table.insert(tasks, {
                taskIndex = i,
                item      = item,
            })
        end
    end
    return tasks
end

-- Get summary of tasks grouped by character.
-- Returns array of { charKey, taskCount, totalValue }, sorted by taskCount desc.
function TodoList:GetCharacterSummary()
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return {}
    end

    local byChar = {}
    for _, item in ipairs(ns.db.todoLists.active.tasks) do
        if item.status == "pending" and item.assignedChar then
            if not byChar[item.assignedChar] then
                byChar[item.assignedChar] = {
                    charKey    = item.assignedChar,
                    taskCount  = 0,
                    totalValue = 0,
                }
            end
            byChar[item.assignedChar].taskCount = byChar[item.assignedChar].taskCount + 1
            byChar[item.assignedChar].totalValue = byChar[item.assignedChar].totalValue
                + ns:ParseGoldValue(item.expectedPrice or "")
        end
    end

    local summary = {}
    for _, data in pairs(byChar) do
        table.insert(summary, data)
    end
    table.sort(summary, function(a, b) return a.taskCount > b.taskCount end)

    return summary
end

-- Get total pending task count
function TodoList:GetPendingCount()
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return 0
    end

    local count = 0
    for _, item in ipairs(ns.db.todoLists.active.tasks) do
        if item.status == "pending" then
            count = count + 1
        end
    end
    return count
end

-- Get unique item names from pending buy tasks in the active list.
-- Returns array of item name strings.
function TodoList:GetBuyTaskNames()
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return {}
    end

    local names = {}
    local seen = {}
    for _, item in ipairs(ns.db.todoLists.active.tasks) do
        if item.status == "pending" and item.action == "buy" then
            local name = item.name
            if name and name ~= "" then
                local lower = name:lower()
                if not seen[lower] then
                    seen[lower] = true
                    table.insert(names, name)
                end
            end
        end
    end
    return names
end

-- Get pending buy tasks grouped by buyRealm.
-- Returns { [realm] = { {name, buyPrice, quality, quantity}, ... } }
function TodoList:GetBuyTasksByRealm()
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return {}
    end

    local byRealm = {}
    for _, item in ipairs(ns.db.todoLists.active.tasks) do
        if item.status == "pending" and item.action == "buy" then
            local realm = item.buyRealm or "Unknown"
            if not byRealm[realm] then byRealm[realm] = {} end
            table.insert(byRealm[realm], {
                name     = item.name or "",
                buyPrice = item.buyPrice or "",
                quality  = item.quality,
                quantity = item.quantity or 1,
            })
        end
    end
    return byRealm
end

-- Get counts by status
function TodoList:GetStatusCounts()
    local counts = {
        pending = 0, posted = 0, skipped = 0,
        missing = 0, unassigned = 0,
    }
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return counts
    end

    for _, item in ipairs(ns.db.todoLists.active.tasks) do
        local s = item.status or "pending"
        counts[s] = (counts[s] or 0) + 1
    end
    return counts
end

--------------------------
-- Location Refresh
--------------------------

-- Update the source field of pending todo items based on live bag contents.
-- Called after BAG_UPDATE_DELAYED so locations stay in sync with inventory.
-- Returns true if any sources changed.
function TodoList:RefreshLocations()
    local current = self:GetCurrentList()
    if not current or not current.tasks then return false end

    local charKey = ns:GetCharKey()

    -- Live scan current character's bags for item keys, IDs, pet species, and names
    local bagsItemKeys = {} -- itemKey -> qty
    local bagsItemIDs = {}  -- numericID -> qty
    local bagsPetSpecies = {} -- speciesID string -> qty
    local bagsItemNames = {} -- lowercase name -> qty
    pcall(function()
        for _, bagIdx in ipairs(ns.INVENTORY_BAGS) do
            local numSlots = C_Container.GetContainerNumSlots(bagIdx)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bagIdx, slot)
                if info and info.hyperlink then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                        bagsItemKeys[key] = (bagsItemKeys[key] or 0) + (info.stackCount or 1)
                        local numID = tonumber(itemID)
                        if numID then
                            bagsItemIDs[numID] = (bagsItemIDs[numID] or 0) + (info.stackCount or 1)
                        end
                        local petSpec = itemID:match("^pet:(%d+)") or itemID:match("^pet_(%d+)")
                        if petSpec then
                            bagsPetSpecies[petSpec] = (bagsPetSpecies[petSpec] or 0) + 1
                        end
                    end
                    local itemName = info.hyperlink:match("|h%[(.-)%]|h")
                    if itemName and itemName ~= "" then
                        bagsItemNames[itemName:lower()] = (bagsItemNames[itemName:lower()] or 0) + (info.stackCount or 1)
                    end
                end
            end
        end
    end)

    -- Build warbank lookup (for deposit task resolution)
    -- Multiple indexes: exact key, numeric ID, pet species, lowercase name
    local warbankItemKeys = {}
    local warbankItemIDs = {}
    local warbankPetSpecies = {}
    local warbankItemNames = {}
    if ns.db and ns.db.warbank and ns.db.warbank.items then
        for key, wbItem in pairs(ns.db.warbank.items) do
            if wbItem.quantity and wbItem.quantity > 0 then
                warbankItemKeys[key] = wbItem.quantity
                local numID = tonumber(key:match("^(%d+)"))
                if numID then
                    warbankItemIDs[numID] = (warbankItemIDs[numID] or 0) + wbItem.quantity
                end
                -- Pet species: "pet:267;..." or "pet_267;..."
                local petSpec = key:match("^pet:(%d+)") or key:match("^pet_(%d+)")
                if petSpec then
                    warbankPetSpecies[petSpec] = (warbankPetSpecies[petSpec] or 0) + wbItem.quantity
                end
                -- Name index
                if wbItem.name and wbItem.name ~= "" then
                    local lname = wbItem.name:lower()
                    warbankItemNames[lname] = (warbankItemNames[lname] or 0) + wbItem.quantity
                end
            end
        end
    end

    -- Helper: check if a task item is in a lookup set (bags or warbank)
    local function IsItemInLookup(item, keyMap, idMap, petMap, nameMap)
        local itemKey = item.itemKey or ""
        local itemNumID = tonumber(item.itemID) or tonumber(itemKey:match("^(%d+)"))
        -- Exact key
        if keyMap[itemKey] and keyMap[itemKey] > 0 then return true end
        -- Numeric ID
        if itemNumID and idMap[itemNumID] and idMap[itemNumID] > 0 then return true end
        -- Pet species
        if petMap then
            local petSpec = itemKey:match("^pet:(%d+)") or itemKey:match("^pet_(%d+)")
                or (item.itemID and (tostring(item.itemID):match("^pet:(%d+)") or tostring(item.itemID):match("^pet_(%d+)")))
            if petSpec and petMap[petSpec] and petMap[petSpec] > 0 then return true end
        end
        -- Name fallback
        if nameMap and item.name and item.name ~= "" then
            local lname = item.name:lower()
            if nameMap[lname] and nameMap[lname] > 0 then return true end
        end
        return false
    end

    local changed = false
    for _, item in ipairs(current.tasks) do
        if item.status == "pending" and item.assignedChar == charKey then
            local inBags = IsItemInLookup(item, bagsItemKeys, bagsItemIDs, bagsPetSpecies, bagsItemNames)

            if inBags and item.source ~= "bags" then
                item.source = "bags"
                changed = true
            elseif not inBags and item.source == "bags" then
                -- Item left bags (posted, deposited, etc.) — mark unavailable
                item.source = "unavailable"
                changed = true
            elseif not inBags and item.source == "warbank" then
                -- Verify item is still in warbank (data may be stale)
                local stillInWarbank = IsItemInLookup(item, warbankItemKeys, warbankItemIDs, warbankPetSpecies, warbankItemNames)
                if not stillInWarbank then
                    item.source = "unavailable"
                    changed = true
                end
            end
        end

        -- Update deposit tasks: clear depositFrom when item reaches warbank.
        -- The warbank is visible from ANY character, so check all deposit tasks,
        -- not just those assigned to the current character.
        if item.status == "pending" and item.depositFrom
                and item.depositFrom ~= "" then
            local inWarbank = IsItemInLookup(item, warbankItemKeys, warbankItemIDs, warbankPetSpecies, warbankItemNames)
            if inWarbank then
                item.source = "warbank"
                item.depositFrom = nil
                item.deferredAt = nil
                item.blocker = nil
                item.failReason = nil
                changed = true
            elseif item.depositFrom == charKey then
                -- Current char is the depositor — check if still in bags
                local inBags = IsItemInLookup(item, bagsItemKeys, bagsItemIDs, bagsPetSpecies, bagsItemNames)
                if not inBags and item.source == "unavailable" then
                    -- Item isn't in bags or warbank — depositor may have sold/deleted it.
                    -- Clear stale deposit so the item can be re-sourced.
                    item.depositFrom = nil
                    item.deferredAt = nil
                    item.blocker = nil
                    changed = true
                end
            end
        end

    end

    -- Orphan detection: sell tasks from cross-realm flips whose buy task was deleted.
    -- If a sell task has depositFrom set but no corresponding buy task exists for that
    -- item + depositor, the deposit is orphaned and should be cleared.
    local buyTaskKeys = {}  -- "itemKey|depositor" -> true
    for _, item in ipairs(current.tasks) do
        if item.action == "buy" and item.status == "pending" and item.assignedChar then
            local bk = (item.itemKey or item.name or "") .. "|" .. item.assignedChar
            buyTaskKeys[bk] = true
        end
    end
    for _, item in ipairs(current.tasks) do
        if item.depositFrom and item.depositFrom ~= ""
                and item.source == "unavailable" and item.action == "sell"
                and item.dealType == "flip" then
            local bk = (item.itemKey or item.name or "") .. "|" .. item.depositFrom
            if not buyTaskKeys[bk] then
                -- No matching buy task — this deposit is orphaned
                item.depositFrom = nil
                item.deferredAt = nil
                item.blocker = nil
                item.failReason = nil
                changed = true
            end
        end
    end

    -- Reconcile deposit tasks: preserve existing assignments when surplus still
    -- supports them, only clear when items are no longer available.
    -- This ensures deposit state survives logout/login cycles.

    -- Step 2: Count how many of each item the current char needs for their own tasks
    local ownNeeded = {} -- lowercase name -> qty needed by current char
    for _, item in ipairs(current.tasks) do
        if item.status == "pending" and item.assignedChar == charKey then
            local lname = (item.name or ""):lower()
            if lname ~= "" then
                ownNeeded[lname] = (ownNeeded[lname] or 0) + (item.quantity or 1)
            end
        end
    end

    -- Step 3: Build available surplus from bags minus own needs
    local surplusByName = {}
    for lname, qty in pairs(bagsItemNames) do
        local needed = ownNeeded[lname] or 0
        local surplus = qty - needed
        if surplus > 0 then
            surplusByName[lname] = surplus
        end
    end

    -- Step 1 (reordered): Validate existing depositFrom == charKey assignments.
    -- Keep if surplus still supports them; clear only when items are gone.
    for _, item in ipairs(current.tasks) do
        if item.status == "pending" and item.depositFrom == charKey
                and item.assignedChar ~= charKey then
            local lname = (item.name or ""):lower()
            local qty = item.quantity or 1
            if lname ~= "" and surplusByName[lname] and surplusByName[lname] >= qty then
                -- Still have surplus — keep existing deposit assignment
                surplusByName[lname] = surplusByName[lname] - qty
            else
                -- No longer have surplus of this item — clear assignment
                item.depositFrom = nil
                item.source = "unavailable"
                changed = true
            end
        end
    end

    -- Step 4: Assign NEW deposit tasks from remaining surplus
    for _, item in ipairs(current.tasks) do
        if item.status == "pending" and item.assignedChar ~= charKey
                and item.assignedChar and not item.depositFrom then
            local lname = (item.name or ""):lower()
            if lname ~= "" and surplusByName[lname] and surplusByName[lname] > 0 then
                local qty = item.quantity or 1
                if surplusByName[lname] >= qty then
                    item.depositFrom = charKey
                    item.source = "unavailable"
                    item.deferredAt = nil
                    surplusByName[lname] = surplusByName[lname] - qty
                    changed = true
                end
            end
        end
    end

    -- Step 5: Cross-character deposit resolution (quantity-aware)
    -- For tasks without a depositFrom, search ALL characters' stored inventories.
    -- Track consumed quantities so a character with 2 items doesn't get assigned 3 deposits.

    -- Build available quantity map: charKey -> lowercase name -> available qty
    -- Also count how many have already been assigned as depositFrom in earlier steps
    -- Include ALL characters (even current) — current char's bank items can be
    -- pulled and deposited to warbank for other characters.
    -- Step 4 already handled current char's BAG surplus; Step 5 handles bank items.
    local charAvailable = {} -- charKey -> { lname -> qty }
    for ck, charData in pairs(ns.db.characters or {}) do
        if (charData.role or "both") ~= "none"
                and charData.inventory and charData.inventory.items then
            local byName = {}
            for k, invItem in pairs(charData.inventory.items) do
                if invItem.name and invItem.name ~= "" then
                    local totalQty = 0
                    if invItem.locations then
                        -- For current character, only count bank items (bags handled by Step 4)
                        if ck == charKey then
                            totalQty = (invItem.locations.bank or 0) + (invItem.locations.reagent or 0)
                        else
                            for _, qty in pairs(invItem.locations) do totalQty = totalQty + qty end
                        end
                    elseif ck ~= charKey and (invItem.quantity or 0) > 0 then
                        totalQty = invItem.quantity
                    end
                    if totalQty > 0 then
                        local ln = invItem.name:lower()
                        byName[ln] = (byName[ln] or 0) + totalQty
                    end
                end
            end
            if next(byName) then
                charAvailable[ck] = byName
            end
        end
    end

    -- Deduct items already assigned as depositFrom to this character (from Step 4 or prior state)
    for _, item in ipairs(current.tasks) do
        if item.status == "pending" and item.depositFrom
                and charAvailable[item.depositFrom] then
            local ln = (item.name or ""):lower()
            if ln ~= "" and charAvailable[item.depositFrom][ln] then
                charAvailable[item.depositFrom][ln] =
                    charAvailable[item.depositFrom][ln] - (item.quantity or 1)
            end
        end
    end

    -- Assign deposit tasks from remaining available quantities
    for _, item in ipairs(current.tasks) do
        if item.status == "pending" and item.assignedChar
                and not item.depositFrom and item.source == "unavailable" then
            local lname = (item.name or ""):lower()
            if lname ~= "" then
                local qty = item.quantity or 1
                for ck, byName in pairs(charAvailable) do
                    if ck ~= item.assignedChar and (byName[lname] or 0) >= qty then
                        item.depositFrom = ck
                        item.blockedBy = ck
                        item.failReason = "Item not in accessible inventory — may need depositing to warbank"
                        byName[lname] = byName[lname] - qty
                        changed = true
                        break
                    end
                end
            end
        end
    end

    return changed
end

--------------------------
-- Task Status Updates
--------------------------

-- Update a task's status
function TodoList:UpdateTaskStatus(taskIndex, status, reason)
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return
    end

    local tasks = ns.db.todoLists.active.tasks
    local item = tasks and tasks[taskIndex]
    if item then
        item.status = status
        if reason then item.failReason = reason end
    end

    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
        local task = tasks and tasks[taskIndex]
        if task and task.taskUUID then
            ns.Sync:EmitDelta("TDSTATUS", { taskUUID = task.taskUUID, status = task.status, failReason = task.failReason })
        end
    end
end

-- Move a completed task to the log
-- realItemKey: optional caller-provided "itemID;bonusIDs;modifiers" for the
-- actual posted bag item. Tasks built from FP/TSM imports often carry the
-- stripped base form (`itemID;;`), but the bag item that was just posted
-- may have bonus IDs / modifiers attached. When the caller knows the
-- real bag-item key, pass it here so the log entry preserves variant
-- data — base form as fallback for legacy callers (FQ-130).
function TodoList:MoveTaskToLog(taskIndex, postedPrice, expirySeconds, postedQuantity, realItemKey)
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return
    end

    local item = ns.db.todoLists.active.tasks[taskIndex]
    if not item then return end

    local taskUUID = item.taskUUID

    local taskQty = item.quantity or 1
    local moveQty = postedQuantity or taskQty

    -- Prefer the caller-supplied real bag-item key when it carries variant
    -- data the task's key lacks. We accept any non-empty key with a non-empty
    -- bonus-ID segment ("itemID;BONUS;..."); fall back to the task key.
    local logItemKey = item.itemKey
    if realItemKey and realItemKey ~= "" then
        local realHasBonus = realItemKey:match("^[^;]*;([^;]+)")
        local taskHasBonus = item.itemKey and item.itemKey:match("^[^;]*;([^;]+)")
        if realHasBonus and not taskHasBonus then
            logItemKey = realItemKey
        end
    end

    -- Look for the most recent prior failed-sale history for this item on this character
    -- so we can carry over postAttempts/totalFeesSpent/postHistory (#71)
    local charKey = item.assignedChar or ns:GetCharKey()
    local priorAttempts = 0
    local priorFees = 0
    local priorHistory = nil
    local itemName = (item.name or ""):lower()
    if itemName ~= "" then
        local latestTime = 0
        for _, entry in ipairs(ns.db.log) do
            if entry.charKey == charKey
                and entry.saleOutcome == "expired"
                and (entry.name or ""):lower() == itemName
                and (entry.postedAt or 0) > latestTime then
                latestTime = entry.postedAt or 0
                priorAttempts = entry.postAttempts or 0
                priorFees = entry.totalFeesSpent or 0
                priorHistory = entry.postHistory
            end
        end
    end

    -- Estimate AH fee: ~5% deposit (Blizzard standard for 48h auctions)
    -- ParseGoldValue returns gold, multiply by 10000 for copper, then 5%
    local ahFeeEstimate = 0
    local priceGold = ns:ParseGoldValue(postedPrice or item.expectedPrice or "")
    if priceGold and priceGold > 0 then
        ahFeeEstimate = math.floor(priceGold * 10000 * 0.05) -- 5% deposit in copper
    end

    -- Capture TSM price data at time of posting
    local tsmPriceAtPost = nil
    local tsmRegionAvgAtPost = nil
    if ns.TSM and ns.TSM:IsEnabled() and item.itemKey then
        local dbMinBuyout = ns.TSM:GetPrice(item.itemKey, "DBMinBuyout")
        local dbRegionSaleAvg = ns.TSM:GetPrice(item.itemKey, "DBRegionSaleAvg")
        if dbMinBuyout then tsmPriceAtPost = dbMinBuyout end
        if dbRegionSaleAvg then tsmRegionAvgAtPost = dbRegionSaleAvg end
    end

    table.insert(ns.db.log, {
        itemKey        = logItemKey,
        itemID         = item.itemID,
        name           = item.name,
        quality        = item.quality,
        icon           = item.icon,
        targetRealm    = item.targetRealm,
        expectedPrice  = item.expectedPrice,
        postedPrice    = postedPrice or item.expectedPrice,
        postedAt       = time(),
        charKey        = charKey,
        expiresAt      = expirySeconds and (time() + expirySeconds) or nil,
        auctionStatus  = "active",
        soldAt         = nil,
        soldPrice      = nil,
        postedQuantity = moveQty,
        ahFee          = ahFeeEstimate,
        tsmPriceAtPost = tsmPriceAtPost,
        tsmRegionAvgAtPost = tsmRegionAvgAtPost,
        -- Carry over failed sale tracking from prior listings (#71)
        postAttempts   = priorAttempts,
        totalFeesSpent = priorFees,
        postHistory    = priorHistory,
    })

    -- Partial post: reduce quantity; full post: mark completed
    if moveQty < taskQty then
        item.quantity = taskQty - moveQty
    else
        item.status = "posted"
        -- Advance step past "post" so steps stay in sync with status
        if item.steps and item.currentStep then
            for i = item.currentStep, #item.steps do
                if item.steps[i].type == "post" then
                    item.steps[i].status = "completed"
                    item.currentStep = i + 1
                    break
                end
            end
        end
        -- Remove from imports source
        if item.importSource and item.importKey then
            ns:ImportRemove(item.importSource, item.importKey)
        end
    end

    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
        if taskUUID then
            local logEntry = ns.db.log[#ns.db.log]
            ns.Sync:EmitDelta("TDLOG", { taskUUID = taskUUID, logEntry = logEntry })
        end
    end

    self:CheckAutoComplete()
end

-- Advance a task's current step to the next one.
-- If all steps are completed, mark the task as completed.
-- Returns true if the task advanced (or completed).
function TodoList:AdvanceStep(taskIndex)
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return false
    end

    local task = ns.db.todoLists.active.tasks[taskIndex]
    if not task or not task.steps or #task.steps == 0 then return false end

    local step = task.steps[task.currentStep]
    if not step then return false end

    step.status = "completed"
    task.currentStep = task.currentStep + 1

    -- If past last step, task is done
    if task.currentStep > #task.steps then
        task.status = "completed"
        -- Remove from imports source
        if task.importSource and task.importKey then
            ns:ImportRemove(task.importSource, task.importKey)
        end
        -- When a buy task completes, unblock the correlated sell task
        if task.action == "buy" then
            local buyChar = task.assignedChar
            local buyKey = task.itemKey or ""
            local buyName = task.name and task.name:lower() or ""
            for _, other in ipairs(ns.db.todoLists.active.tasks) do
                if other.status == "pending" and other.action == "sell"
                        and other.blockedBy == buyChar
                        and ((buyKey ~= "" and other.itemKey == buyKey)
                          or (buyName ~= "" and other.name and other.name:lower() == buyName)) then
                    other.blockedBy = nil
                    other.depositFrom = nil
                    other.deferredAt = nil
                    ns:PrintDebug("[buy-complete] unblocked sell task: " .. (other.name or "?"))
                end
            end
        end
    end

    return true
end

-- Get the current step type for a task (e.g., "retrieve", "post", "collect")
function TodoList:GetCurrentStepType(task)
    if not task or not task.steps or not task.currentStep then return nil end
    local step = task.steps[task.currentStep]
    return step and step.type or nil
end

-- Check if an item exists ANYWHERE across the account (all characters + warbank).
-- Used to auto-skip tasks for items that are completely gone.
-- Extract pet species ID from any key format: "pet:267;q0;", "pet_267;;", "pet_267"
local function ExtractPetSpecies(key)
    if not key then return nil end
    return key:match("^pet:(%d+)") or key:match("^pet_(%d+)")
end

-- Check if an inventory entry has quantity > 0
local function InvHasQuantity(inv)
    if not inv then return false end
    if inv.locations then
        for _, qty in pairs(inv.locations) do
            if qty > 0 then return true end
        end
    elseif (inv.quantity or 0) > 0 then
        return true
    end
    return false
end

local function IsItemInAccountInventory(itemKey, itemNumID)
    local petSpecies = ExtractPetSpecies(itemKey)

    for _, charData in pairs(ns.db.characters or {}) do
        if charData.inventory and charData.inventory.items then
            if InvHasQuantity(charData.inventory.items[itemKey]) then return true end
            for k, invItem in pairs(charData.inventory.items) do
                if k ~= itemKey then
                    local kNumID = tonumber((k:gsub(";.*", "")))
                    if itemNumID and kNumID == itemNumID then
                        if InvHasQuantity(invItem) then return true end
                    end
                    -- Pet species match across formats
                    if petSpecies and ExtractPetSpecies(k) == petSpecies then
                        if InvHasQuantity(invItem) then return true end
                    end
                end
            end
        end
    end

    if ns.db.warbank and ns.db.warbank.items then
        if InvHasQuantity(ns.db.warbank.items[itemKey]) then return true end
        for k, wb in pairs(ns.db.warbank.items) do
            if k ~= itemKey then
                local kNumID = tonumber((k:gsub(";.*", "")))
                if itemNumID and kNumID == itemNumID and (wb.quantity or 0) > 0 then return true end
                if petSpecies and ExtractPetSpecies(k) == petSpecies and (wb.quantity or 0) > 0 then return true end
            end
        end
    end

    return false
end

-- Find which character(s) hold a given item across the account.
-- Returns charKey of the holder, or nil if not found on any character.
-- Excludes the assignedChar (they don't hold the item, that's why we're looking).
-- Excludes ignored characters.
-- consumed: optional table { "charKey:lname" -> qty } to track allocated quantities.
-- itemName: item name for quantity tracking (required if consumed is provided).
-- taskQty: quantity needed (default 1).
local function FindItemHolder(itemKey, itemNumID, excludeChar, consumed, itemName, taskQty)
    local petSpecies = ExtractPetSpecies(itemKey)
    taskQty = taskQty or 1

    -- Helper: check if a character has enough unconsumed quantity of an item
    local function HasAvailable(charKey, inv)
        if not inv then return false end
        local totalQty = 0
        if inv.locations then
            for _, qty in pairs(inv.locations) do totalQty = totalQty + qty end
        elseif (inv.quantity or 0) > 0 then
            totalQty = inv.quantity
        end
        if totalQty <= 0 then return false end
        -- Check consumed quantities
        if consumed and itemName then
            local ckey = charKey .. ":" .. itemName:lower()
            local used = consumed[ckey] or 0
            if totalQty - used < taskQty then return false end
        end
        return true
    end

    -- Helper: mark quantity as consumed
    local function Consume(charKey)
        if consumed and itemName then
            local ckey = charKey .. ":" .. itemName:lower()
            consumed[ckey] = (consumed[ckey] or 0) + taskQty
        end
    end

    for charKey, charData in pairs(ns.db.characters or {}) do
        if charKey ~= excludeChar and (charData.role or "both") ~= "none"
            and charData.inventory and charData.inventory.items then
            -- Exact key
            if HasAvailable(charKey, charData.inventory.items[itemKey]) then
                Consume(charKey)
                return charKey
            end
            -- Fallback matching
            for k, invItem in pairs(charData.inventory.items) do
                if k ~= itemKey then
                    local kNumID = tonumber((k:gsub(";.*", "")))
                    if itemNumID and kNumID == itemNumID then
                        if HasAvailable(charKey, invItem) then
                            Consume(charKey)
                            return charKey
                        end
                    end
                    if petSpecies and ExtractPetSpecies(k) == petSpecies then
                        if HasAvailable(charKey, invItem) then
                            Consume(charKey)
                            return charKey
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- Find actual storage location of a task's item accessible to the current character.
-- Returns "bags", "bank", "reagent", "warbank", or "guildbank" if found; nil otherwise.
local function FindItemSource(itemKey, itemNumID, charKey, inBags)
    if inBags then return "bags" end

    local petSpecies = ExtractPetSpecies(itemKey)

    local function CheckInv(inv)
        if not inv then return nil end
        if inv.locations then
            if (inv.locations.bags or 0) > 0 then return "bags" end
            if (inv.locations.bank or 0) > 0 then return "bank" end
            if (inv.locations.reagent or 0) > 0 then return "reagent" end
        elseif (inv.quantity or 0) > 0 then
            return "bags"
        end
        return nil
    end

    -- Character's stored inventory (bags, bank, reagent from last scan)
    local charData = ns.db.characters and ns.db.characters[charKey]
    if charData and charData.inventory and charData.inventory.items then
        local found = CheckInv(charData.inventory.items[itemKey])
        if found then return found end

        for k, inv in pairs(charData.inventory.items) do
            if k ~= itemKey then
                -- Numeric ID fallback (different bonus/modifier variants)
                local kNumID = tonumber((k:gsub(";.*", "")))
                if itemNumID and kNumID == itemNumID then
                    found = CheckInv(inv)
                    if found then return found end
                end
                -- Pet species match across formats
                if petSpecies and ExtractPetSpecies(k) == petSpecies then
                    found = CheckInv(inv)
                    if found then return found end
                end
            end
        end
    end

    -- Warbank
    if ns.db.warbank and ns.db.warbank.items then
        local wbItem = ns.db.warbank.items[itemKey]
        if wbItem and (wbItem.quantity or 0) > 0 then return "warbank" end
        for k, wb in pairs(ns.db.warbank.items) do
            if k ~= itemKey then
                local kNumID = tonumber((k:gsub(";.*", "")))
                if itemNumID and kNumID == itemNumID and (wb.quantity or 0) > 0 then return "warbank" end
                if petSpecies and ExtractPetSpecies(k) == petSpecies and (wb.quantity or 0) > 0 then return "warbank" end
            end
        end
    end

    -- Guild banks — disabled: Blizzard API returns unreliable item data
    -- Re-enable when API is fixed.

    return nil
end

-- Refresh all pending tasks: update steps based on current game state.
-- Called on login, bag changes, bank open, AH open, mail, TSM data.
-- This checks whether steps have been satisfied by game events,
-- and defers tasks whose items can't be found anywhere accessible.
function TodoList:RefreshTaskSteps()
    local current = self:GetCurrentList()
    if not current or not current.tasks then return false end

    local charKey = ns:GetCharKey()
    local changed = false

    -- Shared consumed-quantity map for FindItemHolder across both loops
    -- Tracks "charKey:lname" -> qty to prevent over-allocating deposits
    local holderConsumed = {}

    -- Pre-populate holderConsumed with items the current character needs for its
    -- own pending tasks. Without this, FindItemHolder sees the current character's
    -- inventory as available for deposit, even though those items are needed here.
    for _, task in ipairs(current.tasks) do
        if task.status == "pending" and task.assignedChar == charKey
            and task.action ~= "buy" and task.name and task.name ~= "" then
            local ckey = charKey .. ":" .. task.name:lower()
            holderConsumed[ckey] = (holderConsumed[ckey] or 0) + (task.quantity or 1)
        end
    end

    -- One-time cleanup: strip "..." from targetRealm fields (FP website truncation)
    if not current._realmsCleaned then
        for _, task in ipairs(current.tasks) do
            if task.targetRealm and task.targetRealm:find("%.%.%.") then
                task.targetRealm = task.targetRealm:gsub(",?%s*%.%.%.%s*$", "")
                task.targetRealm = strtrim(task.targetRealm)
                changed = true
            end
        end
        current._realmsCleaned = true
    end

    -- Build quick bag lookup for current character (includes reagent bag)
    local bagsItemKeys = {}
    local bagsItemIDs = {}
    local bagsPetSpecies = {}
    local bagsItemNames = {}       -- exact lowercase name -> count
    local bagsNormNames = {}       -- normalized (alphanumeric only) -> count
    local bagsNameToID = {}        -- lowercase name -> numeric itemID (for backfill)
    pcall(function()
        for _, bagIdx in ipairs(ns.ALL_PLAYER_BAGS or ns.INVENTORY_BAGS) do
            local numSlots = C_Container.GetContainerNumSlots(bagIdx)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bagIdx, slot)
                if info and info.hyperlink then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                        bagsItemKeys[key] = (bagsItemKeys[key] or 0) + (info.stackCount or 1)
                        local numID = tonumber(itemID)
                        if numID then
                            bagsItemIDs[numID] = (bagsItemIDs[numID] or 0) + (info.stackCount or 1)
                        end
                        local speciesID = itemID:match("^pet:(%d+)") or itemID:match("^pet_(%d+)")
                        if speciesID then
                            bagsPetSpecies[speciesID] = (bagsPetSpecies[speciesID] or 0) + 1
                        end
                        local itemName = info.hyperlink:match("|h%[(.-)%]|h")
                        if itemName and itemName ~= "" then
                            local lname = itemName:lower()
                            bagsItemNames[lname] = (bagsItemNames[lname] or 0) + (info.stackCount or 1)
                            local norm = lname:gsub("[^%w]", "")
                            if norm ~= "" then
                                bagsNormNames[norm] = (bagsNormNames[norm] or 0) + (info.stackCount or 1)
                            end
                            if numID then bagsNameToID[lname] = numID end
                        end
                    end
                end
            end
        end
    end)

    for taskIdx, task in ipairs(current.tasks) do
        if task.status == "pending" and task.assignedChar == charKey
            and task.steps and task.currentStep then

            local stepType = self:GetCurrentStepType(task)
            local itemKey = task.itemKey or ""
            local itemNumID = tonumber(task.itemID) or tonumber(itemKey:match("^(%d+)"))
            local taskPetSpecies = ExtractPetSpecies(itemKey)
                or (task.itemID and ExtractPetSpecies(task.itemID))
            local taskNameLower = task.name and task.name:lower() or nil
            local taskNormName = taskNameLower and taskNameLower:gsub("[^%w]", "") or nil
            local inBags = (bagsItemKeys[itemKey] and bagsItemKeys[itemKey] > 0)
                or (itemNumID and bagsItemIDs[itemNumID] and bagsItemIDs[itemNumID] > 0)
                or (taskPetSpecies and bagsPetSpecies[taskPetSpecies] and bagsPetSpecies[taskPetSpecies] > 0)
                or (taskNameLower and bagsItemNames[taskNameLower] and bagsItemNames[taskNameLower] > 0)
                or (taskNormName and bagsNormNames[taskNormName] and bagsNormNames[taskNormName] > 0)

            -- Backfill itemID from bag scan when matched by name (so future
            -- checks can use the faster numeric-ID path).
            if inBags and (not task.itemID or task.itemID == "") and taskNameLower then
                local resolvedID = bagsNameToID[taskNameLower]
                if resolvedID then
                    task.itemID = tostring(resolvedID)
                end
            end

            local isBuyTask = task.action == "buy"

            local justAdvanced = false
            if isBuyTask then
                if not inBags and (stepType == "browse" or stepType == "buy" or stepType == "collect") then
                    ns:PrintDebug("[buy-step] " .. (task.name or "?") .. " step=" .. tostring(stepType) ..
                        " inBags=false key=" .. tostring(task.itemKey) ..
                        " id=" .. tostring(task.itemID) ..
                        " name=" .. tostring(taskNameLower) ..
                        " norm=" .. tostring(taskNormName))
                end
                -- Buy task steps: browse → buy → collect → deposit
                if stepType == "browse" then
                    -- Item appeared in bags (bought + collected from mail without hook)
                    -- Advance past browse, buy, and collect in one go
                    if inBags then
                        self:AdvanceStep(taskIdx) -- browse → buy
                        self:AdvanceStep(taskIdx) -- buy → collect
                        self:AdvanceStep(taskIdx) -- collect → deposit
                        changed = true
                        task.source = "bags"
                        justAdvanced = true
                    end
                elseif stepType == "buy" then
                    -- Purchase hook already advanced browse→buy.
                    -- Item now in bags (collected from mail) → advance past buy and collect
                    if inBags then
                        self:AdvanceStep(taskIdx) -- buy → collect
                        self:AdvanceStep(taskIdx) -- collect → deposit
                        changed = true
                        task.source = "bags"
                        justAdvanced = true
                    end
                elseif stepType == "collect" then
                    -- Waiting for mail collection. Item in bags = collected.
                    if inBags then
                        self:AdvanceStep(taskIdx) -- collect → deposit
                        changed = true
                        task.source = "bags"
                        justAdvanced = true
                    end
                elseif stepType == "deposit" then
                    -- If item left bags for any reason (deposited, posted, vendored),
                    -- treat deposit step as complete.
                    if not inBags then
                        self:AdvanceStep(taskIdx)
                        changed = true
                        justAdvanced = true
                    end
                end
            else
                -- Standard sell task steps
                if stepType == "retrieve" then
                    -- Check if item has appeared in bags (pulled from bank/warbank)
                    if inBags then
                        self:AdvanceStep(taskIdx)
                        changed = true
                        task.source = "bags"
                        justAdvanced = true
                    end
                elseif stepType == "collect" then
                    -- Item returned from expired auction (collected from mail) — cycle back to post
                    if inBags then
                        -- Reset steps: skip retrieve (item already in bags), go to post
                        task.steps = {
                            { type = "retrieve", from = "bags", status = "done" },
                            { type = "post", status = "pending" },
                            { type = "collect", status = "pending" },
                        }
                        task.currentStep = 2
                        task.source = "bags"
                        task.deferredAt = nil
                        changed = true
                        justAdvanced = true
                    end
                end
                -- "post" step is advanced by Tracker (bag decrease / auction detection)
            end

            -- Check item availability for deferral (skip tasks just advanced)
            -- Buy tasks don't need item availability — they need to buy the item
            if (task.status == "pending" or task.status == "skipped") and not justAdvanced and not isBuyTask then
                local actualSource = FindItemSource(itemKey, itemNumID, charKey, inBags)

                if not actualSource then
                    -- Item not found for this character — check account-wide
                    if not IsItemInAccountInventory(itemKey, itemNumID) then
                        -- Item not in saved DB — defer, don't skip
                        -- (saved inventory may be stale; bank/warbank not scanned yet)
                        if not task.deferredAt then
                            task.deferredAt = time()
                            changed = true
                        end
                    else
                        -- Item exists on account but not on this character —
                        -- find who has it and set blockedBy/depositFrom
                        local holder = FindItemHolder(itemKey, itemNumID, charKey,
                            holderConsumed, task.name, task.quantity)
                        if holder and task.blockedBy ~= holder then
                            task.blockedBy = holder
                            task.depositFrom = holder
                            task.source = "unavailable"
                            task.failReason = "Item not in accessible inventory — may need depositing to warbank"
                            changed = true
                        end
                        if not task.deferredAt then
                            task.deferredAt = time()
                            changed = true
                        end
                    end
                else
                    -- Item found — clear deferral/skip/blockedBy and update source
                    if task.status == "skipped" then
                        -- Un-skip: item reappeared in inventory — re-evaluate
                        task.status = "pending"
                        task.failReason = nil
                        changed = true
                    end
                    if task.deferredAt then
                        task.deferredAt = nil
                        changed = true
                    end
                    if task.blockedBy then
                        task.blockedBy = nil
                        task.depositFrom = nil
                        changed = true
                    end
                    if task.source == "unavailable" or task.source ~= actualSource then
                        task.source = actualSource
                        changed = true
                    end
                end
            end
        end
    end

    -- Build map of items the current character needs for its own tasks,
    -- so we can identify excess items in bags available for deposit to other chars.
    local myNeededKeys = {}  -- itemKey -> qty needed
    local myNeededIDs = {}   -- numID -> qty needed
    local myNeededNames = {} -- lname -> qty needed
    for _, task in ipairs(current.tasks) do
        if task.status == "pending" and task.assignedChar == charKey and task.action ~= "buy" then
            local ik = task.itemKey or ""
            myNeededKeys[ik] = (myNeededKeys[ik] or 0) + (task.quantity or 1)
            local nid = tonumber(task.itemID) or tonumber(ik:match("^(%d+)"))
            if nid then
                myNeededIDs[nid] = (myNeededIDs[nid] or 0) + (task.quantity or 1)
            end
            if task.name and task.name ~= "" then
                myNeededNames[task.name:lower()] = (myNeededNames[task.name:lower()] or 0) + (task.quantity or 1)
            end
        end
    end

    -- Track excess items consumed by deposit assignments (prevent double-counting)
    local excessConsumed = {} -- "id_or_name" -> qty consumed

    -- Helper: does the current character have excess items in bags for deposit?
    -- Uses numeric ID as primary check (robust to key format differences between
    -- tasks and bag items — e.g., bare import key "12345;;" vs enriched "12345;4795;28:").
    local function CurrentCharHasExcess(itemKey, itemNumID, taskName, taskQty)
        taskQty = taskQty or 1
        -- Primary: numeric item ID (aggregates across all key variants)
        if itemNumID then
            local idKey = tostring(itemNumID)
            local inBagsID = bagsItemIDs[itemNumID] or 0
            local neededID = myNeededIDs[itemNumID] or 0
            local consumedID = excessConsumed[idKey] or 0
            if inBagsID - neededID - consumedID >= taskQty then
                excessConsumed[idKey] = consumedID + taskQty
                return true
            end
            -- If this item ID exists in bags at all, trust the ID-based count
            if inBagsID > 0 then return false end
        end
        -- Fallback: name (for items without a usable numeric ID, e.g., battle pets)
        if taskName and taskName ~= "" then
            local lname = taskName:lower()
            local nameKey = "n:" .. lname
            local inBagsName = bagsItemNames[lname] or 0
            local neededName = myNeededNames[lname] or 0
            local consumedName = excessConsumed[nameKey] or 0
            if inBagsName - neededName - consumedName >= taskQty then
                excessConsumed[nameKey] = consumedName + taskQty
                return true
            end
        end
        return false
    end

    -- Also check availability for OTHER characters' tasks using stored DB data.
    -- Can't advance steps or scan live bags for them, but can set/clear deferral
    -- so their groups sort correctly without needing to log into each character.
    -- Buy tasks are excluded — they don't need existing inventory.
    for taskIdx, task in ipairs(current.tasks) do
        if (task.status == "pending" or task.status == "skipped") and task.assignedChar
            and task.assignedChar ~= charKey
            and task.steps and task.currentStep
            and task.action ~= "buy" then

            local itemKey = task.itemKey or ""
            local itemNumID = tonumber(task.itemID) or tonumber(itemKey:match("^(%d+)"))
            local actualSource = FindItemSource(itemKey, itemNumID, task.assignedChar, false)

            if not actualSource then
                -- Item not found for assigned char — check account-wide
                if not IsItemInAccountInventory(itemKey, itemNumID) then
                    if not task.deferredAt then
                        task.deferredAt = time()
                        changed = true
                    end
                else
                    -- Item exists on account but not on assigned char —
                    -- find who has it and set blockedBy/depositFrom
                    local holder = FindItemHolder(itemKey, itemNumID, task.assignedChar,
                        holderConsumed, task.name, task.quantity)
                    if holder and task.blockedBy ~= holder then
                        task.blockedBy = holder
                        task.depositFrom = holder
                        task.source = "unavailable"
                        task.failReason = "Item not in accessible inventory — may need depositing to warbank"
                        changed = true
                    end
                    if not task.deferredAt then
                        task.deferredAt = time()
                        changed = true
                    end
                end
            elseif actualSource == "warbank" then
                -- Warbank is accessible to all characters — trust this source
                if task.status == "skipped" and task.failReason and not task.failReason:find("TSM") then
                    task.status = "pending"
                    task.failReason = nil
                    changed = true
                end
                if task.deferredAt then
                    task.deferredAt = nil
                    changed = true
                end
                if task.blockedBy then
                    task.blockedBy = nil
                    task.depositFrom = nil
                    changed = true
                end
                if task.source ~= "warbank" then
                    task.source = "warbank"
                    changed = true
                end
            else
                -- Source is from assigned char's stored inventory (bags/bank/reagent).
                -- This data may be stale if the character hasn't logged in recently.
                -- If the current character has excess of this item in bags, prefer
                -- flagging as a deposit — the stale source might be wrong, and showing
                -- a deposit task is safer than hiding it.
                if CurrentCharHasExcess(itemKey, itemNumID, task.name, task.quantity or 1) then
                    if task.depositFrom ~= charKey then
                        task.blockedBy = charKey
                        task.depositFrom = charKey
                        task.source = "unavailable"
                        task.failReason = "Item in current character's bags — deposit to warbank"
                        if not task.deferredAt then task.deferredAt = time() end
                        changed = true
                    end
                else
                    if task.status == "skipped" and task.failReason and not task.failReason:find("TSM") then
                        task.status = "pending"
                        task.failReason = nil
                        changed = true
                    end
                    if task.deferredAt then
                        task.deferredAt = nil
                        changed = true
                    end
                    if task.blockedBy then
                        task.blockedBy = nil
                        task.depositFrom = nil
                        changed = true
                    end
                    if task.source ~= actualSource then
                        task.source = actualSource
                        changed = true
                    end
                end
            end
        end
    end

    -- Cleanup posted tasks: advance stale steps, clear stale deferral/blocker state.
    -- Posted tasks are terminal — they should reflect their final state accurately.
    for _, task in ipairs(current.tasks) do
        if task.status == "posted" and task.steps and task.currentStep then
            -- Advance past the "post" step if it's still pending
            for i = 1, #task.steps do
                if task.steps[i].type == "post" and task.steps[i].status ~= "completed" then
                    task.steps[i].status = "completed"
                    if task.currentStep <= i then
                        task.currentStep = i + 1
                    end
                    changed = true
                end
            end
            -- Also advance "retrieve" if still pending (item was retrieved to post)
            for i = 1, #task.steps do
                if task.steps[i].type == "retrieve" and task.steps[i].status ~= "completed" then
                    task.steps[i].status = "completed"
                    changed = true
                end
            end
            -- Clear stale deferral/blocker on posted tasks
            if task.deferredAt then
                task.deferredAt = nil
                changed = true
            end
            if task.blockedBy then
                task.blockedBy = nil
                task.depositFrom = nil
                changed = true
            end
        end
    end

    -- Auto-complete list if no actionable tasks remain
    self:CheckAutoComplete()

    return changed
end

-- Archive the active list if no actionable tasks remain.
-- "Actionable" = pending or unassigned. Missing/skipped/posted are all terminal.
function TodoList:CheckAutoComplete()
    local current = self:GetCurrentList()
    if not current or not current.tasks or #current.tasks == 0 then return end

    for _, task in ipairs(current.tasks) do
        if task.status == "pending" or task.status == "unassigned" then
            return -- still has work to do
        end
    end

    ns:Print(ns.COLORS.GREEN .. "All tasks completed or skipped — archiving to-do list.|r")
    self:ClearCurrent()

    return changed
end

-- Advance buy tasks matching a purchased item.
-- Called from AH purchase hooks (PlaceBid / ConfirmCommoditiesPurchase).
-- Advances browse → buy (purchase confirmed, item en route to mail).
function TodoList:OnItemPurchased(itemID, itemName)
    local current = self:GetCurrentList()
    if not current or not current.tasks then return end

    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
    local numID = tonumber(itemID)
    local lname = itemName and itemName:lower() or nil

    ns:PrintDebug("[buy-hook] OnItemPurchased id=" .. tostring(itemID) ..
        " name=" .. tostring(itemName))

    for taskIdx, task in ipairs(current.tasks) do
        if task.status == "pending" and task.action == "buy"
                and task.assignedChar == charKey
                and ns:RealmMatches(task.buyRealm or "", currentRealm)
                and task.steps and task.currentStep then
            local stepType = self:GetCurrentStepType(task)
            if stepType == "browse" or stepType == "buy" then
                local taskNumID = tonumber(task.itemID) or tonumber((task.itemKey or ""):match("^(%d+)"))
                local matched = (numID and taskNumID and numID == taskNumID)
                    or (lname and task.name and task.name:lower() == lname)
                ns:PrintDebug("[buy-hook] check " .. (task.name or "?") ..
                    " taskID=" .. tostring(taskNumID) ..
                    " step=" .. tostring(stepType) ..
                    " matched=" .. tostring(matched))
                if matched then
                    -- Backfill numeric itemID so RefreshTaskSteps can match by ID
                    if numID and (not task.itemID or task.itemID == "") then
                        task.itemID = tostring(numID)
                    end
                    if stepType == "browse" then
                        self:AdvanceStep(taskIdx) -- browse → buy
                    end
                    self:AdvanceStep(taskIdx) -- buy → collect (waiting for mail)
                    ns:Print(ns.COLORS.GREEN .. "Purchased:|r " .. (task.name or "?") .. " — collect from mail")
                    if ns.UI then
                        if ns.UI.Refresh then ns.UI:Refresh() end
                        if ns.UI.RefreshMini then ns.UI:RefreshMini() end
                    end
                    if ns.BuyListSync then ns.BuyListSync:Rebuild(false) end
                    return
                end
            end
        end
    end
    ns:PrintDebug("[buy-hook] no matching buy task found")
end

-- Skip a task (TSM below threshold, user skip, etc.)
function TodoList:SkipTask(taskIndex, reason)
    self:UpdateTaskStatus(taskIndex, "skipped", reason)

    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
        local task = (ns.db.todoLists.active and ns.db.todoLists.active.tasks) and ns.db.todoLists.active.tasks[taskIndex]
        if task and task.taskUUID then
            ns.Sync:EmitDelta("TDSKIP", { taskUUID = task.taskUUID, reason = reason })
        end
    end

    self:CheckAutoComplete()
end

-- Delete a task entirely (remove from list, no logging).
function TodoList:DeleteTask(taskIndex)
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return
    end
    local tasks = ns.db.todoLists.active.tasks
    if not tasks or not tasks[taskIndex] then return end

    local item = tasks[taskIndex]
    local deletedUUID = item.taskUUID

    -- If deleting a buy task, cascade-delete correlated sell tasks for the same deal.
    -- Cross-realm flips generate a buy + sell pair; removing the buy orphans the sell.
    if item.action == "buy" and item.dealType == "flip" then
        local buyKey = item.itemKey or ""
        local buyName = item.name and item.name:lower() or ""
        local buyTarget = item.targetRealm or ""
        local buyRealm = item.buyRealm or ""

        -- Collect indices of correlated sell tasks (reverse order for safe removal)
        local toRemove = {}
        for i, other in ipairs(tasks) do
            if i ~= taskIndex and other.action == "sell"
                    and other.dealType == "flip"
                    and ((buyKey ~= "" and other.itemKey == buyKey)
                        or (buyName ~= "" and other.name and other.name:lower() == buyName))
                    and ns:RealmsOverlap(other.targetRealm or "", buyTarget)
                    and ns:RealmsOverlap(other.buyRealm or "", buyRealm) then
                table.insert(toRemove, i)
            end
        end

        -- Remove sell tasks + buy task together (descending order)
        table.insert(toRemove, taskIndex)
        table.sort(toRemove, function(a, b) return a > b end)
        local removedNames = {}
        for _, idx in ipairs(toRemove) do
            local t = tasks[idx]
            if t then
                if t.importSource and t.importKey then
                    ns:ImportRemove(t.importSource, t.importKey)
                end
                if t.action == "sell" then
                    table.insert(removedNames, (t.name or "?") .. " (sell)")
                end
                table.remove(tasks, idx)
            end
        end
        if #removedNames > 0 then
            ns:Print(ns.COLORS.YELLOW .. "Also removed " .. #removedNames
                .. " correlated sell task(s):|r " .. table.concat(removedNames, ", "))
        end
    else
        -- Clean up import reference
        if item.importSource and item.importKey then
            ns:ImportRemove(item.importSource, item.importKey)
        end
        table.remove(tasks, taskIndex)
    end

    if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
        if deletedUUID then
            ns.Sync:EmitDelta("TDDEL", { taskUUID = deletedUUID })
        end
    end

    self:CheckAutoComplete()
end

-- Bulk operations on a list of task indices.
-- Indices are sorted descending so removals don't shift subsequent indices.

function TodoList:BulkComplete(taskIndices)
    -- Sort descending for safe removal
    table.sort(taskIndices, function(a, b) return a > b end)
    for _, idx in ipairs(taskIndices) do
        self:MoveTaskToLog(idx)
    end
    self:CheckAutoComplete()
end

function TodoList:BulkSkip(taskIndices, reason)
    for _, idx in ipairs(taskIndices) do
        self:UpdateTaskStatus(idx, "skipped", reason or "bulk skip")
    end
    self:CheckAutoComplete()
end

function TodoList:BulkDelete(taskIndices)
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then return end
    local tasks = ns.db.todoLists.active.tasks
    if not tasks then return end
    -- Sort descending so indices don't shift
    table.sort(taskIndices, function(a, b) return a > b end)
    for _, idx in ipairs(taskIndices) do
        local item = tasks[idx]
        if item then
            if item.importSource and item.importKey then
                ns:ImportRemove(item.importSource, item.importKey)
            end
            table.remove(tasks, idx)
        end
    end
    self:CheckAutoComplete()
end

--------------------------
-- TSM Rejection Handling
--------------------------

-- Find an alternate character on the same realm for a task.
-- Excludes the given character and hidden characters.
-- Filters by role: buy tasks need buy/both, sell tasks need sell/both.
-- Returns charKey or nil.
function TodoList:FindAlternateCharacter(task, excludeChar)
    if not ns.db or not ns.db.characters then return nil end
    local targetRealm = task.targetRealm
    if not targetRealm or targetRealm == "" then return nil end

    local candidates = {}
    for charKey, charData in pairs(ns.db.characters) do
        if charKey ~= excludeChar then
            local role = charData.role or "both"
            if role ~= "none" then
                local roleOk = true
                if task.action == "buy" then
                    roleOk = (role == "both" or role == "buy")
                else
                    roleOk = (role == "both" or role == "sell")
                end
                if roleOk then
                    local charRealm = charKey:match("%-(.+)$")
                    if charRealm and ns:RealmMatches(targetRealm, charRealm) then
                        table.insert(candidates, charKey)
                    end
                end
            end
        end
    end

    if #candidates == 0 then return nil end
    table.sort(candidates) -- deterministic
    return candidates[1]
end

-- Check TSM thresholds for all pending tasks on the current character.
-- Below-threshold items are either reassigned to a realm-mate or skipped.
-- Skips create a log entry AND remove the task from the active list so
-- TSM-rejected tasks don't linger as residue after a posting run (FQ-179).
-- Returns: { reassigned = count, skipped = count }
function TodoList:HandleTSMRejections()
    if not ns.db or not ns.db.settings.tsmAutoSkipRejected then
        return { reassigned = 0, skipped = 0 }
    end
    if not ns.TSM or not ns.TSM:IsEnabled() then
        return { reassigned = 0, skipped = 0 }
    end

    local current = self:GetCurrentList()
    if not current or not current.tasks then
        return { reassigned = 0, skipped = 0 }
    end

    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or ""
    local results = { reassigned = 0, skipped = 0 }
    local messages = {}

    -- Collect indices to remove. We can't table.remove during ipairs
    -- because that shifts subsequent indices and skips entries. Reassigns
    -- mutate in place safely; only skips need post-loop removal.
    local toRemove = {}

    for taskIdx, task in ipairs(current.tasks) do
        -- Only check tasks that are pending, on this character, on this realm,
        -- and on the "post" step (ready to list on AH)
        local stepType = task.steps and task.currentStep and task.steps[task.currentStep]
            and task.steps[task.currentStep].type or nil
        if task.status == "pending" and task.assignedChar == charKey
            and (stepType == "post" or stepType == nil)
            and ns:RealmMatches(task.targetRealm or "", currentRealm) then

            -- Check TSM rejection reason
            -- Only reject if TSM explicitly says the price is below threshold.
            -- If there's no AH data (ahMin is nil), TSM may still post using normalPrice,
            -- so we do NOT treat missing AH data as a rejection.
            local belowThreshold, ahMin, threshold, opName = ns.TSM:IsBelowThreshold(task.itemKey)
            local reason = nil

            if belowThreshold then
                local threshStr = threshold and ns.TSM:FormatCopper(threshold) or "?"
                local ahMinStr = ahMin and ns.TSM:FormatCopper(ahMin) or "?"
                local opStr = opName and (" [" .. opName .. "]") or ""
                reason = "TSM: AH price " .. ahMinStr .. " below min " .. threshStr .. opStr
            end

            if reason then
                -- Try to reassign to another character on the same realm
                local altChar = self:FindAlternateCharacter(task, charKey)
                if altChar then
                    task.assignedChar = altChar
                    task.tsmRejectedFrom = charKey
                    task.tsmRejectedReason = reason
                    results.reassigned = results.reassigned + 1
                    local altName = altChar:match("^(.-)%-") or altChar
                    table.insert(messages, ns.COLORS.CYAN .. "Reassigned:|r " ..
                        (task.name or "?") .. " -> " .. altName .. " (" .. reason .. ")")
                else
                    -- No alternate character — log the skip and queue task
                    -- for removal. The log entry captures the rejection
                    -- reason so the player can audit later via /fq log.
                    results.skipped = results.skipped + 1
                    table.insert(messages, ns.COLORS.ORANGE .. "Skipped:|r " ..
                        (task.name or "?") .. " (" .. reason .. ")")

                    local logEntry = {
                        itemKey        = task.itemKey,
                        itemID         = task.itemID,
                        name           = task.name,
                        quality        = task.quality,
                        icon           = task.icon,
                        targetRealm    = task.targetRealm,
                        expectedPrice  = task.expectedPrice,
                        postedPrice    = nil,
                        postedAt       = time(),
                        charKey        = charKey,
                        expiresAt      = nil,
                        auctionStatus  = "skipped",
                        soldAt         = nil,
                        soldPrice      = nil,
                        postedQuantity = task.quantity or 1,
                        failReason     = reason,
                    }
                    table.insert(ns.db.log, logEntry)

                    table.insert(toRemove, {
                        taskIdx  = taskIdx,
                        taskUUID = task.taskUUID,
                        logEntry = logEntry,
                        importSource = task.importSource,
                        importKey    = task.importKey,
                    })
                end
            end
        end
    end

    -- Remove skipped tasks in reverse so earlier indices stay valid, then
    -- propagate to the linked partner via TDLOG (same delta used by
    -- MoveTaskToLog — partner inserts the log entry and removes the task).
    if #toRemove > 0 then
        table.sort(toRemove, function(a, b) return a.taskIdx > b.taskIdx end)
        for _, entry in ipairs(toRemove) do
            if entry.importSource and entry.importKey then
                ns:ImportRemove(entry.importSource, entry.importKey)
            end
            table.remove(current.tasks, entry.taskIdx)
        end
        if ns.Sync and ns.Sync.IsLinked and ns.Sync:IsLinked() and not ns.Sync._applying then
            for _, entry in ipairs(toRemove) do
                if entry.taskUUID then
                    ns.Sync:EmitDelta("TDLOG", {
                        taskUUID = entry.taskUUID,
                        logEntry = entry.logEntry,
                    })
                end
            end
        end
    end

    -- Print summary messages
    for _, msg in ipairs(messages) do
        ns:Print(msg)
    end
    if results.reassigned + results.skipped > 0 then
        ns:Print(ns.COLORS.YELLOW .. "TSM threshold check:|r " ..
            results.reassigned .. " reassigned, " .. results.skipped .. " skipped")
    end

    -- If skipping cleared the last pending task on the list, archive it.
    if results.skipped > 0 then
        self:CheckAutoComplete()
    end

    return results
end

-- Unskip a task back to pending
function TodoList:UnskipTask(taskIndex)
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return
    end

    local item = ns.db.todoLists.active.tasks[taskIndex]
    if item and item.status == "skipped" then
        item.status = "pending"
        item.failReason = nil
    end
end

-- Re-check unassigned tasks and assign them if a matching character now exists.
-- Called on login after character registration, and after TSM character adds.
function TodoList:ReassignUnassignedTasks()
    local current = self:GetCurrentList()
    if not current or not current.tasks then return 0 end

    local charKey = ns:GetCharKey()
    local reassigned = 0

    for _, task in ipairs(current.tasks) do
        if task.status == "unassigned" and not task.assignedChar then
            local realm = task.targetRealm
            -- For buy tasks, match against buyRealm instead
            if task.action == "buy" and task.buyRealm then
                realm = task.buyRealm
            end

            if realm and realm ~= "" then
                -- Find a character on this realm with matching role
                for ck, charData in pairs(ns.db.characters or {}) do
                    local charRealm = ck:match("%-(.+)$")
                    local role = type(charData) == "table" and (charData.role or "both") or "both"
                    local roleOk = role ~= "none"
                    if roleOk and task.action == "buy" then
                        roleOk = (role == "both" or role == "buy")
                    elseif roleOk then
                        roleOk = (role == "both" or role == "sell")
                    end
                    if charRealm and ns:RealmMatches(realm, charRealm) and roleOk then
                        task.assignedChar = ck
                        task.status = "pending"

                        -- Set up default steps if empty
                        if not task.steps or #task.steps == 0 then
                            if task.action == "buy" then
                                task.steps = {
                                    { type = "browse", status = "pending" },
                                    { type = "buy",    status = "pending" },
                                    { type = "collect", status = "pending" },
                                    { type = "deposit", to = "warbank", status = "pending" },
                                }
                            else
                                task.steps = {
                                    { type = "retrieve", from = "warbank", status = "pending" },
                                    { type = "post", status = "pending" },
                                    { type = "collect", status = "pending" },
                                }
                            end
                            task.currentStep = 1
                        end

                        reassigned = reassigned + 1
                        break
                    end
                end
            end
        end
    end

    return reassigned
end

--------------------------
-- Unknown Name Resolution
--------------------------

-- Scan all tasks for name "Unknown" and request item data from the server.
-- When GET_ITEM_INFO_RECEIVED fires, update the task names and refresh the UI.
local pendingNameRequests = {}  -- itemID -> true

function TodoList:ResolveUnknownNames()
    if not ns.db or not ns.db.todoLists then return end

    local lists = { ns.db.todoLists.active }
    for _, queued in ipairs(ns.db.todoLists.upcoming or {}) do
        lists[#lists + 1] = queued
    end

    local requested = 0
    for _, list in ipairs(lists) do
        if list and list.tasks then
            for _, task in ipairs(list.tasks) do
                if task.name == "Unknown" and task.itemKey then
                    local itemID = tonumber(task.itemKey:match("^(%d+)"))
                    if itemID then
                        -- Try immediate resolution first
                        local name = C_Item.GetItemNameByID(itemID)
                        if name then
                            task.name = name
                        else
                            -- Queue a server request
                            if not pendingNameRequests[itemID] then
                                pendingNameRequests[itemID] = true
                                C_Item.RequestLoadItemDataByID(itemID)
                                requested = requested + 1
                            end
                        end
                    end
                end
            end
        end
    end

    if requested > 0 then
        ns:PrintDebug("[TodoList] Requested item data for " .. requested .. " Unknown items")
    end
end

-- Event frame for GET_ITEM_INFO_RECEIVED
local nameResolveFrame = CreateFrame("Frame")
nameResolveFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
nameResolveFrame:SetScript("OnEvent", function(_, event, itemID, success)
    if not success or not pendingNameRequests[itemID] then return end
    pendingNameRequests[itemID] = nil

    local name = C_Item.GetItemNameByID(itemID)
    if not name then return end

    -- Update all tasks that reference this itemID and still show "Unknown"
    local updated = 0
    local lists = {}
    if ns.db and ns.db.todoLists then
        lists[#lists + 1] = ns.db.todoLists.active
        for _, queued in ipairs(ns.db.todoLists.upcoming or {}) do
            lists[#lists + 1] = queued
        end
    end

    for _, list in ipairs(lists) do
        if list and list.tasks then
            for _, task in ipairs(list.tasks) do
                if task.name == "Unknown" and task.itemKey then
                    local taskItemID = tonumber(task.itemKey:match("^(%d+)"))
                    if taskItemID == itemID then
                        task.name = name
                        updated = updated + 1
                    end
                end
            end
        end
    end

    if updated > 0 then
        ns:PrintDebug("[TodoList] Resolved " .. updated .. " task(s) to \"" .. name .. "\"")
        -- Refresh UI if available
        if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
        if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
    end
end)
