#!/usr/bin/env python3
"""Install this skill's Herdr app mods and their layout into the Herdr home.

check (default): report drift, exit 1 if any. apply: copy mods, clone the layout
when missing, insert each mod's block, then `herdr-app check` every mod. Stdlib only.
"""
import argparse
import filecmp
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "mods"
HOME = Path(os.environ.get("HERDR_APP_HOME") or Path.home() / ".config/herdr-app")
# Herdr's shipped layouts are rewritten on every start, so blocks go into a personal clone.
LAYOUT = {"name": "main-prompts", "clone_of": "main"}
# Each mod's block: where it goes in the clone (before `before` inside column `parent`).
BLOCKS = {
    "quick-prompts": {"parent": "work", "before": "status",
                      "node": {"id": "quick-prompts", "type": "block", "size": {"px": 34},
                               "content": {"mod": "quick-prompts"}}},
}


def mod_drift():
    out = []
    for mod in sorted(p for p in SRC.iterdir() if p.is_dir()):
        for f in sorted(p for p in mod.iterdir() if p.is_file()):
            dest = HOME / "mods" / mod.name / f.name
            if not dest.exists():
                out.append((f, dest, "missing"))
            elif not filecmp.cmp(f, dest, shallow=False):
                out.append((f, dest, "differs"))
    return out


def find(node, node_id):
    if node.get("id") == node_id:
        return node
    for child in node.get("children", []):
        hit = find(child, node_id)
        if hit:
            return hit
    return None


def layout_path():
    return HOME / "layouts" / f"{LAYOUT['name']}.json"


def missing_blocks(tree):
    return [name for name in BLOCKS if not find(tree, BLOCKS[name]["node"]["id"])]


def insert_blocks(tree):
    for name in missing_blocks(tree):
        spec = BLOCKS[name]
        parent = find(tree, spec["parent"])
        if parent is None:
            raise SystemExit(f"{layout_path()}: no node '{spec['parent']}' to hold {name}")
        ids = [c.get("id") for c in parent["children"]]
        at = ids.index(spec["before"]) if spec["before"] in ids else len(ids)
        parent["children"].insert(at, spec["node"])


def herdr(*args):
    return subprocess.run(["herdr-app", *args], capture_output=True, text=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("mode", nargs="?", choices=["check", "apply"], default="check")
    args = ap.parse_args()

    drift = mod_drift()
    for src, dest, why in drift:
        print(f"mod   {why:8} {dest}")
    lp = layout_path()
    tree = json.loads(lp.read_text()) if lp.exists() else None
    if tree is None:
        print(f"layout missing  {lp}")
    else:
        for name in missing_blocks(tree):
            print(f"layout block missing  {name} in {lp}")
    clean = not drift and tree is not None and not missing_blocks(tree)
    if args.mode == "check":
        print("in sync" if clean else "drift; run with apply")
        sys.exit(0 if clean else 1)

    for src, dest, _ in drift:
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)
    if tree is None:
        # layout.clone needs the running window and switches it to the clone.
        r = herdr("do", "layout.clone", json.dumps({"name": LAYOUT["clone_of"], "as": LAYOUT["name"]}))
        if r.returncode != 0 or not lp.exists():
            raise SystemExit(f"layout.clone failed (is Herdr running?): {(r.stdout + r.stderr).strip()}")
        tree = json.loads(lp.read_text())
    if missing_blocks(tree):
        insert_blocks(tree)
        lp.write_text(json.dumps(tree, ensure_ascii=False, indent=2) + "\n")

    failed = False
    for mod in sorted(p for p in SRC.iterdir() if p.is_dir()):
        r = herdr("check", str(HOME / "mods" / mod.name))
        print((r.stdout + r.stderr).strip())
        failed |= r.returncode != 0
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
