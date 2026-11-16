"""Shell lexing shared by the PreToolUse hooks.

One pass produces both views the hooks need:

  masked   - the command with quoted spans and heredoc bodies blanked out,
             length preserved, so a match found in the copy indexes straight
             into the original.
  segments - the quote-removed tokens of each command the shell would run.

Both views answer the same question: which characters are code and which are
data. A `git clean` inside quotes is a string being written, and a hook that
blocks or rewrites it acts on the user's text rather than on a command. Keeping
that judgement in one walk is what stops the two hooks from disagreeing.
"""

import re

MASK = "\x00"

# `<<-` strips leading tabs and the delimiter may be quoted; `<<<` is a herestring
# with no body, so it must not be mistaken for one.
HEREDOC = re.compile(r"<<-?\s*(?P<quote>['\"]?)(?P<delim>[\w.-]+)(?P=quote)")

# Operators that end one command. A single `&` covers both backgrounding and the
# second character of `&&`; runs collapse because empty segments are dropped.
# Parentheses are here because a subshell is its own command: without them
# `(git push --force)` yields the token `(git`, which matches no rule.
SEPARATORS = "|;&\n()"


def _heredoc_body_end(cmd, start, delim):
    """Index where *delim*'s terminator line begins, or end of string."""
    pos = start
    while pos < len(cmd):
        nl = cmd.find("\n", pos)
        line_end = len(cmd) if nl < 0 else nl
        if cmd[pos:line_end].strip() == delim:
            return pos
        if nl < 0:
            break
        pos = nl + 1
    return len(cmd)


def scan(cmd):
    """Lex *cmd* once. Returns (masked, segments)."""
    out = list(cmd)
    segments = []
    tokens = []
    word = []
    # Tracks an argument that exists but may be empty, so `git commit -m ""`
    # keeps its empty operand instead of losing a token.
    started = False
    pending = []  # heredoc delimiters whose bodies have not arrived yet
    arith = 0  # depth of `$((...))`, where `<<` is a shift and not a redirection
    i = 0
    n = len(cmd)

    def end_word():
        nonlocal started
        if started:
            tokens.append("".join(word))
            del word[:]
            started = False

    def end_segment():
        end_word()
        if tokens:
            segments.append(list(tokens))
            del tokens[:]

    while i < n:
        ch = cmd[i]

        if ch == "\\" and i + 1 < n:
            # Backslash-newline is a line continuation: the shell removes both.
            if cmd[i + 1] != "\n":
                word.append(cmd[i + 1])
                started = True
            i += 2
            continue

        if ch in "'\"":
            j = i + 1
            while j < n and cmd[j] != ch:
                # Only double quotes honour backslash escapes.
                if ch == '"' and cmd[j] == "\\" and j + 1 < n:
                    word.append(cmd[j + 1])
                    j += 2
                    continue
                word.append(cmd[j])
                j += 1
            started = True
            for k in range(i, min(j + 1, n)):
                out[k] = MASK
            i = j + 1
            continue

        # Arithmetic is read before both the heredoc and the separator rules:
        # `$((1<<2))` shifts, and its parentheses group an expression rather
        # than opening a subshell. Missing this masks the rest of the command
        # as a body that never terminates, hiding every command after it.
        if cmd.startswith("$((", i) or cmd.startswith("((", i):
            span = 3 if cmd[i] == "$" else 2
            arith += 1
            word.append(cmd[i:i + span])
            started = True
            i += span
            continue

        if arith and cmd.startswith("))", i):
            arith -= 1
            word.append("))")
            started = True
            i += 2
            continue

        if arith == 0 and cmd.startswith("<<", i) and not cmd.startswith("<<<", i):
            m = HEREDOC.match(cmd, i)
            if m:
                # The redirection is not an argument, and what follows it is
                # stdin data rather than a command.
                end_word()
                pending.append(m.group("delim"))
                i = m.end()
                continue

        if ch == "\n" and pending:
            end_segment()
            i += 1
            # Bodies follow the newline in the order their redirections appeared.
            while pending:
                body_end = _heredoc_body_end(cmd, i, pending.pop(0))
                for k in range(i, body_end):
                    out[k] = MASK
                nl = cmd.find("\n", body_end)
                i = n if nl < 0 else nl + 1
            continue

        if ch in SEPARATORS:
            end_segment()
            i += 1
            continue

        if ch in " \t":
            end_word()
            i += 1
            continue

        word.append(ch)
        started = True
        i += 1

    end_segment()
    return "".join(out), segments


def mask_literals(cmd):
    """Copy of *cmd* with quoted spans and heredoc bodies blanked out."""
    return scan(cmd)[0]


def segments(cmd):
    """Quote-removed tokens of each command *cmd* would run."""
    return scan(cmd)[1]
