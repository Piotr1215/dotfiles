#!/usr/bin/env bash
#
# __mail_search_viewer.sh
# Full-text search over WORK mail, as an M-x tab. The mail sibling of
# __linear_issue_viewer.sh: same three-field record contract, same debounced
# reload, same preview highlighting. notmuch is the search engine.
#
# Work only. The scope below pins every query to the loft.sh maildir, which
# carries both work identities (@loft.sh and @vcluster.com). Personal mail
# under piotrzan@gmail.com is never queried.
#
# Modes:
#   search <query>            emit TSV records for the query (fzf reload target)
#   preview <thread> <query>  render one thread, marking the query terms
#   (no args)                 the picker
#
# Keys:
#   Enter  - open the thread in neomutt, in a new tmux window
#   Ctrl+R - hand the thread to ursula and ask her to draft the reply
#   Ctrl+Y - copy the Gmail permalink for the message
#   Tab    - paste the message-id at the cursor in the underlying pane
#   Ctrl+P - toggle the preview pane
#
# Record contract (tab separated, one line per thread):
#   1 display   date | authors | subject, padded past any terminal width
#   2 haystack  subject + authors, so fzf can narrow inside a result set
#   3 thread    the bare notmuch thread id, what Enter and the preview act on.
#               A leading "thread:" is tolerated on input and stripped.

set -eo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

# query_terms and highlight_and_jump: the backend-agnostic preview half,
# shared with the other full-text pickers.
# shellcheck source=scripts/__lib_fzf_search_preview.sh
source "$(dirname "$SCRIPT_PATH")/__lib_fzf_search_preview.sh"

# The work boundary. Matches the virtual-mailboxes convention already in
# ~/.config/mutt/accounts/piotr.zaniewski@loft.sh.muttrc.
readonly WORK_SCOPE='path:piotr.zaniewski@loft.sh/**'

# How many threads an empty query shows. Measured at 35ms for 200.
readonly DEFAULT_LIMIT=200

# How many threads a typed query may return.
readonly SEARCH_LIMIT=500

# Pad the display column past any terminal width so --with-nth=1,2 keeps the
# haystack off the right edge instead of hiding it from the matcher.
readonly DISPLAY_WIDTH=400

