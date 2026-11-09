#!/usr/bin/env bash
# A non-modal tmux 3.8 pane, with an event-driven selection watcher.
set -eo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mode=${1:-}; uuid=${2:-}; origin=${3:-${TMUX_PANE:-}}
selected_row=${4:-}
log_dir=${XDG_STATE_HOME:-$HOME/.local/state}
mkdir -p "$log_dir"
exec 3>&2
exec 2> >(while IFS= read -r line; do printf '%s uuid=%s mode=%s %s\n' "$(date -Is)" "$uuid" "$mode" "$line" | tee -a "$log_dir/handoff-floater.log" >&3; done)
tmux_bin=${HANDOFF_TMUX_COMMAND:-tmux}
nvim_bin=${HANDOFF_NVIM_COMMAND:-nvim}
runtime=${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}/taskwarrior-tui

# Reject command-like input before using it in a remote expression or tmux target.
valid_uuid() { [[ "$1" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]]; }
# Tab in an empty task list still hands focus to an open brief.
[[ "$mode" == focus && -z "$uuid" ]] || valid_uuid "$uuid" || { echo 'Select a task with a full UUID' >&2; exit 2; }
[[ "$origin" =~ ^%[0-9]+$ ]] || { echo 'A Twoy tmux pane is required' >&2; exit 2; }
umask 077
mkdir -p "$runtime"
chmod 700 "$runtime"
socket="$runtime/handoff-${origin#%}.sock"
selection="selected-${origin#%}"
pane_id_file="$runtime/floater-${origin#%}.id"
pin_file="$runtime/pinned-${origin#%}"
peek_file="$runtime/peeking-${origin#%}"
pin_geometry_file="$runtime/pinned-geometry-${origin#%}"

