#!/usr/bin/env bash
set -e

# This script respawns all panes in the "todo" window of the task session with specific commands
# Using a two-step approach: first respawn, then send commands

# Respawn all panes first
tmux respawn-pane -k -t task:todo.1
tmux respawn-pane -k -t task:todo.2
tmux respawn-pane -k -t task:todo.3
tmux respawn-pane -k -t task:todo.4

# Send commands to each pane
tmux send-keys -t task:todo.1 "NCURSES_NO_UTF8_ACS=1 tui -r workdone" Enter
tmux send-keys -t task:todo.2 "NCURSES_NO_UTF8_ACS=1 tui -r backlog" Enter
tmux send-keys -t task:todo.3 "tuiw" Enter
tmux send-keys -t task:todo.4 "NCURSES_NO_UTF8_ACS=1 tui -r current-prs-age" Enter

echo "All panes in the todo window have been respawned" >&2