#!/usr/bin/env python3
"""Aggregate Claude Code transcripts into cost-equation terms and anti-pattern flags.

Reads ~/.claude/projects/<encoded-cwd>/*.jsonl (main sessions) plus
<session-id>/subagents/*.jsonl (Agent tool runs). Stdlib only.
"""
import argparse
import glob
import json
import os
import re
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime

# Anthropic public price ratios relative to uncached input: 1h cache write 2x,
# cache read 0.1x, output ~5x. Ratios, not prices; override with --weights.
DEFAULT_WEIGHTS = {"in": 1.0, "cw": 2.0, "cr": 0.1, "out": 5.0}
REWRITE_RATIO = 0.5          # cache_write > 50% of context = whole prefix rewritten
BIG_RESULT_CHARS = 40_000    # one tool_result this large is re-read on every later request
COMPACT_CAP = 400_000        # context size where compaction should already have happened
IDLE_SHORT = 300             # 5-minute cache TTL boundary
IDLE_LONG = 3600             # 1-hour cache TTL boundary
TOKEN_KEYS = ("input_tokens", "cache_creation_input_tokens",
              "cache_read_input_tokens", "output_tokens")


def claude_home():
    return os.environ.get("CLAUDE_HOME") or os.path.expanduser("~/.claude")


def encode_project_dir(path):
    return re.sub(r"[^A-Za-z0-9-]", "-", os.path.abspath(path))


def resolve_dirs(args):
    if args.dir:
        return [os.path.abspath(d) for d in args.dir]
    root = os.path.join(claude_home(), "projects")
    if not os.path.isdir(root):
        sys.exit(f"projects root not found: {root}")
    names = sorted(os.listdir(root))
    dirs = []
    for project in (args.project or [os.getcwd()]):
        enc = encode_project_dir(project)
        hits = [n for n in names if n == enc]
        if not hits:
            # older Claude Code versions kept '.' in the encoded name
            alt = os.path.abspath(project).replace("/", "-")
            hits = [n for n in names if n == alt]
        if args.include_nested:
            hits += [n for n in names if n.startswith(enc + "-") and n not in hits]
        if not hits:
            close = [n for n in names if enc[-20:] in n][:5]
            sys.exit(f"no transcript dir for {project} (looked for {enc}); close: {close}")
        dirs += [os.path.join(root, n) for n in hits]
    return dirs


def select_sessions(dirs, last, since_days, session_id):
    files = []
    for d in dirs:
        files += glob.glob(os.path.join(d, "*.jsonl"))
    if session_id:
        files = [f for f in files if session_id in os.path.basename(f)]
    if since_days:
        cutoff = time.time() - since_days * 86400
        files = [f for f in files if os.path.getmtime(f) >= cutoff]
    files.sort(key=os.path.getmtime)
    if last and len(files) > last:
        files = files[-last:]
    sessions = []
    for f in files:
        sid = os.path.basename(f)[:-6]
        subs = sorted(glob.glob(os.path.join(os.path.dirname(f), sid, "subagents", "*.jsonl")))
        sessions.append((sid, f, subs))
    return sessions


def records(path):
    with open(path, errors="ignore") as fh:
        for line in fh:
            try:
                yield json.loads(line)
            except ValueError:
                continue


def parse_ts(rec):
    ts = rec.get("timestamp")
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def pct(xs, p):
    if not xs:
        return 0
    xs = sorted(xs)
    return xs[int(p * (len(xs) - 1))]


def blocks(msg):
    content = (msg or {}).get("content")
    return [b for b in content if isinstance(b, dict)] if isinstance(content, list) else []


def result_size(block):
    content = block.get("content")
    chars, images = 0, 0
    if isinstance(content, str):
        chars = len(content)
    elif isinstance(content, list):
        for b in content:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "text":
                chars += len(b.get("text", ""))
            elif b.get("type") == "image":
                images += 1
                chars += len(json.dumps(b))
    return chars, images


