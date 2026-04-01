# 브라우저 자동화 상세

cmux 브라우저는 WKWebView 기반. Playwright/Puppeteer(CDP)와 달리 macOS 네이티브 웹뷰에서 동작.

## 핵심 루프

모든 브라우저 자동화의 기본 패턴:

```
open/goto → wait(load) → snapshot → action(ref) → re-snapshot → ...
```

```bash
cmux --json browser open https://example.com
# 반환된 surface:N 기억

cmux browser surface:7 get url                              # 이동 확인
cmux browser surface:7 wait --load-state complete --timeout-ms 15000
cmux browser surface:7 snapshot --interactive               # ref 부여
cmux browser surface:7 fill e1 "query"                      # ref로 상호작용
cmux --json browser surface:7 click e2 --snapshot-after     # 클릭 + 자동 re-snapshot
```

**`get url` 먼저**: `about:blank`이면 아직 이동 안 된 것. wait 전에 반드시 확인.

## Snapshot Ref

`snapshot --interactive`는 접근성 트리를 반환하며 각 요소에 `e1`, `e2`... ref를 부여.

```bash
cmux browser surface:7 snapshot --interactive
# [e1] heading "Welcome"
# [e2] textbox "Email"
# [e3] textbox "Password"
# [e4] button "Sign In"
```

### Ref 수명 규칙

- ref는 **해당 snapshot 시점의 DOM에만 유효**
- navigation, Ajax, 동적 DOM 변경 후 stale
- stale ref 사용 → 에러 또는 잘못된 요소에 작용
- **원칙: 액션 후 re-snapshot**. `--snapshot-after` 옵션으로 자동화 가능

### Snapshot 옵션

```bash
cmux browser surface:7 snapshot --interactive                    # 기본 — 상호작용 가능 요소에 ref
cmux browser surface:7 snapshot --interactive --compact          # 간결 출력
cmux browser surface:7 snapshot --interactive --selector "#form" # 특정 영역만
cmux browser surface:7 snapshot --interactive --max-depth 3      # 트리 깊이 제한
cmux browser surface:7 snapshot --interactive --cursor           # 커서 위치 포함
```

## Surface 관리

### 생성과 타겟팅

```bash
# 새 browser surface 생성 (새 탭)
cmux --json browser open https://example.com
# → {"surface_id": "surface:7", ...}

# 특정 workspace/window에 열기
cmux --json browser open https://example.com --workspace workspace:2

# 분할로 열기 (터미널 옆에 브라우저)
cmux browser open-split https://example.com
```

### 태스크 내 surface 일관성

하나의 자동화 태스크에서 같은 `surface:N`을 일관되게 사용. 의도적으로 전환하지 않는 한 surface를 바꾸지 않는다.

### Surface 격리

각 surface는 독립된 브라우저 컨텍스트 — 쿠키, localStorage, 세션이 격리됨. 병렬 태스크(예: 서로 다른 계정 테스트)에서 격리 활용.

## 인증

### 기본 로그인 플로우

```bash
cmux --json browser open https://app.example.com/login
cmux browser surface:7 wait --load-state complete --timeout-ms 15000
cmux browser surface:7 snapshot --interactive
cmux browser surface:7 fill e2 "user@example.com"
cmux browser surface:7 fill e3 "password123"
cmux --json browser surface:7 click e4 --snapshot-after
cmux browser surface:7 wait --url-contains "/dashboard" --timeout-ms 15000
```

### 세션 저장/복원

로그인을 반복하지 않기 위해 인증 상태를 파일로 저장:

```bash
# 로그인 직후 저장
cmux browser surface:7 state save ~/auth-state.json

# 나중에 복원
cmux --json browser open https://app.example.com
cmux browser surface:8 state load ~/auth-state.json
cmux browser surface:8 goto https://app.example.com/dashboard
```

쿠키/localStorage가 모두 포함되므로 대부분의 세션 기반 인증에서 작동.

### OAuth/SSO

- OAuth redirect: `wait --url-contains "/callback"` 또는 `wait --url-contains "/dashboard"`
- 팝업 기반: `browser tab list` → `browser tab switch <index>`로 팝업 탭 전환 후 작업, 완료 후 원래 탭 복귀
- 2FA: 자동화 불가. 사용자에게 수동 입력 안내 후 `wait --url-contains`로 완료 감지

