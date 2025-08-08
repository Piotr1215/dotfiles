#!/usr/bin/env bash

set -eo pipefail

# Set new line and tab for word splitting
IFS=$'\n\t'

# Configuration
ACCESS_LOG="$HOME/.tmux_session_access.log"
PINNED_SESSIONS=("task" "mail")
MAX_LOG_ENTRIES=1000

# Function to track session access
function track_access() {
	local session="$1"
	if [[ -n "$session" ]]; then
		echo "$(date +%s) $session" >> "$ACCESS_LOG"
		# Keep log file from growing too large
		if [[ -f "$ACCESS_LOG" ]] && [[ $(wc -l < "$ACCESS_LOG") -gt $MAX_LOG_ENTRIES ]]; then
			tail -n $((MAX_LOG_ENTRIES / 2)) "$ACCESS_LOG" > "${ACCESS_LOG}.tmp"
			mv "${ACCESS_LOG}.tmp" "$ACCESS_LOG"
		fi
	fi
}

# Function to get session access frequencies
function get_frequencies() {
	if [[ -f "$ACCESS_LOG" ]]; then
		# Count accesses in the last 30 days
		local cutoff=$(date -d "30 days ago" +%s 2>/dev/null || date -v-30d +%s 2>/dev/null || echo 0)
		awk -v cutoff="$cutoff" '$1 > cutoff {print $2}' "$ACCESS_LOG" | \
			sort | uniq -c | sort -rn
	fi
}

# Function to list tmux sessions and tmuxinator projects, mark active sessions
function list_sessions() {
	local all_sessions=$(tmuxinator list -n | tail -n +2 | sort)
	local active_sessions=$(tmux ls 2>/dev/null | grep -o '^[^:]*' | sort)
	local inactive_sessions=$(comm -23 <(echo "$all_sessions") <(echo "$active_sessions"))
	
	# Get frequency data
	local frequencies=$(get_frequencies)
	
	# Arrays for different categories
	declare -a pinned_active=()
	declare -a pinned_inactive=()
	declare -a frequent_active=()
	declare -a frequent_inactive=()
	declare -a other_active=()
	declare -a other_inactive=()
	
	# Helper function to check if session is pinned
	is_pinned() {
		local session="$1"
		for pinned in "${PINNED_SESSIONS[@]}"; do
			[[ "$session" == "$pinned" ]] && return 0
		done
		return 1
	}
	
	# Process active sessions
	for session in $active_sessions; do
		if is_pinned "$session"; then
			pinned_active+=("** $session")
		elif echo "$frequencies" | grep -q "[[:space:]]$session$"; then
			frequent_active+=("* $session")
		else
			other_active+=("* $session")
		fi
	done
	
	# Process inactive sessions
	for session in $inactive_sessions; do
		if is_pinned "$session"; then
			pinned_inactive+=("   $session")
		elif echo "$frequencies" | grep -q "[[:space:]]$session$"; then
			frequent_inactive+=("  $session")
		else
			other_inactive+=("  $session")
		fi
	done
	
	# Sort frequent sessions by frequency
	sort_by_frequency() {
		local -a sessions=("$@")
		local -a sorted=()
		
		for session in "${sessions[@]}"; do
			local clean_session=$(echo "$session" | sed 's/^[* ]*//')
			local freq=$(echo "$frequencies" | grep "[[:space:]]$clean_session$" | awk '{print $1}')
			if [[ -z "$freq" ]]; then freq=0; fi
			echo "$freq $session"
		done | sort -rn | cut -d' ' -f2-
	}
	
	# Sort frequent sessions by access frequency
	if [[ ${#frequent_active[@]} -gt 0 ]]; then
		mapfile -t frequent_active < <(sort_by_frequency "${frequent_active[@]}")
	fi
	if [[ ${#frequent_inactive[@]} -gt 0 ]]; then
		mapfile -t frequent_inactive < <(sort_by_frequency "${frequent_inactive[@]}")
	fi
	
	# Combine all arrays in order: task first, then other pinned, then rest
	# Separate task from other pinned sessions
	local -a task_session=()
	local -a other_pinned_active=()
	local -a other_pinned_inactive=()
	
	for session in "${pinned_active[@]}"; do
		if [[ "$session" == *"task" ]]; then
			task_session+=("$session")
		else
			other_pinned_active+=("$session")
		fi
	done
	
	for session in "${pinned_inactive[@]}"; do
		if [[ "$session" == *"task" ]]; then
			task_session+=("$session")
		else
			other_pinned_inactive+=("$session")
		fi
	done
	
	combined_sessions=(
		"${task_session[@]}"
		"${other_pinned_active[@]}"
		"${other_pinned_inactive[@]}"
		"${frequent_active[@]}"
		"${other_active[@]}"
		"${frequent_inactive[@]}"
		"${other_inactive[@]}"
	)
	
	printf "%s\n" "${combined_sessions[@]}"
}

# Use fzf to select a session, removing markers and spaces
function select_session() {
	local selected=$(list_sessions | fzf --reverse --header="**=pinned active  *=active  Task always first")
	local selected_session=$(echo "$selected" | sed 's/^[* ]*//')
	
	if [[ -n "$selected_session" ]]; then
		# Track the access
		track_access "$selected_session"
		
		if tmux has-session -t "$selected_session" 2>/dev/null; then
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
