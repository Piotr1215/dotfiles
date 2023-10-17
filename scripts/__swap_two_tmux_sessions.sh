#!/bin/bash

# Files to keep track of sessions
CURRENT_SESSION_FILE=~/.tmux_current_session
PREVIOUS_SESSION_FILE=~/.tmux_previous_session

# Get the current session name
CURRENT_SESSION=$(tmux display-message -p '#S')

# Read the previous session name from the file
PREVIOUS_SESSION=$(cat "$PREVIOUS_SESSION_FILE" 2>/dev/null)

# Read the stored current session name from the file
STORED_CURRENT_SESSION=$(cat "$CURRENT_SESSION_FILE" 2>/dev/null)

# If the current session is not the same as the stored current session,
# it means a new session has been selected.
if [[ "$CURRENT_SESSION" != "$STORED_CURRENT_SESSION" && -n "$STORED_CURRENT_SESSION" ]]; then
	# Update the previous session to be the stored current session
	echo "$STORED_CURRENT_SESSION" >"$PREVIOUS_SESSION_FILE"
	# Update the stored current session to be the current session
	echo "$CURRENT_SESSION" >"$CURRENT_SESSION_FILE"
	# Switch to the previous session initially
	tmux switch-client -t "$STORED_CURRENT_SESSION"
elif [ -n "$PREVIOUS_SESSION" ]; then
	# If the current session is the same as the stored current session,
	# toggle to the previous session
	tmux switch-client -t "$PREVIOUS_SESSION"
	# Swap the stored current and previous sessions
	echo "$PREVIOUS_SESSION" >"$CURRENT_SESSION_FILE"
	echo "$CURRENT_SESSION" >"$PREVIOUS_SESSION_FILE"
fi
