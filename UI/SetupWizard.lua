-- UI/SetupWizard.lua
-- First-run setup wizard: walks new users through settings step by step
local addonName, ns = ...

local UI = ns.UI

--------------------------
-- Recommended Defaults
--------------------------

local RECOMMENDED = {
    autoScan            = true,
    autoWithdrawGold    = true,
    autoDepositGold     = false,
    maxWithdrawGold     = 500,
    goldBuffer          = 50,
    autoPullBank        = true,
    autoDepositWarbank  = true,
    autoDepositAll      = false,
    showLoginMessage    = true,
    showMini            = true,
    hideMiniInCombat    = true,
    pullBatchSize       = 5,
    defaultSellQty      = 1,
    sellQtyMode         = "tsm",
    skipUnassigned      = false,
    expiryAlertMinutes  = 15,
}

-- Applied only when TSM is detected
local RECOMMENDED_TSM = {
    tsmEnabled          = true,
    tsmShowColumns      = true,
    tsmAutoUpdatePrice  = true,
    tsmMinPriceSource   = "70% DBRegionMarketAvg",
    tsmPriceSource      = "70% DBRegionMarketAvg",
    tsmSkipOnGenerate   = true,
    tsmAutoSkipRejected = true,
    dfPriceSource       = "deal",
}

--------------------------
-- Addon Detection
--------------------------

local function HasTSM()
    return ns.TSM and ns.TSM:IsAvailable()
end

local function HasAuctionator()
    return type(Auctionator) == "table"
end

--------------------------
-- Apply Defaults
--------------------------

local function ApplyDefaults()
    if not ns.db then return end
    for k, v in pairs(RECOMMENDED) do
        ns.db.settings[k] = v
    end
    if HasTSM() then
        for k, v in pairs(RECOMMENDED_TSM) do
            ns.db.settings[k] = v
        end
    else
        -- Without TSM, force fixed quantity mode
        ns.db.settings.sellQtyMode = "fixed"
    end
end

--------------------------
-- Welcome Summary Builder
--------------------------

-- Each section: { icon (WoW atlas or texture path), title, text }
local function GetDefaultsSections()
    local sections = {}
    local H = ns.COLORS.YELLOW  -- highlight color for setting values
    local R = "|r"

    table.insert(sections, {
        icon  = "Interface\\Icons\\INV_Misc_Coin_01",
        title = "Gold",
        text  = "FlipQueue will " .. H .. "withdraw gold" .. R .. " from the warband bank " ..
                "for auction fees, up to " .. H .. "500g" .. R .. " per visit (with a " ..
                H .. "50g" .. R .. " buffer for repairs and reagents). " ..
                "Auto-deposit of earnings is " .. H .. "off" .. R .. " — you can enable " ..
                "it if you want profits sent back to the warbank automatically.",
    })

    table.insert(sections, {
        icon  = "Interface\\Icons\\INV_Misc_Bag_07",
        title = "Bank",
        text  = "It will " .. H .. "automatically pull" .. R .. " items for you when you " ..
                "open your bank, and will " .. H .. "deposit items other characters need" .. R ..
                ", but it will " .. H .. "leave the rest of your inventory alone" .. R .. ".",
    })

    if HasTSM() then
        table.insert(sections, {
            icon  = "Interface\\Icons\\INV_Misc_Note_01",
            title = "Posting",
            text  = "Because we have detected TSM, it will use the " .. H ..
                    "auction rules of your current group" .. R .. " to decide how many " ..
                    "of each item to post.",
        })
        table.insert(sections, {
            icon  = "Interface\\Icons\\INV_Misc_Spyglass_03",
            title = "TSM & Pricing",
            text  = "TSM integration is " .. H .. "enabled" .. R .. " and will show its " ..
                    "latest prices and update your imports with new pricing data. When you " ..
                    "generate new lists, if something isn't priced high enough in TSM, it " ..
                    "will " .. H .. "skip the to-do" .. R .. ", and if TSM rejects posting " ..
                    "on the AH, it will " .. H .. "skip the task automatically" .. R ..
                    ". The default price display uses the " .. H .. "imported deal price" ..
                    R .. ", but you can switch to a " .. H .. "blended price" .. R ..
                    " (which factors in your sales history) or raw TSM sources. For items " ..
                    "not in a TSM group, the fallback minimum price will be " ..
                    H .. "70% of DBRegionMarketAvg" .. R .. ".",
        })
    else
        table.insert(sections, {
            icon  = "Interface\\Icons\\INV_Misc_Note_01",
            title = "Posting",
            text  = "By default you will post " .. H .. "1" .. R .. " of each item on a server.",
        })
    end

    table.insert(sections, {
        icon  = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        title = "Display",
        text  = "When you login, a " .. H .. "text summary" .. R .. " will be displayed " ..
                "in chat, and the " .. H .. "mini window" .. R .. " will be shown. You " ..
                "will be alerted that auctions are due to expire in " ..
                H .. "15 minutes" .. R .. ".",
    })

    return sections
end

--------------------------
-- Dynamic Step Builder
--------------------------

local activeSteps  -- built per ShowSetupWizard call

