-- UI/MiniView.lua
-- Compact overlay showing current-character tasks, moveable with action icons
local addonName, ns = ...

local UI = ns.UI
local MINI_ROW_HEIGHT = 18
-- Default width must fit: 16px FQ icon + "FQ Charname-Realm" title +
-- mail icon + 6 × 16px right-side buttons with spacing. Long realm names
-- like "DerRatvonDalaran" push the total header content near 340px.
local MINI_WIDTH_DEFAULT = 340
local MINI_WIDTH_MIN = 200
local MINI_WIDTH_MAX = 500
local COLLAPSED_ROWS = 2
local MAX_MINI_ROWS = 20

--------------------------
-- Mini Frame
--------------------------

local mini = CreateFrame("Frame", "FlipQueueMiniFrame", UIParent, "BackdropTemplate")
mini:SetSize(MINI_WIDTH_DEFAULT, 60)
mini:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200)
mini:SetMovable(true)
mini:SetResizable(true)
mini:SetResizeBounds(MINI_WIDTH_MIN, 40, MINI_WIDTH_MAX, 600)
mini:EnableMouse(true)
mini:RegisterForDrag("LeftButton")
mini:SetScript("OnDragStart", mini.StartMoving)
mini:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if ns.db then
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.settings.miniPos = {point = point, relPoint = relPoint, x = x, y = y}
    end
end)
mini:SetClampedToScreen(true)
mini:SetFrameStrata("MEDIUM")
mini:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = {left = 3, right = 3, top = 3, bottom = 3},
})
mini:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
mini:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

-- Collapsed state
local miniCollapsed = false

--------------------------
-- Header bar
--------------------------

local header = CreateFrame("Frame", nil, mini)
header:SetHeight(20)
header:SetPoint("TOPLEFT", mini, "TOPLEFT", 4, -4)
header:SetPoint("TOPRIGHT", mini, "TOPRIGHT", -4, -4)

local titleIcon = header:CreateTexture(nil, "ARTWORK")
titleIcon:SetSize(16, 16)
titleIcon:SetPoint("LEFT", header, "LEFT", 2, 0)
titleIcon:SetTexture("Interface\\AddOns\\flipqueue\\Art\\flipqueue-icon")

local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("LEFT", titleIcon, "RIGHT", 3, 0)
titleText:SetText(ns.COLORS.YELLOW .. "FQ" .. ns.COLORS.RESET)

-- Legacy syncDot retained as a hidden fontstring so mailIcon anchor below still works.
-- Actual sync status now lives in the per-partner strip below the header.
local syncDot = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
syncDot:SetPoint("LEFT", titleText, "RIGHT", 4, 0)
syncDot:SetText("")
syncDot:Hide()

-- Icon buttons (right side of header)
local ICON_SIZE = 16
local ICON_SPACING = 2

local function CreateIconButton(parent, icon, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexture(icon)
    btn.tex:SetDesaturated(false)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)

    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(tooltip, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

-- Close button
local closeBtn = CreateIconButton(header, "Interface\\Buttons\\UI-StopButton", "Hide mini view", function()
    mini:Hide()
    if ns.db then ns.db.settings.showMini = false end
end)
closeBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)

-- Open main window button
local mainBtn = CreateIconButton(header, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "Open FlipQueue", function()
    UI.mainFrame:Show()
    UI:Refresh()
end)
mainBtn:SetPoint("RIGHT", closeBtn, "LEFT", -ICON_SPACING, 0)

-- Rescan button
local scanBtn = CreateIconButton(header, "Interface\\Buttons\\UI-RefreshButton", "Rescan bags", function()
    ns.Scanner:ScanCurrentCharacter()
    UI:RefreshMini()
end)
scanBtn:SetPoint("RIGHT", mainBtn, "LEFT", -ICON_SPACING, 0)

-- Transform button (was Import)
local importBtn = CreateIconButton(header, "Interface\\Buttons\\UI-GuildButton-MOTD-Up", "Transform", function()
    UI.currentPage = "transform"
    UI.mainFrame:Show()
    UI:Refresh()
end)
importBtn:SetPoint("RIGHT", scanBtn, "LEFT", -ICON_SPACING, 0)

-- Collapse/expand toggle button
local collapseBtn = CreateIconButton(header, "Interface\\Buttons\\UI-MinusButton-Up", "Collapse", function()
    miniCollapsed = not miniCollapsed
    if ns.db then ns.db.settings.miniCollapsed = miniCollapsed end
    UI:RefreshMini()
end)
collapseBtn:SetPoint("RIGHT", importBtn, "LEFT", -ICON_SPACING, 0)

-- Services drawer toggle button
local servicesBtn = CreateIconButton(header, "Interface\\Icons\\INV_Misc_Gear_02", "Toggle services drawer", function()
    if UI.ToggleServiceDrawer then UI:ToggleServiceDrawer() end
end)
servicesBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -ICON_SPACING, 0)

