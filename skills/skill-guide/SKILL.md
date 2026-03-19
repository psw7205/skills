---
name: skill-guide
description: >
  이 레포에서 새 스킬을 작성하거나 기존 스킬을 수정할 때 사용하는 가이드.
  "스킬 만들어줘", "새 skill 추가", "SKILL.md 작성", "스킬 구조",
  "스킬 수정해줘", "스킬 가이드", "description 다듬기",
  "frontmatter 작성", "스킬 검증" 등의 요청에서 트리거.
  스킬 스펙(frontmatter, description, Progressive Disclosure),
  디렉토리 구조 패턴, 작성 원칙을 제공한다.
---

# Skill Guide

이 레포에서 스킬을 만들거나 수정할 때 따르는 가이드.
상세 스펙은 `references/guide.md` 참조.

## 이 레포 컨벤션

- 경로: `skills/<kebab-case-name>/SKILL.md`
- 기본은 shallow layout (SKILL.md 단독). 참조 문서가 필요하면 `references/` 추가.
- 한국어 위주, 명령형 톤. 기존 스킬(trace-change-why, session-history)과 톤 일관성 유지.
- README.md 스킬 테이블에 행 추가.

## 작성 체크리스트

### 1. Frontmatter

```yaml
---
name: kebab-case-name # 필수. 디렉토리명과 일치, 1-64자
description: > # 필수. 1-1024자, < > 금지
  스킬이 하는 일 + 구체적 트리거 문구.
  사용자가 실제로 말할 법한 표현 포함.
  "언더트리거" 방지를 위해 약간 pushy하게.
---
```

### 2. Description — 트리거의 핵심

- description은 에이전트가 스킬 활성화를 결정하는 **유일한 기준**
- 스킬 기능 + 트리거 컨텍스트 모두 포함
- 추상적 설명("PDF 도구") 대신 구체적 행동("PDF 읽기, 병합, OCR…")

### 3. 본문 구조

- 스킬 목적 1-2줄 요약
- 절차/워크플로우를 번호 매긴 단계로
- 명령형 사용 ("Run…", "Save…" — "You should…" 금지)
- ALWAYS/NEVER 대신 **이유 설명**
- 출력 포맷이 있으면 템플릿 명시

### 4. 크기 관리 (Progressive Disclosure)

| 단계                  | 로드 시점      | 크기 권장 |
| --------------------- | -------------- | --------- |
| name + description    | 항상           | ~100 단어 |
| SKILL.md 본문         | 트리거 시      | < 500줄   |
| references/, scripts/ | 명시적 필요 시 | 무제한    |

- 500줄 초과 → `references/`로 분리
- 300줄 초과 참조 파일 → 목차 포함
- `scripts/`는 실행만 되고 컨텍스트 소비 없음

### 5. 디렉토리 구조 패턴

| 패턴          | 구조                                                        |
| ------------- | ----------------------------------------------------------- |
| 단순          | `SKILL.md` 단독                                             |
| 참조 포함     | `SKILL.md` + `references/`                                  |
| 규칙 기반     | `SKILL.md` + `AGENTS.md` + `rules/`                         |
| 커맨드 포함   | `SKILL.md` + `command/`                                     |
| 도메인 분기   | `SKILL.md` + `references/{domain}.md`                       |
| 복합 플러그인 | `SKILL.md` + `skills/` + `hooks/` + `commands/` + `agents/` |

### 6. 검증

- frontmatter 파싱: `rg -n '^name:|^description:' skills/<name>/SKILL.md`
- 설치 테스트: `npx skills add ./`
- 트리거 확인: 2-3개 현실적 프롬프트로 스킬이 활성화되는지 확인

## 상세 참조

다음 항목의 상세 스펙은 `references/guide.md` 참조:

- Frontmatter 전체 필드 (선택 필드 포함)
- Description 최적화 (trigger eval 프로세스)
- AGENTS.md vs Skills 사용 기준
- Skill 생성 워크플로우 (skill-creator 코어 루프)
- 설치/검색 메커니즘, 플러그인 매니페스트
- CLI 명령어, 컬렉션 레포 요건
- 멀티 에이전트 지원 파일 규칙
- 생태계 참조 링크
