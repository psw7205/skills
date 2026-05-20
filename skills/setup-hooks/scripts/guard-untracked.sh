#!/usr/bin/env bash
set -euo pipefail
# Auto-backup via git stash before dangerous git commands.
# Strategy: stash push --include-untracked (captures unstaged + untracked),
# then stash apply --index immediately to restore working tree. Stash entry
# remains as a recovery point while the original command runs against real
# state — preserving the user's intent.
# Force push is denied outright — remote history destruction is not recoverable.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

STAMP=$(date +%Y%m%d-%H%M%S)

rewrite() {
  local label="$1"
  local cd_prefix="" git_cmd="$CMD"
  if [[ "$CMD" =~ ^(cd[[:space:]]+[^&]+&&[[:space:]]*)(.+)$ ]]; then
    cd_prefix="${BASH_REMATCH[1]}"
    git_cmd="${BASH_REMATCH[2]}"
  fi
  local backup="git stash push --include-untracked -m \"auto-backup before ${label} ${STAMP}\" 2>/dev/null && git stash apply --index --quiet 2>/dev/null"
  local new_cmd="${cd_prefix}${backup}; ${git_cmd}"
  jq -n --arg msg "[guard] auto-backup stash 생성 후 ${label} 정상 실행. 복구: git stash list → git stash apply stash@{N}" \
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

# --- rewrite: auto-backup stash before destructive local commands ---
# Note: git stash drop/clear는 의도적으로 가드하지 않음.
# 이 훅의 책임은 파괴적 명령 전 백업 stash 생성이지, stash lifecycle 관리가 아님.

# git clean: untracked 삭제
echo "$CMD" | grep -qE '\bgit\s+clean\b' && rewrite "git clean"

# git reset --hard: staged + unstaged 모두 폐기
echo "$CMD" | grep -qE '\bgit\s+reset\s+--hard\b' && rewrite "git reset --hard"

# git restore: --staged/-S 단독이면 index만 건드려 안전.
# --worktree/-W가 함께 있거나 staged 플래그가 없으면 worktree 덮어쓰기 → 가드.
if echo "$CMD" | grep -qE '\bgit\s+restore\b'; then
  has_staged=0
  has_worktree=0
  echo "$CMD" | grep -qE '(^|\s)(--staged|--cached|-S)(\s|$)' && has_staged=1
  echo "$CMD" | grep -qE '(^|\s)(--worktree|-W)(\s|$)' && has_worktree=1
  if [ "$has_staged" = "0" ] || [ "$has_worktree" = "1" ]; then
    rewrite "git restore"
  fi
fi

# git checkout: 명시적 파일 복원 형태 (--, .) 또는 force 플래그.
# DWIM 형태 `git checkout <name>`는 branch/file 모호성 때문에 가드 제외.
echo "$CMD" | grep -qE '\bgit\s+checkout\s+(--\s|\.(\s|$))' && rewrite "git checkout (paths)"
echo "$CMD" | grep -qE '\bgit\s+checkout\b.*(^|\s)(-f|--force)(\s|$)' && rewrite "git checkout --force"

exit 0
