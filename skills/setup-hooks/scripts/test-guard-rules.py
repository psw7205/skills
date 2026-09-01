#!/usr/bin/env python3
"""Contract tests for the guard hooks.

Run: python3 skills/setup-hooks/scripts/test-guard-rules.py

Black-box like test-auto-backup.sh: both hooks are invoked as subprocesses with
the PreToolUse payload they see in production, so the JSON contract and the two
policies (Claude Code rewrites, Codex only denies) are covered together.
"""

import json
import pathlib
import subprocess
import sys

SCRIPTS = pathlib.Path(__file__).resolve().parent
CLAUDE_HOOK = SCRIPTS / "guard-commands.py"
CODEX_HOOK = SCRIPTS / "guard-commands-codex.py"

PASS = "pass"
DENY = "deny"
REWRITE = "rewrite"


def run(hook, command):
    """(outcome, rewritten command) as the hook would leave it."""
    proc = subprocess.run(
        [sys.executable, str(hook)],
        input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise AssertionError(f"{hook.name} exited {proc.returncode}: {proc.stderr}")
    if not proc.stdout.strip():
        return PASS, None
    output = json.loads(proc.stdout)["hookSpecificOutput"]
    if output.get("permissionDecision") == "deny":
        return DENY, None
    return REWRITE, output["updatedInput"]["command"]


# (command, Claude Code outcome, Codex outcome, why)
CASES = [
    # Must be caught. Codex denies what Claude Code backs up and lets run.
    ("git push --force", DENY, DENY, "force push, long form"),
    ("git push -f origin main", DENY, DENY, "force push, short form"),
    ("git clean -fd", REWRITE, DENY, "git clean"),
    ("git reset --hard HEAD~1", REWRITE, DENY, "git reset --hard"),
    ("git restore .", REWRITE, DENY, "git restore worktree"),
    ("git restore --staged --worktree f", REWRITE, DENY, "git restore -SW touches the tree"),
    ("git checkout .", REWRITE, DENY, "git checkout paths"),
    ("git checkout -f main", REWRITE, DENY, "git checkout --force"),
    ("git checkout HEAD src/a.ts", REWRITE, DENY, "tree-ish plus path overwrites the file"),
    ("/usr/bin/git push --force", DENY, DENY, "path-qualified command word"),
    ("echo hi && git clean -fd", REWRITE, DENY, "second command in an && chain"),
    ("cat x | git reset --hard", REWRITE, DENY, "right-hand side of a pipe"),
    ("npm test; git clean -fd", REWRITE, DENY, "after a semicolon"),
    ("cd /tmp && git clean -fd", REWRITE, DENY, "after a cd"),
    ("git clean -fd > /dev/null 2>&1", REWRITE, DENY, "redirection is not a new command"),
    ("rg -r 'foo' src/", DENY, DENY, "space-separated replace"),
    ("rg --replace foo bar src/", DENY, DENY, "long replace"),
    # The cluster is repairable, so Claude Code defers to rg-replace-flag-fix.py.
    ("rg -rn foo .", PASS, DENY, "short-flag cluster"),
    # Must pass: no destruction to protect against.
    ("git push --force-with-lease", PASS, PASS, "force-with-lease is the safe form"),
    ("git clean -n", PASS, PASS, "dry run deletes nothing"),
    ("git restore --staged f", PASS, PASS, "staged-only restore touches the index"),
    ("git checkout main", PASS, PASS, "DWIM checkout, git refuses on conflict"),
    ("git checkout -b feature main", PASS, PASS, "branch creation from a start point"),
    ("git -C /tmp checkout main", PASS, PASS, "a global option's value is not a checkout operand"),
    ("rg -o -r '$1' 'v(\\d+)' src/", PASS, PASS, "capture-group extraction with -o"),
    # Must pass: quoting makes these mentions, not commands. These are the
    # false positives the shell implementation produced.
    ('grep -n "a\\|rg -r\\|b" f.md', PASS, PASS, "alternation inside a quoted pattern"),
    ('git commit -m "fix; git reset --hard 제거"', PASS, PASS, "semicolon inside a commit message"),
    ('rg -n "a|b|c" src/', PASS, PASS, "pipe inside a quoted pattern"),
    ('echo "git push --force 금지"', PASS, PASS, "dangerous command quoted as text"),
    ('rg "git clean|git checkout ." docs/', PASS, PASS, "commands named in a search pattern"),
    ("echo 'a|b' && git clean -fd", REWRITE, DENY, "quoted pipe ignored, real && honoured"),
    (
        "cat > notes.md <<'EOF'\ngit clean -fd 는 위험하다\nEOF",
        PASS,
        PASS,
        "heredoc body is data, not commands",
    ),
]


def main():
    failures = []
    for command, claude_want, codex_want, why in CASES:
        claude_got, rewritten = run(CLAUDE_HOOK, command)
        codex_got, _ = run(CODEX_HOOK, command)
        problems = []
        if claude_got != claude_want:
            problems.append(f"claude: want {claude_want}, got {claude_got}")
        if codex_got != codex_want:
            problems.append(f"codex: want {codex_want}, got {codex_got}")
        if claude_got == REWRITE and not rewritten.endswith(command.split("&& ", 1)[-1]):
            problems.append(f"rewrite dropped the original command: {rewritten!r}")
        print(f"{'FAIL' if problems else 'ok  '} {why}")
        if problems:
            failures.append(f"  {why}\n    input: {command!r}\n    " + "\n    ".join(problems))

    # The cd chain must stay in front of the backup, or the stash lands in
    # whatever repository the hook happened to be invoked from.
    _, rewritten = run(CLAUDE_HOOK, "cd /tmp && git clean -fd")
    if not rewritten.startswith("cd /tmp && bash "):
        failures.append(f"  cd prefix must precede the backup\n    actual: {rewritten!r}")
        print("FAIL cd prefix precedes the backup")
    else:
        print("ok   cd prefix precedes the backup")

    print()
    if failures:
        print(f"{len(failures)} failed:\n" + "\n".join(failures))
        return 1
    print(f"all {len(CASES) + 1} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
