#!/usr/bin/env bash
# PROJECT: value-picker
# Global, rofi-based value picker. Not terminal-bound: pick a value and it is
# pasted in place into whatever window has focus (clipboard + Shift+Insert).
#
# Extensible by data, not code: each "set" is a file in ~/.config/value-sets/
#   - plain file      -> each non-comment line is a value
#   - executable file -> run it, its stdout lines are the values (live data)
# Line format:  VALUE              -> pasted verbatim
#               VALUE | label      -> rofi shows the whole line, pastes only VALUE
#               VALUE<TAB>label    -> rofi shows and filters only the label,
#                                     pastes VALUE (ids nobody searches by)
#
# Env: VALUE_PICKER_RESTORE_DELAY  seconds before the clipboard is put back (1)
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
    local prompt="$1"
    shift
    rofi_theme 2000
    rofi -dmenu -i -p "$prompt" \
        -kb-move-front "" -kb-custom-1 "Control+a" \
        -mesg 'Ctrl+A → copy whole list to clipboard' \
        "${ROFI_THEME[@]}" "$@"
}

# What rofi shows for each line on stdin: the label of a VALUE<TAB>label line,
# else all of it. One awk pass, not a bash call per line: ;;open lists 60k
# paths and the per-line loop alone took a second before rofi could open.
display_lines() {
    awk '{ i = index($0, "\t"); print (i ? substr($0, i + 1) : $0) }'
}

# What gets typed for a line: VALUE before a tab, else the text before " | ".
value_of() {
    if [[ "$1" == *$'\t'* ]]; then printf '%s' "${1%%$'\t'*}"; else printf '%s' "${1%% | *}"; fi
}

# What the clipboard holds, as the target to save before a pick borrows it:
# "text" for text, an image/* target for an image, empty when nothing is on it.
# Fails for copied files (a file manager copy also offers text, and restoring
# only that would turn the copy into a path), so the caller types instead.
clipboard_kind() {
    local targets image
    targets=$(xclip -selection clipboard -t TARGETS -o 2>/dev/null) || return 0
    if grep -qxE 'x-special/gnome-copied-files|text/uri-list' <<< "$targets"; then
        return 1
    fi
    if grep -qxE 'UTF8_STRING|STRING|TEXT|text/plain(;charset=utf-8)?' <<< "$targets"; then
        printf 'text'
    elif image=$(grep -m1 '^image/' <<< "$targets"); then
        printf '%s' "$image"
    fi
}

# Put a value where the cursor is by pasting, not typing. Typed keys go through
# the app's own key handling (Slack opens its command menu on a leading /, Claude
# Code its file menu on @, editors auto-pair brackets) at 12 ms a key. A paste
# lands whole and literal, in a terminal as a bracketed paste; Alacritty binds
# Shift+Insert to the clipboard. The clipboard is borrowed: saved, used, and put
# back a second later, an image as an image.
deliver() {
    local value="$1" kind saved=""
    if ! kind=$(clipboard_kind); then
        xdotool type --clearmodifiers --delay 12 -- "$value"
        return 0
    fi
    if [[ -n "$kind" ]]; then
        saved=$(mktemp "${TMPDIR:-/tmp}/value-picker-clip.XXXXXX")
        if [[ "$kind" == text ]]; then
            xclip -selection clipboard -o > "$saved" 2>/dev/null || true
        else
            xclip -selection clipboard -t "$kind" -o > "$saved" 2>/dev/null || true
        fi
    fi
    printf '%s' "$value" | xclip -selection clipboard
    xdotool key --clearmodifiers shift+Insert
    [[ -n "$saved" ]] || return 0
    (
        sleep "${VALUE_PICKER_RESTORE_DELAY:-1}"
        if [[ "$kind" == text ]]; then
            xclip -selection clipboard < "$saved"
        else
            xclip -selection clipboard -t "$kind" < "$saved"
        fi
        rm -f "$saved"
    ) >/dev/null 2>&1 &
}

# rofi hands focus back to the window it opened over a moment after it exits,
# and a key sent sooner is lost: a GTK entry kept the first ";" of ";;open"
# because one erase backspace went nowhere. Wait up to a second for the
# original window, then go ahead anyway.
wait_for_origin() {
    local origin="$1" i
    [[ -n "$origin" ]] || return 0
    for ((i = 0; i < 40; i++)); do
        [[ "$(xdotool getactivewindow 2>/dev/null)" == "$origin" ]] && return 0
        sleep 0.025
    done
}

