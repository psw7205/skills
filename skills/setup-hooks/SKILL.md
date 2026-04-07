---
name: setup-hooks
description: >
  이 플러그인의 git 안전 훅을 ~/.claude/settings.json에 설치하거나 제거하는 스킬.
  "hooks 설치", "guard 설치", "setup hooks", "install hooks", "훅 설정",
  "hooks 제거", "guard 제거", "uninstall hooks", "훅 삭제" 등에서 트리거.
---

# setup-hooks

이 플러그인에 포함된 git 안전 훅(guard-untracked)을 사용자의 CLI 도구 설정에 등록하거나 제거한다.

## 스크립트 위치

```
${CLAUDE_PLUGIN_ROOT}/skills/setup-hooks/scripts/guard-untracked.sh
```

## 동작 요약

| 명령 | 동작 |
|------|------|
| `git clean` | auto-stash 후 실행 |
| `git checkout .` / `git checkout -- .` | auto-stash 후 실행 |
| `git reset --hard` | auto-stash 후 실행 |
| `git restore .` | auto-stash 후 실행 |
| `git push --force` / `git push -f` | deny (차단) |
| `git push --force-with-lease` | 허용 (안전한 대안) |

## 프로토콜

stdin으로 JSON을 받고 stdout으로 JSON을 반환하는 범용 구조:

- **입력**: `{ "tool_input": { "command": "..." } }`
- **출력**: rewrite 시 `updatedInput`, 차단 시 `permissionDecision: "deny"`, 해당 없으면 exit 0 (빈 출력)

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

### 다른 CLI 도구

동일한 stdin/stdout JSON 프로토콜을 지원하는 도구라면 해당 도구의 pre-execution hook에 `bash /path/to/guard-untracked.sh`를 등록한다. 도구별 설정 문서를 참조.

## 설치/제거 절차

Claude에게 "훅 설치해줘" 또는 "훅 제거해줘"라고 요청하면:

1. **설치 시**: `~/.claude/settings.json`을 읽고, `hooks.PreToolUse`에 guard-untracked 항목이 없으면 추가한다. 기존 Bash matcher가 있으면 그 `hooks` 배열에 append한다.
2. **제거 시**: `hooks.PreToolUse`의 Bash matcher에서 guard-untracked 항목만 제거한다. Bash matcher의 hooks가 비면 matcher 자체를 제거한다.
3. 설정 변경 후 Claude Code 재시작 필요.

중복 등록하지 않는다 — 이미 `guard-untracked` 문자열이 command에 포함되어 있으면 skip.

## Gotchas

- settings.json은 세션 시작 시 로드된다. 설치/제거 후 반드시 재시작.
- `git push --force`는 stash로 보호할 수 없어 deny 처리한다. `--force-with-lease`는 안전한 대안이므로 허용하지만, `--force`와 동시 사용 시 deny.
- auto-stash는 best-effort: stash할 것이 없는 clean tree에서도 원본 명령은 정상 실행된다.
