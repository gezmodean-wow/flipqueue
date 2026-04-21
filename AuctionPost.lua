-- AuctionPost.lua
-- AH posting and cancel engine: price resolution, bag scanning, posting, cancellation
local addonName, ns = ...

local AuctionPost = {}
ns.AuctionPost = AuctionPost

--------------------------
-- Post Result Tracking
--------------------------

-- Enum.AuctionHouseError values from Blizzard's API. Used to name error codes
-- from AUCTION_HOUSE_SHOW_ERROR. Derived from the enum order in
-- Blizzard_AuctionHouseUI / the API docs; if Blizzard reorders this we just
-- show the numeric fallback.
local AH_ERROR_NAMES = {
    [0]  = "DatabaseError",
    [1]  = "HigherBid",
    [2]  = "BidIncrement",
    [3]  = "BidOwn",
    [4]  = "ItemNotSuitable",
    [5]  = "AuctionHouseBusy",
    [6]  = "AuctionHouseUnavailable",
    [7]  = "RestrictedAccount",
    [8]  = "HasRestriction",
    [9]  = "NotEnoughMoney",
    [10] = "ItemNotFound",
    [11] = "Repair",
    [12] = "UsedCharges",
    [13] = "Wrapped",
    [14] = "LimitedDuration",
    [15] = "Bag",
}

-- Debounced owned-auctions requery. After a successful post or cancel we
-- re-query the server so the OWNED_AUCTIONS_UPDATED event fires, which causes
-- FlipQueue (via Tracker:CheckOwnedAuctions), TSM, Auctionator, and any
-- other addon listening for the event to refresh their owned-auctions view.
-- Blizzard doesn't always fire the event automatically after PostItem, so
-- we force it. Debounce collapses rapid sequential posts (e.g., multiple
-- commodity stacks posted back-to-back) into a single requery.
local _queryTimer = nil
local function RequestOwnedAuctionsRefresh()
    if _queryTimer then return end
    _queryTimer = C_Timer.After(1.0, function()
        _queryTimer = nil
        if not C_AuctionHouse or not C_AuctionHouse.QueryOwnedAuctions then return end
        -- Only requery if the AH is still open; doing it closed is a no-op
        -- but wastes a throttled query slot.
        if ns.Tracker and not ns.Tracker._isAHOpen then return end
        local ok, err = pcall(C_AuctionHouse.QueryOwnedAuctions, {})
        if ok then
            ns:PrintDebug("[AuctionPost] requested owned-auctions refresh")
        else
            ns:PrintDebug("[AuctionPost] QueryOwnedAuctions failed: " .. tostring(err))
        end
    end)
end

-- Listen for server responses to PostItem/PostCommodity to verify success.
local postResultFrame = CreateFrame("Frame")
postResultFrame:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
postResultFrame:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
postResultFrame:RegisterEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION")
postResultFrame:RegisterEvent("UI_ERROR_MESSAGE")
postResultFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
postResultFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "AUCTION_HOUSE_AUCTION_CREATED" then
        ns:PrintDebug("[AuctionPost] Server confirmed: auction created")
        RequestOwnedAuctionsRefresh()
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        local errIdx = ...
        local name = errIdx and AH_ERROR_NAMES[errIdx] or "Unknown"
        ns:PrintDebug("[AuctionPost] Server error: " .. tostring(errIdx) ..
            " (" .. name .. ")")
    elseif event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" then
        local notification = ...
        ns:PrintDebug("[AuctionPost] Server notification: " .. tostring(notification))
    elseif event == "UI_ERROR_MESSAGE" then
        local errType, msg = ...
        if msg then
            ns:PrintDebug("[AuctionPost] UI error: [" .. tostring(errType) .. "] " .. tostring(msg))
        end
    elseif event == "ADDON_ACTION_BLOCKED" then
        local addonName, funcName = ...
        ns:PrintDebug("[AuctionPost] ACTION BLOCKED: addon=" .. tostring(addonName) ..
            " func=" .. tostring(funcName))
    end
end)

--------------------------
-- Minimal Post Test
--------------------------

