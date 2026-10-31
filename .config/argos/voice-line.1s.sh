#!/usr/bin/env bash
set -eo pipefail

# Flashes the name of the agent that just received a spoken line, so a line
# still shows it landed when spoken replies are off. Hidden the rest of the time.
#
# __voice_mode.py writes the agent's name to the marker after it submits the
# line. One second because a script runs only on its own interval, the same
# reason as totp.1s.sh: the flash has to start when the line lands.

marker="${XDG_RUNTIME_DIR:-/run/user/$UID}/voice-mode-delivered"

# Four seconds, which is four flashes: each tick is one of them.
flash_seconds=4

# A separator with no button lines is what makes argos hide an applet. With no
# output at all it shows the file name instead.
hide() {
	echo "---"
	exit 0
}

[[ -f "$marker" ]] || hide
(($(date +%s) - $(stat -c %Y "$marker") < flash_seconds)) || hide

source /home/decoder/dev/dotfiles/scripts/__lib_screen.sh
panel_size=$(panel_label_size 12)
agent=$(<"$marker")

# The colour sits on the second element because the panel drops one on the first.
badge() {
	printf "<tt><b>V:</b></tt><tt><span color='%s'>%s</span></tt> | font='monospace' size=%s dropdown=false\n" \
		"$1" "$agent" "$panel_size"
}

# Two button lines start argos's line cycler, which is what reads as a flash.
badge '#44ff44'
badge '#222222'
