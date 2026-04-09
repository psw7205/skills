# Repository Guidelines

custom-skills 레포 작업 시 레포 파일만 수정. 로컬 설치 경로(~/.claude/skills/ 등)에 cp, 동기화, 직접 수정 금지. 설치/배포는 사용자가 관리.


## 프로젝트 구조

이 레포는 스킬 컬렉션이며 애플리케이션이 아니다. 변경은 해당 스킬 또는 문서 범위 내로 제한.

- `skills/<skill-name>/SKILL.md`: 스킬당 하나의 디렉토리. 핵심 소스 파일.
- `skills/<skill-name>/references/`: 스킬에 참고 문서가 필요할 때 사용.
- `skills/<skill-name>/scripts/`: 스킬이 런타임에 호출하는 셸 스크립트.
- `.claude-plugin/marketplace.json`: `npx skills add`에서 스킬 분류를 제어하는 매니페스트. 새 스킬은 반드시 `skills` 배열에 등록.
- `docs/`: 스킬 빌딩 참고 자료 및 플랜 아카이브.
- `.claude/settings.local.json`: 로컬 에이전트/에디터 설정. 공유 동작에 의존하지 말 것.

등록된 스킬 목록은 `.claude-plugin/marketplace.json`의 `skills` 배열을 참조한다. `setup-hooks` 스킬은 guard-untracked 훅을 `~/.claude/settings.json`에 설치/제거한다. 이 훅은 `git clean`, `git checkout .`, `git reset --hard`, `git restore .` 실행 전 auto-stash를 삽입하고, `git push --force`는 deny한다. 참고 파일이나 스크립트가 필요한 경우가 아니면 얕은 구조를 유지.

## 빌드, 테스트, 개발 명령어

이 레포에 빌드 파이프라인이나 자동화 테스트 스위트는 없다. 레포 루트에서 경량 검사 명령어를 사용:

```bash
find skills -maxdepth 2 -name SKILL.md | sort
rg -n '^name:|^description:' skills/*/SKILL.md
sed -n '1,120p' skills/<skill-name>/SKILL.md
git status --short
```

- `find ...`: 모든 스킬 엔트리 포인트 나열.
- `rg ...`: 필수 frontmatter 필드 확인.
- `sed ...`: 에디터 없이 스킬 빠르게 검사.
- `git status --short`: 의도한 파일만 변경되었는지 확인.

`skills` CLI가 로컬에 있으면 `npx skills add ./`로 스모크 테스트.

## 코딩 스타일 및 네이밍

간결한 마크다운으로 작성. 명령형 문체. ATX 헤딩(`#`, `##`) 사용. 예시는 최소화.

- 파일이 이미 한국어를 쓰고 있지 않으면 ASCII 우선.
- 스킬 디렉토리와 이름은 소문자 kebab-case. 예: `trace-change-why`.
- frontmatter는 최소화: `name`, `description`, 필수 메타데이터만.
- 코드 블록은 용법이나 명령어를 명확히 할 때만 추가.

## 테스트 가이드라인

검증은 수동:

- frontmatter가 파싱되고 필수 필드가 존재하는지 확인.
- 파일 경로와 명령어가 실제 레포와 일치하는지 검증.
- 스킬 전체를 다시 읽어 트리거 명확성과 모순 확인.
- 가능하면 `npx skills add ./` 실행.

## 커밋 및 PR 가이드라인

커밋 제목은 한국어 명령형으로 짧게. 예: `video-subtitle-dl 스킬 추가 및 관련 문서 정리`.

PR은 범위를 좁게 유지. 짧은 요약, 영향 경로, 수행한 수동 검증, 동작 변경 시 트리거 문구 샘플 포함.
