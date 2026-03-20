-- UI/UntrackedSection.lua
-- Do Not Track management frame
local addonName, ns = ...

local UI = ns.UI

--------------------------
-- Do Not Track Management Frame
--------------------------

local dntFrame

function UI:ShowDoNotTrackFrame()
    if not dntFrame then
        dntFrame = CreateFrame("Frame", "FlipQueueDNTFrame", UIParent, "BackdropTemplate")
        dntFrame:SetSize(400, 400)
        dntFrame:SetPoint("CENTER")
        dntFrame:SetMovable(true)
        dntFrame:EnableMouse(true)
        dntFrame:RegisterForDrag("LeftButton")
        dntFrame:SetScript("OnDragStart", dntFrame.StartMoving)
        dntFrame:SetScript("OnDragStop", dntFrame.StopMovingOrSizing)
        dntFrame:SetFrameStrata("DIALOG")
        dntFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4},
        })
        dntFrame:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        dntFrame:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)

        -- Title bar
        local titleBar = CreateFrame("Frame", nil, dntFrame)
        titleBar:SetHeight(28)
        titleBar:SetPoint("TOPLEFT", dntFrame, "TOPLEFT", 4, -4)
        titleBar:SetPoint("TOPRIGHT", dntFrame, "TOPRIGHT", -4, -4)

        local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
        titleBg:SetAllPoints()
        titleBg:SetColorTexture(0.12, 0.12, 0.18, 1)

        local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
        titleText:SetText(ns.COLORS.YELLOW .. "Do Not Track List" .. ns.COLORS.RESET)

        -- Close button
        local closeBtn = CreateFrame("Button", nil, titleBar)
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        closeBtn:SetScript("OnClick", function() dntFrame:Hide() end)

        -- Scroll area
        dntFrame.scrollFrame = CreateFrame("ScrollFrame", nil, dntFrame, "UIPanelScrollFrameTemplate")
        dntFrame.scrollFrame:SetPoint("TOPLEFT", dntFrame, "TOPLEFT", 8, -36)
        dntFrame.scrollFrame:SetPoint("BOTTOMRIGHT", dntFrame, "BOTTOMRIGHT", -30, 40)

        dntFrame.content = CreateFrame("Frame", nil, dntFrame.scrollFrame)
        dntFrame.content:SetWidth(dntFrame.scrollFrame:GetWidth())
        dntFrame.content:SetHeight(1)
        dntFrame.scrollFrame:SetScrollChild(dntFrame.content)

        dntFrame.scrollFrame:SetScript("OnSizeChanged", function(sf, w)
            dntFrame.content:SetWidth(w)
        end)

        -- Clear All button (dark themed)
        dntFrame.clearBtn = CreateFrame("Button", nil, dntFrame, "BackdropTemplate")
        dntFrame.clearBtn:SetSize(120, 24)
        dntFrame.clearBtn:SetPoint("BOTTOMLEFT", dntFrame, "BOTTOMLEFT", 10, 10)
        dntFrame.clearBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        dntFrame.clearBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        dntFrame.clearBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

        dntFrame.clearBtn.text = dntFrame.clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dntFrame.clearBtn.text:SetPoint("CENTER")
        dntFrame.clearBtn.text:SetText("Clear All")

        dntFrame.clearBtn:SetScript("OnClick", function()
            if ns.db then
                wipe(ns.db.doNotTrack)
                ns:Print("Do Not Track list cleared.")
                UI:RefreshDNTFrame()
                UI:Refresh()
            end
        end)
        dntFrame.clearBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.3, 1)
        end)
        dntFrame.clearBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        end)

        dntFrame:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
                self:SetPropagateKeyboardInput(false)
            else
                self:SetPropagateKeyboardInput(true)
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
        row:EnableMouse(true)

        -- Alternating row background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, rowIndex % 2 == 0 and 0.03 or 0)

        row:SetScript("OnEnter", function(self)
            bg:SetColorTexture(1, 1, 1, 0.08)
        end)
        row:SetScript("OnLeave", function(self)
            bg:SetColorTexture(1, 1, 1, rowIndex % 2 == 0 and 0.03 or 0)
        end)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", row, "LEFT", 6, 0)
        text:SetText(ns.COLORS.WHITE .. data.name .. ns.COLORS.RESET ..
            ns.COLORS.GRAY .. " (" .. data.itemID .. ")" .. ns.COLORS.RESET)

        -- Dark themed remove button
        local removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        removeBtn:SetSize(60, 18)
        removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        removeBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        removeBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        removeBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

        removeBtn.text = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        removeBtn.text:SetPoint("CENTER")
        removeBtn.text:SetText("Remove")

        local capturedID = data.itemID
        removeBtn:SetScript("OnClick", function()
            ns:RemoveDoNotTrack(capturedID)
            UI:RefreshDNTFrame()
            UI:Refresh()
        end)
        removeBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.25, 0.15, 0.15, 1)
        end)
        removeBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        end)

        row:Show()
    end

    if rowIndex == 0 then
        local emptyRow = CreateFrame("Frame", nil, dntFrame.content)
        emptyRow:SetHeight(ROW_HEIGHT)
        emptyRow:SetPoint("TOPLEFT", dntFrame.content, "TOPLEFT", 0, 0)
        emptyRow:SetPoint("RIGHT", dntFrame.content, "RIGHT", 0, 0)
        local text = emptyRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", emptyRow, "LEFT", 6, 0)
        text:SetText(ns.COLORS.GRAY .. "No items in Do Not Track list." .. ns.COLORS.RESET)
        emptyRow:Show()
        rowIndex = 1
    end

    dntFrame.content:SetHeight(math.max(1, rowIndex * ROW_HEIGHT))
end