local function BuildSteps()
    local steps = {}

    -- Step 1: Welcome
    table.insert(steps, {
        title = "Welcome to FlipQueue",
        welcome = true,
    })

    -- Step 2: Gold Management
    table.insert(steps, {
        title = "Gold Management",
        desc  = "FlipQueue can handle gold automatically when you visit a banker.\n\n" ..
                "Your sell characters need gold to pay AH listing fees. These settings " ..
                "move gold between the warband bank and your characters so you don't " ..
                "have to do it manually.",
        settings = {
            {
                type = "checkbox", key = "autoWithdrawGold",
                label = "Auto-withdraw gold for AH fees",
                desc  = "When you open the bank, FlipQueue calculates the estimated AH deposit fees " ..
                        "for all your pending tasks and withdraws enough gold from the warband bank " ..
                        "to cover them. Includes costs for buy tasks too.",
            },
            {
                type = "checkbox", key = "autoDepositGold",
                label = "Auto-deposit earnings back to warbank",
                desc  = "After posting, deposits any excess gold back to the warband bank " ..
                        "so it's available for your other characters. Keeps enough for fees " ..
                        "plus your configured buffer.",
            },
            {
                type = "input", key = "maxWithdrawGold",
                label = "Max withdrawal per visit",
                desc  = "Safety cap so a miscalculation doesn't drain your warbank. " ..
                        "Set to 0 for no limit.",
                suffix = "gold",
            },
            {
                type = "input", key = "goldBuffer",
                label = "Extra gold to keep on character",
                desc  = "Gold to keep beyond AH fees. Covers repairs, travel, reagents, " ..
                        "or anything else you might need while playing.",
                suffix = "gold",
            },
        },
    })

    -- Step 3: Bank Automation
    table.insert(steps, {
        title = "Bank Automation",
        desc  = "When you visit a banker, FlipQueue can automatically move items " ..
                "between your bags, personal bank, and warband bank.\n\n" ..
                "What you set here are " .. ns.COLORS.WHITE .. "global defaults|r " ..
                "that apply to all characters. You can override each setting " ..
                "per-character on the " .. ns.COLORS.YELLOW .. "Characters|r page — " ..
                "for example, enable auto-pull on sell alts but leave it off on " ..
                "your main. The Characters page is also where you set character " ..
                "roles and bank tab preferences.",
        settings = {
            {
                type = "checkbox", key = "autoPullBank",
                label = "Auto-pull queued items from bank",
                desc  = "When you open the bank, automatically pull items that are on your " ..
                        "to-do list from your personal bank and warbank into your bags. " ..
                        "This is how items get from storage to your inventory for posting.",
            },
            {
                type = "checkbox", key = "autoDepositWarbank",
                label = "Auto-deposit items to warbank for other characters",
                desc  = "When items in your bags are assigned to a different character, " ..
                        "automatically deposit them to the warbank so that character " ..
                        "can pick them up later.",
            },
            {
                type = "checkbox", key = "autoDepositAll",
                label = "Auto-deposit ALL extra items to bank/warbank",
                desc  = "Deposit everything you're not actively using into storage. " ..
                        "Keeps your bags clean but may deposit items you want to keep. " ..
                        "Off by default — enable per-character on the Characters page if you want it.",
            },
            {
                type = "info",
                label = "Per-character settings",
                desc  = "On the " .. ns.COLORS.YELLOW .. "Characters|r page you can:\n" ..
                        "\194\183 Override any of the above settings for individual characters\n" ..
                        "\194\183 Set a character role — " ..
                        ns.COLORS.WHITE .. "Both|r (buy and sell), " ..
                        ns.COLORS.YELLOW .. "Sell Only|r, " ..
                        ns.COLORS.BLUE .. "Buy Only|r, or " ..
                        ns.COLORS.GRAY .. "Hidden|r (skipped)\n" ..
                        "\194\183 Choose which bank tabs FlipQueue should use",
            },
        },
    })

    -- Step 4 (conditional): TSM Integration — shown BEFORE pricing/posting
    if HasTSM() then
        table.insert(steps, {
            title = "TSM Integration",
            desc  = "TradeSkillMaster is installed. Enable TSM integration to let " ..
                    "FlipQueue use your price data and Auctioning operations.",
            settings = {
                {
                    type = "checkbox", key = "tsmEnabled",
                    label = "Enable TSM integration",
                    desc  = "Allows FlipQueue to read TSM price data, Post Caps, and min price " ..
                            "thresholds. Required for all other TSM features. You can fine-tune " ..
                            "TSM settings on the TSM page after setup.",
                },
                {
                    type = "profile", key = "tsmProfile",
                    label = "TSM Profile",
                    desc  = "Which TSM profile to read groups and operations from. " ..
                            "'Use active' follows whatever profile TSM is currently using.",
                },
                {
                    type = "checkbox", key = "tsmShowColumns",
                    label = "Show AH Price column on the To-Do page",
                    desc  = "Adds a column to the To-Do task list showing the current TSM " ..
                            "price for each item, so you can see market prices at a glance.",
                },
                {
                    type = "checkbox", key = "tsmAutoUpdatePrice",
                    label = "Auto-update expected prices from TSM",
                    desc  = "Automatically refreshes the expected price on your tasks using " ..
                            "TSM data when you view them. Keeps prices current without manual updates.",
                },
            },
        })

        -- Step 5 (conditional): Pricing
        table.insert(steps, {
            title = "Pricing",
            desc  = "FlipQueue has several price sources available. Choose which one " ..
                    "you want to see and use when making decisions about your deals.",
            settings = {
                {
                    type = "info",
                    label = "TSM price sources",
                    desc  = ns.COLORS.YELLOW .. "AH price column:|r  DBMinBuyout — " ..
                            "the price shown on the To-Do page next to each task.\n\n" ..
                            ns.COLORS.YELLOW .. "Fallback min price:|r  70% DBRegionMarketAvg — " ..
                            "used as the minimum price threshold for items not in a TSM group. " ..
                            "Items in a TSM group use the group's own min price instead.\n\n" ..
                            "You can change both of these on the TSM page at any time.",
                },
                {
                    type = "toggle", key = "dfPriceSource",
                    label = "Price display in Deal Finder and To-Do preview",
                    desc  = "This controls which price is shown when evaluating deals:\n\n" ..
                            ns.COLORS.WHITE .. "Deal Price|r — the sell price from your imported data.\n" ..
                            ns.COLORS.WHITE .. "Blended|r — combines TSM market value with your personal " ..
                            "sales history (your history gains influence with more sales, up to 40%).\n" ..
                            ns.COLORS.WHITE .. "Min Buyout / Regional Avg|r — raw TSM price sources.",
                    options = {
                        { value = "deal",              label = "Deal Price" },
                        { value = "blended",           label = "Blended" },
                        { value = "DBMinBuyout",       label = "Min Buyout" },
                        { value = "DBRegionMarketAvg", label = "Regional Avg" },
                    },
                },
                {
                    type = "checkbox", key = "tsmSkipOnGenerate",
                    label = "Skip underpriced deals when generating to-do list",
                    desc  = "When building a new to-do list, reject deals where the sell price " ..
                            "is below TSM's min price threshold. Rejected deals are shown in a " ..
                            "separate list so you can review and override individual items.",
                },
                {
                    type = "checkbox", key = "tsmAutoSkipRejected",
                    label = "Auto-handle TSM rejections at the AH",
                    desc  = "When you open the Auction House, automatically skip or reassign " ..
                            "tasks that TSM would reject (below min price or already posted). " ..
                            "Reassigns to another character on the same realm if available.",
                },
            },
        })
    end

    -- Step: Posting Behavior — adapts based on whether TSM is available
    if HasTSM() then
        table.insert(steps, {
            title = "Posting Behavior",
            desc  = "With TSM enabled, FlipQueue reads your Post Cap from your " ..
                    "Auctioning operations to decide how many of each item to post.\n\n" ..
                    "You can set a fallback quantity for items without a TSM operation, " ..
                    "or switch to a fixed quantity for everything.",
            settings = {
                {
                    type = "toggle", key = "sellQtyMode",
                    label = "Quantity source",
                    desc  = "'TSM if available' reads Post Cap from your TSM Auctioning operations " ..
                            "and falls back to the fixed quantity below if no operation is set. " ..
                            "'Always fixed' ignores TSM and uses the quantity below for everything.",
                    options = {
                        { value = "tsm",   label = "TSM if available" },
                        { value = "fixed", label = "Always fixed" },
                    },
                },
                {
                    type = "slider", key = "defaultSellQty",
                    label = "Default / fallback sell quantity",
                    desc  = "Used for items that don't have a TSM Auctioning operation, " ..
                            "or when 'Always fixed' mode is selected.",
                    min = 1, max = 20, step = 1,
                },
            },
        })
    else
        table.insert(steps, {
            title = "Posting Behavior",
            desc  = "FlipQueue needs to know how many of each item to post on the " ..
                    "Auction House. Without TSM, it uses a fixed quantity for all items.",
            settings = {
                {
                    type = "slider", key = "defaultSellQty",
                    label = "Sell quantity per item",
                    desc  = "How many of each item to post on the AH. " ..
                            "For example, 1 means post one of each item per realm.",
                    min = 1, max = 20, step = 1,
                },
            },
        })
    end

    -- Step 5: Display & Notifications
    table.insert(steps, {
        title = "Display & Notifications",
        desc  = "Configure how FlipQueue keeps you informed about your tasks " ..
                "and auction status.",
        settings = {
            {
                type = "checkbox", key = "showLoginMessage",
                label = "Show login summary in chat",
                desc  = "When you log in, prints a summary of items to post, expiring auctions, " ..
                        "and tasks assigned to this character. Helps you remember what to do " ..
                        "without opening the FlipQueue window.",
            },
            {
                type = "checkbox", key = "showMini",
                label = "Show mini overlay",
                desc  = "A compact floating task list that stays on screen while you play. " ..
                        "Shows your current character's pending tasks and can be dragged anywhere. " ..
                        "Auto-hides during combat.",
            },
            {
                type = "slider", key = "expiryAlertMinutes",
                label = "Expiry alert window",
                desc  = "Warn about auctions expiring within this many minutes. Affects " ..
                        "login messages, the To-Do page, and the mini view.",
                min = 5, max = 360, step = 5,
                format = function(v)
                    return v >= 60 and string.format("%.1fh", v / 60) or (v .. "m")
                end,
            },
        },
    })

    return steps
