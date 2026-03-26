# npx skills CLI 가이드

> Vercel이 개발한 오픈 에이전트 스킬 패키지 매니저 (v1.4.5)
>
> - CLI 본체: [vercel-labs/skills](https://github.com/vercel-labs/skills)
> - 스킬 컬렉션: [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills)
> - 스킬 디스커버리: https://skills.sh/

## 설치 범위

| 범위 | 저장 경로 | 설명 |
|------|----------|------|
| project (기본) | `./<agent>/skills/` | 현재 프로젝트에만 적용 |
| global (`-g`) | `~/.agents/skills/` | 모든 프로젝트에 적용 |

## 커맨드

### 스킬 관리

```
skills add <package>              # 스킬 패키지 추가
skills remove [skills]            # 스킬 제거 (인자 없으면 인터랙티브)
skills list                       # 설치된 스킬 목록
skills find [query]               # 스킬 검색 (인자 없으면 인터랙티브)
```

### 업데이트

```
skills check                      # 업데이트 가능 여부 확인
skills update                     # 전체 스킬 최신 버전으로 업데이트
```

### 프로젝트

```
skills init [name]                # SKILL.md 스캐폴딩 생성
skills experimental_install       # skills-lock.json으로부터 복원
skills experimental_sync          # node_modules의 스킬을 에이전트 디렉토리로 동기화
```

## 주요 옵션

### add / remove 공통

| 옵션 | 설명 |
|------|------|
| `-g, --global` | 글로벌 스코프에 설치/제거 |
| `-a, --agent <agents>` | 특정 에이전트 지정 (`'*'`로 전체) |
| `-s, --skill <skills>` | 특정 스킬만 선택 (`'*'`로 전체) |
| `-y, --yes` | 확인 프롬프트 스킵 |
| `--all` | `--skill '*' --agent '*' -y`의 축약 |

### add 전용

| 옵션 | 설명 |
|------|------|
| `-l, --list` | 설치 없이 레포의 스킬 목록만 출력 |
| `--copy` | 심볼릭 링크 대신 파일 복사 |
| `--full-depth` | 루트 SKILL.md가 있어도 하위 디렉토리 전체 탐색 |

### list 전용

| 옵션 | 설명 |
|------|------|
| `--json` | JSON 형식 출력 |

## 사용 패턴

### 특정 스킬만 골라서 글로벌 설치

```
skills add vercel-labs/agent-skills -g --skill pr-review commit
```

### 레포에 어떤 스킬이 있는지 확인만

```
skills add vercel-labs/agent-skills --list
```

### 특정 에이전트에만 설치

```
skills add vercel-labs/agent-skills --agent claude-code cursor
```

### 전체 스킬을 전체 에이전트에 무확인 설치

```
skills add vercel-labs/agent-skills --all
```

### JSON으로 설치 현황 파악

```
skills list --json          # 프로젝트
skills list -g --json       # 글로벌
```

## `<package>` 형식

`add` 커맨드의 패키지 인자는 다음 형식을 지원한다:

- GitHub shorthand: `vercel-labs/agent-skills`
- Full URL: `https://github.com/vercel-labs/agent-skills`
