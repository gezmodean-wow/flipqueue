-- UI/ActionDrawer.lua
-- Left drawer for quick-action buttons: pause, pull, deposit, extras, pull all, gold ops
local addonName, ns = ...

local UI = ns.UI
local Tracker = ns.Tracker

--------------------------
-- Drawer state
--------------------------

ns._automationPaused = false

local actionClip = nil
local actionInner = nil
local actionThumb = nil

local BTN_HEIGHT = 18
local BTN_SPACING = 2
local DRAWER_PAD = 4
local THUMB_HEIGHT = 12
local NUM_ROWS = 3
local ICON_AREA_HEIGHT = DRAWER_PAD * 2 + NUM_ROWS * BTN_HEIGHT + (NUM_ROWS - 1) * BTN_SPACING
local FULL_HEIGHT = ICON_AREA_HEIGHT + THUMB_HEIGHT
local ANIM_DURATION = 0.15

local drawerOpen = false
local animating = false
local animTarget = THUMB_HEIGHT

local DRAWER_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = {left = 3, right = 3, top = 3, bottom = 3},
}

local actionButtons = {}

local function GetDrawerWidth()
    local m = _G["FlipQueueMiniFrame"]
    if not m then return 170 end
    return math.max(math.floor(m:GetWidth() / 2), 120)
end

--------------------------
-- Button factory
--------------------------

