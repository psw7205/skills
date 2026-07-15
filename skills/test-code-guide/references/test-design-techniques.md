# Test Design Techniques — 무엇을 테스트할지

테스트 케이스를 도출하는 기법 카탈로그. 기법 이름은 ISTQB 표준 용어를 쓰고, 각 기법에 coverage 기준을 명시한다.
출처: ISTQB CTFL v4.0.1 ch4, CTAL-TA v4.0 ch3, CTAL-TTA v4.0 ch2, CTFL v4.0.1 ch5(레벨 배분).

목차:

1. 기법 선택 결정 트리
2. Data-based 기법 (EP, BVA, combinatorial)
3. Behavior-based 기법 (state transition, CRUD, scenario)
4. Rule-based 기법 (decision table)
5. Oracle이 없을 때 (property-based, metamorphic)
6. 화이트박스 보완 (coverage 기준과 subsumption)
7. 레벨 배분 (pyramid, quadrants)
8. 케이스 작성 순서

## 1. 기법 선택 결정 트리

기법은 "어떤 결함을 잡으려는가"로 고른다. 결함 가설 없이 기법부터 고르지 않는다.

| 결함 가설 | 기법 | 대표 상황 |
|---|---|---|
| 입력 범위·경계 처리 오류 | EP + BVA | 검증 로직, 수치 계산, 페이징 |
| 파라미터 조합에서만 터지는 오류 | combinatorial (pairwise) | 설정 조합, 플래그 조합, 환경 매트릭스 |
| 상태·순서에 따른 오류 | state transition | 세션, 주문/결제 흐름, 상태 머신 |
| entity 수명주기 누락 | CRUD testing | 리소스 생성~삭제, soft-delete 도메인 |
| 흐름 단절·통합 오류 | scenario 기반 | E2E 사용자 여정, use case |
| 조건 조합 규칙의 누락·모순 | decision table | 요금/권한/할인 정책, 비즈니스 규칙 |
| 기대값을 계산할 수 없음 | property-based / metamorphic | 검색 랭킹, AI 출력, 복잡 변환 |
| 명세가 없거나 낡음 | exploratory + 화이트박스 보완 | 레거시, 문서 없는 모듈 |

여러 가설이 걸리면 기법을 결합한다. 예: state transition의 guard 조건에 BVA, scenario 안의 규칙 분기에 decision table.

## 2. Data-based 기법

### Equivalence Partitioning (EP)

입력(또는 출력)을 "동일하게 처리될 값의 집합"으로 나누고 partition당 1개 값만 테스트한다.
같은 partition의 한 값이 결함을 찾으면 다른 값도 찾는다 — 같은 partition에서 여러 값을 테스트하는 것은 중복이다.

- valid partition과 invalid partition을 모두 나눈다. invalid는 한 테스트에 하나씩만 넣는다(결함 masking 방지).
- coverage: 모든 partition을 최소 1회. 다중 파라미터면 각 파라미터의 각 partition을 최소 1회(Each Choice).

### Boundary Value Analysis (BVA)

정렬 가능한 partition의 경계를 테스트한다. 개발자는 경계에서 실수한다(`<`를 `<=`로 등).

- **2-value**: 경계값 + 반대편 인접값. 기본 선택.
- **3-value**: 경계값 + 양쪽 인접값. `x <= 10`을 `x == 10`으로 잘못 구현한 결함은 3-value(x=9)만 잡는다. 위험도 높은 로직에 사용.

### Combinatorial (조합 축소)

전 조합(각 파라미터 값 수의 곱)은 감당이 안 되므로 축소 기준을 고른다. 실증 연구 기준 실패의 대부분은 1~2개 파라미터 상호작용에서 발생한다 — pairwise가 효율적인 이유.

- **base choice**: 대표 조합 1개를 기준으로 파라미터를 하나씩 바꾼다. 조합 수 = 1 + Σ(각 파라미터 값 수 - 1). 단독 파라미터의 영향 확인용 — non-base 값 두 개의 조합은 커버하지 않으므로 상호작용 결함에는 pairwise를 쓴다.
- **pairwise**: 임의 두 파라미터의 모든 값 쌍을 커버. 도구로 생성한다.
- 불가능한 조합(constraint)은 명시하고 제외한다.

## 3. Behavior-based 기법

### State Transition Testing

상태 모델(diagram 또는 table)을 그리고 transition을 커버한다. 모델을 그리는 행위 자체가 명세의 구멍(정의 안 된 전이)을 드러낸다.

- coverage 기준 (약한 순): all states < **valid transitions (0-switch, 기본 선택)** < all transitions(invalid 포함).
- 연속 전이에 걸린 결함이 의심되면 N-switch(연속 N+1개 전이)를 추가한다. N-switch와 all transitions는 서로를 포섭하지 않는 별개 축이다.
- invalid transition(허용 안 되는 전이)은 테스트당 1개만 시도한다. safety/mission-critical은 all transitions가 최소선.

### CRUD Testing

