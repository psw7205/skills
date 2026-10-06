#!/usr/bin/env bash
# Read-only size survey of the usual macOS developer-machine space sinks. Deletes nothing.
#   bash survey.sh [repo-root ...]
set -uo pipefail

L="$HOME/Library"
row() { [ -e "$2" ] && printf '%8s  %-28s %s\n' "$(du -sh "$2" 2>/dev/null | cut -f1)" "$1" "$2"; }

echo "== volume"
df -h /System/Volumes/Data 2>/dev/null | tail -1 || df -h / | tail -1

echo; echo "== Xcode / simulators"
row "DerivedData"            "$L/Developer/Xcode/DerivedData"
row "Archives"               "$L/Developer/Xcode/Archives"
row "iOS DeviceSupport"      "$L/Developer/Xcode/iOS DeviceSupport"
row "simulator devices"      "$L/Developer/CoreSimulator/Devices"
row "simulator dyld cache"   "/Library/Developer/CoreSimulator/Caches/dyld"
for app in /Applications/Xcode*.app; do row "Xcode app" "$app"; done
if command -v xcrun >/dev/null 2>&1; then
  echo "  simulator runtimes (real on-disk size; du on CoreSimulator/Volumes over-counts mounts):"
  xcrun simctl runtime list 2>/dev/null | sed 's/^/    /'
fi

echo; echo "== Android"
row "AVDs"                   "$HOME/.android/avd"
row "system-images"          "$L/Android/sdk/system-images"
row "NDK"                    "$L/Android/sdk/ndk"
row "Gradle caches"          "$HOME/.gradle/caches"

echo; echo "== containers"
find "$HOME/.colima" "$HOME/.lima" -maxdepth 4 -type f \( -name datadisk -o -name diffdisk \) 2>/dev/null \
  | while IFS= read -r f; do
      printf '%8s  %-28s %s (apparent %s)\n' "$(du -sh "$f" | cut -f1)" "VM disk (sparse)" "$f" "$(ls -lh "$f" | awk '{print $5}')"
    done
row "OrbStack data"          "$HOME/.orbstack"
row "Docker Desktop data"    "$L/Containers/com.docker.docker"
command -v docker >/dev/null 2>&1 && docker system df 2>/dev/null | sed 's/^/  /'

echo; echo "== toolchains and caches"
row "mise installs"          "$HOME/.local/share/mise/installs"
row "Homebrew cache"         "$L/Caches/Homebrew"
row "CocoaPods cache"        "$L/Caches/CocoaPods"
row "CocoaPods spec repos"   "$HOME/.cocoapods/repos"
row "yarn berry cache"       "$HOME/.yarn/berry/cache"
row "pnpm store"             "$L/pnpm/store"
row "npm cache"              "$HOME/.npm/_cacache"
row "uv cache"               "$HOME/.cache/uv"
row "~/.cache"               "$HOME/.cache"
for d in "$L"/Caches/JetBrains/*/; do [ -d "$d" ] && row "JetBrains cache" "${d%/}"; done
echo "  largest ~/Library/Caches entries:"
du -sh "$L"/Caches/* 2>/dev/null | sort -rh | head -8 | sed 's/^/    /'
echo "  largest ~/Library/Application Support entries:"
du -sh "$L/Application Support"/* 2>/dev/null | sort -rh | head -8 | sed 's/^/    /'

for root in "$@"; do
  echo; echo "== regenerable dirs under $root (top 15)"
  find "$root" -type d \( -name node_modules -o -name .turbo -o -name .next -o -name Pods \
      -o -name .venv -o -name venv -o -name .gradle -o -name DerivedData \) -prune -print 2>/dev/null \
    | while IFS= read -r d; do du -sk "$d" 2>/dev/null; done | sort -rn | head -15 \
    | awk '{ printf "%7.1fG  %s\n", $1/1048576, $2 }'
  echo "  .git directories (top 5):"
  find "$root" -type d -name .git -prune 2>/dev/null | while IFS= read -r d; do du -sk "$d" 2>/dev/null; done \
    | sort -rn | head -5 | awk '{ printf "    %7.1fG  %s\n", $1/1048576, $2 }'
done
