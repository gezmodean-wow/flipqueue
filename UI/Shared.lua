-- UI/Shared.lua
-- Shared UI utility functions used by multiple page files
local addonName, ns = ...

local UI = ns.UI

-- ==========================================
-- COLOR HELPERS
-- ==========================================
-- Quality-color and gold-format helpers delegate to Cogworks-1.0 (Text.lua)
-- so all suite cogs render these the same way. CLASS_COLORS stays local for
-- now — its consumers do direct table lookups (CLASS_COLORS[class]) and
-- migrating those call sites belongs with the Phase B page rewrites.

-- WoW class colors for display
local CLASS_COLORS = {
    WARRIOR     = "c79c6e", PALADIN     = "f58cba", HUNTER      = "abd473",
    ROGUE       = "fff569", PRIEST      = "ffffff", DEATHKNIGHT = "c41f3b",
    SHAMAN      = "0070de", MAGE        = "69ccf0", WARLOCK     = "9482c9",
    MONK        = "00ff96", DRUID       = "ff7d0a", DEMONHUNTER = "a330c9",
    EVOKER      = "33937f",
}

-- ==========================================
-- UTILITY FUNCTIONS
-- ==========================================

local function QualityColorName(name, quality)
    return ns.cw:QualityColorName(name, quality)
end

-- Look up icon, quality, and resolved numeric ID for an item
-- Returns: icon, quality, resolvedNumericID
local function LookupItemInfo(itemID, itemKey, itemName)
    local icon, quality, resolvedID

    -- Try WoW API with numeric ID
    local numID = tonumber(itemID)
    if numID and numID > 0 then
        resolvedID = numID
        local ok1, _, _, _, _, iconTexture = pcall(C_Item.GetItemInfoInstant, numID)
        if ok1 and iconTexture then icon = iconTexture end
        local ok2, _, _, itemQuality = pcall(C_Item.GetItemInfo, numID)
        if ok2 and itemQuality then quality = itemQuality end
    end

    -- If no numeric ID, try resolving by item name via WoW API
    if not resolvedID and itemName and itemName ~= "" then
        local ok, nameID = pcall(function()
            if C_Item.GetItemIDForItemInfo then
                return C_Item.GetItemIDForItemInfo(itemName)
            end
            return nil
        end)
        if ok and nameID and nameID > 0 then
            resolvedID = nameID
            if not icon then
                local ok3, _, _, _, _, iconTexture = pcall(C_Item.GetItemInfoInstant, nameID)
                if ok3 and iconTexture then icon = iconTexture end
            end
            if not quality then
                local ok4, _, _, itemQuality = pcall(C_Item.GetItemInfo, nameID)
                if ok4 and itemQuality then quality = itemQuality end
            end
        end
    end

    -- Fall back to scanned inventory data for icon
    if not icon and ns.db then
        local searchKey = itemKey or ""
        local searchName = itemName and itemName:lower() or ""

        -- Search character inventories
        for _, charData in pairs(ns.db.characters) do
            if charData.inventory and charData.inventory.items then
                for key, data in pairs(charData.inventory.items) do
                    if key == searchKey or (data.name and data.name:lower() == searchName) then
                        if data.icon then icon = data.icon end
                        if not resolvedID then
                            local invNumID = tonumber(data.itemID)
                            if invNumID and invNumID > 0 then resolvedID = invNumID end
                        end
                        break
                    end
                end
                if icon then break end
            end
        end

        -- Search warbank
        if not icon and ns.db.warbank and ns.db.warbank.items then
            for key, data in pairs(ns.db.warbank.items) do
                if key == searchKey or (data.name and data.name:lower() == searchName) then
                    if data.icon then icon = data.icon end
                    if not resolvedID then
                        local wbNumID = tonumber(data.itemID)
                        if wbNumID and wbNumID > 0 then resolvedID = wbNumID end
                    end
                    break
                end
            end
        end
    end

    return icon, quality, resolvedID
end

local function FormatGoldValue(totalGold)
    return ns.cw:FormatGoldValue(totalGold)
end

-- ==========================================
-- CURRENT CHARACTER TASKS
-- ==========================================