class Audit:
    def __init__(self):
        self.seen_ids = set()
        self.seen_tool_ids = set()
        self.id2tool = {}
        self.sessions = 0
        self.requests = 0
        self.sub_requests = 0
        self.user_turns = 0
        self.compactions = 0
        self.req_per_turn = []
        self.ctx = []
        self.first_ctx = []
        self.tok = defaultdict(Counter)
        self.sub_tok = defaultdict(Counter)
        self.rewrite = Counter()
        self.rewrite_tok = Counter()
        self.idle = {"after_5m": Counter(), "after_1h": Counter()}
        self.tool_chars = Counter()
        self.tool_results = Counter()
        self.tool_big = Counter()
        self.tool_images = Counter()
        self.tool_calls = Counter()
        self.agent_calls = Counter()
        self.mcp = Counter()
        self.effort = Counter()
        self.sub_req_by_model = Counter()
        self.first_ts = None
        self.last_ts = None
        self.tool_big_chars = Counter()

    def note_tool_use(self, block):
        tid, name = block.get("id"), block.get("name", "?")
        if tid:
            self.id2tool[tid] = name
        if tid in self.seen_tool_ids:
            return
        self.seen_tool_ids.add(tid)
        self.tool_calls[name] += 1
        if name == "Agent":
            inp = block.get("input") or {}
            self.agent_calls[(inp.get("subagent_type") or "default", inp.get("model") or "inherit")] += 1
        elif name.startswith("mcp__"):
            parts = name.split("__")
            self.mcp[parts[1] if len(parts) > 1 else name] += 1

    def note_tool_result(self, block):
        name = self.id2tool.get(block.get("tool_use_id"), "?")
        chars, images = result_size(block)
        self.tool_results[name] += 1
        self.tool_chars[name] += chars
        self.tool_images[name] += images
        if chars > BIG_RESULT_CHARS:
            self.tool_big[name] += 1
            self.tool_big_chars[name] += chars

    def add_subagent(self, path):
        for rec in records(path):
            msg = rec.get("message") or {}
            if rec.get("type") != "assistant":
                continue
            for b in blocks(msg):
                if b.get("type") == "tool_use":
                    self.note_tool_use(b)
            usage = msg.get("usage")
            mid = msg.get("id") or rec.get("requestId") or rec.get("uuid")
            if not usage or mid in self.seen_ids:
                continue
            self.seen_ids.add(mid)
            if sum(usage.get(k, 0) or 0 for k in TOKEN_KEYS) == 0:
                continue
            self.sub_requests += 1
            self.sub_req_by_model[msg.get("model", "?")] += 1
            for k in TOKEN_KEYS:
                self.sub_tok[msg.get("model", "?")][k] += usage.get(k, 0) or 0

    def add_session(self, path, sub_paths):
        self.sessions += 1
        first, compacted, prev_model, prev_ts, in_turn = True, False, None, None, 0
        for rec in records(path):
            msg = rec.get("message") or {}
            ts = parse_ts(rec)
            if ts:
                self.first_ts = min(self.first_ts, ts) if self.first_ts else ts
                self.last_ts = max(self.last_ts, ts) if self.last_ts else ts
            if rec.get("isCompactSummary"):
                compacted = True
                self.compactions += 1
                continue
            if rec.get("type") == "user" and not rec.get("isMeta"):
                results = [b for b in blocks(msg) if b.get("type") == "tool_result"]
                if results:
                    for b in results:
                        self.note_tool_result(b)
                    continue
                if in_turn:
                    self.req_per_turn.append(in_turn)
                in_turn = 0
                self.user_turns += 1
                continue
            if rec.get("type") != "assistant":
                continue
            for b in blocks(msg):
                if b.get("type") == "tool_use":
                    self.note_tool_use(b)
            usage = msg.get("usage")
            mid = msg.get("id") or rec.get("requestId") or rec.get("uuid")
            if not usage or mid in self.seen_ids:
                continue
            self.seen_ids.add(mid)
            i = usage.get("input_tokens", 0) or 0
            cw = usage.get("cache_creation_input_tokens", 0) or 0
            cr = usage.get("cache_read_input_tokens", 0) or 0
            ctx = i + cw + cr
            if ctx == 0:
                continue
            model = msg.get("model", "?")
            # cache TTL is measured between consecutive API requests, so the gap
            # is request-to-request (covers long tool waits, not only user idle)
            gap = (ts - prev_ts).total_seconds() if ts and prev_ts else None
            self.requests += 1
            in_turn += 1
            self.ctx.append(ctx)
            if first:
                self.first_ctx.append(ctx)
            for k in TOKEN_KEYS:
                self.tok[model][k] += usage.get(k, 0) or 0
            if rec.get("effort"):
                self.effort[rec["effort"]] += 1
            rewrite = cw > REWRITE_RATIO * ctx
            if rewrite:
                if first:
                    cause = "session first request"
                elif compacted:
                    cause = "after compaction"
                elif prev_model and model != prev_model:
                    cause = "model switch"
                elif gap is not None and gap > IDLE_LONG:
                    cause = "idle >1h"
                elif gap is not None and gap > IDLE_SHORT:
                    cause = "idle 5m-1h"
                else:
                    cause = "other (no gap, same model)"
                self.rewrite[cause] += 1
                self.rewrite_tok[cause] += cw
            if gap is not None and not first:
                if gap > IDLE_SHORT:
                    self.idle["after_5m"]["requests"] += 1
                    self.idle["after_5m"]["cache_miss"] += int(rewrite)
                if gap > IDLE_LONG:
                    self.idle["after_1h"]["requests"] += 1
                    self.idle["after_1h"]["cache_miss"] += int(rewrite)
            compacted, first, prev_model = False, False, model
            if ts:
                prev_ts = ts
        if in_turn:
            self.req_per_turn.append(in_turn)
        for sp in sub_paths:
            self.add_subagent(sp)

    # ---- report -----------------------------------------------------------
    def totals(self, table):
        t = Counter()
        for c in table.values():
            t.update(c)
        return t

    def report(self, weights, top):
        main, sub = self.totals(self.tok), self.totals(self.sub_tok)
        both = main + sub
        cat = {"in": both["input_tokens"], "cw": both["cache_creation_input_tokens"],
               "cr": both["cache_read_input_tokens"], "out": both["output_tokens"]}
        weighted = {k: cat[k] * weights[k] for k in cat}
        wtot = sum(weighted.values()) or 1
        sub_w = sum(sub[k] * w for k, w in zip(TOKEN_KEYS, (weights["in"], weights["cw"], weights["cr"], weights["out"])))
        main_cw = main["cache_creation_input_tokens"] or 1
        rw_tok = sum(self.rewrite_tok.values())

        def model_rows(table):
            rows = {}
            for m, c in sorted(table.items(), key=lambda kv: -sum(kv[1].values())):
                ctx_tot = c["input_tokens"] + c["cache_creation_input_tokens"] + c["cache_read_input_tokens"]
                rows[m] = dict(c)
                rows[m]["cache_read_share"] = round(c["cache_read_input_tokens"] / ctx_tot, 4) if ctx_tot else 0
            return rows

        total_chars = sum(self.tool_chars.values()) or 1
        by_tool = [{"tool": n, "results": self.tool_results[n], "chars": ch,
                    "share": round(ch / total_chars, 4),
                    "avg_chars": ch // max(self.tool_results[n], 1),
                    "over_40kb": self.tool_big[n], "over_40kb_chars": self.tool_big_chars[n],
                    "images": self.tool_images[n]}
                   for n, ch in self.tool_chars.most_common(top)]
        r = {
            "period": {"from": self.first_ts.isoformat() if self.first_ts else None,
                       "to": self.last_ts.isoformat() if self.last_ts else None},
            "summary": {
                "sessions": self.sessions, "requests": self.requests,
                "subagent_requests": self.sub_requests, "user_turns": self.user_turns,
                "compactions": self.compactions,
                "requests_per_turn": {"median": pct(self.req_per_turn, .5),
                                      "p90": pct(self.req_per_turn, .9),
                                      "max": max(self.req_per_turn) if self.req_per_turn else 0},
            },
            "context": {
                "first_request_median": pct(self.first_ctx, .5),
                "first_request_p90": pct(self.first_ctx, .9),
                "per_request_median": pct(self.ctx, .5),
                "per_request_p90": pct(self.ctx, .9),
                "per_request_max": max(self.ctx) if self.ctx else 0,
                "over_200k": sum(1 for x in self.ctx if x > 200_000),
                "over_400k": sum(1 for x in self.ctx if x > COMPACT_CAP),
                "excess_over_400k": sum(x - COMPACT_CAP for x in self.ctx if x > COMPACT_CAP),
            },
            "tokens": {"main": model_rows(self.tok), "subagent": model_rows(self.sub_tok)},
            "spend_share": {"weights": weights, "tokens": cat,
                            "shares": {k: round(v / wtot, 4) for k, v in weighted.items()},
                            "subagent_share": round(sub_w / wtot, 4),
                            "subagent_weighted_tokens": int(sub_w)},
            "prefix_rewrites": {
                "events": sum(self.rewrite.values()), "tokens": rw_tok,
                "share_of_cache_write": round(rw_tok / main_cw, 4),
                "by_cause": [{"cause": c, "events": n, "tokens": self.rewrite_tok[c],
                              "share": round(self.rewrite_tok[c] / (rw_tok or 1), 4)}
                             for c, n in self.rewrite.most_common()],
            },
            "idle": {k: {"requests": v["requests"], "cache_miss": v["cache_miss"]} for k, v in self.idle.items()},
            "tool_results": {"total_chars": sum(self.tool_chars.values()),
                             "results": sum(self.tool_results.values()), "by_tool": by_tool},
            "tool_calls": [{"tool": n, "calls": c} for n, c in self.tool_calls.most_common(top)],
            "subagents": {
                "agent_calls": [{"subagent_type": t, "model": m, "calls": c}
                                for (t, m), c in self.agent_calls.most_common()],
                "transcript_requests": self.sub_requests,
                "transcript_models": dict(self.sub_req_by_model.most_common()),
            },
            "mcp": {"calls": sum(self.mcp.values()),
                    "by_server": [{"server": s, "calls": c} for s, c in self.mcp.most_common()]},
            "effort": dict(self.effort.most_common()),
        }
        r["flags"] = self.flags(r)
        return r

    def flags(self, r):
        f = []
        s, c, pr = r["summary"], r["context"], r["prefix_rewrites"]
        share = r["spend_share"]["shares"]
        w = r["spend_share"]["weights"]

        # impact_weighted: input-token equivalent under the same weights, so flags of
        # different token kinds (re-read, rewrite, output) sort on one scale
        def add(fid, sev, metric, threshold, impact, fix, impact_weighted):
            f.append({"id": fid, "severity": sev, "metric": metric, "threshold": threshold,
                      "impact": impact, "impact_weighted": int(impact_weighted), "remediation": fix})

        if c["first_request_median"] > 60_000:
            add("prompt-init-overhead", "warn",
                f"first request context median {c['first_request_median']:,} tokens",
                "> 60,000 before any user input",
                f"re-read as cache on every one of {s['requests']:,} requests",
                "trim always-loaded instructions (CLAUDE.md/AGENTS.md chain, memory index, "
                "skill list); keep MCP tool schemas deferred",
                c["first_request_median"] * s["requests"] * w["cr"])
        if s["requests"] and c["over_400k"] / s["requests"] > 0.05:
            add("context-over-400k", "warn",
                f"{c['over_400k']:,} of {s['requests']:,} requests above 400K context; "
                f"compactions={s['compactions']}",
                "> 5% of requests above 400K",
                f"p90 context {c['per_request_p90']:,}, max {c['per_request_max']:,}",
                "set autoCompactWindow near 400K (Claude Code settings) or /compact before "
                "long tails; split long cycles across sessions",
                c["excess_over_400k"] * w["cr"])
        if pr["share_of_cache_write"] > 0.30 and pr["events"] > s["sessions"]:
            causes = ", ".join(f"{x['cause']} {x['events']}x/{x['tokens']:,}" for x in pr["by_cause"])
            add("prefix-rewrite-waste", "warn",
                f"{pr['share_of_cache_write']:.0%} of cache writes are whole-prefix rewrites "
                f"({pr['events']} events, {pr['tokens']:,} tokens)",
                "> 30% of cache write tokens",
                causes,
                "avoid /model switches mid-session (each model has its own prompt cache); "
                "resume >1h-idle sessions with /compact or a fresh session; keep 1h promptCacheTtl",
                pr["tokens"] * w["cw"])
        by_cause = {x["cause"]: x for x in pr["by_cause"]}
        if by_cause.get("model switch", {}).get("events", 0) > 0:
            x = by_cause["model switch"]
            add("model-switch-rewrite", "info",
                f"{x['events']} model switches rewrote {x['tokens']:,} tokens",
                "any", "full uncached re-read of the conversation per switch",
                "pick the model at session start; split plan/implement phases by session, not by /model",
                x["tokens"] * w["cw"])
        if by_cause.get("idle >1h", {}).get("events", 0) > 0:
            x = by_cause["idle >1h"]
            add("idle-expiry-rewrite", "info",
                f"{x['events']} resumes after >1h idle rewrote {x['tokens']:,} tokens",
                "any", "1h TTL cannot cover these gaps",
                "/compact before leaving, or start a new session on return",
                x["tokens"] * w["cw"])
        tools = {t["tool"]: t for t in r["tool_results"]["by_tool"]}
        big = sum(t["over_40kb"] for t in tools.values())
        if big > 0:
            top_tool = max(tools.values(), key=lambda t: t["over_40kb"])
            add("large-tool-results", "warn",
                f"{big} tool results above 40KB (most: {top_tool['tool']} x{top_tool['over_40kb']}); "
                f"{top_tool['tool']} is {top_tool['share']:.0%} of tool-result bytes",
                "> 40KB per result",
                "each stays in context and is re-billed on every later request",
                "read with offset/limit or grep first; delegate bulk reads to a subagent and "
                "return only conclusions; keep large MCP payloads out of the main thread",
                sum(t["over_40kb_chars"] for t in tools.values()) / 4 * w["cw"])
        agent_calls = r["subagents"]["agent_calls"]
        inherit = sum(a["calls"] for a in agent_calls if a["model"] == "inherit")
        main_models = set(r["tokens"]["main"])
        sub_models = set(r["subagents"]["transcript_models"])
        if inherit > 0 or (sub_models and sub_models <= main_models):
            add("subagent-model-unpinned", "warn",
                f"{inherit} Agent calls without model; subagent transcripts ran on "
                f"{sorted(sub_models) or 'n/a'}",
                "subagents inherit the primary model",
                f"subagent share of weighted spend {r['spend_share']['subagent_share']:.1%}",
                "set model: sonnet/haiku in .claude/agents/*.md or pass model= on Agent calls; "
                "primary decomposes and evaluates, subagents execute",
                r["spend_share"]["subagent_weighted_tokens"])
        read_share = tools.get("Read", {}).get("share", 0)
        if not agent_calls and read_share > 0.5:
            add("subagent-underuse", "info",
                f"0 Agent calls while Read is {read_share:.0%} of tool-result bytes",
                "no delegation with heavy reads",
                "exploration payloads accumulate in the main context",
                "delegate search/bulk-read to Explore or general-purpose subagents on a cheaper model",
                tools.get("Read", {}).get("chars", 0) / 4 * w["cw"])
        if share["out"] > 0.30:
            add("output-heavy", "info",
                f"output tokens are {share['out']:.0%} of weighted spend",
                "> 30%", "output is the most expensive token category",
                "consider effortLevel medium for routine tasks; keep high effort for design/debug",
                r["spend_share"]["tokens"]["out"] * w["out"])
        eff_total = sum(r["effort"].values())
        eff_high = sum(v for k, v in r["effort"].items() if k in ("high", "xhigh", "max"))
        if eff_total and eff_high / eff_total > 0.8:
            add("effort-high-default", "info",
                f"{eff_high / eff_total:.0%} of requests at high/xhigh/max effort",
                "> 80%", f"output share {share['out']:.0%} of weighted spend",
                "quality tradeoff, not a defect: keep unless output share dominates; "
                "Uber defaults interactive sessions to medium",
                r["spend_share"]["tokens"]["out"] * w["out"])
        tool_total = sum(t["calls"] for t in r["tool_calls"]) or 1
        if r["mcp"]["calls"] / tool_total > 0.3:
            add("mcp-heavy", "info",
                f"{r['mcp']['calls']} MCP calls = {r['mcp']['calls'] / tool_total:.0%} of tool calls",
                "> 30% of tool calls",
                "MCP responses land verbatim in context",
                "batch via shell/code-mode where a CLI exists; scope MCP responses",
                sum(t["chars"] for t in tools.values() if t["tool"].startswith("mcp__")) / 4 * w["cw"])
        rank = {"warn": 0, "info": 1}
        f.sort(key=lambda x: (rank.get(x["severity"], 9), -x["impact_weighted"]))
        return f


