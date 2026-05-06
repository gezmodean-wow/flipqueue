#!/usr/bin/env bash
# sync-standards.sh — agent-driven cogworks shared/ file sync.
#
# Synced from cogworks/shared/scripts/sync-standards.sh; edits to the canonical
# version live there. Add this path to .cogworks-sync-skip to opt out per cog.
#
# This script handles ONLY the file-sync source (cogworks/shared/). Convention
# sources (runbook acknowledgments, scribe PLAYER_FACING_CONVENTIONS) are
# agent-applied behaviorally — see the "Standards acknowledgments" section in
# this cog's CLAUDE.md.
#
# Usage:
#   bash scripts/sync-standards.sh check    # report whether cog is current
#   bash scripts/sync-standards.sh diff     # preview changes without applying
#   bash scripts/sync-standards.sh apply    # fetch and apply latest standards
#
# Exit codes:
#   0 — up to date / apply succeeded
#   1 — outdated (check) / apply failed / unreachable source
#   2 — usage error
#
# Source: https://raw.githubusercontent.com/gezmodean-wow/cogworks/main/shared/
# Override file: .cogworks-sync-skip (one path / glob per line; # for comments)
#
# Acknowledgment is recorded in CLAUDE.md's "Standards acknowledgments" block,
# not in this script. After a successful apply, update the `shared/` row's
# "Last acknowledged" code to the new VERSION.

set -euo pipefail

COGWORKS_REPO="${COGWORKS_REPO:-gezmodean-wow/cogworks}"
COGWORKS_REF="${COGWORKS_REF:-main}"
SHARED_BASE="https://raw.githubusercontent.com/$COGWORKS_REPO/$COGWORKS_REF/shared"

CMD="${1:-check}"

fetch() {
  local url="$1" dest="$2"
  curl -fsSL --max-time 15 "$url" -o "$dest" 2>/dev/null
}

fetch_text() {
  curl -fsSL --max-time 15 "$1" 2>/dev/null
}

get_remote_version() {
  fetch_text "$SHARED_BASE/VERSION" || true
}

get_manifest() {
  # cogworks/shared/MANIFEST is a hand-maintained list of paths under shared/,
  # one per line, comments allowed. Adding a new sync target requires updating
  # MANIFEST in cogworks. See cogworks/runbooks/standards-sync.md.
  fetch_text "$SHARED_BASE/MANIFEST" || true
}

get_local_ack() {
  # Pull the cog's currently-acknowledged shared/ version from CLAUDE.md.
  # Format expected (single line in the Standards acknowledgments table):
  #   | shared/ file pool | <code> |
  # We grep that row and extract the second pipe-delimited field.
  if [[ ! -f CLAUDE.md ]]; then
    echo ""
    return
  fi
  awk -F'|' '
    /Standards acknowledgments/ { in_block=1; next }
    in_block && /shared\// {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
      print $3
      exit
    }
    in_block && /^##[[:space:]]/ { in_block=0 }
  ' CLAUDE.md
}

is_skipped() {
  local path="$1"
  [[ -f .cogworks-sync-skip ]] || return 1
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    # Glob match against full path
    # shellcheck disable=SC2053
    if [[ "$path" == $line ]]; then
      return 0
    fi
  done < .cogworks-sync-skip
  return 1
}

cmd_check() {
  local remote local_ack
  remote=$(get_remote_version)
  if [[ -z "$remote" ]]; then
    echo "ERROR: could not fetch $SHARED_BASE/VERSION (network or cogworks unreachable)" >&2
    return 1
  fi
  local_ack=$(get_local_ack)

  if [[ -z "$local_ack" ]]; then
    echo "Standards not yet acknowledged in CLAUDE.md."
    echo "Cogworks shared/ current: $remote"
    echo "Bootstrap: run 'apply', then add the Standards acknowledgments block to CLAUDE.md."
    return 1
  fi

  if [[ "$local_ack" == "$remote" ]]; then
    echo "Up to date: shared/ at $local_ack"
    return 0
  fi

  echo "Outdated:"
  echo "  cog acknowledged: $local_ack"
  echo "  cogworks current: $remote"
  echo "Next: run 'diff' to preview, then 'apply' to update."
  return 1
}

cmd_diff() {
  local manifest tmpdir changed=0
  manifest=$(get_manifest)
  if [[ -z "$manifest" ]]; then
    echo "ERROR: could not fetch MANIFEST" >&2
    return 1
  fi

  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  echo "Proposed changes from $SHARED_BASE:"
  echo
  while IFS= read -r path; do
    path="${path%%#*}"
    path="${path#"${path%%[![:space:]]*}"}"
    path="${path%"${path##*[![:space:]]}"}"
    [[ -z "$path" ]] && continue

    if is_skipped "$path"; then
      echo "  SKIP $path  (.cogworks-sync-skip)"
      continue
    fi

    local tmpfile="$tmpdir/$(echo "$path" | tr '/' '_')"
    if ! fetch "$SHARED_BASE/$path" "$tmpfile"; then
      echo "  WARN $path  (could not fetch)"
      continue
    fi

    if [[ ! -f "$path" ]]; then
      echo "  NEW  $path"
      changed=$((changed+1))
    elif ! cmp -s "$path" "$tmpfile"; then
      echo "  MOD  $path"
      changed=$((changed+1))
    else
      echo "  ok   $path"
    fi
  done <<< "$manifest"

  echo
  if (( changed == 0 )); then
    echo "No changes."
    return 0
  fi
  echo "$changed file(s) would change."
}

cmd_apply() {
  local manifest applied=0 skipped=0 failed=0
  manifest=$(get_manifest)
  if [[ -z "$manifest" ]]; then
    echo "ERROR: could not fetch MANIFEST" >&2
    return 1
  fi

  while IFS= read -r path; do
    path="${path%%#*}"
    path="${path#"${path%%[![:space:]]*}"}"
    path="${path%"${path##*[![:space:]]}"}"
    [[ -z "$path" ]] && continue

    if is_skipped "$path"; then
      skipped=$((skipped+1))
      continue
    fi

    mkdir -p "$(dirname "$path")"
    if fetch "$SHARED_BASE/$path" "$path"; then
      applied=$((applied+1))
    else
      echo "FAIL: could not fetch $path" >&2
      failed=$((failed+1))
    fi
  done <<< "$manifest"

  if (( failed > 0 )); then
    echo "Apply incomplete: $applied applied, $skipped skipped, $failed failed" >&2
    return 1
  fi

  local remote
  remote=$(get_remote_version)
  echo "Applied $applied file(s); skipped $skipped (per .cogworks-sync-skip)."
  echo "Cogworks shared/ version: $remote"
  echo
  echo "Next steps:"
  echo "  1. Update CLAUDE.md Standards acknowledgments → shared/ row to $remote"
  echo "  2. Review the diff: git status && git diff"
  echo "  3. Open as chore PR: chore/sync-standards-$remote"
  echo "  4. CI must pass before merge."
  return 0
}

case "$CMD" in
  check) cmd_check ;;
  diff)  cmd_diff ;;
  apply) cmd_apply ;;
  *)
    echo "usage: $0 {check|diff|apply}" >&2
    exit 2
    ;;
esac
