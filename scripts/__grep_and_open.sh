#!/usr/bin/env zsh

gif() {
  for cmd in rg fzf bat tmux nvim; do
    if ! command -v $cmd &> /dev/null; then
      return 1
    fi
  done

  if [ -z "$TMUX" ]; then
    return 1
  fi

  local selections
  selections=(${(f)"$(rg --line-number --no-heading --color=always --smart-case --hidden --glob '!.git' --glob '!node_modules' "" 2>/dev/null | \
    fzf --ansi --multi --delimiter : \
        --preview 'bat --style=numbers --color=always --highlight-line {2} {1} 2>/dev/null || echo "Preview not available"' \
        --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' \
        --bind 'change:reload:rg --line-number --no-heading --color=always --smart-case {q} 2>/dev/null || true' \
        --bind 'ctrl-c:abort' \
        --exit-0)"}) || return 0

  if (( ${#selections} == 0 )); then
    return 0
  fi

  local -a files=()
  local -a lines=()
  local count=0
  for selection in $selections; do
    local file=$(echo $selection | awk -F: '{print $1}')
    local line=$(echo $selection | awk -F: '{print $2}')
    if [[ -f "$file" ]]; then
      files+=("${file:A}")
      lines+=($line)
      ((count++))
    fi
  done

  if (( $count == 0 )); then
    return 0
  fi

  open_files_in_nvim() {
    local pane=$1
    shift
    local file_indices=("$@")
    local nvim_cmd="nvim"
    for index in "${file_indices[@]}"; do
      nvim_cmd+=" +${lines[$index]} ${files[$index]}"
    done
    tmux send-keys -t "$pane" "$nvim_cmd" C-m
  }

  if (( $count == 1 )); then
    open_files_in_nvim "$(tmux display-message -p '#P')" 1
  else
    local window_name="gif-$(date +%s)"
    tmux new-window -n "$window_name"

    case $count in
      2)
        tmux split-window -t "$window_name" -h -p 50
        open_files_in_nvim "$window_name.1" 1
        open_files_in_nvim "$window_name.2" 2
        ;;
      3)
        tmux split-window -t "$window_name" -h -p 50
        tmux split-window -t "$window_name.2" -v -p 50
        open_files_in_nvim "$window_name.1" 1
        open_files_in_nvim "$window_name.2" 2
        open_files_in_nvim "$window_name.3" 3
        ;;
      *)
        tmux split-window -t "$window_name" -h -p 50
        tmux split-window -t "$window_name.1" -v -p 50
        tmux split-window -t "$window_name.3" -v -p 50
        open_files_in_nvim "$window_name.1" 1
        open_files_in_nvim "$window_name.2" 2
        open_files_in_nvim "$window_name.3" 3
        local -a remaining_indices
        for i in {4..$count}; do
          remaining_indices+=($i)
        done
        open_files_in_nvim "$window_name.4" $remaining_indices
        ;;
    esac

    tmux select-layout -t "$window_name" tiled
  fi
}

