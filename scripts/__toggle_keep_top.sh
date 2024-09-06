#!/bin/bash

# Get the list of windows with their IDs and titles
windows=$(wmctrl -l)

# Add an indicator to each window title if it is on top
windows_with_status=$(echo "$windows" | while read -r line; do
	window_id=$(echo "$line" | awk '{print $1}')
	if xprop -id "$window_id" | grep -q "_NET_WM_STATE_ABOVE"; then
		echo "$line [ON TOP]"
	else
		echo "$line"
	fi
done)

# Use fzf-tmux to select a window
selected_window=$(echo "$windows_with_status" | fzf-tmux --layout=reverse --prompt="Select window: ")

# Extract the window ID from the selected line
window_id=$(echo "$selected_window" | awk '{print $1}')

# Check if the window is already on top
if xprop -id "$window_id" | grep -q "_NET_WM_STATE_ABOVE"; then
	# If it is, remove the "always on top" property
	wmctrl -i -r "$window_id" -b remove,above
else
	# If it isn't, add the "always on top" property
	wmctrl -i -r "$window_id" -b add,above
fi
