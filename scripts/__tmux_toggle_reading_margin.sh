#!/usr/bin/env bash

set -euo pipefail

ensure=false
repair=false
status=false
sync=false
sync_client=""
manual_zoom=false
case "${1:-}" in
--ensure-session)
  session_name="${2:-}"
  if [[ -z "$session_name" ]]; then
    printf 'usage: %s --ensure-session session-name\n' "${0##*/}" >&2
    exit 2
  fi
  [[ "$session_name" =~ _[0-9a-f]{4}$ ]] && exit 0
  target_pane="$(tmux display-message -p -t "$session_name" '#{pane_id}' 2>/dev/null || true)"
  [ -n "$target_pane" ] || exit 0
  ensure=true
  ;;
--repair-window)
  window_id="${2:-}"
  if [[ -z "$window_id" ]]; then
    printf 'usage: %s --repair-window window-id\n' "${0##*/}" >&2
    exit 2
  fi
  window_id="$(tmux display-message -p -t "$window_id" '#{window_id}' 2>/dev/null || true)"
  [ -n "$window_id" ] || exit 0
  repair=true
  ;;
--status)
  target_pane="${2:-${TMUX_PANE:-}}"
  if [[ -z "$target_pane" ]]; then
    target_pane="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
  fi
  status=true
  ;;
--toggle-client)
  sync_client="${2:-}"
  target_pane="${3:-}"
  if [[ -z "$sync_client" || -z "$target_pane" ]]; then
    printf 'usage: %s --toggle-client client-name pane-id\n' "${0##*/}" >&2
    exit 2
  fi
  ;;
--sync-client)
  sync_client="${2:-}"
  # An empty client is the boot case, not a typo. tmuxinator builds every
  # session detached at login, so the hooks that pass "#{hook_client}" fire
  # before any client exists and expand it to "". Nothing is on screen to sync,
  # so this is the same no-op as an unresolvable pane below, and it must stay
  # silent: a usage error here printed into the first pane that attached.
  if [[ -z "$sync_client" ]]; then
    exit 0
  fi
  target_pane="$(tmux display-message -p -c "$sync_client" '#{pane_id}' 2>/dev/null || true)"
  [ -n "$target_pane" ] || exit 0
  sync=true
  ;;
--sync-window)
  window_id="${2:-}"
  if [[ -z "$window_id" ]]; then
    printf 'usage: %s --sync-window window-id\n' "${0##*/}" >&2
    exit 2
  fi
  window_id="$(tmux display-message -p -t "$window_id" '#{window_id}' 2>/dev/null || true)"
  [ -n "$window_id" ] || exit 0
  sync=true
  ;;
--toggle-zoom)
  target_pane="${2:-${TMUX_PANE:-}}"
  if [[ -z "$target_pane" ]]; then
    printf 'usage: %s --toggle-zoom pane-id\n' "${0##*/}" >&2
    exit 2
  fi
  manual_zoom=true
  ;;
*)
  target_pane="${1:-${TMUX_PANE:-}}"
  ;;
esac
if ! $repair && ! $sync && [[ -z "$target_pane" ]]; then
  printf 'usage: %s pane-id | --ensure-session session-name\n' "${0##*/}" >&2
  exit 2
fi

if ! $repair && [[ -z "${window_id:-}" ]]; then
  window_id="$(tmux display-message -p -t "$target_pane" '#{window_id}')"
fi
# Resize, layout, and selection hooks may overlap. Keep each window's zoom and
# ownership marker as one serialized state transition.
lock_file="${XDG_RUNTIME_DIR:-/tmp}/tmux-reading-margin-$UID-${window_id#@}.lock"
exec {lock_fd}>"$lock_file"
flock "$lock_fd"
margin_pane="$(tmux show-options -wqv -t "$window_id" @reading_margin_pane)"
margin_exists=false
if [[ -n "$margin_pane" ]] &&
  [[ "$(tmux display-message -p -t "$margin_pane" '#{window_id}' 2>/dev/null || true)" == "$window_id" ]]; then
  margin_exists=true
fi

set_visible() {
  tmux set-option -w -t "$window_id" @reading_margin_visible "$1"
}

window_zoomed() {
  tmux display-message -p -t "$window_id" '#{window_zoomed_flag}'
}

auto_zoomed_pane() {
  tmux show-options -wqv -t "$window_id" @reading_margin_auto_zoomed
}

