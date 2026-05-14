-- UI/AuctionatorFrame.lua
-- Auctionator integration page: live buy-list sync settings + manual refresh.
local addonName, ns = ...

local UI = ns.UI

local auctPanel
local auctWidgets = {}

local LEFT_MARGIN = 12
local RIGHT_MARGIN = -12
local SECTION_SPACING = 14
local DESC_COLOR = {0.6, 0.6, 0.6}

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

-- Lightweight checkbox bound to ns.db.settings[key].
local function CreateCheckRow(parent, label, tooltip, settingKey, onChanged)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)

    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)
    cb:SetScript("OnClick", function(self)
        if ns.db and ns.db.settings then
            ns.db.settings[settingKey] = self:GetChecked()
            if onChanged then onChanged() end
        end
    end)

    local txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    txt:SetText(label)
    txt:SetWordWrap(false)

    if tooltip then
        cb:SetScript("OnEnter", function()
            GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    row.cb = cb
    row.settingKey = settingKey
    return row
end

local function CreateModeRadioPair(parent, onChanged)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)

    local function MakeRadio(label, value)
        local r = CreateFrame("CheckButton", nil, row, "UIRadioButtonTemplate")
        r:SetSize(16, 16)
        r.value = value
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r, "RIGHT", 2, 0)
        r.text:SetText(label)
        return r
    end

    local single = MakeRadio("Single list (FlipQueue - Buy)", "single")
    single:SetPoint("LEFT", row, "LEFT", 0, 0)

    local perRealm = MakeRadio("One list per realm", "perRealm")
    perRealm:SetPoint("LEFT", single.text, "RIGHT", 18, 0)

    local function Sync()
        local mode = ns.db and ns.db.settings and ns.db.settings.auctBuyListMode or "single"
        single:SetChecked(mode == "single")
        perRealm:SetChecked(mode == "perRealm")
    end

    single:SetScript("OnClick", function()
        ns.db.settings.auctBuyListMode = "single"
        Sync()
        if onChanged then onChanged() end
    end)
    perRealm:SetScript("OnClick", function()
        ns.db.settings.auctBuyListMode = "perRealm"
        Sync()
        if onChanged then onChanged() end
    end)

    row.Sync = Sync
    return row
