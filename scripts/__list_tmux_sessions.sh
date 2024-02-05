#!/usr/bin/env bash

set -eo pipefail

# Set new line and tab for word splitting
IFS=$'\n\t'

# Function to list tmux sessions and tmuxinator projects, mark active sessions
function list_sessions() {
	local all_sessions=$(tmuxinator list -n | tail -n +2 | sort)
	local active_sessions=$(tmux ls | grep -o '^[^:]*')
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
	tmuxinator start "${selected_session}" || tmux switch-client -t "${selected_session}"
}

# Run the session selection
select_session
