-- UI/MainFrame.lua
-- Main window: frame chrome, tabs, buttons, and refresh orchestration
local addonName, ns = ...

local UI = ns.UI

UI.currentPage = "queue"  -- "queue" or "log"

-- ==========================================
-- MAIN FRAME
-- ==========================================

local mainFrame = CreateFrame("Frame", "FlipQueueMainFrame", UIParent, "BasicFrameTemplateWithInset")
mainFrame:SetSize(600, 600)
mainFrame:SetPoint("CENTER")
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
mainFrame:SetFrameStrata("HIGH")

mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY")
mainFrame.title:SetFontObject("GameFontHighlight")
mainFrame.title:SetPoint("LEFT", mainFrame.TitleBg, "LEFT", 5, 0)
mainFrame.title:SetText("FlipQueue")

-- Summary line
mainFrame.summary = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mainFrame.summary:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, -30)
mainFrame.summary:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -15, -30)
mainFrame.summary:SetJustifyH("LEFT")

-- ==========================================
-- TAB BUTTONS
-- ==========================================

local tabY = -48

-- Queue tab
mainFrame.queueTab = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
mainFrame.queueTab:SetSize(80, 24)
mainFrame.queueTab:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, tabY)
mainFrame.queueTab:SetText("Queue")
mainFrame.queueTab:SetNormalFontObject("GameFontNormalSmall")
mainFrame.queueTab:SetScript("OnClick", function()
    UI.currentPage = "queue"
    UI:Refresh()
end)

-- Log tab
mainFrame.logTab = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
mainFrame.logTab:SetSize(80, 24)
mainFrame.logTab:SetPoint("LEFT", mainFrame.queueTab, "RIGHT", 4, 0)
mainFrame.logTab:SetText("Log")
mainFrame.logTab:SetNormalFontObject("GameFontNormalSmall")
mainFrame.logTab:SetScript("OnClick", function()
    UI.currentPage = "log"
    UI:Refresh()
end)

-- Sort toggle
mainFrame.sortBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
mainFrame.sortBtn:SetSize(100, 24)
mainFrame.sortBtn:SetPoint("LEFT", mainFrame.logTab, "RIGHT", 12, 0)
mainFrame.sortBtn:SetNormalFontObject("GameFontNormalSmall")
mainFrame.sortBtn:SetScript("OnClick", function()
    if ns.db then
        ns.db.settings.sortMode = ns.db.settings.sortMode == "realm" and "name" or "realm"
        UI:Refresh()
    end
end)

-- ==========================================
-- ACTION BUTTONS ROW
-- ==========================================

local btnY = tabY - 28

mainFrame.importBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
mainFrame.importBtn:SetSize(70, 22)
mainFrame.importBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, btnY)
mainFrame.importBtn:SetText("Import")
mainFrame.importBtn:SetNormalFontObject("GameFontNormalSmall")
mainFrame.importBtn:SetScript("OnClick", function()
    UI.importFrame:Show()
    UI.importEditBox:SetFocus(true)
end)

mainFrame.clearPostedBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
mainFrame.clearPostedBtn:SetSize(90, 22)
mainFrame.clearPostedBtn:SetPoint("LEFT", mainFrame.importBtn, "RIGHT", 3, 0)
mainFrame.clearPostedBtn:SetText("Clear Posted")
mainFrame.clearPostedBtn:SetNormalFontObject("GameFontNormalSmall")
mainFrame.clearPostedBtn:SetScript("OnClick", function()
    ns.Queue:Clear("posted")
    ns:Print("Cleared posted items.")
    UI:Refresh()
end)

