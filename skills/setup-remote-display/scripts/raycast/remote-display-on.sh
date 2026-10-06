#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Remote Display → On
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🖥️
# @raycast.packageName Remote Display

# Documentation:
# @raycast.description VNC용 가상 화면을 켜고 물리 디스플레이를 미러로 묶는다

if output="$("$HOME/.local/bin/remote-display" on 2>&1)"; then
    echo "원격 디스플레이 켜짐"
else
    echo "실패 — ${output%%$'\n'*}"
    exit 1
fi
