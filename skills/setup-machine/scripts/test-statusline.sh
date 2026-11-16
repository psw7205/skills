#!/usr/bin/env bash
set -u
script="$(cd "$(dirname "$0")" && pwd)/statusline-command.sh"
pass=0 fail=0

check() {
  if [ "$1" = 0 ]; then pass=$((pass + 1)); echo "ok   $2"; else fail=$((fail + 1)); echo "FAIL $2"; fi
}

out=$(printf '%s' '{"cwd":"/tmp","rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1794807327}}}' | sh "$script")
code=$?
check "$code" "epoch reset exits 0"
printf '%s' "$out" | grep -Eq '→[0-9]{2}:[0-9]{2}'
check $? "epoch reset shows →HH:MM"

printf '%s' '{"cwd":"/tmp","rate_limits":{"five_hour":{"used_percentage":12,"resets_at":"2026-11-16T05:00:00Z"}}}' | sh "$script" >/dev/null
check $? "ISO reset exits 0"

printf '%s' '{"cwd":"/tmp"}' | sh "$script" >/dev/null
check $? "minimal input exits 0"

repo=$(mktemp -d)
git -C "$repo" init -q && git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$repo" tag v1.2.3 && git -C "$repo" checkout -q --detach v1.2.3
printf '{"cwd":"%s"}' "$repo" | sh "$script" | grep -q 'v1.2.3'
check $? "detached HEAD shows tag"
rm -rf "$repo"

echo "passed=$pass failed=$fail"
[ "$fail" = 0 ]
