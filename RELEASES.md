# FlipQueue release notes

This file is the **player-facing** changelog. It's what shows up on CurseForge and Wago project pages. Plain language, organized by what players see and do — no file paths, no internal terminology, no commit references.

The engineering-detail companion lives in `CHANGELOG.md` (commit-readerese — file:line, internal jargon, full alpha-by-alpha breakdown). When working on FlipQueue, update both: `CHANGELOG.md` for the engineering record, this file for the player surface.

---

## Unreleased

- **Deal Finder picks the busier realm when it has nothing else to go on.** If several realms looked equally good for an item — which happens most often when FlipQueue has no listings for it on any of them — the one it picked really was arbitrary, and could differ between sessions for the same item. It now falls back to a **realm order**, which starts out ranked by how busy each realm's auction house actually is, using data TSM already downloads. So between two quiet realms you get the bigger one.
- **You can set that realm order yourself.** There's a **Realm Order...** button in the Deal Finder options: drag realms into whatever order you prefer, and the ones you have a selling character on are highlighted. Each realm shows how many different items are listed there, so you can see why the default order looks the way it does. "Reset to busiest first" hands it back to FlipQueue.
- **How much say realm order gets is up to you.** It appears in the same priority list as Most Profit and No Competition — drag it to the top and it decides, leave it at the bottom and it only settles ties.
- **A priority option that was never usable now is.** "Most Listings" (previously labelled "High Population") has existed in the code since it shipped but could never appear in your priority list, so it never did anything. It's there now.

## v0.13.2-alpha4

Three follow-ups from testing the last build, all in Deal Finder.

- **Realms FlipQueue has no data for no longer pretend to have nothing listed.** When FlipQueue can't find an item's auction data on a realm, it doesn't know how many are posted there — but the realm comparison table printed that as **0**, which reads as "nothing posted, no competition". The ranking never treated those realms as competition-free, because unknown isn't the same as empty, so the screen and the recommendation disagreed with each other. Unknown counts now show as **?**.
- **New option: count realms with no data as having no competition.** Following on from the above — if FlipQueue has no auction data for an item on a realm, should "No Competition" pick that realm anyway? By default it doesn't, because no data isn't the same as no sellers; sometimes it means nobody trades that item there at all, so you'd be posting into no competition *and* no buyers. There's now a checkbox in the Deal Finder options if you'd rather it did. It counts those realms at half strength, so a realm FlipQueue has checked and found empty still wins over one it simply doesn't know about.
- **Reordering your Deal Finder priorities takes effect immediately.** Dragging something to the top of the priority list redrew the list and left every recommendation exactly as it was — you had to run another scan before it did anything, and nothing said so. It now re-ranks the moment you reorder.

## v0.13.2-alpha3

Follow-ups to both problems reported on the last build, after testers came back with more detail.

