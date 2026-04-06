#!/bin/sh
input=$(cat)

# Single jq call for all values
eval "$(echo "$input" | jq -r '
  "cwd=" + (.workspace.current_dir // .cwd // "" | @sh),
  "ctx_used=" + (.context_window.used_percentage // empty | tostring | @sh),
  "rate_used=" + (.rate_limits.five_hour.used_percentage // empty | tostring | @sh),
  "rate_resets=" + (.rate_limits.five_hour.resets_at // empty | tostring | @sh),
  "lines_added=" + (.cost.total_lines_added // 0 | tostring | @sh),
  "lines_removed=" + (.cost.total_lines_removed // 0 | tostring | @sh),
  "wt_name=" + (.worktree.name // empty | @sh)
' 2>/dev/null)"

# Git branch (with detached HEAD fallback)
branch=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$branch" ] && branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" describe --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
fi

# Line 1: dirname + branch + worktree
short_cwd="${cwd##*/}"
sep="\033[0;90m|\033[0m"
line1=$(printf "\033[0;34m%s\033[0m" "$short_cwd")
[ -n "$branch" ]   && line1=$(printf "%s \033[0;35m(%s)\033[0m" "$line1" "$branch")
[ -n "$wt_name" ]  && line1=$(printf "%b \033[0;36m🌿%s\033[0m" "$line1" "$wt_name")

# Line 2: ctx + rate limit + lines changed
parts=""
if [ -n "$ctx_used" ]; then
  ctx_int=$(printf "%.0f" "$ctx_used")
  parts=$(printf "\033[0;36mctx %s%%\033[0m" "$ctx_int")
fi
if [ -n "$rate_used" ]; then
  rate_int=$(printf "%.0f" "$rate_used")
  reset_str=""
  if [ -n "$rate_resets" ]; then
    reset_str=" →$(date -r "$rate_resets" '+%H:%M')"
  fi
  [ -n "$parts" ] && parts=$(printf "%b %b " "$parts" "$sep")
  parts=$(printf "%b\033[0;33mused %s%%%s\033[0m" "$parts" "$rate_int" "$reset_str")
fi
if [ "$lines_added" -gt 0 ] 2>/dev/null || [ "$lines_removed" -gt 0 ] 2>/dev/null; then
  line_parts=""
  [ "$lines_added" -gt 0 ]   && line_parts=$(printf "\033[0;32m+%s\033[0m" "$lines_added")
  [ "$lines_removed" -gt 0 ] && line_parts=$(printf "%s \033[0;31m-%s\033[0m" "$line_parts" "$lines_removed")
  [ -n "$parts" ] && parts=$(printf "%b %b " "$parts" "$sep")
  parts=$(printf "%b%s" "$parts" "$line_parts")
fi

printf "%b\n" "$line1"
[ -n "$parts" ] && printf "%b" "$parts"