-- Build "Check Mail" / expiring task list for current character
local function BuildCurrentCharTasks()
    if not ns.db then return {} end
    local tasks = {}
    local myCharKey = ns:GetCharKey()

    -- Auction summary for current character
    local auctionsByChar = ns.Tracker and ns.Tracker.GetAuctionSummaryByCharacter
        and ns.Tracker:GetAuctionSummaryByCharacter() or {}
    local myAuctions = auctionsByChar[myCharKey]

    -- Active auctions info (not actionable, just informational)
    -- Expired auctions are in MAIL, not AH — handled by "Check Mail" below

    -- Check Mail: distinguish sold (collect gold) vs expired/cancelled (collect items)
    local uncollected = ns.SalesIndex:GetUncollectedForChar(myCharKey)
    local soldInMail = uncollected.sold
    local expiredInMail = uncollected.expired
    local cancelledInMail = uncollected.cancelled
    if soldInMail > 0 then
        table.insert(tasks, {
            icon   = "Interface\\Icons\\INV_Misc_Coin_01",
            text   = ns.COLORS.GREEN .. "Check Mail:|r " .. soldInMail .. " auction(s) sold — collect gold",
            sort   = 2,
            _dismissible = true,
            _onDismiss = function()
                for _, entry in ipairs(ns.db.log) do
                    if entry.charKey == myCharKey and entry.auctionStatus == "sold" and not entry.collectedAt then
                        entry.collectedAt = time()
                    end
                end
            end,
        })
    end
    if expiredInMail > 0 then
        table.insert(tasks, {
            icon   = "Interface\\Icons\\INV_Letter_15",
            text   = ns.COLORS.YELLOW .. "Check Mail:|r " .. expiredInMail .. " expired auction(s) — collect items",
            sort   = 3,
            _dismissible = true,
            _onDismiss = function()
                for _, entry in ipairs(ns.db.log) do
                    if entry.charKey == myCharKey and entry.auctionStatus == "expired" then
                        entry.auctionStatus = "collected"
                    end
                end
            end,
        })
    end
    if cancelledInMail > 0 then
        table.insert(tasks, {
            icon   = "Interface\\Icons\\INV_Letter_15",
            text   = ns.COLORS.ORANGE .. "Check Mail:|r " .. cancelledInMail .. " cancelled auction(s) — collect items",
            sort   = 3,
            _dismissible = true,
            _onDismiss = function()
                for _, entry in ipairs(ns.db.log) do
                    if entry.charKey == myCharKey and entry.auctionStatus == "cancelled" then
                        entry.auctionStatus = "collected"
                    end
                end
            end,
        })
    end

    -- Expiring soon on this character
    if myAuctions and myAuctions.active > 0 and myAuctions.soonest then
        local alertMinutes = ns.db.settings.expiryAlertMinutes or 15
        if myAuctions.soonest < (alertMinutes * 60) then
            local h = math.floor(myAuctions.soonest / 3600)
            local m = math.floor((myAuctions.soonest % 3600) / 60)
            local countdown = h > 0 and (h .. "h " .. m .. "m") or (m .. "m")
            table.insert(tasks, {
                icon   = "Interface\\Icons\\Spell_Holy_BorrowedTime",
                text   = ns.COLORS.ORANGE .. "Expiring:|r " .. myAuctions.active .. " auction(s) — soonest in " .. countdown,
                sort   = 4,
            })
        end
    end

    -- Active auctions info (not urgent, just informational)
    if myAuctions and myAuctions.active > 0 and #tasks == 0 then
        table.insert(tasks, {
            icon   = "Interface\\Icons\\INV_Misc_Coin_17",
            text   = ns.COLORS.GRAY .. myAuctions.active .. " active auction(s) on this character|r",
            sort   = 10,
        })
    end

    -- Transfer items: deposit to warbank or mail to characters that need them
    local todoList = ns.TodoList and ns.TodoList:GetCurrentList()
    if todoList and todoList.tasks then
        local myRealm = myCharKey:match("%-(.+)$") or ""
        for _, item in ipairs(todoList.tasks) do
            if item.status == "pending" and item.source == "unavailable" and item.depositFrom == myCharKey then
                local itemName = item.name or "?"
                local forChar = item.assignedChar and (item.assignedChar:match("^(.-)%-") or item.assignedChar) or "?"
                local targetRealm = item.assignedChar and (item.assignedChar:match("%-(.+)$") or "") or ""
                local sameRealm = myRealm ~= "" and targetRealm ~= "" and ns:RealmMatches(myRealm, targetRealm)

                if sameRealm then
                    table.insert(tasks, {
                        icon   = "Interface\\Icons\\INV_Letter_15",
                        text   = ns.COLORS.YELLOW .. "Mail:|r " .. itemName .. " -> " .. forChar,
                        sort   = 0,
                    })
                else
                    table.insert(tasks, {
                        icon   = "Interface\\Icons\\INV_Misc_Bag_10",
                        text   = ns.COLORS.CYAN .. "Deposit:|r " .. itemName .. " -> " .. forChar,
                        sort   = 0,
                    })
                end
            end
        end
    end

    -- Warbank scan nag: when we have no scan data AT ALL, the scheduler
    -- can't enforce capacity and the overfill warning can't compute a
    -- balance. Ask the user to visit a bank once so we seed the state.
    -- A stale scan is preferred over no scan, so we only nag when the
    -- warbank.freeSlots field is missing entirely.
    if not (ns.db.warbank and type(ns.db.warbank.freeSlots) == "number") then
        table.insert(tasks, {
            icon = "Interface\\Icons\\INV_Misc_Bag_EnchantedRunecloth",
            text = ns.COLORS.YELLOW .. "Visit the warbank|r" ..
                " — FlipQueue needs a scan to plan around its capacity",
            sort = 5,
        })
    end

    table.sort(tasks, function(a, b) return a.sort < b.sort end)
    return tasks