-- Unread mail indicator (left side, next to title). Hidden when no mail.
local mailIcon = CreateFrame("Frame", nil, header)
mailIcon:SetSize(ICON_SIZE, ICON_SIZE)
mailIcon:SetPoint("LEFT", syncDot, "RIGHT", 4, 0)
mailIcon:EnableMouse(true)
mailIcon.tex = mailIcon:CreateTexture(nil, "ARTWORK")
mailIcon.tex:SetAllPoints()
mailIcon.tex:SetTexture("Interface\\Icons\\INV_Letter_15")
mailIcon:Hide()
mailIcon:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("You have unread mail", 1, 1, 1)
    GameTooltip:AddLine("Visit a mailbox to collect.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
mailIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function UpdateMailIndicator()
    local hasMail = HasNewMail and HasNewMail()
    if hasMail then mailIcon:Show() else mailIcon:Hide() end
end

local mailEvents = CreateFrame("Frame")
mailEvents:RegisterEvent("UPDATE_PENDING_MAIL")
mailEvents:RegisterEvent("MAIL_INBOX_UPDATE")
mailEvents:RegisterEvent("MAIL_CLOSED")
mailEvents:RegisterEvent("MAIL_SHOW")
mailEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
mailEvents:SetScript("OnEvent", UpdateMailIndicator)
-- Run once on load in case mail is already pending.
C_Timer.After(1, UpdateMailIndicator)

-- Resize grip (bottom-right corner)
local resizeGrip = CreateFrame("Button", nil, mini)
resizeGrip:SetSize(12, 12)
resizeGrip:SetPoint("BOTTOMRIGHT", mini, "BOTTOMRIGHT", -2, 2)
resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetScript("OnMouseDown", function()
    mini:StartSizing("RIGHT")
end)
resizeGrip:SetScript("OnMouseUp", function()
    mini:StopMovingOrSizing()
    if ns.db then
        ns.db.settings.miniWidth = math.floor(mini:GetWidth() + 0.5)
    end
    UI:RefreshMini()
end)

--------------------------
-- Partner strip (per-linked-account status, force-sync)
-- Sits at the BOTTOM of the mini overlay, below the task area.
-- Each row has a colored backdrop based on transport:
--   blue  = BNet friend link
--   green = same-BNet local link
--------------------------

local PARTNER_STRIP_ROW_HEIGHT = 18

local partnerStrip = CreateFrame("Frame", nil, mini)
-- Positioned after taskArea creation below; points set once both frames exist.
partnerStrip:SetHeight(1)
partnerStrip:Hide()

local partnerRowPool = {}

local function CreatePartnerStripRow(index)
    local row = CreateFrame("Frame", nil, partnerStrip, "BackdropTemplate")
    row:SetHeight(PARTNER_STRIP_ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", partnerStrip, "TOPLEFT", 2, -(index - 1) * PARTNER_STRIP_ROW_HEIGHT)
    row:SetPoint("RIGHT", partnerStrip, "RIGHT", -2, 0)
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.label:SetJustifyH("LEFT")

    row.syncBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.syncBtn:SetSize(44, 14)
    row.syncBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.syncBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    row.syncBtn:SetBackdropColor(0.12, 0.12, 0.16, 0.9)
    row.syncBtn:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.8)
    row.syncBtn.text = row.syncBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.syncBtn.text:SetPoint("CENTER")
    row.syncBtn.text:SetText("Sync")
    row.syncBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.28, 0.95)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Force a full sync with this partner", 1, 1, 1)
        GameTooltip:Show()
    end)
    row.syncBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.16, 0.9)
        GameTooltip:Hide()
    end)

    row.lastSync = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.lastSync:SetPoint("RIGHT", row.syncBtn, "LEFT", -6, 0)
    row.lastSync:SetJustifyH("RIGHT")
    row.lastSync:SetTextColor(0.85, 0.85, 0.85)

    row:Hide()
    return row
end

