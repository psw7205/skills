#!/usr/bin/env bash
# Claude Code Stop hook. transcript에서 마지막 user prompt와 assistant 최종 텍스트를
# 뽑아 세션당 1개 markdown 파일에 append한다. 어떤 실패 경로에서도 exit 0 —
# 로깅 실패가 세션을 방해하는 것이 기록 누락보다 나쁘다.

input=$(cat) || exit 0
command -v jq >/dev/null 2>&1 || exit 0

session_id=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null) || exit 0
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
[ -n "$session_id" ] && [ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# tool_result만 담긴 user 라인, sidechain(subagent), meta, compaction 요약은 제외.
# user prompt는 4000자에서 자른다 — 붙여넣은 대용량 텍스트로 로그가 비대해지는 것 방지.
exchange=$(jq -cs '
  def text_of:
    if (.message.content | type) == "string" then .message.content
    else [.message.content[]? | select(.type == "text") | .text] | join("\n\n")
    end;
  ([ .[]
     | select(.type == "user" and .isSidechain != true and .isMeta != true and .isCompactSummary != true)
     | select(text_of != "")
   ] | last) as $u
  | ([ .[]
      | select(.type == "assistant" and .isSidechain != true)
      | select([.message.content[]? | select(.type == "text")] | length > 0)
    ] | last) as $a
  | if $a == null then empty
    else {
      id: ($a.uuid // ""),
      user: (if $u == null then ""
             else ($u | text_of
                   | if length > 4000 then .[0:4000] + "\n… (truncated)" else . end)
             end),
      assistant: ($a | text_of)
    }
    end
' "$transcript" 2>/dev/null) || exit 0
[ -n "$exchange" ] || exit 0

entry_id=$(jq -r '.id // empty' <<<"$exchange" 2>/dev/null)
[ -n "$entry_id" ] || exit 0

# 에이전트 중립 루트. Codex 등 다른 에이전트 훅도 같은 루트에 쓴다.
log_root="${AGENT_SESSION_LOG_DIR:-$HOME/.agents/session-logs}"
project=$(basename "$(cd "${cwd:-.}" 2>/dev/null && pwd -P || echo "${cwd:-unknown-project}")")
dir="$log_root/$project"
sid8=${session_id:0:8}

# 자정 넘김/resume 대비: 파일명은 생성일 기준이므로 sid로 기존 파일을 먼저 찾는다.
file=$(ls "$dir/"*"-$sid8.md" 2>/dev/null | head -n 1)
if [ -z "$file" ]; then
  mkdir -p "$dir" 2>/dev/null || exit 0
  file="$dir/$(date +%Y-%m-%d)-$sid8.md"
  {
    echo "# $project — $(date +%Y-%m-%d) ($sid8)"
    echo
    echo "- agent: claude-code"
    echo "- session_id: $session_id"
    echo "- cwd: $cwd"
  } >"$file" 2>/dev/null || exit 0
fi

# Stop 재발화(다른 stop hook의 block 등)로 같은 교환이 두 번 오면 skip.
grep -qF "<!-- stop:$entry_id -->" "$file" 2>/dev/null && exit 0

{
  echo
  echo "## $(date +%H:%M)"
  echo
  jq -r '.user' <<<"$exchange" | sed 's/^/> /'
  echo
  jq -r '.assistant' <<<"$exchange"
  echo
  echo "<!-- stop:$entry_id -->"
} >>"$file" 2>/dev/null

exit 0
