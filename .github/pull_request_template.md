<!--
This file is synced from cogworks/shared/.github/pull_request_template.md.
Edits to the canonical version live there. Per-cog overrides go via .cogworks-sync-skip.
-->

## What

<!-- One sentence: what this PR does. -->

## Why

Closes <COG>-N <!-- or Refs <COG>-N if not closing -->

<!-- One sentence on the underlying motivation if not obvious from the linked issue. -->

## What was tested

<!--
Required. State the manual verification path you actually walked. "N/A — packaging only" or "N/A — docs only" is acceptable when literally true.

Examples that work for review:
- "/reload, opened the bank, confirmed deposit-tasks button still fires; manually deposited reagents, no change in behavior."
- "Ran `bash scripts/pre-tag-check.sh v0.14.0-alpha1` — passed F1–F7."
- "Imported a 50k-row TSM CSV; /tally diag showed `compressMs` < 300ms post-fix."
- "N/A — runbook edit only."
-->

## Self-review checklist

- [ ] Issue linked above (`Closes <ID>` or `Refs <ID>`)
- [ ] Manual exercise described above (or "N/A — <reason>")
- [ ] CI green on this branch (`verify-package` + any other workflow checks)
- [ ] No leftover debug prints / TODOs without a follow-up ticket
- [ ] RELEASES.md updated under `## Unreleased` (or "N/A — eng-only / docs-only / etc.")
- [ ] CHANGELOG.md updated under `## [Unreleased]` (or "N/A — same reasons")
- [ ] If this PR bumps Cogworks-1.0 in `.pkgmeta` or the workflow ref: bumped both to the same tag, in this PR alone (no other changes bundled)

## Out-of-scope follow-ups

<!--
Optional. Anything you noticed but deliberately deferred. Each item should already have a ticket OR a one-line note that it needs one.
- "Refactor the pre-cluster dedup pass — TLY-N to file"
- "Tooltip text alignment is off in classic; same root as #142, leaving for that PR"
-->