# Turn notmuch's JSON into the record contract.
# split/join rather than gsub: gsub over a few hundred records costs seconds,
# split/join is a tenth of that.
records_from_json() {
    jq -r --argjson width "$DISPLAY_WIDTH" '
        def clean: (. // "") | split("\n") | join(" ") | split("\t") | join(" ");
        def pad: if (. | length) < $width then . + (" " * ($width - (. | length))) else . end;
        .[]
        | . as $t
        | ($t.tags // []) as $tags
        | (if ($tags | index("unread")) then "●" else " " end) as $unread
        | (if ($tags | index("flagged")) then "⚑" else " " end) as $flag
        | ($t.authors | clean) as $authors
        | ($t.subject | clean) as $subject
        | (($t.date_relative // "") | clean) as $when
        | [
            ("\($unread)\($flag) \($when | .[0:12]) | \($authors | .[0:28]) | \($subject)" | pad),
            "\($subject) \($authors)",
            $t.thread
          ]
        | @tsv
    '
}

# Run one notmuch search inside the work scope.
# A query typed a character at a time is a syntax error most of the time
# ("iomart and", an unclosed quote). When notmuch rejects it, fall back to the
# raw words as literal terms, and emit nothing rather than an error if that
# also fails.
run_search() {
    local user_query="$1" limit="$2" full json

    if [[ -z "${user_query// /}" ]]; then
        full="$WORK_SCOPE"
    else
        full="$WORK_SCOPE and ( $user_query )"
    fi

    if json=$(notmuch search --format=json --sort=newest-first --limit="$limit" -- "$full" 2>/dev/null); then
        printf '%s' "$json" | records_from_json
        return 0
    fi

    local -a terms
    mapfile -t terms < <(query_terms "$user_query")
    [[ ${#terms[@]} -eq 0 ]] && return 0

    local literal
    literal=$(printf '"%s" and ' "${terms[@]}")
    literal="${literal% and }"

    if json=$(notmuch search --format=json --sort=newest-first --limit="$limit" -- "$WORK_SCOPE and ( $literal )" 2>/dev/null); then
        printf '%s' "$json" | records_from_json
    fi
    return 0
}

search_records() {
    local query="${1:-}"
    if [[ -z "${query// /}" ]]; then
        run_search "" "$DEFAULT_LIMIT"
    else
        run_search "$query" "$SEARCH_LIMIT"
    fi
}

# notmuch search --format=json returns a bare thread id. Callers may hand back
# either form, so normalise to a query before it reaches notmuch.
thread_query() {
    local t="${1#thread:}"
    [[ -z "$t" ]] && return 1
    printf 'thread:%s' "$t"
}

# Render one thread and mark the query terms inside it.
# Nothing is preloaded into the record: 21k message bodies in an fzf haystack
# is the build this deliberately is not. notmuch show costs ~8ms per thread.
preview_thread() {
    local thread query="${2:-}" rendered
    thread=$(thread_query "${1:-}") || return 0

    # --format=text wraps everything in message{ / header{ / body{ / part{
    # delimiters and repeats the maildir filename. That is machine framing, not
    # something to read at 3am in a preview pane, so strip it back to the mail.
    rendered=$(notmuch show --format=text --body=true --include-html=false --entire-thread=true -- "$thread" 2>/dev/null \
        | sed -E '/^\x0c?(message|header|body|part|attachment)[{}]/d; /^ *↳? *filename:/d; /^\x0c/d') || return 0
    [[ -z "$rendered" ]] && return 0

    local -a terms
    mapfile -t terms < <(query_terms "$query")
    printf '%s\n' "$rendered" | highlight_and_jump "${terms[@]}"
}

# The message-id of the newest message in a thread, which is what Gmail and
# any reply flow need.
thread_message_id() {
    local thread
    thread=$(thread_query "${1:-}") || return 0
    notmuch search --output=messages --sort=newest-first --limit=1 -- "$thread" 2>/dev/null \
        | head -1 | sed 's/^id://'
}

# Act on whatever the picker returned
handle_selection() {
    local key="$1" selection="$2" thread msgid
    thread=$(printf '%s' "$selection" | cut -f3)
    [[ -z "$thread" ]] && return 0

    case "$key" in
        ctrl-r)
            # Hand it to the agent rather than answering it by hand.
            # Detached: the popup this ran from is already aborting.
            setsid "$(dirname "$SCRIPT_PATH")/__mail_agent_spawn.sh" "$thread" \
                > /dev/null 2>&1 &
            ;;
        ctrl-y)
            msgid=$(thread_message_id "$thread")
            [[ -z "$msgid" ]] && return 0
            local permalink="https://mail.google.com/mail/u/0/#search/rfc822msgid:${msgid}"
            printf '%s' "$permalink" | xclip -selection clipboard
            echo "✓ Copied Gmail permalink: $permalink" >&2
            ;;
        tab)
            msgid=$(thread_message_id "$thread")
            [[ -z "$msgid" ]] && return 0
            # Mirrors __file_opener.sh PASTE_BIND so it lands in the underlying pane
            tmux set-buffer -- "$msgid"
            tmux run-shell -b "sleep 0.1 && tmux paste-buffer"
            ;;
        *)
            # Open the thread as a notmuch virtual mailbox. neomutt is built
            # +notmuch, and the muttrc already uses this URL form.
            local nm_query
            nm_query=$(thread_query "$thread") || return 0
            tmux new-window -n mail \
                "neomutt -R -f 'notmuch://${HOME}/.local/share/mail?query=${nm_query}'"
            ;;
    esac
}

picker() {
    local selected key selection
    selected=$(fzf \
        --delimiter=$'\t' \
        --with-nth=1,2 \
        --nth=1,2 \
        --no-hscroll \
        --disabled \
        --ansi \
        --preview "$SCRIPT_PATH preview {3} {q}" \
        --preview-window 'right:55%:wrap' \
        --header 'Work mail, full text over subject + body + participants | Enter:neomutt C-r:ask ursula C-y:copy link Tab:paste id C-p:preview Esc:quit' \
        --prompt 'Search work mail> ' \
        --bind 'ctrl-p:toggle-preview' \
        --bind 'ctrl-c:abort' \
        --bind "start:reload:$SCRIPT_PATH search {q} || true" \
        --bind "change:reload:sleep 0.3; $SCRIPT_PATH search {q} || true" \
        --expect=ctrl-y,tab,ctrl-r < /dev/null)

    key=$(printf '%s\n' "$selected" | sed -n '1p')
    selection=$(printf '%s\n' "$selected" | sed -n '2,$p')

    [[ -n "$selection" ]] && handle_selection "$key" "$selection"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        search)
            search_records "${2:-}"
            ;;
        preview)
            preview_thread "${2:-}" "${3:-}"
            ;;
        *)
            picker
            ;;
    esac
fi
