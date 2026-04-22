-- UI/SlashCommands.lua
-- Slash command handler
local addonName, ns = ...

local UI = ns.UI

SLASH_FLIPQUEUE1 = "/flipqueue"
SLASH_FLIPQUEUE2 = "/fq"

SlashCmdList["FLIPQUEUE"] = function(msg)
    msg = (msg or ""):lower():trim()

    if msg == "import" then
        UI.currentPage = "transform"
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
            ns:Print("Auto-withdraw gold for AH fees + purchases: " .. (ns.db.settings.autoWithdrawGold and "ON" or "OFF"))
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

    elseif msg == "purge-remote" then
        if ns.db and ns.db.characters then
            local myUUID = ns.db.sync and ns.db.sync.accountUUID or nil
            local validPartners = {}
            if ns.db.sync and ns.db.sync.partners then
                for uuid in pairs(ns.db.sync.partners) do validPartners[uuid] = true end
            end

            -- Build set of characters we've actually logged into (have local scan data)
            local myCharKey = ns:GetCharKey()

            local removed = {}
            for charKey, charData in pairs(ns.db.characters) do
                local dominated = false
                -- Case 1: has foreign accountUUID
                if charData.accountUUID and charData.accountUUID ~= myUUID and not validPartners[charData.accountUUID] then
                    dominated = true
                end
                -- Case 2: no accountUUID but never locally scanned (no inventory.lastScan)
                -- and not the current character
                if not dominated and not charData.accountUUID then
                    local hasScan = charData.inventory and charData.inventory.lastScan and charData.inventory.lastScan > 0
                    if not hasScan and charKey ~= myCharKey then
                        dominated = true
                    end
                end
                if dominated then
                    table.insert(removed, charKey)
                    ns.db.characters[charKey] = nil
                end
            end

            if #removed > 0 then
                table.sort(removed)
                ns:Print(ns.COLORS.GREEN .. "Purged " .. #removed .. " foreign/unscanned characters:|r")
                for _, ck in ipairs(removed) do
                    ns:Print("  " .. ns.COLORS.RED .. ck .. "|r")
                end
            else
                ns:Print(ns.COLORS.GREEN .. "No foreign characters found.|r")
            end
            UI:Refresh()
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
                .. "|depAll=" .. V(s.autoDepositAll) .. "|gold=" .. V(s.autoWithdrawGold) .. "|maxG=" .. V(s.maxWithdrawGold)
                .. "|batch=" .. V(s.pullBatchSize) .. "|sellQty=" .. V(s.sellQtyMode) .. "/" .. V(s.defaultSellQty)
                .. "|tsm=" .. V(s.tsmEnabled) .. "|prof=" .. V(s.tsmProfile)
                .. "|tsmSkip=" .. V(s.tsmAutoSkipRejected) .. "|tsmGenSkip=" .. V(s.tsmSkipOnGenerate) .. "|tsmPrice=" .. V(s.tsmPriceSource)
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
                    .. "|role=" .. (c.role or "both") .. "|login=" .. (c.lastLogin and date("%m/%d %H:%M", c.lastLogin) or "-")
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

    elseif msg == "debug" or msg == "debug console" then
        -- Open the in-game debug console (buttons + live debug log).
        if UI.ToggleDebugConsole then UI:ToggleDebugConsole() end

    elseif msg == "debug toggle" then
        if ns.db then
            ns.db.settings.debugMessages = not ns.db.settings.debugMessages
            ns:Print("Debug messages: " .. (ns.db.settings.debugMessages and
                ns.COLORS.GREEN .. "ON" or ns.COLORS.RED .. "OFF") .. "|r")
        end

    elseif msg:match("^debug bankpopup") then
        -- /fq debug bankpopup [N]              -> N pulls, N deposits, N extras
        -- /fq debug bankpopup [P] [D] [E]      -> explicit per-section counts
        -- Generates fake ops so the popup overflows the visible row window,
        -- letting us validate the scroll behavior without needing real ops.
        local p, d, e = msg:match("^debug bankpopup%s+(%d+)%s+(%d+)%s+(%d+)")
        local n = msg:match("^debug bankpopup%s+(%d+)$")
        if p and d and e then
            p, d, e = tonumber(p), tonumber(d), tonumber(e)
        elseif n then
            n = tonumber(n)
            p, d, e = n, n, n
        else
            p, d, e = 20, 20, 20
        end
        local function fake(prefix, count)
            local arr = {}
            for i = 1, count do
                arr[i] = {
                    op = "fake",
                    name = prefix .. " item " .. i,
                    icon = "Interface\\Icons\\INV_Misc_QuestionMark",
                    quantity = (i % 5) + 1,
                }
            end
            return arr
        end
        if UI.ShowBankPopup then
            -- Reset any in-progress execution state so the popup builds fresh.
            if UI.HideBankPopup then UI:HideBankPopup() end
            UI:ShowBankPopup({
                pulls    = fake("Pull", p),
                deposits = fake("Deposit", d),
                extras   = fake("Extra", e),
            }, function()
                ns:Print("Debug popup: execute clicked (no-op).")
            end)
            ns:Print("Debug bank popup: " .. p .. " pulls, " .. d .. " deposits, " .. e .. " extras.")
        end

    elseif msg == "debug scan" or msg:match("^debug scan%s+%d+$") then
        -- /fq debug scan [N]
        -- Dump the live-AH-scan cache (populated passively from any addon's
        -- search events). Shows per-variant minUnit and how old each entry
        -- is — handy for confirming TSM scans are actually feeding us.
        local n = tonumber(msg:match("^debug scan%s+(%d+)$")) or 20
        if not ns.AuctionScanCache then
            ns:Print("AuctionScanCache not loaded.")
        else
            local rows, total = ns.AuctionScanCache:DebugDump(n)
            ns:Print(("Live-scan cache: %d entries (showing %d newest)"):format(total, #rows))
            for _, line in ipairs(rows) do
                print("  " .. line)
            end
        end

    elseif msg:match("^debug post%s+") then
        -- /fq debug post <fqKey>
        -- Dump the TSM lookup chain for an fqKey so we can see what string
        -- TSM sees and what prices it returns. Used to diagnose variant
        -- collapse (e.g. bonus-ID ilvl upgrades that TSM filters).
        local key = msg:match("^debug post%s+(.+)$")
        if not key or key == "" then
            ns:Print("Usage: /fq debug post <itemID;bonusIDs;modifiers>")
        elseif not ns.TSM or not ns.TSM:IsAvailable() then
            ns:Print("TSM not available.")
        else
            local tsmStr = ns.TSM:ItemKeyToTSMString(key)
            print("fqKey:", key)
            print("TSM string:", tostring(tsmStr))
            if tsmStr and TSM_API and TSM_API.GetCustomPriceValue then
                local function P(src)
                    local ok, v = pcall(TSM_API.GetCustomPriceValue, src, tsmStr)
                    print(src .. ":", ok and tostring(v) or ("err " .. tostring(v)))
                end
                P("DBMinBuyout")
                P("dbmarket")
                P("DBRegionMarketAvg")
            end
            local op = ns.TSM:GetItemAuctioningOp(key)
            if op then
                print("op:", op.opName,
                    "priceReset=" .. tostring(op.priceReset),
                    "aboveMax=" .. tostring(op.aboveMax))
                print("  normalPrice expr:", tostring(op.normalPrice),
                    "-> " .. tostring(ns.TSM:EvaluateOpPrice(key, op.normalPrice)))
                print("  minPrice expr:", tostring(op.minPrice),
                    "-> " .. tostring(ns.TSM:EvaluateOpPrice(key, op.minPrice)))
                print("  maxPrice expr:", tostring(op.maxPrice),
                    "-> " .. tostring(ns.TSM:EvaluateOpPrice(key, op.maxPrice)))
            else
                print("op: <none> (item ungrouped or no TSM profile selected)")
            end
        end

    elseif msg == "tutorial" then
        ns.db.settings.tutorialDone = false
        UI._tutorialActive = true
        UI._tutorialStep = 1
        UI._tutorialCallout = 1
        UI.currentPage = "todo"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg:sub(1, 5) == "link " then
        -- Syntax:
        --   /fq link CharName            (auto: try BNet, fall back to whisper)
        --   /fq link bnet CharName       (explicit: BNet friend)
        --   /fq link local CharName      (explicit: same BNet account, whisper)
        local rest = msg:sub(6):match("^%s*(.-)%s*$") or ""
        local firstWord, remainder = rest:match("^(%S+)%s+(.+)$")
        local target, transportHint
        if firstWord == "bnet" then
            target = remainder and remainder:match("^%s*(.-)%s*$") or ""
            transportHint = "bnet"
        elseif firstWord == "local" or firstWord == "whisper" then
            target = remainder and remainder:match("^%s*(.-)%s*$") or ""
            transportHint = "whisper"
        else
            target = rest
        end
        if target ~= "" and ns.Sync then
            ns.Sync:RequestPair(target, transportHint)
        else
            ns:Print("Usage: /fq link [bnet|local] CharName-Realm")
        end

    elseif msg == "unlink" then
        if ns.Sync then
            ns.Sync:Unlink()
        end

    elseif msg == "sync" then
        if ns.Sync and ns.Sync:IsLinked() then
            ns.Sync:RequestFullSync()
            ns:Print("Full sync requested.")
        else
            ns:Print("Not linked. Use Settings > Multi-Account to link.")
        end

    elseif msg == "help" then
        ns:Print("Commands:")
        print("  /fq - Toggle main window")
        print("  /fq import - Open transform page")
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
        print("  /fq debug - Open the debug console (buttons + live log)")
        print("  /fq debug toggle - Toggle debug message output to chat")
        print("  /fq debug bankpopup [N|P D E] - Show fake bank popup with N (or P/D/E) rows for UI overflow testing")
        print("  /fq debug post <fqKey> - Dump TSM string + price sources + op settings for diagnosing posting divergence")
        print("  /fq debug scan [N] - Dump N (default 20) most recent entries from the live-AH-scan cache")
        print("  /fq tutorial - Show the first-time tutorial")
        print("  /fq settings - Open settings panel")
        print("  /fq link [bnet|local] <Char-Realm> - Link to another account (bnet=friend, local=same BNet)")
        print("  /fq unlink - Disconnect sync link")
        print("  /fq sync - Force full re-sync with linked account")
        print("  /fq dnt add <name> - Add item to Do Not Track")
        print("  /fq dnt remove <name> - Remove from Do Not Track")
        print("  /fq reconcile - Upgrade expired/cancelled log entries to sold using TSM data")
        print("  /fq reconcile reset - Clear the reconcile-checked flag (re-run against all entries)")
        print("")
        print("  Inventory: Right-click by status (DNT/remove DNT/queue info)")
        print("  To-Do: Right-click = posted, Shift+Right = skip")
    elseif msg == "reconcile" then
        if ns.Tracker and ns.Tracker.ReconcileWithTSM then
            ns.Tracker:ReconcileWithTSM(true)
        else
            ns:Print(ns.COLORS.RED .. "TSM reconcile not available.|r")
        end

    elseif msg == "reconcile reset" then
        if ns.Tracker and ns.Tracker.ResetTSMReconcile then
            local n = ns.Tracker:ResetTSMReconcile()
            ns.Tracker._tsmLastReconcile = nil
            ns:Print("Cleared TSM-reconcile flag on " .. n .. " entries.")
        end

    elseif msg == "testpost" then
        if ns.AuctionPost and ns.AuctionPost.TestPost then
            ns.AuctionPost:TestPost()
        else
            ns:Print(ns.COLORS.RED .. "AuctionPost module not loaded.|r")
        end

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
