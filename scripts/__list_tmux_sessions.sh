#!/usr/bin/env bash

set -eo pipefail

# Set new line and tab for word splitting
IFS=$'\n\t'

# Function to list tmux sessions and tmuxinator projects, mark active sessions
function list_sessions() {
	local all_sessions=$(tmuxinator list -n | tail -n +2 | sort)
	local active_sessions=$(tmux ls | grep -o '^[^:]*' | sort)
	local inactive_sessions=$(comm -23 <(echo "$all_sessions") <(echo "$active_sessions"))

	# Arrays to hold active and inactive sessions separately
	declare -a active_array=()
	declare -a inactive_array=()

	# Add active sessions with a star and space to the active array
	for session in $active_sessions; do
		active_array+=("* $session")
	done

	# Add inactive sessions to the inactive array
	for session in $inactive_sessions; do
		inactive_array+=("$session")
	done

	# Combine the arrays, active sessions first
	combined_sessions=("${active_array[@]}" "${inactive_array[@]}")

	printf "%s\n" "${combined_sessions[@]}"
}

# Use fzf to select a session, removing '*' and space for active sessions
function select_session() {
	local selected_session=$(list_sessions | fzf --reverse | sed 's/^\* //')
	if [[ -n "$selected_session" ]]; then
		# Special handling for snippets session
		if [[ "$selected_session" == "snippets" ]]; then
			# Get current session and switch to snippets with proper window focus
			local current_session=$(tmux display-message -p '#S')
			local current_dir=$(tmux display-message -p '#{pane_current_path}')
			
			# Source the composite session manager functions
			source /home/decoder/dev/dotfiles/scripts/__snippets_session_manager.sh
			
			# Switch to snippets with smart window focus
			switch_to_composite "$current_session" "$current_dir"
		elif tmux has-session -t "$selected_session" 2>/dev/null; then
			# Regular session switching
			tmux switch-client -t "$selected_session"
		else
			# Start tmuxinator project
			tmuxinator start "$selected_session"
		fi
	fi
}

# Run the session selection
select_session
