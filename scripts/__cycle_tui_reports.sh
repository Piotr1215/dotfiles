#!/bin/zsh

# Cycle through taskwarrior-tui reports
reports=(inbox byrepo byproject current)
state_file="/tmp/tui_report_index"

# Get current index
if [[ -f "$state_file" ]]; then
	idx=$(<"$state_file")
else
	idx=0
fi

# Cycle to next (zsh arrays are 1-indexed)
idx=$(( (idx % ${#reports[@]}) + 1 ))
echo "$idx" > "$state_file"

report="${reports[$idx]}"

# Get the active pane
pane=$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}')

# Atomic restart and set pane title
tmux select-pane -t "$pane" -T "$report"
tmux respawn-pane -k -t "$pane" "NCURSES_NO_UTF8_ACS=1 taskwarrior-tui -r $report"
