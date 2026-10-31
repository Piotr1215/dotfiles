#!/usr/bin/env bash
# PROJECT: notion-meeting-mic
#
# Argos panel toggle for the Notion AI Meeting Notes virtual mic.
# UP   = PipeWire routing active; pick "NotionMic" inside Notion's recorder.
# DOWN = no virtual mic; conferencing apps see only the real mic.
#
# Click the panel item -> "Turn ON + open Notion" / "Turn OFF".
#
# Refresh: 1s (from filename suffix), so an agent's name blinks as a spoken line
# lands. The same script handles dropdown actions when invoked with --on / --off
# / --open / --restart.
#
# See: https://github.com/Piotr1215/claude/issues/137

# Panel label size follows the main screen width (see panel_label_size).
source /home/decoder/dev/dotfiles/scripts/__lib_screen.sh
PANEL_SIZE=$(panel_label_size 11 letterless)

set -eo pipefail

readonly loopback="$HOME/dev/dotfiles/scripts/__notion_loopback.sh"
readonly notion_url="https://www.notion.so/"
# Title substring stable enough across Notion releases to match the tab.
readonly notion_window_re='Notion - Google Chrome'
# Flips go through the toggle board, which owns the on and off logic.
readonly toggles="${TOGGLES_BIN:-$HOME/dev/dotfiles/scripts/__toggles.sh}"
readonly voice_replies_off_flag="${KLOD_VOICE_STATE:-$HOME/.local/state/klod-voice}/off"
# __voice_mode.py writes the agent's name here after it submits a line.
readonly delivered="${XDG_RUNTIME_DIR:-/run/user/$UID}/voice-mode-delivered"
readonly blink_seconds=4

# --- side-effect actions (invoked from dropdown menu items) ---------------

# Bring an existing Notion tab to the front, or open one in Chrome.
focus_or_open_notion() {
	# wmctrl matches against the active tab title — Chrome rewrites the
	# window title to whichever tab is foreground. So a stale title may not
	# match even though Notion is open in another tab.
	local wid
	wid="$(wmctrl -l 2>/dev/null | awk -v re="$notion_window_re" 'BEGIN{IGNORECASE=1} $0 ~ re {print $1; exit}')"
	if [[ -n "$wid" ]]; then
		wmctrl -i -a "$wid"
		return 0
	fi
	# Fall back: open notion.so in default browser.
	xdg-open "$notion_url" >/dev/null 2>&1 &
	disown
}

case "${1:-}" in
	--on)
		"$loopback" up
		focus_or_open_notion
		exit 0
		;;
	--off)
		"$loopback" down
		exit 0
		;;
	--restart)
		"$loopback" restart
		exit 0
		;;
	--open)
		focus_or_open_notion
		exit 0
		;;
	--voice-off)
		"$toggles" __run voice-mode off
		"$toggles" __run voice-replies off
		exit 0
		;;
esac

# --- state ----------------------------------------------------------------

if "$loopback" status >/dev/null 2>&1; then
	state="up"
else
	state="down"
fi

# Read directly: the board's __render runs every toggle's status, too heavy for
# a 1s refresh.
if systemctl --user is-active --quiet voice-mode.service; then
	voice_listening="on"
	voice_dot=" <span color='#44aaff'>●</span>"
else
	voice_listening="off"
	voice_dot=""
fi
if [[ -e "$voice_replies_off_flag" ]]; then
	voice_replies="off"
else
	voice_replies="on"
fi

# --- panel line -----------------------------------------------------------
# UP   = mic icon + green dot; visually obvious the routing is live.
# DOWN = dim mic icon only.
# A blue dot means voice mode is listening on the headset.
# A blinking name behind them is the agent that just took a spoken line.
if [[ "$state" == "up" ]]; then
	mic="🎙 <span color='#44ff44'>●</span>${voice_dot}"
else
	mic="<span color='#888888'>🎙</span>${voice_dot}"
fi

# Two button lines start argos's line cycler, which is the blink; dropdown=false
# keeps them out of the menu. A name puts letters on the line, so it takes the
# lettered size (see panel_label_size).
if [[ -f "$delivered" ]] && (($(date +%s) - $(stat -c %Y "$delivered") < blink_seconds)); then
	agent=$(<"$delivered")
	name_size=$(panel_label_size 11)
	echo "${mic} <span color='#44ff44'>${agent}</span> | font='monospace' size=${name_size} dropdown=false"
	echo "${mic} <span color='#222222'>${agent}</span> | font='monospace' size=${name_size} dropdown=false"
else
	echo "${mic} | font='monospace' size=${PANEL_SIZE}"
fi

# --- dropdown -------------------------------------------------------------
echo "---"

if [[ "$state" == "up" ]]; then
	echo "<b>Notion virtual mic — UP</b> | font=monospace"
	# Surface what's actually being captured so the user can spot drift
	# (e.g. headset switched but routing still points at the old default).
	"$loopback" status 2>/dev/null \
		| sed -e '1d' \
		| while IFS= read -r line; do
			echo "${line} | font=monospace"
		done
	echo "---"
	echo "🛑 Turn OFF | bash='\"$0\" --off' terminal=false refresh=true"
	echo "🔄 Restart routing | bash='\"$0\" --restart' terminal=false refresh=true"
	echo "🌐 Focus / open Notion | bash='\"$0\" --open' terminal=false"
else
	echo "<b>Notion virtual mic — DOWN</b> | font=monospace"
	echo "Audio routing not active | font=monospace"
	echo "---"
	echo "🎙️ Turn ON + open Notion | bash='\"$0\" --on' terminal=false refresh=true"
	echo "🎙️ Turn ON (audio only) | bash='\"$loopback\" up' terminal=false refresh=true"
fi

echo "---"
echo "<i>In Notion's recorder pick \"NotionMic\".</i> | font=monospace"
echo "---"

# One menu row per board toggle: voice_item <toggle> <label> <on|off>
voice_item() {
	if [[ "$3" == "on" ]]; then
		echo "🟢 $2: on, click to turn off | bash='\"$toggles\" __run $1 off' terminal=false refresh=true"
	else
		echo "⚪ $2: off, click to turn on | bash='\"$toggles\" __run $1 on' terminal=false refresh=true"
	fi
}

echo "<b>Voice bridge</b> | font=monospace"
voice_item voice-mode "Hands-free listening" "$voice_listening"
voice_item voice-replies "Spoken replies (Piper)" "$voice_replies"
if [[ "$voice_listening" == "on" || "$voice_replies" == "on" ]]; then
	echo "🛑 All off (normal mode) | bash='\"$0\" --voice-off' terminal=false refresh=true"
fi

echo "---"
echo "Refresh now | refresh=true"
