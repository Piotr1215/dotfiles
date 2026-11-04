#!/usr/bin/env bash
set -eo pipefail
reports=(inbox byrepo byproject current)
current="${TASKWARRIOR_TUI_REPORT:-inbox}"
state_file="${TUI_REPORT_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tui/previous-report-${TMUX_PANE:-default}}"
tmux_bin="${TUI_REPORT_TMUX:-tmux}"
handoffs_rc="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../.config/taskwarrior-tui/handoffs.taskrc"
if [[ "${1:-cycle}" == toggle ]]; then
  if [[ "$current" == handoffs ]]; then
    report=$(cat "$state_file" 2>/dev/null || printf inbox)
    [[ "$report" =~ ^[a-zA-Z0-9_-]+$ && "$report" != handoffs ]] || report=inbox
  else
    mkdir -p "$(dirname "$state_file")"
    printf '%s\n' "$current" > "$state_file"
    report=handoffs
  fi
else
  report=inbox
  for i in "${!reports[@]}"; do
    if [[ "${reports[$i]}" == "$current" ]]; then report="${reports[$(((i + 1) % ${#reports[@]}))]}"; break; fi
  done
fi
pane=$($tmux_bin display-message -p '#{pane_id}')
"$tmux_bin" select-pane -t "$pane" -T "$report"
printf -v rc_arg '%q' "$handoffs_rc"
printf -v home_arg '%q' "$HOME/.envrc"
tui_args="-r $report"
[[ "$report" == handoffs ]] && tui_args="--taskrc $rc_arg -r $report"
"$tmux_bin" respawn-pane -k -t "$pane" "[ -f $home_arg ] && . $home_arg; exec env NCURSES_NO_UTF8_ACS=1 taskwarrior-tui $tui_args"
