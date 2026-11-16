#!/usr/bin/env python3
"""Converge Claude Code and Codex agent config to this skill's canonical state.

check  shows drift, apply converges, remove takes components out and remembers that.
Python 3.9 compatible on purpose: macOS ships /usr/bin/python3 3.9.
"""
import argparse
import copy
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

SCRIPTS = os.path.dirname(os.path.realpath(__file__))
SKILL = os.path.dirname(SCRIPTS)
REFS = os.path.join(SKILL, "references")

AGENTS = ("claude", "codex")
SETTLED = ("ok", "disabled", "n/a")
SEVERITY = ["ok", "outdated", "missing", "stale", "needs-review", "user-modified", "blocked"]


class SyncError(Exception):
    pass


def home():
    return os.path.expanduser("~")


def agent_dir(agent):
    if agent == "claude":
        return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(home(), ".claude")
    return os.environ.get("CODEX_HOME") or os.path.join(home(), ".codex")


def agent_present(agent):
    return os.path.isdir(agent_dir(agent)) or shutil.which(agent) is not None


def state_dir():
    return os.path.join(home(), ".agents", "setup-machine")


def statusline_command():
    default = os.path.join(home(), ".claude")
    if os.path.realpath(agent_dir("claude")) == os.path.realpath(default):
        return "~/.claude/statusline-command.sh"
    return os.path.join(agent_dir("claude"), "statusline-command.sh")


class Handler(object):
    def __init__(self, event, matcher, interpreter, script, args="", fields=None, legacy=()):
        self.event = event
        self.matcher = matcher
        self.script = script
        self.names = (script,) + tuple(legacy)
        command = "%s %s" % (interpreter, shlex.quote(os.path.join(SCRIPTS, script)))
        self.desired = {"type": "command", "command": command + (" " + args if args else "")}
        self.desired.update(fields or {})

    def owns(self, command):
        return any(re.search(r"(^|[/\s'\"])%s($|[\s'\"])" % re.escape(n), command or "") for n in self.names)


VERIFY_FIELDS = {"timeout": 5, "statusMessage": "Checking for unverified claims..."}
GUARD_MESSAGE = "Guarding risky shell commands..."


def component_specs():
    """Ordered registry. files: (source, path relative to agent dir, mode). keys: (name, value, owned)."""
    return [
        {
            "id": "global-config",
            "requires": [],
            "claude": {"files": [(os.path.join(REFS, "global-config.md"), "CLAUDE.md", None)]},
            "codex": {"files": [(os.path.join(REFS, "global-config.md"), "AGENTS.md", None)]},
        },
        {
            "id": "output-style",
            "requires": [],
            "claude": {
                "files": [(os.path.join(REFS, "korean-concise.md"), "output-styles/korean-concise.md", None)],
                "keys": [("outputStyle", "korean-concise", lambda v: v == "korean-concise")],
            },
        },
        {
            "id": "statusline",
            "requires": ["jq"],
            "interactive": True,
            "claude": {
                "files": [(os.path.join(SCRIPTS, "statusline-command.sh"), "statusline-command.sh", 0o755)],
                "keys": [(
                    "statusLine",
                    {"type": "command", "command": statusline_command()},
                    lambda v: isinstance(v, dict) and str(v.get("command", "")).endswith("statusline-command.sh"),
                )],
            },
        },
        {
            "id": "shell-guard",
            "requires": ["python3"],
            "claude": {"handlers": [
                Handler("PreToolUse", "Bash", "python3", "guard-commands.py",
                        fields={"statusMessage": GUARD_MESSAGE}, legacy=("guard-commands.sh", "guard-untracked.sh")),
                Handler("PreToolUse", "Bash", "python3", "rg-replace-flag-fix.py",
                        fields={"statusMessage": "Repairing rg flag clusters..."}),
            ]},
            "codex": {"handlers": [
                Handler("PreToolUse", "Bash|exec", "python3", "guard-commands-codex.py",
                        fields={"async": False, "timeoutSec": 5, "statusMessage": GUARD_MESSAGE},
                        legacy=("guard-commands-codex.sh", "guard-untracked-codex.sh")),
            ]},
        },
        {
            "id": "artifact-guard",
            "requires": ["python3"],
            "claude": {"handlers": [
                Handler("PreToolUse", "Artifact", "python3", "guard-artifact.py",
                        fields={"timeout": 10, "onFailure": "block"}),
            ]},
        },
        {
            "id": "verify-gate",
            "requires": ["jq"],
            "claude": {"handlers": [Handler("Stop", None, "bash", "stop-verify-gate.sh", "claude", VERIFY_FIELDS)]},
            "codex": {"handlers": [Handler("Stop", None, "bash", "stop-verify-gate.sh", "codex", VERIFY_FIELDS)]},
        },
        {
            "id": "session-log",
            "requires": ["jq"],
            "claude": {"handlers": [
                Handler("Stop", None, "bash", "stop-session-log.sh", fields={"statusMessage": "Appending session log..."}),
            ]},
        },
    ]


