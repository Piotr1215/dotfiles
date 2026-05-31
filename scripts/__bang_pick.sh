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
VALUE_PICKER="$DOTFILES/scripts/__value_picker.sh"
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
        xdotool type --clearmodifiers --delay 12 --file "$txt"
        ;;
    script)
        py="$dir/$name.py"
        # Pickers built on __value_picker.sh: pull the set name (2nd arg) and run
        # it with erase 0 (the trigger was already cleaned above).
        set_name=$(grep -oE '__value_picker\.sh"[^]]*' "$py" 2>/dev/null \
            | sed -E 's/.*,[[:space:]]*"([^"]+)"[[:space:]]*,.*/\1/')
        if [[ -n "$set_name" ]]; then
            "$VALUE_PICKER" "$set_name" 0
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
