---
name: setup-machine
description: >
  머신의 에이전트 환경을 한 요청으로 맞추는 스킬. 새 머신 셋업, 머신 간 싱크, 스킬 업데이트 반영을 같은 절차로 처리한다.
  dotfiles와 herdr는 하위 스킬에 위임하고, Claude Code·Codex 계층(글로벌 지침, output style, statusline,
  셸 가드, Artifact 가드, verify-gate, 세션 로그)은 sync 스크립트로 check → apply한다.
  "새 머신 셋업", "이 머신 환경 구성해줘", "에이전트 환경 맞춰줘", "싱크 맞춰줘", "스킬 업데이트 반영해줘",
  "셋업 점검", "뭐가 빠졌는지 봐줘", "글로벌 설정 설치", "공용 CLAUDE.md 설치", "hooks 설치", "guard 설치",
  "codex hook 설치", "훅 제거", "rg -r 막아줘", "아티팩트 막아줘", "verify gate 설치", "verify gate 꺼줘",
  "미확인 보고 차단", "세션 로그 훅 설치", "세션 자동 기록", "세션 로그 제거", "statusline 설치", "상태바 설치",
  "output style 설치", "한국어 output style", "답변이 영어로 나와",
  "setup this machine", "sync agent config", "install hooks", "install verify gate", "install statusline" 등에서 트리거.
---

# setup-machine

머신 한 대의 에이전트 환경을 이 스킬의 canonical 상태로 맞춘다. 새 머신, 다른 머신과의 싱크, 스킬 업데이트 반영은 모두 같은 절차다. 판정과 쓰기는 `scripts/sync.py`가 하고, 에이전트는 스크립트를 실행하고 사용자 확인이 필요한 지점만 처리한다. 설정 JSON을 손으로 고치지 않는다.

## 구성

| 계층 | 담당 |
|------|------|
| 셸·패키지·툴체인, resume completion | `setup-dotfiles` |
| 에이전트 계층 | 이 스킬의 `scripts/sync.py` |
| herdr 설정 | `setup-herdr` |

에이전트 계층 컴포넌트:

| id | Claude Code | Codex | 요구 |
|----|-------------|-------|------|
| `global-config` | `CLAUDE.md` ← `references/global-config.md` | `AGENTS.md` ← 같은 파일 | — |
| `output-style` | `output-styles/korean-concise.md` + `outputStyle` | — | — |
| `statusline` | `statusline-command.sh` + `statusLine` | — | `jq`, 대화형 머신 |
| `shell-guard` | `PreToolUse` Bash: `guard-commands.py`, `rg-replace-flag-fix.py` | `PreToolUse` `Bash\|exec`: `guard-commands-codex.py` | `python3` |
| `artifact-guard` | `PreToolUse` Artifact: `guard-artifact.py` | — | `python3` |
| `verify-gate` | `Stop`: `stop-verify-gate.sh claude` | `Stop`: `stop-verify-gate.sh codex` | `jq` |
| `session-log` | `Stop`: `stop-session-log.sh` | — | `jq` |

훅별 판정과 계약은 `references/guard.md`, `references/verify-gate.md`, `references/session-log.md`에 있다. 훅 로직을 고치면 `bash scripts/run-tests.sh`를 돌린다.

## 절차

1. **스킬 확보·갱신.** `npx skills add <source> -g --skill setup-machine setup-dotfiles setup-herdr -y`. `<source>`는 이 레포의 로컬 경로 또는 `psw7205/skills`다. 업데이트 반영도 같은 명령이다.
2. **프로파일.** `uname -s`와 `command -v python3 jq herdr codex claude`로 감지한다. 대화형 머신 여부는 감지할 수 없다. `~/.agents/setup-machine/profile.json`에 `interactive`가 없을 때만 사용자에게 묻고 `python3 <S>/sync.py profile --interactive true|false`로 기록한다.
3. **dotfiles.** `setup-dotfiles`를 대조 모드로 먼저 돌린다. 새 머신이거나 사용자가 원할 때만 적용한다. 도구가 새로 설치됐으면 2의 감지를 다시 한다.
4. **에이전트 계층.**
   - `python3 <S>/sync.py check`로 상태를 보이고 `python3 <S>/sync.py apply`를 실행한다.
   - `user-modified` 항목은 대상 파일과 canonical의 diff(설정 값이면 현재 값)를 보이고, 사용자가 승인한 것만 `apply --overwrite <id,...>`로 덮어쓴다.
   - `needs-review`는 Codex가 바뀐 훅의 신뢰를 요구하는 상태다. 사용자가 새 Codex 세션에서 `/hooks`로 승인한 뒤 `check`를 다시 돌린다.
   - `blocked`는 사유(도구 부재, Codex `hooks` 기능)를 그대로 보고한다. 설치 완료로 말하지 않는다.
5. **herdr.** `herdr`가 있고 대화형 머신이면 `setup-herdr`에 위임한다.
6. **옛 스킬 정리.** `rg -n 'skills/(setup-hooks|verify-gate|session-log)/' ~/.claude/settings.json "${CODEX_HOME:-$HOME/.codex}/hooks.json"`가 빈 출력일 때만(`blocked` 컴포넌트는 옛 등록을 옮기지 않고 detail에 "옛 경로 등록 남음"을 적는다) `npx skills remove -g setup-hooks verify-gate session-log statusline setup-output-style setup-global-config resume-completion -y`. `~/.agents/.skill-lock.json`에 없는 이름은 뺀다. 순서를 뒤집으면 등록된 Stop 훅이 없는 파일을 가리켜 매 응답마다 에러가 난다.
7. **리포트.** 컴포넌트×에이전트 상태, 백업 경로, 사용자 할 일을 낸다. 사용자 할 일은 새 Claude Code·Codex 세션, Codex `/hooks` 승인, herdr 재접속(remote attach는 시작 시점에 config를 읽는다)이다. `session-log`가 설치돼 있으면 기록 위치(`~/.agents/session-logs/`)와 끄는 방법(`remove --only session-log`)을 적는다.

