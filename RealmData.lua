-- RealmData.lua
-- Connected realm group data from FlippingPal
-- Maps realm names to connected AH groups for exact matching
-- This replaces substring-based realm matching to avoid false positives
-- (e.g., "Dalaran" vs "Der Rat von Dalaran")
local addonName, ns = ...

--------------------------
-- Connected Realm Groups
--------------------------
-- Each entry is a list of normalized (lowercase, accent-stripped) realm names
-- that share the same Auction House. All realms in one entry = one AH group.
-- Source: FlippingPal realm tables (March 2026)

local US_GROUPS = {
    -- Standalone realms
    {"moon guard"},
    {"stormrage"},
    {"area 52"},
    {"ragnaros"},
    {"illidan"},
    {"tichondrius"},
    {"quel'thalas"},
    {"thrall"},
    {"proudmoore"},
    {"dalaran"},
    {"zul'jin"},
    {"azralon"},
    {"turalyon"},
    {"drakkari"},
    {"sargeras"},
    {"kel'thuzad"},
    {"barthilas"},
    {"kil'jaeden"},
    {"mal'ganis"},
    {"hyjal"},
    {"emerald dream"},
    {"bleeding hollow"},
    {"wyrmrest accord"},
    {"aerie peak"},
    {"gallywix"},
    {"darkspear"},
    {"goldrinn"},
    {"earthen ring"},
    {"arthas"},
    {"stormreaver"},
    {"lightbringer"},
    -- Connected groups
    {"frostmourne", "dreadmaul", "thaurissan", "jubei'thos", "gundrak"},
    {"firetree", "drak'tharon", "rivendare", "vashj", "spirestone", "malorne", "frostwolf", "stormscale"},
    {"aegwynn", "gurubashi", "bonechewer", "hakkar", "garrosh", "daggerspine"},
    {"caelestrasz", "nagrand", "saurfang"},
    {"sen'jin", "dunemaul", "maiev", "bloodscalp", "quel'dorei", "boulderfist", "stonemaul"},
    {"khaz'goroth", "aman'thul", "dath'remar"},
    {"malygos", "garona", "lightning's blade", "icecrown", "onyxia", "burning blade"},
    {"cairne", "cenarius", "frostmane", "tortheldrin", "ner'zhul", "korgath", "perenolde"},
    {"agamaggan", "kargath", "burning legion", "thunderhorn", "the underbog", "blade's edge", "archimonde", "norgannon", "jaedenar"},
    {"azjol-nerub", "muradin", "nordrassil", "blackrock", "khaz modan"},
    {"hellscream", "gorefiend", "spinebreaker", "zangarmarsh", "wildhammer", "eredar"},
    {"trollbane", "grizzly hills", "malfurion", "lothar", "kael'thas", "gnomeregan", "moonrunner", "ghostlands"},
    {"llane", "arygos"},
    {"azgalor", "thunderlord", "destromath", "blood furnace", "mannoroth", "nazjatar", "azshara"},
    {"aggramar", "fizzcrank"},
    {"dragonmaw", "uldum", "akama", "korialstrasz", "eldre'thalas", "mug'thol", "antonidas"},
    {"silvermoon", "skywall", "terenas", "hydraxis", "drak'thul", "borean tundra", "mok'nathal", "shadowsong"},
    {"warsong", "gorgonnash", "the forgotten coast", "balnazzar", "alterac mountains", "undermine", "anvilmar"},
    {"nemesis", "tol barad"},
    {"eonar", "skullcrusher", "gul'dan", "zuluhed", "ursin", "andorhal", "black dragonflight", "velen", "scilla"},
    {"elune", "laughing skull", "auchindoun", "cho'gall", "gilneas"},
    {"chromaggus", "nathrezim", "smolderthorn", "anub'arak", "arathor", "garithos", "drenden", "crushridge"},
    {"bloodhoof", "duskwood"},
    {"durotan", "ysera"},
    {"alleria", "exodar", "medivh", "khadgar"},
    {"suramar", "windrunner", "darrowmere", "draka"},
    {"eitrigg", "shu'halo"},
    {"detheroc", "dethecus", "lethon", "blackwing lair", "shadowmoon", "haomarush"},
    {"ravencrest", "uldaman"},
    {"kilrogg", "winterhoof"},
    {"magtheridon", "anetheron", "ysondre", "altar of storms"},
    {"dark iron", "shattered hand", "coilfang", "demon soul", "dalvengyr"},
    {"rexxar", "misha"},
    {"silver hand", "thorium brotherhood", "farstriders"},
    {"kirin tor", "steamwheedle cartel", "sentinels"},
    {"staghelm", "dawnbringer", "madoran", "azuremyst"},
    {"argent dawn", "the scryers"},
    {"kalecgos", "shattered halls", "executus", "deathwing"},
    {"whisperwind", "dentarg"},
    {"draenor", "echo isles"},
    {"blackhand", "galakrond"},
    {"alexstrasza", "terokkar"},
    {"maelstrom", "twisting nether", "lightninghoof", "the venture co", "ravenholdt"},
    {"bronzebeard", "shandris"},
    {"runetotem", "uther"},
    {"feathermoon", "scarlet crusade"},
    {"shadow council", "sisters of elune", "cenarion circle", "blackwater raiders"},
    {"greymane", "tanaris"},
    {"kul tiras", "bladefist"},
    {"baelgun", "doomhammer"},
    {"dragonblight", "fenris"},
    {"vek'nilash", "nazgrel", "nesingwary"},
}

