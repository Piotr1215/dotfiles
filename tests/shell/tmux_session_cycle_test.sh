#!/usr/bin/env bash
set -euo pipefail

# Agent sessions from /ops-spawn-agent carry @agent_spawn_level=delegated. The
# M-PageUp/PageDown cycle used to skip them, so it and M-i walked different
# sets; now it visits them in tmux order like any other session. Passive
# sessions (relax) are still skipped unless cycling starts there.

SCRIPT="$HOME/dev/dotfiles/scripts/__cycle_tmux_session.sh"
T=$(mktemp -d)
BIN="$T/bin"
SWITCH_LOG="$T/switch.log"
mkdir -p "$BIN"
trap 'rm -rf "$T"' EXIT

cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '%s\n' "$STUB_CURRENT"
    ;;
  list-sessions)
    for session in $STUB_SESSIONS; do
      printf '%s\n' "$session"
    done
    ;;
  list-panes)
    printf '%%1\n'
    ;;
  show-options)
    target=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "-t" ]]; then
        target="$2"
        break
      fi
      shift
    done
    if [[ " $STUB_DELEGATED " == *" $target "* ]]; then
      printf 'delegated\n'
    fi
    ;;
  switch-client)
    printf '%s\n' "${@: -1}" > "$STUB_SWITCH_LOG"
    ;;
esac
EOF
chmod +x "$BIN/tmux"

PASS=0
FAIL=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$label"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL: %s\n    expected: %s\n    actual:   %s\n' \
            "$label" "$expected" "$actual"
    fi
}

cycle() {
    local current="$1" sessions="$2" delegated="$3" direction="${4:-next}"
    : > "$SWITCH_LOG"
    STUB_CURRENT="$current" \
    STUB_SESSIONS="$sessions" \
    STUB_DELEGATED="$delegated" \
    STUB_SWITCH_LOG="$SWITCH_LOG" \
    PATH="$BIN:$PATH" \
        bash "$SCRIPT" "$direction"
    cat "$SWITCH_LOG"
}

echo "== normal cycling visits delegated sessions =="
assert_eq "next lands on a delegated worker" "delegated-a" \
    "$(cycle regular-a 'regular-a delegated-a regular-b' delegated-a)"
assert_eq "previous lands on a delegated worker" "delegated-a" \
    "$(cycle regular-b 'regular-a delegated-a regular-b' delegated-a prev)"

echo "== cycling between delegated sessions =="
sessions='regular-a delegated-a delegated-b regular-b'
delegated='delegated-a delegated-b'
assert_eq "next steps to the next delegated worker" "delegated-b" \
    "$(cycle delegated-a "$sessions" "$delegated")"
assert_eq "previous steps back to the regular session" "regular-a" \
    "$(cycle delegated-a "$sessions" "$delegated" prev)"

echo "== passive sessions are still skipped =="
assert_eq "next skips relax" "regular-b" \
    "$(cycle regular-a 'regular-a relax regular-b' '')"
assert_eq "cycling out of relax still works" "regular-b" \
    "$(cycle relax 'regular-a relax regular-b' '')"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
