---
name: pstack-codex
description: >
  Codex에서 pstack 스킬을 실행할 때 Cursor 도구, 서브에이전트, 모델, 설정과
  transcript 경로를 현재 Codex 환경으로 매핑한다.
  "Codex에서 pstack", "poteto-mode로 작업", "pstack Codex 매핑",
  "use pstack in Codex", "poteto-mode in Codex", "pstack-codex"에서 사용한다.
---

# Pstack Codex

pstack 원본 스킬을 읽고 아래 매핑으로 실행한다. 원본은 `cursor/plugins`에서 설치하고, Codex용 차이만 이 스킬에서 관리한다.

## 진입 절차

1. 사용자가 이름을 지정한 pstack 스킬을 선택한다. 작업만 주면 `poteto-mode`를 선택한다. 매핑 설명이나 설치 요청만 있으면 작업 playbook을 실행하지 않는다.
2. 스킬 카탈로그의 실제 경로에서 대상 `SKILL.md`를 찾는다. 없으면 프로젝트와 상위 repo의 `.agents/skills/`, `~/.agents/skills/`, `${CODEX_HOME:-$HOME/.codex}/skills/` 순으로 설치를 확인한다. 동명 사본은 합치지 말고 선택한 경로를 밝힌다. pstack이 없으면 설치 필요를 보고하고, 설치 요청일 때만 아래 명령을 실행한다.

   ```bash
   npx skills add https://github.com/cursor/plugins/tree/main/pstack --agent codex --skill '*' -g -y
   ```

3. 해당 원문 전체를 읽는다. 호출되는 다른 스킬도 실제 파일을 읽고, `references/`, `playbooks/`, `scripts/`는 그 스킬 디렉토리 기준으로 해석한다. `setup-pstack`은 원문 단계에 아래 설정 매핑을 적용한다.
4. 현재 도구 스키마와 사용자·프로젝트 지시를 우선해 실행한다. pstack의 Autonomy 문구는 외부 메시지 발송, push, merge, 배포나 범위 밖 수정에 대한 새 권한이 아니다. 사용할 수 없는 기능은 이유와 대체한 동작을 밝힌다.

Codex에서는 `$pstack-codex`에 작업이나 대상 스킬 이름을 붙여 호출한다. 원본의 `/pstack:name` 명령을 등록하는 스킬은 아니다.

## 도구 매핑

| Cursor 지시 | Codex 실행 |
|---|---|
| `Task` | 현재 세션의 `spawn_agent`. 제공되는 namespace와 인자 스키마를 확인한다. 서브에이전트가 없거나 상위 지시가 금지하면 직접 처리하고 독립 검증 부재를 보고한다. |
| `AskQuestion` | 제공되는 `request_user_input` 또는 `request_user_input_async`. 도구의 모드·용도 제약을 따른다. 사용할 수 없으면 사용자 응답이 필요한 지점에서 일반 질문으로 넘긴다. |
| Open a todolist | `update_plan`이 있으면 사용한다. 없으면 작업 단계와 상태를 응답이나 작업용 문서로 관리한다. |
| `Read`, `Grep`, `Glob`, `Shell` | 현재 파일 읽기·검색·실행 도구. 셸 검색은 `rg`, 파일 탐색은 `rg --files`를 사용한다. |
| 다른 스킬 `/name`, `the name skill` | 설치된 해당 `SKILL.md`를 읽고 따른다. 사용자에게 안내할 때는 Codex의 `$name` 표기를 쓴다. |
| built-in PR tool | 프로젝트의 forge 도구. GitHub는 `gh`를 사용하며, PR 생성·게시·병합 권한은 현재 요청에서 판단한다. |

도구 이름만 치환하고 Cursor 인자를 그대로 넘기지 않는다. 특히 `Task`와 Codex `spawn_agent`의 스키마는 다르다.

## 서브에이전트 매핑

모든 spawn 메시지에 이 어댑터의 실제 `SKILL.md` 절대 경로를 넣고, 원본 스킬이나 에이전트 문서보다 먼저 전체를 읽어 도구·모델·설정·경로 매핑을 적용하도록 지시한다. 부모 대화의 상속에 의존하지 않으며, 하위 서브에이전트를 생성할 때도 같은 전달 규칙을 적용한다. 읽기는 위임된 역할의 매핑을 위한 것이며, 부모가 맡은 진입 절차나 playbook을 다시 실행하라는 뜻이 아니다.

