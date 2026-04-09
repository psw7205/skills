---
name: cmux-help
description: >
  cmux CLI 전체 레퍼런스. 커맨드 syntax, 개념, 워크플로우 패턴.
  "cmux 사용법", "cmux 명령어", "cmux help", "cmux 옵션",
  "cmux 세션", "cmux split", "cmux 브라우저 열기",
  "cmux send", "cmux read-screen", "cmux workspace",
  "cmux ssh", "cmux 마크다운", "cmux notify",
  "cmux pane", "cmux surface", "cmux 탭"
  등에서 트리거.
---

# cmux CLI Reference

cmux 앱을 Unix socket으로 제어하는 CLI. tmux와 유사하지만 macOS 네이티브 앱 기반이며, 브라우저 자동화와 마크다운 뷰어를 내장.

```bash
cmux <path>          # 디렉토리를 새 workspace로 열기 (앱 미실행 시 자동 시작)
cmux ~/project       # 예: ~/project를 workspace로
```

## 핵심 개념

### 계층

```
Window (macOS 윈도우)
  └─ Workspace (사이드바 항목 — tmux의 session에 해당)
       └─ Pane (분할 영역 — tmux의 pane)
            └─ Surface (pane 안의 탭 — terminal, browser, markdown)
```

tmux와 가장 다른 점: **Surface**. 하나의 pane 안에 여러 surface가 탭으로 공존한다. terminal과 browser를 같은 pane에서 전환 가능.

### Handle

커맨드 대상을 지정하는 세 가지 방식:

| 형식 | 예시 | 비고 |
|------|------|------|
| short ref | `workspace:2`, `surface:7` | 기본 출력 형식 |
| UUID | `550e8400-...` | 고유하지만 장황 |
| index | `2` | 숫자만. workspace, pane, surface에 사용 |

- `--id-format uuids|both`로 출력 형식 변경
- `tab-action`은 `tab:<n>` 형식도 수용

### 환경변수

cmux 터미널 안에서 자동 설정. 대부분의 커맨드가 이 값을 기본으로 사용하므로, **cmux 터미널 안에서 실행하면 `--workspace`/`--surface` 생략 가능**.

| 변수 | 기본 대상 |
|------|-----------|
| `CMUX_WORKSPACE_ID` | `--workspace` |
| `CMUX_SURFACE_ID` | `--surface` |
| `CMUX_TAB_ID` | `--tab` (tab-action/rename-tab) |
| `CMUX_SOCKET_PATH` | 소켓 경로 오버라이드 |

### 글로벌 옵션

```
--json              JSON 출력. 자동화 시 필수 — ref 파싱이 쉬워짐
--id-format <refs|uuids|both>
--socket <path>     소켓 경로 오버라이드
--password <value>  소켓 인증
```

소켓 인증 우선순위: `--password` > `CMUX_SOCKET_PASSWORD` env > Settings 저장값

## 커맨드 Quick Reference

카테고리별 대표 커맨드만 나열. 전체 옵션과 상세는 [references/commands.md](references/commands.md) 참조.

| 카테고리 | 핵심 커맨드 | 용도 |
|----------|------------|------|
| **App** | `identify --json`, `ping`, `tree --all` | 상태 파악, 토폴로지 조회 |
| **Workspace** | `new-workspace --name --cwd --command` | 프로젝트/태스크 단위 생성 |
| **Pane/Surface** | `new-split <방향>`, `new-surface --pane` | 분할(new-split) vs 탭 추가(new-surface) |
| **Terminal I/O** | `send`, `send-key`, `read-screen` | 명령 입력·실행·출력 읽기 |
| **Browser** | `browser open`, `browser snapshot --interactive`, `browser click/fill` | 내장 브라우저 자동화 |
| **Notification** | `notify --title`, `claude-hook` | 에이전트 알림 |
| **SSH** | `ssh <dest> --name --port` | 원격 workspace 생성 |
| **Markdown** | `markdown <path>` | 마크다운 뷰어 (파일 변경 시 자동 리로드) |
| **Agent** | `claude-teams`, `omo`, `codex install-hooks` | 에이전트 통합 |

### Terminal I/O — 핵심 패턴

**tmux와의 가장 큰 차이**: `send`는 텍스트만 입력하고 Enter를 보내지 않는다. 반드시 `send-key Enter`를 따로 호출해야 실행된다.

```bash
cmux send --surface surface:3 'pnpm test'
cmux send-key --surface surface:3 Enter
sleep 2
cmux read-screen --surface surface:3 --lines 50
```

### Browser — 핵심 루프

```bash
cmux --json browser open https://example.com     # surface ref 기억
cmux browser surface:7 wait --load-state complete --timeout-ms 15000
cmux browser surface:7 snapshot --interactive     # ref(e1, e2...) 부여
cmux browser surface:7 fill e1 "query"
cmux --json browser surface:7 click e2 --snapshot-after   # 클릭 + re-snapshot
```

브라우저 자동화 상세 (인증, 세션 관리, snapshot ref, 트러블슈팅)는 [references/browser.md](references/browser.md) 참조.

### tmux 호환 커맨드

기존 tmux 스크립트 마이그레이션용. 주요 매핑:

