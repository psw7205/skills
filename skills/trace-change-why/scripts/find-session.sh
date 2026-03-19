#!/usr/bin/env bash
# trace-change-why: 세션 트랜스크립트에서 특정 파일의 Edit/Write 호출을 찾는다.
# Usage: find-session.sh <file-pattern> [project-dir]
#   file-pattern: 검색할 파일명 또는 경로 일부 (예: "auth.ts", "src/utils")
#   project-dir:  프로젝트 경로 (기본값: $PWD)
#
# 출력: 매칭된 세션 파일과 Edit/Write 호출 라인 번호

set -euo pipefail

FILE_PATTERN="${1:?Usage: find-session.sh <file-pattern> [project-dir]}"
PROJECT_DIR="${2:-$PWD}"

# 프로젝트 경로 → 세션 디렉토리 변환 (/ → -)
SESSION_DIR="$HOME/.claude/projects/$(echo "$PROJECT_DIR" | tr '/' '-' | cut -c2-)"

if [[ ! -d "$SESSION_DIR" ]]; then
  echo "ERROR: 세션 디렉토리 없음: $SESSION_DIR" >&2
  exit 1
fi

# jsonl 파일이 없을 때 glob이 리터럴로 전달되는 것을 방지
shopt -s nullglob

# Step 1: 파일 패턴으로 후보 세션 찾기 (최신순)
jsonl_files=("$SESSION_DIR"/*.jsonl)
if [[ ${#jsonl_files[@]} -eq 0 ]]; then
  echo "NO_MATCH: 세션 파일 없음 ($SESSION_DIR)"
  exit 0
fi
SESSIONS=$(grep -l "$FILE_PATTERN" "${jsonl_files[@]}" 2>/dev/null | head -10 || true)

if [[ -z "$SESSIONS" ]]; then
  echo "NO_MATCH: '$FILE_PATTERN' 패턴이 포함된 세션 없음"
  exit 0
fi

# Step 2: 각 세션에서 Edit/Write 호출 위치 찾기
for session in $SESSIONS; do
  basename_session=$(basename "$session")
  echo "=== $basename_session ==="

  # Edit/Write 호출 중 파일 패턴 매칭
  if command -v rg &>/dev/null; then
    rg -n "\"name\":\"(Edit|Write)\"" "$session" | grep "$FILE_PATTERN" | tail -5 || true
  else
    grep -n '"name":"Edit"\|"name":"Write"' "$session" | grep "$FILE_PATTERN" | tail -5 || true
  fi

  echo ""
done
