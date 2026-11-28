#!/usr/bin/env bash
# PROJECT: sudo-agent-gate
#
# Edit the agent sudo allow list as root, then check that it parses. The click
# behind "Edit allowed commands" in the argos SU menu, opened in a new tmux
# window the way the crontab edit is. sudoedit keeps the file root-owned, which
# is what stops an agent running as Piotr from adding its own commands. A line
# that does not parse turns the whole list off, so the check runs after every
# save and the window stays open on a failure.
set -eo pipefail
allow=${SUDO_GATE_ALLOW_FILE:-/etc/sudo-agent-gate/allow}
gate=${SUDO_GATE_BIN:-/usr/local/sbin/sudo-agent-gate}

# Keep the window open until Enter, so a failure can be read.
pause() {
    printf "%s Press Enter to close." "$1" >&2
    read -r _ || :
}

if ! SUDO_EDITOR=${SUDO_EDITOR:-nvim} sudoedit "$allow"; then
    pause "sudoedit failed."
    exit 1
fi
if ! "$gate" check --allow "$allow"; then
    pause "Fix the line above."
    exit 1
fi
read -rt 2 _ || :
