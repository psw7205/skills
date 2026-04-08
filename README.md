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
| `commit-msg` | 커밋 메시지 추천 (실행 안 함) + 가드레일 체크 | "커밋 만들어", "커밋 메시지 추천", "뭐라고 커밋하지" |
| `self-feedback-loop` | 구현 결과를 plan 기준으로 review-fix-verify-commit 루프 반복 | "피드백 루프 돌려", "self-review", "review loop" |
| `prompt` | 프롬프트 다듬기/생성 (진단 기반 구조·기법·표현 개선) | "프롬프트 다듬어줘", "refine prompt" |
| `tmux` | tmux를 통한 외부 프로세스 상호작용 (SSH, dev 서버, 에이전트, 빌드) | "서버 확인해줘", "dev 서버 로그 봐줘", "다른 터미널에서 실행" |
| `cmux-help` | cmux CLI 전체 레퍼런스 (커맨드, 개념, 워크플로우) | `/cmux-help` (수동 트리거) |
| `setup-hooks` | git 안전 훅 설치/제거 (파괴적 명령 전 auto-stash, force push deny) | "hooks 설치", "guard 설치", "훅 제거" |
| `statusline` | Claude Code statusline 스크립트 설치 (2줄: dir+branch+worktree / ctx+rate+lines) | "statusline 설치", "상태바 설치" |
| `clean-memory` | 프로젝트 메모리 스캔 → CLAUDE.md 중복 삭제 + 범용 규칙 글로벌 승격 | "메모리 정리해줘", "clean memory" |

## 설치

```bash
npx skills add ./
```

## 스킬 추가

1. `skills/<스킬명>/SKILL.md` 파일을 생성한다.

```yaml
---
name: skill-name
description: "트리거 조건을 포함한 설명"
---

# 스킬 본문 (Markdown)
```

2. `.claude-plugin/marketplace.json`의 `skills` 배열에 경로를 추가한다.

```json
"skills": [
  "./skills/<스킬명>"
]
```

> 이 파일에 등록하지 않으면 `npx skills add`에서 "Other"로 분류된다.

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
│   ├── commit-msg/SKILL.md
│   ├── session-history/SKILL.md
│   ├── trace-change-why/
│   │   ├── SKILL.md
│   │   └── scripts/find-session.sh
│   ├── prompt/
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── structure.md
│   │       ├── techniques.md
│   │       └── checklist.md
│   ├── self-feedback-loop/
│   │   ├── SKILL.md
│   │   └── references/output-format.md
│   ├── tmux/SKILL.md
│   ├── cmux-help/
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── commands.md   # 커맨드별 상세 옵션, 엣지케이스
│   │       └── browser.md    # 브라우저 자동화 상세
│   ├── video-subtitle-dl/
│   │   ├── SKILL.md
│   │   ├── references/
│   │   │   ├── yt-dlp-options.md
│   │   │   └── translation-guide.md
│   │   └── scripts/fetch-subs.sh
│   ├── setup-hooks/
│   │   ├── SKILL.md
│   │   └── scripts/guard-untracked.sh
│   └── statusline/
│       ├── SKILL.md
│       └── statusline-command.sh
├── docs/                  # 스킬 빌딩 참고 자료, 플랜 아카이브
├── AGENTS.md              # 레포 가이드라인
└── README.md
```
