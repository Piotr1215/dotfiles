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
  list-sessions) printf 'orchestrator\nworker-b\nhuman-pane\n' ;;
  list-panes)
    target=""
    while [[ $# -gt 0 ]]; do
      [[ "$1" == -t ]] && { target="$2"; break; }
      shift
    done
    case "$target" in
      orchestrator) printf '1|orchestrator\n' ;;
      worker-b) printf '1|worker-b\n' ;;
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
    fi
    ;;
  set-option) exit 0 ;;
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
if [[ $(wc -l <<<"$out") -eq 3 ]]; then ok "all sessions remain selectable"
else bad "all sessions remain selectable"; fi
if [[ "$out" == *'  ↳ worker-b ← orchestrator ◀◀◀'* ]]; then ok "worker shows its parent"
else bad "worker shows its parent"; fi
parent_line=$(grep -n '^orchestrator ◀◀◀$' <<<"$out" | cut -d: -f1)
child_line=$(grep -n '↳ worker-b ' <<<"$out" | cut -d: -f1)
if [[ "$parent_line" -lt "$child_line" ]]; then ok "parent renders before worker"
else bad "parent renders before worker"; fi

echo "== selection preserves the real session target =="
choice=$(grep '↳ worker-b ' <<<"$out")
resolved=$(PATH="$BIN:$PATH" "$SCRIPT" resolve "$choice")
if [[ "$resolved" == worker-b ]]; then ok "decorated worker resolves exactly"
else bad "decorated worker resolves exactly"; fi
: > "$LOG"
claimed=$(PATH="$BIN:$PATH" "$SCRIPT" claim "$choice")
if [[ "$claimed" == worker-b ]]; then ok "claimed worker resolves exactly"
else bad "claimed worker resolves exactly"; fi
if grep -q '^set-option -t worker-b @agent_human_owned 1$' "$LOG"; then
    ok "explicit worker selection records takeover"
else
    bad "explicit worker selection records takeover"
fi

echo "== M-x uses the hierarchy helper =="
if grep -qF '__tmux_session_choices.sh list' "$FILE_OPENER"; then
    ok "picker lists decorated sessions"
else
    bad "picker lists decorated sessions"
fi
if grep -qF "\"\$SESSION_CHOICES\" claim \"\$OUTPUT\"" "$FILE_OPENER"; then
    ok "picker claims the selected worker"
else
    bad "picker claims the selected worker"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
