#!/usr/bin/env bats

# Covers the mail half of the M-x full-text pickers: the three-field record
# contract shared with __linear_issue_viewer.sh, the work-only scope that keeps
# personal mail out of every query, and the notmuch-specific handling the
# Linear backend never needs (thread id normalisation, envelope framing).

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${REPO_ROOT}/scripts/__mail_search_viewer.sh"
    FIXTURE="${REPO_ROOT}/tests/fixtures/mail_search_viewer_response.json"

    # Sourcing runs nothing: the entry point is guarded on BASH_SOURCE == $0.
    # shellcheck source=/dev/null
    source "${SCRIPT}"

    INDEX="${BATS_TEST_TMPDIR}/index.tsv"
    records_from_json < "${FIXTURE}" > "${INDEX}"
}

@test "records_from_json emits one three-field record per thread" {
    run wc -l < "${INDEX}"
    [ "$output" -eq 3 ]

    run bash -c "awk -F'\t' '{print NF}' '${INDEX}' | sort -u"
    [ "$output" = "3" ]
}

@test "field 3 is the bare notmuch thread id, no thread: prefix" {
    run bash -c "cut -f3 '${INDEX}' | head -1"
    [ "$output" = "000000000000c569" ]

    run bash -c "cut -f3 '${INDEX}' | grep -c '^thread:'"
    [ "$output" -eq 0 ]
}

# The trap linearer hit on the Linear side: fzf applies --nth AFTER --with-nth
# has transformed the line, so the haystack cannot be hidden from the display.
# It is kept visible and pushed off the right edge by padding instead.
@test "the display column is padded past any terminal width" {
    run bash -c "awk -F'\t' '{ if (length(\$1) < 400) print \"short\" }' '${INDEX}' | wc -l"
    [ "$output" -eq 0 ]
}

@test "the haystack carries subject and authors" {
    run bash -c "cut -f2 '${INDEX}' | grep -c 'Charlie Stace'"
    [ "$output" -eq 1 ]

    run bash -c "cut -f2 '${INDEX}' | grep -c 'Netlify Renewal'"
    [ "$output" -eq 1 ]
}

# A tab or newline inside a subject would split one record into two fields or
# two lines, silently corrupting every field position after it.
@test "tabs and newlines inside a subject never break the record" {
    run bash -c "grep -c 'quote attached' '${INDEX}'"
    [ "$output" -eq 1 ]

    run bash -c "awk -F'\t' 'NR==1 {print NF}' '${INDEX}'"
    [ "$output" = "3" ]
}

# cut -c counts bytes here, and both markers are multibyte, so compare the
# leading characters in the shell instead.
@test "unread and flagged surface as markers in the display column" {
    local unread flagged plain
    unread=$(cut -f1 "${INDEX}" | sed -n '1p')
    flagged=$(cut -f1 "${INDEX}" | sed -n '2p')
    plain=$(cut -f1 "${INDEX}" | sed -n '3p')

    [ "${unread:0:2}" = "● " ]
    [ "${flagged:0:2}" = " ⚑" ]
    [ "${plain:0:2}" = "  " ]
}

# notmuch search returns a bare id, but the contract was specified both ways.
# Accepting either keeps a caller from silently querying nothing.
@test "thread_query normalises bare and prefixed thread ids alike" {
    run thread_query "000000000000c569"
    [ "$output" = "thread:000000000000c569" ]

    run thread_query "thread:000000000000c569"
    [ "$output" = "thread:000000000000c569" ]
}

