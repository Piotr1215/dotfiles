#!/usr/bin/env bash
# Covers __tmux_full_status.sh with tmux, gh, task and jq stubbed, so the
# precedence and the arithmetic are exercised with no live server.
#
# The point of the inspector is that it reports what the bar DROPPED, so the
# cases that matter are: which source won, and how many characters were lost.
set -uo pipefail

SCRIPT="$HOME/dev/dotfiles/scripts/__tmux_full_status.sh"
PASS=0
FAIL=0
T=$(mktemp -d)
BIN="$T/bin"
CACHE="$T/cache"
mkdir -p "$BIN" "$CACHE"
trap 'rm -rf "$T"' EXIT

assert_has() {
    local label="$1" needle="$2" hay="$3"
    if printf '%s' "$hay" | grep -qF -- "$needle"; then
        PASS=$((PASS + 1)); printf "  PASS: %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s\n    wanted to find: %s\n" "$label" "$needle"
    fi
}

assert_lacks() {
    local label="$1" needle="$2" hay="$3"
    if printf '%s' "$hay" | grep -qF -- "$needle"; then
        FAIL=$((FAIL + 1)); printf "  FAIL: %s\n    should not contain: %s\n" "$label" "$needle"
    else
        PASS=$((PASS + 1)); printf "  PASS: %s\n" "$label"
    fi
}

# tmux stub: status-right-length, @agent_desc and @claude_goal come from env so
# each case can set them independently.
cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
  show-options)
    for a in "\$@"; do
      [ "\$a" = "status-right-length" ] && { printf '%s\n' "\${STUB_LIMIT:-140}"; exit 0; }
      [ "\$a" = "@agent_desc" ] && { printf '%s\n' "\${STUB_DESC:-}"; exit 0; }
    done
    printf '\n' ;;
  display-message)
    for a in "\$@"; do
      case "\$a" in
        '#{@claude_goal}') printf '%s\n' "\${STUB_GOAL:-}"; exit 0 ;;
        '#{@claude_label}') printf '%s\n' "\${STUB_LABEL:-}"; exit 0 ;;
      esac
    done
    printf '\n' ;;
  *) : ;;
esac
exit 0
EOF

# gh and task absent by default; a case that wants them provides its own stub.
chmod +x "$BIN/tmux"

run() {
    PATH="$BIN:$PATH" TMUX_TASK_CACHE_DIR="$CACHE" COLUMNS=100 \
        bash "$SCRIPT" "$1" '%9' 2>&1
}

echo "== a long goal reports how much the bar dropped"
rm -f "$CACHE"/*
STUB_GOAL="$(printf 'g%.0s' {1..280})" out=$(STUB_GOAL="$(printf 'g%.0s' {1..280})" run "dotfiles")
# budget is status-right-length(140) - 24 = 116
assert_has "marks goal as the winning source" "[x] goal" "$out"
assert_has "reports full length and the cap"  "280 chars, bar shows 116" "$out"

echo "== a short goal is reported as complete, not cut"
out=$(STUB_GOAL="short goal" run "dotfiles")
assert_has "says shown in full" "shown in full" "$out"
assert_lacks "does not claim a cap"  "bar shows 116" "$out"

echo "== precedence: @agent_desc outranks @claude_goal"
out=$(STUB_DESC="spawned worker" STUB_GOAL="a goal" run "dotfiles")
assert_has "desc wins" "[x] desc" "$out"
assert_has "goal is listed but not chosen" "[ ] goal" "$out"

echo "== every source empty falls through to the date"
out=$(run "dotfiles")
assert_has "says all sources are empty" "every source empty" "$out"

echo "== an over-long cached line reports the characters tmux cuts"
printf '%s' "$(printf 'x%.0s' {1..170})" > "$CACHE/dotfiles"
out=$(run "dotfiles")
# 170 rendered against a 140 limit means 30 lost off the right, clock first
assert_has "counts the overflow" "30 chars are being cut off the right" "$out"

echo "== a session name with a slash maps to the flat cache key"
rm -f "$CACHE"/*
printf 'cached line' > "$CACHE/_claude-fix-foo"
out=$(run "_claude-fix/foo")
assert_has "reads the slash-mapped cache file" "cached line" "$out"

printf "\n%s passed, %s failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