local function RefreshPartnerStrip()
    if not (ns.Sync and ns.Sync.GetPartners) then
        partnerStrip:Hide()
        partnerStrip:SetHeight(1)
        return
    end

    -- Collect and sort partners for stable row assignment
    local list = {}
    local whisperSelfName = nil  -- stored "my character" from a whisper partner record
    for uuid, partner in pairs(ns.Sync:GetPartners()) do
        list[#list + 1] = { uuid = uuid, partner = partner }
        if partner.transport == "whisper" and partner.myCharName then
            -- Take the first whisper partner's myCharName as the self identity.
            -- All whisper pairs from this account should share the same myCharName
            -- since you can only pair whisper from one character at a time.
            whisperSelfName = whisperSelfName or partner.myCharName
        end
    end
    table.sort(list, function(a, b)
        return (a.partner.label or a.uuid) < (b.partner.label or b.uuid)
    end)

    -- If any partner is local (whisper), prepend a synthetic "self" row so the
    -- user sees both halves of the local pair. The stored myCharName is the
    -- character that established the pair — whisper only works from THAT exact
    -- character, not whoever you happen to be logged in as right now.
    if whisperSelfName then
        -- Determine current character (Name-Realm) for match comparison
        local myName = (UnitName and UnitName("player")) or ""
        local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
        local currentCharName = (myRealm ~= "") and (myName .. "-" .. myRealm) or myName
        local onThisChar = (currentCharName == whisperSelfName)

        table.insert(list, 1, {
            uuid = "__self__",
            partner = {
                label = whisperSelfName,
                transport = "whisper",
                lastFullSync = nil,
            },
            isSelf = true,
            selfOnline = onThisChar,
        })
    end

    if #list == 0 then
        for _, row in ipairs(partnerRowPool) do row:Hide() end
        partnerStrip:Hide()
        partnerStrip:SetHeight(1)
        return
    end

    partnerStrip:Show()
    partnerStrip:SetHeight(#list * PARTNER_STRIP_ROW_HEIGHT + 2)

    for i, entry in ipairs(list) do
        local row = partnerRowPool[i]
        if not row then
            row = CreatePartnerStripRow(i)
            partnerRowPool[i] = row
        end

        local uuid = entry.uuid
        local partner = entry.partner
        local isSelf = entry.isSelf == true
        local pState
        if isSelf then
            pState = entry.selfOnline and "connected" or "disconnected"
        else
            pState = ns.Sync:GetPartnerState(uuid)
        end
        local isConnected = (pState == "connected" or pState == "syncing")
        local isLocal = (partner.transport == "whisper")

        -- Transport-colored backdrop
        if isLocal then
            -- green (same-BNet local link)
            if isConnected then
                row:SetBackdropColor(0.10, 0.30, 0.12, 0.85)
                row:SetBackdropBorderColor(0.25, 0.55, 0.25, 0.9)
            else
                row:SetBackdropColor(0.08, 0.18, 0.10, 0.55)
                row:SetBackdropBorderColor(0.18, 0.35, 0.18, 0.6)
            end
        else
            -- blue (BNet friend link)
            if isConnected then
                row:SetBackdropColor(0.10, 0.20, 0.40, 0.85)
                row:SetBackdropBorderColor(0.25, 0.45, 0.75, 0.9)
            else
                row:SetBackdropColor(0.08, 0.12, 0.22, 0.55)
                row:SetBackdropBorderColor(0.18, 0.25, 0.45, 0.6)
            end
        end

        if isSelf then
            local tag
            if entry.selfOnline then
                tag = "|cffccffccYou|r"
            else
                tag = "|cffffcc66Not on this character|r"
            end
            row.label:SetText("|cffffffff" .. (partner.label or "You") .. "|r  " .. tag)
            row.lastSync:SetText("")
            row.syncBtn:Hide()
        else
            row.syncBtn:Show()
            local stateTag = isConnected and "|cffccffccOnline|r" or "|cffaaaaaaOffline|r"
            row.label:SetText("|cffffffff" .. (partner.label or "Account") .. "|r  " .. stateTag)

            local lastSync = partner.lastFullSync or 0
            if lastSync > 0 then
                row.lastSync:SetText(ns:FormatRelativeTime(lastSync))
            else
                row.lastSync:SetText("—")
            end

            row.syncBtn:SetScript("OnClick", function()
                if ns.Sync and ns.Sync.ForceSyncByUUID then
                    ns.Sync:ForceSyncByUUID(uuid)
                end
            end)
            if isConnected then
                row.syncBtn:Enable()
                row.syncBtn.text:SetTextColor(1, 1, 1)
            else
                row.syncBtn:Disable()
                row.syncBtn.text:SetTextColor(0.45, 0.45, 0.45)
            end
        end

        row:Show()
    end

    -- Hide unused rows
    for i = #list + 1, #partnerRowPool do
        partnerRowPool[i]:Hide()
    end
end

--------------------------
-- Task rows area
--------------------------

local taskArea = CreateFrame("Frame", nil, mini)
taskArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
taskArea:SetPoint("RIGHT", mini, "RIGHT", -4, 0)

-- Partner strip anchors below the task area (set here now that taskArea exists)
partnerStrip:SetPoint("TOPLEFT", taskArea, "BOTTOMLEFT", 0, -2)
partnerStrip:SetPoint("RIGHT", mini, "RIGHT", -4, 0)

-- Services drawer is a separate floating popout managed by UI/ServiceDrawer.lua.
-- It anchors itself to the mini's BOTTOM (centered) and toggles visibility via
-- the header services button. It does NOT extend the mini's height.

local miniRows = {}

local function GetOrCreateMiniRow(index)
    if miniRows[index] then return miniRows[index] end

    local row = CreateFrame("Frame", nil, taskArea)
    row:SetHeight(MINI_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", taskArea, "TOPLEFT", 0, -(index - 1) * MINI_ROW_HEIGHT)
    row:SetPoint("RIGHT", taskArea, "RIGHT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(MINI_ROW_HEIGHT - 2, MINI_ROW_HEIGHT - 2)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 3, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row.tooltipItemID = nil
    row.tooltipItemName = nil

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.tooltipItemID or self.tooltipItemName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local numID = tonumber(self.tooltipItemID)
            if numID and numID > 0 then
                GameTooltip:SetItemByID(numID)
            elseif self.tooltipItemName and self.tooltipItemName ~= "" then
                GameTooltip:SetText(self.tooltipItemName, 1, 1, 1)
                if self.tooltipExtra then
                    GameTooltip:AddLine(self.tooltipExtra, 0.7, 0.7, 0.7, true)
                end
                GameTooltip:Show()
            end
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    miniRows[index] = row
    return row
end

--------------------------
-- Refresh
--------------------------

function UI:RefreshMini()
    if not mini:IsShown() then return end
    if not ns.db then return end
    -- Close detail popup on refresh (data may have changed)
    if detailPopup and detailPopup:IsShown() then
        detailPopup:Hide()
        detailItemKey = nil
    end

    -- Update per-partner status strip (replaces the old single sync dot)
    RefreshPartnerStrip()

    -- Services drawer refresh (it manages its own visibility state)
    if UI.RefreshServiceDrawer then UI:RefreshServiceDrawer() end

    -- Hide all rows and clean up action buttons
    for _, row in ipairs(miniRows) do
        row:Hide()
        row:SetScript("OnMouseDown", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row.tooltipItemID = nil
        row.tooltipItemName = nil
        row.tooltipExtra = nil
        if row._taskActionBtns then
            UI.HideTaskActionBtns(row)
        end
    end

    local charKey = ns:GetCharKey()
    local myRealm = charKey:match("%-(.+)$") or ""
    local charName = charKey:match("^(.-)%-") or charKey
    local fqTitle = ns.COLORS.YELLOW .. "FQ" .. ns.COLORS.RESET .. " |cff888888" .. charName .. "-" .. myRealm .. "|r"

    -- Build bag lookup: item IDs, pet species, and names
    local bagsItemIDs = {}
    local bagsItemKeys = {}
    local bagsPetSpecies = {}
    local bagsItemNames = {}
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
                        local speciesID = itemID:match("^pet:(%d+)") or itemID:match("^pet_(%d+)")
                        if speciesID then
                            bagsPetSpecies[speciesID] = (bagsPetSpecies[speciesID] or 0) + 1
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

    -- Get tasks: prefer TodoList
    local tasks = {}
    local useTodoList = ns.TodoList and ns.TodoList:GetCurrentList()

    if useTodoList then
        local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
        for _, task in ipairs(todoTasks) do
            local isBuyTask = task.item.action == "buy"
            local realmToMatch = isBuyTask and task.item.buyRealm or task.item.targetRealm
            if ns:RealmMatches(realmToMatch or "", myRealm) then
                -- Skip deferred tasks and tasks where another character needs to deposit first
                local isDeferred = task.item.deferredAt and true or false
                local needsOtherDeposit = task.item.depositFrom and task.item.depositFrom ~= charKey
                if isDeferred or (not isBuyTask and needsOtherDeposit) then
                    -- skip — not actionable here
                else

                local itemNumID = tonumber(task.item.itemID) or tonumber(task.item.itemKey and task.item.itemKey:match("^(%d+)"))
                local itemKey = task.item.itemKey or ""
                local petSpecies = itemKey:match("^pet:(%d+)") or itemKey:match("^pet_(%d+)")
                    or (task.item.itemID and (task.item.itemID:match("^pet:(%d+)") or task.item.itemID:match("^pet_(%d+)")))
                local taskName = task.item.name and task.item.name:lower() or nil
                local inBags = (bagsItemKeys[itemKey] and bagsItemKeys[itemKey] > 0)
                    or (itemNumID and bagsItemIDs[itemNumID] and bagsItemIDs[itemNumID] > 0)
                    or (petSpecies and bagsPetSpecies[petSpecies] and bagsPetSpecies[petSpecies] > 0)
                    or (taskName and bagsItemNames[taskName] and bagsItemNames[taskName] > 0)
                table.insert(tasks, {
                    name     = task.item.name or "?",
                    itemID   = task.item.itemID,
                    itemKey  = task.item.itemKey,
                    price    = isBuyTask and task.item.buyPrice or task.item.expectedPrice,
                    realm    = isBuyTask and task.item.buyRealm or task.item.targetRealm,
                    icon     = task.item.icon,
                    source   = task.item.source,
                    quantity = task.item.quantity or 1,
                    inBags   = inBags,
                    _taskIdx = task.taskIndex,
                    _isTodo  = true,
                    _isBuy   = isBuyTask,
                    _deferred = task.item.deferredAt and true or false,
                    _depositFrom = task.item.depositFrom,
                    _taskItem = task.item,  -- full task data for detail popup
                })
                end -- else (not deferred)
            end
        end
    end

    local rowIndex = 0
    local personalRowEnd = 0  -- tracks end of current character's rows (collapse preserves these)

    -- Count buy vs post tasks (used for title and Auctionator button)
    local buyCount, postCount = 0, 0
    for _, t in ipairs(tasks) do
        if t._isBuy then buyCount = buyCount + 1 else postCount = postCount + 1 end
    end

    -- Pre-check for char tasks (Check Mail, Expiring, etc.)
    local preCharTasks = UI.BuildCurrentCharTasks and UI.BuildCurrentCharTasks() or {}

    if #tasks == 0 then
        local todoPending = useTodoList and ns.TodoList:GetPendingCount() or 0
        if #preCharTasks > 0 then
            titleText:SetText(fqTitle ..
                ns.COLORS.YELLOW .. " - " .. #preCharTasks .. " task(s)" .. ns.COLORS.RESET)
        elseif todoPending > 0 then
            titleText:SetText(fqTitle ..
                ns.COLORS.GRAY .. " - " .. todoPending .. " on other chars" .. ns.COLORS.RESET)
            -- The detail listing of other characters is rendered by the
            -- "Next Steps" section below — this branch used to also render
            -- its own grouped summary in the per-character rows, but that
            -- duplicated Next Steps in a different sort order and confused
            -- users. We just set the title here and let Next Steps render
            -- the actual rows.
        else
            titleText:SetText(fqTitle ..
                ns.COLORS.GRAY .. " - nothing to do" .. ns.COLORS.RESET)
        end
    else
        local titleParts = {}
        if postCount > 0 then table.insert(titleParts, postCount .. " to post") end
        if buyCount > 0 then table.insert(titleParts, buyCount .. " to buy") end
        titleText:SetText(fqTitle ..
            ns.COLORS.GREEN .. " - " .. table.concat(titleParts, ", ") .. ns.COLORS.RESET)

        for _, task in ipairs(tasks) do
            rowIndex = rowIndex + 1
            local row = GetOrCreateMiniRow(rowIndex)

            row.icon:SetTexture(task.icon)
            row.tooltipItemID = task.itemID
            row.tooltipItemName = task.name
            if task._isBuy then
                row.tooltipExtra = "BUY on: " .. (task.realm or "?") .. "  @  " .. (task.price or "?")
            else
                row.tooltipExtra = (task.realm or "") ~= "" and
                    ("Sell on: " .. task.realm .. "  @  " .. (task.price or "?")) or nil
            end

            local priceStr = ""
            if task.price and task.price ~= "" then
                priceStr = ns.COLORS.GREEN .. " " .. task.price .. ns.COLORS.RESET
            end

            -- Status icon and suffix tag
            local statusIcon, statusTag
            if task._isBuy then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t "
                statusTag = ""
            elseif task.inBags then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
                statusTag = ""
            elseif task.source == "warbank" then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t "
                statusTag = ns.COLORS.YELLOW .. " [wb]" .. ns.COLORS.RESET
            elseif task.source == "bank" then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:0|t "
                statusTag = ns.COLORS.BLUE .. " [bank]" .. ns.COLORS.RESET
            elseif task._depositFrom then
                local depName = task._depositFrom:match("^(.-)%-") or task._depositFrom
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t "
                statusTag = ns.COLORS.CYAN .. " [via " .. depName .. "]" .. ns.COLORS.RESET
            elseif task._deferred then
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t "
                statusTag = ns.COLORS.RED .. " [deferred]" .. ns.COLORS.RESET
            else
                statusIcon = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:0|t "
                statusTag = ns.COLORS.RED .. " [not found]" .. ns.COLORS.RESET
            end

            local namePrefix = task._isBuy and (ns.COLORS.CYAN .. "[BUY] " .. ns.COLORS.RESET) or ""
            local qtyStr = (task.quantity or 1) > 1 and (" x" .. (task.quantity or 1)) or ""
            row.text:SetText(statusIcon .. namePrefix .. ns.COLORS.WHITE .. task.name .. qtyStr .. ns.COLORS.RESET .. statusTag .. priceStr)

            -- Action buttons (complete/skip/delete) on mouseover
            local capturedTask = task
            if capturedTask._isTodo and capturedTask._taskIdx then
                local miniRefresh = function()
                    UI:RefreshMini()
                    if UI.mainFrame and UI.mainFrame:IsShown() then UI:Refresh() end
                end
                UI.SetupTaskActionBtns(row)
                UI.WireTaskActionBtns(row, capturedTask._taskIdx, miniRefresh)
                UI.HideTaskActionBtns(row)

                row:SetScript("OnEnter", function(self)
                    UI.ShowTaskActionBtns(self)
                    if self.tooltipItemID or self.tooltipItemName then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        local numID = tonumber(self.tooltipItemID)
                        if numID and numID > 0 then
                            GameTooltip:SetItemByID(numID)
                        elseif self.tooltipItemName and self.tooltipItemName ~= "" then
                            GameTooltip:SetText(self.tooltipItemName, 1, 1, 1)
                            if self.tooltipExtra then
                                GameTooltip:AddLine(self.tooltipExtra, 0.7, 0.7, 0.7, true)
                            end
                            GameTooltip:Show()
                        end
                    end
                end)
                row:SetScript("OnLeave", function(self)
                    self._actionBtnHovered = false
                    C_Timer.After(0.1, function()
                        if not self._actionBtnHovered and not self:IsMouseOver() then
                            GameTooltip:Hide()
                            UI.HideTaskActionBtns(self)
                        end
                    end)
                end)
            else
                UI.HideTaskActionBtns(row)
            end

            -- Left-click: show item detail popup
            -- Right-click: mark posted / Shift+Right: skip
            row:SetScript("OnMouseDown", function(self, button)
                if button == "LeftButton" then
                    UI:ShowItemDetail(capturedTask)
                elseif button == "RightButton" then
                    if capturedTask._isTodo and ns.TodoList then
                        if IsShiftKeyDown() then
                            ns.TodoList:SkipTask(capturedTask._taskIdx, "manual skip")
                            ns:Print(ns.COLORS.ORANGE .. "Skipped:|r " .. capturedTask.name)
                        else
                            ns.TodoList:MoveTaskToLog(capturedTask._taskIdx)
                            ns:Print("Posted: " .. capturedTask.name .. " -> moved to log")
                        end
                    end
                    UI:RefreshMini()
                    if UI.mainFrame and UI.mainFrame:IsShown() then UI:Refresh() end
                end
            end)

            row:Show()
        end
    end

    -- Auctionator shopping list button (when buy tasks exist and Auctionator is loaded)
    if buyCount and buyCount > 0 and type(Auctionator) == "table"
            and type(Auctionator.API) == "table" and type(Auctionator.API.v1) == "table" then
        rowIndex = rowIndex + 1
        local auctRow = GetOrCreateMiniRow(rowIndex)
        auctRow.icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
        auctRow.text:SetText(ns.COLORS.YELLOW .. "Create Auctionator Buy List" .. ns.COLORS.RESET)
        auctRow.tooltipItemID = nil
        auctRow.tooltipItemName = "Create Shopping List"
        auctRow.tooltipExtra = "Create Auctionator shopping lists grouped by realm (" .. buyCount .. " buy items)"
        auctRow:SetScript("OnMouseDown", function()
            local count, result = UI.CreateBuyTaskShoppingList()
            if count then
                ns:Print(ns.COLORS.GREEN .. "Created " .. result .. " with " .. count .. " items.|r")
            else
                ns:Print(ns.COLORS.RED .. "Error: " .. (result or "unknown") .. "|r")
            end
            UI:RefreshMini()
        end)
        auctRow:Show()
    end

    -- Current character tasks (Check Mail, Expiring)
    local charTasks = UI.BuildCurrentCharTasks and UI.BuildCurrentCharTasks() or {}
    if #charTasks > 0 then
        for _, task in ipairs(charTasks) do
            rowIndex = rowIndex + 1
            local row = GetOrCreateMiniRow(rowIndex)
            row.icon:SetTexture(task.icon)
            row.text:SetText(task.text)
            row.tooltipItemID = nil
            row.tooltipItemName = task._dismissible and "Right-click to dismiss" or nil
            row.tooltipExtra = nil
            if task._dismissible and task._onDismiss then
                local capturedDismiss = task._onDismiss
                row:SetScript("OnMouseDown", function(_, button)
                    if button == "RightButton" then
                        capturedDismiss()
                        UI:RefreshMini()
                        if UI.mainFrame and UI.mainFrame:IsShown() then UI:Refresh() end
                    end
                end)
            else
                row:SetScript("OnMouseDown", nil)
            end
            row:Show()
        end
    end

    -- Mark end of personal rows (collapse preserves everything above this point)
    personalRowEnd = rowIndex

    -- Next Steps section (always show — login tasks, expiring auctions, etc.)
    local nextData = UI.BuildNextStepsData and UI.BuildNextStepsData() or {}
    local MAX_MINI_STEPS = 3

    if #nextData > 0 then
        -- Separator row
        rowIndex = rowIndex + 1
        local sepRow = GetOrCreateMiniRow(rowIndex)
        sepRow.icon:SetTexture(nil)
        sepRow.text:SetText(ns.COLORS.GRAY .. "--- Next Steps ---" .. ns.COLORS.RESET)
        sepRow.tooltipItemID = nil
        sepRow.tooltipItemName = nil
        sepRow.tooltipExtra = nil
        sepRow:SetScript("OnMouseDown", nil)
        sepRow:Show()

        for idx = 1, math.min(#nextData, MAX_MINI_STEPS) do
            local step = nextData[idx]
            rowIndex = rowIndex + 1
            local row = GetOrCreateMiniRow(rowIndex)

            row.icon:SetTexture(nil)
            row.tooltipItemID = nil
            row.tooltipItemName = step._tooltipText
            row.tooltipExtra = step._tooltipExtra

            -- Click-to-copy: left-click opens a compact copy popup
            -- pinned below the mini row, pre-populated with the char
            -- name (or realm for "Create char" entries). Uses the
            -- shared UI:GetNextStepCopyText extraction so the mini
            -- and full TodoPage behave identically. Closure captures
            -- this specific row's step data — re-installed on every
            -- refresh since the step index can drift.
            local capturedStep = step
            local capturedRow = row
            row:SetScript("OnMouseDown", function(_, button)
                if button ~= "LeftButton" then return end
                if not UI.ShowCopyBlip or not UI.GetNextStepCopyText then return end
                local text, label = UI:GetNextStepCopyText(capturedStep)
                if text then
                    UI:ShowCopyBlip(text, capturedRow, label)
                end
            end)

            local extraStr = ""
            if step.detail and step.detail ~= "" then
                extraStr = " " .. step.detail
            elseif step.value and step.value ~= "" then
                extraStr = ns.COLORS.GREEN .. " " .. step.value .. ns.COLORS.RESET
            end

            row.text:SetText(step.action .. " " .. step.target ..
                ns.COLORS.GRAY .. " (" .. step.itemCount .. ")" .. ns.COLORS.RESET .. extraStr)
            row:Show()
        end

        if #nextData > MAX_MINI_STEPS then
            rowIndex = rowIndex + 1
            local moreRow = GetOrCreateMiniRow(rowIndex)
            moreRow.icon:SetTexture(nil)
            moreRow.text:SetText(ns.COLORS.GRAY .. "+" .. (#nextData - MAX_MINI_STEPS) ..
                " more... (open /fq)" .. ns.COLORS.RESET)
            moreRow.tooltipItemID = nil
            moreRow.tooltipItemName = nil
            moreRow.tooltipExtra = nil
            moreRow:SetScript("OnMouseDown", nil)
            moreRow:Show()
        end
    elseif #tasks == 0 and (not useTodoList or ns.TodoList:GetPendingCount() == 0) then
        rowIndex = rowIndex + 1
        local row = GetOrCreateMiniRow(rowIndex)
        row.icon:SetTexture(nil)
        row.text:SetText(ns.COLORS.GREEN .. "All done!" .. ns.COLORS.RESET ..
            ns.COLORS.GRAY .. " Time to go shopping!" .. ns.COLORS.RESET)
        row.tooltipItemID = nil
        row.tooltipItemName = nil
        row.tooltipExtra = nil
        row:SetScript("OnMouseDown", nil)
        row:Show()

        -- "Open Generator" clickable row
        rowIndex = rowIndex + 1
        local genRow = GetOrCreateMiniRow(rowIndex)
        genRow.icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
        genRow.text:SetText(ns.COLORS.YELLOW .. "Open To-Do Generator" .. ns.COLORS.RESET)
        genRow.tooltipItemID = nil
        genRow.tooltipItemName = "Open Generator"
        genRow.tooltipExtra = "Click to open the main window on the To-Do Generator page"
        genRow:SetScript("OnMouseDown", function()
            UI.currentPage = "generator"
            UI.mainFrame:Show()
            UI:Refresh()
        end)
        genRow:Show()
    end

    -- Auto-width: measure text and stretch to fit (within bounds)
    local savedWidth = ns.db and ns.db.settings.miniWidth
    local maxTextW = 0
    for i = 1, rowIndex do
        local row = miniRows[i]
        if row and row:IsShown() and row.text then
            local tw = row.text:GetStringWidth()
            local iconW = (row.icon and row.icon:IsShown()) and (MINI_ROW_HEIGHT + 3) or 0
            local totalW = tw + iconW + 12 -- padding
            if totalW > maxTextW then maxTextW = totalW end
        end
    end
    local desiredW = math.max(maxTextW + 12, MINI_WIDTH_MIN)
    if savedWidth and savedWidth >= MINI_WIDTH_MIN then
        desiredW = math.max(desiredW, savedWidth)
    end
    desiredW = math.min(desiredW, MINI_WIDTH_MAX)
    mini:SetWidth(desiredW)

    -- Collapse: hide rows beyond personal tasks, show "+N more" hint
    -- personalRowEnd marks the last row that belongs to the current character's tasks
    local visibleRows = rowIndex
    if miniCollapsed and rowIndex > personalRowEnd then
        for i = personalRowEnd + 1, rowIndex do
            if miniRows[i] then miniRows[i]:Hide() end
        end
        visibleRows = personalRowEnd
        -- Show "+N more" hint
        local hiddenCount = rowIndex - personalRowEnd
        if hiddenCount > 0 then
            visibleRows = visibleRows + 1
            local hintRow = GetOrCreateMiniRow(visibleRows)
            hintRow.icon:SetTexture(nil)
            hintRow.text:SetText(ns.COLORS.GRAY .. "+" .. hiddenCount .. " more... (click + to expand)" .. ns.COLORS.RESET)
            hintRow.tooltipItemID = nil
            hintRow.tooltipItemName = nil
            hintRow.tooltipExtra = nil
            hintRow:SetScript("OnMouseDown", nil)
            hintRow:SetScript("OnEnter", nil)
            hintRow:SetScript("OnLeave", nil)
            if hintRow._taskActionBtns then UI.HideTaskActionBtns(hintRow) end
            hintRow:Show()
        end
    end

    -- Update collapse button icon
    if miniCollapsed then
        collapseBtn.tex:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
        collapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Expand (" .. rowIndex .. " rows)", 1, 1, 1)
            GameTooltip:Show()
        end)
    else
        collapseBtn.tex:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
        collapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Collapse", 1, 1, 1)
            GameTooltip:Show()
        end)
    end

    -- Cap visible rows to prevent going off-screen
    if visibleRows > MAX_MINI_ROWS then
        for i = MAX_MINI_ROWS + 1, visibleRows do
            if miniRows[i] then miniRows[i]:Hide() end
        end
        local truncated = visibleRows - MAX_MINI_ROWS + 1 -- +1 because we replace last visible with hint
        if miniRows[MAX_MINI_ROWS] then
            miniRows[MAX_MINI_ROWS].icon:SetTexture(nil)
            miniRows[MAX_MINI_ROWS].text:SetText(ns.COLORS.GRAY .. "+" .. truncated .. " more..." .. ns.COLORS.RESET)
            miniRows[MAX_MINI_ROWS].tooltipItemID = nil
            miniRows[MAX_MINI_ROWS].tooltipItemName = nil
            miniRows[MAX_MINI_ROWS].tooltipExtra = nil
            miniRows[MAX_MINI_ROWS]:SetScript("OnMouseDown", nil)
            miniRows[MAX_MINI_ROWS]:SetScript("OnEnter", nil)
            miniRows[MAX_MINI_ROWS]:SetScript("OnLeave", nil)
            if miniRows[MAX_MINI_ROWS]._taskActionBtns then UI.HideTaskActionBtns(miniRows[MAX_MINI_ROWS]) end
        end
        visibleRows = MAX_MINI_ROWS
    end

    -- Resize frame to fit content, clamped to screen height.
    -- NB: the services drawer is a separate floating panel and does NOT extend
    -- the mini height — it's anchored to the mini's BOTTOM as a popout.
    local contentHeight = math.max(1, visibleRows) * MINI_ROW_HEIGHT
    taskArea:SetHeight(contentHeight)
    local stripH = partnerStrip:IsShown() and partnerStrip:GetHeight() or 0
    local frameHeight = 24 + stripH + contentHeight + 8
    local maxScreenHeight = UIParent:GetHeight() * 0.8
    mini:SetHeight(math.min(frameHeight, maxScreenHeight))
    resizeGrip:SetShown(not miniCollapsed)
end

--------------------------
-- Position restore & show/hide
--------------------------

function UI:ShowMini()
    if ns.db then
        -- Restore position
        if ns.db.settings.miniPos then
            local p = ns.db.settings.miniPos
            mini:ClearAllPoints()
            mini:SetPoint(p.point or "TOPRIGHT", UIParent, p.relPoint or "TOPRIGHT", p.x or -200, p.y or -200)
        end
        -- Restore width
        if ns.db.settings.miniWidth and ns.db.settings.miniWidth >= MINI_WIDTH_MIN then
            mini:SetWidth(ns.db.settings.miniWidth)
        end
        -- Restore collapsed state
        if ns.db.settings.miniCollapsed then
            miniCollapsed = true
        end
    end
    mini:Show()
    if ns.db then ns.db.settings.showMini = true end
    self:RefreshMini()
end

function UI:HideMini()
    mini:Hide()
    -- The services drawer is a child of mini and hides automatically, but we
    -- explicitly hide it too so its isShown state is clean.
    local sd = _G["FlipQueueServiceDrawer"]
    if sd then sd:Hide() end
    if ns.db then ns.db.settings.showMini = false end
end

function UI:ToggleMini()
    if mini:IsShown() then
        self:HideMini()
    else
        self:ShowMini()
    end
end

UI.miniFrame = mini

--------------------------
-- Bank operations progress rollout (visible even when collapsed)
--------------------------

local progressRollout = CreateFrame("Frame", nil, mini, "BackdropTemplate")
progressRollout:SetHeight(22)
progressRollout:SetPoint("TOPLEFT", mini, "BOTTOMLEFT", 0, 2)
progressRollout:SetPoint("TOPRIGHT", mini, "BOTTOMRIGHT", 0, 2)
progressRollout:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = {left = 3, right = 3, top = 3, bottom = 3},
})
progressRollout:SetBackdropColor(0.05, 0.05, 0.1, 0.9)
progressRollout:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
progressRollout:Hide()

local rolloutBar = CreateFrame("StatusBar", nil, progressRollout)
rolloutBar:SetHeight(12)
rolloutBar:SetPoint("LEFT", progressRollout, "LEFT", 6, 0)
rolloutBar:SetPoint("RIGHT", progressRollout, "RIGHT", -6, 0)
rolloutBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
rolloutBar:SetStatusBarColor(0.26, 0.6, 1)
rolloutBar:SetMinMaxValues(0, 1)
rolloutBar:SetValue(0)

local rolloutBarBg = rolloutBar:CreateTexture(nil, "BACKGROUND")
rolloutBarBg:SetAllPoints()
rolloutBarBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

local rolloutText = rolloutBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rolloutText:SetPoint("CENTER", rolloutBar, "CENTER")

function UI:ShowMiniProgress(current, total, label)
    if not mini:IsShown() then return end
    rolloutBar:SetMinMaxValues(0, total)
    rolloutBar:SetValue(current)
    rolloutText:SetText((label or "Bank ops") .. "  " .. current .. "/" .. total)
    progressRollout:Show()
end

function UI:HideMiniProgress()
    progressRollout:Hide()
end

--------------------------
-- Item Detail Popup (click-to-inspect on left side of mini)
--------------------------

local detailPopup = nil
local detailItemKey = nil  -- currently shown itemKey (toggle on re-click)

local function GetDetailPopup()
    if detailPopup then return detailPopup end

    local f = CreateFrame("Frame", "FlipQueueItemDetail", mini, "BackdropTemplate")
    f:SetWidth(280)
    f:SetFrameStrata("DIALOG")

    -- Anchor based on user setting
    local function ApplyDetailAnchor()
        f:ClearAllPoints()
        local anchor = ns.db and ns.db.settings.detailPopupAnchor or "left"
        if anchor == "right" then
            f:SetPoint("TOPLEFT", mini, "TOPRIGHT", 4, 0)
        else -- "left" (default)
            f:SetPoint("TOPRIGHT", mini, "TOPLEFT", -4, 0)
        end
    end
    f.ApplyAnchor = ApplyDetailAnchor
    ApplyDetailAnchor()
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    f:SetBackdropColor(0.06, 0.06, 0.1, 0.95)
    f:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.9)

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    f.title:SetJustifyH("LEFT")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(14, 14)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:GetHighlightTexture():SetAlpha(0.3)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
        detailItemKey = nil
    end)

    -- Content lines pool
    f.lines = {}
    f.lineCount = 0

    f:Hide()
    detailPopup = f
    return f
end

local function ClearDetailLines(f)
    for _, line in ipairs(f.lines) do line:Hide() end
    f.lineCount = 0
end

local function AddDetailLine(f, text, r, g, b)
    f.lineCount = f.lineCount + 1
    local idx = f.lineCount
    local line = f.lines[idx]
    if not line then
        line = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -26 - (idx - 1) * 14)
        line:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)
        f.lines[idx] = line
    end
    line:SetText(text)
    if r then line:SetTextColor(r, g, b) end
    line:Show()
    return line
