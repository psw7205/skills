#!/usr/bin/env node

/**
 * CDP Console + Network Bridge for React Native Metro
 *
 * Metro InspectorProxy에 CDP WebSocket으로 연결하여
 * Runtime.consoleAPICalled / Network.* 이벤트를 터미널에 스트리밍한다.
 *
 * Usage:
 *   node cdp-console.mjs [options]
 *
 * Options:
 *   --port <n>           Metro 포트 (기본 8081)
 *   --network            네트워크 요청도 출력
 *   --target <substring> deviceName 또는 title 부분 매칭
 */

import { parseArgs } from "node:util";

// -- CLI args ----------------------------------------------------------------

const { values: args } = parseArgs({
  options: {
    port: { type: "string", default: "8081" },
    network: { type: "boolean", default: false },
    target: { type: "string", default: "" },
  },
});

const PORT = Number(args.port);
const SHOW_NETWORK = args.network;
const TARGET_FILTER = args.target.toLowerCase();

// -- WebSocket shimming (Node built-in → ws fallback) ------------------------

let WS;
if (typeof globalThis.WebSocket !== "undefined") {
  WS = globalThis.WebSocket;
} else {
  try {
    WS = (await import("ws")).default;
  } catch {
    console.error(
      "[cdp-bridge] WebSocket 불가. Node 22+ 이거나 ws 패키지가 필요합니다.",
    );
    process.exit(1);
  }
}

// -- fetch shimming (Node 18 experimental → node-fetch fallback) -------------

let _fetch = globalThis.fetch;
if (!_fetch) {
  try {
    _fetch = (await import("node-fetch")).default;
  } catch {
    console.error(
      "[cdp-bridge] fetch 불가. Node 18+이거나 node-fetch 패키지가 필요합니다.",
    );
    process.exit(1);
  }
}

// -- Target discovery --------------------------------------------------------

async function fetchTargets(port) {
  const res = await _fetch(`http://localhost:${port}/json/list`);
  if (!res.ok) throw new Error(`/json/list responded ${res.status}`);
  return res.json();
}

function selectTarget(targets) {
  if (!targets.length) return null;

  let pool = targets;

  // --target 필터
  if (TARGET_FILTER) {
    pool = pool.filter(
      (t) =>
        (t.deviceName || "").toLowerCase().includes(TARGET_FILTER) ||
        (t.title || "").toLowerCase().includes(TARGET_FILTER),
    );
    if (!pool.length) return null;
  }

  // Bridgeless 우선
  const bridgeless = pool.filter(
    (t) => t.reactNative?.capabilities?.nativePageReloads,
  );
  if (bridgeless.length) return bridgeless[0];

  // Hermes 우선
  const hermes = pool.filter((t) => /hermes/i.test(t.vm || ""));
  if (hermes.length) return hermes[0];

  return pool[0];
}

// -- Formatting --------------------------------------------------------------

const LEVEL_COLORS = {
  log: "\x1b[0m",
  info: "\x1b[36m",
  warn: "\x1b[33m",
  error: "\x1b[31m",
  debug: "\x1b[90m",
};
const RESET = "\x1b[0m";
const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";

function formatConsoleArgs(args) {
  return args
    .map((a) => {
      if (a.type === "string" || a.type === "number" || a.type === "boolean")
        return String(a.value);
      if (a.type === "undefined") return "undefined";
      if (a.type === "object" && a.preview?.properties) {
        const props = a.preview.properties
          .map((p) => `${p.name}: ${p.value}`)
          .join(", ");
        return `{ ${props} }`;
      }
      return a.description || a.type;
    })
    .join(" ");
}

function printConsole(params) {
  const level = params.type || "log";
  const color = LEVEL_COLORS[level] || LEVEL_COLORS.log;
  const tag = level.toUpperCase().padEnd(5);
  const msg = formatConsoleArgs(params.args || []);
  const frame = params.stackTrace?.callFrames?.[0];
  const loc = frame ? `${DIM}${frame.url?.split("/").pop()}:${frame.lineNumber}${RESET}` : "";

  console.log(`${color}[${tag}]${RESET} ${msg} ${loc}`);
}

