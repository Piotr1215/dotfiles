#!/usr/bin/env bash
set -eo pipefail

# Toggle "on top" for a window: kept above other windows and shown on every
# workspace. The two go together because above alone still vanishes on a
# workspace switch, and a window worth keeping on top is one wanted in view
# whatever workspace is showing. ontop-glow@dotfiles draws the glow.
#
# Usage:
#   __toggle_keep_top.sh           pick a window with fzf
#   __toggle_keep_top.sh --active  the focused window (Super+Shift+T)

# Read with [[ ]] rather than piping into grep -q: under pipefail, grep quitting
# on the first match can SIGPIPE xprop and turn a match into a failure.
is_above() {
	[[ "$(xprop -id "$1" _NET_WM_STATE)" == *_NET_WM_STATE_ABOVE* ]]
}

# Decide off the above flag alone and set both states to match it. Flipping each
# on its own would invert a window that got only one of them, from the title-bar
# menu or wmctrl.
toggle_on_top() {
	local window_id="$1"
	if is_above "$window_id"; then
		wmctrl -i -r "$window_id" -b remove,above,sticky
	else
		wmctrl -i -r "$window_id" -b add,above,sticky
	fi
}

# List every window, marking the ones already on top, and print the picked id.
pick_window() {
	local line window_id
	wmctrl -l | while read -r line; do
		window_id=$(echo "$line" | awk '{print $1}')
		if is_above "$window_id"; then
			echo "$line [ON TOP]"
		else
			echo "$line"
		fi
	done | fzf-tmux --layout=reverse --prompt="Select window: " | awk '{print $1}'
}

main() {
	local window_id
	if [[ "${1:-}" == "--active" ]]; then
		window_id=$(xdotool getactivewindow)
	else
		# A cancelled picker is not an error.
		window_id=$(pick_window) || exit 0
	fi
	[[ -n "$window_id" ]] || exit 0
	toggle_on_top "$window_id"
}

main "$@"
