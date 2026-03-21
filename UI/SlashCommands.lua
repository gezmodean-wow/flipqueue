-- UI/SlashCommands.lua
-- Slash command handler
local addonName, ns = ...

local UI = ns.UI

SLASH_FLIPQUEUE1 = "/flipqueue"
SLASH_FLIPQUEUE2 = "/fq"

SlashCmdList["FLIPQUEUE"] = function(msg)
    msg = (msg or ""):lower():trim()

    if msg == "import" then
        UI.currentPage = "import"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg == "scan" then
        ns.Scanner:ScanCurrentCharacter()

    elseif msg == "bank" then
        ns.Scanner:ScanBank()
        ns.Scanner:ScanWarbank()

    elseif msg == "gbank" then
        ns:Print(ns.COLORS.YELLOW .. "Guild bank scanning is disabled.|r Blizzard's API returns unreliable item data (wrong IDs, missing ilvl, pets as Pet Cage).")

    elseif msg == "cleanup" then
        if ns.db then
            ns.db._cleanupVersion = nil  -- force re-run
            ns:CleanupLegacyData()
            if ns.db._cleanupSummary then
                ns:Print(ns.COLORS.GREEN .. "Data cleanup: " .. ns.db._cleanupSummary .. "|r")
                ns.db._cleanupSummary = nil
            else
                ns:Print(ns.COLORS.GREEN .. "Data cleanup complete — no issues found.|r")
            end
            UI:Refresh()
        end

    elseif msg == "clear" then
        ns:ImportClear("fpScanner")
        ns:Print("Imports cleared.")
        UI:Refresh()

    elseif msg == "clear log" then
        ns:ClearLog()
        ns:Print("Log cleared.")
        UI:Refresh()

    elseif msg == "log" then
        UI.currentPage = "log"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg == "queue" or msg == "generator" then
        UI.currentPage = "generator"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg == "inv" or msg == "inventory" then
        UI.currentPage = "inventory"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg == "autopull" then
        if ns.db then
            ns.db.settings.autoPullBank = not ns.db.settings.autoPullBank
            ns:Print("Auto-pull from bank: " .. (ns.db.settings.autoPullBank and "ON" or "OFF"))
        end

    elseif msg == "gold" then
        if ns.db then
            ns.db.settings.autoWithdrawGold = not ns.db.settings.autoWithdrawGold
            ns:Print("Auto-withdraw gold for AH fees: " .. (ns.db.settings.autoWithdrawGold and "ON" or "OFF"))
        end

    elseif msg == "dnt" or msg == "donottrack" then
        UI:ShowDoNotTrackFrame()

    elseif msg:match("^dnt add ") or msg:match("^donottrack add ") then
        local itemName = msg:match("^d[on]*t[rack]* add (.+)$")
        if itemName and itemName ~= "" then
            -- Resolve itemID from inventory so IsDoNotTrack(itemID) works
            local resolvedID = ns:ResolveItemID({itemID = "", name = itemName})
            local dntKey = resolvedID and tostring(resolvedID) or itemName
            ns:AddDoNotTrack(dntKey, itemName)
            ns:Print("Added to Do Not Track: " .. itemName .. (resolvedID and (" (ID: " .. resolvedID .. ")") or " (name only, item not in inventory)"))
            UI:Refresh()
        end

    elseif msg:match("^dnt remove ") or msg:match("^donottrack remove ") then
        local itemName = msg:match("^d[on]*t[rack]* remove (.+)$")
        if itemName and itemName ~= "" then
            -- Try to find by name
            for id, nameOrTrue in pairs(ns.db.doNotTrack) do
                local name = type(nameOrTrue) == "string" and nameOrTrue or id
                if name:lower() == itemName:lower() or id == itemName then
                    ns:RemoveDoNotTrack(id)
                    ns:Print("Removed from Do Not Track: " .. name)
                    UI:Refresh()
                    return
                end
            end
            ns:PrintError("Item not found in Do Not Track list: " .. itemName)
        end

    elseif msg == "mini" then
        UI:ToggleMini()

    elseif msg == "export" or msg == "export bags" or msg == "export bank"
        or msg == "export warbank" or msg == "export wb" or msg == "export all" then
        UI.currentPage = "export"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg == "settings" or msg == "config" or msg == "options" then
        UI:ShowSettings()

    elseif msg == "sort" then
        if ns.db then
            ns.db.settings.sortMode = ns.db.settings.sortMode == "realm" and "name" or "realm"
            ns:Print("Sort mode: " .. ns.db.settings.sortMode)
            UI:Refresh()
        end

    elseif msg == "state" or msg == "diag" then
        if ns.db then
            local lines = {}
            local function L(s) table.insert(lines, s) end

            L("=== FlipQueue State ===")
            L("schema=" .. (ns.db.schemaVersion or "?") .. " time=" .. date("%Y-%m-%d %H:%M") .. " char=" .. ns:GetCharKey())

            -- Settings (key ones)
            local s = ns.db.settings or {}
            L("-- Settings")
            L("autoPull=" .. tostring(s.autoPullBank) .. " autoDeposit=" .. tostring(s.autoDepositWarbank)
                .. " autoGold=" .. tostring(s.autoWithdrawGold) .. " autoScan=" .. tostring(s.autoScan))
            L("sellQtyMode=" .. tostring(s.sellQtyMode or "default") .. " defaultSellQty=" .. tostring(s.defaultSellQty or 1)
                .. " pullBatch=" .. tostring(s.pullBatchSize or 5))
            L("tsmEnabled=" .. tostring(s.tsmEnabled) .. " tsmProfile=" .. tostring(s.tsmProfile or ""))

            -- Characters
            L("-- Characters (" .. (function() local n=0; for _ in pairs(ns.db.characters or {}) do n=n+1 end; return n end)() .. ")")
            local charKeys = {}
            for ck in pairs(ns.db.characters or {}) do table.insert(charKeys, ck) end
            table.sort(charKeys)
            for _, ck in ipairs(charKeys) do
                local c = ns.db.characters[ck]
                local itemCount = 0
                local locCounts = {}
                if c.inventory and c.inventory.items then
                    for _, item in pairs(c.inventory.items) do
                        itemCount = itemCount + 1
                        if item.locations then
                            for loc, qty in pairs(item.locations) do
                                locCounts[loc] = (locCounts[loc] or 0) + qty
                            end
                        end
                    end
                end
                local locParts = {}
                for loc, qty in pairs(locCounts) do table.insert(locParts, loc .. "=" .. qty) end
                table.sort(locParts)
                L(ck .. " class=" .. tostring(c.class) .. " lvl=" .. tostring(c.level)
                    .. " gold=" .. ns:FormatGold(c.gold or 0)
                    .. " guild=" .. tostring(c.guild or "none")
                    .. " ignored=" .. tostring(c.ignored or false)
                    .. " login=" .. (c.lastLogin and date("%m/%d %H:%M", c.lastLogin) or "?")
                    .. " items=" .. itemCount .. " {" .. table.concat(locParts, ",") .. "}")
            end

            -- Warbank
            local wbCount = 0
            local wbQty = 0
            if ns.db.warbank and ns.db.warbank.items then
                for _, item in pairs(ns.db.warbank.items) do
                    wbCount = wbCount + 1
                    wbQty = wbQty + (item.quantity or 0)
                end
            end
            L("-- Warbank: " .. wbCount .. " unique, " .. wbQty .. " total qty")

            -- Imports
            L("-- Imports")
            for src, srcMap in pairs(ns.db.imports or {}) do
                local count = 0
                local realms = {}
                for _, deal in pairs(srcMap) do
                    count = count + 1
                    local r = deal.targetRealm or "?"
                    realms[r] = (realms[r] or 0) + 1
                end
                L(src .. ": " .. count .. " deals")
                local realmList = {}
                for r, n in pairs(realms) do table.insert(realmList, r .. "(" .. n .. ")") end
                table.sort(realmList)
                for _, rs in ipairs(realmList) do L("  " .. rs) end
            end

            -- Todo Lists
            L("-- TodoLists")
            local active = ns.db.todoLists and ns.db.todoLists.active
            if active and active.tasks then
                L("active: \"" .. (active.name or "?") .. "\" tasks=" .. #active.tasks)
                local statusCounts = {}
                local charCounts = {}
                local deferredCount = 0
                for _, task in ipairs(active.tasks) do
                    local st = task.status or "pending"
                    statusCounts[st] = (statusCounts[st] or 0) + 1
                    if task.assignedChar then
                        if not charCounts[task.assignedChar] then
                            charCounts[task.assignedChar] = { total = 0, deferred = 0, statuses = {} }
                        end
                        local cc = charCounts[task.assignedChar]
                        cc.total = cc.total + 1
                        cc.statuses[st] = (cc.statuses[st] or 0) + 1
                        if task.deferredAt then
                            cc.deferred = cc.deferred + 1
                            deferredCount = deferredCount + 1
                        end
                    end
                end
                local stParts = {}
                for st, n in pairs(statusCounts) do table.insert(stParts, st .. "=" .. n) end
                table.sort(stParts)
                L("  statuses: " .. table.concat(stParts, " "))
                L("  deferred: " .. deferredCount)

                -- Per-character task breakdown
                local charList = {}
                for ck in pairs(charCounts) do table.insert(charList, ck) end
                table.sort(charList)
                for _, ck in ipairs(charList) do
                    local cc = charCounts[ck]
                    local csParts = {}
                    for st, n in pairs(cc.statuses) do table.insert(csParts, st .. "=" .. n) end
                    table.sort(csParts)
                    L("  " .. ck .. ": " .. cc.total .. " tasks (" .. table.concat(csParts, " ")
                        .. ") deferred=" .. cc.deferred)
                end

                -- Show individual tasks with issues (deferred, unavailable, blocked)
                local problemTasks = {}
                for i, task in ipairs(active.tasks) do
                    if task.status == "pending" and (task.deferredAt or task.source == "unavailable" or task.blockedBy) then
                        table.insert(problemTasks, {
                            idx = i,
                            name = task.name or "?",
                            char = task.assignedChar or "unassigned",
                            source = task.source or "?",
                            deferred = task.deferredAt and date("%m/%d %H:%M", task.deferredAt) or "no",
                            blockedBy = task.blockedBy or "",
                            step = task.currentStep or 0,
                            stepType = task.steps and task.steps[task.currentStep] and task.steps[task.currentStep].type or "?",
                        })
                    end
                end
                if #problemTasks > 0 then
                    L("  -- Problem tasks (" .. #problemTasks .. ")")
                    for _, pt in ipairs(problemTasks) do
                        L("  #" .. pt.idx .. " " .. pt.name .. " @" .. pt.char
                            .. " src=" .. pt.source .. " step=" .. pt.stepType
                            .. " deferred=" .. pt.deferred
                            .. (pt.blockedBy ~= "" and (" blocked=" .. pt.blockedBy) or ""))
                    end
                end
            else
                L("active: none")
            end
            local upcoming = ns.db.todoLists and ns.db.todoLists.upcoming or {}
            L("upcoming: " .. #upcoming .. " list(s)")

            -- Log summary
            local logCounts = {}
            for _, entry in ipairs(ns.db.log or {}) do
                local st = entry.auctionStatus or "?"
                logCounts[st] = (logCounts[st] or 0) + 1
            end
            local logParts = {}
            for st, n in pairs(logCounts) do table.insert(logParts, st .. "=" .. n) end
            table.sort(logParts)
            L("-- Log: " .. #(ns.db.log or {}) .. " entries (" .. table.concat(logParts, " ") .. ")")

            -- DNT
            local dntCount = 0
            for _ in pairs(ns.db.doNotTrack or {}) do dntCount = dntCount + 1 end
            L("-- DoNotTrack: " .. dntCount .. " items")

            local output = table.concat(lines, "\n")
            UI:ShowExportPopup(output, "Ctrl+A, Ctrl+C to copy — paste to Claude for diagnosis")
        end

    elseif msg == "debug" then
        if ns.db then
            ns.db.settings.debugMessages = not ns.db.settings.debugMessages
            ns:Print("Debug messages: " .. (ns.db.settings.debugMessages and
                ns.COLORS.GREEN .. "ON" or ns.COLORS.RED .. "OFF") .. "|r")
        end

    elseif msg == "help" then
        ns:Print("Commands:")
        print("  /fq - Toggle main window")
        print("  /fq import - Open import page")
        print("  /fq log - Show posted items log")
        print("  /fq queue - Open To-Do Generator")
        print("  /fq inv - Open full inventory page")
        print("  /fq scan - Rescan current character's bags")
        print("  /fq bank - Scan bank + warbank (must be at bank)")
        print("  /fq gbank - Scan guild bank (must have guild bank open)")
        print("  /fq cleanup - Clean up legacy data and normalize saved variables")
        print("  /fq export - Export page (CSV/AAA formats)")
        print("  /fq sort - Toggle sort mode (realm/name)")
        print("  /fq clear - Clear all imported deals")
        print("  /fq clear log - Clear posted items log")
        print("  /fq autopull - Toggle auto-pull from bank")
        print("  /fq gold - Toggle auto-withdraw gold for AH fees")
        print("  /fq dnt - Show Do Not Track list")
        print("  /fq mini - Toggle mini overlay")
        print("  /fq state - Export full FQ state for diagnosis")
        print("  /fq debug - Toggle debug messages")
        print("  /fq settings - Open settings panel")
        print("  /fq dnt add <name> - Add item to Do Not Track")
        print("  /fq dnt remove <name> - Remove from Do Not Track")
        print("")
        print("  Inventory: Right-click by status (DNT/remove DNT/queue info)")
        print("  To-Do: Right-click = posted, Shift+Right = skip")
    else
        -- Toggle main window
        if UI.mainFrame:IsShown() then
            UI.mainFrame:Hide()
        else
            UI.mainFrame:Show()
            UI:Refresh()
        end
    end
end
