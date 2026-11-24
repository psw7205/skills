#!/usr/bin/env python3
"""Restart idle Claude Code and Codex sessions in hc terminals onto the installed version.

Dry run by default; --apply restarts. Stdlib only.
"""
import argparse
import json
import os
import re
import shlex
import subprocess
import time

IDLE = {"done", "idle"}
SHELLS = {"sh", "bash", "zsh", "fish", "dash", "ksh"}
AGENTS = {
    "claude-code": {
        "bin": "claude", "exit": "/exit", "extra": [],
        "drop": {"-c", "--continue", "-r", "--resume", "--session-id", "--fork-session",
                 "--from-pr", "-p", "--print"},
        "history": ("~/.claude/projects", "{}.jsonl"),
    },
    "codex": {
        # hc runs Codex only with --no-daemon; otherwise its commands run outside hc.
        "bin": "codex", "exit": "/quit", "extra": ["--no-daemon"],
        "drop": {"--last", "--all", "--include-non-interactive"},
        "history": ("~/.codex/sessions", "rollout-*-{}.jsonl"),
    },
}


def hc(*args, check=True, env=None):
    r = subprocess.run(["hc", *args], capture_output=True, text=True, env=env)
    if check and r.returncode != 0:
        raise RuntimeError(f"hc {' '.join(args[:2])}: {r.stderr.strip()}")
    return r.stdout


def type_raw(addr, text):
    # From an agent terminal hc wraps sends in <hc from=...> tags, which breaks
    # slash commands and shell lines; without a sender identity it types plain text.
    env = {k: v for k, v in os.environ.items() if k != "HC_TERMINAL_ID"}
    hc("send", addr, text, env=env)


def on(machine):
    return ["--on", machine] if machine else []


def sh(machine, line):
    return hc("exec", *on(machine), line)


def version(text):
    return tuple(int(x) for x in re.search(r"(\d+(?:\.\d+)+)", text).group(1).split("."))


def flag_arity(help_text):
    # Mirrors commander/clap: <v>/[v] take the next non-flag token, "..." takes all of them.
    arity = {}
    pat = r"^ {2,8}((?:-\w, )?--[\w-]+(?:, --[\w-]+)?)(?: ([<\[][^>\]]+[>\]](?:\.\.\.)?))?"
    for m in re.finditer(pat, help_text, re.M):
        n = 0 if not m.group(2) else ("*" if "..." in m.group(2) else 1)
        for name in m.group(1).split(", "):
            arity[name] = n
    return arity


def relaunch_flags(argv, arity, drop):
    out, i = [], 1
    while i < len(argv):
        tok = argv[i]
        if not tok.startswith("-"):
            i += 1
            continue
        name = tok.split("=", 1)[0]
        take = 0 if "=" in tok else arity.get(name, 0)
        j = i + 1
        while take and j < len(argv) and not argv[j].startswith("-"):
            j += 1
            if take == 1:
                break
        if name not in drop:
            out += argv[i:j]
        i = j
    return out


def parent_flag(parent, machine, me):
    """--parent as the target machine sees it; None when it cannot be expressed."""
    if not parent:
        return ["--no-parent"]
    pm, _, pt = parent.rpartition("/")
    if (pm or None) == machine:
        return ["--parent", pt]
    if not pm and parent == me:
        return []  # hc defaults the parent to the calling terminal
    return None


def running_session(agent, machine, pid):
    """(running version, session id or None until exit)."""
    if agent == "claude-code":
        sess = json.loads(sh(machine, f"cat ~/.claude/sessions/{pid}.json"))
        return version(sess["version"]), sess["sessionId"]
    exe = sh(machine, f"readlink /proc/{pid}/exe 2>/dev/null || lsof -a -p {pid} -d txt -Fn | sed -n 2p")
    m = re.search(r"releases/(\d+(?:\.\d+)+)", exe)
    if not m:
        raise ValueError(f"no version in executable path {exe.strip()!r}")
    return version(m.group(1)), None


def has_conversation(machine, spec, sid):
    # Both agents write the session file at the first message; resuming a session without one fails.
    root, name = spec["history"]
    found = sh(machine, f"if [ -d {root} ]; then find {root} -name '{name.format(sid)}' -print -quit; fi")
    return bool(found.strip())