-- /fq testpost — minimal direct call to PostItem/PostCommodity for the
-- first item in bag 0. Use this to diagnose whether the API works at all
-- from our addon, bypassing all scan/drawer logic.
function AuctionPost:TestPost()
    ns:Print("[TestPost] Starting minimal post test...")

    -- Find first postable item in bags
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, (numSlots or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isBound then
                local itemLoc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if C_Item.DoesItemExist(itemLoc) then
                    local itemID = C_Item.GetItemID(itemLoc)
                    local name = info.hyperlink:match("|h%[(.-)%]|h") or "?"
                    local isCommodity = C_AuctionHouse.GetItemCommodityStatus(itemID)
                        == Enum.ItemCommodityStatus.Commodity

                    -- Use TSM pattern: get price from DBMinBuyout
                    local price
                    if ns.TSM and ns.TSM.GetPrice then
                        price = ns.TSM:GetPrice(tostring(itemID) .. ";;", "DBMinBuyout")
                    end
                    if not price or price <= 0 then
                        price = 10000 -- 1g fallback for testing
                    end

                    -- Round to silver (AH silently rejects copper)
                    price = math.floor(price / 100) * 100
                    if price <= 0 then price = 100 end

                    ns:Print("[TestPost] Item: " .. name .. " bag=" .. bag ..
                        " slot=" .. slot .. " commodity=" .. tostring(isCommodity) ..
                        " price=" .. price)

                    if isCommodity then
                        ns:Print("[TestPost] Calling PostCommodity...")
                        C_AuctionHouse.PostCommodity(itemLoc, 1, info.stackCount or 1, price)
                    else
                        ns:Print("[TestPost] Calling PostItem (buy-it-now, bid=nil)...")
                        C_AuctionHouse.PostItem(itemLoc, 1, 1, nil, price)
                    end
                    ns:Print("[TestPost] Call returned. Watch for server events...")
                    return
                end
            end
        end
    end
    ns:Print("[TestPost] No postable items found in bags.")
end

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

    -- Primary: use the AH API
    if C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus then
        local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, numID)
        if ok and status == Enum.ItemCommodityStatus.Commodity then
            return true
        elseif ok and status == Enum.ItemCommodityStatus.Item then
            return false
        end
    end

    -- Fallback for Unknown status: check if item is stackable (max stack > 1)
    if C_Item and C_Item.GetItemMaxStackSizeByID then
        local ok2, maxStack = pcall(C_Item.GetItemMaxStackSizeByID, numID)
        if ok2 and maxStack and maxStack > 1 then
            return true
        end
    end

    return false
end

--------------------------
-- TSM Price Resolution
--------------------------

-- Price-source key validator for priceReset / aboveMax lookups.
-- TSM's MakePostDecision treats only these three as posting targets when the
-- operation setting names a price to fall back on. "none" / "ignore" mean
-- "don't post" / "ignore low auctions" and are handled separately.
local RESET_ABOVEMAX_KEYS = {
    minPrice    = true,
    maxPrice    = true,
    normalPrice = true,
}

-- Find our character's lowest buyout-per-unit for items matching baseItemID
-- among currently-live owned auctions. TSM's MakePostDecision calls this the
-- isPlayer branch: if we already own the lowest auction, match our own price
-- instead of undercutting ourselves into a cheaper bracket with every repost.
--
-- Returns nil when the AH isn't open, the owned-auctions query hasn't
-- resolved yet, or we have no matching auction on the AH.
local function GetOwnLowestBuyout(itemID)
    if not C_AuctionHouse or not C_AuctionHouse.GetOwnedAuctions then return nil end
    if not itemID then return nil end
    local ok, owned = pcall(C_AuctionHouse.GetOwnedAuctions)
    if not ok or not owned or #owned == 0 then return nil end

    local target = tostring(itemID)
    local lowest
    for _, auction in ipairs(owned) do
        if auction.itemKey and tostring(auction.itemKey.itemID) == target then
            local buyout = auction.buyoutAmount or 0
            local qty = auction.quantity or 1
            if buyout > 0 and qty > 0 then
                local unit = math.floor(buyout / qty)
                if unit > 0 and (not lowest or unit < lowest) then
                    lowest = unit
                end
            end
        end
    end
    return lowest
end

