-- UI/ImportFrame.lua
-- Import dialog for pasting FlippingPal data
local addonName, ns = ...

local UI = ns.UI

local importFrame = CreateFrame("Frame", "FlipQueueImportFrame", UIParent, "BasicFrameTemplateWithInset")
importFrame:SetSize(600, 500)
importFrame:SetPoint("CENTER")
importFrame:SetMovable(true)
importFrame:EnableMouse(true)
importFrame:RegisterForDrag("LeftButton")
importFrame:SetScript("OnDragStart", importFrame.StartMoving)
importFrame:SetScript("OnDragStop", importFrame.StopMovingOrSizing)
importFrame:SetFrameStrata("DIALOG")

importFrame.title = importFrame:CreateFontString(nil, "OVERLAY")
importFrame.title:SetFontObject("GameFontHighlight")
importFrame.title:SetPoint("LEFT", importFrame.TitleBg, "LEFT", 5, 0)
importFrame.title:SetText("FlipQueue - Import")

importFrame.instructions = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
importFrame.instructions:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 15, -35)
importFrame.instructions:SetPoint("TOPRIGHT", importFrame, "TOPRIGHT", -15, -35)
importFrame.instructions:SetJustifyH("LEFT")
importFrame.instructions:SetText("Click below and Ctrl+V to paste FlippingPal data:")

local importScroll = CreateFrame("ScrollFrame", "FlipQueueImportScroll", importFrame, "UIPanelScrollFrameTemplate")
importScroll:SetPoint("TOPLEFT", importFrame, "TOPLEFT", 15, -55)
importScroll:SetPoint("BOTTOMRIGHT", importFrame, "BOTTOMRIGHT", -35, 50)

local importEditBox = CreateFrame("EditBox", "FlipQueueImportEditBox", importScroll)
importEditBox:SetSize(550, 400)
importEditBox:SetMultiLine(true)
importEditBox:SetAutoFocus(false)
importEditBox:SetMaxLetters(0)
importEditBox:SetFontObject("ChatFontNormal")
importEditBox:SetScript("OnEscapePressed", function() importFrame:Hide() end)

-- Auto-detect paste: if text goes from empty to multi-line in one frame, offer quick import
local lastTextLen = 0
importEditBox:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    local text = self:GetText()
    local newLen = #text
    -- Large paste detected (went from <10 chars to >50 chars in one change)
    if lastTextLen < 10 and newLen > 50 and text:find("\n") then
        local items = ns.Import:Parse(text)
        if #items > 0 then
            importFrame.importBtn:SetText("Import (" .. #items .. " items)")
        end
    end
    lastTextLen = newLen
end)

importScroll:SetScrollChild(importEditBox)

-- Import button
importFrame.importBtn = CreateFrame("Button", nil, importFrame, "GameMenuButtonTemplate")
importFrame.importBtn:SetSize(120, 30)
importFrame.importBtn:SetPoint("BOTTOMRIGHT", importFrame, "BOTTOMRIGHT", -15, 10)
importFrame.importBtn:SetText("Import")
importFrame.importBtn:SetScript("OnClick", function()
    local text = importEditBox:GetText()
    if text and text ~= "" then
        local items = ns.Import:Parse(text)
        if #items > 0 then
            local added = ns.Queue:Add(items)
            ns:Print("Imported " .. added .. " new items (" .. #items .. " parsed, duplicates merged).")
            importFrame:Hide()
            importEditBox:SetText("")
            UI:Refresh()
        else
            ns:PrintError("No items found in pasted data.")
        end
    end
end)

-- Clear button
importFrame.clearBtn = CreateFrame("Button", nil, importFrame, "GameMenuButtonTemplate")
importFrame.clearBtn:SetSize(120, 30)
importFrame.clearBtn:SetPoint("BOTTOMLEFT", importFrame, "BOTTOMLEFT", 15, 10)
importFrame.clearBtn:SetText("Clear")
importFrame.clearBtn:SetScript("OnClick", function()
    importEditBox:SetText("")
    importEditBox:SetFocus(true)
end)

-- Auctionator import button
importFrame.auctBtn = CreateFrame("Button", nil, importFrame, "GameMenuButtonTemplate")
importFrame.auctBtn:SetSize(180, 30)
importFrame.auctBtn:SetPoint("BOTTOM", importFrame, "BOTTOM", 0, 10)
importFrame.auctBtn:SetText("From Auctionator List")
importFrame.auctBtn:SetScript("OnClick", function()
    StaticPopupDialogs["FLIPQUEUE_AUCTIONATOR_LIST"] = {
        text = "Enter Auctionator shopping list name:",
        button1 = "Import",
        button2 = "Cancel",
        hasEditBox = true,
        OnAccept = function(self)
            local listName = self.editBox:GetText()
            if listName and listName ~= "" then
                local items = ns.Import:ImportFromAuctionatorList(listName)
                if #items > 0 then
                    local added = ns.Queue:Add(items)
                    ns:Print("Imported " .. added .. " items from Auctionator list '" .. listName .. "'.")
                    importFrame:Hide()
                    UI:Refresh()
                else
                    ns:PrintError("No items found in list '" .. listName .. "'.")
                end
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FLIPQUEUE_AUCTIONATOR_LIST")
end)

importFrame:Hide()

-- Store references for other modules
UI.importFrame = importFrame
UI.importEditBox = importEditBox
