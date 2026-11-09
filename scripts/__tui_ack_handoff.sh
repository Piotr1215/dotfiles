#!/usr/bin/env bash
# Give background TUI shortcuts a terminal for the human's comment.
set -eo pipefail

mode=popup
if [[ "${1:-}" == --comment ]]; then mode=comment; shift; fi
uuid=${1:-}
[[ "$uuid" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]] || {
  echo 'Select a handoff with a full task UUID.' >&2
  exit 1
}

input_bin=$(command -v "${TUI_INPUT_COMMAND:-gum}") || {
  echo 'gum is required for the handoff comment dialog.' >&2
  exit 127
}
tw_bin=${TUI_TW_WRAPPER:-$HOME/.claude/scripts/__tw.sh}
snd_bin=${TUI_SND_COMMAND:-$HOME/.claude/scripts/snd}

if [[ "$mode" == popup ]]; then
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${0##*/}"
  printf -v popup_command '%q --comment %q' "$self" "$uuid"
  exec "${TUI_TMUX_COMMAND:-tmux}" display-popup -E -h 10 -w 80% \
    -T ' Ack with comment ' \
    -e "TUI_INPUT_COMMAND=$input_bin" \
    -e "TUI_TW_WRAPPER=$tw_bin" \
    -e "TUI_SND_COMMAND=$snd_bin" \
    "$popup_command"
fi

if note=$("$input_bin" input --char-limit 0 --prompt 'Comment: ' \
  --placeholder 'Your reply to Gordon' \
  --header 'Enter a comment to acknowledge this handoff. Esc cancels.'); then
  [[ "$note" =~ [^[:space:]] ]] || exit 0
else
  status=$?
  [[ "$status" == 1 || "$status" == 130 ]] && exit 0
  exit "$status"
fi

"$tw_bin" note "$uuid" "piotr-comment: $note"
# __tw.sh suppresses task-change notices. Send the reply once, before done,
# so a failed delivery leaves the handoff open and completion cannot resend it.
SND_FROM=handoffs-tui "$snd_bin" --no-human -t triage "Piotr replied to handoff $uuid: $note"
if output=$(TW_DONE_OPEN_AGENTS_OK=1 TW_PIOTR_HANDOFF_CLOSE=1 "$tw_bin" 'done' "$uuid" 2>&1); then
  [[ -z "$output" ]] || printf '%s\n' "$output"
else
  status=$?
  message="Could not complete handoff $uuid: ${output:-done failed (exit $status)}"
  printf '%s\n' "$message" >&2
  SND_FROM=handoffs-tui "$snd_bin" --no-human -t triage "$message" || echo 'Could not notify triage.' >&2
  if [[ -t 0 ]]; then read -r -p 'Press Enter to close.' _ || true; fi
  exit "$status"
fi
