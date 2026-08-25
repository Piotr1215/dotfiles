#!/usr/bin/env bash

# __linear_issue_viewer.sh
# Linear issue picker for the OPS, DOC and IT teams with full-text search.
#
# Two modes:
#   list   (default) the open issues, fuzzy-searched over title, description
#          and every comment body
#   search (Ctrl+S) live server-side search across every issue, including
#          closed and archived ones, via searchIssues
#
# In both modes the preview renders the issue with its comments, marks the
# search terms in reverse video, and jumps to the first one when it sits below
# the fold, so a hit inside a long comment is visible without scrolling.
#
# Usage: ./__linear_issue_viewer.sh [list|search <term>|preview <base64> [query]]
# Keybindings:
#   Enter  - Open issue in browser
#   Ctrl+Y - Copy issue URL to clipboard
#   Tab    - Paste issue URL at the cursor in the underlying pane
#   Ctrl+S - Switch to server-side search
#   Ctrl+P - Toggle the preview pane

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

# query_terms and highlight_and_jump: the backend-agnostic preview half,
# shared with the other full-text pickers.
# shellcheck source=scripts/__lib_fzf_search_preview.sh
source "$(dirname "$SCRIPT_PATH")/__lib_fzf_search_preview.sh"

# Source .envrc if running from autokey or other environments without LINEAR vars
if [[ -z "${LINEAR_API_KEY}" ]] && [[ -f ~/.envrc ]]; then
    # shellcheck source=/dev/null
    source ~/.envrc
fi

# Validate necessary environment variables
validate_env_vars() {
    local required_vars=(LINEAR_API_KEY LINEAR_OPS_TEAM_ID LINEAR_DOCS_TEAM_ID LINEAR_IT_TEAM_ID)
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "Error: Environment variable $var is not set." >&2
            exit 1
        fi
    done
}

# The fields every query pulls. description and comments are what make the
# search full-text: they are never displayed in the list column, they go into a
# hidden column that fzf still matches against.
issue_fields() {
    cat <<'GQL'
        identifier
        title
        url
        description
        state { name }
        team { key }
        assignee { name }
        priority
        updatedAt
        comments(first: 50) { nodes { body createdAt user { name } } }
GQL
}

team_filter() {
    printf 'team: { id: { in: ["%s", "%s", "%s"] } }' \
        "$LINEAR_OPS_TEAM_ID" "$LINEAR_DOCS_TEAM_ID" "$LINEAR_IT_TEAM_ID"
}

# POST a GraphQL query, fail loudly on errors
linear_graphql() {
    local query="$1" response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: $LINEAR_API_KEY" \
        --data "$(jq -n --arg query "$query" '{query: $query}')" \
        https://api.linear.app/graphql)

    if printf '%s\n' "$response" | jq -e '.errors' > /dev/null 2>&1; then
        echo "Error fetching issues from Linear:" >&2
        printf '%s\n' "$response" | jq '.errors' >&2
        exit 1
    fi

    printf '%s\n' "$response"
}

# Fetch open issues from Linear for OPS, DOC, and IT teams
fetch_linear_issues() {
    linear_graphql 'query {
        issues(
            first: 200
            filter: {
                state: { name: { nin: ["Released", "Closed", "Canceled", "Done"] } }
                '"$(team_filter)"'
            }
            orderBy: updatedAt
        ) {
            nodes {
'"$(issue_fields)"'
            }
        }
    }'
}

# Server-side full-text search over title, description and comments. Unlike the
# list query this reaches closed and archived issues, so it is the only way to
# find something in an issue that has already been shipped.
search_linear_issues() {
    local term="$1"
    [[ -z "$term" ]] && return 0
    linear_graphql 'query {
        searchIssues(
            first: 100
            term: '"$(jq -Rn --arg t "$term" '$t')"'
            includeComments: true
            includeArchived: true
            filter: { '"$(team_filter)"' }
        ) {
            nodes {
'"$(issue_fields)"'
            }
        }
    }'
}

