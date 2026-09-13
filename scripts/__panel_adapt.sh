#!/usr/bin/env bash

# PROJECT: window_manager
# Adapt the GNOME top panel to the main screen width. GNOME bounds the right
# box by the clock's right edge, so on a narrow main screen (a 1080p monitor
# beside the laptop) the indicators do not fit and the longest label is
# clipped to "…". Just Perfection's panel button padding recovers the room:
# every button gives up a few pixels on each side. On the 4k screen at home
# the default padding (0 means GNOME's own) stays. Idempotent, so the layout
# hook can call it on every keypress.
#
# Usage: __panel_adapt.sh [--print]
# Env:   PANEL_COMPACT_PADDING  button padding in px when compact (default 4)

set -eo pipefail
IFS=$'\n\t'

source "$(dirname "${BASH_SOURCE[0]}")/__lib_screen.sh"

SCHEMA="org.gnome.shell.extensions.just-perfection"
SCHEMADIR="${JUST_PERFECTION_SCHEMADIR:-$HOME/.local/share/gnome-shell/extensions/just-perfection-desktop@just-perfection/schemas}"

# Print the button padding the current desk wants.
wanted_padding() {
	if panel_compact; then
		printf '%s\n' "${PANEL_COMPACT_PADDING:-4}"
	else
		printf '0\n'
	fi
}

main() {
	local want have
	want=$(wanted_padding)
	if [[ "${1:-}" == "--print" ]]; then
		printf '%s\n' "$want"
		return 0
	fi
	[[ -d "$SCHEMADIR" ]] || return 0
	have=$(gsettings --schemadir "$SCHEMADIR" get "$SCHEMA" panel-button-padding-size 2>/dev/null || echo "")
	[[ "$have" == "$want" ]] && return 0
	gsettings --schemadir "$SCHEMADIR" set "$SCHEMA" panel-button-padding-size "$want"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
