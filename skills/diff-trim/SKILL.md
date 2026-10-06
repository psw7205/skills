---
name: diff-trim
description: >
  작업을 끝낸 diff에서 이번 변경이 더한 군살을 찾아 동작 변경 없이 걷어내는 스킬. 코드를
  되풀이하는 주석, 변경 과정을 서술한 주석, 한 곳에서만 쓰는 helper·wrapper·추상화, 계약상
  불가능한 상태 방어, 삼키거나 rethrow만 하는 try/catch, 구현을 복제한 테스트, 요청 밖 구조가
  대상이며 이번 변경이 추가한 hunk만 본다. "diff 다이어트", "diff 줄여", "diff 간결하게",
  "군살 빼", "불필요한 주석 지워", "주석 너무 많아", "과잉 주석 정리", "over-engineering 걷어내",
  "helper 왜 만들었어", "방어 코드 과해", "코드 정리하고 마무리", "커밋 전에 정리",
  "trim the diff", "make this change concise", "clean up this diff", "strip unnecessary comments",
  "simplify this change", "deslop", "remove AI slop" 등에서 트리거. 코딩 작업을 마치고 커밋하기 전
  마지막 점검으로도 쓴다. 결함·리스크를 찾는 리뷰는 diff-review, plan 기준 review-fix 루프는
  self-feedback-loop, 산문의 AI 티는 humanizer가 담당한다.
---

# Diff Trim

이번 변경이 **새로 더한 불필요한 복잡도**만 걷어내는 1회 패스. 기능을 다시 설계하는 2차 refactor가 아니고, 기존 코드의 군살을 청소하는 작업도 아니다.

판정 질문은 하나다: **정확성·가독성·안전성·요청된 동작을 그대로 두고 이 diff가 더 작아질 수 있는가.** "더 작아질 수 있는가"만으로 판정하지 않는다.

## 모드 선언

- **대상은 변경 집합의 추가·수정 hunk다.** 기존 코드에서 군살을 보더라도 건드리지 않고 Notes로 남긴다.
- **동작을 바꾸지 않는다.** 걷어낸 뒤 기존 테스트·타입체크가 그대로 통과해야 한다. 통과를 확인하기 전에는 완료라고 하지 않는다.
- **검사 / 정리 두 모드.** `검사`·`리뷰`·`확인`·`봐줘` 요청은 read-only로 후보 목록만 낸다. `diff-trim`·`다이어트`·`정리`·`걷어내`·`지워`·`마무리`·`커밋 전에` 요청은 적용까지 한다.
- **작게 만드는 것 자체는 목표가 아니다.** validation·security·data-loss 방지·accessibility·의미 있는 error handling·가독성을 줄여서 얻는 diff 축소는 하지 않는다.

## 절차

1. **변경 집합 확정.** `git diff`, `git diff --staged`, `git diff <base>...HEAD`, `gh pr diff <n>` 중 대상에 맞는 것을 고른다. 지시가 없으면 unstaged → staged → 최근 커밋 순으로 추정하고 대상을 한 줄로 밝힌다. `git diff`에 안 보이는 untracked 신규 파일(`git status --short`의 `??`)도 이번 변경이 만든 것이면 대상에 넣고, 변경과 무관한 untracked 파일은 건드리지 않는다. 추가 hunk의 파일 수·라인 수를 잰다.
2. **요청 범위 복원.** 이 변경이 답하는 요청(대화, plan, 이슈)을 한 문장으로 적는다. "요청 밖 구조" 판정은 이 문장을 기준으로 한다.
3. **후보 스캔.** 아래 판정표로 추가 hunk를 훑고, 후보마다 `file:line`과 종류를 적는다.
4. **반증.** 후보마다 "지키는 것" 목록과 대조한다. 하나라도 걸리면 후보에서 뺀다. 확신이 없는 주석은 지우지 말고 WHY 한 줄로 축소한다.
5. **적용 (정리 모드).** 삭제·inline·축소. 지운 자리는 이름과 구조가 설명을 대신하는지 확인한다.
6. **검증.** repo의 기존 테스트·타입체크·린트를 돌린다. 테스트가 없으면 그 사실을 보고에 적는다.
7. **보고.** 아래 출력 포맷으로, diff 규모에 비례해 짧게.

## 판정표

| 종류 | 군살 신호 | 처리 |
|------|-----------|------|
| 주석 | 다음 줄이 하는 일을 말함. 변경 과정·이유를 서술("Added X so that…"). ticket/PR/task 본문 복사. caller가 어떻게 쓰는지 설명. 설명하는 코드보다 긺 | 삭제. 코드가 말할 수 없는 WHY가 섞여 있으면 그 부분만 한 줄로 |
| helper·wrapper | 호출부가 1곳(테스트 포함해 셈). 한 줄을 감쌈. 원본 API보다 이해가 어려움 | inline |
| 추상화 | 구현 1개의 interface·strategy·base class. 사용처 1곳의 generic. 요청하지 않은 config flag·옵션·plugin point·확장 훅 | 제거하고 직접 호출로 |
| 방어 코드 | 계약상 불가능한 상태의 분기. 내부 값 재검증. 인접 코드에 없는 수준의 validation. 처리 코드가 없는 "혹시" 분기 | 삭제 |
| try/catch | catch가 rethrow만 함. 로그만 찍고 삼킴. 복구 가능성 없는 호출을 전부 감쌈 | 제거. 복구·번역·컨텍스트 추가가 되는 지점 하나만 남김 |
| 테스트 | 구현과 같은 로직으로 기대값 계산. 상수·대입·getter 확인. 변경과 무관한 fixture·helper 신설. 같은 partition 반복 | 삭제 또는 기존 fixture로 대체 |
| 파일·구조 | 한 번 쓰는 utility 파일. 요청 밖 rename·이동·포맷 변경. 주변 코드의 "개선" | inline하거나 되돌림 |
| 문제 은폐 | `as any`, ignore 주석, skip된 테스트로 통과시킨 것 | 원인을 고칠 수 있으면 고치고, 아니면 finding으로 보고 |

