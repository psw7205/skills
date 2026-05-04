---
name: setup-hooks
description: >
  git 안전 훅을 Claude Code와 Codex 설정에 설치하거나 제거하는 스킬.
  "hooks 설치", "guard 설치", "setup hooks", "install hooks", "훅 설정",
  "codex hook 설치", "hooks 제거", "guard 제거", "uninstall hooks", "훅 삭제" 등에서 트리거.
---

# setup-hooks

이 플러그인에 포함된 git 안전 훅을 사용자의 CLI 도구 설정에 등록하거나 제거한다.

설치 요청을 받으면 대상 에이전트를 먼저 확인한다. 사용자가 `Codex`, `codex hook`, `~/.codex`를 언급하면 Claude Code 설정을 건드리지 말고 Codex 전용 절차를 수행한다.

## 스크립트 위치

```
${CLAUDE_PLUGIN_ROOT}/skills/setup-hooks/scripts/guard-untracked.sh
~/.agents/skills/setup-hooks/scripts/guard-untracked-codex.sh
```

## 동작 요약

### Claude Code

| 명령 | 동작 |
|------|------|
| `git clean` | auto-stash 후 실행 |
| `git checkout .` / `git checkout -- .` | auto-stash 후 실행 |
| `git reset --hard` | auto-stash 후 실행 |
| `git restore .` | auto-stash 후 실행 |
| `git push --force` / `git push -f` | deny (차단) |
| `git push --force-with-lease` | 허용 (안전한 대안) |

### Codex

Codex 전용 hook은 shell command rewrite를 하지 않는다. 현재 Codex hook 출력에서 `updatedInput` rewrite는 신뢰하지 않는다. 따라서 destructive command는 차단하고, agent에게 먼저 백업 명령을 실행한 뒤 재시도하라고 안내한다.

| 명령 | 동작 |
|------|------|
| `git clean` | deny. 단 `-n`, `--dry-run`, `-i`, `--interactive`는 허용 |
| `git checkout .` / `git checkout -- .` | deny |
| `git reset --hard` | deny |
| `git restore .` / `git restore -- .` | deny |
| `git push --force` / `git push -f` | deny |
| `git push --force-with-lease` | 허용 |

## 프로토콜

### Claude Code

- **입력**: `{ "tool_input": { "command": "..." } }`
- **출력**: rewrite 시 `updatedInput`, 차단 시 `permissionDecision: "deny"`, 해당 없으면 exit 0 (빈 출력)

### Codex

- **입력**: `PreToolUse` JSON의 `tool_name`, `tool_input.command`
- **출력**: 차단 시 `hookSpecificOutput.permissionDecision: "deny"`와 non-empty `permissionDecisionReason`
- **제약**: `permissionDecision: "allow" | "ask"`, `updatedInput`, `additionalContext`는 사용하지 않는다.

## 설치 가이드

### Claude Code (`~/.claude/settings.json`)

`hooks.PreToolUse` 배열에 Bash matcher로 등록한다. 이미 Bash matcher가 있으면 해당 `hooks` 배열에 추가한다.

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          // ... 기존 훅들 ...
          {
            "type": "command",
            "command": "bash /absolute/path/to/guard-untracked.sh",
            "statusMessage": "Guarding untracked files..."
          }
        ]
      }
    ]
  }
}
```

ref: https://code.claude.com/docs/en/hooks

### Codex (`~/.codex/hooks.json`)

`npx skills add ./`는 스킬 파일을 설치/동기화하는 단계이고, hook 등록은 별도 설정 파일 변경이다. Codex hook 설치 요청까지 받은 경우 다음 순서로 끝까지 수행한다.

1. `npx skills add ./ -g --skill setup-hooks --agent '*' -y` 또는 사용자가 지정한 `npx skills` 설치 명령으로 최신 `setup-hooks`를 설치한다.
2. 설치된 스킬 경로의 등록 스크립트를 실행한다.

```bash
bash ~/.agents/skills/setup-hooks/scripts/install-codex-hook.sh install
```

등록 결과는 `~/.codex/hooks.json`에 다음 형태로 반영된다.

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /absolute/path/to/guard-untracked-codex.sh",
            "async": false,
            "timeoutSec": 5,
            "statusMessage": "Guarding destructive git commands..."
          }
        ]
      }
    ]
  }
}
```

제거:

```bash
bash ~/.agents/skills/setup-hooks/scripts/install-codex-hook.sh remove
```

중복 등록하지 않는다. `guard-untracked-codex.sh`가 포함된 기존 hook handler를 제거한 뒤 하나만 다시 추가한다.

### 다른 CLI 도구

동일한 stdin/stdout JSON 프로토콜을 지원하는 도구라면 해당 도구의 pre-execution hook에 `bash /path/to/guard-untracked.sh`를 등록한다. 도구별 설정 문서를 참조.

## 설치/제거 절차

Claude Code 대상으로 "훅 설치해줘" 또는 "훅 제거해줘"라고 요청하면:

1. **설치 시**: `~/.claude/settings.json`을 읽고, `hooks.PreToolUse`에 guard-untracked 항목이 없으면 추가한다. 기존 Bash matcher가 있으면 그 `hooks` 배열에 append한다.
2. **제거 시**: `hooks.PreToolUse`의 Bash matcher에서 guard-untracked 항목만 제거한다. Bash matcher의 hooks가 비면 matcher 자체를 제거한다.
3. 설정 변경 후 Claude Code 재시작 필요.

중복 등록하지 않는다 — 이미 `guard-untracked` 문자열이 command에 포함되어 있으면 skip.

Codex 대상으로 "codex hook 설치해줘"라고 요청하면:

1. `~/.codex/hooks.json`이 있는지 확인한다.
2. `install-codex-hook.sh install`을 실행한다.
3. `jq`로 `~/.codex/hooks.json`을 파싱하고 `guard-untracked-codex.sh` handler가 하나만 있는지 확인한다.
4. 설정 변경 후 Codex 재시작 필요.

## Gotchas

- settings.json은 세션 시작 시 로드된다. 설치/제거 후 반드시 재시작.
- Codex도 `hooks.json` 변경 후 새 세션에서 확인한다.
- `git push --force`는 stash로 보호할 수 없어 deny 처리한다. `--force-with-lease`는 안전한 대안이므로 허용하지만, `--force`와 동시 사용 시 deny.
- Claude Code auto-stash는 best-effort: stash할 것이 없는 clean tree에서도 원본 명령은 정상 실행된다.
- Codex hook은 side effect를 만들지 않는다. PreToolUse 단계에서 hook이 직접 `git stash`를 실행하면 실제 원명령이 취소되어도 stash가 남을 수 있으므로, Codex에서는 차단과 안내만 수행한다.