end

--------------------------
-- Frame Construction
--------------------------

local wizardFrame  -- the overlay frame
local wizardStep = 1

local CARD_WIDTH  = 520
local CTRL_GAP    = 4
local CARD_PAD    = 20  -- horizontal padding inside card
local BTN_HEIGHT  = 26
local BTN_AREA    = BTN_HEIGHT + 20  -- buttons + padding above/below

-- Reusable backdrop tables
local CARD_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = {left = 3, right = 3, top = 3, bottom = 3},
}
local BTN_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    insets = {left = 2, right = 2, top = 2, bottom = 2},
}

-- Create a styled button
local function MakeWizardButton(parent, label, width, isGreen)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, BTN_HEIGHT)
    btn:SetBackdrop(BTN_BACKDROP)
    local bgR, bgG, bgB = 0.12, 0.12, 0.16
    if isGreen then bgR, bgG, bgB = 0.10, 0.22, 0.10 end
    btn:SetBackdropColor(bgR, bgG, bgB, 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(label)
    if isGreen then btn.text:SetTextColor(0.3, 1, 0.3) end
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(bgR + 0.06, bgG + 0.06, bgB + 0.06, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(bgR, bgG, bgB, 1)
    end)
    return btn
end

local function EnsureWizardFrame(parent)
    if wizardFrame then return wizardFrame end

    local f = CreateFrame("Frame", "FlipQueueSetupWizard", parent, "BackdropTemplate")
    f:SetAllPoints(parent)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 1)

    -- Step dots container (above card)
    f.dots = CreateFrame("Frame", nil, f)
    f.dots:SetSize(200, 12)
    f.dots:SetPoint("TOP", f, "TOP", 0, -10)
    f.dotTextures = {}

    -- Card container (centered, sized per step)
    local card = CreateFrame("Frame", nil, f, "BackdropTemplate")
    card:SetSize(CARD_WIDTH, 100) -- height set per step
    card:SetPoint("TOP", f, "TOP", 0, -28)
    card:SetBackdrop(CARD_BACKDROP)
    card:SetBackdropColor(0.07, 0.07, 0.10, 1)
    card:SetBackdropBorderColor(0.4, 0.35, 0.15, 0.8)
    f.card = card

    -- Title
    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.title:SetPoint("TOP", card, "TOP", 0, -14)
    card.title:SetTextColor(0.9, 0.82, 0.4)
    card.title:SetWidth(CARD_WIDTH - CARD_PAD * 2)
    card.title:SetJustifyH("CENTER")

    -- Description
    card.desc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.desc:SetWidth(CARD_WIDTH - CARD_PAD * 2)
    card.desc:SetJustifyH("LEFT")
    card.desc:SetWordWrap(true)
    card.desc:SetTextColor(0.72, 0.72, 0.72)
    card.desc:SetSpacing(2)

    -- Settings container (child frames added per step)
    card.settingsArea = CreateFrame("Frame", nil, card)
    card.settingsArea:SetPoint("LEFT", card, "LEFT", CARD_PAD, 0)
    card.settingsArea:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)
    card.settingsArea:SetHeight(10)

    -- Navigation buttons (inside card, at bottom)
    f.backBtn = MakeWizardButton(card, "Back", 90)
    f.nextBtn = MakeWizardButton(card, "Next", 90)
    f.finishBtn = MakeWizardButton(card, "Finish", 90, true)

    -- Welcome-only buttons (also inside card)
    f.defaultsBtn = MakeWizardButton(card, "Use Recommended Defaults", 240, true)
    f.customizeBtn = MakeWizardButton(card, "Let Me Customize", 200)

    -- Button click handlers
    f.backBtn:SetScript("OnClick", function() UI:_WizardBack() end)
    f.nextBtn:SetScript("OnClick", function() UI:_WizardNext() end)
    f.finishBtn:SetScript("OnClick", function() UI:_WizardFinish() end)
    f.defaultsBtn:SetScript("OnClick", function()
        ApplyDefaults()
        UI:_WizardFinish()
    end)
    f.customizeBtn:SetScript("OnClick", function() UI:_WizardNext() end)

    f:Hide()
    wizardFrame = f
    return f
end

--------------------------
-- Step Dots
--------------------------

