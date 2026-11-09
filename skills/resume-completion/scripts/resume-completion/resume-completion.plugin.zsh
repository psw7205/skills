# resume-completion: session picker for `claude --resume <Tab>` and `codex resume <Tab>`.
# Works as an oh-my-zsh custom plugin or sourced from any zshrc before compinit.

0=${(%):-%N}
typeset -g RESUME_COMPLETION_DIR=${0:A:h}
(( ${fpath[(Ie)$RESUME_COMPLETION_DIR]} )) || fpath=($RESUME_COMPLETION_DIR $fpath)

# Group headers are how fzf-tab separates current-dir sessions from other projects.
zstyle ':completion:*:(claude|codex)-session:descriptions' format '[%d]'
# fzf-tab sorts candidates alphabetically unless told not to; keep newest first.
zstyle ':completion:*:(claude|codex)-session' sort false

# fzf-tab keys styles on the context of the last compadd call. Under codex's upstream
# _arguments that is the subcommand context, not ours, so match both.
() {
  local claude_ctx=':fzf-tab:complete:*:claude-session'
  local codex_ctx=':fzf-tab:complete:(*:codex-session|codex-command-(resume|fork)*|codex-exec-command-resume*)'
  zstyle $claude_ctx fzf-preview "$RESUME_COMPLETION_DIR/resume-preview claude \$word"
  zstyle $codex_ctx fzf-preview "$RESUME_COMPLETION_DIR/resume-preview codex \$word"
  local ctx
  for ctx in $claude_ctx $codex_ctx; do
    zstyle $ctx query-string input first
    zstyle $ctx fzf-flags --preview-window=right,50%,wrap
    zstyle $ctx switch-group '<' '>'
  done
}
