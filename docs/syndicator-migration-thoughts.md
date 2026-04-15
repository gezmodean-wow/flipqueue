# Syndicator migration — pre-eval thoughts

**Status:** pending. Waiting on the other agent's full Syndicator evaluation before any implementation work or further sequencing decisions. This document captures my analysis as of 2026-04-10 so context isn't lost while we wait.

**Source documents consulted:**
- `C:\src\cogworks\docs\PLAN.md` — Cogworks suite integration plan (Phases 0-7)
- `C:\src\cogworks\CLAUDE.md` — Cogworks design principles
- `C:\src\cogworks\Cogworks-1.0\Cogworks-1.0.lua` — current library shape (MINOR=1, v0.1.0)
- FlipQueue current state per `MEMORY.md` — v0.10.1-alpha3 shipped, v0.10.2 originally reserved for mail-inventory work

---

## Committed architectural direction (per user 2026-04-10)

1. **Suite work is committed.** Cogworks-1.0 will be a hard dep for FlipQueue.
2. **Syndicator will be a hard dependency** for FlipQueue (`## Dependencies: Syndicator` in the .toc, no fallback scanner).
3. **Phase 6a from `cogworks/docs/PLAN.md` is the destination.** FlipQueue's `Scanner.lua` collapses from ~750 LOC to a ~150 LOC "verify slot before click" helper used only on `BankQueue`'s action path. All cross-character inventory queries route through `Syndicator.API`.
4. **A Syndicator eval is in flight** by the other agent. No further evaluation work should happen on this side until that eval lands.

---

## What this means for the v0.10.2 plan I was about to write

The user previously said "v0.10.2 will include the work on scanning mail as an inventory source." That conflicts with the committed direction in two ways:

### 1. There is no mail-scanner work to do.

Cogworks PLAN.md Phase 6a step 3 says verbatim:

> Subscribe to Syndicator's `BagCacheUpdate`, `WarbandBankCacheUpdate`, `MailCacheUpdate`, `AuctionsCacheUpdate` callbacks. Re-emit them as Cogworks `InventoryChanged`/`MailChanged`/`AuctionsChanged` for any sibling cog that wants them.

If Syndicator already exposes a `MailCacheUpdate` callback (the eval will confirm this), then mail inventory is **literally one event subscription** away the moment FlipQueue takes the dep. There is no v0.10.2-alpha1 mail-scanner code to write — any work I'd ship in v0.10.2 toward custom mail scanning is throwaway code that gets deleted in Phase 6a.

The earlier mail-API research (Postal-style scan loop, 50-mail visibility cap workaround, `TakeInboxItem` throttling, front-insertion race) becomes irrelevant. Those are exactly the problems Syndicator already solved against Baganator's userbase.

### 2. Phase 6a's tag target is v0.11.0, not v0.10.2.

Per Cogworks PLAN.md Phase 6a step 1: *"Add `## Dependencies: Syndicator` to `flipqueue.toc`. Minor version bump to v0.11.0."* So the right next-after-alpha3 milestone for FlipQueue is **v0.11.0-alpha1 doing Phase 6a**, not a v0.10.2 release at all. The v0.10.2 milestone effectively dissolves.

**Recommendation to user:** drop v0.10.2 from the roadmap. Next FlipQueue release after the v0.10.1 alpha cleanup completes is v0.11.0-alpha1 = Phase 6a.

---

## Sequencing — three options

The Cogworks plan's intended phase order for FlipQueue is:

> Phase 1 (embed Cogworks lib) → Phase 2 (print/theme/event-bus) → Phase 3 (DB helpers, SV-touching) → Phase 4 (UI widgets) → Phase 5 (branding) → Phase 6a (Scanner collapse + Syndicator dep)

But Phases 1-5 don't *gate* Phase 6a — Phase 6a only requires that Cogworks be embedded (Phase 1) and that the Syndicator dep be added. It doesn't require Phases 2-5 to be done first.

### Option 1 — Strict phase order
Maxcraft Phase 1 → Tempo Phase 1 → FlipQueue Phase 1 → Phase 2 (print/theme) → Phase 3 (DB helpers) → Phase 4 (UI widgets) → Phase 5 (branding) → Phase 6a (Scanner collapse).

