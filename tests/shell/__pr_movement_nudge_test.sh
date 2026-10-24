#!/usr/bin/env bash
# Tests for __pr_movement_nudge.sh (the PR-movement to auto-dispatch watcher).
#
# Strategy: no network. Put stub `gh`, `tmux`, and `node` on PATH ahead of the
# real ones, drive them from per-test fixtures, then assert on the outbox (what
# would be DM'd to triage), the log, and the watermark state file.
#
# Each trigger is tested as a seed run (first contact, must be silent) followed
# by a mutated run (--live, must emit exactly the expected pr-move line). The
# actor filter, contention guard, push cooldown, bot filter, and cycle cap are
# tested the same way.
#
# Run:  bash tests/shell/__pr_movement_nudge_test.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/__pr_movement_nudge.sh"
PASS=0; FAIL=0

# ---- harness -------------------------------------------------------------
setup() {
    TEST_DIR=$(mktemp -d)
    BIN="$TEST_DIR/bin"; mkdir -p "$BIN"
    PRVIEW_DIR="$TEST_DIR/prviews"; mkdir -p "$PRVIEW_DIR"
    OUTBOX="$TEST_DIR/outbox"; : > "$OUTBOX"
    SEARCH="$TEST_DIR/search.json"; echo '[]' > "$SEARCH"
    REVREQ="$TEST_DIR/revreq.json"; echo '[]' > "$REVREQ"

    # stub: gh
    cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "search prs")
     case "$*" in
       *user-review-requested:*)
          [ -f "$GH_REVREQ_FIXTURE.fail" ] && exit 1
          cat "$GH_REVREQ_FIXTURE" ;;
       *) echo "[]" ;;
     esac ;;
  "api graphql")
     q=""; for a in "$@"; do case "$a" in query=*) q="${a#query=}" ;; esac; done
     # The sources call: Piotr's open PRs come from the search fixture.
     if grep -q '^  viewer {' <<<"$q"; then
        jq -c '{data: {viewer: {open: {pageInfo: {hasNextPage: false}, nodes: .}, merged: {nodes: []}},
                       bot: {pullRequests: {pageInfo: {hasNextPage: false}, nodes: []}}}}' "$GH_SEARCH_FIXTURE"
        exit 0
     fi
     # The batched fetch: one aliased repository(...).pullRequest(...) per PR.
     # Answer each from the same view-shaped fixtures `gh pr view` once served,
     # re-shaped into the GraphQL PullRequest the script maps back.
     echo graphql >> "$GH_CALLS_LOG"
     resp='{"data":{}}'
     while IFS= read -r line; do
        al=$(sed -E 's/^(p[0-9]+):.*/\1/' <<<"$line")
        o=$(sed -E 's/.*owner: "([^"]+)".*/\1/' <<<"$line")
        r=$(sed -E 's/.*name: "([^"]+)".*/\1/' <<<"$line")
        n=$(sed -E 's/.*number: ([0-9]+).*/\1/' <<<"$line")
        url=$(jq -r --arg o "$o/$r" --argjson n "$n" \
              '[.[] | select(.repository.nameWithOwner == $o and .number == $n) | .url] | first // empty' "$GH_SEARCH_FIXTURE")
        [ -n "$url" ] || url="https://github.com/$o/$r/pull/$n"
        f="$GH_PRVIEW_DIR/$(printf '%s' "$url" | sed 's#[^A-Za-z0-9]#_#g').json"
        [ -f "$f" ] || f=/dev/stdin
        node=$( { [ "$f" = /dev/stdin ] && echo '{}' || cat "$f"; } | jq -c --arg url "$url" --argjson n "$n" '
            . as $v | {number: $n, url: $url, title: (.title // ""), isDraft: (.isDraft // false), state: (.state // "OPEN"),
             headRefOid: .headRefOid, reviewDecision: .reviewDecision, mergeable: .mergeable,
             author: (.author // null),
             reviews: {nodes: (.reviews // [])}, comments: {nodes: (.comments // [])},
             commits: {nodes: [ ((.commits // []) | last // empty)
                | {commit: {oid, committedDate, authoredDate,
                            authors: {nodes: [ (.authors // [])[] | {user: {login: .login}} ]},
                            statusCheckRollup: {contexts: {nodes: ($v.statusCheckRollup // [])}}}} ]}}')
        resp=$(jq -c --arg a "$al" --argjson node "$node" '.data[$a] = {pullRequest: $node}' <<<"$resp")
     done < <(grep -oE 'p[0-9]+: repository\(owner: "[^"]+", name: "[^"]+"\) \{ pullRequest\(number: [0-9]+\)' <<<"$q")
     printf '%s\n' "$resp" ;;
  "api user") echo "Piotr1215" ;;
  *) echo "[]" ;;
esac
EOF
    # stub: node snd.js -t <target> <msg>  -> triage msgs to outbox, every DM
    # (never a real bus send) as "<target>: <msg>" to the all-DMs file
    cat > "$BIN/node" <<'EOF'
#!/usr/bin/env bash
target="$3"
shift 3   # drop <snd.js> -t <target>
printf '%s: %s\n' "$target" "$*" >> "$PR_TEST_OUTBOX_ALL"
[ "$target" = triage ] && printf '%s\n' "$*" >> "$PR_TEST_OUTBOX"
exit 0
EOF
    # stub: tmux (contention)
    cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-sessions) [ -n "$PR_TEST_SESSIONS" ] && printf '%s\n' $PR_TEST_SESSIONS ;;
  list-panes)    echo "%1" ;;
  capture-pane)  printf '%s' "$PR_TEST_PANE_TEXT" ;;
  *) : ;;
esac
EOF
    # stub: task. The script reads PR links from pending tasks; the fixture is
    # the `task export` JSON, empty by default so this machine's real tasks
    # never leak into a run.
    cat > "$BIN/task" <<'EOF'
#!/usr/bin/env bash
cat "$PR_TEST_TASKS"
EOF
    # stub: the intake routing helper; prints triage unless a test says otherwise
    cat > "$BIN/intake-route" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${PR_TEST_ROUTE:-triage}"
EOF
    chmod +x "$BIN/gh" "$BIN/node" "$BIN/tmux" "$BIN/task" "$BIN/intake-route"

    export PATH="$BIN:$PATH"
    export GH_SEARCH_FIXTURE="$SEARCH"
    export GH_REVREQ_FIXTURE="$REVREQ"
    export GH_PRVIEW_DIR="$PRVIEW_DIR"
    export GH_CALLS_LOG="$TEST_DIR/gh_calls"; : > "$GH_CALLS_LOG"
    export PR_TEST_TASKS="$TEST_DIR/tasks.json"; echo '[]' > "$PR_TEST_TASKS"
    export INTAKE_ROUTE_BIN="$BIN/intake-route"
    export PR_MOVE_SUMMARY="$TEST_DIR/summary.json"
    export PR_TEST_OUTBOX="$OUTBOX"
    OUTBOX_ALL="$TEST_DIR/outbox_all"; : > "$OUTBOX_ALL"
    export PR_TEST_OUTBOX_ALL="$OUTBOX_ALL"
    export PR_MOVE_STATE="$TEST_DIR/state.json"
    export PR_MOVE_LOG="$TEST_DIR/log"
    export PR_MOVE_LOCK="$TEST_DIR/lock"
    export PR_MOVE_NOTIFY_LOG="$TEST_DIR/notifications.log"
    export PR_MOVE_ME="Piotr1215"
    # Self identities beyond $ME: the Claude bot login Piotr's agent pushes as.
    # Pinned here (not left to the shipped default) so the actor-filter tests are
    # deterministic; value matches the production default.
    export PR_MOVE_SELF_LOGINS="claude[bot]"
    export SND_NODE_BIN="$TEST_DIR/snd.js"
    export PR_MOVE_PUSH_COOLDOWN=600
    export PR_MOVE_STICKY_COOLDOWN=3600
    export PR_MOVE_CYCLE_CAP=8
    export PR_MOVE_HANDOFF_CHECK="$BIN/handoff-check"
    printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$TEST_DIR/handoff.calls" > "$PR_MOVE_HANDOFF_CHECK"
    chmod +x "$PR_MOVE_HANDOFF_CHECK"
    # reset contention-stub state so a session set by one test does not leak into
    # the next (export_sessions never clears it).
    export PR_TEST_SESSIONS="" PR_TEST_PANE_TEXT=""
}
teardown() { rm -rf "$TEST_DIR"; }

# search fixture with one PR
search_one() { # url number repo owner isDraft title
    jq -n --arg u "$1" --argjson n "$2" --arg r "$3" --arg o "$4" --argjson d "${5:-false}" --arg t "${6:-}" \
      '[{url:$u, number:$n, title:$t, repository:{name:$r, nameWithOwner:($o+"/"+$r)}, isDraft:$d}]' > "$SEARCH"
}
# direct-review-request fixture: one PR per "url number owner/repo author type isDraft" arg
revreq() {
    local spec out='[]' u n r a t d
    for spec in "$@"; do
        read -r u n r a t d <<<"$spec"
        out=$(jq -c --arg u "$u" --argjson n "$n" --arg r "$r" --arg a "$a" --arg t "$t" --argjson d "$d" \
            '. + [{url:$u, number:$n, repository:{nameWithOwner:$r}, isDraft:$d, author:{login:$a, type:$t}}]' <<<"$out")
    done
    echo "$out" > "$REVREQ"
}
assert_requested() { # line description
    if grep -qxF "$1" "$OUTBOX" 2>/dev/null; then
        PASS=$((PASS+1)); echo "  PASS: $2"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $2 (outbox: $(outbox | tr '\n' '|'))"
    fi
}
export_sessions() { export PR_TEST_SESSIONS="$1"; export PR_TEST_PANE_TEXT="${2:-}"; }

# build a gh-pr-view fixture for a url
mk_prview() { # url sha reviewDecision mergeable checks(SUCCESS|FAILURE|NONE) commitLogin commitDateISO [foreignLogin foreignDateISO]
    local url="$1" sha="$2" rd="$3" mg="$4" checks="$5" clogin="$6" cdate="$7" flogin="${8:-}" fdate="${9:-}"
    local roll='[]'
    case "$checks" in
      SUCCESS) roll='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]' ;;
      FAILURE) roll='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
      PENDING) roll='[{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":""}]' ;;
      NONE)    roll='[]' ;;
    esac
    local comments='[]'
    [ -n "$flogin" ] && comments=$(jq -n --arg l "$flogin" --arg d "$fdate" '[{author:{login:$l}, createdAt:$d}]')
    local f
    f="$PRVIEW_DIR/$(printf '%s' "$url" | sed 's#[^A-Za-z0-9]#_#g').json"
    jq -n --arg sha "$sha" --arg rd "$rd" --arg mg "$mg" --argjson roll "$roll" \
          --arg cl "$clogin" --arg cd "$cdate" --argjson comments "$comments" \
      '{headRefOid:$sha, reviewDecision:$rd, mergeable:$mg, statusCheckRollup:$roll,
        reviews:[], comments:$comments,
        commits:[{oid:$sha, committedDate:$cd, authoredDate:$cd, authors:[{login:$cl}]}]}' > "$f"
}

run() { : > "$OUTBOX"; : > "$OUTBOX_ALL"; bash "$SCRIPT" "${1:---live}" >/dev/null 2>&1; }
outbox() { cat "$OUTBOX" 2>/dev/null; }

assert_fires() { # reason description
    if grep -q "pr-move: .* $1 " "$OUTBOX" 2>/dev/null || grep -q "pr-move: .*$1.*http" "$OUTBOX" 2>/dev/null; then
        PASS=$((PASS+1)); echo "  PASS: $2"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $2 (outbox: $(outbox | tr '\n' '|'))"
    fi
}
assert_dm() { # "target: line" description (exact line among all DMs)
    if grep -qxF "$1" "$OUTBOX_ALL" 2>/dev/null; then
        PASS=$((PASS+1)); echo "  PASS: $2"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $2 (all DMs: $(tr '\n' '|' < "$OUTBOX_ALL"))"
    fi
}
assert_no_dms() { # description
    if [ -s "$OUTBOX_ALL" ]; then
        FAIL=$((FAIL+1)); echo "  FAIL: $1 (got: $(tr '\n' '|' < "$OUTBOX_ALL"))"
    else
        PASS=$((PASS+1)); echo "  PASS: $1"
    fi
}
assert_silent() { # description
    if [ -s "$OUTBOX" ]; then
        FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected no DM, got: $(outbox | tr '\n' '|'))"
    else
        PASS=$((PASS+1)); echo "  PASS: $1"
    fi
}

OLD="2026-07-02T08:00:00Z"; NEW="2026-07-02T10:00:00Z"
RECENT="$(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"

# ---- tests ---------------------------------------------------------------
echo "T1 first-contact seed is silent"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"
run --live
assert_silent "seed emits no nudge"
teardown

echo "T2 changes-requested fires once"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
mk_prview "https://x/pr/1" sha1 CHANGES_REQUESTED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
assert_fires changes-requested "changes-requested fires"
run --live
assert_silent "changes-requested does not re-fire within cooldown"
teardown

echo "T3 ci-red fires"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live
assert_fires ci-red "ci-red fires on SUCCESS->FAILURE"
teardown

echo "T4 merge-conflict fires"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED CONFLICTING SUCCESS Piotr1215 "$OLD"; run --live
assert_fires merge-conflict "merge-conflict fires on MERGEABLE->CONFLICTING"
teardown

echo "T5 review-comment fires for a human, not a bot"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
# bot comment: must stay silent
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD" "github-actions" "$NEW"; run --live
assert_silent "bot comment does not fire"
# human comment: must fire
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD" "somereviewer" "$NEW"; run --live
assert_fires review-comment "human comment fires review-comment"
teardown

echo "T6 foreign-push fires; own-push does not"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
# own new push (older date so push-cooldown does not swallow it): must stay silent
mk_prview "https://x/pr/1" sha2 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
assert_silent "own push does not fire"
# foreign new push: must fire
mk_prview "https://x/pr/1" sha3 REVIEW_REQUIRED MERGEABLE SUCCESS othercontrib "$OLD"; run --live
assert_fires foreign-push "foreign push fires"
teardown

echo "T7 contention: live session suppresses, spend-stalled does not"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
# a live worker session owns pr-1 -> silent even though CI goes red
export_sessions "vcluster-pr-1" ""
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live
assert_dm "vcluster-pr-1: pr-move: loft-sh/vcluster#1 ci-red https://x/pr/1" "owner session gets the event on the bus"
assert_dm "triage: pr-move: loft-sh/vcluster#1 ci-red https://x/pr/1 (owned by vcluster-pr-1)" "triage gets the same line marked owned"
run --live
assert_no_dms "an owned sticky event does not re-fire"
# same session but spend-stalled -> not an owner, so it fires
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
export_sessions "vcluster-pr-1" "You have hit your spend limit"
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live
assert_fires ci-red "spend-stalled session does not suppress"
teardown

echo "T7b contention: an approval-style event on an owned PR reaches owner and triage"
setup
search_one "https://x/pr/8801" 8801 loft-enterprise loft-sh
mk_prview "https://x/pr/8801" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
export_sessions "loft-enterprise-pr-8801" ""
mk_prview "https://x/pr/8801" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD" "denis" "$NEW"; run --live
assert_dm "loft-enterprise-pr-8801: pr-move: loft-sh/loft-enterprise#8801 review-comment https://x/pr/8801" "owner gets the review-comment"
assert_dm "triage: pr-move: loft-sh/loft-enterprise#8801 review-comment https://x/pr/8801 (owned by loft-enterprise-pr-8801)" "triage gets it marked owned"
# the owner's own fresh push must not swallow a review that follows it
mk_prview "https://x/pr/8801" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$RECENT" "caue" "2026-07-02T11:00:00Z"; run --live
assert_dm "loft-enterprise-pr-8801: pr-move: loft-sh/loft-enterprise#8801 review-comment https://x/pr/8801" "push cooldown does not drop an owned event"
# dry-run sends nothing even when owned
mk_prview "https://x/pr/8801" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD" "denis" "2026-07-02T12:00:00Z"; run --dry-run
assert_no_dms "dry-run on an owned PR sends no DM"
teardown

echo "T8 push cooldown: our own recent push is skipped"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
# CI goes red but our own commit is 2 min old -> within cooldown -> silent
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$RECENT"; run --live
assert_silent "recent own push defers the nudge"
teardown

echo "T9 session boundary: pr-1 session does not shadow pr-157"
setup
search_one "https://x/pr/157" 157 gh-actions loft-sh
mk_prview "https://x/pr/157" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
export_sessions "vcluster-pr-1" ""    # unrelated session
mk_prview "https://x/pr/157" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live
assert_fires ci-red "pr-1 session does not falsely own pr-157"
teardown

echo "T11 pre-existing sticky state at seed does not fire next cycle"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
# already red at first contact
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live   # seed
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live   # no change
assert_silent "already-failing PR seeded silently does not fire on next cycle"
teardown

echo "T10 dry-run sends nothing"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --dry-run
mk_prview "https://x/pr/1" sha1 CHANGES_REQUESTED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --dry-run
assert_silent "dry-run never DMs even on a real movement"
teardown

echo "T12 bare ci-red on a ci(release) PR is suppressed"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh false "ci(release): migrate sync_linear to shared action (v0.30)"
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live
assert_silent "bare ci-red on ci(release) title is filtered"
teardown

echo "T13 bare ci-red on a chore(renovate) PR is suppressed"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh false "chore(renovate): bump default vcluster version"
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live
assert_silent "bare ci-red on chore(renovate) title is filtered"
teardown

echo "T14 ci-red on a substantive code PR still fires"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh false "fix(core): correct nil deref in syncer"
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live
assert_fires ci-red "ci-red still fires on a fix(): PR"
teardown

echo "T15 ci-red accompanied by changes-requested on a ci(release) PR still fires"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh false "ci(release): migrate sync_linear to shared action (v0.30)"
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
mk_prview "https://x/pr/1" sha1 CHANGES_REQUESTED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live
assert_fires changes-requested "accompanied ci-red on ci(release) is not swallowed"
teardown

echo "T16 PR outside the notify scope (non-loft-sh org) never fires"
setup
search_one "https://x/pr/41" 41 nginx-demo Piotr1215 false "fix: real movement but wrong org"
mk_prview "https://x/pr/41" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
mk_prview "https://x/pr/41" sha1 REVIEW_REQUIRED CONFLICTING SUCCESS Piotr1215 "$OLD"; run --live
assert_silent "Piotr1215/nginx-demo is out of notify scope"
teardown

echo "T17 self: a claude[bot] head push is treated as self, not foreign-push"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live   # seed
# the Claude bot Piotr pushes as advances head -> self identity -> silent
mk_prview "https://x/pr/1" sha2 REVIEW_REQUIRED MERGEABLE SUCCESS "claude[bot]" "$OLD"; run --live
assert_silent "claude[bot] head push is self, no self-retrigger"
teardown

echo "T18 external: a teammate push still fires foreign-push (not over-suppressed)"
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live   # seed
# a real collaborator's push is outside the self set -> must fire
mk_prview "https://x/pr/1" sha2 REVIEW_REQUIRED MERGEABLE SUCCESS djwfyi "$OLD"; run --live
assert_fires foreign-push "external teammate push still fires"
teardown

echo "T19 direct review request: seed silent, a new request fires once"
setup
revreq "https://x/pull/20 20 loft-sh/architecture vcauesantos User false"; run --live
assert_silent "requests already open at first contact seed silently"
revreq "https://x/pull/20 20 loft-sh/architecture vcauesantos User false" \
       "https://x/pull/7 7 loft-sh/community-metrics saiyam1814 User false"; run --live
assert_requested "review-request: loft-sh/community-metrics#7 from saiyam1814 https://x/pull/7" "a new direct request fires with ref and author"
run --live
assert_silent "a request still pending does not re-fire"
teardown

echo "T20 direct review request: bot, self and draft PRs never fire"
setup
revreq; run --live
revreq "https://x/pull/52 52 loft-sh/vskills-mcp-server dependabot[bot] Bot false" \
       "https://x/pull/60 60 loft-sh/hosted-platform renovate Bot false" \
       "https://x/pull/61 61 loft-sh/vcluster Piotr1215 User false" \
       "https://x/pull/62 62 loft-sh/vcluster someone User true"; run --live
assert_silent "bot, self and draft requests are skipped"
teardown

echo "T21 direct review request: cleared then re-requested fires again"
setup
revreq; run --live
revreq "https://x/pull/7 7 loft-sh/community-metrics saiyam1814 User false"; run --live
revreq; run --live
assert_silent "a cleared request is silent"
revreq "https://x/pull/7 7 loft-sh/community-metrics saiyam1814 User false"; run --live
assert_requested "review-request: loft-sh/community-metrics#7 from saiyam1814 https://x/pull/7" "a re-request fires again"
teardown

echo "T22 direct review request: a failed search keeps the set"
setup
revreq "https://x/pull/7 7 loft-sh/community-metrics saiyam1814 User false"; run --live
touch "$REVREQ.fail"; run --live
assert_silent "a failed search sends nothing"
rm -f "$REVREQ.fail"; run --live
assert_silent "recovery does not re-fire a request already seen"
teardown

echo "T23 direct review request outside loft-sh still fires (NUDGE_ORGS does not apply)"
setup
revreq; run --live
revreq "https://x/pull/3 3 vClusterLabs-Experiments/vbilling saiyam1814 User false"; run --live
assert_requested "review-request: vClusterLabs-Experiments/vbilling#3 from saiyam1814 https://x/pull/3" "a non-loft-sh direct request fires"
teardown

echo "T24 live cycle closes discharged PR handoffs as a backstop; dry-run does not"
setup
search_one "https://x/pull/1" 1 vcluster loft-sh
run --dry-run
if [ ! -e "$TEST_DIR/handoff.calls" ]; then PASS=$((PASS+1)); echo "  PASS: dry-run leaves handoffs alone"; else FAIL=$((FAIL+1)); echo "  FAIL: dry-run ran the handoff check"; fi
run --live
if grep -qx -- "--close --kind pr-merged,pr-closed" "$TEST_DIR/handoff.calls" 2>/dev/null; then PASS=$((PASS+1)); echo "  PASS: live cycle runs the scoped close"; else FAIL=$((FAIL+1)); echo "  FAIL: live cycle did not run the close"; fi
printf '#!/usr/bin/env bash\nexit 3\n' > "$PR_MOVE_HANDOFF_CHECK"
if run --live; then PASS=$((PASS+1)); echo "  PASS: a failing check does not fail the cycle"; else FAIL=$((FAIL+1)); echo "  FAIL: a failing check failed the cycle"; fi
teardown

echo
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