- **Prices for gear that comes in several item levels are now both wider-reaching and better explained.** The last build was too cautious: if it couldn't find your exact item level it would only look a few levels either way. That turned out to rule out about half of the genuinely close matches, so the range has been widened. More importantly, FlipQueue now checks something it wasn't checking before — whether that particular item's *other* item levels are actually selling for different amounts on that realm. For a lot of gear they aren't; a piece that sells for much the same at any item level can safely be priced from a neighbouring one, and FlipQueue now stops warning you about it. For the gear where item level really does drive the price, the warning stays.
- **You can see the item level spread for yourself.** Hover a realm row in the Deal Finder detail view and you'll get the full picture for that item on that realm: every item level FlipQueue has a price for, what each one is selling at, how many are listed, and which one your price was taken from. If the numbers look wrong, you can now see exactly why rather than taking the answer on trust.
- **New setting: Settings → Pricing.** "Trust close item-level matches when price doesn't vary by item level" is on by default, and you can turn it off if you'd rather see every borrowed price marked as approximate. There's also a choice of how close counts as close — from strict to very lenient. This setting only affects the warnings, never the prices themselves.
- **Correcting something we said last build.** The alpha2 notes said that when FlipQueue can't find a close enough item level it would tell you it has no price for that realm. That was wrong, and we're sorry for the confusion — it falls back to that realm's general price for the item instead, which is normally the cheapest one currently listed there. You were never left without a figure. What was missing was any explanation of where the figure came from, which is what the new tooltip fixes.
- **A tooltip line that never appeared now appears.** The detail view was meant to tell you which item level a borrowed price came from. It never did.
- **Deal Finder now actually follows your priority order.** If you dragged **no competition** to the top, Deal Finder would still recommend a realm that had competition whenever that realm made more than about 100 gold in profit — which is nearly always. The list was supposed to work in order, with the first thing you picked deciding and the rest only breaking ties, but "no competition" is a yes-or-no answer worth a fixed amount while profit and realm population are numbers that grow without limit, so a big enough number further down the list simply outweighed the thing at the top. Everything is now measured on the same scale before your order is applied, so whatever you put first genuinely decides. If you left the priority list on its default this never affected you; if you changed it, it did.
- **Every price in Deal Finder explains itself when you hover it.** Both the realm cards and the realm comparison table now tell you where the number came from: whether it's this realm's own auction data, a close item-level match, or a region-wide average; whether it's the recent market value or the cheapest thing listed right now, with both shown so you can see how far apart they are; **how long ago TSM last downloaded that realm's data**, in red if it's over a day old; every item level FlipQueue has a price for on that realm and which one your price came from; and, if you've sold the item there before, how your own sales changed the figure. If a price looks wrong, the reason should now be on screen instead of something to guess at.
- **Expected prices from FlippingPal are more realistic out of the box.** FlippingPal's "Listing" column is what it suggests posting *at* — an aggressive recommendation, and on a thin or unpredictable item it can be a hundred times what the item really sells for. That was the setting FlipQueue shipped with, and it's the reason some to-do lists showed prices that made no sense. It now uses **Auto** instead, which keeps FlippingPal's listing price except where TradeSkillMaster says it has clearly run away, and falls back to the listing price whenever it can't tell — so it can't do worse than before. **You'll see a one-time message about this when you log in.** If you preferred the old behaviour it's one dropdown away at Settings → Imports, and if you had already picked Sale Avg yourself, nothing changes for you. Prices are set when a list is generated, so regenerate a list to see the difference.
- **`/fq debug alts` was reporting nonsense.** It claimed every character's bags had never been read, no matter how recently FlipQueue had actually read them. It was looking in the wrong place. It also listed characters as fine when they were contributing nothing — either because they'd been deleted in FlipQueue at some point, or because they'd never been read at all. Those are now called out by name, which is very likely the missing quarter of one tester's inventory.

## v0.13.2-alpha2

The first build for the new patch, and it fixes two problems players reported the day it landed.

- **Prices on gear match TradeSkillMaster again.** When a piece of gear exists at several item levels, FlipQueue was working out the wrong item level for the one you actually have. It then went looking for that item in the price data, couldn't find it, and quietly settled for the closest thing it could find — often a completely different version of the item — and showed you that one's price. One reported polearm read 119k on a realm where the real figure was nearer 14k. Plain items and anything that stacks were never affected, which is why it looked like roughly half your list was wrong. FlipQueue now works out the item level correctly, and when it still can't find an exact match it will only accept a nearby item level rather than one fifty levels away. Past that it falls back to that realm's general price for the item rather than confidently quoting a different version's. *(This bullet originally said FlipQueue would tell you it had no price for that realm — that was wrong, and it's corrected here.)*
- **Characters whose inventory never updated now update.** If you have characters spread across a lot of realms, some of them could sit there with stale bags forever — FlipQueue only recognised a realm after you had logged into it, so characters parked on realms you rarely visit were quietly skipped every single time. They're now recognised from the character records FlipQueue already has, no login required. If a character genuinely can't be matched it's still left alone rather than guessed at, but the loading bar now says how many were skipped instead of reporting a tidy "30 / 30" while dropping a quarter of them.
- **Shift-click an item anywhere in FlipQueue to put its link in chat.** This didn't work before — shift-clicking a row did nothing, or in a couple of places did something else entirely. It now behaves the way every other item in the game does. Shift-clicking with the right mouse button still does what it always did on the to-do list and inventory pages.
- **Updated for the new game version**, and re-checked against the latest TradeSkillMaster so posting prices continue to follow your Auctioning operations exactly.

