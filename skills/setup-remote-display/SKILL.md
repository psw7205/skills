---
name: setup-remote-display
description: >
  macOS 기본 화면 공유(VNC)를 Windows·Linux의 서드파티 VNC 뷰어로 원격 사용할 때
  다중 모니터·해상도 문제를 BetterDisplay 가상 화면 + CoreGraphics 미러링으로 풀고,
  VNC 포트를 Tailscale 대역으로만 제한하는 설정을 설치·점검·제거하는 스킬.
  remote-display CLI, Raycast on/off 명령, pf anchor와 LaunchDaemon을 번들한다.
  "맥 화면 공유 윈도우에서", "TigerVNC로 맥 접속", "VNC 듀얼 모니터 문제", "VNC 해상도 안 맞아",
  "가상 디스플레이로 원격", "BetterDisplay 가상 화면", "원격 디스플레이 켜줘", "VNC tailscale만 허용",
  "5900 포트 막아줘", "remote display 설치",
  "mac vnc from windows", "vnc multiple monitors", "headless mac virtual display",
  "restrict vnc to tailscale" 등에서 트리거.
---

# setup-remote-display

macOS VNC 서버는 서드파티 뷰어에게 모든 디스플레이를 이어 붙인 framebuffer를 보낸다. 모니터가 여러 대인 Mac에 다른 OS에서 붙으면 화면이 가로로 길게 잡히고 해상도가 뷰어와 어긋난다. 이 스킬은 원격 전용 가상 화면 하나로 framebuffer를 줄이는 도구를 설치한다.

Mac↔Mac(Apple 화면 공유 앱)은 디스플레이 선택과 고성능 모드가 있어 이 스킬이 필요 없다.

## 번들 파일

| 파일 | 설치 위치 | 역할 |
|------|-----------|------|
| `scripts/remote-display.swift` | `~/.local/bin/remote-display` (symlink) | `on [WxH]` / `off` / `status` CLI |
| `scripts/raycast/remote-display-{on,off}.sh` | 사용자의 Raycast script directory | Raycast 명령. CLI를 `$HOME/.local/bin` 절대경로로 부른다 |
| `scripts/vnc-tailnet-only.pf` | `/etc/pf.anchors/vnc-tailnet-only` | 5900을 lo0와 Tailscale CIDR에서만 허용 |
| `scripts/local.vnc-tailnet-only.plist` | `/Library/LaunchDaemons/` | 부팅 시 anchor 적재와 pf 활성화 |

`~/.agents/skills/setup-remote-display/scripts/` 또는 `${CLAUDE_PLUGIN_ROOT}/skills/setup-remote-display/scripts/`로 resolve한다.

`on`은 가상 화면을 연결하고 지정 해상도로 바꾼 뒤 주 화면으로 옮기고, 나머지 모든 디스플레이를 그 미러로 묶는다. `off`는 미러를 풀고 내장 디스플레이를 주 화면으로 되돌린 뒤 가상 화면을 끊는다. 구성은 `.forSession`으로 적용되어 로그아웃하면 원복된다.

## 전제

감지로 확인하고, 감지로 닫히지 않는 것만 묻는다.

- BetterDisplay 설치: `/Applications/BetterDisplay.app`. 없으면 `brew install --cask betterdisplay`
- 화면 공유 켜짐: `launchctl list | grep com.apple.screensharing`. 켜기는 시스템 설정에서만 된다 — 최신 macOS는 `kickstart`로 켤 수 없다
- VNC 암호: 시스템 설정 → 공유 → 화면 공유 (i) → "VNC 사용자가 암호로 화면을 제어할 수 있음". 감지 불가라 사용자에게 확인한다
- pf 단계는 Tailscale이 이 Mac에 있을 때만 의미가 있다

## 설치 절차

1. **가상 화면 생성** — 같은 이름이 이미 있으면 건너뛴다(`get -name=<이름> -identifiers`).
   ```
   BetterDisplay create -type=VirtualScreen -virtualScreenName="Virtual Remote" -aspectWidth=16 -aspectHeight=9 -virtualScreenHiDPI=off -useResolutionList=on -resolutionList=1280x720,1600x900,1920x1080,2560x1440
   ```
   HiDPI는 끈다. 1080p HiDPI는 실제 framebuffer가 3840×2160이라 VNC 전송량이 4배가 되고, 뷰어 쪽 모니터는 어차피 축소해서 보여준다. 해상도 목록에는 뷰어 모니터 해상도를 넣는다. 이름을 바꾸면 CLI 실행 환경에 `REMOTE_DISPLAY_NAME`을 준다.
2. **CLI 설치** — `ln -sf <scripts>/remote-display.swift ~/.local/bin/remote-display`. symlink라 스킬 업데이트가 그대로 반영된다. `remote-display status`로 가상 화면이 `virtual`로 잡히는지 본다.
3. **Raycast 명령** — 기존 Raycast script directory가 있으면 그곳에, 없으면 `~/.config/raycast/script-commands/`를 만들어 두 파일을 복사한다. 새 디렉토리는 사용자가 Raycast 설정에서 등록해야 한다. 목록에 안 뜨면 `Reload Script Directories`.
4. **pf (sudo)** — 에이전트가 sudo 암호를 받을 수 없으면 명령을 사용자에게 넘긴다.
   ```
   sudo install -m 644 <scripts>/vnc-tailnet-only.pf /etc/pf.anchors/vnc-tailnet-only
   sudo install -m 644 -o root -g wheel <scripts>/local.vnc-tailnet-only.plist /Library/LaunchDaemons/
   sudo launchctl bootstrap system /Library/LaunchDaemons/local.vnc-tailnet-only.plist
   sudo pfctl -a com.apple/250.vnc-tailnet-only -s rules
   ```
   직결 케이블처럼 Tailscale 밖에서도 VNC를 받아야 하는 경로가 있으면 설치 전에 `tailnet` 목록에 그 대역을 추가한다.

