# 기법 카탈로그

진단에서 "기법이 필요하다"고 판단되면 이 문서를 참조한다.

---

## 1. Strategy Escalation

기법 선택의 기본 원칙: **단순한 것부터 시도하고, 필요할 때만 다음 단계로.**

```
zero-shot → few-shot → CoT → self-consistency → prompt chaining
```

- 단순 태스크에 과도한 기법을 적용하면 오히려 성능이 떨어진다
- 전문 지식이 불필요한 태스크에서 Few-shot CoT가 Zero-shot보다 나쁜 사례가 보고됨
- zero-shot으로 충분하면 zero-shot으로 둔다
- **Reasoning 모델**(o1, o3 등)에서는 수동 CoT("step by step" 등)를 제거한다 — 모델 자체가 reasoning을 수행하므로 오히려 방해. simple & direct하게 지시

## 2. 입력 특성 → 기법 매핑

| 입력 특성 | 1차 기법 | 보조 기법 |
|----------|---------|----------|
| 단순 지시, 명확한 작업 | Zero-shot | — |
| 분류/판단 + 출력 형식 중요 | Few-shot | label 균형 + random order |
| 복잡한 추론 (수학, 논리) | CoT | Self-Consistency |
| 여러 단계의 변환/처리 | Prompt Chaining | 각 chain에 fallback |
| 사실 기반, hallucination 우려 | 출처/근거 요구 + fallback | Self-verification |
| 도구/외부 정보 활용 | ReAct | — |
| 탐색적 문제 해결 | ToT | — |
| 정밀 연산 (수학, 날짜) | PAL | — |
| 구조/패턴이 핵심 | Meta Prompting | — |
| 반복 개선이 필요한 생성 | Iterative Refinement | — |
| 평가/비교 | LLM-as-Judge | — |
| 톤/전문성 수준 제어 | Role Prompting | — |

## 3. 기법별 패턴

### Zero-shot

examples 없이 instruction만으로 태스크를 수행한다.
최신 instruction-tuned 모델에서 기본 출발점.

**적용**: instruction을 명확하게 작성하면 별도 기법 없이 충분한 경우.
**패턴**: 구조화된 instruction + output indicator.

### Few-shot

demonstrations(exemplar)을 제공하여 in-context learning을 유도한다.
zero-shot이 기대 품질에 미달할 때 다음 단계.

**적용**: 출력 형식이 중요하거나 분류 태스크에서 일관성이 필요할 때.
**패턴**: 3-5개 input→output 예시. 마지막에 새 input만 제시.
**주의**:
- Label 분포를 균형 있게. 한쪽에 치우치면 출력도 편향
- 같은 label끼리 연속 배치하지 말 것 — random order 권장
- Format 일관성이 label 정확성보다 더 중요할 수 있다

### CoT (Chain-of-Thought)

중간 reasoning steps를 포함하여 복잡한 추론의 정확도를 높인다.

**적용**: 수학, 논리, commonsense reasoning 등 multi-step 추론이 필요할 때.
**패턴**:
- Few-shot CoT: exemplar에 reasoning steps를 포함
- Zero-shot CoT: "Let's work this out in a step by step way to be sure we have the right answer" 추가 (APE 발견 — 기본 "Let's think step by step"보다 우수)
**주의**: 1-shot만으로도 효과적. CoT demonstration의 다양성이 중요.

### Self-Consistency

동일 프롬프트로 다수의 reasoning path를 생성하고 majority voting으로 최종 답을 선택한다.

**적용**: CoT 결과의 신뢰도를 높이고 싶을 때. 산술/commonsense reasoning.
**패턴**: CoT 프롬프트 + 다수 sampling → 가장 많이 나온 답 채택.
**주의**: 계산 비용이 높다 (여러 번 생성). 3-8 samples가 일반적.

### Prompt Chaining

복잡한 태스크를 subtask chain으로 분해하여 순차 실행한다.

**적용**: 하나의 프롬프트로 처리하기엔 복잡한 multi-step 태스크.
**패턴**: Prompt 1 → Output A → Prompt 2 (uses A) → Output B → ...
**주의**:
- 각 단계에 fallback 응답을 명시 ("관련 정보가 없으면 'No relevant data found'라고 답해")
- 단계 간 데이터 전달에 delimiter 사용 (`<quotes>`, `####` 등)

