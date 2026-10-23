#!/usr/bin/env bash
# Alacritty hint target: jump the attached tmux client to an agent's session.
#
# Alacritty passes the matched hint text as the last arg, e.g. "jump:DEVOPS-1017".
# Agent sessions are named with the issue id baked in (e.g.
# "eng-infra-config-DEVOPS-1017"), so we resolve the id to the live session whose
# name contains it as a delimited token, then switch the attached client to it.
# Resolution is dynamic on purpose: the board can name an id whose session has
# since died, and we degrade to a notification instead of switching blindly.
#
# The client lands on the agent's pane, selected by pane id. A bare session
# switch lands on whichever window the session last had active, and `task`
# holds two agents in two windows (Gordon in todo, Kendra in kendra), so once
# Kendra's window had been visited, jump:task landed on Kendra.
set -eo pipefail

raw="${1:-}"
id="${raw#jump:}"
[ -n "$id" ] || exit 0

# agent_pane SESSION: print the pane the jump should land on. Gordon's pane
# (bus name triage, the tag the cockpit uses for his row) wins; otherwise the
# session's only pane tagged with an agent name. Prints nothing when neither
# exists, and the caller falls back to the session.
agent_pane() {
  local pane name only="" count=0
  while IFS='|' read -r pane name; do
    [ -n "$name" ] || continue
    if [ "$name" = triage ]; then
      printf '%s\n' "$pane"
      return 0
    fi
    only="$pane"
    count=$((count + 1))
  done < <(tmux list-panes -s -t "=$1" -F '#{pane_id}|#{@agent_name}' 2>/dev/null)
  if [ "$count" -eq 1 ]; then printf '%s\n' "$only"; fi
  return 0
}

# Match the id as a whole token inside a session name (avoids 192 -> 1923).
# `|| true`: under pipefail a grep with no match would exit the script before
# the notification below.
session="$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
  | grep -iE -- "(^|[-_.])${id}([-_.]|$)" | head -1)" || true

if [ -z "$session" ]; then
  command -v notify-send >/dev/null 2>&1 \
    && notify-send "tmux-jump" "no live agent session for ${id}"
  exit 0
fi

pane="$(agent_pane "$session")"
if [ -z "$pane" ]; then
  tmux switch-client -t "$session"
  exit 0
fi

# A pane target moves the client to its session, window and pane; the window and
# pane are also selected by id, as __cycle_agent_session.sh does.
tmux switch-client -t "$pane"
tmux select-window -t "$pane" 2>/dev/null || true
tmux select-pane -t "$pane" 2>/dev/null || true
