#!/usr/bin/env bash
set -eo pipefail

# M-u in tmux: pick links from the current pane's whole scrollback.
# __tmux_pane_urls.py lists them newest first, OSC 8 hyperlink targets
# included; fzf picks. Enter opens in the browser, Tab marks several,
# ctrl-y copies, alt-enter types the link into the pane without Enter.
#
# The binding calls this with the pane and client. With no links it says so on
# the status line instead of opening an empty popup; otherwise it opens a popup
# that runs this script again with --pick.

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
extractor="$script_dir/__tmux_pane_urls.py"

# Runs inside the popup: fzf over the pane's links, then acts on the pick.
pick() {
    local pane="$1"
    # The single-quoted binds expand in fzf's shell, not here.
    # shellcheck disable=SC2016
    "$extractor" "$pane" | fzf -i --multi --layout=reverse --info=inline --border=none \
        --prompt='link> ' \
        --header='enter: open   tab: mark   ctrl-y: copy   alt-enter: type into pane   esc: quit' \
        --bind 'enter:execute-silent(for u in {+}; do setsid -f xdg-open "$u" </dev/null >/dev/null 2>&1; done)+abort' \
        --bind 'ctrl-y:execute-silent(printf "%s\n" {+} | perl -pe "chomp if eof" | xclip -selection clipboard)+abort' \
        --bind "alt-enter:execute-silent(tmux send-keys -t '$pane' -l -- {+})+abort" \
        || true
}

# Opens the popup on the pane's client, or reports that there is nothing to pick.
main() {
    local pane="${1:?usage: __tmux_pane_urls.sh <pane_id> [client]}"
    local client="${2:-}"
    local count
    count=$("$extractor" "$pane" | wc -l)
    if ((count == 0)); then
        tmux display-message ${client:+-c "$client"} "no links in this pane"
        return 0
    fi
    tmux display-popup ${client:+-c "$client"} -t "$pane" -E -w 80% -h 60% \
        -T " $count links " "$script_dir/__tmux_pane_urls.sh --pick '$pane'"
}

if [[ "${1:-}" == "--pick" ]]; then
    pick "$2"
else
    main "$@"
fi
