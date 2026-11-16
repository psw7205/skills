#!/usr/bin/env python3
"""Contract tests for sync.py. Each test runs the CLI against a throwaway HOME."""
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(SCRIPTS)
SYNC = os.path.join(SCRIPTS, "sync.py")
GLOBAL = os.path.join(SKILL, "references", "global-config.md")
STYLE = os.path.join(SKILL, "references", "korean-concise.md")
STATUSLINE = os.path.join(SCRIPTS, "statusline-command.sh")

FAKE_CODEX = """#!/bin/sh
state="${0%/*}/codex-hooks-feature"
case "$1 $2" in
  "features list") read -r value < "$state"; printf 'hooks                                    stable             %s\\n' "$value" ;;
  "features enable") [ -f "${0%/*}/codex-enable-works" ] && echo true > "$state"; exit 0 ;;
  *) exit 0 ;;
esac
"""


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class Env:
    def __init__(self, jq=True, codex_dir=True, codex_cmd=True, feature=True, enable_works=True):
        self.root = tempfile.mkdtemp()
        self.home = os.path.join(self.root, "home")
        self.claude = os.path.join(self.home, ".claude")
        self.codex = os.path.join(self.home, ".codex")
        self.bin = os.path.join(self.root, "bin")
        os.makedirs(self.claude)
        os.makedirs(self.bin)
        if codex_dir:
            os.makedirs(self.codex)
        tools = ["python3", "sh", "bash"] + (["jq"] if jq else [])
        for tool in tools:
            found = shutil.which(tool)
            if found:
                os.symlink(found, os.path.join(self.bin, tool))
        if codex_cmd:
            path = os.path.join(self.bin, "codex")
            with open(path, "w") as f:
                f.write(FAKE_CODEX)
            os.chmod(path, 0o755)
            self.set_feature(feature)
            if enable_works:
                open(os.path.join(self.bin, "codex-enable-works"), "w").close()

    def set_feature(self, on):
        with open(os.path.join(self.bin, "codex-hooks-feature"), "w") as f:
            f.write("true" if on else "false")

    @property
    def settings(self):
        return os.path.join(self.claude, "settings.json")

    @property
    def hooks_json(self):
        return os.path.join(self.codex, "hooks.json")

    def write_json(self, path, data):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)

    def load(self, path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)

    def run(self, *args):
        env = {"HOME": self.home, "PATH": self.bin, "LC_ALL": "C.UTF-8"}
        proc = subprocess.run(
            [sys.executable, SYNC] + list(args) + ["--json"] if args[0] != "profile" else [sys.executable, SYNC] + list(args),
            env=env, capture_output=True, text=True,
        )
        out = None
        if proc.stdout.strip().startswith("{"):
            out = json.loads(proc.stdout)
        return proc.returncode, out, proc

    def status(self, out, component, agent="claude"):
        for row in out["results"]:
            if row["component"] == component and row["agent"] == agent:
                return row["status"]
        raise AssertionError("no row %s/%s in %r" % (component, agent, out["results"]))

    def backups(self):
        found = []
        for root, _, names in os.walk(self.root):
            found += [os.path.join(root, n) for n in names if ".bak." in n]
        return found

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)


FILES = "global-config,output-style,statusline"


