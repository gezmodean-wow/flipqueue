# Changelog

## v0.12.0-alpha15

UX follow-ups to alpha14's architectural rebuild from in-game testing.

### Characters table column readability

The action-mode columns (Tasks / Extras / Reagents) were 30px wide with full-word labels (`Auto` / `Manual` / `Off`); `Manual` overflowed and rendered cramped or truncated.

- Bumped column widths 30 → 50px to leave room for the longest label.
- Renamed column headers from the legacy `Pull` / `Dep` / `All` to the new action-class names: `Tasks` / `Extras` / `Reag.` — matches the model the underlying data now stores.
- Cell label `Manual` shortened to `Man` so the cell renders cleanly inside 50px without clipping. `Auto` and `Off` unchanged.

`UI/MainFrame.lua` (column defs) and `UI/CharactersPage.lua` (`FormatModeColumn`).

### Defaults bar: tri-state buttons replace mode-key checkboxes

The Character Defaults bar at the top of the Characters page had checkboxes for every action class — but checkboxes only have two states, so the defaults bar couldn't represent the third tri-state value (`disabled`). The bar's checkbox-shaped widgets toggled auto ↔ manual; players who wanted "off" had to drill into the per-character config panel.

New `MakeGlobalModeBtn(anchor, label, settingKey, tooltip)` helper builds a clickable backdrop button that displays the current mode (`Auto` green / `Man` yellow / `Off` red) and cycles `auto → manual → disabled → auto` on click. Tooltip surfaces the cycle order so players don't have to discover it by trial.

Replaced for the five action-class settings: `todoMode`, `extrasMode`, `reagentsMode`, `goldWithdrawMode`, `goldDepositMode`. The two master toggles (`manageItems`, `manageGold`) stay as checkboxes — they're bool, not tri-state.

`MakeGlobalCB`'s mode-key special case (the `if settingKey:sub(-4) == "Mode"` branch from alpha14) is now dead code for the defaults bar but stays in the helper for any future bool-keyed callers; harmless.

### Anchor + Show/Hide plumbing

The new mode-button widget is structurally a label fontstring + clickable button (sibling, not child, so the label can extend left of the button bounds). The surrounding code chains widgets via `widget.text:RIGHT` and the (disabled)-overlay code spans `widget:LEFT` / `lastWidget.text:RIGHT`. To keep both patterns working without breaking callers:

- `widget.text` aliases to the **button** (rightmost edge of the widget) — chained-anchor pattern places the next widget past the button, not overlapping it.
- `widget.labelStart` exposes the **label** fontstring — the (disabled) overlay anchors `LEFT` here so it spans the label too, not just the button.
- `widget:Hide()` / `widget:Show()` are overridden to chain visibility into `labelStart` so callers toggling visibility on the widget hide both pieces together.

### Bank-ops popup: Execute button gets a dedicated footer band (closes #153)

The Execute button visually crowded — and at certain row counts overlapped — the last row in the bank-ops list. Pulled forward from #153 (originally slated for v0.13 polish) since it's adjacent to the alpha14 popup work and bothered testers in-game on alpha14.