`<S>`는 설치된 이 스킬의 `scripts` 디렉토리다(`~/.agents/skills/setup-machine/scripts`).

점검 요청("셋업 점검", "뭐가 빠졌어")에서는 1, 6, `apply`를 하지 않는다. `check`와 dotfiles 대조만 보고한다.

## 개별 요청

| 요청 | 실행 |
|------|------|
| "verify gate 설치", "아티팩트 막아줘", "statusline 설치" | `apply --only <id>` (꺼둔 것도 다시 켠다) |
| "verify gate 꺼줘", "세션 로그 제거", "훅 제거" | `remove --only <id>` (이 머신의 `disabled`에 `<id>:<agent>`로 기록되어 싱크가 되살리지 않는다) |
| "Codex만" | `--agent codex` |

## sync.py

```
sync.py check  [--agent claude,codex] [--only ids] [--json]
sync.py apply  [--agent ...] [--only ids] [--overwrite ids] [--json]
sync.py remove --only ids [--agent ...] [--json]
sync.py profile --interactive true|false
```

| 상태 | 뜻 |
|------|-----|
| `ok` | canonical과 같다 |
| `missing` | 없다. `apply`가 설치한다 |
| `outdated` | 마지막 설치본 그대로인데 canonical이 바뀌었다. `apply`가 갱신한다 |
| `stale` | 옛 경로·옛 이름·중복 handler. `apply`가 정리한다 |
| `user-modified` | 사용자 수정이나 다른 설정 값. `--overwrite` 없이는 건드리지 않는다 |
| `needs-review` | Codex 훅 신뢰 필요 |
| `blocked` | 요구 도구 부재, Codex `hooks` 기능 꺼짐, 대화형 여부 미정 |
| `disabled` / `n/a` | 이 머신에서 끔 / 해당 없음(에이전트 미설치, 헤드리스) |

종료 코드: `0` 수렴, `1` 남은 항목 있음, `2` 사용 오류나 설정 JSON 파싱 실패(아무것도 쓰지 않는다).

쓰기 규칙: 내용이 바뀔 때만 쓰고, 쓰기 전에 `<file>.bak.<timestamp>`를 남기고, symlink는 링크 대상에 쓰고, 우리 것이 아닌 키와 handler는 보존한다. 마지막 설치 해시는 `~/.agents/setup-machine/state.json`, 머신 프로파일은 `profile.json`에 있다.

## Gotchas

- 스킬은 `--agent` 없이 전역 설치한다. 파일은 `~/.agents/skills/`에 놓이고 `~/.claude/skills/`는 그쪽을 가리키는 symlink가 된다. 등록되는 command도 그 경로를 가리킨다.
- `npx skills update`는 레포에서 사라진 스킬을 지울지 물을 수 있다. 갱신은 `add`로 한다.
- 우리 handler는 command 안의 스크립트 파일명으로 식별한다. 그래서 `~/.claude/skills/setup-hooks/...`처럼 옛 경로로 등록된 handler도 제자리에서 새 경로로 바뀐다.
- Codex 훅 신뢰는 `config.toml`의 `[hooks.state."<hooks.json>:<event>:<i>:<j>"]`에 위치 기준으로 저장된다. `sync.py`는 handler 배열 위치를 보존해 무관한 훅의 신뢰를 깨지 않는다. 제자리 갱신은 같은 키에 낡은 해시를 남기므로, 바꿀 때 본 해시를 `state.json`에 기록하고 Codex가 다른 해시를 저장할 때까지 `needs-review`로 둔다. 신뢰 해시를 직접 쓰거나 `--dangerously-bypass-hook-trust`를 쓰지 않는다.
- Codex 훅은 `hooks` 기능이 켜져 있어야 돈다. 옛 키 이름은 `codex_hooks`다. `sync.py`는 `codex features list`로 판정하고 `apply`에서 `codex features enable hooks`로 켠다.
- 상태 파일이 없는 첫 실행에서는 canonical과 다른 파일이 모두 `user-modified`로 나온다. 예전 canonical일 가능성이 높지만 diff를 보고 덮어쓴다.
- 머신마다 다른 사실(OS·PATH 함정, 디렉토리, 네트워크)은 `global-config`에 넣지 않는다. Claude Code는 `~/.claude/rules/host.md`, Codex는 `~/.codex/config.toml`의 `developer_instructions`에 둔다. 이 스킬은 두 곳을 만들거나 덮어쓰지 않는다.
- Project 설정의 `outputStyle`이 user 설정을 이긴다. 응답 스타일이 안 바뀌면 작업 repo의 `.claude/settings*.json`에서 `outputStyle`을 찾아 보고한다. 값은 frontmatter `name`과 대소문자까지 같아야 한다.
- `korean-concise.md`의 `keep-coding-instructions: true`가 빠지면 Claude Code의 software engineering 지시가 system prompt에서 빠진다.
- 모든 변경은 새 세션부터 적용된다. 현재 세션에 소급되지 않는다.
