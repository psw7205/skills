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

Verdict = namedtuple("Verdict", "rule label scope")
Verdict.__new__.__defaults__ = ("",)

# Rules whose damage no stash can undo. Ranked above the recoverable ones so a
# command that mixes the two is judged by its worst segment.
DENY_RULES = ("force-push", "rg-replace")

# Repairable by the companion rg-replace-flag-fix.py hook, so it must lose to
# every real verdict rather than mask one.
DEFER_RULES = ("rg-flag-cluster",)

# rg short flags that take no value.
# -h/-V are excluded: clustering them carries no recoverable intent.
RG_BOOL_FLAGS = set("acFHIiLlNnopqSsUuvwxz")

# rg short flags that swallow the rest of the token as their value, which is
# what makes `-er` rg's -e with value "r" rather than a --replace.
RG_VALUE_FLAGS = set("efgmtjABCM")

# Transparent wrappers: the command word is whatever follows them.
WRAPPERS = (
    "command", "builtin", "exec",
    "env", "sudo", "doas", "nohup", "setsid", "stdbuf", "ionice", "nice",
    "time", "timeout", "xargs",
)

# Programs whose `-c` argument is another command string to lex in turn.
SHELLS = ("sh", "bash", "zsh", "dash", "ksh")

# The programs any rule below can fire on. Used to find the real command word
# behind a wrapper without parsing that wrapper's own options.
GUARDED = ("git", "rg")

# git's own options that consume the following token, which would otherwise be
# read as the subcommand.
GIT_VALUE_OPTIONS = ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path")

# checkout options that make a second operand a start point rather than a path.
GIT_BRANCH_OPTIONS = ("-b", "-B", "--orphan")


def _command_word(tokens):
    """Index of the segment's actual command word, or None.

    Skips `VAR=value` assignments, the `{` of a brace group, and transparent
    wrappers. A leading option means the segment is not a command invocation
    this guard can read.
    """
    for i, tok in enumerate(tokens):
        if tok.startswith("-"):
            return None
        if "=" in tok or tok in ("{", "}"):
            continue
        if tok.rsplit("/", 1)[-1] in WRAPPERS:
            return _behind_wrapper(tokens, i + 1)
        return i
    return None


def _behind_wrapper(tokens, start):
    """Index of a guarded program invoked through a wrapper, or None.

    Wrappers disagree too much to parse exactly -- `sudo -n` takes no value
    while `sudo -u` does, and `timeout 5` puts a bare operand where the command
    belongs. Guessing wrong skips the one token the rules need to read, so this
    looks for the guarded names instead of trying to find where the wrapper's
    own arguments stop. Naming a guarded program in a later operand costs at
    most a verdict on a command that was going to be read anyway.
    """
    for i in range(start, len(tokens)):
        if tokens[i].rsplit("/", 1)[-1] in GUARDED:
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


def _has_flag(letter, long, args, value_flags=""):
    """True when `-<letter>` (possibly bundled) or `--<long>` is present.

    Exact token comparison is what keeps --force-with-lease out of the --force
    rule. An empty *letter* means the option is long-form only.

    *value_flags* names the short options that swallow the rest of the token.
    `git clean -fden` is `-e` with the pattern "n", not a dry run, so scanning a
    bundle has to stop at the first such letter instead of reading its value as
    more flags.
    """
    for tok in args:
        if tok == "--":
            return False
        if long and (tok == "--" + long or tok.startswith("--" + long + "=")):
            return True
        if tok.startswith("--"):
            continue
        if letter and len(tok) > 1 and tok.startswith("-"):
            for ch in tok[1:].split("=", 1)[0]:
                if ch == letter:
                    return True
                if ch in value_flags:
                    break
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


def _forced_refspec(rest):
    """True when a push operand forces the update without naming --force.

    `git push origin +main` destroys remote history exactly as --force does,
    and --mirror does it to every ref at once. Neither carries the flag the
    deny rule was written around.
    """
    if _has_flag("", "mirror", rest):
        return True
    after_ddash = False
    for tok in rest:
        if tok == "--":
            after_ddash = True
            continue
        if not after_ddash and tok.startswith("-"):
            continue
        if tok.startswith("+"):
            return True
    return False


