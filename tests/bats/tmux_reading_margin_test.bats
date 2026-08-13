#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__tmux_toggle_reading_margin.sh"
  WORK_SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__tmux_reading_margin_work.sh"
  SOCKET_NAME="reading-margin-${BATS_TEST_NUMBER}-$$"
  MODE_FILE="${BATS_TEST_TMPDIR}/timeoff-mode"
  COMMAND_LOG="${BATS_TEST_TMPDIR}/margin-command"
  STATUS_LOG="${BATS_TEST_TMPDIR}/margin-status"
  tmux -L "$SOCKET_NAME" -f /dev/null new-session -d -s test -x 120 -y 30
  PANE_ID="$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_TIMEOFF_FILE "$MODE_FILE"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_WORK_COMMAND \
    "printf 'work\\n' > '$COMMAND_LOG'; exec sleep infinity"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_WEEKEND_COMMAND \
    "printf 'weekend\\n' > '$COMMAND_LOG'; exec sleep infinity"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE expanded
  tmux -L "$SOCKET_NAME" set-option -g @reading_margin_default on
}

@test "work margin renders prefix-g status before the vertical cockpit" {
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
  '#{pane_id}') printf '%%42\n' ;;
  '#{pane_width}') printf '%s\n' "${STUB_PANE_WIDTH:-72}" ;;
esac
EOF
  cat > "$bin_dir/status" <<'EOF'
#!/usr/bin/env bash
printf 'status session=%s pane=%s columns=%s\n' "$1" "$2" "$COLUMNS"
EOF
  cat > "$bin_dir/cockpit" <<'EOF'
#!/usr/bin/env bash
printf 'cockpit layout=%s width=%s\n' "$COCKPIT_LAYOUT" "$COCKPIT_VERTICAL_WIDTH"
EOF
  chmod +x "$bin_dir/tmux" "$bin_dir/status" "$bin_dir/cockpit"

  run env PATH="$bin_dir:$PATH" TMUX_PANE='%99' \
    TMUX_READING_MARGIN_FULL_STATUS_COMMAND="$bin_dir/status" \
    TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND="$bin_dir/cockpit" \
    "$WORK_SCRIPT" --render test '@7'

  [ "$status" -eq 0 ]
  [ "$output" = $'status session=test pane=%42 columns=72\n\ncockpit layout=vertical width=72' ]
}

@test "work margin wraps full status before the cockpit edge" {
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
  '#{pane_id}') printf '%%42\n' ;;
  '#{pane_width}') printf '97\n' ;;
esac
EOF
  cat > "$bin_dir/status" <<'EOF'
#!/usr/bin/env bash
printf 'status columns=%s\n' "$COLUMNS"
EOF
  cat > "$bin_dir/cockpit" <<'EOF'
#!/usr/bin/env bash
printf 'cockpit width=%s\n' "$COCKPIT_VERTICAL_WIDTH"
EOF
  chmod +x "$bin_dir/tmux" "$bin_dir/status" "$bin_dir/cockpit"

  run env PATH="$bin_dir:$PATH" TMUX_PANE='%99' \
    TMUX_READING_MARGIN_FULL_STATUS_COMMAND="$bin_dir/status" \
    TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND="$bin_dir/cockpit" \
    "$WORK_SCRIPT" --render test '@7'

  [ "$status" -eq 0 ]
  [ "$output" = $'status columns=80\n\ncockpit width=97' ]
}

teardown() {
  tmux -L "$SOCKET_NAME" kill-server 2>/dev/null || true
  if [[ -n "${ATTACHED_CLIENT_PID:-}" ]]; then
    wait "$ATTACHED_CLIENT_PID" 2>/dev/null || true
  fi
  if [[ "${CLIENT_FIFO_OPEN:-}" == 1 ]]; then exec 9>&-; fi
}

toggle_margin() {
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT '$PANE_ID'"
}

sync_margin() {
  window_id="$(tmux -L "$SOCKET_NAME" display-message -p '#{window_id}')"
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --sync-window '$window_id'"
}

attach_client_with_windowid() {
  client_fifo="${BATS_TEST_TMPDIR}/client-input"
  mkfifo "$client_fifo"
  exec 9<>"$client_fifo"
  CLIENT_FIFO_OPEN=1
  WINDOWID=42 TERM=xterm tmux -L "$SOCKET_NAME" -C attach -t test <&9 \
    >"${BATS_TEST_TMPDIR}/client.log" 2>&1 &
  ATTACHED_CLIENT_PID=$!
  for _ in {1..20}; do
    client_name="$(tmux -L "$SOCKET_NAME" list-clients -F '#{client_name}' 2>/dev/null | head -n 1)"
    [[ -n "$client_name" ]] && return 0
    sleep 0.05
  done
  return 1
}

