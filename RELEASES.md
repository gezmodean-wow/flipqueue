# FlipQueue release notes

This file is the **player-facing** changelog. It's what shows up on CurseForge and Wago project pages. Plain language, organized by what players see and do — no file paths, no internal terminology, no commit references.

The engineering-detail companion lives in `CHANGELOG.md` (commit-readerese — file:line, internal jargon, full alpha-by-alpha breakdown). When working on FlipQueue, update both: `CHANGELOG.md` for the engineering record, this file for the player surface.

---

## v0.12.0 (in development)

The v0.12.0 line is currently in alpha. The notes below describe what will land in the public release once the alpha series stabilizes.

### New: Auto / Manual / Disabled for every managed action

The settings model has been rebuilt around three states per action instead of the prior on/off + master-switch combination:

- **Auto** — runs on bank open, button still works manually
- **Manual** — button works, doesn't auto-fire (so opening the bank doesn't surprise you)
- **Disabled** — action is hidden everywhere (no drawer button, no popup section, no auto-fire)

Items have three independent action classes: **Tasks** (pull + deposit-to-do paired), **Extras**, and **Reagents** (split out from extras into its own group so you can auto-deposit your gear/glyph leftovers without sending crafting mats too). Gold has two: **Withdraw** and **Deposit**.

Practical consequence: the behavior the alpha13 testers hit where "the per-character toggles were off but I still wanted to click the buttons manually" works correctly now. Manual access stays available unless you explicitly pick **Disabled**, regardless of whether auto-fire is on.

The **Pause Automation** drawer button does what its name says now — it pauses auto-fire on bank open. Drawer buttons stay visible and clickable while paused, so you can still pull or deposit on demand. Previously, pausing also disabled all the manual access, which was the wrong thing.

