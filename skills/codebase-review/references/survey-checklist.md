# 정찰 체크리스트 (맵핑 단계)

전체를 읽기 전에 구조를 값싸게 파악하기 위한 병렬 정찰 항목.
LLM 재추론이 아니라 결정적 명령(파일 존재·numstat·경로 패턴)으로 한 번에 수집한다.

## Phase 1: Reconnaissance

- **매니페스트**: `package.json`, `Cargo.toml`, `go.mod`, `pom.xml`, `pyproject.toml`, `Gemfile` 등 → 언어·의존성·스크립트.
- **프레임워크 지문**: 설정 파일(`next.config`, `vite.config`, `tsconfig`, `Dockerfile`, CI yaml)로 스택 식별.
- **엔트리포인트**: `main`, `index`, `app`, `cmd/`, `bin/`, 서버 부트스트랩.
- **디렉토리 스냅샷**: top-level 레이아웃과 모듈 경계. 어디에 무엇이 사는지.
- **툴링**: 린터·포매터·테스트 러너 설정 → "린터가 잡을 것"을 리뷰에서 제외할 근거.
- **테스트 구조**: 테스트 디렉토리·명명·커버리지 설정.

## Phase 1.5: 비파괴 분석 도구 실행

수동 읽기 전에 스택에 맞는 read-only 도구를 돌려 발견의 근거를 확보하고, 도구가 이미 잡는 것은 리뷰에서 뺀다. 근거를 도구 출력으로 뒷받침하면 오탐이 줄고 신뢰가 오른다.

- **타입/린트**: `tsc --noEmit`, `ruff`/`mypy`, `go vet`, `cargo clippy` 등 → 견고성·가독성 축 근거. 린터·타입체커가 잡는 것은 발견으로 올리지 않는다(`false-positives.md`).
- **공급망**: `npm audit`/`pnpm audit`, `pip-audit`, `cargo audit`, lock 파일 신선도, 라이선스 충돌 → 보안 축 근거. 별도 축으로 만들지 말고 보안 축에 흡수한다.
- **dead code**: `knip`/`ts-prune`/`depcheck`, `vulture`, `cargo-udeps` → 리팩토링 축 후보. 단 동적 참조 오탐에 주의(`false-positives.md`의 dead-code 게이트).
- 도구가 없거나 실패하면 그 사실을 Coverage에 남기고 수동 근거로 대체한다. 도구 부재를 이유로 그 영역을 조용히 건너뛰지 않는다.

## Phase 2: 핫스팟 식별

전수 읽기 대신 위험도 높은 곳부터 본다. 핫스팟 신호:

```bash
# 변경 빈도 (churn) — 자주 바뀌는 파일일수록 결함·복잡도 집중
git log --format=format: --name-only | sort | uniq -c | sort -rn | head -20

# 최근 변경 범위
git diff --stat HEAD~20..HEAD 2>/dev/null

# 파일 크기 (큰 파일 = 복잡도·책임 과다 후보)
```

- 변경 빈도(churn) 높은 파일
- 파일 크기·복잡도 큰 파일
- 의존성이 몰리는 지점 (많은 곳에서 import)
- 진입점·신뢰 경계 (외부 입력이 들어오는 곳)

churn·소유권 공백 기반 정량 진단이 더 필요하면 `git-diagnosis` 스킬로 넘긴다.
이 단계의 목적은 "어느 파일을 깊게 볼지" 우선순위를 정하는 것이다.

## 축 선택 (스택 기반)

8개 축을 기계적으로 다 돌리지 않는다. Survey에서 감지한 스택으로 무관한 축을 뺀다:

- frontend 코드 없음 → UI/렌더링 관련 점검 생략.
- DB·쿼리 계층 없음 → N+1·쿼리 성능 점검 생략.
- 순수 라이브러리(진입점·신뢰 경계 없음) → 외부 입력 보안 점검 축소.

무관 축을 빼는 것은 cost-over-taste에 부합한다. 뺀 축은 Coverage에 "해당 없음"으로 명시한다.

## 규모 기반 깊이 스케일링

맵핑 결과로 리뷰 깊이를 조절해 예산을 관리한다:

- **소규모** (파일 수십 개): 단일 패스로 전 축을 한 세션에서.
- **중규모**: 핫스팟 상위 집합에 축별 점검 집중.
- **대형**: 축별 서브에이전트 병렬 dispatch(가능 환경). 핫스팟만 깊게, 나머지는 얕게 훑고 "미심층 영역"을 Coverage에 명시.

불확실하면 얕게 훑지 말고 full로 간다(fail-closed). 대신 안 본 영역을 반드시 보고한다.
