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

-- Debounced owned-auctions requery. After a successful post or cancel
-- *initiated by FlipQueue's own post/cancel flow* we re-query the server
-- so the OWNED_AUCTIONS_UPDATED event fires and FQ's view of owned
-- auctions stays current. The requery is gated by `_fqInitiatedAction`
-- (set right before our C_AuctionHouse.PostItem/PostCommodity/CancelAuction
-- calls and cleared by the matching server event) — without that gate
-- this fired for every AUCTION_HOUSE_AUCTION_CREATED event regardless of
-- which addon initiated the post, which competed with TSM's own posting
-- loop and made TSM occasionally skip queue items (FQ-138).
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

-- True between MarkFQInitiated() and the matching server event (or the
-- safety timeout). The post-result frame consults this to decide whether
-- to fire RequestOwnedAuctionsRefresh — TSM-initiated posts/cancels see
-- AUCTION_HOUSE_AUCTION_CREATED too, but the flag stays false for those
-- so we don't compete with TSM's own state machine.
local _fqInitiatedAction = false
local _fqInitiatedClearTimer = nil
local function ClearFQInitiated()
    _fqInitiatedAction = false
    if _fqInitiatedClearTimer then
        _fqInitiatedClearTimer:Cancel()
        _fqInitiatedClearTimer = nil
    end
end
local function MarkFQInitiated()
    _fqInitiatedAction = true
    if _fqInitiatedClearTimer then _fqInitiatedClearTimer:Cancel() end
    -- Safety: if the post fails silently (no AUCTION_HOUSE_AUCTION_CREATED,
    -- no AUCTION_HOUSE_SHOW_ERROR), the flag would stick and the next
    -- TSM-initiated event would incorrectly fire our requery. 3s is well
    -- past the longest legitimate post round-trip.
    _fqInitiatedClearTimer = C_Timer.NewTimer(3.0, ClearFQInitiated)
end
AuctionPost._MarkFQInitiated = MarkFQInitiated  -- for CancelAuction reuse

-- Listen for server responses to PostItem/PostCommodity to verify success.
local postResultFrame = CreateFrame("Frame")
postResultFrame:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
postResultFrame:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
postResultFrame:RegisterEvent("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION")
postResultFrame:RegisterEvent("UI_ERROR_MESSAGE")
postResultFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
postResultFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "AUCTION_HOUSE_AUCTION_CREATED" then
        ns:PrintDebug("[AuctionPost] Server confirmed: auction created (fqInitiated="
            .. tostring(_fqInitiatedAction) .. ")")
        if _fqInitiatedAction then
            ClearFQInitiated()
            RequestOwnedAuctionsRefresh()
        end
        -- TSM-initiated posts: do nothing. TSM has its own OWNED_AUCTIONS_UPDATED
        -- consumer; our forced requery used to compete with TSM's queue and
        -- caused it to occasionally skip items (FQ-138).
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        local errIdx = ...
        local name = errIdx and AH_ERROR_NAMES[errIdx] or "Unknown"
        ns:PrintDebug("[AuctionPost] Server error: " .. tostring(errIdx) ..
            " (" .. name .. ")")
        if _fqInitiatedAction then ClearFQInitiated() end
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

-- Price-source key validator for priceReset / aboveMax lookups. TSM's
-- MakePostDecision treats only these three as posting targets when the
-- operation setting names a price to fall back on. "none" / "ignore" mean
-- "don't post" / "ignore low auctions" and are handled separately.
local RESET_ABOVEMAX_KEYS = {
    minPrice    = true,
    maxPrice    = true,
    normalPrice = true,
}

-- Approx. seconds-from-listing-end represented by each timeLeft enum bucket
-- the AH API returns. The retail API exposes timeLeftSeconds directly; the
-- fallback table lets us reason about ignoreLowDuration when only the
-- enum is available. Numbers chosen to err on the include side.
local TIMELEFT_SECONDS = {
    [0] = 30 * 60,
    [1] = 2  * 60 * 60,
    [2] = 12 * 60 * 60,
    [3] = 48 * 60 * 60,
}

