#!/usr/bin/env python3
"""PreToolUse guard for Claude Code.

Recoverable damage is rewritten rather than blocked: auto-backup.sh captures
the working tree into a stash and restores it, so the original command still
runs against the user's real state while the stash entry survives as a
recovery point. Damage a stash cannot undo -- remote history, or a search whose
output silently misrepresents the files -- is denied instead.
"""

import json
import pathlib
import re
import shlex
import sys

try:
    from guard_rules import classify
    from shell_lex import mask_literals
except Exception:
    # A broken install must not make every Bash call fail. Guarding nothing is
    # better than a traceback on stderr before each command.
    sys.exit(0)

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
# Quoted rather than interpolated: an install path holding a space or a `$`
# would otherwise reach the shell as two words or as an expansion.
BACKUP = shlex.quote(str(SCRIPT_DIR / "auto-backup.sh"))

# The whole `cd a && cd b &&` chain stays in front of the backup so the stash
# lands in the repository the original command actually targets. Matched
# against the masked copy, never the original: `cd "x&& y" && git clean -fd`
# has an && inside an argument, and cutting there would bury the backup call in
# that argument and run the destructive command with no backup at all.
CD_PREFIX = re.compile(r"((?:cd\s+[^&|;]+&&\s*)+)(.+)", re.DOTALL)

REWRITE_MESSAGE = (
    "[guard] %s 앞에 auto-backup 삽입. 백업이 실패하면 원 명령은 실행되지 않는다. "
    "복구: git stash list → git stash apply stash@{N}"
)

DENY_MESSAGES = {
    "force-push": (
        "[guard] git push --force 차단됨. 원격 히스토리 파괴는 복구 불가. "
        "필요하면 사용자에게 직접 실행을 요청하세요. 안전한 대안: git push --force-with-lease"
    ),
    "rg-replace": (
        "[guard] rg -r/--replace 차단됨. rg는 파일을 수정하지 않고 출력만 치환하며, "
        "-r은 recursive가 아니라 --replace다(rg는 기본 재귀). 검색은 -r 없이, "
        "파일 수정은 Edit 도구나 sed -i, 캡처 그룹 추출은 -o 동반(rg -o -r '$1' ...)으로 사용."
    ),
}


def emit(message, decision):
    json.dump(
        {"systemMessage": message, "hookSpecificOutput": dict(decision, hookEventName="PreToolUse")},
        sys.stdout,
        ensure_ascii=False,
    )


def rewrite(cmd, label, scope=""):
    prefix = ""
    rest = cmd
    match = CD_PREFIX.match(mask_literals(cmd))
    if match:
        cut = match.end(1)
        prefix, rest = cmd[:cut], cmd[cut:]
    args = f"{BACKUP} {shlex.quote(label)}"
    if scope:
        args += f" {shlex.quote(scope)}"
    # `&&`, not `;`: when the backup cannot put the working tree back, the
    # destructive command must not run over the gap it left. The brace group is
    # what makes that hold for every segment -- without it `echo hi ; git reset
    # --hard` would gate only the echo and run the reset anyway. The closing
    # brace goes on its own line so a trailing heredoc still finds its
    # terminator.
    backed_up = f"{prefix}bash {args} && {{\n{rest}\n}}"
    emit(REWRITE_MESSAGE % label, {"updatedInput": {"command": backed_up}})


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    cmd = ((data or {}).get("tool_input") or {}).get("command")
    # An argv list is the same command in another shape. Reading only strings
    # would let `["bash", "-lc", "git push --force"]` past the guard untouched.
    if isinstance(cmd, (list, tuple)):
        cmd = " ".join(str(part) for part in cmd)
    if not isinstance(cmd, str) or not cmd:
        return 0

    verdict = classify(cmd)
    if verdict is None:
        return 0

    # Clusters are left to the companion rg-replace-flag-fix.py hook, which
    # rewrites `-rn` to `-n`. Denying here would preempt that repair.
    if verdict.rule == "rg-flag-cluster":
        return 0

    message = DENY_MESSAGES.get(verdict.rule)
    if message:
        emit(message, {"permissionDecision": "deny"})
    else:
        rewrite(cmd, verdict.label, verdict.scope)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
