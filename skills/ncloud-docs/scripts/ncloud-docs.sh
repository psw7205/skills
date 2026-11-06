#!/usr/bin/env bash
# NCP(ncloud) 공식 문서를 llms.txt 인덱스와 원문 .md로 받는다.
#   search <regex> [-H host]            인덱스에서 제목·slug 검색
#   get <slug|url|/docs/link>... [-H host]  원문 .md 저장, 경로와 heading 출력
#   pull <slug-regex> [-H host] [--max N]  slug가 맞는 문서 전부 저장(부재 판정용)
# host: guide(기본) api guide-gov api-gov guide-fin api-fin
set -euo pipefail

# guide.ncloud-docs.com WAF는 UA `curl/*`·`Mozilla/5.0`·`Claude-User`를 403으로 막는다(2026-11 실측).
UA="${NCLOUD_DOCS_UA:-ncloud-docs-skill/1.0}"
CACHE="${NCLOUD_DOCS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/ncloud-docs}"
HOSTS="guide api guide-gov api-gov guide-fin api-fin"

die() { echo "ERROR: $1" >&2; exit "${2:-1}"; }

usage() {
  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

check_host() {
  case " $HOSTS " in *" $1 "*) ;; *) die "unknown host '$1' (one of: $HOSTS)" 2 ;; esac
}

index() {
  local host=$1 f="$CACHE/$1/llms.txt"
  mkdir -p "$CACHE/$host"
  if [ ! -s "$f" ] || [ -z "$(find "$f" -mmin -1440 2>/dev/null)" ]; then
    curl -fsS -A "$UA" -o "$f.tmp" "https://$host.ncloud-docs.com/llms.txt" \
      || die "llms.txt fetch failed for $host"
    mv "$f.tmp" "$f"
  fi
  echo "$f"
}

# "- [Title](https://host.ncloud-docs.com/docs/slug.md)" -> "slug<TAB>Title"
entries() {
  sed -n 's#^- \[\(.*\)\](https://[^/]*/docs/\([^)]*\)\.md)$#\2	\1#p' "$(index "$1")"
}

fetch() {
  local host=$1 slug=$2 out="$CACHE/$1/$2.md" code
  code=$(curl -sS -A "$UA" -o "$out.tmp" -w '%{http_code}' "https://$host.ncloud-docs.com/docs/$slug.md") || code=000
  if [ "$code" = 200 ] && ! head -c 200 "$out.tmp" | grep -qi '<!doctype\|<html'; then
    mv "$out.tmp" "$out"
    echo "$out"
    return 0
  fi
  rm -f "$out.tmp"
  case $code in
    403) echo "BLOCKED 403 $host/$slug — WAF가 UA를 막았다. NCLOUD_DOCS_UA를 바꾸거나 agent-browser로 연다" >&2; return 3 ;;
    404) echo "NOTFOUND 404 $host/$slug — slug를 search로 확인한다" >&2; return 4 ;;
    *) echo "FAILED $code $host/$slug" >&2; return 1 ;;
  esac
}

# URL 또는 slug -> "host slug". 인덱스에 없으면 대소문자 무시 일치로 보정한다.
resolve() {
  local arg=$1 host=$2 slug exact ci
  case $arg in
    http*://*)
      host=$(printf '%s' "$arg" | sed -E 's#^https?://([a-z-]+)\.ncloud-docs\.com/.*#\1#')
      [ "$host" != "$arg" ] || die "not an ncloud-docs URL: $arg" 2
      arg=$(printf '%s' "$arg" | sed -E 's#^https?://[^/]+##')
      ;;
  esac
  slug=$(printf '%s' "$arg" | sed -E 's#^/?docs/(en/|ja/)?##; s#[?#].*##; s#\.md$##')
  check_host "$host"
  exact=$(entries "$host" | cut -f1 | grep -Fx -- "$slug" || true)
  if [ -z "$exact" ]; then
    ci=$(entries "$host" | cut -f1 | grep -Fxi -- "$slug" | head -1 || true)
    if [ -n "$ci" ]; then
      echo "NOTE: $slug -> $ci (slug는 대소문자를 구분한다)" >&2
      slug=$ci
    else
      echo "NOTE: $host 인덱스에 '$slug' 없음 — 그대로 요청한다" >&2
    fi
  fi
  echo "$host $slug"
}

outline() {
  local f=$1
  printf '%s  (%s lines)\n' "$f" "$(wc -l < "$f" | tr -d ' ')"
  grep -E '^#{1,3} ' "$f" | grep -v '^> ' | head -40 | sed 's/^/    /'
}

cmd=${1:-}; [ -n "$cmd" ] || usage; shift
host=guide max=60 args=()
while [ $# -gt 0 ]; do
  case $1 in
    -H|--host) host=${2:?}; shift 2 ;;
    --max) max=${2:?}; shift 2 ;;
    -h|--help) usage ;;
    *) args+=("$1"); shift ;;
  esac
done
check_host "$host"
[ ${#args[@]} -gt 0 ] || usage

case $cmd in
  search)
    entries "$host" | grep -Ei -- "${args[0]}" | awk -F'\t' -v h="$host" '{printf "%s  %s  %s\n", h, $1, $2}' || {
      echo "no match in $host index ($(index "$host"))" >&2; exit 1; }
    ;;
  get)
    rc=0
    for a in "${args[@]}"; do
      r=$(resolve "$a" "$host") || exit $?
      read -r h s <<<"$r"
      if f=$(fetch "$h" "$s"); then outline "$f"; else rc=$?; fi
    done
    exit $rc
    ;;
  pull)
    slugs=$(entries "$host" | cut -f1 | grep -E -- "${args[0]}" || true)
    n=$(printf '%s' "$slugs" | grep -c . || true)
    [ "$n" -gt 0 ] || die "no slug matches '${args[0]}' in $host"
    [ "$n" -le "$max" ] || die "$n slugs match — 패턴을 좁히거나 --max $n" 2
    ok=0 fail=0
    for s in $slugs; do
      if fetch "$host" "$s" >/dev/null; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
    done
    echo "pulled $ok/$n ($fail failed) into $CACHE/$host"
    printf '%s\n' "$slugs" | sed "s#^#$CACHE/$host/#; s#\$#.md#" > "$CACHE/$host/.last-pull"
    echo "file list: $CACHE/$host/.last-pull"
    [ "$fail" -eq 0 ] || exit 1
    ;;
  *) usage ;;
esac
