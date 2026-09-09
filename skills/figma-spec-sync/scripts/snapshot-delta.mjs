#!/usr/bin/env node
// Figma 기획 스냅샷 md 두 판본의 구조 delta. raw git diff는 섹션 개명을 거대한 삭제+추가로 보여
// 읽을 수 없으므로, 섹션·화면·기획 설명 단위로 접어 무엇이 실제로 달라졌는지만 남긴다.
//
// 게이트는 정합 plan(base 판본) §Sync 상태의 version과 md(head 판본) 서두의 version을 대조한다.
// commit은 "확인했다"의 표시가 아니다 — plan이 기록한 version만 triage가 끝났다는 마커라서,
// 스냅샷을 승인 전에 commit하는 lane에서는 base를 HEAD가 아니라 publish 지점(main)으로 준다.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';

const USAGE = `Usage: node snapshot-delta.mjs [--config <figma-spec-sync.json>] [--base <rev>] [--head <rev|:worktree>]
                               [--md <path>] [--plan <path>] [--repo <dir>]

  --config  설정 파일. out(md)·plan·deltaBase를 읽는다. 없으면 ./figma-spec-sync.json → ./docs/figma-spec-sync.json
  --base    비교 기준 rev (기본: 설정 deltaBase, 없으면 HEAD)
  --head    비교 대상 rev, 또는 :worktree = working tree 파일 (기본 :worktree)
  --md      스냅샷 md 경로 (설정 out을 덮어쓴다)
  --plan    §Sync 상태 표를 가진 정합 plan 경로 (설정 plan을 덮어쓴다)
  --repo    git repo (기본: 설정 파일 위치의 git toplevel, 설정이 없으면 cwd의 toplevel)`;

const DEFAULT_CONFIG_PATHS = ['figma-spec-sync.json', join('docs', 'figma-spec-sync.json')];

function die(message) {
  console.error(message);
  process.exit(1);
}

const cli = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) {
  const flag = argv[i];
  if (flag === '--help' || flag === '-h') {
    console.log(USAGE);
    process.exit(0);
  }
  const key = flag.replace(/^--/, '');
  if (!flag.startsWith('--') || !['config', 'base', 'head', 'md', 'plan', 'repo'].includes(key)) die(`unknown arg: ${flag}\n\n${USAGE}`);
  if (i + 1 >= argv.length) die(`${flag} 뒤에 값이 없다\n\n${USAGE}`);
  cli[key] = argv[i + 1];
}

const configPath = cli.config ?? DEFAULT_CONFIG_PATHS.find((p) => existsSync(p)) ?? '';
let config = {};
if (configPath) {
  try {
    config = JSON.parse(readFileSync(configPath, 'utf8'));
  } catch (e) {
    die(`설정 파일을 읽을 수 없다: ${configPath} (${e.message})`);
  }
}
const configDir = configPath ? dirname(resolve(configPath)) : process.cwd();

