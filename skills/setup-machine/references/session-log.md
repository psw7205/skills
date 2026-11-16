# session-log

`session-log` 컴포넌트의 기록 계약이다. 등록은 `scripts/sync.py`가 한다. `session-history`(정제된 의사결정 요약, 수동 트리거)와 보완 관계다.

## 기록 위치와 포맷

- 기본 경로: `~/.agents/session-logs/{project}/{YYYY-MM-DD}-{session_id 앞 8자}.md`
- 루트는 에이전트 중립이다. Codex 등 다른 에이전트용 세션 로그 훅을 만들 때도 같은 루트에 쓰고, 파일 헤더의 `agent:` 필드로 출처를 구분한다
- `{project}`는 훅 입력 `cwd`의 실제 디렉토리 이름 (`pwd -P` 기준)
- 환경변수 `AGENT_SESSION_LOG_DIR`로 루트 재정의 가능
- 파일 헤더에 agent, 전체 session_id, cwd를 기록하고, 엔트리는 `## HH:MM` + user prompt(blockquote) + assistant 텍스트 + `<!-- stop:UUID -->` 마커 순서

## 추출 규칙

- user: sidechain(subagent), meta, compaction 요약, tool_result 전용 라인을 제외한 마지막 실제 prompt. 4000자 초과분은 절단
- assistant: text 블록을 가진 마지막 assistant 라인의 text 블록 전체. 절단 없음
- 같은 assistant UUID가 이미 파일에 있으면 skip (Stop 재발화 대비)

## Gotchas

- `jq`가 없거나 stdin이 JSON이 아니면 조용히 exit 0 한다. 로깅 실패가 세션을 방해하는 것이 기록 누락보다 나쁘다.
- Stop은 세션 종료가 아니라 **매 응답 종료마다** 발동한다. 이 스킬은 그 특성을 이용해 crash-safe 증분 기록을 만든다. 세션 종료 1회 기록이 필요하면 `SessionEnd`가 맞지만 터미널 강제 종료 시 발동이 보장되지 않는다.
- `claude --resume`은 새 session_id를 만들 수 있다. 그 경우 새 파일로 이어지며, 파일 헤더의 cwd·날짜로 연결을 추적한다.
- 자정을 넘긴 세션은 파일명 날짜(생성일)와 엔트리 시각이 어긋날 수 있다. 파일 탐색은 session_id 기준이므로 파일이 쪼개지지는 않는다.
- 마지막 user prompt가 슬래시 커맨드면 `<command-name>` XML 원문이 그대로 기록된다. 원료 로그이므로 교정하지 않는다.
