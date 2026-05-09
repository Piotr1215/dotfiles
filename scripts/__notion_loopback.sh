#!/usr/bin/env bash
# Idempotent PipeWire loopback so Notion AI Meeting Notes (browser) hears both
# my mic AND remote voices. Creates a virtual sink "notion_capture", routes:
#   real default mic        ->  notion_capture
#   default sink .monitor   ->  notion_capture
# then exposes notion_capture.monitor as a regular source "NotionMic"
# (Chrome filters raw .monitor sources from getUserMedia, so we wrap it).
#
# In the Notion AI Meeting Notes recorder, pick "NotionMic" as the mic.
# Zoom (or any conferencing app) MUST keep using the real mic, not NotionMic
# — otherwise remotes hear themselves.
#
# WARNING: any audio playing through your default sink is captured too
# (music, YouTube, system sounds, Slack pings). Pause non-call audio while
# Notion is recording.
#
# See: https://github.com/Piotr1215/claude/issues/137
#
# Usage:
#   __notion_loopback.sh up       # bring up the virtual mic (default)
#   __notion_loopback.sh down     # tear it all down
#   __notion_loopback.sh status   # show whether it's currently active
#   __notion_loopback.sh restart  # down + up

set -eo pipefail

readonly sink_name="notion_capture"
readonly sink_desc="NotionCapture"
readonly mic_name="notion_mic"
readonly mic_desc="NotionMic"
readonly latency_msec="100"
readonly state_file="${XDG_RUNTIME_DIR:-/tmp}/notion_loopback.modules"

err() { printf '%s\n' "$*" >&2; }

# Load a pulse module and append its id to the state file.
load_module() {
	local module_id
	module_id=$(pactl load-module "$@")
	printf '%s\n' "$module_id" >> "$state_file"
	printf '%s' "$module_id"
}

# True if the named virtual sink is already loaded.
is_up() {
	pactl list short sinks | awk '{print $2}' | grep -qx "$sink_name"
}

cmd_up() {
	if is_up; then
		err "notion_loopback: already up (sink '$sink_name' exists)"
		return 0
	fi

	local default_sink default_source
	default_sink=$(pactl get-default-sink)
	default_source=$(pactl get-default-source)

	if [ -z "$default_sink" ] || [ -z "$default_source" ]; then
		err "notion_loopback: failed to resolve default sink/source"
		return 1
	fi

	# Truncate state file before any new load
	: > "$state_file"

	load_module module-null-sink \
		sink_name="$sink_name" \
		sink_properties="device.description=$sink_desc" >/dev/null

	load_module module-loopback \
		"source=$default_source" \
		"sink=$sink_name" \
		"latency_msec=$latency_msec" \
		source_dont_move=true \
		sink_dont_move=true >/dev/null

	load_module module-loopback \
		"source=${default_sink}.monitor" \
		"sink=$sink_name" \
		"latency_msec=$latency_msec" \
		source_dont_move=true \
		sink_dont_move=true >/dev/null

	# Expose the virtual sink's monitor as a regular source so Chrome's
	# getUserMedia enumerates it (raw .monitor sources are filtered out).
	load_module module-remap-source \
		"master=${sink_name}.monitor" \
		"source_name=$mic_name" \
		"source_properties=device.description=$mic_desc" >/dev/null

	printf 'notion_loopback: up\n'
	printf '  mic         = %s\n' "$default_source"
	printf '  speaker mon = %s.monitor\n' "$default_sink"
	printf '  pick "%s" as microphone in the Notion browser tab\n' "$mic_desc"
}

cmd_down() {
	local any=0

	# Try to unload by recorded ids first (cheapest, no string parsing).
	if [ -s "$state_file" ]; then
		local id
		while IFS= read -r id; do
			[ -z "$id" ] && continue
			if pactl unload-module "$id" 2>/dev/null; then
				any=1
			fi
		done < "$state_file"
		: > "$state_file"
	fi

	# Belt-and-braces: also unload any straggler module referencing our names.
	# Matches null-sink, loopback (both sides), and remap-source (master/name).
	local mod
	while IFS=$'\t' read -r mod _; do
		[ -z "$mod" ] && continue
		if pactl unload-module "$mod" 2>/dev/null; then
			any=1
		fi
	done < <(
		pactl list modules \
			| awk -v s="$sink_name" -v m="$mic_name" '
				/^Module #/ { id=substr($2,2); buf="" }
				{ buf = buf "\n" $0 }
				/^$/ {
					if (buf ~ ("(sink=|sink_name=|source=|master=)" s) \
					 || buf ~ ("(source_name=|source=)" m)) print id
					buf = ""
				}
				END {
					if (buf ~ ("(sink=|sink_name=|source=|master=)" s) \
					 || buf ~ ("(source_name=|source=)" m)) print id
				}
			'
	)

	if [ "$any" = "1" ]; then
		printf 'notion_loopback: down\n'
	else
		printf 'notion_loopback: nothing to do (already down)\n'
	fi
}

cmd_status() {
	if is_up; then
		printf 'notion_loopback: UP\n'
		pactl list short sinks   | awk -v s="$sink_name" '$2==s {print "  sink   #"$1, $2}'
		pactl list short sources | awk -v s="${sink_name}.monitor" '$2==s {print "  source #"$1, $2}'
		pactl list short sources | awk -v s="$mic_name" '$2==s {print "  remap  #"$1, $2, "(pick this in Notion)"}'
		return 0
	fi
	printf 'notion_loopback: DOWN\n'
	return 1
}

main() {
	local action="${1:-up}"
	case "$action" in
		up)      cmd_up ;;
		down|stop|off) cmd_down ;;
		status)  cmd_status ;;
		restart) cmd_down; cmd_up ;;
		-h|--help|help)
			sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
			;;
		*)
			err "notion_loopback: unknown action '$action'"
			err "usage: $(basename "$0") [up|down|status|restart]"
			return 2
			;;
	esac
}

main "$@"
