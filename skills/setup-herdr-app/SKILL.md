---
name: setup-herdr-app
description: >
  Herdr 데스크톱 앱(herdr-app)에 이 레포가 관리하는 mod와 개인 레이아웃을 설치·갱신·대조하는 스킬.
  지금은 하단 상태바 위에 자주 쓰는 지시를 한 번에 보내는 프롬프트 버튼 바(quick-prompts)를 다룬다.
  herdr TUI 설정 이식은 setup-herdr, 에이전트·터미널 제어는 herdr-core(`hc`)가 담당한다.
  "herdr 앱 mod 설치", "프롬프트 버튼 설치", "quick-prompts 갱신", "버튼 문구 바꿔줘",
  "install herdr app mods", "update quick prompts" 등에서 실행.
disable-model-invocation: true
---

# setup-herdr-app

원본은 이 스킬의 `mods/`이고, 앱에서 실제로 쓰는 위치(`~/.config/herdr-app`, 또는 `$HERDR_APP_HOME`)에는 `scripts/install.py`로만 배포한다. 앱 폴더의 mod를 직접 고치면 다음 설치 때 원본으로 덮어써진다. 버튼을 바꿀 때도 이 스킬의 파일을 고친 뒤 설치한다.

```bash
python3 -I scripts/install.py          # check: 앱 폴더와 원본의 차이만 출력, 차이가 있으면 exit 1
python3 -I scripts/install.py apply    # mod 복사 → 레이아웃 없으면 복제 → 블록 삽입 → herdr-app check
```

## 설치하는 것

- `mods/quick-prompts/`: 프롬프트 버튼 바.
  - `prompts.json`: 버튼 목록. 각 항목은 `label`(버튼에 보이는 짧은 이름)과 `text`(실제로 보내는 완성된 지시문)로 되어 있다.
  - `main.js`: 버튼을 누르면 포커스된 에이전트에 `text`를 보낸다.
- `layouts/main-prompts.json`: 공식 `main` 레이아웃을 `layout.clone`으로 복제하고, `work` 열의 `status` 앞에 34px 블록을 넣은 것. 공식 레이아웃은 앱이 시작할 때마다 덮어쓰기 때문에 반드시 복제본에 넣는다.
  - 레이아웃 복제는 앱이 실행 중이어야 하고, 복제하는 순간 화면이 복제본으로 바뀐다.
  - 원래 화면으로는 `ctrl-shift-l`로 돌아간다.

## 확인

`apply`를 실행한 뒤에는 화면을 찍어 확인한다. `herdr-app check`는 비동기로 읽는 `prompts.json`까지는 그려 보지 않는다.

```bash
herdr-app status          # layout이 main-prompts이고 errors가 []인지
herdr-app shot /tmp/qp.png   # 상태바 위에 버튼이 보이는지
```

파일을 저장하면 앱은 1초 안에 다시 읽는다. 저장 직후 바로 찍으면 바뀌기 전 화면이 찍히므로 2초쯤 기다렸다가 찍는다. 버튼 클릭은 사람이 쓰는 화면에서만 확인할 수 있다. 앱 문서가 그 화면에서 포인터 자동화를 하지 말라고 한다.

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

## Gotchas

- **mod에서 `hc send`를 쓰면 안 되는 이유.**
  - herdr-core 0.1.20(2026-11-10)부터 `hc send`는 사람이 쓴 글이 보내지거나 지워질 때까지 최대 60초(`draft_wait`) 기다린다.
  - 그런데 mod의 exec는 30초에 명령을 끊고, 끊긴 `hc send`는 core가 취소한다. 그래서 30초 넘게 기다린 전송은 아무것도 나가지 않고 사라진다. 2026-11-19 재현: 29초까지 살아 있다가 33초에 사라졌고, 그 뒤 사람이 Enter를 눌러도 들어가지 않았다.
- **Enter는 약 3초 늦게 눌릴 수 있다.** `hc keys`는 그 터미널에 사람의 입력이 3초 동안 없을 때까지 기다린다. pane 클릭도 입력으로 잡힌다.
  - 실측(2026-11-19): 클릭 없이 51ms, pane 클릭 직후 3,450ms. 입력이 1초 간격으로 이어지면 마지막 입력 3초 뒤에 눌렸다.
  - 이 대기는 끌 수 없다. `notes_quiet`를 0이나 0.2로 바꿔도 3.0초로 같았고, 앱 명령에 터미널로 키를 보내는 것은 붙여넣기뿐이다.
- **클립보드 내용이 이미지처럼 텍스트가 아니면 되돌리지 못한다.** `read_from_clipboard`가 `undefined`를 돌려주기 때문이다. 이때 버튼을 누르면 클립보드에 버튼 문구가 남는다.
- **앱이 mod 폴더에 `gpui-kit.d.ts`와 `jsconfig.json`을 자동으로 만든다.** 원본에는 넣지 않는다.
