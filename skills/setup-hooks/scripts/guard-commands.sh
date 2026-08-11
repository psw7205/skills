#!/usr/bin/env bash
set -euo pipefail

# PreToolUse guard for Claude Code.
#
# Recoverable damage is rewritten rather than blocked: `git stash push
# --include-untracked` followed immediately by `git stash apply --index` leaves
# the working tree exactly as it was, so the original command still runs against
# the user's real state while the stash entry survives as a recovery point.
# Damage a stash cannot undo — remote history, or a search whose output silently
# misrepresents the files — is denied instead.

# stdin is drained first: bailing out before reading it makes the caller's
# write fail with EPIPE on every single Bash invocation.
INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[ -f "$SCRIPT_DIR/guard-rules.sh" ] || exit 0
# shellcheck source=guard-rules.sh
. "$SCRIPT_DIR/guard-rules.sh"

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

deny() {
  jq -n --arg msg "$1" '{
    "systemMessage": $msg,
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny"
    }
  }'
  exit 0
}

rewrite() {
  local label="$1"
  local stamp cd_prefix rest backup
  stamp=$(date +%Y%m%d-%H%M%S)
  cd_prefix=""
  rest="$CMD"
  # The whole `cd a && cd b &&` chain stays in front of the backup so the stash
  # lands in the repository the original command actually targets.
  if [[ "$CMD" =~ ^((cd[[:space:]]+[^\&|\;]+\&\&[[:space:]]*)+)(.+)$ ]]; then
    cd_prefix="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[3]}"
  fi
  backup="git stash push --include-untracked -m \"auto-backup before ${label} ${stamp}\" 2>/dev/null && git stash apply --index --quiet 2>/dev/null"
  jq -n --arg msg "[guard] auto-backup stash 생성 후 ${label} 정상 실행. 복구: git stash list → git stash apply stash@{N}" \
        --arg cmd "${cd_prefix}${backup}; ${rest}" '{
    "systemMessage": $msg,
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "updatedInput": { "command": $cmd }
    }
  }'
  exit 0
}

guard_classify "$CMD"
[ -n "$GUARD_RULE" ] || exit 0

case "$GUARD_RULE" in
  force-push)
    deny "[guard] git push --force 차단됨. 원격 히스토리 파괴는 복구 불가. 필요하면 사용자에게 직접 실행을 요청하세요. 안전한 대안: git push --force-with-lease"
    ;;
  rg-flag-cluster)
    # Left to the companion rg-replace-flag-fix.py hook, which rewrites `-rn`
    # to `-n`. Denying here would preempt that repair and cost a round trip.
    exit 0
    ;;
  rg-replace)
    deny "[guard] rg -r/--replace 차단됨. rg는 파일을 수정하지 않고 출력만 치환하며, -r은 recursive가 아니라 --replace다(rg는 기본 재귀). 검색은 -r 없이, 파일 수정은 Edit 도구나 sed -i, 캡처 그룹 추출은 -o 동반(rg -o -r '\$1' ...)으로 사용."
    ;;
  *)
    rewrite "$GUARD_LABEL"
    ;;
esac
