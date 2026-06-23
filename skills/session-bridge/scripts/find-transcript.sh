#!/usr/bin/env bash
# session-bridge: Claude Code 또는 Codex CLI transcript 파일을 찾는다.
# Usage:
#   find-transcript.sh locate [auto|claude|claude-projects|claude-transcripts|codex] <session-id-or-fragment>
#   find-transcript.sh grep-file <file-pattern> [project-dir]
#   find-transcript.sh [auto|claude|codex] <session-id-or-fragment>  # locate 호환 호출
#   find-transcript.sh <session-id-or-fragment>                      # locate auto 호환 호출

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  find-transcript.sh locate [auto|claude|claude-projects|claude-transcripts|codex] <session-id-or-fragment>
  find-transcript.sh grep-file <file-pattern> [project-dir]
  find-transcript.sh [auto|claude|codex] <session-id-or-fragment>
  find-transcript.sh <session-id-or-fragment>
USAGE
}

CLAUDE_BASE="${CLAUDE_HOME:-$HOME/.claude}"
CLAUDE_PROJECTS_ROOT="$CLAUDE_BASE/projects"
CLAUDE_TRANSCRIPTS_ROOT="$CLAUDE_BASE/transcripts"
CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}/sessions"

COMMAND="locate"
AGENT="auto"
QUERY=""
PROJECT_DIR="${PWD}"

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi

case "$1" in
  -h|--help|help)
    usage
    exit 0
    ;;
  locate)
    COMMAND="locate"
    if [[ $# -ne 3 ]]; then
      usage
      exit 2
    fi
    AGENT="$2"
    QUERY="$3"
    ;;
  grep-file)
    COMMAND="grep-file"
    if [[ $# -lt 2 || $# -gt 3 ]]; then
      usage
      exit 2
    fi
    QUERY="$2"
    PROJECT_DIR="${3:-$PWD}"
    ;;
  auto|claude|claude-projects|claude-transcripts|codex)
    COMMAND="locate"
    if [[ $# -ne 2 ]]; then
      usage
      exit 2
    fi
    AGENT="$1"
    QUERY="$2"
    ;;
  *)
    COMMAND="locate"
    if [[ $# -ne 1 ]]; then
      usage
      exit 2
    fi
    AGENT="auto"
    QUERY="$1"
    ;;
esac

case "$AGENT" in
  auto|claude|claude-projects|claude-transcripts|codex) ;;
  *)
    echo "ERROR: agent must be auto, claude, claude-projects, claude-transcripts, or codex: $AGENT" >&2
    exit 2
    ;;
esac

if [[ -z "$QUERY" ]]; then
  echo "ERROR: query is empty" >&2
  exit 2
fi

emit_match() {
  local source="$1"
  local file="$2"
  local reason="${3:-match}"
  local bytes
  local lines
  bytes="$(wc -c < "$file" | tr -d ' ')"
  lines="$(wc -l < "$file" | tr -d ' ')"
  printf '%s\t%s\t%s bytes\t%s lines\t%s\n' "$source" "$file" "$bytes" "$lines" "$reason"
}

stat_mtime() {
  local file="$1"
  local mtime
  mtime="$(stat -f '%m' "$file" 2>/dev/null || true)"
  if [[ "$mtime" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$mtime"
    return 0
  fi
  stat -c '%Y' "$file"
}

sort_paths_by_mtime() {
  while IFS= read -r file || [[ -n "$file" ]]; do
    [[ -n "$file" && -f "$file" ]] || continue
    printf '%s\t%s\n' "$(stat_mtime "$file")" "$file"
  done | sort -rn | cut -f2-
}

find_by_name_one() {
  local source="$1"
  local root="$2"
  [[ -d "$root" ]] || return 0
  find "$root" -type f -name '*.jsonl' -name "*$QUERY*" -print 2>/dev/null |
    sort_paths_by_mtime |
    while IFS= read -r file; do
      emit_match "$source" "$file" "filename"
    done
}

find_by_content_one() {
  local source="$1"
  local root="$2"
  [[ -d "$root" ]] || return 0
  if command -v rg >/dev/null 2>&1; then
    { rg -l -F --glob '*.jsonl' "$QUERY" "$root" 2>/dev/null || true; }
  else
    find "$root" -type f -name '*.jsonl' -print 2>/dev/null | while IFS= read -r file; do
      if grep -Fq "$QUERY" "$file" 2>/dev/null; then
        printf '%s\n' "$file"
      fi
    done
  fi |
    sort_paths_by_mtime |
    while IFS= read -r file; do
      emit_match "$source" "$file" "content"
    done
}

locate_name_matches() {
  case "$AGENT" in
    auto)
      find_by_name_one "claude-projects" "$CLAUDE_PROJECTS_ROOT"
      find_by_name_one "claude-transcripts" "$CLAUDE_TRANSCRIPTS_ROOT"
      find_by_name_one "codex" "$CODEX_ROOT"
      ;;
    claude)
      find_by_name_one "claude-projects" "$CLAUDE_PROJECTS_ROOT"
      find_by_name_one "claude-transcripts" "$CLAUDE_TRANSCRIPTS_ROOT"
      ;;
    claude-projects)
      find_by_name_one "claude-projects" "$CLAUDE_PROJECTS_ROOT"
      ;;
    claude-transcripts)
      find_by_name_one "claude-transcripts" "$CLAUDE_TRANSCRIPTS_ROOT"
      ;;
    codex)
      find_by_name_one "codex" "$CODEX_ROOT"
      ;;
  esac
}

