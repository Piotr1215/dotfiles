#!/usr/bin/env zsh

get_fzf_output() {
  local RG_BIND="ctrl-g:reload:rg --line-number --no-heading --color=always --smart-case --glob '!**/.git/**' --glob '!node_modules/**' '' 2>/dev/null || true"
  local FILE_BIND="ctrl-f:reload:rg --files --glob '!**/.git/**' --glob '!node_modules/**' 2>/dev/null || true"
  if command -v fd &>/dev/null; then
    DIR_BIND="ctrl-d:change-prompt(directory> )+reload(cd $HOME && echo $HOME; fd --type d --hidden --absolute-path --color never --exclude .git --exclude node_modules)"
  else
    DIR_BIND="ctrl-d:change-prompt(directory> )+reload(cd $HOME && find ~+ -type d -name node_modules -prune -o -name .git -prune -o -type d -print)"
  fi

  rg --line-number --no-heading --color=always --smart-case --glob '!**/.git/**' --glob '!node_modules/**' '' 2>/dev/null | \
    fzf --ansi --multi --delimiter : \
        --print-query \
        --preview 'bat --style=numbers --color=always --highlight-line {2} {1} 2>/dev/null || echo "Preview not available"' \
        --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' \
        --bind "$FILE_BIND" \
        --bind "$RG_BIND" \
        --bind "$DIR_BIND" \
        --bind 'ctrl-c:abort' \
        --header "Press Ctrl+f to search filenames, Ctrl+g to search file contents, Ctrl+d to search directories"
}

set_nvim_search_variable() {
  local raw_output="$1"
  local query=$(echo "$raw_output" | head -n1)
  export NVIM_SEARCH_REGISTRY="$query"
}

gif() {
  for cmd in rg fzf bat tmux nvim; do
    if ! command -v $cmd &> /dev/null; then
      echo "Error: $cmd not found" >&2
      return 1
    fi
  done
  if [ -z "$TMUX" ]; then
    echo "Error: Not in a tmux session" >&2
    return 1
  fi

  local raw_output
  raw_output=$(get_fzf_output)
  echo "DEBUG: Raw fzf output:" >&2
  echo "$raw_output" >&2
  set_nvim_search_variable "$raw_output"

  # Split the newline-delimited output into an array, skipping the first line (query)
  local -a selections
  selections=("${(@f)$(echo "$raw_output" | sed 1d)}")

  echo "DEBUG: Number of selections: ${#selections[@]}" >&2
  echo "DEBUG: Selections:" >&2
  printf '%s\n' "${selections[@]}" >&2
  if (( ${#selections[@]} == 0 )); then
    echo "DEBUG: No selections made" >&2
    return 0
  fi
  local -a files=()
  local -a lines=()
  local count=0
  for selection in "${selections[@]}"; do
    local file=$(echo $selection | awk -F: '{print $1}')
    local line=$(echo $selection | awk -F: '{print $2}')
    echo "DEBUG: Processing selection: $selection" >&2
    echo "DEBUG: File: $file, Line: $line" >&2
    if [[ -f "$file" ]]; then
      files+=("${file:A}")
      lines+=($line)
      ((count++))
    else
      echo "DEBUG: File not found: $file" >&2
    fi
  done
  echo "DEBUG: Number of valid files: $count" >&2
  echo "DEBUG: Valid files:" >&2
  printf '%s\n' "${files[@]}" >&2
  if (( $count == 0 )); then
    echo "DEBUG: No valid files selected" >&2
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
    nvim_cmd+=" -c 'let @/=\"$NVIM_SEARCH_REGISTRY\"'"
    echo "DEBUG: Running command in pane $pane: $nvim_cmd" >&2
    tmux send-keys -t "$pane" "$nvim_cmd" C-m
  }
  if (( $count == 1 )); then
    echo "DEBUG: Opening single file" >&2
    open_files_in_nvim "$(tmux display-message -p '#P')" 1
  else
    echo "DEBUG: Opening multiple files" >&2
    local window_name="gif-$(date +%s)"
    tmux new-window -n "$window_name"
    case $count in
      2)
        echo "DEBUG: Opening 2 files" >&2
        tmux split-window -t "$window_name" -h -p 50
        open_files_in_nvim "$window_name.1" 1
        open_files_in_nvim "$window_name.2" 2
        ;;
      3)
        echo "DEBUG: Opening 3 files" >&2
        tmux split-window -t "$window_name" -h -p 50
        tmux split-window -t "$window_name.2" -v -p 50
        open_files_in_nvim "$window_name.1" 1
        open_files_in_nvim "$window_name.2" 2
        open_files_in_nvim "$window_name.3" 3
        ;;
      *)
        echo "DEBUG: Opening 4 or more files" >&2
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
    tmux select-layout -t "$window_name" even-horizontal
  fi
  echo "DEBUG: Function completed" >&2
}
