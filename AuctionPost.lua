-- AuctionPost.lua
-- AH posting and cancel engine: price resolution, bag scanning, posting, cancellation
local addonName, ns = ...

local AuctionPost = {}
ns.AuctionPost = AuctionPost

--------------------------
-- Duration Mapping
--------------------------

-- TSM stores duration as 1/2/3; WoW's C_AuctionHouse.PostItem / PostCommodity
-- also takes 1/2/3 (mapping to 12h/24h/48h internally). We keep a lookup for
-- display and validation.
local DURATION_HOURS = { [1] = 12, [2] = 24, [3] = 48 }

--------------------------
-- Commodity Detection
--------------------------

function AuctionPost:IsCommodity(itemID)
    local numID = tonumber(itemID)
    if not numID then return false end
    local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, numID)
    if not ok then return false end
    return status == Enum.ItemCommodityStatus.Commodity
end

--------------------------
-- TSM Price Resolution
--------------------------

-- Resolve posting price from TSM Auctioning operation for a given itemKey.
-- Returns a pricing table or nil if TSM is unavailable or no operation found.
function AuctionPost:ResolvePostPrice(itemKey, itemID)
    if not ns.TSM or not ns.TSM:IsEnabled() then
        ns:PrintDebug("[AuctionPost] ResolvePostPrice: TSM not available")
        return nil
    end

    local tsmStr = ns.TSM:ItemKeyToTSMString(itemKey)
    if not tsmStr then
        tsmStr = "i:" .. tostring(itemID)
    end

    local op = ns.TSM:GetItemAuctioningOp(itemKey)
    local normalCopper, minCopper, maxCopper
    local opName, postCap, duration

    if op then
        opName = op.opName
        postCap = op.postCap
        duration = op.duration

        ns:PrintDebug("[AuctionPost] ResolvePostPrice: " .. tostring(itemKey) ..
            " tsmStr=" .. tostring(tsmStr) .. " op=" .. tostring(opName))

        if op.normalPrice and op.normalPrice ~= "" and type(TSM_API) == "table" then
            local ok, val = pcall(TSM_API.GetCustomPriceValue, op.normalPrice, tsmStr)
            normalCopper = ok and val or nil
            if not ok then
                ns:PrintDebug("[AuctionPost]   normalPrice eval failed: " .. tostring(val))
            end
        end

        if op.minPrice and op.minPrice ~= "" and type(TSM_API) == "table" then
            local ok, val = pcall(TSM_API.GetCustomPriceValue, op.minPrice, tsmStr)
            minCopper = ok and val or nil
        end

        if op.maxPrice and op.maxPrice ~= "" and type(TSM_API) == "table" then
            local ok, val = pcall(TSM_API.GetCustomPriceValue, op.maxPrice, tsmStr)
            maxCopper = ok and val or nil
        end
    else
        ns:PrintDebug("[AuctionPost] ResolvePostPrice: no op for " .. tostring(itemKey) .. ", trying DBMinBuyout")
    end

    -- Fallback: if no operation or normalPrice couldn't be evaluated,
    -- use DBMinBuyout as the posting price reference.
    if not normalCopper then
        local fallback = ns.TSM:GetPrice(itemKey, "DBMinBuyout")
        if fallback and fallback > 0 then
            normalCopper = fallback
            if not opName then opName = "DBMinBuyout" end
        end
    end

    if not normalCopper then
        return nil
    end

    local belowThreshold = false
    if minCopper and normalCopper < minCopper then
        belowThreshold = true
    end

    return {
        normalCopper   = normalCopper,
        minCopper      = minCopper,
        maxCopper      = maxCopper,
        postCap        = postCap,
        duration       = duration,
        opName         = opName,
        belowThreshold = belowThreshold,
    }
end

--------------------------
-- Bag Scanning
--------------------------

