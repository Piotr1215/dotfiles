#!/usr/bin/env bash
# PROJECT: value-picker
# AI snippet picker. Global, not terminal-bound: pick a snippet and its body is
# pasted into whatever window has focus.
#
# Extensible by data, not code: each snippet is one file in ~/.config/ai-snippets/
# The filename (extension stripped) is the label; the file content is the body.
#
#   Enter   -> paste the body into the focused window
#   Ctrl+E  -> open that snippet in $EDITOR, paste nothing
#
# Why paste and not type: bodies are multi-line, and `xdotool type` turns every
# newline into a real Enter, which submits a prompt (or executes a line in a
# terminal) halfway through. Clipboard + shift+Insert is what AutoKey phrases
# already use, and it is inert.
#
# Usage:
#   __snippet_picker.sh [erase]   erase = chars to backspace first (the trigger)
#   __snippet_picker.sh --list    print the rows and exit (no GUI, for testing)
set -eo pipefail

SNIPPETS_DIR="${AI_SNIPPETS_DIR:-$HOME/.config/ai-snippets}"
EXCERPT_LINES="${SNIPPET_EXCERPT_LINES:-3}"

# Rows are NUL-separated so a row can span several lines: rofi shows the label
# plus an excerpt of the body, which is the whole point of the wide window.
# `-eh` must match the row height or rofi clips the excerpt.
ROW_HEIGHT=$((EXCERPT_LINES + 1))

die() {
    command -v notify-send >/dev/null 2>&1 && notify-send "Snippet picker" "$1"
    echo "$1" >&2
    exit 1
}

# Snippet files, sorted. Dotfiles and directories are skipped.
# -L because the directory is itself a symlink (~/.config/ai-snippets points at
# the private repo). Without it find refuses to descend and the library reads as
# empty, which looks like "no snippets" rather than "wrong flag".
list_files() {
    [[ -d "$SNIPPETS_DIR" ]] || return 0
    find -L "$SNIPPETS_DIR" -maxdepth 1 -type f ! -name '.*' -printf '%f\n' 2>/dev/null | sort
}

label_of() { local f="$1"; f="${f%.*}"; echo "${f//[-_]/ }"; }

# Reflow a body into flowing paragraphs: hard wraps are an artefact of editing
# the file in nvim, and pasting them into a prompt box leaves ragged lines that
# re-wrap again at the box width. Blank lines and list items are structure, so
# they survive; everything else in a paragraph joins onto one line.
reflow() {
    python3 -c '
import re, sys
out, buf = [], []
def flush():
    if buf: out.append(" ".join(buf)); buf.clear()
for line in open(sys.argv[1]).read().splitlines():
    s = line.strip()
    if not s:
        # Blank line ends a block and is itself structure worth keeping.
        flush(); out.append("")
    elif re.match(r"([-*+]|\d+[.)])\s", s):
        # A marker starts a new block; its wrapped continuations join it.
        flush(); buf.append(s)
    else:
        buf.append(s)
flush()
sys.stdout.write("\n".join(out).rstrip("\n") + "\n")
' "$1"
}

# One row: label line, then the first EXCERPT_LINES lines of the reflowed body,
# truncated so a long paragraph cannot widen the window. The excerpt is built
# from the same text that gets pasted, so the preview never lies about content.
build_row() {
    local file="$1" label
    label="$(label_of "$file")"
    printf '%s\n' "$label"
    reflow "$SNIPPETS_DIR/$file" 2>/dev/null \
        | grep -vE '^[[:space:]]*$' \
        | head -n "$EXCERPT_LINES" \
        | cut -c1-90 \
        | sed 's/^/    /'
}

# Deliver a body: erase the trigger that launched us, then paste. Erasing only
# after any UI has closed keeps it from racing AutoKey's own key injection, and
# pasting (never typing) keeps newlines from landing as real Enters.
paste_snippet() {
    local file="$1" erase="$2" saved i backspaces=()
    if [[ "$erase" =~ ^[0-9]+$ ]] && (( erase > 0 )); then
        for ((i = 0; i < erase; i++)); do backspaces+=(BackSpace); done
        xdotool key --clearmodifiers "${backspaces[@]}"
    fi
    saved="$(xclip -selection clipboard -o 2>/dev/null || true)"
    reflow "$file" | xclip -selection clipboard
    xdotool key --clearmodifiers shift+Insert
    # Restore is delayed because the paste is asynchronous. A shortcut that
    # silently eats whatever was copied before is worse than no shortcut.
    ( sleep 1; printf '%s' "$saved" | xclip -selection clipboard ) >/dev/null 2>&1 &
}