| Cursor 필드 | Codex 처리 |
|---|---|
| `subagent_type: generalPurpose` | 별도 타입 등록 없이 역할·범위·성공 조건을 spawn 메시지에 명시한다. |
| `subagent_type: poteto-agent` | `poteto-mode/SKILL.md`의 절대 경로를 전달하고 원문과 적용할 principle을 읽도록 한다. 이 역할은 delegate이며, 부모가 playbook을 소유한다. |
| `subagent_type: comment-sicko` | 아래 원본 에이전트 문서를 읽어 spawn 메시지에 역할을 전달한다. Codex에 동명 타입이 등록됐다고 가정하지 않는다. |
| `readonly: true` | 수정 금지 범위를 메시지에 명시한다. Codex 스키마에 강제 옵션이 없으면 강제 격리라고 부르지 않는다. 결과 수령 후 대상 작업 트리 상태를 점검한다. |
| `readonly: false` | 현재 세션의 쓰기·도구 권한을 따른다. MCP 상속은 실제 제공 도구로 확인한다. |
| `environment: "cloud"` | 코드 작성은 별도 git worktree로 격리한다. cloud VM·대시보드·서버 측 기능 자체가 필요한 단계는 이 대체로 충족됐다고 하지 않는다. |
| `environment: "local"` | 현재 머신에서 실행한다. 쓰는 파일·branch를 다른 worker와 분리한다. |
| `cloud_base_branch` | worker가 사용할 branch 또는 SHA와 worktree 경로를 메시지에 명시한다. |
| `run_in_background`, `is_background`, `file_attachments` | 미지원 필드는 생략한다. 비동기 실행은 현재 spawn 도구를 따르고, 첨부 대신 읽을 파일 경로를 메시지에 넣는다. |
| `resume` | 현재 도구의 agent ID와 `send_message`, `followup_task`, `resume_agent` 등 실제 제공 기능을 사용한다. 새 작업에는 원문의 fresh-agent 규칙을 따른다. |

대기·완료 수집·종료도 현재 세션의 `wait` 또는 `wait_agent`, `close_agent` 등 제공 기능을 사용한다. 동시 실행 한도 안에서 나눠 실행하며, 동일 작업 트리에 쓰는 여러 worker를 격리된 것으로 취급하지 않는다.

`npx skills`는 플러그인 루트의 `agents/`를 설치하지 않는다. 플러그인 사본에 문서가 있으면 그 파일을 읽고, 개별 스킬 설치라면 필요한 문서만 upstream에서 읽는다.

