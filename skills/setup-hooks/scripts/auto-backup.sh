#!/usr/bin/env bash
set -uo pipefail

# Backup step injected in front of a destructive git command by guard-commands.py.
#
# The caller chains this with `&&`, so exit 0 lets the original command run and
# exit 1 blocks it. Everything here exists to make one guarantee: the original
# command never runs unless the working tree it would destroy has been captured
# and restored, or there was nothing to capture.

LABEL=${1:-command}
KEEP_RECENT=10
PRUNE_AFTER_DAYS=7

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# refs/stash is repository-global while a repo may have many worktrees, so the
# branch name alone does not say which tree a backup came from.
top=$(git rev-parse --show-toplevel 2>/dev/null) || top=""
worktree=$(basename "${top:-unknown}")

# Only entries this hook wrote are ever dropped. A stash the user made by hand
# is not ours to expire.
BACKUP_MARK="auto-backup "

prune_old_backups() {
  local cutoff idx
  cutoff=$(( $(date +%s) - PRUNE_AFTER_DAYS * 86400 ))
  # Dropping shifts every higher index down by one, so the deletions run from
  # the highest index downwards — descending order is what keeps each remaining
  # index valid at the moment it is used.
  git stash list --format='%ct|%gs' 2>/dev/null | awk -F'|' \
    -v keep="$KEEP_RECENT" -v cutoff="$cutoff" -v mark="$BACKUP_MARK" '
      { idx = NR - 1 }
      idx >= keep && ($1 + 0) < cutoff && index($2, mark) > 0 { print idx }
    ' | sort -rn | while read -r idx; do
      git stash drop "stash@{$idx}" >/dev/null 2>&1
    done
}

before=$(git rev-parse -q --verify refs/stash 2>/dev/null || true)

git stash push --include-untracked \
  -m "auto-backup [$worktree] before $LABEL $(date +%Y%m%d-%H%M%S)" >/dev/null 2>&1

after=$(git rev-parse -q --verify refs/stash 2>/dev/null || true)

# `git stash push` exits 0 on a clean tree without creating anything, so the
# exit status cannot tell "backed up" from "nothing to back up". Comparing
# refs/stash can. Getting this wrong is not a missing backup but active damage:
# `git stash apply` would then restore whatever unrelated entry happens to sit
# on top of the stack into a clean tree, leaving conflict markers and an
# unmerged index behind for a command that was only meant to be a no-op.
if [ "$after" = "$before" ]; then
  exit 0
fi

restore_failed=0
if ! git stash apply --index --quiet 2>/dev/null; then
  # A failing --index means the index state could not be replayed, not that the
  # file contents are lost. Restoring the tree and giving up only the
  # staged/unstaged split beats blocking a command the agent asked for.
  if git stash apply --quiet 2>/dev/null; then
    printf '[auto-backup] index 복원 실패 — 워킹트리는 되돌렸고 staged/unstaged 구분만 잃었다.\n' >&2
  else
    restore_failed=1
  fi
fi

if [ "$restore_failed" = 1 ]; then
  printf '[auto-backup] 백업은 만들었지만 워킹트리 복원에 실패했다. %s 는 실행하지 않았다.\n' "$LABEL" >&2
  printf '[auto-backup] 변경 내용은 stash 에만 있다: %s\n' "$(git stash list | head -1)" >&2
  printf '[auto-backup] 워킹트리를 확인해 정리한 뒤 재실행하면 원래 명령이 실행된다.\n' >&2
  exit 1
fi

# Announced, never silent. A misparsed `cd` chain can land this backup in a
# different repository than the one the original command targets, and this line
# is what makes that visible instead of leaving a stray stash to be found later.
printf '[auto-backup] %s 백업 생성 (복구: git stash apply %s)\n' \
  "$worktree" "$(git stash list --format='%gd' | head -1)" >&2

prune_old_backups

exit 0
