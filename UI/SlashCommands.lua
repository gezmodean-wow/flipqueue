-- UI/SlashCommands.lua
-- Slash command handler
local addonName, ns = ...

local UI = ns.UI

SLASH_FLIPQUEUE1 = "/flipqueue"
SLASH_FLIPQUEUE2 = "/fq"

SlashCmdList["FLIPQUEUE"] = function(msg)
    msg = (msg or ""):lower():trim()

    if msg == "import" then
        UI.currentPage = "import"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg == "scan" then
        ns.Scanner:ScanCurrentCharacter()

    elseif msg == "bank" then
        ns.Scanner:ScanBank()
        ns.Scanner:ScanWarbank()

    elseif msg == "clear" then
        ns.Queue:Clear()
        ns:Print("Queue cleared.")
        UI:Refresh()

    elseif msg == "clear posted" then
        ns.Queue:Clear("posted")
        ns:Print("Posted items cleared.")
        UI:Refresh()

    elseif msg == "clear log" then
        ns.Queue:ClearLog()
        ns:Print("Log cleared.")
        UI:Refresh()

    elseif msg == "log" then
        UI.currentPage = "log"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg == "queue" or msg == "generator" then
        UI.currentPage = "generator"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg == "inv" or msg == "inventory" then
        UI.currentPage = "inventory"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg == "autopull" then
        if ns.db then
            ns.db.settings.autoPullBank = not ns.db.settings.autoPullBank
            ns:Print("Auto-pull from bank: " .. (ns.db.settings.autoPullBank and "ON" or "OFF"))
        end

    elseif msg == "gold" then
        if ns.db then
            ns.db.settings.autoWithdrawGold = not ns.db.settings.autoWithdrawGold
            ns:Print("Auto-withdraw gold for AH fees: " .. (ns.db.settings.autoWithdrawGold and "ON" or "OFF"))
        end

    elseif msg == "dnt" or msg == "donottrack" then
        UI:ShowDoNotTrackFrame()

    elseif msg:match("^dnt add ") or msg:match("^donottrack add ") then
        local itemName = msg:match("^d[on]*t[rack]* add (.+)$")
        if itemName and itemName ~= "" then
            -- Resolve itemID from inventory so IsDoNotTrack(itemID) works
            local resolvedID = ns:ResolveItemID({itemID = "", name = itemName})
            local dntKey = resolvedID and tostring(resolvedID) or itemName
            ns.Queue:AddDoNotTrack(dntKey, itemName)
            ns:Print("Added to Do Not Track: " .. itemName .. (resolvedID and (" (ID: " .. resolvedID .. ")") or " (name only, item not in inventory)"))
            UI:Refresh()
        end

    elseif msg:match("^dnt remove ") or msg:match("^donottrack remove ") then
        local itemName = msg:match("^d[on]*t[rack]* remove (.+)$")
        if itemName and itemName ~= "" then
            -- Try to find by name
            for id, nameOrTrue in pairs(ns.db.doNotTrack) do
                local name = type(nameOrTrue) == "string" and nameOrTrue or id
                if name:lower() == itemName:lower() or id == itemName then
                    ns.Queue:RemoveDoNotTrack(id)
                    ns:Print("Removed from Do Not Track: " .. name)
                    UI:Refresh()
                    return
                end
            end
            ns:PrintError("Item not found in Do Not Track list: " .. itemName)
        end

    elseif msg == "mini" then
        UI:ToggleMini()

    elseif msg == "export" or msg == "export bags" or msg == "export bank"
        or msg == "export warbank" or msg == "export wb" or msg == "export all" then
        UI.currentPage = "export"
        UI.mainFrame:Show()
        UI:Refresh()

    elseif msg == "settings" or msg == "config" or msg == "options" then
        UI:ShowSettings()

    elseif msg == "sort" then
        if ns.db then
            ns.db.settings.sortMode = ns.db.settings.sortMode == "realm" and "name" or "realm"
            ns:Print("Sort mode: " .. ns.db.settings.sortMode)
            UI:Refresh()
        end

    elseif msg == "debug" then
        if ns.db then
            ns.db.settings.debugMessages = not ns.db.settings.debugMessages
            ns:Print("Debug messages: " .. (ns.db.settings.debugMessages and
                ns.COLORS.GREEN .. "ON" or ns.COLORS.RED .. "OFF") .. "|r")
        end

    elseif msg == "help" then
        ns:Print("Commands:")
        print("  /fq - Toggle main window")
        print("  /fq import - Open import page")
        print("  /fq log - Show posted items log")
        print("  /fq queue - Open To-Do Generator")
        print("  /fq inv - Open full inventory page")
        print("  /fq scan - Rescan current character's bags")
        print("  /fq bank - Scan bank + warbank (must be at bank)")
        print("  /fq export - Export page (CSV/AAA formats)")
        print("  /fq sort - Toggle sort mode (realm/name)")
        print("  /fq clear - Clear entire queue")
        print("  /fq clear posted - Clear posted items only")
        print("  /fq clear log - Clear posted items log")
        print("  /fq autopull - Toggle auto-pull from bank")
        print("  /fq gold - Toggle auto-withdraw gold for AH fees")
        print("  /fq dnt - Show Do Not Track list")
        print("  /fq mini - Toggle mini overlay")
        print("  /fq debug - Toggle debug messages")
        print("  /fq settings - Open settings panel")
        print("  /fq dnt add <name> - Add item to Do Not Track")
        print("  /fq dnt remove <name> - Remove from Do Not Track")
        print("")
        print("  Inventory: Right-click by status (DNT/remove DNT/queue info)")
        print("  To-Do: Right-click = posted, Shift+Right = skip")
    else
        -- Toggle main window
        if UI.mainFrame:IsShown() then
            UI.mainFrame:Hide()
        else
            UI.mainFrame:Show()
            UI:Refresh()
        end
    end
end
