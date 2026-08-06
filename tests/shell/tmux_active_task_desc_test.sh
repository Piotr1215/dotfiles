#!/usr/bin/env bash
set -eo pipefail

# Test: the @agent_desc source in the tmux status writer.
#
# __tmux_active_task.sh resolves the status text right of the clock from the
# session name: a "-pr-<num>" name gives the PR title, a Linear id gives the
# issue description out of taskwarrior. An agent spawned by
# ~/.claude/scripts/__spawn_agent.sh from /ops-spawn-agent has neither, so its
# pane showed a bare clock. That spawn now writes a @agent_desc session option
# and this reads it.
#
# What must hold:
#   1. a set @agent_desc becomes the status prefix
#   2. it never displaces PR or Linear, which already worked
#   3. an unset one changes nothing
#   4. tmux format characters and newlines in the description cannot corrupt
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

# tmux stub: report $STUB_SESSION as the current session and $STUB_DESC as the
# value of any option asked for. printf, not echo, so a description containing
# backslashes is not mangled by the stub itself.
cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  display-message) printf '%s\n' "\$STUB_SESSION" ;;
  show-options)    printf '%s\n' "\$STUB_DESC" ;;
  *)               : ;;
esac
exit 0
EOF

# mpv is the source ranked below the description; silence it so a track playing
# on the real machine cannot decide the result.
printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/pgrep"

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
chmod +x "$BIN/tmux" "$BIN/pgrep" "$BIN/task"

# Run the writer for one session and return the cache line it produced.
render() {  # $1 = session name, $2 = @agent_desc value, $3 = taskwarrior desc
    local session="$1"
    rm -f "$CACHE"/* 2>/dev/null || true
    PATH="$BIN:$PATH" \
        TMUX_TASK_CACHE_DIR="$CACHE" \
        STUB_SESSION="$session" \
        STUB_DESC="${2-}" \
        STUB_TASK_DESC="${3-}" \
        "$SCRIPT" --update >/dev/null 2>&1 || true
    cat "$CACHE/${session//\//-}" 2>/dev/null || true
}

echo "Test: a spawn description becomes the status prefix"

line=$(render agent-status-bar "wiring the status bar")
assert_eq "description rendered" \
    "yes" "$([[ "$line" == "🤖 wiring the status bar | "* ]] && echo yes || echo no)"
assert_eq "clock kept" \
    "yes" "$([[ "$line" == *" | "*":"* ]] && echo yes || echo no)"

echo "Test: an unset description changes nothing"
# The whole point of ranking this source last: every session that rendered
# something before must render the same thing now.
line=$(render agent-status-bar "")
assert_eq "no prefix without the option" \
    "no" "$([[ "$line" == *"🤖"* ]] && echo yes || echo no)"
assert_eq "still falls through to the clock" \
    "yes" "$([[ "$line" == *":"* ]] && echo yes || echo no)"

echo "Test: a Linear issue still wins"
# devops-1191-ratelimit resolves through taskwarrior. The issue description is a
# live lookup and richer than a spawn-time label, so the label must not displace
# it even when both are present.
line=$(render devops-1191-ratelimit "wiring the status bar" "fix the rate limiter")
assert_eq "issue description wins over the label" \
    "yes" "$([[ "$line" == "📋 fix the rate limiter | "* ]] && echo yes || echo no)"

# ... but a name that only looks like an issue id, with nothing in taskwarrior
# behind it, must not swallow the label.
line=$(render worker-2-cleanup "wiring the status bar" "")
assert_eq "label used when the issue lookup finds nothing" \
    "yes" "$([[ "$line" == "🤖 wiring the status bar | "* ]] && echo yes || echo no)"

echo "Test: hostile descriptions cannot corrupt the status line"
# '#' opens a format substitution in a tmux status string and a newline would
# split the single-line cache entry the fast path cats verbatim.
line=$(render agent-status-bar "fix #{session_name} in #123")
assert_eq "format characters stripped" \
    "no" "$([[ "$line" == *"#"* ]] && echo yes || echo no)"

multiline=$(render agent-status-bar "first line
second line")
assert_eq "newline folded away" \
    "1" "$(printf '%s\n' "$multiline" | grep -c . || true)"

echo "Test: an over-long description is truncated"
long=$(render agent-status-bar "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
assert_eq "cut to the 60-char budget with an ellipsis" \
    "yes" "$([[ "$long" == *"aaa... | "* ]] && echo yes || echo no)"

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
