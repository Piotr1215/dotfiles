#!/usr/bin/env bash
# PROJECT: git-housekeeping
# Manage git worktrees and orphan branches in the current repo.
#
# Usage:
#   __git_manage_worktrees.sh list    show worktrees + orphan branches in sections
#   __git_manage_worktrees.sh prune   interactively delete anything with a gone
#                                     upstream (worktrees + orphan branches)
#   __git_manage_worktrees.sh sync    fast-forward pull every worktree
#
# Scoped to the current repo (git's own commands are scoped to cwd's gitdir).
set -eo pipefail

cmd="${1:-list}"

case "$cmd" in
    -h|--help)
        sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    list|prune|sync) ;;
    *)
        echo "unknown command: $cmd" >&2
        echo "usage: $0 {list|prune|sync}" >&2
        exit 2
        ;;
esac

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "not inside a git repo" >&2
    exit 1
fi

# True when $1 is the repository's MAIN (primary) worktree — the original clone
# that must never be deleted. Identified authoritatively: the main worktree's
# git dir IS the common git dir, whereas a linked worktree's git dir lives under
# <common>/worktrees/<name>. This compares resolved git dirs, not path strings,
# so symlinks and trailing slashes cannot fool it.
#
# git already refuses `git worktree remove` on the main worktree, but this
# script used to fall back to `rm -rf`, which once wiped the loft-prod main
# clone. Every removal path is gated on this check so that can never recur.
is_main_worktree() {
    local wt="$1" git_dir common_dir
    git_dir=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null) || return 1
    common_dir=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
    [[ "$git_dir" == "$common_dir" ]]
}

# Refresh remote-tracking refs so deleted branches are reflected locally.
refresh_remotes() {
    git fetch --all --prune --quiet 2>&1 || \
        echo "warn: fetch --prune failed; results may be stale" >&2
}

# Classify a worktree by its upstream state.
# Echoes one of: GONE | UNPUSHED | NO_UPSTREAM | OK | DETACHED
classify_worktree() {
    local branch_ref="$1"
    if [[ "$branch_ref" == "DETACHED" ]]; then
        echo "DETACHED"; return
    fi
    local branch="${branch_ref#refs/heads/}"
    local matched="" remote
    while IFS= read -r remote; do
        [[ -z "$remote" ]] && continue
        if git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
            matched="$remote/$branch"; break
        fi
    done < <(git remote)
    if [[ -n "$matched" ]]; then
        echo "OK"; return
    fi
    local upstream
    upstream=$(git for-each-ref --format='%(upstream:short)' "$branch_ref" 2>/dev/null)
    if [[ -z "$upstream" ]]; then
        echo "NO_UPSTREAM"; return
    fi
    if ! git show-ref --verify --quiet "refs/remotes/$upstream"; then
        echo "GONE"; return
    fi
    echo "UNPUSHED"
}

# Emit "path\tbranch_ref" rows for every worktree (DETACHED for headless).
enumerate_worktrees() {
    git worktree list --porcelain | awk '
        /^worktree / { wt=$2 }
        /^branch /   { print wt"\t"$2 }
        /^detached/  { print wt"\tDETACHED" }
    '
}

# Pretty-print one worktree row.
print_row() {
    printf "  %-95s  %s\n" "$1" "${2} → ${3:-<none>}"
}

