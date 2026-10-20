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
  # No visualizer unless a test asks for one, whether or not cava is installed.
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_VISUALIZER ''
  tmux -L "$SOCKET_NAME" set-option -g @reading_margin_default on
}

# Time-off mode with a stub visualizer that runs until it is signalled.
use_visualizer() {
  touch "$MODE_FILE"
  printf '#!/usr/bin/env bash\nexec sleep infinity\n' > "${BATS_TEST_TMPDIR}/visualizer"
  chmod +x "${BATS_TEST_TMPDIR}/visualizer"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_VISUALIZER "${BATS_TEST_TMPDIR}/visualizer"
}

wait_for_pane_count() {
  for _ in {1..40}; do
    [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq "$1" ] && return
    sleep 0.05
  done
  return 1
}

@test "work margin renders the vertical cockpit then the asks, with no status section" {
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
  '#{pane_width}') printf '%s\n' "${STUB_PANE_WIDTH:-72}" ;;
esac
EOF
  cat > "$bin_dir/cockpit" <<'EOF'
#!/usr/bin/env bash
printf 'cockpit layout=%s width=%s\n' "$COCKPIT_LAYOUT" "$COCKPIT_VERTICAL_WIDTH"
EOF
  cat > "$bin_dir/asks" <<'EOF'
#!/usr/bin/env bash
printf 'asks width=%s\n' "$TMUX_PIOTR_ASKS_WIDTH"
EOF
  chmod +x "$bin_dir/tmux" "$bin_dir/cockpit" "$bin_dir/asks"

  run env PATH="$bin_dir:$PATH" TMUX_PANE='%99' \
    TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND="$bin_dir/cockpit" \
    TMUX_READING_MARGIN_ASKS_COMMAND="$bin_dir/asks" \
    "$WORK_SCRIPT" --render test '@7'

  [ "$status" -eq 0 ]
  [ "$output" = $'cockpit layout=vertical width=72\n\nasks width=72' ]
}

@test "work margin passes a waiting-on-permission agent row through unchanged" {
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$bin_dir/tmux"
  cat > "$bin_dir/cockpit" <<'EOF'
#!/usr/bin/env bash
printf 'AGENT:   claude-tmux-kill-ask\nSTATUS:  waiting: permission 20m\n'
EOF
  chmod +x "$bin_dir/tmux" "$bin_dir/cockpit"

  run env PATH="$bin_dir:$PATH" TMUX_PANE='%99' \
    TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND="$bin_dir/cockpit" \
    TMUX_READING_MARGIN_ASKS_COMMAND="$bin_dir/absent" \
    "$WORK_SCRIPT" --render test '@7'

  [ "$status" -eq 0 ]
  [[ "$output" == *"STATUS:  waiting: permission 20m"* ]]
}

@test "work margin default cockpit command is the script that reads @agent_wait" {
  grep -q '@agent_wait' "$HOME/.claude/scripts/__cockpit_state.sh"
  [ -x "$HOME/.claude/scripts/__agent_wait.sh" ]
}

@test "cockpit gives each status its own colour" {
  script="$HOME/.claude/scripts/__cockpit_state.sh"
  fn="$(sed -n '/^status_color() {/,/^}/p' "$script")"
  defs="$(sed -n '/^c_hdr=/,/^c_alert=/p' "$script")"
  run bash -c "$defs; $fn
    for s in 'waiting: permission 20m' 'waiting: dialog' input blocked stalled live working ready 'in review' done idle; do
      printf '%s=%q\n' \"\$s\" \"\$(status_color \"\$s\")\"
    done"
  [ "$status" -eq 0 ]
  [[ "$output" == *"waiting: permission 20m=$'\\E[1;97;41m'"* ]]
  [[ "$output" == *"waiting: dialog=$'\\E[1;97;41m'"* ]]
  [[ "$output" == *"input=$'\\E[1;38;5;208m'"* ]]
  [[ "$output" == *"blocked=$'\\E[31m'"* ]]
  [[ "$output" == *"stalled=$'\\E[35m'"* ]]
  [[ "$output" == *"live=$'\\E[32m'"* ]]
  [[ "$output" == *"working=$'\\E[1;32m'"* ]]
  [[ "$output" == *"ready=$'\\E[36m'"* ]]
  [[ "$output" == *"in review=$'\\E[34m'"* ]]
  [[ "$output" == *"done=$'\\E[90m'"* ]]
  [[ "$output" == *"idle=$'\\E[33m'"* ]]
}

