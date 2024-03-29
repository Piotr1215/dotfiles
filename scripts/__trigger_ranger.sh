#!/bin/bash
# This script is part used in the tmux.conf file to trigger ranger
# PROJECT: ranger-tmux-setup
if [[ $(tmux display-message -p '#{pane_current_command}') == "nvim" ]]; then
	tmux send-keys 'Space' 'm' 'r'
else
	tmux popup -d '#{pane_current_path}' -E -h 95% -w 95% -x 100% 'ranger'
fi
