#!/usr/bin/env bash
# PROJECT: gordon
# Today's daily note in the Obsidian vault: create it from the vault's daily
# note template when it is missing, then print its absolute path.
#
# Usage: __daily_note.sh [--pin]
#   --pin   make today's note the first pin in Gordon's tmux pane. Older
#           daily notes and retired handoff pins are removed.
#
# The folder and template come from the vault's .obsidian/daily-notes.json,
# the settings Obsidian's own Daily notes plugin reads, so a note made here and
# one made in Obsidian are the same file. Only the YYYY-MM-DD format is read.
# The template's {{date}} and {{title}} become the day.
#
# Gordon's pane is the one his hooks recognise: @agent_name triage or gordon,
# or a window or session named gordon; $TMUX_PANE wins when it is one. Its pin
# store is the one __gordon_pin.sh keeps for it, panes/<n>/pins.tsv under
# GORDON_PINS_DIR for TMUX_PANE=%<n>, written under that store's flock.
#
# Env (tests): DAILY_NOTE_VAULT (default ~/dev/obsidian/decoder),
# DAILY_NOTE_DATE (a `date -d` day, default today), GORDON_PINS_DIR,
# HANDOFFS_FILE.
#
# WHY: Piotr, 26 Oct: "your chat is fleeting 'in the moment' information ...
# maybe we can use and pin daily obsidian note file?". Gordon writes the day's
# calls, decisions and commitments here, where the vault's repo keeps them.
set -eo pipefail

vault="${DAILY_NOTE_VAULT:-$HOME/dev/obsidian/decoder}"
handoffs="${HANDOFFS_FILE:-$HOME/.local/state/gordon/handoffs/index.md}"
legacy_handoffs="${HANDOFFS_LEGACY_FILE:-${handoffs%/*}.md}"
pins_base="${GORDON_PINS_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/gordon-pins}"
TAB=$'\t'

# Print an error line and exit 1.
die() {
    echo "__daily_note.sh: $*" >&2
    exit 1
}

# Print the value of key $1 in the vault's daily-notes.json, empty when unset.
setting() {
    local cfg="$vault/.obsidian/daily-notes.json"
    [[ -f "$cfg" ]] || return 0
    jq -r --arg k "$1" '.[$k] // empty' "$cfg"
}

# Print the daily notes folder as an absolute path.
daily_dir() {
    local folder
    folder=$(setting folder)
    folder=${folder%/}
    if [[ -n "$folder" ]]; then echo "$vault/$folder"; else echo "$vault"; fi
}

# Create note $1 for day $2 from the template unless it exists. An unset
# template gives an empty note, as Obsidian does.
create_note() {
    local note=$1 day=$2 template body=''
    [[ -e "$note" ]] && return 0
    template=$(setting template)
    if [[ -n "$template" ]]; then
        template="$vault/${template%.md}.md"
        [[ -f "$template" ]] || die "template not found: $template"
        body=$(<"$template")
        body=${body//'{{date}}'/$day}
        body=${body//'{{title}}'/$day}
        body+=$'\n'
    fi
    mkdir -p "${note%/*}"
    # noclobber creates with O_EXCL, so a note made meanwhile is never overwritten.
    (set -C && printf '%s' "$body" >"$note") 2>/dev/null || [[ -e "$note" ]] || die "cannot write $note"
}

# Print Gordon's pane id: $TMUX_PANE when it is Gordon's, else the first such
# pane tmux lists. Print nothing when there is none.
gordon_pane() {
    { tmux list-panes -a -F "#{pane_id}${TAB}#{@agent_name}${TAB}#{window_name}${TAB}#{session_name}" 2>/dev/null || true; } |
        awk -F'\t' -v me="${TMUX_PANE:-}" '
            $2 == "triage" || $2 == "gordon" || $3 == "gordon" || $4 == "gordon" {
                if ($1 == me) { mine = $1 }
                if (first == "") { first = $1 }
            }
            END { if (mine != "") print mine; else if (first != "") print first }'
}

# True when pins.tsv line $1 pins a daily note in folder $2.
is_daily_pin() {
    [[ "$1" == "note${TAB}$2/"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md ]]
}

# Make note $1 the first pin, preserving unrelated pins and removing retired boards.
pin_note() {
    local note=$1 dir="$pins_base/panes/${2#%}" folder line want=() rest=()
    local pins="$dir/pins.tsv"
    folder=$(daily_dir)
    mkdir -p "$dir"
    exec 9>"$dir/.lock"
    flock 9
    if [[ -f "$pins" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            [[ "$line" == "note${TAB}$handoffs" ]] && continue
            [[ "$line" == "note${TAB}$legacy_handoffs" ]] && continue
            is_daily_pin "$line" "$folder" && continue
            rest+=("$line")
        done <"$pins"
    fi
    want=("note${TAB}$note" "${rest[@]}")
    if [[ -f "$pins" ]] && [[ "$(<"$pins")" == "$(printf '%s\n' "${want[@]}")" ]]; then
        return 0
    fi
    printf '%s\n' "${want[@]}" >"$pins.tmp.$$"
    mv -f "$pins.tmp.$$" "$pins"
}

main() {
    local pin='' day format note pane
    case "${1:-}" in
    '') ;;
    --pin) pin=1 ;;
    *) die "usage: __daily_note.sh [--pin]" ;;
    esac
    format=$(setting format)
    [[ -z "$format" || "$format" == YYYY-MM-DD ]] || die "unsupported daily note format: $format"
    day=$(date -d "${DAILY_NOTE_DATE:-today}" +%Y-%m-%d) || die "bad DAILY_NOTE_DATE: $DAILY_NOTE_DATE"
    note="$(daily_dir)/$day.md"
    create_note "$note" "$day"
    if [[ -n "$pin" ]]; then
        pane=$(gordon_pane)
        if [[ -n "$pane" ]]; then pin_note "$note" "$pane"; else echo "no Gordon pane, not pinned" >&2; fi
    fi
    echo "$note"
}

main "$@"
