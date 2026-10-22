#!/usr/bin/env bats

# Test suite for __pr_movement_nudge.sh: the classification and dedup logic that
# decides whether a PR movement is worth a DM, which PRs are watched (authored
# plus task-linked), the batched GraphQL fetch, the merged/closed edges, and the
# intake/triage routing.
#
# Run from anywhere:  bats tests/bats/pr_movement_nudge_test.bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR
    SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__pr_movement_nudge.sh"
    # Env first: the sourced helpers read it at load time. Nothing here touches
    # the real state, log, lock or gh account.
    export PR_MOVE_STATE="${TEST_DIR}/state.json"
    export PR_MOVE_SUMMARY="${TEST_DIR}/summary.json"
    export PR_MOVE_LOG="${TEST_DIR}/log"
    export PR_MOVE_LOCK="${TEST_DIR}/lock"
    export PR_MOVE_ME="Piotr1215"
    export PR_MOVE_SELF_LOGINS="claude[bot]"
    export PR_MOVE_HANDOFF_CHECK="${TEST_DIR}/no-handoff-check"
    # Source only the helpers, not the flock/main tail that would run a real cycle.
    sed '/^# --- main ---$/,$d' "$SCRIPT" > "${TEST_DIR}/fns.sh"
    # shellcheck source=/dev/null
    source "${TEST_DIR}/fns.sh"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

# checks_for ROLLUP_JSON -> the .checks verdict compute_sig derives from it
checks_for() {
    compute_sig "{\"statusCheckRollup\":$1}" | jq -r '.checks'
}

# --- checks classification ---------------------------------------------------

@test "compute_sig: a CANCELLED re-run beside a same-named SUCCESS is not red" {
    # loft-sh/vcluster#4084: a concurrency group cancelled the in-flight run when
    # a new commit landed, so the rollup kept the aborted row next to the re-run
    # that succeeded. The PR was green and MERGEABLE, yet the watcher DM'd ci-red
    # every hour because CANCELLED was in the failure set. (regression for that)
    run checks_for '[{"name":"build","conclusion":"CANCELLED","status":"COMPLETED"},
                     {"name":"build","conclusion":"SUCCESS","status":"COMPLETED"}]'
    [ "$output" = "SUCCESS" ]
}

@test "compute_sig: CANCELLED alone is not red" {
    run checks_for '[{"name":"e2e","conclusion":"CANCELLED","status":"COMPLETED"}]'
    [ "$output" = "SUCCESS" ]
}

@test "compute_sig: a real FAILURE is still red" {
    run checks_for '[{"name":"e2e","conclusion":"FAILURE","status":"COMPLETED"}]'
    [ "$output" = "FAILURE" ]
}

@test "compute_sig: TIMED_OUT and STARTUP_FAILURE are still red" {
    run checks_for '[{"name":"e2e","conclusion":"TIMED_OUT","status":"COMPLETED"}]'
    [ "$output" = "FAILURE" ]
    run checks_for '[{"name":"e2e","conclusion":"STARTUP_FAILURE","status":"COMPLETED"}]'
    [ "$output" = "FAILURE" ]
}

@test "compute_sig: a legacy StatusContext state=FAILURE is still red" {
    run checks_for '[{"context":"legacy/ci","state":"FAILURE"}]'
    [ "$output" = "FAILURE" ]
}

@test "compute_sig: a real FAILURE still wins alongside a CANCELLED row" {
    run checks_for '[{"name":"a","conclusion":"CANCELLED","status":"COMPLETED"},
                     {"name":"b","conclusion":"FAILURE","status":"COMPLETED"}]'
    [ "$output" = "FAILURE" ]
}

@test "compute_sig: SKIPPED and NEUTRAL are green" {
    run checks_for '[{"name":"a","conclusion":"SKIPPED","status":"COMPLETED"},
                     {"name":"b","conclusion":"NEUTRAL","status":"COMPLETED"}]'
    [ "$output" = "SUCCESS" ]
}

@test "compute_sig: an in-flight check is PENDING, not red" {
    run checks_for '[{"name":"a","status":"IN_PROGRESS"}]'
    [ "$output" = "PENDING" ]
}

@test "compute_sig: an empty rollup is NONE" {
    run checks_for '[]'
    [ "$output" = "NONE" ]
}

# --- sticky dedup ------------------------------------------------------------

@test "sticky_set: reports every true sticky state in canonical order" {
    run sticky_set '{"changesRequested":true,"checks":"FAILURE","mergeable":"CONFLICTING"}'
    [ "$output" = '["changes-requested","ci-red","merge-conflict"]' ]
}

@test "sticky_set: a clean PR has no sticky reasons" {
    run sticky_set '{"changesRequested":false,"checks":"SUCCESS","mergeable":"MERGEABLE"}'
    [ "$output" = '[]' ]
}

@test "sticky_new: an already-notified reason stays silent" {
    # The dedup itself: vcluster-pro#1510 sat CHANGES_REQUESTED + CONFLICTING all
    # morning and re-DM'd on two desynced hourly timers.
    run sticky_new '["changes-requested","merge-conflict"]' '["changes-requested","merge-conflict"]'
    [ -z "$output" ]
}

@test "sticky_new: only the newly-entered reason fires" {
    # Alert-on-new-state must survive the dedup: merge-conflict is new, and
    # changes-requested (already sent) must not ride along again.
    run sticky_new '["changes-requested","merge-conflict"]' '["changes-requested"]'
    [ "$output" = "merge-conflict" ]
}

@test "sticky_new: every reason fires when nothing has been notified yet" {
    run sticky_new '["ci-red","merge-conflict"]' '[]'
    [ "${lines[0]}" = "ci-red" ]
    [ "${lines[1]}" = "merge-conflict" ]
}

@test "sticky_new: a reason that cleared and returned fires again" {
    run sticky_new '["ci-red"]' '[]'
    [ "$output" = "ci-red" ]
}

