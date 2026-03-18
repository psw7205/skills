# custom-skills

개인용 스킬 컬렉션.

기여 전에는 [AGENTS.md](./AGENTS.md)를 먼저 확인한다.

## 포함된 스킬

| 스킬 | 설명 | 트리거 예시 |
|------|------|------------|
| `trace-change-why` | 코드 변경의 WHY(원인, 동기, 판단 근거)를 세션 트랜스크립트에서 추적 | "왜 이렇게 바꿨어?", "이 변경 이유가 뭐야?" |
| `session-history` | 세션 대화 내용을 요약하여 히스토리 파일로 저장 | "세션 정리해줘", "오늘은 여기까지", "마무리" |
| `skill-guide` | 새 스킬 작성 시 참조하는 스펙/구조/워크플로우 가이드 | "스킬 만들어줘", "새 skill 추가" |

## 설치

```bash
npx skills add ./
```

## 스킬 추가

`skills/<스킬명>/SKILL.md` 파일을 생성한다.

```yaml
---
name: skill-name
description: "트리거 조건을 포함한 설명"
---

# 스킬 본문 (Markdown)
```

필요할 때만 `references/` 하위 디렉토리에 보조 문서를 둔다.

## 점검 명령

```bash
find skills -maxdepth 2 -name SKILL.md | sort
rg -n '^name:|^description:' skills/*/SKILL.md
git status --short
```

## 레포 구조

```
custom-skills/
├── skills/
│   ├── skill-guide/
│   │   ├── SKILL.md
│   │   └── references/guide.md
│   ├── trace-change-why/SKILL.md
│   └── session-history/SKILL.md
├── docs/                  # 참고 자료
├── AGENTS.md              # 레포 가이드라인
└── README.md
```
