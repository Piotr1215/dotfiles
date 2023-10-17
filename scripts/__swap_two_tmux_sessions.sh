#!/bin/bash

# Get the current session name
CURRENT_SESSION=$(tmux display-message -p '#S')

# Read the previous session name from the tmux environment
PREVIOUS_SESSION=$(tmux show-environment -g TMUX_PREVIOUS_SESSION 2>/dev/null | cut -d '=' -f2)

# Read the stored current session name from the tmux environment
STORED_CURRENT_SESSION=$(tmux show-environment -g TMUX_CURRENT_SESSION 2>/dev/null | cut -d '=' -f2)

# If the current session is different from the stored current session,
# it means a new session has been selected.
if [[ "$CURRENT_SESSION" != "$STORED_CURRENT_SESSION" ]]; then
	# Update the previous session to be the stored current session
	tmux set-environment -g TMUX_PREVIOUS_SESSION "$STORED_CURRENT_SESSION"
	# Update the stored current session to be the current session
	tmux set-environment -g TMUX_CURRENT_SESSION "$CURRENT_SESSION"
else
	# If the current session is the same as the stored current session,
	# toggle to the previous session
	tmux switch-client -t "$PREVIOUS_SESSION"
	# Swap the stored current and previous sessions
	tmux set-environment -g TMUX_PREVIOUS_SESSION "$CURRENT_SESSION"
	tmux set-environment -g TMUX_CURRENT_SESSION "$PREVIOUS_SESSION"
fi