class FileComponents(unittest.TestCase):
    def setUp(self):
        self.e = Env()
        self.e.run("profile", "--interactive", "true")

    def tearDown(self):
        self.e.cleanup()

    def test_fresh_apply_then_ok(self):
        code, out, p = self.e.run("apply", "--only", FILES)
        self.assertEqual(code, 0, p.stdout + p.stderr)
        self.assertEqual(read(os.path.join(self.e.claude, "CLAUDE.md")), read(GLOBAL))
        self.assertEqual(read(os.path.join(self.e.codex, "AGENTS.md")), read(GLOBAL))
        self.assertEqual(read(os.path.join(self.e.claude, "output-styles", "korean-concise.md")), read(STYLE))
        sl = os.path.join(self.e.claude, "statusline-command.sh")
        self.assertEqual(read(sl), read(STATUSLINE))
        self.assertTrue(os.access(sl, os.X_OK))
        s = self.e.load(self.e.settings)
        self.assertEqual(s["outputStyle"], "korean-concise")
        self.assertEqual(s["statusLine"], {"type": "command", "command": "~/.claude/statusline-command.sh"})
        code, out, p = self.e.run("check", "--only", FILES)
        self.assertEqual(code, 0, p.stdout)

    def test_second_apply_writes_nothing(self):
        self.e.run("apply", "--only", FILES)
        targets = [self.e.settings, os.path.join(self.e.claude, "CLAUDE.md")]
        before = [os.stat(t).st_mtime_ns for t in targets]
        nbak = len(self.e.backups())
        code, out, _ = self.e.run("apply", "--only", FILES)
        self.assertEqual(code, 0)
        self.assertEqual([os.stat(t).st_mtime_ns for t in targets], before)
        self.assertEqual(len(self.e.backups()), nbak)

    def test_outdated_auto_updates(self):
        self.e.run("apply", "--only", "global-config")
        target = os.path.join(self.e.claude, "CLAUDE.md")
        state_path = os.path.join(self.e.home, ".agents", "setup-machine", "state.json")
        state = self.e.load(state_path)
        with open(target, "w") as f:
            f.write("old canonical\n")
        import hashlib
        state["files"][target] = hashlib.sha256(b"old canonical\n").hexdigest()
        self.e.write_json(state_path, state)
        code, out, _ = self.e.run("check", "--only", "global-config")
        self.assertEqual(self.e.status(out, "global-config"), "outdated")
        code, out, _ = self.e.run("apply", "--only", "global-config")
        self.assertEqual(code, 0)
        self.assertEqual(read(target), read(GLOBAL))
        self.assertEqual(len([b for b in self.e.backups() if "CLAUDE.md" in b]), 1)

    def test_user_modified_preserved_until_overwrite(self):
        target = os.path.join(self.e.claude, "CLAUDE.md")
        with open(target, "w") as f:
            f.write("my own rules\n")
        code, out, _ = self.e.run("apply", "--only", "global-config")
        self.assertEqual(code, 1)
        self.assertEqual(self.e.status(out, "global-config"), "user-modified")
        self.assertEqual(read(target), "my own rules\n")
        code, out, _ = self.e.run("apply", "--only", "global-config", "--overwrite", "global-config")
        self.assertEqual(code, 0)
        self.assertEqual(read(target), read(GLOBAL))
        self.assertTrue(any("CLAUDE.md.bak." in b for b in self.e.backups()))

    def test_foreign_output_style_is_user_modified(self):
        self.e.write_json(self.e.settings, {"outputStyle": "Explanatory"})
        code, out, _ = self.e.run("apply", "--only", "output-style")
        self.assertEqual(self.e.status(out, "output-style"), "user-modified")
        self.assertEqual(self.e.load(self.e.settings)["outputStyle"], "Explanatory")

    def test_unrelated_keys_preserved(self):
        original = {
            "permissions": {"allow": ["Bash(ls:*)"]},
            "env": {"FOO": "1"},
            "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "bash /x/herdr.sh"}]}]},
        }
        self.e.write_json(self.e.settings, original)
        self.e.run("apply", "--only", FILES)
        s = self.e.load(self.e.settings)
        for key in original:
            self.assertEqual(s[key], original[key])

    def test_symlinked_settings_written_through(self):
        real = os.path.join(self.e.root, "dotfiles-settings.json")
        self.e.write_json(real, {"env": {"A": "1"}})
        os.symlink(real, self.e.settings)
        self.e.run("apply", "--only", "output-style")
        self.assertTrue(os.path.islink(self.e.settings))
        self.assertEqual(self.e.load(real)["outputStyle"], "korean-concise")

    def test_broken_json_exit2_no_write(self):
        with open(self.e.settings, "w") as f:
            f.write("{")
        code, out, _ = self.e.run("apply", "--only", FILES)
        self.assertEqual(code, 2)
        self.assertEqual(read(self.e.settings), "{")
        self.assertFalse(os.path.exists(os.path.join(self.e.claude, "CLAUDE.md")))

    def test_remove_records_disabled(self):
        self.e.run("apply", "--only", "output-style")
        style = os.path.join(self.e.claude, "output-styles", "korean-concise.md")
        code, out, _ = self.e.run("remove", "--only", "output-style")
        self.assertEqual(code, 0)
        self.assertFalse(os.path.exists(style))
        self.assertNotIn("outputStyle", self.e.load(self.e.settings))
        profile = self.e.load(os.path.join(self.e.home, ".agents", "setup-machine", "profile.json"))
        self.assertIn("output-style:claude", profile["disabled"])
        code, out, _ = self.e.run("apply")
        self.assertFalse(os.path.exists(style))
        self.assertEqual(self.e.status(out, "output-style"), "disabled")
        self.e.run("apply", "--only", "output-style")
        self.assertTrue(os.path.exists(style))
        profile = self.e.load(os.path.join(self.e.home, ".agents", "setup-machine", "profile.json"))
        self.assertNotIn("output-style:claude", profile["disabled"])


