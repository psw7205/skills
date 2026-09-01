#!/usr/bin/env python3
"""PreToolUse(Bash) hook: repair `rg -rn`-style short-flag clusters before they run.

ripgrep's -r is --replace and CONSUMES a value, unlike grep's argument-less
-r/--recursive. So `rg -rn foo .` parses as `-r n`: every match is rewritten to
the literal "n" and the exit code stays 0, so the mistake reads as a successful
search returning garbage rather than a usage error. Same trap for -rl, -rln,
-ril. Rewriting here instead of denying avoids a wasted round trip.

Deliberately NOT touched: space-separated `rg -r <value>` and long --replace,
which remain the escape hatch for real substitution.

Quoted spans and heredoc bodies are not touched either. They are data, not
flags, and rewriting them corrupts what the command writes rather than how it
runs: `echo "never use rg -rn" >> notes.md` would silently record the opposite
of what was meant, and the damage lands in a file instead of in one search.
Detection therefore runs over shell_lex's masked copy while the edit lands on
the original, so both views keep identical offsets.

Lives in its own file rather than inlined into a shell hook because the patterns
below contain both quote characters; embedding them in a shell string is how the
first version of this hook silently broke.
"""

import json
import re
import sys

try:
    # The set the guard defers on must be the set repaired here. Two copies
    # would drift into a gap where the guard passes a cluster expecting this
    # hook to fix it and this hook leaves it alone.
    from guard_rules import RG_BOOL_FLAGS as BOOL_FLAGS
    from shell_lex import SEPARATORS, mask_literals
except Exception:
    # A broken install must not make every Bash call fail. Repairing nothing is
    # better than a traceback on stderr before each command.
    sys.exit(0)

# Shell operators that end one command; -r only rebinds within its own segment.
# Taken from the lexer so the two hooks cannot disagree on where a command ends:
# a cluster after `&` belongs to the next command, not to the rg before it.
SEGMENT = re.compile("([" + re.escape(SEPARATORS) + "])")
# Quote chars are excluded from the lookbehind so a searched-for literal such as
# `rg -n -- '-rn'` survives; the -- cutoff covers bare positional patterns.
CLUSTER = re.compile(r"""(?<![\w'"-])-r([a-zA-Z]+)(?![\w-])""")
# Matches `rg` and `/usr/bin/rg`, but not the `rg` inside `grep` or `merge`.
RG_WORD = re.compile(r"(?<![\w./-])(?:[\w./-]*/)?rg(?![\w./-])")
END_OF_FLAGS = re.compile(r"(?<!\S)--(?!\S)")


def fix_command(cmd):
    masked = mask_literals(cmd)
    edits = []
    offset = 0
    parts = SEGMENT.split(masked)
    for idx, part in enumerate(parts):
        start = offset
        offset += len(part)
        if idx % 2:  # odd indices hold the captured separators
            continue
        m = RG_WORD.search(masked, start, offset)
        if not m:
            continue
        # Everything past a standalone -- is an operand, never a flag cluster.
        stop = END_OF_FLAGS.search(masked, m.end(), offset)
        limit = stop.start() if stop else offset
        for mo in CLUSTER.finditer(masked, m.end(), limit):
            if set(mo.group(1)) <= BOOL_FLAGS:
                edits.append((mo.start(), mo.end(), "-" + mo.group(1)))
    if not edits:
        return cmd, False

    out = cmd
    # Right to left so earlier offsets stay valid as the string shrinks.
    for start, end, repl in sorted(edits, reverse=True):
        out = out[:start] + repl + out[end:]
    return out, True


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
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
