#!/usr/bin/env bash
# pre-tag-check.sh — mechanical pre-tag gate for chronoforge cogs.
#
# Synced from cogworks/shared/scripts/pre-tag-check.sh; edits to the canonical
# version live there. Add the file to .cogworks-sync-skip to opt out per cog.
#
# Usage:
#   bash scripts/pre-tag-check.sh <tag>
# Examples:
#   bash scripts/pre-tag-check.sh v0.14.0-alpha1
#   bash scripts/pre-tag-check.sh v0.14.0
#
# Exit 0 = mechanical checks passed (F8 still requires human confirmation).
# Exit 1 = one or more hard failures.
# Exit 2 = usage error.
#
# See cogworks/runbooks/branch-and-release-flow.md for what F1–F8 mean.

set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "usage: $0 <tag>" >&2
  echo "       e.g. $0 v0.14.0-alpha1" >&2
  exit 2
fi

errors=0
warnings=0

fail() { echo "FAIL: $*" >&2; errors=$((errors+1)); }
warn() { echo "WARN: $*" >&2; warnings=$((warnings+1)); }
ok()   { echo "  ok: $*"; }
note() { echo "note: $*"; }

echo "Pre-tag check for tag: $TAG"
echo

# ── F1: working tree clean on main/master ──────────────────────────────────
echo "[F1] working tree clean on main/master"
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ "$branch" != "main" && "$branch" != "master" ]]; then
  fail "not on main/master (current branch: $branch)"
else
  ok "on $branch"
fi
if [[ -n "$(git status --porcelain)" ]]; then
  fail "working tree dirty (uncommitted changes present)"
else
  ok "working tree clean"
fi

# ── F2: CI green on the tag's commit ───────────────────────────────────────
echo "[F2] CI green on HEAD"
if command -v gh >/dev/null 2>&1; then
  status=$(gh run list --branch "$branch" --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || echo "unknown")
  case "$status" in
    success) ok "latest run on $branch concluded: success" ;;
    "")      warn "no recent runs found on $branch (gh returned empty)" ;;
    unknown) warn "could not query gh for run status (auth or network?)" ;;
    *)       fail "latest run on $branch concluded: $status" ;;
  esac
else
  warn "gh not installed; cannot verify CI status — confirm manually before tagging"
fi

# ── F3: .pkgmeta Cogworks pin (advisory) ───────────────────────────────────
echo "[F3] .pkgmeta Cogworks-1.0 pin"
if [[ -f .pkgmeta ]]; then
  pin=$(awk '
    /Cogworks-1\.0:/ { in_block=1; next }
    in_block && /tag:/ { gsub(/^[[:space:]]+tag:[[:space:]]*/, ""); print; exit }
    in_block && /^[^[:space:]]/ { in_block=0 }
  ' .pkgmeta || echo "")
  if [[ -n "$pin" ]]; then
    ok "Cogworks-1.0 pinned to $pin"
    note "F3 is advisory — confirm $pin matches what was tested in F8"
  else
    warn "could not parse Cogworks-1.0 tag from .pkgmeta"
  fi
else
  note "no .pkgmeta in this repo (skipping F3)"
fi

# ── F4: RELEASES.md has section for tag ────────────────────────────────────
echo "[F4] RELEASES.md has section for $TAG"
if [[ -f RELEASES.md ]]; then
  if grep -qE "^## \[?${TAG//./\\.}(\]| |$)" RELEASES.md; then
    ok "RELEASES.md has $TAG section"
  else
    fail "RELEASES.md missing section for $TAG (heading must match '## $TAG' or '## [$TAG]')"
  fi
else
  note "no RELEASES.md in this repo (skipping F4 — verify this is intentional, e.g. cogworks)"
fi

# ── F5: CHANGELOG.md has entry for tag ─────────────────────────────────────
echo "[F5] CHANGELOG.md has entry for $TAG"
if [[ -f CHANGELOG.md ]]; then
  if grep -qE "^## \[?${TAG//./\\.}(\]| |$)" CHANGELOG.md; then
    ok "CHANGELOG.md has $TAG section"
  else
    fail "CHANGELOG.md missing section for $TAG"
  fi
else
  fail "CHANGELOG.md not found — every cog needs an engineering changelog"
fi

# ── F6: tag name uses literal "alpha"/"beta" (not -aN/-bN) ─────────────────
echo "[F6] tag naming convention"
if [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]]; then
  if [[ "$TAG" =~ -[ab][0-9]+$ ]]; then
    fail "tag '$TAG' uses '-aN'/'-bN' shorthand; BigWigsMods packager needs literal 'alpha'/'beta'"
  else
    ok "tag format looks well-formed"
  fi
else
  warn "tag '$TAG' does not match vX.Y.Z[-suffix] pattern (verify intentional)"
fi

# ── F7: closed-issue refs since previous tag are in CHANGELOG (advisory) ───
echo "[F7] closed-issue refs since previous tag covered in CHANGELOG"
prev_tag=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
if [[ -n "$prev_tag" ]] && [[ -f CHANGELOG.md ]]; then
  commit_msgs=$(git log --format=%s%n%b "$prev_tag..HEAD" 2>/dev/null || echo "")
  refs=$(echo "$commit_msgs" | grep -oE '([A-Z]+-[0-9]+|#[0-9]+)' | sort -u || true)
  missing=()
  if [[ -n "$refs" ]]; then
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      if ! grep -qF "$ref" CHANGELOG.md; then
        missing+=("$ref")
      fi
    done <<< "$refs"
  fi
  if (( ${#missing[@]} == 0 )); then
    ok "all referenced issues since $prev_tag appear in CHANGELOG.md"
  else
    warn "issue refs in commits since $prev_tag but missing from CHANGELOG.md: ${missing[*]}"
  fi
else
  note "no previous tag found or CHANGELOG missing (skipping F7)"
fi

# ── F8: human-only reminder ────────────────────────────────────────────────
echo "[F8] in-game smoke test (human-only)"
note "F8 is not checked by this script — the agent must explicitly confirm with the user"

# ── Summary ────────────────────────────────────────────────────────────────
echo
echo "─────────────────────────────────"
if (( errors > 0 )); then
  echo "Pre-tag check: $errors error(s), $warnings warning(s) — FAIL"
  exit 1
fi
if (( warnings > 0 )); then
  echo "Pre-tag check: $warnings warning(s) — review before proceeding"
fi
echo "Mechanical checks passed. F8 (in-game smoke test) still requires human confirmation."
exit 0
