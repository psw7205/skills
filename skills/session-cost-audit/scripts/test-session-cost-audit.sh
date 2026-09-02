#!/usr/bin/env bash
# Fixture-based contract test for session-cost-audit.py.
# Builds a fake Claude Code projects dir with the traps the script must handle
# (per-content-block duplicate usage lines, nested subagent transcripts, model
# switch, >1h idle gap, compaction, oversized tool_result, unpinned Agent call)
# and asserts the JSON report.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/session-cost-audit.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROJ="$TMP/projects/-tmp-fixture-repo"
mkdir -p "$PROJ/sess-a/subagents"

python3 - "$PROJ" <<'PY'
import json, sys, os
proj = sys.argv[1]

def line(**kw):
    return json.dumps(kw)

def usage(i, cw, cr, o):
    return {"input_tokens": i, "cache_creation_input_tokens": cw,
            "cache_read_input_tokens": cr, "output_tokens": o}

def asst(mid, model, u, content, ts, effort="xhigh"):
    return line(type="assistant", timestamp=ts, effort=effort,
                message={"id": mid, "model": model, "usage": u, "content": content})

def user(text, ts, meta=False):
    d = dict(type="user", timestamp=ts, message={"role": "user", "content": text})
    if meta:
        d["isMeta"] = True
    return line(**d)

def tool_result(tool_use_id, text, ts):
    return line(type="user", timestamp=ts,
                message={"role": "user", "content": [
                    {"type": "tool_result", "tool_use_id": tool_use_id, "content": text}]})

# ---- session A: first request split across 3 content-block lines (same id),
# then a Read >40KB, an Agent call with no model, then a model switch rewrite.
a = []
a.append(user("start", "2026-01-01T10:00:00.000Z"))
u1 = usage(10, 80_000, 0, 200)
a.append(asst("msg_1", "claude-opus-5", u1, [{"type": "text", "text": "hi"}], "2026-01-01T10:00:05.000Z"))
a.append(asst("msg_1", "claude-opus-5", u1, [{"type": "tool_use", "id": "tu_read", "name": "Read", "input": {"file_path": "/x"}}], "2026-01-01T10:00:05.000Z"))
a.append(asst("msg_1", "claude-opus-5", u1, [{"type": "tool_use", "id": "tu_agent", "name": "Agent", "input": {"subagent_type": "Explore", "prompt": "p"}}], "2026-01-01T10:00:05.000Z"))
a.append(tool_result("tu_read", "x" * 50_000, "2026-01-01T10:00:06.000Z"))
a.append(tool_result("tu_agent", "done", "2026-01-01T10:00:07.000Z"))
# second request: incremental write (normal)
a.append(asst("msg_2", "claude-opus-5", usage(5, 15_000, 80_000, 300), [{"type": "text", "text": "ok"}], "2026-01-01T10:00:20.000Z"))
# user turn, then model switch -> full rewrite on a different model
a.append(user("switch", "2026-01-01T10:01:00.000Z"))
a.append(asst("msg_3", "claude-sonnet-5", usage(0, 96_000, 0, 100), [{"type": "text", "text": "sw"}], "2026-01-01T10:01:10.000Z"))
open(os.path.join(proj, "sess-a.jsonl"), "w").write("\n".join(a) + "\n")

# subagent transcript under session A, inherits opus
s = [
    line(type="user", isSidechain=True, agentId="aexplore-1", sessionId="sess-a",
         timestamp="2026-01-01T10:00:08.000Z", message={"role": "user", "content": "explore"}),
    asst("msg_sub1", "claude-opus-5", usage(0, 20_000, 0, 500), [{"type": "text", "text": "r"}], "2026-01-01T10:00:09.000Z"),
    asst("msg_sub2", "claude-opus-5", usage(0, 1_000, 20_000, 500), [{"type": "text", "text": "r"}], "2026-01-01T10:00:10.000Z"),
]
open(os.path.join(proj, "sess-a", "subagents", "agent-aexplore-1.jsonl"), "w").write("\n".join(s) + "\n")

