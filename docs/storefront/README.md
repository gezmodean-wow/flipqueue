# FlipQueue storefront materials

Project-page assets for CurseForge and Wago. **Updated only on public releases**, not on alphas.

## Files in this directory

- **`description.md`** — full project description that goes in the CurseForge / Wago project page main content area. Source of truth for the pitch text. Copy-paste into both dashboards on each public release.
- **`short-description.md`** — one-line tagline shown in addon listings and search results. Same on both platforms.
- **`screenshots/`** — current screenshot set referenced by the project pages. Numbered to indicate display order. Re-upload when UI changes materially.
- **`faq.md`** *(to add)* — common Q&A for the project page. Currently TBD.

## Why these are tracked in repo

CurseForge has no description-update API ([CF-I-6366](https://curseforge-ideas.overwolf.com/ideas/CF-I-6366) is in "Future consideration" since 2024-06), and Wago similarly has no documented endpoint. Project-page descriptions, FAQs, screenshots, tags, and links can only be edited via the web dashboards. Versioning the source content here means:

- One canonical place to revise the text — pull request review, history, blame.
- No risk of "what does the description currently say?" confusion.
- A single per-release chore: paste the latest version into both dashboards.

## What's automated

- **Per-release changelog** (the "Changelog" tab on the project page) — auto-pushed from `RELEASES.md` on every release tag via the BigWigsMods packager's `manual-changelog` directive in `.pkgmeta`. No manual step.
- **Required / optional dependency relations** — auto-pushed from `.pkgmeta`'s `required-dependencies` and `optional-dependencies` lists. (CurseForge re-syncs on every upload; Wago doesn't expose a relations concept the same way, but its installer reads the toc's `## Dependencies` line.)
- **File uploads** — handled by the GitHub Actions workflow on every tag push.

## What stays manual (this directory's purpose)

- Project description text
- Screenshots / project images
- FAQ tab content
- Project tags / categories
- Source link / wiki link / issue tracker link
- Featured-features highlight section

## Public-release workflow

When tagging a full public release (no `-alphaN` / `-betaN` suffix):

1. **Review `description.md`** — does it still describe the addon accurately? Are the headline features still the right ones? Any new capabilities since the last public release that deserve mention?
2. **Update screenshots if UI changed** — drop new files in `screenshots/`, update the order numbers, note in the commit message which CurseForge / Wago slots they fill.
3. **Review `RELEASES.md`** — is the section for the just-tagged version final? Does the prose describe what shipped, not what was attempted?
4. **Tag the release.** Packager auto-uploads files, dependency relations, and the changelog tab.
5. **Manual paste step** — open the CurseForge dashboard for FlipQueue, edit the description, paste the contents of `description.md`. Save. Repeat on Wago.
6. **Commit any updated screenshots** to this directory so the next release inherits the current state.

For alpha and beta releases, skip steps 1, 2, and 5 — the project page stays on whatever the last public release described. Players running alphas already know they're testing pre-release builds.

## When to break this rule

Never. The whole point is the project page only changes on public releases — that's the contract with players reading it. If a feature lands mid-alpha and the description needs to talk about it, that's the cue to cut a public release.
