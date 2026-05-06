<!--
This file is synced from cogworks/shared/.github/ISSUE_TEMPLATE/bug.md.
Edits to the canonical version live there. Per-cog overrides go via .cogworks-sync-skip.
-->

---
name: Bug report
about: Something is misbehaving in-game
title: '[bug] '
labels: ['bug', 'needs-triage']
---

## Steps to reproduce

<!--
Numbered list. Be specific enough that an agent (or another player) could re-walk it without asking.

Example:
1. Open the bank in a city.
2. Click the "Deposit Reagents" drawer button.
3. Observe the chat output.
-->

1.
2.
3.

## Expected behavior

<!-- What you thought would happen. -->

## Actual behavior

<!-- What actually happened. Include error messages verbatim if any. -->

## Environment

- Cog + version: <!-- e.g. flipqueue v0.12.0-alpha17. Run `/<cog> version` if available. -->
- WoW build: <!-- retail / classic / cataclysm; build number if you have it -->
- Cogworks-1.0 version: <!-- shown by `/<cog> version` or in the About page; "embedded in cog" is fine if you don't know -->
- Other addons that might interact: <!-- TSM, Auctionator, Syndicator, Journalator, Bagnon, ElvUI, etc. -->

## Severity (filer's best guess; triage may adjust)

- [ ] **Critical** — blocks login, corrupts saved variables, or causes a Lua error on every UI open
- [ ] **High** — functional regression with a workaround
- [ ] **Medium** — annoyance or confusing behavior
- [ ] **Low** — cosmetic / polish

## Diagnostics

<!--
Run `/<cog> debug` (e.g. `/tally debug`, `/fq debug`) → click "Copy diagnostics" →
paste the output here. Or open the cog's About page and click the same button.

This bundles version + settings + state + recent debug log into one block.
Without it, triage usually round-trips back to you for the same info.
-->

```
<paste Copy diagnostics output here>
```

## Additional context

<!--
Optional. Screenshots, BugSack output, related ticket links.
For Discord-mirrored reports: paste the relevant scribe-bridged thread link here.
-->
