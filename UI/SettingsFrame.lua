-- UI/SettingsFrame.lua
-- Settings page rendered inside the main window content area
local addonName, ns = ...

local UI = ns.UI

local settingsPanel
local settingsWidgets = {}

-- Layout constants
local LEFT_MARGIN = 12
local RIGHT_MARGIN = -12
local SECTION_SPACING = 14
local ITEM_SPACING = 6
local DESC_COLOR = {0.6, 0.6, 0.6}

--------------------------
-- Collapsible Section Header
--------------------------

local sectionContainers = {}  -- sectionKey -> { container, header, content, collapsed, contentHeight }

local function CreateCollapsibleSection(parent, yOffset, sectionKey, title, summary)
    -- Container holds header + content
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    container:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    -- Divider line
    local divider = container:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", container, "TOPLEFT", LEFT_MARGIN, 0)
    divider:SetPoint("RIGHT", container, "RIGHT", RIGHT_MARGIN, 0)
    divider:SetColorTexture(0.35, 0.35, 0.45, 0.6)

    -- Header row (clickable)
    local headerBtn = CreateFrame("Button", nil, container)
    headerBtn:SetHeight(22)
    headerBtn:SetPoint("TOPLEFT", container, "TOPLEFT", LEFT_MARGIN, -4)
    headerBtn:SetPoint("RIGHT", container, "RIGHT", RIGHT_MARGIN, 0)

    local arrow = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetPoint("LEFT", headerBtn, "LEFT", 0, 0)
    arrow:SetTextColor(0.7, 0.7, 0.7)

    local label = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    label:SetTextColor(0.9, 0.8, 0.3)
    label:SetText(title)

    local summaryText = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    summaryText:SetPoint("LEFT", label, "RIGHT", 8, 0)
    summaryText:SetPoint("RIGHT", headerBtn, "RIGHT", 0, 0)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetTextColor(0.5, 0.5, 0.5)
    summaryText:SetText(summary or "")

    -- Highlight on hover
    local hl = headerBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.2, 0.2, 0.3, 0.2)

    -- Content container (holds all settings in this section)
    local sectionContent = CreateFrame("Frame", nil, container)
    sectionContent:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -26)
    sectionContent:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    -- Default to collapsed; user uncollapsing sets collapsed[key] = false explicitly
    local collapsed = not ns.db or ns.db.settings.collapsed[sectionKey] == nil or ns.db.settings.collapsed[sectionKey]

    local section = {
        container = container,
        headerBtn = headerBtn,
        arrow = arrow,
        summaryText = summaryText,
        content = sectionContent,
        collapsed = collapsed,
        contentHeight = 0,
        sectionKey = sectionKey,
    }

    local function UpdateLayout()
        if section.collapsed then
            arrow:SetText("+")
            sectionContent:Hide()
            summaryText:Show()
            container:SetHeight(28)
        else
            arrow:SetText("-")
            sectionContent:Show()
            summaryText:Hide()
            container:SetHeight(26 + section.contentHeight)
        end
    end

    headerBtn:SetScript("OnClick", function()
        section.collapsed = not section.collapsed
        if ns.db then ns.db.settings.collapsed[sectionKey] = section.collapsed end
        UpdateLayout()
        -- Reflow all sections below
        if UI.ReflowSettings then UI:ReflowSettings() end
    end)

    section.UpdateLayout = UpdateLayout
    UpdateLayout()

    sectionContainers[sectionKey] = section
    return section
end

--------------------------
-- Checkbox with inline description
--------------------------

local function CreateSettingsCheckbox(parent, yOffset, title, desc, settingKey)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)

    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

    -- Title text (beside checkbox)
    cb.text:SetText(title)
    cb.text:SetFontObject("GameFontHighlightSmall")

    -- Description text (below, indented to align with title)
    local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    descText:SetPoint("TOPLEFT", cb.text, "BOTTOMLEFT", 0, -1)
    descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    descText:SetText(desc)
    descText:SetSpacing(1)

    cb:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.settings[settingKey] = self:GetChecked()
        end
    end)

    cb.settingKey = settingKey
    cb.descText = descText

    -- Calculate row height dynamically based on description text
    row:SetScript("OnShow", function(self)
        local descH = descText:GetStringHeight() or 12
        self:SetHeight(22 + descH + 4)
    end)

    -- Initial height estimate
    row:SetHeight(38)

    return cb, 42 -- return widget + estimated height consumed
end

-- (#155) Tri-state action mode (auto / manual / disabled). Returns a
-- compound widget table with the three buttons; clicking each sets the
-- mode. Reads/writes ns.db.settings[settingKey].
local function CreateSettingsTriMode(parent, yOffset, title, desc, settingKey)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)
    row:SetHeight(46)

    local titleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleText:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    titleText:SetText(title)

    local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    descText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
    descText:SetPoint("RIGHT", row, "RIGHT", -200, 0)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    descText:SetText(desc)

    local CHOICES = { "auto", "manual", "disabled" }
    local LABELS  = { auto = "Auto", manual = "Manual", disabled = "Off" }
    local buttons = {}

    local function refresh()
        local current = ns.db and ns.db.settings[settingKey] or "manual"
        for _, mode in ipairs(CHOICES) do
            local btn = buttons[mode]
            if btn then
                if mode == current then
                    btn:SetBackdropColor(0.2, 0.4, 0.2, 1)
                    btn.text:SetTextColor(1, 1, 1)
                else
                    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
                    btn.text:SetTextColor(0.7, 0.7, 0.7)
                end
            end
        end
    end

    local btnW = 56
    local x = 0
    for i = #CHOICES, 1, -1 do
        local mode = CHOICES[i]
        local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
        btn:SetSize(btnW, 22)
        btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -x, -2)
        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(LABELS[mode])
        btn:SetScript("OnClick", function()
            if ns.db then
                ns.db.settings[settingKey] = mode
                refresh()
                if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
                if ns.UI and ns.UI.RefreshMini then ns.UI:RefreshMini() end
            end
        end)
        buttons[mode] = btn
        x = x + btnW + 2
    end

    refresh()

    row.settingKey = settingKey
    row.descText = descText
    row.refresh = refresh
    row.buttons = buttons

    row:SetScript("OnShow", function(self)
        local descH = descText:GetStringHeight() or 12
        self:SetHeight(math.max(46, 16 + descH + 12))
        refresh()
    end)

    return row, 50
end

--------------------------
-- Button with inline description
--------------------------

local function CreateSettingsButton(parent, yOffset, label, desc, width, onClick)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)

    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
    btn:SetSize(width, 24)
    btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
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

    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.25, 0.35, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.2, 1)
    end)

    local totalHeight = 28

    -- Optional description beside button
    if desc and desc ~= "" then
        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText(desc)
    end

    row:SetHeight(totalHeight)
    return btn, totalHeight
end

local function CreateSettingsDropdown(parent, yOffset, title, desc, settingKey, options, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_MARGIN, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", RIGHT_MARGIN, 0)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(title)

    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
    btn:SetSize(160, 22)
    btn:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    btn:SetBackdropColor(0.15, 0.15, 0.2, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("LEFT", btn, "LEFT", 6, 0)

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetText("v")

    if desc and desc ~= "" then
        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText(desc)
    end

    -- Menu frame
    local menu = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(160)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    menu:SetBackdropColor(0.1, 0.1, 0.15, 0.98)
    menu:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)
    menu:Hide()

    local menuBtns = {}
    for i, opt in ipairs(options) do
        local mb = CreateFrame("Button", nil, menu)
        mb:SetHeight(20)
        mb:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 20)
        mb:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
        mb.text = mb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mb.text:SetPoint("LEFT", mb, "LEFT", 4, 0)
        mb.text:SetText(opt.label)
        local hl = mb:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.3, 0.3, 0.5, 0.3)
        mb:SetScript("OnClick", function()
            if ns.db then ns.db.settings[settingKey] = opt.value end
            btn.text:SetText(opt.label)
            menu:Hide()
            if onChange then onChange(opt.value) end
        end)
        menuBtns[i] = mb
    end
    menu:SetHeight(8 + #options * 20)

    btn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide() else menu:Show() end
    end)
    menu:SetScript("OnLeave", function(self)
        C_Timer.After(0.2, function()
            if not self:IsMouseOver() and not btn:IsMouseOver() then
                self:Hide()
            end
        end)
    end)

    function btn:SetValue(value)
        for _, opt in ipairs(options) do
            if opt.value == value then
                btn.text:SetText(opt.label)
                return
            end
        end
        btn.text:SetText(value or "?")
    end

    local totalHeight = 40
    row:SetHeight(totalHeight)
    return btn, totalHeight
end

--------------------------
-- Main Panel
--------------------------

-- Section ordering for reflow
local sectionOrder = { "automation", "imports", "items", "gold", "auctionhouse", "notifications", "miniview", "toolbox", "saleslog", "data", "deletedchars", "multiaccount" }

-- Rebuild the pooled row list inside the "Deleted Characters" section.
-- Keeps the section height in sync with how many tombstones exist. Called
-- from RefreshSettings (initial render + after add/remove events).
local function RefreshDeletedCharactersSection()
    local container = settingsWidgets.deletedContainer
    local section   = settingsWidgets._deletedSection
    if not container or not section then return end

    local rows = settingsWidgets.deletedRows
    for _, r in ipairs(rows) do r:Hide() end

    local deleted = (ns and ns.GetDeletedCharacters) and ns:GetDeletedCharacters() or {}
    local ROW_H = 26
    local y = 0

    -- Height above the row container: desc (34) + Clean Orphaned Data
    -- button row (28) + ITEM_SPACING (6) + vertical gap (6) = 74. Kept
    -- as a constant so the calc below stays readable.
    local HEADER_ABOVE_ROWS = 74

    if #deleted == 0 then
        -- Empty state: single line reassuring the user.
        local empty = settingsWidgets.deletedEmpty
        if not empty then
            empty = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            empty:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            empty:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            empty:SetJustifyH("LEFT")
            empty:SetText("No deleted characters.")
            settingsWidgets.deletedEmpty = empty
        end
        empty:Show()
        container:SetHeight(20)
        section.contentHeight = HEADER_ABOVE_ROWS + 20 + 8
    else
        if settingsWidgets.deletedEmpty then
            settingsWidgets.deletedEmpty:Hide()
        end

        for i, entry in ipairs(deleted) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, container)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()

                row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.nameText:SetJustifyH("LEFT")

                row.realmText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.realmText:SetPoint("LEFT", row, "LEFT", 160, 0)

                row.whenText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.whenText:SetPoint("LEFT", row, "LEFT", 300, 0)

                row.restoreBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                row.restoreBtn:SetSize(78, 20)
                row.restoreBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row.restoreBtn:SetBackdrop({
                    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = 8,
                    insets = {left = 1, right = 1, top = 1, bottom = 1},
                })
                row.restoreBtn:SetBackdropColor(0.12, 0.24, 0.12, 1)
                row.restoreBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 0.8)
                row.restoreBtn.text = row.restoreBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.restoreBtn.text:SetPoint("CENTER")
                row.restoreBtn.text:SetText("|cff66ff66Restore|r")
                row.restoreBtn:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(0.18, 0.32, 0.18, 1)
                end)
                row.restoreBtn:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(0.12, 0.24, 0.12, 1)
                end)

                rows[i] = row
            end
            row:SetHeight(ROW_H)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            row.bg:SetColorTexture(
                i % 2 == 0 and 0.08 or 0.05,
                i % 2 == 0 and 0.08 or 0.05,
                i % 2 == 0 and 0.12 or 0.09,
                0.6)

            local name = entry.charKey:match("^(.-)%-") or entry.charKey
            local realm = entry.charKey:match("%-(.+)$") or ""
            row.nameText:SetText(name)
            row.realmText:SetText(realm)
            row.whenText:SetText(ns:FormatRelativeTime(entry.deletedAt) ..
                (entry.syndicatorPurged and " (purged)" or ""))

            local capturedKey = entry.charKey
            row.restoreBtn:SetScript("OnClick", function()
                ns:RestoreCharacter(capturedKey)
                ns:Print(ns.COLORS.GREEN .. "Restored " .. capturedKey ..
                    ". It will reappear on next scan.|r")
                if UI.RefreshSettings then UI:RefreshSettings() end
                if UI.Refresh then UI:Refresh() end
            end)

            row:Show()
            y = y - ROW_H
        end

        container:SetHeight(math.abs(y))
        section.contentHeight = HEADER_ABOVE_ROWS + math.abs(y) + 8
    end

    if section.UpdateLayout then section.UpdateLayout() end
    if UI.ReflowSettings then UI:ReflowSettings() end