end

-- ==========================================
-- NEXT STEPS (other characters)
-- ==========================================

local function BuildNextStepsData()
    if not ns.db then return {} end

    local data = {}
    local myCharKey = ns:GetCharKey()

    -- 1) Build "Log in" entries from the to-do list (primary source)
    local todoList = ns.TodoList and ns.TodoList:GetCurrentList()
    local depositsByChar = {}  -- charKey -> { count, items }
    local receiverOf = {}      -- receiverCharKey -> { depositorCharKey = true }

    if todoList and todoList.tasks then
        -- Collect deposit dependencies (only pending tasks — posted/skipped are terminal).
        -- Don't require source=="unavailable" — for non-logged-in chars, source may
        -- still reflect the last known state (e.g. "warbank") until RefreshLocations runs.
        for _, item in ipairs(todoList.tasks) do
            if item.status == "pending" and item.depositFrom then
                if not depositsByChar[item.depositFrom] then
                    depositsByChar[item.depositFrom] = { count = 0, gold = 0 }
                end
                depositsByChar[item.depositFrom].count = depositsByChar[item.depositFrom].count + 1
                depositsByChar[item.depositFrom].gold = depositsByChar[item.depositFrom].gold
                    + (ns:ParseGoldValue(item.expectedPrice or "") or 0)

                -- Track dependency: receiver depends on depositor
                if item.assignedChar and item.depositFrom ~= item.assignedChar then
                    if not receiverOf[item.assignedChar] then
                        receiverOf[item.assignedChar] = {}
                    end
                    receiverOf[item.assignedChar][item.depositFrom] = true
                end
            end
        end

        local sortMode = (UI.GetGenSortMode and UI:GetGenSortMode()) or "profit"
        local displayGroups = ns.TodoList:BuildDisplayGroups(todoList.tasks, sortMode)

        for _, group in ipairs(displayGroups) do
            if group.charKey and group.charKey ~= myCharKey then
                local name = group.charName or "?"
                local realm = group.realm or ""
                local charInv = ns.db.characters and ns.db.characters[group.charKey]
                local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
                local remotePrefix = ns.IsRemoteChar and ns:IsRemoteChar(group.charKey) and "|cff8866cc*|r " or ""
                local coloredName = remotePrefix .. "|cff" .. classColor .. name .. "|r"

                -- Check if this character also has deposit tasks
                local depInfo = depositsByChar[group.charKey]
                -- Count buy vs sell items in group
                local groupBuys, groupPosts = 0, 0
                for _, gi in ipairs(group.items) do
                    if gi.action == "buy" then groupBuys = groupBuys + 1 else groupPosts = groupPosts + 1 end
                end
                local detailParts = {}
                if groupPosts > 0 then table.insert(detailParts, groupPosts .. " to post") end
                if groupBuys > 0 then table.insert(detailParts, groupBuys .. " to buy") end
                local detailStr = table.concat(detailParts, ", ")
                if depInfo then
                    detailStr = detailStr .. " + " .. depInfo.count .. " to deposit"
                    depositsByChar[group.charKey] = nil  -- merged, don't create standalone
                end

                local actionVerb = groupBuys > 0 and groupPosts == 0 and "buy" or "post"
                table.insert(data, {
                    action    = ns.COLORS.YELLOW .. "Log in" .. "|r",
                    target    = coloredName .. "  (" .. realm .. ")",
                    itemCount = #group.items + (depInfo and depInfo.count or 0),
                    value     = FormatGoldValue(group.totalGold),
                    detail    = detailStr,
                    _sortValue = group.totalGold,
                    _charKey   = group.charKey,
                    _tooltipText = group.charKey,
                    _tooltipExtra = string.format("Log in to %s to %s %d items\nEstimated value: %s",
                        group.charKey, actionVerb, #group.items, FormatGoldValue(group.totalGold)),
                })
            elseif not group.charKey then
                -- Unassigned group = "Create char" entry
                local realmName = group.realm ~= "" and group.realm or "unknown realm"
                table.insert(data, {
                    action    = "|cffff6666" .. "Create char" .. "|r",
                    target    = realmName,
                    itemCount = #group.items,
                    value     = FormatGoldValue(group.totalGold),
                    detail    = "",
                    _sortValue = -1,  -- always sort last
                    _tooltipText = realmName,
                    _tooltipExtra = string.format("Create a character on %s\n%d items worth ~%s waiting",
                        realmName, #group.items, FormatGoldValue(group.totalGold)),
                })
            end
        end
    end

    -- 2) Standalone deposit entries (depositors not already merged with "Log in")
    for charKey, depInfo in pairs(depositsByChar) do
        if charKey ~= myCharKey then
            local name = charKey:match("^(.-)%-") or charKey
            local realm = charKey:match("%-(.+)$") or ""
            local charInv = ns.db.characters and ns.db.characters[charKey]
            local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
            local remotePrefix = ns.IsRemoteChar and ns:IsRemoteChar(charKey) and "|cff8866cc*|r " or ""
            local coloredName = remotePrefix .. "|cff" .. classColor .. name .. "|r"

            table.insert(data, {
                action    = ns.COLORS.CYAN .. "Deposit" .. "|r",
                target    = coloredName .. "  (" .. realm .. ")",
                itemCount = depInfo.count,
                value     = FormatGoldValue(depInfo.gold),
                detail    = depInfo.count .. " to warbank",
                _sortValue = depInfo.gold,
                _charKey   = charKey,
                _tooltipText = charKey,
                _tooltipExtra = string.format("Log in to %s to deposit %d item(s) to warbank",
                    charKey, depInfo.count),
            })
        end
    end

    -- 3) Other characters with done (expired) auctions — items are in mail
    local auctionsByChar = ns.Tracker and ns.Tracker.GetAuctionSummaryByCharacter
        and ns.Tracker:GetAuctionSummaryByCharacter() or {}

    for charKey, info in pairs(auctionsByChar) do
        if info.done > 0 and charKey ~= myCharKey then
            local name = charKey:match("^(.-)%-") or charKey
            local realm = charKey:match("%-(.+)$") or ""
            local charInv = ns.db.characters[charKey]
            local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
            local remotePrefix = ns.IsRemoteChar and ns:IsRemoteChar(charKey) and "|cff8866cc*|r " or ""
            local coloredName = remotePrefix .. "|cff" .. classColor .. name .. "|r"

            table.insert(data, {
                action    = ns.COLORS.YELLOW .. "Check Mail" .. "|r",
                target    = coloredName .. "  (" .. realm .. ")",
                itemCount = info.done,
                value     = FormatGoldValue(info.totalValue or 0),
                detail    = info.done .. " expired auction(s)",
                _sortValue = -2,
                _charKey   = charKey,
                _tooltipText = charKey,
                _tooltipExtra = string.format("Log in to %s to collect %d expired item(s) from mail%s",
                    charKey, info.done,
                    info.active > 0 and ("\n" .. info.active .. " still active on AH") or ""),
            })
        end
    end

    -- 4) Other characters with auctions expiring soon
    local alertMinutes = ns.db.settings.expiryAlertMinutes or 15
    local alertThreshold = alertMinutes * 60
    for charKey, info in pairs(auctionsByChar) do
        if charKey ~= myCharKey and info.active > 0 and info.soonest and info.soonest < alertThreshold then
            if not (info.done > 0) then
                local name = charKey:match("^(.-)%-") or charKey
                local realm = charKey:match("%-(.+)$") or ""
                local charInv = ns.db.characters[charKey]
                local classColor = charInv and CLASS_COLORS[charInv.class] or "888888"
                local remotePrefix = ns.IsRemoteChar and ns:IsRemoteChar(charKey) and "|cff8866cc*|r " or ""
                local coloredName = remotePrefix .. "|cff" .. classColor .. name .. "|r"

                local h = math.floor(info.soonest / 3600)
                local m = math.floor((info.soonest % 3600) / 60)
                local countdown = h > 0 and (h .. "h " .. m .. "m") or (m .. "m")

                table.insert(data, {
                    action    = ns.COLORS.ORANGE .. "Expiring" .. "|r",
                    target    = coloredName .. "  (" .. realm .. ")",
                    itemCount = info.active,
                    value     = FormatGoldValue(info.totalValue or 0),
                    detail    = ns.COLORS.ORANGE .. countdown .. "|r",
                    _sortValue = 0,
                    _charKey   = charKey,
                    _tooltipText = charKey,
                    _tooltipExtra = string.format("%d active auction(s)\nSoonest expires in %s",
                        info.active, countdown),
                })
            end
        end
    end

    -- Dependency-aware sort: depositors before their receivers, then by gold value
    -- Assign numeric priority: depositors get a boost so they sort first
    local depPriority = {}
    for _, d in ipairs(data) do
        local key = d._charKey
        if key and receiverOf[key] then
            -- This char receives deposits — lower priority (sort later)
            depPriority[key] = (depPriority[key] or 0)
        end
        if key then
            for _, d2 in ipairs(data) do
                local k2 = d2._charKey
                if k2 and receiverOf[k2] and receiverOf[k2][key] then
                    -- This char deposits for someone — higher priority (sort first)
                    depPriority[key] = (depPriority[key] or 0) + 1
                end
            end
        end
    end

    table.sort(data, function(a, b)
        if not a or not b then return a ~= nil end
        local aPri = depPriority[a._charKey] or 0
        local bPri = depPriority[b._charKey] or 0
        if aPri ~= bPri then return aPri > bPri end
        return (a._sortValue or 0) > (b._sortValue or 0)
    end)

    return data
