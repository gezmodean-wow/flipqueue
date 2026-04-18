-- UI/ContextDrawer.lua
-- Full-width bottom context-sensitive drawer for the mini view.
-- Replaces ActionDrawer.lua — bank actions are ported here; AH actions
-- delegate to ns.AuctionPost (loaded separately).
local addonName, ns = ...

local UI = ns.UI
local Tracker  -- resolved lazily

--------------------------
-- Session state
--------------------------

ns._automationPaused = false

--------------------------
-- Constants
--------------------------

local THUMB_HEIGHT   = 12
local BTN_HEIGHT     = 18
local BTN_SPACING    = 2
local PAD            = 4
local HEADER_HEIGHT  = 16
local ANIM_DURATION  = 0.15

local DEFAULT_CONTENT_H = HEADER_HEIGHT + PAD + BTN_HEIGHT + PAD  -- 42
local DEFAULT_FULL_H    = DEFAULT_CONTENT_H + THUMB_HEIGHT  -- 54

local BANK_CONTENT_H = HEADER_HEIGHT + PAD + 3 * BTN_HEIGHT + 2 * BTN_SPACING + PAD  -- 82
local BANK_FULL_H    = BANK_CONTENT_H + THUMB_HEIGHT  -- 94

local DRAWER_BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}

local BTN_BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 6,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

--------------------------
-- Context detection
--------------------------

-- ns._serviceState is exported by ToolDrawer.lua (loaded before us).
-- We register for the same events purely to trigger a refresh; the
-- authoritative state lives in the shared table.
local ctxEvt = CreateFrame("Frame")
ctxEvt:RegisterEvent("AUCTION_HOUSE_SHOW")
ctxEvt:RegisterEvent("AUCTION_HOUSE_CLOSED")
ctxEvt:RegisterEvent("BANKFRAME_OPENED")
ctxEvt:RegisterEvent("BANKFRAME_CLOSED")
ctxEvt:RegisterEvent("PLAYER_ENTERING_WORLD")
ctxEvt:SetScript("OnEvent", function()
    -- ToolDrawer updates ns._serviceState before we fire (same event,
    -- but registered first). Just kick our refresh.
    if UI.RefreshContextDrawer then UI:RefreshContextDrawer() end
end)

local function GetContext()
    local ss = ns._serviceState
    if ss and ss.auctionOpen then return "auction" end
    if ss and ss.bankOpen    then return "bank" end
    return "default"
end

--------------------------
-- Drawer frames
--------------------------

local contextClip    = nil   -- clip frame
local contextContent = nil   -- inner backdrop
local contextThumb   = nil   -- bottom grip tab

local currentContext  = nil   -- "bank" | "auction" | "default"
local drawerOpen      = false
local animating       = false
local animTarget      = THUMB_HEIGHT
local currentFullH    = THUMB_HEIGHT  -- recalculated per context

-- Per-context content containers (lazily created)
local bankFrame       = nil
local ahFrame         = nil

-- Button pools
local bankButtons     = {}
local scanRows        = {}
local ownedRows       = {}

-- Scan result storage
local currentScanResults    = {}
local currentOwnedAuctions  = {}

--------------------------
-- Button factory
--------------------------

local function CreateActionButton(parent, label, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(BTN_HEIGHT)
    btn:SetBackdrop(BTN_BACKDROP)
    btn:SetBackdropColor(0.12, 0.14, 0.20, 0.9)
    btn:SetBackdropBorderColor(0.3, 0.35, 0.5, 0.8)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("CENTER")
    btn.label:SetText(label)
    btn.label:SetTextColor(0.85, 0.85, 0.9)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.08)

    btn._tooltip = tooltip
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.22, 0.32, 1)
        if self._tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
            GameTooltip:SetText(self._tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.14, 0.20, 0.9)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)

    return btn
end

--------------------------
-- Bank button actions
--------------------------

local function IsBankOpen()
    return (C_Bank and C_Bank.IsItemCountAvailable) and true or
           (BankFrame and BankFrame:IsShown()) or false
end

-- Forward-declared; set by BuildDefaultContent later in the file.
local _defaultPauseBtn = nil

local function RefreshPauseButton(specificBtn)
    local buttons = {}
    if bankButtons.pause then table.insert(buttons, bankButtons.pause) end
    if specificBtn then table.insert(buttons, specificBtn) end
    if _defaultPauseBtn then table.insert(buttons, _defaultPauseBtn) end
    for _, btn in ipairs(buttons) do
        if ns._automationPaused then
            btn.label:SetText("|cffff8800Resume Automation|r")
            btn._tooltip = "Resume automation (currently paused)"
            btn:SetBackdropBorderColor(0.7, 0.5, 0.2, 0.9)
        else
            btn.label:SetText("Pause Automation")
            btn._tooltip = "Temporarily pause all bank automation"
            btn:SetBackdropBorderColor(0.3, 0.35, 0.5, 0.8)
        end
    end
end

local function DoPause()
    ns._automationPaused = not ns._automationPaused
    RefreshPauseButton()
    ns:Print(ns._automationPaused
        and (ns.COLORS.ORANGE .. "Automation paused.|r")
        or  (ns.COLORS.GREEN  .. "Automation resumed.|r"))
end

local function PostOp()
    if ns.Scanner then ns.Scanner:ScanCurrentCharacter() end
    if ns.TodoList then
        if ns.TodoList.RefreshLocations then ns.TodoList:RefreshLocations() end
        if ns.TodoList.RefreshTaskSteps then ns.TodoList:RefreshTaskSteps() end
    end
    if ns.UI then
        if ns.UI.mainFrame and ns.UI.mainFrame:IsShown() then ns.UI:Refresh() end
        if ns.UI.RefreshMini then ns.UI:RefreshMini() end
    end
end

