---
name: self-feedback-loop
description: >
  구현 결과에 대해 review-fix-verify-commit 루프를 반복 수행하는 스킬.
  plan 기준으로 현재 코드를 검토하고, findings를 severity 순으로 정리하고,
  수정 후 검증하고 커밋하는 사이클을 material finding이 소진될 때까지 반복한다.
  "self-feedback loop 돌려", "피드백 루프 시작", "review fix commit 반복",
  "구현 결과 검토하고 수정해", "코드 리뷰하고 고치고 커밋까지",
  "adversarial review", "self-review", "review session 시작",
  "review loop", "셀프 리뷰", "리뷰 루프", "피드백 루프",
  "구현 검토해줘", "review and fix", "코드 점검하고 수정해줘"
  등에서 트리거.
---

# Self-Feedback Loop

구현 결과를 plan 기준으로 반복 검토하여 품질을 끌어올리는 review-fix-verify-commit 루프.

## 모드 선언

이 스킬이 활성되면 아래 모드로 전환한다:

- **review-only 세션이다.** 새 기능 추가, 범위 확장, 설계 재논의를 하지 않는다.
- **plan이 기준이다.** plan에 없는 개선은 하지 않는다. plan이나 AGENTS.md에 out-of-scope로 명시된 항목을 미구현이라고 지적하지 않는다.
- **surgical fix만 한다.** 수정은 finding에 직접 대응하는 범위로 한정한다. 인접 코드 정리, unrelated refactor, 스타일 통일 금지.

## 시작 절차

### 1. 프로젝트 컨텍스트 수집

아래 파일을 찾아 읽는다 (없으면 건너뜀):

- `AGENTS.md` (프로젝트 root) — 코딩 가이드라인, out-of-scope 정의
- `docs/plans/` 하위 최신 plan 파일 — 구현 목표와 체크리스트
- `README.md` — 프로젝트 개요
- operator/feature guide가 있으면 함께 읽는다

### 2. 현재 상태 파악

```bash
git status
git diff --stat
git log --oneline -5
```

변경된 파일 목록에서 구현 파일과 테스트 파일을 식별한다.

### 3. plan 대조

plan의 각 chunk/task와 현재 구현을 대조한다. 체크박스가 체크되어 있는데 실제로 구현이 안 된 항목, 또는 구현은 되어 있는데 체크 안 된 항목을 찾는다.

## 루프 구조

```
review → findings 정리 → fix → targeted verify → commit
  ↑                                                 |
  └─────────── material finding 있으면 반복 ─────────┘
```

### Review

1. plan 체크리스트 vs 실제 코드 정합성
2. 구현 파일을 읽고 로직 결함, 누락된 edge case, 계약 불일치를 찾는다
3. 테스트가 happy path만 커버하는지 확인한다
4. docs/guide가 구현 상태와 맞는지 확인한다

### Findings 정리

severity 순으로 정리한다:

| Severity | 기준 | 예시 |
|----------|------|------|
| **critical** | 런타임 에러, 데이터 손실, 보안 결함 | race condition, 미검증 입력 |
| **high** | 기능 오동작, 계약 불일치 | async contract 위반, 잘못된 상태 전이 |
| **medium** | edge case 누락, 불완전한 테스트 | 중복 처리 미흡, 경계값 미검증 |
| **low** | docs 불일치, 사소한 불일관성 | 가이드 문구와 코드 동작 차이 |

각 finding은 **파일:라인 + 구체적 문제 + 기대 동작**으로 기술한다. "~하면 좋겠다" 수준의 모호한 제안은 finding이 아니다.

### Fix

- finding 하나당 하나의 수정 단위. 여러 finding을 한 번에 고쳐도 되지만, 각 수정이 어떤 finding에 대응하는지 추적 가능해야 한다.
- 수정 중 새로운 문제를 발견하면 현재 fix를 완료하고, 다음 cycle의 finding으로 기록한다.

### Verify

수정 범위에 맞는 targeted test를 실행한다. 프로젝트의 test runner를 사용한다 (시작 전 `package.json`, `Makefile`, `Gemfile` 등에서 test 명령을 확인).

### Commit

targeted verification이 green일 때만 커밋한다. 메시지는 해당 cycle의 수정 의도를 드러낸다:
```
fix(scope): 구체적 수정 내용
```

## 종료 조건

- **연속 2회 리뷰에서 material finding(critical/high/medium)이 없으면 종료한다.**
- 최소 1회 full cycle(review → fix → verify → commit)은 반드시 수행한다.
- 종료 전 반드시 **full test suite**를 실행하고 green을 확인한다.
- low severity만 남은 경우 한 번에 모아서 수정하고 종료해도 된다.

## 출력 포맷

각 cycle과 최종 결과를 아래 형식으로 보고한다. 상세 템플릿은 `references/output-format.md` 참조.

```
## Cycle N
- Findings: (severity별 목록)
- Fixes: (파일:라인 단위)
- Verification: (실행 명령 + 결과)
- Commit: (hash + 메시지)

## Final
- Full verification: (명령 + 결과)
- Residual risks: (있으면)
```

## Gotchas

- **Scope creep의 가장 흔한 형태**: "이 finding을 고치려면 관련 테스트도 업데이트해야 하고, 그러면 test helper도..." — finding의 직접 수정 범위를 넘어가면 멈추고 다음 cycle finding으로 분리한다.
- **Targeted test만 돌리다가 final에서 깨지는 패턴**: 수정이 3개 파일 이상에 걸치면 targeted 대신 관련 test suite 전체를 돌리는 게 안전하다.
- **첫 리뷰에서 finding 0개**: plan과 코드를 실제로 라인 단위로 대조했는지 자문한다. finding이 정말 없으면 무리하게 만들지 말되, diff/tests/docs/plan status를 한 번 더 확인한 후에 결론 내린다.
- **Finding severity 과대평가**: cosmetic 이슈를 medium으로 올리면 수정 시간을 낭비한다. "이걸 안 고치면 사용자가 영향을 받는가?"로 판단.
- **Fix 도중 새 버그 도입**: 수정 후 targeted verify를 건너뛰고 싶은 유혹이 있다. 반드시 verify를 거친다 — 1줄 수정이라도.
- **Out-of-scope 오판**: plan에 명시적으로 제외된 항목(auth, UI redesign 등)을 "발견"하고 고치려 하면 review session의 목적을 벗어난다. 시작 시 out-of-scope 목록을 메모하고 매 finding마다 대조한다.
- **커밋 단위가 너무 크거나 작음**: 1 finding = 1 commit이 아니다. 한 cycle의 모든 fix를 하나의 커밋으로 묶되, 성격이 완전히 다른 fix(예: 로직 수정 + docs 수정)는 분리한다.
