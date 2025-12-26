#!/usr/bin/env bash

# Get the current values
status=$(tmux show-option -gqv status)

# Toggle the values
if [[ "$status" == "on" ]]; then
	tmux set-option -g pane-border-status off
	tmux set-option -g status off
elif [[ "$status" == "off" ]]; then
	tmux set-option -g pane-border-status top
	tmux set-option -g status on
fi
