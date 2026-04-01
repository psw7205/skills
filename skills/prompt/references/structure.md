# 프롬프트 구조

진단에서 "구조가 약하다"고 판단되면 이 문서를 참조한다.

---

## 1. 4요소

프롬프트는 네 가지 요소의 조합이다. 모두 필수는 아니지만, 빠진 요소가 있으면 의도적인지 확인한다.

### Instruction

태스크 지시. 프롬프트의 가장 앞에 배치한다.

- 명확한 동작 동사 사용: Write, Classify, Summarize, Translate, Extract, Compare, Evaluate
- "다음 텍스트를 분석해줘" 같은 모호한 지시 대신 "다음 텍스트에서 감정을 Positive/Negative/Neutral로 분류해" 처럼 구체적으로
- 하나의 프롬프트에 하나의 핵심 지시. 복합 지시가 필요하면 Prompt Chaining 고려

### Context

배경 정보, 제약 조건, 참고 자료.

- Few-shot examples, 검색 결과, 스키마 정보, 도메인 지식 등
- Instruction과 반드시 delimiter로 분리 (아래 "구조 분리 패턴" 참조)
- 관련 있는 정보만 포함. 무관한 context는 성능을 떨어뜨린다 (noisy information)

### Input Data

처리 대상 데이터, 사용자 입력.

- System instruction과 구조적으로 분리한다 — prompt injection 방어의 기본
- XML 태그(`<user_query>`, `<document>` 등)로 영역을 명확히 격리
- 데이터가 길면 핵심 부분만 발췌하거나 요약을 먼저 제공
- 동적 context(현재 날짜/시간, 사용자 locale 등)는 template 변수로 주입한다 — 빠지면 모델이 추측한다

### Output Indicator

기대 출력 형식을 명시적으로 유도한다.

- 라벨형: "Sentiment:", "Answer:", "Category:" — 모델이 이어서 채우도록
- 포맷형: "JSON으로 응답해", "마크다운 테이블로 정리해"
- 스키마형: JSON schema나 typed fields로 필드별 타입/예시값 명시
- XML을 기본 출력 구조로 권장 (JSON도 가능). 프롬프트 형식이 출력 형식에 영향을 준다

## 2. 구조 분리 패턴

프롬프트 내 영역을 시각적으로 분리해야 모델이 각 부분의 역할을 정확히 인식한다.

### Delimiter 종류와 용도

| Delimiter | 용도 | 예시 |
|-----------|------|------|
| `###` | Instruction과 Context 분리 | `### Context:` |
| `---` | 섹션 간 구분 | Instruction --- Examples --- Input |
| `"""` | 인용/데이터 블록 감싸기 | `"""스키마 정보"""` |
| `<tag></tag>` | User input 격리, 구조화된 영역 | `<user_query>...</user_query>` |
| `//` | 경량 inline 구분 (few-shot) | `텍스트 // 라벨` |

### 배치 원칙

- Instruction을 프롬프트 **시작**에 배치
- 중요 정보는 프롬프트 **시작부와 끝부분**에 배치 — 중간에 묻히면 recall이 약해진다
- User input은 XML 태그로 격리하여 system instruction과 경계를 명확히

## 3. Role 구조

Chat 모델에서 system/user/assistant 역할을 활용하는 패턴.

- **system**: behavior(의도)와 identity(톤/스타일)를 분리하여 설정. "You are a technical writer who explains complex topics clearly."
- **user**: 실제 input과 question
- **assistant**: few-shot에서 기대 응답 형식을 시연. 첫 번째 assistant 메시지로 출력 톤을 고정할 수 있다

모델에 따라 system message보다 user message에 instruction을 넣는 게 더 효과적일 수 있다. 대상 모델의 특성 고려.

## 4. 작성 원칙

### 긍정형 지시

"~하지 마" 대신 "~해" + 대안 행동/fallback 응답을 명시한다.

- Bad: "전문 용어를 사용하지 마"
- Good: "일상 언어로 설명해. 전문 용어가 필요하면 괄호 안에 풀어서 적어"
- Fallback 패턴: "확실하지 않으면 'Unsure about answer'라고 답해"

### 구체성

모호한 표현을 수치/형식/조건으로 치환한다.

- "짧게" → "2-3문장으로"
- "쉽게" → "고등학생이 이해할 수 있도록"
- "자세하게" → "각 항목에 대해 원인, 영향, 해결방안을 1-2문장씩"

### 핵심 지시 반복

중요한 지시는 프롬프트 내에서 반복하면 성능이 향상된다. 프롬프트 시작과 끝에 핵심 제약을 배치하는 것이 효과적.

### Noise 제거

관련 없는 디테일, 불필요한 예시, 중복 설명을 제거한다. 정보가 많을수록 좋은 게 아니다 — 관련성이 핵심.

## 5. 재사용 패턴

### Template 변수

반복 사용하는 프롬프트는 `{variable}` placeholder로 템플릿화한다.

```
다음 {language} 코드를 리뷰해. {focus_area}에 집중해서 {output_format}으로 정리해.
```

### Prompt Function

프롬프트를 함수처럼 캡슐화하면 여러 프롬프트를 chain하여 workflow를 구성할 수 있다.

구조: **Name** (함수명) + **Input** (입력 정의) + **Rules** (처리 규칙) + **Output** (출력 형식)
