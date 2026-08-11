#!/usr/bin/env python3
"""PreToolUse(Bash) hook: repair `rg -rn`-style short-flag clusters before they run.

ripgrep's -r is --replace and CONSUMES a value, unlike grep's argument-less
-r/--recursive. So `rg -rn foo .` parses as `-r n`: every match is rewritten to
the literal "n" and the exit code stays 0, so the mistake reads as a successful
search returning garbage rather than a usage error. Same trap for -rl, -rln,
-ril. Rewriting here instead of denying avoids a wasted round trip.

Deliberately NOT touched: space-separated `rg -r <value>` and long --replace,
which remain the escape hatch for real substitution.

Lives in its own file rather than inlined into a shell hook because the patterns
below contain both quote characters; embedding them in a shell string is how the
first version of this hook silently broke.
"""

import json
import re
import sys

# rg short flags that take no value. -h (help) and -V (version) are excluded:
# clustering them carries no recoverable intent, so leave those alone.
BOOL_FLAGS = set("acFHIiLlNnopqSsUuvwxz")

# Shell operators that end one command; -r only rebinds within its own segment.
SEGMENT = re.compile(r"(\|\||&&|[|;\n])")
# Quote chars are excluded from the lookbehind so a searched-for literal such as
# `rg -n -- '-rn'` survives; the -- cutoff covers bare positional patterns.
CLUSTER = re.compile(r"""(?<![\w'"-])-r([a-zA-Z]+)(?![\w-])""")
# Matches `rg` and `/usr/bin/rg`, but not the `rg` inside `grep` or `merge`.
RG_WORD = re.compile(r"(?<![\w./-])(?:[\w./-]*/)?rg(?![\w./-])")
END_OF_FLAGS = re.compile(r"(?<!\S)--(?!\S)")


def fix_segment(seg):
    m = RG_WORD.search(seg)
    if not m:
        return seg, False
    head, rest = seg[: m.end()], seg[m.end() :]

    # Everything past a standalone -- is an operand, never a flag cluster.
    stop = END_OF_FLAGS.search(rest)
    scan, keep = (rest[: stop.start()], rest[stop.start() :]) if stop else (rest, "")

    changed = False

    def sub(mo):
        nonlocal changed
        if not set(mo.group(1)) <= BOOL_FLAGS:
            return mo.group(0)
        changed = True
        return "-" + mo.group(1)

    return head + CLUSTER.sub(sub, scan) + keep, changed


def fix_command(cmd):
    parts = SEGMENT.split(cmd)
    touched = False
    for i in range(0, len(parts), 2):  # odd indices hold the captured separators
        parts[i], hit = fix_segment(parts[i])
        touched = touched or hit
    return "".join(parts), touched


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    tool_input = (data or {}).get("tool_input") or {}
    cmd = tool_input.get("command")
    if not isinstance(cmd, str) or "rg" not in cmd:
        return 0

    fixed, touched = fix_command(cmd)
    if not touched:
        return 0

    new_input = dict(tool_input)
    new_input["command"] = fixed
    json.dump(
        {
            "systemMessage": "[rg-fix] rg의 -r은 --replace(값 소비)이므로 -r을 제거하고 실행했습니다.",
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "updatedInput": new_input,
            },
        },
        sys.stdout,
        ensure_ascii=False,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
