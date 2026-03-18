# Skill 작성 가이드

> 최종 갱신: 2026-03-18
> 소스: agentskills.io spec, Anthropic docs, skill-creator 스킬, Vercel engineering blog

## 1. SKILL.md 스펙

### Frontmatter (필수/선택)

```yaml
---
name: my-skill                    # 필수. kebab-case, 1-64자, 디렉토리명과 일치
description: "설명"                # 필수. 1-1024자, < > 사용 불가
license: MIT                      # 선택
compatibility: "requires Bash"    # 선택. 환경 요구사항 (max 500자)
metadata:                         # 선택. 임의 key-value (string only)
  author: "name"
  version: "1.0.0"
  internal: true                  # true면 기본 검색에서 숨김
mode: true                        # 선택. true면 Mode Commands 섹션에 표시
disable-model-invocation: true    # 선택. true면 슬래시 커맨드로만 트리거 (모델 자동 호출 차단)
user-invocable: false             # 선택. false면 에이전트만 호출 가능 (UI only, 모델 차단 보장 안 됨)
---
```

### 본문 (Markdown)

- 에이전트가 따를 지시사항, 워크플로우, 가이드라인
- 섹션 구성은 자유 (When to Use, Steps, Examples 등)
- 코드보다 markdown 위주

---

## 2. Description 작성 — 트리거의 핵심

description은 에이전트가 스킬 활성화를 결정하는 **유일한 기준**.

**현재 문제**: 에이전트는 스킬을 "언더트리거"하는 경향이 있음 — 유용한 상황에서도 스킬을 사용하지 않음.

**권장 패턴**:
- 스킬이 하는 일 + **구체적 트리거 컨텍스트** 모두 포함
- 약간 "pushy"하게 작성 — 관련될 수 있는 상황을 넓게 명시
- 추상적 설명 대신 사용자가 실제 말할 법한 문구 포함

```yaml
# Bad
description: "PDF 처리 도구"

# Good
description: >
  PDF 파일 읽기, 편집, 병합, 분할, 양식 채우기, OCR 등 모든 PDF 작업.
  사용자가 .pdf 파일을 언급하거나, 문서 변환, 텍스트 추출, 양식 작성을
  요청할 때 반드시 이 스킬을 사용할 것. "이 문서 열어줘"처럼
  파일 타입을 명시하지 않더라도 PDF가 관련될 수 있으면 트리거.
```

---

## 3. Progressive Disclosure (3단계 로딩)

토큰 효율성의 핵심 메커니즘.

| 단계 | 로드 시점 | 내용 | 크기 권장 |
|------|----------|------|----------|
| 1. Metadata | 항상 (에이전트 시작 시) | name + description | ~100 단어 |
| 2. SKILL.md body | 스킬 트리거 시 | 지시사항, 워크플로우 | < 500줄 |
| 3. Bundled resources | 명시적 필요 시 | scripts/, references/, assets/ | 무제한 |

**핵심 규칙**:
- SKILL.md는 500줄 이내 유지
- 500줄 초과 시 references/로 분리 + 명확한 포인터 제공
- 300줄 초과 참조 파일에는 목차 포함
- scripts/는 로딩 없이 실행 가능 — 컨텍스트 소비 없음

---

## 4. 디렉토리 구조

### 기본 구조

```
skill-name/
├── SKILL.md          # 필수. 에이전트 지시사항
├── scripts/          # 선택. 결정적/반복 작업용 실행 코드
├── references/       # 선택. 필요 시 컨텍스트에 로드되는 문서
├── assets/           # 선택. 출력에 사용되는 파일 (템플릿, 아이콘, 폰트)
├── templates/        # 선택. 보일러플레이트, 리포트 템플릿
├── rules/            # 선택. 개별 규칙 파일 (vercel 패턴)
├── command/          # 선택. 슬래시 커맨드 정의
└── evals/            # 선택. 테스트 케이스 (evals.json)
```

