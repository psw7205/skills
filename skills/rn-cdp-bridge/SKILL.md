---
name: rn-cdp-bridge
description: >
  This skill should be used when the user needs to recover console.log output
  or monitor network requests in React Native 0.77+ where Metro log forwarding
  was removed. Covers CDP WebSocket connection to Metro InspectorProxy,
  target discovery, and a bridge script for streaming console/network events
  to the terminal. Relevant when: "console.log가 안 보여", "Metro 로그가 안 나와",
  "RN console.log not showing", "Metro logs missing", "CDP 연결",
  "DevTools 연결 안 됨", "RN network debugging", "RN 디버깅 런북".
---

# RN Metro CDP

RN 0.77+에서 Metro console.log 스트리밍이 제거되었다. CDP WebSocket을 통해 console 출력과 네트워크 요청을 터미널로 브릿지하는 런북.

> **공식 근거**: "log forwarding via Metro, originally deprecated in 0.76, is removed in 0.77. We are moving exclusively to the Chrome DevTools Protocol (CDP)." — [React Native 0.77 Blog](https://reactnative.dev/blog/2025/01/21/version-0.77)

## 언제 이 스킬을 쓰는가

| 증상 | 이 스킬? | 대안 |
|------|----------|------|
| console.log가 Metro 터미널에 안 보임 (RN 0.77+) | **O** | — |
| 네트워크 요청을 터미널에서 모니터링하고 싶음 | **O** | — |
| DevTools GUI로 디버깅하고 싶음 | X | `j` 키 → React Native DevTools |
| VS Code에서 인라인 로그 보고 싶음 | X | Expo Tools / Radon IDE 확장 |
| Expo CLI 프로젝트 | △ | Expo CLI 자체 로그 스트리밍 있음, 네트워크는 이 스킬 유용 |

## 워크플로우

### 1. Target 확인

```bash
curl -s http://localhost:8081/json/list | jq .
```

Metro 포트: RN CLI 기본 `8081`, Expo SDK 50+도 `8081` 고정 (SDK 49 이하는 `19000`–`19002`). Metro 시작 로그에서 확인.

응답에서 `webSocketDebuggerUrl`이 CDP 연결 주소다. 상세 포맷은 `references/inspector-proxy.md` 참조.

**Page 구분**: Page 번호보다 `title`의 "Bridgeless" 키워드나 `reactNative.capabilities.nativePageReloads`로 판별하는 것이 안정적이다 (bridge 스크립트도 이 방식 사용). 일반적으로 Bridgeless page = 메인 RN Bridge (console.log가 여기로 옴), Reanimated UI runtime은 별도 page.

### 2. Bridge 실행

```bash
node "${SKILL_DIR}/scripts/cdp-console.mjs"
node "${SKILL_DIR}/scripts/cdp-console.mjs" --network              # 네트워크 포함
node "${SKILL_DIR}/scripts/cdp-console.mjs" --port 19000 --target iPhone  # Expo + 디바이스 지정
```

스크립트가 target 탐색 → Bridgeless/Hermes 우선 선택 → WebSocket 연결 → 이벤트 스트리밍을 자동 처리한다. 연결 끊김 시 exponential backoff로 재연결.

`SKILL_DIR`이 없으면 스크립트의 절대 경로를 직접 사용. Node 18+에서 동작하며, Node 22 미만에서는 `ws` 패키지가 필요하다.

**스크립트 없이 수동 연결:**

```bash
WS_URL=$(curl -s http://localhost:8081/json/list | jq -r '.[0].webSocketDebuggerUrl')
echo '{"id":1,"method":"Runtime.enable"}' | websocat "$WS_URL"
```

### 3. 공식 GUI 대안

- **React Native DevTools**: Metro에서 `j` 키, 또는 `http://localhost:8081/open-debugger`
- **VS Code**: [Expo Tools](https://github.com/expo/vscode-expo) / [Radon IDE](https://ide.swmansion.com/)

## Gotchas

- **Hermes CDP에서 async/await 불가**: `Runtime.evaluate`로 JS 실행 시 `async/await` 구문을 쓸 수 없다. Promise 체인(`.then()`)으로 작성하고, `awaitPromise: true` 옵션으로 결과를 받을 것.
- **`require`, `global` 없음**: Hermes CDP 컨텍스트에서는 `globalThis`를 사용. Metro의 require는 `globalThis.__r`로 접근 가능하나 불안정.
- **DevTools 동시 연결 경고**: React Native DevTools가 열려 있는 상태에서 bridge를 연결하면 "unsupported debugging client" 경고가 뜨지만 기능은 동작한다.
- **`chrome://inspect` 미지원**: RN 0.76+부터 작동하지 않는다. `j` 키 또는 `/open-debugger` 사용.
- **Flipper가 WebSocket 선점**: Flipper 실행 중이면 CDP 연결 실패. Flipper 종료 후 재시도.
- **Hermes 전용**: JSC(JavaScriptCore) 사용 시 이 워크플로우 불가.
- **Legacy target CDP 제한**: `reactNative.capabilities`가 없는 Legacy target에서는 일부 이벤트 누락 가능.
- **`Network.getResponseBody`는 experimental**: 응답 body 누락될 수 있다.

## 참조

- `references/inspector-proxy.md` — `/json/list` 응답 파싱이나 WebSocket URL 직접 구성 시 참조
- `references/cdp-domains.md` — `consoleAPICalled` args 파싱이나 `Runtime.evaluate` 사용 시 참조
