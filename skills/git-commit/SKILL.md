---
name: git-commit
description: >
  "커밋 만들어", "커밋해줘", "commit", "PR 만들어", "PR 올려줘",
  "push하고 PR", "create PR", "변경사항 커밋", "코드 올려줘",
  "커밋 메시지 어떻게 쓰지", "commit and push", "make a commit",
  "create a pull request"
  등에서 트리거.
  기존 커밋 스타일 일관성, 시크릿 파일 가드, main/master 직접 커밋 방지를 보강한다.
---

# Git Commit

Claude 기본 커밋/PR 워크플로우에 추가되는 가드레일.

## 기존 스타일 일관성

커밋 메시지 작성 전 반드시 기존 스타일을 분석한다:

```bash
git log --oneline -10
```

최근 커밋의 패턴(prefix, 언어, 길이, 형식)을 파악하고 일관성을 유지한다. 자기 스타일을 강요하지 않는다.

## 시크릿 파일 가드

스테이징 전 다음 패턴의 파일이 포함되지 않는지 확인:

- `.env`, `.env.*`
- `credentials.*`, `*secret*`, `*.pem`, `*.key`
- `*token*`, `*password*` (설정/시크릿 파일인 경우)

시크릿 파일이 변경 목록에 있으면 스테이징하지 말고 사용자에게 알린다.

## main/master 직접 커밋 방지

현재 브랜치가 main/master이면 커밋 전에 브랜치 분리를 제안한다. 사용자 확인 없이 브랜치를 만들지 않는다.

## Gotchas

- `git add .`은 `.gitignore`에 없는 시크릿 파일을 포함시킨다. `.env.local`처럼 gitignore에 빠진 변형 파일이 특히 위험.
- Co-Authored-By를 무조건 붙이면 프로젝트 컨벤션과 충돌할 수 있다. 기존 커밋에 어트리뷰션 패턴이 있는지 먼저 확인.
- main에 직접 커밋 후 force-push하면 다른 사람의 작업을 덮어쓴다.