# Names of all available sets (filenames in SETS_DIR).
list_sets() {
    [[ -d "$SETS_DIR" ]] || return 0
    for f in "$SETS_DIR"/*; do
        [[ -f "$f" ]] && basename "$f"
    done
}

# Emit the value lines of a set, without blank lines. A plain file also drops its
# # comments. An executable's output is all values, because some start with #
# (;;slack types #channel); its comments live in its code.
load_set() {
    local f="$SETS_DIR/$1"
    if [[ ! -f "$f" ]]; then
        notify-send "Value Picker" "No such set: $1"
        exit 1
    fi
    # LC_ALL=C: a UTF-8 [[:space:]] scan took 0.45 s over ;;open's 10 MB list,
    # the C locale 0.04 s. Only lines of nothing but Unicode spaces differ.
    if [[ -x "$f" ]]; then
        "$f" | LC_ALL=C grep -vE '^[[:space:]]*$'
    else
        LC_ALL=C grep -vE '^[[:space:]]*(#|$)' "$f"
    fi
}

set_name="$1"

# No set given: choose one from the menu of all sets.
if [[ -z "$set_name" ]]; then
    set_name=$(list_sets | rofi_pick "set") || exit 0
    [[ -z "$set_name" ]] && exit 0
fi

# If a set resolves to exactly one value, there is nothing to choose: skip rofi
# and paste it straight away. Makes status-style sets (e.g. "reboot" -> yes/no)
# feel instant instead of popping a one-row menu.
#
# The set goes to a temp file first, not into `mapfile < <(...)`: bash reads a
# pipe one byte at a time so it never reads past a line, and ;;open's 10 MB
# list took 1.3 s that way. A command substitution still took 0.8 s; a regular
# file is read in blocks. `|| true` because grep exits 1 on an empty set.
set_file=$(mktemp "${TMPDIR:-/tmp}/value-picker.XXXXXX")
trap 'rm -f "$set_file"' EXIT
load_set "$set_name" > "$set_file" || true
mapfile -t lines < "$set_file"

# A live set with nothing to offer (;;session outside Claude or Codex) opens no
# menu and erases nothing, so the trigger stays as typed.
(( ${#lines[@]} == 0 )) && exit 0

# The window the trigger was typed in, read before rofi takes focus, so the
# erase and the paste can wait for it to come back (wait_for_origin).
origin=""
(( ${#lines[@]} > 1 )) && origin=$(xdotool getactivewindow 2>/dev/null || true)

dump_all=0
if (( ${#lines[@]} == 1 )); then
    selection="${lines[0]}"
elif picked=$(display_lines < "$set_file" | rofi_pick "$set_name" -format 'i s'); then
    # rofi returns "<index> <text>"; the index maps back to the full line, so a
    # hidden VALUE survives. A custom entry has index -1: paste its text as is.
    idx="${picked%% *}"
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx < ${#lines[@]} )); then
        selection="${lines[idx]}"
    else
        selection="${picked#* }"
    fi
else
    # rofi exits 10 for kb-custom-1 (Control+a) = "type the whole list".
    # Anything else (1 = Esc) is a cancel. Read $? first, before any command.
    [[ $? -eq 10 ]] && dump_all=1 || exit 0
fi

# Erase the trigger that launched us (e.g. autokey's ";;awsid"): $2 = char count.
# Backspaces only, after rofi has closed, so it never races autokey's own key
# injection (which left ";;aws" behind / ate the value). This is always safe.
wait_for_origin "$origin"
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
    printf '%s\n' "${lines[@]}" | sed 's/\t/ | /' | xclip -selection clipboard
    command -v notify-send >/dev/null 2>&1 &&
        notify-send "Value picker" "Copied ${#lines[@]} items to clipboard"
    exit 0
fi

# Normal pick: paste the single VALUE (text before " | "). One line, no Enter, so
# nothing executes. Multi-line content is never pasted (see dump-all above).
[[ -z "$selection" ]] && exit 0
deliver "$(value_of "$selection")"