## Wait 패턴

```bash
# 페이지 로드 완료
cmux browser surface:7 wait --load-state complete --timeout-ms 15000

# 특정 요소 출현
cmux browser surface:7 wait --selector "#results" --timeout-ms 10000

# 텍스트 출현
cmux browser surface:7 wait --text "Success" --timeout-ms 10000

# URL 변경 (navigation 후)
cmux browser surface:7 wait --url-contains "/dashboard" --timeout-ms 10000

# 커스텀 JS 조건
cmux browser surface:7 wait --function "document.querySelectorAll('.item').length > 5" --timeout-ms 10000
```

timeout 없으면 무한 대기. 항상 `--timeout-ms` 지정.

## 트러블슈팅

### js_error

복잡한 SPA(React, Angular 대규모 앱)에서 `snapshot --interactive`나 `eval`이 `js_error` 반환 가능.

복구:
```bash
cmux browser surface:7 get url            # 페이지 이동 확인
cmux browser surface:7 get text body      # 순수 텍스트로 fallback
cmux browser surface:7 get html body      # HTML로 fallback
```

여전히 실패 → 간단한 중간 페이지로 이동 후 재시도.

### 빈 snapshot

- 페이지가 아직 로딩 중: `wait --load-state complete` 후 재시도
- iframe 내부 콘텐츠: `browser frame <selector>` → `snapshot`
- 동적 렌더링: `wait --selector <target>` 후 snapshot

### 요소를 못 찾을 때

```bash
# CSS selector 대신 접근성 쿼리 사용
cmux browser surface:7 find role button
cmux browser surface:7 find text "Submit"
cmux browser surface:7 find label "Email"
cmux browser surface:7 find testid "login-btn"

# 요소 시각적 확인
cmux browser surface:7 highlight "#submit-btn"
```

## WKWebView 제약

`not_supported` 반환되는 기능:

- viewport/device emulation
- offline 시뮬레이션
- network route interception/mocking
- trace/screencast recording
- low-level raw input injection

이 기능이 필요하면 Playwright/Puppeteer 등 CDP 기반 도구 사용. cmux 브라우저는 고수준 상호작용(click, fill, wait, snapshot)에 최적화.

## 전체 커맨드 목록

```bash
# Navigation
browser open [url]
browser open-split [url]
browser goto|navigate <url> [--snapshot-after]
browser back|forward|reload [--snapshot-after]
browser url|get-url

# Snapshot
browser snapshot [--interactive|-i] [--cursor] [--compact] [--max-depth <n>] [--selector <css>]

# Interaction
browser click|dblclick|hover|focus|check|uncheck|scroll-into-view <selector> [--snapshot-after]
browser type <selector> <text> [--snapshot-after]
browser fill <selector> [text] [--snapshot-after]
browser press|keydown|keyup <key> [--snapshot-after]
browser select <selector> <value> [--snapshot-after]
browser scroll [--selector <css>] [--dx <n>] [--dy <n>] [--snapshot-after]

# Data
browser screenshot [--out <path>] [--json]
browser get <url|title|text|html|value|attr|count|box|styles> [...]
browser is <visible|enabled|checked> <selector>
browser find <role|text|label|placeholder|alt|title|testid|first|last|nth> ...
browser eval <script>

# Wait
browser wait [--selector <css>] [--text <text>] [--url-contains <text>] [--load-state <interactive|complete>] [--function <js>] [--timeout-ms <ms>]

# Session
browser state <save|load> <path>
browser cookies <get|set|clear> [...]
browser storage <local|session> <get|set|clear> [...]

# Tabs
browser tab <new|list|switch|close|<index>> [...]

# Frame
browser frame <selector|main>

# Dialog
browser dialog <accept|dismiss> [text]

# Download
browser download [wait] [--path <path>] [--timeout-ms <ms>]

# Debug
browser console <list|clear>
browser errors <list|clear>
browser highlight <selector>

# Script injection
browser addinitscript <script>
browser addscript <script>
browser addstyle <css>

# Identity
browser identify [--surface <ref>]
```
