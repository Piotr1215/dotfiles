#!/usr/bin/env bash
# PROJECT: ambient-triage
# See: ops-triage-agent.md, __auto_triage_nudge.sh, __get_prs_for_review.sh,
#      ~/.claude/tmp/pr-nudge-design.md (design)
#
# PR-movement to auto-dispatch watcher. Stage 0: DRY-RUN by default.
#
# Detects movement on Piotr's OPEN AUTHORED PRs and DMs the `triage` agent
# (Gordon) one `pr-move:` line per genuinely-moved PR, mirroring how
# __auto_triage_nudge.sh nudges Gordon after the Linear sync. Gordon then runs
# pull->form->decide and dispatches a NORMAL worker (__spawn_agent.sh --pr,
# defaults to /ops-autonomous-worker), never the review panel.
#
# Wired as ExecStartPost on gh-pr-review-sync.service so it inherits that
# service's 15-min cadence. It enumerates independently and cross-org, so it
# does not depend on the shared project:pr-reviews task dataset.
#
# Movements that FIRE (authored, open, non-draft PRs):
#   changes-requested  reviewDecision -> CHANGES_REQUESTED               (sticky)
#   review-comment     new review/comment by a non-Piotr, non-bot actor  (edge)
#   ci-red             statusCheckRollup -> FAILURE                       (sticky)
#   merge-conflict     mergeable -> CONFLICTING                          (sticky)
#   foreign-push       new head commit whose author is not Piotr         (edge)
# IGNORED: Piotr's own / the agent's own push (both authored as Piotr), draft
#   PRs, bot comments, CI green/pending, approvals (surface-only), Piotr's edits.
#
# Self-retrigger guard: per-PR signature keyed on headSha in the state file.
#   First contact seeds silently (no nudge), mirroring the Linear new_activity
#   silent-seed. Because the worker commits AS Piotr, any Piotr-authored change
#   is by definition not a trigger.
# Contention guard: skip a PR already owned by a live (non-spend-stalled) tmux
#   session, or one Piotr/the agent pushed to within PUSH_COOLDOWN_SECS.
#
# LIMITATION (Stage 0): inline review-thread replies are not in `gh pr view
#   --json`; they surface indirectly via the carrying review / updatedAt. A
#   later GraphQL enrichment can add reviewThreads if needed.
#
# Usage:
#   __pr_movement_nudge.sh            # DRY-RUN (default): log only, no DM
#   __pr_movement_nudge.sh --dry-run  # same, explicit
#   __pr_movement_nudge.sh --live     # send pr-move: DMs to triage
set -eo pipefail

# env for cron/systemd (node on PATH, bus env, gh auth)
# shellcheck disable=SC1091
[[ -f "$HOME/.envrc" ]] && source "$HOME/.envrc"

LOG_FILE="${PR_MOVE_LOG:-/tmp/pr-movement-nudge.log}"
STATE_FILE="${PR_MOVE_STATE:-$HOME/.claude/data/pr-watermarks.json}"
LOCK_FILE="${PR_MOVE_LOCK:-/tmp/pr-movement-nudge.lock}"

DRY_RUN=1
case "${1:-}" in
    --live) DRY_RUN=0 ;;
    --dry-run|"") DRY_RUN=1 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
esac

# Delivery: identical to __auto_triage_nudge.sh (Node snd -> agents.dm.<b64url>).
# No presence gate; NATS Core drops if triage is not subscribed. SND_FROM marks
# origin so the bus shows the nudge as watcher-originated.
SND_NODE_BIN="${SND_NODE_BIN:-/home/decoder/dev/agents-mcp-server/build/snd.js}"
AGENTS_NATS_URL_DEFAULT="nats://nats-nats-tailscale.tail165ec.ts.net:4222"
export AGENTS_NATS_URL="${AGENTS_NATS_URL:-$AGENTS_NATS_URL_DEFAULT}"
export SND_FROM="${SND_FROM:-pr-watch}"

# Tunables
PUSH_COOLDOWN_SECS="${PR_MOVE_PUSH_COOLDOWN:-600}"        # skip if we pushed within 10m
STICKY_COOLDOWN_SECS="${PR_MOVE_STICKY_COOLDOWN:-3600}"   # re-nudge sticky states hourly
CYCLE_CAP="${PR_MOVE_CYCLE_CAP:-8}"                       # max pr-move DMs per cycle
ME="${PR_MOVE_ME:-$(gh api user --jq .login 2>/dev/null || echo Piotr1215)}"

