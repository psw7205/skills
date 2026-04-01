# 커맨드별 상세

SKILL.md의 Quick Reference에 없는 상세 옵션, 출력 형식, 엣지케이스를 다룬다.

## identify — 자동화의 첫 커맨드

```bash
cmux identify --json
```

JSON 출력 예시:
```json
{
  "window_id": "window:1",
  "workspace_id": "workspace:2",
  "pane_id": "pane:3",
  "surface_id": "surface:4",
  "surface_type": "terminal",
  "title": "zsh",
  "loading": false
}
```

- `--no-caller`: 호출 surface 자동 감지 비활성화. 다른 workspace/surface를 명시적으로 조회할 때 사용.
- browser surface면 `url`, `title`, `loading` 필드가 추가됨.
- cmux 터미널 밖에서 실행하면 caller 감지가 안 되므로 `--workspace`/`--surface` 명시 필요.

## tree — 토폴로지 한눈에

```bash
cmux tree                    # 현재 workspace만
cmux tree --all              # 모든 workspace
cmux tree --workspace workspace:2
```

가장 유용한 조회 커맨드. list-panes + list-pane-surfaces를 한 번에 볼 수 있다.

## new-workspace 옵션 상세

```bash
cmux new-workspace --name "dev-server" --cwd /path/to/project --command "pnpm dev"
```

- `--name`: workspace 이름. 생략 시 cwd의 basename 사용.
- `--cwd`: 작업 디렉토리. 생략 시 현재 디렉토리.
- `--command`: shell 안에서 실행할 초기 명령. shell init 완료 후 실행되지만, direnv 같은 느린 init에서는 타이밍 이슈 가능.

## new-split vs new-pane vs new-surface

| 커맨드 | 생성 대상 | 용도 |
|--------|-----------|------|
| `new-split <dir>` | 새 pane + terminal surface | 현재 surface 옆에 분할 |
| `new-split <dir> --panel <ref>` | 패널 기준 분할 | 특정 panel 옆에 분할 |
| `new-pane --type browser --url <url>` | 새 pane + 지정 타입 surface | 타입/URL 지정 분할 |
| `new-surface --pane pane:3 --url <url>` | 기존 pane에 탭 추가 | 같은 영역에 탭 추가 |

`new-split right`은 오른쪽에 새 터미널 분할. `new-surface --pane pane:3 --type browser`는 기존 pane:3에 브라우저 탭 추가.

## list-panels / focus-panel

```bash
cmux list-panels [--workspace <ref>]          # panel ref 목록 조회
cmux focus-panel --panel <ref> [--workspace <ref>]  # panel에 포커스
```

panel은 surface 내부의 분할 영역. `send-panel`, `send-key-panel`의 대상을 확인할 때 `list-panels`로 ref를 조회한다.

## drag-surface-to-split

```bash
cmux drag-surface-to-split --surface surface:7 right
```

surface를 현재 위치에서 분리하여 지정 방향으로 새 split을 만든다. UI 드래그를 CLI로 재현.

## move-surface 전체 옵션

```bash
cmux move-surface --surface surface:7 --pane pane:2 --focus true
cmux move-surface --surface surface:7 --workspace workspace:3
cmux move-surface --surface surface:7 --window window:2
cmux move-surface --surface surface:7 --before surface:3
cmux move-surface --surface surface:7 --after surface:5
cmux move-surface --surface surface:7 --index 0
```

pane, workspace, window 간 이동 모두 가능. `--focus true`로 이동 후 포커스.

## send / send-key 상세

```bash
cmux send 'echo hello'              # 텍스트 입력 (Enter 안 보냄)
cmux send-key Enter                 # Enter 전송 → 실행
cmux send-key Tab                   # Tab 자동완성
cmux send-key Escape                # ESC
cmux send-key Up                    # 이전 명령
cmux send-key 'ctrl+c'             # Ctrl+C (프로세스 중단)
```

`send`와 `send-key`를 분리한 이유: 텍스트에 특수 키 이름(Enter, Tab)이 포함될 수 있으므로 리터럴 텍스트와 키 이벤트를 구분.

패널 대상 (`send-panel`, `send-key-panel`): surface가 아닌 panel ref로 직접 전송. `list-panels`로 panel ref 조회.

## read-screen 상세

```bash
cmux read-screen                           # 현재 화면만
cmux read-screen --scrollback              # 스크롤백 포함
cmux read-screen --lines 100              # 최근 100줄
cmux read-screen --scrollback --lines 500  # 스크롤백에서 500줄
```

- 기본: 현재 보이는 화면 내용만 반환
- `--scrollback` 없이 `--lines`를 쓰면 화면 내에서 줄 수 제한
- 출력이 ANSI escape를 포함할 수 있음. 파싱 시 주의.

## wait-for — 동기화 프리미티브

```bash
cmux wait-for my-signal --timeout 30       # "my-signal" 대기 (최대 30초)
cmux wait-for --signal my-signal           # "my-signal" 발신
```

프로세스 간 동기화에 사용. 예: workspace A에서 빌드 완료 후 signal 발신, workspace B에서 대기.

## resize-pane

```bash
cmux resize-pane --pane pane:2 -R --amount 20    # 오른쪽으로 20 확장
cmux resize-pane --pane pane:2 -L --amount 10    # 왼쪽으로 10 축소
cmux resize-pane --pane pane:2 -U --amount 5     # 위로 5
cmux resize-pane --pane pane:2 -D --amount 5     # 아래로 5
```

## pipe-pane

```bash
cmux pipe-pane --command "tee /tmp/output.log"    # 출력을 파일로 파이프
cmux pipe-pane --command ""                        # 파이프 해제
```

터미널 출력을 외부 커맨드로 스트리밍. 로깅, 모니터링에 유용.

## SSH 상세

```bash
cmux ssh user@host --name "prod-server" --port 2222 --identity ~/.ssh/id_ed25519
cmux ssh user@host --ssh-option "StrictHostKeyChecking=no" --no-focus
cmux ssh user@host -- 'ls -la /var/log'
```

- SSH workspace 안에서도 split, browser, send 모두 사용 가능 (원격 터미널 + 로컬 브라우저 조합)
- `--no-focus`: 백그라운드로 workspace 생성
- `--` 뒤: 원격에서 실행할 커맨드. 인터랙티브 세션 대신 일회성 실행.

## surface-health

```bash
cmux surface-health --workspace workspace:2
```

자동화 루프에서 타겟 surface가 유효한지 확인. hidden, detached, non-windowed surface를 감지. 유효하지 않은 surface에 send/read-screen하면 빈 결과나 에러.

## trigger-flash

```bash
cmux trigger-flash --surface surface:7
cmux trigger-flash --workspace workspace:2
```

에이전트가 사용자 주의를 끌어야 할 때 (에러, 완료 알림 등). notify와 달리 시각적 효과만 — 텍스트 메시지 없음.

## 키보드 단축키 요약

| 카테고리 | 단축키 |
|----------|--------|
| Workspace | ⌘N (new), ⌘1-9 (jump), ⌘⇧W (close), ⌘⇧R (rename) |
| Surface | ⌘T (new tab), ⌘⇧] (next), ⌘W (close), ⌃1-9 (jump) |
| Split | ⌘D (right), ⌘⇧D (down), ⌥⌘←↑↓→ (navigate between panes) |
| Browser | ⌘⇧L (open), ⌘L (address bar), ⌘[/] (back/forward) |
| Notification | ⌘I (show), ⌘⇧U (latest unread) |
| Terminal | ⌘K (clear), ⌘+/- (zoom) |