### 패턴별 예시

**단순 Skill (파일 1개)**

```
skill-name/
└── SKILL.md
```

**참조 포함 Skill**

```
skill-name/
├── SKILL.md
├── references/          # 상세 가이드, 의사결정 트리
├── resources/           # 실행 스크립트 (shell)
└── templates/           # 보일러플레이트, 리포트 템플릿
```

**규칙 기반 Skill (rules 패턴)**

```
skill-name/
├── SKILL.md             # 루트 디스패처 + 요약
├── AGENTS.md            # 범용 에이전트 지시 (전체 규칙 인라인)
└── rules/               # 개별 규칙 파일 (주제별 .md)
```

- `SKILL.md`는 규칙 요약 + 참조 방식, `AGENTS.md`는 전체 규칙을 인라인

**커맨드 포함 Skill**

```
skill-name/
├── SKILL.md
├── command/             # 슬래시 커맨드 정의 (.md)
└── references/          # 참조 문서 (하위 디렉토리 포함)
```

**도메인별 분기 패턴**

멀티 도메인 스킬은 변형별로 참조 파일 분리:

```
cloud-deploy/
├── SKILL.md              # 워크플로우 + 선택 로직
└── references/
    ├── aws.md            # AWS 전용 가이드
    ├── gcp.md            # GCP 전용 가이드
    └── azure.md          # Azure 전용 가이드
```

에이전트는 관련 파일만 읽음 → 토큰 절약.

**복합 플러그인 (서브 skill 포함)**

```
skill-name/
├── SKILL.md             # 루트 (디스패처/라우터 역할)
├── skills/              # 서브 skill 디렉토리
│   ├── sub-skill-a/
│   │   ├── SKILL.md
│   │   └── references/
│   └── sub-skill-b/
│       └── SKILL.md
├── references/          # 공유 참조 문서
├── hooks/               # 이벤트 훅 (hooks.json + 스크립트)
├── commands/            # 슬래시 커맨드 (.md)
├── agents/              # 서브에이전트 정의 (.md)
└── .claude-plugin/      # 플러그인 매니페스트
    ├── plugin.json
    └── marketplace.json
```

> 깊이는 최대 3단계까지 허용 (예: `models/deploy-model/preset/SKILL.md`).

---

## 5. 작성 패턴

### 명령형 사용

```markdown
# Good
Run the test suite before committing.
Save outputs to the workspace directory.

# Bad
You should run the test suite.
It would be good to save outputs.
```

### 출력 포맷 정의

```markdown
## Report structure
ALWAYS use this exact template:
# [Title]
## Executive summary
## Key findings
## Recommendations
```

### 예시 패턴

```markdown
## Commit message format
**Example 1:**
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

### "왜"를 설명

ALWAYS/NEVER 대문자보다 **이유 설명**이 더 효과적:

```markdown
# Bad
ALWAYS validate input before processing. NEVER skip validation.

