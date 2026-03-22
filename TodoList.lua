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

-- Clear the active list
function TodoList:ClearCurrent()
    if not ns.db or not ns.db.todoLists then return end
    ns.db.todoLists.active = nil
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

    -- Live scan current character's bags for item keys and IDs
    local bagsItemKeys = {} -- itemKey -> qty
    local bagsItemIDs = {}  -- numericID -> qty
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
                    end
                end
            end
        end
    end)

    local changed = false
    for _, item in ipairs(current.tasks) do
        if item.status == "pending" and item.assignedChar == charKey then
            local itemKey = item.itemKey or ""
            local itemNumID = tonumber(item.itemID) or tonumber(itemKey:match("^(%d+)"))
            local inBags = (bagsItemKeys[itemKey] and bagsItemKeys[itemKey] > 0)
                or (itemNumID and bagsItemIDs[itemNumID] and bagsItemIDs[itemNumID] > 0)

            if inBags and item.source ~= "bags" then
                item.source = "bags"
                changed = true
            elseif not inBags and item.source == "bags" then
                -- Item left bags (posted, deposited, etc.) — mark unavailable
                -- Full scan (bank open, etc.) will set the correct location
                item.source = "unavailable"
                changed = true
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

    local item = ns.db.todoLists.active.tasks[taskIndex]
    if item then
        item.status = status
        if reason then item.failReason = reason end
    end
end

-- Move a completed task to the log
function TodoList:MoveTaskToLog(taskIndex, postedPrice, expirySeconds, postedQuantity)
    if not ns.db or not ns.db.todoLists or not ns.db.todoLists.active then
        return
    end

    local item = ns.db.todoLists.active.tasks[taskIndex]
    if not item then return end

    local taskQty = item.quantity or 1
    local moveQty = postedQuantity or taskQty

    table.insert(ns.db.log, {
        itemKey        = item.itemKey,
        itemID         = item.itemID,
        name           = item.name,
        quality        = item.quality,
        icon           = item.icon,
        targetRealm    = item.targetRealm,
        expectedPrice  = item.expectedPrice,
        postedPrice    = postedPrice or item.expectedPrice,
        postedAt       = time(),
        charKey        = item.assignedChar or ns:GetCharKey(),
        expiresAt      = expirySeconds and (time() + expirySeconds) or nil,
        auctionStatus  = "active",
        soldAt         = nil,
        soldPrice      = nil,
        postedQuantity = moveQty,
    })

    -- Partial post: reduce quantity; full post: mark completed
    if moveQty < taskQty then
        item.quantity = taskQty - moveQty
    else
        item.status = "posted"
        -- Remove from imports source
        if item.importSource and item.importKey then
            ns:ImportRemove(item.importSource, item.importKey)
        end
    end
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
local function IsItemInAccountInventory(itemKey, itemNumID)
    for _, charData in pairs(ns.db.characters or {}) do
        if charData.inventory and charData.inventory.items then
            local inv = charData.inventory.items[itemKey]
            if inv then
                if inv.locations then
                    for _, qty in pairs(inv.locations) do
                        if qty > 0 then return true end
                    end
                elseif (inv.quantity or 0) > 0 then
                    return true
                end
            end
            if itemNumID then
                for k, invItem in pairs(charData.inventory.items) do
                    if k ~= itemKey then
                        local kNumID = tonumber((k:gsub(";.*", "")))
                        if kNumID == itemNumID then
                            if invItem.locations then
                                for _, qty in pairs(invItem.locations) do
                                    if qty > 0 then return true end
                                end
                            elseif (invItem.quantity or 0) > 0 then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    if ns.db.warbank and ns.db.warbank.items then
        local wbItem = ns.db.warbank.items[itemKey]
        if wbItem and (wbItem.quantity or 0) > 0 then return true end
        if itemNumID then
            for k, wb in pairs(ns.db.warbank.items) do
                if k ~= itemKey then
                    local kNumID = tonumber((k:gsub(";.*", "")))
                    if kNumID == itemNumID and (wb.quantity or 0) > 0 then return true end
                end
            end
        end
    end

    return false
end

