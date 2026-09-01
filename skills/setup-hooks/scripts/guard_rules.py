"""Shared command classification for the PreToolUse guards.

Imported by guard-commands.py (Claude Code) and guard-commands-codex.py (Codex),
which apply different policies (rewrite vs deny) to the same verdicts.

Classification is token-positional rather than substring-based. A rule fires
only when a segment's command word is the real program and its subcommand
matches, so `echo 'git clean'` and `git commit -m "drop git clean"` are not
mistaken for the commands they merely mention. Segmentation comes from
shell_lex, which splits only on operators the shell would honour -- an operator
inside quotes starts no new command, and a heredoc body holds no commands at all.
"""

from collections import namedtuple

from shell_lex import segments

Verdict = namedtuple("Verdict", "rule label")

# rg short flags that take no value.
# -h/-V are excluded: clustering them carries no recoverable intent.
RG_BOOL_FLAGS = set("acFHIiLlNnopqSsUuvwxz")

# rg short flags that swallow the rest of the token as their value, which is
# what makes `-er` rg's -e with value "r" rather than a --replace.
RG_VALUE_FLAGS = set("efgmtjABCM")

# Transparent wrappers: the command word is whatever follows them.
WRAPPERS = ("command", "builtin", "exec")

# git's own options that consume the following token, which would otherwise be
# read as the subcommand.
GIT_VALUE_OPTIONS = ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path")

# checkout options that make a second operand a start point rather than a path.
GIT_BRANCH_OPTIONS = ("-b", "-B", "--orphan")


def _command_word(tokens):
    """Index of the segment's actual command word, or None.

    Skips `VAR=value` assignments and transparent wrappers. A leading option
    means the segment is not a command invocation this guard can read.
    """
    for i, tok in enumerate(tokens):
        if tok.startswith("-"):
            return None
        if "=" in tok or tok in WRAPPERS:
            continue
        return i
    return None


def _git_subcommand(args):
    """(subcommand, its own arguments), skipping git's global options.

    The rules below read the second half only: a global option's value belongs
    to git, so the path in `git -C /repo checkout main` must not be counted as
    an operand of checkout.
    """
    i = 0
    while i < len(args):
        tok = args[i]
        if tok in GIT_VALUE_OPTIONS:
            i += 2
        elif tok.startswith("-"):
            i += 1
        else:
            return tok, args[i + 1:]
    return None, []


def _has_flag(letter, long, args):
    """True when `-<letter>` (possibly bundled) or `--<long>` is present.

    Exact token comparison is what keeps --force-with-lease out of the --force
    rule. An empty *letter* means the option is long-form only.
    """
    for tok in args:
        if tok == "--":
            return False
        if tok == "--" + long or tok.startswith("--" + long + "="):
            return True
        if tok.startswith("--"):
            continue
        if letter and len(tok) > 1 and tok.startswith("-"):
            if letter in tok[1:].split("=", 1)[0]:
                return True
    return False


def _rg_flags(args):
    """The subset of "orc" that rg actually receives, honouring bundled flags."""
    found = ""
    for tok in args:
        if tok == "--":
            break
        if tok == "--only-matching" or tok.startswith("--only-matching="):
            found += "o"
        elif tok == "--replace" or tok.startswith("--replace="):
            found += "r"
        elif tok.startswith("--"):
            continue
        elif len(tok) > 1 and tok.startswith("-"):
            flags = tok[1:]
            # `-rn`-style clusters are ripgrep's other trap: -r silently eats the
            # following letters as its replacement value. Reported separately as
            # "c" because it is repairable -- the caller decides whether to defer
            # to rg-replace-flag-fix.py or block with a correction.
            if flags[0] == "r" and len(flags) > 1 and set(flags[1:]) <= RG_BOOL_FLAGS:
                found += "c"
                continue
            for ch in flags:
                if ch == "o":
                    found += "o"
                elif ch == "r":
                    found += "r"
                    break
                elif ch in RG_VALUE_FLAGS:
                    break
    return found


def classify(cmd):
    """First matching rule for *cmd*, or None.

    Deny-worthy rules are checked before recoverable ones.
    """
    if not cmd:
        return None

    for tokens in segments(cmd):
        idx = _command_word(tokens)
        if idx is None:
            continue
        # A path-qualified invocation runs the same program, so it gets the same
        # rules: /usr/bin/git is git.
        word = tokens[idx].rsplit("/", 1)[-1]
        args = tokens[idx + 1:]

        if word == "rg":
            flags = _rg_flags(args)
            if "o" in flags:
                continue
            if "r" in flags:
                return Verdict("rg-replace", "rg --replace")
            if "c" in flags:
                return Verdict("rg-flag-cluster", "rg -r flag cluster")
            continue

        if word != "git":
            continue

        sub, rest = _git_subcommand(args)
        if sub == "push":
            if _has_flag("f", "force", rest):
                return Verdict("force-push", "git push --force")
        elif sub == "clean":
            if _has_flag("n", "dry-run", rest) or _has_flag("i", "interactive", rest):
                continue
            return Verdict("git-clean", "git clean")
        elif sub == "reset":
            if _has_flag("", "hard", rest):
                return Verdict("git-reset-hard", "git reset --hard")
        elif sub == "restore":
            if _has_flag("W", "worktree", rest) or not (
                _has_flag("S", "staged", rest) or _has_flag("", "cached", rest)
            ):
                return Verdict("git-restore", "git restore")
        elif sub == "checkout":
            if _has_flag("f", "force", rest):
                return Verdict("git-checkout-force", "git checkout --force")
            if "--" in rest or "." in rest:
                return Verdict("git-checkout-paths", "git checkout (paths)")
            # `git checkout <tree-ish> <path>` overwrites the file outright. It
            # is the same loss as the `--` form without the separator, and it
            # gets none of the refusal that protects a plain branch switch.
            # Branch creation is the one two-operand form that touches no file.
            if not any(opt in rest for opt in GIT_BRANCH_OPTIONS):
                if len([tok for tok in rest if not tok.startswith("-")]) > 1:
                    return Verdict("git-checkout-paths", "git checkout (paths)")

    return None
