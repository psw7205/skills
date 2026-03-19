#!/usr/bin/env bash
# video-subtitle-dl: 영상 URL에서 자막을 우선순위대로 다운로드한다.
# Usage: fetch-subs.sh <url> [extra-opts...]
#   url:        영상 URL
#   extra-opts: yt-dlp 추가 옵션 (예: --cookies-from-browser chrome)
#
# 우선순위: ko 수동 > ko 자동 > en 수동 > en 자동
# 출력: 다운로드된 파일 경로 또는 에러 메시지

set -euo pipefail

URL="${1:?Usage: fetch-subs.sh <url> [extra-opts...]}"
shift
# macOS 기본 bash(3.2)에서 빈 배열 + set -u 조합 시 unbound variable 에러 방지
EXTRA_OPTS=()
if [[ $# -gt 0 ]]; then
  EXTRA_OPTS=("$@")
fi
BASE_OPTS=(--skip-download -o "%(title)s")

# yt-dlp 존재 확인
if ! command -v yt-dlp &>/dev/null; then
  echo "ERROR: yt-dlp가 설치되어 있지 않습니다. brew install yt-dlp 또는 pip install yt-dlp" >&2
  exit 1
fi

# 자막 목록 조회
SUB_LIST=$(yt-dlp --list-subs --skip-download "$URL" ${EXTRA_OPTS[@]+"${EXTRA_OPTS[@]}"} 2>&1)

has_sub() {
  local section="$1" lang="$2"
  echo "$SUB_LIST" | awk "/$section/,/^$/" | grep -q "^$lang " 2>/dev/null
}

download_sub() {
  local mode="$1" lang="$2" convert="${3:-}"
  local args=("${BASE_OPTS[@]}" "$mode" --sub-langs "$lang" --sub-format "vtt/srt/best")
  [[ -n "$convert" ]] && args+=(--convert-subs "$convert")
  args+=(${EXTRA_OPTS[@]+"${EXTRA_OPTS[@]}"} "$URL")

  echo "DOWNLOADING: $mode $lang ${convert:+(→ $convert)}" >&2
  yt-dlp "${args[@]}"
}

# 우선순위 실행
if has_sub "Available subtitles" "ko"; then
  download_sub "--write-subs" "ko" "srt"
  echo "RESULT: ko_manual"
elif has_sub "Available automatic captions" "ko"; then
  download_sub "--write-auto-subs" "ko" "srt"
  echo "RESULT: ko_auto"
elif has_sub "Available subtitles" "en"; then
  download_sub "--write-subs" "en"
  echo "RESULT: en_manual_needs_translation"
elif has_sub "Available automatic captions" "en"; then
  download_sub "--write-auto-subs" "en"
  echo "RESULT: en_auto_needs_translation"
else
  echo "NO_SUBS: 사용 가능한 자막(ko/en)이 없습니다." >&2
  echo "RESULT: none"
  exit 0
fi

# 다운로드된 파일 목록
ls -1t *.srt *.vtt 2>/dev/null | head -5
