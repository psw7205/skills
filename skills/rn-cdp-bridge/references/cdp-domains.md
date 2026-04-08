# CDP 도메인 레퍼런스 (React Native)

> 소스: [React Native CDP Status](https://cdpstatus.reactnative.dev)

React Native (Hermes)에서 지원하는 CDP 도메인 중 이 스킬에서 사용하는 메서드/이벤트만 정리한다.

## Runtime 도메인

Console 출력을 캡처하는 핵심 도메인.

### 메서드

| 메서드 | 용도 |
|--------|------|
| `Runtime.enable` | execution context 리포팅 활성화. **console 이벤트 수신의 전제조건** |
| `Runtime.disable` | 리포팅 비활성화 |
| `Runtime.evaluate` | JS 표현식 실행. REPL 용도. **`awaitPromise: true` 필수** (아래 참조) |

### 이벤트

| 이벤트 | 발생 시점 | params 주요 필드 |
|--------|-----------|-----------------|
| `Runtime.consoleAPICalled` | `console.log/warn/error/info/debug` 호출 시 | `type`, `args[]`, `stackTrace`, `timestamp` |
| `Runtime.executionContextCreated` | 새 execution context 생성 시 | `context.id`, `context.name` |
| `Runtime.executionContextDestroyed` | context 파괴 시 | `executionContextId` |
| `Runtime.executionContextsCleared` | 모든 context 클리어 시 | — |

#### `Runtime.consoleAPICalled` 상세

```json
{
  "method": "Runtime.consoleAPICalled",
  "params": {
    "type": "log",
    "args": [
      { "type": "string", "value": "Hello from RN" },
      { "type": "object", "className": "Object", "description": "Object", "objectId": "..." }
    ],
    "stackTrace": {
      "callFrames": [
        {
          "functionName": "myFunction",
          "url": "http://localhost:8081/index.bundle?platform=ios",
          "lineNumber": 42,
          "columnNumber": 10
        }
      ]
    },
    "timestamp": 1706000000000
  }
}
```

`args[]` 항목의 `type`:
- `string`, `number`, `boolean` — `.value`에 직접 값
- `object` — `.description`에 요약, `.objectId`로 상세 조회 가능 (`Runtime.getProperties`)
- `undefined` — 값 없음

`type` 필드 값: `log`, `debug`, `info`, `error`, `warning`, `dir`, `table`, `trace`, `clear`

#### `Runtime.evaluate` 상세

```json
{ "id": 2, "method": "Runtime.evaluate", "params": {
    "expression": "fetch('https://api.example.com/health').then(r => r.json())",
    "awaitPromise": true
}}
```

**Hermes 제한사항**:
- `async/await` 구문 사용 불가 → Promise 체인(`.then()`)으로 작성
- `awaitPromise: true`를 넣어야 Promise 결과가 resolve된 후 반환됨 (없으면 pending 상태로 끝남)
- `require`, `global` 없음 → `globalThis` 사용
- `globalThis.__r` = Metro의 require 함수 (불안정, 모듈 접근용)

## Network 도메인 (experimental)

HTTP 요청/응답을 캡처한다.

### 메서드

| 메서드 | 용도 |
|--------|------|
| `Network.enable` | 네트워크 이벤트 수신 활성화 |
| `Network.disable` | 비활성화 |
| `Network.getResponseBody` | 완료된 요청의 응답 body 조회 (experimental) |

### 이벤트

| 이벤트 | 발생 시점 | params 주요 필드 |
|--------|-----------|-----------------|
| `Network.requestWillBeSent` | HTTP 요청 전송 직전 | `requestId`, `request.url`, `request.method`, `request.headers` |
| `Network.responseReceived` | HTTP 응답 수신 | `requestId`, `response.url`, `response.status`, `response.headers` |
| `Network.loadingFinished` | 요청 완료 | `requestId`, `encodedDataLength` |
| `Network.loadingFailed` | 요청 실패 | `requestId`, `errorText` |
| `Network.dataReceived` | 데이터 청크 수신 | `requestId`, `dataLength` |

#### `Network.requestWillBeSent` 상세

```json
{
  "method": "Network.requestWillBeSent",
  "params": {
    "requestId": "1",
    "request": {
      "url": "https://api.example.com/users",
      "method": "GET",
      "headers": { "Authorization": "Bearer ..." }
    },
    "timestamp": 1706000000.123,
    "type": "Fetch"
  }
}
```

#### `Network.responseReceived` 상세

```json
{
  "method": "Network.responseReceived",
  "params": {
    "requestId": "1",
    "response": {
      "url": "https://api.example.com/users",
      "status": 200,
      "statusText": "OK",
      "headers": { "content-type": "application/json" },
      "mimeType": "application/json"
    },
    "timestamp": 1706000000.456
  }
}
```

## 프로토콜 메시지 형식

모든 CDP 메시지는 JSON이며 3가지 유형으로 구분:

```jsonc
// 1. 요청 (클라이언트 → 디바이스)
{ "id": 1, "method": "Runtime.enable" }
{ "id": 2, "method": "Runtime.evaluate", "params": { "expression": "1+1" } }

// 2. 응답 (디바이스 → 클라이언트)
{ "id": 1, "result": {} }
{ "id": 2, "result": { "result": { "type": "number", "value": 2 } } }

// 3. 이벤트 (디바이스 → 클라이언트, id 없음)
{ "method": "Runtime.consoleAPICalled", "params": { ... } }
```

`id`가 있으면 요청/응답, 없으면 이벤트.