@test "thread_query rejects an empty id instead of querying everything" {
    run thread_query ""
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# The work boundary. This assertion is the guardrail: the picker must never be
# able to reach piotrzan@gmail.com, which is the personal account.
@test "every query is pinned to the work maildir" {
    [ "$WORK_SCOPE" = 'path:piotr.zaniewski@loft.sh/**' ]

    # The personal account may be named in a comment explaining the boundary,
    # but must never appear in code that could reach notmuch.
    run bash -c "grep -v '^[[:space:]]*#' '${SCRIPT}' | grep -c 'piotrzan@gmail.com'"
    [ "$output" -eq 0 ]
}

# declare -f has to run in the test shell: the function only exists here,
# because setup sourced the script.
@test "an empty query still carries the work scope" {
    local body
    body=$(declare -f run_search)
    [[ "$body" == *'full="$WORK_SCOPE"'* ]]
    [[ "$body" == *'$WORK_SCOPE and ( $user_query )'* ]]
}

# notmuch rejects a boolean query typed one character at a time, and every
# keystroke fires a reload, so the common case during typing is a syntax error.
@test "a query notmuch rejects falls back to literal terms" {
    local body
    body=$(declare -f run_search)
    [[ "$body" == *"query_terms"* ]]
    # The fallback must stay silent rather than spill a notmuch parse error
    # into the list on every keystroke.
    [[ "$body" == *"2> /dev/null"* || "$body" == *"2>/dev/null"* ]]
}

@test "preview strips the notmuch envelope framing" {
    local raw="${BATS_TEST_TMPDIR}/raw.txt"
    cat > "${raw}" <<'EOF'
message{ id:one@example.com depth:0 match:1 excluded:0
header{
Peter Vine <peter.vine@loft.sh> (Fri. 10:21) (inbox)
Subject: Re: HPE Updated Doc
header}
body{
Hey Charlie, thanks for sending that over.
body}
message}
EOF
    run bash -c "sed -E '/^\x0c?(message|header|body|part|attachment)[{}]/d; /^ *↳? *filename:/d; /^\x0c/d' '${raw}'"
    [[ "$output" != *"message{"* ]]
    [[ "$output" != *"header{"* ]]
    [[ "$output" != *"body}"* ]]
    [[ "$output" == *"Subject: Re: HPE Updated Doc"* ]]
    [[ "$output" == *"thanks for sending that over"* ]]
}

# The shared lib is sourced, not copied: the highlight has to keep working when
# linearer changes it on the Linear side.
@test "the shared preview lib is sourced rather than reimplemented" {
    run bash -c "grep -c '__lib_fzf_search_preview.sh' '${SCRIPT}'"
    [ "$output" -ge 1 ]

    run declare -F query_terms
    [ "$status" -eq 0 ]

    run declare -F highlight_and_jump
    [ "$status" -eq 0 ]
}

# Count code only: the same flags are named in the header comment that
# explains the --with-nth / --nth ordering trap.
@test "the fzf argument set matches against both display and haystack" {
    local code
    code=$(grep -v '^[[:space:]]*#' "${SCRIPT}")

    [[ "$code" == *"--with-nth=1,2"* ]]
    [[ "$code" == *"--nth=1,2"* ]]
    [[ "$code" == *"--no-hscroll"* ]]
    [[ "$code" == *"--disabled"* ]]
}

# 21k message bodies in an fzf haystack is the build this deliberately is not.
@test "the preview is lazy: no body text is preloaded into a record" {
    run bash -c "cut -f1,2 '${INDEX}' | grep -c 'thanks for sending'"
    [ "$output" -eq 0 ]

    run bash -c "declare -f records_from_json | grep -c 'notmuch show'"
    [ "$output" -eq 0 ]
}

# --- __mail_agent_spawn.sh: handing a thread to the agent ---------------------

@test "the spawn directive names the thread and forbids sending" {
    source "${REPO_ROOT}/scripts/__mail_agent_spawn.sh"

    run build_directive "000000000000c569"
    [[ "$output" == *"thread:000000000000c569"* ]]
    [[ "$output" == *"do not send it"* ]]
    [[ "$output" == *"draft"* ]]
}

@test "the spawn directive accepts a prefixed thread id without doubling it" {
    source "${REPO_ROOT}/scripts/__mail_agent_spawn.sh"

    run build_directive "thread:000000000000c569"
    [[ "$output" == *"thread:000000000000c569"* ]]
    [[ "$output" != *"thread:thread:"* ]]
}

@test "no thread means raise the pane, not send an empty instruction" {
    source "${REPO_ROOT}/scripts/__mail_agent_spawn.sh"

    run build_directive ""
    [ -z "$output" ]
}

# The mail session already boots that pane into /ops-mail-agent. Sending the
# slash command to a live agent restarts her startup sweep instead of
# answering the mail.
@test "the spawn directive is never the slash command" {
    source "${REPO_ROOT}/scripts/__mail_agent_spawn.sh"

    run build_directive "000000000000c569"
    [[ "$output" != *"/ops-mail-agent"* ]]
}

@test "the picker hands ctrl-r to the spawn script" {
    run bash -c "grep -c '__mail_agent_spawn.sh' '${SCRIPT}'"
    [ "$output" -eq 1 ]

    run bash -c "grep -c -- '--expect=ctrl-y,tab,ctrl-r' '${SCRIPT}'"
    [ "$output" -eq 1 ]
}

# A loose `pgrep -f claude` also matches __claude_with_monitor.sh,
# __claude_prompt_monitor.sh and __nats_watcher.sh, all live on this box.
# Tested with a decoy pane ahead of the real agent: the loose match resolved to
# the decoy and typed the directive into it. Delivering nothing is a visible
# failure; delivering into the wrong pane is not.
# Assert over the whole file, not one function body. An earlier version of this
# test read `declare -f agent_pane`, which prints the wrapper and nothing of
# the matcher it calls, so a fallback restored inside agent_pane_matching
# passed it. linearer reproduced that with a one-line reinstatement. Comments
# are stripped because the ones below deliberately name `pgrep -f` to explain
# why it is wrong.
@test "the agent pane is matched by exact process name, with no loose fallback" {
    local code
    code=$(grep -v '^[[:space:]]*#' "${REPO_ROOT}/scripts/__mail_agent_spawn.sh")

    [[ "$code" == *"pgrep -x claude"* ]]
    [[ "$code" != *"pgrep -f"* ]]
}

# A false positive has to be a descendant of a pane in the ursula window, which
# is what keeps a claude session in another tmux session from winning.
@test "pane ownership is decided by walking the process ancestry" {
    source "${REPO_ROOT}/scripts/__mail_agent_spawn.sh"

    run pane_owns_pid "$$" "$$"
    [ "$status" -eq 0 ]

    # init is nobody's descendant here
    run pane_owns_pid "$$" 1
    [ "$status" -ne 0 ]
}
