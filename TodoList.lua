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

-- Refresh all pending tasks: update steps based on current game state.
-- Called on login, bag changes, bank open, AH open, mail, TSM data.
-- This checks whether steps have been satisfied by game events.
function TodoList:RefreshTaskSteps()
    local current = self:GetCurrentList()
    if not current or not current.tasks then return false end

    local charKey = ns:GetCharKey()
    local changed = false

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

            if stepType == "retrieve" then
                -- Check if item has appeared in bags (pulled from bank/warbank)
                local itemKey = task.itemKey or ""
                local itemNumID = tonumber(task.itemID) or tonumber(itemKey:match("^(%d+)"))
                local inBags = (bagsItemKeys[itemKey] and bagsItemKeys[itemKey] > 0)
                    or (itemNumID and bagsItemIDs[itemNumID] and bagsItemIDs[itemNumID] > 0)

                if inBags then
                    self:AdvanceStep(taskIdx)
                    changed = true
                    -- Also update source to bags
                    task.source = "bags"
                end
            end
            -- "post" and "collect" steps are advanced by Tracker (bag decrease / auction check)
        end
    end

    return changed
end

-- Skip a task (TSM below threshold, user skip, etc.)
function TodoList:SkipTask(taskIndex, reason)
    self:UpdateTaskStatus(taskIndex, "skipped", reason)
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