local function CreateActionButton(parent, label, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(BTN_HEIGHT)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
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
-- Button actions
--------------------------

local function IsBankOpen()
    return (C_Bank and C_Bank.IsItemCountAvailable) and true or
           (BankFrame and BankFrame:IsShown()) or false
end

local function RefreshPauseButton()
    local btn = actionButtons.pause
    if not btn then return end
    if ns._automationPaused then
        btn.label:SetText("|cffff8800Unpause|r")
        btn._tooltip = "Resume automation (currently paused)"
        btn:SetBackdropBorderColor(0.7, 0.5, 0.2, 0.9)
    else
        btn.label:SetText("Pause")
        btn._tooltip = "Temporarily pause all bank automation"
        btn:SetBackdropBorderColor(0.3, 0.35, 0.5, 0.8)
    end
end

local function DoPause()
    ns._automationPaused = not ns._automationPaused
    RefreshPauseButton()
    local state = ns._automationPaused and "PAUSED" or "RESUMED"
    ns:Print(ns._automationPaused
        and (ns.COLORS.ORANGE .. "Automation paused.|r")
        or  (ns.COLORS.GREEN .. "Automation resumed.|r"))
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
                                        op = "pull",
                                        srcBag = bagIndex,
                                        srcSlot = slot,
                                        name = queueItem.name or "?",
                                        icon = info.iconFileID,
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
    if not Tracker or not Tracker.AutoWithdrawGold then return end
    local saved = ns.db and ns.db.settings.autoWithdrawGold
    if ns.db then ns.db.settings.autoWithdrawGold = true end
    Tracker:AutoWithdrawGold()
    if ns.db then ns.db.settings.autoWithdrawGold = saved end
end

local function DoDepositGold()
    if not Tracker or not Tracker.AutoDepositGold then return end
    local saved = ns.db and ns.db.settings.autoDepositGold
    if ns.db then ns.db.settings.autoDepositGold = true end
    Tracker:AutoDepositGold()
    if ns.db then ns.db.settings.autoDepositGold = saved end
end

--------------------------
-- Drawer construction
--------------------------

local function EnsureDrawer()
    if actionClip then return true end

    local mini = _G["FlipQueueMiniFrame"]
    if not mini then return false end

    local drawerWidth = GetDrawerWidth()

    actionClip = CreateFrame("Frame", "FlipQueueActionClip", mini)
    actionClip:SetClipsChildren(true)
    actionClip:SetSize(drawerWidth, THUMB_HEIGHT)
    actionClip:SetPoint("TOPLEFT", mini, "BOTTOMLEFT", 0, 3)
    actionClip:SetFrameStrata("MEDIUM")

    actionInner = CreateFrame("Frame", "FlipQueueActionContent", actionClip, "BackdropTemplate")
    actionInner:SetSize(drawerWidth, FULL_HEIGHT)
    actionInner:SetPoint("BOTTOMLEFT", actionClip, "BOTTOMLEFT", 0, 0)
    actionInner:SetPoint("BOTTOMRIGHT", actionClip, "BOTTOMRIGHT", 0, 0)
    actionInner:SetBackdrop(DRAWER_BACKDROP)
    actionInner:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
    actionInner:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    -- Layout: 3 rows of buttons inside actionInner
    local contentW = drawerWidth - DRAWER_PAD * 2
    local col3W = math.floor((contentW - BTN_SPACING * 2) / 3)
    local col2W = math.floor((contentW - BTN_SPACING) / 2)

    local function RowY(row) return -(DRAWER_PAD + (row - 1) * (BTN_HEIGHT + BTN_SPACING)) end

    -- Row 1: [Pause] [Pull Gold] [Dep Gold]
    actionButtons.pause = CreateActionButton(actionInner, "Pause",
        "Temporarily pause all bank automation", DoPause)
    actionButtons.pause:SetPoint("TOPLEFT", actionInner, "TOPLEFT", DRAWER_PAD, RowY(1))
    actionButtons.pause:SetWidth(col3W)

    actionButtons.pullGold = CreateActionButton(actionInner, "Pull Gold",
        "Withdraw gold from warbank for fees + purchases", DoPullGold)
    actionButtons.pullGold:SetPoint("LEFT", actionButtons.pause, "RIGHT", BTN_SPACING, 0)
    actionButtons.pullGold:SetWidth(col3W)

    actionButtons.depGold = CreateActionButton(actionInner, "Dep Gold",
        "Deposit excess gold to warbank", DoDepositGold)
    actionButtons.depGold:SetPoint("LEFT", actionButtons.pullGold, "RIGHT", BTN_SPACING, 0)
    actionButtons.depGold:SetWidth(col3W)

    -- Row 2: [Pull] [Deposit] [Extras]
    actionButtons.pull = CreateActionButton(actionInner, "Pull",
        "Pull items from bank for current character's tasks", DoPull)
    actionButtons.pull:SetPoint("TOPLEFT", actionInner, "TOPLEFT", DRAWER_PAD, RowY(2))
    actionButtons.pull:SetWidth(col3W)

    actionButtons.deposit = CreateActionButton(actionInner, "Deposit",
        "Deposit items to warbank for other characters", DoDeposit)
    actionButtons.deposit:SetPoint("LEFT", actionButtons.pull, "RIGHT", BTN_SPACING, 0)
    actionButtons.deposit:SetWidth(col3W)

    actionButtons.extras = CreateActionButton(actionInner, "Extras",
        "Deposit extra items not needed by current character", DoExtras)
    actionButtons.extras:SetPoint("LEFT", actionButtons.deposit, "RIGHT", BTN_SPACING, 0)
    actionButtons.extras:SetWidth(col3W)

    -- Row 3: [Pull All] (full width)
    actionButtons.pullAll = CreateActionButton(actionInner, "Pull All",
        "Pull all queue items from bank (TSM postCap or default qty)", DoPullAll)
    actionButtons.pullAll:SetPoint("TOPLEFT", actionInner, "TOPLEFT", DRAWER_PAD, RowY(3))
    actionButtons.pullAll:SetPoint("RIGHT", actionInner, "RIGHT", -DRAWER_PAD, 0)

    -- Thumb
    actionThumb = CreateFrame("Button", "FlipQueueActionTab", actionInner)
    actionThumb:SetHeight(THUMB_HEIGHT)
    actionThumb:SetPoint("BOTTOMLEFT", actionInner, "BOTTOMLEFT", 4, 3)
    actionThumb:SetPoint("BOTTOMRIGHT", actionInner, "BOTTOMRIGHT", -4, 3)

    for j = 1, 3 do
        local grip = actionThumb:CreateTexture(nil, "ARTWORK")
        grip:SetHeight(1)
        grip:SetWidth(16)
        grip:SetPoint("CENTER", actionThumb, "CENTER", 0, (j - 2) * 3)
        grip:SetColorTexture(0.4, 0.4, 0.5, 0.6)
    end

    actionThumb.highlight = actionThumb:CreateTexture(nil, "HIGHLIGHT")
    actionThumb.highlight:SetAllPoints()
    actionThumb.highlight:SetColorTexture(1, 1, 1, 0.06)

    actionThumb:SetScript("OnClick", function()
        UI:ToggleActionDrawer()
    end)

    local animSpeed = ICON_AREA_HEIGHT / ANIM_DURATION
    actionClip:SetScript("OnUpdate", function(self, elapsed)
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

    RefreshPauseButton()
    return true
end

local function UpdateDrawerWidth()
    if not actionClip then return end
    local w = GetDrawerWidth()
    actionClip:SetWidth(w)
    actionInner:SetWidth(w)
    actionInner:SetHeight(FULL_HEIGHT)

    local contentW = w - DRAWER_PAD * 2
    local col3W = math.floor((contentW - BTN_SPACING * 2) / 3)

    for _, key in ipairs({"pause", "pullGold", "depGold", "pull", "deposit", "extras"}) do
        if actionButtons[key] then actionButtons[key]:SetWidth(col3W) end
    end
end

--------------------------
-- Public API
--------------------------

local function SaveDrawerShown(shown)
    if ns.db and ns.db.settings then
        ns.db.settings.actionDrawerShown = shown and true or false
    end
end

function UI:ShowActionDrawer()
    if not EnsureDrawer() then return end
    local mini = _G["FlipQueueMiniFrame"]
    if not mini or not mini:IsShown() then return end

    drawerOpen = true
    animTarget = FULL_HEIGHT
    animating = true
    SaveDrawerShown(true)
end

function UI:HideActionDrawer()
    if not actionClip then return end
    drawerOpen = false
    animTarget = THUMB_HEIGHT
    animating = true
    SaveDrawerShown(false)
end

function UI:ToggleActionDrawer()
    if drawerOpen then
        UI:HideActionDrawer()
    else
        UI:ShowActionDrawer()
    end
end

function UI:RefreshActionDrawer()
    if not EnsureDrawer() then return end

    local mini = _G["FlipQueueMiniFrame"]
    if not mini or not mini:IsShown() then
        if actionClip then actionClip:Hide() end
        return
    end

    actionClip:Show()
    UpdateDrawerWidth()

    if ns.db and ns.db.settings then
        local saved = ns.db.settings.actionDrawerShown
        if saved == true and not drawerOpen and not animating then
            drawerOpen = true
            actionClip:SetHeight(FULL_HEIGHT)
            animTarget = FULL_HEIGHT
        elseif (saved == false or saved == nil) and not drawerOpen then
            actionClip:SetHeight(THUMB_HEIGHT)
        end
    end

    RefreshPauseButton()
end

function UI:UpdateActionDrawerWidth()
    UpdateDrawerWidth()
end
