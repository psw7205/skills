#!/usr/bin/env bash
# stop-verify-gate.sh 계약 테스트. 실행: bash test-stop-verify-gate.sh
set -euo pipefail
hook="$(cd "$(dirname "$0")" && pwd)/stop-verify-gate.sh"
fail=0
agent="${1:-claude}"

fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT

run() {
  jq -nc --arg msg "$1" --argjson active "${2:-false}" --argjson bg "${3:-[]}" --arg agent "$agent" \
    --arg transcript "${4:-}" '
    {session_id:"test-session", cwd:"/workspace",
     transcript_path:(if $transcript == "" then null else $transcript end), permission_mode:"default",
     hook_event_name:"Stop", stop_hook_active:$active, last_assistant_message:$msg}
    + if $agent == "codex" then {turn_id:"test-turn"} else {background_tasks:$bg} end
  ' | bash "$hook" "$agent"
}

expect_block() {
  out=$(run "$2" "${3:-false}" "${4:-[]}" "${5:-}")
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

expect_flag() {
  out=$(run "$2")
  if jq -e --arg agent "$agent" --arg needle "$3" '
    (if $agent == "codex" then .reason else .hookSpecificOutput.additionalContext end)
    | split("\n") | map(select(startswith("- "))) | any(contains($needle))
  ' <<<"$out" >/dev/null 2>&1; then
    echo "ok   flag:  $1"
  else
    echo "FAIL flag:  $1 -> '$out'"; fail=1
  fi
}

expect_pass() {
  out=$(run "$2" "${3:-false}" "${4:-[]}" "${5:-}")
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
expect_block "미확인 섹션 아래 돌려 말한 항목" $'## 확인하지 못한 것\n\n- **GitHub Actions secrets:** org secrets 조회가 403으로 막혔습니다.\n- 이번 범위 밖이라 넘어갔습니다.'
expect_block "굵은 글씨 미확인 섹션" $'**남은 확인**\n- 빌드 Mac의 키 파일 존재 여부'
expect_block "섹션 제목 뒤 빈 줄과 문단" $'## 미확인\n\norg secrets 조회가 403으로 막혔습니다.'
expect_block "굵은 문장은 제목이 아님" '**서버 상태는 확인하지 않았습니다.**'
expect_block "동사 없는 보지 않음" "Bitbucket 레포는 보지 않았습니다."
expect_block "사용자에게 확인 넘김" "빌드 Mac에 AuthKey 파일이 있는지도 확인해 볼 만합니다."
expect_block "확인해 보시고" "시뮬레이터에서 확인해 보시고 괜찮으면 다음으로 진행할까요?"
expect_block "직접 확인 요청" "팀 키 목록에서 직접 확인하실 수 있습니다."
expect_block "영문 확인 넘김" "You may want to verify the key on the build Mac."
expect_block "인용 밖의 미확인" '"A" 설정은 확인하지 못했습니다.'
expect_block "backtick 라벨 unresolved" 'Cloudflare SSL 모드는 서버에서 확인할 수 없어 `unresolved` 상태예요.'
expect_block "조사가 붙은 backtick 라벨" '핀치를 넣을 수단이 없어 0006 iOS 확인은 `unresolved`로 남게 됩니다.'
expect_block "backtick 라벨 미확인" '- **증상이 난 실기기의 iOS 버전:** `미확인`. 기기 정보가 없습니다.'
expect_block "보지 않은 활용형" "Ubuntu 부분은 아직 실제로 돌려 보지 않은 내용입니다."
expect_block "보지 않은 것 섹션" $'**실행해 보지 않은 것**\n- iOS 실기기 화면'
expect_block "아직 안 한 것 섹션" $'**아직 안 한 것**\n- Android 캡처'
expect_block "조사가 낀 미확인" "manifest에서 직접 확인하지는 않았습니다."
expect_block "조사가 낀 실행 안 함" "브라우저로 열어 보지는 않았습니다."
expect_block "따옴표 밖 미확인" '"로그인" 화면은 확인하지 않았습니다.'
expect_block "inline code 밖 미확인" '`deploy-prod.yml` 결과는 아직 확인하지 못했습니다.'

expect_pass "명령과 blocker가 있는 unresolved" 'unresolved: `gh auth status` — 세션이 만료돼 로그인이 거부됨'
expect_pass "승인 대기로 실패한 unresolved" 'unresolved: `gh auth status` — 아직 로그인 승인이 없어 인증이 거부됨'
expect_pass "확인되지 않음은 조사 결과" "앱이나 매니페스트 쪽 문제는 확인되지 않았습니다."
expect_pass "heading만" $'## 확인하지 못한 것\n없음'
expect_pass "code fence 안 인용" $'예시:\n```\n확인하지 않았습니다\n```'
expect_pass "중첩 fence 안 인용" $'예시:\n````markdown\n```text\n확인하지 않았습니다.\n```\n````'
expect_pass "다른 fence 문자는 닫지 않음" $'예시:\n~~~text\n```\n확인하지 않았습니다.\n~~~'
expect_pass "Markdown 보고 속 코드 예시" $'```markdown\n테스트 통과.\n~~~text\n확인하지 않았습니다.\n~~~\n```'
expect_pass "큰따옴표 안 인용" '"확인하지는 않았습니다"는 통과했고 "확인하지 않았습니다"는 차단됐습니다.'
expect_pass "둥근 따옴표 안 인용" '“확인하지 않았습니다”라는 문장만 걸립니다.'
expect_pass "inline code 안 인용" '`확인하지 않았습니다`가 패턴에 걸립니다.'
expect_pass "평범한 완료 보고" "테스트 12개가 통과했습니다."
expect_pass "남은 미확인 없음" "미확인 항목은 없습니다."
expect_pass "영문 미확인 없음" "No unverified items remain."
expect_pass "사용자에게 묻는 확인 필요" "확인이 필요한 쪽은 둘 중 하나입니다. 어느 쪽인지 알려 주세요."
expect_pass "과거 실수 설명" "제가 그걸 확인하지 않고 로컬 설정부터 바꾸는 바람에 잠시 실패했습니다."
expect_flag "code span 사이의 미확인" '`a``b` 상태는 확인하지 못했습니다. `c``d`는 완료했습니다.' "확인하지 못했습니다"
expect_flag "목록 없는 섹션의 빈 줄 뒤 문단" $'## 미확인\nunresolved: `gh auth status` — 로그인 거부\n\n빌드 Mac 키 파일 존재 여부' "빌드 Mac 키 파일"
expect_flag "여러 항목 중 돌려 말한 항목" $'## 확인하지 못한 것\n- 브라우저에서는 확인하지 않았습니다.\n- org secrets 조회가 403으로 막혔습니다.' "403으로 막혔습니다"

expect_pass "목록형 없음" $'## 확인하지 못한 것\n- 없음'
expect_pass "번호 목록 없음" $'## 미확인\n1. 없음'
expect_pass "굵은 글씨 없음" $'## 미확인\n- **없음**'
expect_pass "미확인 없음 제목" $'## 미확인 항목은 없습니다\n- 테스트 12개 통과'
expect_pass "직접 확인 불필요" "직접 확인하실 필요는 없습니다. 제가 이미 확인했습니다."
expect_pass "확인해 볼 필요 없음" "확인해 보실 필요는 없습니다."
expect_pass "섹션 안 근거 있는 blocker" $'## 미확인\n- unresolved: `gh api orgs/x/actions/secrets` — admin:org scope 없음(403)'
expect_pass "목록 뒤 문단에서 섹션 종료" $'## 확인하지 못한 것\n- unresolved: `gh auth status` — 세션 만료로 거부됨\n\n나머지는 모두 통과했습니다.'
expect_pass "다음 제목에서 섹션 종료" $'## 미확인\n없음\n## 변경\n- 배포했습니다.'
expect_pass "판정 문구를 따옴표로 인용" '판정식은 "확인하지 못했습니다"나 “확인해 볼 만합니다” 같은 표현을 잡습니다.'
expect_pass "판정 문구를 inline code로 인용" '`확인하지 못했습니다` 한 줄만 넣으면 바로 막힙니다.'
expect_pass "두 겹 backtick 안의 형식 인용" '훅은 ``unresolved: `명령` — blocker`` 형식만 통과시킵니다.'
expect_pass "두 겹 backtick 안의 라벨 인용" '응답이 `` `unresolved` ``를 라벨처럼 씁니다.'
expect_pass "판정어가 섞인 inline code" '`미확인 제목` 같은 명사 표현이 걸렸습니다.'
expect_pass "보지 않고는 과거 서술" "로그를 보지 않고 재시작부터 했던 것이 실수였습니다."
expect_pass "확인 결과 서술" "로그에서 200 응답을 확인할 수 있습니다."
expect_pass "직접 확인한 결과" "제가 직접 확인해 보니 키는 만료 상태였습니다."
expect_pass "stop_hook_active" "확인하지 못했습니다." true
expect_pass "사용자 중단 blocker" '- unresolved: 사용자 중단 — App Store Connect 계약 표 확인'
expect_pass "영문 사용자 중단 blocker" 'unresolved: user interrupted — contract table check'
expect_block "항목 없는 사용자 중단" 'unresolved: 사용자 중단'

# transcript 이벤트: prompt(턴 시작) interrupt reject tool, decoy-a·decoy-b는 중단으로 오인하기 쉬운 비중단 신호
transcript() {
  local file="$fixtures/$1.jsonl"; shift
  : >"$file"
  for event in "$@"; do
    case "$agent:$event" in
      claude:prompt) jq -nc '{type:"user", message:{role:"user", content:"질문"}}' ;;
      claude:interrupt) jq -nc '{type:"user", message:{role:"user", content:[{type:"text", text:"[Request interrupted by user]"}]}}' ;;
      claude:reject) jq -nc '{type:"user", message:{role:"user", content:[{type:"tool_result", tool_use_id:"t1", is_error:true,
        content:"The user doesn'"'"'t want to proceed with this tool use. The tool use was rejected."}]}}' ;;
      claude:tool) jq -nc '{type:"user", message:{role:"user", content:[{type:"tool_result", tool_use_id:"t2", content:"ok"}]}}' ;;
      claude:decoy-a) jq -nc '{type:"user", isSidechain:true, message:{role:"user", content:[{type:"text", text:"[Request interrupted by user]"}]}}' ;;
      claude:decoy-b) jq -nc '{type:"user", message:{role:"user", content:[{type:"tool_result", tool_use_id:"t3", content:"ok"}]}}' ;;
      codex:prompt) jq -nc '{type:"event_msg", payload:{type:"task_started"}}' ;;
      codex:interrupt) jq -nc '{type:"event_msg", payload:{type:"turn_aborted", reason:"interrupted"}}' ;;
      codex:reject) jq -nc '{type:"response_item", payload:{type:"function_call_output", call_id:"c1", output:"exec command rejected by user"}}' ;;
      codex:tool) jq -nc '{type:"response_item", payload:{type:"function_call_output", call_id:"c2", output:"ok"}}' ;;
      codex:decoy-a) jq -nc '{type:"response_item", payload:{type:"function_call_output", call_id:"c3", output:"writing outside of the project; rejected by user approval settings"}}' ;;
      codex:decoy-b) jq -nc '{type:"event_msg", payload:{type:"turn_aborted", reason:"replaced"}}' ;;
    esac >>"$file"
  done
  printf '%s' "$file"
}