- [poteto-agent](https://github.com/cursor/plugins/blob/main/pstack/agents/poteto-agent.md)
- [comment-sicko](https://github.com/cursor/plugins/blob/main/pstack/agents/comment-sicko.md)

원문 에이전트 문서의 Cursor 경로와 도구에도 이 매핑을 적용한다. 문서를 확보하지 못하면 해당 역할을 검증 없이 흉내 내지 말고 누락을 보고한다.

## 모델과 setup-pstack

Cursor의 `grok-*`, `claude-*`, `gpt-*` slug를 Codex 모델 이름으로 추측 변환하지 않는다. 기본은 부모 모델 상속이다. `auto`, `inherit-parent`도 `model`을 생략하는 뜻으로 처리한다.

실제 모델을 지정하려면 현재 Codex spawn 도구가 그 모델을 허용하는지 확인한다. reasoning effort와 fast 여부도 도구가 지원하는 별도 옵션으로만 전달한다. 미지원 effort를 모델 이름 뒤에 붙이지 않는다. 모델 override에 필요한 `fork_turns` 등 다른 조건도 해당 도구 스키마를 따른다.

`arena`의 cross-judge처럼 다른 모델 family가 조건인 단계는 같은 모델로 대체하고 완료라고 하지 않는다. 사용 가능한 다른 family가 없으면 원문의 skip 규칙을 적용하고 검증 차이를 보고한다.

`setup-pstack`을 실행할 때:

1. 원문의 역할 목록과 사용자 선택 절차를 유지하되, 검증된 Codex 모델·effort와 부모 상속만 제시한다. 설정 파일이나 역할 행이 없으면 부모 상속을 기본값으로 사용한다.
2. 역할 설정은 `${CODEX_HOME:-$HOME/.codex}/pstack-models.md`에 저장한다. 원문의 역할 라벨과 `# budget` 행을 유지하고 `.mdc` frontmatter는 쓰지 않는다. 실제 모델 값은 `<model> <effort>`로 기록한다.
3. Codex는 이 파일을 자동 rule로 읽지 않는다. 이 스킬을 통한 pstack 실행은 역할 설정이 필요할 때 파일을 명시적으로 읽는다. `AGENTS.md`나 `config.toml`에 역할 목록을 복제하지 않는다.
4. 설정 변경은 `setup-pstack` 요청 때만 수행한다. 검증 스킬 생성도 원문의 선택 절차를 따르며, 새 프로젝트 스킬은 `.agents/skills/`에 작성한다.

## 경로와 transcript

| Cursor 경로·기능 | Codex 해석 |
|---|---|
| `.cursor/skills/`, `~/.cursor/skills/` | 프로젝트 `.agents/skills/`, 사용자 `~/.agents/skills/`. 기존 Codex 스킬은 카탈로그 경로를 우선한다. |
| `~/.cursor/rules/pstack-models.mdc` | 위 `setup-pstack` 설정 파일. |
| `.cursor/rules/*.mdc`, `alwaysApply`, Custom Mode | Codex의 자동 rule이나 지속 모드로 등록되지 않는다. 이 스킬의 명시적 호출과 현재 대화 지시를 사용한다. |
| `~/.cursor/plugins/`, `.cursor-plugin/plugin.json` | 실제 Codex 플러그인 경로·매니페스트가 있는 경우에만 해석한다. 개별 스킬 설치를 플러그인 설치로 간주하지 않는다. |
| `../../README.md`, `../../docs/` | 개별 스킬 설치에는 없을 수 있다. 파일 존재를 확인하고 없으면 `cursor/plugins`의 해당 `pstack/` 문서를 읽는다. |
| `agent-transcripts/`, `~/.cursor/projects/` | Codex CLI는 `${CODEX_HOME:-$HOME/.codex}/sessions/**/rollout-*.jsonl`. 현재 session ID와 `session_meta.payload.cwd`로 범위를 확인한다. 데스크톱·원격 호스트도 이 파일을 쓴다고 가정하지 않는다. |

Transcript 탐색은 설치된 `session-bridge` 스킬이 있으면 그 locator를 재사용한다. 없으면 session ID와 실제 호스트 저장 경로를 확인한다. 같은 repo의 worktree 기록도 사용자가 지정한 범위로만 확장한다. Cursor의 경로 인코딩 규칙이나 가장 최신 파일 하나로 현재 세션을 단정하지 않는다.

## 번들 밖 의존성과 전용 기능

| 의존성·단계 | 처리 |
|---|---|
| Cursor 내장 `create-skill` | 현재 환경의 `skill-creator` 또는 `skill-guide`를 읽고 사용한다. |
| `cursor-team-kit`의 `deslop` | 설치돼 있으면 원문을 읽는다. 없으면 설치된 `diff-trim`으로 변경 범위의 간결성 점검을 대체하고 대체 사실을 보고한다. |
| `control-ui`, `control-cli` | 설치된 원문 또는 실제 대상 앱을 제어할 수 있는 browser·native·terminal 스킬을 사용한다. 드라이버가 없으면 live 검증은 미완료로 남긴다. |
| Cursor Automations, `update_state` routine, `SendToUser`, Benny | Cursor 전용 단계로 생략하고 이유를 밝힌다. webhook·secret·automation을 임의로 만들지 않는다. |
| Bugbot | 이미 있는 GitHub 리뷰 thread는 forge 도구로 처리한다. 새 실행·설정·Cursor 전용 대기는 대체 가능한 실제 API가 없으면 생략한다. |

생략한 단계가 후속 단계의 입력을 만들 예정이었다면 그 후속 단계도 미완료로 표시한다. 검증·산출물·외부 승인에 필요한 입력이 없는데 다음 단계가 통과했다고 하지 않는다.

## Gotchas

- `$poteto-mode`를 직접 호출하면 이 어댑터가 반드시 함께 읽힌다는 보장은 없다. Codex에서는 `$pstack-codex`를 진입점으로 사용한다.
- `disable-model-invocation`, `paths`, `icon`, `color` 같은 Cursor frontmatter의 동작을 Codex에서도 같다고 가정하지 않는다. Codex invocation policy는 `agents/openai.yaml`을 사용한다.
- 모델 선택을 부모 상속으로 바꾸면 실행은 가능해도 원문의 Grok·Claude 다중 모델 비교는 재현되지 않는다.
- 매핑은 스크립트 내부 경로를 바꾸지 않는다. `worktree-audit.sh`처럼 Cursor transcript 경로를 사용하는 스크립트는 실행 전에 원문을 확인하고 Codex 기록을 감사했다고 보고하지 않는다.
- upstream이나 설치된 pstack 사본을 수정하지 않는다. 매핑 변경은 `custom-skills`에서 관리하고 표준 `npx skills add`로 설치·업데이트한다.

## 원문

- [pstack](https://github.com/cursor/plugins/tree/main/pstack)
- [Claude Code adapter](https://github.com/cursor/plugins/blob/main/pstack/docs/harness/claude-code.md)
- [Codex skills](https://developers.openai.com/codex/skills/)
- [Codex plugin packaging](https://developers.openai.com/plugins/build/plugins)