# Populate the global state arrays.
declare -ga gone=() no_upstream=() unpushed=() ok=() detached=() gone_branches=()
scan_all() {
    gone=(); no_upstream=(); unpushed=(); ok=(); detached=(); gone_branches=()

    while IFS=$'\t' read -r wt branch_ref; do
        local state branch upstream
        state=$(classify_worktree "$branch_ref")
        branch="${branch_ref#refs/heads/}"
        [[ "$branch_ref" == "DETACHED" ]] && branch=""
        upstream=$(git for-each-ref --format='%(upstream:short)' "$branch_ref" 2>/dev/null || true)
        local row="${wt}|${branch}|${upstream}"
        case "$state" in
            GONE)        gone+=("$row") ;;
            NO_UPSTREAM) no_upstream+=("$row") ;;
            UNPUSHED)    unpushed+=("$row") ;;
            OK)          ok+=("$row") ;;
            DETACHED)    detached+=("$row") ;;
        esac
    done < <(enumerate_worktrees)

    # Dangling branches: local branches with no attached worktree, where one
    # of the following is true:
    #   1. Their configured upstream ref no longer exists (PR merged, branch
    #      deleted on remote).
    #   2. Their name matches the agent timestamp pattern `*/YYYYMMDD-HHMMSS`
    #      and they have no remote sibling — these are throwaway branches.
    # Meaningful branches that were never pushed (dependabot/*, feature names,
    # one-off experiments) are left alone — they belong to humans.
    local wt_branches
    wt_branches=$(git worktree list --porcelain | awk '/^branch / { sub("refs/heads/","",$2); print $2 }')
    local remotes
    remotes=$(git remote)
    while IFS='|' read -r br up_short up_full; do
        [[ -z "$br" ]] && continue
        # Skip if checked out by some worktree.
        if [[ -n "$wt_branches" ]] && grep -qFx "$br" <<< "$wt_branches"; then
            continue
        fi
        # Rule 1: upstream config points to a now-missing ref.
        local is_gone="false"
        if [[ -n "$up_full" ]] && ! git show-ref --verify --quiet "$up_full"; then
            is_gone="true"
        fi
        # Rule 2: timestamp pattern AND no remote sibling.
        local is_timestamp="false"
        if [[ "$br" =~ /[0-9]{8}-[0-9]{6}$ ]]; then
            local has_remote_sibling="false" remote
            while IFS= read -r remote; do
                [[ -z "$remote" ]] && continue
                if git show-ref --verify --quiet "refs/remotes/$remote/$br"; then
                    has_remote_sibling="true"; break
                fi
            done <<< "$remotes"
            [[ "$has_remote_sibling" == "false" ]] && is_timestamp="true"
        fi
        if [[ "$is_gone" == "true" || "$is_timestamp" == "true" ]]; then
            gone_branches+=("${br}|${up_short:-<none>}")
        fi
    done < <(git for-each-ref --format='%(refname:short)|%(upstream:short)|%(upstream)' refs/heads/)
}

# ---------------- list ----------------

cmd_list() {
    scan_all
    echo
    echo "=== UPSTREAM GONE — worktrees (${#gone[@]}) ==="
    local row
    for row in "${gone[@]}"; do
        IFS='|' read -r wt branch upstream <<< "$row"
        print_row "$wt" "$branch" "$upstream"
    done

    echo
    echo "=== DANGLING BRANCHES — no worktree, no remote sibling (${#gone_branches[@]}) ==="
    for row in "${gone_branches[@]}"; do
        IFS='|' read -r br up <<< "$row"
        printf "  %-95s  %s\n" "$br" "→ $up"
    done

    echo
    echo "=== UNPUSHED — branch never pushed (${#unpushed[@]}) ==="
    for row in "${unpushed[@]}"; do
        IFS='|' read -r wt branch upstream <<< "$row"
        print_row "$wt" "$branch" "$upstream"
    done

    echo
    echo "=== NO UPSTREAM (${#no_upstream[@]}) ==="
    for row in "${no_upstream[@]}"; do
        IFS='|' read -r wt branch upstream <<< "$row"
        print_row "$wt" "$branch" "$upstream"
    done

    echo
    echo "=== DETACHED HEAD (${#detached[@]}) ==="
    for row in "${detached[@]}"; do
        IFS='|' read -r wt _ _ <<< "$row"
        printf "  %s\n" "$wt"
    done

    echo
    echo "=== HEALTHY (${#ok[@]}) ==="
    for row in "${ok[@]}"; do
        IFS='|' read -r wt branch upstream <<< "$row"
        print_row "$wt" "$branch" "$upstream"
    done
    echo
}

# ---------------- prune ----------------

