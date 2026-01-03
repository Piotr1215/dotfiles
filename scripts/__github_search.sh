#!/usr/bin/env bash
set -eo pipefail

# GitHub repo search - prompts for query, shows results, clones/opens in tmux session

# Prompt for search query
echo -n "Search GitHub repos: "
read -r query
[[ -z "$query" ]] && exit 0

# Search and display with fzf
selected=$(gh search repos "$query" --limit 50 --json fullName,description \
  | jq -r '.[] | "\(.fullName)\t\(.description // "")"' \
  | awk -F'\t' '
      { name[NR]=$1; desc[NR]=$2; if(length($1)>max) max=length($1) }
      END { for(i=1;i<=NR;i++) printf "%-*s  %s\n", max, name[i], desc[i] }
    ' \
  | fzf --layout=reverse --border --height=80% \
        --preview 'gh repo view {1} | bat --color=always --style=plain --language=md' \
        --preview-window=right:60%:wrap \
  | awk '{print $1}')

[[ -z "$selected" ]] && exit 0

repo_name="${selected##*/}"
target_dir="$HOME/dev/$repo_name"

if [[ -d "$target_dir" ]]; then
  echo "Already exists: $target_dir"
else
  gh repo clone "$selected" "$target_dir"
fi

# Create/switch to tmux session for this repo
session_name=$(echo "$repo_name" | tr ' .:' '_')
if [[ -d "$target_dir/.git" ]]; then
  session_name+="_$(git -C "$target_dir" symbolic-ref --short HEAD 2>/dev/null)"
fi

if ! tmux has-session -t "$session_name" 2>/dev/null; then
  tmux new-session -d -s "$session_name" -c "$target_dir"
fi

tmux switch-client -t "$session_name"