wait_for_command() {
  for _ in {1..20}; do
    [ -s "$COMMAND_LOG" ] && return
    sleep 0.05
  done
  return 1
}

@test "reading margin toggles a left third without taking focus" {
  toggle_margin

  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_visible)" = on ]
  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 2 ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_left}')" -eq 0 ]
  margin_width="$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_width}')"
  [ "$margin_width" -ge 38 ]
  [ "$margin_width" -le 40 ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$PANE_ID" ]
  messages="$(tmux -L "$SOCKET_NAME" show-messages)"
  [[ "$messages" != *"Reading margin"* ]]

  toggle_margin

  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 1 ]
  [ -z "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)" ]
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_visible)" = off ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$PANE_ID" ]
  messages="$(tmux -L "$SOCKET_NAME" show-messages)"
  [[ "$messages" != *"Reading margin"* ]]
}

@test "layout changes restore the margin to one third in one pass" {
  toggle_margin
  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  tmux -L "$SOCKET_NAME" set-hook -g window-layout-changed \
    "run-shell -b \"$SCRIPT --repair-window '#{hook_window}'\""

  tmux -L "$SOCKET_NAME" resize-pane -t "$margin_id" -x 55
  for _ in {1..20}; do
    [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_width}')" -eq 39 ] && break
    sleep 0.05
  done

  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_width}')" -eq 39 ]
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_visible)" = on ]
}

@test "tiled Alacritty zooms the work pane and expanded Alacritty restores the margin" {
  toggle_margin
  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"

  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE tiled
  sync_margin

  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 1 ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$PANE_ID" ]
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_auto_zoomed)" = "$PANE_ID" ]
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)" = "$margin_id" ]
  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 2 ]

  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --status '$PANE_ID' > '$STATUS_LOG'"
  [[ "$(<"$STATUS_LOG")" == *"visible=off"*"hidden=tiled"* ]]

  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE expanded
  sync_margin

  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 0 ]
  [ -z "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_auto_zoomed)" ]
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)" = "$margin_id" ]
}

@test "display sync preserves a zoom the user started" {
  toggle_margin
  tmux -L "$SOCKET_NAME" resize-pane -Z -t "$PANE_ID"

  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE tiled
  sync_margin
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 1 ]
  [ -z "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_auto_zoomed)" ]

  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE expanded
  sync_margin
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 1 ]
}

@test "manual same-pane rezoom is not mistaken for automatic ownership" {
  toggle_margin
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE tiled
  sync_margin

  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --toggle-zoom '$PANE_ID'"
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --toggle-zoom '$PANE_ID'"
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 1 ]
  [ -z "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_auto_zoomed)" ]

  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE expanded
  sync_margin
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 1 ]
}

@test "display sync does not unzoom a pane the user selected after auto zoom" {
  toggle_margin
  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE tiled
  sync_margin

  tmux -L "$SOCKET_NAME" resize-pane -Z -t "$PANE_ID"
  tmux -L "$SOCKET_NAME" resize-pane -Z -t "$margin_id"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE expanded
  sync_margin

  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 1 ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$margin_id" ]
  [ -z "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_auto_zoomed)" ]
}

@test "overlapping display syncs keep zoom and ownership consistent" {
  toggle_margin
  window_id="$(tmux -L "$SOCKET_NAME" display-message -p '#{window_id}')"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE tiled

  for i in {1..20}; do
    tmux -L "$SOCKET_NAME" run-shell -b \
      "$SCRIPT --sync-window '$window_id'; tmux wait-for -S 'margin-tiled-$i'"
  done
  for i in {1..20}; do tmux -L "$SOCKET_NAME" wait-for "margin-tiled-$i"; done
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 1 ]
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_auto_zoomed)" = "$PANE_ID" ]

  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE expanded
  for i in {1..20}; do
    tmux -L "$SOCKET_NAME" run-shell -b \
      "$SCRIPT --sync-window '$window_id'; tmux wait-for -S 'margin-expanded-$i'"
  done
  for i in {1..20}; do tmux -L "$SOCKET_NAME" wait-for "margin-expanded-$i"; done
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 0 ]
  [ -z "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_auto_zoomed)" ]
}