### If you're helping test this

Two commands are worth knowing:

- `/fq debug pricing` followed by a shift-clicked item shows exactly how FlipQueue priced it on every realm, including which item level it matched.
- `/fq debug alts` is new. It lists every character FlipQueue knows about, when each one's bags were last read, and flags any that can't be matched up — the thing that was invisible before.

Both open a window you can copy out of with Ctrl+A, Ctrl+C.

## v0.13.2-alpha1

The first build after v0.13.1 went stable — four fixes and one new setting, all from things players asked for.

- **Deal Finder no longer offers you crafting materials as cross-realm deals.** Materials, potions, ore, herbs and anything else that stacks trade on a single *region-wide* auction house, so the price is identical on every realm and there is no profit in moving them. They were filling the scan with items that could never pay, and every realm row for them showed the same number — which looked like a pricing bug and wasn't. They're now left out, the inventory preview tells you how many were skipped, and there's a **"Hide region-wide items"** checkbox in the Deal Finder options if you want to scan them anyway.
- **A mailbox toy in the Tools drawer works when you click it.** With a toy chosen as the summon method, clicking the tool did nothing at all — the only thing that appeared was the method menu the hover had already opened, which is why it looked like the click was opening a menu. Toys were being used as if they were sitting in your bags; a learned toy lives in the toy box, so nothing happened.
- **FlipQueue notices when your pinned TSM profile no longer exists.** If you picked a TSM profile in FlipQueue's settings and later renamed or deleted it in TSM, FlipQueue kept asking for the old one — so the group tree came up empty with nothing to explain why. It now falls back to whichever profile TSM is actually using and tells you once. The group list also names the profile it's showing you at the top, and says so plainly when that profile simply has no groups in it.
- **Wildly inflated expected prices now point you at the setting that fixes them.** FlippingPal's "Listing" column is an aggressive recommendation and on thin items it can land a hundred times over what the item really fetches. There has been a setting to use a more conservative column since v0.13.0 — but nothing on screen connected the silly number to it. To-do rows whose price is more than 10× TSM's regional average now carry an orange **!** with the comparison in the tooltip, the generator says how many tasks are affected with the worst one as an example, and both point at **Settings → Imports → FlippingPal price source**. Nothing about your prices changed in this build; what changed is that FlipQueue now tells you when they look wrong and what to do about it.
- **"No character on that realm" no longer shows up for realms you do have a character on.** If your characters there are set to **Buy Only** — a common setup for bank alts parked on every realm — none of them is allowed to post a sale, so the deal can't be assigned. FlipQueue told you there was nobody there, which is the one answer guaranteed to send you looking in the wrong place. It now counts those separately, names the realms, and tells you the fix is a role change on the Characters page rather than a new character.
- **New: storage-only characters.** Set a character's role to **Storage** on the Characters page and it holds your stock without ever being given a posting or buying task. Its bags and bank still count as items you own, and it can still be asked to hand something over to the character that's selling it. Previously the only way to keep a character out of your to-do lists was **Hidden**, which also hid its inventory — so FlipQueue would tell you an item was nowhere on your account while it sat in that character's bank.

## v0.13.1

A stability release — everything in it is a fix. Large accounts froze, a full FlippingPal export crashed the client, bank operations quietly stopped planning, and Deal Finder showed the same price on every realm. All four are fixed, along with a long tail of smaller things. Everything below is new since v0.13.0.

### Large accounts don't freeze any more

If you run a lot of characters and import big cross-realm lists, FlipQueue could lock the game up — sometimes badly enough to need a restart. Four separate causes, all fixed:

- **Building a to-do list runs in the background** with a progress bar now, however you start it: the automatic generate-after-import, the **Generate** button, a filter change, or reordering your priorities.
- **Full auction house scans** no longer stall the client. If you run Auctionator, its full scan made FlipQueue read the entire auction house in one go — seconds at a time on a busy realm.
- **Opening the auction house is smooth.** FlipQueue cross-checks your sales against TradeSkillMaster shortly after you open the AH; on big TSM setups that check froze the client, once per character switch.
- **Checking mail and posting is faster.** Refreshing your to-do steps no longer re-scans your whole account's inventory for every task on every bag change.