-- Compact age string for tooltip / debug labels: 12s, 4m, 2h, 3d.
local function FormatShortAge(sec)
    sec = tonumber(sec) or 0
    if sec < 60 then return sec .. "s" end
    if sec < 3600 then return math.floor(sec / 60) .. "m" end
    if sec < 86400 then return math.floor(sec / 3600) .. "h" end
    return math.floor(sec / 86400) .. "d"
end

-- TSM AuctioningOperation.IsAuctionFiltered (LibTSMSystem v4.14.66:269-285).
-- Drops a listing before it can be considered the lowest competitor.
local function IsAuctionFiltered(op, listing, opCtx)
    if not op then return false end
    if op.ignoreLowDuration and op.ignoreLowDuration > 0 then
        local secs = listing.timeLeftSec
        if not secs then secs = TIMELEFT_SECONDS[3] end  -- assume long if unknown
        if secs <= op.ignoreLowDuration then return true end
    end
    if op.matchStackSize and opCtx.opStackSize and listing.quantity ~= opCtx.opStackSize then
        return true
    end
    if op.priceReset == "ignore" and opCtx.minCopper and opCtx.undercutCopper then
        if (listing.buyout - opCtx.undercutCopper) < opCtx.minCopper then
            return true
        end
    end
    return false
end

-- TSM Util.GetLowestAuction retail path (Core/Service/Auctioning/Util.lua:30).
-- Walks the cached listings (already buyout-ascending), filters via
-- IsAuctionFiltered, returns the first survivor's data plus seller flags.
local function GetLowestFromListings(listings, op, opCtx)
    if not listings or #listings == 0 then return nil end

    local whitelist = ns.TSM and ns.TSM.GetWhitelist and ns.TSM:GetWhitelist() or nil

    for _, listing in ipairs(listings) do
        if not IsAuctionFiltered(op, listing, opCtx) then
            local seller = listing.seller or ""
            local sellerLower = seller:lower()
            local isWhitelist = false
            if whitelist and seller ~= "" then
                isWhitelist = whitelist[sellerLower] == true
            end
            local isBlacklist = false
            if op and op.blacklist and seller ~= "" then
                isBlacklist = ns.TSM:IsBlacklisted(op, seller)
            end
            return {
                buyout           = listing.buyout,
                quantity         = listing.quantity,
                seller           = seller,
                isPlayer         = listing.isPlayer == true,
                isWhitelist      = isWhitelist,
                isBlacklist      = isBlacklist,
                hasInvalidSeller = (not listing.isPlayer) and (not listing.hasOwner)
                                    and whitelist and next(whitelist) ~= nil,
            }
        end
    end
    return nil
end

