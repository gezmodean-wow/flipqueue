-- UI/GeneratorRegenerateTrack.lua
-- 4th Generator track: rebuild an existing list from saved data (active,
-- queued, or favorited templates) and re-resolve prices via the user's
-- current FP setting (Settings -> Imports) or against live TSM. State
-- machine and chrome live in GeneratorPage.lua; this module owns the
-- three step containers and the per-step render logic.
local addonName, ns = ...

local RegenerateTrack = {}
ns.RegenerateTrack = RegenerateTrack

local ROW_H        = 22
local SECTION_PAD  = 8

--------------------------
-- Tiny widget helpers
--------------------------

local function CreateLabel(parent, text, color)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetText(text or "")
    if color then f:SetTextColor(color[1], color[2], color[3]) end
    return f
end

local function CreateRowBg(parent, alpha)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(0.10, 0.12, 0.16, alpha or 0.6)
    return t
end

-- Small clickable row (used for source picker + task rows).
local function CreatePickRow(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(ROW_H)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.08, 0.10, 0.13, 0.85)
    btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hl:SetAllPoints()
    btn.hl:SetColorTexture(0.3, 0.4, 0.6, 0.25)
    btn.label = CreateLabel(btn, "")
    btn.label:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.tag = CreateLabel(btn, "")
    btn.tag:SetPoint("LEFT", btn.label, "RIGHT", 8, 0)
    btn.tag:SetTextColor(0.5, 0.8, 1)
    btn.count = CreateLabel(btn, "")
    btn.count:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn.count:SetTextColor(0.7, 0.7, 0.7)
    return btn
end

-- Task row with [X] remove control on the right.
local function CreateTaskRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.06, 0.08, 0.11, 0.7)

    row.name = CreateLabel(row, "")
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)

    row.char = CreateLabel(row, "")
    row.char:SetTextColor(0.7, 0.7, 0.7)
    row.char:SetPoint("LEFT", row, "LEFT", 200, 0)

    row.price = CreateLabel(row, "")
    row.price:SetTextColor(1, 0.85, 0.4)
    row.price:SetPoint("RIGHT", row, "RIGHT", -40, 0)

    row.action = CreateLabel(row, "")
    row.action:SetTextColor(0.5, 0.8, 1)
    row.action:SetPoint("LEFT", row, "LEFT", 380, 0)

    row.xBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.xBtn:SetSize(18, 18)
    row.xBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.xBtn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = {left = 1, right = 1, top = 1, bottom = 1},
    })
    row.xBtn:SetBackdropColor(0.3, 0.1, 0.1, 1)
    row.xBtn:SetBackdropBorderColor(0.7, 0.2, 0.2, 0.8)
    row.xBtn.text = row.xBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.xBtn.text:SetText("x")
    row.xBtn.text:SetPoint("CENTER")

    return row
end

local function MakeScrollList(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetClipsChildren(true)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(sf, w)
        content:SetWidth(w)
    end)
    return scroll, content
end

--------------------------
-- One-time init: build the three step containers
--------------------------