FlipQueue also stops growing without limit over a long session. Its record of scanned auction prices is now capped as you play — one reported session had reached over 400 MB — and **Max entries kept** for your sales log defaults to 10,000 instead of unlimited. Your existing history is untouched, and you can set it back to Unlimited in Settings → Sales Log.

### Pasting a full FlippingPal export works

The crash that hit anyone importing a full multi-character export is gone. It took several attempts to find, because it wasn't one bug:

- **The game was dying before FlipQueue got a turn.** WoW hands a paste over in one uninterrupted burst, and while that's happening it re-draws everything pasted so far every time another piece arrives. On a few-hundred-KB export that's a colossal amount of work in a fraction of a second, which is why nothing appeared on screen — not even a progress line. FlipQueue now takes the text out of the box the instant it arrives, so the game never has to hold or draw more than a few lines of it.
- **The import got slower the further it got.** Every incoming deal was checked against every deal already imported, to spot the same item offered on connected realms — work that grows with the *square* of the export. On a 4,000-deal export that work is now roughly 35 times less, and it no longer gets disproportionately worse as your export grows.
- **A paste that couldn't be read no longer takes the client down.** If the box ever failed to clear, FlipQueue re-read the same text every frame, forever, filling memory until the game died. It now checks, and stops safely if something's wrong. A paste beyond any sane size tells you to split it up.
- **Pasting a second large export in the same session works** — previously the box was left in a state where every later paste silently did nothing until you reloaded.
- **The progress line is under the paste box**, where you're actually looking, rather than six hundred pixels away at the bottom of the window. The Transform page's paste box got the same treatment.

### Bank operations work again

Since the first v0.13.1 test build, opening your bank quietly did nothing at all for anyone with a cross-realm to-do list — nothing pulled, nothing deposited, no gold withdrawn, and no window ever opened. Because WoW hides addon errors unless you turn them on, there was nothing on screen to explain it. The same fault also stopped the "N items ready to post!" message at the auction house. Nothing about your to-do lists, settings or inventory was damaged; the work simply wasn't being done. Open your bank once after updating and it picks up where it left off.

### Deal Finder shows real per-realm prices for gear

Gear gets listed at many different item levels, and FlipQueue could only recognise your item at one exact item level. When that didn't line up with what TradeSkillMaster had recorded — which is most of the time, because the auction house reports item levels scaled to whoever is looking — FlipQueue quietly fell back to a single region-wide average, so every realm showed the same number. Plain items like recipes and pets were never affected, which is why a handful of items looked fine while hundreds didn't.

FlipQueue now uses the closest item level TSM actually has for that item, then the base item, and only falls back to a region-wide average when the item is genuinely missing from that realm's data. Prices matched approximately are marked with a `~` and the item level they came from, so you can see how solid each number is.

### Pulling from the bank, one bagful at a time

If you had more to pull than free bag space — one player had 304 waiting and room for 164 — FlipQueue planned the whole lot, ran until your bags filled, and quietly dropped the rest with nothing on screen to explain it. It now pulls only what fits, and orders the batch so it works through one realm at a time instead of scattering items across all of them, so you can finish that realm's posting before coming back for the next load. The popup says "Pull tasks (164 of 304)" and tells you what's left; if your bags are completely full it says so rather than showing nothing.

### Your imports and exports arrive whole

- **Auctionator and PBS shopping lists import in full.** Items from those lists arrive without an item ID, and FlipQueue treated "no ID" as "the same item" — so a 30-item list could import as two or three deals with the rest vanishing silently.
- **Your inventory export no longer contains items called "Unknown".** When the game hadn't finished loading an item — most likely something in a bank or warbank you haven't opened recently — FlipQueue wrote "Unknown" as the name, with no quality and an item level of zero, straight into the file you upload to FlippingPal. One export had it in 22 of the first 99 rows. FlipQueue now waits for those details, exports again once they arrive, and leaves out anything it still can't name, with a note telling you how many and why.
- **Your shopping lists find deals again.** v0.13.0 turned on "Match exact item level" for everyone, and because the auction house shows item levels scaled to your character's level, that quietly hid almost every armor and weapon listing. It's now off by default; turn it back on in Settings → Auctionator if you snipe specific gear variants on a max-level character.