function printNetworkRequest(params) {
  const { method, url } = params.request || {};
  console.log(`${DIM}[NET →]${RESET} ${BOLD}${method}${RESET} ${url}`);
}

function printNetworkResponse(params) {
  const { status, url } = params.response || {};
  const color = status >= 400 ? LEVEL_COLORS.error : LEVEL_COLORS.info;
  console.log(`${DIM}[NET ←]${RESET} ${color}${status}${RESET} ${url}`);
}

function printNetworkFailed(params) {
  console.log(
    `${LEVEL_COLORS.error}[NET ✗]${RESET} ${params.errorText} (id: ${params.requestId})`,
  );
}

// -- CDP connection ----------------------------------------------------------

let msgId = 0;

function connect(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WS(wsUrl);

    ws.onopen = () => {
      // Runtime.enable 필수
      ws.send(JSON.stringify({ id: ++msgId, method: "Runtime.enable" }));

      if (SHOW_NETWORK) {
        ws.send(JSON.stringify({ id: ++msgId, method: "Network.enable" }));
      }

      // 연결 후 에러는 로깅만 (reconnect 루프가 onclose에서 처리)
      ws.onerror = (err) => {
        console.error(`${DIM}[cdp-bridge] WebSocket 에러: ${err.message || err}${RESET}`);
      };

      resolve(ws);
    };

    ws.onmessage = (event) => {
      const data = typeof event.data === "string" ? event.data : event.data.toString();
      let msg;
      try {
        msg = JSON.parse(data);
      } catch {
        return;
      }

      // 이벤트만 처리 (id 없는 메시지)
      if (msg.id != null) return;

      switch (msg.method) {
        case "Runtime.consoleAPICalled":
          printConsole(msg.params);
          break;
        case "Network.requestWillBeSent":
          printNetworkRequest(msg.params);
          break;
        case "Network.responseReceived":
          printNetworkResponse(msg.params);
          break;
        case "Network.loadingFailed":
          printNetworkFailed(msg.params);
          break;
      }
    };

    ws.onerror = (err) => reject(err);
  });
}

// -- Reconnection loop -------------------------------------------------------

const MAX_RETRIES = 8;

async function run() {
  let retries = 0;

  while (retries <= MAX_RETRIES) {
    try {
      console.log(`${DIM}[cdp-bridge] localhost:${PORT} 에서 target 탐색 중...${RESET}`);
      const targets = await fetchTargets(PORT);
      const target = selectTarget(targets);

      if (!target) {
        console.error(
          `[cdp-bridge] 연결 가능한 target 없음.`,
          TARGET_FILTER ? `(필터: "${TARGET_FILTER}")` : "",
          `\n${DIM}확인: Metro가 실행 중인지, 앱이 디바이스에서 열려 있는지 점검.${RESET}`,
        );
        process.exit(1);
      }

      const wsUrl = target.webSocketDebuggerUrl;
      console.log(
        `${DIM}[cdp-bridge] 연결: ${target.title}${RESET}`,
        target.deviceName ? `${DIM}(${target.deviceName})${RESET}` : "",
      );
      console.log(`${DIM}[cdp-bridge] ${wsUrl}${RESET}`);
      console.log(
        `${DIM}[cdp-bridge] 모드: console${SHOW_NETWORK ? " + network" : ""}${RESET}\n`,
      );

      const ws = await connect(wsUrl);
      retries = 0; // 연결 성공 시 리셋

      // 종료 대기
      await new Promise((resolve) => {
        ws.onclose = () => {
          console.log(`\n${DIM}[cdp-bridge] 연결 끊김. 재연결 시도...${RESET}`);
          resolve();
        };
      });
    } catch (err) {
      retries++;
      if (retries > MAX_RETRIES) {
        console.error(`[cdp-bridge] 재연결 실패 (${MAX_RETRIES}회 초과). 종료.`);
        process.exit(1);
      }
      const delay = Math.min(1000 * 2 ** (retries - 1), 16000);
      console.log(
        `${DIM}[cdp-bridge] 재연결 ${retries}/${MAX_RETRIES} (${delay / 1000}s 후)...${RESET}`,
      );
      await new Promise((r) => setTimeout(r, delay));
    }
  }
}

run();
