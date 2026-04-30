# Self-Feedback Loop — 출력 포맷

각 cycle과 최종 결과의 상세 출력 템플릿.

## Cycle 출력

````markdown
## Cycle {N} Review

### Findings

| # | Severity | File:Line | Issue | Expected |
|---|----------|-----------|-------|----------|
| 1 | critical | `src/service/order.ts:42` | race condition on concurrent writes | mutex or DB-level lock |
| 2 | high | `src/worker/sync.ts:15` | async contract mismatch with caller | return job ID, not result |

### Fixes

- **Finding 1**: `src/service/order.ts:42` — added row-level lock
- **Finding 2**: `src/worker/sync.ts:15` — caller now receives job ID, polls for result

### Verification

```
$ {test command} -- {targeted filter}
# 예: pnpm test -- --testPathPattern="order|sync"
Tests: 12 passed, 12 total
```

### Commit

```
abc1234 fix(service): add row-level lock to prevent concurrent write race
def5678 fix(worker): align async contract between caller and worker
```
````

## Final 출력

````markdown
## Final Review

Material findings: **none** (연속 2회 clean)

## Full Verification

```
$ {test command}
# 예: pnpm test
Tests: 148 passed, 148 total
```

## Residual Risks

- (없으면 "None identified" 로 명시)
- (있으면 구체적으로: "X 시나리오에서 Y가 발생할 수 있으나 현재 test로 커버 불가 — 수동 QA 권장")

## Notes (개선 / 범위 밖 — 자동 수정 안 함)

cycle 동안 누적한 항목을 한 번에 보고. 없으면 "없음".

- `src/foo/bar.ts:88` — handler가 3중 nested. 후속 plan 후보 (이번 변경 범위 밖)
- `docs/setup.md` — 새 env var 언급 누락. 즉시 깨지지 않아 Notes 처리
- design: queue 재시도 정책이 caller마다 다름 — 통합 검토 필요
````

## 빈 Cycle (no findings)

finding이 없는 cycle은 간략하게:

```markdown
## Cycle {N} Review

Findings: **none**

Checked: diff (N files), tests (N passing), docs (aligned), plan status (all checked items verified)

→ 종료 조건 충족 여부: {예/아니오 + 사유}
```