class Requirements(unittest.TestCase):
    def test_statusline_blocked_without_profile(self):
        e = Env()
        try:
            code, out, _ = e.run("check", "--only", "statusline")
            self.assertEqual(e.status(out, "statusline"), "blocked")
        finally:
            e.cleanup()

    def test_jq_missing_blocks(self):
        e = Env(jq=False)
        try:
            e.run("profile", "--interactive", "true")
            code, out, _ = e.run("apply", "--only", "statusline")
            self.assertEqual(e.status(out, "statusline"), "blocked")
            self.assertFalse(os.path.exists(os.path.join(e.claude, "statusline-command.sh")))
        finally:
            e.cleanup()


HANDLERS = "shell-guard,artifact-guard,verify-gate,session-log"
S = SCRIPTS


def cmds(cfg, event):
    """[(entry index, handler index, matcher, command)] for one event."""
    out = []
    for i, entry in enumerate(cfg.get("hooks", {}).get(event, [])):
        for j, h in enumerate(entry.get("hooks", [])):
            out.append((i, j, entry.get("matcher"), h["command"]))
    return out


def wsl_settings(home):
    old = os.path.join(home, ".agents", "skills")
    return {"hooks": {
        "SessionStart": [{"matcher": "^(startup|resume)$", "hooks": [
            {"type": "command", "command": "bash '/x/herdr-agent-state.sh' session", "timeout": 10}]}],
        "Stop": [
            {"hooks": [{"type": "command", "command": "bash %s/session-log/scripts/stop-session-log.sh" % old,
                        "statusMessage": "Appending session log..."}]},
            {"hooks": [{"type": "command", "command": "bash %s/verify-gate/scripts/stop-verify-gate.sh claude" % old,
                        "timeout": 5, "statusMessage": "Checking for unverified claims..."}]},
        ],
        "PreToolUse": [{"matcher": "Artifact", "hooks": [
            {"type": "command", "command": "python3 %s/setup-hooks/scripts/guard-artifact.py" % old,
             "timeout": 10, "onFailure": "block"}]}],
    }}


