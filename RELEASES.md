# FlipQueue release notes

This file is the **player-facing** changelog. It's what shows up on CurseForge and Wago project pages. Plain language, organized by what players see and do — no file paths, no internal terminology, no commit references.

The engineering-detail companion lives in `CHANGELOG.md` (commit-readerese — file:line, internal jargon, full alpha-by-alpha breakdown). When working on FlipQueue, update both: `CHANGELOG.md` for the engineering record, this file for the player surface.

---

## v0.13.1-alpha4

One fix, and it's the big one for anyone whose game died the moment they pasted a large FlippingPal export.

- **Pasting a huge export no longer crashes the game.** It turns out the crash happened *while the paste was still arriving* — on some systems the game delivers a paste one character at a time, and FlipQueue was re-reading the entire pasted text on every one of those events. On a few-hundred-KB paste that adds up to a colossal amount of wasted memory in a fraction of a second, and the client died before any progress bar could appear. FlipQueue now waits quietly until the paste has fully arrived (you'll see a "Receiving paste..." note for big ones), reads it exactly once, and then processes it in the background as before.

## v0.13.1-alpha3

This build fixes a serious bug where FlipQueue couldn't find deals on the auction house that were sitting right there — plus two import-and-inventory annoyances.

- **Your shopping lists find deals again.** Version 0.13.0 added a "Match exact item level" option to the Auctionator shopping lists FlipQueue builds, and turned it on for everyone. The catch: the auction house shows item levels *scaled to your character's level*, and most of us buy on low-level characters — so the exact match quietly hid almost every armor and weapon listing. Only recipes, pets, and similar items still came up, which made it look like your imported deals had vanished from the AH. The option is now **off** by default (a chat message will tell you it changed). If you snipe specific gear variants on a max-level character, you can turn it back on in Settings → Auctionator.
- **Pasting a big FlippingPal export is easier on the game.** The paste box now empties itself the moment a large paste is picked up — just holding that much text on screen was enough to freeze the game, even with the import itself running in the background.
- **Right-clicking items in the Inventory tab always responds now.** Before, items already assigned to your queue ignored the right-click completely — which felt like "I can't add anything to Do Not Track," especially right after an import when almost everything is assigned. Now assigned items open a small menu (**Remove from queue** / **Add to Do Not Track**), posted items tell you the live auction has to be collected or cancelled first, and if an action can't find anything to act on you get a message instead of silence.

## v0.13.1-alpha2

More freeze fixes for large accounts — this build finishes the job alpha1 started. If you tested alpha1 and still froze, this one is for you.

- **The Generate button no longer freezes the game.** alpha1 only covered the automatic "generate after import" path. If you have that option switched off — or you just click **Generate** yourself, or change a filter, or reorder your priorities — you were still hitting the old freeze with no progress bar. Every one of those now builds in the background with a progress bar.
- **Full auction house scans don't lock up the client.** If you run Auctionator, its full scan made FlipQueue read the entire auction house in one go, freezing you for seconds at a time. Busy realms were far worse than quiet ones. That work now happens in the background.
- **FlipQueue stops hogging memory over a long session.** Its record of scanned auction prices had no size limit while you played, so on a busy realm it grew until you logged out — one reported session ballooned to over 400 MB. It's now capped as you go.
- **Opening the auction house is smooth again.** FlipQueue cross-checks your sales against TradeSkillMaster's records shortly after you open the AH. On big TSM setups that check froze the client, and it ran again each time you switched characters. It now runs in the background.
- **Checking mail and posting is faster.** Several checks were re-scanning your whole account's inventory far more often than they needed to — worst when you have many characters and a big to-do list.

## v0.13.1-alpha1

Performance fixes for large accounts. If you run a lot of characters and import big cross-realm lists, FlipQueue could freeze — sometimes badly enough to need a game restart — while importing, or while checking mail and posting. This build fixes the three causes:

- **Importing a big list no longer freezes the game.** Building your to-do list from a large import now runs in the background with a progress bar instead of locking up the client, and it does far less duplicate work along the way.
- **Checking mail and posting stays smooth.** Refreshing your to-do steps no longer re-scans your whole account's inventory for every task on every bag change — the part that made posting and mail lag pile up when you have lots of characters.
- **Your sales log won't grow without limit.** "Max entries kept" now defaults to 10,000 instead of unlimited, so a long-running account's log can't balloon and slow things down. Want to keep everything? Set it back to Unlimited in Settings → Sales Log.

## v0.13.0

The big themes this release: a rebuilt Tools drawer you arrange yourself, a Deal Finder that steers around realms you're already posted on, more control over pricing and your to-do lists, and support for the latest WoW client and TradeSkillMaster. Everything below is new since v0.12.0.

### A Tools drawer you arrange yourself

The Tools drawer is now yours to lay out — show or hide each tool, reorder them, and choose how each service is summoned. You can also add your own macros so the things you reach for most are one click away.

### Deal Finder gets smarter about where to sell

- **Avoids realms you've already posted on**, steering each item toward a realm where you're not already competing with yourself — so you stop splitting your own listings.
- **Pick which FlippingPal column** sets your expected price, so thin items stop importing with wildly inflated numbers.
- The deal-priority controls no longer overlap the section beneath them, and list scrollbars sit flush instead of leaving a gap on shorter lists.

### More control over your to-do lists

- **Regenerate an existing list** without re-pasting your deals — rebuild in place when prices or inventory shift.
- **Clear Current vs Clear All** are now separate buttons, each with a confirmation. "Clear all" no longer leaves a queued list behind.
- **Finished lists are archived** instead of deleted, so you can rebuild from them later.
- **Item-level filtering on Auctionator shopping lists**, so the right gear variant comes up first.

### FlippingPal inventory scans read correctly

When you scan your inventory on FlippingPal, the deals it sends back are "sell what you already own on another realm" — there's no buying involved. FlipQueue was mistakenly treating those as cross-realm flips and adding pointless buy steps. Now they're correctly recognized as sell deals.

> Heads up on inventory scans: FlippingPal only returns the items it found a worthwhile sell on. If you send 300 items and get 40 back, that's normal — the rest just didn't have a good cross-realm sale.

### Pause and trim your sales log

A new **Sales Log** section in Settings lets you turn sales logging off, choose how long history is kept (from 7 days up to a year, or forever), and cap the total number of entries. Your existing history and the previous 30-day default are untouched unless you change them.

### Smooth auction posting

Posting a batch of auctions no longer causes lag or stutter, even with a heavily stocked bank. Your bank items still count toward your deals — FlipQueue just stops re-reading everything on every post.

### Updated for the latest WoW and TradeSkillMaster

FlipQueue now targets the current WoW 12.0.7 client, so it no longer shows as out of date. Posting behavior has been re-checked against the newest TradeSkillMaster (v4.14.69) and continues to match it.

### Smaller polish

- Warbound gear stays out of auto-generated AH lists.
- Routine confirmations now show as brief toasts instead of cluttering your chat.
- Buy and sell rows are visually distinct in the mini overlay, and buy rows relabel themselves through the `[BUY]` → `[CHECK MAIL]` → `[DEPOSIT]` lifecycle.

## v0.13.0-alpha4

A focused alpha: the Deal Finder no longer sends items to realms you're already selling them on.

### Deal Finder avoids realms you've already posted on

Before, the Deal Finder could pick a realm where you already had that item up for sale. You'd fly there, pull from your warbank, open the auction house — and FlipQueue would spot the duplicate and drop the task, wasting the trip. Now it checks what you already have posted and steers each item to a realm you're *not* already on, moving to the next best realm instead.

- **On by default.** Turn it off in Settings → Deal Finder ("Avoid realms where I already have an auction posted") if you'd rather rank every realm purely by price.
- Realms you're already posted on are marked **POSTED** in the realm list. They stay selectable — if you do want to add to an existing listing, just click to pick one.
- If *every* realm for an item is one you're already on, the item isn't dropped. FlipQueue still shows it and flags the situation so you can decide.

## v0.13.0-alpha3

A focused alpha: the Tools drawer has been rebuilt from the ground up.

### The Tools drawer is now yours to arrange

Every summon tool — auction house, vendor, warbank, hearthstone, mailbox, banker, and your own macros — now lives in one drawer you control.

- **Show, hide, and reorder** any tool from Settings → Toolbox. Mailbox and banker start hidden; turn on whatever you use.
- **Pick how each service summons.** Most services have several options — a toy, a mount, an item, a spell. Set the order you prefer and FlipQueue uses it.
- **Add your own macros** straight from your saved macro list.

### Smarter summoning

Hover any service and a small sub-drawer rolls out with every way you can summon it, so you can pick on the spot. FlipQueue also chooses for you: if you're already on a relevant mount that one wins, otherwise it uses your highest-priority ready option, otherwise whatever comes off cooldown first.

### Find your way there

Each service gets a find button that drops a map waypoint and quest arrow to the nearest spot FlipQueue has seen it — handy for mailboxes and bankers in unfamiliar towns.

## v0.13.0-alpha2

A bigger alpha than originally planned. The three follow-ups from alpha1 are all in (mini overlay buy/sell visual fix, TSM-skipped task cleanup, price-inflation root cause), plus three new features that landed while tracking down the inflation: a price-source dropdown so you can pick which FlippingPal column to trust, a Regenerate track on the To-Do Generator that rebuilds an existing list without a fresh paste, and proper ilvl filtering on Auctionator shopping lists. Old to-do lists also now stick around instead of getting deleted on completion.

### Pick which FlippingPal column to use for expected price

The alpha1 "wildly inflated expected price" reports turned out to come from FlippingPal's *Listing price* column — the aggressive recommendation FP suggests posting at. On thin items, that recommendation can run 50–150× above what the item actually sells for on your realm, and TSM then refuses to post anything because the listing is "below min."

There's a new **FlippingPal price source** dropdown in Settings → Imports:

- **Listing price** (default) — FP's aggressive recommendation. Matches how alpha1 behaved; pick this if your import data is already where you want it.
- **Sale Avg** — FP's conservative historical median. Lower expected prices, but they actually post.
- **Auto** — Use Listing price normally, but fall back to Sale Avg when Listing is more than 10× TSM's region market average. Best of both for most setups.

The setting applies on the next generate (or regenerate, see below). Existing to-do lists keep their stored prices until you rebuild.

If you want to see what's actually in your data, `/fq debug pricesource <item name>` (or shift-click an item into the command) dumps the stored price + every upstream price field for matching tasks. The diagnostic was the bridge to the fix, but it stays in for triaging any future price weirdness.

### Regenerate an existing to-do list without re-pasting

To-Do Generator gets a fourth card: **Regenerate**. The flow rebuilds an existing list from saved data instead of forcing you to paste FlippingPal again every time you want to refresh prices.

Three steps:

1. **Pick List** — choose from your active list, any queued lists, or archived lists (see the archive note below)
2. **Edit Tasks** — every task on the source list is shown with an X button; click to drop items you don't want, click again to bring them back
3. **Refresh & Save** — pick how prices get refreshed: *Use FP saved data* (re-runs the price column through your current FlippingPal price-source setting) or *Use my TSM op* (evaluates your TSM Auctioning operation's normalPrice expression for each item — supports the complex formulas like `max(DBMinBuyout-1c, 250% DBRegionMarketAvg)`). Save commits the regenerated list as queued (or as the active list if you don't have one).

The preview surfaces three states per task:

- **POST** (green) — sell as planned
- **BUY** (cyan) — you don't have inventory for this sell anymore, so it converted to a buy task using the cheapest known source
- **SKIP** (orange) — either no inventory and no buy source, or the regenerated price is below your TSM minimum, so it stays out of your active list. The reason shows next to the row.

Skipped rows still appear in the log so you have a record of what was dropped and why.

### Auctionator shopping lists filter by item level

If you push your buy tasks to Auctionator, the generated shopping-list searches now constrain to the exact item level of the task. Previously the searches left the ilvl fields blank, so an ilvl-220 Tarnished Dawnlit Band buy task would surface every ilvl variant — you had to disambiguate by hand. Now the search is exact-ilvl by default.

There's a new **Match exact item level** checkbox in the Auctionator settings panel if you want any-ilvl matches back. Default is on.

### Old to-do lists archive instead of disappearing

When a list completes, gets manually deleted, or gets replaced by a new generation, it used to vanish entirely. The per-task log preserved task-level history, but the list-level shape (the name, the specific set of tasks, who was assigned where) was gone. Lists now snapshot into an archive instead — up to 50 entries, newest first, with the reason they got archived ("completed", "discarded", "replaced") and how long ago.

The archive surfaces in the Regenerate Step 1 picker so you can rebuild a list from your history. A dedicated history view (browse, restore, delete archived) is still on the roadmap — for now Regenerate is the way to revisit old lists.

Note: only lists created or deleted from this version onward get archived. Anything already gone from previous alphas stays gone.

### Buy and sell rows look different in the mini overlay now

Every row in the mini overlay carries a colored verb prefix at the start of the item name:

- **`[POST]`** in green — sell tasks
- **`[BUY]`** in cyan — buy tasks at the AH step
- **`[CHECK MAIL]`** in yellow — buy tasks waiting for mail delivery
- **`[DEPOSIT]`** in orange — buy tasks ready to drop into the warbank

Previously only buy rows carried a prefix. A sell row tucked between buys would visually disappear into the buy stack and end up not getting posted. The new sell-row prefix solves that at-a-glance read.

### TSM-skipped sell tasks now clear from the active list

When TSM rejects a post because the AH price is below your minimum, the skipped task is recorded in the log and removed from the active to-do — same as a finished post. Previously the task stayed visible (as a `skipped` row) and accumulated as cruft across posting sessions. The skip reason is preserved in the log entry so you can still audit which items got rejected and why.

If you have a linked partner account, the skip propagates so your partner's view stays in sync.

## v0.13.0-alpha1

First alpha on the v0.13.0 line. The headline fixes a long-standing leak where Warbound gear was sneaking into your auto-generated to-do list, plus a polish pass on chat noise: posting, pulling, depositing, importing, saving, and linking confirmations now show up as toasts in the top-right of the screen instead of chat lines. Behind the scenes, the addon is in the middle of consolidating onto the shared Cogworks library; this alpha lands the first wave of that consolidation. The bigger UI swaps (main window, settings page, mini overlay, setup wizard, bank popup) are queued behind matching upgrades on the Cogworks side and will land in future v0.13.0 alphas.

### Warbound gear stays out of the auto-generated AH list

If you ran *To-Do Generator → Deal Finder* and saw Warbound or Warbound-until-Equipped gear queued up to post, that should no longer happen. The previous filter caught fully soulbound items but missed warband-bound stacks because they look like regular tradeable gear at the API level. The new filter scans each item's tooltip for the "Warbound" / "Warbound until Equipped" lines (the same way Syndicator does) and excludes them from the pool.

If you have an existing to-do list with warbound items already queued, regenerate the list to clear them — entries from before this update stay in your data and the filter only activates when items are next scanned.

### Confirmations now toast instead of cluttering chat

Posted, pulled, deposited, imported, saved, linked, unlinked — every "yes, that happened" confirmation now appears as a brief toast in the upper-right corner instead of as a chat line. The toasts stack when several fire close together (during a posting run or bank operation) so you can glance at the corner instead of scrolling chat. Errors and warnings still go to chat — those want your full attention.

### Mini overlay: redundant manual button removed

The "Refresh Auctionator Buy List" row in the mini overlay is gone. The buy list already rebuilds automatically when you open the auction house, after every post, after every buy, when you toggle the Auctionator integration on/off, and after deleting a list. The manual row was just an extra trigger for the same path — and on busy realms with lots of buy rows it ended up scrolled off-screen anyway. If you ever need a manual rebuild, `/fq` will gain a slash command for it in a future alpha.

### Slash commands restructured

`/fq` and `/flipqueue` still work for everything they did before. A few small differences you might notice:

- **Garbage subcommands print a usage hint instead of toggling the window.** Typing `/fq clear foo` (or any unknown subcommand) now prints a brief list of what's available instead of opening the FlipQueue window.
- **Errors inside slash handlers no longer pop the WoW error frame.** They print as a yellow line in chat instead — easier to dismiss, easier to copy for bug reports.
- **`/fq help` is now auto-generated** from the registered subcommand list, so it stays in sync as new commands get added.

### Debug console refresh

`/fq debug` opens the debug console with a slightly different look — the chrome is the new shared Cogworks debug surface, tabs for Actions / Inspectors / Profile / Log, and the toggle button reads "Toggle debug" instead of the dedicated "Toggle debug mode" action button. All the FlipQueue debug actions (bank popup tests, export FQ state, copy debug log, etc.) still work as before. The chat-echo line for debug messages reads `[FlipQueue debug]` instead of `FlipQueue [debug]:` — closest match the shared library supports without a custom prefix.

### Known issues

- **Some to-do tasks may show wildly inflated expected prices** vs the actual auction-house market. This is being investigated — the suspected cause is German thousands-separator parsing on FlippingPal CSV imports (where `113.190` gets read as `113,190` instead of `113.19`) or a unit mixup in the Deal Finder profit calculation. If you see prices that look 100× to 1000× too high, regenerating the to-do list after the fix lands will clear them; in the meantime you can manually skip the affected rows.
- **Buy and sell tasks look identical in the mini overlay.** If you have a sell sandwiched between several buy rows on the same character, the sell row can visually disappear into the stack and end up not getting posted. A visual differentiation pass (icon tint, row stripe, or pill marker) is queued for the next alpha.
- **TSM-skipped sell tasks stay in the active to-do list.** When TSM rejects a post because the AH price is below your minimum, the task is marked skipped but doesn't auto-clear out of the active list the way a manual skip does. They're safe to skip manually for now; a clean-up pass is queued for the next alpha.

## v0.12.0

Public release. The big shifts since v0.11.x are the Auto / Manual / Disabled per-action settings model, the **Manage my items** / **Manage my gold** master switches, the live Auctionator buy-list sync, and the buy-task workflow labels in the mini overlay (`[BUY]` → `[CHECK MAIL]` → `[DEPOSIT]`). Plus a long arc of bag-taint hardening, the deposit-planner correctness pass, and the Generator-wizard chunked-parse fix so huge FlippingPal pastes don't freeze the client.

### Generator wizard handles huge pastes without freezing

The earlier import-chunking work covered the dedicated Import page, but the Generator wizard's own paste box was still parsing synchronously. Pasting a full-region FlippingPal scan (a few thousand deals) into the wizard would freeze the client for several seconds. The wizard now routes large pastes through the same chunked parser the Import page uses, with a status line that ticks `Parsing 1234 / 4509 items...` so you can see progress instead of staring at a frozen screen.

### Auctionator buy list now updates itself as you shop

Your FlipQueue buy list in Auctionator is now a living list. Open the auction house and FlipQueue maintains a single shopping list called **FlipQueue - Buy** that mirrors what your current character still needs to buy. As you make purchases and the items land in your bags, those items drop off the list automatically — no more wondering whether you've already bought enough.

How it works:

- **One list per character session** by default. Switch characters and reopen the AH; the list refreshes to show what *that* character needs.
- **Auto-refresh** on AH open and after every purchase, so the list always matches what's still outstanding.
- **A manual Refresh button** on the Auctionator page in case you want to force an update — handy if you've just imported new deals.

If you'd rather have the old behavior of one list per buy realm, that's still available — flip the **One list per realm** option on the Auctionator page. In that mode, when a realm's buy list goes empty FlipQueue cleans the empty list out of Auctionator's dropdown so old realms don't pile up.

### Buy task labels follow the lifecycle

Buy tasks in the MiniView and the To-Do page now relabel themselves as you move through the workflow, so each row tells you what to do next instead of staying frozen on "[BUY]" the whole way through:

- **[BUY]** (cyan) — still need to click it in the auction house
- **[CHECK MAIL]** (yellow) — purchase confirmed, walk to the mailbox to collect
- **[DEPOSIT]** (orange) — item is in your bags, drop it in the warbank so the sell character can pick it up

The switch from **[BUY]** to **[CHECK MAIL]** happens the instant you click Buy — the same instant you hear the buyout sound — not when the item arrives in your bags. For items won by bid (mail-delivered hours later) this is a big difference: the row would previously stay stuck on "[BUY]" until you actually collected the mail.

The MiniView title at the top splits the same way: you'll see `X to post, Y to buy, Z in mail, W to deposit` so each physical action is countable independently.

The Auctionator shopping list reflects the same change — items drop off the list the moment you click Buy. This is especially useful for items won by bid where the old behavior would leave them on the shopping list indefinitely.

### Wallet and warbank now know when you've already bought

Two follow-on fixes from the lifecycle work above. Previously, once you'd bought items but hadn't yet deposited them to the warbank:

- The auto-withdraw still pulled extra gold "to pay for" the items you'd just paid for — your wallet kept ballooning every time you opened the bank.
- Auto-deposit to the warbank silently skipped those items because the buy task itself was "claiming" them, so the cross-realm flip stalled at the deposit step indefinitely. You'd see a `[DEPOSIT]` row in the MiniView, open the warbank, and nothing would happen.

Both flows are now lifecycle-aware:

- The withdraw target only counts gold for buys still ahead of you (browse / buy step). Items already in your bags don't double-charge.
- The deposit planner stops letting the buy task block its own item — once you reach the warbank, the bought item moves over for the sell character to retrieve, and the buy task progresses to completion.
- The deposit planner now also fires off the buy task itself when a paired sell task is missing or unassigned. Previously the deposit step relied entirely on the sell-side task being present; if there was no sell character configured for the target realm, your bought item would sit in your bags indefinitely with the To-Do list stuck at "deposit". Now the buy task drives its own deposit so the warbank handoff completes either way.
- When you have a post task for an item AND another character also has a task for the same item that you're meant to source for them, the deposit planner now keeps only the units you actually need to post. Surplus stacks flow to the warbank for the other character on the same trip, instead of all of it staying behind because "this char also needs some" — the partial-stack overlap that left units stranded in bags is gone.

### Auctionator search results: better matches by default

The shopping list FlipQueue creates now searches more loosely on quality and crafting tier. Several testers reported items being on the AH at or below their target price but not appearing in the FlipQueue list — the most common cause was an item carrying bonus IDs that bumped its quality to a higher bracket than the deal record knew about, which caused Auctionator's exact-match filter to skip it.

The new defaults match on item name and price ceiling only, so those listings now show up. If you want strict matching back, two new toggles on the Auctionator settings page let you opt in:

- **Match exact quality** — useful when you only want one specific bracket.
- **Match exact crafting tier** — useful for crafted reagents where tier 1/2/3 are very different items.

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

### German EU buy tasks with prices like `2.000g`: parser handles hidden characters

A long-tail follow-up to the earlier fix that taught FlipQueue to read German-locale prices (`2.000g` → 2000g, dot as thousands separator). The fix worked for most players, but at least one tester kept seeing buy tasks skipped with `(no price)` even after updating. Cause was a non-breaking space character that some web pages — including FlippingPal's — invisibly insert between the digits and the `g` suffix on EU locales. Copy-paste preserves the byte, but it doesn't render, so it looked like a bare `2.000g` to anyone reading the log.

The parser now strips invisible whitespace and zero-width characters before matching the number, covering the realistic candidates (non-breaking space, narrow non-breaking space, zero-width space / joiner / LRM / RLM, byte-order mark). German EU buy tasks should resolve cleanly across all tested input sources.

### Mini-view restore after instance: doesn't override your manual hide

Alpha17's new "Hide mini view in raids and dungeons" setting had a small logic bug: if you'd manually closed the mini (close button) before zoning into an instance, the mini would reappear after you zoned out — even though you hadn't asked for it back. The hide-tracker was claiming responsibility for hides it hadn't actually performed. Now it only restores the mini if it was actually the one that hid it.

Only triggered if you'd turned the new instance-hide toggle on (default is off), so most players didn't see it.

### Bag clicks broken in raids / after pet battles: hardened

If you've ever seen the bag UI go dead after a raid pull or a pet battle — items refusing to right-click, pet bandages or knowledge tomes silently failing, the game menu or logout broken until `/reload` — multiple paths were contributing, and this build closes the rest of them.

Each previous alpha closed one path:

- Earlier in the v0.12 line: FlipQueue's bank queue learned to pause when combat or a pet battle starts, and resume when it clears. Cursor state is defensively cleared between every move so nothing carries forward.
- A Cogworks library bump (the shared core FlipQueue ships with) closed an ESCAPE-key handler that interfered with Blizzard's secure game-menu path.
- A second Cogworks bump closed a related issue specific to right-click on items that prompt a confirmation popup (knowledge tomes were the most visible victim).

This alpha adds another layer:

- The bank queue's batched flow — the path used by auto-deposit of extras, reagents, and to-do tasks — now pauses on combat the same way the simpler paths already did. A queue that started cleanly and then ran into a raid pull no longer leaks the issue through to your bag UI.
- The protected container calls themselves now refuse to fire if combat starts at the wrong moment, regardless of which code path led to them. Belt-and-suspenders.
- A new **Pause bank ops in raids and dungeons** setting (default on) holds auto-deposit and auto-pull while you're inside a raid, dungeon, battleground, arena, or scenario. Resumes automatically when you leave. Banks aren't reachable inside an instance anyway, so this is purely defensive.
- A new **Hide mini view in raids and dungeons** setting (default off) lets you keep the mini overlay during open-world play but hide it for cleaner raid frames. Works alongside the existing combat-hide toggle — turn either or both on.
- A new internal listener catches any future taint event blamed on FlipQueue and writes a short snapshot for diagnosis. If you ever see this issue again on a future build, your bug report lands with hard evidence already attached.

If you've been seeing this in any flavor, this build should close it.

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

### Right-click on profession knowledge tomes works again

A taint bug in the shared Cogworks library blocked right-click "use" on items that prompt a Blizzard confirmation popup — the most visible victims being TWW Midnight profession knowledge tomes (Glimmer / Flicker of Midnight Jewelcrafting / Blacksmithing / etc. Knowledge). Equipment, tradegoods, and most other items were unaffected. If you saw `AddOn 'cogworks' tried to call the protected function 'UNKNOWN()'` after right-clicking one of these consumables, this was the cause. Fix landed in Cogworks v0.13.2 and is bundled into this build.

### Gold withdraw no longer pulls wildly inflated amounts

Players using TradeSkillMaster Auctioning groups with high posting caps (the typical setup for high-volume trade goods like ore, ink, and enchanting scrolls) saw FlipQueue try to withdraw enormous amounts from the warbank — 150k or more for a handful of items, in extreme cases 300k+ for two items. The estimate was reading TSM's "post cap" (a *ceiling* on total quantity ever posted) as if it were the per-task quantity to charge listing fees against, so a 50,000-cap on enchanting scrolls produced a 75,000g fee estimate per scroll instead of a couple of gold.

The fix: the cap is now used as a cap (the actual quantity is clamped against it) instead of replacing the actual quantity. Posting fee estimates now match what TSM would actually charge.

If you have a maximum-withdraw safety cap configured, this fix matters less — the cap was clipping the bogus number to whatever you'd set. If you don't have a cap, this is the difference between FlipQueue pulling a few gold for fees vs. emptying a meaningful chunk of your warbank.

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
- `/fq debug gold` — prints the gold-withdraw calculation for the current character. Per-task breakdown shows vendor sell price, posting quantity, auction duration, and the resulting deposit fee for every task on the to-do list, then the aggregate target balance and what would be withdrawn. The right command to run when a withdraw amount looks wrong.
- `/fq debug pulls` — toggles per-operation tracing during bank queue activity. Useful for diagnosing item-specific bank op failures.
- `/fq debug parsegold` — interactive gold-string parse trace plus a self-test covering EN/DE locale variants, k/m abbreviations, and color-coded strings. Lets US-locale testers verify EU client behavior without an EU account.
- `/fq debug log <name or itemID>` — dumps every entry the addon's log holds for a given item, with full sale / fee / status metadata. Useful when Item Research shows a sales count that doesn't match what the player remembers.
- `/fq debug expired`, `/fq debug realms`, `/fq debug pricing`, `/fq debug bagprices` — various diagnostic dumps for support investigations.

---

*For previous public releases, see `CHANGELOG.md` in the source repository.*
