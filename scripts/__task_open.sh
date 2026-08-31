#!/usr/bin/env bash
# Open a TaskWarrior task from a `task:<uuid-prefix>` Alacritty hint (ctrl+5).
#
# The asks section of the Alt-m margin (~/.claude/scripts/__piotr_asks_margin.sh)
# prints one of these per row so a proposal is reachable, not just readable.
#
# WHY A SPLIT RUNNING `task information` RATHER THAN taskwarrior-tui: the tui
# takes no filter argument (`taskwarrior-tui --help` offers only -d, -c,
# --taskdata, --taskrc and -r), so there is no supported way to open it focused
# on one task. `task <uuid> information` also shows the annotation trail, which
# is the part worth arriving at: the reasoning, the blockers and every URL the
# row had no width to print.
#
# The pane keeps its own hints, so a URL in an annotation is one ctrl+1 away
# once you land here.

set -eo pipefail

token="${1:-}"
if [[ -z "$token" ]]; then
  printf 'usage: %s task:<uuid-prefix> | <uuid-prefix>\n' "${0##*/}" >&2
  exit 2
fi

# Accept the hint token, a bare uuid prefix, or a numeric id, since the hint
# regex is shared with whatever else happens to be on screen.
uuid="${token#task:}"
if [[ ! "$uuid" =~ ^[0-9a-fA-F-]+$ ]]; then
  printf 'not a task reference: %s\n' "$token" >&2
  exit 2
fi

task_bin="${TASK_OPEN_TASK_COMMAND:-task}"
command -v "$task_bin" >/dev/null 2>&1 || {
  printf 'task binary not found\n' >&2
  exit 127
}

# Resolve before opening a pane. A hint can capture stale text, and an empty
# pane that flashes and dies tells Piotr nothing about why.
# rc.context=none matters: these tasks are frequently outside the applied
# context, which is the whole reason the asks section exists.
if ! "$task_bin" rc.context=none rc.verbose=nothing "$uuid" export 2>/dev/null | grep -q '"uuid"'; then
  printf 'no task matches %s\n' "$uuid" >&2
  exit 1
fi

tmux_bin="${TASK_OPEN_TMUX_COMMAND:-/usr/local/bin/tmux}"
command -v "$tmux_bin" >/dev/null 2>&1 || tmux_bin=tmux

# A popup, matching M-z / M-b / M-l / M-R in .tmux.conf, rather than a split.
# Reading a task is a glance, not a workspace change: a split rearranges the
# window you were reading and has to be closed again, while a popup returns you
# to exactly what you were looking at on any key.
#
# No -t: a hint runs outside tmux with no client context, so tmux resolves the
# most recently used client, which is the terminal in front of Piotr. This is
# the same assumption the working ctrl+2 hint already relies on.
#
# Absolute tmux path by default: an Alacritty hint runs outside the shell that
# set up PATH, and /usr/bin/tmux (apt 3.4) cannot talk to the source-built
# 3.7b server. That mismatch fails silently, because hint stderr is discarded.
#
# nvim -R rather than a pager: the popup has to be READABLE and COPYABLE.
# tmux popups are not panes, so copy-mode is unavailable in them and a pager
# leaves the text look-only. nvim reads the report on stdin, gives search and
# normal-mode motion over long annotation trails, and yanks to the system
# clipboard with the existing config. Read-only so the buffer cannot be saved
# over anything.
title=" task ${uuid} "
exec "$tmux_bin" display-popup -E -h 80% -w 85% -T "$title" \
  "'$task_bin' rc.context=none '$uuid' information | nvim -R -"
