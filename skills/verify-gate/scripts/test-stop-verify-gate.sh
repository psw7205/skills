#!/usr/bin/env bash
# stop-verify-gate.sh 계약 테스트. 실행: bash test-stop-verify-gate.sh
set -euo pipefail
hook="$(cd "$(dirname "$0")" && pwd)/stop-verify-gate.sh"
fail=0
agent="${1:-claude}"

run() {
  jq -nc --arg msg "$1" --argjson active "${2:-false}" --argjson bg "${3:-[]}" --arg agent "$agent" '
    {session_id:"test-session", cwd:"/workspace", transcript_path:null, permission_mode:"default",
     hook_event_name:"Stop", stop_hook_active:$active, last_assistant_message:$msg}
    + if $agent == "codex" then {turn_id:"test-turn"} else {background_tasks:$bg} end
  ' | bash "$hook" "$agent"
}

expect_block() {
  out=$(run "$2" "${3:-false}" "${4:-[]}")
  if jq -e --arg agent "$agent" '
    if $agent == "codex" then
      .decision == "block" and (.reason | startswith("verify-gate:"))
    else
      .hookSpecificOutput.hookEventName == "Stop"
      and (.hookSpecificOutput.additionalContext | startswith("verify-gate:"))
    end
  ' <<<"$out" >/dev/null 2>&1; then
    echo "ok   block: $1"
  else
    echo "FAIL block: $1 -> '$out'"; fail=1
  fi
}

expect_pass() {
  out=$(run "$2" "${3:-false}" "${4:-[]}")
  if [ -z "$out" ]; then echo "ok   pass:  $1"; else echo "FAIL pass:  $1 -> '$out'"; fail=1; fi
}

expect_block "시도 없는 미확인" "다만 모란이 그 서버를 실제로 쓰고 있는지는 제가 직접 확인하지 못했습니다."
expect_block "아직 확인" "지금 Traefik에 지표 엔드포인트가 켜져 있는지는 아직 확인하지 않았습니다."
expect_block "실행해 보지 않음" "- 미확인으로 남은 것: Tempo 3.1.1이 기동하는지는 아무도 실행해 보지 않았다."
expect_block "근거 없는 unresolved" "- **unresolved — 버킷 단위 권한 축소:** 콘솔에서 확인해야 합니다."
expect_block "blocker 없는 unresolved" 'unresolved: `curl https://example.com/health`'
expect_block "시도하지 않은 unresolved" 'unresolved: `curl https://example.com/health` — 아직 확인하지 않았습니다.'
expect_block "연기만 하는 unresolved" 'unresolved: `curl https://example.com/health` — 나중에 확인하겠습니다.'
expect_block "무관한 inline code는 명령 근거가 아님" '아직 확인하지 않았습니다. `API` 상태는 unresolved: 나중에 확인하겠습니다.'
expect_block "영문" "I did not verify the deployment."
expect_block "섹션 아래 항목" $'## 확인하지 못한 것\n- 브라우저에서는 확인하지 않았습니다.'
expect_block "Markdown으로 감싼 완료 보고" $'```markdown\n변경을 마쳤습니다.\n서버 상태는 확인하지 않았습니다.\n```'
expect_block "예외 줄 뒤의 별도 미확인" $'unresolved: `gh auth status` — 로그인 거부\n브라우저에서는 확인하지 않았습니다.'
expect_block "정상 요약 뒤의 별도 미확인" $'미확인 항목은 없습니다.\n서버 상태는 확인하지 않았습니다.'

expect_pass "명령과 blocker가 있는 unresolved" 'unresolved: `gh auth status` — 세션이 만료돼 로그인이 거부됨'
expect_pass "승인 대기로 실패한 unresolved" 'unresolved: `gh auth status` — 아직 로그인 승인이 없어 인증이 거부됨'
expect_pass "확인되지 않음은 조사 결과" "앱이나 매니페스트 쪽 문제는 확인되지 않았습니다."
expect_pass "heading만" $'## 확인하지 못한 것\n없음'
expect_pass "code fence 안 인용" $'예시:\n```\n확인하지 않았습니다\n```'
expect_pass "중첩 fence 안 인용" $'예시:\n````markdown\n```text\n확인하지 않았습니다.\n```\n````'
expect_pass "다른 fence 문자는 닫지 않음" $'예시:\n~~~text\n```\n확인하지 않았습니다.\n~~~'
expect_pass "Markdown 보고 속 코드 예시" $'```markdown\n테스트 통과.\n~~~text\n확인하지 않았습니다.\n~~~\n```'
expect_pass "평범한 완료 보고" "테스트 12개가 통과했습니다."
expect_pass "남은 미확인 없음" "미확인 항목은 없습니다."
expect_pass "영문 미확인 없음" "No unverified items remain."
expect_pass "사용자에게 묻는 확인 필요" "확인이 필요한 쪽은 둘 중 하나입니다. 어느 쪽인지 알려 주세요."
expect_pass "과거 실수 설명" "제가 그걸 확인하지 않고 로컬 설정부터 바꾸는 바람에 잠시 실패했습니다."
expect_pass "stop_hook_active" "확인하지 못했습니다." true
if [ "$agent" = "claude" ]; then
  expect_pass "background task 대기 중" "결과는 아직 확인하지 않았습니다." false '[{"id":"t1","type":"shell","status":"running"}]'
fi

out=$(printf 'not json' | bash "$hook" "$agent"); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then echo "ok   pass:  invalid JSON"; else echo "FAIL pass:  invalid JSON rc=$rc"; fail=1; fi

out=$(printf '{"hook_event_name":"Stop"}' | bash "$hook" "$agent")
if [ -z "$out" ]; then echo "ok   pass:  last_assistant_message 없음"; else echo "FAIL pass:  last_assistant_message 없음"; fail=1; fi

exit $fail
