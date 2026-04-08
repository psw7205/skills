# InspectorProxy 엔드포인트 레퍼런스

> 소스: `@react-native/dev-middleware` — `packages/dev-middleware/src/inspector-proxy/InspectorProxy.js`

## HTTP 엔드포인트

### GET `/json` 또는 `/json/list`

연결된 모든 디바이스의 디버깅 가능한 페이지 목록을 반환한다.

**응답 포맷** (JSON 배열):

```json
[
  {
    "id": "<deviceId>-<pageId>",
    "title": "React Native Bridgeless [C++ connection]",
    "description": "com.example.app",
    "appId": "com.example.app",
    "type": "node",
    "devtoolsFrontendUrl": "devtools://...",
    "webSocketDebuggerUrl": "ws://localhost:8081/inspector/debug?device=<deviceId>&page=<pageId>",
    "vm": "Hermes",
    "deviceName": "iPhone 15 Pro",
    "reactNative": {
      "logicalDeviceId": "<deviceId>",
      "capabilities": {
        "nativePageReloads": true,
        "nativeSourceCodeFetching": true
      }
    }
  }
]
```

주요 필드:

| 필드 | 용도 |
|------|------|
| `id` | `<deviceId>-<pageId>` 복합키 |
| `webSocketDebuggerUrl` | 디버거가 연결할 WebSocket URL |
| `vm` | JS 엔진 (`"Hermes"` 등) |
| `deviceName` | 디바이스 식별 (다중 디바이스 구분용) |
| `reactNative.capabilities` | target 유형 판별. `nativePageReloads: true` → Bridgeless |

### GET `/json/version`

프로토콜 버전 메타데이터를 반환한다. Chrome DevTools가 호환성 확인에 사용.

## WebSocket 엔드포인트

### `/inspector/device?device=<deviceId>`

**디바이스 → 프록시** 연결. 네이티브 앱이 시작 시 자동 연결한다. 직접 사용할 일 없음.

### `/inspector/debug?device=<deviceId>&page=<pageId>`

**디버거 → 프록시** 연결. CDP 메시지를 주고받는 실제 디버깅 채널.

- `device`: `/json/list` 응답의 `reactNative.logicalDeviceId`와 매칭
- `page`: 해당 디바이스 내 페이지 ID
- 두 파라미터 모두 필수. 누락 시 `INCORRECT_URL` 에러

URL 구성:
```
ws://<host>:<port>/inspector/debug?device=<deviceId>&page=<pageId>
```

HTTPS 환경에서는 `wss://` 사용.

## 포트

| 환경 | 기본 포트 |
|------|-----------|
| React Native CLI | 8081 |
| Expo CLI (SDK 50+) | 8081 |
| Expo CLI (SDK 49 이하) | 19000–19002 |
| 커스텀 | Metro 시작 로그에서 확인 |

## InspectorProxy 동작

- 디바이스와 디버거 사이의 CDP 메시지를 양방향 프록시
- `Runtime.consoleAPICalled` 이벤트의 스택트레이스 URL을 디버거 기준으로 리라이팅
- 디바이스 연결이 끊기면 디버거 WebSocket도 자동 종료
- 세션 ID는 UUID 기반 (`crypto.randomUUID()`)
