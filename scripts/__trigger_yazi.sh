#!/usr/bin/env bash

current_command=$(tmux display-message -p '#{pane_current_command}')

if [[ "$current_command" == "nvim" ]]; then
	tmux send-keys 'Space' '-'
else
	tmux split-window -h -c '#{pane_current_path}' 'EDITOR=nvim yazi'
fi
