#!/usr/bin/env bash
# PROJECT: ambient-triage
# See: skills/gordon/skills/gordon/references/interfaces.md,
# __auto_triage_nudge.sh,
#      ~/.claude/tmp/pr-nudge-design.md (design)
#
# PR-movement to auto-dispatch watcher. Stage 0: DRY-RUN by default.
#
# Detects movement on the PRs it watches and DMs one `pr-move:` line per
# genuinely-moved PR, mirroring how __auto_triage_nudge.sh nudges Gordon after
# the Linear sync. Delivery goes to Kendra (`intake`) while she is live, else to
# Gordon (`triage`): __intake_route.sh decides, once per run (INTAKE_ROUTE_BIN).
# Gordon then runs pull->form->decide and dispatches a NORMAL worker
# (__spawn_agent.sh --pr, defaults to /ops-autonomous-worker), never the review
# panel.
#
# WATCHED PRs: Piotr's open authored PRs, plus every GitHub PR linked
#   (https://github.com/<owner>/<repo>/pull/<n>) from the description or an
#   annotation of any PENDING taskwarrior task, any tag (`rc.context=none`, so
#   hidden +gordon tasks count; dependabot and other bot PRs included). A line
#   for a task-linked PR ends in ` task:<uuid8>[,<uuid8>]`, naming the owning
#   task(s). A PR no source names any more keeps its entry for PR_MOVE_TRACK_WINDOW
#   (3 days): one that merged or closed meanwhile is reported (the `merged` and
#   `closed` edge), one still open is retired when the window ends.
#   Also the backport bot's (PR_MOVE_BACKPORT_BOT, default loft-bot; empty turns
#   it off) open PRs whose title ends "(#N)" or whose body carries "Original PR
#   Nr.: #N", where #N in the same repo is a PR Piotr authored (open, or among
#   his 100 most recent merged) or one a pending task links. Their lines end in
#   ` (backport of <owner>/<repo>#N)` and name the parent's tasks. Once a
#   backport merges or closes it leaves the bot's open list, is fetched once
#   more to report it, and is retired.
#
# Runs from gh-pr-review-sync.service (ExecStart) on its 15-min timer, cross-org.
# The PR task sync that once shared this unit was discontinued on 2026-10-13.
#
# SOURCES: one `gh api graphql` call reads Piotr's open PRs (viewer, which is
#   complete: `gh search prs --author @me` returned 37, 34 and 48 of his 51 open
#   PRs in three calls a minute apart on 22 Oct 2026, and the PRs it dropped went
#   unwatched for that cycle), his 100 most recent merged PRs, and the backport
#   bot's open PRs. Over 100 in either open list logs a WARN.
#
# COST: the sources call plus one `gh api graphql` call per PR_MOVE_GQL_CHUNK
#   (default 25) PRs, each query holding one aliased repository(...).pullRequest(...)
#   field per PR. ~100 PRs is four calls, not one `gh pr view` each. A chunk that
#   fails logs a WARN and skips only its PRs. Measured 22 Oct 2026: 0.27 s per PR
#   server side (10 PRs 3.7 s, 20 PRs 5.5 s, 30 PRs 8.1 s) against GitHub's 10 s
#   GraphQL timeout, so 25 keeps a margin that 30 does not.
#
# STATUS LINE: each run writes {"watched": N, "updated": ISO, "epoch": N} to
#   PR_MOVE_SUMMARY (default pr-watch-summary.json beside the state file) so the
#   status line shows the count without a gh call or parsing the state file.
#
# Movements that FIRE (open, non-draft PRs):
#   changes-requested  reviewDecision -> CHANGES_REQUESTED               (sticky)
#   review-comment     new review/comment by a non-Piotr, non-bot actor  (edge)
#   ci-red             statusCheckRollup -> FAILURE                       (sticky)
#   merge-conflict     mergeable -> CONFLICTING                          (sticky)
#   foreign-push       new head commit whose author is not a self login  (edge)
#                      (only on a PR a self login authored: on someone else's
#                      task-linked PR every push is theirs)
#   merged / closed    the PR left the open state                        (terminal)
# merged and closed fire ONCE, on the edge from open to that state, then the PR
#   stays quiet (and is no longer fetched) while a task still links it. A PR
#   first seen already merged or closed seeds silently, so a task that cites a
#   long-merged PR does not replay history. The owning task is closed or
#   annotated by the receiver; __gordon_board_check.sh keeps closing +piotr
#   handoffs whose close-when PR merged (the backstop below), and is not repeated.
# A sticky reason names a STATE the PR sits in, so it fires ONCE on entry and
#   then stays quiet for as long as it holds; it fires again only if it clears
#   and returns. `notifiedSticky` in the state file is the per-PR record of what
#   has been sent. Edge reasons carry their own baseline (headSha,
#   lastForeignActivity) and fire per occurrence.
# IGNORED: pushes/commits/comments by a self identity (Piotr, or the Claude bot
#   login he pushes as -- see PR_MOVE_SELF_LOGINS), draft PRs, bot comments, CI
#   green/pending, approvals (surface-only), Piotr's edits.
# NOISE FILTER (Gordon's live-cycle feedback):
#   - PRs outside NUDGE_ORGS (default loft-sh) are skipped entirely: the
#     dispatcher hardcodes loft-sh URLs, so other orgs are undispatchable.
#   - A BARE ci-red (sole reason) on a CI/dependency/release PR is suppressed,
#     keyed on the conventional-commit title (ci(...):, chore/build(deps|renovate
#     |release):, or a bump/pin subject). Its E2E-on-PR red is not a code defect.
#     An accompanied ci-red still rides along with the other reason.
#
# Direct review requests (someone else's PR) send `review-request: <ref> from
#   <author> <url>`. GitHub's user-review-requested: qualifier matches only a
#   request naming Piotr himself, never one to a team he is in, which is the
#   noise he closes on sight. Each request fires once when it appears and drops
#   out of state once reviewed or withdrawn, so a re-request fires again. Bot,
#   self and draft PRs are skipped. NUDGE_ORGS does not apply: Gordon surfaces
#   these to Piotr rather than dispatching them. First contact seeds silently.
#
# Self-retrigger guard: per-PR signature keyed on headSha in the state file.
#   First contact seeds silently (no nudge), mirroring the Linear new_activity
#   silent-seed. Any change attributable to a SELF identity is by definition not
#   a trigger: Piotr's handle plus the Claude bot login he pushes as (the local
#   worker commits as Piotr; the GitHub Claude app pushes/opens PRs as a bot).
#   The self set is $ME + PR_MOVE_SELF_LOGINS (default claude[bot]). A non-self
#   actor (a teammate's review, an external contributor's push) still fires.
# Contention guard: a PR owned by a live (non-spend-stalled) tmux session is
#   handled by that worker, so the receiver must not dispatch a second one. The
#   event is still delivered, never dropped: the same line goes to the owner on
#   the bus (its session name is its bus name) and to the target marked "(owned
#   by <session>)", so it can act if the worker is idle or finished. A PR
#   Piotr/the agent pushed to within PUSH_COOLDOWN_SECS is skipped (unowned only).
#
# LIMITATION: inline review-thread replies are not fetched (reviews and PR
#   comments are); they surface indirectly via the carrying review. reviewThreads
#   can be added to GQL_PR_FRAGMENT if needed. Check rows beyond the first 100
#   contexts of a PR's newest commit are not read.
#
# DELIVERY: one DM per line up to PR_MOVE_CYCLE_CAP (default 8) per cycle. Past
#   the cap the remaining lines ride together in one more DM, one per line, so a
#   burst (a parent's seven backports merging at once) is never dropped: state is
#   written before delivery, so an unsent line would be lost for good.
# RECORDS: before its DM, every line is also appended to notifications.log
#   (PR_MOVE_NOTIFY_LOG) as one `github` record, the source the GitHub
#   notifications cron writes, so a PR move reaches the EVENTS stream and
#   intake's github row even when no agent is on the bus to take the DM:
#     <date time>\tgithub\t🐙<ref>:\tkind:pr-move|review-request via:pr-watch link:<url> | <line>
#   The DM stays until the records are proven to reach Kendra and Gordon.
#
# Usage:
#   __pr_movement_nudge.sh            # DRY-RUN (default): log only, no DM
#   __pr_movement_nudge.sh --dry-run  # same, explicit
#   __pr_movement_nudge.sh --live     # send pr-move: DMs to intake, else triage, and write the records
# Dry-run still advances the state file, like --live; point PR_MOVE_STATE at a
# copy to rehearse without consuming real movements.
set -eo pipefail

