#!/usr/bin/env zsh
# Drives an interactive zsh through zpty and checks what Tab offers and inserts.
# Usage: zsh test-resume-completion.zsh [plugin-dir]
# Env: FZF_TAB_PLUGIN overrides the fzf-tab plugin path (set to '' to skip fzf-tab tests).

emulate -L zsh
setopt extended_glob
zmodload zsh/zpty || { print -u2 'zsh/zpty module missing'; exit 1 }

plugin=${1:-${0:A:h}/resume-completion}
plugin=${plugin:A}
fzf_tab=${FZF_TAB_PLUGIN-${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fzf-tab/fzf-tab.plugin.zsh}
tmp=$(mktemp -d)
trap 'zpty -d z 2>/dev/null; rm -rf $tmp' EXIT
export RESUME_COMPLETION_CACHE_DIR=$tmp/cache
# Run the child shell where the newest Claude session lives so both groups (here / elsewhere) appear.
test_cwd=$("$plugin/resume-sessions" claude 2>/dev/null | awk -F'\t' '$3 != "" && system("test -d \"" $3 "\"") == 0 { print $3; exit }')
[[ -d $test_cwd ]] || test_cwd=$HOME

uuid='[0-9a-f](#c8)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c12)'
typeset -i pass=0 fail=0

cat > $tmp/fake-fzf <<'FZF'
#!/usr/bin/env zsh
# Stands in for fzf: records args, prints query + empty key + the first (or FAKE_PICK-matching) candidate.
emulate -L zsh
typeset -i header=0
query=''
for a in "$@"; do
  case $a in
    --header-lines=*) header=${a#*=} ;;
    --query=*) query=${a#*=} ;;
  esac
done
print -r -- "$@" >> ${FAKE_FZF_LOG:-/dev/null}
lines=( "${(@f)$(cat)}" )
print -r -- "$query"
print -r -- ""
for l in "${(@)lines[header+1,-1]}"; do
  if [[ -z $FAKE_PICK || $l == *$FAKE_PICK* ]]; then
    print -r -- "$l"
    break
  fi
done
FZF
chmod +x $tmp/fake-fzf

cat > $tmp/rc-common.zsh <<EOF2
export COLUMNS=220 LINES=60
cd $test_cwd
setopt no_beep
unsetopt auto_menu
fpath=($plugin \$fpath)
autoload -Uz compinit; compinit -u -d $tmp/zcompdump
zstyle ':completion:*' completer _complete
zstyle ':completion:*' menu no
LISTMAX=100000
source $plugin/resume-completion.plugin.zsh
CAPTURE_FILE=$tmp/capture
dump-buffer() { print -r -- "BUFFER=\$BUFFER" >> \$CAPTURE_FILE; zle kill-whole-line }
zle -N dump-buffer
bindkey '^X^D' dump-buffer
PS1='%% '
EOF2

cat > $tmp/rc-plain.zsh <<EOF2
source $tmp/rc-common.zsh
_cap_main() { _main_complete "\$@"; compstate[list]=''; compstate[insert]='' }
zle -C cap-complete complete-word _cap_main
bindkey '^I' cap-complete
compadd() {
  local -a __hits __dscr __d __x __opts
  zparseopts -a __opts P: p: d:=__d X+:=__x O: A: D: f i: S: s: I: x: r: R: W: F: M+: E: q e Q n U C J: V: a l k o:: 1 2
  (( \$#__d )) && __dscr=( "\${(@P)__d[2]}" )
  builtin compadd -A __hits -D __dscr "\$@"
  local i
  for i in {1..\$#__hits}; do
    print -r -- "\${__x[-1]}"\$'\t'"\$__hits[i]"\$'\t'"\$__dscr[i]" >> \$CAPTURE_FILE
  done
  builtin compadd "\$@"
}
EOF2

cat > $tmp/rc-fzf.zsh <<EOF2
source $tmp/rc-common.zsh
source $fzf_tab
zstyle ':fzf-tab:*' fzf-command $tmp/fake-fzf
export FAKE_FZF_LOG=$tmp/fzf.log
EOF2

start_shell() {
  zpty -d z 2>/dev/null
  zpty -b z zsh -f -i || { print -u2 'zpty spawn failed'; exit 1 }
  zpty -w z "source $1"
  wait_for 'READY_OK' 'print -r -- READY_O""K'
}

wait_for() {
  local mark=$1 cmd=$2 buf='' chunk
  local -i i
  [[ -n $cmd ]] && zpty -w z "$cmd"
  for i in {1..600}; do
    while zpty -rt z chunk 2>/dev/null; do buf+=$chunk; print -rn -- $chunk >> $tmp/pty.log; done
    [[ $buf == *$mark* ]] && return 0
    sleep 0.05
  done
  print -u2 -- "timeout waiting for $mark"
  return 1
}

# Wait until the child has produced no output for a while (completion finished redrawing).
wait_quiet() {
  local chunk
  local -i quiet=0 i
  for i in {1..400}; do
    if zpty -rt z chunk 2>/dev/null; then
      print -rn -- $chunk >> $tmp/pty.log
      quiet=0
    else
      (( ++quiet >= 8 )) && return 0
    fi
    sleep 0.05
  done
  return 1
}

# run_case name "typed text" "key" → fills $tmp/capture (compadd lines and/or BUFFER=)
# Never sends Enter while the line may hold a command: the dump widget writes the
# buffer to a file and clears the line, and we poll that file instead of the pty.
run_case() {
  local name=$1 typed=$2 key=$3
  local -i i
  : > $tmp/capture
  : > $tmp/pty.log
  zpty -wn z "$typed"
  zpty -wn z "$key"
  wait_quiet
  zpty -wn z $'\x18\x04'
  for i in {1..200}; do
    [[ $(<$tmp/capture) == *BUFFER=* ]] && break
    sleep 0.05
  done
  zpty -wn z $'\x15'
  wait_quiet
  [[ $(<$tmp/capture) == *BUFFER=* ]] || { print -u2 -- "dump-buffer did not run for $name"; return 1 }
}

check() {
  local name=$1 cond=$2
  if eval "$cond"; then
    (( pass++ )); print -r -- "PASS  $name"
  else
    (( fail++ )); print -r -- "FAIL  $name"
    sed 's/^/      /' $tmp/capture | head -8
    print -r -- "      pty: ${${$(<$tmp/pty.log)//[[:cntrl:]]/ }[-300,-1]}"
  fi
}

hits_match() { [[ -n ${(M)${(f)"$(<$tmp/capture)"}:#*$'\t'${~1}$'\t'*} ]] }
capture_has() { [[ $(<$tmp/capture) == *${~1}* ]] }
buffer_line() { print -r -- ${(M)${(f)"$(<$tmp/capture)"}:#BUFFER=*} }

print "== plain compsys =="
start_shell $tmp/rc-plain.zsh || exit 1

run_case c1 'claude --resume ' $'\t'
check 'claude --resume <Tab> offers session ids' 'hits_match $uuid'
check 'claude --resume <Tab> groups by Claude sessions' 'capture_has "Claude sessions · "'
check 'claude --resume <Tab> display carries title and short id' '[[ -n ${(M)${(f)"$(<$tmp/capture)"}:#*$'"'"'\t'"'"'* · [0-9a-f](#c8)} ]]'

zpty -w z "alias claude='claude --dangerously-skip-permissions'"
wait_for ALIAS_OK 'print -r -- ALIAS_O""K'
run_case c2 'claude --resume ' $'\t'
check 'aliased claude --resume <Tab> still offers sessions' 'hits_match $uuid'

run_case c3 'claude --' $'\t'
check 'claude --<Tab> lists --resume and --continue from --help' 'hits_match "--resume" && hits_match "--continue"'

run_case c5 'codex resume ' $'\t'
check 'codex resume <Tab> offers session ids' 'hits_match $uuid'
check 'codex resume <Tab> groups by Codex sessions' 'capture_has "Codex sessions · "'

run_case c6 'codex ' $'\t'
check 'codex <Tab> keeps upstream subcommands' 'hits_match resume && hits_match exec'

run_case c7 'codex resume --' $'\t'
check 'codex resume --<Tab> keeps upstream options' 'hits_match "--last"'

run_case c8 'codex fork ' $'\t'
check 'codex fork <Tab> offers session ids' 'hits_match $uuid'

if [[ -n $fzf_tab && -r $fzf_tab ]]; then
  print "== fzf-tab with fake fzf =="
  start_shell $tmp/rc-fzf.zsh || exit 1

  run_case f1 'claude --resume ' $'\t'
  check 'fzf-tab: picking a candidate inserts the id' '[[ $(buffer_line) == BUFFER=claude\ --resume\ ${~uuid}* ]]'
  check 'fzf-tab: fzf received group headers' '[[ $(<$tmp/fzf.log) == *--header-lines=[1-9]* ]]'

  : > $tmp/fzf.log
  run_case f2 'claude --resume zz' $'\t'
  check 'fzf-tab: typed text becomes the fzf query' '[[ $(<$tmp/fzf.log) == *--query=zz* ]]'
  check 'fzf-tab: typed text is replaced by the picked id' '[[ $(buffer_line) == BUFFER=claude\ --resume\ ${~uuid}* && $(buffer_line) != *zz* ]]'

  run_case f3 'codex resume ' $'\t'
  check 'fzf-tab: codex resume pick inserts the id' '[[ $(buffer_line) == BUFFER=codex\ resume\ ${~uuid}* ]]'
else
  print "== fzf-tab plugin not found; skipping fzf-tab tests =="
fi

print
print "passed=$pass failed=$fail"
(( fail == 0 ))
