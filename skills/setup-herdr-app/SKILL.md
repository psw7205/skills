---
name: setup-herdr-app
description: >
  Herdr 데스크톱 앱(herdr-app)에 이 레포가 관리하는 mod와 개인 레이아웃을 설치·갱신·대조하는 스킬.
  지금은 하단 상태바 위에 자주 쓰는 지시를 한 번에 보내는 프롬프트 버튼 바(quick-prompts)와,
  에이전트가 있는 탭을 cmd-w로 닫기 전에 묻는 close-guard, cmd-alt-좌우로 끝 pane을 넘어 옆 탭으로 가는 pane-edge를 다룬다.
  herdr TUI 설정 이식은 setup-herdr, 에이전트·터미널 제어는 herdr-core(`hc`)가 담당한다.
  "herdr 앱 mod 설치", "프롬프트 버튼 설치", "quick-prompts 갱신", "버튼 문구 바꿔줘",
  "cmd-w 탭 닫기 확인", "close-guard 설치", "pane 끝에서 다음 탭으로", "pane-edge 설치",
  "install herdr app mods", "update quick prompts" 등에서 실행.
disable-model-invocation: true
---

# setup-herdr-app

원본은 이 스킬의 `mods/`이고, 앱에서 실제로 쓰는 위치(`~/.config/herdr-app`, 또는 `$HERDR_APP_HOME`)에는 `scripts/install.py`로만 배포한다. 앱 폴더의 mod를 직접 고치면 다음 설치 때 원본으로 덮어써진다. 버튼을 바꿀 때도 이 스킬의 파일을 고친 뒤 설치한다. `keys.json`은 사람의 파일이라 `install.py`의 `KEYS`에 있는 바인딩만 바꾸고, 바꾸기 전에 `keys.json.bak-<시각>`으로 백업한다.

```bash
python3 -I scripts/install.py          # check: 앱 폴더와 원본의 차이만 출력, 차이가 있으면 exit 1
python3 -I scripts/install.py apply    # mod 복사 → 레이아웃 없으면 복제 → 블록 삽입 → 키 설정 → herdr-app check
```

## 설치하는 것

- `mods/quick-prompts/`: 프롬프트 버튼 바.
  - `prompts.json`: 버튼 목록. 각 항목은 `label`(버튼에 보이는 짧은 이름)과 `text`(실제로 보내는 완성된 지시문)로 되어 있다.
  - `main.js`: 버튼을 누르면 포커스된 에이전트에 `text`를 보낸다.
- `layouts/main-prompts.json`: 공식 `main` 레이아웃을 `layout.clone`으로 복제하고, `work` 열의 `status` 앞에 quick-prompts 34px 블록과 pane-edge 0px 블록을 넣은 것. 공식 레이아웃은 앱이 시작할 때마다 덮어쓰기 때문에 반드시 복제본에 넣는다.
  - 레이아웃 복제는 앱이 실행 중이어야 하고, 복제하는 순간 화면이 복제본으로 바뀐다.
  - 원래 화면으로는 `ctrl-shift-l`로 돌아간다.
- `mods/close-guard/`: `cmd-w`를 `mod.open:close-guard`로 바꿔 탭 닫기가 이 mod를 거치게 한다. 화면에 보이지 않는 1px 오버레이로 열렸다가 바로 닫힌다.
- `mods/pane-edge/`: `keys.json`의 `layout:main-prompts` 섹션에서 `cmd-alt-left`/`cmd-alt-right`를 `pane-edge.left`/`pane-edge.right`로 바꾼다. 이 레이아웃의 0px 블록에 있는 mod가 `nextCommand()`로 받는다. 다른 레이아웃에서는 전역의 `pane.go`가 그대로 쓰인다.

## 확인

`apply`를 실행한 뒤에는 화면을 찍어 확인한다. `herdr-app check`는 비동기로 읽는 `prompts.json`까지는 그려 보지 않는다.

```bash
herdr-app status          # layout이 main-prompts이고 errors가 []인지
herdr-app shot /tmp/qp.png   # 상태바 위에 버튼이 보이는지
```

파일을 저장하면 앱은 1초 안에 다시 읽는다. 저장 직후 바로 찍으면 바뀌기 전 화면이 찍히므로 2초쯤 기다렸다가 찍는다. 버튼 클릭은 사람이 쓰는 화면에서만 확인할 수 있다. 앱 문서가 그 화면에서 포인터 자동화를 하지 말라고 한다.

