-- UI/AuctionatorFrame.lua
-- Auctionator integration page: shopping list export from queue/inventory
local addonName, ns = ...

local UI = ns.UI

local auctPanel
local auctWidgets = {}

-- Layout constants (match SettingsFrame / TSMFrame)
local LEFT_MARGIN = 12
local RIGHT_MARGIN = -12
local SECTION_SPACING = 14
local ITEM_SPACING = 6
local DESC_COLOR = {0.6, 0.6, 0.6}

--------------------------
-- Helpers
--------------------------

local function IsAuctionatorAvailable()
    return type(Auctionator) == "table"
        and type(Auctionator.API) == "table"
        and type(Auctionator.API.v1) == "table"
end

local function SectionHeader(parent, yOffset, text)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    divider:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)
    divider:SetColorTexture(0.35, 0.35, 0.45, 0.6)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset - 6)
    label:SetTextColor(0.9, 0.8, 0.3)
    label:SetText(text)
    return 22
end

local function CreateActionBtn(label, parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(24)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    btn:SetWidth(btn.text:GetStringWidth() + 20)
    btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.3, 1) end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.15, 0.2, 1) end)
    return btn
end

--------------------------
-- Build Shopping List Items
--------------------------

local function GetQueueItemNames()
    if not ns.db or not ns.db.imports then return {} end
    local names = {}
    local seen = {}
    for _, item in pairs(ns.db.imports.fpScanner or {}) do
        if item.name and item.name ~= "" then
            local lower = item.name:lower()
            if not seen[lower] then
                seen[lower] = true
                table.insert(names, item.name)
            end
        end
    end
    return names
end

local BOUND_TYPES = {
    [1] = true, [4] = true, [7] = true, [8] = true, [9] = true,
}

local function GetInventoryItemNames()
    if not ns.db then return {} end
    local names = {}
    local seen = {}
    for _, charData in pairs(ns.db.characters) do
        if charData.inventory and charData.inventory.items then
            for _, itemData in pairs(charData.inventory.items) do
                if itemData.name and itemData.name ~= ""
                    and not BOUND_TYPES[itemData.bindType or 0]
                    and not itemData.isBound then
                    local lower = itemData.name:lower()
                    if not seen[lower] then
                        seen[lower] = true
                        table.insert(names, itemData.name)
                    end
                end
            end
        end
    end
    if ns.db.warbank and ns.db.warbank.items then
        for _, itemData in pairs(ns.db.warbank.items) do
            if itemData.name and itemData.name ~= ""
                and not BOUND_TYPES[itemData.bindType or 0]
                and not itemData.isBound then
                local lower = itemData.name:lower()
                if not seen[lower] then
                    seen[lower] = true
                    table.insert(names, itemData.name)
                end
            end
        end
    end
    return names
end

--------------------------
-- Get Auctionator Shopping Lists
--------------------------

local function GetShoppingLists()
    return ns:GetAuctionatorListNames()
end

--------------------------
-- Main Panel
--------------------------