local function UpdateDots(f)
    for _, tex in ipairs(f.dotTextures) do tex:Hide() end

    local total = #activeSteps
    local dotSize = 8
    local dotGap = 6
    local totalWidth = total * dotSize + (total - 1) * dotGap
    local startX = -totalWidth / 2

    for i = 1, total do
        local tex = f.dotTextures[i]
        if not tex then
            tex = f.dots:CreateTexture(nil, "ARTWORK")
            tex:SetSize(dotSize, dotSize)
            tex:SetTexture("Interface\\COMMON\\Indicator-Gray")
            f.dotTextures[i] = tex
        end
        tex:ClearAllPoints()
        tex:SetPoint("LEFT", f.dots, "CENTER", startX + (i - 1) * (dotSize + dotGap), 0)
        if i == wizardStep then
            tex:SetTexture("Interface\\COMMON\\Indicator-Yellow")
        elseif i < wizardStep then
            tex:SetTexture("Interface\\COMMON\\Indicator-Green")
        else
            tex:SetTexture("Interface\\COMMON\\Indicator-Gray")
        end
        tex:Show()
    end
end

--------------------------
-- Widget Builders
--------------------------

local function BuildCheckbox(parent, yOffset, setting)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(40)

    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

    cb.text:SetText(setting.label)
    cb.text:SetFontObject("GameFontHighlight")

    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", cb.text, "BOTTOMLEFT", 0, -1)
    desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.55, 0.55, 0.55)
    desc:SetText(setting.desc)

    local val = ns.db.settings[setting.key]
    if val == nil then val = RECOMMENDED[setting.key] or RECOMMENDED_TSM[setting.key] end
    cb:SetChecked(val and true or false)

    cb:SetScript("OnClick", function(self)
        ns.db.settings[setting.key] = self:GetChecked() and true or false
    end)

    local descH = desc:GetStringHeight() or 12
    local totalH = 22 + descH + 6
    row:SetHeight(totalH)
    return totalH
end

local function BuildInput(parent, yOffset, setting)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(54)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(setting.label)

    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(80, 20)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -4)
    box:SetAutoFocus(false)
    box:SetMaxLetters(10)
    box:SetNumeric(true)

    local val = ns.db.settings[setting.key]
    if val == nil then val = RECOMMENDED[setting.key] or 0 end
    box:SetText(tostring(val))

    if setting.suffix then
        local suf = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        suf:SetPoint("LEFT", box, "RIGHT", 6, 0)
        suf:SetTextColor(0.6, 0.6, 0.6)
        suf:SetText(setting.suffix)
    end

    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -4)
    desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.55, 0.55, 0.55)
    desc:SetText(setting.desc)

    local function Save()
        local v = tonumber(box:GetText()) or 0
        ns.db.settings[setting.key] = v
    end
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) Save(); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", Save)

    local descH = desc:GetStringHeight() or 12
    local totalH = 18 + 24 + descH + 8
    row:SetHeight(totalH)
    return totalH
end

local function BuildSlider(parent, yOffset, setting)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(64)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(setting.label)

    local slider = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
    slider:SetWidth(200)
    slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -10)
    slider:SetMinMaxValues(setting.min, setting.max)
    slider:SetValueStep(setting.step)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText(tostring(setting.min))
    slider.High:SetText(setting.format and setting.format(setting.max) or tostring(setting.max))

    local valLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valLabel:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valLabel:SetTextColor(1, 1, 1)

    local val = ns.db.settings[setting.key]
    if val == nil then val = RECOMMENDED[setting.key] or setting.min end

    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / setting.step + 0.5) * setting.step
        valLabel:SetText(setting.format and setting.format(v) or tostring(v))
        ns.db.settings[setting.key] = v
    end)
    slider:SetValue(val)

    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -4)
    desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.55, 0.55, 0.55)
    desc:SetText(setting.desc)

    local descH = desc:GetStringHeight() or 12
    local totalH = 18 + 30 + descH + 8
    row:SetHeight(totalH)
    return totalH
end

local function BuildInfo(parent, yOffset, setting)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(40)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(setting.label)

    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.55, 0.55, 0.55)
    desc:SetText(setting.desc)

    local descH = desc:GetStringHeight() or 12
    local totalH = 16 + descH + 6
    row:SetHeight(totalH)
    return totalH
end

local function BuildProfile(parent, yOffset, setting)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(56)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(setting.label)

    -- Get available profiles
    local profiles = (ns.TSM and ns.TSM.GetProfiles) and ns.TSM:GetProfiles() or {}
    local activeProfile = (ns.TSM and ns.TSM.GetActiveProfile) and ns.TSM:GetActiveProfile() or nil

    local buttons = {}
    local btnX = 0
    local btnY = -4  -- offset below label
    local btnLines = 1
    local maxWidth = CARD_WIDTH - CARD_PAD * 2
    local BTN_GAP = 4
    local BTN_ROW_H = 26

    local function UpdateHighlight()
        local current = ns.db.settings[setting.key] or ""
        for _, b in ipairs(buttons) do
            if b._value == current then
                b:SetBackdropColor(0.15, 0.35, 0.15, 1)
                b._active = true
            else
                b:SetBackdropColor(0.12, 0.12, 0.16, 1)
                b._active = false
            end
        end
    end

    local function MakeBtn(labelText, value)
        local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
        btn:SetHeight(22)
        btn:SetBackdrop(BTN_BACKDROP)
        btn:SetBackdropColor(0.12, 0.12, 0.16, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(labelText)
        local btnW = btn.text:GetStringWidth() + 20
        btn:SetWidth(btnW)
        btn._value = value

        -- Wrap to next line if this button would overflow
        if btnX > 0 and (btnX + btnW) > maxWidth then
            btnX = 0
            btnY = btnY - BTN_ROW_H
            btnLines = btnLines + 1
        end

        btn:SetPoint("TOPLEFT", label, "BOTTOMLEFT", btnX, btnY)
        btnX = btnX + btnW + BTN_GAP

        btn:SetScript("OnClick", function()
            ns.db.settings[setting.key] = value
            UpdateHighlight()
        end)
        btn:SetScript("OnEnter", function(self)
            if not self._active then self:SetBackdropColor(0.18, 0.18, 0.24, 1) end
        end)
        btn:SetScript("OnLeave", function(self)
            if not self._active then self:SetBackdropColor(0.12, 0.12, 0.16, 1) end
        end)
        table.insert(buttons, btn)
    end

    -- "Use active profile" option (empty string = auto)
    local activeLabel = "Use active"
    if activeProfile then
        activeLabel = "Use active (" .. activeProfile .. ")"
    end
    MakeBtn(activeLabel, "")

    -- Individual profile buttons
    for _, name in ipairs(profiles) do
        MakeBtn(name, name)
    end

    UpdateHighlight()

    -- Anchor desc below all button rows
    local btnAreaH = btnLines * BTN_ROW_H
    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -(btnAreaH + 4))
    desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.55, 0.55, 0.55)
    desc:SetText(setting.desc)

    local descH = desc:GetStringHeight() or 12
    local totalH = 18 + btnAreaH + 4 + descH + 8
    row:SetHeight(totalH)
    return totalH