| tmux | cmux | 비고 |
|------|------|------|
| `capture-pane` | `read-screen` | |
| `resize-pane` | 동일 | `--pane <ref> -L\|-R\|-U\|-D --amount <n>` |
| `pipe-pane` | 동일 | 출력 스트리밍 |
| `wait-for` | 동일 | 프로세스 간 동기화 |
| `swap-pane`, `break-pane`, `join-pane` | 동일 | pane 조작 |
| `find-window`, `next/previous/last-window` | 동일 | workspace 탐색 |
| `set-buffer`, `paste-buffer` | 동일 | 클립보드 |
| `set-hook`, `bind-key` | 동일 | 제한적 지원 |

전체 호환 커맨드 목록은 [references/commands.md](references/commands.md) 참조.

## 워크플로우

### 현재 상태 파악

```bash
cmux identify --json        # 내가 어디에 있는지
cmux tree --all             # 전체 토폴로지
```

### 명령 실행 + 결과 읽기

```bash
cmux send --surface surface:3 'pnpm test'
cmux send-key --surface surface:3 Enter
sleep 2
cmux read-screen --surface surface:3 --lines 50
```

결과가 길면 `--scrollback`과 `--lines`로 범위 조절. polling이 필요하면 `read-screen`을 반복하며 완료 패턴(`✓`, `PASS`, 프롬프트 복귀) 탐지.

### 병렬 workspace 세팅

```bash
cmux new-workspace --name "server" --cwd ~/project --command "pnpm dev"
cmux new-workspace --name "test" --cwd ~/project --command "pnpm test --watch"
cmux new-workspace --name "agent" --cwd ~/project
```

### 브라우저 자동화 루프

```bash
cmux --json browser open https://example.com
# surface ref 기억 (예: surface:7)
cmux browser surface:7 wait --load-state complete --timeout-ms 15000
cmux browser surface:7 snapshot --interactive
# ref로 상호작용
cmux browser surface:7 fill e1 "query"
cmux --json browser surface:7 click e2 --snapshot-after
# DOM 변경 후 반드시 re-snapshot
cmux browser surface:7 snapshot --interactive
```

### plan 실시간 표시

```bash
cat > /tmp/plan.md << 'EOF'
# Implementation Plan
1. [ ] Analyze codebase
2. [ ] Implement feature
3. [ ] Write tests
EOF
cmux markdown /tmp/plan.md
# 이후 파일 수정 시 뷰어 자동 갱신
```

## tmux에서 cmux로

| tmux | cmux | 비고 |
|------|------|------|
| `tmux new-session -s work` | `cmux new-workspace --name work` | session → workspace |
| `tmux send-keys 'cmd' Enter` | `cmux send 'cmd'` + `cmux send-key Enter` | Enter 분리 |
| `tmux capture-pane -p` | `cmux read-screen` | 동일 |
| `tmux split-window -h` | `cmux new-split right` | 방향 이름 사용 |
| `tmux list-sessions` | `cmux list-workspaces` | — |
| `tmux has-session -t work` | `cmux ping` + `cmux list-workspaces` | 직접 존재 확인 없음 |
| 없음 | `cmux <path>` | 디렉토리 → workspace |
| 없음 | `cmux browser open <url>` | 브라우저 내장 |
| 없음 | `cmux markdown <path>` | 마크다운 뷰어 내장 |

## Gotchas

- **send + send-key 분리**: `cmux send 'ls'`만으로는 실행 안 됨. `cmux send-key Enter` 필수. 가장 흔한 실수.
- **read-screen 타이밍**: send 직후 read-screen은 이전 화면을 반환할 수 있다. 최소 `sleep 1`, 긴 명령은 완료 패턴 polling.
- **snapshot ref 수명**: `snapshot --interactive`의 ref(e1, e2...)는 DOM 변경(navigation, Ajax) 시 stale. 액션 후 반드시 re-snapshot. stale ref 사용 시 에러 또는 잘못된 요소 클릭.
- **WKWebView 제약**: cmux 브라우저는 WKWebView 기반. viewport emulation, network interception, trace recording 미지원. CDP 기반 도구(Playwright 등)와 다름.
- **js_error fallback**: 복잡한 SPA에서 `snapshot --interactive`/`eval`이 실패할 수 있음. `get text body`나 `get html body`로 대체.
- **소켓 미연결**: cmux 앱이 꺼져 있으면 모든 커맨드 실패. `cmux ping`으로 사전 확인.
- **cmux 밖에서 실행**: cmux 터미널 바깥(일반 터미널)에서 실행하면 `CMUX_WORKSPACE_ID` 등이 미설정. `--workspace`, `--surface`를 명시해야 함.
- **new-workspace --command**: 명령이 즉시 실행됨. shell init(PATH, direnv 등)이 완료되기 전에 실행될 수 있으므로, 복잡한 초기화가 필요하면 `send` + `send-key`로 분리.
- **browser open vs goto**: `open`은 새 surface 생성, `goto`는 기존 surface에서 이동. 기존 surface에 `open`을 쓰면 불필요한 탭이 생김.

## 상세 참조

| Reference | 용도 |
|-----------|------|
| [references/commands.md](references/commands.md) | 커맨드별 상세 옵션, 출력 예시, 엣지케이스 |
| [references/browser.md](references/browser.md) | 브라우저 자동화 상세 (인증, 세션, snapshot ref, 트러블슈팅) |
