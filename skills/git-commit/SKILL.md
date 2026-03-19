---
name: git-commit
description: >
  Git 커밋 메시지 작성과 PR 생성 워크플로우 가이드.
  기존 커밋 스타일 분석, 시크릿 파일 제외, 커밋 히스토리 기반 PR 작성을 안내한다.
  "커밋 만들어", "커밋 메시지 작성", "commit", "커밋해줘",
  "PR 만들어", "PR 올려줘", "push하고 PR", "create PR",
  "변경사항 커밋", "코드 올려줘", "push해줘",
  "커밋 메시지 어떻게 쓰지", "PR description 작성",
  "commit and push", "make a commit", "create a pull request"
  등에서 트리거.
---

# Git Commit

커밋 메시지 작성과 PR 생성 워크플로우.

## 커밋 절차

### 1. 변경 사항 파악

```bash
git status
git diff HEAD
git branch --show-current
```

staged와 unstaged 변경을 모두 확인한다. 현재 브랜치도 확인하여 main/master 직접 커밋 여부를 판단한다.

### 2. 스테이징

**파일명을 지정하여 추가한다.** `git add -A`나 `git add .`는 의도하지 않은 파일을 포함시킨다.

스테이징 전 다음 패턴의 파일이 포함되지 않는지 확인:

- `.env`, `.env.*`
- `credentials.*`, `*secret*`, `*.pem`, `*.key`
- `*token*`, `*password*` (설정/시크릿 파일인 경우)

시크릿 파일이 변경 목록에 있으면 스테이징하지 말고 사용자에게 알린다.

### 3. 커밋 메시지 작성

**기존 스타일을 먼저 분석한다:**

```bash
git log --oneline -10
```

최근 커밋 메시지의 패턴(prefix, 언어, 길이, 형식)을 파악하고 일관성을 유지한다. 자기 스타일을 강요하지 않는다.

**메시지 원칙:**

- **"why" 중심** — 변경 내용(what)은 diff에 있다. 변경 이유와 목적을 쓴다.
- **간결하게** — 1-2문장. 장황한 설명은 PR 본문에.
- **정확하게** — "add"는 새 기능, "update"는 기존 기능 개선, "fix"는 버그 수정. 변경 성격에 맞는 동사를 사용한다.

**커밋 실행:**

```bash
git commit -m "$(cat <<'EOF'
커밋 메시지

Co-Authored-By: ...
EOF
)"
```

HEREDOC으로 전달하여 특수문자 문제를 방지한다. Co-Authored-By는 프로젝트에 기존 어트리뷰션 패턴이 있을 때만 포함한다.

## PR 생성

사용자가 PR을 요청했을 때만 실행한다.

### 1. 브랜치 확인

main/master에 있으면 새 브랜치 생성을 제안한다. 사용자 확인 없이 브랜치를 만들지 않는다.

### 2. 변경 범위 분석

```bash
git log --oneline <base-branch>..HEAD
git diff <base-branch>...HEAD
```

**분기 이후 모든 커밋을 분석한다.** 최신 커밋만 보면 PR 설명이 불완전해진다.

### 3. PR 작성

- **제목**: 70자 이내, 변경의 핵심을 한 줄로
- **본문**: Summary (1-3 bullet) + Test plan

```bash
gh pr create --title "제목" --body "$(cat <<'EOF'
## Summary
- 변경 요약 bullet

## Test plan
- 테스트 방법

EOF
)"
```

리모트에 푸시되지 않은 상태면 `git push -u origin <branch>` 먼저 실행한다.

## Gotchas

- `git add .`은 `.gitignore`에 없는 시크릿 파일을 포함시킨다. `.env.local`처럼 gitignore에 빠진 변형 파일이 특히 위험.
- 커밋 메시지에 작은따옴표(`'`)가 포함되면 `git commit -m '...'`이 깨진다. HEREDOC이 안전.
- `git diff`만 보면 staged 변경을 놓친다. `git diff HEAD`로 staged + unstaged 모두 확인.
- PR에서 최신 커밋만 분석하면 이전 커밋의 맥락이 누락된다. `git log base..HEAD` 전체를 읽어야 정확한 PR 설명이 된다.
- main에 직접 커밋 후 force-push하면 다른 사람의 작업을 덮어쓴다. main에서 작업 중이면 커밋 전에 브랜치 분리를 제안.
- Co-Authored-By를 무조건 붙이면 프로젝트 컨벤션과 충돌할 수 있다. 기존 커밋에 어트리뷰션 패턴이 있는지 먼저 확인.
