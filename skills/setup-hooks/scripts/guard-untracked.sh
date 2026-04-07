#!/usr/bin/env bash
set -euo pipefail
# Auto-stash before dangerous git commands to preserve untracked files.
# Force push is denied outright — remote history destruction is not recoverable.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

STAMP=$(date +%Y%m%d-%H%M%S)

rewrite() {
  local label="$1"
  local new_cmd="git stash push --include-untracked -m \"auto-backup before ${label} ${STAMP}\" 2>/dev/null; ${CMD}"
  jq -n --arg msg "[guard] auto-stash 실행 후 ${label} 진행. 복구: git stash list → git stash pop" \
        --arg cmd "$new_cmd" '{
    "systemMessage": $msg,
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "updatedInput": { "command": $cmd }
    }
  }'
  exit 0
}

deny() {
  local label="$1"
  jq -n --arg msg "[guard] ${label} 차단됨. 원격 히스토리 파괴는 복구 불가. 필요하면 사용자에게 직접 실행을 요청하세요." '{
    "systemMessage": $msg,
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny"
    }
  }'
  exit 0
}

# --- deny: force push (irrecoverable) ---
# --force-with-lease / --force-if-includes 단독은 허용하되,
# --force와 동시 사용 시 --force가 우선하므로 deny.
PUSH_CHECK=$(echo "$CMD" | sed -E 's/--force-(with-lease|if-includes)//g')
echo "$PUSH_CHECK" | grep -qE '\bgit\s+push\s+.*(-f|--force)\b' && deny "git push --force"

# --- rewrite: auto-stash before destructive local commands ---
echo "$CMD" | grep -qE '\bgit\s+clean\b' && rewrite "git clean"
echo "$CMD" | grep -qE '\bgit\s+checkout\s+(--\s+)?\.(\s|$)' && rewrite "git checkout ."
echo "$CMD" | grep -qE '\bgit\s+reset\s+--hard\b' && rewrite "git reset --hard"
echo "$CMD" | grep -qE '\bgit\s+restore\s+\.(\s|$)' && rewrite "git restore ."

exit 0
