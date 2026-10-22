#!/usr/bin/env bash
# Print a compact brief of one TaskWarrior task: description, project, tags,
# due, then annotations oldest first, wrapped. Read-only.
#
# WHY: Gordon's handoff tasks keep the brief (what it is, what "yes" does) in
# annotations, and Piotr had no way to read them without asking. Use:
#   __task_brief.sh <uuid-or-prefix>          print the brief
#   __task_brief.sh --popup <token>           open it in a tmux popup (nvim -R,
#                                             readable and copyable); this is
#                                             the plain read-only popup
#   __task_brief.sh --actions <token>         popup with actions; what the
#                                             Alacritty ctrl+6 hint runs, for a
#                                             full uuid or a 4-hex handoff ref
#                                             from the Alt-m board. Keys:
#                                             q/Esc close, Enter unfurl the task
#                                             token into Gordon's prompt, s the
#                                             same prefixed with /ops-spawn-agent,
#                                             d marks the task done. Text is
#                                             typed, never submitted.
# <token> may be a full uuid, a prefix, `task:<prefix>`, or a whole
# `@"<uuid>|..."` picker token; the first uuid-looking run is used.
# A ref that matches several pending tasks opens a pick list first.
#
# The Gordon pane is the tmux pane whose @agent_name is `triage`, resolved live.
# The token has the shape of the Claude Code @ picker (file-suggestion.toml):
#   @"<uuid>|<linear id or ->|<repo or ->|<description>"
#
# Env (tests): TASK_BRIEF_TASK_COMMAND, TASK_BRIEF_TMUX_COMMAND,
# TASK_BRIEF_NVIM_COMMAND, TASK_BRIEF_WIDTH

set -eo pipefail

mode=plain
case "${1:-}" in
  --popup) mode=popup; shift ;;
  --actions) mode=actions; shift ;;
  --actions-run) mode=actions_run; shift ;;
esac

token="${1:-}"
if [[ -z "$token" ]]; then
  printf 'usage: %s [--popup|--actions] <uuid-or-prefix>\n' "${0##*/}" >&2
  exit 2
fi

# Pull the first hex/dash run of 4+ chars out of whatever was passed.
if [[ "$token" =~ ([0-9a-fA-F][0-9a-fA-F-]{3,35}) ]]; then
  uuid="${BASH_REMATCH[1]}"
else
  printf 'not a task reference: %s\n' "$token" >&2
  exit 2
fi