close-guard는 사람 창에서 시험하지 않는다. 그 창에서 포커스된 탭이 일반 셸이면 바로 닫힌다. 대신 임시 홈으로 두 번째 창을 띄운다. 포커스는 창마다 따로고, 스페이스는 core를 통해 양쪽에 보인다. 두 번째 창은 사람 화면에 Herdr가 하나 더 뜬 것으로 보이므로 띄우기 전에 알린다.

```bash
export HERDR_APP_HOME=$(mktemp -d "$TMPDIR/hg.XXXX")    # 소켓 경로 104바이트 제한 안쪽
/Applications/Herdr.app/Contents/MacOS/Herdr &           # 두 번째 창
python3 -I scripts/install.py apply
herdr-app do space.new '{"name":"cg-test"}'
herdr-app status                                         # space가 cg-test인지 먼저 확인
herdr-app do mod.open '{"name":"close-guard"}'
```

working 탭은 `tab.new`의 `argv`로 `sh -c "printf '\033]7501;state=working\007'; sleep 300"`를 돌려 만든다. 끝나면 `space.close {id, confirmed: true}`, `app.quit`, 임시 홈 삭제 순으로 정리한다.

pane-edge도 같은 두 번째 창에서 시험한다. 탭 두 개를 만들고 각각 `pane.split {direction: "right"}`으로 나눈다. 그다음 `herdr-app do pane-edge.right`(또는 `.left`)를 보낼 때마다 `herdr-app status`의 `tab`과 `focused_pane`을 읽는다. 키를 누르는 것과 같은 경로다.

## quick-prompts의 동작 계약

- **대상**: 클릭하는 순간 포커스된 터미널이다. `agents()`에 있고 상태가 `idle`, `done`, `working` 중 하나일 때만 버튼이 켜진다. 일반 셸, 상태 없음(시작 전 업데이트·hook 신뢰 화면), `blocked`일 때는 꺼진다. 이 화면들에서 Enter가 기본 선택을 눌러 버리기 때문이다.
- **전송**: `hc send`를 쓰지 않는다. 클릭하는 순간 다음 순서로 보낸다.
  1. 클립보드에 `text`를 넣는다.
  2. 앱 명령 `terminal.paste`로 포커스된 터미널에 바로 붙여넣는다.
  3. `hc keys <주소> enter`로 제출한다.
  4. 클립보드를 원래 텍스트로 되돌린다.
  - `<hc from>` 태그는 붙지 않는다.
- **입력창에 남은 글**: 입력창에 쓰던 글이 있으면 버튼 문구가 그 뒤에 붙어 함께 나간다. 사람이 직접 누른 버튼이므로 따로 막지 않는다.
- **보내는 중**: 해당 버튼에 "보내는 중…"을 표시하고, Enter가 눌릴 때까지 다른 클릭은 무시한다. 15초 안에 Enter가 눌리지 않으면 버튼을 원래대로 돌리고 "직접 Enter를 누르라"는 토스트를 띄운다.

## close-guard의 동작 계약

- **대상**: 누르는 순간 포커스된 탭이다.
- **물을 때**: 그 탭에 `agents()`가 하나라도 있으면 상태(`working`·`blocked`·`done`·`idle`)와 상관없이 내장 `confirm` 다이얼로그를 띄운다(Enter 닫기, Esc 취소). 쉬는 Claude도 닫으면 세션이 끝나 `claude -c`로 다시 띄워야 하기 때문이다. 확인하면 `tab.close {confirmed: true}`로 닫으므로 마지막 탭이어도 한 번만 묻는다.
- **바로 닫을 때**: 에이전트가 없는 탭(셸, 끝난 프로그램)은 `tab.close`를 확인 없이 부른다. 마지막 탭이면 Herdr가 스페이스 닫기를 묻는다.
- **막지 않는 경로**: 탭바의 ×와 탭 우클릭 메뉴의 Close는 shipped mod가 `tab.close`를 바로 부른다. `cmd-shift-w`(`pane.close`)도 터미널을 끝낸다.

## pane-edge의 동작 계약

- **옆 pane이 있을 때**: `pane.go`와 같다. 어느 pane으로 갈지는 `pane.go`가 정한다.
- **끝 pane일 때**: 오른쪽은 `tab.next`, 왼쪽은 `tab.prev`를 부른다. 도착한 탭에서는 들어온 쪽 끝 pane에 선다. 오른쪽으로 왔으면 가장 왼쪽 pane이고, 왼쪽으로 왔으면 가장 오른쪽 pane이다. 그래서 같은 키를 계속 누르면 모든 pane을 순서대로 지난다.
- **스페이스 끝**: `tab.next`·`tab.prev`가 순환하므로 마지막 탭 다음은 첫 탭이다. 탭이 하나뿐이면 움직이지 않는다.
- 위아래(`cmd-alt-up`/`down`)는 `pane.go` 그대로다.