function UI:CreateAuctionatorPanel(parent)
    if auctPanel then return auctPanel end

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(scroll:GetWidth())
    content:SetHeight(800)
    scroll:SetScrollChild(content)

    scroll:SetScript("OnSizeChanged", function(sf, w)
        content:SetWidth(w)
    end)

    local y = -6
    local h

    ------------------------------------------------
    -- Status
    ------------------------------------------------

    auctWidgets.status = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    auctWidgets.status:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    y = y - 24

    ------------------------------------------------
    -- Not Installed Message
    ------------------------------------------------

    auctWidgets.notInstalled = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    auctWidgets.notInstalled:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    auctWidgets.notInstalled:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    auctWidgets.notInstalled:SetJustifyH("LEFT")
    auctWidgets.notInstalled:SetWordWrap(true)
    auctWidgets.notInstalled:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    auctWidgets.notInstalled:SetText(
        "Auctionator provides an in-game shopping list feature. When installed, FlipQueue can:\n\n" ..
        "  - Create Auctionator shopping lists from your queue items\n" ..
        "  - Create shopping lists from your full tradeable inventory\n" ..
        "  - Use Auctionator lists as export filters\n\n" ..
        "Install Auctionator from CurseForge to enable these features.")
    y = y - 100

    ------------------------------------------------
    -- Shopping List Export
    ------------------------------------------------

    y = y - SectionHeader(content, y, "Create Shopping List")

    -- List name input
    local nameRow = CreateFrame("Frame", nil, content)
    nameRow:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    nameRow:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    nameRow:SetHeight(44)

    local nameLabel = nameRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", nameRow, "TOPLEFT", 0, 0)
    nameLabel:SetText("List name:")

    local nameBox = CreateFrame("EditBox", nil, nameRow, "InputBoxTemplate")
    nameBox:SetSize(220, 20)
    nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 4, -4)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(100)
    nameBox:SetText("FlipQueue - " .. date("%Y-%m-%d"))
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    auctWidgets.nameBox = nameBox
    y = y - 48

    -- Source toggle: Queue only / Full Inventory
    local sourceLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sourceLabel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    sourceLabel:SetText("Source:")
    y = y - 18

    local sourceFrame = CreateFrame("Frame", nil, content)
    sourceFrame:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    sourceFrame:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    sourceFrame:SetHeight(24)

    local sourceMode = "queue" -- "queue" or "inventory"

    local queueBtn = CreateActionBtn("Queue Items", sourceFrame)
    queueBtn:SetPoint("LEFT", sourceFrame, "LEFT", 0, 0)

    local invBtn = CreateActionBtn("Full Inventory", sourceFrame)
    invBtn:SetPoint("LEFT", queueBtn, "RIGHT", 4, 0)

    local function UpdateSourceButtons()
        if sourceMode == "queue" then
            queueBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
            invBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        else
            queueBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
            invBtn:SetBackdropColor(0.2, 0.4, 0.2, 1)
        end
    end

    queueBtn:SetScript("OnClick", function()
        sourceMode = "queue"
        UpdateSourceButtons()
    end)
    invBtn:SetScript("OnClick", function()
        sourceMode = "inventory"
        UpdateSourceButtons()
    end)
    UpdateSourceButtons()

    auctWidgets.sourceMode = function() return sourceMode end
    y = y - 30

    -- Create List button
    local createBtn = CreateActionBtn("Create Shopping List", content)
    createBtn:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    createBtn:SetWidth(180)
    y = y - 30

    -- Result text
    auctWidgets.result = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    auctWidgets.result:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    auctWidgets.result:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    auctWidgets.result:SetJustifyH("LEFT")
    auctWidgets.result:SetWordWrap(true)
    auctWidgets.result:SetText("")
    y = y - 20

    createBtn:SetScript("OnClick", function()
        if not IsAuctionatorAvailable() then
            auctWidgets.result:SetText("|cffff4444Auctionator is not installed.|r")
            return
        end

        local listName = auctWidgets.nameBox:GetText():match("^%s*(.-)%s*$")
        if listName == "" then
            auctWidgets.result:SetText("|cffff4444Please enter a list name.|r")
            return
        end

        local items
        if auctWidgets.sourceMode() == "queue" then
            items = GetQueueItemNames()
        else
            items = GetInventoryItemNames()
        end

        if #items == 0 then
            auctWidgets.result:SetText("|cffff8800No items found.|r")
            return
        end

        local ok, err = pcall(Auctionator.API.v1.CreateShoppingList, "FlipQueue", listName, items)
        if ok then
            auctWidgets.result:SetText(ns.COLORS.GREEN .. "Created list '" .. listName ..
                "' with " .. #items .. " items.|r")
            UI:RefreshAuctionatorPage()
        else
            auctWidgets.result:SetText("|cffff4444Error: " .. tostring(err) .. "|r")
        end
    end)

    ------------------------------------------------
    -- Available Shopping Lists
    ------------------------------------------------
    y = y - SECTION_SPACING
    y = y - SectionHeader(content, y, "Available Shopping Lists")

    auctWidgets.listInfo = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    auctWidgets.listInfo:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    auctWidgets.listInfo:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    auctWidgets.listInfo:SetJustifyH("LEFT")
    auctWidgets.listInfo:SetWordWrap(true)
    auctWidgets.listInfo:SetSpacing(2)
    y = y - 100

    content:SetHeight(math.abs(y) + 10)

    auctPanel = scroll
    return auctPanel
end

--------------------------
-- Show / Hide / Refresh
--------------------------

function UI:ShowAuctionatorPage()
    if not auctPanel then
        self:CreateAuctionatorPanel(self.tableContainer)
    end
    auctPanel:Show()
    self:RefreshAuctionatorPage()
end

function UI:HideAuctionatorPage()
    if auctPanel then
        auctPanel:Hide()
    end
end

function UI:RefreshAuctionatorPage()
    if not auctWidgets.status then return end

    local available = IsAuctionatorAvailable()

    if available then
        auctWidgets.status:SetText("|cff00ff00Auctionator detected|r")
        auctWidgets.notInstalled:Hide()
    else
        auctWidgets.status:SetText("|cffff4444Auctionator is not installed or not loaded.|r")
        auctWidgets.notInstalled:Show()
    end

    -- Update shopping lists display
    if auctWidgets.listInfo then
        if available then
            local lists = GetShoppingLists()
            if #lists > 0 then
                local lines = {}
                for _, name in ipairs(lists) do
                    lines[#lines + 1] = "|cff00ff00>|r " .. name
                end
                auctWidgets.listInfo:SetText(table.concat(lines, "\n"))
            else
                auctWidgets.listInfo:SetText("|cff888888No shopping lists found.|r")
            end
        else
            auctWidgets.listInfo:SetText("|cff888888Install Auctionator to see shopping lists.|r")
        end
    end
end