# ---- session B: idle >1h rewrite, then compaction rewrite, and an mcp call
b = []
b.append(user("go", "2026-01-02T09:00:00.000Z"))
b.append(asst("msg_b1", "claude-opus-5", usage(0, 90_000, 0, 100), [{"type": "tool_use", "id": "tu_mcp", "name": "mcp__figma__get_screenshot", "input": {}}], "2026-01-02T09:00:05.000Z"))
b.append(tool_result("tu_mcp", "img", "2026-01-02T09:00:06.000Z"))
b.append(asst("msg_b2", "claude-opus-5", usage(0, 2_000, 90_000, 100), [{"type": "text", "text": "t"}], "2026-01-02T09:00:10.000Z"))
# come back after 2h -> cache expired -> full rewrite
b.append(user("back", "2026-01-02T11:10:00.000Z"))
b.append(asst("msg_b3", "claude-opus-5", usage(0, 93_000, 0, 100), [{"type": "text", "text": "t"}], "2026-01-02T11:10:05.000Z"))
# compaction summary then rewrite
b.append(line(type="user", isCompactSummary=True, timestamp="2026-01-02T11:11:00.000Z", message={"role": "user", "content": "summary"}))
b.append(asst("msg_b4", "claude-opus-5", usage(0, 30_000, 0, 100), [{"type": "text", "text": "t"}], "2026-01-02T11:11:05.000Z"))
open(os.path.join(proj, "sess-b.jsonl"), "w").write("\n".join(b) + "\n")
PY

OUT="$(python3 "$SCRIPT" --dir "$PROJ" --json)"

python3 - "$OUT" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
def eq(path, want):
    cur = r
    for p in path.split("."):
        cur = cur[int(p)] if isinstance(cur, list) else cur[p]
    assert cur == want, f"{path}: got {cur!r}, want {want!r}"

eq("summary.sessions", 2)
eq("summary.requests", 7)                 # 3 duplicate lines of msg_1 count once
eq("summary.subagent_requests", 2)
eq("summary.user_turns", 4)               # start, switch, go, back (compact summary is not a turn)
eq("summary.compactions", 1)
eq("context.first_request_median", 80010)
eq("context.over_400k", 0)

causes = {c["cause"]: c for c in r["prefix_rewrites"]["by_cause"]}
assert causes["session first request"]["events"] == 2, causes
assert causes["model switch"]["events"] == 1, causes
assert causes["idle >1h"]["events"] == 1, causes
assert causes["after compaction"]["events"] == 1, causes

tools = {t["tool"]: t for t in r["tool_results"]["by_tool"]}
assert tools["Read"]["over_40kb"] == 1, tools
assert tools["Read"]["chars"] == 50000, tools

agent = r["subagents"]
assert agent["agent_calls"] == [{"subagent_type": "Explore", "model": "inherit", "calls": 1}], agent
assert agent["transcript_models"] == {"claude-opus-5": 2}, agent

mcp = {m["server"]: m["calls"] for m in r["mcp"]["by_server"]}
assert mcp == {"figma": 1}, mcp

assert r["effort"] == {"xhigh": 7}, r["effort"]

assert r["period"] == {"from": "2026-01-01T10:00:00+00:00", "to": "2026-01-02T11:11:05+00:00"}, r["period"]
sev = [f["severity"] for f in r["flags"]]
assert sev == sorted(sev, key={"warn": 0, "info": 1}.get), sev
warn_impacts = [f["impact_weighted"] for f in r["flags"] if f["severity"] == "warn"]
assert warn_impacts == sorted(warn_impacts, reverse=True), warn_impacts
assert all(isinstance(f["impact_weighted"], int) for f in r["flags"])
flags = {f["id"] for f in r["flags"]}
for want in ("prompt-init-overhead", "prefix-rewrite-waste", "subagent-model-unpinned", "large-tool-results"):
    assert want in flags, f"missing flag {want}; got {sorted(flags)}"
assert "context-over-400k" not in flags, flags
print("assertions passed")
PY

# human-readable mode must run and mention the report header
python3 "$SCRIPT" --dir "$PROJ" | grep -q "session-cost-audit" || { echo "text report missing header" >&2; exit 1; }

# project path resolution: encoded dir name must be derivable from a path
mkdir -p "$TMP/projects/-tmp-dotted-repo--worktree-x"
cp "$PROJ/sess-b.jsonl" "$TMP/projects/-tmp-dotted-repo--worktree-x/"
RES="$(CLAUDE_HOME="$TMP" python3 "$SCRIPT" --project /tmp/dotted-repo/.worktree/x --json)"
python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert r["summary"]["sessions"]==1, r["summary"]' "$RES"

echo "test-session-cost-audit: OK"