mapfile -t files < <(list_files)
(( ${#files[@]} > 0 )) || die "No snippets in $SNIPPETS_DIR"

# Direct mode: a trigger bound straight to one snippet, no menu. The name may be
# given with or without its extension, so ";;br" survives done-check.md becoming
# done-check.txt later.
if [[ -n "${2:-}" ]]; then
    want="$2"
    direct=""
    for f in "${files[@]}"; do
        [[ "$f" == "$want" || "${f%.*}" == "$want" ]] && { direct="$SNIPPETS_DIR/$f"; break; }
    done
    [[ -n "$direct" ]] || die "No snippet named '$want' in $SNIPPETS_DIR"
    paste_snippet "$direct" "${1:-0}"
    exit 0
fi

if [[ "${1:-}" == "--list" ]]; then
    for f in "${files[@]}"; do build_row "$f"; echo "---"; done
    exit 0
fi

# Shared rofi look, matching __value_picker.sh but wider: the excerpt needs room.
rofi_pick() {
    # Control+e is rofi's default kb-move-end, and rofi refuses a custom binding
    # that is already taken ("failed to set binding"), so unbind it first. Same
    # trick __value_picker.sh uses to free Control+a from kb-move-front.
    #
    # The palette is set on `*` rather than per widget: row text is drawn by the
    # element-text child, which does not inherit a colour set on `element`, so
    # per-widget overrides alone leave the rows in the stock theme's colours.
    rofi -dmenu -i -p snippet -sep '\0' -eh "$ROW_HEIGHT" -format i -no-custom \
        -kb-move-end "" -kb-custom-1 "Control+e" \
        -mesg 'Enter → paste    Ctrl+E → edit' \
        -theme-str '* {font: "JetBrainsMono Nerd Font 12"; background-color: argb:ff282a36; text-color: argb:fff8f8f2;}' \
        -theme-str 'window {width: 1000px; background-color: argb:ff282a36; border: 2px solid; border-color: argb:ffbd93f9; border-radius: 8px;}' \
        -theme-str 'mainbox {background-color: transparent;}' \
        -theme-str 'inputbar {background-color: argb:ff44475a; padding: 8px;}' \
        -theme-str 'prompt {background-color: transparent; text-color: argb:ffbd93f9;}' \
        -theme-str 'entry {background-color: transparent;}' \
        -theme-str 'message {background-color: transparent;}' \
        -theme-str 'textbox {background-color: transparent; text-color: argb:ff6272a4;}' \
        -theme-str 'listview {background-color: transparent; lines: 8;}' \
        -theme-str 'element {padding: 8px;}' \
        -theme-str 'element normal.normal {background-color: transparent; text-color: argb:fff8f8f2;}' \
        -theme-str 'element alternate.normal {background-color: transparent; text-color: argb:fff8f8f2;}' \
        -theme-str 'element selected.normal {background-color: argb:ff44475a; text-color: argb:ff50fa7b;}' \
        -theme-str 'element-text {background-color: transparent; text-color: inherit;}'
}

index=""
edit=0
if index=$(for f in "${files[@]}"; do build_row "$f"; printf '\0'; done | rofi_pick); then
    :
else
    # rofi exits 10 for kb-custom-1 (Ctrl+E) and still prints the selection.
    # Read $? first, before any other command clobbers it.
    [[ $? -eq 10 ]] && edit=1 || exit 0
fi

[[ "$index" =~ ^[0-9]+$ ]] || exit 0
file="$SNIPPETS_DIR/${files[$index]}"
[[ -f "$file" ]] || die "Snippet vanished: $file"

# Ctrl+E: edit and stop. The trigger is left on screen deliberately, since
# nothing is being pasted and erasing it would look like the pick was lost.
if (( edit )); then
    editor="${EDITOR:-nvim}"
    for term in alacritty ghostty x-terminal-emulator; do
        if command -v "$term" >/dev/null 2>&1; then
            setsid "$term" -e "$editor" "$file" >/dev/null 2>&1 &
            exit 0
        fi
    done
    die "No terminal found to run $editor"
fi

paste_snippet "$file" "${1:-0}"
