<!--
This file is synced from cogworks/shared/.github/ISSUE_TEMPLATE/task.md.
Edits to the canonical version live there. Per-cog overrides go via .cogworks-sync-skip.
-->

---
name: Task / feature
about: Implementation work, refactor, chore
title: ''
labels: ['needs-triage']
---

## Goal

<!-- One sentence. What outcome does this ticket produce? -->

## Acceptance criteria

<!--
Bulleted, testable. An agent should be able to look at this list and decide "am I done?".

Example for a chore:
- `.pkgmeta` `Libs/Cogworks-1.0` external is pinned to `v0.13.2` (was `v0.13.1`)
- `release.yml` `verify-package.yml` ref is pinned to `@v0.13.2` (was `@main`)
- Local `bash scripts/pre-tag-check.sh v0.12.0-alpha18` passes F1–F7
- PR description states which in-game flow was exercised post-bump

Example for a feature:
- `/fq config import-window 30` slash command sets the import window in seconds
- Setting persists across `/reload`
- Default value is unchanged (no migration needed)
- About page surfaces the current value
-->

-

## Out of scope

<!--
Optional but recommended. Prevents scope creep mid-implementation. State adjacent things that COULD be done but explicitly aren't part of this ticket.

Example:
- Updating other cogs' `.pkgmeta` pins — those get their own per-cog tickets.
- Refactoring the pre-cluster dedup pass — that's TLY-N.
-->

-

## References

<!--
Optional. Linked tickets, runbook references, PR drafts.
- Master ticket: COG-N
- Runbook: cogworks/runbooks/library-bump-propagation.md
-->
