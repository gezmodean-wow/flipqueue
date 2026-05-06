# FlipQueue - Claude Code Instructions

## Permissions
- Allowed to create, edit, and delete files in this repo without confirmation
- Allowed to run git commands (commit, push, branch, etc.) without confirmation
- Allowed to run `gh` CLI commands (create repos, PRs, issues) in the `gezmodean-wow` org
- Allowed to create/modify files in `C:\src\flipqueue\` and subdirectories
- Allowed to read files in WoW AddOns directory for reference: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
- Allowed to run lua syntax checks and file operations without asking

## Project Context
- WoW addon (Lua, .toc) for The War Within (Interface 120005, current retail only)
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

## Standards acknowledgments

Each session, check the top entry of each source against the codes below. If newer, prefix the first response with `Standards updated:` plus a one-line summary per new entry, then update the code below as part of the session's commit.

| Source | Last acknowledged |
|---|---|
| [comms conventions](https://github.com/gezmodean-wow/cogworks/blob/main/runbooks/comms-conventions.md) | 2026-05-05a |
| [branch & release flow](https://github.com/gezmodean-wow/cogworks/blob/main/runbooks/branch-and-release-flow.md) | 2026-05-05a |
| [doc conventions](https://github.com/gezmodean-wow/cogworks/blob/main/runbooks/doc-conventions.md) | 2026-05-05a |
| [technical standards](https://github.com/gezmodean-wow/cogworks/blob/main/runbooks/technical-standards.md) | 2026-05-05a |
| [shared/ file pool](https://github.com/gezmodean-wow/cogworks/blob/main/shared/VERSION) | 2026-05-05a — `bash scripts/sync-standards.sh check` |
| [standards-sync (this mechanism)](https://github.com/gezmodean-wow/cogworks/blob/main/runbooks/standards-sync.md) | 2026-05-05a |

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

**GitHub is canonical.** Issues live at https://github.com/gezmodean-wow/flipqueue/issues — this is the single source of truth for bugs, feature requests, and engineering discussion. The `scribe` bot (deployed on Railway, source at `C:/src/scribe`) mirrors Discord forum activity into GitHub issues automatically and broadcasts engineering comments back to the Discord thread.

When shipping a fix for a tracked issue, post the engineering note as a comment on the GitHub issue via `gh issue comment <number> --repo gezmodean-wow/flipqueue --body "..."`. Don't update Discord directly — scribe handles propagation.

FlipQueue issue IDs use the prefix `FQ` (e.g. `FQ-001`). The GitHub issue number is the canonical identifier; the `FQ-N` ID is for commit-message convenience.

### Proactive capture

When the user mentions a bug, regression, feature idea, or improvement during normal work, offer to file or update the GitHub issue. Don't open issues unprompted; ask first. When shipping a fix for a tracked issue, offer to post a status comment to the GitHub issue.

Commit messages referencing a tracked issue should use `<type>(<ID>): <subject>` — e.g. `fix(FQ-004): sniper delay cancels on target change`.

### Player-facing standards (canonical source)

Conventions for `## Player summary` (issue body), `## Player update` (issue comments), and player-facing release copy live in the SCRIBE repo. This file is the single source of truth — do not restate the rules here.

**Required:** `WebFetch` the canonical doc before any of the following:

- Closing a player-visible issue
- Writing a GitHub comment that wants a player response
- Tagging a release or writing a `CHANGELOG.md` entry

URL: https://raw.githubusercontent.com/gezmodean-wow/scribe/main/docs/PLAYER_FACING_CONVENTIONS.md

The doc has a `## Changelog` section at the top. Compare its most recent entry code to the line below. If newer entries exist, prefix your first response with `Standards updated:` plus a one-line summary of each new entry, then update the code below in this file.

**Last acknowledged:** 2026-04-30f

## Release artifacts: dual changelog + storefront

FlipQueue maintains two changelogs and a separate storefront-materials directory:

- **`CHANGELOG.md`** — engineering-focused. Internal terminology, file:line references, full alpha-by-alpha breakdown. Used during development; not pushed to project pages. Update on every alpha as part of the release commit.
- **`RELEASES.md`** — player-facing. Plain language, organized by what players see and do, no commit references or file paths. **This is the file that flows through `.pkgmeta`'s `manual-changelog` directive to the CurseForge / Wago changelog tabs on every release.** Update on every alpha *and* when refining prose for clarity — the project-page tab will pick up the new wording on the next upload.
- **`docs/storefront/`** — long-form project-page assets (description, short description, screenshots). Versioned in repo, **hand-pasted to CurseForge / Wago dashboards on public releases only**. See `docs/storefront/README.md` for the full workflow.

When tagging an alpha or beta: only `CHANGELOG.md` and `RELEASES.md` need touching. The storefront stays on whatever the last public release described.

When tagging a public release (no `-alphaN` / `-betaN` suffix): also review `docs/storefront/description.md`, refresh screenshots if UI changed materially, then paste `description.md` into both project dashboards. The release commit updates `CHANGELOG.md` and finalizes the relevant section of `RELEASES.md`.

## Cross-cog feature requests

When you spot a gap in a sibling cog's library while working here — most often Cogworks (the shared core) needing a new helper, event, or primitive — offer to file a GitHub Issue on that cog's tracker via `gh issue create --repo gezmodean-wow/<target-cog>`. Mention FlipQueue as the source in the body so the maintainer can triage it as a cross-cog ask. Scribe will mirror it to the target cog's Discord forum where its players can follow along.
