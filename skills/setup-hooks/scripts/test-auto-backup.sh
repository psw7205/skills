#!/usr/bin/env bash
set -uo pipefail

# Contract test for auto-backup.sh. Run directly: bash test-auto-backup.sh
#
# Each case builds a throwaway repository, so nothing here touches the tree it
# runs from. Cases 1 and 4 are the ones that matter: they cover the two ways a
# backup step can cause the damage it exists to prevent — restoring an unrelated
# stash into a clean tree, and letting the destructive command run after the
# restore failed.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BACKUP="$SCRIPT_DIR/auto-backup.sh"
REAL_GIT=$(command -v git)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$name" "$expected" "$actual"
  fi
}

new_repo() {
  local dir="$TMP/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name tester
  printf 'committed\n' > "$dir/f.txt"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init
  printf '%s' "$dir"
}

# A git that fails every `stash apply` and delegates everything else, used to
# reach the restore-failed branch without depending on a real conflict.
failing_git_dir() {
  local dir="$TMP/bin-$1"
  mkdir -p "$dir"
  cat > "$dir/git" <<EOS
#!/usr/bin/env bash
if [ "\${1:-}" = "stash" ] && [ "\${2:-}" = "apply" ]; then exit 1; fi
exec "$REAL_GIT" "\$@"
EOS
  chmod +x "$dir/git"
  printf '%s' "$dir"
}

echo '--- case 1: clean tree with an unrelated stash on the stack'
# The regression that made this script necessary: `git stash push` exits 0 on a
# clean tree without stashing anything, so an unconditional `git stash apply`
# restores whatever is on top of the stack into a tree that had no changes.
repo=$(new_repo clean)
printf 'unrelated work\n' > "$repo/f.txt"
git -C "$repo" stash push --include-untracked -m "auto-backup [other] before git restore" -q
cd "$repo"
bash "$BACKUP" "git restore" >/dev/null 2>&1
rc=$?
cd - >/dev/null
check "exit 0 so the original command still runs" 0 "$rc"
check "tree left clean" "clean" "$(git -C "$repo" status --porcelain | grep -q . && echo dirty || echo clean)"
check "file untouched" "committed" "$(cat "$repo/f.txt")"
check "no backup created" 1 "$(git -C "$repo" stash list | wc -l | tr -d ' ')"

echo '--- case 2: dirty tree'
repo=$(new_repo dirty)
printf 'in progress\n' > "$repo/f.txt"
printf 'staged\n' > "$repo/g.txt"
git -C "$repo" add g.txt
cd "$repo"
bash "$BACKUP" "git reset --hard" >/dev/null 2>&1
rc=$?
cd - >/dev/null
check "exit 0" 0 "$rc"
check "backup created" 1 "$(git -C "$repo" stash list | wc -l | tr -d ' ')"
check "worktree change preserved" "in progress" "$(cat "$repo/f.txt")"
check "staged state preserved" "A  g.txt" "$(git -C "$repo" status --porcelain g.txt)"
check "label and worktree recorded" 1 \
  "$(git -C "$repo" stash list | grep -c 'auto-backup \[dirty\] before git reset --hard')"

echo '--- case 3: untracked files'
repo=$(new_repo untracked)
printf 'new file\n' > "$repo/u.txt"
cd "$repo"
bash "$BACKUP" "git clean" >/dev/null 2>&1
rc=$?
cd - >/dev/null
check "exit 0" 0 "$rc"
check "untracked file restored" "new file" "$(cat "$repo/u.txt" 2>/dev/null)"
check "untracked file captured in backup" 1 \
  "$(git -C "$repo" stash show --include-untracked --name-only 'stash@{0}' 2>/dev/null | grep -c '^u.txt$')"

echo '--- case 4: restore fails'
# Blocking here is the whole point. With `;` instead of `&&`, or with the
# failure swallowed, the destructive command runs against a tree the backup has
# already emptied and the work survives only inside the stash.
repo=$(new_repo restore-fail)
printf 'precious\n' > "$repo/f.txt"
bin=$(failing_git_dir restore-fail)
cd "$repo"
PATH="$bin:$PATH" bash "$BACKUP" "git reset --hard" >/dev/null 2>&1
rc=$?
cd - >/dev/null
check "exit 1 blocks the original command" 1 "$rc"
check "work is recoverable from the stash" "precious" \
  "$(git -C "$repo" show 'stash@{0}:f.txt' 2>/dev/null)"

echo '--- case 5: retention'
repo=$(new_repo retention)
old_ts=$(( $(date +%s) - 8 * 86400 ))
make_stash() {
  local msg="$1" ts="${2:-}"
  printf 'change %s\n' "$RANDOM" > "$repo/f.txt"
  if [ -n "$ts" ]; then
    GIT_COMMITTER_DATE="@$ts +0000" GIT_AUTHOR_DATE="@$ts +0000" \
      git -C "$repo" stash push -q -m "$msg"
  else
    git -C "$repo" stash push -q -m "$msg"
  fi
}
make_stash "auto-backup [x] before git restore old-1" "$old_ts"
make_stash "auto-backup [x] before git restore old-2" "$old_ts"
make_stash "auto-backup [x] before git restore old-3" "$old_ts"
make_stash "WIP by hand — do not expire" "$old_ts"
for i in 1 2 3 4 5 6 7 8 9; do make_stash "auto-backup [x] before git restore recent-$i"; done
check "13 entries before pruning" 13 "$(git -C "$repo" stash list | wc -l | tr -d ' ')"
printf 'live edit\n' > "$repo/f.txt"
cd "$repo"
bash "$BACKUP" "git reset --hard" >/dev/null 2>&1
cd - >/dev/null
# 14 entries existed at prune time; the three aged auto-backups past the
# ten most recent are dropped.
check "aged surplus dropped" 11 "$(git -C "$repo" stash list | wc -l | tr -d ' ')"
check "hand-made stash kept" 1 "$(git -C "$repo" stash list | grep -c 'do not expire')"
check "aged old-1 dropped" 0 "$(git -C "$repo" stash list | grep -c 'old-1')"
check "recent kept" 9 "$(git -C "$repo" stash list | grep -c 'recent-')"

echo '--- case 6: outside a repository'
mkdir -p "$TMP/bare"
cd "$TMP/bare"
bash "$BACKUP" "git clean" >/dev/null 2>&1
rc=$?
cd - >/dev/null
check "exit 0 so the command is not blocked" 0 "$rc"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