local EU_GROUPS = {
    -- Standalone realms
    {"gordunni"},
    {"howling fjord"},
    {"eversong"},
    {"draenor"},
    {"silvermoon"},
    {"argent dawn"},
    {"soulflayer"},
    {"hyjal"},
    {"kazzak"},
    {"twisting nether"},
    {"aegwynn"},
    {"outland"},
    {"ravencrest"},
    {"magtheridon"},
    {"ragnaros"},
    {"khaz modan"},
    {"frostwolf"},
    {"stormscale"},
    {"blackrock"},
    {"nemesis"},
    {"fordragon"},
    {"ysondre"},
    {"eredar"},
    {"archimonde"},
    {"chamber of aspects"},
    {"azuregos"},
    {"deathguard"},
    {"die aldor"},
    {"pozzo dell'eternita"},
    {"ashenvale"},
    {"antonidas"},
    -- Connected groups
    {"dentarg", "tarren mill"},
    {"turalyon", "doomhammer"},
    {"blackscar", "deathweaver", "borean tundra", "thermaplugg", "grom", "booty bay"},
    {"todeswache", "zirkel des cenarius", "der mithrilorden", "forscherliga", "der rat von dalaran", "die nachtwache"},
    {"karazhan", "dragonblight", "the maelstrom", "ghostlands", "lightning's blade", "deathwing"},
    {"genjuros", "zenedar", "bladefist", "neptulon", "frostwhisper", "darksorrow"},
    {"zul'jin", "uldum", "sanguino", "shen'dralar"},
    {"auchindoun", "dunemaul", "sylvanas", "jaedenar"},
    {"spinebreaker", "dragonmaw", "vashj", "stormreaver", "haomarush"},
    {"lothar", "baelgun", "azshara", "krag'jin"},
    {"al'akir", "skullcrusher", "xavius", "burning legion"},
    {"galakrond", "deepholm", "razuvious"},
    {"marecage de zangar", "cho'gall", "eldre'thalas", "sinstralis", "dalaran"},
    {"arygos", "khaz'goroth"},
    {"hellfire", "runetotem", "arathor", "kilrogg", "nagrand"},
    {"norgannon", "dun morogh"},
    {"blackmoore", "tichondrius", "lordaeron"},
    {"wildhammer", "thunderhorn"},
    {"rexxar", "alleria"},
    {"nethersturm", "alexstrasza", "madmortem", "proudmoore"},
    {"nefarian", "gilneas", "destromath", "ulduar", "mannoroth", "gorgonnash", "nera'thor"},
    {"scarshield legion", "sporeggar", "earthen ring", "defias brotherhood", "ravenholdt", "darkmoon faire", "the venture co"},
    {"grim batol", "aggra (portugues)", "frostmane"},
    {"drak'thul", "burning blade"},
    {"arthas", "blutkessel", "wrathbringer", "durotan", "kel'thuzad", "vek'lor", "tirion"},
    {"garona", "sargeras", "ner'zhul"},
    {"moonglade", "steamwheedle cartel", "the sha'tar"},
    {"arak-arahm", "rashgarroth", "kael'thas", "throk'feroth"},
    {"vol'jin", "chants eternels"},
    {"goldrinn", "lich king", "greymane"},
    {"tyrande", "los errantes", "colinas pardas"},
    {"nazjatar", "zuluhed", "dalvengyr", "aman'thul", "frostmourne", "anub'arak"},
    {"elune", "varimathras"},
    {"naxxramas", "arathi", "illidan", "temple noir"},
    {"quel'thalas", "azjol-nerub"},
    {"thrall", "kargath", "ambossar"},
    {"dun modr", "c'thun"},
    {"die arguswacht", "die ewige wacht", "die todeskrallen", "das syndikat", "der abyssische rat", "kult der verdammten", "das konsortium", "die silberne hand"},
    {"echsenkessel", "blackhand", "mal'ganis", "taerar"},
    {"emeriss", "twilight's hammer", "bloodscalp", "crushridge", "agamaggan", "hakkar"},
    {"anetheron", "kil'jaeden", "rajaxx", "festung der sturme", "gul'dan", "nathrezim"},
    {"dethecus", "theradras", "onyxia", "mug'thol", "terrordar"},
    {"kor'gall", "executus", "shattered hand", "bloodfeather", "terokkar", "saurfang", "darkspear", "burning steppes"},
    {"confrerie du thorium", "la croisade ecarlate", "culte de la rive noire", "les sentinelles", "kirin tor", "les clairvoyants", "conseil des ombres"},
    {"suramar", "medivh"},
    {"shattered halls", "chromaggus", "sunstrider", "balnazzar", "talnivarr", "ahn'qiraj", "daggerspine", "laughing skull", "trollbane", "boulderfist"},
    {"uldaman", "drek'thar", "krasus", "eitrigg"},
    {"blade's edge", "eonar", "vek'nilash", "aerie peak", "bronzebeard"},
    {"lightbringer", "mazrigos"},
    {"garrosh", "shattrath", "nozdormu", "perenolde", "teldrassil"},
    {"malygos", "malfurion"},
    {"khadgar", "bloodhoof"},
    {"terenas", "emerald dream"},
    {"azuremyst", "stormrage"},
    {"shadowsong", "aszune"},
    {"un'goro", "sen'jin", "area 52"},
    {"aggramar", "hellscream"},
    {"bronze dragonflight", "nordrassil"},
    {"exodar", "minahonda"},
    {"ysera", "malorne"},
    {"kul tiras", "alonsus", "anachronos"},
}