## 지키는 것

후보가 아래에 걸리면 남긴다. 판정이 흔들리면 남기는 쪽을 택한다.

- trust boundary의 validation: public API, HTTP·CLI·파일 입력, 외부 응답 파싱, auth·권한 체크, data-loss 방지, accessibility
- 복구하거나 다른 에러로 번역하거나 컨텍스트를 더하는 error handling
- 코드가 말할 수 없는 WHY 주석: 숨은 invariant, 외부 시스템 제약, protocol 요구, 동시성·순서 제약, 의도적 trade-off, 알려진 외부 버그 우회. 코드보다 길어도 algorithm·protocol 설명이면 유지
- 실제 domain concept이거나 여러 call site의 일관성을 보장하는 추상화. 세 번째 실제 반복이 있는 helper
- 회귀 위험이 실질적인 focused regression test
- repo 관례가 요구하는 것: public API마다 docstring을 두는 repo, 특정 error wrapper 패턴, 명시적 타입 표기 등. 관례는 인접 파일 2–3개와 AGENTS.md·CLAUDE.md에서 확인
- 이번 변경 밖의 기존 코드. 발견은 Notes로만

## 출력 포맷

검사 모드:

```
대상 <범위> / 추가 hunk <파일 n · +라인 m>
- path:line — <종류> — <처리 제안 한 줄>
지킴: <후보였지만 남긴 것과 이유. 없으면 생략>
```

정리 모드:

```
제거: <종류 — path:line — 한 줄> …
지킴: <남긴 판단. 없으면 생략>
검증: <실행 명령 + 결과>
Notes: <기존 코드의 군살, 범위 밖 항목. 없으면 생략>
```

제거할 것이 없으면 "제거할 것 없음"과 검증 한 줄로 끝낸다. 보고가 diff보다 길면 보고를 줄인다.

## 인접 스킬과의 경계

- **diff-review** — 결함·리스크를 찾는 read-only 리뷰. diff-trim은 결함이 아니라 불필요한 추가물을 본다. 둘 다 할 때는 diff-trim을 먼저 — 걷어낸 diff가 리뷰 비용이 낮다.
- **self-feedback-loop** — plan 기준 review-fix-verify-commit 루프. diff-trim은 1회 패스이고 루프를 돌지 않는다.
- **commit-msg** — 커밋 메시지 작성과 body 판정. diff-trim은 diff만 다룬다.
- **test-code-guide** — 테스트 품질 심층. diff-trim은 이번 변경이 추가한 테스트의 필요성만 본다.
- **humanizer** — 산문·문서의 AI 티. 코드 주석은 문체가 아니라 존재 여부가 diff-trim의 관심이다.
- **내장 `/simplify`(Claude Code)** — 재사용·효율 개선까지 적용하는 넓은 정리. diff-trim은 이번 변경이 더한 것만 빼고 새로운 개선은 하지 않는다. Codex 등 `/simplify`가 없는 환경에서는 diff-trim만 쓴다.

## Gotchas

- **WHAT처럼 보이는 WHY**: `// keep sequential` 한 줄이 실은 provider 제약일 수 있다. 지우기 전에 "이 주석이 없으면 다음 사람이 잘못 바꿀 수 있나"를 묻는다. 그렇다면 WHY 형태로 축소해 남긴다.
- **호출부 셀 때 테스트 누락**: helper를 사용처 1곳이라 inline했는데 테스트가 그 helper를 직접 import한다. 호출부는 테스트까지 포함해 센다.
- **"불가능한 상태"의 caller가 외부**: 함수가 HTTP·CLI·파일·외부 응답을 받으면 그 validation은 trust boundary다. 계약상 불가능은 내부 호출 사이에서만 성립한다.
- **catch 제거로 전파 경로가 바뀜**: 삼키는 catch를 지우면 상위에 처리기가 없는 예외가 될 수 있다. 상위 처리 지점을 확인하고, 없으면 "삼킴"이 아니라 "전파"가 요청된 동작인지 판정한다.
- **범위 창발**: "이왕 정리하는데 옆 함수도"는 unrelated cleanup이다. Notes로 남기고 손대지 않는다.
- **code golf**: 세 줄 if를 중첩 삼항으로 접는 것은 diff 축소가 아니다. 읽기 어려워지면 그대로 둔다.
- **repo 관례를 군살로 오판**: JSDoc 필수, explicit return type, 특정 Result 래퍼는 프로젝트 선택이다. 인접 파일을 보기 전에 지우지 않는다.
- **검증 없는 완료 선언**: 삭제도 변경이다. 테스트·타입체크를 돌린 결과 없이 "동작 무변경"이라 말하지 않는다.
