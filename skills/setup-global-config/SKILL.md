---
name: setup-global-config
description: >
  팀 공용 글로벌 에이전트 설정(CLAUDE.md / AGENTS.md)을 Claude Code와 Codex에 설치하거나 제거하는 스킬.
  Audience/Tone, Execution Boundary, Inspect-Don't-Ask, Git Safety, Commit Messages 등 공통 규칙을 담는다.
  "글로벌 설정 설치", "global config 설치", "공용 CLAUDE.md 설치", "팀 글로벌 규칙 적용",
  "global CLAUDE.md AGENTS.md 설치", "에이전트 공통 규칙 설치", "글로벌 설정 제거",
  "install global config", "setup global config", "uninstall global config" 등에서 트리거.
---

# setup-global-config

이 플러그인에 번들된 팀 공용 글로벌 설정을 사용자의 에이전트 설정 파일에 설치하거나 제거한다.

설치하는 사람마다 OS·런타임·이미 가진 글로벌 설정이 다르다. 환경을 가정하지 말고, 아래 절차를 따르되 기존 설정 충돌·외부 종속성은 그 환경에서 직접 확인해 판단한다.

## 대상 파일

| 에이전트 | 설치 위치 | 비고 |
|----------|-----------|------|
| Claude Code | `~/.claude/CLAUDE.md` | 세션 시작 시 자동 로드되는 글로벌 메모리 |
| Codex | `~/.codex/AGENTS.md` | Codex가 읽는 글로벌 지침 |

두 파일은 **동일한 내용**을 받는다. 사용자가 특정 에이전트(`Claude`, `Codex`)만 지정하면 그쪽만 설치한다. 지정이 없으면 두 곳 모두 설치한다.

## Canonical 소스

```
${CLAUDE_PLUGIN_ROOT}/skills/setup-global-config/references/global-config.md
```

이 파일이 single source of truth다. 대상 파일은 항상 이 내용으로 맞춘다.

## 설치 절차

각 대상 파일에 대해:

1. canonical 소스를 읽는다.
2. 대상 파일이 **없으면** canonical 내용을 그대로 쓴다.
3. 대상 파일이 있고 canonical과 **byte-identical**이면 이미 설치됨 — skip (idempotent).
4. 대상 파일이 있고 **다르면** 사용자가 가진 기존 글로벌 설정이다. 무단 덮어쓰기 금지:
   - 차이를 요약해 보여준다.
   - 기존 파일을 `<file>.bak.<timestamp>`로 백업한다.
   - 덮어쓸지 확인받은 뒤 canonical 내용을 쓴다.
   - 백업 경로를 알려준다.

설치 후 안내: 설정은 **새 세션부터** 적용된다. Claude Code / Codex 재시작 필요.

## 외부 종속성 (필요 시 설치하는 agent가 판단)

이 설정 본문은 아래 외부 요소를 전제로 한다. 환경별로 유무가 다르므로 자동 감지/설치는 하지 않는다. 설정을 설치하는 agent가 자기 환경을 보고 필요하면 갖춘다.

- **`agent-browser`** — "Browser Automation" 섹션이 참조하는 web automation CLI (npm: "Browser automation CLI for AI agents"). 브라우저 자동화를 실제로 쓸 거면 PATH에 있어야 한다. 없으면 글로벌 설치(`npm i -g agent-browser`)나 즉석 실행(`npx agent-browser`) 중 환경에 맞게 선택. 안 쓸 거면 무시해도 무방 — 해당 섹션은 지침일 뿐 런타임 강제는 아니다.
- **`guard-untracked.sh` git 안전 훅** — "Git Safety" 섹션은 이 훅으로 auto-stash / force-push deny가 강제된다고 전제한다. 훅 자체는 이 설정에 포함되지 않는다. 동작까지 원하면 같은 플러그인의 `setup-hooks` 스킬로 별도 설치한다.

## 제거 절차

"글로벌 설정 제거" 요청 시:

1. 대상 파일이 canonical과 동일하면 삭제하거나, 설치 직전 백업(`<file>.bak.<timestamp>`)이 있으면 그걸로 복원한다.
2. 백업이 없으면 무단 삭제하지 말고 사용자에게 어떻게 할지 확인한다.

## Gotchas

- `CLAUDE.md`와 `~/.codex/AGENTS.md`는 자동 로드 글로벌 설정 — 설치/제거 후 반드시 새 세션에서 확인. 현재 세션엔 반영 안 된다.
- 4번(기존 설정 상이) 경로에서 백업 없이 덮어쓰면 사용자의 개인 글로벌 규칙이 사라진다. 차이가 사소해 보여도 백업은 항상 만든다.
- canonical 본문이 참조하는 `~/...` 경로(`~/.claude/settings.json` 등)는 관례적 설정 경로다. 이 스킬을 수정할 때 본문에 실제 machine-local 절대경로(`/Users/...`)를 넣지 말 것 — 레포 "No Local Paths" 규칙 대상이다.
