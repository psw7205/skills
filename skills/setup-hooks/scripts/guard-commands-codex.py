#!/usr/bin/env python3
"""PreToolUse guard for Codex.

Codex does not honour command rewrite via updatedInput, and running `git stash`
from the hook itself would leave a stray stash behind whenever the original
command is then cancelled. So this guard only blocks, and tells the agent the
exact backup command to run before retrying.
"""

import json
import pathlib
import shlex
import sys

try:
    from guard_rules import classify
except Exception:
    # A broken install must not make every shell call fail. Guarding nothing is
    # better than a traceback on stderr before each command.
    sys.exit(0)

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
# The reason text is meant to be copied and run, so it carries shell quoting.
BACKUP = shlex.quote(str(SCRIPT_DIR / "auto-backup.sh"))

# Codex names its shell tool `exec` in the rollout log and `Bash` in the hook
# payload depending on the layer, so both spellings have to be accepted. The
# empty string covers a payload that omits the field entirely.
SHELL_TOOLS = ("", "Bash", "shell", "shell_command", "local_shell", "exec_command", "exec")

DENY_REASONS = {
    "force-push": (
        "Blocked git push --force. Remote history destruction is not recoverable. "
        "Use git push --force-with-lease only when you have verified it is safe."
    ),
    "rg-flag-cluster": (
        "Blocked an rg -r<flags> cluster. In ripgrep -r is --replace and consumes what "
        "follows as its value, so rg -rn foo . rewrites every match to the literal \"n\" "
        "and still exits 0 -- the mistake reads as a successful search returning garbage. "
        "Drop the -r and rerun (rg -n foo .). rg recurses by default; there is no "
        "recursive flag."
    ),
    "rg-replace": (
        "Blocked rg -r/--replace. ripgrep never modifies files -- --replace only rewrites "
        "the printed output -- and -r is not a recursive flag (rg recurses by default), so "
        "rg -r 'foo' src/ silently searches for the pattern src/ instead. To search, drop "
        "-r. To edit files, use sed -i or an editor tool. To extract capture groups, pass "
        "-o as well (rg -o -r '$1' ...), which is allowed."
    ),
}


def backup_reason(label):
    # Points at auto-backup.sh rather than spelling out a stash pipeline: a bare
    # `git stash push && git stash apply` exits 0 on a clean tree without stashing
    # anything, so the apply restores an unrelated entry from the top of the stack.
    return (
        f'Blocked "{label}". Codex hooks do not rewrite shell commands here. If this '
        f"command is intentional, first run: bash {BACKUP} {shlex.quote(label)} "
        "&& <original command>. That script backs the tree up, restores it, and exits "
        "non-zero rather than letting the command run without a backup."
    )


def deny(reason):
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
        ensure_ascii=False,
    )


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    data = data or {}
    if (data.get("tool_name") or "") not in SHELL_TOOLS:
        return 0

    tool_input = data.get("tool_input") or {}
    cmd = tool_input.get("command") or tool_input.get("cmd")
    # An argv list is the same command in another shape. Reading only strings
    # would let `["bash", "-lc", "git push --force"]` past the guard untouched.
    if isinstance(cmd, (list, tuple)):
        cmd = " ".join(str(part) for part in cmd)
    if not isinstance(cmd, str) or not cmd:
        return 0

    verdict = classify(cmd)
    if verdict is None:
        return 0

    deny(DENY_REASONS.get(verdict.rule) or backup_reason(verdict.label))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