end

local function BuildToggle(parent, yOffset, setting)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(56)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(setting.label)

    local buttons = {}
    local prevBtn

    local function UpdateHighlight()
        local current = ns.db.settings[setting.key]
        for _, b in ipairs(buttons) do
            if b._value == current then
                b:SetBackdropColor(0.15, 0.35, 0.15, 1)
                b._active = true
            else
                b:SetBackdropColor(0.12, 0.12, 0.16, 1)
                b._active = false
            end
        end
    end

    for _, opt in ipairs(setting.options) do
        local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
        btn:SetHeight(22)
        btn:SetBackdrop(BTN_BACKDROP)
        btn:SetBackdropColor(0.12, 0.12, 0.16, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(opt.label)
        btn:SetWidth(btn.text:GetStringWidth() + 20)
        btn._value = opt.value

        if prevBtn then
            btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
        end
        prevBtn = btn

        btn:SetScript("OnClick", function()
            ns.db.settings[setting.key] = opt.value
            UpdateHighlight()
        end)
        btn:SetScript("OnEnter", function(self)
            if not self._active then self:SetBackdropColor(0.18, 0.18, 0.24, 1) end
        end)
        btn:SetScript("OnLeave", function(self)
            if not self._active then self:SetBackdropColor(0.12, 0.12, 0.16, 1) end
        end)
        table.insert(buttons, btn)
    end

    local val = ns.db.settings[setting.key]
    if val == nil then
        ns.db.settings[setting.key] = RECOMMENDED[setting.key]
    end
    UpdateHighlight()

    local desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", buttons[1] or label, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.55, 0.55, 0.55)
    desc:SetText(setting.desc)

    local descH = desc:GetStringHeight() or 12
    local totalH = 18 + 26 + descH + 8
    row:SetHeight(totalH)
    return totalH
end

--------------------------
-- Welcome Page Renderer
--------------------------

local function RenderWelcome(card, f)
    local area = card.settingsArea

    card.desc:SetText("")
    card.title:SetText("")  -- banner replaces the title

    local y = 0

    -- Banner image
    local banner = area:CreateTexture(nil, "ARTWORK")
    banner:SetSize(340, 86)
    banner:SetPoint("TOP", area, "TOP", 0, y)
    banner:SetTexture("Interface\\AddOns\\flipqueue\\Art\\flipqueue-banner")
    y = y - 90

    -- Addon detection
    local tsmColor = HasTSM() and ns.COLORS.GREEN or ns.COLORS.RED
    local tsmLabel = HasTSM() and "Detected" or "Not installed"
    local auctColor = HasAuctionator() and ns.COLORS.GREEN or ns.COLORS.RED
    local auctLabel = HasAuctionator() and "Detected" or "Not installed"

    local addonInfo = area:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addonInfo:SetPoint("TOP", area, "TOP", 0, y)
    addonInfo:SetJustifyH("CENTER")
    addonInfo:SetTextColor(0.7, 0.7, 0.7)
    addonInfo:SetText(
        "TradeSkillMaster: " .. tsmColor .. tsmLabel .. "|r    " ..
        "Auctionator: " .. auctColor .. auctLabel .. "|r"
    )
    local addonH = addonInfo:GetStringHeight() or 14
    y = y - addonH - 10

    -- Divider
    local div = area:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", area, "TOPLEFT", 0, y)
    div:SetPoint("RIGHT", area, "RIGHT", 0, 0)
    div:SetColorTexture(0.35, 0.35, 0.45, 0.5)
    y = y - 8

    -- Intro line
    local intro = area:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", area, "TOPLEFT", 0, y)
    intro:SetPoint("RIGHT", area, "RIGHT", 0, 0)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetTextColor(0.8, 0.8, 0.8)
    intro:SetText("Here's what the recommended defaults will do. " ..
        "You can change any of these later in Settings, or click " ..
        ns.COLORS.WHITE .. "Let Me Customize|r to go through them step by step.")
    local introH = intro:GetStringHeight() or 14
    y = y - introH - 10

    -- Render each section with icon, title, and description
    local ICON_SIZE = 18
    local TEXT_INDENT = ICON_SIZE + 8
    local sections = GetDefaultsSections()

    for i, sec in ipairs(sections) do
        -- Section divider (between sections, not before first)
        if i > 1 then
            local secDiv = area:CreateTexture(nil, "ARTWORK")
            secDiv:SetHeight(1)
            secDiv:SetPoint("TOPLEFT", area, "TOPLEFT", 0, y)
            secDiv:SetPoint("RIGHT", area, "RIGHT", 0, 0)
            secDiv:SetColorTexture(0.25, 0.25, 0.35, 0.3)
            y = y - 6
        end

        -- Icon
        local icon = area:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("TOPLEFT", area, "TOPLEFT", 0, y)
        icon:SetTexture(sec.icon)

        -- Title
        local title = area:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        title:SetTextColor(0.9, 0.82, 0.4)
        title:SetText(sec.title)
        y = y - ICON_SIZE - 2

        -- Body text
        local body = area:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", area, "TOPLEFT", TEXT_INDENT, y)
        body:SetPoint("RIGHT", area, "RIGHT", 0, 0)
        body:SetJustifyH("LEFT")
        body:SetWordWrap(true)
        body:SetSpacing(2)
        body:SetTextColor(0.68, 0.68, 0.68)
        body:SetText(sec.text)
        local bodyH = body:GetStringHeight() or 14
        y = y - bodyH - 8
    end

    return math.abs(y)
end

--------------------------
-- Button Positioning
--------------------------

local function PositionNavButtons(f, card, isWelcome, isLast, contentBottom)
    -- Hide all nav buttons first
    f.backBtn:Hide()
    f.nextBtn:Hide()
    f.finishBtn:Hide()
    f.defaultsBtn:Hide()
    f.customizeBtn:Hide()

    if isWelcome then
        -- Center the two welcome buttons below the content
        f.defaultsBtn:ClearAllPoints()
        f.defaultsBtn:SetPoint("TOP", card.settingsArea, "TOPLEFT",
            (CARD_WIDTH - CARD_PAD * 2) / 2, -contentBottom - 8)
        f.defaultsBtn:Show()

        f.customizeBtn:ClearAllPoints()
        f.customizeBtn:SetPoint("TOP", f.defaultsBtn, "BOTTOM", 0, -6)
        f.customizeBtn:Show()

        return contentBottom + 8 + BTN_HEIGHT + 6 + BTN_HEIGHT + 12
    else
        -- Back on the left, Next/Finish on the right — inside card at bottom
        f.backBtn:ClearAllPoints()
        f.backBtn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", CARD_PAD, 10)
        f.backBtn:Show()

        if isLast then
            f.finishBtn:ClearAllPoints()
            f.finishBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_PAD, 10)
            f.finishBtn:Show()
        else
            f.nextBtn:ClearAllPoints()
            f.nextBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_PAD, 10)
            f.nextBtn:Show()
        end

        return BTN_AREA
    end