# --- bare ci-red noise suppression (unchanged behavior, guarded) --------------

@test "ci_red_is_noise: CI and dependency PR titles suppress a bare ci-red" {
    run ci_red_is_noise "ci(release): migrate sync_linear to the shared action"
    [ "$status" -eq 0 ]
    run ci_red_is_noise "chore(deps): bump golang.org/x/net to 0.38.0"
    [ "$status" -eq 0 ]
}

@test "ci_red_is_noise: a normal code PR does not suppress ci-red" {
    run ci_red_is_noise "fix(syncer): stop dropping events on resync"
    [ "$status" -ne 0 ]
}

# --- harness for the tests below ---------------------------------------------
# Stubs for gh, task, node, tmux and the routing helper go on PATH ahead of the
# real ones; the real script runs as a subprocess against a temp state file.

# e2e_setup: build the stubs and per-test fixtures.
e2e_setup() {
    BIN="${TEST_DIR}/bin"; mkdir -p "$BIN"
    GQL_DIR="${TEST_DIR}/gql"; mkdir -p "$GQL_DIR"
    GH_LOG="${TEST_DIR}/gh.log"; : > "$GH_LOG"
    DMS="${TEST_DIR}/dms"; : > "$DMS"
    TASKS_FILE="${TEST_DIR}/tasks.json"; echo '[]' > "$TASKS_FILE"
    SEARCH_FILE="${TEST_DIR}/search.json"; echo '[]' > "$SEARCH_FILE"
    MERGED_FILE="${TEST_DIR}/merged.json"; echo '[]' > "$MERGED_FILE"
    BOT_FILE="${TEST_DIR}/bot.json"; echo '[]' > "$BOT_FILE"
    ROUTE_FILE="${TEST_DIR}/route"; echo triage > "$ROUTE_FILE"
    TMUX_SESSIONS_FILE="${TEST_DIR}/tmux-sessions"; : > "$TMUX_SESSIONS_FILE"
    export BIN GQL_DIR GH_LOG DMS TASKS_FILE SEARCH_FILE MERGED_FILE BOT_FILE ROUTE_FILE TMUX_SESSIONS_FILE
    export GH_GQL_FAIL="${TEST_DIR}/gql-fail" GH_SOURCES_FAIL="${TEST_DIR}/sources-fail"

    cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "search prs")
    case "$*" in
      *user-review-requested:*) echo '[]' ;;
      *) echo "other: $*" >> "$GH_LOG"; echo '[]' ;;
    esac ;;
  "api user") echo Piotr1215 ;;
  "api graphql")
    q=""; for a in "$@"; do case "$a" in query=*) q="${a#query=}" ;; esac; done
    # The sources call: Piotr's open PRs (SEARCH_FILE), his merged ones
    # (MERGED_FILE, [{owner, repo, num}]) and the backport bot's (BOT_FILE).
    if grep -q '^  viewer {' <<<"$q"; then
      echo "sources bot=$(grep -oE 'user\(login: "[^"]+"\)' <<<"$q")" >> "$GH_LOG"
      [ ! -f "$GH_SOURCES_FAIL" ] || { echo "stub: sources error" >&2; exit 1; }
      jq -n --slurpfile a "$SEARCH_FILE" --slurpfile m "$MERGED_FILE" --slurpfile b "$BOT_FILE" '
        {data: {viewer: {open: {pageInfo: {hasNextPage: false}, nodes: $a[0]},
                         merged: {nodes: [$m[0][] | {number: .num, repository: {nameWithOwner: "\(.owner)/\(.repo)"}}]}},
                bot: {pullRequests: {pageInfo: {hasNextPage: false}, nodes: $b[0]}}}}'
      exit 0
    fi
    echo "graphql aliases=$(grep -cE '^p[0-9]+: repository' <<<"$q")" >> "$GH_LOG"
    if [ -f "$GH_GQL_FAIL" ] && grep -qF "$(cat "$GH_GQL_FAIL")" <<<"$q"; then
      echo "stub: server error" >&2; exit 1
    fi
    resp='{"data":{}}'; missing=0
    while IFS= read -r line; do
      al=$(sed -E 's/^(p[0-9]+):.*/\1/' <<<"$line")
      o=$(sed -E 's/.*owner: "([^"]+)".*/\1/' <<<"$line")
      r=$(sed -E 's/.*name: "([^"]+)".*/\1/' <<<"$line")
      n=$(sed -E 's/.*number: ([0-9]+).*/\1/' <<<"$line")
      f="$GQL_DIR/$(tr 'A-Z' 'a-z' <<<"${o}_${r}_${n}").json"
      if [ -f "$f" ]; then
        resp=$(jq -c --arg a "$al" --slurpfile n "$f" '.data[$a] = {pullRequest: $n[0]}' <<<"$resp")
      else
        resp=$(jq -c --arg a "$al" '.data[$a] = {pullRequest: null}' <<<"$resp"); missing=1
      fi
    done < <(grep -oE 'p[0-9]+: repository\(owner: "[^"]+", name: "[^"]+"\) \{ pullRequest\(number: [0-9]+\)' <<<"$q")
    printf '%s\n' "$resp"
    # gh prints the data and still exits 1 when one alias had an error
    [ "$missing" -eq 0 ] || exit 1 ;;
  *) echo "other: $*" >> "$GH_LOG"; echo '[]' ;;
esac
STUB
    cat > "$BIN/task" <<'STUB'
#!/usr/bin/env bash
[ -f "$TASKS_FILE.fail" ] && exit 1
cat "$TASKS_FILE"
STUB
    cat > "$BIN/node" <<'STUB'
