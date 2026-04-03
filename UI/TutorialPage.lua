-- UI/TutorialPage.lua
-- Tutorial overlay system: tooltip callouts on real pages
local addonName, ns = ...

local UI = ns.UI

-- Tutorial state
UI._tutorialActive = false
UI._tutorialStep = 1
UI._tutorialCallout = 1

-- ==========================================
-- TUTORIAL STEP DEFINITIONS
-- ==========================================

-- Each step: { page = "pageName", label = "Step Label", callouts = { ... } }
-- Callout types:
--   { type = "center", title, text }  — centered in content area
--   { type = "banner", text }         — banner at top of content area
--   { type = "anchor", anchor, arrow, text } — anchored to a UI element

local TUTORIAL_STEPS = {
    -- Step 1: Welcome
    {
        page = nil,  -- no specific page, show centered
        label = "Welcome",
        callouts = {
            {
                type = "center",
                title = "Welcome to FlipQueue!",
                text = "FlipQueue organizes your AH flipping workflow.\n\n" ..
                    "This tutorial will walk you through the real interface —\n" ..
                    "your inventory, the to-do generator, and how deals\n" ..
                    "turn into a task list for your characters.\n\n" ..
                    "Click |cffe8c840Next|r to begin.",
            },
        },
    },
    -- Step 2: Inventory
    {
        page = "inventory",
        label = "Inventory",
        callouts = {
            {
                type = "banner",
                text = "This is your |cffe8c840Inventory|r page. It shows every tradeable item " ..
                    "across all your characters and the warbank in one place.",
            },
            {
                type = "anchor",
                anchor = "inventoryTable.headerFrame",
                arrow = "UP",
                text = "Each row shows an item, its quantity, which character owns it, " ..
                    "where it is (bags, bank, warbank), and its status.",
            },
            {
                type = "banner",
                text = "|cffe8c840Status|r tells you what's happening with each item:\n" ..
                    "|cff4ae14aAssigned|r = in your to-do list  |  " ..
                    "|cffffff00Posted|r = on the AH  |  " ..
                    "|cff888888Unassigned|r = not on a to-do list yet",
            },
            {
                type = "banner",
                text = "FQ auto-scans your bags on login. To scan your |cffe8c840bank|r and " ..
                    "|cffe8c840warbank|r, simply visit a banker and open them.\n" ..
                    "Log into each character once so FQ can see all your items.",
            },
        },
    },
    -- Step 3: Generator
    {
        page = "generator",
        label = "Generator",
        callouts = {
            {
                type = "banner",
                text = "This is the |cffe8c840To-Do Generator|r. It takes your imported deals " ..
                    "and builds a task list — which items to post, on which characters.",
            },
            {
                type = "banner",
                text = "There are three ways to generate tasks:\n\n" ..
                    "|cffe8c840Deal Finder|r — Scans your inventory against TSM data to find " ..
                    "profitable items to sell on other realms.\n\n" ..
                    "|cffe8c840Inventory Scan|r — Export your inventory to FlippingPal, " ..
                    "import the deals it finds, and generate tasks from them.\n\n" ..
                    "|cffe8c840Cross-Realm Import|r — Import FlippingPal's cross-realm flip " ..
                    "report to buy items on cheap realms and sell on expensive ones.",
            },
        },
    },
    -- Step 4: All Set
    {
        page = "todo",
        label = "To-Do",
        callouts = {
            {
                type = "center",
                title = "You're All Set!",
                text = "Your |cffe8c840To-Do|r list will appear here\n" ..
                    "once you generate one.\n\n" ..
                    "The daily workflow:\n" ..
                    "|cff66b2ff1.|r Retrieve items from the warbank\n" ..
                    "|cffffff002.|r Post on the Auction House\n" ..
                    "|cff4ae14a3.|r Collect gold or expired items from mail\n\n" ..
                    "FQ auto-detects bag contents, AH posts,\n" ..
                    "and mail — steps advance automatically.\n\n" ..
                    "Click |cff4ae14aFinish|r to start using FlipQueue!",
            },
        },
    },
}

-- ==========================================
-- CALLOUT FRAME
-- ==========================================

local calloutFrame  -- single reusable callout
local nudgeBanner   -- "Return to Tutorial" banner