end

local function AddDetailSpacer(f)
    AddDetailLine(f, " ")
end

local function FormatCopper(copper)
    if not copper or copper == 0 then return "0g" end
    return math.floor(copper / 10000) .. "g"
end

local function ShowItemDetail(task)
    if not task or not task._taskItem then return end
    local item = task._taskItem
    local f = GetDetailPopup()
    ClearDetailLines(f)

    -- Title: item name with icon
    local qualColor = ITEM_QUALITY_COLORS[item.quality or 1]
    local colorHex = qualColor and qualColor.hex or "|cffffffff"
    f.title:SetText(colorHex .. (item.name or "Unknown") .. "|r")

    -- Section: Location & Assignment
    AddDetailLine(f, ns.COLORS.YELLOW .. "Location & Assignment|r")

    local source = item.source or "unknown"
    if source == "bags" then
        AddDetailLine(f, "  In bags on " .. (item.assignedChar or "?"))
    elseif source == "warbank" then
        AddDetailLine(f, "  In warband bank")
    elseif source == "bank" then
        AddDetailLine(f, "  In personal bank")
    elseif item.depositFrom then
        local depName = item.depositFrom:match("^(.-)%-") or item.depositFrom
        AddDetailLine(f, "  Needs deposit from " .. depName)
    else
        AddDetailLine(f, "  " .. source)
    end

    AddDetailLine(f, "  Assigned to: " .. (item.assignedChar or "unassigned"))

    if item.action == "buy" then
        AddDetailLine(f, "  Action: BUY on " .. (item.buyRealm or "?"))
        if item.buyPrice then AddDetailLine(f, "  Buy price: " .. item.buyPrice) end
    else
        AddDetailLine(f, "  Action: SELL on " .. (item.targetRealm or "?"))
    end

    -- Section: Pricing
    AddDetailSpacer(f)
    AddDetailLine(f, ns.COLORS.YELLOW .. "Pricing|r")
    if item.expectedPrice then
        AddDetailLine(f, "  Expected price: " .. item.expectedPrice)
    end
    if item.profitAmount then
        local profitStr = FormatCopper(item.profitAmount)
        local pctStr = item.profitPct and string.format(" (%.0f%%)", item.profitPct) or ""
        AddDetailLine(f, "  Est. profit: " .. ns.COLORS.GREEN .. profitStr .. pctStr .. "|r")
    end
    if item.saleAvg then
        AddDetailLine(f, "  Regional avg: " .. FormatCopper(item.saleAvg))
    end

    -- Section: Research (if ItemResearch is available)
    if ns.ItemResearch and item.itemKey then
        AddDetailSpacer(f)
        AddDetailLine(f, ns.COLORS.YELLOW .. "Research|r")

        local research = ns.ItemResearch:GetItemResearch(item.itemKey, item.name)
        if research then
            -- Inventory
            if research.totalInventory then
                AddDetailLine(f, "  Total inventory: " .. research.totalInventory)
            end
            if research.inventory then
                for _, inv in ipairs(research.inventory) do
                    local charName = inv.charKey and (inv.charKey:match("^(.-)%-") or inv.charKey) or "?"
                    local locs = {}
                    if inv.locations then
                        if inv.locations.bags and inv.locations.bags > 0 then table.insert(locs, inv.locations.bags .. " bags") end
                        if inv.locations.bank and inv.locations.bank > 0 then table.insert(locs, inv.locations.bank .. " bank") end
                        if inv.locations.warbank and inv.locations.warbank > 0 then table.insert(locs, inv.locations.warbank .. " wb") end
                    end
                    local locStr = #locs > 0 and (" (" .. table.concat(locs, ", ") .. ")") or ""
                    AddDetailLine(f, "    " .. charName .. ": " .. inv.quantity .. locStr)
                end
            end

            -- Sales summary
            if research.salesSummary and research.salesSummary.count > 0 then
                local ss = research.salesSummary
                AddDetailLine(f, "  Sales: " .. ss.count .. " sold, avg " .. FormatCopper(ss.avgPrice))
            end

            -- Failure summary
            if research.failureSummary then
                local fs = research.failureSummary
                local expCount = fs.expiredCount or 0
                local canCount = fs.cancelledCount or 0
                if expCount > 0 or canCount > 0 then
                    local feesStr = fs.totalFeesLost and (" (" .. FormatCopper(fs.totalFeesLost) .. " fees)") or ""
                    AddDetailLine(f, "  Failures: " .. expCount .. " expired, " .. canCount .. " cancelled" .. feesStr, 1, 0.5, 0.5)
                end
            end

            -- Sell rate
            if item.sellRate then
                AddDetailLine(f, "  Sell rate: " .. string.format("%.1f", item.sellRate) .. "/day")
            elseif research.fpDeals then
                for _, deal in ipairs(research.fpDeals) do
                    if deal.sellRate then
                        AddDetailLine(f, "  Sell rate: " .. string.format("%.1f", deal.sellRate) .. "/day")
                        break
                    end
                end
            end
        else
            AddDetailLine(f, "  No research data available", 0.5, 0.5, 0.5)
        end
    end

    -- Resize to fit
    local height = 26 + f.lineCount * 14 + 8
    f:SetHeight(height)
    f:Show()
