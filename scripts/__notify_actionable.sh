#!/usr/bin/env bash
# PROJECT: desktop-notifications
#
# One desktop notification carrying one action button. Click it and the command
# that follows runs; dismiss it, or wait long enough, and nothing happens.
#
# THE ACTION KEY MUST NOT BE "default". That key is reserved by the freedesktop
# spec for "the notification body itself was activated", so a server fires it on
# a body click without ever drawing a button. That is why the Taskwarrior action
# on the PR notification never looked wired: it used "default" and there was
# nothing to press. A named key renders as a real button. Verified live on
# gnome-shell 46, which advertises the "actions" capability.
#
# dunstify blocks on read() until the button is clicked, and it does NOT return
# when the popup expires: a 3s notification left the waiter still blocked twelve
# seconds later. So the wait is bounded here, or every ignored notification
# leaks a process for the life of the session. Past the window the popup may
# still sit in the tray, but its button is inert.
#
# A short-lived caller (a systemd oneshot, a git hook) must also detach this, or
# the waiter dies with the caller and the button does nothing:
#
#     systemd-run --user --collect --quiet -- __notify_actionable.sh ...
#
# Usage: __notify_actionable.sh <urgency> <title> <body> <label> <cmd> [args...]
set -uo pipefail

WAIT_SEC="${NOTIFY_ACTION_WAIT_SEC:-3600}"

if (( $# < 5 )); then
	echo "usage: ${0##*/} <urgency> <title> <body> <label> <cmd> [args...]" >&2
	exit 2
fi

urgency="$1"
title="$2"
body="$3"
label="$4"
shift 4

response="$(timeout "$WAIT_SEC" dunstify \
	--urgency="$urgency" \
	--timeout 0 \
	--action="act,${label}" \
	"$title" "$body" 2>/dev/null)" || exit 0

[[ "$response" == "act" ]] || exit 0

exec "$@"
