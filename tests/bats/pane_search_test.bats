#!/usr/bin/env bats

# Pane text search index (__lib_pane_search.sh): agent-only filter, dedupe,
# agent labels, cockpit order, and the all-panes toggle view. tmux is stubbed.

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    LIB="${REPO_ROOT}/scripts/__lib_pane_search.sh"
    TEST_DIR="$(mktemp -d)"
    export PANE_SEARCH_ORDER_CACHE="${TEST_DIR}/order_cache"
    export PATH="${TEST_DIR}:${PATH}"

    # Panes: %1 task gordon (triage), %2 task intake, %3 task shell,
    # %4 board margin, %5 sess-x agent without @agent_name.
    cat > "${TEST_DIR}/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    printf '%s\n' '%1|task|1|1|triage' '%2|task|2|1|intake' '%3|task|1|3|' '%4|task|1|4|' '%5|sess-x|1|1|'
    ;;
  capture-pane)
    pane="${*: -1}"
    cat "${TEST_DIR}/cap${pane}"
    ;;
esac
STUB
    chmod +x "${TEST_DIR}/tmux"
    export TEST_DIR

    printf 'kendra said hi\nother\n\nkendra said hi\ntail\n' > "${TEST_DIR}/cap%1"
    printf 'intake line\n  intake line  \n' > "${TEST_DIR}/cap%2"
    printf 'shell kendra\n' > "${TEST_DIR}/cap%3"
    printf 'HANDOFFS kendra board\n' > "${TEST_DIR}/cap%4"
    printf 'sess line\n' > "${TEST_DIR}/cap%5"
    # Cockpit order: sess-x first, then intake, then gordon. Margin and shell absent.
    export PANE_SEARCH_ORDER_CMD="printf '%s\n' %5 %2 %1"
    # shellcheck source=/dev/null
    source "$LIB"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "agents view skips shell and board panes" {
    run pane_search_index agents
    [[ "$output" != *"shell kendra"* ]]
    [[ "$output" != *"HANDOFFS"* ]]
}

@test "agents view follows cockpit order" {
    run pane_search_index agents
    labels=$(printf '%s\n' "$output" | cut -f2 | uniq | paste -sd, -)
    [ "$labels" = "sess-x,intake,gordon" ]
}

@test "agents view keeps one copy of a repeated line, the newest" {
    run pane_search_index agents
    [ "$(printf '%s\n' "$output" | grep -c 'kendra said hi')" -eq 1 ]
    # newest copy sits after "other": order is other, kendra said hi, tail
    texts=$(printf '%s\n' "$output" | awk -F'\t' '$2=="gordon"{print $3}' | paste -sd, -)
    [ "$texts" = "other,kendra said hi,tail" ]
}

@test "dedupe ignores surrounding whitespace" {
    run pane_search_index agents
    [ "$(printf '%s\n' "$output" | awk -F'\t' '$2=="intake"' | wc -l)" -eq 1 ]
}

@test "rows carry pane id, agent label, text" {
    run pane_search_index agents
    [[ "$output" == *$'%5\tsess-x\tsess line'* ]]
}

@test "triage in session task is labelled gordon, no agent_name falls back to session" {
    [ "$(pane_search_label task triage)" = "gordon" ]
    [ "$(pane_search_label other triage)" = "other" ]
    [ "$(pane_search_label sess-x '')" = "sess-x" ]
    [ "$(pane_search_label task intake)" = "intake" ]
}

@test "toggle view lists every pane with session:win.pane labels and no dedupe" {
    run pane_search_index all
    [[ "$output" == *$'%3\ttask:1.3\tshell kendra'* ]]
    [[ "$output" == *$'%4\ttask:1.4\tHANDOFFS kendra board'* ]]
    [ "$(printf '%s\n' "$output" | grep -c 'kendra said hi')" -eq 2 ]
}

@test "order entries for unknown panes are ignored" {
    export PANE_SEARCH_ORDER_CMD="printf '%s\n' %99 %2"
    rm -f "$PANE_SEARCH_ORDER_CACHE"
    run pane_search_index agents
    labels=$(printf '%s\n' "$output" | cut -f2 | uniq | paste -sd, -)
    [ "$labels" = "intake" ]
}

@test "order is cached so a second open does not recompute" {
    run pane_search_index agents
    export PANE_SEARCH_ORDER_CMD="false"
    run pane_search_index agents
    labels=$(printf '%s\n' "$output" | cut -f2 | uniq | paste -sd, -)
    [ "$labels" = "sess-x,intake,gordon" ]
}

@test "file opener wires the toggle key and header" {
    grep -q 'C-t:all panes/agents' "${REPO_ROOT}/scripts/__file_opener.sh"
    grep -q 'ctrl-t:transform' "${REPO_ROOT}/scripts/__file_opener.sh"
}
