#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

# Function to list tmux windows from the current session and all sessions
function list_windows() {
	local current_session
	current_session=$(tmux display-message -p "#S")
	local local_windows
	local_windows=$(tmux list-windows -F '#{session_name}:#{window_index}:#{window_name}')
	local all_windows
	all_windows=$(tmux list-windows -a -F '#{session_name}:#{window_index}:#{window_name}' | grep -v "^$current_session")
	echo -e "$local_windows\n$all_windows" | sort -u
}

# Function to select a window via fzf
function select_window() {
	# Define the preview command: uses positional parameters {1} and {2} to get session and window index,
	# clears the screen, finds the active pane, then pipes the last 50 lines through ccze -A for color.
	local preview_cmd='bash -c "
clear
session_name=\$1
window_index=\$2
pane_id=\$(tmux list-panes -t \"\${session_name}:\${window_index}\" -F \"#{pane_active} #{pane_id}\" | grep \"^1\" | cut -d\" \" -f2)
echo \"=== Content Preview ===\"
if [ -n \"\$pane_id\" ]; then
  tmux capture-pane -p -t \"\$pane_id\" -S -50 | ccze -A
else
  echo \"No active pane found.\"
fi
" -- {1} {2}'

	# Run fzf:
	# --exit-0 causes fzf to exit immediately when a selection is made.
	# The binding sends a Ctrl-C key (C-c) to fzf after executing the tmux switch.
	local selected
	selected=$(list_windows | fzf \
		--reverse \
		--height=65 \
		--inline-info \
		--prompt='❯ ' \
		--delimiter=':' \
		--exit-0 \
		--preview "$preview_cmd" \
		--preview-window=right:60%:wrap \
		--bind "enter:execute-silent(tmux switch-client -t {1}:{2})+abort")

	# In case the binding didn't trigger, fallback:
	if [ -n "$selected" ]; then
		local target
		target=$(echo "$selected" | cut -d: -f1,2)
		tmux switch-client -t "$target"
	fi
}

select_window
