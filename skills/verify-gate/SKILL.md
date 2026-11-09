---
name: verify-gate
description: >
  Claude Code와 Codex에서 근거 없는 미확인 보고를 감지해 한 번 더 검증하게 하는
  Stop 훅을 설치하거나 제거한다. jq로 마지막 응답을 판정하고, 확인하거나 시도한
  명령과 blocker를 남기도록 턴을 잇는다. "verify gate 설치", "Codex 검증 훅 설치",
  "확인 안 하고 멈추는 것 막아줘", "미확인 보고 차단", "검증 게이트 훅",
  "verify gate 제거", "install verify gate", "Codex stop hook",
  "stop hook for unverified claims" 등에서 트리거.
---

# verify-gate

Claude Code와 Codex의 `Stop` 훅으로 근거 없는 미확인 표현을 감지하고, 검증을 마치도록 한 번 더 턴을 잇는다. 실제 도구 실행 여부를 감사하는 훅은 아니다.

대상 CLI는 사용자 요청을 따른다. 지정이 없으면 현재 CLI를 대상으로 삼고, 둘 다 요청한 경우에만 양쪽 설정을 수정한다.

## 스크립트 구성

| 파일 | 역할 |
|------|------|
| `scripts/stop-verify-gate.sh` | Stop 훅 본체. 첫 인자는 `claude`(기본값) 또는 `codex`. stdin JSON의 `last_assistant_message`를 판정 |
| `scripts/test-stop-verify-gate.sh` | CLI별 계약 테스트. `bash test-stop-verify-gate.sh claude`와 `bash test-stop-verify-gate.sh codex` |

## 판정

다음 표현이 있는 줄을 미확인 줄로 본다: `확인하지 않았/못했`, `확인 못 했`, `아직 확인`, `미확인`, `실행해/돌려/띄워/열어 보지 않`, `시도하지 않았`, `unverified`, `unresolved`, `did not/haven't/not yet verify·check·test·run`.

줄과 Markdown은 다음처럼 처리한다.

| 형식 | 처리 |
|------|------|
| ``unresolved: `명령` — blocker`` 형식의 줄 | 명령·구분자·비어 있지 않은 사유가 있으면 제외. 명시적인 미시도·연기 사유는 계속 판정 |
| markdown heading 줄 | 섹션 제목만으로는 판정하지 않고 아래 항목을 본다 |
| code fence 안 | 여는 fence의 문자·길이를 기억해 중첩 예시를 건너뜀 |
| 응답 전체를 감싼 `markdown` 또는 `md` fence | 바깥 fence만 벗겨 보고를 판정. 그 안의 코드 fence는 계속 제외 |
| `미확인 항목은 없습니다.`, `No unverified items remain.` | 미확인이 없다는 독립된 줄은 제외. 뒤에 다른 미확인 표현이 붙으면 판정 |
| `확인되지 않았다` | "찾아봤는데 없었다"는 조사 결과다 |
| `확인하지 않고 …했다` | 과거 실수 설명이지 남은 미확인이 아니다 |

미확인 줄이 있으면 각 300자, 최대 10개와 지시를 돌려준다. 지금 도구로 확인하고, 막힌 것만 ``unresolved: `실제로 실행한 명령` — blocker``로 남기게 한다. 대기 중인 작업은 사용 가능한 도구로 기다리고, 공유 상태 변경이 필요한 확인은 그 사실을 blocker로 적게 한다.

## CLI별 계약

| 항목 | Claude Code | Codex |
|------|-------------|-------|
| 입력 | `last_assistant_message`, `stop_hook_active`, `background_tasks` | `last_assistant_message`, `stop_hook_active`; `background_tasks`는 제공되지 않음 |
| 턴을 잇는 출력 | `hookSpecificOutput: {hookEventName: "Stop", additionalContext: "..."}` | `decision: "block", reason: "..."` |
| 설정 | `~/.claude/settings.json`의 `hooks.Stop` | `${CODEX_HOME:-$HOME/.codex}/hooks.json`의 `hooks.Stop` |

Claude Code는 정상적인 안내가 훅 에러로 표시되지 않도록 `additionalContext`를 쓴다. Codex는 `reason`으로 continuation prompt를 만들므로 `codex` 인자를 빠뜨리지 않는다. 통과 시에는 양쪽 모두 출력 없이 exit 0 한다.

통과시키는 경우:

- `stop_hook_active == true`: 정지 시도 한 번에 한 번만 되돌린다. 무한 루프 방지.
- Claude Code에서 `background_tasks`가 비어 있지 않음: 백그라운드 작업 완료로 다시 깨어날 수 있으므로 대기 중 보고는 통과.
- `jq` 부재, 잘못된 JSON, `last_assistant_message` 없음: 조용히 exit 0.

## 설치 절차