def _checkout_path_operand(rest):
    """True when checkout's single operand reads as a path rather than a ref.

    A one-operand checkout is ambiguous, and git resolves it by looking at the
    repository, which this classifier cannot do. The tell-tales below cost an
    unnecessary stash when a branch happens to look like a path, and that is
    the cheap direction: the verdict only prepends a backup, while guessing
    "branch" on a real path loses the file outright.
    """
    operands = [tok for tok in rest if not tok.startswith("-")]
    if len(operands) != 1:
        return False
    operand = operands[0]
    if operand.endswith("/") or operand.startswith(("./", "../", "/")):
        return True
    return "." in operand.rsplit("/", 1)[-1]


def _verdicts(cmd, depth=0):
    """Every rule *cmd* trips, in the order the segments appear."""
    found = []
    if not cmd or depth > 2:
        return found

    for tokens in segments(cmd):
        idx = _command_word(tokens)
        if idx is None:
            continue
        # A path-qualified invocation runs the same program, so it gets the same
        # rules: /usr/bin/git is git.
        word = tokens[idx].rsplit("/", 1)[-1]
        args = tokens[idx + 1:]

        # `sh -c "git push --force"` runs the string as a command, so the guard
        # has to read it as one. Depth is bounded because each level re-lexes.
        if word in SHELLS:
            for i, tok in enumerate(args):
                if tok.startswith("-") and "c" in tok[1:] and i + 1 < len(args):
                    found.extend(_verdicts(args[i + 1], depth + 1))
                    break
            continue

        if word == "rg":
            flags = _rg_flags(args)
            if "o" in flags:
                continue
            if "r" in flags:
                found.append(Verdict("rg-replace", "rg --replace"))
            elif "c" in flags:
                found.append(Verdict("rg-flag-cluster", "rg -r flag cluster"))
            continue

        if word != "git":
            continue

        sub, rest = _git_subcommand(args)
        if sub == "push":
            if _has_flag("f", "force", rest) or _forced_refspec(rest):
                found.append(Verdict("force-push", "git push --force"))
        elif sub == "clean":
            if _has_flag("n", "dry-run", rest, "e") or _has_flag("i", "interactive", rest, "e"):
                continue
            # -x and -X reach files --include-untracked never stashes, so the
            # backup has to widen with them or it reports a capture it did not
            # make.
            ignored = _has_flag("x", "", rest, "e") or _has_flag("X", "", rest, "e")
            found.append(Verdict("git-clean", "git clean", "--all" if ignored else ""))
        elif sub == "reset":
            if _has_flag("", "hard", rest):
                found.append(Verdict("git-reset-hard", "git reset --hard"))
        elif sub == "restore":
            if _has_flag("W", "worktree", rest) or not (
                _has_flag("S", "staged", rest) or _has_flag("", "cached", rest)
            ):
                found.append(Verdict("git-restore", "git restore"))
        elif sub == "checkout":
            if _has_flag("f", "force", rest, "b"):
                found.append(Verdict("git-checkout-force", "git checkout --force"))
            elif "--" in rest or "." in rest:
                found.append(Verdict("git-checkout-paths", "git checkout (paths)"))
            # `git checkout <tree-ish> <path>` overwrites the file outright. It
            # is the same loss as the `--` form without the separator, and it
            # gets none of the refusal that protects a plain branch switch.
            # Branch creation is the one two-operand form that touches no file.
            elif not any(opt in rest for opt in GIT_BRANCH_OPTIONS):
                operands = [tok for tok in rest if not tok.startswith("-")]
                if len(operands) > 1 or _checkout_path_operand(rest):
                    found.append(Verdict("git-checkout-paths", "git checkout (paths)"))

    return found


def _rank(verdict):
    if verdict.rule in DENY_RULES:
        return 0
    if verdict.rule in DEFER_RULES:
        return 2
    return 1


def classify(cmd):
    """The worst rule *cmd* trips, or None.

    Every segment is read before a verdict is chosen. Returning the first match
    instead would let a harmless-looking leading segment decide the whole
    command: `rg -rn foo . && git push --force` would be handed to the flag-fix
    hook and the force push would never be seen.
    """
    found = _verdicts(cmd)
    if not found:
        return None
    return min(found, key=_rank)
