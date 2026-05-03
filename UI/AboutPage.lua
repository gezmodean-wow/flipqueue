-- UI/AboutPage.lua
-- About page: banner, version, credits, links, diagnostic export.
-- Splits the credits/version block out of UI/SettingsFrame.lua so testers
-- and players have a dedicated, easy-to-find surface for "what version am I
-- running?" — the most common triage question.
local addonName, ns = ...

local UI = ns.UI

local LINK_DISCORD = "https://discord.gg/2qsxsp4HuG"
local LINK_GITHUB  = "https://github.com/gezmodean-wow/flipqueue"
local LINK_CF      = "https://www.curseforge.com/wow/addons/flipqueue"
local LINK_WAGO    = "https://addons.wago.io/addons/flipqueue"

local aboutPage
local versionLabel  -- exposed so /fq version refresh keeps the label live

-- Build a one-line "FlipQueue v0.12.0-alpha10 (Cogworks-1.0 v0.12.0)" string.
function UI:GetVersionLine()
    local fq = ns.VERSION or "dev"
    local cw = "?"
    if LibStub then
        local _, minor = LibStub:GetLibrary("Cogworks-1.0", true)
        if type(minor) == "number" then
            cw = "MINOR " .. minor
        end
    end
    return string.format("FlipQueue v%s (Cogworks-1.0 %s)", fq, cw)
end

-- Build the diagnostics blob for the copy button. Includes everything
-- needed to triage a version-sensitive bug report.
function UI:GetDiagnostics()
    local lines = {}
    local function L(s) table.insert(lines, s) end

    L("=== FlipQueue diagnostics ===")
    L("Generated: " .. date("%Y-%m-%d %H:%M:%S"))
    L("")
    L(self:GetVersionLine())
    if ns.VERSION == "dev" then
        L("  (dev build — packager substitution did not run)")
    end

    local v, build, dateStr, tocVer = GetBuildInfo()
    L(string.format("WoW: %s build %s (toc %s, %s)", tostring(v), tostring(build), tostring(tocVer), tostring(dateStr)))
    L("")

    -- Sibling addons of interest
    L("=== Relevant addons ===")
    local relevant = {
        "TradeSkillMaster",
        "Auctionator",
        "Syndicator",
        "Tempo",
        "Tally",
        "Maxcraft",
    }
    for _, name in ipairs(relevant) do
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded(name)
        local version = C_AddOns and C_AddOns.GetAddOnMetadata(name, "Version") or "?"
        L(string.format("  %-20s loaded=%s version=%s",
            name, tostring(loaded), tostring(version)))
    end
    L("")

    -- FlipQueue runtime state
    L("=== Runtime ===")
    L("Character: " .. tostring(ns.GetCharKey and ns:GetCharKey() or "?"))
    L("DB schema version: " .. tostring(ns.db and ns.db.schemaVersion or "?"))
    if ns.Sync and ns.Sync.IsLinked then
        L("Multi-account: linked=" .. tostring(ns.Sync:IsLinked()) ..
          " connected=" .. tostring(ns.Sync.IsConnected and ns.Sync:IsConnected() or "?"))
    end

    return table.concat(lines, "\n")
end

-- Slash-friendly version of the version line — chat printable.
function UI:PrintVersion()
    if ns.Print then
        ns:Print(self:GetVersionLine())
    else
        print("|cff00ff88FlipQueue|r " .. self:GetVersionLine())
    end
end

-- ==========================================
-- PAGE BUILD
-- ==========================================