#!/usr/bin/env bash
target="$3"; shift 3
printf '%s: %s\n' "$target" "$*" >> "$DMS"
STUB
    cat > "$BIN/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  list-sessions) cat "$TMUX_SESSIONS_FILE" ;;
  list-panes) echo "%1" ;;
  *) : ;;
esac
STUB
    cat > "$BIN/intake-route" <<'STUB'
#!/usr/bin/env bash
cat "$ROUTE_FILE"
STUB
    chmod +x "$BIN"/*
    export INTAKE_ROUTE_BIN="$BIN/intake-route"
    export SND_NODE_BIN="${TEST_DIR}/snd.js"
}

# add_task UUID STATUS DESCRIPTION [ANNOTATION...]: append a task to the export.
add_task() {
    local u="$1" st="$2" d="$3"; shift 3
    local anns
    anns=$(printf '%s\n' "$@" | jq -R . | jq -sc 'map(select(. != "")) | map({entry: "20261022T072533Z", description: .})')
    jq -c --arg u "$u" --arg st "$st" --arg d "$d" --argjson a "$anns" \
        '. + [{uuid: $u, status: $st, description: $d, tags: ["gordon", "work"], annotations: $a}]' \
        "$TASKS_FILE" > "${TASKS_FILE}.new" && mv "${TASKS_FILE}.new" "$TASKS_FILE"
}

# gql_node OWNER REPO NUM [STATE REVIEW_DECISION MERGEABLE CONCLUSION HEAD_AUTHOR PR_AUTHOR]:
# what GitHub's GraphQL returns for that PR, as a fixture the gh stub serves.
gql_node() {
    local o="$1" r="$2" n="$3" st="${4:-OPEN}" rd="${5:-REVIEW_REQUIRED}" mg="${6:-MERGEABLE}"
    local concl="${7:-SUCCESS}" head="${8:-Piotr1215}" pa="${9:-Piotr1215}"
    jq -n --arg o "$o" --arg r "$r" --argjson n "$n" --arg st "$st" --arg rd "$rd" --arg mg "$mg" \
          --arg concl "$concl" --arg head "$head" --arg pa "$pa" '
        {number: $n, url: "https://github.com/\($o)/\($r)/pull/\($n)", title: "feat: work", isDraft: false,
         state: $st, merged: ($st == "MERGED"), closed: ($st != "OPEN"),
         headRefOid: "sha-\($head)", reviewDecision: $rd, mergeable: $mg, author: {login: $pa},
         reviews: {nodes: []}, comments: {nodes: []},
         commits: {nodes: [{commit: {oid: "sha-\($head)", committedDate: "2026-07-02T08:00:00Z",
                                     authoredDate: "2026-07-02T08:00:00Z",
                                     authors: {nodes: [{user: {login: $head}}]},
                                     statusCheckRollup: {contexts: {nodes:
                                        [{__typename: "CheckRun", name: "ci", status: "COMPLETED", conclusion: $concl}]}}}}]}}' \
        > "$GQL_DIR/$(tr 'A-Z' 'a-z' <<<"${o}_${r}_${n}").json"
}

# set_search OWNER REPO NUM: Piotr's one open authored PR (viewer.open).
set_search() {
    jq -n --arg o "$1" --arg r "$2" --argjson n "$3" \
        '[{url: "https://github.com/\($o)/\($r)/pull/\($n)", number: $n, title: "feat: work",
           repository: {name: $r, nameWithOwner: "\($o)/\($r)"}, isDraft: false}]' > "$SEARCH_FILE"
}

# bot_pr OWNER REPO NUM TITLE [BODY]: one open PR in the backport bot's list.
bot_pr() {
    jq --arg o "$1" --arg r "$2" --argjson n "$3" --arg t "$4" --arg b "${5:-}" \
        '. + [{url: "https://github.com/\($o)/\($r)/pull/\($n)", number: $n, title: $t, body: $b, isDraft: false,
               repository: {name: $r, nameWithOwner: "\($o)/\($r)"}}]' "$BOT_FILE" > "${BOT_FILE}.new" \
        && mv "${BOT_FILE}.new" "$BOT_FILE"
}

# run_nudge [MODE]: one cycle of the real script (default --live).
run_nudge() {
    PATH="$BIN:$PATH" bash "$SCRIPT" "${1:---live}" > "${TEST_DIR}/run.out" 2>&1
}

dms() { cat "$DMS"; }
gql_calls() { grep -c '^graphql' "$GH_LOG" || true; }

# --- task-linked PR enumeration ----------------------------------------------

@test "task_pr_links: finds a PR URL in a description and in an annotation, +gordon task included" {
    TASKS_FILE="${TEST_DIR}/tasks.json"; echo '[]' > "$TASKS_FILE"
    add_task 7debf451-2d63-40d4-9df0-a687b763646c pending "PR 8827 vite bump (dependabot) awaiting approval: watch" \
        "Left for Piotr: approval + merge https://github.com/loft-sh/loft-enterprise/pull/8827 (you have ruleset bypass)."
    add_task aaaaaaaa-0000-0000-0000-000000000001 pending "Review https://github.com/loft-sh/vcluster/pull/4084 today"
    task() { cat "$TASKS_FILE"; }
    run task_pr_links
    [ "$status" -eq 0 ]
    [ "$(jq -c 'map(select(.num == 8827)) | .[0]' <<<"$output")" = '{"owner":"loft-sh","repo":"loft-enterprise","num":8827,"task":"7debf451"}' ]
    [ "$(jq -c 'map(select(.num == 4084)) | .[0]' <<<"$output")" = '{"owner":"loft-sh","repo":"vcluster","num":4084,"task":"aaaaaaaa"}' ]
    [ "$(jq 'length' <<<"$output")" -eq 2 ]
}

@test "task_pr_links: only pending tasks count, and a repeated link is one row" {
    TASKS_FILE="${TEST_DIR}/tasks.json"; echo '[]' > "$TASKS_FILE"
    add_task bbbbbbbb-0000-0000-0000-000000000001 completed "done https://github.com/loft-sh/vcluster/pull/1"
    add_task cccccccc-0000-0000-0000-000000000001 waiting "later https://github.com/loft-sh/vcluster/pull/2"
    add_task dddddddd-0000-0000-0000-000000000001 pending "twice https://github.com/loft-sh/vcluster/pull/3" \
        "again HTTPS://GitHub.com/loft-sh/vcluster/pull/3/files"
    add_task eeeeeeee-0000-0000-0000-000000000001 pending "not a PR https://github.com/loft-sh/vcluster/issues/9 or loft-sh/vcluster#9"
    task() { cat "$TASKS_FILE"; }
    run task_pr_links
    [ "$(jq -c 'map(.num)' <<<"$output")" = '[3]' ]
}

@test "task_pr_links: fails when task fails, so the caller can tell from an empty list" {
    task() { return 1; }
    run task_pr_links
    [ "$status" -ne 0 ]
}

@test "build_watch: an authored PR also linked by two tasks is one item naming both" {
    local authored links
    authored='[{"url":"https://github.com/loft-sh/loft-enterprise/pull/8827","number":8827,"title":"t","repository":{"name":"loft-enterprise","nameWithOwner":"loft-sh/loft-enterprise"},"isDraft":false}]'
    links='[{"owner":"loft-sh","repo":"loft-enterprise","num":8827,"task":"bbbbbbbb"},{"owner":"Loft-SH","repo":"loft-enterprise","num":8827,"task":"7debf451"}]'
    run build_watch "$authored" "$links" 0 <<<'{}'
    [ "$(jq 'length' <<<"$output")" -eq 1 ]
    [ "$(jq -c '.[0] | [.key, .authored, .watch, .tasks, .skip]' <<<"$output")" = '["loft-sh/loft-enterprise#8827",true,true,["7debf451","bbbbbbbb"],""]' ]
}

@test "build_watch: org scope, drafts and already-terminal task PRs are skipped before any fetch" {
    local authored links state
    authored='[{"url":"u1","number":1,"title":"t","repository":{"name":"d","nameWithOwner":"loft-sh/d"},"isDraft":true}]'
    links='[{"owner":"someone","repo":"fork","num":2,"task":"11111111"},{"owner":"loft-sh","repo":"old","num":3,"task":"22222222"},{"owner":"loft-sh","repo":"new","num":4,"task":"33333333"}]'
    state='{"https://github.com/loft-sh/old/pull/3":{"ref":"loft-sh/old#3","url":"https://github.com/loft-sh/old/pull/3","terminal":"merged"}}'
    run build_watch "$authored" "$links" 0 <<<"$state"
    [ "$(jq -r '.[] | select(.num == 1) | .skip' <<<"$output")" = "draft" ]
    [ "$(jq -r '.[] | select(.num == 2) | .skip' <<<"$output")" = "org" ]
    [ "$(jq -r '.[] | select(.num == 3) | .skip' <<<"$output")" = "terminal" ]
    [ "$(jq -r '.[] | select(.num == 4) | .skip' <<<"$output")" = "" ]
}

@test "build_watch: a PR only the state names is tracked inside the window and ignored outside it" {
    local state
    state='{"u1":{"ref":"loft-sh/a#1","url":"https://github.com/loft-sh/a/pull/1","seenOpen":1000,"tasks":["99999999"]},
            "u2":{"ref":"loft-sh/b#2","url":"https://github.com/loft-sh/b/pull/2","seenOpen":10},
            "u3":{"ref":"loft-sh/c#3","url":"https://github.com/loft-sh/c/pull/3"},
            "_reviewRequests":["x"]}'
    run build_watch '[]' '[]' 500 <<<"$state"
    [ "$(jq -c 'map([.key, .watch, .tasks])' <<<"$output")" = '[["loft-sh/a#1",false,["99999999"]]]' ]
}

# --- GraphQL mapping ----------------------------------------------------------

@test "gql_to_view then compute_sig: the signature matches what gh pr view gave" {
    local node view sig
    node='{"number":7,"url":"u","title":"t","isDraft":false,"state":"OPEN","merged":false,"closed":false,
      "headRefOid":"abc","reviewDecision":"CHANGES_REQUESTED","mergeable":"CONFLICTING","author":{"login":"Piotr1215"},
      "reviews":{"nodes":[{"author":{"login":"denis"},"submittedAt":"2026-07-02T10:00:00Z"},
                          {"author":{"login":"github-actions"},"submittedAt":"2026-07-02T12:00:00Z"},
                          {"author":null,"submittedAt":"2026-07-02T13:00:00Z"}]},
      "comments":{"nodes":[{"author":{"login":"Piotr1215"},"createdAt":"2026-07-02T14:00:00Z"},
                           {"author":{"login":"caue"},"createdAt":"2026-07-02T11:00:00Z"}]},
      "commits":{"nodes":[{"commit":{"oid":"abc","committedDate":"2026-07-02T09:00:00Z","authoredDate":"2026-07-02T08:00:00Z",
                 "authors":{"nodes":[{"user":{"login":"djwfyi"}},{"user":null}]},
                 "statusCheckRollup":{"contexts":{"nodes":[
                    {"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"CANCELLED"},
                    {"__typename":"CheckRun","name":"b","status":"COMPLETED","conclusion":"FAILURE"},
                    {"__typename":"StatusContext","context":"legacy","state":"SUCCESS"}]}}}}]}}'
    view=$(gql_to_view "$node")
    sig=$(compute_sig "$view")
    [ "$(jq -r '.headSha' <<<"$sig")" = "abc" ]
    [ "$(jq -r '.checks' <<<"$sig")" = "FAILURE" ]
    [ "$(jq -r '.mergeable' <<<"$sig")" = "CONFLICTING" ]
    [ "$(jq -r '.changesRequested' <<<"$sig")" = "true" ]
    [ "$(jq -r '.lastCommitMine' <<<"$sig")" = "false" ]
    [ "$(jq -r '.lastCommitKnownAuthors' <<<"$sig")" = "1" ]
    [ "$(jq -r '.lastCommitDate' <<<"$sig")" = "2026-07-02T09:00:00Z" ]
    # newest FOREIGN activity: caue's comment (the bot, Piotr and a deleted user do not count)
    [ "$(jq -r '.lastForeignActivity' <<<"$sig")" = "2026-07-02T11:00:00Z" ]
}

@test "gql_to_view: an empty PR (no reviews, comments, commits) maps to empty lists, not errors" {
    run gql_to_view '{"number":1,"url":"u","reviews":null,"comments":{"nodes":[]},"commits":{"nodes":[]}}'
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.reviews, .comments, .commits, .statusCheckRollup]' <<<"$output")" = '[[],[],[],[]]' ]
}

# --- merged / closed edges -----------------------------------------------------

@test "merged: a task-linked PR is seeded open, fires once on the edge into merged, then stays quiet" {
    e2e_setup
    add_task 7debf451-2d63-40d4-9df0-a687b763646c pending "PR 8827 vite bump (dependabot) awaiting approval: watch" \
        "Left for Piotr: merge https://github.com/loft-sh/loft-enterprise/pull/8827"
    gql_node loft-sh loft-enterprise 8827 OPEN
    run_nudge
    [ -z "$(dms)" ]
    gql_node loft-sh loft-enterprise 8827 MERGED
    run_nudge
    [ "$(dms)" = "triage: pr-move: loft-sh/loft-enterprise#8827 merged https://github.com/loft-sh/loft-enterprise/pull/8827 task:7debf451" ]
    : > "$DMS"; : > "$GH_LOG"
    run_nudge
    [ -z "$(dms)" ]
    # a merged PR that stays linked is not fetched again
    [ "$(gql_calls)" -eq 0 ]
}

@test "merged: a state entry from before seenOpen existed seeds silently instead of replaying history" {
    # The state file held every PR Piotr ever authored. One of them, long closed,
    # is now cited by a task: its old entry says "open" about some past day, not
    # about the last cycle, so closing must not read as a fresh movement.
    e2e_setup
    add_task d3ab8470-0000-0000-0000-000000000000 pending "see https://github.com/loft-sh/support/pull/8"
    jq -n '{"https://github.com/loft-sh/support/pull/8": {ref: "loft-sh/support#8", url: "https://github.com/loft-sh/support/pull/8",
            headSha: "x", notifiedSticky: [], lastSeen: 1792675000}}' > "$PR_MOVE_STATE"
    gql_node loft-sh support 8 CLOSED
    run_nudge
    [ -z "$(dms)" ]
    grep -q "seed (first contact, already closed): loft-sh/support#8" "${TEST_DIR}/log"
}

@test "closed: a task-linked PR closed without merge fires once as closed" {
    e2e_setup
    add_task 7debf451-2d63-40d4-9df0-a687b763646c pending "watch https://github.com/loft-sh/vcluster/pull/4084"
    gql_node loft-sh vcluster 4084 OPEN
    run_nudge
    gql_node loft-sh vcluster 4084 CLOSED
    run_nudge
    [ "$(dms)" = "triage: pr-move: loft-sh/vcluster#4084 closed https://github.com/loft-sh/vcluster/pull/4084 task:7debf451" ]
    : > "$DMS"
    run_nudge
    [ -z "$(dms)" ]
}

@test "merged: a PR first seen already merged seeds silently" {
    e2e_setup
    add_task 7debf451-2d63-40d4-9df0-a687b763646c pending "old context https://github.com/loft-sh/vcluster/pull/100"
    gql_node loft-sh vcluster 100 MERGED
    run_nudge
    [ -z "$(dms)" ]
    grep -q "seed (first contact, already merged): loft-sh/vcluster#100" "${TEST_DIR}/log"
}

@test "merged: an authored PR that leaves the open search is fetched once more and reported" {
    e2e_setup
    set_search loft-sh vcluster 5
    gql_node loft-sh vcluster 5 OPEN
    run_nudge
    [ -z "$(dms)" ]
    echo '[]' > "$SEARCH_FILE"
    gql_node loft-sh vcluster 5 MERGED
    run_nudge
    [ "$(dms)" = "triage: pr-move: loft-sh/vcluster#5 merged https://github.com/loft-sh/vcluster/pull/5" ]
    : > "$DMS"; : > "$GH_LOG"
    run_nudge
    [ -z "$(dms)" ]
    [ "$(gql_calls)" -eq 0 ]
    # the terminal entry is retired once no source names the PR
    [ "$(jq 'has("https://github.com/loft-sh/vcluster/pull/5")' "$PR_MOVE_STATE")" = "false" ]
}

@test "idle: a PR no source names that is still open keeps its baseline until the track window ends" {
    # gh search skips a PR for a cycle now and then; dropping its entry on the
    # first miss would lose the baseline and swallow the movement in between.
    e2e_setup
    set_search loft-sh vcluster 6
    gql_node loft-sh vcluster 6 OPEN
    run_nudge
    echo '[]' > "$SEARCH_FILE"
    run_nudge
    [ -z "$(dms)" ]
    [ "$(jq 'has("https://github.com/loft-sh/vcluster/pull/6")' "$PR_MOVE_STATE")" = "true" ]
    grep -q "idle (no source names it, still open): loft-sh/vcluster#6" "${TEST_DIR}/log"
    # back in the search: it moves against the old baseline, not as a stranger
    set_search loft-sh vcluster 6
    gql_node loft-sh vcluster 6 OPEN CHANGES_REQUESTED
    run_nudge
    [ "$(dms)" = "triage: pr-move: loft-sh/vcluster#6 changes-requested https://github.com/loft-sh/vcluster/pull/6" ]
}

@test "idle: past the track window the entry is retired without a nudge" {
    e2e_setup
    set_search loft-sh vcluster 6
    gql_node loft-sh vcluster 6 OPEN
    run_nudge
    echo '[]' > "$SEARCH_FILE"
    PR_MOVE_TRACK_WINDOW=-1 run_nudge
    [ -z "$(dms)" ]
    [ "$(jq 'has("https://github.com/loft-sh/vcluster/pull/6")' "$PR_MOVE_STATE")" = "false" ]
}

@test "state: a failed task export prunes nothing; a healthy run retires entries no source names" {
    e2e_setup
    jq -n '{"https://github.com/loft-sh/gone/pull/1": {ref: "loft-sh/gone#1", url: "https://github.com/loft-sh/gone/pull/1", headSha: "x"},
            "_reviewRequests": ["https://github.com/loft-sh/z/pull/9"]}' > "$PR_MOVE_STATE"
    touch "${TASKS_FILE}.fail"
    run_nudge
    [ "$(jq 'has("https://github.com/loft-sh/gone/pull/1")' "$PR_MOVE_STATE")" = "true" ]
    grep -q "WARN: pending task export failed" "${TEST_DIR}/log"
    rm -f "${TASKS_FILE}.fail"
    run_nudge
    [ "$(jq 'has("https://github.com/loft-sh/gone/pull/1")' "$PR_MOVE_STATE")" = "false" ]
    [ "$(jq -c '._reviewRequests' "$PR_MOVE_STATE")" = '[]' ]
}

# --- task-linked movement lines -------------------------------------------------

@test "movement on a task-linked PR names the owning task" {
    e2e_setup
    add_task 7debf451-2d63-40d4-9df0-a687b763646c pending "watch https://github.com/loft-sh/loft-enterprise/pull/8827"
    gql_node loft-sh loft-enterprise 8827 OPEN REVIEW_REQUIRED MERGEABLE SUCCESS dependabot[bot] dependabot[bot]
    run_nudge
    gql_node loft-sh loft-enterprise 8827 OPEN CHANGES_REQUESTED MERGEABLE SUCCESS dependabot[bot] dependabot[bot]
    run_nudge
    [ "$(dms)" = "triage: pr-move: loft-sh/loft-enterprise#8827 changes-requested https://github.com/loft-sh/loft-enterprise/pull/8827 task:7debf451" ]
}

@test "foreign-push stays quiet on a task-linked PR someone else authored, fires on one a self login authored" {
    e2e_setup
    add_task 7debf451-2d63-40d4-9df0-a687b763646c pending "other https://github.com/loft-sh/vcluster/pull/11"
    add_task 8debf451-2d63-40d4-9df0-a687b763646c pending "mine https://github.com/loft-sh/vcluster/pull/12"
    gql_node loft-sh vcluster 11 OPEN REVIEW_REQUIRED MERGEABLE SUCCESS alice alice
    gql_node loft-sh vcluster 12 OPEN REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 Piotr1215
    run_nudge
    gql_node loft-sh vcluster 11 OPEN REVIEW_REQUIRED MERGEABLE SUCCESS bob alice
    gql_node loft-sh vcluster 12 OPEN REVIEW_REQUIRED MERGEABLE SUCCESS bob Piotr1215
    run_nudge
    [ "$(dms)" = "triage: pr-move: loft-sh/vcluster#12 foreign-push https://github.com/loft-sh/vcluster/pull/12 task:8debf451" ]
}

# --- batched GraphQL fetch ------------------------------------------------------

# many_task_prs N: N distinct task-linked PRs (loft-sh/vcluster#1..N), all open.
many_task_prs() {
    local i
    jq -n --argjson n "$1" '[range(1; $n + 1) | {uuid: "aaaa\(. + 1000)-0000-0000-0000-000000000000", status: "pending",
        description: "t", tags: ["gordon"], annotations: [{entry: "20261022T072533Z", description: "https://github.com/loft-sh/vcluster/pull/\(.)"}]}]' > "$TASKS_FILE"
    for i in $(seq 1 "$1"); do gql_node loft-sh vcluster "$i" OPEN; done
}

@test "fetch: 65 PRs cost ceil(65/25) = 3 graphql calls, never one gh pr view per PR" {
    e2e_setup
    many_task_prs 65
    run_nudge
    [ "$(gql_calls)" -eq 3 ]
    [ "$(grep '^graphql' "$GH_LOG" | tr '\n' ' ')" = "graphql aliases=25 graphql aliases=25 graphql aliases=15 " ]
    ! grep -q '^other: pr view' "$GH_LOG"
    # every PR was read: all 65 seeded
    [ "$(jq '[to_entries[] | select(.key | startswith("https://"))] | length' "$PR_MOVE_STATE")" -eq 65 ]
}

@test "fetch: PR_MOVE_GQL_CHUNK sets the chunk size" {
    e2e_setup
    many_task_prs 25
    PR_MOVE_GQL_CHUNK=10 run_nudge
    [ "$(gql_calls)" -eq 3 ]
    [ "$(grep '^graphql' "$GH_LOG" | tr '\n' ' ')" = "graphql aliases=10 graphql aliases=10 graphql aliases=5 " ]
}

@test "fetch: a failed chunk logs a WARN and skips only its PRs" {
    e2e_setup
    many_task_prs 4
    echo 'pullRequest(number: 3)' > "$GH_GQL_FAIL"
    PR_MOVE_GQL_CHUNK=2 run_nudge
    [ "$(gql_calls)" -eq 2 ]
    grep -q "WARN: graphql chunk at offset 2 failed (2 PR(s))" "${TEST_DIR}/log"
    [ "$(jq -c '[keys[] | select(startswith("https://"))] | sort' "$PR_MOVE_STATE")" \
        = '["https://github.com/loft-sh/vcluster/pull/1","https://github.com/loft-sh/vcluster/pull/2"]' ]
    # the run still completed and reported
    grep -q "=== done:" "${TEST_DIR}/log"
}

@test "fetch: one PR GitHub cannot resolve logs a WARN and the rest of the chunk still lands" {
    e2e_setup
    many_task_prs 3
    rm -f "$GQL_DIR/loft-sh_vcluster_2.json"
    run_nudge
    grep -q "WARN: no GraphQL data for loft-sh/vcluster#2" "${TEST_DIR}/log"
    [ "$(jq -c '[keys[] | select(startswith("https://"))] | sort' "$PR_MOVE_STATE")" \
        = '["https://github.com/loft-sh/vcluster/pull/1","https://github.com/loft-sh/vcluster/pull/3"]' ]
}

@test "fetch: nothing to watch makes no graphql call" {
    e2e_setup
    run_nudge
    [ "$(gql_calls)" -eq 0 ]
}

# --- routing --------------------------------------------------------------------

# one_merge_event: seed an open task-linked PR, then merge it, so a single DM is sent.
one_merge_event() {
    add_task 7debf451-2d63-40d4-9df0-a687b763646c pending "watch https://github.com/loft-sh/vcluster/pull/21"
    gql_node loft-sh vcluster 21 OPEN
    run_nudge
    gql_node loft-sh vcluster 21 MERGED
    run_nudge
}

@test "routing: the DM goes to intake when the helper says intake" {
    e2e_setup
    echo intake > "$ROUTE_FILE"
    one_merge_event
    [ "$(dms)" = "intake: pr-move: loft-sh/vcluster#21 merged https://github.com/loft-sh/vcluster/pull/21 task:7debf451" ]
}

@test "routing: the DM goes to triage when the helper says triage" {
    e2e_setup
    echo triage > "$ROUTE_FILE"
    one_merge_event
    [ "$(dms | cut -d: -f1)" = "triage" ]
}

@test "routing: a missing helper means triage" {
    e2e_setup
    export INTAKE_ROUTE_BIN="${TEST_DIR}/does-not-exist"
    one_merge_event
    [ "$(dms | cut -d: -f1)" = "triage" ]
}

@test "routing: a helper that prints anything else means triage" {
    e2e_setup
    echo "kendra" > "$ROUTE_FILE"
    one_merge_event
    [ "$(dms | cut -d: -f1)" = "triage" ]
}

@test "routing: a failing helper means triage" {
    e2e_setup
    printf '#!/usr/bin/env bash\nexit 7\n' > "$BIN/intake-route"
    one_merge_event
    [ "$(dms | cut -d: -f1)" = "triage" ]
}

@test "routing: the target is resolved once per run" {
    e2e_setup
    printf '#!/usr/bin/env bash\necho x >> "%s/route-calls"\necho intake\n' "$TEST_DIR" > "$BIN/intake-route"
    many_task_prs 3
    run_nudge
    [ "$(wc -l < "${TEST_DIR}/route-calls")" -eq 1 ]
}

@test "routing: an owned PR reaches its owner plain and the target marked (owned by ...)" {
    e2e_setup
    echo intake > "$ROUTE_FILE"
    echo "vcluster-pr-21" > "$TMUX_SESSIONS_FILE"
    one_merge_event
    grep -qxF "vcluster-pr-21: pr-move: loft-sh/vcluster#21 merged https://github.com/loft-sh/vcluster/pull/21 task:7debf451" "$DMS"
    grep -qxF "intake: pr-move: loft-sh/vcluster#21 merged https://github.com/loft-sh/vcluster/pull/21 task:7debf451 (owned by vcluster-pr-21)" "$DMS"
}

@test "dry-run sends nothing, even to intake" {
    e2e_setup
    echo intake > "$ROUTE_FILE"
    add_task 7debf451-2d63-40d4-9df0-a687b763646c pending "watch https://github.com/loft-sh/vcluster/pull/21"
    gql_node loft-sh vcluster 21 OPEN
    run_nudge --dry-run
    gql_node loft-sh vcluster 21 MERGED
    run_nudge --dry-run
    [ -z "$(dms)" ]
    grep -q "\[DRY-RUN\] would send to intake -> pr-move: loft-sh/vcluster#21 merged" "${TEST_DIR}/log"
}

# --- status-line summary ----------------------------------------------------------

@test "summary: watched counts the PRs under watch, not terminal ones, and is its own small file" {
    e2e_setup
    add_task 7debf451-2d63-40d4-9df0-a687b763646c pending "a https://github.com/loft-sh/vcluster/pull/31 b https://github.com/loft-sh/vcluster/pull/32 c https://github.com/loft-sh/vcluster/pull/33"
    set_search loft-sh vcluster 34
    gql_node loft-sh vcluster 31 OPEN
    gql_node loft-sh vcluster 32 OPEN
    gql_node loft-sh vcluster 33 OPEN
    gql_node loft-sh vcluster 34 OPEN
    run_nudge
    [ "$(jq -r '.watched' "$PR_MOVE_SUMMARY")" = "4" ]
    [ "$(jq -r '.updated | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")' "$PR_MOVE_SUMMARY")" = "true" ]
    [ "$(jq -r '.epoch | type' "$PR_MOVE_SUMMARY")" = "number" ]
    gql_node loft-sh vcluster 32 MERGED
    run_nudge
    gql_node loft-sh vcluster 32 MERGED
    run_nudge
    [ "$(jq -r '.watched' "$PR_MOVE_SUMMARY")" = "3" ]
    # the state file keeps no meta key, so nothing that walks it meets a non-PR row
    [ "$(jq -r 'keys[] | select(startswith("_"))' "$PR_MOVE_STATE")" = "_reviewRequests" ]
}

# --- backports, sources and delivery ------------------------------------------------

@test "backport: a bot backport of Piotr's merged PR is watched, reports ci-red and merged, then retires" {
    # loft-enterprise#8833 merged and the bot opened #8851-#8857; none were
    # authored by Piotr or task-linked, so none were watched (22 Oct 2026).
    e2e_setup
    echo '[{"owner":"loft-sh","repo":"loft-enterprise","num":8833}]' > "$MERGED_FILE"
    bot_pr loft-sh loft-enterprise 8851 "[release-4.6] fix(ci): skip the mirror release step on sync push runs (#8833)" \
        $'Backport from `main` to `release-4.6`\n\nOriginal PR Nr.: #8833\n'
    gql_node loft-sh loft-enterprise 8851 OPEN REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 loft-bot
    run_nudge
    [ -z "$(dms)" ]
    grep -q "backports: 1" "${TEST_DIR}/log"
    gql_node loft-sh loft-enterprise 8851 OPEN REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 loft-bot
    run_nudge
    [ "$(dms)" = "triage: pr-move: loft-sh/loft-enterprise#8851 ci-red https://github.com/loft-sh/loft-enterprise/pull/8851 (backport of loft-sh/loft-enterprise#8833)" ]
    : > "$DMS"
    # merged: gone from the bot's open list, fetched once more and reported
    echo '[]' > "$BOT_FILE"
    gql_node loft-sh loft-enterprise 8851 MERGED REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 loft-bot
    run_nudge
    [ "$(dms)" = "triage: pr-move: loft-sh/loft-enterprise#8851 merged https://github.com/loft-sh/loft-enterprise/pull/8851 (backport of loft-sh/loft-enterprise#8833)" ]
    : > "$DMS"; : > "$GH_LOG"
    run_nudge
    [ -z "$(dms)" ]
    [ "$(gql_calls)" -eq 0 ]
    [ "$(jq 'has("https://github.com/loft-sh/loft-enterprise/pull/8851")' "$PR_MOVE_STATE")" = "false" ]
}

@test "backport: the body line names a task-linked parent, and the parent's task rides along" {
    e2e_setup
    add_task 22db7da1-0000-0000-0000-000000000000 pending "fix https://github.com/loft-sh/vcluster-pro/pull/2600"
    gql_node loft-sh vcluster-pro 2600 MERGED REVIEW_REQUIRED MERGEABLE SUCCESS someone someone
    bot_pr loft-sh vcluster-pro 2620 "[v0.37] fix: re-assert tenant content" $'Backport\n\nOriginal PR Nr.: #2600\n'
    gql_node loft-sh vcluster-pro 2620 OPEN REVIEW_REQUIRED MERGEABLE SUCCESS someone loft-bot
    run_nudge
    [ -z "$(dms)" ]
    gql_node loft-sh vcluster-pro 2620 CLOSED REVIEW_REQUIRED MERGEABLE SUCCESS someone loft-bot
    run_nudge
    [ "$(dms)" = "triage: pr-move: loft-sh/vcluster-pro#2620 closed https://github.com/loft-sh/vcluster-pro/pull/2620 task:22db7da1 (backport of loft-sh/vcluster-pro#2600)" ]
}

@test "backport: a bot PR naming no parent, or a parent neither Piotr's nor task-linked, is not watched" {
    e2e_setup
    echo '[{"owner":"loft-sh","repo":"loft-enterprise","num":8833}]' > "$MERGED_FILE"
    bot_pr loft-sh loft-enterprise 8776 "[release-4.12] fix(logging): log patch bodies only at debug (#8700)"
    bot_pr loft-sh loft-enterprise 8053 "licenses: update loft licenses"
    # same number, other repo: the parent must be in the backport's own repo
    bot_pr loft-sh vcluster 99 "[v0.30] fix: x (#8833)"
    run_nudge
    [ "$(gql_calls)" -eq 0 ]
    grep -q "backports: 0" "${TEST_DIR}/log"
}

@test "sources: authored PRs come from the viewer, and a failed sources call prunes nothing" {
    e2e_setup
    set_search loft-sh vcluster 7
    gql_node loft-sh vcluster 7 OPEN
    run_nudge
    grep -q '^sources ' "$GH_LOG"
    ! grep -q '^other: search prs' "$GH_LOG"
    touch "$GH_SOURCES_FAIL"
    PR_MOVE_TRACK_WINDOW=-1 run_nudge
    grep -q "WARN: authored PR query failed" "${TEST_DIR}/log"
    grep -q "WARN: loft-bot PR query failed" "${TEST_DIR}/log"
    [ "$(jq 'has("https://github.com/loft-sh/vcluster/pull/7")' "$PR_MOVE_STATE")" = "true" ]
}

@test "sources: an empty PR_MOVE_BACKPORT_BOT leaves the bot out of the query" {
    e2e_setup
    PR_MOVE_BACKPORT_BOT= run_nudge
    grep -qx "sources bot=" "$GH_LOG"
    run_nudge
    grep -qx 'sources bot=user(login: "loft-bot")' "$GH_LOG"
}

@test "delivery: lines past the cycle cap ride in one more DM, none dropped" {
    # State is written before delivery, so the old "deferring to next cycle"
    # dropped every line past the cap for good.
    e2e_setup
    many_task_prs 4
    run_nudge
    local i
    for i in 1 2 3 4; do gql_node loft-sh vcluster "$i" MERGED; done
    PR_MOVE_CYCLE_CAP=2 run_nudge
    [ "$(grep -c '^triage: ' "$DMS")" -eq 2 ]
    for i in 1 2 3 4; do grep -q "pr-move: loft-sh/vcluster#$i merged" "$DMS"; done
    grep -q "cycle cap 2 reached; 3 line(s) ride in one DM" "${TEST_DIR}/log"
}