### Clearing out to-do tasks that can never finish

A to-do list only ever grows, and some of what accumulates in it is genuinely stuck: a task assigned to a character you've since deleted, one waiting on an item that isn't on any of your characters, or the sell half of a cross-realm flip whose buy you removed. Those are now marked **[trapped]**, counted next to the list name, and shown as a banner in the mini window — trapped tasks never appear as one of your current character's rows, so the pile builds up out of sight. `/fq cleanup trapped` shows you what it found and why; `/fq cleanup trapped confirm` removes it. Nothing is ever deleted automatically.

Tasks that simply haven't moved in a while are marked **[stale]** — two weeks by default, flagged only, never removed. An old task isn't a dead one. You can change the threshold or switch the flag off in the settings.

### Where every imported deal went

If FlippingPal gives you two thousand deals and FlipQueue makes ninety tasks, that gap needs explaining. The most common reasons a deal doesn't become a task are that you have no character on the realm it wants you to sell on, that you don't own the item, or that you own it but a better-priced deal already claimed your stock — and all of those were happening silently. Step 3 of the generator now reads something like "2,088 deals imported → 94 tasks; 1,600 no character on that realm, 300 item not in your inventory, 94 stock already claimed", so the arithmetic is yours to check. The realms you're missing a character on are recorded too, which is exactly the list you need when deciding where to roll one.

### Smaller fixes

- **"Skip deals with no character" stays checked.** The setting was always saved and always obeyed, but the checkbox drew itself unchecked on every login — so clicking it to "turn it back on" was actually turning it off.
- **Posting one version of an item no longer clears a to-do for a different version** of the same item.
- **Right-clicking items in the Inventory tab always responds.** Items already assigned to your queue ignored the right-click completely, which felt like "I can't add anything to Do Not Track" — especially right after an import, when almost everything is assigned. Assigned items now open a small menu, posted items explain that the live auction has to be collected or cancelled first, and an action with nothing to act on tells you so.
- **The Log Out button in the tools drawer works** instead of throwing a blocked-action error.
- **`/fq state` shows your FlipQueue version on its first line**, and records your last paste and the generator's breakdown — so when something still looks wrong, we can usually see why without asking you to reproduce it.
- **`/fq debug realms` and `/fq debug pricing`** open a copyable box instead of printing into chat, list your sell realms and whether each has real per-realm pricing behind it, and say up front when an item is a commodity — those trade on a region-wide auction house, so there is one price everywhere and no cross-realm profit to be had.

## v0.13.1-alpha13

- **The generator now shows you where every imported deal went.** If FlippingPal gives you two thousand deals and FlipQueue makes ninety tasks, that gap needs explaining — and until now nothing explained it. The most common reasons a deal doesn't become a task are that you have no character on the realm it wants you to sell on, or that you don't own the item, or that you own it but a better-priced deal already claimed your stock. All of those were happening silently. Step 3 of the generator now reads something like "2,088 deals imported → 94 tasks; 1,600 no character on that realm, 300 item not in your inventory, 94 stock already claimed", so the arithmetic is yours to check. The realms you're missing a character on are recorded too, which is exactly the list you need when deciding where to roll one.
- **`/fq state` records the same breakdown**, so if the numbers still look wrong we can see where they went without asking you to reproduce anything.

## v0.13.1-alpha12

Cleaning up the to-do list.

- **Tasks that can never be completed are now flagged, and you can clear them out.** A to-do list only grows, and some of what accumulates in it is genuinely stuck: a task assigned to a character you've since deleted, one waiting on an item that isn't on any of your characters, or the sell half of a cross-realm flip whose buy you removed. Those are marked **[trapped]**, counted next to the list name, and shown as a banner in the mini window — trapped tasks never show up as one of your current character's rows, so the pile builds up out of sight. `/fq cleanup trapped` shows you what it found and why; `/fq cleanup trapped confirm` removes it. Nothing is ever deleted automatically.
- **Tasks that simply haven't moved in a while are marked [stale].** Two weeks by default. These are only ever flagged, never removed — an old task isn't a dead one, and a list you left alone over a holiday is perfectly fine. You can change the threshold, or switch the flag off, in the settings.
- **Fixed two small display bugs.** The "won't fit in your bags" rows added in the last build were drawing without their icon, and a note on the regenerate screen was showing `xe2x86x92` where it meant to show an arrow.

