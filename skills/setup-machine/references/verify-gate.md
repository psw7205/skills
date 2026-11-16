# verify-gate

`verify-gate` 컴포넌트의 판정·CLI 계약이다. 등록은 `scripts/sync.py`가 한다.

## 판정

다음 표현이 있는 줄을 미확인 줄로 본다.

- 미확인 보고: `확인하지 않았/못했`, `확인 못 했`, `아직 확인`, `미확인`, `보지 않았/못했`, `시도하지 않았`, `unverified`, `unresolved`, `did not/haven't/not yet verify·check·test·run`. 동사와 부정 사이의 보조사(`확인하지는 않았`, `확인은 못 했`, `열어 보지도 않았`)도 같은 표현으로 본다
- 사용자에게 확인 넘김: `확인해 보세요/보시면/보시고/볼 만/보면 좋`, `직접 확인하세요/하시면/하실 수 있`, `you can/may/should (want to) check·verify·confirm`, `worth checking`. 활용형 전체를 맞춰서 `직접 확인하실 필요는 없습니다` 같은 부정문은 판정하지 않는다

줄과 Markdown은 다음처럼 처리한다.

| 형식 | 처리 |
|------|------|
| ``unresolved: `명령` — blocker`` 형식의 줄 | 명령·구분자·비어 있지 않은 사유가 있으면 제외. 명시적인 미시도·연기 사유는 계속 판정 |
| `unresolved: 사용자 중단 — 항목` 형식의 줄 | 사용자가 멈춘 확인이므로 명령 없이 제외. `사용자 거부`, `user interrupted/declined/rejected/stopped`도 같다. 항목이 없으면 판정 |
| 미확인 섹션 | 제목(`#` 또는 굵은 글씨 한 줄)이 `확인하지 못한`, `확인 못 한`, `보지 않은`, `아직 안 한`, `미확인`, `남은 확인`, `unverified`, `unresolved`를 담으면 그 아래 줄은 표현과 무관하게 판정. `미확인 항목은 없습니다`처럼 없다고 말하는 제목은 섹션을 열지 않는다. `없음`(목록·번호·굵은 글씨 포함)과 근거 있는 `unresolved:` 줄은 제외. 다음 제목, 또는 목록 항목이 나온 뒤 빈 줄 다음의 목록 아닌 문단에서 섹션이 끝난다. 목록 없이 문단만 있으면 다음 제목까지 이어진다 |
| markdown heading 줄 | 제목 자체는 판정하지 않는다. `.`이나 `다`로 끝나는 굵은 글씨 줄은 제목이 아니라 문장으로 본다 |
| inline code, `"…"`, `“…”`, `‘…’` 안 | 인용으로 보고 판정 표현에서 뺀다. 훅 자체를 설명하는 응답이 판정 문구를 인용해 걸리는 일을 막는다. 두 겹 이상 backtick code span도 통째로 뺀다 |
| backtick 하나로 감싼 판정어 단독(`` `unresolved` ``, `` `미확인` ``) | 인용이 아니라 상태 라벨로 보고 판정한다. 뒤에 조사가 붙어도(`` `unresolved`로 ``) 잡는다 |
| code fence 안 | 여는 fence의 문자·길이를 기억해 중첩 예시를 건너뜀 |
| 응답 전체를 감싼 `markdown` 또는 `md` fence | 바깥 fence만 벗겨 보고를 판정. 그 안의 코드 fence는 계속 제외 |
| `미확인 항목은 없습니다.`, `No unverified items remain.` | 미확인이 없다는 독립된 줄은 제외. 뒤에 다른 미확인 표현이 붙으면 판정 |
| `확인되지 않았다` | "찾아봤는데 없었다"는 조사 결과다 |
| `확인하지 않고 …했다` | 과거 실수 설명이지 남은 미확인이 아니다 |

미확인 줄이 있으면 각 300자, 최대 10개와 지시를 돌려준다. 사용자가 중단·거부한 확인은 다시 시도하지 않고 `unresolved: 사용자 중단 — 항목`으로 남기게 한다. 나머지는 지금 도구로 확인하고, 막힌 것만 ``unresolved: `실제로 실행한 명령` — blocker``로 남기게 한다. 권한상 접근할 수 없는 확인은 근거를 blocker로 적고, 답에 필요 없는 확인은 보고에서 빼게 한다. 대기 중인 작업은 사용 가능한 도구로 기다리고, 공유 상태 변경이 필요한 확인은 그 사실을 blocker로 적게 한다.

