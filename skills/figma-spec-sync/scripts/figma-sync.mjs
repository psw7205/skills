#!/usr/bin/env node
// Figma REST API → 기획 스냅샷 Markdown (+ 선택적으로 화면 PNG).
//
// MCP(get_metadata)와 달리 에이전트 세션 없이 돌아 반복 pull이 가능하고, 텍스트를 레이어 이름이 아니라
// TEXT 노드의 `characters`(실제 본문)로 읽어 더 정확하다. 파일 `version`을 캐시해 변경됐을 때만 받는다.
//
// Usage: `--help`. 설정은 대상 repo의 figma-spec-sync.json(플래그가 덮어쓴다).
//
// 토큰: env `FIGMA_TOKEN`, 없으면 `~/.config/figma/token` 파일. repo에 커밋하지 않는다.
// 필요 scope는 `file_content:read`(파일 읽기)뿐이다.
//
// md 서두에 파일 version을 기록한다. 이 줄이 "마지막으로 받은 시점"의 마커라서, 이미지 캐시(.sync-state.json)가
// 없는 머신에서도 무변경 조기 종료와 snapshot-delta의 게이트가 md만으로 선다.

import { existsSync, mkdirSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';

const API = 'https://api.figma.com/v1';
const SCREEN_MIN_WIDTH = 1000;
const SCREEN_MIN_HEIGHT = 600;
// 이 길이 이상인 TEXT를 기획 설명으로 본다. 60은 "논의 필요" 류 미결 메모가 들어오는 하한이다.
const SPEC_MIN_LENGTH = 60;
// images API는 id를 쿼리스트링에 싣는다. URL 길이와 서버 렌더 시간을 감안한 배치 크기.
const IMAGE_BATCH = 40;
const DOWNLOAD_CONCURRENCY = 8;

function fail(message) {
  console.error(message);
  process.exit(1);
}

const USAGE = `Usage:
  node figma-sync.mjs [--config <figma-spec-sync.json>] [--force]
  node figma-sync.mjs --file-key <key> --node-id <id> --out <md>
                      [--images <dir>] [--file-slug <slug>] [--title <title>] [--state <json>] [--force]

설정 파일 키: fileKey, nodeId, out, title, fileSlug, images, state (경로는 설정 파일 위치 기준).
--config 없이 돌리면 ./figma-spec-sync.json → ./docs/figma-spec-sync.json 순으로 찾는다. 플래그가 설정을 덮어쓴다.
--force 는 version이 같아도 다시 렌더한다.`;

const DEFAULT_CONFIG_PATHS = ['figma-spec-sync.json', join('docs', 'figma-spec-sync.json')];

function loadConfig(path) {
  let raw;
  try {
    raw = JSON.parse(readFileSync(path, 'utf8'));
  } catch (e) {
    fail(`설정 파일을 읽을 수 없다: ${path} (${e.message})`);
  }
  const dir = dirname(resolve(path));
  const at = (p) => (p ? resolve(dir, p) : '');
  return {
    fileKey: raw.fileKey,
    nodeId: raw.nodeId,
    title: raw.title,
    fileSlug: raw.fileSlug,
    out: at(raw.out),
    images: at(raw.images),
    state: at(raw.state),
  };
}

const compact = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined && v !== ''));

function parseArgs(argv) {
  const cli = {};
  let configPath = '';
  let force = false;
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === '--help' || flag === '-h') {
      console.log(USAGE);
      process.exit(0);
    }
    if (flag === '--force') {
      force = true;
      continue;
    }
    const value = argv[++i];
    if (value === undefined) fail(`missing value for ${flag}\n\n${USAGE}`);
    if (flag === '--config') configPath = value;
    else if (flag === '--file-key') cli.fileKey = value;
    else if (flag === '--node-id') cli.nodeId = value;
    else if (flag === '--out') cli.out = value;
    else if (flag === '--images') cli.images = value;
    else if (flag === '--file-slug') cli.fileSlug = value;
    else if (flag === '--title') cli.title = value;
    else if (flag === '--state') cli.state = value;
    else fail(`unknown arg: ${flag}\n\n${USAGE}`);
  }
  if (!configPath) configPath = DEFAULT_CONFIG_PATHS.find((p) => existsSync(p)) ?? '';
  const fromConfig = configPath ? compact(loadConfig(configPath)) : {};
  const opts = { title: 'Figma 기획 스냅샷', fileSlug: '', images: '', state: '', ...fromConfig, ...cli, force, configForDoc: configPath };
  for (const required of ['fileKey', 'nodeId', 'out']) {
    if (!opts[required]) fail(`required: fileKey, nodeId, out — 설정 파일 또는 --file-key --node-id --out\n\n${USAGE}`);
  }
  // REST는 콜론 형식만 받는다. URL에서 복사한 하이픈 id를 그대로 넘겨도 되게 정규화한다.
  opts.nodeId = opts.nodeId.replace('-', ':');
  if (!opts.state && opts.images) opts.state = join(opts.images, '.sync-state.json');
  return opts;
}