-- AuctioningOperation.MakePostDecision (LibTSMSystem v4.14.66:417-506) port.
-- Returns: { reason, buyoutCopper, seller, belowThreshold, aboveMaxSkip,
--            invalidReason, skipWhitelist }
local function MakePostDecision(itemKey, lowest, ctx)
    local normalCopper = ctx.normalCopper
    local minCopper    = ctx.minCopper
    local maxCopper    = ctx.maxCopper
    local undercut     = ctx.undercutCopper or 0
    local op           = ctx.op
    local matchWhitelist = ctx.matchWhitelist

    local result = { seller = lowest and lowest.seller or nil }

    if not lowest then
        result.reason       = "normal (no competition)"
        result.buyoutCopper = normalCopper
    elseif lowest.hasInvalidSeller then
        result.invalidReason = "invalid_seller"
        return result
    elseif lowest.isBlacklist and lowest.isPlayer then
        result.invalidReason = "alt_blacklisted"
        return result
    elseif lowest.isBlacklist and lowest.isWhitelist then
        result.invalidReason = "blacklist_whitelist_conflict"
        return result
    elseif minCopper and (lowest.buyout - undercut) < minCopper then
        local resetKey = op and op.priceReset
        if resetKey and RESET_ABOVEMAX_KEYS[resetKey] then
            local resetValue
            if resetKey == "minPrice"    then resetValue = minCopper end
            if resetKey == "maxPrice"    then resetValue = maxCopper end
            if resetKey == "normalPrice" then resetValue = normalCopper end
            if resetValue then
                result.buyoutCopper = resetValue
                result.reason = "reset_" .. resetKey .. " (lowest below min)"
            else
                result.belowThreshold = true
                result.reason = "below min (reset price unavailable)"
            end
        elseif lowest.isBlacklist then
            result.buyoutCopper = lowest.buyout - undercut
            result.reason = "undercut blacklist"
        else
            result.belowThreshold = true
            result.reason = "below min (no reset configured)"
        end
    elseif lowest.isPlayer or (lowest.isWhitelist and matchWhitelist) then
        result.buyoutCopper = lowest.buyout
        result.reason = lowest.isPlayer and "match own (we're lowest)" or "match whitelist"
    elseif lowest.isWhitelist then
        result.skipWhitelist = true
        result.reason = "skip whitelist (no match-whitelist)"
    elseif maxCopper and (lowest.buyout - undercut) > maxCopper then
        local aboveMaxKey = op and op.aboveMax
        if aboveMaxKey and RESET_ABOVEMAX_KEYS[aboveMaxKey] then
            local aboveMaxValue
            if aboveMaxKey == "minPrice"    then aboveMaxValue = minCopper end
            if aboveMaxKey == "maxPrice"    then aboveMaxValue = maxCopper end
            if aboveMaxKey == "normalPrice" then aboveMaxValue = normalCopper end
            if aboveMaxValue then
                result.buyoutCopper = aboveMaxValue
                result.reason = "aboveMax_" .. aboveMaxKey
            else
                result.aboveMaxSkip = true
                result.reason = "above max (fallback unavailable)"
            end
        else
            result.aboveMaxSkip = true
            result.reason = "above max (no fallback configured)"
        end
    else
        result.buyoutCopper = lowest.buyout - undercut
        result.reason = "undercut"
    end

    -- TSM's final clamp: buyout = max(buyout, minPrice). Bypassed on the
    -- blacklist undercut branch, matching TSM's reason-gated clamp.
    if result.buyoutCopper and minCopper and result.buyoutCopper < minCopper
        and result.reason ~= "undercut blacklist" then
        result.buyoutCopper = minCopper
    end

    return result
end

-- Read TSM's global "match whitelist" toggle. Defaults true in v4.14.66.
local function ReadMatchWhitelist()
    if type(TradeSkillMasterDB) ~= "table" then return true end
    local v = TradeSkillMasterDB["g@ @auctioningOptions@matchWhitelist"]
    if v == nil then return true end
    return v ~= false
end

