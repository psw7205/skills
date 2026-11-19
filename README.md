# custom-skills

개인용 스킬 컬렉션.

기여 전에는 [AGENTS.md](./AGENTS.md)를 먼저 확인한다.

## 포함된 스킬

분류는 사람이 탐색하기 좋도록 트리거 맥락 기준으로 묶은 메타데이터다. 실제 자동 트리거는 각 스킬의 `description`이 결정한다.

### Git & 버전 관리

| 스킬 | 설명 | 트리거 예시 |
|------|------|------------|
| `commit-msg` | 커밋 메시지 추천 (실행 안 함) + 가드레일 체크 | "커밋 만들어", "커밋 메시지 추천", "뭐라고 커밋하지" |
| `commit-regroup` | push 전 로컬 커밋을 논리 단위로 재구성 (soft-reset 재배치 + 트리 동일성 검증) | "커밋 묶어줘", "로컬 커밋 grouping", "push 전에 커밋 정리해줘" |
| `trace-change-why` | 코드 변경의 WHY(원인, 동기, 판단 근거)를 세션 트랜스크립트에서 추적 | "왜 이렇게 바꿨어?", "이 변경 이유가 뭐야?" |
| `git-diagnosis` | Git 이력 기반 코드베이스 건강 진단 — 교차 분석으로 고위험 코드 식별 | "프로젝트 분석해줘", "코드베이스 진단", "codebase audit" |
| `worktree-lifecycle` | git worktree lifecycle 4단계(setup/working/prep/cleanup) 식별 + fast-path 결정 트리 + squash 직전 정리 가이드 | "worktree 만들까", "여기서 바로 할까", "main 머지 준비", "worktree 정리" |

### Workflow & 세션

| 스킬 | 설명 | 트리거 예시 |
|------|------|------------|
| `rough` | 방향·순서만 잡는 러프 문서 작성 + "착수 가능성" 기준 리뷰 (구현 디테일 금지, 일반 "plan" 요청엔 트리거 안 함) | "러프 잡아줘", "러프 써줘", "러프 리뷰해줘", "러프 착수 가능해?" |
| `diff-review` | 변경 집합(diff·staged·PR) read-only 리뷰. 비용 사다리(inline 기본 → 단일 리뷰어 → fan-out은 명시 게이트) → 수정은 self-feedback-loop로 위임 | "코드 리뷰해줘", "이 변경 리뷰", "PR 리뷰", "diff 봐줘" |
| `diff-trim` | 작업을 마친 diff의 추가 hunk에서 군살(코드 되풀이 주석·1회용 helper·불가능 상태 방어·구현 복제 테스트·요청 밖 구조)을 동작 무변경으로 걷어내는 1회 패스. 검사/정리 모드 | "diff 다이어트", "불필요한 주석 지워", "커밋 전에 정리", "trim the diff" |
| `codebase-review` | 전체 코드베이스를 다축(구조·리팩토링·성능·보안·테스트 등)으로 훑는 read-only 리뷰 → 개선은 self-feedback-loop로 위임 | "코드베이스 전체 리뷰해줘", "리팩토링 관점에서 봐줘", "코드 개선점 찾아줘" |
| `self-feedback-loop` | 구현 결과를 plan 기준으로 review-fix-verify-commit 루프 반복 | "피드백 루프 시작", "리뷰하고 고쳐", "review and fix" |
| `pstack-codex` | pstack 원본 스킬의 Cursor 도구·모델·경로를 Codex로 매핑하고 모든 서브에이전트에 어댑터를 전달하는 실행 진입점 | "Codex에서 pstack", "poteto-mode로 작업", "use pstack in Codex" |
| `compound` | 해결한 문제를 `docs/solutions/`에 frontmatter 붙은 검색 가능한 단위로 자산화 | "이 문제 자산화해줘", "solution 저장", "compound 이거" |
| `session-history` | 세션 대화 내용을 요약하여 히스토리 파일로 저장 | "세션 정리해줘", "오늘은 여기까지", "마무리" |
| `daily-work-report` | 하루치 Claude Code·Codex 대화(여러 머신)와 GitHub 커밋을 근거로 팀 일일 보고용 Markdown 작성. org·호스트·보고 DB는 로컬 설정 | "작업 일지", "재택근무 리포트", "오늘 한 일 정리" |
| `session-bridge` | Claude Code/Codex CLI/OpenCode transcript를 session id로 찾아 handoff 요약 작성 | "claude 세션 이어서", "opencode session handoff" |
| `session-cost-audit` | Claude Code transcript 토큰 집계 → 비용 방정식 항(요청/턴·컨텍스트·cache 재구축 원인·도구 출력·subagent 모델·effort)과 anti-pattern flag 보고 | "세션 비용 분석", "토큰 어디서 새", "캐시 미스 확인", "cost dashboard" |
| `repo-prd-sync` | 구현 repo와 PRD/design repo 사이의 수동 pull-in/back-sync 가드레일 | "PRD 반영", "repo prd sync", "sync PRD with repo" |
| `figma-spec-sync` | Figma 기획 파일 → 기계 추출 스냅샷(md+PNG) → 구조 delta → 구현 대조 → 정합 plan(대조표) 라우팅. version 게이트로 미반영 pull 판정 | "figma 뭐 바뀌었나", "figma 스냅샷 받아", "figma 변경으로 계획 세워줘", "figma sync" |

