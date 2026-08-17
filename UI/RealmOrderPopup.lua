-- UI/RealmOrderPopup.lua
-- Drag-to-reorder list of realms, used as the last tie-break when Deal Finder
-- picks where to sell (FQ-255).
--
-- Lives in a popup rather than inline in the Deal Finder config column: that
-- column does not scroll, and a realm list runs to dozens of rows.
--
-- The order starts seeded from how busy each realm's auction house is, using
-- TSM's own per-realm data, so it is useful before the player touches it.
-- Dragging is what turns the seed into a stored preference — until then the
-- list tracks TSM's data rather than freezing a snapshot of it.
local addonName, ns = ...

local UI = ns.UI or {}
ns.UI = UI

local ROW_H = 28
local frame, scrollChild, rowPool, working

local function SaveOrder()
    if not ns.db then return end
    local copy = {}
    for i, realm in ipairs(working or {}) do copy[i] = realm end
    ns.db.settings.dfRealmOrder = copy
end

-- Realms the player can actually sell on. The order applies to every realm,
-- but these are the only ones a scan ever scores, so they are worth marking.
local function SellRealmSet()
    local set = {}
    if not (ns.DealFinder and ns.DealFinder.GetSellRealms) then return set end
    for _, info in pairs(ns.DealFinder:GetSellRealms()) do
        set[info.display] = true
        if ns.NormalizeRealmKey then set[ns:NormalizeRealmKey(info.display)] = true end
    end
    return set
end

local function BuildMeta()
    local meta = {}
    local sellSet = SellRealmSet()
    for _, realm in ipairs(working or {}) do
        local activity = (ns.TSMRealms and ns.TSMRealms.GetRealmActivity)
            and ns.TSMRealms:GetRealmActivity(realm) or 0
        local mine = sellSet[realm]
            or (ns.NormalizeRealmKey and sellSet[ns:NormalizeRealmKey(realm)])
        -- Colour carries the "you sell here" signal; the count is the evidence
        -- behind the default ordering, shown so the player can see why a realm
        -- sits where it does rather than being asked to trust it.
        meta[realm] = {
            label = realm .. (activity > 0
                and ("  |cff888888" .. activity .. " items listed|r") or ""),
            color = mine and { 0.4, 1, 0.5 } or { 0.65, 0.65, 0.7 },
        }
    end
    return meta
end

local function Render()
    if not (frame and scrollChild) then return end
    local endY = UI:RenderAllocList(working, BuildMeta(), rowPool, scrollChild, -2, function()
        SaveOrder()
        Render()
    end)
    scrollChild:SetHeight(math.max(-endY + 4, 1))
end

function UI:ShowRealmOrderPopup()
    if not frame then
        frame = CreateFrame("Frame", "FlipQueueRealmOrderPopup", UIParent,
            "BasicFrameTemplateWithInset")
        frame:SetSize(340, 460)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetClampedToScreen(true)
        if frame.TitleText then frame.TitleText:SetText("Realm Order") end

        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -30)
        desc:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetText("Used when realms are otherwise equal — most often when " ..
            "FlipQueue has no listings for an item on any of them. Drag to " ..
            "reorder. |cff66ff88Green|r means you have a character selling there.")

        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -76)
        scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 44)
        scrollChild = CreateFrame("Frame", nil, scroll)
        scrollChild:SetWidth(280)
        scrollChild:SetHeight(1)
        scroll:SetScrollChild(scrollChild)

        local reset = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
        reset:SetSize(150, 22)
        reset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
        reset:SetText("Reset to busiest first")
        reset:SetScript("OnClick", function()
            -- Clearing the stored order rather than writing the seed into it:
            -- an empty setting means "follow TSM's data", so the order keeps
            -- tracking realm activity instead of freezing today's snapshot.
            if ns.db then ns.db.settings.dfRealmOrder = {} end
            working = ns.DealFinder and ns.DealFinder:GetRealmOrder() or {}
            Render()
        end)

        local close = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
        close:SetSize(80, 22)
        close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
        close:SetText("Close")
        close:SetScript("OnClick", function() frame:Hide() end)

        rowPool = {}
        tinsert(UISpecialFrames, "FlipQueueRealmOrderPopup")
    end

    -- Snapshot the effective order (stored, or the activity seed) into a
    -- working copy. Only a drag writes it back, so opening and closing the
    -- window without touching anything leaves the player on the seed.
    working = ns.DealFinder and ns.DealFinder:GetRealmOrder() or {}
    Render()
    frame:Show()
end

function UI:ToggleRealmOrderPopup()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:ShowRealmOrderPopup()
    end
end