function readToken() {
  const fromEnv = process.env.FIGMA_TOKEN?.trim();
  if (fromEnv) return fromEnv;
  const path = join(homedir(), '.config', 'figma', 'token');
  if (existsSync(path)) {
    const fromFile = readFileSync(path, 'utf8').trim();
    if (fromFile) return fromFile;
  }
  fail(
    [
      'Figma 토큰이 없다. 아래 중 하나로 준다:',
      '  export FIGMA_TOKEN=<token>',
      `  echo '<token>' > ${path} && chmod 600 ${path}`,
      '토큰 발급: Figma → Settings → Security → Personal access tokens (scope: file_content:read)',
    ].join('\n'),
  );
}

async function figmaGet(path, token) {
  const res = await fetch(`${API}${path}`, { headers: { 'X-Figma-Token': token } });
  if (res.status === 403)
    fail('403 — 토큰이 이 파일에 접근할 수 없다. scope(file_content:read)와 파일 권한을 확인한다.');
  if (res.status === 404) fail('404 — file-key 또는 node-id가 없다.');
  if (res.status === 429) fail('429 — Figma rate limit. 잠시 후 다시 시도한다.');
  if (!res.ok) fail(`Figma API ${res.status}: ${(await res.text()).slice(0, 300)}`);
  return res.json();
}

// REST 노드 트리를 렌더러가 쓰는 평면 표현으로 접는다. MCP XML 경로와 같은 shape이라 출력이 동일하다.
function flatten(root) {
  const out = [];
  const walk = (node, depth) => {
    const box = node.absoluteBoundingBox;
    out.push({
      depth,
      type: node.type,
      id: node.id,
      // TEXT는 레이어 이름이 아니라 본문을 쓴다. 이름은 Figma가 본문에서 자동 생성한 사본이라 잘릴 수 있다.
      name: node.type === 'TEXT' ? (node.characters ?? '') : (node.name ?? ''),
      width: box?.width ?? 0,
      height: box?.height ?? 0,
    });
    for (const child of node.children ?? []) walk(child, depth + 1);
  };
  walk(root, 0);
  return out;
}

