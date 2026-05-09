#!/usr/bin/env bash
# PROJECT: notion-meeting-mic
#
# Argos panel toggle for the Notion AI Meeting Notes virtual mic.
# UP   = PipeWire routing active; pick "NotionMic" inside Notion's recorder.
# DOWN = no virtual mic; conferencing apps see only the real mic.
#
# Click the panel item -> "Turn ON + open Notion" / "Turn OFF".
#
# Refresh: 5s (from filename suffix). The same script handles dropdown
# actions when invoked with --on / --off / --open / --restart.
#
# See: https://github.com/Piotr1215/claude/issues/137

set -eo pipefail

readonly loopback="$HOME/dev/dotfiles/scripts/__notion_loopback.sh"
readonly notion_url="https://www.notion.so/"
# Title substring stable enough across Notion releases to match the tab.
readonly notion_window_re='Notion - Google Chrome'

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
esac

# --- state ----------------------------------------------------------------

if "$loopback" status >/dev/null 2>&1; then
	state="up"
else
	state="down"
fi

# --- panel line -----------------------------------------------------------
# UP   = mic icon + green dot; visually obvious the routing is live.
# DOWN = dim mic icon only.
if [[ "$state" == "up" ]]; then
	echo "🎙 <span color='#44ff44'>●</span> | font='monospace' size=11"
else
	echo "<span color='#888888'>🎙</span> | font='monospace' size=11"
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
echo "Refresh now | refresh=true"
