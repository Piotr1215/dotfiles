#!/usr/bin/env bats

# The backend-agnostic preview half shared by the full-text pickers. These
# tests source the library directly, so they hold whether the records came from
# Linear, notmuch, or anything added later.

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    LIB="${REPO_ROOT}/scripts/__lib_fzf_search_preview.sh"
    # shellcheck source=/dev/null
    source "${LIB}"
}

@test "query_terms strips fzf operators and drops negations" {
    run query_terms "'quokkavault ^ops key\$ !ignoreme x"
    [ "${lines[0]}" = "quokkavault" ]
    [ "${lines[1]}" = "ops" ]
    [ "${lines[2]}" = "key" ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "query_terms keeps a quoted phrase whole" {
    run query_terms '"rotate the deploy key" extra'
    [ "${lines[0]}" = "rotate the deploy key" ]
    [ "${lines[1]}" = "extra" ]
}

@test "query_terms returns nothing for an empty query" {
    run query_terms ""
    [ "$output" = "" ]
}

@test "highlight_and_jump marks every term in reverse video" {
    run bash -c "printf 'alpha\nbeta\n' | (source '${LIB}'; highlight_and_jump beta)"
    [[ "$output" == *$'\e[7mbeta\e[27m'* ]]
    [[ "$output" == *"alpha"* ]]
}

@test "highlight_and_jump matches case-insensitively" {
    run bash -c "printf 'Stacked PRs\n' | (source '${LIB}'; highlight_and_jump stacked)"
    [[ "$output" == *$'\e[7mStacked\e[27m'* ]]
}

@test "highlight_and_jump marks a term the renderer wrapped codes around" {
    # Matching runs on an ANSI-stripped copy, so a styled line still resolves.
    run bash -c "printf '\e[1mneedle\e[0m here\n' | (source '${LIB}'; highlight_and_jump needle)"
    [[ "$output" == *$'\e[7mneedle\e[27m'* ]]
}

@test "highlight_and_jump passes the text through when there is no query" {
    run bash -c "printf 'alpha\nbeta\n' | (source '${LIB}'; highlight_and_jump)"
    [ "$output" = "alpha
beta" ]
}

@test "highlight_and_jump jumps to a match below the fold, keeping the heading" {
    run bash -c "seq 1 60 | sed '55s/.*/needle/' | \
        (source '${LIB}'; FZF_PREVIEW_LINES=20 highlight_and_jump needle)"
    [ "${lines[0]}" = "1" ]
    [ "${lines[2]}" = "3" ]
    [[ "${lines[3]}" == *". . ."* ]]
    [ "${lines[4]}" = "53" ]
    [[ "$output" != *$'\n''30'$'\n'* ]]
}

@test "highlight_and_jump leaves an early match in place" {
    run bash -c "seq 1 60 | sed '3s/.*/needle/' | \
        (source '${LIB}'; FZF_PREVIEW_LINES=20 highlight_and_jump needle)"
    [[ "$output" != *". . ."* ]]
    [ "${lines[0]}" = "1" ]
}

@test "highlight_and_jump works on plain notmuch-style output" {
    # No renderer, no ANSI: the mail picker pipes notmuch show straight in.
    run bash -c "printf 'Subject: deploy key\nFrom: ada\n\nblocked on quokkavault\n' | \
        (source '${LIB}'; highlight_and_jump quokkavault)"
    [[ "$output" == *$'\e[7mquokkavault\e[27m'* ]]
    [[ "$output" == *"Subject: deploy key"* ]]
}