active_pane() {
  tmux display-message -p -t "$window_id" '#{pane_id}'
}

auto_zoom_active() {
  local pane
  pane="$(auto_zoomed_pane)"
  [[ -n "$pane" && "$(window_zoomed)" == 1 && "$(active_pane)" == "$pane" ]]
}

content_pane() {
  tmux list-panes -t "$window_id" -F '#{pane_id}|#{pane_active}' | awk -F'|' -v margin="$margin_pane" '
    $1 != margin {
      if ($2 == 1) { print $1; found = 1; exit }
      if (first == "") first = $1
    }
    END { if (!found && first != "") print first }
  '
}

display_state() {
  local client_pid client_name x_window_id wm_state
  case "${TMUX_READING_MARGIN_DISPLAY_STATE:-}" in
    expanded|tiled)
      printf '%s\n' "$TMUX_READING_MARGIN_DISPLAY_STATE"
      return
      ;;
  esac

  x_window_id="${TMUX_READING_MARGIN_X_WINDOW_ID:-}"
  if [[ -z "$sync_client" ]]; then
    client_name="$(tmux list-clients -F '#{client_name}|#{window_id}' 2>/dev/null \
      | awk -F'|' -v window="$window_id" '$2 == window { print $1; exit }')"
    sync_client="$client_name"
  fi
  if [[ -z "$x_window_id" && -n "$sync_client" ]]; then
    # WINDOWID belongs to this exact tmux client. Never guess from the first
    # visible Alacritty because several terminals may use different layouts.
    client_pid="$(tmux display-message -p -c "$sync_client" '#{client_pid}' 2>/dev/null || true)"
    if [[ -n "$client_pid" && -r "/proc/$client_pid/environ" ]]; then
      x_window_id="$(tr '\0' '\n' < "/proc/$client_pid/environ" | sed -n 's/^WINDOWID=//p' | head -n 1)"
    fi
  fi
  if [[ -z "$x_window_id" ]] || ! command -v xprop >/dev/null 2>&1; then
    printf 'unknown\n'
    return
  fi

  wm_state="$(xprop -id "$x_window_id" _NET_WM_STATE 2>/dev/null || true)"
  if [[ "$wm_state" != _NET_WM_STATE* ]]; then
    printf 'unknown\n'
  elif [[ "$wm_state" == *'_NET_WM_STATE_FULLSCREEN'* ]] ||
    [[ "$wm_state" == *'_NET_WM_STATE_MAXIMIZED_HORZ'* &&
      "$wm_state" == *'_NET_WM_STATE_MAXIMIZED_VERT'* ]]; then
    printf 'expanded\n'
  else
    printf 'tiled\n'
  fi
}

sync_display_state() {
  local state="$1" pane tracked
  $margin_exists || return 0

  tracked="$(auto_zoomed_pane)"
  case "$state" in
    tiled)
      if [[ "$(window_zoomed)" == 1 ]]; then
        if [[ -n "$tracked" && "$(active_pane)" != "$tracked" ]]; then
          tmux set-option -wu -t "$window_id" @reading_margin_auto_zoomed 2>/dev/null || true
        fi
        set_visible off
        return 0
      fi
      pane="$(content_pane)"
      [[ -n "$pane" ]] || return 0
      tmux resize-pane -Z -t "$pane"
      tmux set-option -w -t "$window_id" @reading_margin_auto_zoomed "$pane"
      set_visible off
      ;;
    expanded)
      [[ -n "$tracked" ]] || return 0
      if auto_zoom_active; then
        tmux resize-pane -Z -t "$tracked"
      fi
      tmux set-option -wu -t "$window_id" @reading_margin_auto_zoomed 2>/dev/null || true
      set_visible on
      repair_width
      ;;
  esac
}

clear_auto_zoom() {
  local tracked
  tracked="$(auto_zoomed_pane)"
  [[ -n "$tracked" ]] || return 0
  if auto_zoom_active; then
    tmux resize-pane -Z -t "$tracked"
  fi
  tmux set-option -wu -t "$window_id" @reading_margin_auto_zoomed 2>/dev/null || true
}

repair_width() {
  local expected_width margin_width window_width
  [[ "$(window_zoomed)" == 1 ]] && return 0
  window_width="$(tmux display-message -p -t "$window_id" '#{window_width}')"
  margin_width="$(tmux display-message -p -t "$margin_pane" '#{pane_width}')"
  expected_width=$((window_width * 33 / 100))
  ((expected_width > 0)) || expected_width=1
  if ((margin_width != expected_width)); then
    tmux resize-pane -t "$margin_pane" -x 33%
  fi
}