def fmt_text(r, dirs):
    o = []
    s, c, pr, sp = r["summary"], r["context"], r["prefix_rewrites"], r["spend_share"]
    o.append("session-cost-audit")
    o.append("  dirs: " + ", ".join(dirs))
    o.append(f"  period: {r['period']['from']} .. {r['period']['to']}")
    o.append(f"  sessions={s['sessions']} requests={s['requests']:,} subagent_requests={s['subagent_requests']:,} "
             f"user_turns={s['user_turns']:,} compactions={s['compactions']}")
    rpt = s["requests_per_turn"]
    o.append(f"  requests/turn median={rpt['median']} p90={rpt['p90']} max={rpt['max']}")
    o.append("")
    o.append("context (tokens)")
    o.append(f"  first request  median={c['first_request_median']:,} p90={c['first_request_p90']:,}")
    o.append(f"  per request    median={c['per_request_median']:,} p90={c['per_request_p90']:,} max={c['per_request_max']:,}")
    o.append(f"  >200K={c['over_200k']:,}  >400K={c['over_400k']:,}")
    o.append("")
    o.append(f"weighted spend share (weights {sp['weights']})")
    for k in ("cr", "cw", "out", "in"):
        o.append(f"  {k:3s} {sp['tokens'][k]:>16,}  {sp['shares'][k]:6.1%}")
    o.append(f"  subagent share {sp['subagent_share']:.1%}")
    o.append("")
    o.append("tokens by model (main)")
    for m, t in r["tokens"]["main"].items():
        o.append(f"  {m:28s} cw={t['cache_creation_input_tokens']:>13,} cr={t['cache_read_input_tokens']:>15,} "
                 f"out={t['output_tokens']:>11,} cache_read={t['cache_read_share']:.1%}")
    if r["tokens"]["subagent"]:
        o.append("tokens by model (subagent)")
        for m, t in r["tokens"]["subagent"].items():
            o.append(f"  {m:28s} cw={t['cache_creation_input_tokens']:>13,} cr={t['cache_read_input_tokens']:>15,} "
                     f"out={t['output_tokens']:>11,} requests={r['subagents']['transcript_models'].get(m, 0)}")
    o.append("")
    o.append(f"prefix rewrites: {pr['events']} events, {pr['tokens']:,} tokens = {pr['share_of_cache_write']:.0%} of cache writes")
    for x in pr["by_cause"]:
        o.append(f"  {x['cause']:30s} {x['events']:>4}  {x['tokens']:>13,}  {x['share']:4.0%}")
    idle = r["idle"]
    o.append(f"  requests after >5m gap: {idle['after_5m']['requests']} (miss {idle['after_5m']['cache_miss']}); "
             f"after >1h gap: {idle['after_1h']['requests']} (miss {idle['after_1h']['cache_miss']})")
    o.append("")
    o.append(f"tool results: {r['tool_results']['total_chars']:,} chars over {r['tool_results']['results']:,} results")
    o.append(f"  {'tool':40s}{'n':>7}{'chars':>14}{'share':>7}{'avg':>9}{'>40KB':>6}{'img':>5}")
    for t in r["tool_results"]["by_tool"]:
        o.append(f"  {t['tool'][:39]:40s}{t['results']:>7,}{t['chars']:>14,}{t['share']:>7.0%}{t['avg_chars']:>9,}{t['over_40kb']:>6}{t['images']:>5}")
    o.append("")
    o.append("subagents: " + (", ".join(f"{a['subagent_type']}/{a['model']} x{a['calls']}" for a in r["subagents"]["agent_calls"]) or "no Agent calls"))
    o.append(f"  transcript requests={r['subagents']['transcript_requests']} models={r['subagents']['transcript_models']}")
    o.append("mcp: " + (", ".join(f"{m['server']} x{m['calls']}" for m in r["mcp"]["by_server"]) or "none"))
    o.append("effort: " + (", ".join(f"{k} x{v}" for k, v in r["effort"].items()) or "not recorded"))
    o.append("")
    o.append(f"flags ({len(r['flags'])}, ordered: warn first, then impact_weighted desc; "
             f"impact_weighted = input-token equivalent under the weights above)")
    for fl in r["flags"]:
        o.append(f"  [{fl['severity']}] {fl['id']} (impact_weighted={fl['impact_weighted']:,}): {fl['metric']}")
        o.append(f"      threshold: {fl['threshold']}")
        o.append(f"      impact:    {fl['impact']}")
        o.append(f"      fix:       {fl['remediation']}")
    return "\n".join(o)


