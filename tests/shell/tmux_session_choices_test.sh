#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$REPO_ROOT/scripts/__tmux_session_choices.sh"
FILE_OPENER="$REPO_ROOT/scripts/__file_opener.sh"
T=$(mktemp -d)
BIN="$T/bin"
LOG="$T/tmux.log"
mkdir -p "$BIN"
trap 'rm -rf "$T"' EXIT

cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_TMUX_LOG"
[[ "$1" == list-sessions ]] || exit 1
printf '%s\n' 'orchestrator|captain||' 'worker-b|worker-b|delegated|captain' 'task|task||' 'ai-agents-pr-74|ai-agents-pr-74|delegated|task' 'human-pane|||'
EOF
chmod +x "$BIN/tmux"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

export STUB_TMUX_LOG="$LOG"
out=$(PATH="$BIN:$PATH" "$SCRIPT" list)
if [[ $(wc -l < "$LOG") -eq 1 ]]; then ok "one tmux call for the whole session list"
else bad "one tmux call for the whole session list"; fi

echo "== hierarchy without filtering =="
if [[ $(wc -l <<<"$out") -eq 5 ]]; then ok "all sessions remain selectable"
else bad "all sessions remain selectable"; fi
expected=$'human-pane ◀◀◀\norchestrator ◀◀◀\n  - worker-b ◀◀◀\ntask ◀◀◀\n  - ai-agents-pr-74 ◀◀◀'
if [[ "$out" == "$expected" ]]; then ok "each parent heads its own worker group"
else bad "each parent heads its own worker group"; fi
parent_line=$(grep -n '^orchestrator ◀◀◀$' <<<"$out" | cut -d: -f1)
child_line=$(grep -n -- '- worker-b ' <<<"$out" | cut -d: -f1)
if [[ "$parent_line" -lt "$child_line" ]]; then ok "parent renders before worker"
else bad "parent renders before worker"; fi
if [[ "$out" != *'←'* && "$out" != *'↳'* ]]; then ok "grouping replaces parent suffixes and arrows"
else bad "grouping replaces parent suffixes and arrows"; fi

echo "== selection preserves the real session target =="
choice=$(grep -- '- worker-b ' <<<"$out")
resolved=$(PATH="$BIN:$PATH" "$SCRIPT" resolve "$choice")
if [[ "$resolved" == worker-b ]]; then ok "decorated worker resolves exactly"
else bad "decorated worker resolves exactly"; fi
if ! PATH="$BIN:$PATH" "$SCRIPT" claim "$choice" 2>/dev/null; then
    ok "claim is gone"
else
    bad "claim is gone"
fi

echo "== real tmux active pane and session options =="
socket="mx-choices-test-$$"
cleanup() { command tmux -L "$socket" kill-server 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT
command tmux -L "$socket" -f /dev/null new-session -d -s root
command tmux -L "$socket" set-option -p -t root:0.0 @agent_name captain
command tmux -L "$socket" new-window -d -t root -n inactive
command tmux -L "$socket" set-option -p -t root:inactive.0 @agent_name wrong
command tmux -L "$socket" split-window -d -t root:0
command tmux -L "$socket" set-option -p -t root:0.1 @agent_name wrong
command tmux -L "$socket" select-pane -t root:0.0
command tmux -L "$socket" new-session -d -s child
command tmux -L "$socket" set-option -t child @agent_spawn_level delegated
command tmux -L "$socket" set-option -t child @agent_spawn_parent captain
mkdir -p "$T/real-bin"
TEST_TMUX_BIN="$(command -v tmux)"
export TEST_TMUX_BIN
cat > "$T/real-bin/tmux" <<'EOF'
#!/usr/bin/env bash
exec "$TEST_TMUX_BIN" -L "$TEST_TMUX_SOCKET" "$@"
EOF
chmod +x "$T/real-bin/tmux"
export TEST_TMUX_SOCKET="$socket"
real_out=$(PATH="$T/real-bin:$PATH" "$SCRIPT" list)
if [[ "$real_out" == $'root ◀◀◀\n  - child ◀◀◀' ]]; then ok "active pane alias and session metadata group child"
else bad "active pane alias and session metadata group child: $real_out"; fi
command tmux -L "$socket" kill-server
if [[ -z $(PATH="$T/real-bin:$PATH" "$SCRIPT" list) ]]; then ok "no tmux server yields an empty list"
else bad "no tmux server yields an empty list"; fi

echo "== M-x uses the hierarchy helper =="
if grep -qF '__tmux_session_choices.sh list' "$FILE_OPENER"; then
    ok "picker lists decorated sessions"
else
    bad "picker lists decorated sessions"
fi
if grep -qF "\"\$SESSION_CHOICES\" resolve \"\$OUTPUT\"" "$FILE_OPENER"; then
    ok "picker resolves the selected worker"
else
    bad "picker resolves the selected worker"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