# Absolute tmux: a hint runs outside the shell that set PATH (see __task_open.sh).
tmux_bin="${TASK_BRIEF_TMUX_COMMAND:-/usr/local/bin/tmux}"
command -v "$tmux_bin" >/dev/null 2>&1 || tmux_bin=tmux
self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${0##*/}"

if [[ "$mode" == popup ]]; then
  exec "$tmux_bin" display-popup -E -h 80% -w 85% -T " task ${uuid:0:8} " \
    "'$self' '$uuid' | nvim -R -"
fi

if [[ "$mode" == actions ]]; then
  exec "$tmux_bin" display-popup -E -h 80% -w 85% -T " handoff ${uuid:0:8} " \
    "'$self' --actions-run '$uuid'"
fi

task_bin="${TASK_BRIEF_TASK_COMMAND:-task}"
command -v "$task_bin" >/dev/null 2>&1 || {
  printf 'task binary not found\n' >&2
  exit 127
}

tw() {
  "$task_bin" rc.context=none rc.verbose=nothing rc.hooks=off rc.gc=off \
    rc.confirmation=no "$@"
}

# Print the brief of task $1 (full uuid) to stdout.
print_brief() {
  local id="$1" width json
  width="${TASK_BRIEF_WIDTH:-${FZF_PREVIEW_COLUMNS:-${COLUMNS:-80}}}"
  [[ "$width" =~ ^[0-9]+$ ]] || width=80

  json=$(tw "$id" export 2>/dev/null) || json=""
  if ! jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$json"; then
    printf 'no task matches %s\n' "$id" >&2
    return 1
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
}

# Wait for a key so a popup message can be read before -E closes it.
pause() {
  printf '%s\n(press any key)\n' "$1"
  read -rsn1 _ || true
}

# The picker token for task $1, same shape as file-suggestion.toml builds.
build_token() {
  tw "$1" export 2>/dev/null | jq -r '.[0] |
    "@\"\(.uuid)|\(.linear_issue_id // "-")|\(.repo // "-")|\(.description)\""'
}

# Type $1 into the Gordon pane (@agent_name = triage). -l keeps it literal and
# no Enter is sent, so Piotr reviews the line and submits it himself.
send_to_gordon() {
  local pane
  pane=$("$tmux_bin" list-panes -a -F '#{pane_id} #{@agent_name}' 2>/dev/null |
    awk '$2 == "triage" { print $1; exit }')
  if [[ -z "$pane" ]]; then
    pause 'no Gordon pane (no tmux pane has @agent_name=triage)'
    return 1
  fi
  "$tmux_bin" send-keys -t "$pane" -l -- "$1"
}

# Popup body for --actions: resolve the ref, show the brief, act on the key.
actions_run() {
  local ref="${1,,}" id line n i key rc keys tmpf token
  local -a ids=() descs=()
  # A full uuid opens whatever its status; a short ref means a pending task.
  local -a filter=(status:pending)
  [[ ${#ref} -eq 36 ]] && filter=("$ref")
  while IFS=$'\t' read -r id line; do
    [[ -n "$id" ]] || continue
    ids+=("$id")
    descs+=("$line")
  done < <(tw "${filter[@]}" export 2>/dev/null |
    jq -r --arg p "$ref" '.[] | select(.uuid | startswith($p)) | "\(.uuid)\t\(.description)"')

  n=${#ids[@]}
  if ((n == 0)); then
    pause "no pending task matches $ref"
    return 1
  fi
  id="${ids[0]}"
  if ((n > 1)); then
    keys=123456789abcdefghijklmnopqrstuvwxyz
    printf '%s matches %d pending tasks, pick one:\n\n' "$ref" "$n"
    for ((i = 0; i < n && i < ${#keys}; i++)); do
      printf '  %s  %s  %s\n' "${keys:i:1}" "${ids[i]:0:8}" "${descs[i]}"
    done
    printf '\nkey to pick, anything else cancels\n'
    read -rsn1 key || key=""
    id=""
    for ((i = 0; i < n && i < ${#keys}; i++)); do
      [[ "$key" == "${keys:i:1}" ]] && id="${ids[i]}"
    done
    [[ -n "$id" ]] || return 0
  fi

  tmpf=$(mktemp)
  {
    printf '[Enter] unfurl into Gordon   [s] spawn   [d] done   [q/Esc] close\n\n'
    print_brief "$id"
  } >"$tmpf"

  rc=0
  "${TASK_BRIEF_NVIM_COMMAND:-nvim}" -R \
    -c 'nnoremap <silent> q :qa!<CR>' \
    -c 'nnoremap <silent> <Esc> :qa!<CR>' \
    -c 'nnoremap <silent> <CR> :cq 10<CR>' \
    -c 'nnoremap <silent> s :cq 11<CR>' \
    -c 'nnoremap <silent> d :cq 12<CR>' \
    - <"$tmpf" || rc=$?
  rm -f "$tmpf"

  case "$rc" in
    10) token=$(build_token "$id"); send_to_gordon "$token" ;;
    11) token=$(build_token "$id"); send_to_gordon "/ops-spawn-agent $token " ;;
    # Hooks stay on: closing is a real write, unlike the reads above.
    12) "$task_bin" rc.confirmation=no rc.verbose=nothing "$id" 'done' >/dev/null ;;
    *) return 0 ;;
  esac
}

if [[ "$mode" == actions_run ]]; then
  actions_run "$uuid"
  exit $?
fi

print_brief "$uuid" || exit 1
