-- Scanner.lua
-- Scans current character inventory and stores to account-wide DB
local addonName, ns = ...

local Scanner = {}
ns.Scanner = Scanner

-- Hidden tooltip for bind-type detection
local scanTooltip = CreateFrame("GameTooltip", "FlipQueueScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

--------------------------
-- Bind Type Detection
--------------------------

-- Check tooltip lines for warbound-until-equipped text
local function IsWarboundUntilEquipped(bagIndex, slot)
    scanTooltip:ClearLines()
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:SetBagItem(bagIndex, slot)
    for i = 2, 6 do
        local line = _G["FlipQueueScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                if text:find("Warbound until equipped") or text:find("Binds to Warband until equipped") then
                    scanTooltip:Hide()
                    return true
                end
            end
        end
    end
    scanTooltip:Hide()
    return false
end

-- Get bind info for an item
-- Returns bindType (number), isBound (boolean)
-- bindType: 0=none, 1=BoP, 2=BoE, 3=BoU, 4=Quest, 7=BtA, 8=BtW, 9=WuE
local function GetBindInfo(itemLink, containerItemInfo, bagIndex, slot)
    local isBound = containerItemInfo.isBound or false
    local ok, _, _, _, _, _, _, _, _, _, _, _, _, _, bt = pcall(C_Item.GetItemInfo, itemLink)
    local bindType = (ok and bt) or 0

    -- Check for warbound-until-equipped via tooltip
    if bindType == 2 and not isBound and bagIndex and slot then
        if IsWarboundUntilEquipped(bagIndex, slot) then
            bindType = 9
        end
    end

    return bindType, isBound
end

--------------------------
-- Container Scanning
--------------------------

local function ScanContainers(bagIndices, captureBindInfo)
    local items = {}
    for _, bagIndex in ipairs(bagIndices) do
        local okSlots, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if not okSlots or not numSlots then numSlots = 0 end
        for slot = 1, numSlots do
            local okInfo, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
            if not okInfo then info = nil end
            if info and info.hyperlink then
                local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                if itemID then
                    local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                    if not items[key] then
                        local itemName
                        -- Battle pets: C_Item.GetItemInfo returns nil, extract name from link
                        if info.hyperlink:find("|Hbattlepet:") then
                            itemName = info.hyperlink:match("|h%[(.-)%]|h")
                        else
                            local okName, n = pcall(C_Item.GetItemInfo, info.hyperlink)
                            itemName = okName and n or nil
                        end
                        items[key] = {
                            itemID    = itemID,
                            name      = itemName or "Unknown",
                            bonusIDs  = bonusIDs,
                            modifiers = modifiers,
                            quantity  = 0,
                            icon      = info.iconFileID,
                        }
                        if captureBindInfo then
                            -- Battle pets (caged) are always tradeable
                            if info.hyperlink:find("|Hbattlepet:") then
                                items[key].bindType = 0
                                items[key].isBound = false
                            else
                                local bindType, isBound = GetBindInfo(info.hyperlink, info, bagIndex, slot)
                                items[key].bindType = bindType
                                items[key].isBound = isBound
                            end
                        end
                    end
                    items[key].quantity = items[key].quantity + (info.stackCount or 1)
                end
            end
        end
    end
    return items
end

local function MergeItems(target, source, location)
    for key, data in pairs(source) do
        if not target[key] then
            target[key] = {
                itemID    = data.itemID,
                name      = data.name,
                bonusIDs  = data.bonusIDs,
                modifiers = data.modifiers,
                quantity  = 0,
                icon      = data.icon,
                locations = {},
                bindType  = data.bindType,
                isBound   = data.isBound,
            }
        end
        target[key].quantity = target[key].quantity + data.quantity
        target[key].locations[location] = (target[key].locations[location] or 0) + data.quantity
        if data.bindType and not target[key].bindType then
            target[key].bindType = data.bindType
            target[key].isBound = data.isBound
        end
    end
end

--------------------------
-- Deal Enrichment
--------------------------

-- When we scan physical items, backfill import entries that have incomplete data.
-- Imports from FP often arrive with bare item IDs (no bonus IDs, no icon, no quality).
-- The scanned item has the real hyperlink data — use it to fill the gaps.
local function EnrichDealsFromInventory(scannedItems)
    if not ns.db or not ns.db.imports or not ns.db.imports.fpScanner then return end

    for _, queueItem in pairs(ns.db.imports.fpScanner) do
        local queueNumID = tonumber(queueItem.itemID) or tonumber((queueItem.itemKey or ""):match("^(%d+)"))
        local queueName = (queueItem.name or ""):lower()
        local queueHasBonuses = queueItem.itemKey and queueItem.itemKey:match("^[^;]*;([^;]*)") or ""

        -- Only enrich if the queue item is missing bonus IDs
        if queueHasBonuses == "" and queueNumID then
            for key, itemData in pairs(scannedItems) do
                local scannedNumID = tonumber((key:match("^(%d+)")))
                local scannedBonuses = key:match("^[^;]*;([^;]*)") or ""
                local nameMatch = queueName ~= "" and itemData.name
                    and itemData.name:lower() == queueName

                if (scannedNumID and scannedNumID == queueNumID) or nameMatch then
                    -- Found a match with real data — enrich the queue item
                    local enriched = false

                    if scannedBonuses ~= "" then
                        queueItem.itemKey = key
                        queueItem.bonusIDs = itemData.bonusIDs
                        queueItem.modifiers = itemData.modifiers
                        enriched = true
                    end

                    if not queueItem.icon and itemData.icon then
                        queueItem.icon = itemData.icon
                        enriched = true
                    end

                    if (not queueItem.name or queueItem.name == "") and itemData.name then
                        queueItem.name = itemData.name
                        enriched = true
                    end

                    -- Look up quality if missing
                    if not queueItem.quality or queueItem.quality == "" then
                        local numID = tonumber(itemData.itemID)
                        if numID and numID > 0 then
                            local ok, _, _, q = pcall(C_Item.GetItemInfo, numID)
                            if ok and q then
                                local qualityNames = {[0]="Poor",[1]="Common",[2]="Uncommon",
                                    [3]="Rare",[4]="Epic",[5]="Legendary"}
                                queueItem.quality = qualityNames[q] or ""
                                enriched = true
                            end
                        end
                    end

                    break -- only match one inventory item per queue item
                end
            end
        end
    end
end

--------------------------
-- Public Scan Functions
--------------------------

function Scanner:ScanCurrentCharacter()
    if not ns.db then return end

    local charKey = ns:GetCharKey()
    local allItems = {}

    local bagItems = ScanContainers(ns.INVENTORY_BAGS, true)
    MergeItems(allItems, bagItems, "bags")

    local reagentItems = ScanContainers({ns.REAGENT_BAG}, true)
    MergeItems(allItems, reagentItems, "reagent")

    -- Preserve bank locations from previous scan (bank can only be scanned when open)
    ns.db.characters[charKey] = ns.db.characters[charKey] or {}
    local charEntry = ns.db.characters[charKey]
    charEntry.class = select(2, UnitClass("player"))
    local prevData = charEntry.inventory
    if prevData and prevData.items then
        for key, prevItem in pairs(prevData.items) do
            if prevItem.locations and prevItem.locations.bank and prevItem.locations.bank > 0 then
                if not allItems[key] then
                    allItems[key] = {
                        itemID    = prevItem.itemID,
                        name      = prevItem.name,
                        bonusIDs  = prevItem.bonusIDs,
                        modifiers = prevItem.modifiers,
                        quantity  = 0,
                        icon      = prevItem.icon,
                        locations = {},
                        bindType  = prevItem.bindType,
                        isBound   = prevItem.isBound,
                    }
                end
                allItems[key].locations.bank = prevItem.locations.bank
                allItems[key].quantity = allItems[key].quantity + prevItem.locations.bank
            end
        end
    end

    local prevBankScan = prevData and prevData.lastBankScan or nil
    charEntry.inventory = {
        lastScan     = time(),
        lastBankScan = prevBankScan,
        items        = allItems,
    }

    local count = 0
    for _ in pairs(allItems) do count = count + 1 end
    ns:PrintDebug("Scanned " .. count .. " unique items on " .. charKey)

    EnrichDealsFromInventory(allItems)
end

function Scanner:ScanBank()
    if not ns.db then return end

    local charKey = ns:GetCharKey()
    local charEntry = ns.db.characters[charKey]
    local charData = charEntry and charEntry.inventory
    if not charData then
        self:ScanCurrentCharacter()
        charEntry = ns.db.characters[charKey]
        charData = charEntry and charEntry.inventory
    end

    -- Clear existing bank locations (authoritative scan replaces all bank data)
    for key, item in pairs(charData.items) do
        if item.locations and item.locations.bank and item.locations.bank > 0 then
            item.quantity = item.quantity - item.locations.bank
            item.locations.bank = nil
        end
    end
    -- Remove items that only existed in bank (zero quantity after clearing)
    for key, item in pairs(charData.items) do
        if item.quantity <= 0 then
            charData.items[key] = nil
        end
    end

    local bankItems = ScanContainers(ns:GetEnabledBankTabs(), true)
    MergeItems(charData.items, bankItems, "bank")
    charData.lastScan = time()
    charData.lastBankScan = time()

    local count = 0
    for _ in pairs(bankItems) do count = count + 1 end
    ns:PrintDebug("Bank scanned: " .. count .. " unique items.")

    EnrichDealsFromInventory(bankItems)
end

function Scanner:ScanWarbank()
    if not ns.db then return end

    -- Check if warbank is accessible (follows Baganator/Syndicator pattern)
    local okLock, lockReason = pcall(C_Bank.FetchBankLockedReason, Enum.BankType.Account)
    if not okLock or lockReason ~= nil then
        ns:PrintDebug("Warbank not accessible, skipping scan.")
        return
    end

    local warbankItems = ScanContainers(ns:GetEnabledWarbankTabs(), true)
    local items = {}
    for key, data in pairs(warbankItems) do
        items[key] = {
            itemID    = data.itemID,
            name      = data.name,
            bonusIDs  = data.bonusIDs,
            modifiers = data.modifiers,
            quantity  = data.quantity,
            icon      = data.icon,
            bindType  = data.bindType,
            isBound   = data.isBound,
        }
    end

    ns.db.warbank = {
        lastScan = time(),
        items    = items,
    }

    local count = 0
    for _ in pairs(items) do count = count + 1 end
    ns:PrintDebug("Warbank scanned: " .. count .. " unique items.")

    EnrichDealsFromInventory(items)
end

--------------------------
-- Guild Bank Scanning
--------------------------

local guildBankOpen = false
local guildBankScanning = false
local guildScanQueue = {}  -- tabs remaining to scan
local guildScanData = {}   -- accumulated scan results

-- Scan a single guild bank tab (items already loaded by QueryGuildBankTab)
local function ScanGuildBankTab(tab)
    local items = {}
    for slot = 1, 98 do
        local ok, texture, itemCount, locked = pcall(GetGuildBankItemInfo, tab, slot)
        if ok and texture and itemCount and itemCount > 0 then
            local okLink, link = pcall(GetGuildBankItemLink, tab, slot)
            if okLink and link then
                local itemID, bonusIDs, modifiers = ns:ParseItemLink(link)
                if itemID then
                    local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                    if not items[key] then
                        local itemName
                        if link:find("|Hbattlepet:") then
                            itemName = link:match("|h%[(.-)%]|h")
                        else
                            local okName, n = pcall(C_Item.GetItemInfo, link)
                            itemName = okName and n or nil
                        end
                        items[key] = {
                            itemID    = itemID,
                            name      = itemName or "Unknown",
                            bonusIDs  = bonusIDs,
                            modifiers = modifiers,
                            quantity  = 0,
                            icon      = texture,
                        }
                    end
                    items[key].quantity = items[key].quantity + itemCount
                end
            end
        end
    end
    return items
end

-- Process next tab in the scan queue
local function ProcessNextGuildTab()
    if #guildScanQueue == 0 then
        -- All tabs scanned — save results
        guildBankScanning = false
        if not ns.db then return end
        local guildName = GetGuildInfo("player") or "Unknown Guild"
        ns.db.guilds = ns.db.guilds or {}
        if not ns.db.guilds[guildName] then
            ns.db.guilds[guildName] = { enabled = true, members = {} }
        end
        ns.db.guilds[guildName].enabled = true  -- enable on first scan
        ns.db.guilds[guildName].lastScan = time()
        ns.db.guilds[guildName].items = guildScanData
        local count = 0
        for _ in pairs(guildScanData) do count = count + 1 end
        ns:Print(ns.COLORS.CYAN .. "Guild bank scanned: " .. count .. " unique items (" .. guildName .. ")|r")
        guildScanData = {}
        return
    end

    local tab = table.remove(guildScanQueue, 1)
    QueryGuildBankTab(tab)
    -- GUILDBANKBAGSLOTS_CHANGED will fire when data is ready
end

-- Called when GUILDBANKBAGSLOTS_CHANGED fires during a scan
local function OnGuildBankSlotsChanged()
    if not guildBankOpen or not guildBankScanning then return end

    local currentTab = GetCurrentGuildBankTab()
    if currentTab then
        local tabItems = ScanGuildBankTab(currentTab)
        -- Merge into accumulated data
        for key, data in pairs(tabItems) do
            if not guildScanData[key] then
                guildScanData[key] = {
                    itemID    = data.itemID,
                    name      = data.name,
                    bonusIDs  = data.bonusIDs,
                    modifiers = data.modifiers,
                    quantity  = 0,
                    icon      = data.icon,
                }
            end
            guildScanData[key].quantity = guildScanData[key].quantity + data.quantity
        end
    end

    -- Continue to next tab after a short delay (server throttle)
    C_Timer.After(0.3, ProcessNextGuildTab)
end

function Scanner:ScanGuildBank()
    if not ns.db then return end
    if not guildBankOpen then
        ns:PrintError("Guild bank must be open to scan.")
        return
    end

    local numTabs = GetNumGuildBankTabs()
    if numTabs == 0 then
        ns:PrintError("No guild bank tabs available.")
        return
    end

    guildScanData = {}
    guildScanQueue = {}

    -- Check per-tab config for this guild
    local guildName = GetGuildInfo("player")
    local disabledTabs = guildName and ns.db.guilds and ns.db.guilds[guildName]
        and ns.db.guilds[guildName].disabledTabs or {}

    for tab = 1, numTabs do
        local ok, name, icon, isViewable = pcall(GetGuildBankTabInfo, tab)
        if ok and isViewable and not disabledTabs[tab] then
            table.insert(guildScanQueue, tab)
        end
    end

    if #guildScanQueue == 0 then
        ns:PrintError("No viewable guild bank tabs.")
        return
    end

    guildBankScanning = true
    ns:PrintDebug("Scanning " .. #guildScanQueue .. " guild bank tab(s)...")
    ProcessNextGuildTab()
end

--------------------------
-- Character Metadata
--------------------------

local function UpdateCharacterMeta()
    if not ns.db then return end
    local charKey = ns:GetCharKey()
    ns.db.characters[charKey] = ns.db.characters[charKey] or {}
    local char = ns.db.characters[charKey]
    char.gold = GetMoney()
    char.lastLogin = time()
    char.class = select(2, UnitClass("player"))
    char.level = UnitLevel("player")
    char.guild = GetGuildInfo("player")
    -- Register guild even if guild bank hasn't been scanned yet
    if char.guild then
        ns.db.guilds = ns.db.guilds or {}
        if not ns.db.guilds[char.guild] then
            ns.db.guilds[char.guild] = { enabled = false, members = {} }
        end
        local guild = ns.db.guilds[char.guild]
        guild.members = guild.members or {}
        local found = false
        for _, ck in ipairs(guild.members) do
            if ck == charKey then found = true; break end
        end
        if not found then
            table.insert(guild.members, charKey)
        end
    end
end

--------------------------
-- Event Handling
--------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("PLAYER_MONEY")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
frame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        ns:InitDB()
        UpdateCharacterMeta()

        -- Print cleanup summary if data was migrated/cleaned
        if ns.db._cleanupSummary then
            ns:Print(ns.COLORS.GRAY .. "Data cleanup: " .. ns.db._cleanupSummary .. "|r")
            ns.db._cleanupSummary = nil
        end

        -- Start periodic expiry checker
        if ns.Tracker and ns.Tracker.StartExpiryTicker then
            ns.Tracker:StartExpiryTicker()
        end

        if ns.db.settings.autoScan then
            C_Timer.After(2, function()
                -- Check if this is a new character being scanned for the first time
                local isFirstScan = not ns.db.characters[ns:GetCharKey()] or not ns.db.characters[ns:GetCharKey()].inventory
                Scanner:ScanCurrentCharacter()

                -- First-time onboarding: if there are deals but few characters, show hint
                if isFirstScan then
                    local charCount = 0
                    for _ in pairs(ns.db.characters) do charCount = charCount + 1 end
                    local dealCount = ns:ImportGetCount("fpScanner")
                    if dealCount > 0 and charCount <= 2 then
                        ns:Print(ns.COLORS.YELLOW .. "Character registered!|r Log into each of your posting characters once so FlipQueue can match deals to them.")
                    end
                end

                -- Refresh task steps on login (items may have changed since last session)
                if ns.TodoList and ns.TodoList.RefreshTaskSteps then
                    ns.TodoList:RefreshTaskSteps()
                end

                if ns.db.settings.showLoginMessage and ns.TodoList then
                    local charKey = ns:GetCharKey()
                    local todoTasks = ns.TodoList:GetCharacterTasks(charKey)
                    if #todoTasks > 0 then
                        ns:Print(ns.COLORS.GREEN .. #todoTasks .. " items|r to post on this character! Type /fq to see details.")
                    end
                end

                -- Expired auctions on this character (need collecting)
                local currentCharKey = ns:GetCharKey()
                local expiredCount = 0
                for _, entry in ipairs(ns.db.log) do
                    if entry.auctionStatus == "expired" and entry.charKey == currentCharKey then
                        expiredCount = expiredCount + 1
                    end
                end
                if expiredCount > 0 then
                    ns:Print(ns.COLORS.ORANGE .. expiredCount .. " expired auction(s) to collect — check the AH!|r")
                end

                -- Expiring auction alerts (across all characters)
                if ns.Tracker and ns.Tracker.CheckExpiringAuctions then
                    local expiring = ns.Tracker:CheckExpiringAuctions()
                    if #expiring > 0 then
                        local byChar = {}
                        for _, entry in ipairs(expiring) do
                            local ck = entry.charKey or "Unknown"
                            byChar[ck] = (byChar[ck] or 0) + 1
                        end
                        for ck, count in pairs(byChar) do
                            ns:Print(ns.COLORS.ORANGE .. count .. " auction(s) expiring soon on " .. ck .. "!|r")
                        end
                    end
                end
            end)
        end

    elseif event == "BANKFRAME_OPENED" then
        C_Timer.After(0.5, function()
            Scanner:ScanCurrentCharacter()
            Scanner:ScanBank()
            Scanner:ScanWarbank()
        end)

    elseif event == "PLAYER_MONEY" then
        if ns.db then
            local charKey = ns:GetCharKey()
            if ns.db.characters[charKey] then
                ns.db.characters[charKey].gold = GetMoney()
            end
        end

    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        -- GuildBanker = 10 (Enum.PlayerInteractionType.GuildBanker)
        if interactionType == 10 or (Enum.PlayerInteractionType and interactionType == Enum.PlayerInteractionType.GuildBanker) then
            guildBankOpen = true
            -- Guild bank scanning disabled: Blizzard API returns unreliable item data
            -- (stripped bonus IDs, wrong ilvl, pets as "Pet Cage"). Re-enable when fixed.
        end

    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        if interactionType == 10 or (Enum.PlayerInteractionType and interactionType == Enum.PlayerInteractionType.GuildBanker) then
            guildBankOpen = false
            guildBankScanning = false
            guildScanQueue = {}
        end

    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        if guildBankOpen then
            OnGuildBankSlotsChanged()
        end
    end
end)
