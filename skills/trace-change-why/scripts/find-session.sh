#!/usr/bin/env bash
# trace-change-why: Claude transcript에서 특정 파일 관련 세션과 tool/context match를 찾는다.
# Usage: find-session.sh <file-pattern> [project-dir]

set -euo pipefail

FILE_PATTERN="${1:?Usage: find-session.sh <file-pattern> [project-dir]}"
PROJECT_DIR="${2:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  BRIDGE_SCRIPT="$CLAUDE_PLUGIN_ROOT/skills/session-bridge/scripts/find-transcript.sh"
else
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  BRIDGE_SCRIPT="$REPO_ROOT/skills/session-bridge/scripts/find-transcript.sh"
fi

if [[ -f "$BRIDGE_SCRIPT" ]]; then
  exec bash "$BRIDGE_SCRIPT" grep-file "$FILE_PATTERN" "$PROJECT_DIR"
fi

CLAUDE_BASE="${CLAUDE_HOME:-$HOME/.claude}"
CLAUDE_PROJECTS_ROOT="$CLAUDE_BASE/projects"
CLAUDE_TRANSCRIPTS_ROOT="$CLAUDE_BASE/transcripts"

literal_file_matches() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  if command -v rg >/dev/null 2>&1; then
    { rg -l -F --glob '*.jsonl' "$FILE_PATTERN" "$root" 2>/dev/null || true; }
  else
    find "$root" -type f -name '*.jsonl' -print 2>/dev/null | while IFS= read -r file; do
      if grep -Fq "$FILE_PATTERN" "$file" 2>/dev/null; then
        printf '%s\n' "$file"
      fi
    done
  fi
}

literal_lines() {
  local file="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -n -F "$FILE_PATTERN" "$file" 2>/dev/null || true
  else
    grep -n -F "$FILE_PATTERN" "$file" 2>/dev/null || true
  fi
}

regex_lines() {
  local file="$1"
  local pattern="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$file" 2>/dev/null || true
  else
    grep -nE "$pattern" "$file" 2>/dev/null || true
  fi
}

truncate_lines() {
  awk 'length($0) > 600 { print substr($0, 1, 600) "..."; next } { print }'
}

encoded_dirs() {
  printf '%s\n' "$CLAUDE_PROJECTS_ROOT/$(printf '%s' "$PROJECT_DIR" | tr '/' '-')"
  printf '%s\n' "$CLAUDE_PROJECTS_ROOT/$(printf '%s' "$PROJECT_DIR" | tr '/.' '--')"
}

FILES=""
while IFS= read -r dir; do
  [[ -d "$dir" ]] || continue
  FILES+="$(literal_file_matches "$dir")"$'\n'
done <<EOF_DIRS
$(encoded_dirs | sort -u)
EOF_DIRS

FILES="$(printf '%s' "$FILES" | sed '/^[[:space:]]*$/d' | sort -u)"
if [[ -z "$FILES" ]]; then
  FILES="$(
    {
      literal_file_matches "$CLAUDE_PROJECTS_ROOT"
      literal_file_matches "$CLAUDE_TRANSCRIPTS_ROOT"
    } | sort -u
  )"
fi

if [[ -z "$FILES" ]]; then
  echo "NO_MATCH: '$FILE_PATTERN' pattern not found in Claude transcripts"
  exit 0
fi

while IFS= read -r session; do
  [[ -n "$session" ]] || continue
  echo "=== $(basename "$session") ==="
  echo "PATH: $session"
  tool_matches="$(
    regex_lines "$session" '"name":"(Edit|Write)"|"tool_name":"(Edit|Write)"|"type":"tool_use"' |
      grep -F "$FILE_PATTERN" |
      tail -5 |
      truncate_lines || true
  )"
  if [[ -n "$tool_matches" ]]; then
    echo "TOOL_MATCHES:"
    printf '%s\n' "$tool_matches"
  else
    echo "TOOL_MATCHES: none"
  fi
  context_matches="$(literal_lines "$session" | head -5 | truncate_lines || true)"
  if [[ -n "$context_matches" ]]; then
    echo "CONTEXT_MATCHES:"
    printf '%s\n' "$context_matches"
  fi
  echo ""
done <<EOF_FILES
$FILES
EOF_FILES