mainFrame.clearAllBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
mainFrame.clearAllBtn:SetSize(70, 22)
mainFrame.clearAllBtn:SetPoint("LEFT", mainFrame.clearPostedBtn, "RIGHT", 3, 0)
mainFrame.clearAllBtn:SetText("Clear All")
mainFrame.clearAllBtn:SetNormalFontObject("GameFontNormalSmall")
mainFrame.clearAllBtn:SetScript("OnClick", function()
    StaticPopupDialogs["FLIPQUEUE_CLEAR_ALL"] = {
        text = "Clear ALL items from the FlipQueue?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            ns.Queue:Clear()
            ns:Print("Queue cleared.")
            UI:Refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FLIPQUEUE_CLEAR_ALL")
end)

mainFrame.rescanBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
mainFrame.rescanBtn:SetSize(70, 22)
mainFrame.rescanBtn:SetPoint("LEFT", mainFrame.clearAllBtn, "RIGHT", 3, 0)
mainFrame.rescanBtn:SetText("Rescan")
mainFrame.rescanBtn:SetNormalFontObject("GameFontNormalSmall")
mainFrame.rescanBtn:SetScript("OnClick", function()
    ns.Scanner:ScanCurrentCharacter()
    UI:Refresh()
end)

mainFrame.pullBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
mainFrame.pullBtn:SetSize(75, 22)
mainFrame.pullBtn:SetPoint("LEFT", mainFrame.rescanBtn, "RIGHT", 3, 0)
mainFrame.pullBtn:SetText("Pull Bank")
mainFrame.pullBtn:SetNormalFontObject("GameFontNormalSmall")
mainFrame.pullBtn:SetScript("OnClick", function()
    local saved = ns.db.settings.autoPullBank
    ns.db.settings.autoPullBank = true
    ns.Tracker:AutoPullFromBank()
    ns.db.settings.autoPullBank = saved
end)

mainFrame.dntBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
mainFrame.dntBtn:SetSize(55, 22)
mainFrame.dntBtn:SetPoint("LEFT", mainFrame.pullBtn, "RIGHT", 3, 0)
mainFrame.dntBtn:SetText("DNT")
mainFrame.dntBtn:SetNormalFontObject("GameFontNormalSmall")
mainFrame.dntBtn:SetScript("OnClick", function()
    UI:ShowDoNotTrackFrame()
end)
mainFrame.dntBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Do Not Track List", 1, 1, 1)
    GameTooltip:AddLine("Manage items excluded from the Untracked section.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
mainFrame.dntBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ==========================================
-- SCROLL AREA
-- ==========================================

local scrollFrame = CreateFrame("ScrollFrame", "FlipQueueScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, btnY - 26)
scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -30, 40)

local content = CreateFrame("Frame", "FlipQueueContentFrame", scrollFrame)
content:SetSize(scrollFrame:GetWidth(), 1)
scrollFrame:SetScrollChild(content)

-- Connect the content frame to the row pool
UI.content = content

-- ==========================================
-- BOTTOM BAR
-- ==========================================

mainFrame.autoPullCB = CreateFrame("CheckButton", nil, mainFrame, "UICheckButtonTemplate")
mainFrame.autoPullCB:SetSize(24, 24)
mainFrame.autoPullCB:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 10, 10)
mainFrame.autoPullCB.text:SetText("Auto-pull from bank")
mainFrame.autoPullCB.text:SetFontObject("GameFontNormalSmall")
mainFrame.autoPullCB:SetScript("OnClick", function(self)
    if ns.db then
        ns.db.settings.autoPullBank = self:GetChecked()
    end
end)

-- Clear Log button (only visible on log page)
mainFrame.clearLogBtn = CreateFrame("Button", nil, mainFrame, "GameMenuButtonTemplate")
mainFrame.clearLogBtn:SetSize(100, 22)
mainFrame.clearLogBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 10)
mainFrame.clearLogBtn:SetText("Clear Log")
mainFrame.clearLogBtn:SetNormalFontObject("GameFontNormalSmall")
mainFrame.clearLogBtn:SetScript("OnClick", function()
    StaticPopupDialogs["FLIPQUEUE_CLEAR_LOG"] = {
        text = "Clear ALL items from the FlipQueue log?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            ns.Queue:ClearLog()
            ns:Print("Log cleared.")
            UI:Refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FLIPQUEUE_CLEAR_LOG")
end)

mainFrame:Hide()
UI.mainFrame = mainFrame

-- ==========================================
-- REFRESH ORCHESTRATION
-- ==========================================

local function UpdateTabHighlights()
    if UI.currentPage == "queue" then
        mainFrame.queueTab:SetText("|cffffffff[Queue]|r")
        mainFrame.logTab:SetText("Log")
    else
        mainFrame.queueTab:SetText("Queue")
        mainFrame.logTab:SetText("|cffffffff[Log]|r")
    end
end

function UI:Refresh()
    if not mainFrame:IsShown() then return end
    if not ns.db then return end

    self:HideAllRows()
    UpdateTabHighlights()

    -- Sort button label
    local sortLabel = ns.db.settings.sortMode == "realm" and "Sort: Realm" or "Sort: Name"
    mainFrame.sortBtn:SetText(sortLabel)

    -- Show/hide page-specific controls
    mainFrame.clearLogBtn:SetShown(self.currentPage == "log")
    mainFrame.autoPullCB:SetShown(self.currentPage == "queue")

    -- Summary counts
    local pending = ns.Queue:GetPendingCount()
    local logCount = #ns.db.log
    mainFrame.summary:SetText(string.format(
        "Queue: %s%d pending|r  |  Log: %s%d posted|r  |  %d total tracked",
        ns.COLORS.YELLOW, pending,
        ns.COLORS.GREEN, logCount,
        #ns.db.queue + logCount
    ))

    if ns.db.settings then
        mainFrame.autoPullCB:SetChecked(ns.db.settings.autoPullBank)
    end

    local rowIndex = 0

    if self.currentPage == "log" then
        rowIndex = self:RenderLog(rowIndex)
    else
        local charKey = ns:GetCharKey()
        local myRealm = charKey:match("%-(.+)$") or ""

        rowIndex = self:RenderThisCharacter(rowIndex, charKey, myRealm)
        rowIndex = self:RenderOtherRealms(rowIndex, charKey, myRealm)
        rowIndex = self:RenderNeedAccount(rowIndex)
        rowIndex = self:RenderUntracked(rowIndex)
        rowIndex = self:RenderFullQueue(rowIndex)
    end

    -- Empty state
    if rowIndex == 0 then
        rowIndex = 1
        local row = self:GetOrCreateRow(1)
        row.icon:SetTexture(nil)
        row.text:SetText(ns.COLORS.GRAY .. "Queue is empty. Click Import to add items from FlippingPal." .. ns.COLORS.RESET)
        row:Show()
    end

    content:SetHeight(math.max(1, rowIndex * UI.ROW_HEIGHT))
end

mainFrame:SetScript("OnShow", function()
    UI:Refresh()
end)