-- Resolve the actual posting buyout for an item by mirroring TSM v4.14.66's
-- AuctioningOperation.MakePostDecision (LibTSMSystem/Source/Operation/
-- AuctioningOperation.lua:417). Decision data:
--   - normal/min/max prices via TSM's AuctioningOpNormal/Min/Max sources
--     (TSM resolves the assigned op AND evaluates the expression in one
--     call — no drift if the player changes ops or groups).
--   - lowest competitor from AuctionScanCache, filtered through TSM's
--     IsAuctionFiltered (timeLeft / matchStackSize / threshold-ignore).
--   - blacklist from op settings, whitelist from TSM's factionrealm-scoped
--     global setting, matchWhitelist from TSM's global toggle.
-- Returns a pricing table or nil when no operation / price source resolves.
function AuctionPost:ResolvePostPrice(itemKey, itemID, itemLink, isCommodity)
    if not ns.TSM or not ns.TSM:IsEnabled() then
        ns:PrintDebug("[AuctionPost] ResolvePostPrice: TSM not available")
        return nil
    end

    local op = ns.TSM:GetItemAuctioningOp(itemKey)

    -- Two TSM item-string forms, used for different query paths:
    --
    -- 1. Level form ("i:<id>::i<ilvl>"): TSM's AuctionDB sources
    --    (DBMinBuyout, DBRegionMarketAvg, dbmarket) internally key on
    --    this via ItemString.ToLevel. Querying with bonus-ID canonical
    --    misses by ~10% on items with ilvl variants (FQ-003 fix).
    --
    -- 2. Canonical / TSM string ("i:<id>:<bonusIDsFiltered>"): TSM's
    --    AuctioningOp* sources go through the group→operation lookup
    --    which is keyed on the canonical form. Querying these with
    --    level form returns wrong values for some items — for designs/
    --    recipes (no real ilvl variance) we've seen `AuctioningOpMin`
    --    return ~half the canonical value, which silently flipped our
    --    decision tree from "below min, skip" to "undercut, post".
    --
    -- So: use canonical for AuctioningOp* (these resolve the player's
    -- own op settings), level form for raw DB price sources.
    local levelStr = ns.TSM:ItemKeyToLevelString(itemKey, itemLink)
    local tsmStr   = ns.TSM:ItemKeyToTSMString(itemKey)
    -- Defense-in-depth: the outer `ns.TSM:IsEnabled()` gate at the top of
    -- ResolvePostPrice catches the "TSM never loaded" case, but if TSM is
    -- present at function entry and disappears before these closures fire
    -- (or if `IsEnabled` returns a stale-true snapshot), the
    -- `TSM_API.GetCustomPriceValue` index would throw before pcall catches
    -- anything. TSM is OptionalDeps and must never be a hard dep at runtime.
    local function EvalLevel(source)
        if not TSM_API or not levelStr or not source or source == "" then return nil end
        local ok, v = pcall(TSM_API.GetCustomPriceValue, source, levelStr)
        return ok and v or nil
    end
    local function EvalCanonical(source)
        if not TSM_API or not tsmStr or not source or source == "" then return nil end
        local ok, v = pcall(TSM_API.GetCustomPriceValue, source, tsmStr)
        return ok and v or nil
    end

    local normalCopper = EvalCanonical("AuctioningOpNormal")
    local minCopper    = EvalCanonical("AuctioningOpMin")
    local maxCopper    = EvalCanonical("AuctioningOpMax")
    if op then
        if not normalCopper and op.normalPrice then
            normalCopper = EvalCanonical(op.normalPrice)
        end
        if not minCopper and op.minPrice then
            minCopper = EvalCanonical(op.minPrice)
        end
        if not maxCopper and op.maxPrice then
            maxCopper = EvalCanonical(op.maxPrice)
        end
    end
    local undercut = op and op.undercut and EvalCanonical(op.undercut) or 0
    undercut = undercut or 0

    -- Live AH state. Freshness ceiling enforced by Lookup — anything older
    -- than DefaultFreshAge is treated as missing so AuctionAutoScan can
    -- refresh it. Stale data is read separately for UI display purposes.
    local cache = ns.AuctionScanCache
    local freshAge = cache and cache:DefaultFreshAge() or 1800
    local liveLookup = cache and cache:Lookup(itemKey, isCommodity, freshAge) or nil

    -- Display-only fallback for normal price when the op didn't evaluate
    -- (item ungrouped). Keeps the row from disappearing entirely; the
    -- decision tree still skips because no op = no postable decision.
    if not normalCopper then
        local priceSrc = ns.db and ns.db.settings.tsmPriceSource or "DBMarket"
        local sources = { priceSrc, "DBMarket", "DBRegionMarketAvg" }
        local seen = {}
        for _, src in ipairs(sources) do
            if src and not seen[src] then
                seen[src] = true
                local val = ns.TSM:GetPrice(itemKey, src)
                if val and val > 0 then normalCopper = val; break end
            end
        end
    end

    if not normalCopper then
        ns:PrintDebug("[AuctionPost]   no price source available for " .. tostring(itemKey))
        return nil
    end

    local opName   = op and op.opName or "fallback"
    local postCap  = op and op.postCap
    local duration = op and op.duration

    -- IsAuctionFiltered context. opStackSize is needed for matchStackSize
    -- filtering; TSM allows expressions there but most ops use literals.
    local opStackSize
    if op and op.stackSize then
        opStackSize = tonumber(op.stackSize)
        if not opStackSize then
            opStackSize = ns.TSM:EvaluateOpPrice(itemKey, op.stackSize)
        end
    end
    local opCtx = {
        opStackSize    = opStackSize,
        minCopper      = minCopper,
        undercutCopper = undercut,
    }

    local lowest
    if liveLookup and liveLookup.listings then
        lowest = GetLowestFromListings(liveLookup.listings, op, opCtx)
    end

    local matchWhitelist = ReadMatchWhitelist()
    local decision = MakePostDecision(itemKey, lowest, {
        normalCopper   = normalCopper,
        minCopper      = minCopper,
        maxCopper      = maxCopper,
        undercutCopper = undercut,
        op             = op,
        matchWhitelist = matchWhitelist,
    })

    -- Surface own-lowest separately for the tooltip even when the decision
    -- tree picked a different competitor. Helps the player see when they're
    -- already the floor.
    local ownLowestCopper
    if liveLookup and liveLookup.listings then
        for _, l in ipairs(liveLookup.listings) do
            if l.isPlayer then ownLowestCopper = l.buyout; break end
        end
    end

    -- Provenance for the AH-lowest number. live = fresh harvest; stale =
    -- have a cache entry but it's older than the freshness ceiling; none =
    -- never scanned this item on this realm.
    local lowestCopper      = lowest and lowest.buyout or (liveLookup and liveLookup.lowestUnit) or nil
    local lowestSourceKey, lowestSourceLabel, lowestAgeSec
    if liveLookup then
        lowestSourceKey   = "live"
        lowestSourceLabel = "live " .. (liveLookup.source or "scan")
        lowestAgeSec      = liveLookup.age
    elseif cache then
        local stale = cache:Lookup(itemKey, isCommodity)
        if stale then
            lowestSourceKey   = "stale"
            lowestSourceLabel = "stale (" .. FormatShortAge(stale.age) .. ")"
            lowestAgeSec      = stale.age
            lowestCopper      = stale.lowestUnit
        else
            lowestSourceKey   = "none"
            lowestSourceLabel = "no scan yet"
        end
    end

    ns:PrintDebug(("[AuctionPost] ResolvePostPrice: %s op=%s lowest=%s(%s) own=%s normal=%s min=%s max=%s uc=%s -> buyout=%s (%s)"):format(
        tostring(itemKey), tostring(opName),
        tostring(lowestCopper), tostring(lowestSourceLabel or "?"),
        tostring(ownLowestCopper),
        tostring(normalCopper), tostring(minCopper), tostring(maxCopper),
        tostring(undercut),
        tostring(decision.buyoutCopper), tostring(decision.reason)))

    return {
        buyoutCopper      = decision.buyoutCopper,
        normalCopper      = normalCopper,
        minCopper         = minCopper,
        maxCopper         = maxCopper,
        lowestCopper      = lowestCopper,
        ownLowestCopper   = ownLowestCopper,
        undercutCopper    = undercut,
        postCap           = postCap,
        duration          = duration,
        opName            = opName,
        reason            = decision.reason,
        seller            = decision.seller,
        invalidReason     = decision.invalidReason,
        belowThreshold    = decision.belowThreshold == true,
        aboveMaxSkip      = decision.aboveMaxSkip == true,
        skipWhitelist     = decision.skipWhitelist == true,
        lowestSourceKey   = lowestSourceKey,
        lowestSourceLabel = lowestSourceLabel,
        lowestAgeSec      = lowestAgeSec,
        liveIsPlayer      = lowest and lowest.isPlayer or false,
    }
