#!/usr/bin/env bash
set -euo pipefail

# Codex PreToolUse guard for destructive git commands.
# Codex currently does not support command rewrite via updatedInput, so this
# hook blocks risky commands and tells the agent the explicit backup command.

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.cmd // empty')

[ -z "$CMD" ] && exit 0

case "$TOOL_NAME" in
  ""|"Bash"|"shell"|"shell_command"|"local_shell"|"exec_command")
    ;;
  *)
    exit 0
    ;;
esac

deny() {
  local label="$1"
  local reason="$2"
  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
  exit 0
}

backup_reason() {
  local label="$1"
  printf 'Blocked command "%s". Codex hooks do not rewrite shell commands here. If this command is intentional, first run: git stash push --include-untracked -m "manual backup before %s" && git stash apply --index; then verify git stash list and rerun the original command.' "$label" "$label"
}

# --force-with-lease and --force-if-includes are allowed unless --force is also present.
PUSH_CHECK=$(printf '%s' "$CMD" | sed -E 's/--force-(with-lease|if-includes)//g')
if printf '%s' "$PUSH_CHECK" | grep -qE '\bgit[[:space:]]+push\b.*(^|[[:space:]])(-f|--force)([[:space:]]|$)'; then
  deny "git push --force" "Blocked git push --force. Remote history destruction is not recoverable. Use git push --force-with-lease only when you have verified it is safe."
fi

if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+clean\b'; then
  if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(-n|--dry-run|-i|--interactive)([[:space:]]|$)'; then
    exit 0
  fi
  deny "git clean" "$(backup_reason "git clean")"
fi

if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+reset[[:space:]]+--hard\b'; then
  deny "git reset --hard" "$(backup_reason "git reset --hard")"
fi

# git restore: --staged/-S 단독이면 안전. --worktree/-W 동반 또는 staged 없으면 deny.
if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+restore\b'; then
  has_staged=0
  has_worktree=0
  printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(--staged|--cached|-S)([[:space:]]|$)' && has_staged=1
  printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(--worktree|-W)([[:space:]]|$)' && has_worktree=1
  if [ "$has_staged" = "0" ] || [ "$has_worktree" = "1" ]; then
    deny "git restore" "$(backup_reason "git restore")"
  fi
fi

# git checkout: 명시적 파일 복원(--, .) 또는 force 플래그
if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+checkout[[:space:]]+(--[[:space:]]|\.([[:space:]]|$))'; then
  deny "git checkout (paths)" "$(backup_reason "git checkout (paths)")"
fi
if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+checkout\b.*(^|[[:space:]])(-f|--force)([[:space:]]|$)'; then
  deny "git checkout --force" "$(backup_reason "git checkout --force")"
fi

exit 0
