#!/bin/bash

# Capture the current session and window name
current_session=$(tmux display-message -p '#S')
current_window=$(tmux display-message -p '#I')
current_pane=$(tmux display-message -p '#P')

# File path from the input parameter
FILE_PATH="$1"

# Create a new vertical split pane and run neovim
tmux split-window -h
new_pane=$(tmux display-message -p '#P')
tmux send-keys -t "$new_pane" "nvim $FILE_PATH; tmux wait-for -S nvim-exit" Enter

# Automatically switch focus to the new pane
tmux select-pane -t "$new_pane"

# Wait for the new pane to signal that Neovim has exited
tmux wait-for nvim-exit

# Close the new pane
tmux kill-pane -t "$new_pane"

# Switch back to the original pane
tmux select-pane -t "$current_pane"
