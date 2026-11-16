#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
failed=0
run() {
  if "$@" >/dev/null 2>&1; then echo "ok   $*"; else echo "FAIL $*"; failed=1; fi
}
run python3 test-sync.py
run python3 test-guard-rules.py
run bash test-auto-backup.sh
run python3 test-rg-replace-flag-fix.py
run python3 test-guard-artifact.py
run bash test-stop-verify-gate.sh claude
run bash test-stop-verify-gate.sh codex
run bash test-statusline.sh
exit "$failed"
