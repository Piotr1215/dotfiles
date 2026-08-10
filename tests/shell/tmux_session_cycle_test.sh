#!/usr/bin/env bash
set -euo pipefail

# Delegated agent sessions stay in tmux and explicit selectors, but the normal
# M-PageUp/PageDown cycle skips them. A delegated current session remains in the
# cycle so an explicit jump into one never traps the user there.

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

echo "== normal cycling skips delegated sessions =="
assert_eq "next skips a delegated worker" "regular-b" \
    "$(cycle regular-a 'regular-a delegated-a regular-b' delegated-a)"
assert_eq "previous skips a delegated worker" "regular-a" \
    "$(cycle regular-b 'regular-a delegated-a regular-b' delegated-a prev)"

echo "== cycling from a delegated session still works =="
sessions='regular-a delegated-a delegated-b regular-b'
delegated='delegated-a delegated-b'
assert_eq "next leaves the current delegated worker" "regular-b" \
    "$(cycle delegated-a "$sessions" "$delegated")"
assert_eq "previous leaves the current delegated worker" "regular-a" \
    "$(cycle delegated-a "$sessions" "$delegated" prev)"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