entity별로 Create/Read/Update/Delete 매트릭스를 만든다.

- 정적 점검: 모든 entity에 C·R·U·D가 존재하는가. 누락은 명세 구멍이거나 dead feature.
- 동적 점검: 수명주기 전체를 조합으로 커버 + negative(미생성 entity의 read, 삭제된 entity의 update).

### Scenario 기반

use case나 activity diagram에서 시나리오를 도출한다. main scenario → extension → exception 순.

- loop가 있으면: 0회 / 1회 / 여러 회 / 최대 반복.
- E2E·acceptance 레벨의 기본 기법. 세부 입력 검증은 하위 레벨의 EP/BVA에 맡기고 시나리오는 흐름만 본다.

## 4. Rule-based 기법

### Decision Table Testing

조건 조합 → 결과 규칙을 표로 만든다. 표를 만드는 과정에서 요구사항의 gap과 모순이 드러난다 — 기법의 절반은 defect prevention이다.

- coverage: feasible한 규칙(열) 전부.
- 조건이 많아 표가 커지면 don't care(–) 병합으로 최소화하되, 고위험 로직은 full table을 유지한다.

## 5. Oracle이 없을 때

기대값을 구현과 독립적으로 산출할 수 없으면 assertion이 구현 미러링으로 전락한다. 이 순서로 대안을 찾는다.

1. **독립 계산**: 스펙·수식·외부 기준으로 손 계산한 고정 기대값.
2. **Property-based**: 개별 값 대신 성질을 검증 — 역함수 왕복(encode→decode), 불변량(정렬 후 길이 동일), 멱등성.
3. **Metamorphic relation**: 입력을 바꿨을 때 출력이 어떻게 변해야 하는지를 검증한다. 예: "필터를 추가하면 결과 수는 같거나 줄어야 한다", "입력 순서를 바꿔도 합계는 같아야 한다". random 입력 생성과 결합하면 케이스를 대량 생성할 수 있다.
4. **근거 있는 스냅샷**: 현재 출력을 사람이 검증한 뒤 고정. 검증 없이 "현재 출력 = 정답"으로 만드는 스냅샷은 회귀 감지기일 뿐 정당성 근거가 없다 — 리뷰에서 스냅샷의 최초 검증 근거를 물을 것.

## 6. 화이트박스 보완

블랙박스 기법을 먼저 적용하고, coverage 측정으로 남은 gap에만 화이트박스를 추가한다. 순서를 뒤집으면 구현 미러링이 된다.

- subsumption 계층: statement < branch/decision < MC/DC < multiple condition. 상위 100%는 하위 100%를 포함하므로 기준은 하나만 명시하면 된다.
- 일반 코드는 branch coverage가 실용 기준. MC/DC 이상은 safety-critical 표준(IEC 61508, ISO 26262, DO-178C)이 요구할 때.
- 화이트박스의 한계: 구현 안 된 요구사항(omission defect)은 절대 못 잡는다. 요구사항 기반 케이스를 대체하지 않는다.
- coverage가 100%여도 데이터 의존 결함(특정 값에서만 0 나누기)은 남는다. coverage는 "테스트 안 된 코드"를 찾는 도구지 품질 증명이 아니다.

## 7. 레벨 배분

behavior를 검증할 수 있는 가장 낮은 레벨에 배치한다. 레벨이 오를수록 느리고, 격리가 약해지고, 실패 원인 특정이 어렵다.

- **pyramid는 유연한 모델이다**: 층 명칭·개수는 프로젝트마다 다르다(unit/service/UI, unit/integration/E2E 등). "아래층은 많고 빠르게, 위층은 적고 굵게"라는 비율 원칙만 가져간다.
- **quadrants는 레벨이 아니라 목적 분류다**: 비즈니스/기술 대면 × 팀 지원/제품 비평 축으로 나눈다. 레벨 배분 후 자동화 대상과 탐색·비평 활동이 모두 있는지 점검하는 보완 뷰로 쓴다.
- structural coverage(statement/branch)는 unit·integration 레벨에서 측정한다. 상위 레벨은 requirements/시나리오/risk 기준으로 커버리지를 정의한다.
- unit에서 이미 검증한 로직 조합을 E2E에서 반복하지 않는다. E2E는 통합 지점과 사용자 여정만.
- 배분이 계약·규제로 정해지는 도메인(의료, 차량, 금융)은 해당 표준이 우선한다.

## 8. 케이스 작성 순서

1. **positive 먼저**: 정상 경로가 통과해야 나머지가 의미 있다.
2. **negative**: 잘못된 입력, 권한 없음, 리소스 부재, 예외 경로.
3. **경계·조합**: 선택한 기법의 coverage 기준을 채운다.
4. **non-functional (해당 시)**: 성능·보안이 acceptance criteria에 있으면 해당 레벨에 배치.

케이스 하나는 behavior 하나만 검증한다. 중복 판단 기준은 `automation-quality.md`의 Necessity 항목을 따른다.