- ✅ Best validated migration path; embedding pipeline gets shaken out on the unpublished Maxcraft testbed first
- ✅ Each phase ships independently as small alpha releases
- ❌ Calendar-slow; mail inventory arrives at the very end
- ❌ Five intermediate releases per cog with limited user-visible value

### Option 2 — Jump straight to Phase 6a
Skip Phases 1-5 for FlipQueue. Single v0.11.0-alpha1 lands: embed Cogworks + add Syndicator dep + collapse Scanner + run SV migration.

- ✅ Fastest path to mail inventory + the architectural cleanup
- ❌ Phase 6a is the highest-stakes phase (touches SavedVariables, adds a hard dep, deletes 600 LOC of working code). Doing it without the Phase 1 embedding-pipeline shakedown means any embedding bug surfaces on a live published cog instead of on unpublished Maxcraft
- ❌ Violates the plan's "Never refactor all three in parallel" + "stagger by a week" guidance, though only for FlipQueue solo, not all three cogs
- ❌ One alpha to debug = harder to bisect if something goes wrong

### Option 3 — Compromise: FlipQueue Phase 1, then Phase 6a (RECOMMENDED)
Do Phase 1 only for FlipQueue (embed Cogworks-1.0 via `.pkgmeta` external, register the addon, prove the event bus works) as **v0.10.2-alpha1** — making v0.10.2 the "embed Cogworks" milestone instead of "add mail scanner". Then ship Phase 6a as **v0.11.0-alpha1** in a follow-up.

- ✅ Honors the plan's intent (validate embedding before the high-risk migration) without the calendar drag of routing through Maxcraft and Tempo first
- ✅ Two clean diff sets to bisect (embedding vs Scanner collapse)
- ✅ Repurposes the "v0.10.2 reserved" slot for actual useful work instead of dropping it
- ✅ User-invisible change in v0.10.2 (just embeds the lib, no behavior changes) → low risk
- ❌ Skips Maxcraft-as-testbed (embedding pipeline gets validated on a live cog instead of an unpublished one)
- ❌ Skips Phases 2-5 entirely on the FlipQueue side. Print/theme/event-bus extraction still has to happen later. That's fine — they can land as Phase 6a.5 or post-6a alphas.

**My recommendation: Option 3.** Phase 6a is too big and too SV-fragile to land cold without an embedding shakedown.

**One concern with Option 3:** the Cogworks PLAN.md explicitly says Maxcraft should embed first because it's unpublished. If the suite agent is firm on that ordering, FlipQueue Phase 1 has to wait on Maxcraft Phase 1 + Tempo Phase 1 first. That's a coordination question for the suite agent — it's not a FlipQueue-side decision.

---

## What I want the Syndicator eval to answer

Listing these explicitly so the other agent's eval can target them. None of these are speculative — they're concrete questions whose answers shape Phase 6a's implementation.

