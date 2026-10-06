---
name: karabiner-rules
description: >
  Karabiner-Elements complex modification 규칙을 작성·수정·디버깅할 때 쓰는 스킬.
  modifier flag가 remap 이후 상태로 매칭되는 모델, 출력 키가 macOS 시스템 단축키에 먹히는 문제,
  select_input_source 비동기 race와 hold 완화, 프로필별 규칙 유실, lint 검증 절차를 다룬다.
  "karabiner 규칙", "karabiner 키 매핑", "karabiner 안 먹어", "cmd를 ctrl로 바꿨더니 조합이 안 돼",
  "한글 상태에서 단축키 깨져", "입력 소스 자동 전환", "원격 데스크톱 키 매핑", "karabiner.json 수정",
  "karabiner complex modification", "karabiner rule not working", "remap modifier karabiner" 등에서 트리거.
---

# karabiner-rules

`~/.config/karabiner/karabiner.json`의 complex modification을 다룬다. Karabiner는 파일 변경을 감지해 바로 다시 읽으므로, 편집이 곧 적용이다. 편집 전에 사본을 남긴다.

## 절차

1. **대상 프로필 확인** — `karabiner_cli --show-current-profile-name`과 `--list-profile-names`. 규칙은 프로필마다 독립이라, 편집한 프로필과 활성 프로필이 다르면 아무 효과가 없다.
2. **사본** — `cp karabiner.json karabiner.json.bak-<timestamp>`.
3. **편집** — 아래 모델에 맞춰 `from`을 쓴다. 조건(`frontmost_application_if` 등)으로 범위를 좁힌다.
4. **lint** — 활성 프로필의 rules를 `{"title": "...", "rules": [...]}` 형태로 추출해 `karabiner_cli --lint-complex-modifications <file>`에 넘긴다. 출력이 `<file>: ok`인지 **문자열로** 확인한다.
5. **동작 확인** — Karabiner-EventViewer로 입력·출력 이벤트를 본다. 애매하면 manipulator 하나만 바꿔 A/B로 대조한다.

`karabiner_cli` 경로는 `/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli`다(PATH에 없음).

## 모델

- **modifier flag는 manipulator 체인을 거친 뒤의 단일 상태다.** `left_command → left_control` 같은 blanket remap이 있으면, 조합 규칙은 원래 키가 아니라 **remap된 뒤의 modifier**로 매칭해야 한다. `mandatory: ["left_command"]`는 blanket이 keydown 시점에 flag를 이미 바꿨으므로 절대 매칭되지 않는다. `rules` 배열 순서는 같은 순간에 도착한 이벤트의 우선순위만 정하고, 이미 눌려 있는 modifier에는 영향이 없다. "구체 규칙을 blanket보다 앞에 두면 원본으로 매칭된다"는 통념은 틀렸다.
- 부작용: remap 결과로 매칭하면 물리 키가 원래 그 modifier인 조합도 함께 잡힌다(위 예에서는 물리 Left Ctrl). 감수할지 사용자에게 확인한다.
- **`to` 출력은 체인을 다시 타지 않지만 macOS 시스템 단축키는 그대로 처리된다.** 가상 HID로 주입되기 때문이다. 출력이 시스템 단축키와 겹치면 앱에 닿기 전에 가로채진다. 예: `Ctrl+←/→`는 Spaces 전환과 충돌한다. 시스템 단축키 매칭은 좌우 구분이 없어서 `right_control`로 바꿔도 소용없다. 시스템 설정에서 그 단축키를 끄거나 다른 출력을 고른다.

## 입력 소스 전환 race

`select_input_source`는 비동기다. 전환이 정착하기 전에 다음 키가 도착하면 이전 입력 소스로 해석된다. 증상은 "가끔" 실패하는 것이다.

한글 입력 상태에서 터미널 multiplexer prefix(`ctrl+s`, `ctrl+b`)가 깨지는 경우가 대표적이다. kitty keyboard protocol을 쓰는 터미널은 키를 현재 레이아웃의 codepoint로 보고하므로 `ctrl+s`가 `ctrl+ㄴ`이 되어 prefix 매칭이 실패한다. 완화 패턴:

```json
"to": [
  { "select_input_source": { "input_source_id": "com.apple.keylayout.ABC" } },
  { "key_code": "vk_none", "hold_down_milliseconds": 80 },
  { "key_code": "s", "modifiers": ["control"] }
]
```

`vk_none` hold가 전환이 정착할 시간을 번다. 타이밍 기반이라 부하가 크면 여전히 질 수 있다. 근본 해결은 받는 쪽(터미널·앱)이 base layout 키로 매칭하는 것이다.

## Gotchas

- **`--lint-complex-modifications`는 에러가 있어도 exit 0으로 끝난다.** `karabiner.json` 전체를 넘기면 `manipulators is missing or empty`를 출력하면서도 0을 돌려준다. 종료 코드가 아니라 출력이 `: ok`인지로 판정하고, 입력은 `{"title","rules"}` 형태로 추출해서 넘긴다.
- **프로필을 바꾸면 완화 규칙이 조용히 사라진다.** 한 프로필에만 고친 규칙이 있고 다른 프로필에는 구버전이 남아 있는 경우가 흔하다. 증상이 재발하면 활성 프로필부터 확인하고, 필요한 규칙을 쓰는 프로필 전부에 넣는다.
- **`enabled: false` 규칙도 파일에 남는다.** 폐기한 규칙과 살아 있는 규칙이 같은 키를 다루면 읽는 사람이 헷갈린다. 비교할 때 `enabled` 필드를 같이 본다.
