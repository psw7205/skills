---
name: hc-agent-refresh
description: >
  Claude Code·Codex 자동 업데이트 뒤 "Restart to update"가 뜰 때, herdr-core(`hc`) 터미널에서
  유휴(done·idle) 상태인 구버전 세션을 같은 대화로 resume해 새 버전으로 바꾼다.
  "claude 재시작", "codex 재시작", "에이전트 업데이트 반영", "hc agent refresh",
  "restart idle agent sessions" 등에서 실행.
disable-model-invocation: true
---

# hc-agent-refresh

`hc server restart`나 core 업데이트는 실행 중인 프로그램을 살려 두므로 에이전트는 구버전 바이너리로 계속 돈다. `keep` 복구도 셸만 띄우고 원래 명령을 다시 실행하지 않는다. 이 스킬은 세션별로 종료 후 resume한다.

```bash
python3 -I scripts/refresh.py                 # dry run: 대상과 실행할 명령만 출력
python3 -I scripts/refresh.py --apply         # 전체 적용
python3 -I scripts/refresh.py --apply t11 wsl-dev/info-card-text   # 주소·이름으로 한정
python3 -I scripts/refresh.py --apply --force wsl-dev/t29          # 버전이 같아도 재시작
```

`hc ls`에 보이는 모든 머신을 다룬다. 바꿀 대상은 실행 중인 버전이 그 머신의 `<bin> --version`보다 낮은 세션이다.

| | Claude Code | Codex |
|---|---|---|
| 실행 중 버전 | `~/.claude/sessions/<pid>.json`의 `version` | 실행 파일 경로의 `releases/<version>` |
| 세션 id | 같은 파일의 `sessionId` | 종료 화면의 `codex resume <id>` 또는 `Session ID: <id>` |
| 종료 → 재개 | `/exit` → `claude --resume <id>` | `/quit` → `codex resume <id> --no-daemon` |

## 동작

- 루트가 셸인 터미널(pane에서 직접 띄운 것): 종료 명령을 보낸 뒤 같은 셸에서 `command <bin> …`로 다시 띄운다. 주소와 pane 위치가 유지된다. `command`는 원래 argv에 이미 들어 있는 플래그를 alias가 한 번 더 붙이지 않게 한다.
- 루트가 에이전트인 터미널(`hc run claude "…"`): 종료되면 rm하고, 같은 cwd·name·parent·keep·labels로 다시 띄운다. 주소는 바뀐다.
- 대화가 없는 세션은 resume 대신 같은 플래그로 새 세션을 띄운다. 두 에이전트 모두 첫 메시지 때 대화 파일을 만들기 때문이다. Claude는 `~/.claude/projects/*/<id>.jsonl`, Codex는 `~/.codex/sessions/**/rollout-*-<id>.jsonl`이 없으면 대화가 없는 것으로 본다. 대화가 없는 Codex는 종료 화면에 `codex resume <id>` 대신 `Session ID: <id>`만 남긴다.
- 원래 argv에서 플래그만 남긴다. 초기 프롬프트 인자와 resume·continue·print 계열은 뺀다. 그래서 같은 작업이 다시 전송되지 않는다. 값을 받는 플래그는 그 머신의 `<bin> --help`에서 판별한다.
- Codex에는 `--no-daemon`을 붙인다. daemon 모드에서는 명령이 hc 밖에서 실행되기 때문이다.

## 건너뛰는 경우

- `working`·`blocked` 등 유휴가 아닌 세션, 그리고 이 스크립트를 실행한 터미널 자신
- 자식 hc 터미널이 있는 세션: 부모를 종료하면 자식도 함께 끝날 수 있다
- 부모 주소를 대상 머신 기준으로 지정할 수 없는, 루트가 에이전트인 터미널: 그 부모 터미널에서 실행한다

## 함정

- 에이전트 터미널 안에서 `hc send`를 하면 `<hc from=…>` 태그가 붙어 슬래시 명령과 셸 명령이 깨진다. 스크립트는 `HC_TERMINAL_ID`를 뺀 환경에서 send한다.
- daemon 모드로 돌던 Codex는 TUI를 종료해도 app-server가 thread lock(`~/.codex/thread-writer-locks/<id>.lock`)을 계속 쥐고 있다. 그래서 다시 띄운 세션이 "This conversation is open in another app"에서 멈춘다. 이때 스크립트는 다음 조치를 출력만 한다: 그 daemon에 다른 클라이언트가 없는지 확인한 뒤 `codex app-server daemon restart`를 실행하고, 터미널에서 `r`을 누른다. daemon은 직접 건드리지 않는다.
- resume 뒤 첫 턴은 prompt cache가 비어 있어서 전체 맥락을 다시 읽는다. 오래된 세션이 많으면 비용이 커진다.
