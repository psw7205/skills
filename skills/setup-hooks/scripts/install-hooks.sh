#!/usr/bin/env bash
set -euo pipefail
# guard-untracked 훅을 ~/.claude/settings.json에 등록하거나 제거한다.
# Usage: install-hooks.sh [--remove]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD_SCRIPT="${SCRIPT_DIR}/guard-untracked.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

# settings.json 읽기 (없으면 빈 객체)
if [ -f "$SETTINGS_FILE" ]; then
  settings=$(cat "$SETTINGS_FILE")
  if ! echo "$settings" | jq empty 2>/dev/null; then
    echo "error: $SETTINGS_FILE 이 유효한 JSON이 아닙니다. 수동으로 확인하세요." >&2
    exit 1
  fi
else
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  settings='{}'
fi

# 이미 설치 여부 확인
is_installed() {
  echo "$settings" | jq -e '.PreToolUse[]?.hooks[]? | select(.command | contains("guard-untracked"))' > /dev/null 2>&1
}

# --- 제거 모드 ---
if [ "${1:-}" = "--remove" ]; then
  if ! is_installed; then
    echo "guard-untracked hook이 설치되어 있지 않습니다."
    exit 0
  fi
  echo "$settings" | jq '
    .PreToolUse = [.PreToolUse[]? | select(.hooks[]?.command | contains("guard-untracked") | not)]
    | if .PreToolUse == [] then del(.PreToolUse) else . end
  ' > "$SETTINGS_FILE"
  echo "guard-untracked hook 제거 완료. Claude Code를 재시작하세요."
  exit 0
fi

# --- 설치 모드 ---
if is_installed; then
  echo "guard-untracked hook이 이미 설치되어 있습니다."
  exit 0
fi

if [ ! -f "$GUARD_SCRIPT" ]; then
  echo "error: guard-untracked.sh를 찾을 수 없습니다: $GUARD_SCRIPT" >&2
  exit 1
fi

hook_entry=$(jq -n --arg cmd "bash ${GUARD_SCRIPT}" '{
  "matcher": "Bash",
  "hooks": [{
    "type": "command",
    "command": $cmd,
    "statusMessage": "Guarding untracked files..."
  }]
}')

echo "$settings" | jq --argjson hook "$hook_entry" '
  .PreToolUse = ((.PreToolUse // []) + [$hook])
' > "$SETTINGS_FILE"

echo "guard-untracked hook 설치 완료: $SETTINGS_FILE"
echo "스크립트 경로: $GUARD_SCRIPT"
echo "Claude Code를 재시작하세요."