end

-- ==========================================
-- TASK ACTION BUTTONS (complete / skip / delete)
-- ==========================================

local ACTION_BTN_SIZE = 14
local ACTION_BTN_GAP = 1

local function MakeActionBtn(parent, icon, tooltipText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ACTION_BTN_SIZE, ACTION_BTN_SIZE)
    btn:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexture(icon)
    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.3)
    btn._tooltipText = tooltipText
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self._tooltipText, 1, 1, 1)
        GameTooltip:Show()
        parent._actionBtnHovered = true
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        parent._actionBtnHovered = false
        C_Timer.After(0.1, function()
            if not parent._actionBtnHovered and not parent:IsMouseOver() then
                UI.HideTaskActionBtns(parent)
            end
        end)
    end)
    btn:Hide()
    return btn
end

-- Create 3 action buttons on a row frame (idempotent — returns existing if already created).
function UI.SetupTaskActionBtns(row)
    if row._taskActionBtns then return row._taskActionBtns end

    local btns = {}
    btns.delete = MakeActionBtn(row, "Interface\\Buttons\\UI-StopButton", "Delete task")
    btns.delete:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    btns.skip = MakeActionBtn(row, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", "Skip task")
    btns.skip:SetPoint("RIGHT", btns.delete, "LEFT", -ACTION_BTN_GAP, 0)

    btns.complete = MakeActionBtn(row, "Interface\\RaidFrame\\ReadyCheck-Ready", "Mark complete")
    btns.complete:SetPoint("RIGHT", btns.skip, "LEFT", -ACTION_BTN_GAP, 0)

    row._taskActionBtns = btns
    return btns
end

function UI.ShowTaskActionBtns(row)
    if not row._taskActionBtns then return end
    row._taskActionBtns.complete:Show()
    row._taskActionBtns.skip:Show()
    row._taskActionBtns.delete:Show()
end

function UI.HideTaskActionBtns(row)
    if not row._taskActionBtns then return end
    row._taskActionBtns.complete:Hide()
    row._taskActionBtns.skip:Hide()
    row._taskActionBtns.delete:Hide()
end

-- Wire button click handlers to a specific task index.
function UI.WireTaskActionBtns(row, taskIndex, refreshFn)
    local btns = row._taskActionBtns
    if not btns then return end

    btns.complete:SetScript("OnClick", function()
        if ns.TodoList then
            local task = ns.db and ns.db.todoLists and ns.db.todoLists.active
                and ns.db.todoLists.active.tasks[taskIndex]
            local name = task and task.name or "task"
            ns.TodoList:MoveTaskToLog(taskIndex)
            ns:Print(ns.COLORS.GREEN .. "Completed:|r " .. name)
        end
        UI.HideTaskActionBtns(row)
        if refreshFn then refreshFn() end
    end)

    btns.skip:SetScript("OnClick", function()
        if ns.TodoList then
            local task = ns.db and ns.db.todoLists and ns.db.todoLists.active
                and ns.db.todoLists.active.tasks[taskIndex]
            local name = task and task.name or "task"
            ns.TodoList:SkipTask(taskIndex, "manual skip")
            ns:Print(ns.COLORS.ORANGE .. "Skipped:|r " .. name)
        end
        UI.HideTaskActionBtns(row)
        if refreshFn then refreshFn() end
    end)

    btns.delete:SetScript("OnClick", function()
        if ns.TodoList then
            local task = ns.db and ns.db.todoLists and ns.db.todoLists.active
                and ns.db.todoLists.active.tasks[taskIndex]
            local name = task and task.name or "task"
            ns.TodoList:DeleteTask(taskIndex)
            ns:Print(ns.COLORS.RED .. "Deleted:|r " .. name)
        end
        UI.HideTaskActionBtns(row)
        if refreshFn then refreshFn() end
    end)
end

-- ==========================================
-- ASYNC TO-DO GENERATION
-- ==========================================
-- Centralizes the loading-banner + GenerateTodoListAsync glue (FQ-223) so the
-- half-dozen call sites that build a preview don't each freeze the client on a
-- large import. Callers pass the frame to anchor the banner on and a completion
-- handler; onComplete(preview) runs after the banner hides. preview is nil if
-- generation errored. A second call while one is in flight is ignored (returns
-- false) so overlapping generations can't stack banners or duplicate work.
UI._genInFlight = UI._genInFlight or false
function UI:GenerateTodoListWithLoading(parent, source, allocationOrder, opts, onComplete)
    -- Fallback to synchronous if the async engine isn't present (older core).
    if not (ns.TodoList and ns.TodoList.GenerateTodoListAsync) then
        local preview = ns.TodoList
            and ns.TodoList:GenerateTodoList(source, allocationOrder, opts) or nil
        if onComplete then onComplete(preview) end
        return true
    end

    if UI._genInFlight then return false end
    UI._genInFlight = true

    local handle
    if parent and ns.cw and ns.cw.ShowLoading then
        handle = ns.cw:ShowLoading(parent, {
            text = "Generating to-do list…",
            progress = 0,
        })
    end

    ns.TodoList:GenerateTodoListAsync(source, allocationOrder, opts,
        function(processed, total)
            if handle and total and total > 0 then
                handle:SetProgress(processed / total)
                handle:SetText(string.format(
                    "Generating to-do list… %d of %d", processed, total))
            end
        end,
        function(preview)
            UI._genInFlight = false
            if handle then handle:Hide() end
            if onComplete then onComplete(preview) end
        end)
    return true
end

-- ==========================================
-- EXPOSE ON UI TABLE
-- ==========================================

UI._LookupItemInfo = LookupItemInfo
UI._QualityColorName = QualityColorName
UI._CLASS_COLORS = CLASS_COLORS
UI._FormatGoldValue = FormatGoldValue
UI.BuildNextStepsData = BuildNextStepsData
UI.BuildCurrentCharTasks = BuildCurrentCharTasks

-- Auctionator buy-list creation now lives in BuyListSync.lua. Callers should
-- use `ns.BuyListSync:Rebuild(true)` for a manual refresh.