## v0.13.1-alpha11

Two fixes from the list of things players have asked for.

- **Your inventory export no longer contains items called "Unknown".** When the game hadn't finished loading an item — most likely for things sitting in a bank or warbank you haven't opened recently — FlipQueue wrote "Unknown" as the name, with no quality and an item level of zero. That went into the file you upload to FlippingPal, which has no way to tell a placeholder from a real name. One export had it in 22 of the first 99 rows. FlipQueue now asks the game to load those details, exports again once they arrive, and leaves out anything it still can't name — with a note telling you how many and why, so you can open the bank holding them and export again.
- **Pulling from the bank now sends one bagful at a time.** If you had more items to pull than free bag space — one player had 304 waiting and room for 164 — FlipQueue planned the whole lot, ran until your bags filled, and quietly dropped the rest with nothing on screen to explain it. It now pulls only what fits, and orders the batch so it works through one realm at a time instead of scattering items across all of them, which means you can actually finish that realm's posting before coming back for the next batch. The popup says "Pull tasks (164 of 304)" and tells you what's left; if your bags are completely full it says so rather than showing nothing at all.

## v0.13.1-alpha10

**Another go at the crash when pasting a full FlippingPal export.** If you have been hitting the spinning cursor and a dead client, this is the build to test.

- **The paste no longer sits in the box while the game struggles with it.** WoW delivers a paste in one go, before anything else can run — and while that is happening, the game is re-drawing the entire pasted text every time another piece of it arrives. On a full multi-character export that is hundreds of thousands of characters, and the game dies before FlipQueue is ever given a turn. That is why nothing appeared on screen, not even the progress line we asked you to watch for. FlipQueue now takes the text out of the box the instant it arrives rather than waiting its turn, so the game never has to hold or draw more than a few lines of it.
- **The progress line is now under the paste box, where you are actually looking.** It used to be at the very bottom of the window, next to the Back button, six hundred pixels from the box. Receiving, parsing and any "too large" message now appear directly beneath the box you pasted into.
- **The Transform page's paste box got the same treatment.** It accepts the same exports and had the same problem waiting to happen.
- **`/fq state` now records your last paste** — how big it was and how the game handed it over. If a paste still fails, running that afterwards on a *smaller* one that worked tells us something we cannot work out from here.

One thing worth checking after a big paste: the number of deals FlipQueue reports should be close to what FlippingPal told you it found. If it comes up short, say so — that would be a different problem, and a much easier one.

## v0.13.1-alpha9

**Importing a big FlippingPal export.** If you have been fighting the freeze-then-crash when pasting a full export, this is the build to test.

- **Importing a large export is dramatically faster.** Every deal coming in was being checked against every deal already imported, one at a time, to spot the same item offered on connected realms. That check gets slower and slower as the import grows — four times slower each time the export doubles in size — so a small paste finished fine while a full multi-character export ground the game to a halt. FlipQueue now looks only at the deals that could actually be a match. On a 4,000-deal export the work dropped by roughly 35 times, and it no longer gets disproportionately worse as your export grows.
- **A paste that can't be read no longer takes the game down with it.** The import reads your pasted text in small pieces and clears the box as it goes. If the box ever refused to clear, FlipQueue would read the same text over and over, forever, filling memory until the client died — with a spinning cursor and no error message. It now checks that the box actually cleared, and stops safely if it didn't. A paste beyond any sane size now tells you to split it up instead of quietly trying.
- **Pasting a second large export in the same session works.** After a big paste, the box was left in a broken state and every later paste silently did nothing until you reloaded. If you have been reloading between attempts without knowing why, this was it.
- **Auctionator and PBS shopping lists import in full.** Items from those lists arrive without an item ID, and FlipQueue was treating "no ID" as "the same item" — so a 30-item list would import as two or three deals and the rest vanished with no warning. Each item is now kept on its own.

## v0.13.1-alpha8

**If your bank stopped doing anything, this is the build.** One bug, and it was a bad one.