# ---------- persistence ----------

def load_json(path, default):
    if not os.path.exists(path):
        return default
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        return json.loads(text) if text.strip() else default
    except (OSError, ValueError) as exc:
        raise SyncError("cannot parse %s: %s" % (path, exc))


def dump_json(data):
    return (json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


class Writer:
    """Writes only on change, backs up first, writes through symlinks."""

    def __init__(self):
        self.backups = []
        self.stamp = time.strftime("%Y%m%dT%H%M%S")

    def write(self, path, data, mode=None):
        real = os.path.realpath(path)
        if os.path.exists(real):
            if read_bytes(real) == data:
                if mode is not None and (os.stat(real).st_mode & 0o777) != mode:
                    os.chmod(real, mode)
                    return True
                return False
            backup = "%s.bak.%s" % (real, self.stamp)
            shutil.copy2(real, backup)
            self.backups.append(backup)
        os.makedirs(os.path.dirname(real), exist_ok=True)
        with open(real, "wb") as f:
            f.write(data)
        if mode is not None:
            os.chmod(real, mode)
        return True

    def delete(self, path):
        real = os.path.realpath(path)
        backup = "%s.bak.%s" % (real, self.stamp)
        shutil.copy2(real, backup)
        self.backups.append(backup)
        os.remove(real)


# ---------- item reconcilers ----------

def file_item(mode, source, target, perm, state, writer, overwrite):
    canonical = read_bytes(source)
    files = state.setdefault("files", {})
    if not os.path.exists(target):
        if mode == "apply":
            writer.write(target, canonical, perm)
            files[target] = sha(canonical)
            return "ok", ["installed %s" % target]
        return ("disabled" if mode == "remove" else "missing"), []
    current = read_bytes(target)
    if current == canonical:
        if mode == "remove":
            writer.delete(target)
            files.pop(target, None)
            return "disabled", ["removed %s" % target]
        files[target] = sha(canonical)
        changed = mode == "apply" and perm is not None and writer.write(target, canonical, perm)
        return "ok", (["chmod %s" % target] if changed else [])
    ours = files.get(target) == sha(current)
    if mode == "remove":
        if ours:
            writer.delete(target)
            files.pop(target, None)
            return "disabled", ["removed %s" % target]
        return "user-modified", ["kept %s (differs from canonical)" % target]
    if mode == "apply" and (ours or overwrite):
        writer.write(target, canonical, perm)
        files[target] = sha(canonical)
        return "ok", ["updated %s" % target]
    return ("outdated" if ours else "user-modified"), []


def key_item(mode, cfg, name, value, owned, overwrite):
    if name not in cfg:
        if mode == "apply":
            cfg[name] = value
            return "ok", ["set %s" % name]
        return ("disabled" if mode == "remove" else "missing"), []
    current = cfg[name]
    if mode == "remove":
        if owned(current):
            del cfg[name]
            return "disabled", ["unset %s" % name]
        return "disabled", []
    if current == value:
        return "ok", []
    if owned(current) or overwrite:
        if mode == "apply":
            cfg[name] = value
            return "ok", ["set %s" % name]
        return ("stale" if owned(current) else "user-modified"), []
    return "user-modified", ["%s is %s" % (name, json.dumps(current, ensure_ascii=False))]


def occurrences(cfg, handler):
    found = []
    for i, entry in enumerate(cfg.get("hooks", {}).get(handler.event, [])):
        for j, h in enumerate(entry.get("hooks", [])):
            if handler.owns(h.get("command")):
                found.append((i, j))
    return found


def handler_item(mode, cfg, handler):
    """Edits cfg in place. Keeps array positions: Codex hook trust is keyed by them."""
    entries = cfg.get("hooks", {}).get(handler.event, [])
    found = occurrences(cfg, handler)
    if mode == "remove":
        for i, j in reversed(found):
            del entries[i]["hooks"][j]
        return "disabled", (["unregistered %s" % handler.script] if found else [])
    keep = found[0] if found and entries[found[0][0]].get("matcher") == handler.matcher else None
    extra = [loc for loc in found if loc != keep]
    if keep is not None and not extra and entries[keep[0]]["hooks"][keep[1]] == handler.desired:
        return "ok", []
    status = "stale" if found else "missing"
    if mode != "apply":
        return status, []
    for i, j in sorted(extra, reverse=True):
        del entries[i]["hooks"][j]
    if keep is not None:
        entries[keep[0]]["hooks"][keep[1]] = dict(handler.desired)
        return "ok", ["updated %s" % handler.script]
    entries = cfg.setdefault("hooks", {}).setdefault(handler.event, entries)
    for entry in entries:
        if entry.get("matcher") == handler.matcher:
            entry.setdefault("hooks", []).append(dict(handler.desired))
            break
    else:
        entry = {"matcher": handler.matcher} if handler.matcher is not None else {}
        entry["hooks"] = [dict(handler.desired)]
        entries.append(entry)
    return "ok", ["registered %s" % handler.script]


def sweep_empty(cfg):
    notes = []
    hooks = cfg.get("hooks", {})
    for event in list(hooks):
        entries = hooks[event]
        for i in reversed(range(len(entries))):
            if not entries[i].get("hooks"):
                if i != len(entries) - 1:
                    notes.append("index shift: %s" % event)
                del entries[i]
        if not entries:
            del hooks[event]
    return notes


def snake(event):
    return re.sub(r"(?<!^)([A-Z])", r"_\1", event).lower()


def codex_hooks_feature():
    if shutil.which("codex") is None:
        return None
    try:
        out = subprocess.run(["codex", "features", "list"], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    for line in out.splitlines():
        parts = line.split()
        if parts and parts[0] == "hooks":
            return parts[-1] == "true"
    return None


def codex_trust(config_toml):
    """{hook position key: trusted_hash} from [hooks.state."<key>"] tables."""
    trust = {}
    key = None
    try:
        with open(config_toml, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    m = re.match(r'^\[hooks\.state\."(.+)"\]$', line)
                    key = m.group(1) if m else None
                    if key:
                        trust[key] = None
                elif key:
                    m = re.match(r'^trusted_hash\s*=\s*"(.*)"$', line)
                    if m:
                        trust[key] = m.group(1)
    except OSError:
        pass
    return trust


def worst(statuses):
    if not statuses:
        return "ok"
    if all(s == "disabled" for s in statuses):
        return "disabled"
    statuses = [s for s in statuses if s != "disabled"] or ["ok"]
    return max(statuses, key=SEVERITY.index)


# ---------- main ----------

def parse_list(text, allowed, what):
    if not text:
        return None
    items = [x.strip() for x in text.split(",") if x.strip()]
    bad = [x for x in items if x not in allowed]
    if bad:
        raise SyncError("unknown %s: %s" % (what, ", ".join(bad)))
    return items


def run(argv):
    parser = argparse.ArgumentParser(prog="sync.py")
    parser.add_argument("mode", choices=["check", "apply", "remove", "profile"])
    parser.add_argument("--agent")
    parser.add_argument("--only")
    parser.add_argument("--overwrite")
    parser.add_argument("--interactive", choices=["true", "false"])
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    specs = component_specs()
    ids = [s["id"] for s in specs]
    profile_path = os.path.join(state_dir(), "profile.json")
    state_path = os.path.join(state_dir(), "state.json")
    profile = load_json(profile_path, {})
    profile.setdefault("disabled", [])
    writer = Writer()

    if args.mode == "profile":
        if args.interactive is not None:
            profile["interactive"] = args.interactive == "true"
            writer.write(profile_path, dump_json(profile))
        print(json.dumps(profile, ensure_ascii=False))
        return 0

    only = parse_list(args.only, ids, "component")
    agents = parse_list(args.agent, AGENTS, "agent") or list(AGENTS)
    overwrite = set(parse_list(args.overwrite, ids, "component") or [])
    if args.mode == "remove" and not only:
        raise SyncError("remove needs --only")

    state = load_json(state_path, {"files": {}})
    settings_path = os.path.join(agent_dir("claude"), "settings.json")
    settings = load_json(settings_path, None) if "claude" in agents else None
    settings_out = copy.deepcopy(settings) if isinstance(settings, dict) else {}
    hooks_path = os.path.join(agent_dir("codex"), "hooks.json")
    codex_cfg = load_json(hooks_path, None) if "codex" in agents else None
    codex_out = copy.deepcopy(codex_cfg) if isinstance(codex_cfg, dict) else {"hooks": {}}
    cfg_for = {"claude": settings_out, "codex": codex_out}
    feature = {}
    codex_rows = []

    results = []
    for spec in specs:
        cid = spec["id"]
        if only is not None and cid not in only:
            continue
        explicit = only is not None and cid in only
        for agent in agents:
            part = spec.get(agent)
            if part is None:
                continue
            off = "%s:%s" % (cid, agent)
            if args.mode == "apply" and explicit and off in profile["disabled"]:
                profile["disabled"].remove(off)
            if args.mode == "remove" and off not in profile["disabled"]:
                profile["disabled"].append(off)
            row = {"component": cid, "agent": agent, "status": "ok", "detail": "", "changes": []}
            results.append(row)
            if not agent_present(agent):
                row["status"], row["detail"] = "n/a", "%s not installed" % agent
                continue
            if args.mode != "remove" and off in profile["disabled"]:
                row["status"] = "disabled"
                continue
            if args.mode != "remove":
                missing = [t for t in spec["requires"] if shutil.which(t) is None]
                if missing:
                    row["status"], row["detail"] = "blocked", "missing %s" % ", ".join(missing)
                    if any(handler_item("check", cfg_for[agent], h)[0] == "stale" for h in part.get("handlers", [])):
                        row["detail"] += "; 옛 경로 등록 남음, 옛 스킬을 지우지 말 것"
                    continue
                if spec.get("interactive"):
                    if profile.get("interactive") is None:
                        row["status"], row["detail"] = "blocked", "profile interactive 미정"
                        continue
                    if profile["interactive"] is False:
                        row["status"], row["detail"] = "n/a", "headless machine"
                        continue
            statuses = []
            for source, rel, perm in part.get("files", []):
                status, changes = file_item(
                    args.mode, source, os.path.join(agent_dir(agent), rel), perm, state, writer, cid in overwrite)
                statuses.append(status)
                row["changes"] += changes
            for name, value, owned in part.get("keys", []):
                status, changes = key_item(args.mode, settings_out, name, value, owned, cid in overwrite)
                statuses.append(status)
                row["changes"] += changes
            for handler in part.get("handlers", []):
                status, changes = handler_item(args.mode, cfg_for[agent], handler)
                statuses.append(status)
                row["changes"] += changes
            row["status"] = worst(statuses)
            if agent == "codex" and part.get("handlers") and args.mode != "remove":
                if "on" not in feature:
                    feature["on"] = codex_hooks_feature()
                    if feature["on"] is False and args.mode == "apply":
                        try:
                            subprocess.run(["codex", "features", "enable", "hooks"], capture_output=True, timeout=30)
                        except (OSError, subprocess.SubprocessError):
                            pass
                        feature["on"] = codex_hooks_feature()
                        if feature["on"]:
                            row["changes"].append("enabled codex hooks feature")
                if feature["on"] is None:
                    row["status"], row["detail"] = "blocked", "codex 명령 없음, hooks 기능 상태 미확정"
                elif feature["on"] is False:
                    row["status"], row["detail"] = "blocked", "codex hooks 기능 꺼짐 (apply가 codex features enable hooks로 켠다)"
                elif row["status"] == "ok":
                    codex_rows.append((row, part["handlers"]))
            if row["status"] == "user-modified" and not row["detail"]:
                row["detail"] = "differs from canonical; rerun apply with --overwrite %s after review" % cid

    for agent in agents:
        for note in sweep_empty(cfg_for[agent]):
            for r in results:
                if r["agent"] == agent and r["changes"]:
                    r["changes"].append(note)
                    break
    # Codex keys trust by position, so an in-place command change keeps a stale hash under the same key.
    # Remember the hash seen when we changed a handler; it is reviewed once Codex stores a different one.
    trust = codex_trust(os.path.join(agent_dir("codex"), "config.toml"))
    pending = state.setdefault("codex_trust", {})
    for row, handlers in codex_rows:
        keys = ["%s:%s:%d:%d" % (hooks_path, snake(h.event), i, j) for h in handlers for i, j in occurrences(codex_out, h)]
        for k in keys:
            if row["changes"]:
                pending[k] = trust.get(k)
            elif k in pending and k in trust and trust[k] != pending[k]:
                del pending[k]
        if not keys or any(k not in trust or k in pending for k in keys):
            row["status"], row["detail"] = "needs-review", "새 Codex 세션에서 /hooks로 승인"

    if args.mode != "check":
        if settings_out != (settings or {}) and (settings is not None or settings_out):
            writer.write(settings_path, dump_json(settings_out))
        if "codex" in agents and agent_present("codex") and codex_out != (codex_cfg or {"hooks": {}}):
            writer.write(hooks_path, dump_json(codex_out))
        writer.write(state_path, dump_json(state))
        writer.write(profile_path, dump_json(profile))

    changed = any(r["changes"] for r in results)
    report = {"results": results, "backups": writer.backups, "restart": changed}
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        for r in results:
            line = "%-16s %-7s %-14s %s" % (r["component"], r["agent"], r["status"], r["detail"])
            print(line.rstrip())
            for c in r["changes"]:
                print("    - " + c)
        for b in writer.backups:
            print("backup: " + b)
        if changed:
            print("새 Claude Code·Codex 세션부터 적용된다.")
    return 0 if all(r["status"] in SETTLED for r in results) else 1


def main():
    try:
        sys.exit(run(sys.argv[1:]))
    except SyncError as exc:
        print("error: %s" % exc, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