end

--------------------------
-- Step Rendering
--------------------------

local function RenderStep(f, stepIdx)
    local step = activeSteps[stepIdx]
    if not step then return end

    local card = f.card
    card.title:SetText(step.title)

    -- Position desc below title
    card.desc:ClearAllPoints()
    card.desc:SetPoint("TOP", card.title, "BOTTOM", 0, -8)
    card.desc:SetPoint("LEFT", card, "LEFT", CARD_PAD, 0)
    card.desc:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)

    -- Clear previous settings widgets
    local area = card.settingsArea
    for _, child in ipairs({area:GetChildren()}) do
        child:Hide()
    end
    for _, region in ipairs({area:GetRegions()}) do
        region:Hide()
    end

    -- Build content
    local settingsHeight = 0
    local isWelcome = step.welcome
    local isLast = stepIdx == #activeSteps

    if isWelcome then
        settingsHeight = RenderWelcome(card, f)
    elseif step.settings then
        card.desc:SetText(step.desc or "")
        local y = 0
        for _, setting in ipairs(step.settings) do
            local h = 0
            if setting.type == "checkbox" then
                h = BuildCheckbox(area, y, setting)
            elseif setting.type == "input" then
                h = BuildInput(area, y, setting)
            elseif setting.type == "slider" then
                h = BuildSlider(area, y, setting)
            elseif setting.type == "toggle" then
                h = BuildToggle(area, y, setting)
            elseif setting.type == "info" then
                h = BuildInfo(area, y, setting)
            elseif setting.type == "profile" then
                h = BuildProfile(area, y, setting)
            end
            y = y - h - CTRL_GAP
            settingsHeight = settingsHeight + h + CTRL_GAP
        end
    else
        card.desc:SetText(step.desc or "")
    end

    -- Calculate card height
    local titleH = card.title:GetStringHeight() or 0
    local descH = card.desc:GetStringHeight() or 0
    local topPad
    if isWelcome then
        topPad = 8  -- banner and content are inside settingsArea
    else
        topPad = 14 + titleH + 8 + descH + 10
    end

    -- Position settings area
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -topPad)
    area:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)
    area:SetHeight(math.max(settingsHeight, 1))

    -- Position buttons and get their height contribution
    local btnAreaH = PositionNavButtons(f, card, isWelcome, isLast, settingsHeight)

    local cardHeight = topPad + settingsHeight + btnAreaH
    card:SetHeight(math.max(cardHeight, 140))

    UpdateDots(f)
end

--------------------------
-- Navigation
--------------------------

function UI:_WizardBack()
    if wizardStep > 1 then
        wizardStep = wizardStep - 1
        RenderStep(wizardFrame, wizardStep)
    end
end

function UI:_WizardNext()
    if wizardStep < #activeSteps then
        wizardStep = wizardStep + 1
        -- Pre-populate recommended values for settings on this step that haven't been touched
        local step = activeSteps[wizardStep]
        if step.settings then
            for _, s in ipairs(step.settings) do
                if ns.db.settings[s.key] == nil then
                    local rec = RECOMMENDED[s.key] or RECOMMENDED_TSM[s.key]
                    if rec ~= nil then
                        ns.db.settings[s.key] = rec
                    end
                end
            end
        end
        RenderStep(wizardFrame, wizardStep)
    end
end

function UI:_WizardFinish()
    ns.db.settings.setupDone = true
    wizardStep = 1
    if wizardFrame then wizardFrame:Hide() end
    -- Apply mini view state immediately
    if ns.db.settings.showMini then
        UI:ShowMini()
    else
        UI:HideMini()
    end
    UI:Refresh()
end

--------------------------
-- Public API
--------------------------

function UI:ShowSetupWizard()
    if not ns.db then return end

    -- Build steps dynamically based on detected addons
    activeSteps = BuildSteps()

    local f = EnsureWizardFrame(self.tableContainer or UIParent)
    wizardStep = 1

    -- Pre-seed nil settings with recommended values so widgets show good defaults
    for k, v in pairs(RECOMMENDED) do
        if ns.db.settings[k] == nil then
            ns.db.settings[k] = v
        end
    end
    if HasTSM() then
        for k, v in pairs(RECOMMENDED_TSM) do
            if ns.db.settings[k] == nil then
                ns.db.settings[k] = v
            end
        end
    end

    RenderStep(f, wizardStep)
    f:Show()
end

function UI:HideSetupWizard()
    if wizardFrame then wizardFrame:Hide() end
end

function UI:IsSetupWizardShown()
    return wizardFrame and wizardFrame:IsShown()
end

--============================================================================
-- Link Account Wizard
--
-- A self-contained 3-page modal for linking a sync partner. Separate from the
-- main Setup Wizard to avoid state entanglement.
--
--   Page 1: Mode selection (BattleNet friend / Same BNet account)
--   Page 2: Character name + mode-specific constraints
--   Page 3: "Link request sent, waiting..." with auto-dismiss on success
--============================================================================

local linkWizardFrame = nil
local linkWizardStep = 1
local linkWizardMode = nil      -- "bnet" or "whisper"
local linkWizardTarget = nil    -- character name entered by user
local linkWizardPartnerUUIDsBefore = nil  -- snapshot for auto-dismiss detection
local linkWizardPollTicker = nil

local LW_CARD_WIDTH = 540
local LW_CARD_PAD = 20
local LW_BTN_HEIGHT = 26