- **Bank operations work again — pulls, deposits, gold, the lot.** Since v0.13.1-alpha1, opening your bank quietly did nothing at all for anyone with a cross-realm to-do list. A performance rewrite in that build changed how FlipQueue looks up which character is holding an item, and one place in the code was left calling the old version. That threw an error the moment FlipQueue checked a task belonging to another character — which is most of them in a cross-realm setup — and the error happened *just before* the bank operations window was due to appear, so nothing was pulled, nothing was deposited, no gold was withdrawn, and no window ever opened. Because WoW hides addon errors unless you turn them on, there was nothing on screen to explain it. The same error also stopped the "N items ready to post!" message when you opened the auction house.
- Nothing about your to-do lists, settings or inventory data was damaged by this — the work simply wasn't being done. Open your bank once after updating and it should pick up where it left off.

## v0.13.1-alpha7

A small fix for a setting that looked like it kept switching itself off.

- **"Skip deals with no character" stays checked.** The setting itself was always being saved and always being obeyed — but the checkbox in Settings drew itself unchecked every time you logged in or reloaded, so it looked like it had turned itself off. Worth knowing if you hit this: clicking it to "turn it back on" was actually turning it off, which could explain unexpected "create character" tasks showing up in a generated list.

## v0.13.1-alpha6

Two long-running bugs finally have their real causes, plus two smaller fixes. If you reported the "same price on every realm" problem or the crash when pasting a big FlippingPal export, this is the build to test.

- **Deal Finder shows real per-realm prices for gear again.** Gear gets listed on the auction house at many different item levels, and FlipQueue could only recognise your item at one exact item level. When that didn't line up with what TradeSkillMaster had recorded — which is most of the time, because the auction house reports item levels scaled to whichever character is looking — we quietly fell back to a single region-wide average, so every realm showed the same number. Plain items like recipes and pets were never affected, which is why a handful of items looked fine while hundreds didn't. FlipQueue now uses the closest item level TSM actually has for that item, then the base item, and only falls back to a region-wide average when the item is genuinely missing from that realm's data. Prices matched approximately are marked with a `~` and the item level they came from, so you can see how solid each number is.
- **Pasting a large FlippingPal export no longer crashes the game.** Earlier attempts at this fix went into a part of the addon that was no longer being used, so the box you actually paste into never received them — which is why it kept happening for anyone who reported it. The paste boxes in the To-Do Generator now take a big export in small steps instead of holding all of it at once. Typing into those boxes is unchanged.
- **Posting one version of an item no longer clears a to-do for a different version.** If you had a to-do for a specific version of an item and posted a different version of it, opening the auction house wiped the to-do — while TSM still (correctly) offered the original to post.
- **The Log Out button in the tools drawer works.** It was throwing a blocked-action error instead of logging out.
- **`/fq state` now shows your FlipQueue version on its first line**, so when we ask you to confirm which build you're testing, that line actually answers it.

## v0.13.1-alpha5

A diagnostics build. Nothing changes in how Deal Finder prices your items — this build only improves the troubleshooting commands, so we can get to the bottom of "every realm shows the same price."

- **Debug output you can actually copy.** `/fq debug realms` and `/fq debug pricing` used to print into chat, which the game won't let you select or copy. Both now open the same copyable box the other debug commands use — click it, Ctrl+A, Ctrl+C, paste it to us.
- **`/fq debug realms` now shows the half that mattered.** It listed how many realms TradeSkillMaster gave us, but never whether *your selling realms* were among them. It now lists each of your sell realms and tells you plainly whether it has real per-realm pricing behind it or is falling back to a region-wide average.
- **`/fq debug pricing` tells you if an item is a commodity.** Crafting materials, potions, ore, herbs and anything else that stacks trade on a **region-wide** auction house in retail WoW — there is genuinely one price across every realm for those, and no cross-realm profit to be had. The command now says so up front, so you can tell "working as intended" apart from a real bug. It also names which realms it couldn't find the item on instead of just counting them.
- **Fixed an error when shift-clicking an item into `/fq debug pricing`.** If the item wasn't in your log, inventory, or warbank, the command errored out partway through instead of finishing the report.

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
