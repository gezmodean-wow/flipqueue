# Transformer Architecture (Future — #32)

## Pattern: Input → Transform → Output pipeline

**New file:** `Transformer.lua`

## Input Adapters (each returns normalized item array)
- `InputFromTSMGroup(profile, groupPath)` — reads `TradeSkillMasterDB` items
- `InputFromImports(source)` — reads `ns.db.imports[source]`
- `InputFromInventory(filter, value)` — reuses `BuildItemPool()`
- `InputFromAuctionatorList(name)` — reads `AUCTIONATOR_SHOPPING_LISTS`

## Normalized Item Structure
```lua
{ itemKey, itemID, name, quality, quantity, expectedPrice,
  targetRealm, isBattlePet, speciesID, category, icon }
```

## Transform Functions (array in → array out, composable)
- `SplitPets(items)` → returns `{items=[], pets=[]}` for AAA format
- `PriceModify(items, source, modifier)` → e.g., DBMarket × 0.8
- `FieldMap(items, mapping)` → rename/reformat fields
- `Filter(items, predicate)` → filter by condition
- `MergeByKey(items)` → dedup, sum quantities

## Output Adapters (array → formatted string)
- `OutputAAAJSON(items)` — refactor from `Export.lua`
- `OutputFPCSV(items)` — refactor from `Export.lua`
- `OutputTSMGroupString(items)` → `"i:12345,i:67890"` format
- `OutputAuctionatorList(items, name)` → search term format

## Initial Transforms
1. TSM group → AAA JSON: `InputTSMGroup → SplitPets → PriceModify → OutputAAAJSON`
2. X-realm CSV → TSM group: `InputImports("fpCrossRealm") → OutputTSMGroupString`

## UI
New "Transform" page in sidebar nav. Source picker → transform config → preview table → output format → copy.