end

-- Re-resolve pricing for an existing scan-results list without rewalking
-- bags. Called from the scan-cache update listener so rows reflect a fresh
-- TSM Post Scan / Cancel Scan within a couple of seconds. Updates each
-- entry's `pricing`, `status`, and `postQty` in place.
function AuctionPost:RerunPricing(scanResults)
    if not scanResults then return end
    for _, entry in ipairs(scanResults) do
        if entry.itemKey and entry.itemID and entry.status ~= "dnt" then
            local pricing = self:ResolvePostPrice(entry.itemKey, entry.itemID, entry.itemLink, entry.isCommodity)
            entry.pricing = pricing
            local status = "ready"
            if not pricing then
                status = "no_price"
            elseif pricing.invalidReason then
                status = "invalid"
            elseif pricing.belowThreshold then
                status = "below_threshold"
            elseif pricing.aboveMaxSkip then
                status = "above_max"
            elseif pricing.skipWhitelist then
                status = "skip_whitelist"
            elseif pricing.lowestSourceKey == "none"
                or pricing.lowestSourceKey == "stale" then
                status = "scan_pending"
            elseif not pricing.buyoutCopper then
                status = "no_price"
            end
            entry.status = status
            local cap = pricing and tonumber(pricing.postCap)
            if cap and cap > 0 then
                entry.postQty = math.min(entry.totalCount or 1, cap)
            elseif pricing then
                entry.postQty = math.min(entry.totalCount or 1, 1)
            else
                entry.postQty = 0
            end
        end
    end
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
                                local isCommodity = self:IsCommodity(itemID)
                                local pricing = self:ResolvePostPrice(key, itemID, info.hyperlink, isCommodity)

                                -- "ready" means we have a valid post price.
                                -- "below_threshold" / "above_max" / "no_price" mean TSM's
                                -- operation refuses to post this item right now.
                                local status = "ready"
                                if not pricing then
                                    status = "no_price"
                                elseif pricing.invalidReason then
                                    status = "invalid"
                                elseif pricing.belowThreshold then
                                    status = "below_threshold"
                                elseif pricing.aboveMaxSkip then
                                    status = "above_max"
                                elseif pricing.skipWhitelist then
                                    status = "skip_whitelist"
                                elseif pricing.lowestSourceKey == "none"
                                    or pricing.lowestSourceKey == "stale" then
                                    status = "scan_pending"
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
                                    itemLink    = info.hyperlink,
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

    -- Player has opted out of FlipQueue's posting flow (using TSM or
    -- another addon to post). Refuse to post even if the row's button
    -- somehow stayed enabled.
    if ns.db and ns.db.settings and ns.db.settings.ahPostingEnabled == false then
        cb(false, "FlipQueue posting is disabled (Settings > Auction House)")
        return
    end

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
    -- Mark this post as FQ-initiated so the post-result frame's listener
    -- knows to fire its owned-auctions requery for OUR post and not for
    -- TSM-initiated posts that happen to land in the same event stream
    -- (FQ-138). The flag self-clears via the 3s safety timer if neither
    -- AUCTION_HOUSE_AUCTION_CREATED nor AUCTION_HOUSE_SHOW_ERROR arrives.
    MarkFQInitiated()
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
                        -- Pass scanResult.itemKey so MoveTaskToLog preserves
                        -- bonus IDs / modifiers from the bag item even when
                        -- the task itself was imported with stripped key
                        -- (FQ-130).
                        ns.TodoList:MoveTaskToLog(taskIdx, ns:FormatGold(unitPrice), durationHours * 3600, quantity, scanResult.itemKey)
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