-- Find actual storage location of a task's item accessible to the current character.
-- Returns "bags", "bank", "reagent", "warbank", or "guildbank" if found; nil otherwise.
local function FindItemSource(itemKey, itemNumID, charKey, inBags)
    if inBags then return "bags" end

    -- Character's stored inventory (bags, bank, reagent from last scan)
    local charData = ns.db.characters and ns.db.characters[charKey]
    if charData and charData.inventory and charData.inventory.items then
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

        local found = CheckInv(charData.inventory.items[itemKey])
        if found then return found end

        -- Numeric ID fallback (different bonus/modifier variants)
        if itemNumID then
            for k, inv in pairs(charData.inventory.items) do
                if k ~= itemKey then
                    local kNumID = tonumber((k:gsub(";.*", "")))
                    if kNumID == itemNumID then
                        found = CheckInv(inv)
                        if found then return found end
                    end
                end
            end
        end
    end

    -- Warbank
    if ns.db.warbank and ns.db.warbank.items then
        local wbItem = ns.db.warbank.items[itemKey]
        if wbItem and (wbItem.quantity or 0) > 0 then return "warbank" end
        if itemNumID then
            for k, wb in pairs(ns.db.warbank.items) do
                if k ~= itemKey then
                    local kNumID = tonumber((k:gsub(";.*", "")))
                    if kNumID == itemNumID and (wb.quantity or 0) > 0 then return "warbank" end
                end
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

    -- Build quick bag lookup for current character
    local bagsItemKeys = {}
    local bagsItemIDs = {}
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
            local inBags = (bagsItemKeys[itemKey] and bagsItemKeys[itemKey] > 0)
                or (itemNumID and bagsItemIDs[itemNumID] and bagsItemIDs[itemNumID] > 0)

            -- Buy tasks have different step logic
            local isBuyTask = task.action == "buy"

            local justAdvanced = false
            if isBuyTask then
                -- Buy task steps: browse → buy → deposit
                if stepType == "browse" then
                    -- "browse" is user-initiated at AH — no auto-advance
                elseif stepType == "buy" then
                    -- If item now in bags, the buy step is complete
                    if inBags then
                        self:AdvanceStep(taskIdx)
                        changed = true
                        task.source = "bags"
                        justAdvanced = true
                    end
                elseif stepType == "deposit" then
                    -- If item left bags (deposited to warbank), deposit step is complete
                    if not inBags and task.source == "bags" then
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
                end
                -- "post" and "collect" steps are advanced by Tracker (bag decrease / auction check)
            end

            -- Check item availability for deferral (skip tasks just advanced)
            -- Buy tasks don't need item availability — they need to buy the item
            if task.status == "pending" and not justAdvanced and not isBuyTask then
                local actualSource = FindItemSource(itemKey, itemNumID, charKey, inBags)

                if not actualSource then
                    -- Item not found for this character — check account-wide
                    if not IsItemInAccountInventory(itemKey, itemNumID) then
                        -- Item gone from entire account — auto-skip
                        task.status = "skipped"
                        task.failReason = "Item no longer in any inventory"
                        task.deferredAt = nil
                        changed = true
                    elseif not task.deferredAt then
                        task.deferredAt = time()
                        changed = true
                    end
                else
                    -- Item found — clear deferral and update source
                    if task.deferredAt then
                        task.deferredAt = nil
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

    -- Also check availability for OTHER characters' tasks using stored DB data.
    -- Can't advance steps or scan live bags for them, but can set/clear deferral
    -- so their groups sort correctly without needing to log into each character.
    -- Buy tasks are excluded — they don't need existing inventory.
    for taskIdx, task in ipairs(current.tasks) do
        if task.status == "pending" and task.assignedChar
            and task.assignedChar ~= charKey
            and task.steps and task.currentStep
            and task.action ~= "buy" then

            local itemKey = task.itemKey or ""
            local itemNumID = tonumber(task.itemID) or tonumber(itemKey:match("^(%d+)"))
            local actualSource = FindItemSource(itemKey, itemNumID, task.assignedChar, false)

            if not actualSource then
                -- Item not found for assigned character — check account-wide
                if not IsItemInAccountInventory(itemKey, itemNumID) then
                    task.status = "skipped"
                    task.failReason = "Item no longer in any inventory"
                    task.deferredAt = nil
                    changed = true
                elseif not task.deferredAt then
                    task.deferredAt = time()
                    changed = true
                end
            else
                if task.deferredAt then
                    task.deferredAt = nil
                    changed = true
                end
                if task.source ~= actualSource then
                    task.source = actualSource
                    changed = true
                end
            end
        end
    end

    return changed
end

-- Skip a task (TSM below threshold, user skip, etc.)
function TodoList:SkipTask(taskIndex, reason)
    self:UpdateTaskStatus(taskIndex, "skipped", reason)
end

--------------------------
-- TSM Rejection Handling
--------------------------

-- Find an alternate non-ignored character on the same realm for a task.
-- Excludes the given character and any ignored characters.
-- Returns charKey or nil.
function TodoList:FindAlternateCharacter(task, excludeChar)
    if not ns.db or not ns.db.characters then return nil end
    local targetRealm = task.targetRealm
    if not targetRealm or targetRealm == "" then return nil end

    local candidates = {}
    for charKey, charData in pairs(ns.db.characters) do
        if charKey ~= excludeChar and not charData.ignored then
            local charRealm = charKey:match("%-(.+)$")
            if charRealm and ns:RealmMatches(targetRealm, charRealm) then
                table.insert(candidates, charKey)
            end
        end
    end

    if #candidates == 0 then return nil end
    table.sort(candidates) -- deterministic
    return candidates[1]
end

-- Check TSM thresholds for all pending tasks on the current character.
-- Below-threshold items are either reassigned to a realm-mate or skipped.
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

    for taskIdx, task in ipairs(current.tasks) do
        if task.status == "pending" and task.assignedChar == charKey
            and ns:RealmMatches(task.targetRealm or "", currentRealm) then

            local belowThreshold, ahMin, threshold, opName = ns.TSM:IsBelowThreshold(task.itemKey)

            if belowThreshold then
                local threshStr = threshold and ns.TSM:FormatCopper(threshold) or "?"
                local ahMinStr = ahMin and ns.TSM:FormatCopper(ahMin) or "?"
                local opStr = opName and (" [" .. opName .. "]") or ""
                local reason = "TSM: AH price " .. ahMinStr .. " below min " .. threshStr .. opStr

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
                    -- No alternate character — skip with reason
                    task.status = "skipped"
                    task.failReason = reason
                    results.skipped = results.skipped + 1
                    table.insert(messages, ns.COLORS.ORANGE .. "Skipped:|r " ..
                        (task.name or "?") .. " (" .. reason .. ")")

                    -- Log the rejection
                    table.insert(ns.db.log, {
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