# RPC returns an error without switching when writing the current buffer fails.
rpc() { "$nvim_bin" --server "$socket" --remote-expr "$1"; }
current_floater_id() {
  local pane_id
  pane_id=$(cat "$pane_id_file" 2>/dev/null || rpc "luaeval('vim.env.TMUX_PANE')" 2>/dev/null || true)
  pane_id=${pane_id//[\'\"] /}
  pane_id=${pane_id//[\'\"]/}
  [[ "$pane_id" =~ ^%[0-9]+$ ]] || return 1
  printf '%s\n' "$pane_id"
}

# Peek panes follow the selected TUI row. Row numbers are relative to the
# origin pane's content area; tmux positions floating panes in window space.
peek_geometry() {
  [[ "$selected_row" =~ ^[0-9]+$ ]] || return 1
  local geometry pane_top window_height float_height below top
  geometry=$("$tmux_bin" display-message -p -t "$origin" \
    '#{pane_top} #{window_height}') || return 1
  read -r pane_top window_height <<<"$geometry"
  [[ "$pane_top" =~ ^[0-9]+$ && "$window_height" =~ ^[0-9]+$ ]] || return 1
  (( window_height > 2 )) || return 1
  float_height=$((window_height / 2))
  (( float_height > 1 )) || float_height=1
  # Floating panes have a one-cell border around their content height.
  below=$((pane_top + selected_row + 1))
  if (( below + float_height + 2 <= window_height )); then
    top=$below
  else
    top=$((pane_top + selected_row - float_height - 2))
    (( top >= 0 )) || top=0
  fi
  # tmux's floating-pane coordinates include its one-cell outer border.
  printf '%s %s\n' "$float_height" "$top"
}

# Put a floating pane under the selected row, or above it when there is no room.
place_peek() {
  local pane_id=$1 geometry float_height float_top pane_left
  geometry=$(peek_geometry) || return 1
  read -r float_height float_top <<<"$geometry"
  pane_left=$("$tmux_bin" display-message -p -t "$pane_id" '#{pane_left}') || return 1
  "$tmux_bin" resize-pane -t "$pane_id" -y "$((float_height + 2))" \; \
    move-pane -t "$pane_id" -X "$((pane_left - 1))" -Y "$float_top"
}

# Bring the brief to the row the task list selected. The TUI writes
# "<uuid> <row>"; older builds wrote the uuid alone, which switches without a
# move. The editor answers 1 when it now shows that task and 0 when it keeps
# its own (pinned, or holding an edit it could not save), so a kept brief
# stays beside its own row.
follow_selection() {
  local selected="" row="" pane_id followed
  read -r selected row 2>/dev/null < "$runtime/$selection" || [[ -n "$selected" ]] || return 0
  valid_uuid "$selected" || return 0
  pane_id=$(current_floater_id) || return 0
  # While the brief has the keyboard the list cannot move; Tab back catches up.
  [[ $("$tmux_bin" display-message -p -t "$pane_id" '#{pane_active}' 2>/dev/null) == 1 ]] && return 0
  followed=$(rpc "luaeval('HandoffSelection(_A)', '$selected')" 2>/dev/null) || return 0
  [[ "$followed" == 1 ]] || return 0
  selected_row=$row
  place_peek "$pane_id" || true
}

# Serialize with b, pin and close, which move the same pane under this lock.
follow_locked() {
  (
    flock -w 5 9 || exit 0
    follow_selection
  ) 9>"$runtime/handoff-${origin#%}.lock"
}

case "$mode" in
  prepare)
    exec python3 "$root/__handoff_floater_file.py" "$uuid" ;;
  watch)
    # Watching the directory survives interface A's atomic rename of the file.
    coproc events { exec inotifywait -m -q -e moved_to,close_write --format '%f' "$runtime"; }
    # Bash creates this variable for the named coprocess.
    # shellcheck disable=SC2154
    watcher=$events_PID
    trap 'kill "$watcher" 2>/dev/null || true' EXIT
    trap 'exit 0' TERM INT HUP
    # Holding j renames the selection file once per row. Wait until it rests
    # and follow only the last row, so a held key costs one switch, not one
    # Neovim client and tmux move per row.
    debounce=${HANDOFF_FOLLOW_DEBOUNCE:-0.15}
    [[ "$debounce" =~ ^[0-9]+(\.[0-9]+)?$ ]] || debounce=0.15
    while IFS= read -r changed <&"${events[0]}"; do
      [[ "$changed" == "$selection" ]] || continue
      while IFS= read -r -t "$debounce" changed <&"${events[0]}"; do :; done
      follow_locked || true
    done
    ;;
  focus)
    # Tab in the task list gives an open brief the keyboard. No brief, no-op.
    [[ -S "$socket" ]] || exit 0
    pane_id=$(current_floater_id) || exit 0
    "$tmux_bin" select-pane -t "$pane_id" 2>/dev/null || true
    ;;
  focus-list)
    # Tab in the brief gives the task list the keyboard and leaves the brief
    # open, caught up with any selection made while it had focus.
    "$tmux_bin" select-pane -t "$origin"
    follow_locked || true
    ;;
  open|toggle|pin|close)
    exec 9>"$runtime/handoff-${origin#%}.lock"
    flock 9
    if [[ -S "$socket" ]] && rpc '1' >/dev/null 2>&1; then
      if [[ "$mode" == toggle ]]; then
        rpc "luaeval('HandoffToggle(_A)', '$uuid')" >/dev/null
        if [[ -f "$pin_file" ]] && pane_id=$(current_floater_id); then
          printf '%s\n' "$pane_id" > "$pane_id_file"
          if [[ $(cat "$peek_file" 2>/dev/null || true) != 1 ]]; then
            printf '1\n' > "$peek_file"
            place_peek "$pane_id" || true
          else
            printf '0\n' > "$peek_file"
            if [[ -f "$pin_geometry_file" ]]; then
              read -r pin_left pin_top pin_width pin_height < "$pin_geometry_file"
              "$tmux_bin" resize-pane -t "$pane_id" -x "$((pin_width + 2))" -y "$((pin_height + 2))"
              "$tmux_bin" move-pane -t "$pane_id" -X "$pin_left" -Y "$pin_top"
            fi
          fi
        fi
      elif [[ "$mode" == close ]]; then
        rpc "luaeval('HandoffHide()')" >/dev/null
        rm -f "$pin_file" "$peek_file" "$pin_geometry_file" "$pane_id_file"
      elif [[ "$mode" == pin ]]; then
        rpc "luaeval('HandoffPin(_A)', '$uuid')" >/dev/null
        pane_id=$(current_floater_id) || pane_id=
        printf '%s\n' "$uuid" > "$pin_file"
        printf '0\n' > "$peek_file"
        if [[ -n "$pane_id" ]]; then
          printf '%s\n' "$pane_id" > "$pane_id_file"
          pin_position=$("$tmux_bin" display-message -p -t "$pane_id" '#{pane_left} #{pane_top}')
          read -r pin_left pin_top <<<"$pin_position"
          pin_dimensions=$("$tmux_bin" display-message -p -t "$pane_id" '#{pane_width} #{pane_height}')
          read -r pin_width pin_height <<<"$pin_dimensions"
          printf '%s %s %s %s\n' "$((pin_left - 1))" "$((pin_top - 1))" "$pin_width" "$pin_height" > "$pin_geometry_file"
        fi
      else
        rpc "luaeval('HandoffSwitch(_A, true)', '$uuid')" >/dev/null
      fi
      exit 0
    fi
    [[ "$mode" == close ]] && exit 0
    # A q key or prior toggle may have removed Neovim without cleaning its
    # runtime markers. A new pane starts with fresh, unpinned state.
    rm -f "$pin_file" "$peek_file" "$pin_geometry_file" "$pane_id_file"
    file=$(HANDOFF_TASK_UUID="$uuid" python3 "$root/__handoff_floater_file.py" "$uuid")
    float_size='-x 90% -y 65% -X 5% -Y 30%'
    if [[ "$mode" == toggle ]] && geometry=$(peek_geometry); then
      read -r float_height float_top <<<"$geometry"
      float_size="-x 90% -y $((float_height + 2)) -X 5% -Y $float_top"
    fi
    # b (toggle) opens the brief to read and type in, so it takes focus at once
    # (Piotr, 6 Nov). Handoff starts pin it with -d and keep the task view focused.
    focus=(-d)
    [[ "$mode" == toggle ]] && focus=()
    # Multiple command argv bypass tmux's shell-string path.
    # shellcheck disable=SC2086 # tmux geometry is a fixed, validated argv fragment.
    pane_id=$("$tmux_bin" new-pane "${focus[@]}" -P -F '#{pane_id}' -t "$origin" $float_size \
      -T "handoff ${uuid:0:8}" \
      env "HANDOFF_ROOT=$root" "HANDOFF_ORIGIN=$origin" "HANDOFF_UUID=$uuid" \
      "HANDOFF_RETURN_FOCUS=1" \
      "HANDOFF_PINNED=$([[ "$mode" == pin ]] && printf 1 || printf 0)" \
      "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" "XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}" \
      "HANDOFF_TASK_COMMAND=${HANDOFF_TASK_COMMAND:-task}" \
      "HANDOFF_NVIM_COMMAND=$nvim_bin" "HANDOFF_TMUX_COMMAND=$tmux_bin" \
      "HANDOFF_SAVE_SCRIPT=$root/__handoff_brief_save.py" \
      "HANDOFF_TW_WRAPPER=${HANDOFF_TW_WRAPPER:-$HOME/.claude/scripts/__tw.sh}" \
      "HANDOFF_SND_COMMAND=${HANDOFF_SND_COMMAND:-$HOME/.claude/scripts/snd}" \
      "HANDOFF_RECONCILE_COMMAND=${HANDOFF_RECONCILE_COMMAND:-$HOME/.claude/scripts/__tw_brief.py}" \
      "$root/__handoff_editor.sh" "$file")
    printf '%s\n' "$pane_id" > "$pane_id_file"
    if [[ "$mode" == pin ]]; then
      printf '%s\n' "$uuid" > "$pin_file"
      printf '0\n' > "$peek_file"
      pin_position=$("$tmux_bin" display-message -p -t "$pane_id" '#{pane_left} #{pane_top}')
      read -r pin_left pin_top <<<"$pin_position"
      pin_dimensions=$("$tmux_bin" display-message -p -t "$pane_id" '#{pane_width} #{pane_height}')
      read -r pin_width pin_height <<<"$pin_dimensions"
      printf '%s %s %s %s\n' "$((pin_left - 1))" "$((pin_top - 1))" "$pin_width" "$pin_height" > "$pin_geometry_file"
    fi
    # Serialize overlapping shortcut presses through editor startup too.
    for ((attempt=0; attempt<100; attempt++)); do
      if [[ -S "$socket" ]] && rpc '1' >/dev/null 2>&1; then exit 0; fi
      sleep 0.05
    done
    echo 'Handoff editor did not become ready' >&2
    exit 1
    ;;
  *) echo 'usage: __handoff_floater.sh open|toggle|pin|close|focus|focus-list <uuid> [<twoy-pane>] [<row>]' >&2; exit 2 ;;
esac