@test "display sync reads Alacritty maximized state from X11" {
  toggle_margin
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/xprop" <<'EOF'
#!/usr/bin/env bash
printf '_NET_WM_STATE(ATOM) = %s\n' "$STUB_WM_STATE"
EOF
  chmod +x "$bin_dir/xprop"
  tmux -L "$SOCKET_NAME" set-environment -gu TMUX_READING_MARGIN_DISPLAY_STATE
  tmux -L "$SOCKET_NAME" set-environment -g PATH "$bin_dir:$PATH"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_X_WINDOW_ID 42

  tmux -L "$SOCKET_NAME" set-environment -g STUB_WM_STATE _NET_WM_STATE_FOCUSED
  sync_margin
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 1 ]

  tmux -L "$SOCKET_NAME" set-environment -g STUB_WM_STATE \
    '_NET_WM_STATE_MAXIMIZED_HORZ, _NET_WM_STATE_MAXIMIZED_VERT'
  sync_margin
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 0 ]
}

@test "ensure mode uses the exact attached client's X11 window" {
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  xprop_log="${BATS_TEST_TMPDIR}/xprop.log"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/xprop" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$XPROP_LOG"
printf '_NET_WM_STATE(ATOM) = %s\n' "$STUB_WM_STATE"
EOF
  chmod +x "$bin_dir/xprop"
  tmux -L "$SOCKET_NAME" set-environment -gu TMUX_READING_MARGIN_DISPLAY_STATE
  tmux -L "$SOCKET_NAME" set-environment -g PATH "$bin_dir:$PATH"
  tmux -L "$SOCKET_NAME" set-environment -g XPROP_LOG "$xprop_log"
  tmux -L "$SOCKET_NAME" set-environment -g STUB_WM_STATE _NET_WM_STATE_FOCUSED
  attach_client_with_windowid

  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --ensure-session test"

  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 1 ]
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_auto_zoomed)" = "$PANE_ID" ]
  grep -qF -- '-id 42 _NET_WM_STATE' "$xprop_log"
}

@test "tmux hooks sync the margin after outer-window size and session changes" {
  config="${BATS_TEST_DIRNAME}/../../.tmux.conf"
  grep -qF "set-hook -g client-resized" "$config"
  grep -qF -- "--sync-client \\\"#{hook_client}\\\"" "$config"
  grep -qF "set-hook -g client-session-changed" "$config"
  grep -qF "set-hook -g after-select-window" "$config"
  grep -qF -- "--toggle-client '#{client_name}' '#{pane_id}'" "$config"
  grep -qF -- "--toggle-zoom '#{pane_id}'" "$config"
}

@test "reading margin spans the window beside an existing split" {
  tmux -L "$SOCKET_NAME" split-window -v -t "$PANE_ID"
  split_pane_id="$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')"

  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT '$split_pane_id'"

  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_top}')" -eq 0 ]
  margin_height="$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_height}')"
  [ "$margin_height" -eq "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_height}')" ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$split_pane_id" ]
}

@test "reading margin recovers after its pane is closed elsewhere" {
  toggle_margin
  old_margin="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  tmux -L "$SOCKET_NAME" kill-pane -t "$old_margin"

  toggle_margin

  new_margin="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ -n "$new_margin" ]
  [ "$new_margin" != "$old_margin" ]
  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 2 ]
}

@test "reading margin shows the work view at work and playlist during time off" {
  toggle_margin
  wait_for_command
  [ "$(<"$COMMAND_LOG")" = work ]
  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_input_off}')" -eq 1 ]
  toggle_margin

  rm -f "$COMMAND_LOG"
  touch "$MODE_FILE"
  toggle_margin
  wait_for_command
  [ "$(<"$COMMAND_LOG")" = weekend ]
  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_input_off}')" -eq 0 ]
}

@test "ensure mode follows the global default knob" {
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --ensure-session test"
  first_margin="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ -n "$first_margin" ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$PANE_ID" ]

  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --ensure-session test"
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)" = "$first_margin" ]

  toggle_margin
  tmux -L "$SOCKET_NAME" set-option -g @reading_margin_default off
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --ensure-session test"
  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 1 ]
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_visible)" = off ]

  tmux -L "$SOCKET_NAME" new-session -d -s ambient_track_1a2b
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --ensure-session ambient_track_1a2b"
  [ "$(tmux -L "$SOCKET_NAME" list-panes -t ambient_track_1a2b -F '#{pane_id}' | wc -l)" -eq 1 ]
}

@test "status reports the default and current window state" {
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --status '$PANE_ID' > '$STATUS_LOG'"
  output="$(<"$STATUS_LOG")"
  [[ "$output" == *"default=on visible=off"* ]]

  toggle_margin
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --status '$PANE_ID' > '$STATUS_LOG'"
  output="$(<"$STATUS_LOG")"
  [[ "$output" == *"default=on visible=on"* ]]
  [[ "$output" == *"width=39"* ]]
}
