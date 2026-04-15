# Multi-Account Architecture (Future — #15)

## TSM Account Detection
- `TradeSkillMasterDB._syncAccountKey`: `{ "Faction - Realm" → "Faction - Realm - UniqueID" }` — per-factionrealm account identifier
- `TradeSkillMasterDB._syncOwner`: `{ "Name - Faction - Realm" → accountKey }` — links characters to accounts
- Characters on the same `_syncOwner` value are on the same WoW account

## Proposed Data Model
```lua
ns.db.accounts = {
    primary = { syncKey = "...", characters = {"Char-Realm", ...} },
    external = { ... },  -- existing manual entry
    linked = {
        ["syncKey2"] = {
            label = "Alt Account",
            characters = {"AltChar-Realm", ...},
            lastSync = timestamp,
        },
    },
}
```

## Key Constraints
- TSM syncs pricing data, NOT inventory across accounts
- Inventory unification requires: shared SavedVariables (same WoW install) or desktop companion app
- Same Bnet can have multiple WoW accounts sharing the same install → same `WTF/Account/` folder
- Different Bnet accounts = different installs = no automatic sharing

## Recommended Phased Approach

### Phase 1: Detect Accounts
Detect accounts from TSM `_syncOwner` groupings. Show in Settings.

### Phase 2: Same-Install Inventory
For same-install accounts, read other account's FlipQueueDB SavedVariables at `WTF/Account/<acct>/SavedVariables/FlipQueue.lua` — requires knowing account folder names.

### Phase 3: Unified Import
Tag imports with source account, unified inventory view with account column.

## Use Cases
- Buy on Account A, sell on Account B: import → assign to Account B character → track transfer via warbank/mail
- Split realms across accounts: unified "need chars" view across all accounts
- Inventory view: show which account owns each item
