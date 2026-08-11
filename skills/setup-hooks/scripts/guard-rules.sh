#!/usr/bin/env bash
# Shared command classification for the PreToolUse guards.
# Sourced by guard-commands.sh (Claude Code) and guard-commands-codex.sh (Codex),
# which apply different policies (rewrite vs deny) to the same verdicts.
#
# Classification is token-positional rather than substring-based. A rule fires
# only when a pipeline segment's command word is the real program and its
# subcommand matches — so `echo 'git clean'` and `git commit -m "drop git clean"`
# are not mistaken for the commands they merely mention.

GUARD_RULE=""
GUARD_LABEL=""

_guard_segments() {
  # tr, not sed: BSD sed emits a literal 'n' for \n in the replacement.
  printf '%s' "$1" | tr '|;&' '\n\n\n'
}

# Prints the first token that is neither a `VAR=value` assignment nor a
# transparent wrapper, i.e. the segment's actual command word.
_guard_command_word() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -*) return 1 ;;
      *=*) shift ;;
      command|builtin|exec) shift ;;
      *) printf '%s' "$1"; return 0 ;;
    esac
  done
  return 1
}

# Prints git's subcommand, skipping the global options that precede it.
_guard_git_subcommand() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path) shift 2 || return 1 ;;
      -*) shift ;;
      *) printf '%s' "$1"; return 0 ;;
    esac
  done
  return 1
}

# True when the option token `-<letter>` (possibly bundled) or `--<long>` is present.
# Exact token comparison is what keeps --force-with-lease out of the --force rule.
_guard_has_flag() {
  local letter="$1" long="$2"
  shift 2
  local tok flags
  for tok in "$@"; do
    case "$tok" in
      --) return 1 ;;
      "--$long"|"--$long"=*) return 0 ;;
      --*) ;;
      -?*)
        # An empty letter means the option is long-form only.
        [ -n "$letter" ] || continue
        flags="${tok#-}"
        flags="${flags%%=*}"
        case "$flags" in *"$letter"*) return 0 ;; esac
        ;;
    esac
  done
  return 1
}

# True when every character is an rg short flag that takes no value.
# -h/-V are excluded: clustering them carries no recoverable intent.
_guard_rg_bool_only() {
  local s="$1" i=0 ch
  [ -n "$s" ] || return 1
  while [ "$i" -lt "${#s}" ]; do
    ch="${s:$i:1}"
    case "acFHIiLlNnopqSsUuvwxz" in
      *"$ch"*) ;;
      *) return 1 ;;
    esac
    i=$((i + 1))
  done
  return 0
}

# Prints the subset of "or" that rg actually receives, honouring bundled short
# flags. Scanning stops at a flag that swallows the rest of the token as its
# value, so `-er` is rg's -e with value "r", not a --replace.
_guard_rg_flags() {
  local tok flags i ch found=""
  for tok in "$@"; do
    case "$tok" in
      --) break ;;
      --only-matching|--only-matching=*) found="${found}o" ;;
      --replace|--replace=*) found="${found}r" ;;
      --*) ;;
      -?*)
        flags="${tok#-}"
        # `-rn`-style clusters are ripgrep's other trap: -r silently eats the
        # following letters as its replacement value. Reported separately as "c"
        # because it is repairable — the caller decides whether to defer to
        # rg-replace-flag-fix.py or block with a correction.
        case "$flags" in
          r?*)
            if _guard_rg_bool_only "${flags#r}"; then
              found="${found}c"
              continue
            fi
            ;;
        esac
        i=0
        while [ "$i" -lt "${#flags}" ]; do
          ch="${flags:$i:1}"
          case "$ch" in
            o) found="${found}o" ;;
            r) found="${found}r"; break ;;
            e|f|g|m|t|j|A|B|C|M) break ;;
          esac
          i=$((i + 1))
        done
        ;;
    esac
  done
  printf '%s' "$found"
}

_guard_verdict() {
  GUARD_RULE="$1"
  GUARD_LABEL="$2"
}

# Sets GUARD_RULE and GUARD_LABEL to the first matching rule, or leaves both
# empty. Deny-worthy rules are checked before recoverable ones.
guard_classify() {
  local cmd="$1" seg word sub tok restore_glob=1
  GUARD_RULE=""
  GUARD_LABEL=""
  [ -n "$cmd" ] || return 0

  case "$-" in *f*) restore_glob=0 ;; esac
  set -f

  # `|| [ -n "$seg" ]` keeps the final segment: tr emits no trailing newline,
  # so read returns non-zero on it even though it holds the whole command.
  while IFS= read -r seg || [ -n "$seg" ]; do
    [ -n "$seg" ] || continue
    # shellcheck disable=SC2086
    set -- $seg
    [ $# -gt 0 ] || continue
    word=$(_guard_command_word "$@") || continue

    while [ $# -gt 0 ] && [ "$1" != "$word" ]; do shift; done
    shift

    case "$word" in
      rg)
        case "$(_guard_rg_flags "$@")" in
          *o*) ;;
          *r*) _guard_verdict "rg-replace" "rg --replace"; break ;;
          *c*) _guard_verdict "rg-flag-cluster" "rg -r flag cluster"; break ;;
        esac
        ;;
      git)
        sub=$(_guard_git_subcommand "$@") || continue
        case "$sub" in
          push)
            _guard_has_flag f force "$@" && { _guard_verdict "force-push" "git push --force"; break; }
            ;;
          clean)
            _guard_has_flag n dry-run "$@" && continue
            _guard_has_flag i interactive "$@" && continue
            _guard_verdict "git-clean" "git clean"
            break
            ;;
          reset)
            _guard_has_flag '' hard "$@" && { _guard_verdict "git-reset-hard" "git reset --hard"; break; }
            ;;
          restore)
            if _guard_has_flag W worktree "$@" ||
               ! { _guard_has_flag S staged "$@" || _guard_has_flag '' cached "$@"; }; then
              _guard_verdict "git-restore" "git restore"
              break
            fi
            ;;
          checkout)
            if _guard_has_flag f force "$@"; then
              _guard_verdict "git-checkout-force" "git checkout --force"
              break
            fi
            for tok in "$@"; do
              if [ "$tok" = "--" ] || [ "$tok" = "." ]; then
                _guard_verdict "git-checkout-paths" "git checkout (paths)"
                break 2
              fi
            done
            ;;
        esac
        ;;
    esac
  done < <(_guard_segments "$cmd")

  [ "$restore_glob" = 1 ] && set +f
  return 0
}
