# Fuzzy-complete text from the current tmux pane's scrollback.
# Candidate generation is kept outside ZLE so it can be tested and reused.
typeset -g PANE_TEXT_CANDIDATES="${PANE_TEXT_CANDIDATES:-$HOME/dev/dotfiles/scripts/__pane_text_candidates.py}"

fzf-pane-word() {
  emulate -L zsh
  [[ -n "$TMUX" ]] || { zle redisplay; return }

  local prefix=${LBUFFER##* }
  local selection kind text
  selection=$( {
      fc -ln 1 2>/dev/null | tail -n 10000
      tmux capture-pane -p -J -S -10000
    } | python3 "$PANE_TEXT_CANDIDATES" \
    | fzf --delimiter=$'\t' --with-nth=2 \
        --no-sort --exact +i --height 40% --reverse \
        --query "$prefix" --prompt 'text> ' \
        --header 'pane + history · words · phrases · lines · quotes/brackets') \
    || { zle redisplay; return }

  IFS=$'\t' read -r kind text <<< "$selection"
  [[ -n "$kind" && -n "$text" ]] || { zle redisplay; return }
  LBUFFER="${LBUFFER%$prefix}$text"
  zle reset-prompt
}

zle -N fzf-pane-word
bindkey '^Xw' fzf-pane-word