end

UI._RefreshDeletedCharactersSection = RefreshDeletedCharactersSection

--------------------------
-- Tools Drawer section (FQ-005 / #115)
--------------------------

-- Whether the native-macro picker list is currently expanded.
local toolboxPickerOpen = false

local MINIBTN_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- Rebuild the Tools Drawer settings section. Mirrors the
-- RefreshDeletedCharactersSection pattern: pooled rows, recomputed height.
local function RefreshToolboxSection()
    local container = settingsWidgets.toolboxContainer
    local section   = settingsWidgets._toolboxSection
    local TR        = ns.ToolRegistry
    if not (container and section and ns.db and TR) then return end

    local tb = TR.EnsureConfig and TR:EnsureConfig() or nil
    if not tb then return end

    local rows = settingsWidgets.toolboxRows
    if not rows then rows = {}; settingsWidgets.toolboxRows = rows end
    for _, r in ipairs(rows) do r:Hide() end

    local ROW_H = 24
    local rowIndex, y = 0, 0

    -- A row carries every possible widget; emitters show/hide what they need.
    local function AcquireRow()
        rowIndex = rowIndex + 1
        local row = rows[rowIndex]
        if not row then
            row = CreateFrame("Frame", nil, container)
            row:SetHeight(ROW_H)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(20, 20)
            row.check:SetPoint("LEFT", row, "LEFT", 2, 0)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.label:SetJustifyH("LEFT")
            row.label:SetWordWrap(false)

            local function MiniBtn(w)
                local b = CreateFrame("Button", nil, row, "BackdropTemplate")
                b:SetSize(w, 18)
                b:SetBackdrop(MINIBTN_BACKDROP)
                b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                b.text:SetPoint("CENTER")
                return b
            end
            row.up     = MiniBtn(22)
            row.down   = MiniBtn(22)
            row.action = MiniBtn(58)
            row.up:SetPoint("RIGHT", row, "RIGHT", -28, 0)
            row.down:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.action:SetPoint("RIGHT", row, "RIGHT", -4, 0)

            rows[rowIndex] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        row.check:Hide(); row.icon:Hide()
        row.up:Hide(); row.down:Hide(); row.action:Hide()
        row.up:SetScript("OnClick", nil)
        row.down:SetScript("OnClick", nil)
        row.action:SetScript("OnClick", nil)
        row.check:SetScript("OnClick", nil)
        -- Restore the default action-button anchor; the macro-toggle row
        -- re-anchors it LEFT, so every reuse must reset it first.
        row.action:ClearAllPoints()
        row.action:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.action:SetWidth(58)
        row.bg:SetColorTexture(rowIndex % 2 == 0 and 0.07 or 0.04,
                               rowIndex % 2 == 0 and 0.07 or 0.04,
                               rowIndex % 2 == 0 and 0.10 or 0.07, 0.5)
        row.label:ClearAllPoints()
        row.label:SetWordWrap(false)
        row:Show()
        y = y - ROW_H
        return row
    end

    -- Style one of the pooled mini buttons. tone: "normal"|"good"|"bad".
    local function StyleBtn(b, label, enabled, tone, onClick)
        b.text:SetText(label)
        b:Show()
        if enabled then
            b:Enable()
            if tone == "good" then
                b:SetBackdropColor(0.10, 0.22, 0.10, 1)
                b:SetBackdropBorderColor(0.3, 0.55, 0.3, 0.9)
                b.text:SetTextColor(0.5, 1, 0.5)
            elseif tone == "bad" then
                b:SetBackdropColor(0.24, 0.10, 0.10, 1)
                b:SetBackdropBorderColor(0.55, 0.3, 0.3, 0.9)
                b.text:SetTextColor(1, 0.6, 0.6)
            else
                b:SetBackdropColor(0.15, 0.15, 0.2, 1)
                b:SetBackdropBorderColor(0.35, 0.35, 0.45, 0.9)
                b.text:SetTextColor(0.9, 0.9, 0.9)
            end
            b:SetScript("OnClick", onClick)
        else
            b:Disable()
            b:SetBackdropColor(0.10, 0.10, 0.12, 0.7)
            b:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.6)
            b.text:SetTextColor(0.4, 0.4, 0.4)
            b:SetScript("OnClick", nil)
        end
    end

    local function Rebuild()
        RefreshToolboxSection()
        if UI.RefreshToolDrawer then UI:RefreshToolDrawer() end
    end

    -- Sub-header row.
    local function EmitHeader(text)
        local row = AcquireRow()
        row.bg:SetColorTexture(0, 0, 0, 0)
        row.label:SetFontObject("GameFontNormal")
        row.label:SetTextColor(0.9, 0.8, 0.3)
        row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.label:SetText(text)
    end

    -- Dim informational line.
    local function EmitInfo(text, indent)
        local row = AcquireRow()
        row.bg:SetColorTexture(0, 0, 0, 0)
        row.label:SetFontObject("GameFontDisableSmall")
        row.label:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        row.label:SetPoint("LEFT", row, "LEFT", 6 + (indent or 0), 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.label:SetText(text)
    end

    -- Wire a row's up/down reorder pair. moveFn(dir) does the actual move.
    local function EmitReorder(row, idx, total, moveFn)
        StyleBtn(row.up, "\226\150\178", idx > 1, "normal", function()
            moveFn(-1); Rebuild()
        end)
        StyleBtn(row.down, "\226\150\188", idx < total, "normal", function()
            moveFn(1); Rebuild()
        end)
    end

    -- A drawer tool: show/hide checkbox + icon + label + reorder buttons.
    local function EmitTool(tool, idx, total)
        local row = AcquireRow()
        local hidden = TR:IsHidden(tool.id)

        row.check:Show()
        row.check:SetChecked(not hidden)
        row.check:SetScript("OnClick", function(self)
            TR:SetHidden(tool.id, not self:GetChecked())
            Rebuild()
        end)

        row.icon:Show()
        row.icon:SetPoint("LEFT", row, "LEFT", 26, 0)
        row.icon:SetTexture(tool.icon or tool.iconFallback or TR.MISSING_ICON)
        row.icon:SetDesaturated(hidden)

        local typeTag
        if tool.type == "macro" then
            typeTag = tool.missing and "|cffff5555macro (missing)|r" or "|cff888888macro|r"
        elseif tool.type == "action" then
            typeTag = "|cff888888action|r"
        else
            typeTag = "|cff888888service|r"
        end
        row.label:SetFontObject("GameFontHighlightSmall")
        row.label:SetTextColor(hidden and 0.5 or 0.95, hidden and 0.5 or 0.95,
                               hidden and 0.5 or 0.95)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -56, 0)
        row.label:SetText(tool.label .. "  " .. typeTag)

        EmitReorder(row, idx, total, function(dir) TR:MoveTool(tool.id, dir) end)
    end

    -- Per-method state string, keyed off the registry's shared classifier.
    local METHOD_STATE = {
        active      = "|cff66cc66active|r",
        cooldown    = "|cffffcc66on cooldown|r",
        unavailable = "|cff888888unavailable|r",
        ready       = "|cff888888owned|r",
    }

    -- A summon method under a service tool: icon + label + reorder buttons.
    local function EmitMethod(tool, eval, idx, total)
        local row = AcquireRow()
        row.icon:Show()
        row.icon:SetPoint("LEFT", row, "LEFT", 30, 0)
        row.icon:SetTexture(eval.icon or tool.iconFallback)
        row.icon:SetDesaturated(false)

        row.label:SetFontObject("GameFontHighlightSmall")
        row.label:SetTextColor(0.85, 0.85, 0.9)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -56, 0)
        row.label:SetText(eval.dispatchName .. "  " .. METHOD_STATE[TR:ClassifyEval(eval)])

        local key = TR.MethodKey(eval.method)
        EmitReorder(row, idx, total, function(dir) TR:MoveMethod(tool, key, dir) end)
    end

    -- An already-added macro tool: icon + name + Remove button.
    local function EmitMacro(name)
        local row = AcquireRow()
        local def = TR.BuildMacroTool(name)
        row.icon:Show()
        row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.icon:SetTexture(def.icon)
        row.icon:SetDesaturated(def.missing)
        row.label:SetFontObject("GameFontHighlightSmall")
        row.label:SetTextColor(0.9, 0.9, 0.9)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -68, 0)
        row.label:SetText(def.missing and (name .. "  |cffff5555(missing)|r") or name)
        StyleBtn(row.action, "Remove", true, "bad", function()
            TR:RemoveMacro(name); Rebuild()
        end)
    end

    -- A native WoW macro the player can add as a tool.
    local function EmitPicker(macro)
        local row = AcquireRow()
        row.icon:Show()
        row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.icon:SetTexture(macro.icon or TR.MISSING_ICON)
        row.icon:SetDesaturated(false)
        row.label:SetFontObject("GameFontHighlightSmall")
        row.label:SetTextColor(0.85, 0.85, 0.9)
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -68, 0)
        row.label:SetText(macro.name ..
            (macro.perChar and "  |cff888888(this character)|r" or ""))
        StyleBtn(row.action, "Add", true, "good", function()
            TR:AddMacro(macro.name)
            toolboxPickerOpen = false
            Rebuild()
        end)
    end

    ----------------------------------------------------------------
    -- Section 1: the ordered drawer tool list (+ per-service methods)
    ----------------------------------------------------------------
    EmitHeader("Drawer tools")
    local allTools = TR:GetAllTools()
    for i, tool in ipairs(allTools) do
        EmitTool(tool, i, #allTools)
        if tool.type == "service" and not TR:IsHidden(tool.id) then
            local evals = TR:GetOwnedMethodEvals(tool)
            if #evals >= 2 then
                for j, e in ipairs(evals) do
                    EmitMethod(tool, e, j, #evals)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Section 2: macro tools
    ----------------------------------------------------------------
    EmitHeader("Macro tools")
    EmitInfo("Add one of your WoW macros as a one-click drawer tool. "
        .. "It keeps the macro's own name and icon.")
    if #tb.macros == 0 then
        EmitInfo("No macros added yet.")
    else
        for _, name in ipairs(tb.macros) do EmitMacro(name) end
    end

    do
        local row = AcquireRow()
        row.bg:SetColorTexture(0, 0, 0, 0)
        StyleBtn(row.action, toolboxPickerOpen and "Done" or "Add macro",
            true, toolboxPickerOpen and "normal" or "good", function()
                toolboxPickerOpen = not toolboxPickerOpen
                Rebuild()
            end)
        -- The action button anchors RIGHT; widen the click target's label.
        row.action:ClearAllPoints()
        row.action:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.action:SetWidth(90)
    end

    if toolboxPickerOpen then
        local added = {}
        for _, n in ipairs(tb.macros) do added[n] = true end
        local macros = TR:ListWoWMacros()
        local shown = 0
        for _, m in ipairs(macros) do
            if not added[m.name] then
                EmitPicker(m)
                shown = shown + 1
            end
        end
        if shown == 0 then
            EmitInfo("No other macros found. Create macros with /macro.")
        end
    end

    container:SetHeight(math.max(10, math.abs(y)))
    section.contentHeight = (settingsWidgets._toolboxHeaderAbove or 38)
        + math.abs(y) + 8
    if section.UpdateLayout then section.UpdateLayout() end
    if UI.ReflowSettings then UI:ReflowSettings() end
end

UI._RefreshToolboxSection = RefreshToolboxSection

function UI:ReflowSettings()
    if not settingsWidgets.contentFrame then return end
    local y = -6
    for _, key in ipairs(sectionOrder) do
        local section = sectionContainers[key]
        if section then
            section.container:ClearAllPoints()
            section.container:SetPoint("TOPLEFT", settingsWidgets.contentFrame, "TOPLEFT", 0, y)
            section.container:SetPoint("RIGHT", settingsWidgets.contentFrame, "RIGHT", 0, 0)
            section.UpdateLayout()
            if section.collapsed then
                y = y - 28 - SECTION_SPACING
            else
                y = y - (26 + section.contentHeight) - SECTION_SPACING
            end
        end
    end
    settingsWidgets.contentFrame:SetHeight(math.abs(y) + 40)
end

function UI:CreateSettingsPanel(parent)
    if settingsPanel then return settingsPanel end

    -- Scrollable settings container
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(scroll:GetWidth())
    content:SetHeight(1200)
    scroll:SetScrollChild(content)
    settingsWidgets.contentFrame = content

    scroll:SetScript("OnSizeChanged", function(sf, w)
        content:SetWidth(w)
    end)

    local y = -6
    local h

    ------------------------------------------------
    -- Section: Scanning & Automation
    ------------------------------------------------
    local secAuto = CreateCollapsibleSection(content, y, "automation",
        "General",
        "Scanning, deal lists, posting quantities, alerts")
    local sc = secAuto.content  -- widgets go here
    local sy = 0  -- y offset within section

    settingsWidgets.autoScan, h = CreateSettingsCheckbox(sc, sy,
        "Auto-scan bags on login",
        "Automatically scan your character's bags when you log in so FlipQueue knows what you're carrying.",
        "autoScan")
    sy = sy - h - ITEM_SPACING

    -- Auto-pull / auto-deposit / auto-deposit-all moved to Characters page
    -- (per-character settings with global defaults).
    -- Bank/warbank/gold settings moved to the dedicated "Bank & Warbank"
    -- section below. TSM behavior toggles moved to the TSM Integration page.

    settingsWidgets.skipUnassigned, h = CreateSettingsCheckbox(sc, sy,
        "Skip deals with no character",
        "When generating a to-do list, skip deals that have no matching character on the required realm instead of creating 'new character' tasks. Useful when you only want tasks for realms you already have characters on.",
        "skipUnassigned")
    sy = sy - h - ITEM_SPACING

    -- Default sell quantity slider
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(68)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Default sell quantity")

        local slider = CreateFrame("Slider", "FlipQueueSellQtySlider", row, "OptionsSliderTemplate")
        slider:SetWidth(180)
        slider:SetHeight(16)
        slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -8)
        slider:SetMinMaxValues(1, 20)
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        slider.Low:SetText("1")
        slider.High:SetText("20")

        local valLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valLabel:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        valLabel:SetTextColor(1, 1, 1)

        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            valLabel:SetText(tostring(value))
            if ns.db then
                ns.db.settings.defaultSellQty = value
            end
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("Baseline quantity per item when posting or pulling from bank.")

        settingsWidgets.sellQtySlider = slider
        settingsWidgets.sellQtyLabel = valLabel
    end
    sy = sy - 68 - ITEM_SPACING

    -- Sell quantity mode toggle
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(56)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Quantity source")

        local function CreateModeBtn(label, parent)
            local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:SetHeight(20)
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
            btn:SetWidth(btn.text:GetStringWidth() + 16)
            btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.3, 1) end)
            btn:SetScript("OnLeave", function(self)
                if not self._active then self:SetBackdropColor(0.15, 0.15, 0.2, 1) end
            end)
            return btn
        end

        local fixedBtn = CreateModeBtn("Always fixed", row)
        fixedBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

        local tsmBtn = CreateModeBtn("TSM if available", row)
        tsmBtn:SetPoint("LEFT", fixedBtn, "RIGHT", 4, 0)

        local function UpdateSellQtyMode()
            local mode = ns.db and ns.db.settings.sellQtyMode or "tsm"
            fixedBtn._active = (mode == "fixed")
            tsmBtn._active = (mode == "tsm")
            fixedBtn:SetBackdropColor(mode == "fixed" and 0.2 or 0.15, mode == "fixed" and 0.4 or 0.15, mode == "fixed" and 0.2 or 0.2, 1)
            tsmBtn:SetBackdropColor(mode == "tsm" and 0.2 or 0.15, mode == "tsm" and 0.4 or 0.15, mode == "tsm" and 0.2 or 0.2, 1)
        end

        fixedBtn:SetScript("OnClick", function()
            if ns.db then ns.db.settings.sellQtyMode = "fixed" end
            UpdateSellQtyMode()
        end)
        tsmBtn:SetScript("OnClick", function()
            if ns.db then ns.db.settings.sellQtyMode = "tsm" end
            UpdateSellQtyMode()
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", fixedBtn, "BOTTOMLEFT", 0, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("'Always fixed' uses the slider above. 'TSM if available' uses TSM's Post Cap when the item has an Auctioning operation, otherwise falls back to the fixed value.")

        settingsWidgets.sellQtyModeFixed = fixedBtn
        settingsWidgets.sellQtyModeTSM = tsmBtn
        settingsWidgets.updateSellQtyMode = UpdateSellQtyMode
    end
    sy = sy - 56 - ITEM_SPACING

    -- Expiry alert timer slider
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(68)

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Expiry alert timer (minutes)")

        local slider = CreateFrame("Slider", "FlipQueueExpiryAlertSlider", row, "OptionsSliderTemplate")
        slider:SetWidth(180)
        slider:SetHeight(16)
        slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -8)
        slider:SetMinMaxValues(5, 360)
        slider:SetValueStep(5)
        slider:SetObeyStepOnDrag(true)
        slider.Low:SetText("5m")
        slider.High:SetText("6h")

        local valLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valLabel:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        valLabel:SetTextColor(1, 1, 1)

        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value / 5 + 0.5) * 5
            local displayStr = value >= 60 and string.format("%.1fh", value / 60) or (value .. "m")
            valLabel:SetText(displayStr)
            if ns.db then
                ns.db.settings.expiryAlertMinutes = value
            end
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("Show 'expiring soon' alerts for auctions within this many minutes of expiry. Affects login messages, To-Do page, and mini view.")

        settingsWidgets.expiryAlertSlider = slider
        settingsWidgets.expiryAlertLabel = valLabel
    end
    sy = sy - 68 - SECTION_SPACING

    -- Bank Tab Selection moved to Characters page (per-character config panel)

    -- Tutorial + Setup Wizard buttons (relocated from the multi-account tail
    -- section so they sit with the rest of the general account-level controls).
    -- The About page lives in the sidebar nav now, so its in-settings link
    -- was removed.
    do
        local tutorialBtn = CreateFrame("Button", nil, sc, "BackdropTemplate")
        tutorialBtn:SetSize(180, 26)
        tutorialBtn:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        tutorialBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        tutorialBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        tutorialBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        local tutBtnText = tutorialBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tutBtnText:SetPoint("CENTER")
        tutBtnText:SetText("Show Tutorial Again")
        tutorialBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.3, 1) end)
        tutorialBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.15, 0.2, 1) end)
        tutorialBtn:SetScript("OnClick", function()
            ns.db.settings.tutorialDone = false
            UI._tutorialActive = true
            UI._tutorialStep = 1
            UI._tutorialCallout = 1
            UI.currentPage = "todo"
            UI:Refresh()
        end)

        local tutDesc = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tutDesc:SetPoint("LEFT", tutorialBtn, "RIGHT", 8, 0)
        tutDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        tutDesc:SetText("Walk through the first-time setup again")
    end
    sy = sy - 30 - ITEM_SPACING

    do
        local wizardBtn = CreateFrame("Button", nil, sc, "BackdropTemplate")
        wizardBtn:SetSize(180, 26)
        wizardBtn:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        wizardBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        wizardBtn:SetBackdropColor(0.15, 0.15, 0.2, 1)
        wizardBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        local wizBtnText = wizardBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        wizBtnText:SetPoint("CENTER")
        wizBtnText:SetText("Run Setup Wizard")
        wizardBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.3, 1) end)
        wizardBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.15, 0.2, 1) end)
        wizardBtn:SetScript("OnClick", function()
            ns.db.settings.setupDone = false
            UI:Refresh()
        end)

        local wizDesc = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        wizDesc:SetPoint("LEFT", wizardBtn, "RIGHT", 8, 0)
        wizDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        wizDesc:SetText("Walk through settings step by step")
    end
    sy = sy - 30 - SECTION_SPACING

    secAuto.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Imports (FQ-177)
    ------------------------------------------------
    local secImports = CreateCollapsibleSection(content, y, "imports",
        "Imports",
        "Which FlippingPal column flows into task prices")
    sc = secImports.content
    sy = 0

    settingsWidgets.fpPriceSource, h = CreateSettingsDropdown(sc, sy,
        "FlippingPal price source",
        "Which FP column flows into expectedPrice when /fq generate builds a task. Listing = aggressive recommendation; Sale Avg = conservative historical median; Auto = Listing unless it's >10x TSM region market, then Sale Avg. Applies on next generate; existing tasks keep their stored price.",
        "fpPriceSource",
        {
            { label = "Listing price",  value = "listing" },
            { label = "Sale Avg",       value = "saleavg" },
            { label = "Auto (TSM-clamped)", value = "auto" },
        })
    sy = sy - h - SECTION_SPACING

    secImports.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Item Management (#148 master + item-related settings)
    ------------------------------------------------
    local secItems = CreateCollapsibleSection(content, y, "items",
        "Item Management",
        "Manage my items, reagents, deposit overflow, batch size")
    sc = secItems.content
    sy = 0

    -- Master switch — top of the section. When OFF, every item-related
    -- row in this section dims and goes non-interactive (handled in
    -- RefreshSettings).
    settingsWidgets.manageItems, h = CreateSettingsCheckbox(sc, sy,
        "Manage my items",
        "Allow FlipQueue to move items between your bag, bank, and warbank. " ..
        "Off: FlipQueue won't plan or execute item moves for this character. " ..
        "Per-character overrides on the Characters page take precedence.",
        "manageItems")
    settingsWidgets.manageItems:HookScript("OnClick", function()
        if UI.RefreshContextDrawer then UI:RefreshContextDrawer() end
        if UI.currentPage == "characters" and UI.RefreshCharactersPage then
            UI:RefreshCharactersPage()
        end
        if UI.RefreshSettings then UI:RefreshSettings() end
    end)
    sy = sy - h - SECTION_SPACING

    -- (#155) Reagents are now their own action class with a tri-state mode.
    -- Replaces the old depositIncludeReagents bool which conflated "include
    -- in extras" with "should auto-fire."
    settingsWidgets.reagentsModeRow, h = CreateSettingsTriMode(sc, sy,
        "Reagent deposits",
        "Auto: deposit non-task reagents (Tradegoods) to warbank on bank open. Manual: button works, no auto-fire. Off: hidden everywhere.",
        "reagentsMode")
    sy = sy - h - ITEM_SPACING

    -- Deposit overflow (nested setting — built by hand instead of via
    -- CreateSettingsCheckbox which only writes to ns.db.settings[key]).
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        settingsWidgets.depositOverflowRow = row

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        cb.text:SetText("Deposit to bank when warbank is full")
        cb.text:SetFontObject("GameFontHighlightSmall")

        local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", cb.text, "BOTTOMLEFT", 0, -1)
        desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        desc:SetText("When trying to deposit to the warbank, automatically deposit to the player bank if the warbank is full.")

        cb:SetScript("OnClick", function(self)
            if not (ns.db and ns.db.settings.depositOverflow) then return end
            ns.db.settings.depositOverflow.enabled = self:GetChecked() and true or false
            if settingsWidgets.depositOverflowCrossStack then
                local sub = settingsWidgets.depositOverflowCrossStack
                if ns.db.settings.depositOverflow.enabled then
                    sub:Enable()
                    sub.text:SetTextColor(1, 1, 1)
                else
                    sub:Disable()
                    sub.text:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end)

        row:SetScript("OnShow", function(self)
            local descH = desc:GetStringHeight() or 12
            self:SetHeight(22 + descH + 4)
        end)
        row:SetHeight(38)
        settingsWidgets.depositOverflow = cb
    end
    sy = sy - 42 - ITEM_SPACING

    -- Sub-setting: combine partial stacks across both banks
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN + 20, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        settingsWidgets.depositOverflowCrossStackRow = row

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        cb.text:SetText("Combine partial stacks across both banks")
        cb.text:SetFontObject("GameFontHighlightSmall")

        local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", cb.text, "BOTTOMLEFT", 0, -1)
        desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        desc:SetText("When depositing to the player bank because the warbank is full, also top up existing stacks of the same item. Otherwise only empty slots in the bank are used.")

        cb:SetScript("OnClick", function(self)
            if not (ns.db and ns.db.settings.depositOverflow) then return end
            ns.db.settings.depositOverflow.crossStack = self:GetChecked() and true or false
        end)

        row:SetScript("OnShow", function(self)
            local descH = desc:GetStringHeight() or 12
            self:SetHeight(20 + descH + 4)
        end)
        row:SetHeight(36)
        settingsWidgets.depositOverflowCrossStack = cb
    end
    sy = sy - 40 - ITEM_SPACING

    -- Items per batch slider
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(68)
        settingsWidgets.batchSizeRow = row

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Items moved per batch")

        local slider = CreateFrame("Slider", "FlipQueueBatchSizeSlider", row, "OptionsSliderTemplate")
        slider:SetWidth(180)
        slider:SetHeight(16)
        slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -8)
        slider:SetMinMaxValues(1, 10)
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        slider.Low:SetText("1")
        slider.High:SetText("10")

        local valLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valLabel:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        valLabel:SetTextColor(1, 1, 1)

        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            valLabel:SetText(tostring(value))
            if ns.db then
                ns.db.settings.pullBatchSize = value
            end
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("How many items to withdraw or deposit at once. Lower values are safer but slower.")

        settingsWidgets.batchSizeSlider = slider
        settingsWidgets.batchSizeLabel = valLabel
    end
    sy = sy - 68 - SECTION_SPACING

    settingsWidgets.pauseAutoOpsInInstance, h = CreateSettingsCheckbox(sc, sy,
        "Pause bank ops in raids and dungeons",
        "Defer auto-deposit and auto-pull while you're inside a raid, dungeon, " ..
        "battleground, arena, or scenario. Resumes automatically when you leave. " ..
        "Recommended on — protects against rare taint that can break bag clicks " ..
        "if a queue runs while you're under combat lockdown.",
        "pauseAutoOpsInInstance")
    sy = sy - h - ITEM_SPACING

    secItems.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Gold Management (#148 master + gold-related settings)
    ------------------------------------------------
    local secGold = CreateCollapsibleSection(content, y, "gold",
        "Gold Management",
        "Manage my gold, withdrawals, deposits, buffer, Warband Miser integration")
    sc = secGold.content
    sy = 0

    settingsWidgets.manageGold, h = CreateSettingsCheckbox(sc, sy,
        "Manage my gold",
        "Allow FlipQueue to move gold between your bag and warbank for AH " ..
        "fees and buffer maintenance. Off: FlipQueue won't plan or execute " ..
        "gold moves for this character. Per-character overrides on the " ..
        "Characters page take precedence.",
        "manageGold")
    settingsWidgets.manageGold:HookScript("OnClick", function()
        if UI.RefreshContextDrawer then UI:RefreshContextDrawer() end
        if UI.currentPage == "characters" and UI.RefreshCharactersPage then
            UI:RefreshCharactersPage()
        end
        if UI.RefreshSettings then UI:RefreshSettings() end
    end)
    sy = sy - h - SECTION_SPACING

    -- Warband Miser detection banner. If the addon is loaded, FlipQueue's
    -- auto-gold routines defer to it. The override re-takes control.
    if ns.IsWarbandMiserActive and
       C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("WarbandMiser") then
        local banner = CreateFrame("Frame", nil, sc, "BackdropTemplate")
        banner:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        banner:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        banner:SetHeight(48)
        banner:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        banner:SetBackdropColor(0.15, 0.12, 0.05, 0.9)
        banner:SetBackdropBorderColor(0.6, 0.5, 0.2, 0.8)

        local text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", banner, "TOPLEFT", 8, -6)
        text:SetPoint("RIGHT", banner, "RIGHT", -8, 0)
        text:SetJustifyH("LEFT")
        text:SetText(ns.COLORS.YELLOW ..
            "Warband Miser detected.|r FlipQueue's auto-gold settings " ..
            "are disabled while it's running.")

        local overrideCB = CreateFrame("CheckButton", nil, banner, "UICheckButtonTemplate")
        overrideCB:SetSize(18, 18)
        overrideCB:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 6, 4)
        overrideCB:SetChecked(ns.db and ns.db.settings and ns.db.settings.warbandMiserOverride or false)
        overrideCB:SetScript("OnClick", function(self)
            if ns.db then ns.db.settings.warbandMiserOverride = self:GetChecked() and true or false end
        end)
        local cbLabel = banner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cbLabel:SetPoint("LEFT", overrideCB, "RIGHT", 2, 0)
        cbLabel:SetText("Let FlipQueue manage gold anyway")

        settingsWidgets.wmOverride = overrideCB
        sy = sy - 48 - ITEM_SPACING
    end

    -- (#155) Withdraw gold tri-state.
    settingsWidgets.goldWithdrawModeRow, h = CreateSettingsTriMode(sc, sy,
        "Withdraw gold for AH fees and purchases",
        "Auto: withdraw enough on bank open to cover estimated fees + buy tasks. Manual: drawer button works, no auto-fire. Off: hidden everywhere.",
        "goldWithdrawMode")
    sy = sy - h - ITEM_SPACING

    -- Max withdrawal gold input
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(52)
        settingsWidgets.maxWithdrawRow = row

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Maximum gold to withdraw per visit")

        local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        box:SetSize(100, 20)
        box:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -4)
        box:SetAutoFocus(false)
        box:SetMaxLetters(10)
        box:SetNumeric(true)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText()) or 0
            if ns.db then ns.db.settings.maxWithdrawGold = val end
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function(self)
            local val = tonumber(self:GetText()) or 0
            if ns.db then ns.db.settings.maxWithdrawGold = val end
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("Cap how much gold is taken in one visit. 0 means no limit.")

        settingsWidgets.maxWithdrawBox = box
    end
    sy = sy - 52 - ITEM_SPACING

    -- (#155) Deposit gold tri-state.
    settingsWidgets.goldDepositModeRow, h = CreateSettingsTriMode(sc, sy,
        "Deposit extra gold back to the warbank",
        "Auto: deposit excess gold on bank open. Manual: drawer button works, no auto-fire. Off: hidden everywhere.",
        "goldDepositMode")
    sy = sy - h - ITEM_SPACING

    -- Default gold per character (gold buffer)
    do
        local row = CreateFrame("Frame", nil, sc)
        row:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
        row:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
        row:SetHeight(52)
        settingsWidgets.goldBufferRow = row

        local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        title:SetText("Default gold per character (gold to keep)")

        local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        box:SetSize(100, 20)
        box:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -4)
        box:SetAutoFocus(false)
        box:SetMaxLetters(10)
        box:SetNumeric(true)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText()) or 0
            if ns.db then ns.db.settings.goldBuffer = val end
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function(self)
            local val = tonumber(self:GetText()) or 0
            if ns.db then ns.db.settings.goldBuffer = val end
        end)

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        descText:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -4)
        descText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(true)
        descText:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
        descText:SetText("Minimum gold to keep on each character. Used as a floor — if AH fees exceed this, fees win. (Per-character overrides coming in #149.)")

        settingsWidgets.goldBufferBox = box
    end
    sy = sy - 52 - SECTION_SPACING

    secGold.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Auction House
    ------------------------------------------------
    local secAH = CreateCollapsibleSection(content, y, "auctionhouse",
        "Auction House",
        "Posting drawer and AH behavior")
    sc = secAH.content
    sy = 0

    settingsWidgets.ahPostingEnabled, h = CreateSettingsCheckbox(sc, sy,
        "Use FlipQueue for AH posting",
        "When off, FlipQueue won't initiate AH scans or offer post controls — leaves the AH to TSM (or whatever you prefer). The passive scan-cache listener still harvests data when other addons scan.",
        "ahPostingEnabled")
    sy = sy - h - SECTION_SPACING

    settingsWidgets.ahAutoScan, h = CreateSettingsCheckbox(sc, sy,
        "Auto-scan inventory when the Auction House opens",
        "When on, FlipQueue scans bags and issues live AH price queries the moment you open the AH. " ..
        "|cffff7777Strongly recommended OFF if you also use TradeSkillMaster or Auctionator|r — " ..
        "all three addons share Blizzard's global AH query rate limit, and running them in parallel " ..
        "stacks delays into the tens-of-seconds-to-minutes range during posting. " ..
        "With this off, the Scan To-Do / Scan All buttons in the AH drawer are your manual triggers, " ..
        "and FlipQueue still passively reads any prices the other addons fetch.",
        "ahAutoScanOnOpen")
    sy = sy - h - SECTION_SPACING

    secAH.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Notifications
    ------------------------------------------------
    local secNotif = CreateCollapsibleSection(content, y, "notifications",
        "Notifications",
        "Login messages and alerts")
    sc = secNotif.content
    sy = 0

    settingsWidgets.loginMsg, h = CreateSettingsCheckbox(sc, sy,
        "Show login message",
        "Print a chat message on login listing items to post, expired auctions to collect, and other tasks for this character.",
        "showLoginMessage")
    sy = sy - h - SECTION_SPACING

    secNotif.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Mini View
    ------------------------------------------------
    local secMini = CreateCollapsibleSection(content, y, "miniview",
        "Mini View",
        "Overlay, minimap icon, popup positions")
    sc = secMini.content
    sy = 0

    settingsWidgets.showMini, h = CreateSettingsCheckbox(sc, sy,
        "Show mini overlay",
        "Show a compact floating overlay listing current-character tasks. Drag it anywhere on screen. Persists across sessions.",
        "showMini")
    settingsWidgets.showMini:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.settings.showMini = self:GetChecked()
            if self:GetChecked() then
                UI:ShowMini()
            else
                UI:HideMini()
            end
        end
    end)
    sy = sy - h - ITEM_SPACING

    settingsWidgets.hideMiniCombat, h = CreateSettingsCheckbox(sc, sy,
        "Hide mini view in combat",
        "Automatically hide the mini overlay when you enter combat and restore it when combat ends.",
        "hideMiniInCombat")
    sy = sy - h - ITEM_SPACING

    settingsWidgets.hideMiniInstance, h = CreateSettingsCheckbox(sc, sy,
        "Hide mini view in raids and dungeons",
        "Hide the mini overlay while you're inside a raid, dungeon, battleground, " ..
        "arena, or scenario. Restores when you leave. Independent of the combat " ..
        "toggle above — turn either or both on.",
        "hideMiniInInstance")
    sy = sy - h - ITEM_SPACING

    settingsWidgets.showMinimap, h = CreateSettingsCheckbox(sc, sy,
        "Show minimap icon",
        "Show the FlipQueue icon on the minimap border for quick access. Uses LibDBIcon for compatibility with minimap managers.",
        "showMinimap")
    settingsWidgets.showMinimap:SetScript("OnClick", function(self)
        if self:GetChecked() then
            UI:ShowMinimapButton()
        else
            UI:HideMinimapButton()
        end
    end)
    sy = sy - h - ITEM_SPACING

    local bankAnchorOpts = {
        {value = "below", label = "Below mini"},
        {value = "above", label = "Above mini"},
        {value = "left",  label = "Left of mini"},
        {value = "right", label = "Right of mini"},
    }
    settingsWidgets.bankPopupAnchor, h = CreateSettingsDropdown(sc, sy,
        "Bank popup position", "Where the bank operations popup appears relative to the mini view.",
        "bankPopupAnchor", bankAnchorOpts)
    sy = sy - h - ITEM_SPACING

    local detailAnchorOpts = {
        {value = "left",  label = "Left of mini"},
        {value = "right", label = "Right of mini"},
    }
    settingsWidgets.detailPopupAnchor, h = CreateSettingsDropdown(sc, sy,
        "Item detail position", "Where the item detail popup appears when clicking a task.",
        "detailPopupAnchor", detailAnchorOpts)
    sy = sy - h - ITEM_SPACING

    -- Click-to-copy mode: clicking a row in the Next Steps queue
    -- pops up a small copy dialog with either the realm or the
    -- character name. Realm is the default because most users paste
    -- into the realm filter on the character-select screen.
    local copyModeOpts = {
        {value = "realm", label = "Realm"},
        {value = "name",  label = "Character name"},
    }
    settingsWidgets.copyOnClickMode, h = CreateSettingsDropdown(sc, sy,
        "Click-to-copy", "What a click on a Next Steps row copies — realm (to paste into the character-select realm filter) or character name.",
        "copyOnClickMode", copyModeOpts)
    sy = sy - h - ITEM_SPACING

    settingsWidgets.resetMiniPos, h = CreateSettingsButton(sc, sy,
        "Reset Mini Position", "Move the mini overlay back to its default position.", 160, function()
        if ns.db then
            ns.db.settings.miniPos = nil
            if UI.miniFrame and UI.miniFrame:IsShown() then
                UI.miniFrame:ClearAllPoints()
                UI.miniFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -200)
            end
            ns:Print("Mini view position reset.")
        end
    end)
    sy = sy - h - ITEM_SPACING
    secMini.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Tools Drawer
    ------------------------------------------------
    -- Static shell only; the dynamic row list is built by
    -- RefreshToolboxSection (rebuilt whenever tools / macros change).
    local secToolbox = CreateCollapsibleSection(content, y, "toolbox",
        "Tools Drawer",
        "Drawer contents, summon priority, macros")
    sc = secToolbox.content
    sy = 0

    local toolboxDesc = sc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    toolboxDesc:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
    toolboxDesc:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
    toolboxDesc:SetJustifyH("LEFT")
    toolboxDesc:SetWordWrap(true)
    toolboxDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    toolboxDesc:SetText("Choose which tools appear in the drawer beside the mini overlay, "
        .. "their order, the preferred summon for each service, and add your own WoW "
        .. "macros as one-click tools.")
    sy = sy - 38

    local toolboxContainer = CreateFrame("Frame", nil, sc)
    toolboxContainer:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, sy)
    toolboxContainer:SetPoint("RIGHT", sc, "RIGHT", 0, 0)
    toolboxContainer:SetHeight(10)
    settingsWidgets.toolboxContainer = toolboxContainer
    settingsWidgets._toolboxSection = secToolbox
    settingsWidgets._toolboxHeaderAbove = math.abs(sy)

    secToolbox.contentHeight = math.abs(sy) + 10

    ------------------------------------------------
    -- Section: Data Management
    ------------------------------------------------
    ------------------------------------------------
    -- Section: Sales Log (FQ-214)
    ------------------------------------------------
    local secSalesLog = CreateCollapsibleSection(content, y, "saleslog",
        "Sales Log",
        "Record sales, history retention")
    sc = secSalesLog.content
    sy = 0

    settingsWidgets.salesLoggingEnabled, h = CreateSettingsCheckbox(sc, sy,
        "Record sales to the log",
        "When on, every post, sale, expire, and cancel is recorded in the activity log and reconciled for profit accounting. Turn off to stop new entries — existing history is kept.",
        "salesLoggingEnabled")
    sy = sy - h - ITEM_SPACING

    local retentionDayOpts = {
        {value = 7,   label = "7 days"},
        {value = 14,  label = "14 days"},
        {value = 30,  label = "30 days"},
        {value = 60,  label = "60 days"},
        {value = 90,  label = "90 days"},
        {value = 365, label = "1 year"},
        {value = 0,   label = "Never (keep all)"},
    }
    settingsWidgets.salesRetentionDays, h = CreateSettingsDropdown(sc, sy,
        "Keep history for",
        "Collected sales older than this are pruned automatically. 'Never' disables age-based pruning.",
        "salesRetentionDays", retentionDayOpts)
    sy = sy - h - ITEM_SPACING

    -- nil value = unlimited (matches the DB default; no count cap applied).
    local retentionCountOpts = {
        {value = nil,   label = "Unlimited"},
        {value = 500,   label = "500 entries"},
        {value = 1000,  label = "1,000 entries"},
        {value = 2500,  label = "2,500 entries"},
        {value = 5000,  label = "5,000 entries"},
        {value = 10000, label = "10,000 entries"},
    }
    settingsWidgets.salesRetentionCount, h = CreateSettingsDropdown(sc, sy,
        "Max entries kept",
        "Hard cap on total log size — when exceeded, the oldest entries are removed. 'Unlimited' keeps everything within the time window above.",
        "salesRetentionCount", retentionCountOpts)
    sy = sy - h - ITEM_SPACING

    secSalesLog.contentHeight = math.abs(sy)

    local secData = CreateCollapsibleSection(content, y, "data",
        "Data Management",
        "Clear inventory, imports, logs, do-not-track")
    sc = secData.content
    sy = 0

    settingsWidgets.clearInv, h = CreateSettingsButton(sc, sy,
        "Clear Inventory Data", "Wipe all saved bag/bank/warbank data. You'll need to rescan each character.", 180, function()
        StaticPopupDialogs["FLIPQUEUE_CLEAR_INVENTORY"] = {
            text = "Clear all saved inventory data? You will need to rescan on each character.",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                if ns.db then
                    for ck, charData in pairs(ns.db.characters) do
                        charData.inventory = nil
                    end
                    wipe(ns.db.warbank)
                    ns:Print("All inventory data cleared.")
                    UI:Refresh()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("FLIPQUEUE_CLEAR_INVENTORY")
    end)
    sy = sy - h - ITEM_SPACING

    settingsWidgets.clearQueue, h = CreateSettingsButton(sc, sy,
        "Clear All Imports", "Remove all imported deals.", 180, function()
        StaticPopupDialogs["FLIPQUEUE_CLEAR_ALL_SETTINGS"] = {
            text = "Clear ALL imported deals?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                ns:ImportClear("fpScanner")
                ns:Print("Imports cleared.")
                UI:Refresh()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("FLIPQUEUE_CLEAR_ALL_SETTINGS")
    end)
    sy = sy - h - ITEM_SPACING

    settingsWidgets.clearLog, h = CreateSettingsButton(sc, sy,
        "Clear Posted Log", "Remove all entries from the posted items log.", 180, function()
        StaticPopupDialogs["FLIPQUEUE_CLEAR_LOG_SETTINGS"] = {
            text = "Clear ALL items from the posted log?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                ns:ClearLog()
                ns:Print("Log cleared.")
                UI:Refresh()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("FLIPQUEUE_CLEAR_LOG_SETTINGS")
    end)
    sy = sy - h - ITEM_SPACING

    settingsWidgets.clearDNT, h = CreateSettingsButton(sc, sy,
        "Clear Do Not Track", "Remove all items from the Do Not Track list.", 180, function()
        if ns.db then
            wipe(ns.db.doNotTrack)
            ns:Print("Do Not Track list cleared.")
            UI:Refresh()
        end
    end)
    sy = sy - h - ITEM_SPACING
    secData.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Deleted Characters (tombstones)
    ------------------------------------------------
    -- Shows characters that were explicitly deleted from the Characters
    -- page. Their tombstones prevent TSM/Syndicator/sync from re-adding
    -- them. Restore lifts the tombstone; the character reappears on the
    -- next scan (or immediate reload if the user is logged in on that
    -- character).
    local secDeleted = CreateCollapsibleSection(content, y, "deletedchars",
        "Deleted Characters",
        "Restore characters you've previously deleted")
    sc = secDeleted.content
    sy = 0

    -- Header description
    local delDesc = sc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    delDesc:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
    delDesc:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
    delDesc:SetJustifyH("LEFT")
    delDesc:SetWordWrap(true)
    delDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    delDesc:SetText("Deleted characters are kept out of FlipQueue even if " ..
        "TSM or Syndicator still knows about them. Restore reverses the " ..
        "deletion; the character reappears on the next scan.")
    sy = sy - 34

    -- Manual orphan-cleanup button: for characters that were deleted
    -- and then restored (or deleted before cascade cleanup existed),
    -- this scans log + to-do lists for entries referencing charKeys that
    -- no longer exist in db.characters and removes them.
    local cleanBtn, cleanH = CreateSettingsButton(sc, sy,
        "Clean Orphaned Data",
        "Remove tasks and log entries referencing characters that no longer exist.",
        170, function()
            StaticPopupDialogs["FLIPQUEUE_CLEAN_ORPHANED"] = {
                text = "Scan for tasks and log entries referencing characters " ..
                    "that are no longer tracked and remove them?\n\n" ..
                    "Use this if you deleted a character and still see " ..
                    "references to it in the to-do list or log.",
                button1 = "Clean",
                button2 = "Cancel",
                OnAccept = function()
                    local counts = ns:PurgeOrphanedCharData()
                    local total = counts.logs + counts.tasks
                    if total == 0 then
                        ns:Print(ns.COLORS.GRAY .. "No orphaned data found.|r")
                    else
                        ns:Print(ns.COLORS.GREEN .. "Removed " .. counts.tasks ..
                            " orphaned task(s) and " .. counts.logs ..
                            " orphaned log entr" ..
                            (counts.logs == 1 and "y" or "ies") .. ".|r")
                    end
                    UI:Refresh()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("FLIPQUEUE_CLEAN_ORPHANED")
        end)
    settingsWidgets.cleanOrphansBtn = cleanBtn
    sy = sy - cleanH - ITEM_SPACING

    -- Container for the dynamic row list. Rows are pooled in
    -- settingsWidgets.deletedRows and rebuilt by RebuildDeletedList() on
    -- each refresh.
    local delContainer = CreateFrame("Frame", nil, sc)
    delContainer:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT_MARGIN, sy)
    delContainer:SetPoint("RIGHT", sc, "RIGHT", RIGHT_MARGIN, 0)
    delContainer:SetHeight(1)
    settingsWidgets.deletedContainer = delContainer
    settingsWidgets.deletedRows = {}
    settingsWidgets._deletedSection = secDeleted
    sy = sy - 6

    -- Space reserved for the row list. The actual height is set by
    -- RebuildDeletedList, which also updates secDeleted.contentHeight.
    local RESERVED = 60  -- empty-state height; overridden on refresh
    sy = sy - RESERVED
    secDeleted.contentHeight = math.abs(sy)

    ------------------------------------------------
    -- Section: Multi-Account
    ------------------------------------------------
    local secMulti = CreateCollapsibleSection(content, y, "multiaccount",
        "Multi-Account",
        "Sync inventory and to-dos across your accounts via BattleNet")
    sc = secMulti.content
    sy = 0

    -- Everything in this section uses a lower container
    local lower = CreateFrame("Frame", nil, sc)
    lower:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, sy)
    lower:SetPoint("RIGHT", sc, "RIGHT", 0, 0)
    settingsWidgets.lowerSection = lower

    local ly = 0

    -- Linked Accounts section header
    local syncLabel = lower:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncLabel:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    syncLabel:SetTextColor(0.4, 0.95, 0.4)
    syncLabel:SetText("Linked Accounts")
    ly = ly - 18

    -- Brief description
    local syncDesc = lower:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    syncDesc:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    syncDesc:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    syncDesc:SetJustifyH("LEFT")
    syncDesc:SetWordWrap(true)
    syncDesc:SetTextColor(DESC_COLOR[1], DESC_COLOR[2], DESC_COLOR[3])
    syncDesc:SetText("Link other WoW accounts to keep their characters, bags, bank, and to-dos in sync with this one. " ..
        "Click |cffffd100Add Linked Account|r to start the guided setup.")
    ly = ly - 32

    -- Add Linked Account button (opens wizard)
    do
        local btn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        btn:SetSize(170, 26)
        btn:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        btn:SetBackdropColor(0.10, 0.22, 0.10, 1)
        btn:SetBackdropBorderColor(0.3, 0.5, 0.3, 0.9)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.text:SetPoint("CENTER")
        btn.text:SetText("+ Add Linked Account")
        btn.text:SetTextColor(0.3, 1, 0.3)
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.14, 0.28, 0.14, 1) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.10, 0.22, 0.10, 1) end)
        btn:SetScript("OnClick", function()
            if UI.ShowLinkWizard then UI:ShowLinkWizard() end
        end)
        settingsWidgets.addLinkedAccountBtn = btn
    end
    ly = ly - 34

    -- Partner rows container — fixed height, supports up to MAX_PARTNER_ROWS visible.
    -- Rows are pooled and assigned in RefreshSettings as partners change.
    local MAX_PARTNER_ROWS = 5
    local PARTNER_ROW_HEIGHT = 32

    local partnerListFrame = CreateFrame("Frame", nil, lower)
    partnerListFrame:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    partnerListFrame:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    partnerListFrame:SetHeight(MAX_PARTNER_ROWS * PARTNER_ROW_HEIGHT + 20)
    settingsWidgets.partnerListFrame = partnerListFrame

    -- Empty state text (shown when no partners)
    settingsWidgets.partnerListEmpty = partnerListFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    settingsWidgets.partnerListEmpty:SetPoint("TOPLEFT", partnerListFrame, "TOPLEFT", 4, -4)
    settingsWidgets.partnerListEmpty:SetTextColor(0.5, 0.5, 0.5)
    settingsWidgets.partnerListEmpty:SetText("No accounts linked yet.")

    -- Build the row widget pool
    local function BuildPartnerRow(parent, rowIdx)
        local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetSize(10, PARTNER_ROW_HEIGHT - 4)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(rowIdx - 1) * PARTNER_ROW_HEIGHT)
        row:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
        row:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        row:SetBackdropColor(0.10, 0.10, 0.13, 0.6)
        row:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.6)

        -- Status dot (left)
        row.dot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.dot:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.dot:SetText("\226\151\143")  -- ●

        -- Label (name + transport tag)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.label:SetPoint("LEFT", row.dot, "RIGHT", 6, 0)
        row.label:SetJustifyH("LEFT")

        -- Status / last sync text
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.status:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
        row.status:SetJustifyH("LEFT")
        row.status:SetTextColor(0.7, 0.7, 0.7)

        -- Remove button (right)
        row.removeBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.removeBtn:SetSize(70, 20)
        row.removeBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.removeBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        row.removeBtn:SetBackdropColor(0.25, 0.1, 0.1, 1)
        row.removeBtn:SetBackdropBorderColor(0.5, 0.2, 0.2, 0.8)
        row.removeBtn.text = row.removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.removeBtn.text:SetPoint("CENTER")
        row.removeBtn.text:SetText("Remove")
        row.removeBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.35, 0.15, 0.15, 1) end)
        row.removeBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.25, 0.1, 0.1, 1) end)

        -- Force Sync button (right of Remove)
        row.syncBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.syncBtn:SetSize(80, 20)
        row.syncBtn:SetPoint("RIGHT", row.removeBtn, "LEFT", -4, 0)
        row.syncBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        row.syncBtn:SetBackdropColor(0.12, 0.18, 0.28, 1)
        row.syncBtn:SetBackdropBorderColor(0.3, 0.4, 0.6, 0.8)
        row.syncBtn.text = row.syncBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.syncBtn.text:SetPoint("CENTER")
        row.syncBtn.text:SetText("Force Sync")
        row.syncBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.18, 0.24, 0.36, 1) end)
        row.syncBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.12, 0.18, 0.28, 1) end)

        return row
    end

    settingsWidgets.partnerRows = {}
    for i = 1, MAX_PARTNER_ROWS do
        local row = BuildPartnerRow(partnerListFrame, i)
        row:Hide()
        settingsWidgets.partnerRows[i] = row
    end

    ly = ly - (MAX_PARTNER_ROWS * PARTNER_ROW_HEIGHT + 28)

    -- Incoming pair request display
    settingsWidgets.pairRequestText = lower:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    settingsWidgets.pairRequestText:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
    settingsWidgets.pairRequestText:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
    settingsWidgets.pairRequestText:SetJustifyH("LEFT")
    ly = ly - 16

    -- Accept / Deny buttons (shown when there's a pending request)
    do
        local acceptBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        acceptBtn:SetSize(80, 22)
        acceptBtn:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        acceptBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        acceptBtn:SetBackdropColor(0.1, 0.3, 0.1, 1)
        acceptBtn:SetBackdropBorderColor(0.2, 0.5, 0.2, 0.8)
        acceptBtn.text = acceptBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        acceptBtn.text:SetPoint("CENTER")
        acceptBtn.text:SetText("Accept")
        acceptBtn:SetScript("OnClick", function()
            if ns.Sync then
                local _, senderGAID = ns.Sync:GetPendingPairFrom()
                if senderGAID then ns.Sync:AcceptPair(senderGAID) end
            end
            UI:RefreshSettings()
        end)
        settingsWidgets.pairAcceptBtn = acceptBtn

        local denyBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        denyBtn:SetSize(80, 22)
        denyBtn:SetPoint("LEFT", acceptBtn, "RIGHT", 6, 0)
        denyBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        denyBtn:SetBackdropColor(0.3, 0.1, 0.1, 1)
        denyBtn:SetBackdropBorderColor(0.5, 0.2, 0.2, 0.8)
        denyBtn.text = denyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        denyBtn.text:SetPoint("CENTER")
        denyBtn.text:SetText("Deny")
        denyBtn:SetScript("OnClick", function()
            if ns.Sync then
                local _, senderGAID = ns.Sync:GetPendingPairFrom()
                ns.Sync:DenyPair(senderGAID)
            end
            UI:RefreshSettings()
        end)
        settingsWidgets.pairDenyBtn = denyBtn
    end
    ly = ly - 26 - ITEM_SPACING

    -- Sync Debug Log (collapsible)
    do
        local toggleBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        toggleBtn:SetSize(130, 20)
        toggleBtn:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        toggleBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        toggleBtn:SetBackdropColor(0.1, 0.1, 0.15, 1)
        toggleBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        toggleBtn.text = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        toggleBtn.text:SetPoint("CENTER")
        toggleBtn.text:SetText("Show Sync Log")
        toggleBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.25, 1) end)
        toggleBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.1, 0.1, 0.15, 1) end)

        -- Copy button: opens the existing Export popup preloaded with the
        -- sync log in plain text so the user can Ctrl+A / Ctrl+C it. The
        -- inline EditBox in this panel can't reliably hold focus for copy,
        -- so we piggyback on the export popup infrastructure that already
        -- handles selection, focus, and pipe-escaping correctly.
        local copyBtn = CreateFrame("Button", nil, lower, "BackdropTemplate")
        copyBtn:SetSize(80, 20)
        copyBtn:SetPoint("LEFT", toggleBtn, "RIGHT", 6, 0)
        copyBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        copyBtn:SetBackdropColor(0.1, 0.1, 0.15, 1)
        copyBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        copyBtn.text = copyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        copyBtn.text:SetPoint("CENTER")
        copyBtn.text:SetText("Copy Log")
        copyBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.2, 0.25, 1) end)
        copyBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.1, 0.1, 0.15, 1) end)
        copyBtn:SetScript("OnClick", function()
            if not (ns.Sync and ns.Sync.GetSyncLog) then return end
            local log = ns.Sync:GetSyncLog()
            if #log == 0 then
                if UI.ShowExportPopup then
                    UI:ShowExportPopup("(no sync events yet)", "Sync log")
                end
                return
            end
            local lines = {}
            for i = 1, #log do
                local entry = log[i]
                if entry and entry.t then
                    local ts = date("%Y-%m-%d %H:%M:%S", entry.t)
                    local ev = entry.event
                    if type(ev) ~= "string" or ev == "" then ev = "?" end
                    local detail = entry.detail
                    if type(detail) ~= "string" then detail = "" end
                    lines[#lines + 1] = ts .. "  " .. ev .. "  " .. detail
                end
            end
            if UI.ShowExportPopup then
                UI:ShowExportPopup(table.concat(lines, "\n"),
                    "Sync log (" .. #log .. " entries)")
            end
        end)
        settingsWidgets.syncLogCopyBtn = copyBtn

        ly = ly - 24

        local logFrame = CreateFrame("Frame", nil, lower, "BackdropTemplate")
        logFrame:SetPoint("TOPLEFT", lower, "TOPLEFT", LEFT_MARGIN, ly)
        logFrame:SetPoint("RIGHT", lower, "RIGHT", RIGHT_MARGIN, 0)
        logFrame:SetHeight(180)
        logFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        logFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
        logFrame:SetBackdropBorderColor(0.25, 0.25, 0.35, 0.8)
        logFrame:Hide()

        -- Scrollable text inside
        local scroll = CreateFrame("ScrollFrame", nil, logFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", -28, 6)

        local logText = CreateFrame("EditBox", nil, scroll)
        logText:SetMultiLine(true)
        logText:SetAutoFocus(false)
        logText:SetFontObject(GameFontHighlightSmall)
        logText:SetWidth(scroll:GetWidth() or 350)
        logText:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        logText:EnableMouse(true)
        logText:SetScript("OnMouseUp", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(logText)

        settingsWidgets.syncLogFrame = logFrame
        settingsWidgets.syncLogText = logText
        settingsWidgets.syncLogScroll = scroll

        local logVisible = false
        toggleBtn:SetScript("OnClick", function()
            logVisible = not logVisible
            if logVisible then
                logFrame:Show()
                toggleBtn.text:SetText("Hide Sync Log")
                UI:RefreshSyncLog()
            else
                logFrame:Hide()
                toggleBtn.text:SetText("Show Sync Log")
            end
        end)
        settingsWidgets.syncLogToggle = toggleBtn

        -- Auto-refresh timer when log is visible
        local logRefreshTicker = nil
        logFrame:SetScript("OnShow", function()
            logRefreshTicker = C_Timer.NewTicker(2, function()
                if logFrame:IsShown() then
                    UI:RefreshSyncLog()
                end
            end)
        end)
        logFrame:SetScript("OnHide", function()
            if logRefreshTicker then logRefreshTicker:Cancel(); logRefreshTicker = nil end
        end)

        ly = ly - 4 -- collapsed height

        -- When sync log toggles, shift everything below it
        local SYNC_LOG_HEIGHT = 180
        local belowSyncBaseY = ly - SECTION_SPACING
        local belowSync = CreateFrame("Frame", nil, lower)
        belowSync:SetPoint("TOPLEFT", lower, "TOPLEFT", 0, belowSyncBaseY)
        belowSync:SetPoint("RIGHT", lower, "RIGHT", 0, 0)
        belowSync:SetHeight(600)
        settingsWidgets.belowSyncFrame = belowSync
        settingsWidgets.belowSyncBaseY = belowSyncBaseY

        local origToggleOnClick = toggleBtn:GetScript("OnClick")
        toggleBtn:SetScript("OnClick", function(self)
            origToggleOnClick(self)
            -- Reposition the content below the sync log
            belowSync:ClearAllPoints()
            if logFrame:IsShown() then
                belowSync:SetPoint("TOPLEFT", lower, "TOPLEFT", 0, belowSyncBaseY - SYNC_LOG_HEIGHT)
            else
                belowSync:SetPoint("TOPLEFT", lower, "TOPLEFT", 0, belowSyncBaseY)
            end
            -- Update total content height
            local extraH = logFrame:IsShown() and SYNC_LOG_HEIGHT or 0
            local bsH = settingsWidgets.belowSyncContentHeight or 300
            lower:SetHeight(math.abs(belowSyncBaseY) + bsH + extraH + 10)
            if sectionContainers.multiaccount then
                sectionContainers.multiaccount.contentHeight = math.abs(belowSyncBaseY) + bsH + extraH + 10
            end
            if UI.ReflowSettings then UI:ReflowSettings() end
        end)
    end

    -- Everything below the sync log goes into belowSync container.
    -- Tutorial + Setup Wizard moved to the General section above.
    -- About link removed entirely — the About page lives in the sidebar nav.
    local belowSync = settingsWidgets.belowSyncFrame
    local bsy = -10  -- small buffer so the multi-account section doesn't end flush

    settingsWidgets.belowSyncContentHeight = math.abs(bsy)
    belowSync:SetHeight(math.abs(bsy) + 10)

    local belowSyncBaseY = settingsWidgets.belowSyncBaseY or 0
    lower:SetHeight(math.abs(belowSyncBaseY) + math.abs(bsy) + 10)
    settingsWidgets.lowerSectionHeight = math.abs(belowSyncBaseY) + math.abs(bsy) + 10

    -- Set multi-account section height from the lower container
    secMulti.contentHeight = math.abs(belowSyncBaseY) + math.abs(bsy) + 10

    -- Initial reflow positions all collapsible sections
    UI:ReflowSettings()

    settingsPanel = scroll
    return settingsPanel
end

function UI:ShowSettingsPage()
    if not settingsPanel then
        self:CreateSettingsPanel(self.tableContainer)
    end
    settingsPanel:Show()
    self:RefreshSettings()
end

function UI:HideSettingsPage()
    if settingsPanel then
        settingsPanel:Hide()
    end
end

function UI:RefreshSettings()
    if not ns.db then return end
    if UI._RefreshDeletedCharactersSection then
        UI._RefreshDeletedCharactersSection()
    end
    if UI._RefreshToolboxSection then
        UI._RefreshToolboxSection()
    end
    local manageItemsOn = ns.db.settings.manageItems ~= false
    local manageGoldOn  = ns.db.settings.manageGold  ~= false

    if settingsWidgets.manageItems then
        settingsWidgets.manageItems:SetChecked(manageItemsOn)
    end
    if settingsWidgets.manageGold then
        settingsWidgets.manageGold:SetChecked(manageGoldOn)
    end
    if settingsWidgets.autoScan then
        settingsWidgets.autoScan:SetChecked(ns.db.settings.autoScan)
    end
    -- autoPull, autoDeposit, autoDepositAll moved to Characters page
    if settingsWidgets.autoGold then
        settingsWidgets.autoGold:SetChecked(ns.db.settings.autoWithdrawGold)
    end

    -- #148: dim + disable rows in Bank & Warbank whose master is off.
    -- Setting the row's alpha cascades to its children (title, description,
    -- input border) for a uniform "this section is inactive" appearance.
    -- Disabling the interactive widget keeps the row from accepting clicks
    -- while the master is off.
    local function ApplyRowState(rowFrame, widget, enabled)
        local alpha = enabled and 1.0 or 0.4
        if rowFrame and rowFrame.SetAlpha then rowFrame:SetAlpha(alpha) end
        if widget and widget.SetEnabled then widget:SetEnabled(enabled) end
    end

    -- Gold-related rows (Withdraw / Max withdraw / Deposit excess / Buffer).
    -- (#155) Tri-mode rows are themselves the row frame, not a child widget.
    if settingsWidgets.goldWithdrawModeRow then
        settingsWidgets.goldWithdrawModeRow:SetAlpha(manageGoldOn and 1.0 or 0.4)
    end
    ApplyRowState(settingsWidgets.maxWithdrawRow, settingsWidgets.maxWithdrawBox, manageGoldOn)
    if settingsWidgets.goldDepositModeRow then
        settingsWidgets.goldDepositModeRow:SetAlpha(manageGoldOn and 1.0 or 0.4)
    end
    ApplyRowState(settingsWidgets.goldBufferRow, settingsWidgets.goldBufferBox, manageGoldOn)

    -- Items-related rows
    if settingsWidgets.reagentsModeRow then
        settingsWidgets.reagentsModeRow:SetAlpha(manageItemsOn and 1.0 or 0.4)
    end
    ApplyRowState(settingsWidgets.depositOverflowRow, settingsWidgets.depositOverflow, manageItemsOn)
    ApplyRowState(settingsWidgets.depositOverflowCrossStackRow, settingsWidgets.depositOverflowCrossStack, manageItemsOn)
    ApplyRowState(settingsWidgets.batchSizeRow, settingsWidgets.batchSizeSlider, manageItemsOn)
    if settingsWidgets.maxWithdrawBox then
        local val = ns.db.settings.maxWithdrawGold or 0
        settingsWidgets.maxWithdrawBox:SetText(tostring(val))
    end
    if settingsWidgets.ahAutoScan then
        settingsWidgets.ahAutoScan:SetChecked(ns.db.settings.ahAutoScanOnOpen)
    end
    if settingsWidgets.ahPostingEnabled then
        settingsWidgets.ahPostingEnabled:SetChecked(ns.db.settings.ahPostingEnabled ~= false)
    end
    if settingsWidgets.goldBufferBox then
        local val = ns.db.settings.goldBuffer or 0
        settingsWidgets.goldBufferBox:SetText(tostring(val))
    end
    -- (#155) Tri-mode widgets self-refresh via their internal `refresh`
    -- closure when the player clicks. Re-apply on settings refresh too
    -- so external changes (slash command toggle, migration) propagate.
    if settingsWidgets.goldWithdrawModeRow and settingsWidgets.goldWithdrawModeRow.refresh then
        settingsWidgets.goldWithdrawModeRow.refresh()
    end
    if settingsWidgets.goldDepositModeRow and settingsWidgets.goldDepositModeRow.refresh then
        settingsWidgets.goldDepositModeRow.refresh()
    end
    if settingsWidgets.reagentsModeRow and settingsWidgets.reagentsModeRow.refresh then
        settingsWidgets.reagentsModeRow.refresh()
    end
    if settingsWidgets.depositOverflow then
        local ov = ns.db.settings.depositOverflow or {}
        settingsWidgets.depositOverflow:SetChecked(ov.enabled and true or false)
    end
    if settingsWidgets.depositOverflowCrossStack then
        local ov = ns.db.settings.depositOverflow or {}
        local sub = settingsWidgets.depositOverflowCrossStack
        sub:SetChecked(ov.crossStack and true or false)
        if ov.enabled then
            sub:Enable()
            sub.text:SetTextColor(1, 1, 1)
        else
            sub:Disable()
            sub.text:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    -- TSM behavior toggles moved to the TSM Integration page; their populate
    -- logic now lives in UI/TSMFrame.lua RefreshTSMPage().
    if settingsWidgets.loginMsg then
        settingsWidgets.loginMsg:SetChecked(ns.db.settings.showLoginMessage)
    end
    if settingsWidgets.showMini then
        settingsWidgets.showMini:SetChecked(ns.db.settings.showMini)
    end
    if settingsWidgets.hideMiniCombat then
        settingsWidgets.hideMiniCombat:SetChecked(ns.db.settings.hideMiniInCombat)
    end
    if settingsWidgets.hideMiniInstance then
        settingsWidgets.hideMiniInstance:SetChecked(ns.db.settings.hideMiniInInstance)
    end
    if settingsWidgets.pauseAutoOpsInInstance then
        settingsWidgets.pauseAutoOpsInInstance:SetChecked(ns.db.settings.pauseAutoOpsInInstance)
    end
    if settingsWidgets.showMinimap then
        settingsWidgets.showMinimap:SetChecked(UI:IsMinimapButtonShown())
    end
    if settingsWidgets.bankPopupAnchor then
        settingsWidgets.bankPopupAnchor:SetValue(ns.db.settings.bankPopupAnchor)
    end
    if settingsWidgets.detailPopupAnchor then
        settingsWidgets.detailPopupAnchor:SetValue(ns.db.settings.detailPopupAnchor)
    end
    if settingsWidgets.copyOnClickMode then
        settingsWidgets.copyOnClickMode:SetValue(ns.db.settings.copyOnClickMode or "realm")
    end
    if settingsWidgets.fpPriceSource then
        settingsWidgets.fpPriceSource:SetValue(ns.db.settings.fpPriceSource or "listing")
    end
    -- Sales Log (FQ-214)
    if settingsWidgets.salesLoggingEnabled then
        settingsWidgets.salesLoggingEnabled:SetChecked(ns.db.settings.salesLoggingEnabled ~= false)
    end
    if settingsWidgets.salesRetentionDays then
        local d = ns.db.settings.salesRetentionDays
        if d == nil then d = 30 end
        settingsWidgets.salesRetentionDays:SetValue(d)
    end
    if settingsWidgets.salesRetentionCount then
        settingsWidgets.salesRetentionCount:SetValue(ns.db.settings.salesRetentionCount)
    end
    -- Batch size slider
    if settingsWidgets.batchSizeSlider then
        local batchSize = ns.db.settings.pullBatchSize or 5
        settingsWidgets.batchSizeSlider:SetValue(batchSize)
        if settingsWidgets.batchSizeLabel then
            settingsWidgets.batchSizeLabel:SetText(tostring(batchSize))
        end
    end
    -- Default sell quantity slider
    if settingsWidgets.sellQtySlider then
        local sellQty = ns.db.settings.defaultSellQty or 1
        settingsWidgets.sellQtySlider:SetValue(sellQty)
        if settingsWidgets.sellQtyLabel then
            settingsWidgets.sellQtyLabel:SetText(tostring(sellQty))
        end
    end
    -- Sell quantity mode toggle
    if settingsWidgets.updateSellQtyMode then
        settingsWidgets.updateSellQtyMode()
    end
    -- Expiry alert slider
    if settingsWidgets.expiryAlertSlider then
        local mins = ns.db.settings.expiryAlertMinutes or 15
        settingsWidgets.expiryAlertSlider:SetValue(mins)
        if settingsWidgets.expiryAlertLabel then
            local displayStr = mins >= 60 and string.format("%.1fh", mins / 60) or (mins .. "m")
            settingsWidgets.expiryAlertLabel:SetText(displayStr)
        end
    end
    -- Bank tab selection moved to Characters page config panel

    -- Partner list rows (per-partner management)
    if settingsWidgets.partnerRows then
        -- Collect partners into an ordered list so row assignment is stable
        local partnersList = {}
        if ns.Sync and ns.Sync.GetPartners then
            for uuid, partner in pairs(ns.Sync:GetPartners()) do
                partnersList[#partnersList + 1] = { uuid = uuid, partner = partner }
            end
            table.sort(partnersList, function(a, b)
                return (a.partner.label or a.uuid) < (b.partner.label or b.uuid)
            end)
        end

        if settingsWidgets.partnerListEmpty then
            settingsWidgets.partnerListEmpty:SetShown(#partnersList == 0)
        end

        for i, row in ipairs(settingsWidgets.partnerRows) do
            local entry = partnersList[i]
            if entry then
                local uuid = entry.uuid
                local partner = entry.partner
                local pState = ns.Sync:GetPartnerState(uuid)
                local isConnected = (pState == "connected" or pState == "syncing")

                if isConnected then
                    row.dot:SetTextColor(0.3, 1, 0.3)
                else
                    row.dot:SetTextColor(1, 0.3, 0.3)
                end

                local transportTag = ""
                if partner.transport == "whisper" then
                    transportTag = " |cff888888[local]|r"
                else
                    transportTag = " |cff888888[bnet]|r"
                end
                row.label:SetText((partner.label or "Account") .. transportTag)

                local statusBits = {}
                statusBits[#statusBits + 1] = isConnected and "|cff66cc66Online|r" or "|cffcc6666Offline|r"
                local lastSync = partner.lastFullSync or 0
                if lastSync > 0 then
                    statusBits[#statusBits + 1] = "last sync " .. ns:FormatRelativeTime(lastSync)
                else
                    statusBits[#statusBits + 1] = "not yet synced"
                end
                local pending = ns.Sync:GetPendingCount(uuid)
                if pending > 0 then
                    statusBits[#statusBits + 1] = "|cffffcc66" .. pending .. " queued|r"
                end
                row.status:SetText(table.concat(statusBits, "  •  "))

                -- Wire up per-partner button handlers (re-wire each refresh since uuid may change position)
                row.removeBtn:SetScript("OnClick", function()
                    if ns.Sync and ns.Sync.UnlinkByUUID then
                        ns.Sync:UnlinkByUUID(uuid)
                        UI:RefreshSettings()
                    end
                end)
                row.syncBtn:SetScript("OnClick", function()
                    if ns.Sync and ns.Sync.ForceSyncByUUID then
                        ns.Sync:ForceSyncByUUID(uuid)
                    end
                end)
                row.syncBtn:SetEnabled(isConnected)
                if isConnected then
                    row.syncBtn.text:SetTextColor(1, 1, 1)
                else
                    row.syncBtn.text:SetTextColor(0.5, 0.5, 0.5)
                end

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Pair request display
    if settingsWidgets.pairRequestText then
        if ns.Sync and ns.Sync:HasPendingPairRequest() then
            local from = ns.Sync:GetPendingPairFrom()
            settingsWidgets.pairRequestText:SetText(ns.COLORS.CYAN .. (from or "?") .. "|r wants to link.")
            if settingsWidgets.pairAcceptBtn then settingsWidgets.pairAcceptBtn:Show() end
            if settingsWidgets.pairDenyBtn then settingsWidgets.pairDenyBtn:Show() end
        else
            settingsWidgets.pairRequestText:SetText("")
            if settingsWidgets.pairAcceptBtn then settingsWidgets.pairAcceptBtn:Hide() end
            if settingsWidgets.pairDenyBtn then settingsWidgets.pairDenyBtn:Hide() end
        end
    end

end

function UI:RefreshSyncLog()
    if not settingsWidgets.syncLogText then return end
    if not ns.Sync or not ns.Sync.GetSyncLog then return end

    local log = ns.Sync:GetSyncLog()
    if #log == 0 then
        settingsWidgets.syncLogText:SetText("|cff888888No sync events yet.|r")
        return
    end

    local lines = {}
    -- Show most recent entries at the bottom (natural chat order)
    local start = math.max(1, #log - 99) -- last 100 entries
    for i = start, #log do
        local entry = log[i]
        if entry and entry.t then
            local ts = date("%H:%M:%S", entry.t)
            local ev = entry.event
            if type(ev) ~= "string" or ev == "" then ev = "?" end
            local detail = entry.detail
            if type(detail) ~= "string" then detail = "" end
            lines[#lines + 1] = "|cff888888" .. ts .. "|r |cff66aaff" .. ev .. "|r " .. detail
        end
    end
    settingsWidgets.syncLogText:SetText(table.concat(lines, "\n"))

    -- Auto-scroll to bottom
    C_Timer.After(0, function()
        if settingsWidgets.syncLogScroll then
            local max = settingsWidgets.syncLogScroll:GetVerticalScrollRange()
            settingsWidgets.syncLogScroll:SetVerticalScroll(max)
        end
    end)
end

-- Legacy ShowSettings opens the main window to settings page
function UI:ShowSettings()
    self.currentPage = "settings"
    self.mainFrame:Show()
    self:Refresh()
end