# env for cron/systemd (node on PATH, bus env, gh auth)
# shellcheck disable=SC1091
[[ -f "$HOME/.envrc" ]] && source "$HOME/.envrc"

LOG_FILE="${PR_MOVE_LOG:-/tmp/pr-movement-nudge.log}"
STATE_FILE="${PR_MOVE_STATE:-$HOME/.claude/data/pr-watermarks.json}"
LOCK_FILE="${PR_MOVE_LOCK:-/tmp/pr-movement-nudge.lock}"
# Gordon's handoff checker. This cycle never sees a merge (it lists open PRs
# only); the real-time close rides pr-watch's merged prompt through
# __handoff_discharge_prompt_hook.sh. This call is the backstop for a PR no
# live session tracks. Skipped when not executable.
HANDOFF_CHECK="${PR_MOVE_HANDOFF_CHECK:-$HOME/.claude/scripts/__gordon_board_check.sh}"
# The status line's view of this run: a tiny file, so a render never parses the
# state file or calls gh.
SUMMARY_FILE="${PR_MOVE_SUMMARY:-${STATE_FILE%/*}/pr-watch-summary.json}"
# The event log the shipper follows: each line also lands here as a record.
NOTIFY_LOG="${PR_MOVE_NOTIFY_LOG:-$HOME/.local/state/notifications.log}"
# Who receives the DMs: prints `intake` or `triage`. Stubbed by tests.
INTAKE_ROUTE_BIN="${INTAKE_ROUTE_BIN:-$HOME/.claude/scripts/__intake_route.sh}"
# PRs per `gh api graphql` call.
GQL_CHUNK="${PR_MOVE_GQL_CHUNK:-25}"
[[ "$GQL_CHUNK" =~ ^[1-9][0-9]*$ ]] || GQL_CHUNK=25
# An entry no source names any more is still fetched once to catch a merge when
# it was last seen open within this window (default 3 days).
TRACK_WINDOW_SECS="${PR_MOVE_TRACK_WINDOW:-259200}"
# The login that opens backport PRs; empty turns the backport source off.
BACKPORT_BOT="${PR_MOVE_BACKPORT_BOT-loft-bot}"
[[ -z "$BACKPORT_BOT" || "$BACKPORT_BOT" =~ ^[A-Za-z0-9-]+$ ]] || BACKPORT_BOT=""

DRY_RUN=1
case "${1:-}" in
    --live) DRY_RUN=0 ;;
    --dry-run|"") DRY_RUN=1 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
esac

# Delivery: identical to __auto_triage_nudge.sh (Node snd -> agents.dm.<b64url>).
# No presence gate here (resolve_target holds it); NATS Core drops if the target
# is not subscribed. SND_FROM marks origin so the bus shows the nudge as
# watcher-originated.
SND_NODE_BIN="${SND_NODE_BIN:-/home/decoder/dev/agents-mcp-server/build/snd.js}"
AGENTS_NATS_URL_DEFAULT="nats://nats-nats-tailscale.tail165ec.ts.net:4222"
export AGENTS_NATS_URL="${AGENTS_NATS_URL:-$AGENTS_NATS_URL_DEFAULT}"
export SND_FROM="${SND_FROM:-pr-watch}"

# Tunables
PUSH_COOLDOWN_SECS="${PR_MOVE_PUSH_COOLDOWN:-600}"        # skip if we pushed within 10m
CYCLE_CAP="${PR_MOVE_CYCLE_CAP:-8}"                       # max pr-move DMs per cycle
ME="${PR_MOVE_ME:-$(gh api user --jq .login 2>/dev/null || echo Piotr1215)}"
# Self identities: any actor whose movement is Piotr's own and must NOT nudge.
# The local worker commits AS Piotr (personal and work emails both resolve to
# $ME), but the GitHub-hosted Claude app pushes/opens PRs under a bot login, so
# a commit/push/comment by that bot would otherwise read as a foreign actor and
# re-trigger. Broaden "self" to $ME plus PR_MOVE_SELF_LOGINS (space/comma-
# separated; default the Claude app's bot login). A teammate's review or an
# external contributor's push stays outside this set and still fires.
SELF_LOGINS_EXTRA="${PR_MOVE_SELF_LOGINS:-claude[bot]}"
SELVES_JSON=$(jq -cn --arg me "$ME" --arg extra "$SELF_LOGINS_EXTRA" \
    '([$me] + ($extra | [splits("[[:space:],]+")])) | map(select(. != "")) | unique')
# Notify scope: only DM for PRs whose owner is in this space/comma-separated
# allowlist. The dispatcher (__spawn_agent.sh --pr) hardcodes loft-sh URLs, so a
# nudge for any other org (personal/experiment repos) is undispatchable. Empty = all.
NUDGE_ORGS="${PR_MOVE_NUDGE_ORGS:-loft-sh}"

# Spend/rate-limit wall markers (same set __cockpit_state.sh uses): a session at
# this wall is dead work, not ownership, so it must not suppress a nudge.
STALL_RE='spend limit|rate-limit-options|Add funds|wait for limit to reset|usage-credits|approaching your usage limit'

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*" | tee -a "$LOG_FILE"; }

# Send a DM over the NATS comms bus (same path as __auto_triage_nudge.sh).
# send_dm MSG [TARGET] -> DM MSG to TARGET (default triage).
send_dm() { node "$SND_NODE_BIN" -t "${2:-triage}" "$1" 2>&1; }

# deliver MSG TARGET: send it, or in dry-run only log what would be sent.
deliver() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] would send to $2 -> $1"
    else
        send_dm "$1" "$2" | while read -r line; do log "  snd($2): $line"; done
    fi
}