The **Deposit Tasks** drawer button (renamed from "Deposit Items" so it's clear it deposits the items routed to your other characters via the to-do list) sits next to a new **Deposit Reagents** button.

Existing setups migrate silently: anything that was auto-firing keeps firing; anything that was off becomes Manual (button still works, just no auto-fire on bank open). One chat line on first load explains where to find the new controls. If you actually wanted an action to disappear entirely, set it to Disabled from Settings or click a character row on the Characters page for the per-character override.

### New: Manage my items / Manage my gold master switches

The Settings page now opens with two big switches: **Manage my items** and **Manage my gold**. Each one decides whether FlipQueue is allowed to move that resource for a given character. Per-character overrides on the Characters page take precedence — useful for letting FlipQueue handle items globally but turning it off for a specific alt without touching anything else. When a master is off, the corresponding drawer buttons hide, the bank popup skips that section entirely, and the related sub-settings dim to make it clear they're inactive.

The Characters page's defaults bar got the same treatment — renamed to **Character Defaults**, with the Items group on a blue background and the Gold group on a gold background, each with its own master switch. When you turn a master off, its sub-checkboxes hide and a `(disabled)` label appears in their place. The bar header is now distinct from the broader **Settings** page so they aren't conflated.

Existing setups migrate silently — your current behavior is preserved, with a single chat line on first load explaining where to find the new switches. Behind the scenes, the planner and executor now share a single source of truth for "is FlipQueue allowed to move this?" — which closes a long-standing class of bugs where deposit operations would silently skip without explanation (toeknee's repeating "deposit completed but didn't actually move anything" report).

### Settings menu reorganized

The settings page now reads top-down as **General** → **Item Management** → **Gold Management** → (existing sections). Item Management collects the master switch plus reagent / overflow / batch-size controls. Gold Management collects the master switch plus Warband Miser integration / withdrawal / max-cap / deposit / default-gold-to-keep. The old "Bank & Warbank" section is gone — its contents redistributed under the two management sections.

The "Show Tutorial Again" and "Run Setup Wizard" buttons moved from the bottom of the settings page into the General section so they sit with the rest of the account-level controls. The in-settings "About FlipQueue" link is gone — see the new About sidebar tab below.

### New: About page in the sidebar

A standalone **About** page in the main FlipQueue window (between Settings and Tutorial in the sidebar) now shows your installed version prominently, along with the embedded Cogworks-1.0 library version and current WoW build. Plus credits, links to GitHub / Discord / CurseForge / Wago, and a one-click **Copy diagnostics** button that bundles version + relevant addon list into a clipboard-ready block for bug reports.

`/fq version` is a new chat command that prints `FlipQueue v0.12.0-alpha11 (Cogworks-1.0 MINOR …)` in one line, useful for confirming your installed version when reporting bugs. Every `/fq debug *` output now starts with that same version line, and the in-game debug console window's title bar shows it too — so screenshots / pastes self-identify which build they came from.

### Pet bandage / bag-click error after pet battle: fixed

If you saw a red `ADDON_ACTION_FORBIDDEN` error after a pet battle — pet bandages refusing to work, the bag UI partly locked, the game menu / logout silently broken until `/reload` — there were two separate causes contributing, and both are now closed.

The first surfaced when FlipQueue was mid-bank-operation as a pet battle started: protected container calls running through timer continuations left a taint trail that pet-battle UI lockdown surfaced on the next click. FlipQueue's bank queue now pauses cleanly when combat or a pet battle starts and resumes when both clear, with a chat banner so you know what's happening. Cursor state is defensively cleared between every move to keep taint from chaining forward.

The second was upstream — Cogworks (the shared library FlipQueue, Tempo, and the rest of the suite use) had a key handler that intercepted ESCAPE in a way that interfered with Blizzard's secure game-menu path. This one fired even when FlipQueue itself was idle, because the library is loaded with the addon. Players who hit the issue while FlipQueue was doing nothing in particular (the niduin case in our tracker) were on this path. Fixed by bumping the embedded Cogworks library to v0.13.1.

If you've been seeing the error in any flavor, this build should close it.

### Auction house scanning and posting works smoothly with TSM

Players running FlipQueue alongside TradeSkillMaster reported that the auction house felt sluggish — scans took tens of seconds to start, posts occasionally got skipped from TSM's queue, and the slowness scaled with how many items were in the bag. The root cause was FlipQueue doing its own work in parallel with TSM and competing for Blizzard's auction house rate limits.

The fix is layered:

- FlipQueue's auto-scan-on-AH-open is now opt-in. With TradeSkillMaster or Auctionator installed, the setting defaults to off, so FlipQueue stops issuing its own price queries in parallel with theirs. Manual **Scan To-Do** and **Scan All** buttons in the AH drawer remain as on-demand triggers when fresh prices are wanted. (Re-enable the auto-scan from Settings → Auction House if the old behavior is preferred.)
- The auction window opens immediately instead of pausing while FlipQueue refreshes its task list. The refresh runs a fraction of a second later in the background.
- Posting bursts (during a TSM Post Scan) no longer cause repeated bag-state rescans on FlipQueue's side.
- TSM's post queue no longer occasionally skips items when FlipQueue is loaded. (FlipQueue used to refresh its owned-auctions view after every post regardless of who initiated it; now only after FlipQueue's own posts.)
- Cross-account inventory broadcasts only fire when something actually changed.

### Bank operations: progress feedback and reliability

The bank operations popup that drives Pull, Deposit, and Pull Saleable used to look frozen during long bursts and didn't always tell players what failed. Several improvements:

- A countdown timer between moves replaces the prior cycling animation. Each step says what it's waiting for ("Verifying moves", "Waiting for bag update", "Retrying 4 failed moves") with a definite duration.
- The deposit phase ticks per move instead of jumping in batches.
- Long pulls (80+ items) no longer report "1 pull failed" for items that actually moved — the verify-race that caused tail items to look stuck has been fixed.
- After a session ends with a failed pull, the next bank reopen automatically retries instead of skipping straight to deposit. A yellow banner explains what's happening.
- Failed items show by name in the completion summary instead of just an error count.
- The bank operations popup no longer plans "Deposit Extras" ops when that setting is turned off. Previously these ghost ops left the popup's progress bar showing wrong-looking "complete" states with items still in the bag.

### Per-character gold management overrides

Each character now has independent **Withdraw Gold** and **Deposit Gold** toggles on the Characters page, mirroring the existing Pull / Deposit / Deposit All toggles. Defaults to "use global" — no behavior change unless explicitly overridden. Useful for letting FlipQueue manage gold globally but turning it off for one alt without touching account-wide settings.

### Logging into a new character is faster

Switching characters used to cause a noticeable hitch as FlipQueue refreshed its view of every alt's bags. The refresh now spreads across multiple frames, and the Characters page shows a progress banner so it's clear what's loading instead of looking blank.

### Item variant data preserved everywhere

Posted auctions in the log used to lose their bonus-ID variant info, collapsing different versions of the same item (an ilvl 253 piece and a base-ilvl piece) into one row. Bag scans now preserve the full variant key going forward, and DealFinder shows correct per-variant pricing for items that come in ilvl variants. Tooltip rendering across every page now displays the right variant instead of falling back to base-form.

### DealFinder per-realm pricing fix for ilvl variants

DealFinder was showing a single flat regional value for variant gear (most modern items with bonus IDs) instead of the actual per-realm prices. It now resolves real per-realm pricing for variant items, so a Greatlock Girdle ilvl 253 shows distinct prices on each realm instead of one synthetic value across all of them.

### Auctionator and FlippingPal integrations work end-to-end

- Auctionator shopping lists generated from buy tasks now use a max-price ceiling that correctly captures items priced just below the next whole gold (a 200g target accepts up to 200g 99s 99c).
- The "Auctionator" output format on the Transform page now produces the actual Auctionator wire format that the addon can re-import.
- Auctionator-imported shopping lists now preserve their full per-item metadata (quantity, exact-match flag, ilvl filters, quality) instead of stripping everything except the name.
- Importing a very large to-do list (4,000+ items — full-region FlippingPal dumps in any of the supported formats: website copy-paste, downloadable CSV, the FP-extractor addon's semicolon export, or a tab-delimited table) no longer freezes the game. A progress message shows status during long imports. Earlier alphas only covered the website copy-paste path; this one covers the CSV / semicolon / tab-delimited paths too, including the regex-heavy line-classification pre-roll that ran before the per-item progress started ticking.
- FlippingPal prices in German EU client formats (`1.500g`, `2.000g`) parse correctly to 1500g and 2000g respectively, instead of being misread as 500g and 0g.
- The Transform page's AAA JSON output now shows when items couldn't be included because their names hadn't been resolved to item IDs yet — instead of silently producing a smaller list than the source. With an Auctionator-imported source where the WoW item cache hasn't seen the names, the output prompts you to click the **Deep Search** button (which warms the cache from your TSM and Auctionator data) to resolve them.

### DealFinder profit %: optional abbreviation

For very-cheap items where DealFinder finds extreme deal multiples (`+12,500%`), a new opt-in setting collapses 4-digit-plus values to `1.5k%`, `25k%`, `2.5M%` form. Off by default; enable it in DealFinder's config if your sell list has lots of deep-value items.

### Phantom expired-auction notifications resolved

The login message saying "N expired auctions to collect" sometimes fired when there were no expired items in the mailbox. Cancelled and expired auctions are now distinguished correctly, mail reconciliation handles empty mailboxes properly, and pet matching uses the species ID instead of the (always identical) "Pet Cage" item name.

### Cogworks gear-border minimap

The minimap button now uses the brass gear-border styling shared across the Cogworks suite. Visual change only — click and drag behavior unchanged.

### Support and diagnostic commands

When a player reports something off, several `/fq debug` commands help capture what's happening:

- `/fq debug perf` — bundles per-addon CPU/memory, FlipQueue's internal cache stats, and current settings into one copy-pasteable text dump. Use after `/console scriptProfile 1` + `/reload` to capture an actual CPU profile.
- `/fq debug pulls` — toggles per-operation tracing during bank queue activity. Useful for diagnosing item-specific bank op failures.
- `/fq debug parsegold` — interactive gold-string parse trace plus a self-test covering EN/DE locale variants, k/m abbreviations, and color-coded strings. Lets US-locale testers verify EU client behavior without an EU account.
- `/fq debug log <name or itemID>` — dumps every entry the addon's log holds for a given item, with full sale / fee / status metadata. Useful when Item Research shows a sales count that doesn't match what the player remembers.
- `/fq debug expired`, `/fq debug realms`, `/fq debug pricing`, `/fq debug bagprices` — various diagnostic dumps for support investigations.

---

*For previous public releases, see `CHANGELOG.md` in the source repository.*
