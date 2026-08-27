#!/usr/bin/env bash
# PROJECT: task-resume-annotations
# See: .taskopenrc, .config/taskwarrior-tui/shortcut-scripts/taskopen-annotation.sh
#
# Opens a url annotation in the browser, tiles browser + terminal (layout 2),
# and raises the browser.
#
# The tiling used to live in taskopen-annotation.sh, which runs after taskopen
# regardless of which action fired. Opening a file, a brief or a note therefore
# rearranged the desktop and raised a browser around a window that never
# opened. Tiling belongs to the opener that actually spawns the browser, the
# same way __slack_open.sh owns layout 8 for the Slack deep link.

set -eo pipefail

OPENER="${TASKOPEN_URL_OPENER:-open}"
LAYOUT_SCRIPT="${TASKOPEN_URL_LAYOUT_SCRIPT:-$HOME/dev/dotfiles/scripts/__layouts.sh}"
TASKOPEN_URL_LAYOUT="${TASKOPEN_URL_LAYOUT:-2}"
TASKOPEN_URL_LAYOUT_DELAY="${TASKOPEN_URL_LAYOUT_DELAY:-0.4}"

usage() {
	cat <<'EOF'
Usage: __taskopen_url_open.sh <url>

Opens the url in the browser, then tiles browser + terminal and focuses the
browser. Called by the url, link and pr actions in .taskopenrc.

  TASKOPEN_URL_LAYOUT=0   open without tiling
EOF
}

url="${1:-}"
if [[ -z "$url" ]]; then
	usage >&2
	exit 1
fi

# Detach the browser so taskopen returns to the prompt instead of waiting on it,
# and so Chromium diagnostics stay off this terminal. TASKOPEN_URL_NO_DETACH=1
# runs it synchronously; the tests set it so they can assert on the stub.
if [[ "${TASKOPEN_URL_NO_DETACH:-0}" == "1" ]] || ! command -v setsid >/dev/null 2>&1; then
	"$OPENER" "$url" </dev/null >/dev/null 2>&1 || true
else
	setsid -f "$OPENER" "$url" </dev/null >/dev/null 2>&1 || true
fi

# Raise the browser window: Chrome for work, LibreWolf in timeoff mode.
focus_browser() {
	command -v xdotool >/dev/null 2>&1 || return 0

	local wid
	if [[ -f /tmp/timeoff_mode ]]; then
		wid=$(xdotool search --onlyvisible --classname Navigator 2>/dev/null | head -n1) || true
	else
		command -v wmctrl >/dev/null 2>&1 || return 0
		wid=$(wmctrl -l -x | grep google-chrome | head -n1 | awk '{print $1}') || true
	fi

	[[ -n "${wid:-}" ]] && xdotool windowactivate "$wid" >/dev/null 2>&1
	return 0
}

# `open` is async, so the browser needs a moment to map its window before
# xdotool can find and tile it.
[[ "$TASKOPEN_URL_LAYOUT" == "0" ]] && exit 0
[[ -x "$LAYOUT_SCRIPT" ]] || exit 0

sleep "$TASKOPEN_URL_LAYOUT_DELAY"
DISPLAY="${DISPLAY:-:0}" "$LAYOUT_SCRIPT" "$TASKOPEN_URL_LAYOUT" >/dev/null 2>&1 || true
focus_browser
exit 0
