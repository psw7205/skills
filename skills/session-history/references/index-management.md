# Session History — 이력 관리

저장할 때마다 `~/history/index.jsonl`에 한 줄 추가한다. 이전 기록을 참조하여 중복 방지 및 연속 작업 컨텍스트를 제공한다.

## 인덱스 초기화

```bash
# 인덱스 파일 초기화 (없을 때만)
touch ~/history/index.jsonl
```

## 저장 형식

저장 직후 아래 형식으로 한 줄 append:
```jsonl
{"date":"2026-03-18","time":"14:30","project":"custom-skills","slug":"auth-middleware-decision","path":"~/history/2026-03-18/custom-skills/14-30-auth-middleware-decision.md"}
```

## 이전 기록 활용

- 저장 전 `grep "\"project\":\"$PROJECT_NAME\"" ~/history/index.jsonl | tail -5`로 최근 5건 확인
- 동일 slug가 같은 날짜에 이미 존재하면 `-2`, `-3` 접미사 추가
- 직전 세션의 "후속 작업" 항목이 이번 세션과 연관되면 "요약"에 연속 작업임을 명시
