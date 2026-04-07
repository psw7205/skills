---
name: setup-hooks
description: >
  이 플러그인의 git 안전 훅을 ~/.claude/settings.json에 설치하거나 제거하는 스킬.
  "hooks 설치", "guard 설치", "setup hooks", "install hooks", "훅 설정",
  "hooks 제거", "guard 제거", "uninstall hooks", "훅 삭제" 등에서 트리거.
---

# setup-hooks

이 플러그인에 포함된 git 안전 훅(guard-untracked)을 사용자의 `~/.claude/settings.json`에 등록하거나 제거한다.

## 설치

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup-hooks/scripts/install-hooks.sh"
```

설치 후 Claude Code를 재시작해야 훅이 활성화된다.

## 제거

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup-hooks/scripts/install-hooks.sh" --remove
```

## 포함된 훅

### guard-untracked

위험한 git 명령 실행 전 자동으로 `git stash push --include-untracked`를 삽입해 untracked 파일 손실을 방지한다.

| 명령 | 동작 |
|------|------|
| `git clean` | auto-stash 후 실행 |
| `git checkout .` / `git checkout -- .` | auto-stash 후 실행 |
| `git reset --hard` | auto-stash 후 실행 |
| `git restore .` | auto-stash 후 실행 |
| `git push --force` / `git push -f` | deny (차단) |
| `git push --force-with-lease` | 허용 (안전한 대안) |

## Gotchas

- settings.json은 세션 시작 시 로드된다. 설치/제거 후 반드시 Claude Code 재시작.
- 이미 설치된 상태에서 재실행하면 중복 등록하지 않는다.
- `git push --force`는 stash로 보호할 수 없어 deny 처리한다. `--force-with-lease`는 안전한 대안이므로 허용하지만, `--force`와 동시 사용 시 deny된다.
- auto-stash는 best-effort: stash할 것이 없는 clean tree에서도 원본 명령은 정상 실행된다. `git stash push` 실패 시 에러를 숨기고 원본을 그대로 실행하는 구조.
