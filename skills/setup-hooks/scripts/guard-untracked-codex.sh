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
  printf 'Blocked command "%s". Codex hooks do not rewrite shell commands here. If this command is intentional, first run: git stash push --include-untracked -m "manual backup before %s"; then inspect git stash list and rerun the original command.' "$label" "$label"
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

if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+checkout[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)'; then
  deny "git checkout ." "$(backup_reason "git checkout .")"
fi

if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+reset[[:space:]]+--hard\b'; then
  deny "git reset --hard" "$(backup_reason "git reset --hard")"
fi

if printf '%s' "$CMD" | grep -qE '\bgit[[:space:]]+restore[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)'; then
  deny "git restore ." "$(backup_reason "git restore .")"
fi

exit 0