### Meta Prompting

구체적 내용이 아닌 **구조와 패턴**에 초점을 맞춘다. "이 유형의 문제는 이런 구조로 풀어라."

**적용**: 구조적 사고가 핵심인 문제. 유사 구조의 다양한 문제를 하나의 프롬프트로.
**패턴**: Abstract examples를 framework로 제공 — 내용이 아닌 문제/해답의 구조를 보여준다.
**장점**: Few-shot보다 token efficient.

### ToT (Tree of Thoughts)

여러 reasoning path를 탐색하고 self-evaluate하며 가장 유망한 경로를 선택한다.

**적용**: 전략적 탐색, 설계 결정, 퍼즐 등 backtracking이 필요한 문제.
**패턴**: "세 명의 전문가가 이 문제를 논의한다고 상상해. 각자 한 단계씩 사고를 공유하고, 틀렸다고 판단되면 퇴장한다."
**주의**: CoT보다 비용이 높지만 복잡한 문제에서 정확도가 크게 향상.

### Generated Knowledge

관련 지식을 먼저 생성하게 한 후, 그 지식을 context로 포함하여 최종 답변을 생성한다.

**적용**: Commonsense reasoning에서 오류를 줄이고 싶을 때.
**패턴**: 2단계 — (1) "이 주제에 대해 알고 있는 사실을 나열해" → (2) 나열된 사실을 context로 포함하여 질문에 답변.

### ReAct

Thought(사고) → Action(도구 호출) → Observation(결과 확인) 루프를 반복한다.

**적용**: 외부 도구/검색이 필요한 knowledge-intensive 태스크.
**패턴**:
```
Thought 1: [무엇을 확인해야 하는가]
Action 1: Search[query]
Observation 1: [검색 결과]
Thought 2: [결과를 바탕으로 다음 단계]
...
```
**주의**: Reasoning 중심 태스크에서는 thought를 많이, action 중심에서는 thought를 sparse하게.

### PAL (Program-Aided Language)

Reasoning을 자연어 대신 코드로 생성하여 런타임에서 실행한다.

**적용**: 정밀한 수학 연산, 날짜 계산 등 free-form text reasoning이 부정확한 경우.
**패턴**: Few-shot으로 "자연어 문제 → 코드" 변환 예시를 제공.

### LLM-as-Judge

모델에 평가자 역할을 부여하여 출력을 비교/평가하게 한다.

**적용**: 두 출력 비교, 품질 평가, 채점 등.
**패턴**: "당신은 [역할]입니다. 아래 두 답변을 [기준]에 따라 비교하고 어느 쪽이 더 나은지 판단하세요."

### Iterative Refinement

첫 출력에 피드백을 주어 반복적으로 개선한다.

**적용**: 한 번에 완벽한 결과를 기대하기 어려운 생성 태스크 (글쓰기, 디자인, 복잡한 코드).
**패턴**: 생성 → 구체적 피드백 → 재생성. "위 결과에서 [구체적 문제]를 수정해" 형태로 반복.
**주의**: 피드백은 구체적이어야 한다 — "더 좋게"보다 "톤을 더 격식 있게, 예시를 2개 추가해".

### Self-verification

모델에게 자기 출력을 source와 대조하게 하는 2단계 패턴.

**적용**: 사실 기반 답변에서 hallucination을 줄이고 싶을 때.
**패턴**: (1) 답변 생성 → (2) "위 답변의 각 주장이 제공된 facts에 정확히 포함되어 있는지 검증해. 포함되지 않은 정보를 보고해."

### Role Prompting

Persona를 설정하여 톤, 스타일, 전문성 수준을 제어한다.

**적용**: 특정 전문 분야의 어조가 필요하거나, 청중 수준에 맞춘 설명이 필요할 때.
**패턴**: system message에 "You are a [role] who [behavior]" 설정.
**주의**: 같은 내용도 persona에 따라 출력 수준이 달라진다 — "초등학생에게 설명하는 교사" vs "동료 엔지니어".
