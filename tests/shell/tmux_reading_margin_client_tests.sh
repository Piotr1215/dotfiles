#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
margin_script="$script_dir/../../scripts/__tmux_toggle_reading_margin.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/reading-margin-client.XXXXXX")"
tmux_bin="$(command -v tmux)"
client_pid=""

# Keep every test command finite so its private server exits without a kill.
cleanup() {
  for _ in {1..300}; do
    if ! test_tmux has-session 2>/dev/null; then
      if [[ -n "$client_pid" ]]; then wait "$client_pid" 2>/dev/null || true; fi
      rm -rf -- "$test_dir"
      return 0
    fi
    sleep 0.1
  done
  printf 'FAIL: finite test panes did not exit; inspect %s\n' "$test_dir" >&2
  return 1
}
trap cleanup EXIT

# Always address the disposable server, including when run inside live tmux.
test_tmux() {
  "$tmux_bin" -S "$test_dir/socket" "$@"
}

# Report the failed state along with the check that expected it.
assert_equal() {
  if [[ "$1" != "$2" ]]; then
    printf 'FAIL: %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    exit 1
  fi
}

content_pane="$(test_tmux -f /dev/null new-session -d -P -F '#{pane_id}' -s attached -x 120 -y 30 'exec sleep 20')"
content_window="$(test_tmux display-message -p -t "$content_pane" '#{window_id}')"
test_tmux set-environment -g TMUX_READING_MARGIN_TIMEOFF_FILE "$test_dir/no-timeoff"
test_tmux set-environment -g TMUX_READING_MARGIN_WORK_COMMAND 'exec sleep 20'
test_tmux set-environment -g TMUX_READING_MARGIN_VISUALIZER ''
test_tmux set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE expanded
test_tmux run-shell -t "$content_pane" "\"$margin_script\" '$content_pane'"
margin_pane="$(test_tmux show-options -wqv -t "$content_window" @reading_margin_pane)"
caller_pane="$(test_tmux new-session -d -P -F '#{pane_id}' -s caller 'exec sleep 20')"

mkfifo "$test_dir/client-input"
exec 9<>"$test_dir/client-input"
WINDOWID=42 TERM=xterm script -q -c \
  "\"$tmux_bin\" -S '$test_dir/socket' attach-session -t '=attached'" \
  /dev/null <&9 >"$test_dir/client.log" 2>&1 &
client_pid=$!
client_name=""
for _ in {1..40}; do
  client_name="$(test_tmux list-clients -F '#{client_name}')"
  [[ -n "$client_name" ]] && break
  sleep 0.025
done
[[ -n "$client_name" ]]

# A hook may inherit another pane. The client must supply the pane context.
test_tmux set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE tiled
test_tmux run-shell -t "$caller_pane" "TMUX_PANE='$caller_pane' \"$margin_script\" --sync-client '$client_name'"
assert_equal "$(test_tmux display-message -p -t "$content_window" '#{window_zoomed_flag}')" 1 'attached window hides its margin'
assert_equal "$(test_tmux show-options -wqv -t "$content_window" @reading_margin_auto_zoomed)" "$content_pane" 'automatic zoom belongs to attached content'
assert_equal "$(test_tmux display-message -p -t "$caller_pane" '#{window_zoomed_flag}')" 0 'caller window stays unchanged'

