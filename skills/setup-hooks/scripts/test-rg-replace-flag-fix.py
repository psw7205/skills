#!/usr/bin/env python3
"""Contract tests for rg-replace-flag-fix.py.

Run: python3 skills/setup-hooks/scripts/test-rg-replace-flag-fix.py

Black-box like test-auto-backup.sh: the hook is invoked as a subprocess with the
PreToolUse payload it sees in production, so the JSON contract is covered too.
"""

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

HOOK = pathlib.Path(__file__).with_name("rg-replace-flag-fix.py")

UNCHANGED = object()


def run(command):
    """Command as the hook would leave it (identical object when untouched)."""
    proc = subprocess.run(
        [sys.executable, str(HOOK)],
        input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise AssertionError(f"hook exited {proc.returncode}: {proc.stderr}")
    if not proc.stdout.strip():
        return UNCHANGED
    payload = json.loads(proc.stdout)
    return payload["hookSpecificOutput"]["updatedInput"]["command"]


CASES = [
    # Clusters: the whole point of the hook.
    ("rg -rn foo .", "rg -n foo .", "cluster -rn"),
    ("rg -rl foo .", "rg -l foo .", "cluster -rl"),
    ("rg -rln foo .", "rg -ln foo .", "cluster -rln"),
    ("cat a.txt | rg -rn foo", "cat a.txt | rg -n foo", "cluster after a pipe"),
    ("rg -rn 'pat' src/", "rg -n 'pat' src/", "quoted operand, unquoted flag"),
    ("echo hi && rg -rn foo", "echo hi && rg -n foo", "command after a quoted one"),
    # Real substitution stays reachable; the shell guard denies these, not us.
    ("rg -r n foo .", UNCHANGED, "space-separated replace"),
    ("rg --replace n foo .", UNCHANGED, "long replace"),
    ("/usr/bin/rg -rn foo .", "/usr/bin/rg -n foo .", "path-qualified rg"),
    # Not rg, or not a repairable cluster.
    ("grep -rn foo .", UNCHANGED, "grep -r is recursive and valid"),
    ("git merge -rn", UNCHANGED, "rg inside another word"),
    ("rg -rA3 foo .", UNCHANGED, "-A takes a value, not a bool cluster"),
    ("rg -n -- '-rn'", UNCHANGED, "operand past --"),
    ("rg -n foo . & echo -rn banner", UNCHANGED, "a bare & ends the rg command too"),
    # Literals are data: rewriting them corrupts what the command writes.
    ("echo 'never use rg -rn'", UNCHANGED, "single-quoted text"),
    ('echo "never use rg -rn"', UNCHANGED, "double-quoted text"),
    (
        "cat > notes.md <<'EOF'\nnever use rg -rn here\nEOF",
        UNCHANGED,
        "heredoc body",
    ),
    (
        "cat <<EOF\nrg -rn inside\nEOF\nrg -rn foo",
        "cat <<EOF\nrg -rn inside\nEOF\nrg -n foo",
        "heredoc body kept, real command after it repaired",
    ),
]


def orphaned():
    """(exit code, output) with the hook cut off from its sibling modules."""
    with tempfile.TemporaryDirectory() as tmp:
        alone = pathlib.Path(tmp) / HOOK.name
        shutil.copy(HOOK, alone)
        proc = subprocess.run(
            [sys.executable, str(alone)],
            input=json.dumps({"tool_input": {"command": "rg -rn foo ."}}),
            capture_output=True,
            text=True,
        )
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def main():
    failures = []
    for command, expected, why in CASES:
        actual = run(command)
        ok = actual == expected
        status = "ok  " if ok else "FAIL"
        print(f"{status} {why}")
        if not ok:
            shown = "(unchanged)" if actual is UNCHANGED else repr(actual)
            want = "(unchanged)" if expected is UNCHANGED else repr(expected)
            failures.append(f"  {why}\n    input:    {command!r}\n    expected: {want}\n    actual:   {shown}")

    # An incomplete install must cost the repair, not every Bash call: a hook
    # that raises here puts a traceback in front of each command the user runs.
    code, output = orphaned()
    if code == 0 and not output:
        print("ok   silent pass when the sibling modules are missing")
    else:
        print("FAIL silent pass when the sibling modules are missing")
        failures.append(f"  missing siblings\n    exit: {code}\n    output: {output[:200]!r}")

    print()
    if failures:
        print(f"{len(failures)} failed:\n" + "\n".join(failures))
        return 1
    print(f"all {len(CASES) + 1} cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