## 버튼 문구 쓰기

버튼 문구는 받는 에이전트의 전역 지침(`skills/setup-machine/references/global-config.md`가 배포) 위에서 읽힌다.

- 전역 지침이 이미 막는 것은 문구에 다시 쓰지 않는다. push, 되돌리기 어려운 작업, 범위 밖 수정이 그렇다. 겹쳐 쓴 멈춤 조건은 버튼마다 클릭을 한 번 더 요구한다.
- 전역 지침은 `확인`, `리뷰` 같은 동사를 read-only로 읽는다. 확인한 뒤 고치게 하려면 고치라는 지시를 문구에 직접 넣는다. "기다려" 같은 금지 문구를 지우기만 하면 동작은 그대로다.
- 멈춤 조건은 되돌리기 어려운 단계(커밋, 머지, 삭제)에만 둔다.
- 문구를 바꾸면 버그를 하나 심은 임시 git 레포에서 이전 문구와 새 문구를 `claude -p "<맥락과 문구>"`로 각각 돌린다. 파일 변경(`git diff --stat`)과 마지막 응답을 비교한다. 버튼 클릭은 자동화할 수 없으므로 문구의 효과는 이 방법으로 확인한다.

## Gotchas

- **mod에서 `hc send`를 쓰면 안 되는 이유.**
  - herdr-core 0.1.20부터 `hc send`는 사람이 쓴 글이 보내지거나 지워질 때까지 최대 60초(`draft_wait`) 기다린다.
  - mod의 exec는 30초에 명령을 끊고, 끊긴 `hc send`는 core가 취소한다. 그래서 30초 넘게 기다린 전송은 아무것도 보내지 않고 사라진다. 재현하면 29초까지 살아 있다가 33초에 사라졌고, 그 뒤 사람이 Enter를 눌러도 들어가지 않았다.
- **Enter는 약 3초 늦게 눌릴 수 있다.** `hc keys`는 그 터미널에 사람의 입력이 3초 동안 없을 때까지 기다린다. pane 클릭도 입력으로 잡힌다.
  - 실측: 클릭 없이 51ms, pane 클릭 직후 3,450ms. 입력이 1초 간격으로 이어지면 마지막 입력 3초 뒤에 눌렸다.
  - 이 대기는 끌 수 없다. `notes_quiet`를 0이나 0.2로 바꿔도 3.0초로 같았고, 앱 명령에 터미널로 키를 보내는 것은 붙여넣기뿐이다.
- **클립보드 내용이 이미지처럼 텍스트가 아니면 되돌리지 못한다.** `read_from_clipboard`가 `undefined`를 돌려주기 때문이다. 이때 버튼을 누르면 클립보드에 버튼 문구가 남는다.
- **앱이 mod 폴더에 `gpui-kit.d.ts`와 `jsconfig.json`을 자동으로 만든다.** 원본에는 넣지 않는다.
- **`herdr-app check`는 `props()`를 `null`로 준다.** 오버레이로 여는 mod도 `props()?.overlay`로 읽는다.
- **`HERDR_APP_HOME`이 길면 창은 뜨지만 CLI가 붙지 못한다.** `herdr-app.sock` 경로가 104바이트(`SUN_LEN`)를 넘기 때문이다. 에이전트 scratchpad 경로가 그렇다.
- **`herdr-app status`의 `overlays`는 mod 이름이다.** `overlay.close {id: "confirm"}`은 ok를 돌려주지만 닫지 않는다. 인자 없이 부르면 맨 위 다이얼로그가 닫힌다.
- **확인 창이 떠 있는 동안 cmd-w를 다시 누르면 확인 창이 하나 더 쌓인다.** Esc를 그 수만큼 누른다.
- **`run()`의 결과는 호출이 끝난 뒤에 적용된다.** `run("pane.go")` 바로 다음 줄의 `focused()`는 아직 이전 pane이다. `await cx.sleep(1)` 뒤에 읽는다.
- **`cx.sleep()`을 ms 없이 부르면 끝나지 않는다.** 루프가 거기서 멈춰 이후 명령이 모두 사라진다.
- **mod는 다른 mod 폴더의 모듈을 import하지 못한다** (`resolves outside the application directory`). 그리고 `mod.open`은 `name` 외의 인자를 받지 않는다. 그래서 키마다 다른 인자가 필요하면 mod를 둘로 나누지 말고, 레이아웃 블록 하나에 `<mod>.<command>`로 보낸다. `herdr-app do <mod>.<command>`도 같은 경로로 들어간다.