function RegenerateTrack:Init(gf)
    if gf.regenStepContainers then return end
    gf.regenStepContainers = {}
    for i = 1, 3 do
        local sc = CreateFrame("Frame", nil, gf)
        sc:Hide()
        gf.regenStepContainers[i] = sc
    end

    -- ===== STEP 1: SOURCE PICKER =====
    local r1 = gf.regenStepContainers[1]
    r1.title = CreateLabel(r1, "Pick a list to regenerate")
    r1.title:SetTextColor(0.95, 0.85, 0.35)
    r1.title:SetPoint("TOPLEFT", r1, "TOPLEFT", 8, -8)

    r1.subtitle = CreateLabel(r1, "Active list, queued lists, and favorited templates are all options.")
    r1.subtitle:SetTextColor(0.6, 0.6, 0.6)
    r1.subtitle:SetPoint("TOPLEFT", r1.title, "BOTTOMLEFT", 0, -4)

    r1.scroll, r1.scrollContent = MakeScrollList(r1)
    r1.scroll:SetPoint("TOPLEFT", r1, "TOPLEFT", 4, -48)
    r1.scroll:SetPoint("BOTTOMRIGHT", r1, "BOTTOMRIGHT", -24, 4)

    r1.rows = {}
    r1.empty = CreateLabel(r1, "No saved lists found. Generate one first.")
    r1.empty:SetTextColor(0.6, 0.6, 0.6)
    r1.empty:SetPoint("CENTER", r1, "CENTER", 0, 0)
    r1.empty:Hide()

    r1._selectedKey = nil   -- string key of selected source
    r1._sources     = {}    -- last rendered source array

    -- ===== STEP 2: REMOVE-ONLY EDIT GRID =====
    local r2 = gf.regenStepContainers[2]
    r2.title = CreateLabel(r2, "Confirm tasks (remove any you don't want)")
    r2.title:SetTextColor(0.95, 0.85, 0.35)
    r2.title:SetPoint("TOPLEFT", r2, "TOPLEFT", 8, -8)

    r2.summary = CreateLabel(r2, "")
    r2.summary:SetTextColor(0.7, 0.7, 0.7)
    r2.summary:SetPoint("TOPLEFT", r2.title, "BOTTOMLEFT", 0, -4)

    r2.scroll, r2.scrollContent = MakeScrollList(r2)
    r2.scroll:SetPoint("TOPLEFT", r2, "TOPLEFT", 4, -48)
    r2.scroll:SetPoint("BOTTOMRIGHT", r2, "BOTTOMRIGHT", -24, 4)
    r2.rows = {}
    r2._removed = {}  -- removalKey -> true

    -- ===== STEP 3: REFRESH MODE + PREVIEW + SAVE =====
    local r3 = gf.regenStepContainers[3]
    r3.title = CreateLabel(r3, "Configure regeneration")
    r3.title:SetTextColor(0.95, 0.85, 0.35)
    r3.title:SetPoint("TOPLEFT", r3, "TOPLEFT", 8, -8)

    r3.subtitle = CreateLabel(r3, "Choose which price source to apply.")
    r3.subtitle:SetTextColor(0.6, 0.6, 0.6)
    r3.subtitle:SetPoint("TOPLEFT", r3.title, "BOTTOMLEFT", 0, -4)

    -- Refresh-mode radios
    local function CreateRadio(parent, labelText, descText)
        local btn = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
        btn:SetSize(20, 20)
        btn.label = CreateLabel(parent, labelText)
        btn.label:SetTextColor(0.95, 0.95, 0.95)
        btn.desc = CreateLabel(parent, descText)
        btn.desc:SetTextColor(0.55, 0.55, 0.55)
        return btn
    end

    r3.modeFp = CreateRadio(r3,
        "Use FP saved data",
        "Re-resolves expectedPrice from import buckets using your FlippingPal price source setting.")
    r3.modeFp:SetPoint("TOPLEFT", r3.subtitle, "BOTTOMLEFT", 0, -10)
    r3.modeFp.label:SetPoint("LEFT", r3.modeFp, "RIGHT", 4, 0)
    r3.modeFp.desc:SetPoint("TOPLEFT", r3.modeFp.label, "BOTTOMLEFT", 0, -2)

    r3.modeTsm = CreateRadio(r3,
        "Use live TSM prices",
        "Looks up DBRegionMarketAvg per item right now. Requires TSM.")
    r3.modeTsm:SetPoint("TOPLEFT", r3.modeFp.desc, "BOTTOMLEFT", -24, -6)
    r3.modeTsm.label:SetPoint("LEFT", r3.modeTsm, "RIGHT", 4, 0)
    r3.modeTsm.desc:SetPoint("TOPLEFT", r3.modeTsm.label, "BOTTOMLEFT", 0, -2)

    r3._mode = "fpsaved"
    r3.modeFp:SetChecked(true)
    r3.modeFp:SetScript("OnClick", function()
        r3._mode = "fpsaved"
        r3.modeFp:SetChecked(true)
        r3.modeTsm:SetChecked(false)
        if r3._onModeChange then r3._onModeChange() end
    end)
    r3.modeTsm:SetScript("OnClick", function()
        r3._mode = "tsmlive"
        r3.modeFp:SetChecked(false)
        r3.modeTsm:SetChecked(true)
        if r3._onModeChange then r3._onModeChange() end
    end)

    -- Name field
    r3.nameLabel = CreateLabel(r3, "List name:")
    r3.nameLabel:SetTextColor(0.7, 0.7, 0.7)
    r3.nameBox = CreateFrame("EditBox", nil, r3, "InputBoxTemplate")
    r3.nameBox:SetSize(240, 20)
    r3.nameBox:SetAutoFocus(false)
    r3.nameBox:SetFontObject("GameFontHighlightSmall")
    r3.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    r3.nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Preview list
    r3.previewLabel = CreateLabel(r3, "Preview (first 50):")
    r3.previewLabel:SetTextColor(0.7, 0.7, 0.7)
    r3.scroll, r3.scrollContent = MakeScrollList(r3)
    r3.rows = {}

    -- Track-level state holders surfaced to GeneratorPage.lua
    gf.regenState = {
        selectedKey = nil,
        sourceList  = nil,
        removed     = {},
        mode        = "fpsaved",
        preview     = nil,
    }
end

--------------------------
-- Rendering
--------------------------

-- Returns array of source descriptors with a stable key per row.
local function GetSourcesWithKeys()
    if not ns.TodoList or not ns.TodoList.GetRegenSources then return {} end
    local list = ns.TodoList:GetRegenSources()
    for i, src in ipairs(list) do
        src.key = src.kind .. ":" .. (src.queueIdx or src.label or i)
    end
    return list
