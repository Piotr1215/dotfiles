#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$HOME/dev/dotfiles/scripts/__tmux_session_choices.sh"
FILE_OPENER="$HOME/dev/dotfiles/scripts/__file_opener.sh"
T=$(mktemp -d)
BIN="$T/bin"
LOG="$T/tmux.log"
mkdir -p "$BIN"
trap 'rm -rf "$T"' EXIT

cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_TMUX_LOG"
case "$1" in
  list-sessions) printf 'orchestrator\nworker-b\ntask\nai-agents-pr-74\nhuman-pane\n' ;;
  list-panes)
    target=""
    while [[ $# -gt 0 ]]; do
      [[ "$1" == -t ]] && { target="$2"; break; }
      shift
    done
    case "$target" in
      orchestrator) printf '1|orchestrator\n' ;;
      worker-b) printf '1|worker-b\n' ;;
      task) printf '1|task\n' ;;
      ai-agents-pr-74) printf '1|ai-agents-pr-74\n' ;;
      human-pane) printf '1|\n' ;;
    esac
    ;;
  show-options)
    target=""; option="${@: -1}"
    while [[ $# -gt 0 ]]; do
      [[ "$1" == -t ]] && { target="$2"; break; }
      shift
    done
    if [[ "$target" == worker-b ]]; then
      [[ "$option" == @agent_spawn_level ]] && printf 'delegated\n'
      [[ "$option" == @agent_spawn_parent ]] && printf 'orchestrator\n'
    elif [[ "$target" == ai-agents-pr-74 ]]; then
      [[ "$option" == @agent_spawn_level ]] && printf 'delegated\n'
      [[ "$option" == @agent_spawn_parent ]] && printf 'task\n'
    fi
    ;;
esac
EOF
chmod +x "$BIN/tmux"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

export STUB_TMUX_LOG="$LOG"
out=$(PATH="$BIN:$PATH" "$SCRIPT" list)

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
