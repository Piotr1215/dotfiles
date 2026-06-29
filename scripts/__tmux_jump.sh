#!/usr/bin/env bash
# Alacritty hint target: jump the attached tmux client to an agent's session.
#
# Alacritty passes the matched hint text as the last arg, e.g. "jump:DEVOPS-1017".
# Agent sessions are named with the issue id baked in (e.g.
# "eng-infra-config-DEVOPS-1017"), so we resolve the id to the live session whose
# name contains it as a delimited token, then switch the attached client to it.
# Resolution is dynamic on purpose: the board can name an id whose session has
# since died, and we degrade to a notification instead of switching blindly.
set -eo pipefail

raw="${1:-}"
id="${raw#jump:}"
[ -n "$id" ] || exit 0

# Match the id as a whole token inside a session name (avoids 192 -> 1923).
session="$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
  | grep -iE -- "(^|[-_.])${id}([-_.]|$)" | head -1)"

if [ -n "$session" ]; then
  tmux switch-client -t "$session"
else
  command -v notify-send >/dev/null 2>&1 \
    && notify-send "tmux-jump" "no live agent session for ${id}"
fi
