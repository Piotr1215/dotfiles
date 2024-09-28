#!/usr/bin/env zsh

gif() {
  # Check if required commands are available
  for cmd in rg fzf bat; do
    if ! command -v $cmd &> /dev/null; then
      echo "Error: $cmd is not installed or not in PATH" >&2
      return 1
    fi
  done

  local selections
  selections=(${(f)"$(rg --line-number --no-heading --color=always --smart-case "" 2>/dev/null | \
    fzf --ansi --multi --delimiter : \
        --preview 'bat --style=numbers --color=always --highlight-line {2} {1} 2>/dev/null || echo "Preview not available"' \
        --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' \
        --bind 'change:reload:rg --line-number --no-heading --color=always --smart-case {q} 2>/dev/null || true' \
        --bind 'ctrl-c:abort' \
        --exit-0)"}) || return 0

  if (( ${#selections} == 0 )); then
    echo "No files selected."
    return 0
  fi

  local files=()
  local line=""
  for selection in $selections; do
    local file=$(echo $selection | awk -F: '{print $1}')
    if [[ -f "$file" ]]; then
      files+=${file:A}
      if (( ${#selections} == 1 )); then
        line=$(echo $selection | awk -F: '{print $2}')
      fi
    else
      echo "Warning: File not found: $file" >&2
    fi
  done

  if (( ${#files} == 0 )); then
    echo "No valid files to open."
    return 0
  fi

  local editor=${EDITOR:-nvim}
  if ! command -v $editor &> /dev/null; then
    echo "Error: $editor is not installed or not in PATH" >&2
    return 1
  fi

  case ${#files} in
    1)
      if [[ -n $line ]]; then
        $editor "${files[1]}" "+${line}"
      else
        $editor "${files[1]}"
      fi
      ;;
    2)
      $editor -O +'silent! normal g;' "${files[@]}"
      ;;
    3)
      $editor -O "${files[1]}" -c 'wincmd j' -c "silent! vsplit ${files[2]}" -c "silent! split ${files[3]}"
      ;;
    4)
      $editor -O "${files[1]}" -c "silent! vsplit ${files[2]}" -c "silent! split ${files[3]}" -c 'wincmd h' -c "silent! split ${files[4]}"
      ;;
    *)
      $editor "${files[@]}"
      ;;
  esac
}
