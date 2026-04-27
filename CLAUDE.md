# FlipQueue - Claude Code Instructions

## Permissions
- Allowed to create, edit, and delete files in this repo without confirmation
- Allowed to run git commands (commit, push, branch, etc.) without confirmation
- Allowed to run `gh` CLI commands (create repos, PRs, issues) in the `gezmodean-wow` org
- Allowed to create/modify files in `C:\src\flipqueue\` and subdirectories
- Allowed to read files in WoW AddOns directory for reference: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
- Allowed to run lua syntax checks and file operations without asking

## Project Context
- WoW addon (Lua, .toc) for The War Within (Interface 120001)
- GitHub org: `gezmodean-wow` (private)
- Repo: `gezmodean-wow/flipqueue`
- Local path: `C:\src\flipqueue`
- WoW symlink: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\flipqueue` -> `C:\src\flipqueue`
- SavedVariables: FlipQueueDB (account-wide)

## Cogworks suite context

This addon is part of the **Cogworks** WoW addon suite alongside Tempo, Maxcraft, and Tally. The shared core lives at `C:\src\cogworks\`. Before making structural or architectural changes, read:

- `C:\src\cogworks\docs\AGENT_BRIEF.md` — single-page suite overview
- `C:\src\cogworks\docs\PLAN.md` — integration plan and phased rollout
- `C:\src\cogworks\docs\SYNDICATOR_INTEGRATION.md` — implementation patterns for Syndicator migration (complete)

**Live-user constraints:** This cog is published on CurseForge and Wago. The SavedVariables name `FlipQueueDB`, the slash commands `/fq` and `/flipqueue`, and the addon folder name `flipqueue` are all immutable without a migration plan — renaming any of them would break every existing install. The item key format `itemID;bonusIDs;modifiers` is also user-data-shaped and matched against external imports (FlippingPal, TSM, Auctionator).

**Upcoming change (Phase 6a):** The Cogworks integration plan makes Syndicator a hard dependency for FlipQueue, collapses ~600 LOC of `Scanner.lua` onto Syndicator's API, adds a small `ItemLookup.lua` lazy lookup cache, keeps `Sync.lua` (BNet multi-account) but rewires its source of truth, and preserves `TrackerMail.lua` / `TrackerAuctions.lua` / `SalesIndex.lua` untouched. See `SYNDICATOR_INTEGRATION.md` for the preservation list and implementation patterns. Don't start that work without coordinating with the user.

## Coding Conventions
- All Lua files use `local addonName, ns = ...` for namespace
- Colors defined in Core.lua ns.COLORS table
- Use WoW native templates (BasicFrameTemplateWithInset, GameMenuButtonTemplate, etc.)
- Item key format: `itemID;bonusIDs;modifiers` (matches FlippingPal)

## User Preferences
- Keep last character slot as "flex slot" for temp characters on sell realms
- German EU account - item names and realm names may be in German
- Uses FlippingPal.com + TSM + Auctionator for cross-realm arbitrage
- Prefers clean TSM-like UI styling (tabular data, sortable columns, side navigation)

## Feedback tracking

**GitHub is canonical.** Issues live at https://github.com/gezmodean-wow/flipqueue/issues — this is the single source of truth for bugs, feature requests, and engineering discussion. The `scribe` bot mirrors Discord forum activity into GitHub issues automatically and broadcasts engineering comments back to the Discord thread.

When shipping a fix for a tracked issue, post the engineering note as a comment on the GitHub issue via `gh issue comment <number> --repo gezmodean-wow/flipqueue --body "..."`. Don't update Discord directly — scribe handles propagation.

The local `feedback/` directory is **legacy / transitional**. Older issues have md files there; new issues should not. Existing md files are being reduced to thin pointers at their canonical GitHub issue (see `feedback/collection/FQ-003-...md` for the pattern).

FlipQueue issue IDs use the prefix `FQ` (e.g. `FQ-001`). The GitHub issue number is the canonical identifier; the `FQ-N` ID is for commit-message convenience.

### Proactive capture

When the user mentions a bug, regression, feature idea, or improvement during normal work, offer to file or update the GitHub issue. Don't open issues unprompted; ask first. When shipping a fix for a tracked issue, offer to post a status comment to the GitHub issue.

Commit messages referencing a tracked issue should use `<type>(<ID>): <subject>` — e.g. `fix(FQ-004): sniper delay cancels on target change`.

The `/feedback-*` slash commands (feedback-capture, feedback-note, feedback-ask, etc.) predate the scribe workflow and should not be used for FlipQueue. Use `gh issue` commands instead.