# Column the haystack is pushed out to. fzf applies --nth to the line AFTER
# --with-nth has transformed it, so a field dropped from the display is also
# dropped from the search: the only way to have both is to keep the haystack in
# the displayed line and park it past the right edge, where --no-hscroll keeps
# it. 400 clears any plausible width for the list half of the popup.
HAYSTACK_COLUMN=400

# One tab-separated record per issue:
#   1 display     what the list shows, padded out to HAYSTACK_COLUMN
#   2 haystack    title + description + comments, flattened to one line
#   3 url         opened, copied or pasted on selection
#   4 body        base64 markdown rendered in the preview pane
# @tsv keeps every record on a single line.
format_issues() {
    jq -r --argjson haystack_column "$HAYSTACK_COLUMN" '
        def prio_icon:
            if . == 1 then "🔴"
            elif . == 2 then "🟠"
            elif . == 3 then "🟡"
            elif . == 4 then "🔵"
            else "⚪" end;
        def pad($n): tostring | . + ((" " * ($n - length)) // "");
        # split/join, not gsub: the jq regex engine takes seconds over 200 issue
        # bodies, plain string splits take milliseconds.
        def flat: (. // "") | split("\n") | join(" ") | split("\r") | join(" ") | split("\t") | join(" ");

        ((.data.issues // .data.searchIssues).nodes // [])[]
        | . as $i
        | [$i.comments.nodes[]?] as $c
        | (($i.priority | prio_icon) + " "
           + ($i.identifier | pad(13))
           + ($i.state.name | .[0:12] | pad(13))
           + (($i.assignee.name // "Unassigned") | .[0:15] | pad(16))
           + ($i.title // "") | pad($haystack_column)) as $display
        | ([$i.title, ($i.description // ""), ($i.assignee.name // "Unassigned"), $i.state.name]
           + [$c[].body] | join(" ") | flat) as $haystack
        | ("# " + $i.identifier + "  " + ($i.title // "") + "\n\n"
           + "`" + $i.state.name + "` · `" + ($i.assignee.name // "Unassigned") + "`"
           + " · " + $i.team.key + " · updated " + (($i.updatedAt // "") | split("T")[0]) + "\n\n"
           + "---\n\n"
           + (if (($i.description // "") | length) > 0 then $i.description else "_No description._" end)
           + (if ($c | length) > 0
              then "\n\n---\n\n## Comments (" + ($c | length | tostring) + ")\n\n"
                   + ([$c[]
                       | "**" + (.user.name // "unknown") + "** · " + ((.createdAt // "") | split("T")[0])
                         + "\n\n" + (.body // "")]
                      | join("\n\n---\n\n"))
              else "" end)) as $body
        | [$display, $haystack, $i.url, ($body | @base64)] | @tsv
    '
}

# Render one issue in the preview pane. fzf calls this back with field 4 and
# the live query, so the preview re-renders as the query changes.
render_preview() {
    local body rendered
    local -a terms
    body=$(printf '%s' "$1" | base64 -d 2>/dev/null) || return 0
    [[ -z "$body" ]] && return 0

    if command -v glow > /dev/null 2>&1; then
        rendered=$(printf '%s\n' "$body" | glow -s dark -w "${FZF_PREVIEW_COLUMNS:-80}" 2>/dev/null)
    fi
    if [[ -z "$rendered" ]]; then
        rendered=$(printf '%s\n' "$body" | bat --language=md --color=always --style=plain 2>/dev/null) \
            || rendered="$body"
    fi

    mapfile -t terms < <(query_terms "${2:-}")
    printf '%s\n' "$rendered" | highlight_and_jump "${terms[@]}"
}

# Act on whatever the picker returned
handle_selection() {
    local key="$1" selection="$2" url
    url=$(printf '%s' "$selection" | cut -f3)
    [[ -z "$url" ]] && return 0

    if [[ "$key" == "tab" ]]; then
        # Paste URL at cursor: set tmux buffer, schedule paste after popup closes
        # (mirrors __file_opener.sh PASTE_BIND so the URL lands in the underlying pane)
        tmux set-buffer -- "$url"
        tmux run-shell -b "sleep 0.1 && tmux paste-buffer"
    elif [[ "$key" == "ctrl-y" ]]; then
        echo -n "$url" | xclip -selection clipboard
        echo "✓ Copied issue URL to clipboard: $url" >&2
    else
        # Open in browser (default action), backgrounded so it doesn't block the popup.
        # Swap to the alacritty/browser split (layout 2) once the tab is open.
        tmux run-shell -b "xdg-open '$url' >/dev/null 2>&1 && __focus_browser.sh && ~/dev/dotfiles/scripts/__layouts.sh 2"
    fi
}

fzf_common_args() {
    printf '%s\n' \
        --delimiter=$'\t' \
        --with-nth=1,2 \
        --nth=1,2 \
        --no-hscroll \
        --preview "$SCRIPT_PATH preview {4} {q}" \
        --preview-window 'right:50%:wrap' \
        --bind 'ctrl-p:toggle-preview' \
        --bind 'ctrl-c:abort'
}

# The open-issues list. Everything is already local, so matching a word from a
# comment is as fast as matching the title.
list_mode() {
    local formatted_issues issue_count selected query key selection
    local -a common
    echo "Fetching Linear issues from OPS, DOC, and IT teams..." >&2

    formatted_issues=$(fetch_linear_issues | format_issues)

    if [[ -z "$formatted_issues" ]]; then
        echo "No issues found." >&2
        read -rp "Press Enter to exit..."
        exit 0
    fi

    issue_count=$(printf '%s\n' "$formatted_issues" | wc -l)

    mapfile -t common < <(fzf_common_args)
    # --print-query so Ctrl+S can carry whatever was already typed into the
    # server-side search instead of making it be typed twice.
    selected=$(printf '%s\n' "$formatted_issues" | fzf "${common[@]}" \
        --print-query \
        --header "Linear: $issue_count open, searching title + description + comments | Enter:open C-y:copy Tab:paste C-s:search everything C-p:preview" \
        --prompt "Search issues> " \
        --expect=ctrl-y,tab,ctrl-s)

    query=$(printf '%s\n' "$selected" | sed -n '1p')
    key=$(printf '%s\n' "$selected" | sed -n '2p')
    selection=$(printf '%s\n' "$selected" | sed -n '3,$p')

    if [[ "$key" == "ctrl-s" ]]; then
        # Hand Linear the words, not the fzf operators wrapped around them.
        local seed
        seed=$(query_terms "$query" | tr '\n' ' ')
        search_mode "${seed%"${seed##*[![:space:]]}"}"
        return
    fi

    [[ -n "$selection" ]] && handle_selection "$key" "$selection"
}

# Live server-side search. Each keystroke re-queries Linear after a short
# debounce, which is the only way to reach the closed and archived issues the
# list never loads. --disabled hands the query to Linear instead of to fzf.
search_mode() {
    local seed="${1:-}" selected key selection
    local -a common
    mapfile -t common < <(fzf_common_args)
    selected=$(fzf "${common[@]}" \
        --disabled \
        --query "$seed" \
        --header 'Linear full-text search over every issue, closed and archived included | Enter:open C-y:copy Tab:paste C-p:preview Esc:quit' \
        --prompt "Linear search> " \
        --bind "start:reload:$SCRIPT_PATH search {q} || true" \
        --bind "change:reload:sleep 0.4; $SCRIPT_PATH search {q} || true" \
        --expect=ctrl-y,tab < /dev/null)

    key=$(printf '%s\n' "$selected" | sed -n '1p')
    selection=$(printf '%s\n' "$selected" | sed -n '2,$p')

    [[ -n "$selection" ]] && handle_selection "$key" "$selection"
}

# Execute main only if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        search)
            validate_env_vars
            search_linear_issues "${2:-}" | format_issues
            ;;
        preview)
            render_preview "${2:-}" "${3:-}"
            ;;
        *)
            validate_env_vars
            list_mode
            ;;
    esac
fi