end

function UI:ShowItemDetail(task)
    if not task or not task.itemKey then
        if detailPopup then detailPopup:Hide() end
        detailItemKey = nil
        return
    end
    -- Toggle: clicking same item closes the popup
    if detailItemKey == task.itemKey and detailPopup and detailPopup:IsShown() then
        detailPopup:Hide()
        detailItemKey = nil
        return
    end
    detailItemKey = task.itemKey
    if detailPopup and detailPopup.ApplyAnchor then detailPopup.ApplyAnchor() end
    ShowItemDetail(task)
end

function UI:HideItemDetail()
    if detailPopup then detailPopup:Hide() end
    detailItemKey = nil
end

--------------------------
-- Hide in combat (optional)
--------------------------

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- entering combat
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- leaving combat
local hiddenForCombat = false

combatFrame:SetScript("OnEvent", function(_, event)
    if not ns.db or not ns.db.settings.hideMiniInCombat then return end
    if event == "PLAYER_REGEN_DISABLED" then
        if mini:IsShown() then
            hiddenForCombat = true
            mini:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if hiddenForCombat then
            hiddenForCombat = false
            mini:Show()
            UI:RefreshMini()
        end
    end
end)

--------------------------
-- Auto-show on login if enabled
--------------------------

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    C_Timer.After(3, function()
        if ns.db and ns.db.settings.showMini then
            UI:ShowMini()
        end
    end)
end)

mini:Hide()

--------------------------
-- Refresh on bag changes
--------------------------

local bagUpdateFrame = CreateFrame("Frame")
bagUpdateFrame:RegisterEvent("BAG_UPDATE_DELAYED")
local bagUpdatePending = false
bagUpdateFrame:SetScript("OnEvent", function()
    if not mini:IsShown() then return end
    if not bagUpdatePending then
        bagUpdatePending = true
        C_Timer.After(0.5, function()
            bagUpdatePending = false
            if mini:IsShown() then
                UI:RefreshMini()
            end
        end)
    end
end)
