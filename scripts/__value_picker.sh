#!/usr/bin/env bash
# PROJECT: value-picker
# Global, rofi-based value picker. Not terminal-bound: pick a value and it is
# typed in place into whatever window has focus (xdotool).
#
# Extensible by data, not code: each "set" is a file in ~/.config/value-sets/
#   - plain file      -> each non-comment line is a value
#   - executable file -> run it, its stdout lines are the values (live data)
# Line format:  VALUE              -> typed verbatim
#               VALUE | label      -> rofi shows the whole line, types only VALUE
#
# Usage:
#   __value_picker.sh <set>   pick a value from <set>
#   __value_picker.sh         pick the set first (menu of all sets), then a value
set -eo pipefail

SETS_DIR="${VALUE_SETS_DIR:-$HOME/.config/value-sets}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/__lib_rofi_theme.sh"

# Control+a is rebound from kb-move-front to kb-custom-1 so it exits with code 10,
# our "copy the whole list to the clipboard" signal (handled by the caller).
# -mesg advertises it.
#
# 2000px, wider than the shared default: the "skills" set carries absolute
# SKILL.md paths and its longest row is 235 chars. The discriminator (run vs
# file, and the skill name) sits at the END of the line, so a truncating window
# hides exactly the part being chosen between.
rofi_pick() {
    rofi_theme 2000
    rofi -dmenu -i -p "$1" \
        -kb-move-front "" -kb-custom-1 "Control+a" \
        -mesg 'Ctrl+A → copy whole list to clipboard' \
        "${ROFI_THEME[@]}"
}

# Names of all available sets (filenames in SETS_DIR).
list_sets() {
    [[ -d "$SETS_DIR" ]] || return 0
    for f in "$SETS_DIR"/*; do
        [[ -f "$f" ]] && basename "$f"
    done
}

# Emit the value lines of a set: run it if executable, else cat. Strip comments/blanks.
load_set() {
    local f="$SETS_DIR/$1"
    if [[ ! -f "$f" ]]; then
        notify-send "Value Picker" "No such set: $1"
        exit 1
    fi
    if [[ -x "$f" ]]; then "$f"; else cat "$f"; fi | grep -vE '^[[:space:]]*(#|$)'
}

set_name="$1"

# No set given: choose one from the menu of all sets.
if [[ -z "$set_name" ]]; then
    set_name=$(list_sets | rofi_pick "set") || exit 0
    [[ -z "$set_name" ]] && exit 0
fi

# If a set resolves to exactly one value, there is nothing to choose: skip rofi
# and type it straight away. Makes status-style sets (e.g. "reboot" -> yes/no)
# feel instant instead of popping a one-row menu.
mapfile -t lines < <(load_set "$set_name")

dump_all=0
if (( ${#lines[@]} == 1 )); then
    selection="${lines[0]}"
elif selection=$(printf '%s\n' "${lines[@]}" | rofi_pick "$set_name"); then
    : # normal pick
else
    # rofi exits 10 for kb-custom-1 (Control+a) = "type the whole list".
    # Anything else (1 = Esc) is a cancel. Read $? first, before any command.
    [[ $? -eq 10 ]] && dump_all=1 || exit 0
fi

# Erase the trigger that launched us (e.g. autokey's ";;awsid"): $2 = char count.
# Backspaces only, after rofi has closed, so it never races autokey's own key
# injection (which left ";;aws" behind / ate the value). This is always safe.
erase="${2:-0}"
if [[ "$erase" =~ ^[0-9]+$ ]] && (( erase > 0 )); then
    backspaces=()
    for ((i = 0; i < erase; i++)); do backspaces+=(BackSpace); done
    xdotool key --clearmodifiers "${backspaces[@]}"
fi

# Ctrl+A (dump-all): copy the WHOLE list (value + label, one per line) to the
# clipboard. Deliberately NEVER typed: xdotool would inject a real Enter at every
# newline and, in a terminal, execute each line. Clipboard + manual paste keeps
# the list inert and lets the user place it where they want.
if (( dump_all )); then
    printf '%s\n' "${lines[@]}" | xclip -selection clipboard
    command -v notify-send >/dev/null 2>&1 &&
        notify-send "Value picker" "Copied ${#lines[@]} items to clipboard"
    exit 0
fi

# Normal pick: type the single VALUE (text before " | "). One line, no Enter, so
# nothing executes. Multi-line content is never typed (see dump-all above).
[[ -z "$selection" ]] && exit 0
to_type="${selection%% | *}"
xdotool type --clearmodifiers --delay 12 -- "$to_type"