# record LINE: append LINE to notifications.log as one `github` record (see
# RECORDS above), or in dry-run only log it. A failed append is logged and the
# DM still goes.
record() {
    local ref url="-" rec
    read -r _ ref _ <<<"$1"
    if [[ "$1" =~ https://github\.com/[^[:space:]]+/pull/[0-9]+ ]]; then url="${BASH_REMATCH[0]}"; fi
    rec=$(printf '%s\tgithub\t🐙%s:\tkind:%s via:pr-watch link:%s | %s' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$ref" "${1%%:*}" "$url" "${1//[$'\t\n']/ }")
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] would record -> $rec"
    elif ! printf '%s\n' "$rec" >> "$NOTIFY_LOG"; then
        log "ERROR: cannot append to $NOTIFY_LOG: $1"
    fi
}

now_epoch() { date +%s; }
iso_to_epoch() { date -d "$1" +%s 2>/dev/null || echo 0; }

# --- contention: a live, non-spend-stalled tmux session owns this PR? ---
# On a match, sets OWNER_SESSION to the owning session name.
OWNER_SESSION=""
pr_has_live_session() {
    local num="$1" sess pane
    OWNER_SESSION=""
    while IFS= read -r sess; do
        [[ -z "$sess" ]] && continue
        # match "<repo>-pr-<num>" or "<repo>-pr<num>" with a numeric boundary so
        # pr-15 does not match pr-157.
        if [[ "$sess" =~ (^|[^0-9])pr-?"$num"([^0-9]|$) ]]; then
            pane=$(tmux list-panes -t "$sess" -F '#{pane_id}' 2>/dev/null | head -1)
            if [[ -n "$pane" ]] && tmux capture-pane -t "$pane" -p 2>/dev/null | grep -qiE "$STALL_RE"; then
                log "  contention: $sess matches pr-$num but is spend-stalled; not an owner"
                continue
            fi
            log "  contention: live session $sess owns pr-$num"
            OWNER_SESSION="$sess"
            return 0
        fi
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
    return 1
}

# --- signature: reduce one PR's `gh pr view` JSON to the watched dimensions ---
compute_sig() {
    local detail="$1"
    jq -c --argjson selves "$SELVES_JSON" '
        def isself($l): ($l != null) and (($selves | index($l)) != null);
        def isbot($l): ($l|type=="string") and (($l|endswith("[bot]"))
            or ((["dependabot","dependabot-preview","renovate","codecov","github-actions","loft-bot","snyk-bot"])|index($l) != null));
        def foreign($l): ($l != null) and (isself($l)|not) and (isbot($l)|not);
        (.commits // []) as $c
        | ($c | last) as $last
        | ($last.authors // [] | map(.login)) as $la
        | {
            headSha: (.headRefOid // ""),
            reviewDecision: (.reviewDecision // ""),
            mergeable: (.mergeable // "UNKNOWN"),
            lastCommitKnownAuthors: ($la | map(select(. != null and . != "")) | length),
            lastCommitMine: (any($la[]?; isself(.))),
            lastCommitDate: ($last.committedDate // $last.authoredDate // ""),
            lastForeignActivity: (
                ([ (.reviews // [])[] | select(foreign(.author.login)) | .submittedAt ]
                 + [ (.comments // [])[] | select(foreign(.author.login)) | .createdAt ])
                | map(select(. != null)) | (max // "")),
            changesRequested: ((.reviewDecision // "") == "CHANGES_REQUESTED"),
            checks: (
                # A red build means a check REPORTED failure. CANCELLED does not:
                # a concurrency group cancels the in-flight run when a new commit
                # lands, so the rollup keeps the aborted row next to the re-run
                # that then succeeded under the same name (observed on
                # loft-sh/vcluster#4084: 4 CANCELLED rows, each with a same-named
                # SUCCESS row, PR green and MERGEABLE, nudged ci-red hourly).
                # An abort carries no verdict about the code, so it is not a
                # trigger. NEUTRAL/SKIPPED likewise fall through to SUCCESS.
                (.statusCheckRollup // []) as $r
                | if ($r | length) == 0 then "NONE"
                  elif any($r[];
                        ((.conclusion // "" | ascii_upcase) as $x | ($x=="FAILURE" or $x=="TIMED_OUT" or $x=="ERROR" or $x=="STARTUP_FAILURE"))
                        or ((.state // "" | ascii_upcase) as $s | ($s=="FAILURE" or $s=="ERROR")))
                    then "FAILURE"
                  elif any($r[];
                        ((.status // "" | ascii_upcase) as $st | ($st=="IN_PROGRESS" or $st=="QUEUED" or $st=="PENDING" or $st=="WAITING" or $st=="REQUESTED"))
                        or ((.state // "" | ascii_upcase) as $s | ($s=="PENDING" or $s=="EXPECTED")))
                    then "PENDING"
                  else "SUCCESS" end)
        }' <<<"$detail"
}

# sticky_set SIG -> JSON array of the sticky reasons true in this signature, in
# canonical report order. A sticky reason describes a STATE the PR is sitting in
# (red build, changes requested, conflicting), so it stays true across cycles;
# `notifiedSticky` in the state file records which of them we have already sent.
sticky_set() {
    jq -c '[ (if .changesRequested then "changes-requested" else empty end),
             (if .checks == "FAILURE" then "ci-red" else empty end),
             (if .mergeable == "CONFLICTING" then "merge-conflict" else empty end) ]' <<<"$1"
}

# sticky_new SIG_SET NOTIFIED_SET -> newline-separated reasons in SIG_SET that
# are not yet in NOTIFIED_SET, i.e. the states entered since the last DM.
# Bind the element ($x) BEFORE piping into $n: inside `$n | index(.)` the `.` is
# $n itself, not the element, so that form matches nothing and silences every
# reason.
sticky_new() {
    jq -r --argjson n "$2" '.[] | . as $x | select(($n | index($x)) == null)' <<<"$1"
}

# ci_red_is_noise TITLE -> 0 if a BARE ci-red on this PR is expected noise: CI
# plumbing / dependency / release-sync PRs whose E2E-on-PR red is not a code
# defect. The conventional-commit title prefix is the only reliable signal here:
# these PRs are Piotr-authored (so bot-author checks miss them) and carry no
# distinguishing label. Only sole-reason ci-red is suppressed by the caller;
# changes-requested / merge-conflict / review-comment always pass through.
ci_red_is_noise() {
    local t="${1,,}"
    # ci(...) plumbing PRs, e.g. "ci(release): migrate sync_linear ..."
    [[ "$t" =~ ^ci(\([^\)]*\))?!?: ]] && return 0
    # chore/build dependency or release PRs
    if [[ "$t" =~ ^(chore|build)(\([^\)]*\))?!?: ]]; then
        [[ "$t" =~ ^(chore|build)\((deps|dependencies|renovate|dependabot|release)\) ]] && return 0
        [[ "$t" =~ (bump|pin|renovate|dependabot|dependenc) ]] && return 0
    fi
    return 1
}

# review_requests_human REQS -> REQS narrowed to non-draft PRs opened by a human
# other than Piotr. Dependency bots request him directly on every bump.
review_requests_human() {
    jq -c --argjson selves "$SELVES_JSON" '
        map(select((.isDraft | not)
            and ((.author.login // "") as $a
                 | $a != "" and (.author.type // "") != "Bot"
                   and ($a | endswith("[bot]") | not)
                   and (($selves | index($a)) == null))))' <<<"$1"
}

# review_requests_new REQS SEEN -> one "ref<TAB>author<TAB>url" line per PR in
# REQS whose url is not in the SEEN array. Bind the PR before piping into $seen,
# for the same reason as sticky_new.
review_requests_new() {
    jq -r --argjson seen "$2" '.[] | . as $p | select(($seen | index($p.url)) == null)
        | ["\($p.repository.nameWithOwner)#\($p.number)", $p.author.login, $p.url] | @tsv' <<<"$1"
}

# resolve_target -> `intake` or `triage`: who receives this run's DMs. Kendra
# (`intake`) takes routine events off Gordon (`triage`) while she is live. The
# rule lives in one helper, __intake_route.sh; a missing helper, a failure, or
# any other output means triage, exactly as before she existed.
resolve_target() {
    local t=""
    if [[ -x "$INTAKE_ROUTE_BIN" ]]; then
        t=$(timeout 30 "$INTAKE_ROUTE_BIN" 2>/dev/null) || t=""
    fi
    t="${t//[[:space:]]/}"
    case "$t" in
        intake | triage) printf '%s' "$t" ;;
        *) printf 'triage' ;;
    esac
}

# sources_query -> the one GraphQL query behind the watch list's own sources:
# viewer.open (Piotr's open PRs), viewer.merged (his 100 most recently created
# merged PRs, the parents a backport can name) and, unless BACKPORT_BOT is
# empty, bot (that login's open PRs, with the body that names a parent).
sources_query() {
    local bot=""
    [[ -z "$BACKPORT_BOT" ]] || bot="
  bot: user(login: \"$BACKPORT_BOT\") { pullRequests(states: OPEN, first: 100) { pageInfo { hasNextPage } nodes { url number title body isDraft repository { nameWithOwner name } } } }"
    printf '%s\n' "query {
  viewer {
    open: pullRequests(states: OPEN, first: 100) { pageInfo { hasNextPage } nodes { url number title isDraft repository { nameWithOwner name } } }
    merged: pullRequests(states: MERGED, last: 100, orderBy: {field: CREATED_AT, direction: ASC}) { nodes { number repository { nameWithOwner } } }
  }$bot
}"
}

# backport_items BOT_PRS PARENTS LINKS -> JSON array of the backport PRs to
# watch: the bot's open PRs whose title ends "(#N)" or whose body carries
# "Original PR Nr.: #N", where N in the same repo is in PARENTS (lowercase refs
# of PRs Piotr authored) or linked by a pending task (LINKS, task_pr_links).
# Item: owner, repo, num, url, title, isDraft, backportOf (the parent ref) and
# tasks (the uuid8s of the tasks linking the parent).
backport_items() {
    jq -c --argjson parents "$2" --argjson links "$3" '
        def lc: ascii_downcase;
        ($links | map({key: ("\(.owner)/\(.repo)#\(.num)" | lc), value: .task})
         | group_by(.key) | map({key: .[0].key, value: (map(.value) | unique)}) | from_entries) as $lt
        | [ .[]
            | (.repository.nameWithOwner // "") as $nwo
            | select($nwo | test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$"))
            | ( ((.title // "") | capture("\\(#(?<n>[0-9]+)\\)\\s*$") | .n)
                // ((.body // "") | capture("Original PR Nr\\.:\\s*#(?<n>[0-9]+)") | .n) ) as $pn
            | "\($nwo)#\($pn)" as $parent
            | ($parent | lc) as $pk
            | select((($parents | index($pk)) != null) or ($lt[$pk] != null))
            | {owner: ($nwo | split("/")[0]), repo: ($nwo | split("/")[1]), num: .number, url: (.url // ""),
               title: (.title // ""), isDraft: (.isDraft // false), backportOf: $parent, tasks: ($lt[$pk] // [])} ]' <<<"$1"
}

# task_pr_links -> JSON array of {owner, repo, num, task}: one row per GitHub PR
# URL (https://github.com/<owner>/<repo>/pull/<n>) found in the description or
# an annotation of any PENDING task, with the first 8 characters of the task
# uuid. Context none, so hidden +gordon tasks count. Fails when task does.
task_pr_links() {
    local out
    out=$(task rc.context=none rc.verbose=nothing rc.hooks=off rc.confirmation=no status:pending export 2>/dev/null) || return 1
    jq -c '
        [ .[]? | select(.status == "pending") | (.uuid // "")[0:8] as $u
          | ([.description // ""] + [(.annotations // [])[]? | .description // ""])[]
          | scan("(?i)https?://github\\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)/pull/([0-9]+)")
          | {owner: .[0], repo: .[1], num: (.[2] | tonumber), task: $u} ]
        | unique' <<<"$out"
}

# build_watch AUTHORED LINKS CUTOFF [BACKPORTS] < STATE -> JSON array, one item
# per PR to look at, merged from four sources: Piotr's open authored PRs
# (AUTHORED, the viewer.open rows), PRs linked from pending tasks (LINKS,
# task_pr_links), backport PRs (BACKPORTS, backport_items), and PRs the state
# file saw open at or after CUTOFF (epoch) that no source names any more, which
# are fetched once to catch a merge or close and then dropped.
# Item: key (lowercase owner/repo#n), owner, repo, num, url, title, isDraft,
# authored, tasks (uuid8 list), backportOf (parent ref or ""), watch (named by a
# live source), skey (state key, "" when new), terminal ("merged"/"closed"/""),
# skip ("org", "draft", "terminal" or "" to fetch it). Order follows first
# appearance.
build_watch() {
    local orgs
    orgs=$(jq -cn --arg o "${NUDGE_ORGS//,/ }" '$o | [splits("[[:space:]]+")] | map(select(. != "") | ascii_downcase)')
    jq -c --argjson authored "$1" --argjson links "$2" --argjson cutoff "$3" --argjson backports "${4:-[]}" --argjson orgs "$orgs" '
        def lc: ascii_downcase;
        def ok: test("^[A-Za-z0-9._-]+$");
        (to_entries
         | map(select((.key | startswith("_") | not) and (.value | type == "object") and ((.value.ref // "") != ""))
               | {key: (.value.ref | lc),
                  value: {sk: .key, term: (.value.terminal // ""), seen: (.value.seenOpen // 0),
                          tasks: (.value.tasks // []), url: (.value.url // .key), bp: (.value.backportOf // "")}})
         | from_entries) as $idx
        | ( [ $authored[]
              | ((.repository.nameWithOwner // "") | split("/")) as $p
              | {owner: (if ($p | length) == 2 and $p[0] != "" then $p[0] else "loft-sh" end),
                 repo: (.repository.name // ($p[1] // "")), num: .number, url: (.url // ""),
                 title: (.title // ""), isDraft: (.isDraft // false), authored: true, tasks: []} ]
            + [ $links[] | {owner, repo, num, url: "https://github.com/\(.owner)/\(.repo)/pull/\(.num)",
                            title: "", isDraft: false, authored: false, tasks: [.task]} ]
            + [ $backports[] | {owner, repo, num, url, title, isDraft, authored: false, tasks, backportOf} ]
            + [ $idx | to_entries[] | select(.value.seen >= $cutoff)
                | (.key | capture("^(?<o>[^/]+)/(?<r>[^#]+)#(?<n>[0-9]+)$")?) as $c | select($c != null)
                | {owner: $c.o, repo: $c.r, num: ($c.n | tonumber), url: .value.url, title: "",
                   isDraft: false, authored: false, tasks: .value.tasks, backportOf: .value.bp, tracked: true} ] ) as $all
        | $all | to_entries | map(.value + {rank: .key})
        | map(select((.owner | ok) and (.repo | ok) and (.num | type == "number")))
        | map(. + {key: ("\(.owner)/\(.repo)#\(.num)" | lc)})
        | group_by(.key)
        | map( (any(.[]; .tracked | not)) as $live
               | (sort_by(if .authored then 0 elif .tracked then 2 else 1 end) | .[0])
                 + { authored: any(.[]; .authored), watch: $live, rank: (map(.rank) | min),
                     backportOf: ([.[] | .backportOf // "" | select(. != "")] | first // ""),
                     tasks: ([.[] | select((.tracked | not) or ($live | not)) | .tasks[]] | unique) } )
        | sort_by(.rank)
        | map(. + {skey: ($idx[.key].sk // ""), terminal: ($idx[.key].term // "")})
        | map((.owner | lc) as $o
              | . + {skip: (if ($orgs | length) > 0 and (($orgs | index($o)) == null) then "org"
                          elif .isDraft then "draft"
                          elif (.authored | not) and .terminal != "" then "terminal"
                          else "" end)})'
}

# finish_state LIVE CUTOFF PRUNE < STATE -> STATE with the owning tasks stamped
# on every entry a live source still names (LIVE: lowercase ref -> task list).
# With PRUNE=1 it also drops entries no source names that are terminal or were
# last seen open before CUTOFF, which retires the entries of PRs long merged.
# PRUNE=0 (a source failed) drops nothing, so a flaky search cannot erase state.
finish_state() {
    jq -c --argjson live "$1" --argjson cutoff "$2" --argjson prune "$3" '
        with_entries(
            if (.key | startswith("_")) or (.value | type != "object") then .
            else ((.value.ref // "") | ascii_downcase) as $r
                 | if $live[$r] != null then .value += {tasks: $live[$r]}
                   elif $prune == 1 and (((.value.terminal // "") != "") or ((.value.seenOpen // 0) < $cutoff)) then empty
                   else . end
            end)'
}

# jq expression for a state entry's backport marker, given --arg bp: the parent
# ref, so a backport fetched once more after it leaves the bot's open list still
# names its parent.
# shellcheck disable=SC2016  # jq variables, expanded by jq
BP_JQ='(if $bp == "" then {} else {backportOf: $bp} end)'

# GraphQL selection for one PR: what compute_sig reads (the `gh pr view --json`
# fields number,url,title,isDraft,headRefOid,reviewDecision,mergeable,reviews,
# comments,commits,statusCheckRollup,author) plus state/merged/closed. Only the
# newest commit is read: compute_sig takes `last`, and its rollup is the head's.
GQL_PR_FRAGMENT='fragment F on PullRequest {
  number url title isDraft state merged closed
  headRefOid reviewDecision mergeable
  author { login }
  reviews(last: 100) { nodes { author { login } submittedAt } }
  comments(last: 100) { nodes { author { login } createdAt } }
  commits(last: 1) { nodes { commit {
    oid committedDate authoredDate
    authors(first: 10) { nodes { user { login } } }
    statusCheckRollup { contexts(first: 100) { nodes {
      __typename
      ... on CheckRun { name status conclusion }
      ... on StatusContext { context state }
    } } }
  } } }
}'

# jq def mapping the GraphQL PullRequest above onto the `gh pr view --json`
# shape compute_sig consumes, so the signature code does not change.
GQL_VIEW_JQ='
    def nodes: (. // {}) | (.nodes // []);
    def view: {
        number, url, title, isDraft, state, merged, closed, headRefOid, reviewDecision, mergeable,
        author: {login: (.author.login // null)},
        reviews: [ (.reviews | nodes)[] | {author: {login: (.author.login // null)}, submittedAt} ],
        comments: [ (.comments | nodes)[] | {author: {login: (.author.login // null)}, createdAt} ],
        commits: [ (.commits | nodes)[] | .commit | {oid, committedDate, authoredDate,
                   authors: [ (.authors | nodes)[] | {login: (.user.login // null)} ]} ],
        statusCheckRollup: ((.commits | nodes | last | .commit.statusCheckRollup.contexts | nodes) // [])
    };'

# gql_to_view PR_JSON -> the PullRequest node as a `gh pr view --json` object.
gql_to_view() {
    jq -c "$GQL_VIEW_JQ"' view' <<<"$1"
}

# gql_query ITEMS -> one query with an aliased repository(...).pullRequest(...)
# field per item (p0, p1, ...). Owner and repo passed build_watch's name check.
gql_query() {
    jq -r --arg frag "$GQL_PR_FRAGMENT" '
        "query {\n"
        + ([to_entries[] | "p\(.key): repository(owner: \"\(.value.owner)\", name: \"\(.value.repo)\") { pullRequest(number: \(.value.num)) { ...F } }"] | join("\n"))
        + "\n}\n" + $frag' <<<"$1"
}

# fetch_details ITEMS OUT_FILE -> OUT_FILE holds {lowercase ref: view-shaped PR}
# for every PR GitHub returned, read GQL_CHUNK PRs per `gh api graphql` call
# (ceil(N/GQL_CHUNK) calls, not N). gh exits 1 and still prints the data when one
# alias fails (a repo that is gone), so stdout is judged, not the exit status. A
# chunk with no data logs a WARN and skips only its PRs.
fetch_details() {
    local items="$1" out_file="$2" total i=0 chunk q resp k
    echo '{}' > "$out_file"
    total=$(jq 'length' <<<"$items")
    while (( i < total )); do
        chunk=$(jq -c --argjson i "$i" --argjson n "$GQL_CHUNK" '.[$i:$i+$n]' <<<"$items")
        q=$(gql_query "$chunk")
        resp=$(gh api graphql -f query="$q" 2>"${out_file}.err") || true
        if jq -e '(.data | type) == "object"' <<<"$resp" >/dev/null 2>&1; then
            jq -c --argjson chunk "$chunk" --slurpfile acc "$out_file" "$GQL_VIEW_JQ"'
                $acc[0] + ( [ range(0; $chunk | length) as $i
                              | (.data["p\($i)"].pullRequest // null) as $pr | select($pr != null)
                              | {($chunk[$i].key): ($pr | view)} ] | add // {} )' <<<"$resp" > "${out_file}.tmp" \
                && mv "${out_file}.tmp" "$out_file"
            while IFS= read -r k; do
                [[ -n "$k" ]] && log "WARN: no GraphQL data for $k (not found or no access); skipping"
            done < <(jq -r --argjson chunk "$chunk" \
                '[range(0; $chunk | length) as $i | select(.data["p\($i)"].pullRequest == null) | $chunk[$i].key] | .[]' <<<"$resp")
        else
            log "WARN: graphql chunk at offset $i failed ($(jq 'length' <<<"$chunk") PR(s)): $(head -c 200 "${out_file}.err" | tr '\n' ' ' | sed 's/ *$//'); skipping them this cycle"
        fi
        i=$(( i + GQL_CHUNK ))
    done
}

# write_summary WATCHED -> the status line's view of this run, in a tiny file of
# its own so the render never parses the state file or calls gh. Epoch lets a
# reader judge staleness without parsing the ISO stamp.
write_summary() {
    local tmp
    tmp=$(mktemp "${SUMMARY_FILE}.XXXXXX") || return 0
    if jq -cn --argjson w "$1" --arg u "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson e "$(now_epoch)" \
        '{watched: $w, updated: $u, epoch: $e}' > "$tmp"; then
        mv "$tmp" "$SUMMARY_FILE"
    else
        rm -f "$tmp"
    fi
}

# --- main ---
main() {
    local mode="LIVE"; [[ "$DRY_RUN" -eq 1 ]] && mode="DRY-RUN"
    log "=== PR-movement watcher starting (me=$ME, selves=$SELVES_JSON, mode=$mode) ==="

    [[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"
    local old_state; old_state=$(cat "$STATE_FILE" 2>/dev/null); [[ -n "$old_state" ]] || old_state='{}'

    # Resolved once per run: every DM below goes to Kendra (intake) while she is
    # live, else to Gordon (triage).
    local target; target=$(resolve_target)
    log "delivery target: $target"

    # Sources. A source that fails never reads as "nothing there": it only
    # stops state from being pruned (healthy=0), so a flaky search cannot erase
    # what we already track.
    local authored links src backports parents='[]' botprs='[]' healthy=1
    # Open authored PRs (all orgs), recent merged ones and the backport bot's
    # open PRs, in one call. gh exits 1 when one field errors and still prints
    # the rest, so stdout is judged, not the exit status.
    src=$(gh api graphql -f query="$(sources_query)" 2>/dev/null) || true
    if jq -e '(.data.viewer.open.nodes | type) == "array"' <<<"$src" >/dev/null 2>&1; then
        authored=$(jq -c '.data.viewer.open.nodes' <<<"$src")
        parents=$(jq -c '[.data.viewer.open.nodes[], (.data.viewer.merged.nodes // [])[]
                          | "\(.repository.nameWithOwner)#\(.number)" | ascii_downcase] | unique' <<<"$src")
        if jq -e '.data.viewer.open.pageInfo.hasNextPage == true' <<<"$src" >/dev/null 2>&1; then
            log "WARN: over 100 open authored PRs; only the first 100 are read"; healthy=0
        fi
    else
        log "WARN: authored PR query failed; tracked PRs stay as they are"
        authored='[]'; healthy=0
    fi
    if [[ -n "$BACKPORT_BOT" ]]; then
        if jq -e '(.data.bot.pullRequests.nodes | type) == "array"' <<<"$src" >/dev/null 2>&1; then
            botprs=$(jq -c '.data.bot.pullRequests.nodes' <<<"$src")
            if jq -e '.data.bot.pullRequests.pageInfo.hasNextPage == true' <<<"$src" >/dev/null 2>&1; then
                log "WARN: over 100 open $BACKPORT_BOT PRs; only the first 100 are read"; healthy=0
            fi
        else
            log "WARN: $BACKPORT_BOT PR query failed; backports stay as they are"; healthy=0
        fi
    fi
    # PRs linked from pending tasks, any tag.
    if ! links=$(task_pr_links); then
        log "WARN: pending task export failed; task-linked PRs not refreshed"
        links='[]'; healthy=0
    fi
    backports=$(backport_items "$botprs" "$parents" "$links") || { log "WARN: reading backports failed"; backports='[]'; healthy=0; }
    log "authored open PRs: $(jq 'length' <<<"$authored"); task-linked PR refs: $(jq 'map([.owner, .repo, .num] | join("/") | ascii_downcase) | unique | length' <<<"$links"); backports: $(jq 'length' <<<"$backports")"

    local now; now=$(now_epoch)
    local cutoff=$(( now - TRACK_WINDOW_SECS ))
    local watch
    watch=$(build_watch "$authored" "$links" "$cutoff" "$backports" <<<"$old_state") \
        || { log "ERROR: building the watch list failed"; return 1; }

    # Notify scope and drafts are settled before any API call.
    local skip sref
    while IFS=$'\t' read -r skip sref; do
        case "$skip" in
            org)   log "skip (org '${sref%%/*}' out of notify scope): $sref" ;;
            draft) log "skip (draft): $sref" ;;
        esac
    done < <(jq -r '.[] | select(.watch and (.skip == "org" or .skip == "draft")) | [.skip, "\(.owner)/\(.repo)#\(.num)"] | @tsv' <<<"$watch")

    local seen; seen=$(jq '[.[] | select(.watch and (.skip == "" or .skip == "draft"))] | length' <<<"$watch")
    local fetch_items; fetch_items=$(jq -c 'map(select(.skip == ""))' <<<"$watch")
    local polled; polled=$(jq 'length' <<<"$fetch_items")
    local watched; watched=$(jq '[.[] | select(.watch)] | length' <<<"$fetch_items")
    log "polling $polled PR(s), $watched watched, in $(( (polled + GQL_CHUNK - 1) / GQL_CHUNK )) graphql call(s)"

    DETAILS_FILE=$(mktemp "${TMPDIR:-/tmp}/pr-move-details.XXXXXX") || { log "ERROR: mktemp failed"; return 1; }
    trap 'rm -f "$DETAILS_FILE" "${DETAILS_FILE}.tmp" "${DETAILS_FILE}.err"' EXIT
    fetch_details "$fetch_items" "$DETAILS_FILE"

    local new_state="$old_state"
    local -a nudges=() owners=()
    local moved=0

    local item key org repo num is_authored skey tracked_only backport_of
    local url ref title detail pstate old sig tasks_json tasks_csv task_sfx bp_sfx foreign_ok
    while read -r item; do
        [[ -z "$item" ]] && continue
        IFS=$'\x1f' read -r key org repo num is_authored skey tracked_only backport_of < <(
            jq -r '[.key, .owner, .repo, (.num | tostring), (.authored | tostring), .skey, ((.watch | not) | tostring), (.backportOf // "")] | join("\u001f")' <<<"$item")
        # fetch_details already logged why a PR has no data.
        detail=$(jq -c --arg k "$key" '.[$k] // empty' "$DETAILS_FILE")
        [[ -n "$detail" ]] || continue

        url=$(jq -r '.url // empty' <<<"$detail"); [[ -n "$url" ]] || url=$(jq -r '.url' <<<"$item")
        ref=$(jq -r --arg d "$org/$repo#$num" '(.url // "" | capture("github\\.com/(?<o>[^/]+)/(?<r>[^/]+)/pull/(?<n>[0-9]+)")? | "\(.o)/\(.r)#\(.n)") // $d' <<<"$detail")
        title=$(jq -r '.title // ""' <<<"$item"); [[ -n "$title" ]] || title=$(jq -r '.title // ""' <<<"$detail")
        [[ -n "$skey" ]] || skey="$url"
        tasks_json=$(jq -c '.tasks' <<<"$item")
        tasks_csv=$(jq -r 'join(",")' <<<"$tasks_json")
        task_sfx=""; [[ -n "$tasks_csv" ]] && task_sfx=" task:$tasks_csv"
        bp_sfx=""; [[ -n "$backport_of" ]] && bp_sfx=" (backport of $backport_of)"
        pstate=$(jq -r '.state // "OPEN"' <<<"$detail")
        old=$(jq -c --arg k "$skey" '.[$k] // empty' <<<"$old_state" 2>/dev/null || true)

        # Contention: a live worker owns it. Detect events as usual, but the
        # delivery below goes to the owner and to the target (marked owned), so a
        # review or approval landing while the worker is idle is never lost.
        local owner=""

        # ---- merged / closed: terminal, fires once on the edge ----
        # Seen open before (`seenOpen`, written below each time an open PR is
        # fetched) and gone terminal now is the edge. First contact seeds
        # silently, like every other reason, so a task that cites a long-merged
        # PR does not replay history. That includes an entry from before
        # `seenOpen` existed: it records a PR open at some past date, not at the
        # last cycle. The entry is kept as terminal so a PR that stays linked is
        # neither fetched nor reported again.
        if [[ "$pstate" == "MERGED" || "$pstate" == "CLOSED" ]]; then
            local term="${pstate,,}"
            new_state=$(jq -c --arg k "$skey" --arg ref "$ref" --arg url "$url" --arg t "$term" --argjson now "$now" --argjson tasks "$tasks_json" --arg bp "$backport_of" \
                ".[\$k] = ({ref:\$ref, url:\$url, terminal:\$t, terminalAt:\$now, tasks:\$tasks} + $BP_JQ)" <<<"$new_state")
            if [[ -z "$old" ]] || ! jq -e 'has("seenOpen")' <<<"$old" >/dev/null 2>&1; then
                log "seed (first contact, already $term): $ref"
                continue
            fi
            if jq -e '(.terminal // "") != ""' <<<"$old" >/dev/null 2>&1; then
                continue
            fi
            pr_has_live_session "$num" && owner="$OWNER_SESSION"
            moved=$((moved + 1))
            local tmsg_term="pr-move: $ref $term $url$task_sfx$bp_sfx"
            log "MOVED: $tmsg_term"
            nudges+=("$tmsg_term")
            owners+=("$owner")
            continue
        fi

        # Back open after a terminal state (reopened): first contact again.
        if [[ -n "$old" ]] && jq -e '(.terminal // "") != ""' <<<"$old" >/dev/null 2>&1; then old=""; fi

        # Tracked only to catch a merge or close, and it is still open: no source
        # names it now. Leave its entry alone, without refreshing seenOpen, so it
        # ages out of the track window. Dropping it at once would lose the
        # baseline whenever `gh search` skips a PR for a cycle (it does: the
        # authored count moved 42 to 41 and back between two runs minutes apart).
        if [[ "$tracked_only" == "true" ]]; then
            log "idle (no source names it, still open): $ref"
            continue
        fi

        if [[ "$(jq -r '.isDraft // false' <<<"$detail")" == "true" ]]; then
            log "skip (draft): $ref"
            continue
        fi

        sig=$(compute_sig "$detail") || { log "WARN: sig compute failed for $ref"; continue; }

        # First contact: seed silently, no nudge (mirrors Linear new_activity seed).
        # Record any sticky reason ALREADY true at seed as notified, so a
        # pre-existing red build / changes-requested / conflict does not fire on
        # the next cycle; it fires only if it clears and comes back. Edge reasons
        # need no seed handling: their baseline (headSha, lastForeignActivity) is
        # recorded here, so only new activity fires later.
        local sticky_now; sticky_now=$(sticky_set "$sig")

        if [[ -z "$old" ]]; then
            log "seed (first contact): $ref"
            new_state=$(jq -c --arg k "$skey" --argjson s "$sig" --arg ref "$ref" --arg url "$url" --argjson ns "$sticky_now" --argjson now "$now" --arg bp "$backport_of" \
                ".[\$k] = (\$s + {ref:\$ref, url:\$url, notifiedSticky:\$ns, seenOpen:\$now} + $BP_JQ)" <<<"$new_state")
            continue
        fi

        # Carry the notified set forward (old is non-empty here); recomputed below
        # once we know what fired. An entry written by the pre-dedup version has no
        # notifiedSticky: adopt the current sticky state rather than defaulting to
        # empty, or every already-nudged PR would re-fire once on upgrade.
        local notified
        if jq -e 'has("notifiedSticky")' <<<"$old" >/dev/null 2>&1; then
            notified=$(jq -c '.notifiedSticky // []' <<<"$old")
        else
            log "migrate (adopting current sticky state, no nudge): $ref"
            notified="$sticky_now"
        fi

        pr_has_live_session "$num" && owner="$OWNER_SESSION"

        # Push cooldown: we (Piotr or the agent, same login) pushed recently.
        # Not applied to an owned PR: the owner's own push would otherwise
        # swallow a review that arrives right after it.
        local mine last_date last_epoch
        mine=$(jq -r '.lastCommitMine' <<<"$sig")
        last_date=$(jq -r '.lastCommitDate' <<<"$sig")
        if [[ -z "$owner" && "$mine" == "true" && -n "$last_date" ]]; then
            last_epoch=$(iso_to_epoch "$last_date")
            if [[ $(( $(now_epoch) - last_epoch )) -lt "$PUSH_COOLDOWN_SECS" ]]; then
                log "skip (recent own push, cooldown): $ref"
                new_state=$(jq -c --arg k "$skey" --argjson s "$sig" --arg ref "$ref" --arg url "$url" --argjson ns "$notified" --argjson now "$now" --arg bp "$backport_of" \
                    ".[\$k] = (\$s + {ref:\$ref, url:\$url, notifiedSticky:\$ns, seenOpen:\$now} + $BP_JQ)" <<<"$new_state")
                continue
            fi
        fi

        # foreign-push means "someone else pushed to MY PR". On a task-linked PR
        # another person authored, every push is theirs, so it stays quiet there.
        foreign_ok=0
        if [[ "$is_authored" == "true" ]] || jq -e --argjson selves "$SELVES_JSON" \
            '(.author.login // "") as $l | ($selves | index($l)) != null' <<<"$detail" >/dev/null 2>&1; then
            foreign_ok=1
        fi

        # ---- diff old vs new; collect reasons ----
        local -a reasons=()
        local r cur_fa old_fa cur_sha old_sha known
        cur_fa=$(jq -r '.lastForeignActivity' <<<"$sig");      old_fa=$(jq -r '.lastForeignActivity' <<<"$old")
        cur_sha=$(jq -r '.headSha' <<<"$sig");                 old_sha=$(jq -r '.headSha' <<<"$old")
        known=$(jq -r '.lastCommitKnownAuthors' <<<"$sig")

        # Sticky reasons (changes-requested, ci-red, merge-conflict) fire only on
        # ENTERING the state: a reason already in notifiedSticky stays silent for
        # as long as it holds, and re-fires only if it clears and comes back.
        while IFS= read -r r; do
            [[ -n "$r" ]] && reasons+=("$r")
        done < <(sticky_new "$sticky_now" "$notified")
        # review-comment (edge): new foreign activity, unless already counted as changes-requested
        if [[ -n "$cur_fa" && "$cur_fa" > "$old_fa" ]]; then
            local has_cr=0; for r in "${reasons[@]:-}"; do [[ "$r" == "changes-requested" ]] && has_cr=1; done
            [[ "$has_cr" -eq 0 ]] && reasons+=("review-comment")
        fi
        # foreign-push (edge): head moved to a commit not authored by us
        if [[ "$cur_sha" != "$old_sha" && "$known" -gt 0 && "$mine" != "true" && "$foreign_ok" -eq 1 ]]; then
            reasons+=("foreign-push")
        fi

        # The sticky states we will record as notified: everything true now. A
        # reason that has cleared drops out here, so it fires again if it returns.
        local new_notified="$sticky_now"

        # Suppress a BARE ci-red on CI/dependency/release PRs: the red is
        # E2E-on-PR that does not apply, not a code defect (Gordon re-verifies
        # regardless). Only when ci-red is the sole reason; an accompanied ci-red
        # rides along with changes-requested/merge-conflict/review-comment. Leave
        # ci-red OUT of the notified set so it stays un-sent and can still ride
        # along the day a real reason lands on this PR.
        if [[ ${#reasons[@]} -eq 1 && "${reasons[0]}" == "ci-red" ]] && ci_red_is_noise "$title"; then
            log "suppress (bare ci-red, ci/deps/release PR): $ref [$title]"
            reasons=()
            new_notified=$(jq -c 'map(select(. != "ci-red"))' <<<"$new_notified")
        fi

        # persist the advanced signature + notified set regardless of fire
        new_state=$(jq -c --arg k "$skey" --argjson s "$sig" --arg ref "$ref" --arg url "$url" --argjson ns "$new_notified" --argjson now "$now" --arg bp "$backport_of" \
            ".[\$k] = (\$s + {ref:\$ref, url:\$url, notifiedSticky:\$ns, seenOpen:\$now} + $BP_JQ)" <<<"$new_state")

        if [[ ${#reasons[@]} -eq 0 ]]; then
            continue
        fi
        moved=$((moved + 1))
        local reason_str; reason_str=$(IFS=,; echo "${reasons[*]}")
        local msg="pr-move: $ref $reason_str $url$task_sfx$bp_sfx"
        log "MOVED: $msg"
        nudges+=("$msg")
        owners+=("$owner")
    done < <(jq -c '.[]' <<<"$fetch_items")

    # Direct review requests on other people's PRs. A failed search keeps the
    # previous set, or every open request would re-fire once the search recovers.
    local reqs
    if reqs=$(gh search prs --state open --limit 100 \
                --json url,number,repository,isDraft,author -- "user-review-requested:$ME" 2>/dev/null) \
            && jq -e 'type == "array"' <<<"$reqs" >/dev/null 2>&1; then
        reqs=$(review_requests_human "$reqs")
        if jq -e 'has("_reviewRequests")' <<<"$old_state" >/dev/null; then
            local seen_reqs author
            seen_reqs=$(jq -c '._reviewRequests' <<<"$old_state")
            while IFS=$'\t' read -r ref author url; do
                [[ -z "$url" ]] && continue
                log "REQUESTED: review-request: $ref from $author $url"
                nudges+=("review-request: $ref from $author $url")
                owners+=("")
            done < <(review_requests_new "$reqs" "$seen_reqs")
        else
            log "seed (first contact): $(jq 'length' <<<"$reqs") direct review request(s)"
        fi
        new_state=$(jq -c --argjson u "$(jq -c 'map(.url)' <<<"$reqs")" '._reviewRequests = $u' <<<"$new_state")
    else
        log "WARN: direct review-request search failed; keeping the previous set"
    fi

    # Name the owning tasks on what a live source still names, retire the rest,
    # and write state atomically.
    local live; live=$(jq -c 'map(select(.watch)) | map({key: .key, value: .tasks}) | from_entries' <<<"$watch")
    new_state=$(finish_state "$live" "$cutoff" "$healthy" <<<"$new_state")
    local tmp; tmp=$(mktemp "${STATE_FILE}.XXXXXX") || { log "ERROR: mktemp failed"; return 1; }
    echo "$new_state" | jq '.' > "$tmp" && mv "$tmp" "$STATE_FILE"
    write_summary "$watched"

    # Deliver: one DM per line up to the cap; past it the rest ride together in
    # one more DM, one line each. State is already written, so a line left
    # unsent here would be lost for good.
    local total=${#nudges[@]} sent=0 i own tmsg
    local -a out=() overflow=()
    for i in "${!nudges[@]}"; do
        own="${owners[$i]}" tmsg="${nudges[$i]}"
        if [[ -n "$own" ]]; then
            tmsg="${nudges[$i]} (owned by $own)"
        fi
        record "$tmsg"
        if [[ -n "$own" ]]; then
            deliver "${nudges[$i]}" "$own"
        fi
        if (( total <= CYCLE_CAP || ${#out[@]} < CYCLE_CAP - 1 )); then
            out+=("$tmsg")
        else
            overflow+=("$tmsg")
        fi
    done
    if (( ${#overflow[@]} > 0 )); then
        log "cycle cap $CYCLE_CAP reached; ${#overflow[@]} line(s) ride in one DM"
        out+=("$(printf '%s\n' "${overflow[@]}")")
    fi
    for tmsg in "${out[@]}"; do
        deliver "$tmsg" "$target"
        sent=$((sent + 1))
    done

    if [[ "$DRY_RUN" -eq 0 && -x "$HANDOFF_CHECK" ]]; then
        timeout 120 "$HANDOFF_CHECK" --close --kind pr-merged,pr-closed 2>&1 |
            while read -r line; do log "  handoff: $line"; done || true
    fi

    log "=== done: seen=$seen watched=$watched moved=$moved sent=$([[ $DRY_RUN -eq 1 ]] && echo 0 || echo $sent) (mode=$mode) ==="
}

# Serialize runs (manual invocation must not race the systemd one).
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "another pr-movement run holds the lock; exiting" >&2
    exit 0
fi
main "$@"
