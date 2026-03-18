---
name: session-history
description: >
  Use when the user is wrapping up work or asks to save session notes, history, or handoff notes,
  including prompts like "세션 정리해줘", "오늘은 여기까지", "마무리", "save session history",
  "write handoff notes", or after completing a significant unit of work and signaling closure.
---

# Session History

세션 대화 내용을 요약하여 히스토리 파일로 저장한다.

## 왜 이 스킬이 존재하는가

코드는 git에 남지만 "왜 그렇게 결정했는지"는 사라진다. 이 스킬은 의사결정의 맥락과 근거를 보존하여 미래의 자신(또는 동료)이 과거 결정을 이해할 수 있게 한다.

## 언제 사용하는가

아래 조건을 **모두** 만족할 때 제안한다:

1. **종료 신호 감지** — 다음 중 하나 이상:
   - 사용자가 명시적으로 종료를 언급 ("끝", "마무리", "오늘은 여기까지", "done" 등)
   - 사용자가 직접 세션 기록을 요청 ("세션 정리해줘", "히스토리 저장", "save session" 등)
2. **기록할 내용이 존재** — 다음 중 하나 이상:
   - 코드 변경(Edit/Write)이 1건 이상 발생
   - 설계 결정 또는 아키텍처 논의가 있었음
   - 사용자가 피드백/수정 지시를 한 적 있음

## 언제 사용하지 않는가

- 단순 질의응답만 오간 세션 (코드 변경 없음, 결정 없음)
- 탐색/읽기만 한 세션 (grep, read만 사용)
- 사용자가 종료 신호 없이 대화 중인 경우 (먼저 제안하지 않음)
- 이미 이 세션에서 히스토리를 저장한 경우 (중복 저장 방지)

## 경로 규칙

- **project_name**: `basename $PWD` (현재 작업 디렉토리 이름)
- **저장 경로**: `~/history/projects/{project_name}/{YYYY-MM-DD-HH-mm}-{summary-slug}.md`
- **summary-slug**: 대화 핵심을 영문 kebab-case로 2-4단어 (예: `auth-middleware-decision`, `api-refactor-feedback`)
- 디렉토리가 없으면 `mkdir -p`로 생성

## 요약 원칙

- **대화 context를 직접 참조한다.** transcript 파일이나 외부 로그를 읽지 말 것.
- **사실만 기록한다.** 추측, 일반론, 뻔한 설명 금지.
- **"왜"가 핵심이다.** 무엇을 했는지보다 왜 그렇게 결정했는지, 어떤 근거로 수정했는지에 집중.
- **각 항목은 1줄로.** 장황한 설명은 히스토리의 가치를 떨어뜨린다.
- **빈 섹션은 생략한다.** 코드 변경이 없었으면 "변경 사항" 섹션을 넣지 않는다. 후속 작업이 없으면 해당 섹션도 생략.
- **한국어로 작성한다.** 기술 용어, 파일명, 코드는 원문 유지.
- **전체 30줄 이내.** 긴 세션이라도 핵심만 남긴다.

## 출력 포맷

아래 템플릿에서 해당 세션에 내용이 있는 섹션만 포함한다:

```markdown
# {project} — {YYYY-MM-DD HH:mm}

## 요약
이 세션에서 무엇을 했고 왜 했는지 1-3문장.

## 주요 결정
- **{결정 내용}** — {근거/이유}

## 피드백 & 수정
- {사용자가 수정 지시한 내용} — {왜 수정했는지}

## 작업 내역
- [x] 완료된 작업
- [ ] 시도했으나 미완료

## 변경 사항
- `path/to/file.ts` — 변경 내용 한 줄 설명

## 후속 작업
- 다음에 이어서 할 것, 열린 질문, 주의사항
```

### 섹션 순서의 이유

"주요 결정"과 "피드백"이 상위에 있는 것은 의도적이다. 이 스킬의 목적이 "왜" 중심 기록이므로, 결정과 근거가 가장 먼저 눈에 들어와야 한다. 작업 내역과 변경 사항은 부차적 맥락이다.

## 실행 절차

1. 현재 시각을 가져온다: `date +%Y-%m-%d-%H-%M` (파일명용), `date +"%Y-%m-%d %H:%M"` (제목용)
2. project_name을 결정한다: `basename $PWD`
3. 대화 내용을 위 원칙과 포맷에 따라 요약한다
4. summary-slug를 생성한다 (대화 핵심을 영문 kebab-case 2-4단어)
5. `mkdir -p ~/history/projects/{project_name}/`
6. Write 도구로 파일을 저장한다
7. 저장 경로를 사용자에게 알려준다