locate_content_matches() {
  case "$AGENT" in
    auto)
      find_by_content_one "claude-projects" "$CLAUDE_PROJECTS_ROOT"
      find_by_content_one "claude-transcripts" "$CLAUDE_TRANSCRIPTS_ROOT"
      find_by_content_one "codex" "$CODEX_ROOT"
      ;;
    claude)
      find_by_content_one "claude-projects" "$CLAUDE_PROJECTS_ROOT"
      find_by_content_one "claude-transcripts" "$CLAUDE_TRANSCRIPTS_ROOT"
      ;;
    claude-projects)
      find_by_content_one "claude-projects" "$CLAUDE_PROJECTS_ROOT"
      ;;
    claude-transcripts)
      find_by_content_one "claude-transcripts" "$CLAUDE_TRANSCRIPTS_ROOT"
      ;;
    codex)
      find_by_content_one "codex" "$CODEX_ROOT"
      ;;
  esac
}

literal_file_matches() {
  local root="$1"
  local pattern="$2"
  [[ -d "$root" ]] || return 0
  if command -v rg >/dev/null 2>&1; then
    { rg -l -F --glob '*.jsonl' "$pattern" "$root" 2>/dev/null || true; }
  else
    find "$root" -type f -name '*.jsonl' -print 2>/dev/null | while IFS= read -r file; do
      if grep -Fq "$pattern" "$file" 2>/dev/null; then
        printf '%s\n' "$file"
      fi
    done
  fi
}

literal_lines() {
  local file="$1"
  local pattern="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -n -F "$pattern" "$file" 2>/dev/null || true
  else
    grep -n -F "$pattern" "$file" 2>/dev/null || true
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

encoded_project_dirs() {
  local project_dir="$1"
  local raw
  local dot_normalized
  raw="$(printf '%s' "$project_dir" | tr '/' '-')"
  dot_normalized="$(printf '%s' "$project_dir" | tr '/.' '--')"
  printf '%s\n' "$CLAUDE_PROJECTS_ROOT/$raw"
  printf '%s\n' "$CLAUDE_PROJECTS_ROOT/$dot_normalized"
  if [[ -d "$project_dir" ]]; then
    local physical
    physical="$(cd "$project_dir" && pwd -P)"
    printf '%s\n' "$CLAUDE_PROJECTS_ROOT/$(printf '%s' "$physical" | tr '/' '-')"
    printf '%s\n' "$CLAUDE_PROJECTS_ROOT/$(printf '%s' "$physical" | tr '/.' '--')"
  fi
}

print_grep_file_match() {
  local source="$1"
  local file="$2"
  local reason="$3"
  local tool_matches
  local context_matches

  echo "=== $(basename "$file") ==="
  echo "SOURCE: $source"
  echo "PATH: $file"
  echo "MATCH_REASON: $reason"

  tool_matches="$(
    regex_lines "$file" '"name":"(Edit|Write)"|"tool_name":"(Edit|Write)"|"type":"tool_use"' |
      grep -F "$QUERY" |
      tail -5 |
      truncate_lines || true
  )"
  if [[ -n "$tool_matches" ]]; then
    echo "TOOL_MATCHES:"
    printf '%s\n' "$tool_matches"
  else
    echo "TOOL_MATCHES: none"
  fi

  context_matches="$(literal_lines "$file" "$QUERY" | head -5 | truncate_lines || true)"
  if [[ -n "$context_matches" ]]; then
    echo "CONTEXT_MATCHES:"
    printf '%s\n' "$context_matches"
  else
    echo "CONTEXT_MATCHES: none"
  fi
  echo ""
}

run_locate() {
  local results
  results="$(locate_name_matches | sort -u)"
  if [[ -z "$results" ]]; then
    results="$(locate_content_matches | sort -u)"
  fi
  if [[ -z "$results" ]]; then
    echo "NO_MATCH: no transcript found for '$QUERY' (agent=$AGENT)"
    exit 1
  fi
  printf '%s\n' "$results"
}

run_grep_file() {
  local files=""
  local dirs
  dirs="$(encoded_project_dirs "$PROJECT_DIR" | sed '/^[[:space:]]*$/d' | sort -u)"
  while IFS= read -r dir; do
    [[ -d "$dir" ]] || continue
    files+="$(literal_file_matches "$dir" "$QUERY")"$'\n'
  done <<EOF_DIRS
$dirs
EOF_DIRS

  files="$(printf '%s' "$files" | sed '/^[[:space:]]*$/d' | sort -u)"
  if [[ -z "$files" ]]; then
    files="$(
      {
        literal_file_matches "$CLAUDE_PROJECTS_ROOT" "$QUERY"
        literal_file_matches "$CLAUDE_TRANSCRIPTS_ROOT" "$QUERY"
      } | sort -u
    )"
  fi
  files="$(printf '%s' "$files" | sort_paths_by_mtime | head -10)"

  if [[ -z "$files" ]]; then
    echo "NO_MATCH: '$QUERY' pattern not found in Claude transcripts"
    exit 0
  fi

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    local source="claude-projects"
    local reason="project-dir-or-global-content"
    case "$file" in
      "$CLAUDE_TRANSCRIPTS_ROOT"/*)
        source="claude-transcripts"
        ;;
    esac
    print_grep_file_match "$source" "$file" "$reason"
  done <<EOF_FILES
$files
EOF_FILES
}

case "$COMMAND" in
  locate)
    run_locate
    ;;
  grep-file)
    run_grep_file
    ;;
esac