local function EnsureCalloutFrame()
    if calloutFrame then return calloutFrame end

    local f = CreateFrame("Frame", "FlipQueueTutorialCallout", UIParent, "BackdropTemplate")
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:SetSize(380, 100)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    f:SetBackdropColor(0.06, 0.06, 0.1, 0.97)
    f:SetBackdropBorderColor(0.7, 0.55, 0.15, 0.9)

    -- Step indicator (top-left)
    f.stepLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.stepLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    f.stepLabel:SetTextColor(0.5, 0.5, 0.5)

    -- Title (optional, for center type)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -24)
    f.title:SetTextColor(0.9, 0.85, 0.5)
    f.title:SetWidth(350)
    f.title:SetJustifyH("CENTER")

    -- Text
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetWidth(350)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(true)
    f.text:SetTextColor(0.82, 0.82, 0.82)

    -- Arrow (directional indicator)
    f.arrow = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.arrow:SetTextColor(0.7, 0.55, 0.15, 0.9)

    -- Navigation buttons
    local function MakeBtn(label, isGreen)
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(70, 22)
        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        local bgR, bgG, bgB = 0.12, 0.12, 0.16
        if isGreen then bgR, bgG, bgB = 0.12, 0.2, 0.12 end
        btn:SetBackdropColor(bgR, bgG, bgB, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(label)
        if isGreen then btn.text:SetTextColor(0.3, 1, 0.3) end
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(bgR + 0.06, bgG + 0.06, bgB + 0.06, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(bgR, bgG, bgB, 1)
        end)
        return btn
    end

    f.backBtn = MakeBtn("Back")
    f.backBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)

    f.nextBtn = MakeBtn("Next")
    f.nextBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)

    f.finishBtn = MakeBtn("Finish", true)
    f.finishBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)

    f.skipLink = MakeBtn("Skip Tutorial")
    f.skipLink:SetSize(100, 22)
    f.skipLink:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    f.skipLink.text:SetTextColor(0.7, 0.5, 0.5)
    f.skipLink:SetScript("OnClick", function()
        ns.db.settings.tutorialDone = true
        UI._tutorialActive = false
        UI:HideTutorialCallouts()
        UI:Refresh()
    end)

    -- Button handlers
    f.backBtn:SetScript("OnClick", function()
        UI:_TutorialPrev()
    end)
    f.nextBtn:SetScript("OnClick", function()
        UI:_TutorialNext()
    end)
    f.finishBtn:SetScript("OnClick", function()
        ns.db.settings.tutorialDone = true
        UI._tutorialActive = false
        UI:HideTutorialCallouts()
        UI:Refresh()
    end)

    f:Hide()
    calloutFrame = f
    return f
end

-- ==========================================
-- NUDGE-BACK BANNER
-- ==========================================

local function EnsureNudgeBanner()
    if nudgeBanner then return nudgeBanner end

    local b = CreateFrame("Frame", "FlipQueueTutorialNudge", UIParent, "BackdropTemplate")
    b:SetFrameStrata("TOOLTIP")
    b:SetHeight(28)
    b:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    b:SetBackdropColor(0.15, 0.12, 0.05, 0.95)
    b:SetBackdropBorderColor(0.7, 0.55, 0.15, 0.8)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.text:SetTextColor(0.9, 0.8, 0.4)

    b.returnBtn = CreateFrame("Button", nil, b)
    b.returnBtn:SetSize(120, 18)
    b.returnBtn.text = b.returnBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.returnBtn.text:SetAllPoints()
    b.returnBtn.text:SetText("|cff4ae14aReturn to Tutorial|r")
    b.returnBtn.text:SetJustifyH("CENTER")
    b.returnBtn:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    b.returnBtn:SetScript("OnEnter", function()
        b.returnBtn.text:SetText("|cff6aff6aReturn to Tutorial|r")
    end)
    b.returnBtn:SetScript("OnLeave", function()
        b.returnBtn.text:SetText("|cff4ae14aReturn to Tutorial|r")
    end)
    b.returnBtn:SetScript("OnClick", function()
        local step = TUTORIAL_STEPS[UI._tutorialStep]
        if step and step.page then
            UI.currentPage = step.page
            UI:Refresh()
        end
    end)

    b:Hide()
    nudgeBanner = b
    return b
end

-- ==========================================
-- RESOLVE ANCHOR
-- ==========================================

