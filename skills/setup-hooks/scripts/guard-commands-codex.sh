#!/usr/bin/env bash
set -euo pipefail

# PreToolUse guard for Codex.
#
# Codex does not honour command rewrite via updatedInput, and running `git stash`
# from the hook itself would leave a stray stash behind whenever the original
# command is then cancelled. So this guard only blocks, and tells the agent the
# exact backup command to run before retrying.

# stdin is drained first: bailing out before reading it makes the caller's
# write fail with EPIPE on every single shell invocation.
INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[ -f "$SCRIPT_DIR/guard-rules.sh" ] || exit 0
# shellcheck source=guard-rules.sh
. "$SCRIPT_DIR/guard-rules.sh"

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.cmd // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

case "$TOOL_NAME" in
  ""|"Bash"|"shell"|"shell_command"|"local_shell"|"exec_command") ;;
  *) exit 0 ;;
esac

deny() {
  jq -n --arg reason "$1" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
  exit 0
}

backup_reason() {
  printf 'Blocked "%s". Codex hooks do not rewrite shell commands here. If this command is intentional, first run: git stash push --include-untracked -m "manual backup before %s" && git stash apply --index; then verify git stash list and rerun the original command.' "$1" "$1"
}

guard_classify "$CMD"
[ -n "$GUARD_RULE" ] || exit 0

case "$GUARD_RULE" in
  force-push)
    deny "Blocked git push --force. Remote history destruction is not recoverable. Use git push --force-with-lease only when you have verified it is safe."
    ;;
  rg-flag-cluster)
    deny "Blocked an rg -r<flags> cluster. In ripgrep -r is --replace and consumes what follows as its value, so rg -rn foo . rewrites every match to the literal \"n\" and still exits 0 — the mistake reads as a successful search returning garbage. Drop the -r and rerun (rg -n foo .). rg recurses by default; there is no recursive flag."
    ;;
  rg-replace)
    deny "Blocked rg -r/--replace. ripgrep never modifies files — --replace only rewrites the printed output — and -r is not a recursive flag (rg recurses by default), so rg -r 'foo' src/ silently searches for the pattern src/ instead. To search, drop -r. To edit files, use sed -i or an editor tool. To extract capture groups, pass -o as well (rg -o -r '\$1' ...), which is allowed."
    ;;
  *)
    deny "$(backup_reason "$GUARD_LABEL")"
    ;;
esac