function gitToplevel(dir) {
  try {
    return execFileSync('git', ['-C', dir, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return die(`${dir} 는 git repo 안이 아니다. --repo 로 지정한다`);
  }
}

const repo = cli.repo ? resolve(cli.repo) : gitToplevel(configDir);
// git show 는 repo-relative 경로만 받는다. 설정의 경로는 설정 파일 기준, 플래그의 경로는 cwd 기준으로 해석한다.
const inRepo = (p, base) => (p ? relative(repo, resolve(base, p)) : '');
const opts = {
  base: cli.base ?? config.deltaBase ?? 'HEAD',
  head: cli.head ?? ':worktree',
  md: cli.md ? inRepo(cli.md, process.cwd()) : inRepo(config.out, configDir),
  plan: cli.plan ? inRepo(cli.plan, process.cwd()) : inRepo(config.plan, configDir),
};
if (!opts.md) die(`스냅샷 md 경로가 없다 — 설정 out 또는 --md\n\n${USAGE}`);
if (opts.md.startsWith('..')) die(`md 가 repo 밖이다: ${opts.md} (repo=${repo})`);

function gitShow(spec, { optional = false } = {}) {
  try {
    return execFileSync('git', ['-C', repo, 'show', spec], { encoding: 'utf8', maxBuffer: 64 << 20, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    if (optional) return null;
    const reason = (e.stderr ?? String(e)).trim().split('\n')[0];
    return die(`git show ${spec} 실패: ${reason}\n\n${USAGE}`);
  }
}

function load(rev) {
  if (rev === ':worktree') {
    const path = join(repo, opts.md);
    if (!existsSync(path)) die(`파일 없음: ${path}`);
    return readFileSync(path, 'utf8');
  }
  return gitShow(`${rev}:${opts.md}`);
}

// 섹션은 `## `, 단 문서 서두의 `## 갱신`은 본문이 아니라 사용법이라 제외한다.
function parse(text) {
  const sections = [];
  let current = null;
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const heading = /^## (.+)$/.exec(line);
    if (heading) {
      if (heading[1].trim() === '갱신') {
        current = null;
        continue;
      }
      current = { name: heading[1].trim(), screens: [], specs: [] };
      sections.push(current);
      continue;
    }
    if (!current) continue;
    const row = /^\| (.+?) \| (\d+×\d+) \| \[열기\]/.exec(line);
    if (row) {
      current.screens.push({ name: row[1].trim(), size: row[2] });
      continue;
    }
    if (line.startsWith('<details><summary>')) {
      // 본문은 다음 ```text 펜스 안이다. summary는 28자 라벨이라 판정에 못 쓴다.
      const start = lines.indexOf('```text', i);
      if (start === -1) continue;
      const end = lines.indexOf('```', start + 1);
      if (end === -1) continue;
      current.specs.push({ text: lines.slice(start + 1, end).join('\n').trim() });
      i = end;
    }
  }
  return sections;
}

const total = (list, key) => list.reduce((n, s) => n + s[key].length, 0);

// 파서는 figma-sync.mjs의 렌더 포맷에 결합돼 있고 테스트가 없다. generator가 md 서두에 이미 쓰는
// 요약 줄과 파싱 결과를 대조해, 포맷이 바뀌어 0건으로 읽히는 조용한 실패를 잡는다.
function selfCheck(label, text, sections) {
  const m = /^추출 결과: 섹션 (\d+)개, 기획 설명 (\d+)건/m.exec(text);
  if (!m) return `  ⚠ ${label}: md 서두에 "추출 결과" 요약 줄이 없다 — 파서 자기검증 불가`;
  const want = { sections: Number(m[1]), specs: Number(m[2]) };
  const got = { sections: sections.length, specs: total(sections, 'specs') };
  const problems = [];
  if (want.sections !== got.sections) problems.push(`섹션 서두 ${want.sections} ≠ 파싱 ${got.sections}`);
  if (want.specs !== got.specs) problems.push(`기획 설명 서두 ${want.specs} ≠ 파싱 ${got.specs}`);
  if (sections.length > 0 && total(sections, 'screens') === 0) problems.push('화면 표가 0행으로 읽힘 (표 포맷 변경?)');
  if (problems.length) return `  ⚠ ${label}: ${problems.join(' · ')} — figma-sync.mjs 렌더 포맷이 바뀌었는지 확인, 아래 delta는 신뢰 불가`;
  return `  ${label}: 서두 요약과 파싱 일치 (섹션 ${got.sections} · 기획 설명 ${got.specs})`;
}

const mdVersionOf = (text) => /^Figma file version: `(\d+)`/m.exec(text)?.[1] ?? null;

// "확인했다"의 기계 마커는 commit이 아니라 정합 plan §Sync 상태의 version이다. base 판본의 plan을 읽어
// head md의 version과 다르면 plan이 아직 반영하지 않은 pull이 있다.
function gate(headText) {
  if (!opts.plan) return '  판정 불가: plan 경로가 없다 (설정 plan 또는 --plan)';
  const plan = gitShow(`${opts.base}:${opts.plan}`, { optional: true });
  if (plan === null) return `  판정 불가: ${opts.base}:${opts.plan} 을 읽을 수 없다`;
  const planVersion = /\| Figma file version \| `(\d+)` \|/.exec(plan)?.[1] ?? null;
  if (!planVersion) return '  판정 불가: plan §Sync 상태 표에 `| Figma file version | `<version>` |` 행이 없다';
  const mdVersion = mdVersionOf(headText);
  if (!mdVersion) return `  판정 불가: head md 서두에 "Figma file version" 줄이 없다 (구 포맷) — figma-sync.mjs --force 로 재생성 (plan version=${planVersion})`;
  if (planVersion === mdVersion) return `  plan §Sync 상태 version=${planVersion} = md version → plan이 최신 pull을 반영함. 아래 delta는 비어 있어야 정상`;
  return `  plan §Sync 상태 version=${planVersion} ≠ md version=${mdVersion} → 미반영 pull 있음. 아래 delta가 이번 작업 범위`;
}

const baseText = load(opts.base);
const headText = load(opts.head);
const baseSections = parse(baseText);
const headSections = parse(headText);
const byName = (list) => new Map(list.map((s) => [s.name, s]));
const baseMap = byName(baseSections);
const headMap = byName(headSections);

const out = [];
out.push(`base=${opts.base}  head=${opts.head}  md=${opts.md}  (${repo})`);
out.push('\n[게이트]');
out.push(gate(headText));
out.push('\n[검증]');
out.push(selfCheck(`base ${opts.base}`, baseText, baseSections));
out.push(selfCheck(`head ${opts.head}`, headText, headSections));
out.push(
  `\n섹션 ${baseSections.length}→${headSections.length} · 화면 ${total(baseSections, 'screens')}→${total(headSections, 'screens')} · 기획 설명 ${total(baseSections, 'specs')}→${total(headSections, 'specs')}`,
);

function jaccard(a, b) {
  if (a.size === 0 && b.size === 0) return 0;
  let hit = 0;
  for (const x of a) if (b.has(x)) hit++;
  return hit / (a.size + b.size - hit);
}

function screenSet(section) {
  return new Set(section.screens.map((s) => s.name));
}

const removed = baseSections.filter((s) => !headMap.has(s.name));
const added = headSections.filter((s) => !baseMap.has(s.name));

// 개명·재편 추정: 화면 이름 집합이 겹치면 같은 섹션이 이름만 바뀐 것으로 본다.
// 한 섹션이 둘로 갈리는 경우도 있어 removed 하나가 여러 added에 매칭될 수 있게 둔다.
const lineage = [];
for (const a of added) {
  const scored = removed
    .map((r) => ({ from: r.name, score: jaccard(screenSet(r), screenSet(a)) }))
    .filter((x) => x.score >= 0.3)
    .sort((x, y) => y.score - x.score);
  if (scored.length) lineage.push({ to: a.name, ...scored[0] });
}
const explained = new Set(lineage.map((l) => l.from));

if (!removed.length && !added.length) out.push('\n[섹션] 변화 없음');
else {
  out.push('\n[섹션]');
  for (const l of lineage) out.push(`  ~ ${l.from} → ${l.to}  (화면 겹침 ${(l.score * 100).toFixed(0)}%)`);
  for (const r of removed) if (!explained.has(r.name)) out.push(`  - 사라짐: ${r.name} (화면 ${r.screens.length})`);
  // 신규 섹션은 base 짝이 없어 [화면] 블록에 안 나오므로 여기서 화면 이름을 바로 나열한다.
  for (const a of added) {
    if (lineage.some((l) => l.to === a.name)) continue;
    out.push(`  + 신규: ${a.name} (화면 ${a.screens.length}, 설명 ${a.specs.length})`);
    for (const s of a.screens) out.push(`      · ${s.name}`);
  }
}

out.push('\n[화면]');
let screenNoise = 0;
for (const head of headSections) {
  const from = baseMap.get(head.name) ?? baseSections.find((r) => lineage.some((l) => l.from === r.name && l.to === head.name));
  if (!from) continue;
  const before = screenSet(from);
  const after = screenSet(head);
  const plus = [...after].filter((n) => !before.has(n));
  const minus = [...before].filter((n) => !after.has(n));
  if (!plus.length && !minus.length) continue;
  out.push(`  ${head.name}:`);
  for (const n of plus) out.push(`    + ${n}`);
  for (const n of minus) out.push(`    - ${n}`);
  screenNoise++;
}
if (!screenNoise) out.push('  (기존 섹션의 화면 목록 변화 없음)');

const specKey = (s) => s.text.slice(0, 30);
const baseSpecs = new Map(baseSections.flatMap((s) => s.specs.map((p) => [p.text, s.name])));
const headSpecs = new Map(headSections.flatMap((s) => s.specs.map((p) => [p.text, s.name])));
const specAdded = [...headSpecs].filter(([t]) => !baseSpecs.has(t));
const specRemoved = [...baseSpecs].filter(([t]) => !headSpecs.has(t));
const pairs = [];
for (const [text, section] of specAdded) {
  const hit = specRemoved.find(([old]) => specKey({ text: old }) === specKey({ text }));
  if (hit) pairs.push({ section, before: hit[0], after: text });
}
const paired = new Set(pairs.flatMap((p) => [p.before, p.after]));

out.push('\n[기획 설명]');
if (!specAdded.length && !specRemoved.length) out.push('  변화 없음');
for (const p of pairs) {
  out.push(`  ~ 수정 (${p.section}): ${p.before.split('\n')[0].slice(0, 40)}`);
  out.push(`      before: ${p.before.replace(/\n/g, ' ⏎ ').slice(0, 300)}`);
  out.push(`      after : ${p.after.replace(/\n/g, ' ⏎ ').slice(0, 300)}`);
}
for (const [text, section] of specAdded) {
  if (paired.has(text)) continue;
  out.push(`  + 신규 (${section}):`);
  for (const line of text.split('\n')) out.push(`      ${line}`);
}
for (const [text, section] of specRemoved) {
  if (paired.has(text)) continue;
  out.push(`  - 사라짐 (${section}): ${text.replace(/\n/g, ' ⏎ ').slice(0, 160)}`);
}

console.log(out.join('\n'));