@test "cockpit colours avoid the sequences viddy drops" {
  # viddy reads a leading 0; as a reset that loses the colour, and ignores 7.
  run grep -E "^c_[a-z]+=.*\\\\033\[(0;|[0-9;]*;7[;m]|7[;m])" "$HOME/.claude/scripts/__cockpit_state.sh"
  [ "$status" -ne 0 ]
}

@test "cockpit detects an approval dialog from a captured screen" {
  script="$HOME/.claude/scripts/__cockpit_state.sh"
  fn="$(sed -n '/^screen_has_dialog() {/,/^}/p' "$script")"
  dialog=$' Bash command\n\n Hook PreToolUse:Bash requires confirmation for this command:\n rm outside /tmp and ~/.cache: /home/x (rm-gate on the toggle board)\n\n Do you want to proceed?\n ❯ 1. Yes\n   2. No\n\n Esc to cancel · Tab to amend\n'
  quoted="$dialog$(printf 'agent output line\n%.0s' $(seq 20))"
  run bash -c "$fn; printf '%s' \"\$1\" | screen_has_dialog" _ "$dialog"
  [ "$status" -eq 0 ]
  run bash -c "$fn; printf '%s' \"\$1\" | screen_has_dialog" _ "$quoted"
  [ "$status" -ne 0 ]
  run bash -c "$fn; printf '%s' 'just a shell prompt' | screen_has_dialog"
  [ "$status" -ne 0 ]
}

@test "agent_wait stamps a resume on a prompt and a set then clear leaves no wait" {
  bin_dir="${BATS_TEST_TMPDIR}/bin"; mkdir -p "$bin_dir"
  cat > "$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
state="$STUB_TMUX_STATE"
case "$1" in
  show-options) grep "^$5=" "$state" 2>/dev/null | head -1 | cut -d= -f2- ;;
  set-option)
    if [[ "$2" == -put ]]; then sed -i "/^$5=/d" "$state" 2>/dev/null || true
    else sed -i "/^$4=/d" "$state" 2>/dev/null || true; printf '%s=%s\n' "$4" "$5" >> "$state"; fi ;;
esac
EOF
  chmod +x "$bin_dir/tmux"
  : > "$BATS_TEST_TMPDIR/state"
  wait_sh="$HOME/.claude/scripts/__agent_wait.sh"
  env_=(env PATH="$bin_dir:$PATH" TMUX_PANE=%9 STUB_TMUX_STATE="$BATS_TEST_TMPDIR/state")
  printf '{"hook_event_name":"PermissionRequest"}' | "${env_[@]}" "$wait_sh" set
  grep -q '^@agent_wait=permission ' "$BATS_TEST_TMPDIR/state"
  printf '{"hook_event_name":"PostToolUse"}' | "${env_[@]}" "$wait_sh" clear
  ! grep -q '^@agent_wait=' "$BATS_TEST_TMPDIR/state"
  ! grep -q '^@agent_resumed=' "$BATS_TEST_TMPDIR/state"
  printf '{"hook_event_name":"UserPromptSubmit"}' | "${env_[@]}" "$wait_sh" clear
  grep -Eq '^@agent_resumed=[0-9]+$' "$BATS_TEST_TMPDIR/state"
}

@test "work margin skips the asks section when its command is absent" {
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
  '#{pane_width}') printf '97\n' ;;
esac
EOF
  cat > "$bin_dir/cockpit" <<'EOF'
#!/usr/bin/env bash
printf 'cockpit width=%s\n' "$COCKPIT_VERTICAL_WIDTH"
EOF
  chmod +x "$bin_dir/tmux" "$bin_dir/cockpit"

  run env PATH="$bin_dir:$PATH" TMUX_PANE='%99' \
    TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND="$bin_dir/cockpit" \
    TMUX_READING_MARGIN_ASKS_COMMAND="$bin_dir/absent" \
    "$WORK_SCRIPT" --render test '@7'

  [ "$status" -eq 0 ]
  [ "$output" = 'cockpit width=97' ]
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
  # Both modes now accept input. Work mode used to be -d; that dropped every
  # keystroke before viddy saw it, leaving the asks section unscrollable.
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_input_off}')" -eq 0 ]
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

