# custom-skills

개인용 스킬 컬렉션.

기여 전에는 [AGENTS.md](./AGENTS.md)를 먼저 확인한다.

## 포함된 스킬

| 스킬 | 설명 | 트리거 예시 |
|------|------|------------|
| `trace-change-why` | 코드 변경의 WHY(원인, 동기, 판단 근거)를 세션 트랜스크립트에서 추적 | "왜 이렇게 바꿨어?", "이 변경 이유가 뭐야?" |
| `session-history` | 세션 대화 내용을 요약하여 히스토리 파일로 저장 | "세션 정리해줘", "오늘은 여기까지", "마무리" |
| `skill-guide` | 새 스킬 작성 시 참조하는 스펙/구조/워크플로우 가이드 | "스킬 만들어줘", "새 skill 추가" |
| `video-subtitle-dl` | 영상 URL에서 자막 추출, 번역, 포맷 변환 (yt-dlp 기반) | "자막 다운로드", "CC 스크립트 추출", "이 영상 자막 한국어로" |
| `git-commit` | 커밋 메시지 작성과 PR 생성 워크플로우 가이드 | "커밋 만들어", "PR 올려줘", "commit and push" |
| `self-feedback-loop` | 구현 결과를 plan 기준으로 review-fix-verify-commit 루프 반복 | "피드백 루프 돌려", "self-review", "review loop" |
| `tmux` | tmux를 통한 외부 프로세스 상호작용 (SSH, dev 서버, 에이전트, 빌드) | "서버 확인해줘", "dev 서버 로그 봐줘", "다른 터미널에서 실행" |

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
│   ├── git-commit/SKILL.md
│   ├── session-history/SKILL.md
│   ├── trace-change-why/
│   │   ├── SKILL.md
│   │   └── scripts/find-session.sh
│   ├── self-feedback-loop/
│   │   ├── SKILL.md
│   │   └── references/output-format.md
│   ├── tmux/SKILL.md
│   └── video-subtitle-dl/
│       ├── SKILL.md
│       ├── references/
│       │   ├── yt-dlp-options.md
│       │   └── translation-guide.md
│       └── scripts/fetch-subs.sh
├── docs/                  # 스킬 빌딩 참고 자료, 플랜 아카이브
├── AGENTS.md              # 레포 가이드라인
└── README.md
```
