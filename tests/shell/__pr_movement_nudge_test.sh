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

    # stub: gh
    cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "search prs") cat "$GH_SEARCH_FIXTURE" ;;
  "pr view")
     url="$3"
     f="$GH_PRVIEW_DIR/$(printf '%s' "$url" | sed 's#[^A-Za-z0-9]#_#g').json"
     if [ -f "$f" ]; then cat "$f"; else echo '{}'; fi ;;
  "api user") echo "Piotr1215" ;;
  *) echo "[]" ;;
esac
EOF
    # stub: node snd.js -t triage <msg>  -> append msg to outbox
    cat > "$BIN/node" <<'EOF'
#!/usr/bin/env bash
shift 3   # drop <snd.js> -t triage
printf '%s\n' "$*" >> "$PR_TEST_OUTBOX"
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
    chmod +x "$BIN/gh" "$BIN/node" "$BIN/tmux"

    export PATH="$BIN:$PATH"
    export GH_SEARCH_FIXTURE="$SEARCH"
    export GH_PRVIEW_DIR="$PRVIEW_DIR"
    export PR_TEST_OUTBOX="$OUTBOX"
    export PR_MOVE_STATE="$TEST_DIR/state.json"
    export PR_MOVE_LOG="$TEST_DIR/log"
    export PR_MOVE_LOCK="$TEST_DIR/lock"
    export PR_MOVE_ME="Piotr1215"
    export SND_NODE_BIN="$TEST_DIR/snd.js"
    export PR_MOVE_PUSH_COOLDOWN=600
    export PR_MOVE_STICKY_COOLDOWN=3600
    export PR_MOVE_CYCLE_CAP=8
}
teardown() { rm -rf "$TEST_DIR"; }

# search fixture with one PR
search_one() { # url number repo owner isDraft
    jq -n --arg u "$1" --argjson n "$2" --arg r "$3" --arg o "$4" --argjson d "${5:-false}" \
      '[{url:$u, number:$n, repository:{name:$r, nameWithOwner:($o+"/"+$r)}, isDraft:$d}]' > "$SEARCH"
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

run() { : > "$OUTBOX"; bash "$SCRIPT" "${1:---live}" >/dev/null 2>&1; }
outbox() { cat "$OUTBOX" 2>/dev/null; }

assert_fires() { # reason description
    if grep -q "pr-move: .* $1 " "$OUTBOX" 2>/dev/null || grep -q "pr-move: .*$1.*http" "$OUTBOX" 2>/dev/null; then
        PASS=$((PASS+1)); echo "  PASS: $2"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $2 (outbox: $(outbox | tr '\n' '|'))"
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
assert_silent "live session on the PR suppresses the nudge"
# same session but spend-stalled -> not an owner, so it fires
setup
search_one "https://x/pr/1" 1 vcluster loft-sh
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE SUCCESS Piotr1215 "$OLD"; run --live
export_sessions "vcluster-pr-1" "You have hit your spend limit"
mk_prview "https://x/pr/1" sha1 REVIEW_REQUIRED MERGEABLE FAILURE Piotr1215 "$OLD"; run --live
assert_fires ci-red "spend-stalled session does not suppress"
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

echo
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
