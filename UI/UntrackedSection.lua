-- UI/UntrackedSection.lua
-- Shows inventory items not in the queue, with "do not track" management
local addonName, ns = ...

local UI = ns.UI

-- Bind types that should be excluded from untracked display
local BOUND_TYPES = {
    [1] = true,  -- BoP (soulbound)
    [4] = true,  -- Quest
    [7] = true,  -- BtA (Bind to Account)
    [8] = true,  -- BtW (Bind to Warband)
    [9] = true,  -- WuE (Warbound until Equipped) - these are warband-bound
}

--------------------------
-- Gather untracked items
--------------------------

local function GetUntrackedItems()
    if not ns.db then return {} end

    -- Build a set of all item keys and names currently in the queue
    local queuedKeys = {}
    local queuedNames = {}
    for _, item in ipairs(ns.db.queue) do
        queuedKeys[item.itemKey] = true
        if item.name and item.name ~= "" then
            queuedNames[item.name:lower()] = true
        end
    end

    -- Also check the log (recently posted items)
    for _, item in ipairs(ns.db.log) do
        queuedKeys[item.itemKey] = true
        if item.name and item.name ~= "" then
            queuedNames[item.name:lower()] = true
        end
    end

    local untracked = {}

    -- Check current character inventory
    local charKey = ns:GetCharKey()
    local charData = ns.db.inventory[charKey]
    if charData and charData.items then
        for key, itemData in pairs(charData.items) do
            if not queuedKeys[key]
                and not (itemData.name and queuedNames[(itemData.name or ""):lower()])
                and not ns.Queue:IsDoNotTrack(itemData.itemID)
                and not BOUND_TYPES[itemData.bindType or 0]
                and not itemData.isBound then
                table.insert(untracked, {
                    itemKey  = key,
                    itemID   = itemData.itemID,
                    name     = itemData.name or "Unknown",
                    icon     = itemData.icon,
                    quantity = itemData.quantity,
                    source   = charKey,
                    locations = itemData.locations,
                })
            end
        end
    end

    -- Check warbank
    if ns.db.warbank and ns.db.warbank.items then
        for key, itemData in pairs(ns.db.warbank.items) do
            if not queuedKeys[key]
                and not (itemData.name and queuedNames[(itemData.name or ""):lower()])
                and not ns.Queue:IsDoNotTrack(itemData.itemID)
                and not BOUND_TYPES[itemData.bindType or 0]
                and not itemData.isBound then
                -- Avoid duplicates if already found on character
                local found = false
                for _, existing in ipairs(untracked) do
                    if existing.itemKey == key then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(untracked, {
                        itemKey  = key,
                        itemID   = itemData.itemID,
                        name     = itemData.name or "Unknown",
                        icon     = itemData.icon,
                        quantity = itemData.quantity,
                        source   = "Warbank",
                    })
                end
            end
        end
    end

    -- Sort by name
    table.sort(untracked, function(a, b) return a.name:lower() < b.name:lower() end)

    return untracked
end

--------------------------
-- Section: Untracked Items
--------------------------

function UI:RenderUntracked(rowIndex)
    local untracked = GetUntrackedItems()

    if #untracked == 0 then return rowIndex end

    rowIndex = rowIndex + 1
    local collapsed = self:CreateSectionHeader(rowIndex, "untracked",
        "Untracked inventory items", ns.COLORS.GRAY, #untracked)

    if collapsed then return rowIndex end

    -- Hint row
    rowIndex = rowIndex + 1
    local hintRow = self:GetOrCreateRow(rowIndex)
    hintRow.icon:SetTexture(nil)
    hintRow.text:SetText(ns.COLORS.GRAY ..
        "  Right-click: Do Not Track  |  Shift+Right-click: Add to Queue" ..
        ns.COLORS.RESET)
    hintRow:Show()

    for _, item in ipairs(untracked) do
        rowIndex = rowIndex + 1
        local row = self:GetOrCreateRow(rowIndex)

        row.icon:SetTexture(item.icon)
        row.tooltipItemID = item.itemID
        row.tooltipItemName = item.name

        local locStr = ""
        if item.locations then
            local parts = {}
            for loc, qty in pairs(item.locations) do
                table.insert(parts, loc .. ": " .. qty)
            end
            locStr = ns.COLORS.GRAY .. " [" .. table.concat(parts, ", ") .. "]" .. ns.COLORS.RESET
        end

        row.text:SetText(string.format("  %s%s|r (x%d) %s%s|r%s",
            ns.COLORS.WHITE, item.name, item.quantity,
            ns.COLORS.GRAY, item.source, locStr))

        local capturedItem = item
        row:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                if IsShiftKeyDown() then
                    -- Add to queue as a simple item
                    ns.Queue:Add({{
                        itemKey  = capturedItem.itemKey,
                        itemID   = capturedItem.itemID,
                        name     = capturedItem.name,
                        quantity = capturedItem.quantity,
                    }})
                    ns:Print("Added to queue: " .. capturedItem.name)
                else
                    -- Add to do-not-track
                    ns.Queue:AddDoNotTrack(capturedItem.itemID, capturedItem.name)
                    ns:Print("Do not track: " .. capturedItem.name)
                end
                UI:Refresh()
            end
        end)

        row:Show()
    end

    return rowIndex