1. 대상 CLI의 버전과 아래 공식 문서를 확인한다. Codex에서는 `codex features list`로 `hooks`가 활성인지 확인한다. 현재 키는 `[features].hooks`이며 `codex_hooks`는 이전 별칭이다. 꺼져 있으면 비활성 원인을 확인하고 설치 요청 범위에서 활성화한다. 관리자 정책으로 비활성인 경우 그 제한을 보고한다.
2. `npx skills add ./ -g --skill verify-gate --agent codex -y` 또는 `--agent claude-code`로 설치·갱신한다. `./`는 이 저장소 루트에서만 사용한다. 다른 작업 디렉토리라면 확인한 저장소 경로나 설치 source를 사용한다. 로컬 설치 폴더에 직접 복사하지 않는다.
3. 설치된 스크립트의 절대 경로와 훅 실행 환경의 `bash`, `jq`를 확인한다. `jq`가 없으면 게이트는 동작하지 않으므로 설치 완료로 보고하지 않는다. 프로젝트의 도구 관리 방식으로 의존성을 준비한 뒤 대상 CLI의 계약 테스트를 돌린다.
4. 대상 설정을 읽고 아래 handler를 동기식으로 등록한다. command 안의 실제 경로를 셸 인용한다. 같은 스크립트의 기존 handler는 경로·CLI 인자를 갱신해 하나만 남기고, 다른 handler와 설정 키는 보존한다. symlink인 설정 파일은 링크 대상에 반영한다.
5. JSON을 다시 파싱하고 대상 handler가 하나인지, 실제 command를 미확인 입력과 `stop_hook_active: true` 입력으로 실행했을 때 각각 continuation JSON과 빈 출력을 내는지 확인한다. 새 세션에서 `/hooks`로 등록·신뢰 상태를 확인한 뒤 완료를 보고한다. 신뢰 승인이 필요한 경우 사용자의 CLI 승인 절차를 안내한다.

### Claude Code

```jsonc
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash '/absolute/path/to/stop-verify-gate.sh' claude",
            "timeout": 5,
            "statusMessage": "Checking for unverified claims..."
          }
        ]
      }
    ]
  }
}
```

### Codex

`CODEX_HOME`이 설정되어 있으면 그 디렉토리의 `hooks.json`을 사용한다. 기존 `config.toml`의 inline `[hooks]`나 프로젝트·플러그인에 같은 훅이 있으면 중복 등록하지 않는다.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash '/absolute/path/to/stop-verify-gate.sh' codex",
            "timeout": 5,
            "statusMessage": "Checking for unverified claims..."
          }
        ]
      }
    ]
  }
}
```

공식 계약:

- [Claude Code hooks](https://code.claude.com/docs/en/hooks#stop-decision-control)
- [Codex hooks](https://developers.openai.com/codex/hooks#stop)

## 제거 절차

대상 CLI의 실제 등록 위치에서 `stop-verify-gate.sh` handler만 제거한다. 같은 entry 안의 다른 handler는 남기고, `hooks` 배열이 비면 entry 자체를 제거한다. 다른 훅이 사용할 수 있으므로 Codex의 `hooks` 기능 전체를 끄지 않는다. 설정을 다시 파싱하고 새 세션의 `/hooks`에서 제거를 확인한다.

## Gotchas

- 설치·제거 검증은 새 세션에서 한다. 현재 세션이 자동으로 갱신됐다고 가정하지 않는다.
- `unresolved` 검사는 보고 형식과 명시적인 미시도 표현만 확인한다. 명령이 실제로 실행됐는지, 적힌 blocker가 사실인지는 보장하지 않는다.
- 응답 전체를 감싼 Markdown은 보고로 간주한다. 응답 전체가 복사할 예시인 경우에도 한 번 걸릴 수 있다.
- 판정은 표현 기반이라 미확인 표현을 **인용**하는 응답(이 훅 자체를 논의하는 대화 등)도 한 번 걸린다. 비용은 한 턴 추가이고, 두 번째 정지는 `stop_hook_active`로 통과한다.
- 반대로 미확인 표현 없이 확인을 건너뛴 응답은 잡지 못한다. 이 훅은 "미확인을 보고하고 멈추는" 패턴만 다룬다.
- Claude Code는 무관한 백그라운드 작업이 돌고 있어도 통과한다. Codex에서는 같은 입력 필드가 없으므로 이 예외를 적용하지 않는다.
- 판정은 jq(Oniguruma) 정규식으로 한다. `grep -E`로 옮기면 C locale에서 한글 뒤 수량자가 마지막 byte에만 걸려 조용히 빗나간다.
- Claude Code는 stop 훅 연속 continuation을 8회로 제한한다(`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`). 이 훅은 정지 한 번에 한 번만 이어가므로 cap에 닿지 않는다.
