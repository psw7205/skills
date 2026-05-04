#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install-codex-hook.sh [install|remove]

Registers or removes the Codex guard hook in:
  ${CODEX_HOME:-$HOME/.codex}/hooks.json

Environment:
  CODEX_HOME                 Override Codex home directory.
  CODEX_HOOKS_FILE           Override hooks.json path.
  SETUP_HOOKS_CODEX_SCRIPT   Override guard-untracked-codex.sh path.
USAGE
}

ACTION="${1:-install}"
case "$ACTION" in
  install|remove)
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    usage >&2
    exit 2
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to edit Codex hooks.json" >&2
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HOOK_SCRIPT="${SETUP_HOOKS_CODEX_SCRIPT:-$SCRIPT_DIR/guard-untracked-codex.sh}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
HOOKS_FILE="${CODEX_HOOKS_FILE:-$CODEX_HOME/hooks.json}"
HOOK_COMMAND="bash $HOOK_SCRIPT"

if [ "$ACTION" = "install" ] && [ ! -f "$HOOK_SCRIPT" ]; then
  echo "Codex hook script not found: $HOOK_SCRIPT" >&2
  exit 1
fi

mkdir -p "$(dirname "$HOOKS_FILE")"

SOURCE_JSON=$(mktemp)
UPDATED_JSON=$(mktemp)
cleanup() {
  rm -f "$SOURCE_JSON" "$UPDATED_JSON"
}
trap cleanup EXIT

if [ -s "$HOOKS_FILE" ]; then
  jq . "$HOOKS_FILE" >"$SOURCE_JSON"
else
  printf '{"hooks":{}}\n' >"$SOURCE_JSON"
fi

jq --arg action "$ACTION" --arg command "$HOOK_COMMAND" '
  .hooks = (.hooks // {}) |
  .hooks.PreToolUse = (
    (.hooks.PreToolUse // [])
    | map(
        .hooks = (
          (.hooks // [])
          | map(select(((.command // "") | contains("guard-untracked-codex.sh")) | not))
        )
      )
    | map(select((.hooks // []) | length > 0))
  ) |
  if $action == "install" then
    .hooks.PreToolUse += [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": $command,
            "async": false,
            "timeoutSec": 5,
            "statusMessage": "Guarding destructive git commands..."
          }
        ]
      }
    ]
  else
    .
  end
' "$SOURCE_JSON" >"$UPDATED_JSON"

umask 077
mv "$UPDATED_JSON" "$HOOKS_FILE"
trap - EXIT
rm -f "$SOURCE_JSON"

if [ "$ACTION" = "install" ]; then
  echo "Installed Codex guard hook: $HOOKS_FILE"
  echo "Hook command: $HOOK_COMMAND"
else
  echo "Removed Codex guard hook from: $HOOKS_FILE"
fi
