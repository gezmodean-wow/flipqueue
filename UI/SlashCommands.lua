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

    elseif msg == "debug bagprices" then
        -- /fq debug bagprices
        -- Walk current character's bags, parse each item's actual fqKey,
        -- and print: bag fqKey | live-cache hit | DBMinBuyout | item link.
        -- The point is to compare what FQ thinks the bag item is vs. what
        -- the cache and TSM data say for that exact variant — useful when
        -- the displayed post price looks wrong and we suspect the bag item
        -- is parsing to a different fqKey than the task expects.
        local bagList = ns.ALL_PLAYER_BAGS or ns.INVENTORY_BAGS or {0, 1, 2, 3, 4}
        local lines = 0
        for _, bag in ipairs(bagList) do
            local ok, num = pcall(C_Container.GetContainerNumSlots, bag)
            if ok and num then
                for slot = 1, num do
                    local ok2, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                    -- Skip soulbound items (Hearthstone, quest items, etc.) —
                    -- they can't be auctioned, so they're noise in this dump.
                    if ok2 and info and info.hyperlink and not info.isBound then
                        local id, bonus, mods = ns:ParseItemLink(info.hyperlink)
                        if id then
                            local fqKey = ns:MakeItemKey(id, bonus, mods)
                            local liveStr = "-"
                            if ns.AuctionScanCache then
                                local live = ns.AuctionScanCache:Lookup(fqKey, false)
                                if live and live.lowestUnit then
                                    liveStr = string.format("%.0fc (%s, %ds, %d listings%s)",
                                        live.lowestUnit, live.source or "?", live.age,
                                        live.listings and #live.listings or 0,
                                        live.lowestIsPlayer and ", own" or "")
                                end
                            end
                            local dbmin = ns.TSM and ns.TSM:IsEnabled() and ns.TSM:GetPrice(fqKey, "DBMinBuyout") or nil
                            local dbminStr = dbmin and string.format("%.0fc", dbmin) or "-"
                            print(string.format("  %s | live=%s | dbmin=%s | %s",
                                fqKey, liveStr, dbminStr, info.hyperlink))
                            lines = lines + 1
                        end
                    end
                end
            end
        end
        ns:Print("Bag prices: " .. lines .. " items")

    elseif msg:match("^debug parsegold") then
        -- /fq debug parsegold <input>     → print parsed gold value
        -- /fq debug parsegold             → run self-test of locale variants
        -- Lets a maintainer or tester verify the gold-string parser without
        -- being on the locale that produces the format (German "1.500g",
        -- English "1,500g", abbreviated "1.5k", etc.). Surfaces the parser's
        -- output as a number so you can confirm the FQ-121 family of bugs
        -- are fixed end-to-end.
        local input = msg:match("^debug parsegold%s+(.+)$")
        if input then
            local v = ns:ParseGoldValue(input)
            print(string.format("=== /fq debug parsegold ===\ninput: [%s]  len=%d\nparsed: %s gold",
                input, #input, tostring(v)))
        else
            print("=== /fq debug parsegold (self-test) ===")
            local cases = {
                -- input,           expected, comment
                {"1,999g",          1999,    "EN thousands separator"},
                {"1.999g",          1999,    "DE thousands separator"},
                {"2.000g",          2000,    "DE four-digit-style format"},
                {"2,000g",          2000,    "EN four-digit-style format"},
                {"500g",            500,     "no separator"},
                {"1.5k",            1500,    "EN k-abbreviation decimal"},
                {"1,5k",            1500,    "DE k-abbreviation decimal"},
                {"1.3m",            1300000, "EN m-abbreviation decimal"},
                {"1,3m",            1300000, "DE m-abbreviation decimal"},
                {"|cffffd700200g|r", 200,    "WoW color-coded"},
                {"",                0,       "empty"},
                {"junk",            0,       "no recognizable suffix"},
            }
            local pass, fail = 0, 0
            for _, c in ipairs(cases) do
                local got = ns:ParseGoldValue(c[1])
                local ok = got == c[2]
                if ok then pass = pass + 1 else fail = fail + 1 end
                print(string.format("  %s [%s] -> %s (expected %s) %s",
                    ok and "PASS" or "FAIL", c[1], tostring(got), tostring(c[2]), c[3]))
            end
            print(string.format("Total: %d pass, %d fail", pass, fail))
            print("Use: /fq debug parsegold <string>  to test a specific input")
        end

    elseif msg == "debug pulls" or msg == "debug ops" then
        -- /fq debug pulls (alias /fq debug ops) — toggle per-op trace for
        -- ProcessSync/Process bank ops (pulls AND deposits). OFF by default
        -- for performance (logs ~6 lines per op when on). Captures every
        -- ISSUE / ISSUE-DEPOSIT / SKIP source-empty / SKIP impostor /
        -- LOCKED / BANK-CLOSED / NO-DEST / DEFERRED / CURSOR-REJECT /
        -- VERIFY-FAIL decision in the debug ring buffer (visible via the
        -- popup or chat dump).
        if not ns.BankQueue then ns:Print("BankQueue not loaded.") return end
        ns.BankQueue._tracePulls = not ns.BankQueue._tracePulls
        if ns.BankQueue._tracePulls then
            ns:Print(ns.COLORS.YELLOW .. "Op trace ON|r — pull + deposit decisions go to debug log. Re-run to capture failures.")
        else
            ns:Print(ns.COLORS.GREEN .. "Op trace OFF.|r")
        end

    elseif msg == "debug gold" then
        -- /fq debug gold
        -- Walk the gold-required calculation for the current character
        -- with verbose per-task printing. Surfaces every filter / skip /
        -- cap that AutoWithdrawGold applies, so we can localise where a
        -- "wildly off" or "doesn't appear to work" report is coming from
        -- without having to flip /fq debug toggle and reproduce blind.
        if not ns.Tracker then ns:Print("Tracker not available.") return end
        local charKey = ns:GetCharKey()
        local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
        print("=== /fq debug gold ===")
        print("character:    " .. charKey)
        print("currentRealm: " .. currentRealm)

        local s = ns.db and ns.db.settings or {}
        print("--- Settings ---")
        print(string.format("  autoWithdrawGold = %s", tostring(s.autoWithdrawGold)))
        print(string.format("  autoDepositGold  = %s", tostring(s.autoDepositGold)))
        print(string.format("  goldBuffer       = %sg",  tostring(s.goldBuffer or 0)))
        print(string.format("  maxWithdrawGold  = %sg",  tostring(s.maxWithdrawGold or 0)))
        print(string.format("  sellQtyMode      = %s",  tostring(s.sellQtyMode)))
        print(string.format("  defaultSellQty   = %s",  tostring(s.defaultSellQty)))
        if ns.IsWarbandMiserActive then
            print(string.format("  WarbandMiser active = %s (defers withdraw/deposit if true)",
                tostring(ns:IsWarbandMiserActive())))
        end

        -- Walk every task on the current character, print per-task
        -- decisions verbatim so we see why something gets skipped.
        local tasks = ns.TodoList and ns.TodoList:GetCharacterTasks(charKey) or {}
        print("--- Tasks (" .. #tasks .. " total) ---")
        if #tasks == 0 then
            print("  (no tasks — withdraw target collapses to goldBuffer)")
        end
        for _, task in ipairs(tasks) do
            local item = task.item
            if item.action == "buy" then
                local realmOk = ns:RealmMatches(item.buyRealm or "", currentRealm)
                local raw = item.buyPrice or "(none)"
                local parsed = ns:ParseGoldValue(raw)
                local qty = item.quantity or 1
                print(string.format(
                    "  [BUY ] %s | qty=%d | buyRealm=%s | matches=%s | rawPrice=%q | parsed=%dg | cost=%dg %s",
                    tostring(item.name or "?"), qty, tostring(item.buyRealm),
                    tostring(realmOk), tostring(raw), parsed, parsed * qty,
                    realmOk and "" or "← SKIPPED (realm)"))
            else
                local realmOk = ns:RealmMatches(item.targetRealm or "", currentRealm)
                print(string.format(
                    "  [POST] %s | targetRealm=%s | matches=%s %s",
                    tostring(item.name or "?"), tostring(item.targetRealm),
                    tostring(realmOk), realmOk and "" or "← SKIPPED (realm)"))
            end
        end

        -- Aggregate via the same helpers AutoWithdrawGold uses, so the
        -- numbers we print match what the actual flow sees.
        local postCopper, postCount = ns.Tracker:CalculatePostingFees(charKey, currentRealm)
        local buyCopper, buyCount = ns.Tracker:CalculatePurchaseCosts(charKey, currentRealm)
        local totalCopper = postCopper + buyCopper

        print("--- Aggregate ---")
        print(string.format("  Posting fees: %s over %d task(s)", ns:FormatGold(postCopper), postCount))
        print(string.format("  Buy costs:    %s over %d task(s)", ns:FormatGold(buyCopper), buyCount))
        print(string.format("  Total need:   %s", ns:FormatGold(totalCopper)))

        -- Mirror AutoWithdrawGold's target-balance formula.
        local goldBufferCopper = (s.goldBuffer or 0) * 10000
        local estimatedFeesCopper = math.max(goldBufferCopper, math.ceil(totalCopper * 1.1))
        estimatedFeesCopper = math.ceil(estimatedFeesCopper / 10000) * 10000
        print(string.format("  Target balance: max(goldBuffer=%s, total + 10%%) = %s",
            ns:FormatGold(goldBufferCopper), ns:FormatGold(estimatedFeesCopper)))

        local playerCopper = GetMoney() or 0
        print(string.format("  Player has:   %s", ns:FormatGold(playerCopper)))

        if playerCopper >= estimatedFeesCopper then
            print("  → No withdraw needed (player has at-or-above target)")
        else
            local shortfall = estimatedFeesCopper - playerCopper
            local maxGold = s.maxWithdrawGold or 0
            local capStr = ""
            if maxGold > 0 and shortfall > maxGold * 10000 then
                shortfall = maxGold * 10000
                capStr = " (capped from larger by maxWithdrawGold)"
            end
            print(string.format("  → Would withdraw %s%s", ns:FormatGold(shortfall), capStr))
        end

        if C_Bank and C_Bank.FetchDepositedMoney and Enum and Enum.BankType then
            local ok, warbank = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
            if ok and warbank then
                print(string.format("  Warbank balance: %s", ns:FormatGold(warbank)))
            else
                print("  Warbank balance: (FetchDepositedMoney failed — bank panel may not be on warband tab)")
            end
        end

    elseif msg:match("^debug pricing%s+") then
        -- /fq debug pricing <itemName or itemID>
        -- Trace per-realm pricing for one item: shows the item's itemKey,
        -- the TSM string we produce, and per-realm hit/miss for the
        -- captured AuctionDB data. Used to diagnose "DealFinder shows the
        -- same price for items on every realm" — if all realms miss, the
        -- tsmStr we build doesn't match how TSM encoded the item in its
        -- realm data (variant/base mismatch).
        local rawQuery = msg:match("^debug pricing%s+(.+)$") or ""
        if rawQuery == "" then
            ns:Print("Usage: /fq debug pricing <itemName or itemID>  (or shift-click an item into chat)")
            return
        end

        -- Accept a shift-clicked item link (full "item:ID:..." string with
        -- "[Name]" suffix), a numeric ID, or a partial name. Extract the
        -- most useful matcher from whichever form was pasted.
        local linkID = rawQuery:match("[Hh]?item:(%d+)") or rawQuery:match("|Hitem:(%d+)")
        local linkName = rawQuery:match("%[(.-)%]")
        local query = (linkName or rawQuery):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local queryID = linkID or rawQuery:match("^(%d+)$")

        local function entryMatches(name, itemID)
            local nm = (name or ""):lower()
            if queryID and tostring(itemID) == queryID then return true end
            if nm == query or (query ~= "" and nm:find(query, 1, true)) then return true end
            return false
        end

        -- Resolve query to an itemKey. Search the log first (most recent
        -- posts), then character inventories, then warbank.
        local found
        if ns.db and ns.db.log then
            for _, entry in ipairs(ns.db.log) do
                local nm = (entry.name or ""):lower()
                if nm == query or nm:find(query, 1, true) or tostring(entry.itemID) == query then
                    found = { itemKey = entry.itemKey, name = entry.name, itemID = entry.itemID, source = "log" }
                    break
                end
            end
        end
        if not found and ns.db and ns.db.characters then
            for charKey, charData in pairs(ns.db.characters) do
                if charData.inventory and charData.inventory.items then
                    for key, item in pairs(charData.inventory.items) do
                        local nm = (item.name or ""):lower()
                        if nm == query or nm:find(query, 1, true) or tostring(item.itemID) == query then
                            found = { itemKey = key, name = item.name, itemID = item.itemID, source = "inventory:" .. charKey }
                            break
                        end
                    end
                end
                if found then break end
            end
        end
        if not found and ns.db and ns.db.warbank and ns.db.warbank.items then
            for key, item in pairs(ns.db.warbank.items) do
                local nm = (item.name or ""):lower()
                if nm == query or nm:find(query, 1, true) or tostring(item.itemID) == query then
                    found = { itemKey = key, name = item.name, itemID = item.itemID, source = "warbank" }
                    break
                end
            end
        end

        -- If the user pasted a full hyperlink, derive a variant itemKey from
        -- it directly so we can test the bonus-ID-decorated form even when
        -- our log entry stored the stripped base form.
        local linkItemKey = nil
        if rawQuery:find("item:") and ns.ParseItemLink and ns.MakeItemKey then
            local linkItemID, bonusIDs, modifiers = ns:ParseItemLink(rawQuery)
            if linkItemID then
                linkItemKey = ns:MakeItemKey(linkItemID, bonusIDs, modifiers)
            end
        end

        if not found and not linkItemKey then
            ns:Print("No item matching '" .. rawQuery .. "' found in log, inventory, or warbank.")
            return
        end

        print("=== /fq debug pricing ===")
        if found then
            print("name:    " .. tostring(found.name))
            print("itemID:  " .. tostring(found.itemID))
            print("itemKey (from " .. found.source .. "): " .. tostring(found.itemKey))
        end
        if linkItemKey and (not found or found.itemKey ~= linkItemKey) then
            print("itemKey (parsed from link): " .. linkItemKey)
        end

        if not ns.TSMRealms or not ns.TSMRealms:IsLoaded() then
            print("(TSMRealms not loaded)")
            return
        end

        -- Test pricing for each candidate itemKey we have (base form from
        -- log, variant form from link). Reports per-realm hit/miss for each
        -- so we can see whether the variant lookup is what's missing.
        local function TestKey(label, itemKey)
            print("--- pricing for " .. label .. " (itemKey=" .. itemKey .. ") ---")
            local tsmStr = ns.TSM and ns.TSM.ItemKeyToTSMString
                and ns.TSM:ItemKeyToTSMString(itemKey)
                or nil
            print("tsmStr:        " .. tostring(tsmStr))
            -- Show the level-form variant we'd use as a fallback against
            -- TSM's per-realm AuctionDB. If different from tsmStr, that's
            -- the key actually used for the match.
            if tsmStr and ns.TSMRealms and ns.TSMRealms.ToLevelForm then
                local levelStr = ns.TSMRealms:ToLevelForm(tsmStr)
                if levelStr and levelStr ~= tsmStr then
                    print("level form:    " .. levelStr)
                elseif levelStr == tsmStr then
                    print("level form:    (same as tsmStr)")
                else
                    print("level form:    (could not derive — item may not be loaded)")
                end
            end
            if not tsmStr then
                print("(no TSM string — lookup not possible)")
                return
            end
            local pricing = ns.TSMRealms:GetAllRealmPricing(tsmStr) or {}
            local hits, misses = 0, 0
            local realms = ns.TSMRealms:GetRealmList() or {}
            for _, realmName in ipairs(realms) do
                local p = pricing[realmName]
                if p then
                    hits = hits + 1
                    local mb = p.minBuyout and ns:FormatGold(p.minBuyout) or "?"
                    local mvr = p.marketValueRecent and ns:FormatGold(p.marketValueRecent) or "?"
                    print(string.format("  HIT  %-20s minBuyout=%s recent=%s n=%s",
                        realmName, mb, mvr, tostring(p.numAuctions)))
                else
                    misses = misses + 1
                end
            end
            print(string.format("  %d hit(s), %d miss(es) across %d realms", hits, misses, #realms))
        end

        -- De-dup: only test each unique itemKey once.
        local tested = {}
        if found and found.itemKey and not tested[found.itemKey] then
            TestKey("log/inventory entry", found.itemKey)
            tested[found.itemKey] = true
        end
        if linkItemKey and not tested[linkItemKey] then
            TestKey("pasted link (variant)", linkItemKey)
            tested[linkItemKey] = true
        end

        -- Show TSM region/single-realm fallback values DealFinder would use.
        if ns.TSM and ns.TSM.GetPrice then
            print("TSM region fallbacks:")
            print("  DBMinBuyout (current realm only): " ..
                tostring(ns.TSM:GetPrice(found.itemKey, "DBMinBuyout") or "nil"))
            print("  DBRegionMarketAvg: " ..
                tostring(ns.TSM:GetPrice(found.itemKey, "DBRegionMarketAvg") or "nil"))
            print("  DBRegionSaleAvg: " ..
                tostring(ns.TSM:GetPrice(found.itemKey, "DBRegionSaleAvg") or "nil"))
        end

    elseif msg == "debug realms" then
        -- /fq debug realms
        -- Show whether TSMRealms has captured per-realm AuctionDB data, and
        -- which realms it has. Used to diagnose "DealFinder shows the same
        -- price for items on every realm" complaints — TSM ignores realm
        -- data outside of (current realm, auctionDBAltRealm) so unless
        -- FlipQueue's hook captured it before TSM, DealFinder falls back to
        -- region-wide pricing for everything.
        if not ns.TSMRealms then ns:Print("TSMRealms not loaded.") return end
        local realms = ns.TSMRealms:GetRealmList() or {}
        print("=== /fq debug realms ===")
        print(string.format("captured %d realm(s)", #realms))
        if ns._tsmRealmsHookInstalled then
            print("hook: installed at file load")
        else
            print("hook: NOT installed (TSM_APPHELPER_LOAD_DATA was missing)")
        end
        if #realms == 0 then
            print("(empty — TSM_AppHelper's AppData.lua likely fired before our")
            print(" hook. DealFinder will use TSM region-wide pricing for all")
            print(" non-current-realm targets, so prices will look identical.")
            print(" Confirm by checking the realm rows in DealFinder Detail —")
            print(" each line ends with 'Per-Realm TSM' or 'Regional Fallback'.)")
        else
            for i, realmName in ipairs(realms) do
                local ts = ns.TSMRealms:GetRealmUpdateTime(realmName)
                local age = ts and string.format("%.1fh ago", (time() - ts) / 3600) or "?"
                print(string.format("  [%d] %s (updated %s)", i, realmName, age))
            end
        end

    elseif msg == "debug expired" or msg == "debug expired clear" then
        -- /fq debug expired         — list uncollected expired/cancelled entries.
        -- /fq debug expired clear   — also finalize them as collected (no
        --                             mail to recover; usually the mail was
        --                             already taken on another character via
        --                             warband mail, by Postal/automail, or
        --                             during a session where ScanMailForSales
        --                             didn't see them).
        --
        -- Diagnostic helper for phantom "N expired auction(s) to collect"
        -- notifications when no mail actually exists (#122). The auto-cleanup
        -- on mail-open handles the typical case; this is for log entries
        -- that fall outside that path.
        local doClear = (msg == "debug expired clear")
        if not ns.db or not ns.db.log then ns:Print("Log not available.") return end
        local charKey = ns:GetCharKey()
        local now = time()
        print("=== /fq debug expired" .. (doClear and " clear" or "") .. " ===")
        print("character: " .. charKey)
        if not doClear then
            print("(Run `/fq reconcile` first — it now matches against TSM expired/")
            print(" cancelled records and finalizes confirmed orphans automatically.")
            print(" Use `/fq debug expired clear` only if reconcile didn't catch them")
            print(" and you've verified there's no mail to collect.)")
        end

        -- Pre-build TSM record indexes once so per-entry annotation is O(1)
        -- on the inner loop (#127). Skipped silently if TSM isn't loaded.
        local tsmExpireByCharBase, tsmCancelByCharBase
        if ns.Tracker and ns.Tracker.GetTSMExpireRecords and type(TradeSkillMasterDB) == "table" then
            local function indexByCB(records)
                local m = {}
                for _, r in ipairs(records) do
                    m[r.charKey] = m[r.charKey] or {}
                    m[r.charKey][r.baseID] = m[r.charKey][r.baseID] or {}
                    table.insert(m[r.charKey][r.baseID], r)
                end
                return m
            end
            tsmExpireByCharBase = indexByCB(ns.Tracker:GetTSMExpireRecords())
            tsmCancelByCharBase = indexByCB(ns.Tracker:GetTSMCancelRecords())
        end

        local function CanonChar(s)
            if not s then return nil end
            return (s:gsub("%s+", ""))
        end
        local function FQBase(fqKey)
            if not fqKey or fqKey == "" then return nil end
            local pet = fqKey:match("^pet:(%d+)")
            if pet then return "pet:" .. pet end
            return fqKey:match("^(%d+)")
        end

        -- Look up TSM presence for one entry. Returns "expired YYYY-MM-DD",
        -- "cancelled YYYY-MM-DD", or "no TSM record" / "TSM not loaded".
        local function TSMNote(entry)
            if not tsmExpireByCharBase then return "TSM not loaded" end
            local canon = CanonChar(entry.charKey)
            local baseID = FQBase(entry.itemKey)
            if not canon or not baseID then return "no TSM record (no key)" end
            local postedAt = entry.postedAt or 0
            local earliest = postedAt - 60 * 60
            local latest   = postedAt + 49 * 60 * 60
            local function findIn(idx, label)
                local list = idx[canon] and idx[canon][baseID]
                if not list then return nil end
                for _, r in ipairs(list) do
                    if r.time >= earliest and r.time <= latest then
                        return label .. " " .. date("%Y-%m-%d", r.time)
                    end
                end
                return nil
            end
            return findIn(tsmExpireByCharBase, "expired")
                or findIn(tsmCancelByCharBase, "cancelled")
                or "no TSM record"
        end

        local mineCount, totalCount, cleared = 0, 0, 0
        for i, entry in ipairs(ns.db.log) do
            if (entry.auctionStatus == "expired" or entry.auctionStatus == "cancelled")
                and not entry.collectedAt then
                totalCount = totalCount + 1
                if entry.charKey == charKey then
                    mineCount = mineCount + 1
                    local postedDate = entry.postedAt and date("%Y-%m-%d %H:%M", entry.postedAt) or "?"
                    local expiredAge = entry.expiresAt and string.format("%.1fd ago", (now - entry.expiresAt) / 86400) or "?"
                    print(string.format(
                        "  [%d] %s | status=%s | postedAt=%s | expired=%s | itemKey=%s | TSM: %s",
                        i, tostring(entry.name), tostring(entry.auctionStatus),
                        postedDate, expiredAge, tostring(entry.itemKey), TSMNote(entry)))
                    if doClear then
                        local prior = entry.auctionStatus  -- "expired" or "cancelled"
                        entry.auctionStatus = "collected"
                        entry.saleOutcome = entry.saleOutcome or "expired"
                        entry.endReason = entry.endReason or prior
                        entry.collectedAt = now
                        entry.finalReason = "manual_debug_clear"
                        cleared = cleared + 1
                    end
                end
            end
        end
        print(string.format("--- %d uncollected on %s (of %d total across all characters) ---",
            mineCount, charKey, totalCount))
        if doClear and cleared > 0 then
            if ns.SalesIndex then ns.SalesIndex:Invalidate() end
            if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
            if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
            ns:Print(ns.COLORS.GREEN .. "Cleared " .. cleared ..
                " phantom expired entries on " .. charKey .. ".|r")
        elseif doClear then
            ns:Print("Nothing to clear.")
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
                -- Operation-evaluated prices: these are the values we
                -- now feed into the decision tree (TSM resolves the op
                -- AND evaluates the expression in one call).
                P("AuctioningOpNormal")
                P("AuctioningOpMin")
                P("AuctioningOpMax")
                -- Raw price sources for comparison — useful for spotting
                -- when our normal differs from TSM's posting view because
                -- of bonus-ID canonicalisation (the variant we pass has
                -- different DBMarket than the variant TSM uses internally).
                P("DBMinBuyout")
                P("dbmarket")
                P("DBRegionMarketAvg")
                -- Also show the canonical TSM string TSM would derive
                -- from the BASE itemID (no bonuses) — if AuctioningOp*
                -- values differ between the variant string and the base
                -- string, TSM's BonusIds.Filter is collapsing variants
                -- our cache treats as distinct.
                local baseStr = "i:" .. (key:match("^([^;]+)") or "?")
                if baseStr ~= tsmStr then
                    print("--- base item " .. baseStr .. ":")
                    local function PB(src)
                        local ok, v = pcall(TSM_API.GetCustomPriceValue, src, baseStr)
                        print("  " .. src .. ":", ok and tostring(v) or ("err " .. tostring(v)))
                    end
                    PB("AuctioningOpNormal")
                    PB("AuctioningOpMin")
                    PB("AuctioningOpMax")
                    PB("DBMinBuyout")
                    PB("dbmarket")
                    PB("DBRegionMarketAvg")
                end
                -- Also try the LEVEL form (i:<id>::i<ilvl>) since TSM's
                -- AuctionDB internally goes through ItemString.ToLevel
                -- before lookup. Some price sources may key on the level
                -- form rather than the variant string.
                local ilvl
                if GetDetailedItemLevelInfo and ns.ItemKeyToItemString then
                    local wowStr = ns:ItemKeyToItemString(key)
                    if wowStr then
                        ilvl = GetDetailedItemLevelInfo(wowStr)
                    end
                end
                if ilvl then
                    local levelStr = baseStr .. "::i" .. ilvl
                    print("--- level form " .. levelStr .. ":")
                    local function PL(src)
                        local ok, v = pcall(TSM_API.GetCustomPriceValue, src, levelStr)
                        print("  " .. src .. ":", ok and tostring(v) or ("err " .. tostring(v)))
                    end
                    -- AuctionPost.EvalLevel uses level form for ALL op
                    -- prices, so query the same set here. If level form
                    -- returns nil for OpMin/Max while canonical doesn't,
                    -- the decision tree's below-min / above-max branches
                    -- will silently skip and we'll fall through to
                    -- "undercut" — exactly the divergence we're chasing.
                    PL("AuctioningOpNormal")
                    PL("AuctioningOpMin")
                    PL("AuctioningOpMax")
                    PL("DBMinBuyout")
                    PL("dbmarket")
                    PL("DBRegionMarketAvg")
                end
                -- Also dump the level string AuctionPost.EvalLevel actually
                -- builds (via TSM:ItemKeyToLevelString). The hand-rolled
                -- baseStr .. "::i" .. ilvl above and that helper can
                -- diverge if itemLink is missing or the helper's
                -- normalization differs. Both should produce the same
                -- string; if they don't, that's a clue.
                if ns.TSM and ns.TSM.ItemKeyToLevelString then
                    local apLevelStr = ns.TSM:ItemKeyToLevelString(key, nil)
                    print("AuctionPost.levelStr (no link):", tostring(apLevelStr))
                    if apLevelStr and TSM_API and TSM_API.GetCustomPriceValue then
                        local function PA(src)
                            local ok, v = pcall(TSM_API.GetCustomPriceValue, src, apLevelStr)
                            print("  " .. src .. " @ AP-levelStr:",
                                ok and tostring(v) or ("err " .. tostring(v)))
                        end
                        PA("AuctioningOpMin")
                        PA("AuctioningOpMax")
                    end
                end
            end
            -- Profile + group resolution chain. When the row's op shows
            -- as #Default but TSM's UI says the item is grouped, the
            -- divergence is one of: wrong profile selected, TSM string
            -- mismatch (e.g. pets keyed by full p:<species>:<breed>:...
            -- instead of our p:<species>), or GetGroupPathByItem refusing
            -- the bonus-stripped canonical we pass it.
            if ns.TSM and ns.TSM.GetSelectedProfile then
                local selProfile = ns.TSM:GetSelectedProfile()
                local activeProfile = ns.TSM:GetActiveProfile()
                print("profile (selected):", tostring(selProfile))
                print("profile (TSM active):", tostring(activeProfile))
                if selProfile ~= activeProfile then
                    print("  ⚠ FQ is querying a different profile than TSM's active one — set ns.db.settings.tsmProfile=nil or match TSM's active profile.")
                end
                if TSM_API and TSM_API.GetGroupPathByItem and tsmStr then
                    local ok2, gp = pcall(TSM_API.GetGroupPathByItem, TSM_API, tsmStr)
                    print("groupPath @ tsmStr:", ok2 and tostring(gp) or "err")
                end
                -- For pets, also probe the items DB directly. TSM may store
                -- group entries under a more granular key than our p:<id>.
                if key:find("^pet:") and ns.TSM.GetItemsDB then
                    local itemsDB = ns.TSM:GetItemsDB(selProfile)
                    if itemsDB then
                        local matches = {}
                        local idStr = key:match("^pet:(%d+)") or ""
                        for k in pairs(itemsDB) do
                            if k:find("^p:" .. idStr .. "[:$]") or k == ("p:" .. idStr) then
                                matches[#matches + 1] = k .. " → " .. tostring(itemsDB[k])
                            end
                        end
                        if #matches > 0 then
                            print("itemsDB pet entries for species " .. idStr .. ":")
                            for _, m in ipairs(matches) do print("  " .. m) end
                        else
                            print("itemsDB: no pet entries match species " .. idStr)
                        end
                    end
                end
            end

            local op = ns.TSM:GetItemAuctioningOp(key)
            if op then
                print("op:", op.opName,
                    "priceReset=" .. tostring(op.priceReset),
                    "aboveMax=" .. tostring(op.aboveMax),
                    "ignoreLowDuration=" .. tostring(op.ignoreLowDuration),
                    "matchStackSize=" .. tostring(op.matchStackSize))
                print("  normalPrice expr:", tostring(op.normalPrice),
                    "-> " .. tostring(ns.TSM:EvaluateOpPrice(key, op.normalPrice)))
                print("  minPrice expr:", tostring(op.minPrice),
                    "-> " .. tostring(ns.TSM:EvaluateOpPrice(key, op.minPrice)))
                print("  maxPrice expr:", tostring(op.maxPrice),
                    "-> " .. tostring(ns.TSM:EvaluateOpPrice(key, op.maxPrice)))
            else
                print("op: <none> (item ungrouped or no TSM profile selected)")
            end
            -- Dump per-listing cache detail. The decision tree's lowest is
            -- whatever survives IsAuctionFiltered (low time-left, wrong
            -- stack size, threshold-ignore) — when our chosen lowest
            -- diverges from TSM's, the per-listing fields say why.
            if ns.AuctionScanCache then
                local live = ns.AuctionScanCache:Lookup(key, false)
                if live and live.listings and #live.listings > 0 then
                    print("--- live cache: " .. #live.listings .. " listings, " ..
                        live.age .. "s old, source=" .. tostring(live.source))
                    for i, L in ipairs(live.listings) do
                        local tl = L.timeLeftSec and (L.timeLeftSec .. "s") or "?"
                        print(string.format(
                            "  [%d] buyout=%dc qty=%d seller=%s timeLeft=%s isPlayer=%s hasOwner=%s",
                            i, L.buyout or 0, L.quantity or 0,
                            tostring(L.seller or ""), tl,
                            tostring(L.isPlayer == true), tostring(L.hasOwner == true)))
                    end
                else
                    print("--- live cache: (no entry)")
                end
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
        print("  /fq debug bagprices - Walk bags, dump each item's fqKey + cache hit + DBMinBuyout + link")
        print("  /fq debug gold - Walk the gold-required calc per task, dump settings + skip reasons + final withdraw amount")
        print("  /fq debug realms - Dump TSMRealms-captured realms; diagnose DealFinder flat-price-across-realms")
        print("  /fq debug pricing <name|id> - Trace per-realm AuctionDB lookup for one item (hit/miss per realm + tsmStr used)")
        print("  /fq debug expired - Dump uncollected expired/cancelled log entries for the current character (phantom-notification diagnosis)")
        print("  /fq debug expired clear - Finalize the listed entries as collected (use after verifying there's no mail to recover)")
        print("  /fq debug pulls - Toggle per-op trace for pulls AND deposits; off by default for perf, on for diagnosing item-specific failures")
        print("  /fq debug parsegold [<string>] - Run gold-string parser against input or self-test locale variants (German/EN dot/comma)")
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