## CLI별 계약

| 항목 | Claude Code | Codex |
|------|-------------|-------|
| 입력 | `last_assistant_message`, `stop_hook_active`, `background_tasks`, `transcript_path` | `last_assistant_message`, `stop_hook_active`, `transcript_path`; `background_tasks`는 제공되지 않음 |
| 턴 경계 | 사이드체인·meta가 아닌 사용자 메시지(`tool_result`와 중단 표시 제외) | `event_msg`의 `task_started` |
| 사용자 중단 신호 | `[Request interrupted by user` 텍스트, `The user doesn't want to proceed` 도구 결과 | `turn_aborted`의 `reason: interrupted`, `rejected by user`로 끝나는 도구 출력(`rejected by user approval settings` 제외) |
| 턴을 잇는 출력 | `hookSpecificOutput: {hookEventName: "Stop", additionalContext: "..."}` | `decision: "block", reason: "..."` |
| 설정 | `~/.claude/settings.json`의 `hooks.Stop` | `${CODEX_HOME:-$HOME/.codex}/hooks.json`의 `hooks.Stop` |

Claude Code는 정상적인 안내가 훅 에러로 표시되지 않도록 `additionalContext`를 쓴다. Codex는 `reason`으로 continuation prompt를 만들므로 `codex` 인자를 빠뜨리지 않는다. 통과 시에는 양쪽 모두 출력 없이 exit 0 한다.

통과시키는 경우:

- `stop_hook_active == true`: 정지 시도 한 번에 한 번만 되돌린다. 무한 루프 방지.
- 최근 두 턴(이번 턴과 직전 턴) 안에 사용자 중단 신호가 있음: 사용자가 멈춘 확인을 다음 턴 보고에서 다시 꺼내도 재시도를 시키지 않는다.
- Claude Code에서 `background_tasks`가 비어 있지 않음: 백그라운드 작업 완료로 다시 깨어날 수 있으므로 대기 중 보고는 통과.
- `jq` 부재, 잘못된 JSON, `last_assistant_message` 없음: 조용히 exit 0.

`transcript_path`가 없거나 읽을 수 없거나 깨져 있으면 중단이 없던 것으로 보고 평소대로 판정한다.

## Gotchas

- 설치·제거 검증은 새 세션에서 한다. 현재 세션이 자동으로 갱신됐다고 가정하지 않는다.
- `unresolved` 검사는 보고 형식과 명시적인 미시도 표현만 확인한다. 명령이 실제로 실행됐는지, 적힌 blocker가 사실인지는 보장하지 않는다.
- 응답 전체를 감싼 Markdown은 보고로 간주한다. 응답 전체가 복사할 예시인 경우에도 한 번 걸릴 수 있다.
- 판정은 표현 기반이다. 따옴표 없이 미확인 표현을 그대로 옮겨 쓰거나 판정어를 backtick 하나로 감싸 언급한 응답은 한 번 걸린다. 판정어 자체를 설명할 때는 따옴표나 두 겹 backtick으로 인용한다. 비용은 한 턴 추가이고, 두 번째 정지는 `stop_hook_active`로 통과한다.
- 반대로 판정 표현도 미확인 섹션도 없이 확인을 건너뛴 응답은 잡지 못한다. `확인할 수 있습니다`, `확인해 주세요`는 확인 결과 서술이나 결정 요청과 구분할 수 없어 일부러 판정에서 뺐다.
- Claude Code는 무관한 백그라운드 작업이 돌고 있어도 통과한다. Codex에서는 같은 입력 필드가 없으므로 이 예외를 적용하지 않는다.
- 판정은 jq(Oniguruma) 정규식으로 한다. `grep -E`로 옮기면 C locale에서 한글 뒤 수량자가 마지막 byte에만 걸려 조용히 빗나간다.
- 중단 감지는 transcript 마지막 2000줄만 읽는다. 직전 턴의 중단 뒤 이번 턴이 그보다 길면 놓치고 평소대로 한 번 걸린다. 이때는 `unresolved: 사용자 중단 — 항목` 형식이 통과 경로다.
- 사용자가 중단한 직후 두 턴은 무관한 미확인 보고도 판정하지 않는다. 사용자가 방향을 다시 잡는 구간이라 재시도 압박을 거는 비용이 더 크다고 본 선택이다.
- Claude Code는 stop 훅 연속 continuation을 8회로 제한한다(`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`). 이 훅은 정지 한 번에 한 번만 이어가므로 cap에 닿지 않는다.