local function CreateAboutPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide()
    aboutPage = panel
    UI._aboutPage = panel

    -- Inner padded container
    local inner = CreateFrame("Frame", nil, panel)
    inner:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -24)
    inner:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 24)

    local y = 0

    -- Banner image
    local banner = inner:CreateTexture(nil, "ARTWORK")
    banner:SetSize(360, 90)
    banner:SetPoint("TOP", inner, "TOP", 0, y)
    banner:SetTexture("Interface\\AddOns\\flipqueue\\Art\\flipqueue-banner")
    y = y - 100

    -- Version (large, prominent, copy-able feel)
    versionLabel = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    versionLabel:SetPoint("TOP", inner, "TOP", 0, y)
    versionLabel:SetTextColor(1, 0.82, 0.2)
    versionLabel:SetJustifyH("CENTER")
    versionLabel:SetText("v" .. (ns.VERSION or "dev"))
    y = y - 24

    -- Sub-line: cogworks + WoW build
    local subline = inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subline:SetPoint("TOP", inner, "TOP", 0, y)
    subline:SetJustifyH("CENTER")
    do
        local wowV, wowB = GetBuildInfo()
        local cw = "?"
        if LibStub then
            local _, minor = LibStub:GetLibrary("Cogworks-1.0", true)
            if type(minor) == "number" then cw = tostring(minor) end
        end
        subline:SetText(string.format("Cogworks-1.0 MINOR %s   |   WoW %s (build %s)", cw, tostring(wowV), tostring(wowB)))
    end
    y = y - 22

    -- Dev-build warning when the packager substitution failed.
    if ns.VERSION == "dev" then
        local warn = inner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        warn:SetPoint("TOP", inner, "TOP", 0, y)
        warn:SetTextColor(1, 0.7, 0.2)
        warn:SetJustifyH("CENTER")
        warn:SetText("Development build — version unknown.\nReinstall from CurseForge or Wago for a versioned build.")
        y = y - 36
    end

    y = y - 8

    -- Credits divider
    local credLine = inner:CreateTexture(nil, "ARTWORK")
    credLine:SetHeight(1)
    credLine:SetPoint("TOPLEFT", inner, "TOPLEFT", 80, y)
    credLine:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -80, y)
    credLine:SetColorTexture(0.35, 0.35, 0.45, 0.6)
    y = y - 14

    local function AddLine(label, value, color)
        local line = inner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOP", inner, "TOP", 0, y)
        line:SetJustifyH("CENTER")
        local pre = label and ((color or "|cffe8c840") .. label .. "|r  ") or ""
        line:SetText(pre .. (value or ""))
        y = y - 16
    end

    AddLine("Developed by", "Gezmodean & Claude")
    AddLine("Chronosmith:", "Berick")
    AddLine("Honorary Chronosmiths:", "Toeknee_AtX, Zong")
    AddLine("Additional testing by", "KittyKiller, Niduin, Artificer Skills")
    y = y - 6

    local thanksHeader = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    thanksHeader:SetPoint("TOP", inner, "TOP", 0, y)
    thanksHeader:SetTextColor(0.6, 0.6, 0.6)
    thanksHeader:SetText("Special thanks to")
    y = y - 14

    local thanks = inner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    thanks:SetPoint("TOP", inner, "TOP", 0, y)
    thanks:SetText("FlippingPal  |  TradeSkillMaster  |  Auctionator  |  Epos")
    y = y - 24

    -- Links section
    local linksDivider = inner:CreateTexture(nil, "ARTWORK")
    linksDivider:SetHeight(1)
    linksDivider:SetPoint("TOPLEFT", inner, "TOPLEFT", 80, y)
    linksDivider:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -80, y)
    linksDivider:SetColorTexture(0.35, 0.35, 0.45, 0.6)
    y = y - 14

    local linksHeader = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    linksHeader:SetPoint("TOP", inner, "TOP", 0, y)
    linksHeader:SetTextColor(0.6, 0.6, 0.6)
    linksHeader:SetText("Links")
    y = y - 16

    local function AddLink(label, url)
        local row = CreateFrame("Frame", nil, inner)
        row:SetSize(420, 18)
        row:SetPoint("TOP", inner, "TOP", 0, y)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
        lbl:SetWidth(140)
        lbl:SetJustifyH("RIGHT")
        lbl:SetTextColor(0.9, 0.8, 0.3)
        lbl:SetText(label)

        local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        edit:SetSize(260, 18)
        edit:SetPoint("LEFT", lbl, "RIGHT", 12, 0)
        edit:SetAutoFocus(false)
        edit:SetText(url)
        edit:SetCursorPosition(0)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnTextChanged", function(self) self:SetText(url); self:SetCursorPosition(0) end)
        edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)

        y = y - 22
    end

    AddLink("GitHub", LINK_GITHUB)
    AddLink("Discord", LINK_DISCORD)
    AddLink("CurseForge", LINK_CF)
    AddLink("Wago", LINK_WAGO)
    y = y - 8

    -- Copy diagnostics button — opens an export popup with the full diagnostics blob
    local diagBtn = CreateFrame("Button", nil, inner, "BackdropTemplate")
    diagBtn:SetSize(220, 28)
    diagBtn:SetPoint("TOP", inner, "TOP", 0, y)
    diagBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    diagBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    diagBtn:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.8)
    local diagLabel = diagBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    diagLabel:SetPoint("CENTER")
    diagLabel:SetText("Copy diagnostics")
    diagBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.22, 0.3, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Copy diagnostics", 1, 1, 1)
        GameTooltip:AddLine("Opens a dialog with version + relevant addons + WoW build info,\nready to paste into a bug report.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    diagBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
        GameTooltip:Hide()
    end)
    diagBtn:SetScript("OnClick", function()
        if UI.ShowExportPopup then
            UI:ShowExportPopup(UI:GetDiagnostics(), "Diagnostics — paste into a bug report or Discord")
        end
    end)

    return panel
end

-- ==========================================
-- REFRESH
-- ==========================================

function UI:RefreshAboutPage()
    local mainFrame = self.mainFrame
    if mainFrame and mainFrame.pageTitle then
        mainFrame.pageTitle:SetText("About FlipQueue")
    end
    if self._HideAllActionBtns then self._HideAllActionBtns() end

    if not aboutPage then
        CreateAboutPanel(self.tableContainer)
    end

    -- Keep the version label live (e.g. if ns.VERSION was unset at panel-creation)
    if versionLabel then
        versionLabel:SetText("v" .. (ns.VERSION or "dev"))
    end

    aboutPage:Show()

    if mainFrame and mainFrame.statusText then
        mainFrame.statusText:SetText(self:GetVersionLine())
    end
end

function UI:HideAboutPage()
    if aboutPage then aboutPage:Hide() end
end
