#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat >&2 <<'EOF'
usage: mirror.sh [options] SRC DEST
  SRC, DEST       local path or host:path (at most one side remote)
  --exclude-from F  rsync exclude file (default: references/excludes-base.txt)
  --parallel N      concurrent rsync workers (default 4)
  --split "a b"     top-level dirs expanded into child units
  --to-linux        target filesystem is Linux/WSL: NFD->NFC names, no owner/group; needs rsync 3.x
  --delete          remove files on DEST that are gone from SRC
  --rsync PATH      rsync binary (default: /usr/bin/rsync, or Homebrew rsync 3.x with --to-linux)
  --log-dir D       per-unit logs (default: a new temp dir)
  --dry-run         pass -n to rsync
EOF
  exit 2
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXFILE="$HERE/../references/excludes-base.txt"
PARALLEL=4 SPLIT="" TO_LINUX=0 DELETE=0 DRY=0 RSYNC="" LOGDIR=""
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --exclude-from) EXFILE="$2"; shift 2 ;;
    --parallel) PARALLEL="$2"; shift 2 ;;
    --split) SPLIT="$2"; shift 2 ;;
    --to-linux) TO_LINUX=1; shift ;;
    --delete) DELETE=1; shift ;;
    --rsync) RSYNC="$2"; shift 2 ;;
    --log-dir) LOGDIR="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) POS+=("$1"); shift ;;
  esac
done
[ ${#POS[@]} -eq 2 ] || usage
SRC="${POS[0]%/}" DEST="${POS[1]%/}"
[ -f "$EXFILE" ] || { echo "exclude file not found: $EXFILE" >&2; exit 2; }

is_remote() { case "$1" in /*|./*|../*|~*) return 1 ;; *:*) return 0 ;; *) return 1 ;; esac; }
host_of() { printf '%s' "${1%%:*}"; }
path_of() { printf '%s' "${1#*:}"; }
if is_remote "$SRC" && is_remote "$DEST"; then echo "only one side may be remote" >&2; exit 2; fi

# /usr/bin/rsync on macOS is openrsync: no --iconv, no --info. A linked Homebrew
# rsync shadows it on PATH and breaks Xcode's IPA export, so 3.x is called by
# absolute path instead of relying on PATH order.
if [ -z "$RSYNC" ]; then
  if [ "$TO_LINUX" = 1 ]; then
    for c in /opt/homebrew/opt/rsync/bin/rsync /usr/local/opt/rsync/bin/rsync; do
      [ -x "$c" ] && RSYNC="$c" && break
    done
    [ -n "$RSYNC" ] || { echo "--to-linux needs rsync 3.x (brew install rsync; keep it unlinked)" >&2; exit 2; }
  else
    RSYNC="/usr/bin/rsync"
  fi
fi
if [ "$TO_LINUX" = 1 ] && "$RSYNC" --version 2>&1 | head -1 | grep -q openrsync; then
  echo "$RSYNC is openrsync; --to-linux needs rsync 3.x for --iconv" >&2; exit 2
fi

FLAGS=(-a --partial "--exclude-from=$EXFILE")
[ "$TO_LINUX" = 1 ] && FLAGS+=(-H --no-owner --no-group --iconv=utf-8-mac,utf-8)
[ "$DELETE" = 1 ] && FLAGS+=(--delete)
[ "$DRY" = 1 ] && FLAGS+=(-n)

list_dir() {
  if is_remote "$1"; then ssh "$(host_of "$1")" "cd $(printf '%q' "$(path_of "$1")") && ls -A1"
  else ls -A1 "$1"; fi
}
make_dir() {
  if is_remote "$1"; then ssh "$(host_of "$1")" "mkdir -p $(printf '%q' "$(path_of "$1")")"
  else mkdir -p "$1"; fi
}

UNITS=""
while IFS= read -r e; do
  [ "$e" = ".DS_Store" ] && continue
  split=0; for s in $SPLIT; do [ "$e" = "$s" ] && split=1; done
  if [ "$split" = 1 ]; then
    while IFS= read -r c; do
      [ "$c" = ".DS_Store" ] || UNITS+="$e/$c"$'\n'
    done < <(list_dir "$SRC/$e")
  else
    UNITS+="$e"$'\n'
  fi
done < <(list_dir "$SRC")
UNITS="$(printf '%s' "$UNITS" | sed '/^$/d')"
[ -n "$UNITS" ] || { echo "no entries under $SRC" >&2; exit 1; }

LOGDIR="${LOGDIR:-$(mktemp -d "${TMPDIR:-/tmp}/repo-mirror.XXXXXX")}"
mkdir -p "$LOGDIR"
make_dir "$DEST" || { echo "cannot create $DEST" >&2; exit 1; }
for s in $SPLIT; do printf '%s\n' "$UNITS" | grep -q "^$s/" && make_dir "$DEST/$s"; done

export RSYNC SRC DEST LOGDIR
export FLAGS_STR="$(printf '%q ' "${FLAGS[@]}")"
sync_unit() {
  local rel="$1" parent start rc
  parent="$(dirname "$rel")"
  start=$(date +%s)
  eval "flags=($FLAGS_STR)"
  "$RSYNC" "${flags[@]}" "$SRC/$rel" "$DEST/${parent#.}/" > "$LOGDIR/${rel//\//_}.log" 2>&1
  rc=$?
  printf '[rc=%s] %-32s %ss\n' "$rc" "$rel" "$(( $(date +%s) - start ))"
  # 24 = source files vanished mid-transfer; normal for live trees.
  [ "$rc" = 0 ] || [ "$rc" = 24 ]
}
export -f sync_unit

count="$(printf '%s\n' "$UNITS" | wc -l | tr -d ' ')"
echo "=== $count units, $PARALLEL workers, $("$RSYNC" --version 2>&1 | head -1) ==="
echo "=== logs: $LOGDIR ==="
T0=$(date +%s)
printf '%s\n' "$UNITS" | xargs -P "$PARALLEL" -I{} bash -c 'sync_unit "$1"' _ {}
status=$?
echo "=== done in $(( $(date +%s) - T0 ))s, exit $status ==="
exit "$status"