### 개발 환경

`(수동)`은 모델이 자동 호출하지 않고 `/name`·`$name`으로만 실행하는 스킬, `(1회용)`은 설치하지 않고 `npx skills use psw7205/skills@<name>`이나 레포 파일로 실행하는 스킬이다.

| 스킬 | 설명 | 트리거 예시 |
|------|------|------------|
| `setup-machine` | (수동) 머신 셋업·싱크·업데이트 반영 진입점. dotfiles·herdr 위임 + Claude Code·Codex 계층(글로벌 지침, output style, statusline, 셸 가드·Artifact 가드, verify-gate, 세션 로그)을 `sync.py`로 check→apply, 위치 보존 handler 마이그레이션, 머신별 끄기 기록 | "새 머신 셋업", "싱크 맞춰줘", "스킬 업데이트 반영해줘", "verify gate 꺼줘", "아티팩트 막아줘" |
| `setup-dotfiles` | (수동) 셸·brew·mise 기준선 설치·대조 (번들 zshenv/zprofile/zshrc/Brewfile/mise, 머신 고유 값은 `.local` 분리) + `claude --resume`·`codex resume` Tab 세션 picker(resume-completion) 설치·갱신 | "dotfiles 설치", "Brewfile 적용", "dotfiles 대조", "resume 자동완성 설치" |
| `tmux` | tmux를 통한 외부 프로세스 상호작용 (SSH, dev 서버, 에이전트, 빌드) | "서버 확인해줘", "dev 서버 로그 봐줘", "다른 터미널에서 실행" |
| `cmux-help` | cmux CLI 가이드 (모델·함정 정적, 커맨드 카탈로그는 `cmux --help`/`cmux docs`로 위임) | "cmux 사용법", "cmux 설정", "cmux 브라우저", "cmux sidebar" |
| `setup-herdr` | (1회용) herdr TUI 전용. `config.toml`을 다른 머신으로 이식·검증 (OS별 경로, byte-exact 전송, `config check` 3단 진단, remote attach 키 소유권) | "herdr 설정 이식", "윈도우에 herdr 설정 적용", "herdr prefix 바꿔줘", "herdr 단축키 안 먹어" |
| `setup-herdr-app` | (수동) Herdr 데스크톱 앱에 이 레포가 관리하는 mod·개인 레이아웃을 설치·대조(`install.py check`/`apply`). 하단 상태바 위 프롬프트 버튼 바(quick-prompts: 라벨과 실제 지시문 분리, 에이전트 상태별 활성화, 붙여넣기 후 `hc keys`로 제출, 버튼 문구 작성·검증 기준) | "herdr 앱 mod 설치", "프롬프트 버튼 설치", "quick-prompts 갱신" |
| `hc-agent-refresh` | (수동) Claude Code·Codex 업데이트 뒤 herdr-core(`hc`) 터미널의 유휴 구버전 세션을 같은 대화로 resume해 교체 (셸 루트는 제자리, 에이전트 루트는 재실행, 초기 프롬프트 제외, Codex는 `--no-daemon`, dry run 기본) | "claude 재시작", "codex 재시작", "에이전트 업데이트 반영" |
| `setup-remote-display` | (수동) macOS 화면 공유를 서드파티 VNC 뷰어로 쓸 때 BetterDisplay 가상 화면 + 미러링으로 framebuffer를 하나로 줄이는 CLI·Raycast 명령 설치, VNC 5900을 Tailscale 대역으로만 제한하는 pf anchor | "TigerVNC로 맥 접속", "VNC 듀얼 모니터 문제", "원격 디스플레이 켜줘", "VNC tailscale만 허용" |
| `repo-mirror` | 여러 repo 작업 트리를 외장 볼륨·다른 Mac·Linux/WSL로 병렬 rsync 복사 (`.git` 보존, 산출물 제외, Linux 대상 NFD→NFC, openrsync vs rsync 3.x 선택) | "repo 백업", "WSL로 레포 복사", "한글 파일명 깨져", "mirror repositories to linux" |
| `tailnet-server-hardening` | 클라우드 VM 관리 경로를 Tailscale로 옮기고 공개 SSH를 닫는 순서·검증(키 만료, sshd 실효값, 2중 방화벽, CDN 대역 제한, 비상 경로) + 바깥·서버 안·OCI control plane 3지점 read-only 점검 스크립트 | "서버 SSH 포트 닫기", "tailscale로만 서버 접속", "서버 헬스체크", "node key expired" |
| `mac-disk-reclaim` | macOS 개발 머신 디스크 회수 — read-only 실측 스크립트, 재생성 비용 기준 A/B/C 등급, 되살릴 수 없는 데이터는 사본 체크섬 검증 후 삭제, VM 디스크 fstrim | "디스크 용량 확보", "맥 용량 줄이기", "Docker 용량 줄이기", "free up disk space on mac" |
| `karabiner-rules` | Karabiner complex modification 작성·디버깅 — remap 이후 modifier로 매칭되는 모델, 출력이 시스템 단축키에 먹히는 문제, `select_input_source` race와 hold 완화, 프로필별 규칙, lint가 exit 0으로 에러를 숨기는 함정 | "karabiner 안 먹어", "cmd를 ctrl로 바꿨더니 조합이 안 돼", "한글 상태에서 단축키 깨져" |
| `rn-cdp-bridge` | RN 0.77+ Metro CDP 디버깅 — console.log·네트워크 브릿지 + release 크래시를 debug+Metro로 진단 + 실기기 debug 빌드 툴체인 함정 | "console.log 안 보여", "Metro 로그 안 나와", "release 크래시가 안 잡혀", "화면 진입하면 죽어" |
| `agent-native-audit` | 프로젝트의 agent 친화도를 7개 축으로 점수화 + P1/P2/P3 개선 추천 | "agent-native 점검", "이 레포 agent에 최적화돼 있어?", "AGENTS.md 점검" |