def wait_exit(addr, pid, root_is_shell):
    deadline = time.time() + 30
    while time.time() < deadline:
        d = json.loads(hc("get", "--json", addr))
        if root_is_shell:
            # foreground is briefly absent while the process exits
            if d.get("foreground", {}).get("pid") not in (pid, None):
                return
        elif d["state"] == "finished":
            return
        time.sleep(0.5)
    raise SystemExit(f"{addr}: agent did not exit")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("terminals", nargs="*", help="only these addresses or names (default: all)")
    ap.add_argument("--apply", action="store_true", help="restart (default: dry run)")
    ap.add_argument("--force", action="store_true", help="restart even when already on the installed version")
    args = ap.parse_args()

    me = os.environ.get("HC_TERMINAL_ID")
    live = [t for t in json.loads(hc("ls", "--json"))["terminals"] if t["state"] == "live"]
    info = {t["address"]: json.loads(hc("get", "--json", t["address"])) for t in live}
    parents = {d.get("parent") for d in info.values()}
    tools = {}

    for t in live:
        addr, agent = t["address"], t.get("agent")
        if agent not in AGENTS or addr == me:
            continue
        spec = AGENTS[agent]
        d = info[addr]
        machine = addr.split("/")[0] if "/" in addr else None
        names = {addr, d.get("name"), f"{machine}/{d.get('name')}" if machine else None}
        if args.terminals and not names & set(args.terminals):
            continue
        try:
            if (machine, agent) not in tools:
                tools[machine, agent] = (version(sh(machine, f"{spec['bin']} --version")),
                                         flag_arity(sh(machine, f"{spec['bin']} --help")))
            installed, arity = tools[machine, agent]
            fg = d["foreground"]
            running, sid = running_session(agent, machine, fg["pid"])
        except (RuntimeError, ValueError, AttributeError, KeyError) as e:
            print(f"{addr:14} skip  {e}")
            continue
        label = f"{addr:14} {'.'.join(map(str, running)):>9} -> {'.'.join(map(str, installed))}  {sid or '(id at exit)'}"
        if running >= installed and not args.force:
            continue
        status = t.get("status") or ""
        if status not in IDLE:
            print(f"{label}  skip  status={status or 'none'}")
            continue
        if addr in parents or addr.split("/")[-1] in parents:
            print(f"{label}  skip  has child terminals")
            continue
        root_is_shell = os.path.basename(d["argv"][0]) in SHELLS
        pflag = parent_flag(d.get("parent"), machine, me)
        if not root_is_shell and pflag is None:
            print(f"{label}  skip  parent {d['parent']} not addressable from {machine}; run from it")
            continue
        # A daemon-mode Codex thread stays locked by the app-server after the TUI quits.
        from_daemon = agent == "codex" and "--no-daemon" not in fg["argv"]
        flags = relaunch_flags(fg["argv"], arity, spec["drop"])
        flags += [f for f in spec["extra"] if f not in flags]
        fresh = sid is not None and not has_conversation(machine, spec, sid)

        def command(resume_id):
            if resume_id is None:
                return [spec["bin"], *flags]
            resume = ["--resume", resume_id] if agent == "claude-code" else ["resume", resume_id]
            return [spec["bin"], *resume, *flags]

        mode = ("in-place" if root_is_shell else "relaunch") + (", no conversation" if fresh else "")
        print(f"{label}  {mode}  {shlex.join(command(None if fresh else sid or '<id>'))}")
        daemon_note = (f"{'':14} then: hc exec{' --on ' + machine if machine else ''} 'codex app-server daemon restart'"
                       f"; press r in {addr} (daemon holds the thread lock)")
        if from_daemon:
            print(daemon_note)
        if not args.apply:
            continue

        type_raw(addr, spec["exit"])
        wait_exit(addr, fg["pid"], root_is_shell)
        if sid is None:
            # Scrollback also holds conversation text; accept only the UUID of Codex's exit lines.
            # Without a conversation it prints "Session ID:" and no resume hint.
            found = re.findall(r"(?:To continue this session, run:\s+codex resume|^Session ID:) "
                               r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b",
                               hc("read", addr, "--lines", "60"), re.M)
            if not found:
                raise SystemExit(f"{addr}: exited but printed no session id")
            sid = found[-1]
            fresh = not has_conversation(machine, spec, sid)
        cmd = command(None if fresh else sid)

        if root_is_shell:
            # `command` skips shell aliases that would repeat flags already in argv
            type_raw(addr, f"cd {shlex.quote(d['foreground'].get('cwd') or d['cwd'])} && command {shlex.join(cmd)}")
        else:
            hc("rm", addr)
            run = ["run", "--bg", *on(machine), "--cwd", fg.get("cwd") or d["cwd"], *pflag]
            if d.get("name"):
                run += ["--name", d["name"]]
            if d.get("keep"):
                run.append("--keep")
            for k, v in (d.get("labels") or {}).items():
                run += ["--label", f"{k}={v}"]
            try:
                new = json.loads(hc(*run, "--json", "--", *cmd))
            except RuntimeError as e:
                raise SystemExit(f"{e}\nold terminal is gone; recover with: hc {shlex.join(run + ['--', *cmd])}")
            print(f"{'':14} now {new.get('address')}")
        print(f"{'':14} {'new session; ' + sid + ' had no conversation' if fresh else 'resumed ' + sid}")

    if not args.apply:
        print("dry run; pass --apply to restart")


if __name__ == "__main__":
    main()