# Spend/rate-limit wall markers (same set __cockpit_state.sh uses): a session at
# this wall is dead work, not ownership, so it must not suppress a nudge.
STALL_RE='spend limit|rate-limit-options|Add funds|wait for limit to reset|usage-credits|approaching your usage limit'

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*" | tee -a "$LOG_FILE"; }

# Send a DM to triage over the NATS comms bus (same path as __auto_triage_nudge.sh).
send_dm() { node "$SND_NODE_BIN" -t triage "$1" 2>&1; }

now_epoch() { date +%s; }
iso_to_epoch() { date -d "$1" +%s 2>/dev/null || echo 0; }

# --- contention: a live, non-spend-stalled tmux session owns this PR? ---
pr_has_live_session() {
    local num="$1" sess pane
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
            return 0
        fi
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
    return 1
}

# --- signature: reduce one PR's `gh pr view` JSON to the watched dimensions ---
compute_sig() {
    local detail="$1"
    jq -c --arg me "$ME" '
        def isbot($l): ($l|type=="string") and (($l|endswith("[bot]"))
            or ((["dependabot","dependabot-preview","renovate","codecov","github-actions","loft-bot","snyk-bot"])|index($l) != null));
        def foreign($l): ($l != null) and ($l != $me) and (isbot($l)|not);
        (.commits // []) as $c
        | ($c | last) as $last
        | ($last.authors // [] | map(.login)) as $la
        | {
            headSha: (.headRefOid // ""),
            reviewDecision: (.reviewDecision // ""),
            mergeable: (.mergeable // "UNKNOWN"),
            lastCommitKnownAuthors: ($la | map(select(. != null and . != "")) | length),
            lastCommitMine: (($la | index($me)) != null),
            lastCommitDate: ($last.committedDate // $last.authoredDate // ""),
            lastForeignActivity: (
                ([ (.reviews // [])[] | select(foreign(.author.login)) | .submittedAt ]
                 + [ (.comments // [])[] | select(foreign(.author.login)) | .createdAt ])
                | map(select(. != null)) | (max // "")),
            changesRequested: ((.reviewDecision // "") == "CHANGES_REQUESTED"),
            checks: (
                (.statusCheckRollup // []) as $r
                | if ($r | length) == 0 then "NONE"
                  elif any($r[];
                        ((.conclusion // "" | ascii_upcase) as $x | ($x=="FAILURE" or $x=="TIMED_OUT" or $x=="CANCELLED" or $x=="ERROR" or $x=="STARTUP_FAILURE"))
                        or ((.state // "" | ascii_upcase) as $s | ($s=="FAILURE" or $s=="ERROR")))
                    then "FAILURE"
                  elif any($r[];
                        ((.status // "" | ascii_upcase) as $st | ($st=="IN_PROGRESS" or $st=="QUEUED" or $st=="PENDING" or $st=="WAITING" or $st=="REQUESTED"))
                        or ((.state // "" | ascii_upcase) as $s | ($s=="PENDING" or $s=="EXPECTED")))
                    then "PENDING"
                  else "SUCCESS" end)
        }' <<<"$detail"
}

# sticky_ready OLD_JSON REASON  -> 0 if the per-reason cooldown has elapsed
sticky_ready() {
    local old="$1" reason="$2" until_epoch
    until_epoch=$(jq -r --arg r "$reason" '.cooldownUntil[$r] // 0' <<<"$old" 2>/dev/null || echo 0)
    [[ "$until_epoch" =~ ^[0-9]+$ ]] || until_epoch=0
    [[ "$(now_epoch)" -ge "$until_epoch" ]]
}

# --- main ---
main() {
    local mode="LIVE"; [[ "$DRY_RUN" -eq 1 ]] && mode="DRY-RUN"
    log "=== PR-movement watcher starting (me=$ME, mode=$mode) ==="

    [[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"
    local old_state; old_state=$(cat "$STATE_FILE" 2>/dev/null); [[ -n "$old_state" ]] || old_state='{}'

    # Enumerate open authored PRs, all orgs (cross-org fixes the loft-sh-only gap).
    local prs
    prs=$(gh search prs --author "@me" --state open --limit 100 \
            --json url,number,title,repository,isDraft 2>/dev/null || echo '[]')
    local total; total=$(jq 'length' <<<"$prs")
    log "authored open PRs: $total"

    local new_state="$old_state"
    local -a nudges=()
    local seen=0 moved=0

    local pr url num repo owner ref is_draft detail sig old key
    while read -r pr; do
        [[ -z "$pr" ]] && continue
        url=$(jq -r '.url' <<<"$pr")
        num=$(jq -r '.number' <<<"$pr")
        repo=$(jq -r '.repository.name // ""' <<<"$pr")
        owner=$(jq -r '(.repository.nameWithOwner // "") | split("/")[0]' <<<"$pr")
        is_draft=$(jq -r '.isDraft' <<<"$pr")
        [[ -z "$owner" ]] && owner="loft-sh"
        ref="$owner/$repo#$num"
        key="$url"
        seen=$((seen + 1))

        [[ "$is_draft" == "true" ]] && { log "skip (draft): $ref"; continue; }

        detail=$(gh pr view "$url" --json number,url,title,isDraft,headRefOid,reviewDecision,mergeable,reviews,comments,commits,statusCheckRollup,author 2>/dev/null) \
            || { log "WARN: gh pr view failed for $ref"; continue; }

        sig=$(compute_sig "$detail") || { log "WARN: sig compute failed for $ref"; continue; }
        old=$(jq -c --arg k "$key" '.[$k] // empty' <<<"$old_state" 2>/dev/null || true)

        # First contact: seed silently, no nudge (mirrors Linear new_activity seed).
        # Arm the sticky cooldown for any reason ALREADY true at seed, so a
        # pre-existing red build / changes-requested / conflict does not fire on
        # the next cycle; it re-nudges only after STICKY_COOLDOWN if still true,
        # or on a fresh transition. Edge reasons need no seed handling: their
        # baseline (headSha, lastForeignActivity) is recorded here, so only new
        # activity fires later.
        if [[ -z "$old" ]]; then
            log "seed (first contact): $ref"
            local seed_cd
            seed_cd=$(jq -cn --argjson t "$(( $(now_epoch) + STICKY_COOLDOWN_SECS ))" --argjson s "$sig" \
                'reduce ([ (if $s.changesRequested then "changes-requested" else empty end),
                           (if $s.checks == "FAILURE" then "ci-red" else empty end),
                           (if $s.mergeable == "CONFLICTING" then "merge-conflict" else empty end) ][]) as $r ({}; . + {($r): $t})')
            new_state=$(jq -c --arg k "$key" --argjson s "$sig" --arg ref "$ref" --arg url "$url" --argjson cd "$seed_cd" \
                '.[$k] = ($s + {ref:$ref, url:$url, cooldownUntil:$cd})' <<<"$new_state")
            continue
        fi

        # carry the cooldown map forward (old is non-empty here); refreshed below
        # when a sticky reason fires.
        local cooldown; cooldown=$(jq -c '.cooldownUntil // {}' <<<"$old" 2>/dev/null || echo '{}')

        # Contention: a live worker owns it -> stay silent, but advance the
        # watermark so we do not later treat the worker's changes as new.
        if pr_has_live_session "$num"; then
            new_state=$(jq -c --arg k "$key" --argjson s "$sig" --arg ref "$ref" --arg url "$url" --argjson cd "$cooldown" \
                '.[$k] = ($s + {ref:$ref, url:$url, cooldownUntil:$cd})' <<<"$new_state")
            continue
        fi

        # Push cooldown: we (Piotr or the agent, same login) pushed recently.
        local mine last_date last_epoch
        mine=$(jq -r '.lastCommitMine' <<<"$sig")
        last_date=$(jq -r '.lastCommitDate' <<<"$sig")
        if [[ "$mine" == "true" && -n "$last_date" ]]; then
            last_epoch=$(iso_to_epoch "$last_date")
            if [[ $(( $(now_epoch) - last_epoch )) -lt "$PUSH_COOLDOWN_SECS" ]]; then
                log "skip (recent own push, cooldown): $ref"
                new_state=$(jq -c --arg k "$key" --argjson s "$sig" --arg ref "$ref" --arg url "$url" --argjson cd "$cooldown" \
                    '.[$k] = ($s + {ref:$ref, url:$url, cooldownUntil:$cd})' <<<"$new_state")
                continue
            fi
        fi

        # ---- diff old vs new; collect reasons ----
        local -a reasons=()
        local cur_cr old_cr cur_ck old_ck cur_mg old_mg cur_fa old_fa cur_sha old_sha known
        cur_cr=$(jq -r '.reviewDecision' <<<"$sig");           old_cr=$(jq -r '.reviewDecision' <<<"$old")
        cur_ck=$(jq -r '.checks' <<<"$sig");                   old_ck=$(jq -r '.checks' <<<"$old")
        cur_mg=$(jq -r '.mergeable' <<<"$sig");                old_mg=$(jq -r '.mergeable' <<<"$old")
        cur_fa=$(jq -r '.lastForeignActivity' <<<"$sig");      old_fa=$(jq -r '.lastForeignActivity' <<<"$old")
        cur_sha=$(jq -r '.headSha' <<<"$sig");                 old_sha=$(jq -r '.headSha' <<<"$old")
        known=$(jq -r '.lastCommitKnownAuthors' <<<"$sig")

        # changes-requested (sticky)
        if [[ "$cur_cr" == "CHANGES_REQUESTED" ]]; then
            if [[ "$old_cr" != "CHANGES_REQUESTED" ]] || sticky_ready "$old" changes-requested; then
                reasons+=("changes-requested")
                cooldown=$(jq -c --arg r changes-requested --argjson t "$(( $(now_epoch) + STICKY_COOLDOWN_SECS ))" '. + {($r): $t}' <<<"$cooldown")
            fi
        fi
        # ci-red (sticky)
        if [[ "$cur_ck" == "FAILURE" ]]; then
            if [[ "$old_ck" != "FAILURE" ]] || sticky_ready "$old" ci-red; then
                reasons+=("ci-red")
                cooldown=$(jq -c --arg r ci-red --argjson t "$(( $(now_epoch) + STICKY_COOLDOWN_SECS ))" '. + {($r): $t}' <<<"$cooldown")
            fi
        fi
        # merge-conflict (sticky)
        if [[ "$cur_mg" == "CONFLICTING" ]]; then
            if [[ "$old_mg" != "CONFLICTING" ]] || sticky_ready "$old" merge-conflict; then
                reasons+=("merge-conflict")
                cooldown=$(jq -c --arg r merge-conflict --argjson t "$(( $(now_epoch) + STICKY_COOLDOWN_SECS ))" '. + {($r): $t}' <<<"$cooldown")
            fi
        fi
        # review-comment (edge): new foreign activity, unless already counted as changes-requested
        if [[ -n "$cur_fa" && "$cur_fa" > "$old_fa" ]]; then
            local has_cr=0; for r in "${reasons[@]:-}"; do [[ "$r" == "changes-requested" ]] && has_cr=1; done
            [[ "$has_cr" -eq 0 ]] && reasons+=("review-comment")
        fi
        # foreign-push (edge): head moved to a commit not authored by us
        if [[ "$cur_sha" != "$old_sha" && "$known" -gt 0 && "$mine" != "true" ]]; then
            reasons+=("foreign-push")
        fi

        # persist the advanced signature + refreshed cooldown regardless of fire
        new_state=$(jq -c --arg k "$key" --argjson s "$sig" --arg ref "$ref" --arg url "$url" --argjson cd "$cooldown" \
            '.[$k] = ($s + {ref:$ref, url:$url, cooldownUntil:$cd})' <<<"$new_state")

        if [[ ${#reasons[@]} -eq 0 ]]; then
            continue
        fi
        moved=$((moved + 1))
        local reason_str; reason_str=$(IFS=,; echo "${reasons[*]}")
        local msg="pr-move: $ref $reason_str $url"
        log "MOVED: $msg"
        nudges+=("$msg")
    done < <(jq -c '.[]' <<<"$prs")

    # stamp lastNudgedAt on the whole run and write state atomically
    local tmp; tmp=$(mktemp "${STATE_FILE}.XXXXXX") || { log "ERROR: mktemp failed"; return 1; }
    echo "$new_state" | jq '.' > "$tmp" && mv "$tmp" "$STATE_FILE"

    # deliver, capped per cycle
    local sent=0 i
    for i in "${!nudges[@]}"; do
        if [[ "$sent" -ge "$CYCLE_CAP" ]]; then
            local dropped=$(( ${#nudges[@]} - sent ))
            log "cycle cap $CYCLE_CAP reached; deferring $dropped nudge(s) to next cycle"
            break
        fi
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "[DRY-RUN] would send -> ${nudges[$i]}"
        else
            send_dm "${nudges[$i]}" | while read -r line; do log "  snd: $line"; done
        fi
        sent=$((sent + 1))
    done

    log "=== done: seen=$seen moved=$moved sent=$([[ $DRY_RUN -eq 1 ]] && echo 0 || echo $sent) (mode=$mode) ==="
}

# Serialize runs (manual invocation must not race the systemd one).
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "another pr-movement run holds the lock; exiting" >&2
    exit 0
fi
main "$@"