claim="App Store Connect 계약 표는 확인하지 못했습니다."
expect_pass "이번 턴 중단 뒤" "$claim" false '[]' "$(transcript current prompt tool interrupt prompt)"
expect_pass "직전 턴 중단 뒤 새 질문" "$claim" false '[]' "$(transcript previous prompt prompt tool interrupt prompt tool)"
expect_pass "직전 턴 도구 거부 뒤" "$claim" false '[]' "$(transcript rejected prompt reject prompt tool)"
expect_block "두 턴 전 중단" "$claim" false '[]' "$(transcript old prompt interrupt prompt tool prompt tool)"
expect_block "중단 없는 transcript" "$claim" false '[]' "$(transcript clean prompt tool prompt tool)"
expect_block "중단이 아닌 신호" "$claim" false '[]' "$(transcript other prompt decoy-a decoy-b prompt tool)"
expect_block "없는 transcript 경로" "$claim" false '[]' "$fixtures/missing.jsonl"
printf 'not json\n' >"$fixtures/broken.jsonl"
expect_block "깨진 transcript" "$claim" false '[]' "$fixtures/broken.jsonl"

if [ "$agent" = "claude" ]; then
  expect_pass "background task 대기 중" "결과는 아직 확인하지 않았습니다." false '[{"id":"t1","type":"shell","status":"running"}]'
fi

out=$(printf 'not json' | bash "$hook" "$agent"); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then echo "ok   pass:  invalid JSON"; else echo "FAIL pass:  invalid JSON rc=$rc"; fail=1; fi

out=$(printf '{"hook_event_name":"Stop"}' | bash "$hook" "$agent")
if [ -z "$out" ]; then echo "ok   pass:  last_assistant_message 없음"; else echo "FAIL pass:  last_assistant_message 없음"; fail=1; fi

exit $fail