local function LW_ClearSettings(card)
    if not card.settingsArea then return end
    for _, child in ipairs({ card.settingsArea:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
        child:ClearAllPoints()
    end
    for _, region in ipairs({ card.settingsArea:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            region:Hide()
            region:SetParent(nil)
            region:ClearAllPoints()
        end
    end
end

local function LW_EnsureFrame()
    if linkWizardFrame then return linkWizardFrame end

    local parent = UI.tableContainer or UIParent
    local f = CreateFrame("Frame", "FlipQueueLinkWizard", parent, "BackdropTemplate")
    f:SetAllPoints(parent)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
    f:EnableMouse(true)  -- swallow clicks so underlying UI isn't interactive

    -- Card (centered)
    local card = CreateFrame("Frame", nil, f, "BackdropTemplate")
    card:SetSize(LW_CARD_WIDTH, 380)
    card:SetPoint("CENTER", f, "CENTER", 0, 0)
    card:SetBackdrop(CARD_BACKDROP)
    card:SetBackdropColor(0.07, 0.07, 0.10, 1)
    card:SetBackdropBorderColor(0.4, 0.35, 0.15, 0.8)
    f.card = card

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.title:SetPoint("TOP", card, "TOP", 0, -14)
    card.title:SetTextColor(0.9, 0.82, 0.4)
    card.title:SetWidth(LW_CARD_WIDTH - LW_CARD_PAD * 2)
    card.title:SetJustifyH("CENTER")

    card.desc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.desc:SetWidth(LW_CARD_WIDTH - LW_CARD_PAD * 2)
    card.desc:SetJustifyH("LEFT")
    card.desc:SetWordWrap(true)
    card.desc:SetTextColor(0.72, 0.72, 0.72)
    card.desc:SetSpacing(2)
    card.desc:SetPoint("TOP", card.title, "BOTTOM", 0, -8)

    card.settingsArea = CreateFrame("Frame", nil, card)
    card.settingsArea:SetPoint("TOPLEFT", card, "TOPLEFT", LW_CARD_PAD, -80)
    card.settingsArea:SetPoint("TOPRIGHT", card, "TOPRIGHT", -LW_CARD_PAD, -80)
    card.settingsArea:SetHeight(240)

    -- Navigation buttons
    f.backBtn = MakeWizardButton(card, "Back", 90)
    f.backBtn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", LW_CARD_PAD, 14)
    f.backBtn:SetScript("OnClick", function() UI:_LinkWizardBack() end)

    f.cancelBtn = MakeWizardButton(card, "Cancel", 90)
    f.cancelBtn:SetPoint("BOTTOM", card, "BOTTOM", 0, 14)
    f.cancelBtn:SetScript("OnClick", function() UI:HideLinkWizard() end)

    f.nextBtn = MakeWizardButton(card, "Send Request", 140, true)
    f.nextBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -LW_CARD_PAD, 14)
    f.nextBtn:SetScript("OnClick", function() UI:_LinkWizardSend() end)

    f.doneBtn = MakeWizardButton(card, "Done", 90, true)
    f.doneBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -LW_CARD_PAD, 14)
    f.doneBtn:SetScript("OnClick", function() UI:HideLinkWizard() end)

    f:Hide()
    linkWizardFrame = f
    return f
end

local function LW_SnapshotPartners()
    local snapshot = {}
    if ns.Sync and ns.Sync.GetPartners then
        for uuid in pairs(ns.Sync:GetPartners()) do
            snapshot[uuid] = true
        end
    end
    return snapshot
end

local function LW_NewPartnerAppeared()
    if not linkWizardPartnerUUIDsBefore then return false end
    if not (ns.Sync and ns.Sync.GetPartners) then return false end
    for uuid in pairs(ns.Sync:GetPartners()) do
        if not linkWizardPartnerUUIDsBefore[uuid] then
            return true
        end
    end
    return false
end

local function LW_RenderStep1(card)
    card.title:SetText("Link Another Account")
    card.desc:SetText("How do you want to connect? Pick the option that matches your setup.")

    LW_ClearSettings(card)
    local area = card.settingsArea

    -- BNet friend card
    local bnetBtn = CreateFrame("Button", nil, area, "BackdropTemplate")
    bnetBtn:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
    bnetBtn:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, 0)
    bnetBtn:SetHeight(100)
    bnetBtn:SetBackdrop(BTN_BACKDROP)
    bnetBtn:SetBackdropColor(0.10, 0.14, 0.20, 1)
    bnetBtn:SetBackdropBorderColor(0.3, 0.4, 0.6, 0.9)
    bnetBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.14, 0.18, 0.26, 1) end)
    bnetBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.10, 0.14, 0.20, 1) end)
    bnetBtn:SetScript("OnClick", function()
        linkWizardMode = "bnet"
        linkWizardStep = 2
        UI:_LinkWizardRender()
    end)

    local bnetTitle = bnetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bnetTitle:SetPoint("TOPLEFT", bnetBtn, "TOPLEFT", 14, -10)
    bnetTitle:SetTextColor(0.5, 0.75, 1)
    bnetTitle:SetText("BattleNet friend")

    local bnetBody = bnetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bnetBody:SetPoint("TOPLEFT", bnetTitle, "BOTTOMLEFT", 0, -4)
    bnetBody:SetPoint("RIGHT", bnetBtn, "RIGHT", -14, 0)
    bnetBody:SetJustifyH("LEFT")
    bnetBody:SetWordWrap(true)
    bnetBody:SetTextColor(0.75, 0.75, 0.75)
    bnetBody:SetText("Sync with a different person's account. They must be on your BattleNet friends list and in WoW.\n|cff66cc66Works cross-realm. Survives character switches.|r")

    -- Same BNet account card
    local localBtn = CreateFrame("Button", nil, area, "BackdropTemplate")
    localBtn:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -112)
    localBtn:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -112)
    localBtn:SetHeight(110)
    localBtn:SetBackdrop(BTN_BACKDROP)
    localBtn:SetBackdropColor(0.18, 0.14, 0.10, 1)
    localBtn:SetBackdropBorderColor(0.6, 0.45, 0.25, 0.9)
    localBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.22, 0.18, 0.14, 1) end)
    localBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.18, 0.14, 0.10, 1) end)
    localBtn:SetScript("OnClick", function()
        linkWizardMode = "whisper"
        linkWizardStep = 2
        UI:_LinkWizardRender()
    end)

    local localTitle = localBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    localTitle:SetPoint("TOPLEFT", localBtn, "TOPLEFT", 14, -10)
    localTitle:SetTextColor(1, 0.8, 0.5)
    localTitle:SetText("Same BNet account")

    local localBody = localBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    localBody:SetPoint("TOPLEFT", localTitle, "BOTTOMLEFT", 0, -4)
    localBody:SetPoint("RIGHT", localBtn, "RIGHT", -14, 0)
    localBody:SetJustifyH("LEFT")
    localBody:SetWordWrap(true)
    localBody:SetTextColor(0.75, 0.75, 0.75)
    localBody:SetText("Sync your own second WoW license (e.g. WoW1/WoW2). BattleNet won't let you friend yourself.\n|cffffcc66Must be same realm. Both characters must be online at the same time. Pair specific characters — no character switching.|r")

    -- Hide nav buttons on page 1 (card clicks advance)
    linkWizardFrame.backBtn:Hide()
    linkWizardFrame.nextBtn:Hide()
    linkWizardFrame.doneBtn:Hide()
    linkWizardFrame.cancelBtn:Show()