local function ResolveAnchor(anchorStr)
    -- Resolve a dotted path like "_genFrame.trackSelectPanel.inventoryCard"
    local parts = { strsplit(".", anchorStr) }
    local obj = UI
    for _, part in ipairs(parts) do
        if obj and type(obj) == "table" then
            obj = obj[part]
        else
            return nil
        end
    end
    return obj
end

-- ==========================================
-- SHOW / HIDE CALLOUTS
-- ==========================================

function UI:ShowTutorialCallouts()
    local step = TUTORIAL_STEPS[UI._tutorialStep]
    if not step then
        self:HideTutorialCallouts()
        return
    end

    local f = EnsureCalloutFrame()
    local nb = EnsureNudgeBanner()

    -- Check if we're on the right page
    local onRightPage = step.page == nil or UI.currentPage == step.page
    if not onRightPage then
        -- Show nudge-back banner, hide callout
        f:Hide()
        nb.text:SetText("Tutorial Step " .. UI._tutorialStep .. "/" .. #TUTORIAL_STEPS ..
            ": " .. step.label)
        nb:ClearAllPoints()
        nb:SetPoint("TOPLEFT", self.tableContainer, "TOPLEFT", 0, 0)
        nb:SetPoint("TOPRIGHT", self.tableContainer, "TOPRIGHT", 0, 0)
        nb:Show()
        return
    end

    nb:Hide()

    -- Get current callout
    local calloutIdx = UI._tutorialCallout
    local callout = step.callouts[calloutIdx]
    if not callout then
        -- No more callouts in this step — show the last one
        calloutIdx = #step.callouts
        callout = step.callouts[calloutIdx]
        UI._tutorialCallout = calloutIdx
    end
    if not callout then
        f:Hide()
        return
    end

    -- Step indicator
    local totalCallouts = #step.callouts
    local stepInfo = "Step " .. UI._tutorialStep .. "/" .. #TUTORIAL_STEPS
    if totalCallouts > 1 then
        stepInfo = stepInfo .. "  (" .. calloutIdx .. "/" .. totalCallouts .. ")"
    end
    f.stepLabel:SetText(stepInfo)

    -- Title
    f.text:ClearAllPoints()
    if callout.title then
        f.title:SetText(callout.title)
        f.title:Show()
        f.text:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
        f.text:SetJustifyH("CENTER")
    else
        f.title:Hide()
        f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -22)
        f.text:SetPoint("RIGHT", f, "RIGHT", -14, 0)
        f.text:SetJustifyH("LEFT")
    end

    -- Text
    f.text:SetText(callout.text or "")

    -- Arrow
    f.arrow:Hide()

    -- Size the frame to fit the text
    local textHeight = f.text:GetStringHeight() or 40
    local titleHeight = callout.title and ((f.title:GetStringHeight() or 20) + 8) or 0
    local totalHeight = 22 + titleHeight + textHeight + 40  -- padding + step label + title + text + buttons
    f:SetHeight(math.max(totalHeight, 80))

    -- Position based on type
    f:ClearAllPoints()

    if callout.type == "center" then
        -- Centered in the content area
        f:SetWidth(400)
        f:SetPoint("CENTER", self.tableContainer, "CENTER", 0, 20)

    elseif callout.type == "banner" then
        -- Banner at top of content area
        f:SetWidth(self.tableContainer:GetWidth() - 8)
        f:SetPoint("TOP", self.tableContainer, "TOP", 0, -2)

    elseif callout.type == "anchor" then
        -- Anchored to a UI element
        local target = ResolveAnchor(callout.anchor)
        if target and target.GetCenter and target:IsShown() then
            f:SetWidth(380)
            local arrowDir = callout.arrow or "DOWN"

            if arrowDir == "UP" then
                f:SetPoint("BOTTOM", target, "TOP", 0, 14)
                f.arrow:SetText("|cffb38f26v|r")
                f.arrow:ClearAllPoints()
                f.arrow:SetPoint("TOP", f, "BOTTOM", 0, 6)
                f.arrow:Show()
            elseif arrowDir == "DOWN" then
                f:SetPoint("TOP", target, "BOTTOM", 0, -14)
                f.arrow:SetText("|cffb38f26^|r")  -- upward caret as "arrow pointing up to target"
                f.arrow:ClearAllPoints()
                f.arrow:SetPoint("BOTTOM", f, "TOP", 0, -6)
                f.arrow:Show()
            else
                -- Default: below target
                f:SetPoint("TOP", target, "BOTTOM", 0, -14)
            end
        else
            -- Anchor not found/visible — fall back to banner
            f:SetWidth(self.tableContainer:GetWidth() - 8)
            f:SetPoint("TOP", self.tableContainer, "TOP", 0, -2)
        end
    end

    -- Nav buttons
    local isFirstCallout = (UI._tutorialStep == 1 and calloutIdx == 1)
    local isLastStep = (UI._tutorialStep == #TUTORIAL_STEPS)
    local isLastCallout = (calloutIdx == #step.callouts)

    f.backBtn:SetShown(not isFirstCallout)
    f.nextBtn:SetShown(not (isLastStep and isLastCallout))
    f.finishBtn:SetShown(isLastStep and isLastCallout)
    f.skipLink:SetShown(not (isLastStep and isLastCallout))

    -- Position Skip: center when Back is hidden, otherwise between Back and Next
    f.skipLink:ClearAllPoints()
    if isFirstCallout then
        f.skipLink:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    else
        f.skipLink:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    end

    -- Highlight the current step's nav button in the sidebar
    self:_HighlightTutorialNav(step.page)

    f:Show()
end

function UI:HideTutorialCallouts()
    if calloutFrame then calloutFrame:Hide() end
    if nudgeBanner then nudgeBanner:Hide() end
    self:_HighlightTutorialNav(nil)  -- clear highlights
end

-- ==========================================
-- NAVIGATION
-- ==========================================

function UI:_TutorialNext()
    local step = TUTORIAL_STEPS[UI._tutorialStep]
    if not step then return end

    if UI._tutorialCallout < #step.callouts then
        -- Next callout within this step
        UI._tutorialCallout = UI._tutorialCallout + 1
        self:ShowTutorialCallouts()
    elseif UI._tutorialStep < #TUTORIAL_STEPS then
        -- Next step
        UI._tutorialStep = UI._tutorialStep + 1
        UI._tutorialCallout = 1
        local nextStep = TUTORIAL_STEPS[UI._tutorialStep]
        if nextStep and nextStep.page then
            UI.currentPage = nextStep.page
        end
        UI:Refresh()
    end
end

function UI:_TutorialPrev()
    if UI._tutorialCallout > 1 then
        -- Previous callout within this step
        UI._tutorialCallout = UI._tutorialCallout - 1
        self:ShowTutorialCallouts()
    elseif UI._tutorialStep > 1 then
        -- Previous step (go to last callout of that step)
        UI._tutorialStep = UI._tutorialStep - 1
        local prevStep = TUTORIAL_STEPS[UI._tutorialStep]
        UI._tutorialCallout = prevStep and #prevStep.callouts or 1
        if prevStep and prevStep.page then
            UI.currentPage = prevStep.page
        end
        UI:Refresh()
    end
end

-- ==========================================
-- SIDEBAR HIGHLIGHT
-- ==========================================

local highlightedNavKey = nil

function UI:_HighlightTutorialNav(pageKey)
    -- Clear previous highlight
    if highlightedNavKey and UI._navButtons then
        local btn = UI._navButtons[highlightedNavKey]
        if btn and UI.currentPage ~= highlightedNavKey then
            btn.bg:SetColorTexture(1, 1, 1, 0)
            btn.label:SetTextColor(0.7, 0.7, 0.7)
        end
    end

    highlightedNavKey = pageKey
    if not pageKey then return end

    -- Apply gold highlight
    if UI._navButtons then
        local btn = UI._navButtons[pageKey]
        if btn and UI.currentPage ~= pageKey then
            btn.bg:SetColorTexture(0.8, 0.6, 0, 0.25)
            btn.label:SetTextColor(1, 0.85, 0.3)
        end
    end
end

-- ==========================================
-- LEGACY COMPAT: RefreshTutorialPage
-- ==========================================
-- Called by old MainFrame intercept if it still exists; redirect to overlay
function UI:RefreshTutorialPage()
    -- Old standalone tutorial — redirect to overlay system
    UI._tutorialActive = true
    UI._tutorialStep = UI._tutorialStep or 1
    UI._tutorialCallout = UI._tutorialCallout or 1
    UI:Refresh()
end
