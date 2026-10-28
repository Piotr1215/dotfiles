#!/usr/bin/env bash
# Exercise the live margin only on an isolated tmux server and task database.
set -euo pipefail
repo=${DOTFILES_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
actual_cockpit="$HOME/.claude/scripts/__cockpit_state.sh"
real_claude_scripts="$HOME/.claude/scripts"
tmux_bin=$(command -v tmux)
export TMUX_BIN="$tmux_bin"
root=$(mktemp -d /tmp/mm-margin-test.XXXXXX)
socket="margin-regression-$$-$RANDOM"
# Remove only the private server created by this test, never the default server.
cleanup() { "$tmux_bin" -L "$socket" kill-server 2>/dev/null || true; }
trap cleanup EXIT
mkdir -p "$root/bin" "$root/home/.claude" "$root/cache" "$root/proc"
ln -s "$real_claude_scripts" "$root/home/.claude/scripts"
export HOME="$root/home" XDG_CACHE_HOME="$root/cache" XDG_RUNTIME_DIR="$root/cache" TASKRC="$root/taskrc"
export PATH="$root/bin:$PATH" TEST_SOCKET="$socket" COCKPIT_PROC_DIR="$root/proc"
cat > "$root/bin/tmux" <<'WRAPPER'
#!/usr/bin/env bash
exec "$TMUX_BIN" -L "$TEST_SOCKET" "$@"
WRAPPER
cat > "$root/bin/pgrep" <<'PGREP'
#!/usr/bin/env bash
[[ ${2:-} == codex ]] && cat "$COCKPIT_PROC_DIR/agents" || :
PGREP
cat > "$root/bin/task" <<'TASK'
#!/usr/bin/env bash
printf '[]\n'
TASK
cat > "$root/focus" <<'FOCUS'
#!/usr/bin/env bash
printf 'focus width=%s\n' "$3"
FOCUS
cat > "$root/cockpit" <<'COCKPIT'
#!/usr/bin/env bash
[[ ! -f "$HOME/fail" ]] || exit 1
printf 'board width=%s roster=%s cache=%s\n' "$COCKPIT_VERTICAL_WIDTH" "$(cat "$HOME/roster")" "${COCKPIT_CACHE:-1}"
COCKPIT
chmod +x "$root/bin/"* "$root/focus" "$root/cockpit"
tmux -f /dev/null new-session -d -s margin -x 100 -y 30
pane=$(tmux display-message -p '#{pane_id}')
export TMUX_PANE="$pane" TMUX_READING_MARGIN_FOCUS_COMMAND="$root/focus" TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND="$root/cockpit"
# Run one draw against the private pane's current dimensions.
render() { bash "${MARGIN_WORK_UNDER_TEST:-$repo/scripts/__tmux_reading_margin_work.sh}" --cached-render margin @0; }
# Fail with the actual frame when a required value is absent.
assert_has() { [[ "$1" == *"$2"* ]] || { printf 'missing %q in: %s\n' "$2" "$1" >&2; exit 1; }; }
# Reject a stale roster value or placeholder in the new frame.
assert_not() { [[ "$1" != *"$2"* ]] || { printf 'unexpected %q in: %s\n' "$2" "$1" >&2; exit 1; }; }
printf 'alpha' > "$HOME/roster"
out=$(render); assert_has "$out" 'board width=100 roster=alpha cache=0'; assert_not "$out" 'Loading cockpit'; printf 'ok 1 - first render\n'
tmux resize-window -t margin -x 60
out=$(render); assert_has "$out" 'focus width=60'; assert_has "$out" 'board width=60 roster=alpha cache=0'; printf 'ok 2 - resize\n'
printf 'beta' > "$HOME/roster"
out=$(render); assert_has "$out" 'roster=beta'; assert_not "$out" 'roster=alpha'; printf 'ok 3 - fresh roster\n'
touch "$HOME/fail"
out=$(render || :); assert_not "$out" 'roster=beta'; printf 'ok 4 - failure avoids stale roster\n'
export TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND="$actual_cockpit" COCKPIT_CACHE=0
# Link a deterministic interactive-process fixture to a real private pane.
fixture() {
  local target="$1" pid="$2" name="$3" ppid
  ppid=$(tmux display-message -p -t "$target" '#{pane_pid}')
  tmux set-option -p -t "$target" @agent_name "$name"
  mkdir -p "$COCKPIT_PROC_DIR/$pid"
  printf 'codex\0--model\0test\0' > "$COCKPIT_PROC_DIR/$pid/cmdline"
  printf '%s (codex) S %s 0 0 0\n' "$pid" "$ppid" > "$COCKPIT_PROC_DIR/$pid/stat"
  printf '%s\n' "$pid" >> "$COCKPIT_PROC_DIR/agents"
}
: > "$COCKPIT_PROC_DIR/agents"
fixture "$pane" 900001 alpha
tmux set-option -p -t "$pane" @claude_state working
tmux set-option -p -t "$pane" @agent_model 'codex · snapshot-model'
tmux set-option -p -t "$pane" @agent_prs 'loft-sh/repo#123'
tmux resize-window -t margin -x 23
out=$(render); assert_has "$out" 'alpha'; assert_not "$out" 'Loading cockpit'; printf 'ok 5 - narrow roster\n'
tmux resize-window -t margin -x 100
second=$(tmux split-window -h -P -F '#{pane_id}' -t "$pane" 'sleep 300')
fixture "$second" 900002 beta
out=$(render); assert_has "$out" 'alpha'; assert_has "$out" 'beta'; printf 'ok 6 - added pane\n'
assert_has "$out" 'working'
assert_has "$out" 'snapshot-model'
assert_has "$out" 'repo#123'
tmux kill-pane -t "$second"
out=$(render); assert_has "$out" 'alpha'; assert_not "$out" 'beta'; printf 'ok 7 - removed pane\n'
# Start the real refresh loop, retaining a logical line to test narrow and wide
# redraws. The runner sets all test paths explicitly.
cat > "$root/short-cockpit" <<'SHORT'
#!/usr/bin/env bash
printf 'LATEST:  alpha beta gamma delta epsilon\n'
SHORT
chmod +x "$root/short-cockpit"
cat > "$root/runner" <<RUNNER
#!/usr/bin/env bash
export HOME='$HOME' XDG_CACHE_HOME='$XDG_CACHE_HOME' XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' TASKRC='$TASKRC'
export PATH='$PATH' TEST_SOCKET='$TEST_SOCKET' TMUX_BIN='$TMUX_BIN'
export TMUX_READING_MARGIN_FOCUS_COMMAND='$root/focus' TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND='$root/short-cockpit'
exec '$repo/scripts/__tmux_reading_margin_work.sh' margin
RUNNER
chmod +x "$root/runner"
tmux new-window -d -t margin -n viddy "$root/runner"
tmux resize-window -t margin:viddy -x 60 -y 30
viddy_pane=$(tmux list-panes -t margin:viddy -F '#{pane_id}')
# Wait for the actual viewer to paint a frame at the new pane width.
wait_frame() {
  local expected="$1" frame
  for _ in {1..100}; do
    frame=$(tmux capture-pane -p -t "$viddy_pane")
    if [[ "$frame" == *"$expected"* ]]; then
      assert_not "$frame" 'Loading cockpit'
      return 0
    fi
    sleep 0.05
  done
  printf 'frame never contained %q: %s\n' "$expected" "$frame" >&2
  return 1
}
wait_frame 'LATEST:  alpha beta gamma delta epsilon'
tmux resize-window -t margin:viddy -x 23
wait_frame 'LATEST:  alpha beta'
tmux resize-window -t margin:viddy -x 60
wait_frame 'LATEST:  alpha beta gamma delta epsilon'
printf 'ok 8 - refresh loop reflows after resize\n'
printf '8 margin regression checks passed\n'
