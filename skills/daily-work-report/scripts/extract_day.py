#!/usr/bin/env python3
"""Print one day's Claude Code and Codex conversations, one block per session.

Usage: python3 -I extract_day.py [YYYY-MM-DD] [--utc-offset +09:00]
Remote: ssh -o BatchMode=yes <host> python3 -I - [YYYY-MM-DD] [--utc-offset +09:00] < extract_day.py
The day defaults to today at the given offset. Honors CLAUDE_CONFIG_DIR and CODEX_HOME.
"""
import argparse
import json
import os
import re
import subprocess
from datetime import date, datetime, timedelta, timezone

TZ = timezone(timedelta(hours=9))
CLAUDE_DIR = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
CODEX_DIR = os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")
SHIP = re.compile(r"git (commit|push)|gh (pr (create|merge)|release create)|fastlane|terraform apply")
AI_CLIP = 250
USER_CLIP = 2500
REPORT_CLIP = 3000
CLIPPED = " …[clipped: read file=]"


def clip(text, limit):
    return text if len(text) <= limit else text[:limit] + CLIPPED


def local(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(TZ)


def parse_offset(text):
    sign = -1 if text.startswith("-") else 1
    hours, _, minutes = text.lstrip("+-").partition(":")
    return timezone(sign * timedelta(hours=int(hours), minutes=int(minutes or 0)))


def jsonl_files(root, depth=None):
    """List *.jsonl under root at exactly `depth` levels (any depth if None); raise on unreadable dirs."""
    try:
        os.stat(root)
    except FileNotFoundError:
        return []

    def fail(err):
        raise err

    found = []
    for dirpath, _, files in os.walk(root, onerror=fail):
        level = 0 if dirpath == root else os.path.relpath(dirpath, root).count(os.sep) + 1
        if depth is None or level == depth:
            found += [os.path.join(dirpath, f) for f in files if f.endswith(".jsonl")]
    return found


def text_of(content):
    if isinstance(content, str):
        return content
    return "".join(x.get("text", "") for x in content if isinstance(x, dict) and x.get("type") == "text")


def remote_of(cwd):
    if not cwd or not os.path.isdir(cwd):
        return "-"
    try:
        out = subprocess.run(["git", "-C", cwd, "remote", "get-url", "origin"],
                             capture_output=True, text=True, timeout=5)
        return out.stdout.strip() or "-"
    except (OSError, subprocess.SubprocessError):
        return "-"


def clip_turns(entries):
    """Keep user turns and the last AI text before each user turn; clip the rest."""
    next_kind, nxt = [], "U"
    for kind, _ in reversed(entries):
        next_kind.append(nxt)
        if kind != "C":
            nxt = kind
    next_kind.reverse()
    out = []
    for (kind, line), nxt in zip(entries, next_kind):
        if kind == "A":
            line = clip(line, REPORT_CLIP if nxt == "U" else AI_CLIP)
        out.append(line)
    return out


def claude_sessions(day, start):
    for path in sorted(jsonl_files(os.path.join(CLAUDE_DIR, "projects"), depth=1)):
        if os.path.getmtime(path) < start.timestamp():
            continue
        entries, cwd, first, last = [], None, None, None
        with open(path, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                try:
                    d = json.loads(raw)
                except ValueError:
                    continue
                ts = d.get("timestamp")
                if not ts or d.get("isSidechain") or d.get("isMeta"):
                    continue
                t = local(ts)
                if t.date() != day:
                    continue
                cwd = d.get("cwd") or cwd
                msg = d.get("message") or {}
                if d.get("type") == "user":
                    txt = text_of(msg.get("content", "")).strip()
                    if not txt or txt.startswith(("<local-command", "<system-reminder")):
                        continue
                    if "<task-notification>" in txt:
                        continue
                    first, last = first or t, t
                    entries.append(("U", f"\n[{t:%H:%M}] USER: {clip(txt, USER_CLIP)}"))
                elif d.get("type") == "assistant" and isinstance(msg.get("content"), list):
                    for x in msg["content"]:
                        if x.get("type") == "text" and x["text"].strip():
                            first, last = first or t, t
                            entries.append(("A", f"[{t:%H:%M}] AI: {x['text'].strip()}"))
                        elif x.get("type") == "tool_use" and x.get("name") == "Bash":
                            cmd = x.get("input", {}).get("command", "")
                            if SHIP.search(cmd):
                                first, last = first or t, t
                                entries.append(("C", f"[{t:%H:%M}] CMD: {cmd[:200]}"))
        if first:
            yield "claude", path, cwd, first, last, entries


def codex_sessions(day, start):
    # A resumed session keeps appending to the file under its start date's folder, so pick by mtime.
    paths = jsonl_files(os.path.join(CODEX_DIR, "sessions"), depth=3)
    paths += jsonl_files(os.path.join(CODEX_DIR, "archived_sessions"))
    for path in sorted(paths):
        if os.path.getmtime(path) < start.timestamp():
            continue
        entries, cwd, first, last = [], None, None, None
        with open(path, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                try:
                    d = json.loads(raw)
                except ValueError:
                    continue
                p = d.get("payload") or {}
                if d.get("type") == "session_meta":
                    cwd = p.get("cwd")
                if d.get("type") != "event_msg" or p.get("type") not in ("user_message", "agent_message"):
                    continue
                t = local(d["timestamp"])
                if t.date() != day:
                    continue
                m = (p.get("message") or "").strip()
                if not m:
                    continue
                if p["type"] == "user_message":
                    first, last = first or t, t
                    entries.append(("U", f"\n[{t:%H:%M}] USER: {clip(m, USER_CLIP)}"))
                else:
                    first, last = first or t, t
                    entries.append(("A", f"[{t:%H:%M}] AI: {m}"))
        if first:
            yield "codex", path, cwd, first, last, entries


def main():
    global TZ
    ap = argparse.ArgumentParser(usage=__doc__)
    ap.add_argument("day", nargs="?")
    ap.add_argument("--utc-offset", default="+09:00")
    args = ap.parse_args()
    TZ = parse_offset(args.utc_offset)
    day = date.fromisoformat(args.day) if args.day else datetime.now(TZ).date()
    start = datetime(day.year, day.month, day.day, tzinfo=TZ)
    try:
        sessions = list(claude_sessions(day, start)) + list(codex_sessions(day, start))
    except OSError as err:
        ap.exit(2, f"cannot read session logs: {err}\n")
    sessions.sort(key=lambda s: s[3])
    print(f"# {day} utc_offset={args.utc_offset} host={os.uname().nodename} sessions={len(sessions)}")
    for agent, path, cwd, first, last, entries in sessions:
        users = sum(1 for k, _ in entries if k == "U")
        print(f"\n######## {first:%H:%M}-{last:%H:%M} {agent} users={users} "
              f"remote={remote_of(cwd)} cwd={cwd} file={path}")
        print("\n".join(clip_turns(entries)))


if __name__ == "__main__":
    main()