local function DoPull()
    if not Tracker then Tracker = ns.Tracker end
    if not Tracker then return end
    local ops = Tracker:BuildPullOps()
    if #ops == 0 then ns:Print("Nothing to pull.") return end
    if ns.BankQueue and ns.BankQueue.ProcessSync then
        ns.BankQueue:ProcessSync(ops, "Pulling...", function(success, errors)
            if #success > 0 then ns:Print("Pulled: " .. table.concat(success, ", ")) end
            if errors > 0 then ns:Print(ns.COLORS.YELLOW .. errors .. " pull(s) failed|r") end
            PostOp()
        end)
    end
end

local function DoDeposit()
    if not Tracker then Tracker = ns.Tracker end
    if not Tracker then return end
    local ops = Tracker:BuildDepositOps()
    if #ops == 0 then ns:Print("Nothing to deposit.") return end
    if ns.BankQueue and ns.BankQueue.ProcessSync then
        ns.BankQueue:ProcessSync(ops, "Depositing...", function(success, errors)
            if #success > 0 then ns:Print("Deposited: " .. table.concat(success, ", ")) end
            if errors > 0 then ns:Print(ns.COLORS.YELLOW .. errors .. " deposit(s) failed|r") end
            PostOp()
        end)
    end
end

local function DoExtras()
    if not Tracker then Tracker = ns.Tracker end
    if not Tracker then return end
    local depositSlots = {}
    local depositOps = Tracker:BuildDepositOps()
    for _, op in ipairs(depositOps) do
        depositSlots[op.srcBag .. ":" .. op.srcSlot] = true
    end
    local ops = Tracker:BuildExtraDepositOps(depositSlots)
    if #ops == 0 then ns:Print("No extras to deposit.") return end
    if ns.BankQueue and ns.BankQueue.ProcessSync then
        ns.BankQueue:ProcessSync(ops, "Extras...", function(success, errors)
            if #success > 0 then ns:Print("Extras: " .. table.concat(success, ", ")) end
            if errors > 0 then ns:Print(ns.COLORS.YELLOW .. errors .. " extra(s) failed|r") end
            PostOp()
        end)
    end
end