# Ask y/n/a/q. Sets global REPLY_CHOICE.
# Args: $1=idx, $2=total, $3=kind(WT|BR), $4=wt, $5=branch, $6=upstream
REPLY_CHOICE=""
prompt_one() {
    local idx="$1" total="$2" kind="$3" wt="$4" branch="$5" upstream="$6"
    local header
    if [[ "$kind" == "WT" ]]; then
        header="[$idx/$total] (worktree) $wt"
    else
        header="[$idx/$total] (branch)   $branch"
    fi
    while true; do
        printf "%s\n        branch:   %s → %s\n        prune? [y]es [n]o [a]ll [q]uit: " \
            "$header" "$branch" "$upstream" >&2
        local ans=""
        if ! read -r ans </dev/tty; then
            REPLY_CHOICE="q"; echo >&2; return
        fi
        case "$ans" in
            y|Y|yes)  REPLY_CHOICE="y"; return ;;
            n|N|no)   REPLY_CHOICE="n"; return ;;
            a|A|all)  REPLY_CHOICE="a"; return ;;
            q|Q|quit) REPLY_CHOICE="q"; return ;;
            *)        echo "  (please answer y, n, a, or q)" >&2 ;;
        esac
    done
}

# Remove a worktree: force-remove, also delete the local branch.
remove_worktree_entry() {
    local wt="$1" branch="$2"
    # HARD GUARD: never remove the repository's main worktree. git refuses to
    # `worktree remove` it, and the rm -rf fallback below would otherwise wipe
    # the real checkout. This is the line that once nuked the loft-prod clone.
    if is_main_worktree "$wt"; then
        echo "REFUSING to remove main worktree: $wt" >&2
        return
    fi
    if git worktree remove --force "$wt" 2>/dev/null; then
        echo "removed worktree: $wt"
    else
        rm -rf "$wt" 2>/dev/null || true
        git worktree prune >/dev/null 2>&1 || true
        if [[ -d "$wt" ]]; then
            echo "failed to remove worktree: $wt" >&2
            return
        fi
        echo "removed worktree: $wt (admin entry cleaned)"
    fi
    if [[ -n "$branch" ]] && git show-ref --verify --quiet "refs/heads/$branch"; then
        git branch -D "$branch" >/dev/null 2>&1 && \
            echo "  deleted branch: $branch"
    fi
}