--------------------------
-- Lookup Table Builder
--------------------------

-- Build reverse lookup: normalized realm name -> group index
local function BuildLookup(groups)
    local lookup = {}
    for groupID, realms in ipairs(groups) do
        for _, realm in ipairs(realms) do
            lookup[realm] = groupID
        end
    end
    return lookup
end

-- Store raw data for potential future migration
ns._realmDataUS = US_GROUPS
ns._realmDataEU = EU_GROUPS

-- Build the lookup tables. Call from InitDB after saved variables are loaded.
function ns:BuildRealmLookup()
    local usLookup = BuildLookup(US_GROUPS)
    local euLookup = BuildLookup(EU_GROUPS)

    -- Detect current region: 1=US, 2=KR, 3=EU, 4=TW, 5=CN
    local region = GetCurrentRegion and GetCurrentRegion() or 1
    if region == 3 then
        ns.REALM_LOOKUP = euLookup
    else
        ns.REALM_LOOKUP = usLookup
    end

    -- Also store both for cross-region checks if needed
    ns.REALM_LOOKUP_US = usLookup
    ns.REALM_LOOKUP_EU = euLookup
end

-- Get the connected realm group ID for a realm name (using current region)
function ns:GetRealmGroupID(realmName)
    if not realmName or realmName == "" then return nil end
    if not ns.REALM_LOOKUP then return nil end
    return ns.REALM_LOOKUP[ns:NormalizeRealmKey(realmName)]
end

-- Get all realm names in the same connected group as the given realm
function ns:GetConnectedRealms(realmName)
    if not realmName or realmName == "" then return {} end
    local groupID = ns:GetRealmGroupID(realmName)
    if not groupID then return {realmName} end

    local region = GetCurrentRegion and GetCurrentRegion() or 1
    local groups = region == 3 and EU_GROUPS or US_GROUPS
    return groups[groupID] or {realmName}
end