local function DoPullAll()
    if not Tracker then Tracker = ns.Tracker end
    if not Tracker or not ns.TodoList then return end
    local todoList = ns.TodoList:GetCurrentList()
    if not todoList or not todoList.tasks then ns:Print("No active to-do list.") return end

    local currentRealm = (ns:GetCharKey()):match("%-(.+)$") or GetRealmName()
    local needed = {}
    local defaultQty = ns.db and ns.db.settings.defaultSellQty or 1
    local tsmEnabled = ns.TSM and ns.TSM.IsEnabled and ns.TSM:IsEnabled()

    for _, item in ipairs(todoList.tasks) do
        if item.status == "pending" and item.action ~= "buy"
                and ns:RealmMatches(item.targetRealm or "", currentRealm) then
            local qty = item.quantity or defaultQty
            if tsmEnabled and ns.TSM.GetItemAuctioningOp then
                local ok, op = pcall(ns.TSM.GetItemAuctioningOp, ns.TSM, item.itemKey)
                if ok and op and op.postCap then
                    local cap = tonumber(op.postCap)
                    if cap and cap > 0 then qty = cap end
                end
            end
            local inBags = Tracker._CountInBags and Tracker._CountInBags(item) or 0
            local stillNeeded = qty - inBags
            if stillNeeded > 0 then
                needed[item] = stillNeeded
            end
        end
    end

    if not next(needed) then ns:Print("Nothing to pull (all in bags or no tasks on this realm).") return end

    local allBankTabs = {}
    for _, b in ipairs(ns:GetEnabledBankTabs()) do table.insert(allBankTabs, b) end
    for _, b in ipairs(ns:GetEnabledWarbankTabs()) do table.insert(allBankTabs, b) end

    local ops = {}
    for _, bagIndex in ipairs(allBankTabs) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                        local slotName
                        for queueItem, count in pairs(needed) do
                            if count > 0 then
                                local matched = ns:ItemsMatch(key, nil, queueItem, false, false)
                                if not matched then
                                    if slotName == nil then
                                        slotName = (info.hyperlink:match("|h%[(.-)%]|h")) or false
                                    end
                                    if slotName then
                                        matched = ns:ItemsMatch(key, slotName, queueItem, false, false)
                                    end
                                end
                                if matched then
                                    table.insert(ops, {
                                        op       = "pull",
                                        srcBag   = bagIndex,
                                        srcSlot  = slot,
                                        name     = queueItem.name or "?",
                                        icon     = info.iconFileID,
                                        quantity = info.stackCount or 1,
                                    })
                                    needed[queueItem] = count - (info.stackCount or 1)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #ops == 0 then ns:Print("No matching items in bank.") return end
    ns:Print("Pulling " .. #ops .. " item(s) from bank...")
    if ns.BankQueue and ns.BankQueue.ProcessSync then
        ns.BankQueue:ProcessSync(ops, "Pull All...", function(success, errors)
            if #success > 0 then ns:Print("Pulled: " .. table.concat(success, ", ")) end
            if errors > 0 then ns:Print(ns.COLORS.YELLOW .. errors .. " pull(s) failed|r") end
            PostOp()
        end)
    end
end

local function DoPullGold()
    if not Tracker then Tracker = ns.Tracker end
    if not Tracker or not Tracker.AutoWithdrawGold then return end
    local saved = ns.db and ns.db.settings.autoWithdrawGold
    if ns.db then ns.db.settings.autoWithdrawGold = true end
    Tracker:AutoWithdrawGold()
    if ns.db then ns.db.settings.autoWithdrawGold = saved end
end

local function DoDepositGold()
    if not Tracker then Tracker = ns.Tracker end
    if not Tracker or not Tracker.AutoDepositGold then return end
    local saved = ns.db and ns.db.settings.autoDepositGold
    if ns.db then ns.db.settings.autoDepositGold = true end
    Tracker:AutoDepositGold()
    if ns.db then ns.db.settings.autoDepositGold = saved end
end

--------------------------
-- Gold amount helpers
--------------------------

local function GetWithdrawLabel()
    if not Tracker then Tracker = ns.Tracker end
    if not Tracker or not Tracker.CalculateRequiredGold then return "Withdraw Gold" end
    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
    local ok, totalCopper = pcall(Tracker.CalculateRequiredGold, Tracker, charKey, currentRealm)
    if not ok or not totalCopper or totalCopper <= 0 then return "Withdraw Gold" end
    local estimatedCopper = math.max(10000, math.ceil(totalCopper * 1.1))
    local playerCopper = GetMoney and GetMoney() or 0
    if playerCopper >= estimatedCopper then return "Withdraw Gold: 0g" end
    local shortfall = estimatedCopper - playerCopper
    return "Withdraw Gold: " .. ns:FormatGold(shortfall)
end

local function GetDepositLabel()
    if not Tracker then Tracker = ns.Tracker end
    if not Tracker or not Tracker.CalculateRequiredGold then return "Deposit Earnings" end
    local charKey = ns:GetCharKey()
    local currentRealm = charKey:match("%-(.+)$") or GetRealmName()
    local ok, feesCopper = pcall(Tracker.CalculateRequiredGold, Tracker, charKey, currentRealm)
    if not ok then feesCopper = 0 end
    local bufferCopper = (ns.db and ns.db.settings.goldBuffer or 0) * 10000
    local keepCopper = math.max(10000, math.ceil((feesCopper or 0) * 1.1)) + bufferCopper
    local playerCopper = GetMoney and GetMoney() or 0
    if playerCopper <= keepCopper then return "Deposit Earnings: 0g" end
    local excess = math.floor((playerCopper - keepCopper) / 10000) * 10000
    if excess <= 0 then return "Deposit Earnings: 0g" end
    return "Deposit Earnings: " .. ns:FormatGold(excess)
end

--------------------------
-- Scroll row factory
--------------------------

local ROW_HEIGHT = 34

local function GetOrCreateScanRow(parent, index)
    if scanRows[index] then return scanRows[index] end

    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    row:SetBackdropColor(0.08, 0.08, 0.12, 0.6)
    row:SetBackdropBorderColor(0.2, 0.2, 0.3, 0.5)

    -- Line 1: [icon] Name                          x5
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetTextColor(0.85, 0.85, 0.9)
    row.name:SetWordWrap(false)

    row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.qty:SetPoint("TOPRIGHT", row, "TOPRIGHT", -78, -4)
    row.qty:SetJustifyH("RIGHT")
    row.qty:SetTextColor(0.7, 0.7, 0.7)

    row.name:SetPoint("RIGHT", row.qty, "LEFT", -4, 0)

    -- Line 2: Deal: 500g  Post: 450g  [status]    [Post][Skip]
    row.dealPrice = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.dealPrice:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 3)
    row.dealPrice:SetJustifyH("LEFT")
    row.dealPrice:SetTextColor(0.5, 0.8, 0.5)

    row.postPrice = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.postPrice:SetPoint("LEFT", row.dealPrice, "RIGHT", 6, 0)
    row.postPrice:SetJustifyH("LEFT")
    row.postPrice:SetTextColor(0.9, 0.85, 0.5)

    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.info:SetPoint("LEFT", row.postPrice, "RIGHT", 6, 0)
    row.info:SetJustifyH("LEFT")

    row.postBtn = CreateActionButton(row, "Post", "Post this item", nil)
    row.postBtn:SetSize(34, 14)
    row.postBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -2)

    row.skipBtn = CreateActionButton(row, "Skip", "Skip this item", nil)
    row.skipBtn:SetSize(34, 14)
    row.skipBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)

    row._result = nil
    row:SetScript("OnEnter", function(self)
        local r = self._result
        if not r then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        local numID = tonumber(r.itemID)
        if numID and numID > 0 then
            GameTooltip:SetItemByID(numID)
        else
            GameTooltip:SetText(r.name or "?", 1, 1, 1)
        end
        if r.pricing then
            GameTooltip:AddLine(" ")
            if r.pricing.normalCopper then
                GameTooltip:AddDoubleLine("Post price:", ns:FormatGold(r.pricing.normalCopper), 0.7, 0.7, 0.7, 1, 1, 1)
            end
            if r.pricing.minCopper then
                GameTooltip:AddDoubleLine("Min price:", ns:FormatGold(r.pricing.minCopper), 0.7, 0.7, 0.7, 0.9, 0.7, 0.3)
            end
            if r.pricing.maxCopper then
                GameTooltip:AddDoubleLine("Max price:", ns:FormatGold(r.pricing.maxCopper), 0.7, 0.7, 0.7, 0.9, 0.7, 0.3)
            end
            if r.pricing.opName then
                GameTooltip:AddDoubleLine("TSM operation:", r.pricing.opName, 0.7, 0.7, 0.7, 0.5, 0.7, 1)
            end
            if r.pricing.postCap then
                GameTooltip:AddDoubleLine("Post cap:", tostring(r.pricing.postCap), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
            end
        end
        if r.dealPrice then
            GameTooltip:AddDoubleLine("Deal price:", r.dealPrice, 0.7, 0.7, 0.7, 0.4, 0.9, 0.4)
        end
        if r.status == "below_threshold" then
            GameTooltip:AddLine("Cheapest auction below min price", 1, 0.4, 0.3)
        elseif r.status == "no_price" then
            GameTooltip:AddLine("No TSM pricing data", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    scanRows[index] = row
    return row
end

local function GetOrCreateOwnedRow(parent, index)
    if ownedRows[index] then return ownedRows[index] end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetTextColor(0.85, 0.85, 0.9)

    row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.qty:SetWidth(30)
    row.qty:SetJustifyH("RIGHT")
    row.qty:SetTextColor(0.7, 0.7, 0.7)

    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.price:SetWidth(60)
    row.price:SetJustifyH("RIGHT")
    row.price:SetTextColor(0.9, 0.85, 0.6)

    row.undercut = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.undercut:SetJustifyH("LEFT")
    row.undercut:SetTextColor(1, 0.4, 0.3)

    row.cancelBtn = CreateActionButton(row, "Cancel", "Cancel this auction", nil)
    row.cancelBtn:SetSize(46, ROW_HEIGHT - 2)

    row._auction = nil
    row:SetScript("OnEnter", function(self)
        local a = self._auction
        if not a then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        local numID = tonumber(a.itemID)
        if numID and numID > 0 then
            GameTooltip:SetItemByID(numID)
        else
            GameTooltip:SetText(a.name or "?", 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        if a.totalBuyout then
            GameTooltip:AddDoubleLine("Your price:", ns:FormatGold(a.totalBuyout), 0.7, 0.7, 0.7, 1, 1, 1)
        end
        if a.buyoutPerUnit and a.quantity and a.quantity > 1 then
            GameTooltip:AddDoubleLine("Per unit:", ns:FormatGold(a.buyoutPerUnit), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
        end
        if a.marketPrice then
            GameTooltip:AddDoubleLine("Market (DBMinBuyout):", ns:FormatGold(a.marketPrice), 0.7, 0.7, 0.7, 0.5, 0.8, 1)
        end
        if a.isUndercut then
            local diff = (a.undercutBy and a.undercutBy > 0) and ns:FormatGold(a.undercutBy) or "?"
            GameTooltip:AddLine("Undercut by " .. diff, 1, 0.3, 0.3)
        end
        if a.timeLeft then
            local hrs = math.floor(a.timeLeft / 3600)
            local mins = math.floor((a.timeLeft % 3600) / 60)
            GameTooltip:AddDoubleLine("Time left:", hrs .. "h " .. mins .. "m", 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Anchors: [icon][name...][qty][price][undercut][Cancel]
    row.cancelBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.undercut:SetPoint("RIGHT", row.cancelBtn, "LEFT", -4, 0)
    row.price:SetPoint("RIGHT", row.undercut, "LEFT", -4, 0)
    row.qty:SetPoint("RIGHT", row.price, "LEFT", -4, 0)
    row.name:SetPoint("RIGHT", row.qty, "LEFT", -4, 0)

    ownedRows[index] = row
    return row
end

--------------------------
-- Bank context builder
--------------------------

local bankHeader = nil

local function BuildBankContent(parent)
    if bankFrame then return bankFrame end

    bankFrame = CreateFrame("Frame", nil, parent)
    bankFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -PAD)
    bankFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -PAD)
    bankFrame:SetHeight(BANK_CONTENT_H - PAD)  -- content below top pad

    -- Header
    bankHeader = bankFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bankHeader:SetPoint("TOPLEFT", bankFrame, "TOPLEFT", 0, 0)
    bankHeader:SetText("Bank Operations")
    bankHeader:SetTextColor(1, 1, 1)

    local function RowY(row)
        return -(HEADER_HEIGHT + (row - 1) * (BTN_HEIGHT + BTN_SPACING))
    end

    -- We need to defer width calculation — use OnShow to resize
    local function LayoutButtons()
        local contentW = bankFrame:GetWidth()
        if contentW <= 0 then contentW = 300 end
        local col4W = math.floor((contentW - BTN_SPACING * 3) / 4)
        local col2W = math.floor((contentW - BTN_SPACING) / 2)

        -- Row 1: 4 equal buttons
        if bankButtons.pause then
            bankButtons.pause:SetWidth(col4W)
        end
        if bankButtons.pull then
            bankButtons.pull:SetWidth(col4W)
        end
        if bankButtons.deposit then
            bankButtons.deposit:SetWidth(col4W)
        end
        if bankButtons.extras then
            bankButtons.extras:SetWidth(col4W)
        end

        -- Row 2: 2 half buttons
        if bankButtons.pullGold then
            bankButtons.pullGold:SetWidth(col2W)
        end
        if bankButtons.depGold then
            bankButtons.depGold:SetWidth(col2W)
        end

        -- Row 3: full width
        -- pullAll is anchored left+right so no explicit width needed
    end

    -- Row 1: [Pause] [Pull Items] [Deposit Items] [Deposit Extras]
    bankButtons.pause = CreateActionButton(bankFrame, "Pause Automation",
        "Temporarily pause all bank automation", DoPause)
    bankButtons.pause:SetPoint("TOPLEFT", bankFrame, "TOPLEFT", 0, RowY(1))

    bankButtons.pull = CreateActionButton(bankFrame, "Pull Items",
        "Pull items from bank for current character's tasks", DoPull)
    bankButtons.pull:SetPoint("LEFT", bankButtons.pause, "RIGHT", BTN_SPACING, 0)

    bankButtons.deposit = CreateActionButton(bankFrame, "Deposit Items",
        "Deposit items to warbank for other characters", DoDeposit)
    bankButtons.deposit:SetPoint("LEFT", bankButtons.pull, "RIGHT", BTN_SPACING, 0)

    bankButtons.extras = CreateActionButton(bankFrame, "Deposit Extras",
        "Deposit extra items not needed by current character", DoExtras)
    bankButtons.extras:SetPoint("LEFT", bankButtons.deposit, "RIGHT", BTN_SPACING, 0)

    -- Row 2: [Withdraw Gold: Xg] [Deposit Earnings: Xg]
    bankButtons.pullGold = CreateActionButton(bankFrame, GetWithdrawLabel(),
        "Withdraw gold from warbank for fees + purchases", DoPullGold)
    bankButtons.pullGold:SetPoint("TOPLEFT", bankFrame, "TOPLEFT", 0, RowY(2))

    bankButtons.depGold = CreateActionButton(bankFrame, GetDepositLabel(),
        "Deposit excess gold to warbank", DoDepositGold)
    bankButtons.depGold:SetPoint("LEFT", bankButtons.pullGold, "RIGHT", BTN_SPACING, 0)

    -- Row 3: [Pull Saleable] — full width
    bankButtons.pullAll = CreateActionButton(bankFrame, "Pull Saleable",
        "Pull all queue items from bank (TSM postCap or default qty)", DoPullAll)
    bankButtons.pullAll:SetPoint("TOPLEFT", bankFrame, "TOPLEFT", 0, RowY(3))
    bankButtons.pullAll:SetPoint("RIGHT", bankFrame, "RIGHT", 0, 0)

    bankFrame:SetScript("OnShow", LayoutButtons)
    -- Also lay out immediately if we have width
    C_Timer.After(0, LayoutButtons)

    RefreshPauseButton()
    return bankFrame
end

local function RefreshBankLabels()
    if bankButtons.pullGold then
        bankButtons.pullGold.label:SetText(GetWithdrawLabel())
    end
    if bankButtons.depGold then
        bankButtons.depGold.label:SetText(GetDepositLabel())
    end
    RefreshPauseButton()
end

--------------------------
-- AH context builder
--------------------------

local ahContentFrame = nil
local ahHeader       = nil
local ahScanTodo     = nil
local ahScanAll      = nil
local ahPostAll      = nil
local ahSeparator    = nil
local ahOwnedHeader  = nil
local ahCancelUnder  = nil
local ahNoModule     = nil

local MAX_SCAN_ROWS  = 6
local MAX_OWNED_ROWS = 4

local function CalculateAHHeight()
    -- Header + top row
    local h = HEADER_HEIGHT + BTN_HEIGHT + BTN_SPACING

    -- Scan results
    local scanCount = math.min(#currentScanResults, MAX_SCAN_ROWS)
    if scanCount > 0 then
        h = h + scanCount * ROW_HEIGHT + BTN_SPACING
    end

    -- Post All button (only if scan results exist)
    if #currentScanResults > 0 then
        h = h + BTN_HEIGHT + BTN_SPACING
    end

    -- Separator + owned header
    h = h + 2 + BTN_SPACING + HEADER_HEIGHT + BTN_SPACING

    -- Owned auction rows
    local ownedCount = math.min(#currentOwnedAuctions, MAX_OWNED_ROWS)
    if ownedCount > 0 then
        h = h + ownedCount * ROW_HEIGHT + BTN_SPACING
    end

    -- Cancel Undercuts button
    local hasUndercuts = false
    for _, a in ipairs(currentOwnedAuctions) do
        if a.isUndercut then hasUndercuts = true; break end
    end
    if hasUndercuts then
        h = h + BTN_HEIGHT + BTN_SPACING
    end

    h = h + PAD * 2
    return math.min(h, 400)
end

local function FindDealPrice(itemKey, itemName)
    if not ns.TodoList then return nil end
    local list = ns.TodoList:GetCurrentList()
    if not list or not list.tasks then return nil end
    local lname = itemName and itemName:lower() or nil
    for _, task in ipairs(list.tasks) do
        if task.status == "pending" and task.expectedPrice and task.expectedPrice ~= "" then
            if task.itemKey == itemKey
                or (lname and task.name and task.name:lower() == lname) then
                return task.expectedPrice
            end
        end
    end
    return nil
end

local function RefreshAHScanRows()
    if not ahContentFrame then return end
    local scanCount = math.min(#currentScanResults, MAX_SCAN_ROWS)
    local AP = ns.AuctionPost

    for i = 1, MAX_SCAN_ROWS do
        local row = scanRows[i]
        if row then row:Hide() end
    end

    local yOff = -(HEADER_HEIGHT + BTN_HEIGHT + BTN_SPACING)
    for i = 1, scanCount do
        local row = GetOrCreateScanRow(ahContentFrame, i)
        local result = currentScanResults[i]
        row:SetPoint("TOPLEFT", ahContentFrame, "TOPLEFT", 0, yOff - (i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", ahContentFrame, "RIGHT", 0, 0)

        if result.icon then row.icon:SetTexture(result.icon) end
        row.name:SetText(result.name or "?")
        row.qty:SetText("x" .. (result.postQty or result.totalCount or 1))

        -- Deal price from todo list
        local dealStr = FindDealPrice(result.itemKey, result.name)
        result.dealPrice = dealStr
        row._result = result

        if dealStr then
            row.dealPrice:SetText("|cff88bb88Deal:|r " .. dealStr)
        else
            row.dealPrice:SetText("")
        end

        -- Post price from TSM operation
        local priceCopper = result.pricing and result.pricing.normalCopper
        if priceCopper then
            row.postPrice:SetText("|cffddcc66Post:|r " .. ns:FormatGold(priceCopper))
        else
            row.postPrice:SetText("")
        end

        -- Status info and row coloring
        if result.status == "below_threshold" then
            row.info:SetText("|cffff6644Below min price|r")
            row.name:SetTextColor(0.7, 0.5, 0.5)
            row:SetBackdropBorderColor(0.5, 0.2, 0.2, 0.7)
        elseif result.status == "no_price" then
            row.info:SetText("|cff888888No TSM data|r")
            row.name:SetTextColor(0.6, 0.6, 0.6)
            row:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
        elseif result.status == "dnt" then
            row.info:SetText("|cffff8800Do Not Track|r")
            row.name:SetTextColor(0.6, 0.5, 0.4)
            row:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.7)
        else
            row.info:SetText("")
            row.name:SetTextColor(0.85, 0.85, 0.9)
            row:SetBackdropBorderColor(0.2, 0.2, 0.3, 0.5)
        end

        -- Disable Post for non-ready items
        if result.status ~= "ready" then
            row.postBtn:Disable()
            row.postBtn.label:SetTextColor(0.4, 0.4, 0.4)
        else
            row.postBtn:Enable()
            row.postBtn.label:SetTextColor(0.85, 0.85, 0.9)
        end

        local capturedI = i
        row.postBtn:SetScript("OnClick", function()
            local ap = ns.AuctionPost
            if ap and ap.PostItem then
                ap:PostItem(result, function(ok)
                    if ok then
                        table.remove(currentScanResults, capturedI)
                        RefreshAHScanRows()
                    end
                end)
            end
        end)
        row.skipBtn:SetScript("OnClick", function()
            table.remove(currentScanResults, capturedI)
            RefreshAHScanRows()
        end)
        row:Show()
    end
end

local function RefreshAHOwnedRows()
    if not ahContentFrame then return end
    local ownedCount = math.min(#currentOwnedAuctions, MAX_OWNED_ROWS)
    local AP = ns.AuctionPost

    for i = 1, MAX_OWNED_ROWS do
        local row = ownedRows[i]
        if row then row:Hide() end
    end

    if not ahOwnedHeader then return end

    ahOwnedHeader:SetText("Your Auctions (" .. #currentOwnedAuctions .. ")")

    -- Position owned rows below the separator
    for i = 1, ownedCount do
        local row = GetOrCreateOwnedRow(ahContentFrame, i)
        local auction = currentOwnedAuctions[i]

        if auction.icon then row.icon:SetTexture(auction.icon) end
        row.name:SetText(auction.name or "?")
        row.qty:SetText(auction.quantity and ("x" .. auction.quantity) or "")
        row.price:SetText(auction.buyoutPerUnit and ns:FormatGold(auction.buyoutPerUnit) or "")

        if auction.isUndercut then
            row.undercut:SetText("|cffff4433undercut|r")
            row.name:SetTextColor(1, 0.5, 0.4)
        else
            row.undercut:SetText("")
            row.name:SetTextColor(0.85, 0.85, 0.9)
        end

        row._auction = auction

        local capturedI = i
        row.cancelBtn:SetScript("OnClick", function()
            local ap = ns.AuctionPost
            if ap and ap.CancelAuction and auction.auctionID then
                ap:CancelAuction(auction.auctionID, function(ok)
                    if ok then
                        table.remove(currentOwnedAuctions, capturedI)
                        RefreshAHOwnedRows()
                    end
                end)
            end
        end)
        row:Show()
    end

    -- Cancel Undercuts button
    local hasUndercuts = false
    for _, a in ipairs(currentOwnedAuctions) do
        if a.isUndercut then hasUndercuts = true; break end
    end
    if ahCancelUnder then
        if hasUndercuts then ahCancelUnder:Show() else ahCancelUnder:Hide() end
    end
end

local function BuildAHContent(parent)
    if ahContentFrame then return ahContentFrame end

    ahContentFrame = CreateFrame("Frame", nil, parent)
    ahContentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -PAD)
    ahContentFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -PAD)
    ahContentFrame:SetHeight(200)

    local AP = ns.AuctionPost

    -- Header
    ahHeader = ahContentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ahHeader:SetPoint("TOPLEFT", ahContentFrame, "TOPLEFT", 0, 0)
    ahHeader:SetText("Auction House")
    ahHeader:SetTextColor(1, 1, 1)

    -- Graceful degradation if AuctionPost not loaded
    if not AP then
        ahNoModule = ahContentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ahNoModule:SetPoint("TOPLEFT", ahHeader, "BOTTOMLEFT", 0, -4)
        ahNoModule:SetText("|cff888888AuctionPost not loaded|r")
        return ahContentFrame
    end

    -- Top row: [Scan To-Do] [Scan All]
    ahScanTodo = CreateActionButton(ahContentFrame, "Scan To-Do",
        "Scan bags for items on your to-do list", function()
            local ap = ns.AuctionPost
            if ap and ap.ScanBags then
                currentScanResults = ap:ScanBags(true) or {}
                RefreshAHScanRows()
                UI:RefreshContextDrawer()
            else
                ns:Print(ns.COLORS.RED .. "AuctionPost module not loaded.|r")
            end
        end)
    ahScanTodo:SetPoint("TOPLEFT", ahContentFrame, "TOPLEFT", 0, -HEADER_HEIGHT)

    ahScanAll = CreateActionButton(ahContentFrame, "Scan All",
        "Scan all bag items for posting", function()
            local ap = ns.AuctionPost
            if ap and ap.ScanBags then
                currentScanResults = ap:ScanBags(false) or {}
                RefreshAHScanRows()
                UI:RefreshContextDrawer()
            else
                ns:Print(ns.COLORS.RED .. "AuctionPost module not loaded.|r")
            end
        end)
    ahScanAll:SetPoint("LEFT", ahScanTodo, "RIGHT", BTN_SPACING, 0)

    -- Post All button (positioned dynamically)
    ahPostAll = CreateActionButton(ahContentFrame, "Post All",
        "Post all scanned items", function()
            local ap = ns.AuctionPost
            if ap and ap.PostAll and #currentScanResults > 0 then
                ap:PostAll(currentScanResults,
                    function(i, total) -- onProgress
                        ahPostAll.label:SetText("Posting " .. i .. "/" .. total)
                    end,
                    function() -- onComplete
                        ahPostAll.label:SetText("Post All")
                        currentScanResults = {}
                        RefreshAHScanRows()
                        UI:RefreshContextDrawer()
                    end
                )
            end
        end)
    ahPostAll:Hide()

    -- Separator
    ahSeparator = ahContentFrame:CreateTexture(nil, "ARTWORK")
    ahSeparator:SetHeight(1)
    ahSeparator:SetColorTexture(0.3, 0.3, 0.4, 0.6)

    -- Owned header
    ahOwnedHeader = ahContentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ahOwnedHeader:SetText("Your Auctions (0)")
    ahOwnedHeader:SetTextColor(1, 1, 1)

    -- Cancel Undercuts
    ahCancelUnder = CreateActionButton(ahContentFrame, "Cancel Undercuts",
        "Cancel all undercut auctions", function()
            local AP = ns.AuctionPost
            if AP and AP.CancelAuction then
                local toCancel = {}
                for _, a in ipairs(currentOwnedAuctions) do
                    if a.isUndercut and a.auctionID then
                        table.insert(toCancel, a)
                    end
                end
                for _, a in ipairs(toCancel) do
                    AP:CancelAuction(a.auctionID, function() end)
                end
                -- Re-fetch after a short delay
                C_Timer.After(0.5, function()
                    if AP and AP.GetOwnedAuctions then
                        currentOwnedAuctions = AP:GetOwnedAuctions() or {}
                    end
                    RefreshAHOwnedRows()
                    UI:RefreshContextDrawer()
                end)
            end
        end)
    ahCancelUnder:Hide()

    -- Width layout
    local function LayoutAH()
        local contentW = ahContentFrame:GetWidth()
        if contentW <= 0 then contentW = 300 end
        local col2W = math.floor((contentW - BTN_SPACING) / 2)

        ahScanTodo:SetWidth(col2W)
        ahScanAll:SetWidth(col2W)

        -- Dynamic vertical layout
        local yOff = -(HEADER_HEIGHT + BTN_HEIGHT + BTN_SPACING)

        local scanCount = math.min(#currentScanResults, MAX_SCAN_ROWS)
        yOff = yOff - scanCount * ROW_HEIGHT
        if scanCount > 0 then yOff = yOff - BTN_SPACING end

        if #currentScanResults > 0 then
            ahPostAll:SetPoint("TOPLEFT", ahContentFrame, "TOPLEFT", 0, yOff)
            ahPostAll:SetPoint("RIGHT", ahContentFrame, "RIGHT", 0, 0)
            ahPostAll:Show()
            yOff = yOff - BTN_HEIGHT - BTN_SPACING
        else
            ahPostAll:Hide()
        end

        -- Separator
        ahSeparator:SetPoint("TOPLEFT", ahContentFrame, "TOPLEFT", 0, yOff)
        ahSeparator:SetPoint("RIGHT", ahContentFrame, "RIGHT", 0, 0)
        yOff = yOff - 2 - BTN_SPACING

        -- Owned header
        ahOwnedHeader:SetPoint("TOPLEFT", ahContentFrame, "TOPLEFT", 0, yOff)
        yOff = yOff - HEADER_HEIGHT - BTN_SPACING

        -- Owned rows
        local ownedCount = math.min(#currentOwnedAuctions, MAX_OWNED_ROWS)
        for i = 1, ownedCount do
            local row = GetOrCreateOwnedRow(ahContentFrame, i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", ahContentFrame, "TOPLEFT", 0, yOff - (i - 1) * ROW_HEIGHT)
            row:SetPoint("RIGHT", ahContentFrame, "RIGHT", 0, 0)
        end
        yOff = yOff - ownedCount * ROW_HEIGHT
        if ownedCount > 0 then yOff = yOff - BTN_SPACING end

        -- Cancel Undercuts
        local hasUndercuts = false
        for _, a in ipairs(currentOwnedAuctions) do
            if a.isUndercut then hasUndercuts = true; break end
        end
        if hasUndercuts then
            ahCancelUnder:ClearAllPoints()
            ahCancelUnder:SetPoint("TOPLEFT", ahContentFrame, "TOPLEFT", 0, yOff)
            ahCancelUnder:SetPoint("RIGHT", ahContentFrame, "RIGHT", 0, 0)
            ahCancelUnder:Show()
        else
            ahCancelUnder:Hide()
        end
    end

    ahContentFrame:SetScript("OnShow", LayoutAH)
    C_Timer.After(0, LayoutAH)

    -- Fetch owned auctions on first build
    local ap2 = ns.AuctionPost
    if ap2 and ap2.GetOwnedAuctions then
        currentOwnedAuctions = ap2:GetOwnedAuctions() or {}
        RefreshAHOwnedRows()
    end

    return ahContentFrame
end

--------------------------
-- Drawer construction
--------------------------

local function EnsureDrawer()
    if contextClip then return true end

    local mini = _G["FlipQueueMiniFrame"]
    if not mini then return false end

    -- Resolve Tracker now that Core has loaded
    Tracker = ns.Tracker

    -- Clip frame: full width, flush below the mini (no overlap)
    contextClip = CreateFrame("Frame", "FlipQueueContextClip", mini)
    contextClip:SetClipsChildren(true)
    contextClip:SetHeight(THUMB_HEIGHT)
    contextClip:SetPoint("TOPLEFT",  mini, "BOTTOMLEFT",  0, 0)
    contextClip:SetPoint("TOPRIGHT", mini, "BOTTOMRIGHT", 0, 0)
    contextClip:SetFrameStrata("MEDIUM")

    -- Content frame: inner backdrop, anchored to BOTTOM of clip
    contextContent = CreateFrame("Frame", "FlipQueueContextContent", contextClip, "BackdropTemplate")
    contextContent:SetHeight(THUMB_HEIGHT)
    contextContent:SetPoint("BOTTOMLEFT",  contextClip, "BOTTOMLEFT",  0, 0)
    contextContent:SetPoint("BOTTOMRIGHT", contextClip, "BOTTOMRIGHT", 0, 0)
    contextContent:SetBackdrop(DRAWER_BACKDROP)
    contextContent:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
    contextContent:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    -- Thumb (grip tab at bottom)
    contextThumb = CreateFrame("Button", "FlipQueueContextTab", contextContent)
    contextThumb:SetHeight(THUMB_HEIGHT)
    contextThumb:SetPoint("BOTTOMLEFT",  contextContent, "BOTTOMLEFT",  4, 3)
    contextThumb:SetPoint("BOTTOMRIGHT", contextContent, "BOTTOMRIGHT", -4, 3)

    for j = 1, 3 do
        local grip = contextThumb:CreateTexture(nil, "ARTWORK")
        grip:SetHeight(1)
        grip:SetWidth(16)
        grip:SetPoint("CENTER", contextThumb, "CENTER", 0, (j - 2) * 3)
        grip:SetColorTexture(0.4, 0.4, 0.5, 0.6)
    end

    contextThumb.highlight = contextThumb:CreateTexture(nil, "HIGHLIGHT")
    contextThumb.highlight:SetAllPoints()
    contextThumb.highlight:SetColorTexture(1, 1, 1, 0.06)

    contextThumb:SetScript("OnClick", function()
        UI:ToggleContextDrawer()
    end)

    -- Animation via OnUpdate
    local animSpeed = 300 / ANIM_DURATION  -- generous speed for any context
    contextClip:SetScript("OnUpdate", function(self, elapsed)
        if not animating then return end
        local cur = self:GetHeight()
        local diff = animTarget - cur
        local step = animSpeed * elapsed
        if math.abs(diff) <= step then
            self:SetHeight(animTarget)
            animating = false
        else
            self:SetHeight(cur + (diff > 0 and step or -step))
        end
    end)

    return true
end

--------------------------
-- Context switching
--------------------------

local defaultFrame = nil

local function BuildDefaultContent(parent)
    if defaultFrame then return defaultFrame end

    defaultFrame = CreateFrame("Frame", nil, parent)
    defaultFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -PAD)
    defaultFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -PAD)
    defaultFrame:SetHeight(DEFAULT_CONTENT_H - PAD)

    local hdr = defaultFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT", defaultFrame, "TOPLEFT", 0, 0)
    hdr:SetText("|cffffffffFlipQueue|r")

    local pauseBtn = CreateActionButton(defaultFrame, "Pause Automation",
        "Temporarily pause all bank automation", DoPause)
    pauseBtn:SetPoint("TOPLEFT", defaultFrame, "TOPLEFT", 0,
        -(HEADER_HEIGHT + PAD))
    pauseBtn:SetPoint("RIGHT", defaultFrame, "RIGHT", 0, 0)

    defaultFrame._pauseBtn = pauseBtn
    _defaultPauseBtn = pauseBtn
    defaultFrame:SetScript("OnShow", function()
        RefreshPauseButton(pauseBtn)
    end)

    return defaultFrame
end

local function HideAllContextContent()
    if bankFrame then bankFrame:Hide() end
    if ahContentFrame then ahContentFrame:Hide() end
    if defaultFrame then defaultFrame:Hide() end
end

local function ShowContext(ctx)
    HideAllContextContent()

    if ctx == "bank" then
        local bf = BuildBankContent(contextContent)
        bf:Show()
        RefreshBankLabels()
        currentFullH = BANK_FULL_H
        contextContent:SetHeight(BANK_FULL_H)
    elseif ctx == "auction" then
        -- Re-resolve AuctionPost each time (may have loaded late)
        local af = BuildAHContent(contextContent)
        af:Show()
        -- Recalculate AH height based on current data
        local ahH = CalculateAHHeight() + THUMB_HEIGHT
        currentFullH = ahH
        contextContent:SetHeight(ahH)
        -- Refresh scan/owned rows
        RefreshAHScanRows()
        RefreshAHOwnedRows()
    else
        -- default: pause button only
        local df = BuildDefaultContent(contextContent)
        df:Show()
        currentFullH = DEFAULT_FULL_H
        contextContent:SetHeight(DEFAULT_FULL_H)
    end
end

--------------------------
-- Drawer persistence
--------------------------

local function SaveDrawerShown(shown)
    if ns.db and ns.db.settings then
        ns.db.settings.contextDrawerShown = shown and true or false
    end
end

--------------------------
-- Public API (on ns.UI)
--------------------------

function UI:ShowContextDrawer()
    if not EnsureDrawer() then return end
    local mini = _G["FlipQueueMiniFrame"]
    if not mini or not mini:IsShown() then return end

    drawerOpen = true
    animTarget = currentFullH
    animating  = true
    SaveDrawerShown(true)
end

function UI:HideContextDrawer()
    if not contextClip then return end
    drawerOpen = false
    animTarget = THUMB_HEIGHT
    animating  = true
    SaveDrawerShown(false)
end

function UI:ToggleContextDrawer()
    if drawerOpen then
        UI:HideContextDrawer()
    else
        UI:ShowContextDrawer()
    end
end

function UI:IsContextDrawerShown()
    return drawerOpen
end

function UI:UpdateContextDrawerWidth()
    -- The clip frame is anchored TOPLEFT/TOPRIGHT to the mini so width
    -- follows automatically. Content is anchored BOTTOMLEFT/BOTTOMRIGHT
    -- to the clip so it also auto-sizes. We just need to trigger a re-layout
    -- of the current context's buttons.
    if bankFrame and bankFrame:IsShown() then
        local handler = bankFrame:GetScript("OnShow")
        if handler then handler(bankFrame) end
    end
    if ahContentFrame and ahContentFrame:IsShown() then
        local handler = ahContentFrame:GetScript("OnShow")
        if handler then handler(ahContentFrame) end
    end
end

function UI:RefreshContextDrawer()
    if not EnsureDrawer() then return end

    -- Lazy-resolve Tracker each refresh in case it loaded after us
    if not Tracker then Tracker = ns.Tracker end

    local mini = _G["FlipQueueMiniFrame"]
    if not mini or not mini:IsShown() then
        if contextClip then contextClip:Hide() end
        return
    end

    contextClip:Show()

    local ctx = GetContext()

    -- Rebuild content only on context change
    if ctx ~= currentContext then
        currentContext = ctx
        ShowContext(ctx)

        -- Restore saved open/closed state or auto-open for non-default
        if ns.db and ns.db.settings then
            local saved = ns.db.settings.contextDrawerShown
            if saved == true then
                drawerOpen = true
                contextClip:SetHeight(currentFullH)
                animTarget = currentFullH
                animating = false
            elseif saved == false then
                drawerOpen = false
                contextClip:SetHeight(THUMB_HEIGHT)
                animTarget = THUMB_HEIGHT
                animating = false
            else
                -- First time: auto-open when a service is detected
                drawerOpen = true
                animTarget = currentFullH
                animating = true
                SaveDrawerShown(true)
            end
        end
    else
        -- Same context, just refresh labels / data
        if ctx == "bank" then
            RefreshBankLabels()
        elseif ctx == "auction" then
            if ahContentFrame and ahContentFrame:IsShown() then
                RefreshAHScanRows()
                RefreshAHOwnedRows()
                -- Recalculate height in case data changed
                local ahH = CalculateAHHeight() + THUMB_HEIGHT
                if ahH ~= currentFullH then
                    currentFullH = ahH
                    contextContent:SetHeight(ahH)
                    if drawerOpen then
                        animTarget = currentFullH
                        animating = true
                    end
                end
            end
        end
    end
end
