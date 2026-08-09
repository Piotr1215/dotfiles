#!/usr/bin/env bash
set -eo pipefail

# Test: pane goals in the tmux status writer.
#
# __tmux_active_task.sh resolves the status text right of the clock from a PR
# title, a Linear issue description, or the active pane's @claude_goal. Spawned
# panes receive that goal before launch, and recap hooks replace it later.
#
# What must hold:
#   1. a set @claude_goal becomes the status prefix
#   2. it never displaces PR or Linear, which already worked
#   3. an unset goal changes nothing
#   4. tmux format characters and newlines in the goal cannot corrupt
#      the single-line cache entry the status bar cats
#
# Hermetic: tmux, task and pgrep are stubbed and the cache is redirected, so no
# real session, taskwarrior database or status cache is touched.

SCRIPT="$HOME/dev/dotfiles/scripts/__tmux_active_task.sh"

PASS=0
FAIL=0
T=$(mktemp -d)
BIN="$T/bin"
CACHE="$T/cache"
mkdir -p "$BIN" "$CACHE"
trap 'rm -rf "$T"' EXIT

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1)); printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s\n    expected: %s\n    actual:   %s\n" "$label" "$expected" "$actual"
    fi
}

# tmux stub: distinguish the session-name, pane-goal and global length lookups.
cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  display-message)
    case "\${*: -1}" in
      '#S') printf '%s\n' "\$STUB_SESSION" ;;
      '#{@claude_goal}') printf '%s\n' "\$STUB_GOAL" ;;
    esac
    ;;
  show-options)
    case "\${*: -1}" in
      status-right-length) printf '140\n' ;;
      @agent_desc) printf '%s\n' "\$STUB_DESC" ;;
    esac
    ;;
  *)               : ;;
esac
exit 0
EOF

# taskwarrior stub: $STUB_TASK_DESC is what the Linear lookup finds, empty means
# no such task.
cat > "$BIN/task" <<EOF
#!/usr/bin/env bash
if [ -n "\$STUB_TASK_DESC" ]; then
  printf '[{"description":"%s"}]\n' "\$STUB_TASK_DESC"
else
  printf '[]\n'
fi
EOF
chmod +x "$BIN/tmux" "$BIN/task"

# Run the writer for one session and return the cache line it produced.
render() {  # $1 session, $2 task desc, $3 @claude_goal, $4 legacy @agent_desc
    local session="$1"
    rm -f "$CACHE"/* 2>/dev/null || true
    PATH="$BIN:$PATH" \
        TMUX_TASK_CACHE_DIR="$CACHE" \
        STUB_SESSION="$session" \
        STUB_TASK_DESC="${2-}" \
        STUB_GOAL="${3-}" \
        STUB_DESC="${4-}" \
        "$SCRIPT" --update >/dev/null 2>&1 || true
    cat "$CACHE/${session//\//-}" 2>/dev/null || true
}

echo "Test: a pane goal becomes the status prefix"

line=$(render agent-status-bar "" "wiring the status bar")
assert_eq "goal rendered" \
    "yes" "$([[ "$line" == "🤖 wiring the status bar | "* ]] && echo yes || echo no)"
assert_eq "clock kept" \
    "yes" "$([[ "$line" == *" | "*":"* ]] && echo yes || echo no)"

echo "Test: the retired static description cannot hide the pane goal"
line=$(render agent-status-bar "" "current pane goal" "dead static description")
assert_eq "goal wins even if a legacy option exists" \
    "yes" "$([[ "$line" == "🤖 current pane goal | "* ]] && echo yes || echo no)"

echo "Test: an unset goal changes nothing"
line=$(render agent-status-bar "" "")
assert_eq "no prefix without the goal" \
    "no" "$([[ "$line" == *"🤖"* ]] && echo yes || echo no)"
assert_eq "still falls through to the clock" \
    "yes" "$([[ "$line" == *":"* ]] && echo yes || echo no)"

echo "Test: a Linear issue still wins"
# devops-1191-ratelimit resolves through taskwarrior. The issue description is a
# live lookup and richer than the pane goal, so the goal must not displace
# it even when both are present.
line=$(render devops-1191-ratelimit "fix the rate limiter" "wiring the status bar")
assert_eq "issue description wins over the goal" \
    "yes" "$([[ "$line" == "📋 fix the rate limiter | "* ]] && echo yes || echo no)"

# A name that only looks like an issue id, with nothing in taskwarrior behind
# it, must not swallow the pane goal.
line=$(render worker-2-cleanup "" "wiring the status bar")
assert_eq "goal used when the issue lookup finds nothing" \
    "yes" "$([[ "$line" == "🤖 wiring the status bar | "* ]] && echo yes || echo no)"

echo "Test: hostile goals cannot corrupt the status line"
# '#' opens a format substitution in a tmux status string and a newline would
# split the single-line cache entry the fast path cats verbatim.
line=$(render agent-status-bar "" "fix #{session_name} in #123")
assert_eq "format characters stripped" \
    "no" "$([[ "$line" == *"#"* ]] && echo yes || echo no)"

multiline=$(render agent-status-bar "" "first line
second line")
assert_eq "newline folded away" \
    "1" "$(printf '%s\n' "$multiline" | grep -c . || true)"

echo "Test: an over-long goal is truncated"
long=$(render agent-status-bar "" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
assert_eq "cut to the 60-char budget with an ellipsis" \
    "yes" "$([[ "$long" == *"aaa... | "* ]] && echo yes || echo no)"

echo "Test: a busy cache lock gets one eventual retry"
LOCK_FILE="$T/update.lock"
exec 9>"$LOCK_FILE"
flock 9
rm -f "$CACHE/agent-status-bar"
PATH="$BIN:$PATH" \
    TMUX_TASK_CACHE_DIR="$CACHE" \
    TMUX_TASK_LOCK_FILE="$LOCK_FILE" \
    STUB_SESSION=agent-status-bar \
    STUB_TASK_DESC="" \
    STUB_GOAL="retry the summarized goal" \
    "$SCRIPT" --update >/dev/null 2>&1 || true
assert_eq "the held test lock blocks the first writer" \
    "yes" "$([[ ! -e "$CACHE/agent-status-bar" ]] && echo yes || echo no)"
flock -u 9
for _ in $(seq 1 30); do
    [[ -r "$CACHE/agent-status-bar" ]] && break
    sleep 0.1
done
line=$(cat "$CACHE/agent-status-bar" 2>/dev/null || true)
assert_eq "the retry writes the missed cache update" \
    "yes" "$([[ "$line" == "🤖 retry the summarized goal | "* ]] && echo yes || echo no)"

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
