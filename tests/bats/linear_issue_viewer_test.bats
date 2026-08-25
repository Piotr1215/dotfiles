#!/usr/bin/env bats

# Covers the full-text search plumbing in __linear_issue_viewer.sh: the record
# format that carries descriptions and comments, the fzf argument set that has
# to match against them, and the preview highlighting built on the query.

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${REPO_ROOT}/scripts/__linear_issue_viewer.sh"
    FIXTURE="${REPO_ROOT}/tests/fixtures/linear_issue_viewer_response.json"

    # Sourcing runs nothing: the entry point is guarded on BASH_SOURCE == $0.
    # The env vars keep the ~/.envrc fallback from firing during a test run.
    LINEAR_API_KEY=test-key \
        LINEAR_OPS_TEAM_ID=ops \
        LINEAR_DOCS_TEAM_ID=docs \
        LINEAR_IT_TEAM_ID=it
    export LINEAR_API_KEY LINEAR_OPS_TEAM_ID LINEAR_DOCS_TEAM_ID LINEAR_IT_TEAM_ID
    # shellcheck source=/dev/null
    source "${SCRIPT}"

    INDEX="${BATS_TEST_TMPDIR}/index.tsv"
    format_issues < "${FIXTURE}" > "${INDEX}"
}

@test "format_issues emits one four-field record per issue" {
    run wc -l < "${INDEX}"
    [ "$output" -eq 2 ]

    run bash -c "awk -F'\t' '{print NF}' '${INDEX}' | sort -u"
    [ "$output" = "4" ]
}

@test "the haystack carries description and comment text" {
    run bash -c "cut -f2 '${INDEX}' | grep -c quokkavault"
    [ "$output" -eq 1 ]

    run bash -c "cut -f2 '${INDEX}' | grep -c 'revocation does not take both down'"
    [ "$output" -eq 1 ]
}

@test "the display column stays free of comment text" {
    run bash -c "cut -f1 '${INDEX}' | grep -c quokkavault || true"
    [ "$output" -eq 0 ]

    run bash -c "cut -f1 '${INDEX}' | head -1"
    [[ "$output" == *"OPS-101"* ]]
    [[ "$output" == *"In Progress"* ]]
    [[ "$output" == *"Ada Lovelace"* ]]
    [[ "$output" == *"rotate the deploy key"* ]]
}

@test "the fzf argument set matches a term that only exists in a comment" {
    # Regression: --with-nth transforms the line before --nth applies to it, so
    # a haystack hidden from the display is also hidden from the search.
    local -a common
    mapfile -t common < <(fzf_common_args)

    run bash -c "fzf $(printf '%q ' "${common[@]}") --filter=\"'quokkavault\" < '${INDEX}' | cut -f1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPS-101"* ]]
}

@test "an unmatched term returns nothing" {
    local -a common
    mapfile -t common < <(fzf_common_args)

    run bash -c "fzf $(printf '%q ' "${common[@]}") --filter=\"'nosuchtermanywhere\" < '${INDEX}' | wc -l"
    [ "$output" -eq 0 ]
}

@test "the preview body decodes to markdown holding the comment" {
    run bash -c "head -1 '${INDEX}' | cut -f4 | base64 -d"
    [[ "$output" == *"# OPS-101"* ]]
    [[ "$output" == *"## Comments (1)"* ]]
    [[ "$output" == *"Grace Hopper"* ]]
    [[ "$output" == *"quokkavault"* ]]
}

@test "issues without a description, assignee or comments still format" {
    run bash -c "sed -n 2p '${INDEX}' | cut -f1"
    [[ "$output" == *"DOC-202"* ]]
    [[ "$output" == *"Unassigned"* ]]

    run bash -c "sed -n 2p '${INDEX}' | cut -f4 | base64 -d"
    [[ "$output" == *"_No description._" ]]
    [[ "$output" != *"## Comments"* ]]
}

@test "searchIssues responses format the same as issues responses" {
    jq '{data: {searchIssues: .data.issues}}' "${FIXTURE}" > "${BATS_TEST_TMPDIR}/search.json"

    run format_issues < "${BATS_TEST_TMPDIR}/search.json"
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" == *"OPS-101"* ]]
}

# query_terms and highlight_and_jump now live in __lib_fzf_search_preview.sh
# and are covered by lib_fzf_search_preview_test.bats. What stays here is the
# viewer wiring: that the preview command actually reaches them.

@test "the preview marks a term that only appears in a comment" {
    local b64
    b64=$(head -1 "${INDEX}" | cut -f4)

    run bash -c "FZF_PREVIEW_COLUMNS=80 FZF_PREVIEW_LINES=40 \
        '${SCRIPT}' preview '${b64}' quokkavault"
    [[ "$output" == *$'\e[7mquokkavault\e[27m'* ]]
}

@test "the preview renders without a query" {
    local b64
    b64=$(head -1 "${INDEX}" | cut -f4)

    run bash -c "FZF_PREVIEW_COLUMNS=80 FZF_PREVIEW_LINES=40 '${SCRIPT}' preview '${b64}' ''"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPS-101"* ]]
}
