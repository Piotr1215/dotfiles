#!/usr/bin/env bash
# Give background TUI shortcuts a terminal for a comment or question.
set -eo pipefail

mode=popup
action=ack
if [[ "${1:-}" == --ask ]]; then action=ask; shift; fi
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
title=' Ack with comment '
prompt='Comment: '
placeholder='Your reply to Gordon'
header='Enter a comment to acknowledge this handoff. Esc cancels.'
popup_close=-E
if [[ "$action" == ask ]]; then
  title=' Ask Gordon '
  prompt='Question: '
  placeholder='What do you need to know about this handoff?'
  header='Enter sends your question. The handoff stays open. Esc cancels.'
  popup_close=-EE
fi

if [[ "$mode" == popup ]]; then
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${0##*/}"
  popup_args=()
  [[ "$action" != ask ]] || popup_args+=(--ask)
  printf -v popup_command '%q ' "$self" "${popup_args[@]}" --comment "$uuid"
  exec "${TUI_TMUX_COMMAND:-tmux}" display-popup "$popup_close" -h 10 -w 80% \
    -T "$title" \
    -e "TUI_INPUT_COMMAND=$input_bin" \
    -e "TUI_TW_WRAPPER=$tw_bin" \
    -e "TUI_SND_COMMAND=$snd_bin" \
    "$popup_command"
fi

if note=$("$input_bin" input --char-limit 0 --prompt "$prompt" \
  --placeholder "$placeholder" --header "$header"); then
  [[ "$note" =~ [^[:space:]] ]] || exit 0
else
  status=$?
  [[ "$status" == 1 || "$status" == 130 ]] && exit 0
  exit "$status"
fi

if [[ "$action" == ask ]]; then
  "$tw_bin" note "$uuid" "piotr-question: $note"
  printf -v message 'Piotr asks about handoff %s: %s\nAnswer this question in the handoff brief. Keep the handoff open.' "$uuid" "$note"
  if SND_FROM=handoffs-tui "$snd_bin" --no-human -t triage "$message"; then
    exit 0
  else
    status=$?
    echo 'Could not send your question to Gordon. It is saved on the task; the handoff stays open.' >&2
    exit "$status"
  fi
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