cmd_prune() {
    scan_all

    local candidates=()
    local row
    for row in "${gone[@]}"; do
        IFS='|' read -r wt _ _ <<< "$row"
        is_main_worktree "$wt" && continue
        candidates+=("WT|$row")
    done
    # Unpushed worktrees with no local commits ahead of their upstream are
    # safe: nothing was ever committed, only working-tree noise. Working-tree
    # state is discarded by `git worktree remove --force` — no loss of commits.
    for row in "${unpushed[@]}"; do
        IFS='|' read -r wt branch upstream <<< "$row"
        is_main_worktree "$wt" && continue
        local ahead
        ahead=$(git -C "$wt" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo "?")
        if [[ "$ahead" == "0" ]]; then
            candidates+=("WT|$row")
        fi
    done
    for row in "${gone_branches[@]}"; do
        IFS='|' read -r br up <<< "$row"
        candidates+=("BR||$br|$up")
    done

    if [[ ${#candidates[@]} -eq 0 ]]; then
        echo "nothing to prune — no upstream-gone worktrees or branches"
        return
    fi

    # Count by kind for the summary line.
    local wt_total=0 br_total=0
    for row in "${candidates[@]}"; do
        IFS='|' read -r kind _ _ _ <<< "$row"
        [[ "$kind" == "WT" ]] && wt_total=$((wt_total + 1))
        [[ "$kind" == "BR" ]] && br_total=$((br_total + 1))
    done

    local repo_top
    repo_top=$(git rev-parse --show-toplevel 2>/dev/null || echo "?")
    echo "Repo: $repo_top"
    echo "Found ${#candidates[@]} prune candidate(s): ${wt_total} worktree(s), ${br_total} branch(es)."
    local i=0
    for row in "${candidates[@]}"; do
        i=$((i + 1))
        IFS='|' read -r kind wt branch upstream <<< "$row"
        if [[ "$kind" == "WT" ]]; then
            printf "  %d. (worktree) %s\n        branch: %s → %s\n" "$i" "$wt" "$branch" "$upstream"
        else
            printf "  %d. (branch)   %s → %s\n" "$i" "$branch" "$upstream"
        fi
    done
    echo

    local selected=()
    local accept_all="false"
    local total=${#candidates[@]}
    i=0
    for row in "${candidates[@]}"; do
        i=$((i + 1))
        IFS='|' read -r kind wt branch upstream <<< "$row"
        if [[ "$accept_all" == "true" ]]; then
            selected+=("$row"); continue
        fi
        prompt_one "$i" "$total" "$kind" "$wt" "$branch" "$upstream"
        case "$REPLY_CHOICE" in
            y) selected+=("$row") ;;
            n) ;;
            a) selected+=("$row"); accept_all="true" ;;
            q) echo "aborted by user" >&2; return ;;
        esac
    done

    if [[ ${#selected[@]} -eq 0 ]]; then
        echo "nothing selected"
        return
    fi

    echo
    echo "pruning ${#selected[@]} item(s)..."
    for row in "${selected[@]}"; do
        IFS='|' read -r kind wt branch _ <<< "$row"
        if [[ "$kind" == "WT" ]]; then
            remove_worktree_entry "$wt" "$branch"
        else
            if git branch -D "$branch" >/dev/null 2>&1; then
                echo "deleted branch: $branch"
            else
                echo "failed to delete branch: $branch" >&2
            fi
        fi
    done
    git worktree prune
}

# ---------------- sync ----------------

# Fast-forward a single worktree from its upstream ref. Lets git decide whether
# the merge is safe; only refuses when tracked changes would actually conflict.
sync_one() {
    local wt="$1" branch="$2" upstream="$3"
    if [[ ! -d "$wt" ]]; then
        echo "skip (missing): $wt" >&2; return
    fi

    local local_sha upstream_sha
    local_sha=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
    upstream_sha=$(git -C "$wt" rev-parse "refs/remotes/$upstream" 2>/dev/null)
    if [[ "$local_sha" == "$upstream_sha" ]]; then
        echo "up-to-date: $wt ($branch)"; return
    fi
    if ! git -C "$wt" merge-base --is-ancestor "$local_sha" "$upstream_sha" 2>/dev/null; then
        local counts ahead behind
        counts=$(git -C "$wt" rev-list --left-right --count "$local_sha...$upstream_sha" 2>/dev/null)
        ahead=$(awk '{print $1}' <<< "$counts")
        behind=$(awk '{print $2}' <<< "$counts")
        echo "skip (diverged, ↑${ahead} ↓${behind}): $wt ($branch)" >&2
        return
    fi

    local err rc
    err=$(git -C "$wt" merge --ff-only "refs/remotes/$upstream" 2>&1)
    rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "synced: $wt ($branch ← $upstream)"
    else
        local reason
        reason=$(grep -E 'would be overwritten|Your local changes|cannot pull|refusing' <<< "$err" | head -1)
        [[ -z "$reason" ]] && reason="$(head -1 <<< "$err")"
        echo "skip (merge refused: ${reason}): $wt ($branch)" >&2
    fi
}

cmd_sync() {
    scan_all
    local candidates=("${ok[@]}" "${unpushed[@]}")
    if [[ ${#candidates[@]} -eq 0 ]]; then
        echo "nothing to sync"
        return
    fi
    echo "syncing ${#candidates[@]} worktree(s)..."
    local row
    for row in "${candidates[@]}"; do
        IFS='|' read -r wt branch upstream <<< "$row"
        sync_one "$wt" "$branch" "$upstream"
    done
}

# ---------------- main ----------------

# Skip the dispatch when sourced (e.g. by tests) so functions can be exercised
# in isolation without touching remotes or the working tree.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    refresh_remotes

    case "$cmd" in
        list)  cmd_list ;;
        prune) cmd_prune ;;
        sync)  cmd_sync ;;
    esac
fi
