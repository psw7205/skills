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
SEPARATORS = "|;&\n"


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

        if cmd.startswith("<<", i) and not cmd.startswith("<<<", i):
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