@test "a window in the skip list never gets a margin" {
  tmux -L "$SOCKET_NAME" rename-window -t test todo
  tmux -L "$SOCKET_NAME" set-option -g @reading_margin_skip_windows 'other:main test:todo'

  toggle_margin
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --ensure-session test"
  sync_margin
  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 1 ]
  [ -z "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)" ]

  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --status '$PANE_ID' > '$STATUS_LOG'"
  [[ "$(<"$STATUS_LOG")" == *"skipped"*"(test:todo)"* ]]

  tmux -L "$SOCKET_NAME" split-window -d
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --toggle-zoom '$PANE_ID'"
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_zoomed_flag}')" -eq 1 ]
  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 2 ]
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

@test "work margin accepts input so its viddy pane can scroll" {
  # Regression: the work branch used select-pane -d, so tmux dropped every
  # keystroke before viddy saw it. The pane looked frozen and the only
  # available diagnosis was "viddy cannot scroll", which is false. The asks
  # section at the bottom is longer than the pane, so scrolling is required.
  toggle_margin
  margin="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ -n "$margin" ]
  run tmux -L "$SOCKET_NAME" display-message -p -t "$margin" '#{pane_input_off}'
  [ "$output" = "0" ]
}

@test "repair re-enables input on a margin created before the fix" {
  # Creation-time flags do not apply retroactively, so a long-lived pane stayed
  # unscrollable with no visible cause. Repair must heal it in place rather
  # than requiring a toggle off and on.
  toggle_margin
  margin="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  window="$(tmux -L "$SOCKET_NAME" display-message -p '#{window_id}')"
  tmux -L "$SOCKET_NAME" select-pane -d -t "$margin"
  run tmux -L "$SOCKET_NAME" display-message -p -t "$margin" '#{pane_input_off}'
  [ "$output" = "1" ]
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --repair-window '$window'"
  run tmux -L "$SOCKET_NAME" display-message -p -t "$margin" '#{pane_input_off}'
  [ "$output" = "0" ]
}

@test "repair exits clean when its window closes mid-run" {
  # Layout hooks run in the background, so a window can close between the
  # script's first lookup and a later write. tmux printed each such run as
  # "returned 1" into whatever pane the user was looking at.
  window="$(tmux -L "$SOCKET_NAME" new-window -dP -F '#{window_id}')"
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/tmux" <<STUB
#!/usr/bin/env bash
$(command -v tmux) -L "$SOCKET_NAME" "\$@"; rc=\$?
$(command -v tmux) -L "$SOCKET_NAME" kill-window -t "$window" 2>/dev/null
exit \$rc
STUB
  chmod +x "$bin_dir/tmux"

  run env PATH="$bin_dir:$PATH" "$SCRIPT" --repair-window "$window"

  [ "$status" -eq 0 ]
  [ "$(tmux -L "$SOCKET_NAME" list-windows -F '#{window_id}' | grep -c "^$window\$")" -eq 0 ]
}

@test "time-off margin stacks a visualizer under the picker" {
  use_visualizer
  toggle_margin

  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  visualizer_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_visualizer_pane)"
  [ -n "$visualizer_id" ]
  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 3 ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$visualizer_id" '#{pane_left}')" -eq 0 ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$visualizer_id" '#{pane_top}')" -gt 0 ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$visualizer_id" '#{pane_input_off}')" -eq 0 ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$visualizer_id" '#{pane_title}')" = 'cava  f/b colors  ↑↓ sensitivity  ←→ bars  q quit' ]
  margin_height="$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_height}')"
  visualizer_height="$(tmux -L "$SOCKET_NAME" display-message -p -t "$visualizer_id" '#{pane_height}')"
  [ "$margin_height" -gt "$visualizer_height" ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$PANE_ID" ]
}

@test "work margin never gets a visualizer" {
  use_visualizer
  rm -f "$MODE_FILE"
  toggle_margin

  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 2 ]
  [ -z "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_visualizer_pane)" ]
}

@test "toggling the margin off takes the visualizer with it" {
  use_visualizer
  toggle_margin
  wait_for_pane_count 3
  toggle_margin

  wait_for_pane_count 1
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$PANE_ID" ]
}

@test "the visualizer ends when the picker exits on its own" {
  use_visualizer
  toggle_margin
  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  wait_for_pane_count 3

  tmux -L "$SOCKET_NAME" send-keys -t "$margin_id" C-c
  wait_for_pane_count 1
}

@test "tiled auto zoom never picks the visualizer" {
  use_visualizer
  toggle_margin
  visualizer_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_visualizer_pane)"
  [ -n "$visualizer_id" ]
  tmux -L "$SOCKET_NAME" select-pane -t "$visualizer_id"

  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE tiled
  sync_margin

  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_auto_zoomed)" = "$PANE_ID" ]
}