## 검증

- **디스플레이**: 원격 뷰어로 접속해 잠금을 푼 뒤, 그 세션에서 Raycast `Remote Display → On`. 뷰어 창이 가상 화면 하나 크기로 줄고 `remote-display status`에서 물리 디스플레이가 모두 `mirrors <virtual id>`면 통과.
- **pf**: 같은 LAN의 다른 호스트에서 `nc -z -G 3 <Mac LAN IP> 5900`이 실패하고, tailnet 피어에서 `nc -z <Mac tailnet IP> 5900`이 성공하면 통과. Mac 자신에서 LAN IP로 치는 검사는 lo0를 타서 의미가 없다.

## 점검 모드

"설정 점검", "뭐가 빠졌는지" 류 요청에서는 쓰지 않는다. 가상 화면 존재, symlink 대상, Raycast 파일 존재, `/etc/pf.anchors/vnc-tailnet-only`와 LaunchDaemon 존재, `sudo -n pfctl -a com.apple/250.vnc-tailnet-only -s rules`(암호 필요 시 `unresolved`)만 보고한다.

## 제거

`remote-display off` → `sudo launchctl bootout system/local.vnc-tailnet-only` → `sudo pfctl -a com.apple/250.vnc-tailnet-only -F all` → 설치한 파일 삭제 → 필요하면 `BetterDisplay discard -name=<이름>`. `discard`는 식별자 없이 부르면 모든 가상 화면을 지우므로 이름을 반드시 붙인다.

## Gotchas

- **잠금 상태에서는 mode 변경이 거부된다.** 화면이 잠겨 있으면 WindowServer가 해상도·미러 변경을 CGError 1014로 거절하고, BetterDisplay CLI의 `set -resolution`도 `Failed.`만 낸다. 연결(`-connected=on`)은 잠금 중에도 된다. CLI는 잠금을 먼저 감지해 아무것도 바꾸지 않고 멈춘다.
- **GUI 세션에서 실행한다.** Raycast나 VNC 세션의 터미널이 기준이다. SSH 세션에서의 디스플레이 구성 변경은 검증되지 않았다.
- **BetterDisplay 상태 보고를 믿지 않는다.** 가상 화면은 online이어도 `get -connected`가 `off`를, `displayID`가 `0`을 돌려준 사례가 있다. 가상 화면 대상의 `set -resolution`·`get -displayModeList`도 실패한다. 실제 상태는 `CGGetOnlineDisplayList`가 진실이고, CLI는 vendor·model·serial로 CG 디스플레이를 찾는다.
- **CGDirectDisplayID는 재연결마다 바뀐다.** 번호를 저장해 두지 않는다.
- **`get`에 파라미터를 여러 개 주면 값이 쉼표로 이어져 나오고 순서가 요청 순서와 다를 수 있다.** 설정 확인은 파라미터 하나씩 조회한다.
- **물리 디스플레이 disconnect는 BetterDisplay Pro 기능이다.** 무료에서는 `-connected` 조회부터 `Failed.`가 난다. 미러링은 macOS 기본 기능이라 라이선스 없이 같은 효과(framebuffer 축소)를 낸다.
- **DDC로 모니터를 끄거나 입력을 돌려도 VNC 화면은 안 준다.** DDC는 모니터 하드웨어 계층이고 macOS는 HPD·EDID가 살아 있는 한 그 디스플레이를 online으로 유지한다. KVM으로 다른 PC에 넘긴 모니터도 여전히 framebuffer에 포함된다.
- **서드파티 뷰어는 VNC 암호가 필요하다.** TigerVNC 등은 Apple 계정 인증(security type 30)을 못 해서, VNC 암호를 켜지 않으면 인증 단계에서 끊긴다. 암호는 8자까지만 유효하다.
- **스트림 암호화는 경로가 맡는다.** 레거시 VNC 인증은 화면 스트림을 암호화하지 않는다. Tailscale(WireGuard) 위에서는 문제없지만, 화면 공유는 모든 인터페이스에서 listen하므로 LAN에 그대로 노출된다 — pf 단계가 이것을 닫는다.
- **`pfctl -f /etc/pf.conf`로 규칙을 올리지 않는다.** 시스템이 부팅 시 넣은 main ruleset을 비운다. 기본 `pf.conf`에 이미 있는 `anchor "com.apple/*"` 아래에 실으면 `pf.conf`를 고치지 않아 macOS 업데이트에도 살아남는다.
- **Raycast는 셸 PATH를 읽지 않는다.** 래퍼가 CLI를 절대경로로 부르는 이유다.
- **`#!/usr/bin/swift`는 실행마다 컴파일한다.** 첫 실행이 1–3초 걸린다. Command Line Tools 또는 Xcode가 있어야 한다.
