#!/usr/bin/env bash
set -euo pipefail
#
# Regroup local commits (<base>..HEAD) into logical commits via soft-reset + path repartition.
#
# Usage: regroup.sh <base-ref> <mapping-file> <messages-file>
#   <mapping-file>  : lines "<bucket>\t<path>" — every changed path (incl. rename old AND new),
#                     each path exactly once. Build it from a per-task classifier (see SKILL.md).
#   <messages-file> : lines "<bucket>\t<commit subject>" — order defines commit order.
#
# The script enforces the invariants so the dangerous part is safe:
#   1. preconditions: clean index/worktree (untracked OK), base is an ancestor of HEAD
#   2. full-coverage check BEFORE reset: every changed path classified exactly once
#   3. mixed reset to base, then stage+commit each bucket with `git add -A` (handles M/A/D/rename)
#   4. verify final tree == original tree; on mismatch, report and print rollback command
#
# Assumes paths contain no embedded tabs/newlines (true for normal source trees).

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ $# -eq 3 ] || die "usage: regroup.sh <base-ref> <mapping-file> <messages-file>"
BASE_REF="$1"; MAP="$2"; MSGS="$3"
[ -f "$MAP" ]  || die "mapping file not found: $MAP"
[ -f "$MSGS" ] || die "messages file not found: $MSGS"

BASE="$(git rev-parse --verify "${BASE_REF}^{commit}" 2>/dev/null)" || die "bad base ref: $BASE_REF"
ORIG_HEAD="$(git rev-parse HEAD)"
ORIG_TREE="$(git rev-parse 'HEAD^{tree}')"

git diff --quiet         || die "unstaged tracked changes present; commit/stash them first"
git diff --cached --quiet || die "staged changes present; commit/stash them first"
git merge-base --is-ancestor "$BASE" HEAD || die "$BASE_REF is not an ancestor of HEAD"

CHANGED="$(mktemp)"; MAPPATHS="$(mktemp)"
trap 'rm -f "$CHANGED" "$MAPPATHS"' EXIT

# authoritative changed-path set (rename -> old AND new)
git diff --name-status -M "$BASE" HEAD | awk -F'\t' '
  $1 ~ /^R/ { print $2; print $3; next }
  { print $2 }' | sort -u > "$CHANGED"

awk -F'\t' 'NF>=2 {print $2}' "$MAP" | sort > "$MAPPATHS"

DUP="$(uniq -d "$MAPPATHS" || true)"
[ -z "$DUP" ] || die "path(s) assigned to multiple buckets:"$'\n'"$DUP"
sort -u "$MAPPATHS" -o "$MAPPATHS"

MISSING="$(comm -23 "$CHANGED" "$MAPPATHS")"
STALE="$(comm -13 "$CHANGED" "$MAPPATHS")"
[ -z "$MISSING" ] || die "UNCLASSIFIED (in diff, not in mapping):"$'\n'"$MISSING"
[ -z "$STALE" ]   || die "stale (in mapping, not in diff — fix mapping):"$'\n'"$STALE"

# bucket sets in mapping and messages must match (every bucket committed, none orphaned)
MAP_BUCKETS="$(awk -F'\t' 'NF>=2{print $1}' "$MAP"  | sort -u)"
MSG_BUCKETS="$(awk -F'\t' 'NF>=2{print $1}' "$MSGS" | sort -u)"
ORPHAN="$(comm -23 <(printf '%s\n' "$MSG_BUCKETS") <(printf '%s\n' "$MAP_BUCKETS"))"
UNCOMMITTED="$(comm -13 <(printf '%s\n' "$MSG_BUCKETS") <(printf '%s\n' "$MAP_BUCKETS"))"
[ -z "$ORPHAN" ]      || die "messages bucket(s) with no paths in mapping:"$'\n'"$ORPHAN"
[ -z "$UNCOMMITTED" ] || die "mapping bucket(s) missing from messages (would be left uncommitted):"$'\n'"$UNCOMMITTED"

echo "precheck OK: $(wc -l < "$CHANGED" | tr -d ' ') changed paths classified, 0 unclassified"
echo "orig HEAD: $ORIG_HEAD"
echo "orig tree: $ORIG_TREE"

git reset -q "$BASE"

while IFS=$'\t' read -r bucket subject; do
  [ -n "${bucket:-}" ] || continue
  n=0
  while IFS=$'\t' read -r b p; do
    [ "$b" = "$bucket" ] || continue
    git add -A -- "$p"; n=$((n+1))
  done < "$MAP"
  git commit -q -m "$subject"
  echo ">>> [$bucket] $n paths -> $(git log -1 --format='%h %s')"
done < "$MSGS"

NEW_TREE="$(git rev-parse 'HEAD^{tree}')"
if [ "$NEW_TREE" = "$ORIG_TREE" ]; then
  echo "PASS: final tree identical to original ($NEW_TREE)"
else
  printf 'FAIL: tree differs!\n  orig=%s\n  new =%s\n' "$ORIG_TREE" "$NEW_TREE" >&2
  git --no-pager diff --stat "$ORIG_HEAD" HEAD >&2
  printf 'rollback: git reset --hard %s\n' "$ORIG_HEAD" >&2
  exit 1
fi

printf 'rollback point (if needed): git reset --hard %s\n' "$ORIG_HEAD"
git --no-pager log --oneline "$BASE..HEAD"
