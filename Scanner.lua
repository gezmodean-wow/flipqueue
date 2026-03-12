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
        local numSlots = C_Container.GetContainerNumSlots(bagIndex)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagIndex, slot)
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

    ns.db.inventory[charKey] = {
        lastScan = time(),
        class    = select(2, UnitClass("player")),
        items    = allItems,
    }

    local count = 0
    for _ in pairs(allItems) do count = count + 1 end
    ns:Print("Scanned " .. count .. " unique items on " .. charKey)
end

function Scanner:ScanBank()
    if not ns.db then return end

    local charKey = ns:GetCharKey()
    local charData = ns.db.inventory[charKey]
    if not charData then
        self:ScanCurrentCharacter()
        charData = ns.db.inventory[charKey]
    end

    local bankItems = ScanContainers(ns:GetEnabledBankTabs(), true)
    MergeItems(charData.items, bankItems, "bank")
    charData.lastScan = time()

    local count = 0
    for _ in pairs(bankItems) do count = count + 1 end
    ns:Print("Bank scanned: " .. count .. " unique items.")
end

function Scanner:ScanWarbank()
    if not ns.db then return end

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
    ns:Print("Warbank scanned: " .. count .. " unique items.")
end

--------------------------
-- Event Handling
--------------------------

--------------------------
-- Character Metadata
--------------------------

local function UpdateCharacterMeta()
    if not ns.db then return end
    local charKey = ns:GetCharKey()
    ns.db.characters[charKey] = ns.db.characters[charKey] or {}
    local meta = ns.db.characters[charKey]
    meta.gold = GetMoney()
    meta.lastLogin = time()
    meta.class = select(2, UnitClass("player"))
    meta.level = UnitLevel("player")
end

--------------------------
-- Event Handling
--------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("PLAYER_MONEY")

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ns:InitDB()
        UpdateCharacterMeta()

        -- Auto-unskip items that have been skipped for more than 24h
        if ns.Queue and ns.Queue.UnskipExpired then
            ns.Queue:UnskipExpired()
        end

        if ns.db.settings.autoScan then
            C_Timer.After(2, function()
                Scanner:ScanCurrentCharacter()
                if ns.db.settings.showLoginMessage and ns.Queue then
                    local charKey = ns:GetCharKey()
                    local myRealm = charKey:match("%-(.+)$") or ""
                    local allTasks = ns.Queue:GetCharacterTasks(charKey)
                    local realmCount = 0
                    for _, task in ipairs(allTasks) do
                        if ns:RealmMatches(task.queueItem.targetRealm, myRealm) then
                            realmCount = realmCount + 1
                        end
                    end
                    if realmCount > 0 then
                        ns:Print(ns.COLORS.GREEN .. realmCount .. " items|r to post on this character! Type /fq to see details.")
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
    end
end)