end

--------------------------
-- Do Not Track Management Frame
--------------------------

local dntFrame

function UI:ShowDoNotTrackFrame()
    if not dntFrame then
        dntFrame = CreateFrame("Frame", "FlipQueueDNTFrame", UIParent, "BasicFrameTemplateWithInset")
        dntFrame:SetSize(400, 400)
        dntFrame:SetPoint("CENTER")
        dntFrame:SetMovable(true)
        dntFrame:EnableMouse(true)
        dntFrame:RegisterForDrag("LeftButton")
        dntFrame:SetScript("OnDragStart", dntFrame.StartMoving)
        dntFrame:SetScript("OnDragStop", dntFrame.StopMovingOrSizing)
        dntFrame:SetFrameStrata("DIALOG")

        dntFrame.title = dntFrame:CreateFontString(nil, "OVERLAY")
        dntFrame.title:SetFontObject("GameFontHighlight")
        dntFrame.title:SetPoint("LEFT", dntFrame.TitleBg, "LEFT", 5, 0)
        dntFrame.title:SetText("FlipQueue - Do Not Track List")

        dntFrame.scrollFrame = CreateFrame("ScrollFrame", nil, dntFrame, "UIPanelScrollFrameTemplate")
        dntFrame.scrollFrame:SetPoint("TOPLEFT", dntFrame, "TOPLEFT", 10, -30)
        dntFrame.scrollFrame:SetPoint("BOTTOMRIGHT", dntFrame, "BOTTOMRIGHT", -30, 40)

        dntFrame.content = CreateFrame("Frame", nil, dntFrame.scrollFrame)
        dntFrame.content:SetSize(340, 1)
        dntFrame.scrollFrame:SetScrollChild(dntFrame.content)

        dntFrame.clearBtn = CreateFrame("Button", nil, dntFrame, "GameMenuButtonTemplate")
        dntFrame.clearBtn:SetSize(120, 24)
        dntFrame.clearBtn:SetPoint("BOTTOMLEFT", dntFrame, "BOTTOMLEFT", 10, 10)
        dntFrame.clearBtn:SetText("Clear All")
        dntFrame.clearBtn:SetNormalFontObject("GameFontNormalSmall")
        dntFrame.clearBtn:SetScript("OnClick", function()
            if ns.db then
                wipe(ns.db.doNotTrack)
                ns:Print("Do Not Track list cleared.")
                UI:RefreshDNTFrame()
                UI:Refresh()
            end
        end)
    end

    dntFrame:Show()
    self:RefreshDNTFrame()
end

function UI:RefreshDNTFrame()
    if not dntFrame or not dntFrame:IsShown() then return end

    -- Clear old rows
    local children = {dntFrame.content:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    if not ns.db then return end

    local rowIndex = 0
    local ROW_HEIGHT = 20

    -- Sort by name for display
    local sorted = {}
    for itemID, nameOrTrue in pairs(ns.db.doNotTrack) do
        local name = type(nameOrTrue) == "string" and nameOrTrue or ("Item " .. itemID)
        table.insert(sorted, {itemID = itemID, name = name})
    end
    table.sort(sorted, function(a, b) return a.name:lower() < b.name:lower() end)

    for _, data in ipairs(sorted) do
        rowIndex = rowIndex + 1
        local row = CreateFrame("Frame", nil, dntFrame.content)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", dntFrame.content, "TOPLEFT", 0, -(rowIndex - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", dntFrame.content, "RIGHT", 0, 0)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", row, "LEFT", 4, 0)
        text:SetText(ns.COLORS.WHITE .. data.name .. ns.COLORS.RESET ..
            ns.COLORS.GRAY .. " (" .. data.itemID .. ")" .. ns.COLORS.RESET)

        local removeBtn = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
        removeBtn:SetSize(60, 18)
        removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        removeBtn:SetText("Remove")
        removeBtn:SetNormalFontObject("GameFontNormalSmall")
        local capturedID = data.itemID
        removeBtn:SetScript("OnClick", function()
            ns.Queue:RemoveDoNotTrack(capturedID)
            UI:RefreshDNTFrame()
            UI:Refresh()
        end)

        row:Show()
    end

    if rowIndex == 0 then
        local emptyRow = CreateFrame("Frame", nil, dntFrame.content)
        emptyRow:SetHeight(ROW_HEIGHT)
        emptyRow:SetPoint("TOPLEFT", dntFrame.content, "TOPLEFT", 0, 0)
        emptyRow:SetPoint("RIGHT", dntFrame.content, "RIGHT", 0, 0)
        local text = emptyRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", emptyRow, "LEFT", 4, 0)
        text:SetText(ns.COLORS.GRAY .. "No items in Do Not Track list." .. ns.COLORS.RESET)
        emptyRow:Show()
        rowIndex = 1
    end

    dntFrame.content:SetHeight(math.max(1, rowIndex * ROW_HEIGHT))
end