end

local function RenderStep1(gf, refresh)
    local r1 = gf.regenStepContainers[1]
    local sources = GetSourcesWithKeys()
    r1._sources = sources

    for _, row in ipairs(r1.rows) do row:Hide() end
    if #sources == 0 then
        r1.empty:Show()
        gf.regenState.selectedKey = nil
        gf.regenState.sourceList  = nil
        return
    end
    r1.empty:Hide()

    local y = -4
    for i, src in ipairs(sources) do
        local row = r1.rows[i]
        if not row then
            row = CreatePickRow(r1.scrollContent)
            r1.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", r1.scrollContent, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT",   r1.scrollContent, "RIGHT", -4, 0)
        local count = src.list and src.list.tasks and #src.list.tasks or 0
        row.label:SetText(src.label or "?")
        row.tag:SetText("[" .. src.kind .. "]")
        row.count:SetText(count .. " tasks")
        if gf.regenState.selectedKey == src.key then
            row.bg:SetColorTexture(0.2, 0.35, 0.5, 0.9)
        else
            row.bg:SetColorTexture(0.08, 0.10, 0.13, 0.85)
        end
        row:SetScript("OnClick", function()
            gf.regenState.selectedKey = src.key
            gf.regenState.sourceList  = src.list
            -- Reset downstream state when source changes
            gf.regenState.removed = {}
            gf.regenState.preview = nil
            for _, rr in ipairs(gf.regenStepContainers[2].rows) do rr:Hide() end
            for _, rr in ipairs(gf.regenStepContainers[3].rows) do rr:Hide() end
            if refresh then refresh() end
        end)
        row:Show()
        y = y - ROW_H - 2
    end
    r1.scrollContent:SetHeight(math.max(1, math.abs(y)))
end

local function RemovalKey(task)
    return (task.itemKey or "") .. "|" .. (task.assignedChar or "")
end

