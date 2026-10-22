#!/usr/bin/env bash
# Print a compact brief of one TaskWarrior task: description, project, tags,
# due, then annotations oldest first, wrapped. Read-only.
#
# WHY: Gordon's handoff tasks keep the brief (what it is, what "yes" does) in
# annotations, and Piotr had no way to read them without asking. Use:
#   __task_brief.sh <uuid-or-prefix>          print the brief
#   __task_brief.sh --popup <token>           open it in a tmux popup (nvim -R,
#                                             readable and copyable); this is
#                                             what the Alacritty ctrl+6 hint runs
# <token> may be a full uuid, a prefix, `task:<prefix>`, or a whole
# `@"<uuid>|..."` picker token; the first uuid-looking run is used.
#
# Env (tests): TASK_BRIEF_TASK_COMMAND, TASK_BRIEF_TMUX_COMMAND, TASK_BRIEF_WIDTH

set -eo pipefail

popup=0
if [[ "${1:-}" == "--popup" ]]; then
  popup=1
  shift
fi

token="${1:-}"
if [[ -z "$token" ]]; then
  printf 'usage: %s [--popup] <uuid-or-prefix>\n' "${0##*/}" >&2
  exit 2
fi

# Pull the first hex/dash run of 4+ chars out of whatever was passed.
if [[ "$token" =~ ([0-9a-fA-F][0-9a-fA-F-]{3,35}) ]]; then
  uuid="${BASH_REMATCH[1]}"
else
  printf 'not a task reference: %s\n' "$token" >&2
  exit 2
fi

if [[ "$popup" == 1 ]]; then
  # Absolute tmux: a hint runs outside the shell that set PATH (see __task_open.sh).
  tmux_bin="${TASK_BRIEF_TMUX_COMMAND:-/usr/local/bin/tmux}"
  command -v "$tmux_bin" >/dev/null 2>&1 || tmux_bin=tmux
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${0##*/}"
  exec "$tmux_bin" display-popup -E -h 80% -w 85% -T " task ${uuid:0:8} " \
    "'$self' '$uuid' | nvim -R -"
fi

task_bin="${TASK_BRIEF_TASK_COMMAND:-task}"
command -v "$task_bin" >/dev/null 2>&1 || {
  printf 'task binary not found\n' >&2
  exit 127
}

width="${TASK_BRIEF_WIDTH:-${FZF_PREVIEW_COLUMNS:-${COLUMNS:-80}}}"
[[ "$width" =~ ^[0-9]+$ ]] || width=80

json=$("$task_bin" rc.context=none rc.verbose=nothing rc.hooks=off rc.gc=off \
  rc.confirmation=no "$uuid" export 2>/dev/null) || json=""
if ! jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$json"; then
  printf 'no task matches %s\n' "$uuid" >&2
  exit 1
fi

jq -r '.[0] |
  "\(.description)\n" +
  "uuid:    \(.uuid)\n" +
  "status:  \(.status)" + (if .project then "  project: \(.project)" else "" end) + "\n" +
  (if (.tags // []) | length > 0 then "tags:    \(.tags | join(" "))\n" else "" end) +
  (if .due then "due:     \(.due)\n" else "" end) +
  ((.annotations // []) | sort_by(.entry)
    | map("\n[\(.entry)]\n\(.description)") | join("\n"))' <<<"$json" |
  fold -s -w "$width"