-- Scan player bags for postable items.
-- filterToTodo: when true, only include items that match a pending todo task.
-- Returns array of scan result entries (deduplicated by itemKey).
function AuctionPost:ScanBags(filterToTodo)
    local bagList = ns.ALL_PLAYER_BAGS or ns.INVENTORY_BAGS
    if not bagList then return {} end

    -- Pre-build todo task lookup if filtering
    local todoTasks
    if filterToTodo and ns.TodoList then
        local currentList = ns.TodoList:GetCurrentList()
        if currentList and currentList.tasks then
            todoTasks = currentList.tasks
        end
    end

    local byKey = {} -- itemKey -> scan result (for deduplication)
    local order = {} -- ordered keys for stable output

    for _, bagIndex in ipairs(bagList) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        -- Skip Do Not Track items
                        if ns:IsDoNotTrack(itemID) then
                            -- Still record for "dnt" status if not filtering
                            if not filterToTodo then
                                local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                                if not byKey[key] then
                                    local name = info.hyperlink:match("|h%[(.-)%]|h") or ("Item " .. itemID)
                                    local iconOk, icon = pcall(C_Item.GetItemIconByID, tonumber(itemID))
                                    byKey[key] = {
                                        itemKey    = key,
                                        itemID     = itemID,
                                        name       = name,
                                        icon       = iconOk and icon or nil,
                                        slots      = {{bag = bagIndex, slot = slot, count = info.stackCount or 1}},
                                        totalCount = info.stackCount or 1,
                                        isCommodity = self:IsCommodity(itemID),
                                        pricing    = nil,
                                        postQty    = 0,
                                        status     = "dnt",
                                    }
                                    order[#order + 1] = key
                                else
                                    local entry = byKey[key]
                                    entry.slots[#entry.slots + 1] = {bag = bagIndex, slot = slot, count = info.stackCount or 1}
                                    entry.totalCount = entry.totalCount + (info.stackCount or 1)
                                end
                            end
                        else
                            local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)
                            local name = info.hyperlink:match("|h%[(.-)%]|h") or ("Item " .. itemID)

                            -- Filter to todo tasks if requested
                            local todoMatched = true
                            if filterToTodo and todoTasks then
                                todoMatched = false
                                for _, task in ipairs(todoTasks) do
                                    if task.status == "pending" or task.status == "skipped" then
                                        local m = ns:ItemsMatch(key, name, task, nil)
                                        if m then
                                            todoMatched = true
                                            break
                                        end
                                    end
                                end
                            end

                            if todoMatched and not byKey[key] then
                                local iconOk, icon = pcall(C_Item.GetItemIconByID, tonumber(itemID))
                                local pricing = self:ResolvePostPrice(key, itemID)
                                local isCommodity = self:IsCommodity(itemID)

                                local status = "ready"
                                if not pricing then
                                    status = "no_price"
                                elseif pricing.belowThreshold then
                                    status = "below_threshold"
                                end

                                -- Determine post quantity from TSM postCap or default
                                local postQty = info.stackCount or 1
                                if pricing and pricing.postCap and pricing.postCap > 0 then
                                    postQty = math.min(info.stackCount or 1, pricing.postCap)
                                end

                                byKey[key] = {
                                    itemKey     = key,
                                    itemID      = itemID,
                                    name        = name,
                                    icon        = iconOk and icon or nil,
                                    slots       = {{bag = bagIndex, slot = slot, count = info.stackCount or 1}},
                                    totalCount  = info.stackCount or 1,
                                    isCommodity = isCommodity,
                                    pricing     = pricing,
                                    postQty     = postQty,
                                    status      = status,
                                }
                                order[#order + 1] = key
                            elseif todoMatched then
                                local entry = byKey[key]
                                entry.slots[#entry.slots + 1] = {bag = bagIndex, slot = slot, count = info.stackCount or 1}
                                entry.totalCount = entry.totalCount + (info.stackCount or 1)
                                if entry.pricing and entry.pricing.postCap and entry.pricing.postCap > 0 then
                                    entry.postQty = math.min(entry.totalCount, entry.pricing.postCap)
                                else
                                    entry.postQty = entry.totalCount
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Build ordered result array
    local results = {}
    for _, key in ipairs(order) do
        results[#results + 1] = byKey[key]
    end

    return results
end

--------------------------
-- Post Single Item
--------------------------

-- Post a single item to the AH.
-- scanResult: a single entry from ScanBags
-- callback: function(success, errorMsg)
function AuctionPost:PostItem(scanResult, callback)
    local cb = callback or function() end

    -- Validate AH is open
    local ahOpen = (ns.Tracker and ns.Tracker._isAHOpen)
        or (AuctionHouseFrame and AuctionHouseFrame:IsShown())
    if not ahOpen then
        cb(false, "Auction House is not open")
        return
    end

    if not scanResult or not scanResult.slots or #scanResult.slots == 0 then
        cb(false, "No available bag slot")
        return
    end

    if scanResult.status ~= "ready" then
        cb(false, "Item status is " .. (scanResult.status or "unknown"))
        return
    end

    if not scanResult.pricing or not scanResult.pricing.normalCopper then
        cb(false, "No valid price resolved")
        return
    end

    -- Pick the first available slot
    local slotInfo = scanResult.slots[1]
    local itemLoc = ItemLocation:CreateFromBagAndSlot(slotInfo.bag, slotInfo.slot)

    -- Verify item location is valid
    if not C_Item.DoesItemExist(itemLoc) then
        cb(false, "Item no longer exists at bag " .. slotInfo.bag .. " slot " .. slotInfo.slot)
        return
    end

    local unitPrice = scanResult.pricing.normalCopper
    local quantity = scanResult.postQty or 1
    -- Duration: TSM uses 1/2/3, same as WoW API
    local duration = scanResult.pricing.duration or 3 -- default 48h

    local ok, err
    if scanResult.isCommodity then
        ok, err = pcall(C_AuctionHouse.PostCommodity, itemLoc, duration, quantity, unitPrice)
    else
        ok, err = pcall(C_AuctionHouse.PostItem, itemLoc, duration, quantity, unitPrice)
    end

    if not ok then
        ns:PrintDebug("PostItem failed: " .. tostring(err))
        cb(false, tostring(err))
        return
    end

    -- Log the posting
    if ns.db then
        local now = time()
        local charKey = ns:GetCharKey()
        local durationHours = DURATION_HOURS[duration] or 48
        local expiresAt = now + (durationHours * 3600)

        table.insert(ns.db.log, {
            itemKey        = scanResult.itemKey,
            itemID         = scanResult.itemID,
            name           = scanResult.name,
            quality        = "",
            icon           = scanResult.icon,
            targetRealm    = GetRealmName(),
            expectedPrice  = ns:FormatGold(unitPrice),
            postedPrice    = ns:FormatGold(unitPrice * quantity),
            postedAt       = now,
            charKey        = charKey,
            expiresAt      = expiresAt,
            auctionStatus  = "active",
            soldAt         = nil,
            soldPrice      = nil,
            postedQuantity = quantity,
        })

        ns:PrintDebug("Posted " .. (scanResult.name or "?") .. " x" .. quantity
            .. " at " .. ns:FormatGold(unitPrice) .. "/ea for " .. durationHours .. "h")
    end

    -- Move linked todo task to log if applicable
    if ns.TodoList then
        local currentList = ns.TodoList:GetCurrentList()
        if currentList and currentList.tasks then
            for taskIdx, task in ipairs(currentList.tasks) do
                if task.status == "pending" then
                    local matched = ns:ItemsMatch(scanResult.itemKey, scanResult.name, task, nil)
                    if matched then
                        local durationHours = DURATION_HOURS[duration] or 48
                        ns.TodoList:MoveTaskToLog(taskIdx, ns:FormatGold(unitPrice), durationHours * 3600, quantity)
                        break
                    end
                end
            end
        end
    end

    cb(true, nil)
end

--------------------------
-- Post All
--------------------------

-- Post all ready items sequentially with a delay between each.
-- scanResults: array from ScanBags
-- onProgress: function(index, total, currentItem) — called after each attempt
-- onComplete: function(posted, skipped, failed) — called when finished
function AuctionPost:PostAll(scanResults, onProgress, onComplete)
    if not scanResults or #scanResults == 0 then
        if onComplete then onComplete(0, 0, 0) end
        return
    end

    -- Filter to ready items
    local readyItems = {}
    local skipped = 0
    for _, item in ipairs(scanResults) do
        if item.status == "ready" then
            readyItems[#readyItems + 1] = item
        else
            skipped = skipped + 1
        end
    end

    if #readyItems == 0 then
        if onComplete then onComplete(0, skipped, 0) end
        return
    end

    local total = #readyItems
    local posted = 0
    local failed = 0
    local index = 0

    local function PostNext()
        index = index + 1
        if index > total then
            if onComplete then onComplete(posted, skipped, failed) end
            return
        end

        local item = readyItems[index]
        if onProgress then
            onProgress(index, total, item)
        end

        self:PostItem(item, function(success, errMsg)
            if success then
                posted = posted + 1
            else
                failed = failed + 1
                ns:PrintDebug("PostAll: failed " .. (item.name or "?") .. ": " .. (errMsg or "unknown"))
            end

            -- Delay before next post to avoid server throttling
            C_Timer.After(0.5, PostNext)
        end)
    end

    PostNext()
end

--------------------------
-- Owned Auctions
--------------------------

-- Get owned auctions with undercut detection.
-- Returns array of auction entries with market comparison data.
function AuctionPost:GetOwnedAuctions()
    if not C_AuctionHouse then return {} end

    local ok, owned = pcall(C_AuctionHouse.GetOwnedAuctions)
    if not ok or not owned then return {} end

    local results = {}

    for _, auction in ipairs(owned) do
        if auction.itemKey then
            local auctionID = auction.auctionID
            local itemID = auction.itemKey.itemID
            local quantity = auction.quantity or 1
            local totalBuyout = auction.buyoutAmount or 0
            local buyoutPerUnit = quantity > 0 and math.floor(totalBuyout / quantity) or 0
            local timeLeft = auction.timeLeftSeconds

            -- Resolve item name
            local name
            local speciesID = auction.itemKey.battlePetSpeciesID
            if speciesID and speciesID > 0 and C_PetJournal then
                name = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            end
            if not name and itemID then
                local nameOk, n = pcall(C_Item.GetItemInfo, itemID)
                name = nameOk and n or ("Item " .. tostring(itemID))
            end

            -- Get icon
            local icon
            if itemID then
                local iconOk, ic = pcall(C_Item.GetItemIconByID, itemID)
                icon = iconOk and ic or nil
            end

            -- Build item key for TSM lookup
            local itemKey = tostring(itemID) .. ";;"

            -- Undercut detection via TSM DBMinBuyout
            local marketPrice, isUndercut, undercutBy
            if ns.TSM and ns.TSM:IsEnabled() then
                marketPrice = ns.TSM:GetPrice(itemKey, "DBMinBuyout")
                if marketPrice and buyoutPerUnit > 0 then
                    isUndercut = buyoutPerUnit > marketPrice
                    if isUndercut then
                        undercutBy = buyoutPerUnit - marketPrice
                    end
                end
            end

            results[#results + 1] = {
                auctionID     = auctionID,
                itemID        = tostring(itemID),
                name          = name or ("Item " .. tostring(itemID)),
                icon          = icon,
                quantity      = quantity,
                buyoutPerUnit = buyoutPerUnit,
                totalBuyout   = totalBuyout,
                marketPrice   = marketPrice,
                isUndercut    = isUndercut or false,
                undercutBy    = undercutBy,
                timeLeft      = timeLeft,
            }
        end
    end

    return results
end

--------------------------
-- Cancel Auction
--------------------------

-- Cancel an auction by ID.
-- Increments _pendingCancels so TrackerAuctions reconciliation works correctly.
-- callback: function(success, errorMsg)
function AuctionPost:CancelAuction(auctionID, callback)
    local cb = callback or function() end

    if not auctionID then
        cb(false, "No auction ID provided")
        return
    end

    local ok, err = pcall(C_AuctionHouse.CancelAuction, auctionID)
    if not ok then
        ns:PrintDebug("CancelAuction failed: " .. tostring(err))
        cb(false, tostring(err))
        return
    end

    -- Increment pending cancels for TrackerAuctions reconciliation
    if ns.Tracker then
        ns.Tracker._pendingCancels = (ns.Tracker._pendingCancels or 0) + 1
    end

    ns:PrintDebug("Cancelled auction ID " .. tostring(auctionID))
    cb(true, nil)
end

--------------------------
-- Bank Scanning for Saleable Items
--------------------------

-- Scan bank/warbank for items that have a TSM Auctioning operation.
-- filter: "all" | "warbank" | "bank"
-- Returns array of pull ops compatible with BankQueue:ProcessSync.
function AuctionPost:ScanBankForSaleable(filter)
    filter = filter or "all"

    local bankTabs = {}
    local warbankTabs = {}

    if filter == "all" or filter == "bank" then
        local enabled = ns:GetEnabledBankTabs()
        if enabled then
            for _, b in ipairs(enabled) do
                bankTabs[#bankTabs + 1] = b
            end
        end
    end

    if filter == "all" or filter == "warbank" then
        local enabled = ns:GetEnabledWarbankTabs()
        if enabled then
            for _, b in ipairs(enabled) do
                warbankTabs[#warbankTabs + 1] = b
            end
        end
    end

    -- Merge all tabs to scan
    local allTabs = {}
    for _, b in ipairs(bankTabs) do allTabs[#allTabs + 1] = b end
    for _, b in ipairs(warbankTabs) do allTabs[#allTabs + 1] = b end

    if #allTabs == 0 then return {} end

    local ops = {}

    for _, bagIndex in ipairs(allTabs) do
        local ok, numSlots = pcall(C_Container.GetContainerNumSlots, bagIndex)
        if ok and numSlots then
            for slot = 1, numSlots do
                local ok2, info = pcall(C_Container.GetContainerItemInfo, bagIndex, slot)
                if ok2 and info and info.hyperlink then
                    local itemID, bonusIDs, modifiers = ns:ParseItemLink(info.hyperlink)
                    if itemID then
                        -- Skip Do Not Track items
                        if not ns:IsDoNotTrack(itemID) then
                            local key = ns:MakeItemKey(itemID, bonusIDs, modifiers)

                            -- Check if item has a TSM Auctioning operation
                            if ns.TSM and ns.TSM:IsEnabled() then
                                local tsmOp = ns.TSM:GetItemAuctioningOp(key)
                                if tsmOp then
                                    local name = info.hyperlink:match("|h%[(.-)%]|h") or ("Item " .. itemID)
                                    ops[#ops + 1] = {
                                        op       = "pull",
                                        srcBag   = bagIndex,
                                        srcSlot  = slot,
                                        name     = name,
                                        icon     = info.iconFileID,
                                        quantity = info.stackCount or 1,
                                        itemKey  = key,
                                        itemID   = itemID,
                                        postCap  = tsmOp.postCap,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return ops
end