# Good
Validate input before processing — unvalidated user data has caused
silent corruption in production, where bad values propagated through
three downstream services before detection.
```

---

## 6. AGENTS.md vs Skills — 언제 무엇을

Vercel 자체 eval 결과: AGENTS.md(정적 push)가 범용 프레임워크 지식에는 더 효과적.

| 용도 | 권장 방식 |
|------|----------|
| 프레임워크/라이브러리 범용 가이드 | AGENTS.md (수평적, 항상 컨텍스트에 존재) |
| 특정 액션 워크플로우 | Skills (수직적, 사용자가 명시적 트리거) |
| 코딩 컨벤션, 린트 규칙 | AGENTS.md 또는 rules/ |
| 배포, 테스트, 디버깅 절차 | Skills |

둘은 **상호 보완적** — 배타적 선택이 아님.

---

## 7. 멀티 에이전트 지원 파일 규칙

| 파일 | 대상 에이전트 | 용도 |
|------|-------------|------|
| `SKILL.md` | Claude Code | 스킬 정의 (frontmatter + 지시) |
| `CLAUDE.md` | Claude Code | 추가 프로젝트 지시 |
| `AGENTS.md` | Cursor, Cline 등 범용 | 전체 규칙 인라인 (SKILL.md 참조 방식과 다름) |
| `GEMINI.md` | Gemini CLI | 도구 매핑 등 |
| `.codex/` | Codex | 설치/설정 지시 |
| `.cursor-plugin/` | Cursor | 플러그인 매니페스트 |
| `.opencode/` | OpenCode | 설정 |

---

## 8. Skill 생성 워크플로우 (skill-creator 기반)

### 코어 루프

```
의도 파악 → 초안 작성 → 테스트 프롬프트 실행 → 사용자 평가 → 개선 → 반복
```

### 단계별

1. **의도 파악**: 스킬이 무엇을 해야 하는지, 언제 트리거해야 하는지, 예상 출력 포맷
2. **인터뷰**: 엣지 케이스, 입출력 포맷, 성공 기준, 의존성 확인
3. **초안 작성**: SKILL.md + 필요한 bundled resources
4. **테스트**: 2-3개 현실적 프롬프트로 with-skill / without-skill 비교 실행
5. **평가**: 정성적 (사용자 리뷰) + 정량적 (assertion grading)
6. **개선**: 피드백 기반으로 수정, 일반화 (overfitting 주의)
7. **반복**: 만족할 때까지

### 개선 원칙

- **일반화**: 테스트 케이스에만 맞추지 말고 범용적으로
- **간결하게**: 효과 없는 부분 제거
- **반복 작업 번들링**: 테스트 중 모든 서브에이전트가 같은 스크립트를 작성했다면 scripts/에 번들
- **이유 설명**: 무거운 MUST 대신 왜 중요한지 설명

---

## 9. Description 최적화 (trigger eval)

스킬 완성 후 description 트리거 정확도 최적화.

### 프로세스

1. **Eval 쿼리 생성**: should-trigger 8-10개 + should-not-trigger 8-10개
2. **사용자 리뷰**: eval 세트 확인/수정
3. **최적화 루프**: `scripts/run_loop.py`로 자동 반복 (train 60% / test 40% 분리)
4. **결과 적용**: best_description을 frontmatter에 반영

### Eval 쿼리 작성 기준

**Should-trigger** (좋은 예):
```
ok so my boss just sent me this xlsx file (its in my downloads, called
something like 'Q4 sales final FINAL v2.xlsx') and she wants me to add
a column that shows the profit margin as a percentage.
```

**Should-not-trigger** (좋은 예 = near-miss):
- 키워드가 겹치지만 실제로는 다른 도구가 필요한 쿼리
- 인접 도메인의 모호한 요청

**나쁜 예**: `"Format this data"` (너무 추상적), `"Write fibonacci"` (너무 무관)

### 트리거 메커니즘 이해

에이전트는 `available_skills` 리스트에서 name+description만 보고 판단.
**단순한 1-step 쿼리**는 스킬 없이 직접 처리하려는 경향 → eval 쿼리는 충분히 복잡해야 함.

---

## 10. 설치 및 검색 메커니즘

### 설치 명령

```bash
npx skills add owner/repo              # GitHub shorthand
npx skills add https://github.com/...  # Full URL
npx skills add ./local-path            # 로컬 경로
```

### Skill 검색 우선순위

1. 대상 경로에 `SKILL.md`가 바로 있으면 반환
2. 우선 디렉토리 탐색:
   - `skills/`, `skills/.curated/`, `skills/.experimental/`
   - `.agents/skills/`, `.claude/skills/`, `.cursor/skills/`
   - `.claude-plugin/marketplace.json` 또는 `plugin.json`에 선언된 경로
3. Fallback: 최대 5단계 재귀 탐색

### 설치 위치

| 범위 | 경로 | 용도 |
|------|------|------|
| 프로젝트 | `./<agent>/skills/` | 레포에 커밋, 팀 공유 |
| 글로벌 | `~/.agents/skills/` | 사용자 전체 프로젝트 |

### Lock 파일 (`~/.agents/.skill-lock.json`)

```json
{
  "version": 3,
  "skills": {
    "skill-key": {
      "source": "owner/repo",
      "sourceType": "github",
      "sourceUrl": "https://github.com/...",
      "skillPath": "path/to/SKILL.md",
      "skillFolderHash": "git-tree-sha",
      "installedAt": "ISO-8601",
      "updatedAt": "ISO-8601"
    }
  }
}
```

- `skillFolderHash`로 업데이트 감지 (GitHub Trees API SHA 비교)

---

## 11. 플러그인 매니페스트

복합 레포에서 skill 위치를 명시적으로 선언할 때 사용.

### `.claude-plugin/plugin.json` (단일)

```json
{
  "name": "superpowers",
  "description": "Core skills library...",
  "version": "5.0.2",
  "author": { "name": "...", "email": "..." },
  "homepage": "https://github.com/...",
  "repository": "https://github.com/...",
  "license": "MIT",
  "keywords": ["skills", "tdd"]
}
```

### `.claude-plugin/marketplace.json` (멀티)

```json
{
  "name": "plugin-dev",
  "description": "...",
  "owner": { "name": "...", "email": "..." },
  "plugins": [
    {
      "name": "plugin-name",
      "description": "...",
      "version": "1.0.0",
      "source": "./"
    }
  ]
}
```

> 모든 경로는 `./`로 시작해야 함. `../` traversal 차단.

---

## 12. CLI 명령어 (`npx skills`)

| 명령 | 설명 |
|------|------|
| `npx skills add owner/repo` | GitHub 레포에서 설치 |
| `npx skills add owner/repo --skill name` | 특정 스킬만 설치 |
| `npx skills add owner/repo --all` | 전체 설치 |
| `npx skills list` / `ls` | 설치된 스킬 목록 |
| `npx skills ls -a claude-code -a cursor` | 에이전트별 필터 |
| `npx skills find [keyword]` | 스킬 검색 |
| `npx skills init [name]` | 새 SKILL.md 생성 |
| `npx skills check` | 업데이트 확인 |
| `npx skills update` | 전체 업데이트 |
| `npx skills remove` | 인터랙티브 삭제 |

- `-g`: 글로벌(사용자 레벨) 설치
- `-y`: 확인 프롬프트 스킵
- 항상 `npx` 사용 (글로벌 설치 불필요, 최신 버전 보장)

---

## 13. 컬렉션 레포 요건

`npx skills add owner/repo`로 설치 가능하려면:

1. 레포 내에 `skills/` 디렉토리 존재
2. 각 skill 디렉토리에 `SKILL.md` 파일 존재 (올바른 frontmatter)
3. (선택) `.claude-plugin/plugin.json`으로 skill 경로 명시
4. (선택) 루트 `SKILL.md`로 레포 전체를 단일 skill로 제공

---

## 14. 생태계 참조

| 리소스 | URL | 설명 |
|--------|-----|------|
| 공식 스펙 | agentskills.io/specification | SKILL.md 포맷 정의 |
| Skills CLI | github.com/vercel-labs/skills | 패키지 매니저 소스 |
| Vercel 공식 스킬 | github.com/vercel-labs/agent-skills | 큐레이션 스킬 컬렉션 |
| Anthropic 공식 스킬 | github.com/anthropics/skills | skill-creator 포함 |
| Skills 디렉토리 | skills.sh | 83,000+ 스킬, 8M+ 설치 |
| Awesome 목록 | github.com/VoltAgent/awesome-agent-skills | 500+ 스킬 |
| Anthropic 가이드 | platform.claude.com/docs/en/agents-and-tools/agent-skills | 공식 문서 |