- New footer frame anchored to the popup's bottom edge, height `FOOTER_HEIGHT = 40` (room for the 26px button plus 7px padding above and below).
- Footer has its own backdrop (matching the popup's dark color) so any row content scrolled past the visible area is occluded — the button area never paints over content even at frame-level edge cases.
- Top edge of the footer is a 1px separator line, visually severing the row list from the action band.
- Footer's frame level is `popup_level + 5` so it always renders above the scroll content.
- Execute button reparented from the popup root into the footer, anchored `CENTER` (no longer relies on `BOTTOM, f, BOTTOM, 0, 10` which left only an 8px implicit gap).
- `ResizePopup` updated: `bottomHeight` now uses `FOOTER_HEIGHT` instead of the hardcoded 36; the footer is shown only when a button is being shown so auto-mode popups don't carry an empty footer band.

### Batched-deposit heartbeat covers the verify-await window + skip empty inter-batch wait

Two adjacent fixes from the same in-game session, both about idle time the player perceives between batches and at end-of-deposit.

**Verify-await heartbeat.** `BankQueue:Process` (batched path) issues a batch then waits for `ITEM_LOCK_CHANGED` events to settle, debounced by `VERIFY_DELAY = 0.5s` quiet (capped at `BATCH_TIMEOUT = 5s` if no events arrive). During this window no heartbeat fired, so the popup went silent — testers reported "big gap after the batch, nothing happens, then the animation plays super fast" (the "super-fast animation" being the subsequent `INTER_BATCH_DELAY` 0.3s "Next batch" heartbeat firing AFTER the silent verify gap). Now `onWait("Verifying moves", BATCH_TIMEOUT, "variable")` fires when the verify-await begins; either the debounced timer or the BATCH_TIMEOUT fallback calls `onWaitEnd` before invoking VerifyBatch. Variable kind because events typically resolve us well under the ceiling — the `≤` countdown prefix makes that explicit.

**Empty-queue inter-batch skip.** When the verify completes a batch and the queue is empty, the previous flow still played the 0.3s "Next batch" heartbeat + 0.1s wait inside `ProcessNextBatch` before reaching `Finish`. That stacked with the post-action settle for a multi-second perceived idle after the popup ticked `N/N`. Now `VerifyBatch` checks `#queue > 0` and bypasses the inter-batch heartbeat / delay when no more work remains, calling `Finish` on the next frame.

`BankQueue.lua` only.

### Bank-ops post-completion idle reduced from ~3s to ~0.3s

Each Auto* deposit / pull subphase ended with a hardcoded `C_Timer.After(1, ...)` before its `onComplete` callback fired. The 1-second wait predates the `BankQueue:VerifyBatch` flow that already settles bag state via container-state diff with a `SYNC_VERIFY_DELAY = 0.4s` gate; by the time we hit the 1s timer the moves are already verified and bag state is stable, so the additional second was redundant defense from an earlier era of the queue.

With the alpha14 split into to-do / extras / reagents subphases, the cumulative idle stack at the end of a typical 3-subphase deposit was ~3 seconds of nothing happening after the popup ticked `N/N`. Reduced to `C_Timer.After(0.1, ...)` (one-frame settle) on all four sites:

- `TrackerBank.lua:174` `AutoPullFromBank`
- `TrackerBank.lua:762` `AutoDepositToWarbank`
- `TrackerBank.lua:953` `AutoDepositExtraItems`
- `TrackerBank.lua:1108` `AutoDepositReagents`

`BankQueue.SYNC_VERIFY_DELAY` (0.4s, the verify gate) and `Tracker.lua:476`'s 0.3s inter-phase chain delay are unchanged — both are functional, not redundant.

### Files

```
M  BankQueue.lua
M  CHANGELOG.md
M  TrackerBank.lua
M  UI/BankPopup.lua
M  UI/CharactersPage.lua
M  UI/MainFrame.lua
```

No schema change. No behavior change beyond the polish surface — alpha14's underlying tri-state model is unchanged.

## v0.12.0-alpha16

Two bug fixes from in-game testing on alpha15: TSM postCap inflating gold-pull estimates by orders of magnitude (#117 reopen), and the Cogworks library taint blocking right-click on knowledge consumables (#156). Plus the `/fq debug gold` diagnostic gets per-task math so future "gold pull is wrong" reports become a one-command triage.

### Bank-ops gold-pull inflated by TSM postCap (closes #117 reopen)

Mort and Zong reported the addon trying to pull "wildly high" amounts from the warbank — Mort's worst case was 344.7k for a darkmoon deck and a recipe; a separate test hit 150k for two enchant scrolls and two recipes; Zong saw 1.5M+ on enchant-heavy queues. All three traces back to the same line in the posting-fee estimator.

`Tracker:CalculatePostingFees` looked up the player's TSM Auctioning op for each task and lifted `op.postCap` directly into the per-task quantity:

```lua
if op.postCap then
    local tsmQty = tonumber(op.postCap)
    if tsmQty and tsmQty > 0 then
        postQty = tsmQty   -- ← wrong: replaces the queue/default qty
    end
end
```

`postCap` is a *ceiling* on total posted quantity (TSM's "never have more than N posted across all listings"), not a per-task target. Players using `postCap=50000` for high-volume trade goods saw the deposit estimate explode by a factor of 50,000 — `vendor=5g × 50000 × 30% = 75,000g` per such item. Replaced with a clamp:

```lua
postQty = math.min(postQty, tsmQty)
```

Now the existing `postQty = max(queueItem.quantity, defaultSellQty)` baseline is kept and only narrowed by `postCap`, which matches `postCap`'s actual semantic. The fee estimate also drives the actual `AutoWithdrawGold` withdraw amount — not just the popup display — so this is a real-money fix not just a UX one. (Mort's `maxWithdrawGold` was unset, so his bogus pulls went through; the maintainer's repro had `maxWithdrawGold=1000g` which capped the bogus 85.2k withdraw target at 1k, masking how bad it would have been on a less-defensive setup.)

`TrackerBank.lua:260-272`.

### `/fq debug gold` per-task breakdown

The previous `/fq debug gold` printed only aggregates: total posting fees, total need, target balance. To see the per-task `vendor / qty / duration / mult` math (the actual signal needed to localise an inflated total) testers had to flip `/fq debug toggle`, open the bank, let the popup compute, and pull lines from the debug log — a multi-step round trip that gated triage of every "gold pull is wrong" report on getting the player to reproduce live.

`Tracker:CalculatePostingFees` and `Tracker:CalculatePurchaseCosts` already returned `details[]` as their third value; `/fq debug gold` was discarding both. The command now receives them and prints a `--- Per-task fee breakdown ---` block above the aggregate, mirroring the format `AutoWithdrawGold` writes to the debug log when the popup runs:

```
[POST] Refulgent Copper Ore: vendor=0g x65 @ 24h (30%) = 2g
[POST] Sienna Ink:           vendor=5g x138 @ 24h (30%) = 207g
```

This is the line that would have made the FQ-117 reopen a one-message diagnostic instead of a multi-day back-and-forth. `/fq debug gold` is now self-contained — no bank visit, no toggle dance, no log file required.

`UI/SlashCommands.lua:838` (the existing aggregate block, unwrapped to also render `postDetails` and `buyDetails`).

### Cogworks-1.0 bump to v0.13.2 (closes #156)

A reporter (and a maintainer repro on the same character class) hit `ADDON_ACTION_FORBIDDEN` on right-click of profession knowledge tomes — `Glimmer of Midnight Jewelcrafting Knowledge`, `Flicker of Midnight ...`, etc. Equipment, tradegoods, and other right-clickable items were unaffected. The error blamed `cogworks` calling protected `UseContainerItem` from non-secure context.

Upstream root cause (Cogworks COG-30, [d46a07e](https://github.com/gezmodean-wow/cogworks/commit/d46a07e)): a defensive `StaticPopupDialogs = StaticPopupDialogs or {}` line at the top of `Cogworks-1.0/Scaling.lua`'s profile-popup block tainted the global. Any protected Blizzard call that later consulted `StaticPopupDialogs` (notably `UseContainerItem` on consumables, which checks for a "use this?" StaticPopup confirmation) inherited the taint. Items with no confirmation popup didn't traverse that path — explaining the asymmetry.

Cogworks dropped the global rebind; the per-key assignments below it (`StaticPopupDialogs["COGWORKS_NEW_PROFILE"] = …`) stay — that's the supported pattern. Bumped Cogworks library MINOR 18 → 19, `lib.version` 0.13.1 → 0.13.2.

FlipQueue picks up the fix via the `.pkgmeta` external pin bumped from `tag: v0.13.1` to `tag: v0.13.2`. The packager fetches the upstream library at build time, so no `Libs/Cogworks-1.0/` is committed to the FlipQueue repo. Two files differ between the pinned tags: `Cogworks-1.0.lua` (version bumps) and `Scaling.lua` (the rebind removal + comment).

### Files

```
M  .pkgmeta
M  CHANGELOG.md
M  RELEASES.md
M  TrackerBank.lua
M  UI/SlashCommands.lua
```

No schema change. No FQ-side behavior change beyond the postCap clamp + diagnostic improvement — Cogworks change is library-internal taint surface only.

## v0.12.0-alpha14

Architectural rebuild of the manage / automate model (#155). Closes the recurring class of bugs that #148 partially fixed (FQ-110 toeknee silent-skip, the alpha13 player-debug "Execute does nothing when triggers are off"), drops the bool/trigger conflation entirely, and adds a third action class for reagents that was previously folded into extras via a separate `depositIncludeReagents` bool.

### The new model

```
manageItems  (per-char tri-state override of global, existing — unchanged)
    │
    ├── todoMode      [auto / manual / disabled]   ← pull + deposit-to-do paired
    ├── extrasMode    [auto / manual / disabled]
    └── reagentsMode  [auto / manual / disabled]   ← split out from extras

manageGold   (same shape)
    │
    ├── goldWithdrawMode  [auto / manual / disabled]
    └── goldDepositMode   [auto / manual / disabled]
```

Action-mode semantics:

| Mode      | Drawer button | Popup section | Auto-fires on bank open |
|-----------|---------------|---------------|-------------------------|
| `auto`    | shown, works  | shown         | ✓                       |
| `manual`  | shown, works  | shown         | ✗                       |
| `disabled`| hidden        | hidden        | ✗                       |

Master `manageItems = false` forces all three sub-modes to behave as `disabled` regardless of stored value.

### Pause-vs-master split

`ns._automationPaused` no longer collapses `Tracker:InScope` to false. Pause is now a runtime override that forces every action's effective mode `auto → manual` without changing stored values; drawer buttons stay visible, popup sections still appear, manual Execute still works. The previous behavior (Pause hides every drawer item / gold button) was the un-numbered "Pause Automation disables manual access" bug.

### Schema #11 migration

`Migration.lua:RunMigrations` derives the new mode strings from the legacy bool flags so existing installs preserve their behavior:

| Old bool                                    | New mode key            | Mapping policy                                         |
|---------------------------------------------|-------------------------|--------------------------------------------------------|
| `autoPullBank` ∨ `autoDepositWarbank`       | `todoMode`              | either true → `"auto"`; both false → `"manual"`        |
| `autoDepositAll`                            | `extrasMode`            | true → `"auto"`; false → `"manual"`                    |
| `depositIncludeReagents`, `autoDepositAll`  | `reagentsMode`          | reagents=false → `"disabled"`; reagents=true ∧ autoAll=true → `"auto"`; reagents=true ∧ autoAll=false → `"manual"` |
| `autoWithdrawGold`                          | `goldWithdrawMode`      | true → `"auto"`; false → `"manual"`                    |
| `autoDepositGold`                           | `goldDepositMode`       | true → `"auto"`; false → `"manual"`                    |

Per-char overrides migrate the same way. Old keys are dropped post-derive so legacy code reads return nil rather than stale conflicting state. One chat line on first post-upgrade load explaining where to find the new controls.

### Code changes

- **`Tracker.lua`** — new `Tracker:GetActionMode(charKey, actionClass)` resolves master + per-char + global + pause-override into a single tri-state. `Tracker:InScope` reverted to master-only (no pause check). Planner gates (`BuildPullOps` / `BuildDepositOps` / `BuildExtraDepositOps` / new `BuildReagentDepositOps`) gate on `GetActionMode != "disabled"` instead of trigger bools. `WalkBagsInScope` now takes opKind = "extras" or "reagents" with proper Tradegoods filtering on each side. `ShowBankOpsPopup` payload includes per-section auto flags computed from action modes; reagents section added to the popup. The "FQ-132 suppress-after-pull-failures" guard now also clears reagent ops.
- **`TrackerBank.lua`** — executor trigger-gate drops. `AutoPullFromBank` / `AutoDepositToWarbank` / `AutoDepositExtraItems` / `AutoWithdrawGold` / `AutoDepositGold` all gate on `GetActionMode != "disabled"` only. Manual paths (popup Execute, drawer button) work without the save-restore bool-toggle hacks. New `Tracker:AutoDepositReagents` mirrors `AutoDepositExtraItems` for the reagents action class; same warbank-free-slot interrupt + scan refresh shape.
- **`UI/BankPopup.lua`** — new "Deposit reagents (N)" section. "Deposit to warbank" header renamed to "Deposit tasks" (matches the new "Tasks" terminology). Manual-Execute button label "Execute All (N)" — primary path runs everything; per-section Execute buttons deferred to a polish follow-up.
- **`UI/ContextDrawer.lua`** — drawer button visibility now keyed off `GetActionMode != "disabled"` per action class instead of master-only `InScope`. New `bankButtons.reagents` ("Deposit Reagents") drawer button next to "Deposit Extras"; row-1 layout grew from 4 to 5 columns. "Pull Items" → "Pull Tasks" / "Deposit Items" → "Deposit Tasks" rename. The DoPullGold / DoDepositGold save-restore-toggle hacks against the autoWithdrawGold / autoDepositGold gates removed (executor no longer needs the override). New `DoReagents` handler for the new button.
- **`UI/SettingsFrame.lua`** — new `CreateSettingsTriMode(parent, y, title, desc, key)` widget renders a 3-button segmented control (Auto / Manual / Off) for mode keys. Replaces the bool checkboxes for `goldWithdrawMode`, `goldDepositMode`, `reagentsMode`. The dim-when-master-off ApplyRowState wiring updates to use `:SetAlpha` directly on the tri-mode rows.
- **`UI/CharactersPage.lua`** — `FormatModeColumn` renders Auto / Manual / Off badges in the table. Per-char config drilldown's 5 action-mode rows now use a new `SetupModeBtn` 4-state cycler (nil / auto / manual / disabled) — Tasks / Extras / Reagents / Withdraw Gold / Deposit Gold. The Character Defaults bar's sub-checkboxes track `mode == "auto"` (auto ↔ manual toggle); reaching the disabled state from this bar isn't supported — players use the per-char drilldown.
- **`UI/SetupWizard.lua`** — RECOMMENDED defaults now use mode strings (`todoMode = "auto"`, etc.). New `BuildTriMode` setting type renders as a checkbox during setup (checked = auto, unchecked = manual); disabled is reachable post-install.
- **`UI/SlashCommands.lua`** — `/fq autopull` / `/fq gold` toggle the mode keys auto ↔ manual instead of the dropped bool keys. `/fq debug perf` and `/fq debug gold` print the new mode field names.
- **`UI/MainFrame.lua`** — Pull Bank action button drops the save-restore-`autoPullBank` hack now that AutoPullFromBank no longer gates on the trigger.
- **`DB.lua`** — defaults updated for the new mode keys; `depositIncludeReagents` / `autoWithdrawGold` / `autoDepositGold` constructor blocks removed (replaced by per-mode keys); `bankPopupCollapsed.reagents` backfill for installs predating the new section.
- **`Migration.lua`** — schema #11 migration as described above.

### Closes

- **FQ-110** — executor gate alignment closes the toeknee deposit-extras silent-skip and the alpha13 player-debug "Execute does nothing when triggers are off" symptom.
- **FQ-129** — settings architecture for gold management parity collapses into this rebuild's gold action classes.
- The un-numbered "Pause Automation hides drawer buttons" bug from the same player-debug session.
- **#155** is the implementation reference for this work.

### Files

```
M  CHANGELOG.md
M  DB.lua
M  Migration.lua
M  RELEASES.md
M  Tracker.lua
M  TrackerBank.lua
M  UI/BankPopup.lua
M  UI/CharactersPage.lua
M  UI/ContextDrawer.lua
M  UI/MainFrame.lua
M  UI/SettingsFrame.lua
M  UI/SetupWizard.lua
M  UI/SlashCommands.lua
```

### Known follow-ups (deferred to alpha15+)

- Per-section Execute buttons on the bank popup (each section gets its own Execute control beside the section header). The architectural wiring is in place — `Tracker:ShowBankOpsPopup` builds the per-section ops cleanly — the UI just needs the buttons added.
- True 4-state widget on the Characters page Defaults bar so the disabled state is reachable from there too (today the per-char drilldown is the only way to hit "disabled").
- Mixed-mode auto-fire in the popup (auto sections fire automatically on bank open, manual sections wait for click). Today the popup auto-fires only when ALL sections are auto.

## v0.12.0-alpha13

Republish of alpha12. The alpha12 tag (`ad5553f`) was correct in code but never reached CurseForge / Wago — the cogworks reusable verify-package workflow that gates our `release` job choked on Windows-style backslashes in `flipqueue.toc` path lines (`Libs\LibStub\LibStub.lua` etc.) when running on the Linux runner. WoW accepts both separators in TOC paths on every platform, so this never affected in-game testing — it's purely a CI script gap. Alpha13 ships the same content as alpha12 plus a `flipqueue.toc` forward-slash conversion that side-steps the gap defensively even now that cogworks-side `COG-29` (`d305d02 fix(COG-29): normalize backslash separators in TOC/XML path checks`) has landed on cogworks main and the `@main`-pinned verify workflow auto-picks it up.

### `flipqueue.toc` separator hygiene

All `Libs\X\X.lua`, `UI\X.lua`, and `IconTexture` `Interface\AddOns\…` references converted to forward slashes. Pure mechanical change — verified via `diff <(git show HEAD:flipqueue.toc | tr '\\' '/') flipqueue.toc`, no content or load-order drift. WoW's TOC parser handles both, so no behavior change in-game.

### Content carried forward from alpha12

(See alpha12 section below for the full breakdown — that tag's content is what alpha13 actually ships.)

- **#150 / COG-26** — Cogworks v0.13.1 bump (preventive game-menu-taint hotfix; closes the niduin pet-battle vector that alpha11's BankQueue gates couldn't reach).
- **#131** — Import-pipeline chunking finish (FP comma CSV / FP semicolon / tab-delimited chunked variants, plus `FPWebsiteScan` stage 1 chunking; closes zpectre's 4509-deal CSV freeze).
- Audit-only: `TodoList:GenerateTodoList` synchronous freeze on multi-thousand-deal auto-generate (tracked at #151 for v0.13.x).

### Files

- `flipqueue.toc` — `\` → `/` everywhere.
- `CHANGELOG.md` — alpha13 entry.

No other code changes from alpha12. The alpha12 tag remains on origin as a historical reference but has no published artifact.

## v0.12.0-alpha12

Twelfth alpha of v0.12. Two encapsulated changes share this release window: the **#150 / COG-26 Cogworks bump** (preventive game-menu-taint hotfix that also covers the niduin pet-battle vector that alpha11's own BankQueue gates couldn't reach), and the **#131 import-pipeline chunking finish** that closes zpectre's 4509-deal CSV freeze.

### #150 — Cogworks v0.13.1 bump (preventive, COG-26)

Niduin's 2026-05-03 fresh `v0.12.0-alpha11` log on #144 reproduced the pet-battle bag-click error with FlipQueue idle (only background Syndicator refreshes — no `BankQueue` activity in the visible 5-minute window). Conclusion: alpha11's `IsLockdownActive` gates closed the FlipQueue-originated taint path, but a separate vector remained — Cogworks v0.13.0's `ThemedMainFrame` / `Drawer` primitives installed an `OnKeyDown` handler that called `SetPropagateKeyboardInput(false)` on ESCAPE, tainting Blizzard's secure `ToggleGameMenu` path. Symptom: `ADDON_ACTION_FORBIDDEN AddOn 'cogworks' tried to call the protected function 'ClearTarget'`, plus silent breakage of game menu / logout / quit until `/reload`.

Upstream fix shipped as Cogworks v0.13.1 — drops the OnKeyDown handler in favor of `UISpecialFrames` registration, which Blizzard's secure code handles as a first-class consumer. Tracked at `gezmodean-wow/cogworks#26`.

`.pkgmeta` external bumped from `tag: v0.13.0` → `tag: v0.13.1`. Local `Libs/Cogworks-1.0/` synced from cogworks HEAD (which equals the v0.13.1 tag) so source installs (`vdev`) pick up the fix without waiting on a rebuild. New library files: `Debug.lua`, `Drawer.lua`, `Scaling.lua`, `SegmentedControl.lua`, `Slash.lua`, `ThemedMainFrame.lua`, `Toast.lua` — XML manifest at `Libs/Cogworks-1.0/Cogworks-1.0.xml` updated to reference all of them.

FlipQueue is not yet calling `cw:CreateThemedMainFrame` / `cw:CreateDrawer` (its own `UI/MainFrame.lua` still hand-rolls chrome), so the bump is preventive in the strict sense — but every install ships the buggy primitives via the bundled library, and a sibling cog (Tally) shipping v0.13.1 first would supersede the broken methods at LibStub load time only if it loaded first. Bundling v0.13.1 directly removes that ordering dependency.

### #131 — Import-pipeline chunking for all parse formats

zpectre's 2026-05-01 retest with a 4509-deal FlippingPal CSV froze the client past the watchdog window. Root cause: `Import:ParseChunked` (the async parse entry point used by `OnTextChanged` for inputs over 50KB at `UI/ImportPage.lua:177`) only routed FP-website pastes to a chunked variant. Every other format — FP comma CSV, FP-extractor semicolon CSV, tab-delimited — fell through to synchronous `Import:Parse`. zpectre's CSV path hit `ParseFPCommaCSV`'s synchronous loop over 4509 rows × `ParseCSVLine` (per-character regex) × `MakeItemKey` × `ParseGoldValue`. Single-frame execution → freeze.

#### Parse-stage chunking

Three new format-specific chunked variants in `Import.lua`, all yielding via `C_Timer.After(0)` between batches of `Import.CHUNK_SIZE` (100) rows:

- **`Import:ParseFPCommaCSVChunked`** — FP "Download CSV" route. Refactored `ParseFPCommaCSV` to use new file-locals `BuildFPCommaColMap` (header → column index map) and `ProcessFPCommaCSVRow` (per-line parse). Both sync and chunked variants share the row processor. Header / colMap parsing runs sync (cheap, O(1)).
- **`Import:ParseFPFormatChunked`** — FP-extractor semicolon CSV route. Refactored `ParseFPFormat` around new file-local `ProcessFPSemicolonRow`. The extractor format has no header to pre-parse, so the chunked version splits text into lines synchronously then loops in chunks.
- **`Import:ParseTabFormatChunked`** — Excel / table export route. Refactored `ParseTabFormat` around new file-locals `BuildTabColMap` and `ProcessTabRow`.

`Import:ParseChunked` dispatcher updated to mirror `Parse`'s full format-detection chain — PBS check, FP-website check, Auctionator-text check, FP-comma-CSV check, Auctionator-inline check, FP-semicolon check, tab-delimited check, generic-comma-CSV-with-known-headers check, plain-name fallback. Each check routes either to a chunked variant (yields per chunk) or, for naturally-bounded formats (PBS, Auctionator text/inline, plain names), to the sync parser wrapped in a uniform `CompleteSync(items)` helper that still fires `onProgress(total, total)` + `onComplete(items)` so the UI gets a consistent progress contract.

#### FPWebsiteScan stage 1 chunking (defense-in-depth)

The FP-website chunked path was already fixing the per-block `ProcessFPWebsiteBlock` loop (stage 3), but stage 1 of the scan — `FPWebsiteScan`'s line-classification loop — ran sync before chunking started. For a 45k-line / 4500-item full-region paste, ~6 regex matches per line × 45k lines = ~270k regex calls in one frame: tens to hundreds of ms of pre-roll before the first progress tick fires.

Refactored `FPWebsiteScan` into:

- File-local `FPWebsiteFindBlocks(allLines, allTypes)` — stages 2 + 4 (block finding + header-word filter), pure-Lua O(n) cheap loops, no regex. Stays sync.
- File-local `FPWebsiteScanChunked(text, onComplete)` — stage 1a (gmatch line split, sync — C-implemented and fast) + stage 1b (per-line classify in chunks of `SCAN_CHUNK_SIZE = 500`, yielding via `C_Timer.After(0)`), then chains into `FPWebsiteFindBlocks` sync at the end.
- `Import:ParseFPWebsiteChunked` updated to call `FPWebsiteScanChunked` first, then chunk per-block stage 3 inside the scan's `onComplete` callback.

Net: FP-website chunked parse now yields across both regex-heavy stages. Sync `Import:ParseFPWebsite` continues to use the sync `FPWebsiteScan` path for small inputs (`Parse` direct entry).

#### Audit: `TodoList:GenerateTodoList` (deferred)

`TodoGenerator.lua:729` `GenerateTodoList` runs synchronously after auto-import when "Auto-generate To-Do" is checked. Audit findings on a 4500-deal input:

- Pre-loop: `BuildItemPool()` iterates inventory; `CountInventoryForDeal` per-deal pre-compute when `lowInventory` / `highInventory` allocation key is in play.
- Main loop (~478 lines, runs N times for N deals): `FindPoolMatch(pool, deal, poolRemaining)` is O(pool); `FindBestAssignment` iterates characters; 2–3 separate `for charKey, charData in pairs(ns.db.characters)` lookups per deal in cross-realm branches; per-deal TSM API calls (`GetItemAuctioningOp`, `IsBelowThreshold`).

For 4500 deals × ~500 pool × ~15 chars × multiple per-deal lookups + TSM internals, estimated tens of seconds of synchronous CPU work. **Not in zpectre's reproducer's path** (he hits the parse-side freeze first; auto-generate is opt-in), so deferred to follow-up #151 — slated for v0.13.x scope alongside the cogworks primitives migration umbrella (#143).

### Files

- `.pkgmeta` — Cogworks external `tag: v0.12.0` → `tag: v0.13.1`.
- `Libs/Cogworks-1.0/*` — synced from cogworks v0.13.1 (MINOR 18). New files: `Debug.lua`, `Drawer.lua`, `Scaling.lua`, `SegmentedControl.lua`, `Slash.lua`, `ThemedMainFrame.lua`, `Toast.lua`. Updated: `Cogworks-1.0.lua`, `Cogworks-1.0.xml`, plus minor refreshes to `API.lua`, `Forms.lua`, `MiniView.lua`, `ReorderableList.lua`, `Tree.lua`.
- `Import.lua` — `ParseFPCommaCSVChunked`, `ParseFPFormatChunked`, `ParseTabFormatChunked` added. `FPWebsiteScanChunked` + `FPWebsiteFindBlocks` added (split out from `FPWebsiteScan`). `ParseFPCommaCSV`, `ParseFPFormat`, `ParseTabFormat` refactored around new row helpers (`ProcessFPCommaCSVRow`, `ProcessFPSemicolonRow`, `ProcessTabRow`). `Import:ParseChunked` dispatcher rewritten to mirror full `Parse` format detection.
- `CHANGELOG.md` / `RELEASES.md` — alpha12 entries.

No schema migration. No save-data shape change.

## v0.12.0-alpha11

Eleventh alpha of v0.12. Three encapsulated features bundled into one alpha — they share a release window. The big one is **#148** (settings architecture rebuild with the scope-vs-trigger split), which closes FQ-110's toeknee branch as a side effect by unifying the planner and executor on a single `Tracker:InScope` predicate. **#147** adds combat / pet-battle lockdown gates to BankQueue to address niduin's #144 taint report. **#146** ships the About page + version-surfacing pass for tester triage.

### #146 — About page + version surfacing

New `UI/AboutPage.lua` standalone sidebar tab (between Settings and Tutorial) with banner, version (large, prominent), Cogworks-1.0 MINOR + WoW build sub-line, credits, four selectable URL boxes (GitHub / Discord / CurseForge / Wago), and a "Copy diagnostics" button that pipes through the existing `UI:ShowExportPopup`. Replaces the old in-settings credits/version block (`UI/SettingsFrame.lua:1709-1764` removed).

`/fq version` slash command added — chat-prints `FlipQueue v0.12.0-alpha11 (Cogworks-1.0 MINOR <N>)`. Every `/fq debug *` output dump now prefixes with `=== FlipQueue v… — <command> ===` via the new `DumpHeader` helper at the top of `UI/SlashCommands.lua`. SV backups (`_debugLogSearch`, `_debugPerf`, etc.) capture the version line in their first row. The DebugConsole window's title bar reads `FlipQueue Debug Console — vX`, and its **Copy debug log** button now prefixes the export with version + timestamp so bug-report pastes self-identify.

`Core.lua:7-15` strips a leading `v` from the toc-substituted version (some packager toolchains include it from the git tag). Display code can now always prepend `v` cleanly without producing `vv0.12.0-alpha10`. Source installs (where `@project-version@` substitution didn't run) show `vdev` and the About page surfaces a yellow warning.

### #147 — Pet-battle / combat lockdown gates in BankQueue

Niduin reported (#144) `[ADDON_ACTION_FORBIDDEN] AddOn 'flipqueue' tried to call protected function 'UNKNOWN()'` chained through `ContainerFrameItemButton_OnClick` → `UseContainerItem` after a pet battle. Root cause: `pcall(C_Container.UseContainerItem, srcBag, srcSlot)` at `BankQueue.lua:499` runs in non-secure timer continuation context. `UseContainerItem` is a protected function — calls from non-secure code taint downstream state even when wrapped in `pcall`. Pet battles raise UI lockdown sensitivity, so the latent issue surfaced on the first hardware-event bag click after battle exit.

New `IsLockdownActive()` helper (`InCombatLockdown` + `C_PetBattles.IsInBattle`), a deferred-call queue, and an event listener frame for `PLAYER_REGEN_ENABLED` + `PET_BATTLE_CLOSE`. Drains on clear with a chat banner. Two gates installed:

- **ProcessSync entry-gate** — defers the entire call when locked, re-fires from the head once both lockdowns clear.
- **IssueOne mid-flight gate** — aborts ops if lockdown begins during execution; the existing retry mechanism handles re-issue when lockdown clears within the retry window.

Path (a) chosen — NOT a `SecureActionButtonTemplate` migration (would require a hardware-event click per move and break the auto-bank-open chain). Cursor hardening (`pcall(ClearCursor)` immediately before `UseContainerItem`) was already at `BankQueue.lua:498` and stays.

### #148 — Settings architecture rebuild: Manage Items / Manage Gold masters with scope/trigger split

The recurring class of bugs FQ-117 / FQ-110 / FQ-110-toeknee all stem from a single architectural seam: the per-action `auto*` flags were asked to mean both "is FlipQueue allowed to manage X for this character?" (scope) and "should it auto-fire on bank open?" (trigger). The two axes are independent — players want master scope ON with selective auto-fire — but the legacy model conflated them, producing the recurring "FlipQueue did something I didn't expect" reports.

#### Two masters

```
manageItems  — Authority for FQ to move items between bag and warbank/bank
manageGold   — Authority for FQ to move gold between bag and warbank
```

Per-character override on the Characters page tri-state. Per-action triggers (`autoPullBank`, `autoDepositWarbank`, `autoDepositAll`, `autoWithdrawGold`, `autoDepositGold`) become independent toggles under their parent master.

#### Combination matrix

| Master | Trigger | Behavior |
|---|---|---|
| OFF | n/a | Action does not exist. Section hidden from popup. Drawer button hidden. |
| ON | OFF | Action available — appears in popup, requires manual Execute. Drawer button works. |
| ON | ON | Action auto-executes on bank open. Drawer button still available. |

#### Architectural consolidation

- **`Tracker:InScope(charKey, kind)`** — single predicate, single source of truth. Both planners and executors funnel through it. Cannot disagree.
- **`Tracker:WalkBagsInScope(opKind, cb)`** — single bag-walk helper. Both `BuildExtraDepositOps` (planner) and `AutoDepositExtraItems` (executor) walk the same bag set under the same reagent / soulbound rules. The previous mismatch (`ALL_PLAYER_BAGS = {0,1,2,3,4,5}` vs `INVENTORY_BAGS = {0,1,2,3,4}`) is structurally impossible — closes FQ-110 toeknee root cause.
- **Per-section auto-fire** — `Tracker:ShowBankOpsPopup` computes `itemsAuto` and `goldAuto` separately, passes them in the popup payload alongside combined `isAuto`. (Separate per-section Execute buttons deferred to alpha12 polish.)

#### Migration #10

```lua
manageItems = (autoPullBank or autoDepositWarbank or autoDepositAll) and true or false
manageGold  = (autoWithdrawGold or autoDepositGold) and true or false
```

Existing per-action flags preserve their values — they become the trigger toggles under their master. One chat line on first post-upgrade load: `[FlipQueue] Settings layout updated — see /fq settings or /fq about for details — your existing behavior is unchanged.`

#### Settings page restructure

Old "FlipQueue manages…" section + "Bank & Warbank" section removed. Replaced with:

- **General** (existing) — gains the relocated "Show Tutorial Again" + "Run Setup Wizard" buttons.
- **Item Management** (new) — Manage my items master at top → Move reagents → Deposit to bank when warbank is full → Combine partial stacks → Items moved per batch.
- **Gold Management** (new) — Manage my gold master at top → Warband Miser banner (when applicable) → Withdraw gold from warbank → Maximum gold to withdraw → Deposit extra gold → Default gold per character.

`sectionOrder` updated to `{ "automation", "items", "gold", "auctionhouse", "notifications", "miniview", "data", "deletedchars", "multiaccount" }`. New `items` and `gold` sections default to expanded.

When a master is OFF, every row in its section dims to 0.4 alpha and becomes non-interactive. Master toggles trigger immediate refresh of the drawer, characters page (when visible), and settings page.

#### Characters page Global Defaults bar rebuild

Renamed "Global Defaults:" → "Character Defaults:" so it isn't conflated with global settings page. Layout:

```
Character Defaults: [☑ Items | Pull Deposit Dep.All]  [☑ Gold | Withdraw Deposit]  …  Show Hidden Show Deleted
```

Items group sits behind a soft-blue backdrop with a light-blue accent line. Gold group sits behind a soft-amber backdrop with a brass accent line. Vertical light-grey separator between the two groups. When a master is OFF, sub-checkboxes hide and a centered `(disabled)` label appears in the colored space.

Per-character config panel (per-character row click-through) gets two new tri-state rows above the existing per-action overrides — Items master + Gold master — with the existing five rows (Pull / Deposit / Dep. All / Withdraw Gold / Deposit Gold) nested beneath.

#### Drawer button visibility

Item buttons (Pull / Deposit / Pull Saleable / Deposit Extras) hide when `manageItems` is OFF. Gold buttons (Withdraw / Deposit gold) hide when `manageGold` is OFF. Hide, not disable — keeps the drawer surface clean for players who turned a master off intentionally.

### Bonus polish from in-game testing

- `vv0.12.0` doubled-v fix in version display: `Core.lua` strips any leading `v` so all `"v" .. ns.VERSION` display sites produce a single `v` prefix.
- DebugConsole title bar shows version (`FlipQueue Debug Console — vX`).
- DebugConsole's "Copy debug log" export prefixes with version + capture timestamp.
- The settings sectionOrder bug (`manage` not in `sectionOrder` list) that caused the masters block to overlay "General" — fixed by adding the new section keys to the order.

### Files

- New: `UI/AboutPage.lua` (~280 LOC).
- Touched: `Core.lua`, `DB.lua`, `Migration.lua`, `Scanner.lua`, `Tracker.lua`, `TrackerBank.lua`, `BankQueue.lua`, `UI/CharactersPage.lua`, `UI/ContextDrawer.lua`, `UI/DebugConsole.lua`, `UI/MainFrame.lua`, `UI/SettingsFrame.lua`, `UI/SlashCommands.lua`, `flipqueue.toc`.
- Schema bumped to v10 (silent migration).

### Issues opened during the alpha11 cycle

- #145 — bundle item-reference cache to bootstrap name→itemID resolution (greenlit for v0.13.0).
- #149 — per-character custom gold balance overrides in character settings (slated for v0.13.x alongside FQ-129 Phase 5/6).

## v0.12.0-alpha10

Tenth alpha of v0.12. Two correctness fixes surfaced from player triage on alpha9: the bank popup planner was queueing "Deposit Extras" ops even when the player had that setting turned off (FQ-110 root cause for Zong's repeat reports), and the Transform page's AAA JSON output was silently dropping items whose names hadn't resolved to IDs (the never-fully-closed FQ-109 partial-output symptom, now filed as FQ-141).

### FQ-110 extras planner gated against `autoDepositAll`

`Tracker:ShowBankOpsPopup` was unconditionally calling `BuildExtraDepositOps` regardless of the per-character `autoDepositAll` setting. The executor's `AutoDepositExtraItems` correctly skipped when the setting was off, but the planned extras still flowed into the popup's `totalOps` — so `ShowCompletionSummary`'s tally-drift detector saw `completed << total` and force-filled the bar to "complete" without the player ever knowing the planned ops never ran.

Zong's 2026-05-02 log gave the clean reproducer:

```
Bank popup: 1 pulls, 1 deposits, 7 extras, withdraw=0 deposit=0
... 1 pull executes, 1 deposit executes ...
ShowCompletionSummary: tally drift completed=2 failed=0 total=9 — forcing bar full
```

He had `autoDepositAll` explicitly off; the 7 extras were planner ghosts.

Fix mirrors the FQ-117 alpha3 pattern (`autoWithdrawGold` / `autoDepositGold` gating on the gold ops) — when `autoDepositAll` is off, `extraOps` becomes `{}` at planner time and never enters `totalOps`. The same drift could affect pulls / deposits if `autoPullBank` / `autoDepositWarbank` disagree with planner output, but no current report shows that mode — leaving those gates for if/when reproducers surface (toeknee's older `completed=0 failed=1 total=2` shape may be that case).

The manual "Deposit Extras" button on the bank tool drawer is a separate code path that calls `BuildExtraDepositOps` directly and is unaffected by this gate.

### FQ-141 AAA dropped-item count surfaced

`Transformer:OutputAAAJSON` resolves each item's numeric ID via `resolveItemID`; items where neither `item.itemID` is numeric nor `item.itemKey` starts with a numeric token were silently skipped from the output map. The AAA output area showed "Items (N)" with no indication that more items were lost — the original FQ-109 "only transforms some of the items" report from 2026-04-26 was hitting exactly this. The alpha5 metadata-preservation fix (`618daea`) routed Auctionator imports through `Import:ParsePBS` so per-item metadata survived, but the drop in `OutputAAAJSON` itself was never surfaced.

Adds `droppedItems` / `droppedPets` counters to `OutputAAAJSON`'s return tuple. `DoTransform` renders "X dropped" in red next to the item / pet count labels when non-zero. When drops exist AND the existing Deep Search button is currently visible (TSM realm data or Auctionator DB present), the item label appends "click Deep Search to resolve" so the player can connect the AAA drop count to the existing remediation.

The Deep Search button itself was already wired for paste-source unresolved items — it works the same for Auctionator sources. This fix is purely about visibility: surfacing what was previously silent and tying the drop count to the existing one-click fix.

Other callers of `OutputAAAJSON` (`PresetTSMToAAA`, `PresetInventoryToAAA`) ignore the new return values, so the signature change is backward-compatible.

## v0.12.0-alpha9

Ninth alpha of v0.12. Headline fix is the deeper FQ-131 chunked-parse rewrite — alpha8's prior chunking covered SAVE / PREVIEW but left the parse itself synchronous, and zpectre confirmed that 4509 FP-website items still froze the client. Plus a `/fq debug log` diagnostic for ledger-discrepancy triage and a Cogworks-1.0 library bump that pulls in the Phase A/B/C UI primitive set and Phase D suite-settings persistence.

### FQ-131 chunked parse for full-region FP-website pastes

Earlier work (`1524cee`) chunked the SAVE and PREVIEW stages of the FP-website import path. Stage 3 (per-block field extraction, the heaviest stage) was still O(N) synchronous and continued to freeze the client on full-region pastes. zpectre reported 4509 items still crashed alpha8.

Refactor (`cafb213`):
- Extract `FPWebsiteScan` (line classification + block finding) and `ProcessFPWebsiteBlock` (per-block field extraction) as internals shared by sync and chunked entry points.
- Add `Import:ParseFPWebsiteChunked` which yields between batches of `CHUNK_SIZE` blocks via `C_Timer.After(0)`. Stages 1-2 still run synchronously (cheap, ~22k regex iterations); stage 3 gets chunked.
- `Import:ParseChunked` top-level dispatcher detects FP-website format and routes to chunked, falls back to sync `Parse` for other formats.
- `ImportPage.OnTextChanged` switches to `ParseChunked` when input exceeds `PARSE_CHUNK_THRESHOLD = 50000` chars (~330 FP-website items). Status banner reads "Parsing N / M items..." and the progress bar ticks per chunk so the player has feedback during the multi-second parse window.

Smaller pastes keep the synchronous path so preview shows up instantly without a progress-bar flash.

### `/fq debug log <name|itemID>` for ledger-discrepancy triage

New diagnostic slash command (`0c87153`). Dumps every `ns.db.log` entry whose itemKey/itemID/name matches the search term, with full metadata: itemKey, charKey, targetRealm, auctionStatus + saleOutcome + endReason, postedAt + qty + price, soldAt + soldPrice, collectedAt, expiresAt, `_tsmReconciled` flags, isRecovered, failReason, postAttempts, totalFeesSpent.

Use case: Item Research shows N sales, the player believes N is wrong. Run `/fq debug log <name>` to dump the actual entries Item Research counted, then compare against memory / TSM accounting CSV to figure out whether the entries are real posts, reconcile phantoms, sync-replay duplicates, or recovered AH state. Output saved to `FlipQueueDB._debugLogSearch` as backup if the export popup is closed before copy.

### Cogworks-1.0 library bump v0.10.0 → v0.12.0

Two MINOR releases of the shared core library landed since FlipQueue last pinned its external. `.pkgmeta` external pin moves from `v0.10.0` to `v0.12.0`, and `flipqueue.toc` declares `## SavedVariables: CogworksSharedDB` per the v0.12.0 suite-settings persistence model. FlipQueue continues to own `FlipQueueDB`; Cogworks owns `CogworksSharedDB`.

What this pulls in (no FlipQueue-side consumption yet — these unblock future migrations):
- **Phase A/B/C UI primitive set** (cogworks v0.11.0): Forms, Sections, TabPanel, MiniView, Wizard, Tree, ReorderableList, plus per-module load guards so older vendored copies in sibling cogs no longer clobber newer methods.
- **Phase D suite-settings persistence** (cogworks v0.12.0): `CogworksSharedDB` shared SV with profile system, `lib:RegisterScalingFrame` for automatic position/size persistence (the FQ-139 unblock), `lib:CreateUIScalingSettingsBlock` drop-in scaling settings panel.

No behavior change visible from the bump alone. Migrations of FlipQueue's existing UI scaffolding onto these primitives will land in subsequent alphas.

## v0.12.0-alpha8

Eighth alpha of v0.12. The headliner is the FQ-138 fix — TSM's posting queue no longer occasionally skips items when FlipQueue is loaded. Plus a coordinated improvement to the FQ-137 cluster (smart defaults for the auto-scan setting), a relog-hitch fix, a loading banner on the Characters page, and the dual changelog / storefront restructure for a sustainable CurseForge / Wago workflow.

### TSM post-skip fixed (FQ-138)

TSM Post Scan was occasionally jumping over items in its queue when FlipQueue was loaded. Disabling FlipQueue made the skipping stop. Root cause: FlipQueue's post-result frame fired `RequestOwnedAuctionsRefresh` on every `AUCTION_HOUSE_AUCTION_CREATED` event — including TSM-initiated posts. The forced `QueryOwnedAuctions({})` 1 second later competed with TSM's expected event sequence, consuming a slot in Blizzard's AH server throttle and producing a delayed/duplicate `OWNED_AUCTIONS_UPDATED` that confused TSM's posting state machine into thinking the next item was already posted.

Fix: a new `_fqInitiatedAction` flag set right before our `PostItem` / `PostCommodity` calls, cleared by the matching server event. The post-result frame's listener only fires the requery for FlipQueue's own posts now. TSM-initiated posts pass through silently. A 3-second safety timer clears the flag if the post fails without firing either `AUCTION_HOUSE_AUCTION_CREATED` or `AUCTION_HOUSE_SHOW_ERROR`.

The Cancel path is unaffected — `RequestOwnedAuctionsRefresh` after `AuctionPost:CancelAuction` is FlipQueue-initiated by construction, and TSM's Cancel Scan calls `C_AuctionHouse.CancelAuction` directly without going through our flow.

### Auto-scan smart default + cache-aware skip (FQ-137 cluster, continued)

Three coordinated changes targeting the root cause of the FQ-137 reports — players running TSM, Auctionator, *and* FlipQueue all issuing `SendSearchQuery` calls in parallel against Blizzard's shared global rate limit, stacking delays into the minutes range.

- **Schema migration #9** — when TSM or Auctionator is loaded at the time of migration, force `ahAutoScanOnOpen = false`. One-shot, so players who explicitly re-enable later won't get reset on subsequent migrations. Surfaces a chat note explaining the change so the player isn't surprised that their setting flipped.
- **AuctionAutoScan AH_SHOW path** now passes `math.huge` as the freshness ceiling to `ScanQueue`. The auto-scan only queries items with NO cache entry — persisted scan-cache entries from prior sessions count as good-enough for the auto path, instead of re-querying everything older than `DEFAULT_FRESH_AGE_SEC = 1800`. TSM/Auctionator's passive scans naturally refresh stale entries when the player runs their own scans, and the manual Scan To-Do / Scan All buttons keep the original 30-min freshness behavior.
- **Settings tooltip** rewritten to flag the parallel-scan cost prominently in red — "Strongly recommended OFF if you also use TradeSkillMaster or Auctionator" — and explain that the passive listener still reads prices from other addons' scans.

Combined, these eliminate the cold-cache storm that hit Niduin on every relog: even with the setting on, persisted cache entries skip the `SendSearchQuery` queue, and new installs / fresh players with TSM see the setting default to off automatically.

### Relog hitch fix: yielded bulk-project + halved `C_Item.GetItemInfo` calls

A player with many alts pays a multi-second frame hitch on every character switch / `/reload` as `BulkProjectKnownAlts` walks every Syndicator-known character and projects each one's full inventory synchronously. Two changes:

1. **`BulkProjectKnownAlts` now drains its work list one alt per frame** via `C_Timer.After(0, ...)` instead of looping synchronously. Each alt's projection still walks bags/bank, calls `C_Item.GetItemInfo` per unique item, runs `EnrichDealsFromInventory`, and emits a Sync delta — but spreading the work across frames keeps the relog snappy. The full alt picture lands a fraction of a second later instead of in one giant hitch.

2. **`FoldContainerSlots` was calling `C_Item.GetItemInfo` twice per unique slot** (once for `bindType` at index 14, once for `name` at index 1). Combining into one call halves the API hit count during projection, compounding with #1 for relog cost.

The existing 30s `lastBulkProjectAt` debounce is preserved — a relog within 30s still skips the bulk pass since Syndicator's data hasn't changed.

### Characters page: loading banner during bulk-project

Surfaces async work the player would otherwise not see. With the yielded `BulkProjectKnownAlts` draining one alt per frame, the Characters page would show partial / stale alt inventory data with no indication anything was happening. Now an amber banner with a progress fill sits above the Global Defaults bar reading "Loading inventory data: X / Y characters" while the pass runs, and clears when it completes.

`Scanner` exposes status via `ns.Scanner._bulkProjectStatus` and a public `GetBulkProjectStatus()` accessor. After each alt projection, Scanner calls `UI:RefreshCharactersLoadingBanner()` so the banner ticks per-frame without rebuilding the whole table. When idle, the bar pins back to the container top so non-loading sessions look unchanged.

Establishes the precedent for surfacing async work elsewhere — same pattern will apply to the mini view eventually.

### Sustainable CurseForge / Wago workflow

Three structural changes for keeping project-page artifacts in sync without per-release manual labor:

1. **`RELEASES.md` — new player-facing changelog.** Plain language, no commit references or file paths. Replaces `CHANGELOG.md` as the `manual-changelog` source in `.pkgmeta`, so the project-page changelog tab stops getting engineering jargon bled into it.

2. **`CHANGELOG.md` stays as-is** — full alpha-by-alpha engineering record, internal terminology, file:line references. Used during development; not pushed to project pages.

3. **`docs/storefront/`** — versioned source of truth for project-page materials that have no API to push them: `description.md`, `short-description.md`, `screenshots/`, future `faq.md`. CurseForge has no description-update API ([CF-I-6366](https://curseforge-ideas.overwolf.com/ideas/CF-I-6366) in "Future consideration" since 2024-06), Wago similarly. Hand-pasted to dashboards on **public releases only** — alphas leave the project page on whatever the last public release described.

`CLAUDE.md` and the working memory get a `Release artifacts` block documenting the convention so future sessions know which file to update when.

## v0.12.0-alpha7

Seventh alpha of v0.12. Hardening pass after alpha6 — small fixes and a new diagnostic command for triaging player-reported slowness.

### Better diagnostics for "FlipQueue feels slow" reports

A new `/fq debug perf` slash command bundles everything we need to triage a perf complaint into one copy-pasteable text dump: per-addon CPU and memory (when WoW's script profiler is on), FlipQueue's internal scale numbers (character / inventory / log / to-do / scan-cache / inflight scan counts), the perf-relevant settings (`ahPostingEnabled`, `ahAutoScanOnOpen`, `autoScan`, `tsmEnabled`), the current runtime state (AH open, Syndicator ready, TSM API available, multi-account sync linked), and a list of which AH-adjacent addons are loaded.

To capture a CPU profile, the player runs `/console scriptProfile 1`, `/reload`, reproduces the slowness for ~30 seconds, then `/fq debug perf`. The resulting export tells us whether FlipQueue is actually the hot path or whether another addon is — without us having to guess. Output is also saved to `FlipQueueDB._debugPerf` as a backup if the popup is closed before copying.

### TradeSkillMaster stays optional, even mid-session

The auction-house posting price resolver had a defensive gap — the inner `EvalLevel` and `EvalCanonical` closures indexed `TSM_API.GetCustomPriceValue` *before* `pcall` wrapped the call, so if TSM unloaded mid-session the index would throw past pcall instead of getting caught. Hardened the closures to early-exit on a nil `TSM_API`. The intended invariant — TSM is `OptionalDeps`, never required at runtime — is now properly enforced.

### Install: dependency relations registered with CurseForge / Wago

A player reported installing FlipQueue and getting a "Missing Dependencies" error from the WoW client. The toc has always declared `## Dependencies: Syndicator`, which is what blocks the load — but we never told CurseForge to register Syndicator as a required dependency on the project page, so the CurseForge App didn't auto-install it alongside FlipQueue. Now declared in `.pkgmeta` (`required-dependencies: syndicator`, `optional-dependencies: auctionator`, `tradeskill-master`) so future uploads register those relations automatically. The CurseForge project page Relations were also set manually so existing alpha6 builds get auto-install retroactively.

### Interface version: current retail only

Dropped 12.0.1 from the supported Interface set; FlipQueue now targets 12.0.5 only. 12.0.1 was the initial War Within launch and is no longer relevant. Subsequent versions will keep the toc Interface line at the current retail patch.

## v0.12.0-alpha6

Sixth alpha of v0.12. The big fix is auction house performance when running alongside TSM. Plus a shopping-list ceiling fix for FlippingPal-imported buy tasks.

### AH scanning and posting: FlipQueue stays out of TSM's way

Players running FlipQueue with TSM reported AH scanning and posting were "very slow" — to the point that disabling FlipQueue alone made the slowness go away. The problem was that FlipQueue was doing its own work in parallel with TSM's: every time you opened the AH, FlipQueue ran its own price scan on top of TSM's, and every post or cancel triggered redundant rescans of your bags and to-do list. Two addons hammering the AH at the same time made both of them feel sluggish.

The fix is to step back. FlipQueue now does the minimum on AH open — just the things its own UI needs — and leaves TSM alone unless you specifically ask FlipQueue to scan. Posting and cancelling no longer kick off duplicate work in the background, and your inventory only gets re-broadcast to your other accounts when something actually changed.

If you liked the old behavior — FlipQueue auto-scanning the AH the moment you opened it — flip **Settings → Auction House → "Auto-scan inventory when the Auction House opens"** back on. It's *off by default* because it makes a real perf trade-off when running with TSM, but it's there for players who want it. With auto-scan off, the **Scan To-Do** and **Scan All** buttons in the AH drawer are your manual "give me fresh AH prices now" triggers — use them whenever you want a refresh.

The auction house also opens faster now — the per-character to-do refresh and TSM-rejection check happen a fraction of a second after the AH window comes up instead of blocking it.

### Shopping-list max price: inclusive of the gold value you typed

A buy task with a target price of 200g was generating an Auctionator search with `maxPrice` set to a strict ≤200g. That excluded any listing priced at 200g 0s 1c through 200g 99s 99c — exactly the listings you'd want to snipe at a 200g ceiling. The shopping-list export now treats the entered gold value as inclusive of "anything below the next whole gold," so a 200g target accepts up to 200g 99s 99c but won't bleed into 201g.

### New debug command

- **`/fq debug parsegold <string>`** (or no arg for a self-test) — trace how FlipQueue parses a gold string. Covers German/EU thousands separators (`1.500g`, `2.000g`), k/m abbreviations, color codes, and degenerate inputs. Useful for diagnosing locale-specific buy-task parse failures without needing an EU client.

## v0.12.0-alpha5

Fifth alpha of v0.12. One fix, narrow scope: the Transform page's "Auctionator" output produces a format Auctionator can actually import again, and Auctionator-imported lists round-trip correctly through TSM-info enrichment.

### Auctionator → Transformer → Auctionator now actually round-trips

Two long-standing bugs in the Auctionator-list path were biting the same workflow:

- **The "Auctionator" output format was a plain-text list** (`--- ListName\nName\nName`) that Auctionator could not import. The real wire format is `ListName^"Item1";;;;;;;;;;;;;qty^"Item2";;;;;;;;;;;;;qty` (14 semicolon-separated fields per item, `^` between items). Rewrote `OutputAuctionatorList` to emit the valid wire format, preserving the exact-match flag and quantity from imported metadata. For full constraint round-trip (ilvl filters, quality, tier), use the `PBS` output instead.

- **Auctionator-imported items were stripping per-item metadata** during the import step — the parser only captured the name and threw away quantity, exact-match, ilvl filters, and quality. The discarded data was a problem in two ways: (a) the round-trip lost everything except the name, and (b) the resulting `itemKey` was set to the item name as a string, so downstream TSM price lookups (which expect an itemID-prefixed key like `12345;...`) silently fell through, leaving items without TSM info even when TSM had data for them.

Now the import path routes the Auctionator search strings through `Import:ParsePBS`, which already knew how to parse all 14 fields. The full per-item metadata flows into the items' `_pbs` field, name resolution fills `itemKey` from the resolved itemID via the name→ID map (which includes TSM's persistent item DB), and TSM prices populate as expected.

## v0.12.0-alpha4

Fourth alpha of v0.12. Bank operations get a determinate countdown timer between moves, deposit progress finally ticks per move (previously stuck for ~1s per batch), large pulls no longer "lose" tail items to a verify race, and a cross-session safety net keeps auto-deposit from undoing a failed-pull retry. Plus a Cogworks minimap canary, opt-in profit-% abbreviation in DealFinder, locale-aware gold parsing for German FlippingPal, and a chunked importer that handles full-region pastes without freezing the client.

### Bank operations: countdown timer instead of cycling animation

The thin sub-bar under the main progress bar used to fill 0 → 100% over the wait, repeatedly cycling for fast pulls. It now shows a numeric countdown (`0.4s Verifying moves`) and disappears immediately when the wait resolves early — no more cycling for waits under 150 ms. For variable-duration waits (the inter-move bag-update wait), the countdown shows as a maximum (`≤ 0.1s Waiting for bag update`); for fixed waits (verify, retry, panel-settle, inter-batch), it shows the exact remaining time.

### Bank operations: deposit bar updates per move, not per batch

The deposit phase used to look frozen for ~1 second between batches, then jump 5 items at once when verify settled. Now each successful move ticks the bar individually, matching how the pull phase already worked. A heartbeat fires for the inter-batch delay too, so the gap between batches has visible "Next batch" feedback instead of dead air.

### Long pulls: tail-of-pull items no longer "vanish"

Pulling 80+ items at once could end with `1 pull(s) failed: <item>` reported even though the item actually moved — most often surfacing as a repeatable failure on a specific item near the end of the queue. The cause was a verify race: the last few items were issued, but Blizzard's bag cache hadn't caught up to their `BAG_UPDATE_DELAYED` events before our 0.4s verify deadline ran. The verify saw "didn't move" and queued a retry; on retry, the source slot was empty (proving the move did go through), but the addon's old code treated empty-on-retry as "vanished" — uncounted in either successes or failures, leaving a permanent tally drift.

Now empty-on-retry is recognized as a delayed success and counted accordingly. The completion summary lands at the right total without the "forcing bar full" workaround, and items at the tail of large pulls no longer falsely show as failed.

### Cross-session retry: auto-deposit suppressed after a partial pull failure

If a pull op fails (rare, usually Blizzard's rate limiter on very high-volume sessions), the to-do task stays pending and your next bank reopen retries it automatically. But the auto chain ALSO ran the deposit phase on reopen, which silently shoveled newly-pulled-but-not-yet-listed items back to the warbank before the player could intervene.

After a session ending with any pull failures, FlipQueue now suppresses auto-deposit on the next bank open and prints a yellow chat banner: `"N pull(s) failed last session — auto-deposit suppressed for this open so retries can finish first."` One-shot — clears on that reopen so subsequent visits behave normally.

### Per-character gold management overrides

The Characters page now has two new tri-state rows for gold management — **Withdraw Gold** and **Deposit Gold** — mirroring the existing item-flag toggles (Pull, Deposit, Deposit All). Each character can override the global gold settings independently, so you can let FlipQueue manage gold for the account but turn it off for a specific alt without touching the global flags. Defaults to "use global" — no behavior change for existing setups.

### DealFinder profit %: opt-in abbreviation for crazy-high values

For cheap items where DealFinder finds extreme deal multiples (`+12,500%`), the percentage was technically accurate but visually overwhelming. A new opt-in setting under DealFinder's config (`Abbreviate large profit %`) collapses 4-digit-plus values to `1.5k%`, `25k%`, `2.5M%` form. Off by default; flip it on if you sell deep-value items where the percentages routinely run into the thousands.

### Posted item logs: bonus IDs preserved

When an item with bonus IDs (most modern gear) was posted via the FlipQueue button, TSM, or the Blizzard UI, the log entry was storing the stripped base form (`itemID;;`) instead of the full variant key (`itemID;bonusIDs;modifiers`). This collapsed all variants of the same item into one log row — a Nullstrider's Boots ilvl 253 sale and an ilvl 44 base-form sale would share the same accounting. DealFinder lookups for posted items also missed per-variant pricing because they used the stripped form. Now the bag item's full key flows through to the log, preserving variant data going forward. (Existing entries aren't migrated; this is a going-forward fix.)

### Pet auto-scan: multiple pets in one bag now work

If you had two or more different battle pets in your bag queued to post (Cruncher + Lab Rat, etc.), the first one would scan and post correctly but every subsequent pet stayed in `scan pending` forever, even after re-running TSM's Post Scan. Three pet-specific gaps in the auto-scan path:

- The Blizzard search query was malformed for pets (it was always asking for species 0, not the actual species), so the server returned nothing
- The scan queue was de-duping on itemID — but every pet shares the same Pet Cage itemID, so only the first pet ever got queued
- The scan-cache fallback regex was digit-prefixed and never matched pet keys

All three fixed; multiple pets in one bag now scan and post like any other item.

### FlippingPal in German EU: gold parsing handles dot-thousands-separator

If you played on a German client and FlippingPal showed prices like `1.500g`, FlipQueue parsed them as `500g` — the regex only allowed comma as a thousands separator, not dot. So a 1,500g import would silently land in your buy-task list as a 500g target. Now both dot and comma are accepted as thousands separators on `g`-suffixed values, and as decimal markers on `k`/`m` abbreviations (`1.5k` and `1,5k` both correctly parse to 1500g). Auctionator shopping lists created from buy tasks will show the correct max price.

### Importer: full-region FP pastes no longer crash

Importing a very large FlippingPal dump (5,000+ items, e.g. a full-region paste covering every realm) would freeze the client long enough to crash. The synchronous parser was burning the entire UI thread without yielding. The importer now batches input over 500 items into 100-item chunks separated by frame-yields, with a status-line progress message during the run. Existing small-paste behavior is unchanged — the chunked path only kicks in for genuinely huge inputs. Can't be cancelled mid-stream from a UI button (use `/reload`).

### Cogworks gear-border minimap (canary)

The minimap button is now wrapped with the brass gear-border chrome shipped by the Cogworks suite library, replacing the default circular tracking border. First concrete validation of the Cogworks-as-hard-dep integration story for FlipQueue. Visual change only — click and drag behavior unchanged.

### New debug command

- **`/fq debug pulls`** (alias `/fq debug ops`) — toggle a per-op trace of bank-queue decisions during pulls and deposits. Off by default for performance. When on, every issue, skip, lock, recovery, and verify-fail decision logs a structured line to the debug ring buffer. Use to diagnose item-specific bank-op failures: re-run the failing flow with trace on, the decision branch that ate the move shows up in the log.

## v0.12.0-alpha3

Third alpha of v0.12. Bank operations popup feels alive during long pulls instead of looking frozen, DealFinder resolves real per-realm prices for ilvl variants instead of falling back to a single flat regional value, and the phantom "N expired auction(s) to collect — check mail!" login nag finally clears.

### Bank operations popup: move-by-move feedback

The progress bar used to sit at 0% during a 97-item Pull Saleable for the full 36 seconds, then jump straight to the final count when the move finished. Now it advances move-by-move as each item issues, so the bar reads "Pulling 32 / 97" while you're watching it and feels alive during the long pulls.

A new thin heartbeat sub-bar under the main progress bar fills 0 → 100 % over each timed wait, with a label telling you what FlipQueue is waiting for: `Waiting for bag update`, `Verifying moves`, `Retrying 4 failed move(s)`, `Switching bank panel`. The pauses are now legible — you can see they're intentional and how long they'll be.

When something does fail (rare, usually Blizzard's rate limiter), the completion summary lists each failed item by name in red instead of just saying "1 pull(s) failed" — you know exactly which items to chase down.

### Internal Bag Error: addon backs off automatically

When Blizzard's per-frame container rate limiter trips with `[15] Internal bag error` during a high-volume pull, FlipQueue now slows the inter-move delay to 500 ms (from 100 ms) for the rest of that bank visit. Resets to normal on bank close. Previously kept hammering the limiter at the same rate after the first failure, leaking 4-of-97 final-failed moves on long Pull Saleable runs; the adaptive backoff catches most of those before they fail.

### Phantom "expired auction(s) to collect" — fixed

If you got the orange login nag `N expired auction(s) to collect — check mail!` but had no mail, this is the fix. Three real causes were all collapsed into one symptom:

- **Mail UI never scanned an empty inbox.** When you opened a mailbox with nothing in it, the addon returned early without running its cleanup pass, so any expired entries in the log that should have been finalized stayed stuck. Now opening any mailbox — even an empty one — runs the cleanup and clears those orphans.
- **Pet auctions never matched.** Returned battle-pet auctions arrive as `[Pet Cage]` in mail, never as `[Lab Rat]` or whatever the species name was, so name-based matching missed every pet auction. Now matched by the species ID embedded in the mail item's hyperlink, which uniquely identifies the species regardless of the cage's display name.
- **Stale entries past the 30-day mail TTL** are auto-finalized at login. After 30 days the mail evaporates server-side anyway, so an entry stuck "awaiting mail collection" past that point is unrecoverable and shouldn't keep nagging.

If you have phantom entries you want to flush manually, `/fq debug expired` lists them and `/fq debug expired clear` finalizes them.

### TSM reconcile picks up expired and cancelled auctions

`/fq reconcile` previously only matched against TSM's sales records (`csvSales`). It now also reads `csvExpired` and `csvCancelled`, finalizing entries TSM saw end without depending on the mail-side path having run. Each match also fills in `postHistory` and `totalFeesSpent` for the attempt, so accounting reflects the real fee even when TSM was your only source of truth. Failure analytics in Item Research now break down by real cause (expired vs cancelled) instead of collapsing both into "expired."

### DealFinder: per-realm prices for ilvl variants

For gear with bonus IDs (most modern equipment), DealFinder used to show the same regional-average price for every realm — for example the same 43k for Greatlock Girdle on every realm, when the actual realm prices range from 19k to 198k. The cause: TSM stores variant gear under a level-form key (`i:260371::i253`) in its per-realm AuctionDB, but FlipQueue was looking up the bonus-form key TSM uses for general item identity. Bonus-form lookups missed every realm and fell through to the regional fallback.

DealFinder now derives the level-form key and looks up against it, so per-realm prices now reflect each realm's actual market for the variant ilvl. The realm-row tooltip's `Data Source` line shows whether you're seeing `Per-Realm TSM` (TSM has data for that ilvl on that realm) or `Regional Fallback` (TSM doesn't have that exact variant on that realm — rare).

### Tooltips show the right item

Hovering an item in Item Research, Inventory, Log, Generator, Todo, or DealFinder now resolves the tooltip to the actual ilvl variant — so an ilvl 253 ring with bonus IDs shows up as ilvl 253 instead of ilvl 44 (its base form). Two latent bugs were behind this: the WoW item string FlipQueue built was off by one positional field (bonus IDs landed in the wrong slot and the tooltip rendered base/garbage), and per-row metadata like realm/price footnotes was being silently dropped on item tooltips because the append code only ran for text-only tooltips. Both fixed; ilvl labels in Item Research are now correct.

### Bank gold operations: no false-failure reports

If you have `Auto deposit gold` disabled or are using Warband Miser to handle gold, the bank operations popup used to count the no-op as a failure — pop up `1 operation failed` even though nothing went wrong. Now the gold-op estimate respects both settings and the Warband Miser handoff, so the popup doesn't queue a phantom op for something it knows it won't run.

### New debug commands

- **`/fq debug expired`** / **`clear`** — list uncollected expired/cancelled log entries for the current character; the `clear` form finalizes them. Each row also reports whether TSM has a matching expired/cancelled record so you can identify which path orphaned the entry.
- **`/fq debug realms`** — show whether TSMRealms captured per-realm AuctionDB pricing data, with the per-realm update times. Use to diagnose "DealFinder shows the same price for every realm."
- **`/fq debug pricing <name|id|link>`** — trace per-realm AuctionDB lookup for one item. Shows the TSM string we built, the level form we'd use as fallback, and per-realm hit/miss with prices. Shift-click an item from your bag for the most accurate result.

## v0.12.0-alpha2

Second alpha of v0.12. Two fixes, two UX improvements — small but visible. Builds on alpha1.

### Gold withdrawal: stops getting stuck after the first withdrawal of a session

If you opened the bank, withdrew gold (say 8.4k to top up to your minimum), then went and posted auctions or otherwise spent the gold, the next time you opened the bank the addon would refuse to withdraw — silently, marked as "failed" in the operations summary. The cause: the addon was tracking session withdrawals to avoid double-withdrawing within one execution, but never reset the tracker between bank visits. So gold you'd already spent still counted toward "you already withdrew enough." Now the tracker resets every time the bank opens, so each visit is fresh accounting.

### Manual drawer buttons now show the bank operations popup

The four manual buttons in the drawer below the mini view — **Pull Items**, **Deposit Items**, **Deposit Extras**, **Pull Saleable** — used to bypass the bank operations popup and run silently the moment you clicked. They now show the same preview popup the auto chain shows: a list of what's about to move, with an Execute button. Click Execute to perform the moves. This makes the manual flow consistent with the auto flow and gives you a confirmation step before the items actually move.

### Manual gold buttons (Withdraw Gold / Deposit Earnings)

- Clicking a gold button when there's nothing to do now prints a chat message ("Already at or above target balance — nothing to withdraw" / "At or below target balance — nothing to deposit") instead of silently doing nothing.
- The button labels (which display the calculated amount, e.g. "Withdraw Gold: 8.4k") now update after a successful withdrawal or deposit, so they reflect your new balance instead of staying stale.

## v0.12.0-alpha1

First alpha of v0.12. Focused on TSM posting parity — closes a cluster of cases where FlipQueue's post price diverged from TSM's view, plus a working "Pull Saleable" button.

### Posting price parity with TSM

Fixes for items where FlipQueue's "below min", "undercut", or "no competitors" decision didn't match what TSM showed in its posting view:

- **Live cache no longer stomps real listings.** When the auto-scan kicker timed out, it would overwrite real listings the browse listener had just captured with a synthetic "empty" sentinel — making the row sit at "no competition" while TSM correctly saw a competitor. Both paths now leave real data alone.
- **Stack listings read at the right price.** Non-commodity items (gear, recipes, etc.) sold as a multi-unit stack were stored at per-unit price internally — so a 3-stack at 12k showed as a 4k competitor and tripped the "below min" branch falsely. Now stored at the full listing buyout, matching TSM's posting comparison.
- **Op price queries use the right item-string form.** TSM's `AuctioningOpMin/Max/Normal` price sources resolve through the canonical (group-keyed) form, not the level form FlipQueue had been using. For some items (designs, recipes), querying with the level form returned ~half the canonical value, silently flipping decisions from "below min, skip" to "undercut, post". Now uses canonical for op-derived sources, level form for raw DB sources.
- **Pets resolve to their actual TSM group.** TSM's group-lookup API errors out for battle-pet item strings even when the pet is grouped — so grouped pets always dropped to the `#Default` fallback op. New direct items-DB lookup catches what the API misses; pets now use their real op (Boophie's Battle Pets, etc.) instead of #Default.

### Drawer: see your TSM op at a glance

Every row in the post drawer now shows the TSM Auctioning op as a small inline tag after the decision rule. Custom ops in soft blue, `#Default (fallback)` in muted gray with an explanatory tooltip — TSM's posting view often doesn't show competitors for fallback-op items, so when you see the gray tag, FlipQueue's prices may differ from TSM's "no competition" view. Add the item to a TSM group for parity.

### Pull Saleable: real warbank walk

The "Pull Saleable" button used to require an active to-do list and would refuse otherwise. Now walks the warbank for every TSM-Auctioning-grouped item that isn't soulbound, pulling up to `postCap` (or your default sell quantity) of each, capped by what's already in your bags. Independent of the to-do list — this is the "I want one of everything I can sell" button. Reagent inclusion is gated by a new `trackReagents` master setting (default off, matching the existing "reagents aren't tracked for sales or to-dos" rationale) plus a per-flow sub-toggle. UI checkboxes for both are coming in a follow-up alpha; current surface is SavedVariables-only.

### New debug commands

- **`/fq debug post <fqKey>`** — significantly more output. TSM string + level-form values + price source comparison + TSM operation flags + per-listing cache dump (price, quantity, seller, time-left, isPlayer, hasOwner) + profile chain + group-lookup result. Use this whenever a post price looks wrong; the answer is almost always in here.
- **`/fq debug gold`** — walks the gold-required calculation per task with verbose printing. Surfaces every filter / skip / cap that AutoWithdrawGold applies, so when withdraw "doesn't appear to work" or pulls a wildly wrong amount, the dump shows exactly which task contributed what (or why it was skipped).
- **`/fq debug bagprices`** now skips soulbound items (Hearthstone, quest items) so the output is signal-only.

## v0.11.0

The first stable release since v0.9.8. The alphas between the two shipped a lot of new stuff — mini-view drawers, multi-account sync, a from-scratch bank and posting engine, TSM cross-checking, PBS support — and this release wraps all of it up plus fixes the posting regression that held v0.11.0 back. Compatible with WoW 12.0.5 shipping alongside this release.

### New: drawers on the mini view

- **Tools drawer.** Left side of the mini. Summon your warbank, mailbox, or auction house directly from there using toys, mounts, or items you already own. FlipQueue picks the right one based on what you have, and the **Find Nearest** button routes you to the closest service — your learned locations (where you've actually used a bank/mailbox/AH before) are preferred over static capital-city defaults, and the ranking respects your faction and current continent.
- **Context drawer.** Bottom of the mini. When you're at the bank, it gives you manual controls for pulls and deposits. When the AH is open, it turns into a posting panel — scan your bags, see what FlipQueue would post at what price, and post it one click at a time without leaving your current view. Also shows your owned auctions with an **undercut detector** that flags listings below the current AH min and a **Cancel Undercuts** button to clear them in one click.

### New: multi-account sync

- **BattleNet-linked accounts share inventory and tasks in real time.** Link a second WoW account via the Multi-Account section of Settings and both accounts see each other's characters, bags, warbank, and to-do list. Works with both trial and paid accounts on the same BattleNet. Uses Syndicator as the shared inventory backbone, so anything Syndicator knows (bags, bank, warbank across all your characters on both accounts) is immediately available to FlipQueue on either side.
- **Bulk-project alts.** On login, FlipQueue automatically projects inventory data for every character on the other account into your local view so you can plan against them without having to log in to each one.
- **Whisper fallback.** If BattleNet is unavailable (friend limits, same-BNet-account pairs), FlipQueue falls back to whisper-based sync so link-ups still work.

### New: posting and canceling from FlipQueue

- **Post items directly from the Context drawer.** Open the AH, open the drawer, click any scanned item to post it at the price FlipQueue computed (TSM Auctioning operation or your configured fallback source). Commodities use Blizzard's commodity API; individual items use the item API. Prices are rounded to silver so the server accepts them.
- **Cancel Undercuts button.** One-click cancel of every auction currently below the market min. Cancelled items go back to your mailbox; FlipQueue tracks the pending cancels and reconciles them correctly on the next owned-auction refresh.
- **TSM, Auctionator, and FlipQueue all refresh immediately after a post or cancel.** No more closing and reopening the AH to see new listings in TSM.

### New: ledger accuracy via TSM cross-check

- **`/fq reconcile`** — FlipQueue now reads TSM's sales history and upgrades any log entry that TSM knows was sold (missed session, looted without FlipQueue running, mail scan missed the match) from "expired" to "sold" with the real sale price and timestamp. Runs automatically on first AH open each session; the slash command forces a manual pass.
- **`/fq reconcile reset`** — clear the checked flag on every entry and re-run from scratch. Useful if you imported new TSM data or want to re-check a mis-attribution.
- **Active-auction count no longer drifts.** The "N active auctions" badge on the character list used to show the wrong number after cancels, variant posts, or missed mail events. The reconciliation engine was rewritten to match by variant (bonus IDs and item level) rather than bare item ID, and the cleanup and orphan-recovery phases run in the right order, so the badge now stays aligned with what's actually on the AH.
- **Uncounted "collected" entries are finalized.** Any auction that's been closed for more than 49 hours with no sale signal is finalized as expired, so your success-rate stats stop under-counting.

### New: PBS (Point Blank Sniper) integration

- **Import PBS shopping lists.** Paste a PBS export into Transform → Paste and FlipQueue auto-detects the format and round-trips every field (item-level ranges, price caps, quality, tier) byte-for-byte.
- **Export to PBS.** Any FlipQueue list or TSM group can be exported to PBS format.
- **Warm Cache button.** PBS lists usually contain items you don't own and WoW's item cache doesn't know about. Click **Warm Cache (N missing)** and FlipQueue walks TSM's item database plus Auctionator's historical price database to resolve the names, filling in the missing IDs so you can actually use the list.
- **AAA JSON output respects PBS max prices.** When exporting PBS imports to AAA format, FlipQueue uses the PBS snipe-ceiling price as-is instead of applying a TSM discount modifier.

### New: other features

- **Character deletion + restore.** Settings → Characters → Delete removes a character from FlipQueue cleanly (inventory, log entries, to-do items all cascaded out). If you change your mind, Settings → Deleted Characters brings them back with a single click. Tombstones prevent auto-detection from silently re-adding a character you deleted.
- **First-run setup wizard.** New installs walk through a short interactive wizard covering gold settings, bank automation, TSM/Auctionator integration, and posting. Returning users can re-run it from Settings any time.
- **`/fq debug` console.** In-game debug window with a live log and action buttons for common diagnostics (copy state, toggle debug chat output, test bank popup overflow). Captures the last 500 debug messages automatically.
- **Click-to-copy in Next Queue.** Click a character or realm name in the Next queue to copy it straight to your clipboard, with a separate setting for which one is copied by default.
- **Item detail popup.** Left-click any task in the mini view for a popup with full location, pricing, assignment, and research details.
- **TSM Market Data in Item Research.** Sold/day, sale rate, regional avg sale, historical price, market value, and TSM Accounting cost basis. Computes estimated margin when both cost and sale reference are available.
- **TSM fallback operation.** For items without an assigned TSM Auctioning operation, FlipQueue uses a configurable fallback op (dropdown selector in TSM Integration).
- **Gold buffer is now a floor, not an addition.** `goldBuffer` used to mean "extra gold beyond AH fees." It now means "minimum balance to keep on the character." If fees are lower than your buffer, the buffer wins; if fees are higher, fees win. Settings label and Setup Wizard wording updated.

### Fixes: banking

- **Deposits no longer silently swap items.** A warbank-full scenario with overflow disabled used to dump items into your personal bank anyway; a stale container cache on warbank tabs used to cause the deposit to land while an unrelated item got displaced out of the bank. Both paths are fixed — FlipQueue now claims each destination slot before issuing the move, validates the source item on every retry, and rejects cursor drops when the target slot has a different item than expected.
- **Warbank gets disabled after bulk deposits, fixed.** Async deposits were firing container ops too fast and tripping Blizzard's per-frame rate limit, which silently broke warbank on the next character. All async moves now serialize with a short spacer between them.
- **Bank tab filter respected.** Items are now routed to the most specific matching tab (Blizzard's Equipment / Reagents / Tradegoods filters), falling back to general tabs only when no specific one accepts the item. Item classes Blizzard's filter doesn't know about (Gems, Glyphs, Battlepets, Profession, etc.) no longer get rejected by every tab and pushed to the personal bank.
- **Bank pulls reliable.** Multi-item pulls no longer hit "Internal bag error." One move per frame with auto-retry, plus delta verification (the source slot count actually went down) before declaring a pull successful.
- **Bank popup progress matches reality.** Status bar now reaches 100% on completion instead of stopping partway, and deposits/extras run sequentially so the popup knows when each phase is really done.
- **Reagent bag no longer invisible.** Deposits from the reagent bag used to be silently dropped; they're now included.
- **Soulbound items excluded from deposits.** Equipped BoE gear, BoP tokens, and quest items no longer leak into the warbank deposit list.

### Fixes: posting and inventory

- **Posting works.** Three underlying bugs were fixed as the posting engine landed: prices weren't rounded to silver (server silently rejected), commodities were using the wrong API (PostItem instead of PostCommodity), and bid was being set equal to buyout (server rejects that with `ItemNotFound`). Post now succeeds reliably on both individual items (pet cages, gear) and commodities (crafted mats, consumables).
- **Post prices now match what TSM's Post Scan would choose.** The first pass at the posting engine listed items at the Auctioning operation's `normalPrice` — which is TSM's "no competition" baseline, typically around 2× market average. Whenever the AH actually had listings, FlipQueue posted well above market and the auctions sat unsold. Prices now follow TSM's full decision tree: undercut the current market lowest when it's between your min and max; match your own price when you're already the lowest (so reposts don't ratchet the ceiling down every cycle); use the operation's `priceReset` or `aboveMax` when a simple undercut would cross the thresholds; fall back to `normalPrice` only when the market is empty. The tooltip on each scanned row shows the reason FlipQueue picked the price ("undercut", "match own", "reset", etc.).
- **Operations that post in batches of 1 actually post 1.** The `postCap` setting was read with `tonumber()`, which returned nothing for expression-valued caps (anything beyond a literal like `"5"` or `"1"`). The scan fell through to "no cap" and grabbed the whole stack. Caps now evaluate through TSM's price engine, and when evaluation fails the scan defaults to 1 item per auction rather than "post everything" — fees are yours to pay, so the safer default wins.
- **Drift guard for future TSM updates.** FlipQueue now tracks which TSM version its posting logic was last audited against. When you load a newer TSM, FlipQueue prints a one-time chat notice so you know the decision tree should be re-verified against TSM's source. Same guard catches Auctioning operations that are missing fields FlipQueue expects (TSM renamed or removed a setting).
- **Profession tools no longer silently skipped as "below threshold."** The to-do generator had a dual-key fallback that used the base item's price for high-ilvl crafted variants, declaring them below TSM minimum when they weren't. Variants are now checked against their own variant-specific TSM price.
- **Cancelled auctions marked correctly.** Items returned via mail from a cancel used to end up in a "neither sold nor failed" limbo state in stats. They now track as unsold for success-rate purposes.
- **Mail scan records repeat-listing history again.** The number of times each item has expired without selling (plus total fees spent across attempts) was being dropped by an over-eager mail-open handler; it's now recorded correctly.
- **Unknown item names resolved on login.** Tasks showing "Unknown" as the item name used to stay stuck that way until you encountered the item; FlipQueue now requests the item data from the server on login and updates the UI when it arrives.

### Fixes: general

- **FP parsing edge cases.** Lists whose "Name" column header was being parsed as an item, cross-realm CSVs where the source-string "Player Inventory" triggered false cross-realm detection, and dedup after a "..." suffix on realm names — all fixed.
- **Mini view double-list.** When the current character had no tasks, the mini view used to render a duplicate summary in a different sort order. Now there's a single Next Steps section.
- **Performance.** Deal Finder used to freeze the game for multi-second stretches on large realm pricing scans — those now complete in a single frame. Bag-update handler is debounced to collapse bursts of events.
- **Stale imports cleared on list commit.** Imports used to persist across sessions even after being committed to a to-do list; they now clear automatically.
- **Drawer visual polish.** Context drawer backdrop is now a complete rounded rectangle even when collapsed. Tool drawer thumb tracks the mini view's height when you resize with the grip.

### Game compatibility

- **Works on both WoW 12.0.1 and 12.0.5.** FlipQueue's .toc lists both client versions, so it won't be flagged out-of-date on either the current live client or after the 12.0.5 patch rolls out.

## v0.10.2-alpha1

### New Features
- **PBS (Point Blank Sniper) import + export**: FlipQueue now recognizes and produces the Auctionator shopping-list wire format that PBS exports use. Paste a PBS export into the Transform → Paste textarea and the format auto-detects; select the new **PBS** output button to round-trip back out. PBS lists are stored by Auctionator as `listName^entry^entry^...` where each entry is the 14-field `searchString;categoryKey;minItemLevel;maxItemLevel;minLevel;maxLevel;minCraftedLevel;maxCraftedLevel;minPrice;maxPrice;quality;tier;expansion;quantity` string from `Auctionator.Search.ReconstituteAdvancedSearch`. Every field is preserved in a per-item `_pbs` metadata table so round-tripping is byte-identical for items that came from PBS; items from other sources (TSM groups, to-do lists, FP imports) synthesize their PBS output fields from `name` / `ilvl` / `quality`. The preview table's **Detail** column surfaces the most-useful PBS filter (`ilvl≥279`, `≤5000g`, `R3`, etc.) so imported search constraints are visible at a glance.
  - **Input**: `Import:ParsePBS(text)` in `Import.lua`, auto-detected by a hybrid `LooksLikePBS` probe that fast-paths on the `;;#;;` tier-placeholder substring and falls back to a structural "first entry has ≥13 semicolons after `^`" check for edge-case lists that have a real tier value set on every entry.
  - **Output**: `Transformer:OutputPBS(items, listName)` reconstructs the wire format. List name prefers the imported `_listName` over the default so round-trip preserves the original.
  - **Name → itemID resolution via TSM + PBS caches**: PBS shopping lists are typically filled with items the user does NOT own (rare mounts, high-ilvl crafted gear, snipe targets) — which means WoW's `C_Item.GetItemIDForItemInfo(name)` can't resolve them because they're not in the client item cache, and FlipQueue's own inventory/warbank/imports data sources miss them too. First-pass testing showed ~6 items out of ~100 resolving through the existing name→ID chain. `GetNameToIDMap()` in `TransformPage.lua` now walks two additional data sources:
    - `PointBlankSniper.ItemKeyCache.State.orderedKeys` (plus the in-session `newKeys` staging area): catches PBS files the user generated themselves, since their PBS cache contains every item PBS has seen via AH searches.
    - `_G.TSMItemInfoDB` (LongString-decoded `names` / `itemStrings` parallel arrays with `\002` separator, split into 1000-entry chunks per `LibTSMUtil/BaseType/LongString.lua`): catches PBS files authored by OTHER players, since TSM's persistent item-info database is populated from every auction scan and item lookup TSM has ever done across the user's TSM lifetime — typically tens of thousands of items covering most rare mounts, crafted gear, and niche items that end up on snipe lists even when the user has never personally searched for them.
  - **Per-source resolution breakdown in the preview status line**: shows where each resolved item came from — `(inv=2 pbs=4 tsm=58 cache=30)` — so users can see at a glance which data source is actually contributing. Items that failed to resolve are surfaced as `N unresolved` (previously they were silently dropped from the output, making "paste 100 items, see 64" mysterious). `item._resolvedFrom` metadata powers the breakdown, populated during `ProcessItems` as each item flows through the resolution chain.
  - **Warm Cache button** (new): when the preview detects unresolved items AND either TSM's per-realm pricing data or Auctionator's price database is loaded, a **Warm Cache (N missing)** action button appears next to Preview Source. Clicking it walks every unique item ID from the union of `TSMRealms.realmRaw` (items currently on any tracked realm's AH) *and* `AUCTIONATOR_PRICE_DATABASE` (items Auctionator has ever seen on any realm — historical, persists forever, critical for rare snipe targets like TCG mounts that aren't currently on the AH). Auctionator dbKey formats are parsed per `Auctionator/Source/Utilities/DBKeyFromLink.lua`: bare numeric for most items, `g:id:ilvl` for modern gear, `gr:id:suffix` for legacy gear, `p:speciesID` skipped (pets use a separate resolution path). Typical warming pool is 30-80k unique item IDs. Each ID is proactively forced into WoW's client item cache via batched `C_Item.RequestLoadItemDataByID` calls (250 IDs / 0.05s, well under any realistic rate limit). A listener on `GET_ITEM_INFO_RECEIVED` matches incoming item names against the unresolved PBS names, folds matches into the name map with `source = "cache"`, and re-runs the preview after all responses have had 1.5s to land. Progress is shown live in the status text (`Warming cache: 12000/30000 sent, 14/36 resolved`). This is the fix for the expert-authored PBS list workflow — users take a list from an expert, paste it, warm the cache, and get near-complete coverage even on items they've never personally encountered. New `TSMRealms:CollectAllItemIDs()` public API exposes the TSM ID set; the Auctionator pool is collected inline via `CollectWarmingPool()` in `TransformPage.lua`. The warming session state (listener frame, ticker, progress counts) is cancelled cleanly when the source mode changes or the preview is rebuilt.
  - **Recorded-price fallback for unpriced AAA output**: when an item resolves to an ID but TSM has no price data for it (common for rare mounts, old gear, niche consumables), `OutputAAAJSON` now falls back to the item's *recorded* price — `_pbs.maxPrice` from a PBS import first (the snipe ceiling the user explicitly set), then generic `expectedPrice` from other import sources. **No discount modifier is applied** to recorded prices: the user set them explicitly as their target, and applying the TSM discount would change the meaning. Previously the fallback was `expectedPrice × modifier`, which silently discounted user-entered prices and produced the "why is my 5000g entry showing 4500g in AAA" confusion. Works in both `tsm` and `imported` price modes.
  - **AAA price mode toggle**: new row on the Transform page (visible when AAA JSON is the output format) lets users pick between **TSM discount** (the existing behavior — TSM price × discount modifier) and **Imported** (uses PBS `maxPrice` or `expectedPrice` raw, no discount applied). Imported mode is the useful default for PBS → AAA handoffs where each item's AAA threshold should be exactly the max-price the user pasted from their PBS file. Persists via `db.settings.transformPriceMode`.
- Paste-mode auto-detect instruction updated to list PBS alongside FP / CSV / TSM / Auctionator / item names.

### Bug Fixes
- **Profession tools (and other high-ilvl crafted gear) silently rejected from to-do generation as "below TSM min price"**: `TodoGenerator.lua:891-894` had a dual-key fallback that fired whenever the first `IsBelowThreshold` call returned `false` — which happens in two distinct cases the code couldn't tell apart: *(a)* the variant's price is genuinely above threshold (correct), and *(b)* TSM has no data for the key (undecided). The fallback then called `IsBelowThreshold(deal.itemKey)` where `deal.itemKey` was typically the base-item key from an FP import (no bonus IDs). For a high-ilvl profession tool variant, this resolved to the base-item `DBMinBuyout` — dramatically lower than the actual variant's market value — and returned `true`, overriding the correct "above threshold" result and causing the to-do item to be silently skipped. When the user manually posted the item, it sold fine at the variant's real price. Fixed by gating the fallback on `not ahMin` (i.e., only fall back when the first call had no TSM data) and reassigning all four return values so the `failReason` message isn't stale. Full audit of the five `IsBelowThreshold` call sites confirms this was the only buggy one — `TSM:GetPrice`, `TSM:ItemKeyToTSMString`, `DealFinder`'s batch + per-item lookups, and `TSMRealms:GetBatchPricing` are all correctly bonus-keyed.

## v0.10.1-alpha3

### Bug Fixes
- **Bank Operations popup showing "Operations complete" with a partial progress bar**: the popup's row content correctly transitioned to the completion summary, but the status bar would land on `0`, `2/N`, or some partial state instead of full. Three independent bugs feeding the same symptom:
  - **Optimistic deposit progress reports**: `Tracker.lua`'s `DoDeposits` reported `depCount = #depositOps` and `extCount = #extraOps` (the *requested* counts) directly to `BankOpProgress`, never threading the actual `successNames`/`errorCount` returned by `BankQueue:Process`. Refactored to await `AutoDepositToWarbank` and `AutoDepositExtraItems` sequentially via callbacks that pass through the real counts. The two sub-phases now run in series instead of fire-and-forget.
  - **`AutoDepositExtraItems` was fire-and-forget** — no `onComplete` callback at all. The popup chain would proceed to `BankPopupComplete` while the extras' `BankQueue:Process` was still mid-batch. Added an `onComplete(successNames, errorCount)` parameter that fires from every early-return path and from the final `Process` callback after Scanner refresh settles, so the chain can actually wait for extras before declaring completion.
  - **Reagent bag silently dropped from `AutoDepositToWarbank`**: `Tracker:BuildDepositOps` (the popup builder) iterates `ALL_PLAYER_BAGS = {0..5}` which includes the reagent bag, but `Tracker:AutoDepositToWarbank` was iterating `INVENTORY_BAGS = {0..4}` which excludes it. So a deposit task whose source item lived in slot 5 would appear in the popup but get silently skipped during execution. Now both call sites iterate `ALL_PLAYER_BAGS` and stay in agreement.
- **Defensive `ShowCompletionSummary`**: even with the three fixes above, any future regression in the running tally would resurface the partial-bar symptom. `ShowCompletionSummary` now reconciles the running `completed` count up to `totalOps - failed` on transition to "Complete" (preserving the failed count so the orange/green color logic still reflects whether anything failed), and emits a `[bank-popup]` debug line whenever drift is detected so the underlying drift remains diagnosable.

### Diagnostics
- **`[bank-popup]` debug log**: `BeginBankExecution`, `BankOpProgress`, `ShowCompletionSummary`, and `BankPopupComplete` now each emit a one-line debug entry into the in-game debug ring buffer (visible regardless of the `debugMessages` print setting). Records the operation, the running `completed`/`failed`/`total`, and any guard hits (popup not shown, execState nil). Use this to diagnose any future "popup state out of sync" reports — the entire execution timeline lives in the debug console after the bank visit.

## v0.10.1-alpha2

### Bug Fixes
- **Deposits overflowing into personal bank with overflow disabled**: `AutoDepositExtraItems` builds non-soulbound deposits with `destType = "any"`, and both `ProcessNextBatch` and `Attempt`'s `IssueOne` handled `"any"` by *merging* warbank+bank into the picker's primary bag list — which silently bypassed the overflow gate inside `PickDepositSlot`. A user with a full warbank, locked bank tabs, and overflow off would still see items land in their bank tabs because the picker never even consulted the overflow flag. Both call sites now treat `"any"` the same as `"warbank"`: warbank as primary, bank as secondary, gated by `overflowEnabled`.
- **Items leaking to personal bank even when warbank tabs had open slots**: `ItemMatchesTabFlags` only knows about a handful of item classes (Weapon/Armor/Consumable/Tradegoods/Recipe/Questitem/Junk). Items in any other class — Gem, ItemEnhancement, Glyph, Miscellaneous, Battlepet, Profession, etc. — get rejected by every tab that has *any* `depositFlags` set, even when those tabs have empty space. Combined with the overflow bug above, the picker would declare warbank "full" and dump the item into the personal bank. `PickDepositSlot` now has a filter-bypass fallback path: if no filter-matching primary tab can take the item, walk every primary tab ignoring filters before falling back to overflow. Tab filters are now treated as a routing *preference*, not a hard wall. (`FindStackTarget` and `FindEmptyAcceptingSlot` gained an `ignoreFilters` parameter.)
- **Warbank getting disabled after bulk deposits / between characters**: `ProcessNextBatch` (the async path used by `AutoDepositExtraItems`) issued every op in a batch (`pullBatchSize`, default 5) inside a single tight Lua loop with no inter-move spacing — only `INTER_BATCH_DELAY = 0.3s` *between* batches. Five container ops in a single frame is exactly what trips Blizzard's per-frame rate limit, and the resulting backoff manifests as the warbank being unresponsive on the next character. The async path now serializes ops the same way `ProcessSync` does — `WaitForBagUpdate(INTER_MOVE_DELAY=0.1, …)` between every real container move, with skip-cases yielding via `C_Timer.After(0, …)` so big batches don't blow the Lua call stack.

### Diagnostics
- **Deposit slot picker debug log**: every call to `PickDepositSlot` now emits one line into the debug ring buffer (visible in the in-game debug console regardless of the `debugMessages` print setting). Each line discloses the item, the picked destination, *which branch picked it* (`stackTarget(primary)`, `emptySlot(primary,filter-bypass)`, `emptySlot(secondary,overflow)`, etc.), and the full candidate list for both primary and secondary bag groups with each tab's `depositFlags`, specificity, and accept/reject decision. Use this to diagnose "wrong tab" reports — it makes it obvious whether the picker chose tab N because of an existing partial stack, a higher-specificity Blizzard filter, or fall-through into the filter-bypass / overflow paths.

## v0.10.1-alpha1

### Bug Fixes
- **Deposits silently swapping items between bag and warbank**: when the client container cache lagged the server — especially for warbank tabs that hadn't been actively viewed — `PickDepositSlot` would target an "empty"-looking slot that was actually occupied, and the resulting `CursorMove` performed a server-side swap: the deposit landed at the destination while an unrelated item was displaced out of the bank. The delta verification, which only tracks the deposited itemID's count, saw `+1` and declared success. The user was left with items in the wrong inventory.
  - **Allocation ledger** (`allocatedSlots`), scoped per sync attempt and per async batch — each deposit claims its destination slot *before* the `CursorMove` is issued, and `FindStackTarget` / `FindEmptyAcceptingSlot` skip claimed slots so two ops in the same sweep can never collide. Same mechanism Baganator's `BankTransferManager` uses.
  - **`BAG_UPDATE_DELAYED` wait between sync moves**: the fixed 100ms spacer was a best-effort guess; the event is the deterministic signal that the container cache reflects the last server response. Still enforces the 100ms minimum for Blizzard's container-op rate limit, with a 600ms hard ceiling if the event never arrives (rejected move).
  - **`C_Item.DoesItemExist` empty-slot probe**: `FindEmptyAcceptingSlot` now prefers the `ItemLocation`-based API over `C_Container.GetContainerItemInfo`, which is more reliable for warbank tabs the player hasn't opened in this session.
  - **Source-item validation (`op._expectedItemID`)**: `IssueOne` records the source item on first issue and compares on retries — if a prior swap or external move replaced the original item at the source slot, the retry aborts instead of moving an impostor.
  - **`CursorMove` destination guard**: rejects place attempts when the destination holds a different itemID than what's on the cursor. Belt-and-suspenders for the fresh-cache case.

## v0.10.0-a3

### Bug Fixes
- **BankQueue crash on some clients**: `GetBankTypeForBag` used `Enum.BagIndex.BankBag_*` constants that don't exist on every client, causing "compare nil with number" — now uses numeric ranges with nil-safety
- **Deposits silently going to character bank instead of warbank**: `UseContainerItem` on inventory slots ignores `BankPanel:SetBankType` and defaults to character bank — pulls keep shift-click, deposits now use cursor moves with explicit destination so warbank-bound items can never silently misroute
- **Deal Finder game lockup**: TSMRealms was doing O(items × realms × stringSize) string scans on multi-megabyte realm pricing data. New `GetBatchPricing` does a single pass per realm; cost drops from gigabytes to megabytes of byte comparisons for typical pools — multi-second freezes now resolve in a single frame
- **Imports growing unbounded**: imports were meant to be ephemeral working state for the import → generate phase but persisted across sessions. Now auto-cleared in `TodoList:CommitList` so the to-do list becomes the single source of truth once a list is committed
- **Chronic micro-lag during AH/mailbox activity**: `BAG_UPDATE_DELAYED` handler is now debounced — collapses bursts of bag updates into a single Scanner+RefreshLocations+RefreshTaskSteps+UI:Refresh+RefreshMini chain instead of running it N times
- **Mini view double-list bug**: when the current character had no tasks, the mini view rendered a duplicate per-character summary above "Next Steps" in a different sort order. Removed the duplicate render — Next Steps is now the single source of truth for that view
- **Single sale hidden in Item Research**: `RenderSaleHistory` required `> 1` sales; now shows even a single transaction so the "yes this thing has sold once, here's what for" data point isn't lost
- **Soulbound items in deposit extras**: `BuildExtraDepositOps` was routing soulbound items to the character bank; now skips them entirely (matches `BuildDepositOps`)
- **Reagent bag invisible to deposits**: `CountInBags`, `BuildDepositOps`, and `BuildExtraDepositOps` weren't iterating bag 5; new `ALL_PLAYER_BAGS = {0..5}` constant covers it
- **Bank tab filter ignored**: Blizzard's per-tab `depositFlags` (Equipment / Reagents / etc. assignment) wasn't honored. New `ItemMatchesTabFlags` checks each tab's filter and `TabSpecificity` ranks accepting tabs so the most-specific match wins over catch-all
- **Bank popup overflow**: long pull/deposit lists overflowed off-screen; now wrapped in a `ScrollFrame` with mouse wheel support
- **"Internal bag error" during multi-item pulls**: `ProcessSync` now issues one move per frame with auto-retry, pre-sets the bank panel with a settle delay, and uses a configurable inter-move delay to stay above Blizzard's container-op rate limit
- **Debug message leaks in live mode**: audited and fixed several `ns:Print` calls that were debug-style: Scanner iLvl logging (also fixed wrong settings field name), ExportPopup SimpleHTML status, CharactersPage character reorder messages, Export scan summary, Import deduplication count

### Features
- **TSM Market Data section in Item Research**: surfaces sold/day, sale rate, regional avg sale, historical price, market value, and TSM Accounting cost basis. Computes estimated margin when both cost and a sale reference are available, so players can make "should I keep posting?" decisions even when their personal log has zero sales
- **Smart deposit stacking**: `FindStackTarget` merges deposits into existing partial stacks before opening new slots
- **Deposit overflow setting** (off by default): when the warbank has no room, optionally fall back to the character bank. Sub-toggle for combining partial stacks across both banks. Global default with per-character override support
- **Reagent deposit toggle**: new "Move reagents to warbank when depositing all" setting (off by default — reagents aren't tracked for sale because they're not cross-region)
- **Collapsible bank popup sections**: Pulls / Deposits / Gold / Extras can each be collapsed independently; state persists across popups
- **Mail icon on mini view**: small envelope icon shown on the header only when `HasNewMail()` returns true
- **`/fq debug` console**: in-game debug window with action button grid + live debug log view. Buttons for bank popup overflow tests, FQ state export, copy debug log to clipboard, toggle debug mode. Status indicator shows whether chat-output debug mode is on. Captures the last 500 debug messages to a ring buffer regardless of toggle so the console always has recent context
- **`UI:RegisterDebugAction(label, fn)`**: public API for other modules to register their own debug console buttons without editing `DebugConsole.lua`

### Settings reorganization
- **New "Bank & Warbank" section**: bank, gold, reagent, overflow, and batch-size rows moved here from "Scanning & Automation". The remaining section is renamed "General"
- **TSM behavior moved to TSM Integration page**: `tsmSkipOnGenerate` and `tsmAutoSkipRejected` no longer live in the Settings frame; they're under a new "Behavior" sub-header on the TSM Integration page
- **Multi-Account section framing**: "Real-Time Sync (recommended)" header in green with a clear description of what it does (BattleNet-linked, real-time inventory + task sync, unified to-do list). "External Accounts" relabeled to "External Accounts (legacy — use Real-Time Sync above)" in muted gold with an inline deprecation notice
- **Plain-language labels** throughout: e.g. "Withdraw gold from the warbank to cover listing fees", "Deposit to bank when warbank is full", "Move reagents to warbank when depositing all"

## v0.10.0-a2 — BankQueue reliability rewrite

### Bug Fixes
- **Pull verification false positives**: auto-pull was reporting success for items that never moved. The old verification only checked "is the source slot empty?", which gave false positives when a server-rejected destination placement bounced the item to a different slot. New `CountItemsInBags` snapshots stack counts by itemID before/after each batch; an op only counts as moved when the destination's count of that itemID actually went up. Applied to both `ProcessSync` (popup path) and the async `VerifyBatch`
- **"Internal bag error" during pulls**: replaced the `PickupContainerItem` + `PickupContainerItem` cursor dance with single-call `C_Container.UseContainerItem` (shift-click semantics). Half the rate-limit pressure, no cursor state to leak between back-to-back moves, server picks the destination including auto-stacking onto partial stacks. Gated behind `IsBankOpen()` so it can't fall through to "use the item"
- **Failed moves in `ProcessSync` weren't retried**: added auto-retry up to 4 times, matching what the async `Process` path already did

### Features
- **One move per frame**: each pickup is scheduled via `C_Timer.After(0, IssueNext)` so it lands on its own frame, avoiding the 16ms-too-fast tight loop that tripped Blizzard's container-op rate limit
- **Local bank panel tracking**: `SetBankType` is only called when the type actually changes, with a small settle delay after a switch — eliminates redundant panel rebuilds inside a batch

## v0.10.0-a1 — BankQueue rewrite, unified sales tracking, item detail popup

### Bug Fixes
- **Warbank ops blocked by taint**: removed the previous taint workaround (which was causing taint, not fixing it) and rewrote `BankQueue` with explicit `EnsureBankType` mode-setting before warbank operations
- **Deposit/extra slot overlap**: `BuildExtraDepositOps` now excludes slots already claimed by deposit ops
- **Mini view deposit visibility for non-logged-in characters**: deposit tasks for items not in inventory are now hidden in the mini view to avoid stale rows
- **Warbank source verification**: `RefreshLocations` now properly checks warbank inventory for deposit tasks — clears `depositFrom` and updates `source` to "warbank" when the item is found

### Features
- **Unified sales tracking (`SalesIndex.lua`)**: new module with canonical `IsSold` / `IsFailed` / `IsActive` predicates and a cached index exposing `GetSalesSummary`, `GetSalesForRealm`, `GetLogStats`, and `GetUncollectedForChar`. Single source of truth for all views; removed ~130 lines of duplicate sales indexing in `DealFinder.lua`
- **Item detail popup**: left-click a task in the mini view to open a popup showing location, assignment, pricing, and research summary
- **Bank popup with unified progress bar**: color-coded across all phases (pull / deposit / gold), completion summary persists until the bank closes. Anchors to the mini view with configurable position
- **Bank progress rollout on mini view**: when the popup isn't visible, the mini view shows a compact progress indicator instead
- **Collapsible settings sections**: collapse with summaries shown in the collapsed state, persisted across reloads
- **Deferred tasks hidden from mini view**: reduces visual clutter for tasks that aren't actionable right now
- **Canonical item matcher (`ns:ItemsMatch`) adopted in ItemResearch** and other modules

## v0.9.8 — Setup wizard, bank progress, soulbound/warbound fixes

### Features
- **First-run setup wizard**: step-by-step interactive wizard with a "Use Recommended Defaults" fast path. Steps: Welcome, Gold, Bank Automation, TSM (if detected), Pricing, Posting, Display. Steps are dynamic based on TSM/Auctionator detection. Auto-triggers for new installs; existing users skip. Re-runnable from Settings via the "Run Setup Wizard" button
- **Bank progress bar**: status bar overlay during pull/deposit operations showing X / Y progress, updated per batch, hides on completion
- **Pricing model split**: separated "Deal Price" (imported) from "Blended" (TSM + personal sales history) as distinct options across Deal Finder, the TSM page, and the wizard. New `blendedPrice` field on Deal Finder imports

### Bug Fixes
- **Soulbound deposit filter**: deposit allowlist now only includes BtA / BtW items when `isBound=true` (was letting equipped BoE through to the deposit list)
- **Warbank pool builder included untradeable items**: BtW / BtA items were being added to the sell pool; now filtered out
- **Character inventory tradeable check**: also excludes Quest / BtA / BtW bind types

### Default Changes (fresh installs only)
- `autoWithdrawGold`: false → true
- `maxWithdrawGold`: 0 → 500
- `goldBuffer`: 0 → 50
- `autoDepositGold` remains off (players keep earnings by default)

### Settings & Tutorial cleanup
- Sync log toggle now reflows the content below it using a container frame
- Tutorial: removed Export step (page no longer in nav); generator step uses banners instead of anchor-dependent callouts; fixed text overlap on center-type callouts; reduced from 5 to 4 steps

## v0.9.7

### Bug Fixes
- **FP website "Name" header parsed as item**: When FP paste lacks a "/" separator, the column header "Name" was misidentified as an item — now filtered out along with other known header words
- **TSM skip blocks post detection**: Items marked "skipped" by TSM threshold on AH open were invisible to post detection and owned auction matching — posts for skipped items are now detected and the skip is cleaned up automatically
- **Bank over-pull**: Auto-pull recalculated quantity from TSM postCap independently of the task, pulling e.g. 6 when the task needed 1 — now uses the task's own quantity directly
- **Deal Finder quantity set to total inventory**: Per-realm deals stored the full inventory count as quantity, causing over-allocation for items without TSM groups (especially pets) — now stores 1 as baseline, with actual post qty determined by TSM postCap / defaultSellQty during generation
- **Mini view missing quantity**: Mini view task rows now show "x3" etc. when quantity > 1, matching the To-Do page display

### Debug
- **Generation debug logging**: When debug messages are enabled, the to-do generator now logs reasons for dropped deals: no pool match, no character assignment, pool exhausted, and TSM threshold skip
- **Deal Finder debug logging**: Logs items skipped during scan (no TSM key, no market data, below min price)

## v0.7.0

### Bug Fixes
- **Deposit refresh race condition**: BAG_UPDATE_DELAYED no longer runs stale RefreshLocations during active pull/deposit operations — prevents to-do list from flickering or showing incorrect state
- **Mini view action buttons persist**: Action buttons, OnEnter/OnLeave scripts now explicitly cleaned up during row refresh

## v0.7.0-alpha.7

### Bug Fixes
- **Auction cancellation detection**: New `AUCTION_CANCELED` event tracking distinguishes cancelled vs sold auctions — cancelled shows "collect items" (orange), sold is detected via mail invoice data only. Fixes false "collect gold" messages on cancel.
- **Stale reconciliation**: Auction entries no longer on AH are silently marked "collected" instead of falsely "sold". Actual sales detected only by `ScanMailForSales`.
- **TSM false rejection removed**: No longer skips items when TSM has no AH price data — TSM posts using normalPrice, so missing `DBMinBuyout` is not a rejection.
- **Skipped tasks un-skip**: Items returning to bags now un-skip ALL skipped tasks (removed TSM-skip exception that prevented recovery).
- **Mail clears sold entries**: Opening mailbox now sets `collectedAt` on sold entries and clears cancelled/expired, so "Check Mail" tasks resolve immediately.
- **Mini view task indices**: Grouped summary now annotates `_taskIndex` before building display groups, fixing bulk actions on character/create-char groups.

### Features
- **Bulk group actions**: Complete/skip/delete all tasks in a character group — hover action buttons on group headers in both To-Do page and Mini View, including "Create character" groups.
- **Dismissible mail tasks**: Right-click "Check Mail" rows in To-Do page or Mini View to dismiss stuck entries.
- **Gold text offset**: Price/gold text on to-do item rows moved left to avoid overlap with action buttons.
- **Log: Cancelled status**: Log page shows "Cancelled" (orange) for cancelled auctions.
- **Sidebar cleanup**: Removed Export and Import from sidebar, renamed "FlippingPal" section to "Tools", updated Transform icon.

## v0.7.0-alpha.6

### Bug Fixes
- **Warbank deposit scan** (#101): After depositing items to warbank, the addon now scans warbank (not just personal bank) so deposit tasks are properly resolved
- **Buy tasks say "to post"** (#102): Mini view and to-do page now correctly label buy tasks as "to buy" instead of "to post" everywhere — title, group headers, next steps, status bar
- **TSM detected chars overflow** (#66): Detected characters section now caps at 8 visible rows with scroll instead of overflowing the window
- **Auto-pull grabs just-deposited items**: Bank open now runs RefreshLocations before auto-pull, preventing items just deposited to warbank from being pulled back out
- **Auto-pull ignores buy tasks**: Buy tasks are no longer pulled from bank — they need to be purchased from the AH
- **Deposit tasks stuck after warbank deposit**: RefreshLocations now checks warbank inventory for deposit tasks — clears depositFrom and updates source to "warbank" when item is found
- **Buy task browse step stuck**: Browse step now auto-advances when item appears in bags (bought from AH + collected from mail), double-advancing through buy step
- **Gold auto-withdraw for buy tasks**: hasTasks check now matches buy tasks on buyRealm; CalculatePostingFees skips buy tasks; CalculatePurchaseCosts implemented with actual buy prices

### Features
- **Auctionator shopping lists from buy tasks** (#103): Creates per-realm shopping lists ("FQ Buy - RealmName") in Auctionator search format with price filters — button on To-Do page and Mini View when Auctionator is installed
- **To-Do list selector** (#104): Compact bar at top of To-Do page showing active list name + task count; dropdown to switch between active and queued lists
- **Mini view: auto-width**: Frame automatically stretches to fit content text (200-500px range)
- **Mini view: resizable**: Drag grip in bottom-right corner to set preferred width (persisted)
- **Mini view: collapsible**: Collapse/expand button in header — collapsed shows first 2 rows only
- **Mini view: buy task display**: Buy tasks shown with [BUY] prefix, correct price/realm, waiting icon
- **Mini view: deferred task filtering**: Deposit tasks for items not in inventory are hidden
- **Max withdrawal setting**: New "Max withdrawal per visit" gold input in Settings — caps auto-withdraw amount per bank visit (0 = no limit)

### Closed Issues
- #69 (To-Do scroll), #68 (auto-import reset), #67 (hidden char tasks), #38 (TSM rejection), #105 (generator save nav) — all previously fixed

## v0.7.0-alpha.4

### Bug Fixes
- **Deposit task stuck**: Buy task deposit step no longer gets stuck when item is posted on AH instead of deposited — fixed race condition where RefreshLocations clobbered task.source before RefreshTaskSteps could check it
- **Hidden character shared AH**: Hidden/ignored characters no longer cause other characters on the same realm to show "Shared AH" status
- **TSM/Auctionator/Realm filter checkboxes**: Checking a filter checkbox now immediately refreshes the UI to show the filter content (was requiring a page navigation first)
- **Realm filter "create char" tasks**: "Only show realms with characters" now correctly filters by sell realm — no longer passes deals where only the buy realm has a character
- **Save returns to track selection**: Saving a generated list now returns to the track selection screen instead of step 1 of the same track

### Task Management
- **Mouseover action buttons**: Hover over any task row in the To-Do page or Mini View to see complete/skip/delete buttons on the right side
- **DeleteTask**: New function to remove a task entirely without logging

### Import Performance
- **Async chunked import**: Large imports now process in batches of 50 with a progress bar — UI no longer freezes during import
- **Progress bar**: Shows "Importing... X / Y (Z%)" with a green fill bar during processing

### Generator Improvements
- **Side-by-side buy/sell lists**: Separate mode now renders buy and sell preview lists in left/right columns instead of vertical stacking
- **Side-by-side priorities**: Buy and Sell priority lists shown horizontally in Step 3
- **Per-list naming**: Separate mode has individual name inputs for buy and sell lists above each column
- **Sell list includes planned buys**: Cross-realm flips not yet purchased now generate both a buy task and a deferred sell task
- **Removed import button**: Superfluous Import button on Generator cross-realm Step 1 removed — use Import tab instead

## v0.7.0-alpha.1

### Generator Wizard (#84)
- **Two-track wizard**: Generator page redesigned as a step-by-step wizard with track selection
- **Inventory Scan track**: Build Inventory → Import FP Deals → Configure & Generate (3 steps)
- **Cross-Realm Import track**: Import Deals → Filter Deals → Configure & Generate (3 steps)
- **Buy priorities**: New priority system for cross-realm buys — profit, population, low inventory, high inventory, discount
- **List modes**: Generate separate buy/sell lists or a single integrated list (most profitable / best deal / prioritize buys)
- **Realm filter**: Filter cross-realm deals by realms where you have characters
- **Auto-generate**: Preview auto-updates on every config change — no more Generate button
- **Save with name**: Prompt for list name when saving; wizard returns to step 1 after save
- **FP Premium note**: Import steps indicate FlippingPal Premium requirement

### Transformer Pipeline (#32)
- **New Transform page**: Input → Transform → Output pipeline for item data conversion
- **4 input adapters**: TSM groups, imports, inventory, Auctionator lists
- **5 transforms**: SplitPets, PriceModify, FieldMap, Filter, MergeByKey
- **4 output adapters**: AAA JSON, FP CSV, TSM group string, Auctionator list

### Cross-Realm Import (#60)
- **Cross-realm flipping**: Import FP cross-realm flip data (website, CSV, Auctionator formats)
- **Buy to-dos**: Generate "buy" tasks with browse → buy → deposit steps
- **Format support**: FP website copy-paste, FP comma CSV, Auctionator inline (^-separated), Auctionator text export, tab-delimited with buy/sell columns

### Sale vs Expiry Tracking (#70, #71)
- **Sold vs expired**: Mail scan distinguishes sold (gold received) from expired (item returned)
- **Failed sale tracking**: Tracks post attempts, total fees spent, per-attempt history with TSM price data
- **Login message**: Splits sold vs expired counts with distinct colors
- **Log page**: Shows Sold (green) vs Unsold (orange), failed sale count, per-attempt tooltip, total fees lost

### QoL Improvements
- **Characters page**: Heading style fix (#72), auto-expand table when no "create" section (#76), overflow into TSM section fixed (#92)
- **Inventory page**: AH-posted items show correct owner/location (#73), "Unassigned" replaces "Unknown" for tracked items (#74)
- **Scroll tables**: Horizontal scroll bars (#77), auto-hide when nothing to scroll (#78)
- **Empty states**: Generator button on empty To-Do page (#75) and Mini view (#79)
- **Sidebar**: Wider default width (#80)

### Bug Fixes
- **New character auto-assign**: Unassigned tasks automatically assigned when a new character logs in (#83)
- **Warbank deposit batching**: Uses event-driven batch system instead of one-at-a-time timer
- **Bank/warbank transfers**: Now trigger to-do step refresh in both directions (#91)
- **Expired auction cycle-back**: Collected expired items cycle task back to "post" step (#94)
- **TSM rejection step check**: Only checks tasks on "post" step, not retrieve/collect (#95)
- **Battle pet detection**: 4-tier matching (key/ID/species/name) across all inventory lookups and mini view (#82)
- **No more auto-skip**: Tasks defer instead of skip when item not found in stale inventory DB
- **Auto un-skip**: Skipped tasks re-check and un-skip when item reappears
- **Auto-complete lists**: Lists auto-archive when all tasks are done/skipped (#88)
- **Active list auto-promote**: Deleting active list promotes next queued list (#88)
- **Import [XR] prefix**: Fixed inventory imports incorrectly showing cross-realm indicators (#85)
- **Cross-realm CSV parsing**: FP source strings (Player Inventory) no longer trigger cross-realm detection
- **EditBox focus**: Click anywhere on paste area background to focus (#93)

## v0.6.2

### TSM Rejection Handling (#38)
- **Auto-skip below threshold**: When opening the AH, items below TSM's min price are automatically detected and handled
- **Realm-mate reassignment**: Below-threshold items are reassigned to another character on the same realm when available, based on priority settings
- **Skip + log**: When no alternate character exists, items are skipped with full TSM reason (price, threshold, operation name) and logged
- **Log entries for rejections**: Skipped items appear in the Log page with "Skipped" status and TSM reason in tooltip
- **Setting**: "Auto-handle TSM rejections" checkbox in Settings (on by default)

### Bug Fixes
- **Multi-post quantity inflation**: Fixed CheckForPosts logging inflated posted quantities when multiple to-do tasks share the same item type (#54)

## v0.6.2-alpha.4

### Bug Fixes
- **TSM detected characters overflow**: section now scrollable with max height — no longer spills below the window (#66)
- **TSM detected characters persist between tabs**: properly hidden on tab switch; TSM profile dropdown menu also cleaned up (#66)
- **Hidden characters still get to-do tasks**: Generator now skips ignored characters in both item pool building and task assignment (#67)
- **Auto-pull fails for shared AH realm-mate**: tasks route to the visible character instead of the hidden one, so auto-pull works correctly (#67)
- **Auto-import checkbox resets after logout**: setting now persisted to SavedVariables like Auto-generate (#68)
- **To-Do overview cannot scroll**: added explicit mouse wheel handling for TWW compatibility (#69)

## v0.6.1

### To-Do System (replaces Queue)
- **To-Do Generator**: two-column page — left column shows your item pool with filters (All, TSM Group, Auctionator List), right column builds your task list with priority controls and sort modes
- **To-Do List**: replaces the old Queue as the single source of truth for what to post, where, and in what order — tasks track steps (retrieve → post → collect) and advance automatically based on game events
- **Task deferral**: items not currently accessible (e.g., on another character's bank) are deprioritized — deferred groups sort to the bottom so you stop cycling through characters with nothing to do
- **Deposit subtasks**: tracks which character holds items that need depositing to warbank, shows "via CharName" source tags
- **Smart character ordering**: Next Steps sorts depositors before receivers
- **Auto-generate on import**: option to skip the Generator and auto-build a to-do list when importing deals
- **Import type tags**: to-do lists show their data source (Inventory Scan, Cross-Realm Flip, TSM Import, Auctionator Import) in headers

### TSM Integration
- **TSM settings page**: profile selector, per-item Auctioning operation resolution (postCap, duration, minPrice threshold)
- **TSM group filtering**: Generator "What to Sell" column filters items by TSM group tree with profile selection
- **TSM price columns**: AH Price column in To-Do and Generator tables with auto-update option
- **TSM threshold skip**: items below TSM minPrice are auto-skipped with reason shown in red
- **TSM character detection**: auto-detects characters from TSM data on login — add or dismiss on the Characters page

### Auctionator Integration
- **Auctionator settings page**: shopping list viewer with item counts
- **Auctionator list filtering**: Generator filters items by Auctionator shopping list

### Inventory & Scanning
- **Enhanced statuses**: Assigned (green) / Posted (yellow, shows "AH: realm") / Check AH (orange, expired) / Unknown (gray) / Ignored (red) — replaces old Queued/Posted/Untracked/DNT labels
- **Live inventory tracking**: inventory DB updates in real-time on every item movement
- **Bank quantity reconciliation**: fixes inflated item counts from stale location data
- **Battle pet detection**: proper handling via |Hbattlepet: pattern and C_PetJournal lookup

### Export
- **Export page**: inline tab with live scan (Bags/Bank/Warbank/All) and Saved All from DB
- **Export filters**: filter by Everything, TSM Group, or Auctionator List
- **Export formats**: FlippingPal CSV and AAA JSON output

### Characters & Realms
- **AH cluster grouping**: characters on connected realms show "Shared AH" with tooltip listing the full cluster and other characters — replaces the old "Dupe" label
- **Character ignore**: click to hide characters from task routing — visible O/X toggle
- **Manual sort order**: Shift+Right-click and Ctrl+Right-click to reorder
- **TSM character detection**: "Detected from TSM" section with Add/Dismiss/Add All buttons

### Automation
- **Auto-deposit to warbank**: new setting — when opening bank, deposits items needed by other characters
- **Gold withdrawal refactor**: fee calculation extracted into reusable functions (CalculatePostingFees, CalculateRequiredGold) for future buy-task support
- **Configurable bank tabs**: choose which bank/warbank tabs to scan and pull from

### UI & Polish
- **Sidebar navigation**: TSM-style dark theme with section headers (To-Do, Tools, Integrations, System)
- **Sortable scroll tables**: click column headers to sort ascending/descending
- **Mini overlay**: compact draggable overlay with deposit/mail detail, expiring auction timers
- **Custom artwork**: addon icon, banner, and logo
- **Import preview**: shows new/update/duplicate with reasons (same realm, connected realm, duplicate in paste)
- **Text overflow fix**: table cells clipped to column bounds

### Under the Hood
- **Consolidated item matching**: unified 4-tier matching (key → ID → name → fuzzy) across all systems
- **Schema versioning**: migration framework for SavedVariables upgrades
- **Error handling**: all C_Item/C_Container calls wrapped in pcall
- **Accent-insensitive realm matching**: handles German/EU realm names
- **Diagnostic export**: `/fq state` for support conversations

---

## v0.5.0
- Partial post detection: posting fewer than queued quantity keeps remainder in queue
- Mail scan updates: detects expired/cancelled auction returns, marks as collected
- State recovery: discovers pre-existing AH auctions not tracked by the addon
- Live auction expiry timer: 60s ticker auto-marks expired auctions, chat notifications
- Consolidated item matching: unified 4-tier matching (key → ID → name → fuzzy)
- Configurable batch size: settings slider for warbank auto-pull batch size
- Accent-insensitive realm matching: handles German/EU realm names
- Warbank batching rewrite: event-driven 5-item batches with error detection
- Configurable bank tab selection: choose which bank/warbank tabs to scan and pull from
- Error handling hardened: all C_Item/C_Container calls wrapped in pcall
- Release channels: alpha/beta/release via tag naming convention

## v0.4.1
- Custom addon icon and banner artwork
- Credits section in Settings page
- Settings redesigned: inline descriptions below each setting, section dividers, improved spacing
- Import preview shows dupe reason (same realm, connected realm, duplicate in paste)
- Import preview detects price changes as "update" instead of "duplicate"
- Queue:Add now applies updated prices on re-import
- Sold item tracking via AH mail scanning (invoice-based, no false positives from cancels)
- Log table Status column: Active, Sold, Expired, Done with color coding
- "Check AH" next step clears when AH is opened on that character
- Login message shows expired auction alerts
- Next Steps gold values match "realms needing a character" counts (warbank-backed only)
- Realm "..." suffix from FP website no longer causes false dedup
- Gold values sort numerically (1.3k, 22.8k, 1.3m handled correctly)
- Hide mini view in combat (toggle in Settings, on by default)
- Mini view shows FQ icon in header
- Minimap button uses custom FQ icon
- AH fee estimate updated: 60% of vendor price (48h post), cap raised to 200g
- Dead code cleanup: removed Rows.lua, Sections.lua, LogPage.lua, trimmed UntrackedSection.lua
- DNT key fix: /fq dnt add now resolves item IDs from inventory

## v0.4.0
- Skip/unskip queue items: Shift+Right-click to skip items where AH price is too low (auto-unskips after 24h)
- Character tracking: gold, last login, class/level per character
- Auction expiry tracking with login alerts for soon-expiring auctions
- Characters page redesigned: Gold, Tasks, Auctions, Last Login, Status columns
- Multi-account support: add external realm coverage in Settings to exclude from "Create char" suggestions
- Mini view shows next steps (top 3 + "more" link)
- Post Now summary view with next steps when done posting
- Do Not Track dialog restyled to match dark theme
- Auto-pull from bank now prints which items were pulled
- Warbank rescanned on bank open for accurate task counts
- Gold withdrawal capped at 100g max (was overestimating AH fees)
- Click handlers use OnMouseDown for reliable modifier key detection
- CurseForge/Wago automated releases via GitHub Actions
- Version auto-detected from .toc (dev builds show "dev", releases show tag version)

## v0.3.0
- TSM-style UI overhaul: dark theme, side navigation, sortable scroll tables
- New pages: Post Now, Queue, Log, Inventory, Characters, Settings
- Characters page with scanned character overview and "realms needing characters"
- Settings integrated as in-window page (consistent styling)
- Minimap button with left-click (toggle) and right-click (settings)
- Queue table "Found On" column shows storage locations (bags, bank, warbank)
- Class-colored character names in Characters page

## v0.2.0
- Collapsible sections in queue view
- Posted items log with price comparison
- Do Not Track list for excluding inventory items
- Untracked inventory section (excludes soulbound/warbound)
- Mini view compact overlay with action icons
- FlippingPal comma CSV parser with RFC 4180 quoted field support
- Item ID column support for FP CSV exports
- Battle pet detection (name extraction, warbank scanning)
- Bind-type detection via tooltip scanning (Warbound Until Equipped)
- Sort by realm or item name
- Auctionator shopping list import
- Auto-pull queued items from bank
- Auto-scan bags on login

## v0.1.0
- Initial release
- Import from FlippingPal website copy-paste
- Import from semicolon CSV and tab-delimited formats
- Queue management with character routing
- Inventory scanning (bags, bank, reagent bag, warbank)
- Automatic post detection via AH bag monitoring
