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
            local function L(s) table.insert(lines, s or "?") end
            local function V(v) if v == nil then return "-" elseif type(v) == "boolean" then return v and "1" or "0" elseif type(v) == "table" then return "{tbl}" else return tostring(v) end end

            local buildOk, buildErr = pcall(function()

            L("FQ|" .. (ns.db.schemaVersion or "?") .. "|" .. date("%Y-%m-%d %H:%M:%S") .. "|" .. ns:GetCharKey())

            -- Settings (all relevant)
            local s = ns.db.settings or {}
            L("S|scan=" .. V(s.autoScan) .. "|pull=" .. V(s.autoPullBank) .. "|dep=" .. V(s.autoDepositWarbank)
                .. "|gold=" .. V(s.autoWithdrawGold) .. "|maxG=" .. V(s.maxWithdrawGold)
                .. "|batch=" .. V(s.pullBatchSize) .. "|sellQty=" .. V(s.sellQtyMode) .. "/" .. V(s.defaultSellQty)
                .. "|tsm=" .. V(s.tsmEnabled) .. "|prof=" .. V(s.tsmProfile)
                .. "|tsmSkip=" .. V(s.tsmAutoSkipRejected) .. "|tsmPrice=" .. V(s.tsmPriceSource)
                .. "|tsmUpdate=" .. V(s.tsmAutoUpdatePrice) .. "|tsmAge=" .. V(s.tsmPriceMaxAge)
                .. "|mini=" .. V(s.showMini) .. "|debug=" .. V(s.debugMessages)
                .. "|autoGen=" .. V(s.importAutoGenerate) .. "|autoImp=" .. V(s.importAutoImport)
                .. "|sort=" .. V(s.genSortMode) .. "|filter=" .. V(s.genFilterMode))

            -- Characters
            local charKeys = {}
            for ck in pairs(ns.db.characters or {}) do table.insert(charKeys, ck) end
            table.sort(charKeys)
            for _, ck in ipairs(charKeys) do
                local c = ns.db.characters[ck]
                local itemCount, totalQty = 0, 0
                local locCounts = {}
                if c.inventory and c.inventory.items then
                    for _, item in pairs(c.inventory.items) do
                        itemCount = itemCount + 1
                        totalQty = totalQty + (item.quantity or 0)
                        if item.locations then
                            for loc, qty in pairs(item.locations) do
                                locCounts[loc] = (locCounts[loc] or 0) + qty
                            end
                        end
                    end
                end
                local lp = {}
                for loc, qty in pairs(locCounts) do table.insert(lp, loc .. ":" .. qty) end
                table.sort(lp)
                local scanAge = c.inventory and c.inventory.lastScan and (time() - c.inventory.lastScan) or -1
                L("C|" .. ck .. "|" .. V(c.class) .. "|" .. V(c.level) .. "|g=" .. math.floor((c.gold or 0) / 10000)
                    .. "|ign=" .. V(c.ignored) .. "|login=" .. (c.lastLogin and date("%m/%d %H:%M", c.lastLogin) or "-")
                    .. "|items=" .. itemCount .. "/" .. totalQty .. "|scan=" .. (scanAge >= 0 and scanAge .. "s" or "-")
                    .. "|" .. table.concat(lp, ","))
            end

            -- Warbank
            local wbItems = {}
            if ns.db.warbank and ns.db.warbank.items then
                for key, item in pairs(ns.db.warbank.items) do
                    if item.quantity and item.quantity > 0 then
                        table.insert(wbItems, (item.name or key) .. "x" .. item.quantity)
                    end
                end
            end
            table.sort(wbItems)
            local wbScanAge = ns.db.warbank and ns.db.warbank.lastScan and (time() - ns.db.warbank.lastScan) or -1
            L("WB|" .. #wbItems .. " items|scan=" .. (wbScanAge >= 0 and wbScanAge .. "s" or "-"))
            if #wbItems > 0 then
                L("WBI|" .. table.concat(wbItems, "|"))
            end

            -- Imports (summary by source+realm)
            for src, srcMap in pairs(ns.db.imports or {}) do
                local realms = {}
                for _, deal in pairs(srcMap) do
                    local r = deal.targetRealm or "?"
                    realms[r] = (realms[r] or 0) + 1
                end
                local rp = {}
                for r, n in pairs(realms) do table.insert(rp, r .. ":" .. n) end
                table.sort(rp)
                L("I|" .. src .. "|" .. table.concat(rp, "|"))
            end

            -- Todo Lists — full task dump
            local active = ns.db.todoLists and ns.db.todoLists.active
            if active and active.tasks then
                L("TD|\"" .. (active.name or "?") .. "\"|" .. #active.tasks .. " tasks")
                for i, t in ipairs(active.tasks) do
                    local stepStr = "-"
                    if t.steps and t.currentStep then
                        local parts = {}
                        for si, st in ipairs(t.steps) do
                            local marker = si == t.currentStep and ">" or ""
                            table.insert(parts, marker .. st.type .. ":" .. (st.status or "?"))
                        end
                        stepStr = table.concat(parts, ",")
                    end
                    L("T|" .. i .. "|" .. (t.status or "?")
                        .. "|" .. (t.name or "?")
                        .. "|k=" .. (t.itemKey or "-")
                        .. "|q=" .. V(t.quantity)
                        .. "|char=" .. (t.assignedChar or "-")
                        .. "|realm=" .. (t.targetRealm or "-")
                        .. "|src=" .. (t.source or "-")
                        .. "|act=" .. (t.action or "sell")
                        .. "|dep=" .. (t.depositFrom or "-")
                        .. "|def=" .. (t.deferredAt and date("%H:%M", t.deferredAt) or "-")
                        .. "|blk=" .. (t.blockedBy or "-")
                        .. "|steps=" .. stepStr
                        .. (t.failReason and ("|fail=" .. t.failReason) or "")
                        .. (t.tsmRejectedFrom and ("|tsmRej=" .. t.tsmRejectedFrom) or ""))
                end
            else
                L("TD|none")
            end
            local upcoming = ns.db.todoLists and ns.db.todoLists.upcoming or {}
            for qi, qList in ipairs(upcoming) do
                local qCount = qList.tasks and #qList.tasks or 0
                L("TQ|" .. qi .. "|\"" .. (qList.name or "?") .. "\"|" .. qCount .. " tasks")
            end

            -- Log (last 50 entries, compressed)
            local log = ns.db.log or {}
            local logStart = math.max(1, #log - 49)
            L("LOG|" .. #log .. " total|showing " .. (#log - logStart + 1))
            for i = logStart, #log do
                local e = log[i]
                L("L|" .. (e.auctionStatus or "?")
                    .. "|" .. (e.name or "?")
                    .. "|k=" .. (e.itemKey or "-")
                    .. "|char=" .. (e.charKey or "-")
                    .. "|realm=" .. (e.targetRealm or "-")
                    .. "|price=" .. (e.postedPrice or e.expectedPrice or "-")
                    .. "|posted=" .. (e.postedAt and date("%m/%d %H:%M", e.postedAt) or "-")
                    .. "|exp=" .. (e.expiresAt and date("%m/%d %H:%M", e.expiresAt) or "-")
                    .. "|sold=" .. (e.soldAt and date("%m/%d %H:%M", e.soldAt) or "-")
                    .. "|soldG=" .. (e.soldPrice and ns:FormatGold(e.soldPrice) or "-")
                    .. "|col=" .. (e.collectedAt and date("%m/%d %H:%M", e.collectedAt) or "-")
                    .. "|qty=" .. V(e.postedQuantity)
                    .. (e.failReason and ("|fail=" .. e.failReason) or "")
                    .. (e.saleOutcome and ("|out=" .. e.saleOutcome) or ""))
            end

            -- DNT
            local dntCount = 0
            for _ in pairs(ns.db.doNotTrack or {}) do dntCount = dntCount + 1 end
            L("DNT|" .. dntCount)

            -- Runtime state
            local tr = ns.Tracker or {}
            L("RT|pullIP=" .. V(tr._pullInProgress) .. "|depIP=" .. V(tr._depositInProgress)
                .. "|cancels=" .. V(tr._pendingCancels) .. "|ahOpen=" .. V(tr._isAHOpen))

            end) -- pcall

            if not buildOk then
                table.insert(lines, "ERROR|" .. tostring(buildErr))
            end

            local output = table.concat(lines, "\n")

            -- Save full export to SavedVariables as backup
            ns.db._debugExport = output
            ns.db._debugExportAt = date("%Y-%m-%d %H:%M:%S")

            UI:ShowExportPopup(output, #lines .. " lines, " .. #output .. " chars — Ctrl+A, Ctrl+C to copy")
        end

    elseif msg == "debug" then
        if ns.db then
            ns.db.settings.debugMessages = not ns.db.settings.debugMessages
            ns:Print("Debug messages: " .. (ns.db.settings.debugMessages and
                ns.COLORS.GREEN .. "ON" or ns.COLORS.RED .. "OFF") .. "|r")
        end

    elseif msg == "tutorial" then
        ns.db.settings.tutorialDone = false
        UI._tutorialActive = true
        UI._tutorialStep = 1
        UI._tutorialCallout = 1
        UI.currentPage = "todo"
        UI.mainFrame:Show()
        UI:Refresh()

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
        print("  /fq tutorial - Show the first-time tutorial")
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