def parse_weights(text):
    try:
        vals = [float(x) for x in text.split(",")]
        assert len(vals) == 4
    except (ValueError, AssertionError):
        sys.exit("--weights expects four numbers: in,cw,cr,out")
    return dict(zip(("in", "cw", "cr", "out"), vals))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", action="append", help="repo path; default cwd (repeatable)")
    ap.add_argument("--dir", action="append", help="transcript dir directly (bypasses --project)")
    ap.add_argument("--include-nested", action="store_true",
                    help="also include project dirs under the path (e.g. .worktree/*)")
    ap.add_argument("--last", type=int, default=60, help="most recent N sessions (0 = all)")
    ap.add_argument("--since", type=float, default=0, help="only sessions modified in the last N days")
    ap.add_argument("--session", help="single session id (or fragment)")
    ap.add_argument("--weights", default=None, help="in,cw,cr,out cost ratios (default 1,2,0.1,5)")
    ap.add_argument("--top", type=int, default=12)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    dirs = resolve_dirs(args)
    sessions = select_sessions(dirs, args.last, args.since, args.session)
    if not sessions:
        sys.exit(f"no sessions selected in {dirs}")
    audit = Audit()
    for _sid, path, subs in sessions:
        audit.add_session(path, subs)
    weights = parse_weights(args.weights) if args.weights else dict(DEFAULT_WEIGHTS)
    r = audit.report(weights, args.top)
    r["scope"] = {"dirs": dirs, "sessions": [s[0] for s in sessions], "last": args.last, "since_days": args.since}
    if args.json:
        print(json.dumps(r, ensure_ascii=False, indent=1))
    else:
        print(fmt_text(r, dirs))


if __name__ == "__main__":
    main()
