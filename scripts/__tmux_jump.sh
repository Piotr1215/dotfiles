#!/usr/bin/env bash
# Alacritty hint target (Ctrl+3): jump the attached tmux client to an agent's
# window.
#
# Alacritty passes the matched hint text as the last arg. The cockpit
# (~/.claude/scripts/__cockpit_state.sh) prints one token per agent row:
#   jump:<name>            the row's agent name: gordon, kendra, or the pane's
#                          @agent_name tag. Resolved to the tagged pane, wherever
#                          its window sits.
#   jump:<session>:<win>   printed only when two rows share a name.
#   jump:<session>         a row with no tagged pane. Also matches an id as a
#                          delimited token in a session name (DEVOPS-1017 ->
#                          eng-infra-config-DEVOPS-1017).
# The window and pane are selected by id before the client switches. A bare
# session switch lands on whichever window the session last had active, which
# put the jump to Gordon on Kendra's window once both shared `task`.
#
# Pressing the token of the pane the client is already on steps to the next
# agent pane in that session, Gordon (triage) first: on Gordon, jump:gordon goes
# to Kendra; on Kendra, jump:kendra goes back to Gordon.
#
# Resolution is dynamic on purpose: the board can name an agent that has since
# died, and we degrade to a notification instead of switching blindly.
set -eo pipefail

raw="${1:-}"
token="${raw#jump:}"
[ -n "$token" ] || exit 0

# label_of SESSION TAG: set `label` to the name the cockpit gives an agent pane.
# Mirrors pass 1a of __cockpit_state.sh: Gordon (triage in task) and Kendra
# (intake) by role, a stray triage tag by its session, anything else by its tag.
label_of() {
  if [ "$1" = task ] && [ "$2" = triage ]; then label=gordon
  elif [ "$2" = triage ]; then label="$1"
  elif [ "$2" = intake ]; then label=kendra
  else label="$2"; fi
}

# build_ring SESSION: set `ring` to the session's tagged panes, triage first,
# then the rest in tmux order.
build_ring() {
  local row s w wn p tag
  local -a first=() rest=()
  for row in "${panes[@]}"; do
    IFS='|' read -r s w wn p tag <<<"$row"
    if [ "$s" != "$1" ] || [ -z "$tag" ]; then continue; fi
    if [ "$tag" = triage ]; then first+=("$p"); else rest+=("$p"); fi
  done
  ring=("${first[@]}" "${rest[@]}")
}

mapfile -t panes < <(tmux list-panes -a \
  -F '#{session_name}|#{window_id}|#{window_name}|#{pane_id}|#{@agent_name}' 2>/dev/null || true)

session="" window="" pane="" label="" ring=()
if [[ "$token" == *:* ]]; then
  # jump:<session>:<window>, the cockpit's answer to a name two rows share.
  for row in "${panes[@]}"; do
    IFS='|' read -r s w wn p tag <<<"$row"
    if [ "$s" != "${token%%:*}" ] || [ "$wn" != "${token#*:}" ]; then continue; fi
    session="$s"; window="$w"
    if [ -n "$tag" ]; then pane="$p"; break; fi
  done
else
  for row in "${panes[@]}"; do
    IFS='|' read -r s w wn p tag <<<"$row"
    [ -n "$tag" ] || continue
    label_of "$s" "$tag"
    if [ "$label" = "$token" ]; then session="$s"; pane="$p"; break; fi
  done
  if [ -z "$session" ]; then
    # A row with no tagged pane names its session; an id matches as a whole
    # token inside a session name (avoids 192 -> 1923). `|| true`: under
    # pipefail a grep with no match would exit before the notification below.
    sessions="$(tmux list-sessions -F '#{session_name}' 2>/dev/null)" || true
    session="$(grep -xF -- "$token" <<<"$sessions" | head -1)" || true
    [ -n "$session" ] || session="$(grep -iE -- "(^|[-_.])${token}([-_.]|$)" <<<"$sessions" | head -1)" || true
    if [ -n "$session" ]; then
      build_ring "$session"
      pane="${ring[0]:-}"
    fi
  fi
fi

if [ -z "$session" ]; then
  command -v notify-send >/dev/null 2>&1 \
    && notify-send "tmux-jump" "no live agent for ${token}"
  exit 0
fi

# Already on the target: step to the session's next agent pane.
if [ -n "$pane" ]; then
  current="$(tmux display-message -p '#{pane_id}' 2>/dev/null)" || true
  if [ "$pane" = "$current" ]; then
    build_ring "$session"
    for i in "${!ring[@]}"; do
      if [ "${ring[$i]}" = "$pane" ]; then
        pane="${ring[$(( (i + 1) % ${#ring[@]} ))]}"
        break
      fi
    done
  fi
fi

# Select the window, then the pane, by id, so the client lands on them whatever
# the session had active. A pane target moves the client to its session, window
# and pane in one step.
if [ -n "$pane" ]; then
  tmux select-window -t "$pane" 2>/dev/null || true
  tmux select-pane -t "$pane" 2>/dev/null || true
  tmux switch-client -t "$pane"
else
  if [ -n "$window" ]; then tmux select-window -t "$window" 2>/dev/null || true; fi
  tmux switch-client -t "$session"
fi
