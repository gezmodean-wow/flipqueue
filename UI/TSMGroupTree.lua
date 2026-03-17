-- UI/TSMGroupTree.lua
-- Scrollable tree widget for navigating TSM group hierarchy
local addonName, ns = ...

local UI = ns.UI

-- ==========================================
-- TSM GROUP TREE WIDGET
-- ==========================================

-- Create a tree navigator widget for TSM groups.
-- parent: parent frame to anchor within
-- onSelect(groupPath): callback when a group is selected
-- Returns a tree widget with API: SetProfile(name), GetSelectedPath(), Refresh()
function UI:CreateGroupTree(parent, onSelect)
    local ROW_HEIGHT = 20
    local INDENT_PX = 16

    local tree = CreateFrame("Frame", nil, parent)
    tree:SetAllPoints()

    -- Scroll container
    local scroll = CreateFrame("ScrollFrame", nil, tree, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", tree, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", tree, "BOTTOMRIGHT", -22, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(scroll:GetWidth())
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    scroll:SetScript("OnSizeChanged", function(sf, w)
        content:SetWidth(w)
    end)

    -- State
    tree._profile = nil
    tree._selectedPath = nil
    tree._expanded = {}  -- groupPath -> true
    tree._rows = {}
    tree._onSelect = onSelect

    -- Build tree structure from flat group paths
    -- TSM groups: backtick-separated paths like "Crafts`Enchanting`Rings"
    -- groupsDB: groupPath -> groupData (module assignments)
    -- itemsDB:  tsmItemString -> groupPath (item-to-group mapping)
    local function BuildTreeData(groupsDB, itemsDB)
        if not groupsDB then return {} end

        -- Count items per group from the items DB
        local groupItemCounts = {}  -- groupPath -> count
        if itemsDB then
            for _, groupPath in pairs(itemsDB) do
                if type(groupPath) == "string" then
                    groupItemCounts[groupPath] = (groupItemCounts[groupPath] or 0) + 1
                end
            end
        end

        -- Collect all paths
        local nodes = {}  -- path -> { name, path, depth, children[], itemCount }
        local roots = {}

        for groupPath in pairs(groupsDB) do
            if type(groupPath) == "string" and groupPath ~= "" then
                local parts = {strsplit("`", groupPath)}
                local currentPath = ""
                for i, part in ipairs(parts) do
                    local prevPath = currentPath
                    currentPath = (i == 1) and part or (currentPath .. "`" .. part)

                    if not nodes[currentPath] then
                        nodes[currentPath] = {
                            name = part,
                            path = currentPath,
                            depth = i - 1,
                            children = {},
                            itemCount = groupItemCounts[currentPath] or 0,
                        }
                        if i == 1 then
                            table.insert(roots, currentPath)
                        elseif nodes[prevPath] then
                            table.insert(nodes[prevPath].children, currentPath)
                        end
                    end
                end
            end
        end

        -- Sort children alphabetically
        for _, node in pairs(nodes) do
            table.sort(node.children, function(a, b)
                return (nodes[a] and nodes[a].name or a):lower()
                     < (nodes[b] and nodes[b].name or b):lower()
            end)
        end

        table.sort(roots, function(a, b)
            return (nodes[a] and nodes[a].name or a):lower()
                 < (nodes[b] and nodes[b].name or b):lower()
        end)

        return nodes, roots
    end

    -- Flatten visible tree into ordered list
    local function FlattenTree(nodes, roots, expanded)
        local flat = {}
        local function Walk(pathList, depth)
            for _, path in ipairs(pathList) do
                local node = nodes[path]
                if node then
                    table.insert(flat, {
                        path = path,
                        name = node.name,
                        depth = depth,
                        hasChildren = #node.children > 0,
                        itemCount = node.itemCount,
                    })
                    if expanded[path] and #node.children > 0 then
                        Walk(node.children, depth + 1)
                    end
                end
            end
        end
        Walk(roots, 0)
        return flat
    end

    -- Render the tree
    function tree:Refresh()
        -- Hide all existing rows
        for _, row in ipairs(self._rows) do
            row:Hide()
        end

        local profile = self._profile
        if not profile or not ns.TSM then
            return
        end

        local groupsDB = ns.TSM:GetGroupsDB(profile)
        if not groupsDB then return end

        local itemsDB = ns.TSM:GetItemsDB(profile)
        local nodes, roots = BuildTreeData(groupsDB, itemsDB)
        local flat = FlattenTree(nodes, roots, self._expanded)

        local y = 0
        for i, entry in ipairs(flat) do
            local row = self._rows[i]
            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetHeight(ROW_HEIGHT)

                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()

                row.toggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.toggle:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.toggle:SetWidth(12)

                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.label:SetJustifyH("LEFT")

                row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.count:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row.count:SetJustifyH("RIGHT")

                row:EnableMouse(true)
                self._rows[i] = row
            end

            local indent = entry.depth * INDENT_PX
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

            -- Toggle indicator
            row.toggle:ClearAllPoints()
            row.toggle:SetPoint("LEFT", row, "LEFT", 4 + indent, 0)
            if entry.hasChildren then
                row.toggle:SetText(self._expanded[entry.path]
                    and "|cffffffff\226\150\188|r"
                    or "|cffffffff\226\150\182|r")
            else
                row.toggle:SetText("")
            end

            -- Label
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row.toggle, "RIGHT", 2, 0)
            row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)

            local isSelected = (self._selectedPath == entry.path)
            if isSelected then
                row.bg:SetColorTexture(0.2, 0.35, 0.5, 0.6)
                row.label:SetText("|cffffffff" .. entry.name .. "|r")
            else
                row.bg:SetColorTexture(0, 0, 0, 0)
                row.label:SetText(entry.name)
                row.label:SetTextColor(0.8, 0.8, 0.8)
            end

            -- Item count
            if entry.itemCount > 0 then
                row.count:SetText(ns.COLORS.GRAY .. entry.itemCount .. "|r")
            else
                row.count:SetText("")
            end

            -- Click handler
            local path = entry.path
            local hasChildren = entry.hasChildren
            row:SetScript("OnClick", function(_, button)
                if hasChildren then
                    self._expanded[path] = not self._expanded[path]
                end
                self._selectedPath = path
                self:Refresh()
                if self._onSelect then
                    self._onSelect(path)
                end
            end)
            row:SetScript("OnEnter", function(self)
                if not isSelected then
                    self.bg:SetColorTexture(1, 1, 1, 0.05)
                end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(path:gsub("`", " > "), 1, 1, 1)
                if entry.itemCount > 0 then
                    GameTooltip:AddLine(entry.itemCount .. " items in this group", 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                if not (tree._selectedPath == path) then
                    self.bg:SetColorTexture(0, 0, 0, 0)
                end
                GameTooltip:Hide()
            end)

            row:Show()
            y = y + ROW_HEIGHT
        end

        content:SetHeight(math.max(1, y))
    end

    -- API
    function tree:SetProfile(name)
        self._profile = name
        self._selectedPath = nil
        self._expanded = {}
        self:Refresh()
    end

    function tree:GetSelectedPath()
        return self._selectedPath
    end

    return tree
end