local function RenderStep2(gf, refresh)
    local r2 = gf.regenStepContainers[2]
    local src = gf.regenState.sourceList
    for _, row in ipairs(r2.rows) do row:Hide() end
    if not src or not src.tasks then
        r2.summary:SetText("No source selected.")
        return
    end

    local removedN = 0
    for _ in pairs(gf.regenState.removed) do removedN = removedN + 1 end
    r2.summary:SetText(string.format(
        "%d tasks in '%s'  —  %d marked for removal",
        #src.tasks, src.name or "Unnamed", removedN))

    local y = -4
    for i, task in ipairs(src.tasks) do
        local row = r2.rows[i]
        if not row then
            row = CreateTaskRow(r2.scrollContent)
            r2.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", r2.scrollContent, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT",   r2.scrollContent, "RIGHT", -4, 0)
        row.name:SetText(task.name or "?")
        row.char:SetText(task.assignedChar or "(no char)")
        row.action:SetText(task.action == "buy" and "BUY" or "POST")
        row.price:SetText(task.expectedPrice or "")
        local rkey = RemovalKey(task)
        if gf.regenState.removed[rkey] then
            row.bg:SetColorTexture(0.30, 0.10, 0.10, 0.6)
            row.name:SetTextColor(0.6, 0.5, 0.5)
            row.xBtn.text:SetText("+")
        else
            row.bg:SetColorTexture(0.06, 0.08, 0.11, 0.7)
            row.name:SetTextColor(1, 1, 1)
            row.xBtn.text:SetText("x")
        end
        row.xBtn:SetScript("OnClick", function()
            if gf.regenState.removed[rkey] then
                gf.regenState.removed[rkey] = nil
            else
                gf.regenState.removed[rkey] = true
            end
            gf.regenState.preview = nil
            if refresh then refresh() end
        end)
        row:Show()
        y = y - ROW_H - 1
    end
    r2.scrollContent:SetHeight(math.max(1, math.abs(y)))
end

local function BuildPreview(gf)
    local src = gf.regenState.sourceList
    if not src then return nil end
    local mode = gf.regenState.mode or "fpsaved"
    return ns.TodoList:RegenerateList(src, mode, gf.regenState.removed,
        gf.regenStepContainers[3].nameBox:GetText())
end

local function RenderStep3(gf, refresh, contentTop)
    local r3 = gf.regenStepContainers[3]
    local src = gf.regenState.sourceList
    if not src then
        r3.previewLabel:SetText("No source selected.")
        for _, row in ipairs(r3.rows) do row:Hide() end
        return
    end

    -- Default list name if not set
    if not r3.nameBox._initialized or r3.nameBox:GetText() == "" then
        r3.nameBox:SetText("Regen " .. date("%m-%d %H:%M") .. " — " .. (src.name or "list"))
        r3.nameBox._initialized = true
    end

    -- Layout (anchors live in Init; refresh values + layout once-only)
    r3.nameLabel:ClearAllPoints()
    r3.nameLabel:SetPoint("TOPLEFT", r3.modeTsm.desc, "BOTTOMLEFT", -24, -10)
    r3.nameBox:ClearAllPoints()
    r3.nameBox:SetPoint("LEFT", r3.nameLabel, "RIGHT", 8, 0)

    r3.previewLabel:ClearAllPoints()
    r3.previewLabel:SetPoint("TOPLEFT", r3.nameLabel, "BOTTOMLEFT", 0, -10)
    r3.scroll:ClearAllPoints()
    r3.scroll:SetPoint("TOPLEFT", r3.previewLabel, "BOTTOMLEFT", 0, -4)
    r3.scroll:SetPoint("BOTTOMRIGHT", r3, "BOTTOMRIGHT", -24, 4)

    -- Build (or rebuild) preview
    if not gf.regenState.preview or gf.regenState.preview._mode ~= gf.regenState.mode then
        gf.regenState.preview = BuildPreview(gf)
        if gf.regenState.preview then
            gf.regenState.preview._mode = gf.regenState.mode
        end
    end

    r3._onModeChange = function()
        gf.regenState.mode = r3._mode
        gf.regenState.preview = nil
        if refresh then refresh() end
    end

    local preview = gf.regenState.preview
    for _, row in ipairs(r3.rows) do row:Hide() end
    if not preview or not preview.tasks or #preview.tasks == 0 then
        r3.previewLabel:SetText("Preview: (empty — all tasks removed?)")
        return
    end

    r3.previewLabel:SetText(string.format("Preview (%d tasks, showing first 50):", #preview.tasks))
    local y = -2
    local shown = math.min(50, #preview.tasks)
    for i = 1, shown do
        local task = preview.tasks[i]
        local row = r3.rows[i]
        if not row then
            row = CreateTaskRow(r3.scrollContent)
            row.xBtn:Hide()
            r3.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", r3.scrollContent, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT",   r3.scrollContent, "RIGHT", -4, 0)
        row.name:SetText(task.name or "?")
        row.char:SetText(task.assignedChar or "(no char)")
        row.action:SetText(task.action == "buy" and "BUY" or "POST")
        row.price:SetText(task.expectedPrice or "")
        row:Show()
        y = y - ROW_H - 1
    end
    r3.scrollContent:SetHeight(math.max(1, math.abs(y)))
end

function RegenerateTrack:Render(gf, wizStep, refresh, layoutRect)
    -- Position the active container into layoutRect.
    -- layoutRect = { top, bottom } (negative y offsets relative to gf top)
    for i = 1, 3 do
        gf.regenStepContainers[i]:Hide()
    end
    if wizStep < 1 or wizStep > 3 then return end
    local sc = gf.regenStepContainers[wizStep]
    sc:ClearAllPoints()
    sc:SetPoint("TOPLEFT", gf, "TOPLEFT", 0, layoutRect.top)
    sc:SetPoint("BOTTOMRIGHT", gf, "BOTTOMRIGHT", 0, layoutRect.bottom)
    sc:Show()

    if wizStep == 1 then
        RenderStep1(gf, refresh)
    elseif wizStep == 2 then
        RenderStep2(gf, refresh)
    elseif wizStep == 3 then
        RenderStep3(gf, refresh)
    end
end

-- Allow GeneratorPage's nav logic to ask whether Next should be enabled.
function RegenerateTrack:IsNextAvailable(gf, wizStep)
    if wizStep == 1 then
        return gf.regenState and gf.regenState.sourceList ~= nil
    end
    -- Step 2 always allows Next (removals are optional)
    -- Step 3 has no Next (Save is the terminal action)
    return wizStep == 2
end

-- Save terminal action: commits the preview as a queued (or active) list.
-- Returns (committedList, mode) so caller can toast appropriately.
function RegenerateTrack:OnSave(gf)
    if not gf.regenState or not gf.regenState.sourceList then return nil end
    local preview = gf.regenState.preview or BuildPreview(gf)
    if not preview or not preview.tasks or #preview.tasks == 0 then return nil end

    local listName = gf.regenStepContainers[3].nameBox:GetText():match("^%s*(.-)%s*$")
    if not listName or listName == "" then
        listName = "Regenerated " .. date("%Y-%m-%d %H:%M")
    end
    preview.name = listName

    local currentList = ns.TodoList:GetCurrentList()
    local mode = currentList and "upcoming" or "replace"
    ns.TodoList:CommitList(preview, mode)

    -- Clear in-memory state so a follow-up regen starts fresh.
    gf.regenState.preview = nil
    gf.regenStepContainers[3].nameBox._initialized = false
    return preview, mode
end