# Exercise actual WINDOWID discovery and the fullscreen atom on restoration.
mkdir "$test_dir/bin"
cat >"$test_dir/bin/xprop" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == '-id 42 _NET_WM_STATE' ]] || exit 1
cat "$STUB_WM_STATE_FILE"
EOF
chmod +x "$test_dir/bin/xprop"
printf '_NET_WM_STATE(ATOM) = _NET_WM_STATE_FULLSCREEN\n' >"$test_dir/wm-state"
test_tmux set-environment -g PATH "$test_dir/bin:$PATH"
test_tmux set-environment -g STUB_WM_STATE_FILE "$test_dir/wm-state"
test_tmux set-environment -gu TMUX_READING_MARGIN_DISPLAY_STATE
test_tmux set-environment -gu TMUX_READING_MARGIN_X_WINDOW_ID
test_tmux run-shell -t "$caller_pane" "TMUX_PANE='$caller_pane' \"$margin_script\" --sync-client '$client_name'"
assert_equal "$(test_tmux display-message -p -t "$content_window" '#{window_zoomed_flag}')" 0 'fullscreen restores attached margin'
assert_equal "$(test_tmux show-options -wqv -t "$content_window" @reading_margin_auto_zoomed)" '' 'fullscreen clears automatic ownership'
assert_equal "$(test_tmux show-options -wqv -t "$content_window" @reading_margin_pane)" "$margin_pane" 'fullscreen preserves the original margin'

# Half-screen -> maximized must restore it through the real resize hook.
test_tmux set-hook -g client-resized \
  "run-shell -b \"$margin_script --sync-client \\\"#{hook_client}\\\"; tmux wait-for -S margin-resized\""
printf '_NET_WM_STATE(ATOM) = _NET_WM_STATE_FOCUSED\n' >"$test_dir/wm-state"
stty -F "$client_name" cols 70 rows 30
timeout 5 "$tmux_bin" -S "$test_dir/socket" wait-for margin-resized
assert_equal "$(test_tmux display-message -p -t "$content_window" '#{window_zoomed_flag}')" 1 'half-screen resize hides the margin'
assert_equal "$(test_tmux show-options -wqv -t "$content_window" @reading_margin_auto_zoomed)" "$content_pane" 'half-screen resize records automatic ownership'
printf '_NET_WM_STATE(ATOM) = _NET_WM_STATE_MAXIMIZED_HORZ, _NET_WM_STATE_MAXIMIZED_VERT\n' >"$test_dir/wm-state"
stty -F "$client_name" cols 140 rows 30
timeout 5 "$tmux_bin" -S "$test_dir/socket" wait-for margin-resized
for _ in {1..40}; do
  [[ "$(test_tmux display-message -p -t "$content_window" '#{window_zoomed_flag}')" == 0 ]] && break
  sleep 0.025
done
assert_equal "$(test_tmux display-message -p -t "$content_window" '#{window_zoomed_flag}')" 0 'maximized resize restores the margin'
assert_equal "$(test_tmux show-options -wqv -t "$content_window" @reading_margin_auto_zoomed)" '' 'resize hook clears automatic ownership'
assert_equal "$(test_tmux show-options -wqv -t "$content_window" @reading_margin_pane)" "$margin_pane" 'resize hook preserves the original margin'

# Expansion must leave a zoom the user started alone.
test_tmux run-shell -t "$content_pane" "\"$margin_script\" --toggle-zoom '$content_pane'"
assert_equal "$(test_tmux display-message -p -t "$content_window" '#{window_zoomed_flag}')" 1 'manual zoom starts on the content pane'
test_tmux run-shell -t "$caller_pane" "TMUX_PANE='$caller_pane' \"$margin_script\" --sync-client '$client_name'"
assert_equal "$(test_tmux display-message -p -t "$content_window" '#{window_zoomed_flag}')" 1 'manual zoom stays owned by the user'
test_tmux run-shell -t "$content_pane" "\"$margin_script\" --toggle-zoom '$content_pane'"

# A vanished client must not fall back to whichever pane invoked the hook.
test_tmux set-environment -g TMUX_READING_MARGIN_DISPLAY_STATE tiled
test_tmux run-shell -t "$caller_pane" "TMUX_PANE='$caller_pane' \"$margin_script\" --sync-client 'missing-client'"
assert_equal "$(test_tmux display-message -p -t "$content_window" '#{window_zoomed_flag}')" 0 'missing client is a no-op'
trap - EXIT
cleanup
printf 'PASS: client sync targets the attached window and restores fullscreen margins\n'
