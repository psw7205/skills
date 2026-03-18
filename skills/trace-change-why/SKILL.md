---
name: trace-change-why
description: >
  Use when the user asks WHY code changed rather than WHAT changed,
  including prompts like "왜 이렇게 바꿨어?", "이 변경 이유가 뭐야?", "왜 수정한거야?",
  "이거 왜 바뀐거야?", "who changed this and why", "what was the reasoning behind this change",
  or questions about the reasoning behind a diff, commit, or staged change.
---

# Trace Change Why

코드 변경의 WHY(원인, 동기, 판단 근거)를 추적하여 설명하는 스킬.
사용자는 diff를 이미 보고 있다. WHAT을 반복하지 말고 WHY를 말하라.

## 추적 절차

### 1. 현재 세션 확인

이 세션에서 만든 변경이면 이미 맥락을 알고 있다. 바로 설명.

### 2. 변경 대상 식별

- 특정 파일/라인을 지목한 경우: `git diff` 또는 `git diff --staged` 로 해당 변경 확인
- 이미 커밋된 변경인 경우: `git log -p -- <파일경로>` 또는 `git show <커밋>` 로 확인
- 대상이 불명확한 경우: 사용자에게 확인. 추측하지 말 것.
- 변경된 **파일 경로**와 **코드 패턴**(함수명, 변수명 등)을 기록

### 3. 세션 트랜스크립트에서 원인 찾기

세션 디렉토리에서 해당 변경을 만든 Edit/Write 호출을 검색한다.

**세션 디렉토리 경로:**
```
프로젝트 경로의 / → - 로 변환
예: /Users/hc/repo/project → ~/.claude/projects/-Users-hc-repo-project/
```

**Step 1: 최신 세션 파일 목록 획득**
```bash
ls -t ~/.claude/projects/<project-dir>/*.jsonl | head -10
```

**Step 2: 파일 경로로 후보 세션 좁히기**
```bash
# 전체 경로가 아닌 파일명/상대경로 일부로 검색 (jsonl에 절대경로로 저장됨)
grep -l '파일명.ts' ~/.claude/projects/<project-dir>/*.jsonl
```
여러 세션이 매칭되면 가장 최근 세션부터 확인한다.

**Step 3: 후보 세션에서 Edit/Write 호출 위치 찾기**
```bash
grep -n '"name":"Edit"' <session>.jsonl | grep '파일명'
grep -n '"name":"Write"' <session>.jsonl | grep '파일명'
```

**Step 4: 해당 줄 번호 앞의 대화 맥락 역추적**
```bash
# Edit 호출이 라인 500에 있다면, 그 직전 user 메시지와 assistant 분석을 찾는다
grep -n '"role":"user"' <session>.jsonl    # 500 직전의 user 메시지 라인 번호 확인
grep -n '"role":"assistant"' <session>.jsonl  # 500 직전의 assistant 텍스트 확인
```
찾은 라인 번호 범위를 Read 도구로 읽어 대화 맥락을 파악한다.

### 4. Fallback: 세션을 못 찾은 경우

1. `git log --all --oneline -- <파일경로>` 와 `git blame <파일경로> -L <줄>,<줄>` 로 단서 추출
2. 코드 컨텍스트에서 합리적 이유 추론
3. **추론임을 명시**하고, 확인된 사실과 구분하여 설명

### 5. WHY 중심으로 설명

1. **트리거**: 어떤 요청/문제가 이 변경을 유발했는지
2. **판단 근거**: 왜 이 방식을 선택했는지
3. **변경 요약**: 간략하게만

"이전 세션에서 한 것 같습니다" 같은 애매한 답변 금지. 구체적 맥락을 제시하거나 fallback을 따르라.

## 응답 출력 규칙

모든 응답에서 **확인된 사실**과 **추론**을 명시적으로 분리한다.

- **확인됨**: 세션 트랜스크립트, 커밋 메시지, git blame 등에서 직접 확인한 근거
- **추론**: 코드 컨텍스트, 패턴, 타이밍 등에서 유추한 근거

출력 예시:
```
**확인됨** — 세션에서 사용자가 "N+1 쿼리 제거해줘"라고 요청 (2025-03-15 세션)
**추론** — eager loading 대신 batch loader를 선택한 이유는 기존 코드의 DataLoader 패턴과 일관성을 맞추기 위한 것으로 보임
```

세션에서 직접 확인한 경우에도 판단 근거 해석이 포함되면 해당 부분은 **추론**으로 표기한다.
