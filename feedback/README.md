# FlipQueue feedback

Per-cog feedback tracking. See [`~/.chronoforge/CONVENTIONS.md`](file:///C:/Users/gezmo/.chronoforge/CONVENTIONS.md) for schema, ID format, and lifecycle rules.

## Directories

- `collection/` — still gathering info, not yet scoped to a release
- `releases/v<X.Y.Z>/` — scoped to a target FlipQueue release
- `archive/` — shipped, wontfix, or duplicate

## ID prefix

`FQ-NNN` (e.g. `FQ-001`).

## Commands

User-scoped `/feedback-*` commands work from any Claude Code session — they route FlipQueue-scoped feedback here automatically based on the `--cog flipqueue` flag or by inference from context.