class Handlers(unittest.TestCase):
    def setUp(self):
        self.e = Env()

    def tearDown(self):
        self.e.cleanup()

    def test_fresh_handlers_installed_once(self):
        code, out, p = self.e.run("apply", "--only", HANDLERS)
        s = self.e.load(self.e.settings)
        pre = cmds(s, "PreToolUse")
        self.assertEqual(pre, [
            (0, 0, "Bash", "python3 %s/guard-commands.py" % S),
            (0, 1, "Bash", "python3 %s/rg-replace-flag-fix.py" % S),
            (1, 0, "Artifact", "python3 %s/guard-artifact.py" % S),
        ])
        self.assertEqual([c[3] for c in cmds(s, "Stop")],
                         ["bash %s/stop-verify-gate.sh claude" % S, "bash %s/stop-session-log.sh" % S])
        artifact = s["hooks"]["PreToolUse"][1]["hooks"][0]
        self.assertEqual((artifact["timeout"], artifact["onFailure"]), (10, "block"))
        h = self.e.load(self.e.hooks_json)
        self.assertEqual(cmds(h, "PreToolUse"), [(0, 0, "Bash|exec", "python3 %s/guard-commands-codex.py" % S)])
        guard = h["hooks"]["PreToolUse"][0]["hooks"][0]
        self.assertEqual((guard["async"], guard["timeoutSec"]), (False, 5))
        self.assertEqual(cmds(h, "Stop"), [(0, 0, None, "bash %s/stop-verify-gate.sh codex" % S)])

    def test_wsl_layout_migrates_paths(self):
        self.e.write_json(self.e.settings, wsl_settings(self.e.home))
        code, out, _ = self.e.run("check", "--only", HANDLERS)
        self.assertEqual(self.e.status(out, "verify-gate"), "stale")
        self.assertEqual(self.e.status(out, "shell-guard"), "missing")
        self.e.run("apply", "--only", HANDLERS)
        s = self.e.load(self.e.settings)
        self.assertEqual(cmds(s, "SessionStart"), [(0, 0, "^(startup|resume)$", "bash '/x/herdr-agent-state.sh' session")])
        self.assertEqual(cmds(s, "Stop"), [
            (0, 0, None, "bash %s/stop-session-log.sh" % S),
            (1, 0, None, "bash %s/stop-verify-gate.sh claude" % S),
        ])
        self.assertEqual(cmds(s, "PreToolUse"), [
            (0, 0, "Artifact", "python3 %s/guard-artifact.py" % S),
            (1, 0, "Bash", "python3 %s/guard-commands.py" % S),
            (1, 1, "Bash", "python3 %s/rg-replace-flag-fix.py" % S),
        ])
        code, out, _ = self.e.run("check", "--only", HANDLERS, "--agent", "claude")
        self.assertEqual(code, 0)

    def test_mac_layout_paths_rewritten_in_place(self):
        old = os.path.join(self.e.home, ".claude", "skills", "setup-hooks", "scripts")
        self.e.write_json(self.e.settings, {"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
            {"type": "command", "command": "python3 %s/rg-replace-flag-fix.py" % old,
             "statusMessage": "Repairing rg flag clusters..."},
            {"type": "command", "command": "python3 %s/guard-commands.py" % old,
             "statusMessage": "Guarding risky shell commands..."},
        ]}]}})
        self.e.run("apply", "--only", "shell-guard", "--agent", "claude")
        self.assertEqual(cmds(self.e.load(self.e.settings), "PreToolUse"), [
            (0, 0, "Bash", "python3 %s/rg-replace-flag-fix.py" % S),
            (0, 1, "Bash", "python3 %s/guard-commands.py" % S),
        ])

    def test_legacy_and_duplicate_removed(self):
        self.e.write_json(self.e.settings, {"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
            {"type": "command", "command": "bash /old/guard-commands.sh"},
            {"type": "command", "command": "python3 /a/guard-commands.py"},
            {"type": "command", "command": "python3 /b/guard-commands.py"},
        ]}]}})
        code, out, _ = self.e.run("check", "--only", "shell-guard", "--agent", "claude")
        self.assertEqual(self.e.status(out, "shell-guard"), "stale")
        self.e.run("apply", "--only", "shell-guard", "--agent", "claude")
        self.assertEqual([c[3] for c in cmds(self.e.load(self.e.settings), "PreToolUse")], [
            "python3 %s/guard-commands.py" % S, "python3 %s/rg-replace-flag-fix.py" % S])

    def test_unrelated_codex_handler_position_kept(self):
        self.e.write_json(self.e.hooks_json, {"hooks": {
            "SessionStart": [{"hooks": [{"type": "command", "command": "bash '/x/herdr-agent-state.sh' session"}]}],
            "Stop": [{"hooks": [{"type": "command",
                                 "command": "bash /old/verify-gate/scripts/stop-verify-gate.sh codex", "timeout": 5}]}],
        }})
        self.e.run("apply", "--only", "shell-guard,verify-gate", "--agent", "codex")
        h = self.e.load(self.e.hooks_json)
        self.assertEqual(cmds(h, "SessionStart"), [(0, 0, None, "bash '/x/herdr-agent-state.sh' session")])
        self.assertEqual(cmds(h, "Stop"), [(0, 0, None, "bash %s/stop-verify-gate.sh codex" % S)])

    def test_codex_feature_enabled_on_apply(self):
        self.e.set_feature(False)
        code, out, _ = self.e.run("apply", "--only", "verify-gate", "--agent", "codex")
        self.assertEqual(read(os.path.join(self.e.bin, "codex-hooks-feature")).strip(), "true")
        self.assertEqual(self.e.status(out, "verify-gate", "codex"), "needs-review")
        self.assertEqual(code, 1)

    def test_codex_feature_enable_fails_blocks(self):
        self.e.cleanup()
        self.e = Env(feature=False, enable_works=False)
        code, out, _ = self.e.run("apply", "--only", "verify-gate", "--agent", "codex")
        self.assertEqual(self.e.status(out, "verify-gate", "codex"), "blocked")
        self.assertEqual(code, 1)

    def test_trust_key_present_is_ok(self):
        self.e.run("apply", "--only", "shell-guard,verify-gate", "--agent", "codex")
        with open(os.path.join(self.e.codex, "config.toml"), "w") as f:
            f.write('model = "x"\n\n[hooks.state]\n\n'
                    '[hooks.state."%s:pre_tool_use:0:0"]\ntrusted_hash = "sha256:aa"\n\n'
                    '[hooks.state."%s:stop:0:0"]\ntrusted_hash = "sha256:bb"\n' % (self.e.hooks_json, self.e.hooks_json))
        code, out, p = self.e.run("check", "--only", "shell-guard,verify-gate", "--agent", "codex")
        self.assertEqual(self.e.status(out, "shell-guard", "codex"), "ok")
        self.assertEqual(self.e.status(out, "verify-gate", "codex"), "ok")
        self.assertEqual(code, 0, p.stdout)

    def test_codex_absent_is_na(self):
        self.e.cleanup()
        self.e = Env(codex_dir=False, codex_cmd=False)
        code, out, p = self.e.run("apply", "--only", "verify-gate")
        self.assertEqual(self.e.status(out, "verify-gate", "codex"), "n/a")
        self.assertEqual(self.e.status(out, "verify-gate", "claude"), "ok")
        self.assertEqual(code, 0, p.stdout)
        self.assertFalse(os.path.exists(self.e.codex))

    def test_command_quotes_space_path(self):
        spaced = os.path.join(self.e.root, "my skills", "setup-machine")
        shutil.copytree(SKILL, spaced, ignore=shutil.ignore_patterns("__pycache__"))
        env = {"HOME": self.e.home, "PATH": self.e.bin}
        subprocess.run([sys.executable, os.path.join(spaced, "scripts", "sync.py"), "apply", "--only", "shell-guard",
                        "--agent", "claude"], env=env, capture_output=True)
        command = cmds(self.e.load(self.e.settings), "PreToolUse")[0][3]
        words = shlex.split(command)
        self.assertEqual(words, ["python3", os.path.join(spaced, "scripts", "guard-commands.py")])

    def test_remove_handler_only_ours(self):
        self.e.write_json(self.e.settings, wsl_settings(self.e.home))
        self.e.run("apply", "--only", HANDLERS)
        code, out, _ = self.e.run("remove", "--only", "verify-gate")
        self.assertEqual(code, 0)
        s = self.e.load(self.e.settings)
        self.assertEqual([c[3] for c in cmds(s, "Stop")], ["bash %s/stop-session-log.sh" % S])
        self.assertEqual(len(cmds(s, "SessionStart")), 1)
        self.assertEqual(cmds(self.e.load(self.e.hooks_json), "Stop"), [])


    def test_stale_trust_hash_stays_needs_review(self):
        self.e.write_json(self.e.hooks_json, {"hooks": {"Stop": [{"hooks": [
            {"type": "command", "command": "bash /old/verify-gate/scripts/stop-verify-gate.sh codex", "timeout": 5}]}]}})
        toml = os.path.join(self.e.codex, "config.toml")
        trust = '[hooks.state."%s:stop:0:0"]\ntrusted_hash = "sha256:%s"\n'
        with open(toml, "w") as f:
            f.write(trust % (self.e.hooks_json, "old"))
        code, out, _ = self.e.run("apply", "--only", "verify-gate", "--agent", "codex")
        self.assertEqual(self.e.status(out, "verify-gate", "codex"), "needs-review")
        code, out, _ = self.e.run("check", "--only", "verify-gate", "--agent", "codex")
        self.assertEqual(self.e.status(out, "verify-gate", "codex"), "needs-review")
        self.assertEqual(code, 1)
        with open(toml, "w") as f:
            f.write(trust % (self.e.hooks_json, "new"))
        code, out, _ = self.e.run("check", "--only", "verify-gate", "--agent", "codex")
        self.assertEqual(self.e.status(out, "verify-gate", "codex"), "ok")

    def test_trust_key_missing_is_needs_review(self):
        self.e.run("apply", "--only", "verify-gate", "--agent", "codex")
        code, out, _ = self.e.run("check", "--only", "verify-gate", "--agent", "codex")
        self.assertEqual(self.e.status(out, "verify-gate", "codex"), "needs-review")

    def test_blocked_component_reports_old_registration(self):
        self.e.cleanup()
        self.e = Env(jq=False)
        self.e.write_json(self.e.settings, wsl_settings(self.e.home))
        code, out, _ = self.e.run("apply", "--only", "verify-gate", "--agent", "claude")
        row = [r for r in out["results"] if r["component"] == "verify-gate"][0]
        self.assertEqual(row["status"], "blocked")
        self.assertIn("옛 경로 등록", row["detail"])

    def test_remove_one_agent_keeps_other(self):
        self.e.run("apply", "--only", "verify-gate")
        self.e.run("remove", "--only", "verify-gate", "--agent", "codex")
        code, out, _ = self.e.run("check", "--only", "verify-gate")
        self.assertEqual(self.e.status(out, "verify-gate", "claude"), "ok")
        self.assertEqual(self.e.status(out, "verify-gate", "codex"), "disabled")
        self.assertEqual([c[3] for c in cmds(self.e.load(self.e.settings), "Stop")],
                         ["bash %s/stop-verify-gate.sh claude" % S])


if __name__ == "__main__":
    unittest.main()
