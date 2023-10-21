#!/bin/bash

# Define file paths for storing session names
CURRENT_SESSION_FILE="/tmp/tmux_current_session"
PREVIOUS_SESSION_FILE="/tmp/tmux_previous_session"

# Get the current session name
CURRENT_SESSION=$(tmux display-message -p '#S')

# Read the previous session name from the file
if [[ -f "$PREVIOUS_SESSION_FILE" ]]; then
	PREVIOUS_SESSION=$(cat "$PREVIOUS_SESSION_FILE")
else
	PREVIOUS_SESSION=""
fi

# Read the stored current session name from the file
if [[ -f "$CURRENT_SESSION_FILE" ]]; then
	STORED_CURRENT_SESSION=$(cat "$CURRENT_SESSION_FILE")
else
	STORED_CURRENT_SESSION=""
fi

# If the current session is different from the stored current session,
# it means a new session has been selected.
if [[ "$CURRENT_SESSION" != "$STORED_CURRENT_SESSION" ]]; then
	# Update the previous session to be the stored current session
	echo "$STORED_CURRENT_SESSION" >"$PREVIOUS_SESSION_FILE"
	# Update the stored current session to be the current session
	echo "$CURRENT_SESSION" >"$CURRENT_SESSION_FILE"
else
	# If the current session is the same as the stored current session,
	# toggle to the previous session
	tmux switch-client -t "$PREVIOUS_SESSION"
	# Swap the stored current and previous sessions
	echo "$PREVIOUS_SESSION" >"$CURRENT_SESSION_FILE"
	echo "$CURRENT_SESSION" >"$PREVIOUS_SESSION_FILE"
fi