// `characters`는 실제 개행을 담는다. 기획 설명이 목록 구조라 개행을 접으면 원문 구조가 통째로 뭉개진다
// (MCP의 레이어 이름 경로에는 애초에 개행이 없어 이 정보를 얻을 수 없었다).
// 줄 안의 연속 공백만 접고, 빈 줄은 문단 구분으로 하나까지 남긴다.
function normalizeText(raw) {
  return raw
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map((line) => line.replace(/[ \t]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function groupBySection(nodes) {
  const groups = [];
  // 같은 안내 문구가 여러 화면에 반복 배치돼 있다. 첫 등장만 남긴다.
  const seenSpecs = new Set();
  for (const node of nodes) {
    if (node.depth === 1 && node.type === 'SECTION') {
      groups.push({ section: node, screens: [], specs: [] });
      continue;
    }
    const group = groups.at(-1);
    if (!group) continue;
    if (node.type === 'FRAME' && node.width >= SCREEN_MIN_WIDTH && node.height >= SCREEN_MIN_HEIGHT) {
      group.screens.push(node);
    } else if (node.type === 'TEXT') {
      const text = normalizeText(node.name);
      if (text.length >= SPEC_MIN_LENGTH && !seenSpecs.has(text)) {
        seenSpecs.add(text);
        group.specs.push({ ...node, name: text });
      }
    }
  }
  return groups;
}

function nodeLink({ fileKey, fileSlug }, id) {
  const path = fileSlug ? `${fileKey}/${fileSlug}` : fileKey;
  return `https://www.figma.com/design/${path}?node-id=${id.replace(':', '-')}`;
}

// summary는 raw HTML 안이라 기획 원문의 <꺾쇠>가 태그로 먹혀 사라진다. 본문은 fenced block이라 안전.
// 결과는 텍스트 노드와 alt·title 큰따옴표 속성 양쪽에 들어간다(아래 esc alias).
// 따옴표를 막지 않으면 이름에 `"`가 든 프레임에서 속성이 끊긴다.
function escapeHtml(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function isNamed(node) {
  return node.name && node.name !== '-' && node.name !== 'Container';
}

// 재생성 명령은 문서를 읽는 사람이 그대로 복사해 돌릴 수 있게 실제로 쓴 형태로 남긴다.
function regenerateCommand(opts) {
  if (opts.configForDoc) return [`node <figma-spec-sync 스킬>/scripts/figma-sync.mjs --config ${opts.configForDoc}`];
  const slugArg = opts.fileSlug ? ` --file-slug ${opts.fileSlug}` : '';
  return [
    `node <figma-spec-sync 스킬>/scripts/figma-sync.mjs --file-key ${opts.fileKey} --node-id ${opts.nodeId}${slugArg} \\`,
    `  --title '${opts.title}' --out ${opts.outForDoc}`,
  ];
}

function render(groups, opts) {
  const total = groups.reduce((n, g) => n + g.specs.length, 0);
  const out = [
    `# ${opts.title}`,
    '',
    '이 문서는 Figma REST API로 기계 추출한 **기획 스냅샷**이다. 정본은 Figma이고 여기 담긴 것은 추출 시점의 사본이다.',
    '확정 디자인이 아니므로 구현 판단의 근거로 쓰지 않는다 — 의미·기획 의도를 읽는 용도이고,',
    '현재 동작은 언제나 source와 config가 권위다.',
    '',
    '손으로 고치지 않는다. 갱신은 아래 명령으로 재생성한다(파일 version이 그대로면 아무것도 하지 않는다).',
    '',
    '## 갱신',
    '',
    '```bash',
    ...regenerateCommand(opts),
    '```',
    '',
    '토큰은 env `FIGMA_TOKEN` 또는 `~/.config/figma/token`에서 읽는다(scope: `file_content:read`). repo에 두지 않는다.',
    '화면 PNG까지 받으려면 설정의 `images`(또는 `--images`)를 준다 — 용량이 크고 가장 먼저 낡으므로 repo 밖에 둔다.',
    '',
    `Figma file version: \`${opts.version}\` (최종 수정 ${opts.lastModified})`,
    '',
    `추출 결과: 섹션 ${groups.length}개, 기획 설명 ${total}건.`,
    '',
  ];

  for (const group of groups) {
    const name = group.section.name;
    out.push(`## ${name}`, '', `[섹션 열기](${nodeLink(opts, group.section.id)})`, '');
    const named = group.screens.filter(isNamed);
    if (named.length === 0) {
      out.push('_명명된 화면 프레임 없음._', '');
    } else {
      out.push('| 화면 | 크기 | Figma |', '|---|---|---|');
      for (const s of named) {
        out.push(`| ${s.name} | ${Math.round(s.width)}×${Math.round(s.height)} | [열기](${nodeLink(opts, s.id)}) |`);
      }
      out.push('');
    }
    if (group.specs.length === 0) continue;
    out.push('### 기획 설명', '');
    for (const spec of group.specs) {
      // summary는 한 줄짜리 표면이라 본문 개행을 접어 라벨을 만든다(본문 자체는 개행을 유지한다).
      const flat = spec.name.replace(/\n/g, ' ');
      const head = flat.slice(0, 28).trim() + (flat.length > 28 ? '…' : '');
      out.push(
        `<details><summary>${escapeHtml(head)} — <a href="${nodeLink(opts, spec.id)}">Figma</a></summary>`,
        '',
        '```text',
        spec.name,
        '```',
        '',
        '</details>',
        '',
      );
    }
  }
  return out.join('\n');
}

function screenFileName(index, name) {
  const safe = (name || 'untitled').replace(/[\s/]+/g, '_').replace(/[<>:"\\|?*]/g, '');
  return `${String(index).padStart(2, '0')}_${safe}.png`;
}

async function downloadImages(groups, opts, token) {
  const targets = [];
  for (const group of groups) {
    let n = 0;
    for (const screen of group.screens) {
      n++;
      targets.push({
        id: screen.id,
        section: group.section.name,
        name: isNamed(screen) ? screen.name : `무제-${n}`,
        size: `${Math.round(screen.width)}x${Math.round(screen.height)}`,
      });
    }
  }
  mkdirSync(opts.images, { recursive: true });

  const urls = new Map();
  for (let i = 0; i < targets.length; i += IMAGE_BATCH) {
    const batch = targets.slice(i, i + IMAGE_BATCH);
    const ids = batch.map((t) => t.id).join(',');
    const res = await figmaGet(`/images/${opts.fileKey}?ids=${encodeURIComponent(ids)}&format=png&scale=1`, token);
    if (res.err) fail(`images API error: ${res.err}`);
    for (const [id, url] of Object.entries(res.images ?? {})) if (url) urls.set(id, url);
    console.error(`  렌더 요청 ${Math.min(i + IMAGE_BATCH, targets.length)}/${targets.length}`);
  }

  let done = 0;
  let missing = 0;
  const written = new Set();
  const queue = targets.map((t, i) => ({ ...t, index: i + 1 }));
  const workers = Array.from({ length: DOWNLOAD_CONCURRENCY }, async () => {
    for (;;) {
      const item = queue.shift();
      if (!item) return;
      const url = urls.get(item.id);
      if (!url) {
        missing++;
        continue;
      }
      const res = await fetch(url);
      if (!res.ok) {
        missing++;
        continue;
      }
      const bytes = Buffer.from(await res.arrayBuffer());
      const file = screenFileName(item.index, item.name);
      writeFileSync(join(opts.images, file), bytes);
      written.add(file);
      done++;
    }
  });
  await Promise.all(workers);

  // 화면이 추가되면 뒤쪽 index가 통째로 밀려, 이전 run의 PNG가 현행과 같은 번호대에 남는다.
  // index.html은 현행만 가리키지만 파일명으로 훑으면 구판이 현행으로 읽히므로 지운다.
  // 받지 못한 장이 있으면 돌리지 않는다 — 실패한 화면의 이전 정상본까지 지워지고 그 자리를
  // 다시 채울 수 없다. 전량 실패도 missing으로 걸린다. 화면이 0장인 정상 결과에서는
  // 그대로 돌아 디렉토리를 비운다.
  const stale = missing === 0 ? pruneStale(opts.images, written) : 0;
  writeGallery(targets, opts);
  return { done, missing, stale };
}

function pruneStale(dir, keep) {
  let removed = 0;
  for (const name of readdirSync(dir)) {
    if (!name.endsWith('.png') || keep.has(name)) continue;
    unlinkSync(join(dir, name));
    removed++;
  }
  return removed;
}

// 브라우저로 한 번에 훑는 로컬 인덱스. repo에 들어가지 않으므로 이미지와 같은 디렉토리에 둔다.
function writeGallery(targets, opts) {
  const bySection = new Map();
  targets.forEach((t, i) => {
    if (!bySection.has(t.section)) bySection.set(t.section, []);
    bySection.get(t.section).push({ ...t, index: i + 1 });
  });
  const esc = escapeHtml;
  let html = `<!doctype html><meta charset=utf-8><title>${esc(opts.title)} — 화면</title>
<style>
:root{color-scheme:light dark}
body{font:14px/1.5 -apple-system,system-ui,sans-serif;margin:0;padding:24px;background:#f6f7f9;color:#111}
@media(prefers-color-scheme:dark){body{background:#16181d;color:#e8e8ea}.card{background:#22252b!important;border-color:#31343c!important}h2{border-color:#31343c!important}}
h1{font-size:20px;margin:0 0 4px}
.meta{color:#777;margin-bottom:24px}
h2{font-size:16px;margin:32px 0 12px;padding-bottom:6px;border-bottom:1px solid #d8dae0}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:16px}
.card{background:#fff;border:1px solid #e2e4ea;border-radius:10px;overflow:hidden}
.card img{width:100%;display:block;background:#fafafa;cursor:zoom-in}
.cap{padding:8px 10px;font-size:12px;display:flex;justify-content:space-between;gap:8px;align-items:center}
.cap b{font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cap a{color:#3b82f6;text-decoration:none;flex:none}
.sz{color:#999;font-size:11px}
</style>
<h1>${esc(opts.title)} — 화면</h1>
<div class=meta>${targets.length}개 · 확정 디자인 아님 · 이미지 클릭 시 원본, 오른쪽 링크는 Figma</div>`;
  for (const [section, items] of bySection) {
    html += `<h2>${esc(section)} <span class=sz>(${items.length})</span></h2><div class=grid>`;
    for (const item of items) {
      const file = encodeURIComponent(screenFileName(item.index, item.name));
      html += `<div class=card><a href="./${file}" target=_blank><img loading=lazy src="./${file}" alt="${esc(item.name)}"></a>
<div class=cap><b title="${esc(item.name)}">${item.index}. ${esc(item.name)}</b><a href="${nodeLink(opts, item.id)}" target=_blank>Figma ↗</a></div>
<div class=cap><span class=sz>${item.size}</span></div></div>`;
    }
    html += '</div>';
  }
  writeFileSync(join(opts.images, 'index.html'), html);
}

function readState(path) {
  if (!path || !existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    return null;
  }
}

// 마지막으로 받은 version. 이미지 캐시 state가 있으면 그것, 없으면 기존 md 서두의 version 줄.
// md 판정이 있어야 state 파일이 없는 머신(clone만 한 곳)에서도 무변경 조기 종료가 된다.
function readPrevVersion(opts) {
  const state = readState(opts.state);
  if (state?.version) return state.version;
  if (!existsSync(opts.out)) return null;
  return /^Figma file version: `(\d+)`/m.exec(readFileSync(opts.out, 'utf8'))?.[1] ?? null;
}

const opts = parseArgs(process.argv.slice(2));
opts.outForDoc = opts.out;
const token = readToken();

const meta = await figmaGet(`/files/${opts.fileKey}?depth=1`, token);
const prevVersion = readPrevVersion(opts);
if (!opts.force && prevVersion === meta.version) {
  console.log(`변경 없음 (version ${meta.version}, 최종 수정 ${meta.lastModified}). --force로 강제 재생성.`);
  process.exit(0);
}
if (prevVersion) console.log(`변경 감지: version ${prevVersion} → ${meta.version}`);
opts.version = meta.version;
opts.lastModified = meta.lastModified;

const tree = await figmaGet(`/files/${opts.fileKey}/nodes?ids=${encodeURIComponent(opts.nodeId)}`, token);
const root = tree.nodes?.[opts.nodeId]?.document;
if (!root) fail(`node ${opts.nodeId} 가 응답에 없다. node-id를 확인한다.`);

const groups = groupBySection(flatten(root));
mkdirSync(dirname(opts.out), { recursive: true });
writeFileSync(opts.out, render(groups, opts));
const screens = groups.reduce((n, g) => n + g.screens.length, 0);
const specs = groups.reduce((n, g) => n + g.specs.length, 0);
console.log(`${opts.out}: 섹션 ${groups.length}개 · 화면 ${screens}개 · 기획 설명 ${specs}건`);

let incomplete = false;
if (opts.images) {
  const { done, missing, stale } = await downloadImages(groups, opts, token);
  incomplete = missing > 0;
  const notes = [missing ? `렌더 실패 ${missing}장` : '', stale ? `이전 산출물 ${stale}장 삭제` : '']
    .filter(Boolean)
    .join(', ');
  console.log(`${opts.images}: PNG ${done}장${notes ? ` (${notes})` : ''} + index.html`);
}

if (incomplete) {
  console.log('일부 화면을 받지 못해 version을 기록하지 않는다 — 다음 실행이 다시 받는다.');
}

// 부분 실패를 완료로 기록하면 다음 실행이 version 게이트에서 조기 종료해, 못 받은 PNG가
// 영구히 복구되지 않는다. 기록하지 않으면 state가 구 version으로 남아 다음 실행이 다시 받는다.
if (opts.state && !incomplete) {
  mkdirSync(join(opts.state, '..'), { recursive: true });
  writeFileSync(
    opts.state,
    `${JSON.stringify({ version: meta.version, lastModified: meta.lastModified, syncedAt: new Date().toISOString() }, null, 2)}\n`,
  );
}
