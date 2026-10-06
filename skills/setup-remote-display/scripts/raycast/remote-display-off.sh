#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Remote Display → Off
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💻
# @raycast.packageName Remote Display

# Documentation:
# @raycast.description 미러를 풀고 가상 화면을 끈다

if output="$("$HOME/.local/bin/remote-display" off 2>&1)"; then
    echo "원격 디스플레이 꺼짐"
else
    echo "실패 — ${output%%$'\n'*}"
    exit 1
fi
