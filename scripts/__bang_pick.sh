#!/usr/bin/env bash
# PROJECT: value-picker
# ";;?" discovery menu. Shows every ";;" abbreviation in rofi (global, not
# terminal-bound) and EXECUTES the chosen one, so it behaves like having typed
# the trigger directly:
#   - phrase entry -> types the phrase text (its paired .txt)
#   - picker script -> runs __value_picker.sh for that set (erase 0, since the
#     ";;?" trigger is already cleaned below)
#
# So: forget a binding -> type ";;?" -> pick from the list -> it runs.
set -eo pipefail

DOTFILES="/home/decoder/dev/dotfiles"
BINDINGS="$DOTFILES/scripts/__show_autokey_bindings.sh"
AUTOKEY_DATA_DIR="/home/decoder/.config/autokey/data"

selection=$("$BINDINGS" --bang-rofi) || exit 0
[[ -z "$selection" ]] && exit 0

# Column 1 of the aligned line is the trigger, e.g. ";;awsid".
trigger="${selection%% *}"
[[ -z "$trigger" ]] && exit 0

# Find the AutoKey JSON that owns this trigger.
json=""
while read -r f; do
    if jq -e --arg t "$trigger" \
        '((.abbreviation.abbreviations // []) | index($t)) != null' "$f" >/dev/null 2>&1; then
        json="$f"
        break
    fi
done < <(find "$AUTOKEY_DATA_DIR" -name '*.json' 2>/dev/null)

[[ -z "$json" ]] && { notify-send "Bang menu" "No entry for $trigger"; exit 1; }

entry_type=$(jq -r '.type // "phrase"' "$json")
dir=$(dirname "$json")
name=$(basename "$json" .json); name="${name#.}"   # ".email_work.json" -> "email_work"

# Erase the ";;?" that launched this menu (3 chars), after rofi has closed so it
# never races AutoKey's own key injection.
xdotool key --clearmodifiers BackSpace BackSpace BackSpace

case "$entry_type" in
    phrase)
        txt="$dir/$name.txt"
        [[ -f "$txt" ]] || { notify-send "Bang menu" "Missing phrase: $name.txt"; exit 1; }
        # Paste, never type. A multi-line phrase typed with xdotool turns every
        # newline into a real Enter, which submits the prompt (or executes the
        # line in a terminal) halfway through the text. AutoKey's own sendMode
        # for these phrases is <shift>+<insert> for exactly this reason.
        saved="$(xclip -selection clipboard -o 2>/dev/null || true)"
        xclip -selection clipboard < "$txt"
        xdotool key --clearmodifiers shift+Insert
        ( sleep 1; printf '%s' "$saved" | xclip -selection clipboard ) >/dev/null 2>&1 &
        ;;
    script)
        py="$dir/$name.py"
        # Every script entry is a subprocess.Popen list of quoted strings, so run
        # that argv directly instead of pattern-matching one known picker. The
        # trailing erase count is forced to 0: the trigger was cleaned above, and
        # a stale count would eat the user's own text.
        mapfile -t argv < <(grep -m1 'subprocess\.Popen' "$py" 2>/dev/null \
            | grep -oE '"[^"]*"' | tr -d '"')
        if (( ${#argv[@]} > 0 )) && [[ -x "${argv[0]}" ]]; then
            [[ "${argv[-1]}" =~ ^[0-9]+$ ]] && argv[-1]=0
            "${argv[@]}"
        else
            notify-send "Bang menu" "Cannot auto-run script: $name"
            exit 1
        fi
        ;;
    *)
        notify-send "Bang menu" "Unknown entry type: $entry_type"
        exit 1
        ;;
esac