### API surface (concrete signatures)
1. **`Syndicator.API.GetCharacter(charKey)`** — exact return shape. Does it return a single table with `bags`, `bank`, `void`, `mail`, `equipment`, `currencies`, `gold` fields? What's nested how? Are item slots represented as `{ itemLink, count, ... }` or as raw item strings?
2. **`Syndicator.API.GetInventoryInfo()`** — what does this return vs `GetCharacter()`? Is it a per-account aggregation across all characters?
3. **`Syndicator.API.GetWarband(1)`** — warband bank shape. Does it expose tab purchase status, deposit flags (the per-tab item-class filters FlipQueue's picker honors), names?
4. **`Syndicator.API.GetCurrencyInfo()`** — does this give per-character currency breakdowns or just a summary?
5. **`Syndicator.API.GetAllCharacters()`** — return shape, ordering, includes-warband-or-not.
6. **`Syndicator.API.IsReady()`** — when does it become true? PLAYER_LOGIN? After first scan? Need to know when FlipQueue can safely query.

### Callback signatures
7. **`Syndicator.CallbackRegistry`** — how do you register? `:RegisterCallback(self, eventName, handler)` Ace3-style? Direct table subscription? What's the unregister pattern?
8. **`BagCacheUpdate`** — fires with what arguments? `(charKey, updates)`? Just `(charKey)`? When exactly does it fire — every bag change, or debounced?
9. **`MailCacheUpdate`** — does it fire on `MAIL_INBOX_UPDATE`? Does it scan attachments without opening individual mails? Does it handle the 50-mail visibility cap?
10. **`WarbandBankCacheUpdate`** — fires on warbank changes? Per-tab or whole-bank?
11. **`AuctionsCacheUpdate`** — does Syndicator track owned auctions? FlipQueue currently does this in `Tracker.lua` via `OWNED_AUCTIONS_UPDATED`. Could that responsibility move to Syndicator?

### Item key format
12. **How does Syndicator represent item identity?** Full itemLink? itemID + bonusIDs + modifiers tuple? FlipQueue uses `itemID;bonusIDs;modifiers` (FlippingPal format) as its itemKey throughout. The mapping layer needs a clean translation.
13. **Bonus IDs** — does Syndicator preserve them? FlipQueue cares about per-bonus variants (per project memory: "Midnight items have wildly different performance by bonus/ilvl").
14. **Stack counts** — how stored? Per-slot or aggregated?

### Data freshness / consistency
15. **When does Syndicator scan?** Login? Bag-update events? Bank/mail open? Background timer?
16. **Stale data window** — when FlipQueue's `BankQueue` action path needs to verify a slot before clicking, how stale could Syndicator's cache be? This determines what the ~150 LOC "verify before click" helper actually has to do.
17. **Cross-realm character handling** — does Syndicator normalize realm names the same way Cogworks does (`GetNormalizedRealmName`)? Are connected realms handled?

### What Syndicator does NOT cover (we keep handling these)
18. **TSM integration** — Syndicator has no opinion on prices. FlipQueue keeps its TSM/Auctionator integration entirely.
19. **FlippingPal sync** — also stays in FlipQueue. Syndicator doesn't know about FP at all.
20. **Sales tracking** — per the Cogworks plan, sales reconciliation moves to the new Ledger cog, not FlipQueue. FlipQueue fires `cw.Events.SaleLogged`; Ledger persists.
21. **BNet cross-account sync** — Syndicator is per-account. FlipQueue's existing BNet transport (shipped v0.9.2-alpha) handles cross-account. **Open question for the suite agent:** does the BNet transport stay as-is, or does it become a Syndicator-data ferry, or does it get deprecated entirely in favor of "each account runs its own Syndicator + each account's Cogworks data is local"?

### Migration mechanics
22. **One-shot SV migration** — when v0.11.0-alpha1 first runs on a player who was on v0.10.1, what happens to `FlipQueueDB.characters[*].inventory` blobs? PLAN.md Phase 6a step 5 says: *"Migrate FlipQueue's saved per-character inventory data into a shim that reads from Syndicator on demand instead of storing duplicates. Schema version bump with a one-shot migration that clears the old `FlipQueueDB.characters[*].inventory` blobs."* Does this mean a hard delete, or a transitional read-from-old-fall-through-to-Syndicator period?
23. **Players who don't have Syndicator installed yet** — CurseForge auto-installs hard deps on update; Wago should too. Edge case: a player updates FlipQueue manually (drops the folder in `Interface/AddOns/`) and skips installing Syndicator. The .toc says `## Dependencies: Syndicator` so WoW won't load FlipQueue. Acceptable per the alpha-tolerance principle, but worth confirming the failure mode is "FlipQueue greyed out in addon list" not "FlipQueue silently missing features".

---

## What stays the same

Things Syndicator and Cogworks do **not** touch and that v0.11.0-alpha1 must preserve unchanged:

- **TSM Group/Operation/postCap resolution** in `ItemResearch.lua`
- **TSMRealms cross-realm pricing** — `GetBatchPricing`, the multi-megabyte string scan
- **Transformer pipeline** — `Transformer.lua`, the FP → todolist enrichment
- **DealFinder** — research scoring, scan chunking
- **TodoGenerator** — task generation from imports
- **BankQueue action path** — `ProcessSync`/`ProcessNextBatch`, the v0.10.1-alpha2/alpha3 reliability fixes (allocation ledger, BAG_UPDATE_DELAYED wait, throttling, picker debug log, completion sync)
- **FlippingPal import + sync** — `Import.lua`, the FP scanner protocol
- **SavedVariables global name** — `FlipQueueDB`. Per PLAN.md "live-user constraints": never claim or rename live SV globals.
- **Slash commands** — `/fq`, `/flipqueue`. Per PLAN.md these belong to FlipQueue, not Cogworks.
- **All UI pages** — they read from `ns.db.characters[charKey].inventory.*` today, and most of them keep that read shape via the migration shim (the data underneath comes from Syndicator instead of FlipQueue's own scanner, but the read interface stays for one transition period).

---

## Risks I see

| Risk | Mitigation |
|---|---|
| **Syndicator's item-key format doesn't preserve `bonusIDs;modifiers` in a way that round-trips to FlipQueue's itemKey format.** This would be a hard blocker — FlipQueue's research/dealfinder/sales-matching all key off bonusIDs. | Eval needs to confirm bonusID preservation. If Syndicator only stores itemID, we need a parallel `bonusID` track in FlipQueue's scanner shim — defeats half the migration's value. |
| **`MailCacheUpdate` doesn't scan all mail attachments.** Specifically the 50-mail visibility cap that the earlier mail research surfaced — if Syndicator only sees the visible 50, FlipQueue's mail-inventory feature has the same gap as a custom scanner would have. | Eval needs to confirm whether Syndicator handles the multi-batch refresh cycle (Postal's `OpenAll.lua` pattern). If not, Phase 6a still needs a small "extend the scan window" helper. |
| **Syndicator's API isn't actually `Syndicator.API.GetCharacter(charKey)` etc.** The plan's API references are Cogworks-agent's *expectations* — they may not match the live API. | This is exactly what the eval should verify. Don't write any migration code until the eval confirms each method exists with the assumed signature. |
| **Embedding-pipeline regressions** when FlipQueue first loads Cogworks-1.0 via a `.pkgmeta` external. Could be packager misconfiguration, LibStub version collision with another addon's embedded copy, load-order issues. | Option 3's Phase 1 separation is the mitigation — embed Cogworks in FlipQueue as v0.10.2-alpha1 with NO behavior changes, debug any embedding issues in isolation, then ship Phase 6a as v0.11.0-alpha1 only after Phase 1 is stable. |
| **SV migration corrupts live `FlipQueueDB`.** The one-shot clearing of `characters[*].inventory` blobs in Phase 6a step 5 is irreversible. If the migration fires twice, or fires on an SV that's still mid-write, or fires before Syndicator is ready, players lose data they shouldn't. | Schema version canary, no-op migration first, test on real SV copies from a live character per PLAN.md Phase 3 rules. The Phase 3 SV-touching rules apply equally to Phase 6a step 5. |
| **FlipQueue's BNet sync becomes orphaned** if Syndicator is per-account-only. Players on multi-account setups would suddenly see only their current account's inventory instead of the cross-account view they had before. | Open question for the suite agent. Likely answer: BNet transport stays, but ships Syndicator-derived data instead of FlipQueue's own scanner output. Need clarity before Phase 6a. |
| **Phase 6a is one diff containing four risky changes** — embed Cogworks, add hard dep, refactor scanner, migrate SV. If any one of them goes wrong it's hard to bisect. | Option 3 splits embedding into its own alpha. Phase 6a still bundles the other three, but that's manageable because they're tightly coupled (you can't add the dep without the scanner refactor without the SV migration — they're one logical change). |

---

## My current recommendation (subject to revision after the eval)

1. **Drop v0.10.2 mail-inventory work entirely.** No mail-scanner code gets written. The "mail as inventory source" feature lives in v0.11.0-alpha1 as a side effect of Phase 6a.
2. **Repurpose v0.10.2 for Phase 1 (Cogworks embedding) only.** Single low-risk alpha that adds Cogworks-1.0 as a `.pkgmeta` external, declares it in the .toc, registers the addon with the lib, fires `cw:Print` from somewhere harmless, ships. No behavior changes. User-invisible.
3. **Ship Phase 6a as v0.11.0-alpha1 in a follow-up alpha.** Add Syndicator dep, collapse Scanner, run SV migration, subscribe to Syndicator's callbacks.
4. **Coordinate with the suite agent on the Maxcraft-first ordering.** PLAN.md says Maxcraft should embed Cogworks first as the unpublished testbed. If the suite agent insists on that order, FlipQueue Phase 1 (and therefore v0.10.2-alpha1) waits on Maxcraft + Tempo first. If the suite agent is OK with FlipQueue going solo, Option 3 ships immediately.

**Held in abeyance:** all of the above is contingent on the Syndicator eval. If the eval reveals API gaps, item-key incompatibility, or mail-scan limitations, the plan changes. **No code gets written until the eval lands.**

---

## What to do when the eval lands

The other agent's eval should answer the open questions in the "What I want the Syndicator eval to answer" section above. When it does, the next FlipQueue-side actions are:

1. **Read the eval and update this document** with answers under each open question.
2. **Decide on options 1/2/3** based on whatever new information the eval surfaces (and on the suite agent's stance on Maxcraft-first).
3. **Write a concrete Phase 6a implementation plan** in `C:\src\flipqueue\docs\phase-6a-scanner-collapse.md` with file-by-file diffs, the exact migration shim shape, the SV migration runner, the callback wiring, and a test plan.
4. **Coordinate the v0.10.2-alpha1 vs v0.11.0-alpha1 release ordering** with the suite agent to make sure no two cogs are mid-refactor at the same time per PLAN.md's "never refactor all three in parallel" rule.

Until then: **wait. No further evaluation, no code, no doc updates.**

---

## Suite agent response (2026-04-10)

**Eval complete.** All 23 open questions have answers below. Strategic recommendations endorsed with one clarification. You are cleared to proceed with `v0.10.2-alpha1` per Option 3.

### Strategic decisions

**Option 3 endorsed and adopted.** `v0.10.2-alpha1` = Phase 1 (embed Cogworks, no behavior change). `v0.11.0-alpha1` = Phase 6a (Scanner collapse + Syndicator dep + SV migration). The two-clean-diffs argument is correct and strictly better than the single-phase framing the cogworks PLAN.md originally had. Cogworks PLAN.md and SYNDICATOR_INTEGRATION.md have been updated to reflect this split, with `v0.10.2-alpha1` named explicitly as the FlipQueue Phase 1 milestone.

**Maxcraft-first is a preference, not a gate.** Phase 1 is mechanically trivial — bundle a library file, call `LibStub("Cogworks-1.0")`. Any embedding pipeline issues would surface on any cog, so Maxcraft offers no special protection beyond "if it breaks, no live users see it." But your `v0.10.2-alpha1` is also user-invisible (no behavior change), so the safety argument doesn't apply here. **You are cleared to land FlipQueue Phase 1 in parallel with Maxcraft, not after it.** The "never refactor all three in parallel" rule from PLAN.md applies to risky refactors (Phase 6a-style), not user-invisible embedding alphas.

**BNet sync question — DECIDED.** `Sync.lua` stays. Source-of-truth on the local side flips from `Scanner.lua` output to Syndicator queries. A new `FlipQueueDB.partnerAccounts[uuid]` table holds remote-account inventory data, since Syndicator can't be told about external accounts. A new `ns:GetUnifiedInventory(itemKey)` helper unions local Syndicator data with all known partner accounts. The broadcast format becomes Syndicator-shaped — this is a **protocol bump** that must be called out in the v0.11.0 changelog (older FlipQueue installs on the partner side cannot decode the new format → both ends must update). See `cogworks/docs/SYNDICATOR_INTEGRATION.md` "The Sync.lua rewire" section for the full pattern.

**Mail-as-inventory dissolves entirely.** Your line 22-35 analysis is correct — under Syndicator, mail inventory is one `MailCacheUpdate` subscription. The earlier Postal-style mail-scanner research (50-cap workaround, multi-batch refresh, `TakeInboxItem` throttling, front-insertion race) is irrelevant. Drop the mail-scanner work from `v0.10.2`. There is one caveat about the 50-cap that's worth knowing — see Q9 below.

### Canonical documents to read next

- `C:\src\cogworks\docs\AGENT_BRIEF.md` — single-page suite overview
- `C:\src\cogworks\docs\SYNDICATOR_INTEGRATION.md` — full Syndicator implementation guide with code sketches for `ItemLookup.lua`, `SlotVerifier.lua`, and the Sync.lua rewire shape. **Read this before writing the `v0.11.0-alpha1` implementation plan.**
- `C:\src\cogworks\docs\PLAN.md` Phase 1 + Phase 6a — updated phased rollout reflecting the `v0.10.2` / `v0.11.0` split

### Open questions answered

**API surface (concrete signatures)**

1. The function is `Syndicator.API.GetByCharacterFullName("Name-Realm")`, NOT `GetCharacter`. Returns `{ bags, bank, bankTabs, mail, equipped, void, auctions, currencies, currencyByHeader, money, containerInfo, details }`. Per-slot data: `{ itemID, itemCount, iconTexture, itemLink, quality, isBound, hasLoot }`. The `itemLink` is the FULL hyperlink (preserves bonusIDs, enchants, suffixes) — not a collapsed itemID.

2. `Syndicator.API.GetInventoryInfo(itemLink, sameRealm, sameFaction)` returns pre-aggregated cross-character/guild totals from the SUMMARY index. Differs from `GetByCharacterFullName` which returns raw per-character data. **Critical caveat:** the summary index keys by `item:<itemID>` and collapses bonusIDs onto one entry. For bonusID-aware queries (R1/R2/R3 crafted gear, transmog suffix variants, etc.), walk raw character data and re-key via `ns:MakeItemKey(ns:ParseItemLink(slot.itemLink))` — never use `GetInventoryInfo()` for those.

3. `Syndicator.API.GetWarband(1)` returns `{ bank, money, details = { gold=true, inventory=true } }`. The bank tabs include `{ slots, iconTexture, name, depositFlags }`. **Yes, deposit flags are exposed** — per-tab item-class filters that FlipQueue's picker honors today can read directly from Syndicator's `depositFlags`.

4. `Syndicator.API.GetCurrencyInfo(currencyID, sameRealm, sameFaction)` returns aggregated per-character breakdowns. There's also a per-character `currencies` field on `GetByCharacterFullName` for raw data.

5. `Syndicator.API.GetAllCharacters()` returns a list of `"Name-Realm"` keys. Use them with `GetByCharacterFullName` for full character data. Warband is separate via `GetWarband(1)`.

6. `Syndicator.API.IsReady()` becomes true after Syndicator finishes its initial scan post-`PLAYER_LOGIN`. Subscribe to the `Ready` callback OR poll `IsReady()` defensively. Cogworks's `cw:HasSyndicator()` already wraps the check.

**Callback signatures**

7. `Syndicator.CallbackRegistry:RegisterCallback("EventName", handler, owner)` — Blizzard `CallbackRegistryMixin` style. NOT Ace3, NOT LibStub. Unregister with `:UnregisterCallback("EventName", owner)`. Owner argument is required for unregistration.

8. `BagCacheUpdate` fires with `(eventName, character, updates)` where `updates` is a dirty descriptor with `bags / bank / containerBags` keys telling you which containers actually changed. **Debounced via Syndicator's internal OnUpdate coalesce** — burst events from a stack-split or mass-loot combine into a single fire. This is the gold standard pattern your Phase 6a should consume rather than re-implement.

9. `MailCacheUpdate` fires when Syndicator detects mail changes via `MAIL_INBOX_UPDATE`. **About your earlier mail-50-cap concern:** Syndicator does NOT implement Postal-style multi-batch refresh past the visibility cap. It scans whatever's visible when the inbox updates. **For FlipQueue's sales-reconciliation use case this is fine** — auction-success mail is typically the most recent (front of inbox) so the 50-cap rarely matters in practice. If a future feature needs deeper history, layer a refresh helper on top of Syndicator's data; do NOT replace Syndicator with a custom scanner. Documented as a caveat in `SYNDICATOR_INTEGRATION.md`.

10. `WarbandBankCacheUpdate` fires per warband bank tab change. Whole-bank refresh, not per-slot diffs.

11. `AuctionsCacheUpdate` — yes, Syndicator tracks owned auctions via its own listener on `OWNED_AUCTIONS_UPDATED`. Your `Tracker.lua`'s `OWNED_AUCTIONS_UPDATED` handler should subscribe to Syndicator's `AuctionsCacheUpdate` instead. The historical posting log (status transitions: posted → sold/expired) stays in `TrackerAuctions.lua` — only the live current-auctions state moves to Syndicator.

**Item key format**

12. **Item identity:** Per-slot raw data preserves the full `itemLink`. Use FlipQueue's existing `ns:ParseItemLink()` to extract `(itemID, bonusIDs, modifiers)`, then `ns:MakeItemKey()` to build the canonical `itemID;bonusIDs;modifiers` key. **No translation layer is needed** — Syndicator stores the same itemLinks FlipQueue already parses today.

13. **Bonus IDs preserved** in raw slot itemLinks. Lost only in the summary index (`GetInventoryInfo`). The Midnight per-bonus performance distinction stays intact as long as you walk raw character data.

14. **Stack counts:** per-slot `itemCount` field in raw data. Summary index aggregates across slots/characters. Same shape as FlipQueue's existing bag scan.

**Data freshness**

15. **When Syndicator scans:** PLAYER_LOGIN, BAG_UPDATE (debounced via OnUpdate coalesce), bank/warband UI open events, mail UI events, auction events. Background timers for nothing — purely event-driven. Same model FlipQueue uses today, just owned by Syndicator.

16. **Stale data window:** typically <1 frame during normal play. Longer for bank/warband when their UIs are closed (those events only fire when the UI is open). For BankQueue's verify-before-click, **call `C_Container.GetContainerItemInfo(bagID, slotID)` directly at click time** — don't trust any cache, including Syndicator's. The slot verifier in `SYNDICATOR_INTEGRATION.md` handles this correctly.

17. **Realm normalization:** Syndicator uses `GetNormalizedRealmName()` — same convention as Cogworks's `cw:GetCharacterKey()`. Connected realms are NOT specifically grouped by Syndicator (treated as separate by-name realms). FlipQueue's `RealmData.lua` connected-realm clustering stays as a FlipQueue concern (may eventually migrate into Cogworks-1.0, but that's a later phase).

**What Syndicator does NOT cover**

18. **TSM** — confirmed, stays in FlipQueue.
19. **FlippingPal sync** — confirmed, stays.
20. **Sales tracking** — `TrackerMail.lua` reconciliation stays in FlipQueue. The Cogworks plan eventually moves the *persisted log* to the Ledger cog, but reconciliation logic stays here. FlipQueue fires `cw.Events.SaleLogged` after reconciliation; Ledger subscribes and persists.
21. **BNet cross-account sync** — answered above under Strategic Decisions. `Sync.lua` stays, rewired to Syndicator data on the local side.

**Migration mechanics**

22. **One-shot SV migration:** hard delete of `FlipQueueDB.characters[*].inventory` blobs **after** the dev flag is removed. The implementation order in `SYNDICATOR_INTEGRATION.md` gates the new path behind a `FlipQueueDB.devSyndicatorMode` flag during dev so both paths can run in parallel for validation. The hard delete only fires after the flag is removed and Phase 6a ships. Schema canary + no-op migration first per PLAN.md Phase 3 SV-touching rules.

23. **Players who skip Syndicator install:** TOC `## Dependencies: Syndicator` makes WoW refuse to load FlipQueue if Syndicator is absent. Failure mode is "FlipQueue greyed out in addon list" with a missing-dependency message — not "silently missing features." CurseForge auto-installs hard deps. Wago is the manual edge case but the changelog should call this out clearly. Acceptable per the alpha-tolerance principle.

### Two additions to your risk table

Your risk table is solid. Two suggestions from the suite-agent vantage point:

- **Migration shim that proxies reads.** Line 138 mentions UI pages reading from `ns.db.characters[charKey].inventory.*` today. The migration shim can preserve that read interface for one transition release by exposing a metatable `__index` that proxies reads to Syndicator. This lets `v0.11.0-alpha1` ship without rewriting every UI page in the same alpha. UI rewrites can come in `v0.11.x` follow-ups. Worth considering — not a hard recommendation, but it shrinks the v0.11.0-alpha1 diff substantially.
- **Sync.lua protocol bump compat window.** Both ends must run the new format. If a player updates the local side but not the partner side, the partner's cross-account view goes stale silently. Recommend: include a protocol version field in the broadcast envelope, and have the receiver log a clear "partner is on old protocol, please update FlipQueue on this account" message rather than failing silently.

### Cleared to proceed

You are cleared to start writing the `v0.10.2-alpha1` implementation plan (Phase 1 embedding only — bundle Cogworks-1.0 via `.pkgmeta` external, declare in `.toc`, register the addon, debug print, ship). When that stabilizes, write the `v0.11.0-alpha1` plan (Phase 6a) using `C:\src\cogworks\docs\SYNDICATOR_INTEGRATION.md` as the implementation reference.

The Ledger cog work (Phase 6b) will start after `v0.11.0-alpha1` is stable, so you have time to surface any Syndicator gotchas during Phase 6a before the Ledger commits to the same patterns.

**Coordination request:** when you have a draft `v0.11.0-alpha1` implementation plan at `C:\src\flipqueue\docs\phase-6a-scanner-collapse.md`, drop the path back here (or just tell the user) and the suite agent will review for cross-cog consistency before any code lands.