### 저작 도구

| 스킬 | 설명 | 트리거 예시 |
|------|------|------------|
| `prompt` | 프롬프트 다듬기/생성 (진단 기반 구조·기법·표현 개선) | "프롬프트 다듬어줘", "refine prompt" |
| `humanizer` | 문장과 글의 AI 티 검사 + 한국어 번역투/GPT 말투 rewrite | "문장 검사", "AI 티 제거", "번역투 고쳐", "GPT 말투 빼줘", "humanize this" |
| `skill-guide` | 새 스킬 작성 시 참조하는 스펙/구조/워크플로우 가이드 | "스킬 만들어줘", "새 skill 추가" |
| `clean-memory` | 프로젝트 메모리 스캔 → CLAUDE.md 중복 삭제 + 범용 규칙 글로벌 승격 | "메모리 정리해줘", "clean memory" |

### 구현 패턴

| 스킬 | 설명 | 트리거 예시 |
|------|------|------------|
| `api-crud-pattern` | API CRUD 작업 전 domain shape, delete/restore, identifier, projection, conflict 정책 점검 | "CRUD API 구현", "API CRUD 검토", "scoped resource" |
| `test-code-guide` | 테스트 3모드(설계 점검·작성 규범·리뷰) — 구현 미러링, 무의미 커버리지, 비결정성, 테스트 간 결합 방지 | "테스트 짜줘", "테스트 코드 리뷰해줘", "write tests" |

### 유틸리티

| 스킬 | 설명 | 트리거 예시 |
|------|------|------------|
| `video-subtitle-dl` | 영상 URL에서 자막 추출, 번역, 포맷 변환 (yt-dlp 기반) | "자막 다운로드", "CC 스크립트 추출", "이 영상 자막 한국어로" |
| `ncloud-docs` | NCP 공식 문서를 llms.txt 인덱스·원문 `.md`로 수집 (slug 검색, 상품 단위 pull 후 grep으로 부재 판정, WAF UA 차단·SPA 셸·WebFetch 요약 함정 회피) | "ncloud 문서 확인해", "NCP API 스펙", "네이버 클라우드 가이드" |

## 설치

전체 에이전트용 global 설치:

```bash
npx skills add . -g --all
```

로컬 스모크 테스트:

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

2. `.claude-plugin/marketplace.json`에서 README 분류에 맞는 `plugins[]` 항목의 `skills` 배열에 경로를 추가한다.

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
│   └── <skill-name>/
│       ├── SKILL.md       # 엔트리 포인트 (frontmatter: name, description)
│       ├── references/    # 필요할 때만: 보조 문서
│       └── scripts/       # 필요할 때만: 런타임에 호출하는 스크립트
├── .claude-plugin/
│   └── marketplace.json   # npx skills add 분류 매니페스트
├── docs/                  # 스킬 빌딩 참고 자료, 플랜 아카이브
├── AGENTS.md              # 레포 가이드라인
└── README.md
```

스킬별 파일은 `find skills -type f | sort`로 확인한다.