-- Resolve the actual posting buyout for an item, matching TSM's
-- AuctioningOperation.MakePostDecision logic (see TSM's
-- LibTSMSystem/Source/Operation/AuctioningOperation.lua:417).
--
-- Returns a pricing table or nil if no operation / no price sources are
-- available or the item is below the operation's threshold with no reset
-- configured.
--
-- The critical piece the old implementation was missing: TSM posts at an
-- UNDERCUT of the current market (not at the normalPrice baseline). Our
-- old code evaluated normalPrice and stopped there, which meant FlipQueue
-- was posting at ~2x average market — way above what players would post
-- via TSM's own Post Scan.
function AuctionPost:ResolvePostPrice(itemKey, itemID)
    if not ns.TSM or not ns.TSM:IsEnabled() then
        ns:PrintDebug("[AuctionPost] ResolvePostPrice: TSM not available")
        return nil
    end

    local op = ns.TSM:GetItemAuctioningOp(itemKey)

    -- Evaluate every price expression through TSM up front. These are copper
    -- values for this specific item/variant.
    local normalCopper = op and ns.TSM:EvaluateOpPrice(itemKey, op.normalPrice) or nil
    local minCopper    = op and ns.TSM:EvaluateOpPrice(itemKey, op.minPrice)    or nil
    local maxCopper    = op and ns.TSM:EvaluateOpPrice(itemKey, op.maxPrice)    or nil
    local undercut     = op and ns.TSM:EvaluateOpPrice(itemKey, op.undercut)    or 0
    -- Undercut may be 0 ("match") for players who prefer matching the market.
    undercut = undercut or 0

    -- Current lowest buyout on the AH (from TSM's last scan). This is the
    -- market reference the decision tree branches on. DBMinBuyout can lag
    -- reality between scans and doesn't tell us who owns the lowest listing
    -- — see ownLowestCopper below for the self-owned guard.
    local lowestCopper = ns.TSM:GetPrice(itemKey, "DBMinBuyout")

    -- Our own lowest live buyout for this item (if the AH is open and we
    -- have a matching active auction). TSM's MakePostDecision has an
    -- `isPlayer` branch: when the market's lowest auction is ours, TSM
    -- matches our own price instead of undercutting — otherwise every
    -- repost ratchets the price down further. Without this guard FlipQueue
    -- undercuts itself and TSM's cancel scan immediately flags the post as
    -- undercut or cancellable for repost.
    local ownLowestCopper = GetOwnLowestBuyout(itemID)

    -- Fallback chain when no auctioning operation OR normalPrice didn't
    -- evaluate. We'd rather post at *something* sensible than refuse.
    -- Prefer the current market (DBMinBuyout), then the player's configured
    -- tsmPriceSource, then market/regional fallbacks. minCopper falls back to
    -- the tsmMinPriceSource setting so below-threshold checks still fire.
    if not normalCopper then
        local priceSrc = ns.db and ns.db.settings.tsmPriceSource or "DBMinBuyout"
        local sources = {"DBMinBuyout", priceSrc, "DBMarket", "DBRegionMarketAvg"}
        local seen = {}
        for _, src in ipairs(sources) do
            if not seen[src] then
                seen[src] = true
                local val = ns.TSM:GetPrice(itemKey, src)
                if val and val > 0 then
                    normalCopper = val
                    ns:PrintDebug("[AuctionPost]   normalPrice fallback " .. src .. " = " .. tostring(val))
                    break
                end
            end
        end
    end
    if not minCopper then
        local minSrc = ns.db and ns.db.settings.tsmMinPriceSource
        if minSrc and minSrc ~= "" then
            minCopper = ns.TSM:GetPrice(itemKey, minSrc)
        end
    end

    if not normalCopper then
        ns:PrintDebug("[AuctionPost]   no price source available for " .. tostring(itemKey))
        return nil
    end

    local opName   = op and op.opName or "fallback"
    local postCap  = op and op.postCap
    local duration = op and op.duration

    -- Helper: resolve priceReset / aboveMax setting string to its copper value.
    local function ResolveReferencedPrice(settingKey)
        if not op or not op[settingKey] then return nil end
        local priceKeyName = op[settingKey]
        if not RESET_ABOVEMAX_KEYS[priceKeyName] then return nil end
        if priceKeyName == "minPrice"    then return minCopper    end
        if priceKeyName == "maxPrice"    then return maxCopper    end
        if priceKeyName == "normalPrice" then return normalCopper end
        return nil
    end

    -- MakePostDecision branch tree.
    local buyoutCopper
    local reason
    local belowThreshold = false
    local aboveMaxSkip = false

    if not lowestCopper or lowestCopper <= 0 then
        -- No competition on the AH — post at normalPrice (TSM's "empty market"
        -- branch). Still clamp against min/max below.
        buyoutCopper = normalCopper
        reason = "normal (no competition)"
    elseif ownLowestCopper and ownLowestCopper <= lowestCopper + 100 then
        -- We own the market's lowest listing (1s slack for silver rounding).
        -- Match our own price — do not self-undercut. This matches TSM's
        -- isPlayer branch: without it, every repost ratchets the ceiling
        -- down and TSM's cancel scan immediately flags the post as
        -- undercut / cancellable-for-repost-higher.
        buyoutCopper = ownLowestCopper
        reason = "match own (we're lowest)"
    else
        local proposed = lowestCopper - (undercut or 0)
        if minCopper and proposed < minCopper then
            -- Undercut would put us below our configured floor. Apply the
            -- operation's priceReset setting.
            local resetValue = ResolveReferencedPrice("priceReset")
            if resetValue then
                buyoutCopper = resetValue
                reason = "reset (lowest below min)"
            else
                -- priceReset is "none" or "ignore" — TSM refuses to post.
                belowThreshold = true
                reason = "below min (no reset configured)"
            end
        elseif maxCopper and proposed > maxCopper then
            -- Undercut would leave us above our configured ceiling. Apply
            -- the aboveMax setting.
            local aboveMaxValue = ResolveReferencedPrice("aboveMax")
            if aboveMaxValue then
                buyoutCopper = aboveMaxValue
                reason = "aboveMax"
            else
                -- aboveMax is "none" — TSM refuses to post.
                aboveMaxSkip = true
                reason = "above max (no fallback configured)"
            end
        else
            -- Normal case: undercut the current lowest auction.
            buyoutCopper = proposed
            reason = "undercut (lowest - undercut)"
        end
    end

    -- Clamp buyout >= minPrice if we have one and we're actually posting.
    if buyoutCopper and minCopper and buyoutCopper < minCopper then
        buyoutCopper = minCopper
    end

    ns:PrintDebug(("[AuctionPost] ResolvePostPrice: %s op=%s lowest=%s own=%s normal=%s min=%s max=%s uc=%s -> buyout=%s (%s)"):format(
        tostring(itemKey), tostring(opName),
        tostring(lowestCopper), tostring(ownLowestCopper),
        tostring(normalCopper),
        tostring(minCopper), tostring(maxCopper),
        tostring(undercut), tostring(buyoutCopper), tostring(reason)))

    return {
        -- The price we will actually post at. Consumers use this instead of
        -- normalCopper; normalCopper is kept for UI display of "baseline".
        buyoutCopper      = buyoutCopper,
        normalCopper      = normalCopper,
        minCopper         = minCopper,
        maxCopper         = maxCopper,
        lowestCopper      = lowestCopper,
        ownLowestCopper   = ownLowestCopper,
        undercutCopper    = undercut,
        postCap           = postCap,
        duration          = duration,
        opName            = opName,
        reason            = reason,
        belowThreshold    = belowThreshold,
        aboveMaxSkip      = aboveMaxSkip,
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
                        -- Skip soulbound items (can't be posted)
                        if info.isBound then
                            -- silently skip
                        -- Skip Do Not Track items
                        elseif ns:IsDoNotTrack(itemID) then
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

                                -- "ready" means we have a valid post price.
                                -- "below_threshold" / "above_max" / "no_price" mean TSM's
                                -- operation refuses to post this item right now.
                                local status = "ready"
                                if not pricing then
                                    status = "no_price"
                                elseif pricing.belowThreshold then
                                    status = "below_threshold"
                                elseif pricing.aboveMaxSkip then
                                    status = "above_max"
                                elseif not pricing.buyoutCopper then
                                    status = "no_price"
                                end

                                -- Determine post quantity. TSM's postCap is the number of
                                -- auctions per scan cycle (non-commodity) or total items
                                -- to list (commodity). pricing.postCap is pre-evaluated
                                -- to a number in TSM:GetItemAuctioningOp. When we have
                                -- a TSM op but the postCap evaluation failed, fall back
                                -- to 1 — safer to post too few than too many, since each
                                -- post incurs an AH deposit fee the player pays back.
                                local postQty = info.stackCount or 1
                                local cap = pricing and tonumber(pricing.postCap)
                                if cap and cap > 0 then
                                    postQty = math.min(info.stackCount or 1, cap)
                                elseif pricing then
                                    postQty = math.min(info.stackCount or 1, 1)
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
                                local entryCap = entry.pricing and tonumber(entry.pricing.postCap)
                                if entryCap and entryCap > 0 then
                                    entry.postQty = math.min(entry.totalCount, entryCap)
                                elseif entry.pricing then
                                    -- Have a TSM op but postCap didn't evaluate — be
                                    -- conservative, don't default to "post everything".
                                    entry.postQty = math.min(entry.totalCount, 1)
                                else
                                    -- No TSM op at all — fall through to full stack.
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

    -- Prefer the computed post buyout (TSM decision tree) over the baseline
    -- normalPrice. Fall back to normalPrice only for old callers that haven't
    -- been re-scanned since this field was added.
    local postPrice = scanResult.pricing and (scanResult.pricing.buyoutCopper or scanResult.pricing.normalCopper) or nil
    if not postPrice or postPrice <= 0 then
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

    local unitPrice = postPrice
    local quantity = scanResult.postQty or 1
    local duration = tonumber(scanResult.pricing.duration) or 3
    local isCommodity = scanResult.isCommodity

    ns:PrintDebug("[AuctionPost] PostItem: " .. (scanResult.name or "?") ..
        " qty=" .. quantity .. " price=" .. unitPrice ..
        " dur=" .. duration .. " commodity=" .. tostring(isCommodity) ..
        " bag=" .. slotInfo.bag .. " slot=" .. slotInfo.slot ..
        " reason=" .. tostring(scanResult.pricing.reason))

    -- WoW AH silently rejects prices with non-zero copper — round to silver.
    local COPPER_PER_SILVER = 100
    unitPrice = math.floor(unitPrice / COPPER_PER_SILVER) * COPPER_PER_SILVER

    -- Commodities use PostCommodity (unitPrice + stack quantity).
    -- Non-commodities use PostItem with bid=nil for buy-it-now only. Blizzard's
    -- validator requires buyout > bid strictly when both are set, and the
    -- server rejects bid==buyout with AuctionHouseError.ItemNotFound.
    --
    -- quantity semantics differ between the two APIs:
    --   PostCommodity(itemLoc, duration, quantity, unitPrice) — quantity is
    --     the total number of units to list at unitPrice (fungible pool).
    --   PostItem(itemLoc, duration, quantity, bid, buyout) — quantity is the
    --     number of SEPARATE AUCTIONS to create; Blizzard finds `quantity`
    --     matching items in bags and posts each as its own auction.
    --
    -- Both honor postCap via scanResult.postQty (pre-capped during scan).
    local loggedQuantity = quantity
    if isCommodity then
        ns:PrintDebug("[AuctionPost] calling PostCommodity: dur=" .. duration ..
            " qty=" .. quantity .. " unitPrice=" .. unitPrice)
        C_AuctionHouse.PostCommodity(itemLoc, duration, quantity, unitPrice)
    else
        ns:PrintDebug("[AuctionPost] calling PostItem: dur=" .. duration ..
            " qty=" .. quantity .. " bid=nil buyout=" .. unitPrice)
        C_AuctionHouse.PostItem(itemLoc, duration, quantity, nil, unitPrice)
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
            postedPrice    = ns:FormatGold(unitPrice * loggedQuantity),
            postedAt       = now,
            charKey        = charKey,
            expiresAt      = expiresAt,
            auctionStatus  = "active",
            soldAt         = nil,
            soldPrice      = nil,
            postedQuantity = loggedQuantity,
        })

        ns:PrintDebug("Posted " .. (scanResult.name or "?") .. " x" .. loggedQuantity
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

-- Post the next ready item from a scan result set. Must be called from
-- a hardware event (button click) because C_AuctionHouse.PostItem is
-- protected. Returns true if an item was posted, false if none remain.
-- The caller should re-invoke on the next button click.
function AuctionPost:PostNext(scanResults, onPosted)
    if not scanResults then return false end

    -- Find the first ready item
    for i, item in ipairs(scanResults) do
        if item.status == "ready" then
            self:PostItem(item, function(success, errMsg)
                if success then
                    item.status = "posted"
                end
                if onPosted then onPosted(success, item, errMsg) end
            end)
            return true
        end
    end
    return false
end

-- Count remaining ready items in a scan result set.
function AuctionPost:CountReady(scanResults)
    if not scanResults then return 0 end
    local count = 0
    for _, item in ipairs(scanResults) do
        if item.status == "ready" then count = count + 1 end
    end
    return count
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

    -- Force a re-query so TSM, Auctionator, and our own drawer see the
    -- cancelled auction disappear. Blizzard fires AUCTION_CANCELED for us
    -- but doesn't always push a fresh OWNED_AUCTIONS_UPDATED — the requery
    -- guarantees it.
    RequestOwnedAuctionsRefresh()

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
