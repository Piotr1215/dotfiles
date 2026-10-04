#!/usr/bin/env bash

set -eo pipefail

# Link picker popup. __link_candidates.py streams
# "display<TAB>command<TAB>title<TAB>url<TAB>key" lines: pins, today's
# history, the curated pet links, then every bookmark and history row the
# browser profiles hold, newest first. fzf shows column one only (--with-nth=1)
# but hands back the whole line, so cut recovers the command with no mapping
# file in between. Only field 2 is cut: fields 3 and 4 are what the ctrl-f pin
# toggle reads, and eval must never see them.
#
# fzf does the matching, the ranking and the highlighting, over the whole
# list, in process: fuzzy, so "classifreadme" finds classif/README.md, and
# case ignored (-i). --scheme=history drops fzf's positional bonuses and
# breaks ties by input order, which is the recency order the script emits,
# so a page seen today sits above the same word on a page from last year.
# --nth=1,3,4 matches the hidden untruncated title and url as well as the
# display, so a hit past the display's cut is still a hit. The two-line
# preview shows the highlighted row's full title and url, which the columns
# truncate.
#
# The picker reloaded the list from a subprocess on every keystroke before,
# with a port of Vimium C's ranking that matched a typed word only unbroken.
# That cost a quarter second a key and found nothing for a run-together or
# misspelt word; fzf finds it and puts it first.

source /home/decoder/dev/dotfiles/scripts/__lib_alacritty_popup.sh

CANDIDATES=/home/decoder/dev/dotfiles/scripts/__link_candidates.py
TEMP_FILE=$(mktemp)

handle_link_selection() {
    "$CANDIDATES" | /usr/local/bin/fzf \
        --ansi -i \
        --scheme=history \
        --delimiter=$'\t' \
        --with-nth=1 \
        --nth=1,3,4 \
        --height=100% \
        --layout=reverse \
        --info=inline \
        --border=sharp \
        --header=$'enter: open in browser   ctrl-y: copy url   ctrl-f: pin/unpin *   esc: quit\ntype to search, words in any order, typos ok   #pin #link #mark #work #home: narrow by source' \
        --prompt='🔍 ' \
        --preview='printf "%s\n%s\n" {3} {4}' \
        --preview-window=down,2,wrap,border-top \
        --bind "ctrl-f:execute-silent(${CANDIDATES} --toggle-pin {})+reload(${CANDIDATES})" \
        --bind 'ctrl-y:execute-silent(printf %s {4} | xclip -selection clipboard)+abort' \
        --color='fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4' \
        | cut -f2 > "$TEMP_FILE"
}

export -f handle_link_selection
export CANDIDATES TEMP_FILE

# Bring the long tail up to date while the popup opens. Detached, so the
# popup never waits on a hundred megabytes of sqlite being copied.
"$CANDIDATES" --refresh >/dev/null 2>&1 &

# The popup's 172 columns fit the row the script renders: title 70 and url
# 80 with the marker, the gaps and the tag, plus fzf's pointer, border and
# scrollbar.
alacritty_popup bookmarks-popup bash -c "handle_link_selection"

# After terminal closes, handle the selection in the parent process
if [[ -f "$TEMP_FILE" ]]; then
    selection=$(cat "$TEMP_FILE")
    rm -f "$TEMP_FILE"

    if [[ -n "$selection" ]]; then
        if [[ "$selection" =~ ^xdg-open ]]; then
            eval "$selection" &
            __focus_browser.sh
        else
            # Copy command to clipboard for pasting elsewhere
            echo -n "$selection" | xclip -selection clipboard
        fi
    fi
fi