end

local function LW_RenderStep2(card)
    if linkWizardMode == "bnet" then
        card.title:SetText("Link a BattleNet friend")
        card.desc:SetText("Enter the character name of a BattleNet friend who's currently online in WoW. You can use Name or Name-Realm.")
    else
        card.title:SetText("Link a same-account character")
        card.desc:SetText("Enter the character name of your other WoW license. They must be on |cffffcc66this realm|r (" .. GetNormalizedRealmName() .. ") and logged in right now.")
    end

    LW_ClearSettings(card)
    local area = card.settingsArea

    -- Input label
    local lbl = area:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
    lbl:SetText("Character name (Name or Name-Realm):")

    -- EditBox
    local eb = CreateFrame("EditBox", nil, area, "InputBoxTemplate")
    eb:SetSize(260, 22)
    eb:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 4, -6)
    eb:SetAutoFocus(true)
    eb:SetMaxLetters(0)
    eb:SetText(linkWizardTarget or "")
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self)
        linkWizardTarget = self:GetText():match("^%s*(.-)%s*$")
        UI:_LinkWizardSend()
    end)
    eb:SetScript("OnTextChanged", function(self)
        linkWizardTarget = self:GetText():match("^%s*(.-)%s*$")
    end)
    area.editBox = eb

    -- Mode-specific constraint callout
    local callout = area:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    callout:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", -4, -16)
    callout:SetPoint("RIGHT", area, "RIGHT", 0, 0)
    callout:SetJustifyH("LEFT")
    callout:SetWordWrap(true)
    callout:SetSpacing(2)
    if linkWizardMode == "bnet" then
        callout:SetTextColor(0.7, 0.9, 0.7)
        callout:SetText("• They must already be your BattleNet friend.\n• Both of you need to be logged into WoW.\n• Once linked, the connection survives character switches and works cross-realm.")
    else
        callout:SetTextColor(0.95, 0.85, 0.5)
        callout:SetText("• Both characters must be on |cffffffff" .. GetNormalizedRealmName() .. "|r (or a connected realm).\n• Both must be online at the same time for updates to flow.\n• If either logs out, updates queue until you're both online again.\n• This pair is tied to specific characters — changing characters on either side breaks the link.")
    end

    linkWizardFrame.backBtn:Show()
    linkWizardFrame.nextBtn:Show()
    linkWizardFrame.doneBtn:Hide()
    linkWizardFrame.cancelBtn:Show()
end

local function LW_RenderStep3(card)
    card.title:SetText("Link request sent")

    local modeLabel = (linkWizardMode == "whisper") and "same-account" or "BNet friend"
    card.desc:SetText("A " .. modeLabel .. " link request was sent to |cffffffff" .. (linkWizardTarget or "?") .. "|r.\n\nOpen FlipQueue on the other character and click |cff66cc66Accept|r in Settings > Multi-Account. This wizard will close automatically when the link is established.")

    LW_ClearSettings(card)
    local area = card.settingsArea

    local status = area:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -10)
    status:SetPoint("RIGHT", area, "RIGHT", 0, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(true)
    status:SetTextColor(0.8, 0.8, 0.8)
    status:SetText("|cffaaaaaaWaiting for the other side to accept...|r")
    area.statusText = status

    linkWizardFrame.backBtn:Hide()
    linkWizardFrame.nextBtn:Hide()
    linkWizardFrame.doneBtn:Show()
    linkWizardFrame.cancelBtn:Hide()
end

function UI:_LinkWizardRender()
    local f = LW_EnsureFrame()
    if linkWizardStep == 1 then
        LW_RenderStep1(f.card)
    elseif linkWizardStep == 2 then
        LW_RenderStep2(f.card)
    elseif linkWizardStep == 3 then
        LW_RenderStep3(f.card)
    end
    f:Show()
end

function UI:_LinkWizardBack()
    if linkWizardStep > 1 then
        linkWizardStep = linkWizardStep - 1
        UI:_LinkWizardRender()
    end
end

function UI:_LinkWizardSend()
    if not linkWizardTarget or linkWizardTarget == "" then
        if linkWizardFrame and linkWizardFrame.card and linkWizardFrame.card.settingsArea and linkWizardFrame.card.settingsArea.editBox then
            linkWizardFrame.card.settingsArea.editBox:SetFocus()
        end
        return
    end
    if not ns.Sync then return end

    linkWizardPartnerUUIDsBefore = LW_SnapshotPartners()
    ns.Sync:RequestPair(linkWizardTarget, linkWizardMode)

    linkWizardStep = 3
    UI:_LinkWizardRender()

    -- Poll for successful link and auto-dismiss
    if linkWizardPollTicker then linkWizardPollTicker:Cancel() end
    linkWizardPollTicker = C_Timer.NewTicker(1, function()
        if not linkWizardFrame or not linkWizardFrame:IsShown() then
            if linkWizardPollTicker then linkWizardPollTicker:Cancel(); linkWizardPollTicker = nil end
            return
        end
        if LW_NewPartnerAppeared() then
            if linkWizardFrame.card and linkWizardFrame.card.settingsArea and linkWizardFrame.card.settingsArea.statusText then
                linkWizardFrame.card.settingsArea.statusText:SetText("|cff66cc66Link established! You can close this window.|r")
            end
            if linkWizardPollTicker then linkWizardPollTicker:Cancel(); linkWizardPollTicker = nil end
        end
    end)
end

function UI:ShowLinkWizard()
    linkWizardStep = 1
    linkWizardMode = nil
    linkWizardTarget = nil
    linkWizardPartnerUUIDsBefore = nil
    UI:_LinkWizardRender()
end

function UI:HideLinkWizard()
    if linkWizardPollTicker then linkWizardPollTicker:Cancel(); linkWizardPollTicker = nil end
    if linkWizardFrame then linkWizardFrame:Hide() end
end

function UI:IsLinkWizardShown()
    return linkWizardFrame and linkWizardFrame:IsShown()
end