end

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

    ------------------------------------------------
    -- Status
    ------------------------------------------------

    auctWidgets.status = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    auctWidgets.status:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    y = y - 24

    auctWidgets.notInstalled = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    auctWidgets.notInstalled:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    auctWidgets.notInstalled:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    auctWidgets.notInstalled:SetJustifyH("LEFT")
    auctWidgets.notInstalled:SetWordWrap(true)
    auctWidgets.notInstalled:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    auctWidgets.notInstalled:SetText(
        "FlipQueue keeps a live Auctionator shopping list synced to the buy tasks " ..
        "you currently need to fulfill. The list refreshes when you open the AH " ..
        "and as you make purchases, so each item drops off as soon as you've bought enough.\n\n" ..
        "Install Auctionator from CurseForge to enable this feature.")
    auctWidgets.notInstalled:SetHeight(80)
    y = y - 90

    ------------------------------------------------
    -- Buy List Sync settings
    ------------------------------------------------

    y = y - SectionHeader(content, y, "Buy List Sync")

    auctWidgets.enabled = CreateCheckRow(content,
        "Sync buy tasks to an Auctionator shopping list",
        "When on, the FlipQueue buy list is automatically populated from your current character's outstanding buy tasks. Items drop off as your bags fill — that's how purchase detection works.",
        "auctBuyListEnabled",
        function() UI:RefreshAuctionatorPage(); if ns.BuyListSync then ns.BuyListSync:Rebuild(true) end end)
    auctWidgets.enabled:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    auctWidgets.enabled:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    y = y - 22

    auctWidgets.autoUpdate = CreateCheckRow(content,
        "Auto-update when the AH opens or you buy something",
        "Off = the list only refreshes when you click Refresh below. On is the default and matches Profession Shopping List's behavior.",
        "auctBuyListAutoUpdate")
    auctWidgets.autoUpdate:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 18, y)
    auctWidgets.autoUpdate:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    y = y - 22

    auctWidgets.modeRow = CreateModeRadioPair(content,
        function() if ns.BuyListSync then ns.BuyListSync:Rebuild(true) end end)
    auctWidgets.modeRow:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 18, y)
    auctWidgets.modeRow:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    y = y - 26

    auctWidgets.includeQuality = CreateCheckRow(content,
        "Match exact quality (epic/rare/uncommon)",
        "Off (default) widens the search so listings carrying bonus IDs that bumped quality still appear. On forces an exact-quality match — useful when you only want one specific bracket.",
        "auctBuyListIncludeQuality",
        function() if ns.BuyListSync then ns.BuyListSync:Rebuild(true) end end)
    auctWidgets.includeQuality:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 18, y)
    auctWidgets.includeQuality:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    y = y - 22

    auctWidgets.includeTier = CreateCheckRow(content,
        "Match exact crafting tier",
        "Off (default) leaves tier unconstrained. On forces an exact-tier match — useful for crafted reagents where tier 1/2/3 carry very different prices.",
        "auctBuyListIncludeTier",
        function() if ns.BuyListSync then ns.BuyListSync:Rebuild(true) end end)
    auctWidgets.includeTier:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 18, y)
    auctWidgets.includeTier:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    y = y - 22

    auctWidgets.includeIlvl = CreateCheckRow(content,
        "Match exact item level",
        "On (default) constrains the search to the exact ilvl on the buy task so a level-220 Tarnished Dawnlit Band doesn't surface ilvl-200 variants. Off widens the search to any ilvl — useful when an item's ilvl wasn't captured at import.",
        "auctBuyListIncludeIlvl",
        function() if ns.BuyListSync then ns.BuyListSync:Rebuild(true) end end)
    auctWidgets.includeIlvl:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 18, y)
    auctWidgets.includeIlvl:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    y = y - 22

    auctWidgets.autoDelete = CreateCheckRow(content,
        "Delete empty per-realm lists automatically",
        "Only applies in per-realm mode. When a realm's buy list goes empty, FlipQueue removes the list from Auctionator's dropdown so old realms don't pile up. The single-mode list is never deleted automatically — it's the persistent target.",
        "auctBuyListAutoDelete")
    auctWidgets.autoDelete:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + 18, y)
    auctWidgets.autoDelete:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    y = y - 28

    -- Manual refresh button
    local refreshBtn = CreateActionBtn("Refresh Buy List Now", content)
    refreshBtn:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    refreshBtn:SetWidth(180)
    refreshBtn:SetScript("OnClick", function()
        if not IsAuctionatorAvailable() then
            auctWidgets.result:SetText("|cffff4444Auctionator is not installed.|r")
            return
        end
        if not ns.BuyListSync then
            auctWidgets.result:SetText("|cffff4444BuyListSync not loaded.|r")
            return
        end
        local total, created, deleted, err = ns.BuyListSync:Rebuild(true)
        if err then
            auctWidgets.result:SetText("|cffff4444" .. err .. "|r")
        elseif total == 0 then
            auctWidgets.result:SetText(ns.COLORS.GRAY .. "No outstanding buy tasks for this character.|r")
        else
            local msg = "Refreshed " .. (created or 0) .. " list(s), " .. (total or 0) .. " item(s)"
            if deleted and deleted > 0 then msg = msg .. " (removed " .. deleted .. " empty)" end
            auctWidgets.result:SetText(ns.COLORS.GREEN .. msg .. ".|r")
        end
        UI:RefreshAuctionatorPage()
    end)
    y = y - 30

    auctWidgets.result = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    auctWidgets.result:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    auctWidgets.result:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    auctWidgets.result:SetJustifyH("LEFT")
    auctWidgets.result:SetWordWrap(true)
    auctWidgets.result:SetText("")
    y = y - 20

    ------------------------------------------------
    -- Available Shopping Lists
    ------------------------------------------------
    y = y - SECTION_SPACING
    y = y - SectionHeader(content, y, "Auctionator Shopping Lists")

    auctWidgets.listInfo = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    auctWidgets.listInfo:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, y)
    auctWidgets.listInfo:SetPoint("RIGHT", content, "RIGHT", RIGHT_MARGIN, 0)
    auctWidgets.listInfo:SetJustifyH("LEFT")
    auctWidgets.listInfo:SetWordWrap(true)
    auctWidgets.listInfo:SetSpacing(2)
    y = y - 120

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

    -- Sync checkbox + radio state from settings.
    if ns.db and ns.db.settings then
        if auctWidgets.enabled and auctWidgets.enabled.cb then
            auctWidgets.enabled.cb:SetChecked(ns.db.settings.auctBuyListEnabled)
        end
        if auctWidgets.autoUpdate and auctWidgets.autoUpdate.cb then
            auctWidgets.autoUpdate.cb:SetChecked(ns.db.settings.auctBuyListAutoUpdate)
        end
        if auctWidgets.includeQuality and auctWidgets.includeQuality.cb then
            auctWidgets.includeQuality.cb:SetChecked(ns.db.settings.auctBuyListIncludeQuality)
        end
        if auctWidgets.includeTier and auctWidgets.includeTier.cb then
            auctWidgets.includeTier.cb:SetChecked(ns.db.settings.auctBuyListIncludeTier)
        end
        if auctWidgets.includeIlvl and auctWidgets.includeIlvl.cb then
            auctWidgets.includeIlvl.cb:SetChecked(ns.db.settings.auctBuyListIncludeIlvl)
        end
        if auctWidgets.autoDelete and auctWidgets.autoDelete.cb then
            auctWidgets.autoDelete.cb:SetChecked(ns.db.settings.auctBuyListAutoDelete)
        end
        if auctWidgets.modeRow and auctWidgets.modeRow.Sync then
            auctWidgets.modeRow.Sync()
        end
    end

    if auctWidgets.listInfo then
        if available then
            local lists = GetShoppingLists()
            if #lists > 0 then
                local lines = {}
                for _, name in ipairs(lists) do
                    local marker = "|cff00ff00>|r "
                    if name:sub(1, #"FlipQueue - Buy") == "FlipQueue - Buy" then
                        marker = "|cffffd200>|r "  -- highlight FQ-managed lists
                    end
                    lines[#lines + 1] = marker .. name
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