if $manual_zoom; then
  tmux set-option -wu -t "$window_id" @reading_margin_auto_zoomed 2>/dev/null || true
  tmux resize-pane -Z -t "$target_pane"
  if $margin_exists && [[ "$(window_zoomed)" == 1 ]]; then
    set_visible off
  elif $margin_exists; then
    set_visible on
    repair_width
  fi
  exit 0
fi

if $status; then
  default="$(tmux show-options -gqv @reading_margin_default)"
  hidden=""
  if $margin_exists && [[ "$(window_zoomed)" == 1 ]]; then
    visible=off
    if auto_zoom_active; then hidden=' hidden=tiled'
    else hidden=' hidden=zoomed'
    fi
  elif $margin_exists; then
    visible=on
  else
    visible=off
  fi
  printf 'reading-margin default=%s visible=%s window=%s' "${default:-off}" "$visible" "$window_id"
  if $margin_exists; then
    printf '%s pane=%s width=%s\n' "$hidden" "$margin_pane" \
      "$(tmux display-message -p -t "$margin_pane" '#{pane_width}')"
  else
    printf '\n'
  fi
  exit 0
fi

if $sync; then
  sync_display_state "$(display_state)"
  exit 0
fi

if $repair; then
  if $margin_exists; then
    # A margin pane created before 2026-08-31 was built with select-pane -d, so
    # it silently swallows the j/k/G that scroll viddy. Creation-time flags do
    # not apply retroactively, which left long-lived panes permanently
    # unscrollable with no visible cause. Re-assert it on every repair so an
    # existing pane heals itself instead of needing a toggle off and on.
    tmux select-pane -e -t "$margin_pane" 2>/dev/null || true
    if [[ "$(window_zoomed)" == 1 ]]; then
      set_visible off
    else
      set_visible on
      repair_width
    fi
  else
    tmux set-option -wu -t "$window_id" @reading_margin_pane 2>/dev/null || true
    set_visible off
  fi
  exit 0
fi

if $margin_exists; then
  if $ensure; then
    set_visible on
    repair_width
    sync_display_state "$(display_state)"
    exit 0
  fi
  clear_auto_zoom
  set_visible off
  tmux kill-pane -t "$margin_pane"
  tmux set-option -wu -t "$window_id" @reading_margin_pane
  exit 0
fi

tmux set-option -wu -t "$window_id" @reading_margin_pane 2>/dev/null || true
if $ensure && [[ "$(tmux show-options -gqv @reading_margin_default)" != on ]]; then
  set_visible off
  exit 0
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
timeoff_file="${TMUX_READING_MARGIN_TIMEOFF_FILE:-/tmp/timeoff_mode}"
if [ -f "$timeoff_file" ]; then
  margin_command="${TMUX_READING_MARGIN_WEEKEND_COMMAND:-exec \"$script_dir/__play_track.sh\" --run}"
  input_flag=-e
else
  session_name="$(tmux display-message -p -t "$target_pane" '#{session_name}')"
  margin_command="${TMUX_READING_MARGIN_WORK_COMMAND:-exec \"$script_dir/__tmux_reading_margin_work.sh\" \"$session_name\" \"$window_id\"}"
  # Input ENABLED, changed from -d on 2026-08-31. The work margin runs viddy,
  # which scrolls with j/k/G and handles the mouse, and the asks section at the
  # bottom is now longer than the pane. Under -d tmux dropped every keystroke
  # before viddy saw it, so the pane looked frozen and the only diagnosis
  # available was "viddy cannot scroll", which is false.
  # This does not leak stray keys: input reaches a pane only while it is the
  # active one, and the toggle re-selects the content pane on the next line.
  input_flag=-e
fi
margin_pane="$(
  tmux split-window -bdfl 33% -h -t "$target_pane" -P -F '#{pane_id}' "$margin_command"
)"
tmux set-option -w -t "$window_id" @reading_margin_pane "$margin_pane"
margin_exists=true
set_visible on
tmux select-pane "$input_flag" -T ' ' -t "$margin_pane"
tmux select-pane -t "$target_pane"
sync_display_state "$(display_state)"
