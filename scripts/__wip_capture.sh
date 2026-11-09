#!/usr/bin/env bash
# Restore with an intact worktree: rsync the mirror's .git/ back to the repo's .git/.
# If everything is lost: git clone <mirror .git> <destination>, then in that
# clone: git fetch <mirror .git> refs/wip/<branch>:refs/wip/<branch>
# git restore --source=refs/wip/<branch> --worktree -- .
# Or clone from GitHub, then run the same fetch and restore commands.
# One file: git --git-dir=<mirror .git> show refs/wip/<branch>:<path>
# Older snapshots: git --git-dir=<mirror .git> reflog refs/wip/<branch>
# Linked worktrees use refs/wip/worktrees/<worktree-name>/<branch>.
# Git clone fetches branch refs by default; fetch the refs/wip ref explicitly.
# bubblewrap makes live paths read-only even to configured Git filters.
set -eo pipefail
umask 077

# Keep inherited Git settings from redirecting commands into a live repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
export GIT_OPTIONAL_LOCKS=0
export GIT_TERMINAL_PROMPT=0
export LC_ALL=C

# The target is a mountpoint by default. The override is for isolated tests.
target=${WIP_CAPTURE_TARGET:-/mnt/nas-backup/git-mirror}
state=${WIP_CAPTURE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/wip-capture}
mount=${WIP_CAPTURE_MOUNT:-/mnt/nas-backup}
repo_timeout=${WIP_CAPTURE_REPO_TIMEOUT:-120}
# A repo with no good capture for this long raises the daily stale alert. The
# alert is a service-health line in the log that intake's events-monitor class
# shows to Kendra. Tests point the log elsewhere and fake the clock.
stale_after=${WIP_CAPTURE_STALE_AFTER:-86400}
notify_log=${WIP_CAPTURE_NOTIFY_LOG:-$HOME/.local/state/notifications.log}

# Refuse writable mirror or state paths that overlap a source repository.
paths_overlap() {
  local a b
  a=$(realpath -m -- "$1")
  b=$(realpath -m -- "$2")
  [[ $a == "$b" || $a == "$b/"* || $b == "$a/"* ]]
}

# Worktree fingerprint: what a wip snapshot records. Dirty file metadata is
# included because porcelain alone does not change when an already modified
# file is edited again.
fingerprint() {
  local repo=$1 gitdir=$2 tmp=$3 f
  git -c core.fsmonitor=false -C "$repo" status --porcelain=v2 -z --untracked-files=all > "$tmp/status"
  git -c core.fsmonitor=false -C "$repo" ls-files -z --modified --deleted --others --exclude-standard > "$tmp/paths"
  {
    cat "$tmp/status"
    git -C "$repo" rev-parse --verify -q HEAD || true
    if [[ -f $gitdir/index ]]; then sha256sum "$gitdir/index"; fi
    # One stat for all dirty paths: a fork per path cost minutes on repos with
    # thousands of untracked files. Missing paths print nothing.
    while IFS= read -r -d '' f; do printf '%s/%s\0' "$repo" "$f"; done < "$tmp/paths" |
      xargs -0 -r stat -c '%n %s %y %z' -- 2>/dev/null || true
  } | sha256sum | cut -d ' ' -f 1
}

# Common fingerprint: refs, logs and every worktree's HEAD in the shared Git
# directory. All worktrees of a repo share it, so one sync serves them all; a
# fetch or commit in one worktree no longer recaptures its 40 siblings.
common_fingerprint() {
  local common=$1 f
  {
    for f in "$common/HEAD" "$common/packed-refs"; do
      if [[ -e $f ]]; then stat -c '%n %s %y %z' -- "$f"; fi
    done
    for f in "$common/refs" "$common/logs"; do
      if [[ -d $f ]]; then find "$f" -printf '%p %s %T@ %C@\0'; fi
    done
    if [[ -d $common/worktrees ]]; then
      find "$common/worktrees" -mindepth 1 \( -path '*/logs/*' -o -name HEAD -o -name gitdir \) -printf '%p %s %T@ %C@\0'
    fi
  } | sha256sum | cut -d ' ' -f 1
}

# Copy alternate object stores into the mirror so it does not depend on live paths.
copy_objects() {
  local source=$1 dest=$2 alternate resolved
  local -a object_rsync=(-rlt --omit-dir-times --exclude=/info/alternates)
  source=$(realpath -e -- "$source")
  [[ -d $source ]] || return 1
  [[ -z ${object_sources[$source]+seen} ]] || return 0
  object_sources[$source]=1
  if [[ $source != "$primary_objects" ]]; then object_rsync+=(--exclude=/info/); fi
  rsync "${object_rsync[@]}" "$source/" "$dest/"
  if [[ -f $source/info/alternates ]]; then
    while IFS= read -r alternate || [[ -n $alternate ]]; do
      [[ -n $alternate ]] || continue
      if [[ $alternate == \"* ]]; then
        printf 'quoted alternate object path unsupported: %s\n' "$source" >&2; return 1
      fi
      if [[ $alternate == /* ]]; then resolved=$alternate; else resolved=$source/$alternate; fi
      copy_objects "$resolved" "$dest"
    done < "$source/info/alternates"
  fi
}

# Copy one common Git directory and write a snapshot using only a temporary index.
capture_one() {
  local repo=$1 gitdir common main_repo mirror mirror_git mirror_work_git name branch label stamp old_stamp common_stamp common_before work before after head tree commit msg f size
  local -A object_sources=()
  local primary_objects
  # Glob magic: **/ also matches the root, and git add -A exits 1 when a
  # non-glob exclude names a gitignored file.
  local -a excludes=( ':(exclude,glob)**/.env' ':(exclude,glob)**/.envrc' )
  repo=$(realpath -e -- "$repo")
  gitdir=$(git -C "$repo" rev-parse --absolute-git-dir)
  common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
  common=$(realpath -e -- "$common")
  if [[ ${common##*/} == .git ]]; then
    main_repo=${common%/.git}
  elif [[ $gitdir == "$common" ]]; then
    # Submodules have their Git directory under the parent repo's modules/.
    main_repo=$repo
  else
    printf 'unsupported common git directory: %s\n' "$common" >&2; return 1
  fi
  if paths_overlap "$repo" "$target" || paths_overlap "$common" "$target" ||
     paths_overlap "$repo" "$state" || paths_overlap "$common" "$state"; then
    printf 'source overlaps writable target or state: %s\n' "$repo" >&2; return 1
  fi
  case "$main_repo/" in "$HOME/"*) ;; *) printf 'repository outside HOME: %s\n' "$main_repo" >&2; return 1 ;; esac
  mirror="$target/${main_repo#"$HOME"/}"
  mirror_git="$mirror/.git"
  mirror_work_git=$mirror_git
  name=
  if [[ $gitdir != "$common" ]]; then
    case "$gitdir" in "$common"/worktrees/*) name=${gitdir#"$common"/worktrees/} ;; *) printf 'unsupported worktree gitdir: %s\n' "$gitdir" >&2; return 1 ;; esac
    [[ $name != */* ]] || return 1
    mirror_work_git="$mirror_git/worktrees/$name"
  fi
  branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD || true)
  if [[ -z $branch ]]; then branch="detached-$(git -C "$repo" rev-parse --verify HEAD)"; fi
  label=$branch
  if [[ -n $name ]]; then label="worktrees/$name/$branch"; fi
  git check-ref-format "refs/wip/$label" >/dev/null
  work=$(mktemp -d "$state/work.XXXXXXXX")
  cleanup_work=$work
  trap 'rm -rf -- "$cleanup_work"' EXIT
  before=$(fingerprint "$repo" "$gitdir" "$work")
  common_before=$(common_fingerprint "$common")
  stamp="$state/$(printf '%s\0%s' "$target" "$repo" | sha256sum | cut -d ' ' -f 1).stamp"
  common_stamp="$state/$(printf '%s\0%s' "$target" "$common" | sha256sum | cut -d ' ' -f 1).common.stamp"
  old_stamp=$(cat "$stamp" 2>/dev/null || true)
  if [[ $before == "$old_stamp" && $common_before == "$(cat "$common_stamp" 2>/dev/null)" && -d $mirror_work_git ]]; then
    printf 'skip %s\n' "$repo"
    return 0
  fi
  head=$(git -C "$repo" rev-parse --verify -q HEAD || true)
  # Worktrees of one repo share a mirror; parallel workers take turns on it.
  exec 8>"$state/$(printf '%s' "$mirror_git" | sha256sum | cut -d ' ' -f 1).mirror.lock"
  flock 8
  if [[ $common_before != "$(cat "$common_stamp" 2>/dev/null)" || ! -d $mirror_work_git ]] ||
     { [[ -n $head ]] && ! git --git-dir="$mirror_git" cat-file -e "$head^{commit}" 2>/dev/null; }; then
    mkdir -p "$mirror_git/objects"
    chmod 700 "$mirror_git"
    rsync -rltc --omit-dir-times --delete --exclude='/objects/' --exclude='/refs/wip/' --exclude='/logs/refs/wip/' --exclude='*.lock' "$common/" "$mirror_git/"
    primary_objects=$(realpath -e -- "$common/objects")
    copy_objects "$primary_objects" "$mirror_git/objects"
    rm -f -- "$mirror_git/objects/info/alternates"
    if [[ ${common##*/} != .git ]]; then
      # Its relative core.worktree points into the live parent, not this mirror.
      git config --file "$mirror_git/config" --unset-all core.worktree || [[ $? == 5 ]]
    fi
    [[ $common_before == "$(common_fingerprint "$common")" ]] || { printf 'repository changed during capture: %s\n' "$repo" >&2; return 1; }
    printf '%s\n' "$common_before" > "$work/common_stamp"
    mv -f -- "$work/common_stamp" "$common_stamp"
  fi
  [[ -d $mirror_work_git ]] || { printf 'missing mirrored worktree metadata: %s\n' "$repo" >&2; return 1; }
  if [[ $before == "$old_stamp" ]]; then
    printf 'synced %s (%s)\n' "$repo" "$label"
    return 0
  fi
  if [[ -f $gitdir/index ]]; then cp -- "$gitdir/index" "$work/index"; fi
  git -c core.fsmonitor=false -C "$repo" ls-files -z --others --exclude-standard > "$work/untracked"
  while IFS= read -r -d '' f; do
    if [[ -f $repo/$f && ! -L $repo/$f ]]; then
      size=$(stat -c %s -- "$repo/$f")
      if (( size > 50000000 )); then
        printf 'skip large untracked file: %s/%s (%s bytes)\n' "$repo" "$f" "$size" >&2
        excludes+=(":(exclude,literal)$f")
      fi
    fi
  done < "$work/untracked"
  export GIT_DIR=$mirror_work_git GIT_WORK_TREE=$repo GIT_INDEX_FILE=$work/index
  cd -- "$repo"
  git -c core.hooksPath=/dev/null -c core.fsmonitor=false add -A -- . "${excludes[@]}"
  tree=$(git write-tree)
  # HEAD comes from the live repo: the mirror's worktree HEAD is only as new
  # as the last common sync.
  msg="wip capture $(date -u +%Y-%m-%dT%H:%M:%SZ) $label"
  if [[ -n $head ]]; then
    commit=$(printf '%s\n' "$msg" | git -c user.name='WIP Capture' -c user.email='wip-capture@localhost' commit-tree "$tree" -p "$head")
  else
    commit=$(printf '%s\n' "$msg" | git -c user.name='WIP Capture' -c user.email='wip-capture@localhost' commit-tree "$tree")
  fi
  git -c core.logAllRefUpdates=always update-ref --create-reflog -m "$msg" "refs/wip/$label" "$commit"
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  after=$(fingerprint "$repo" "$gitdir" "$work")
  [[ $before == "$after" ]] || { printf 'repository changed during capture: %s\n' "$repo" >&2; return 1; }
  printf '%s\n' "$after" > "$work/stamp"
  mv -f -- "$work/stamp" "$stamp"
  printf 'captured %s (%s)\n' "$repo" "$label"
}

# Classify a failed capture from its stderr. Known repo-side breakage and
# races are warnings: cron would otherwise report the same checkouts every run.
known_reason() {
  local err=$1
  # A checkout too large to capture in time (a module cache in the worktree)
  # would otherwise fail every run; the stderr note names the timeout.
  if grep -q '^timed out after ' "$err"; then echo 'capture timed out (too many untracked files?)'
  elif grep -q 'repository changed during capture' "$err"; then echo 'changed during capture, retried next run'
  elif grep -q 'fatal: not a git repository' "$err"; then echo 'git directory missing (orphan worktree or submodule)'
  elif grep -q 'from promisor remote' "$err"; then echo 'partial clone needs network for missing objects'
  elif grep -q 'does not have a commit checked out' "$err"; then echo 'embedded repository without a checked out commit'
  else return 1
  fi
}

# "3d 2h" style age for the alert text.
fmt_age() {
  local s=$1
  if (( s >= 86400 )); then printf '%sd %sh' $((s/86400)) $((s%86400/3600))
  elif (( s >= 3600 )); then printf '%sh %sm' $((s/3600)) $((s%3600/60))
  else printf '%sm' $((s/60)); fi
}

# Read a two-column tsv (repo, epoch) into the associative array named $2.
load_times() {
  local file=$1 repo t
  local -n map=$2
  [[ -f $file ]] || return 0
  while IFS=$'\t' read -r repo t; do
    # shellcheck disable=SC2004,SC2034  # nameref into the caller's array
    if [[ -n $repo && $t =~ ^[0-9]+$ ]]; then map[$repo]=$t; fi
  done < "$file"
}

# Write the array named $2 as a two-column tsv, atomically.
save_times() {
  local file=$1 tmp repo
  local -n times=$2
  tmp=$(mktemp "$state/times.XXXXXXXX")
  for repo in "${!times[@]}"; do printf '%s\t%s\n' "$repo" "${times[$repo]}"; done | sort > "$tmp"
  mv -f -- "$tmp" "$file"
}

# Capture one repository in the sandbox and print one tab-separated result line.
run_one() {
  local repo=$1 out err rc=0 reason line
  out=$(mktemp "$state/out.XXXXXXXX")
  err=$(mktemp "$state/err.XXXXXXXX")
  timeout -k 5 "$repo_timeout" bwrap --die-with-parent --unshare-net --ro-bind / / --dev /dev --bind "$target" "$target" --bind "$state" "$state" --setenv TMPDIR "$state" --setenv WIP_CAPTURE_SANDBOXED 1 -- "$self" --capture-one "$repo" > "$out" 2> "$err" || rc=$?
  if (( rc == 0 )); then
    if grep -q '^captured ' "$out"; then line="captured"$'\t'"$repo"
    elif grep -q '^synced ' "$out"; then line="synced"$'\t'"$repo"
    else line="skip"$'\t'"$repo"; fi
    # Notes such as skipped large files still reach the log.
    grep -Ev '^(captured|synced|skip) ' "$out" >&2 || true
    grep '^skip large untracked file' "$err" >&2 || true
  elif { (( rc != 124 && rc != 137 )) || printf 'timed out after %ss: %s\n' "$repo_timeout" "$repo" >> "$err"; } &&
       reason=$(known_reason "$err"); then
    line="known"$'\t'"$repo"$'\t'"$reason"
  else
    { printf 'failed %s\n' "$repo"; cat -- "$err"; } >&2
    line="failed"$'\t'"$repo"
  fi
  rm -f -- "$out" "$err"
  printf '%s\n' "$line"
}

# Track the last good capture per repo and raise one alert a day while any repo
# with work to back up has had none for over stale_after seconds. Uses the
# arrays and $now of main (bash dynamic scope). A repo with no good capture on
# record counts from its first failure. Repos that are gone drop out of the
# state. Orphan worktrees and embedded repos without a commit have nothing to
# capture, so they never alert.
stale_check() {
  local repo reason since age today list='' n=0 shown=0 alerted_file="$state/stale-alerted"
  for repo in "${!new_good[@]}"; do good_at[$repo]=${new_good[$repo]}; done
  for repo in "${!bad[@]}"; do new_fail[$repo]=${fail_at[$repo]:-$now}; done
  # Keep the old good time of a failing repo; drop repos that are gone.
  for repo in "${!good_at[@]}"; do
    if [[ -z ${new_good[$repo]+set} && -z ${bad[$repo]+set} ]]; then unset "good_at[$repo]"; fi
  done
  while IFS= read -r repo; do
    [[ -n $repo ]] || continue
    reason=${bad[$repo]}
    case $reason in 'git directory missing'* | 'embedded repository without'*) continue ;; esac
    since=${good_at[$repo]:-${new_fail[$repo]}}
    age=$((now - since))
    (( age > stale_after )) || continue
    n=$((n+1))
    if (( shown < 5 )); then
      shown=$((shown+1))
      if [[ -n ${good_at[$repo]+set} ]]; then list+="${list:+; }$repo ($reason, last good capture $(fmt_age "$age") ago)"
      else list+="${list:+; }$repo ($reason, never captured, failing for $(fmt_age "$age"))"; fi
    fi
  done < <(printf '%s\n' "${!bad[@]}" | sort)
  save_times "$state/last-good.tsv" good_at
  save_times "$state/first-fail.tsv" new_fail
  (( n > 0 )) || return 0
  today=$(date -d "@$now" +%F)
  [[ $(cat "$alerted_file" 2>/dev/null || true) != "$today" ]] || return 0
  (( n <= shown )) || list+="; and $((n-shown)) more, see known-broken.tsv"
  if printf '%s\t%s\t%s\t%s\n' "$(date -d "@$now" '+%F %T')" service-health \
       "⚙ wip-capture: $n repos not backed up for over $((stale_after/3600))h" "$list" >> "$notify_log"; then
    printf '%s\n' "$today" > "$alerted_file"
    printf 'alert %s repos not backed up for over %sh\n' "$n" "$((stale_after/3600))"
  else
    printf 'could not write the stale alert to %s\n' "$notify_log" >&2
  fi
}

main() {
  if [[ ${1:-} == --capture-one && ${WIP_CAPTURE_SANDBOXED:-0} == 1 ]]; then
    shift
    capture_one "$1"
    return
  fi
  if [[ ${1:-} == --run-one && ${WIP_CAPTURE_PARENT:-0} == 1 ]]; then
    self=$0
    run_one "$2"
    return
  fi

  command -v bwrap >/dev/null || { printf 'bubblewrap is required to protect live repositories\n' >&2; return 1; }
  mkdir -p "$state"
  exec 9>"$state/capture.lock"
  flock -n 9 || { printf 'wip capture already running\n' >&2; return 1; }
  if [[ ${WIP_CAPTURE_ALLOW_DIRECTORY:-0} != 1 ]] && ! mountpoint -q -- "$mount"; then
    printf 'target mount is not mounted: %s\n' "$mount" >&2; return 1
  fi
  if [[ ${WIP_CAPTURE_ALLOW_DIRECTORY:-0} != 1 ]]; then
    case "$(realpath -m -- "$target")/" in "$(realpath -e -- "$mount")/"*) ;; *) printf 'target is outside mount: %s\n' "$target" >&2; return 1 ;; esac
  fi
  mkdir -p "$target"
  local probe="$target/.wip-probe-$$"
  if ! timeout -k 5 10 touch -- "$probe"; then
    printf 'target write probe failed: %s\n' "$target" >&2; return 1
  fi
  rm -f -- "$probe"
  local -a roots
  if (( $# )); then roots=("$@"); elif [[ -n ${WIP_CAPTURE_ROOTS:-} ]]; then IFS=: read -r -a roots <<< "$WIP_CAPTURE_ROOTS"; else roots=("$HOME/dev" "$HOME/loft" "$HOME/.claude" "$HOME/.codex"); fi
  # Workers run a private copy, so editing the script mid-run cannot change them.
  local list self_copy results root failed=0 kind repo reason count=0 skipped=0 synced=0 captured=0 known=0
  list=$(mktemp "$state/repos.XXXXXXXX")
  self_copy=$(mktemp "$state/self.XXXXXXXX")
  results=$(mktemp "$state/results.XXXXXXXX")
  cleanup_main=("$list" "$self_copy" "$results")
  trap 'rm -f -- "${cleanup_main[@]}"' EXIT
  cat -- "$0" > "$self_copy"
  chmod 700 "$self_copy"
  for root in "${roots[@]}"; do
    if [[ ! -e $root ]]; then continue; fi
    if ! find "$root" \( -type d \( -name node_modules -o -name vendor \) -prune \) -o \( -name .git \( -type d -o -type f \) -print0 -prune \) >> "$list"; then failed=$((failed+1)); fi
  done
  # Repos are independent; parallel workers hide per-repo git latency.
  sed -z 's#/\.git$##' "$list" |
    WIP_CAPTURE_PARENT=1 xargs -0 -r -n 1 -P "${WIP_CAPTURE_JOBS:-4}" "$self_copy" --run-one > "$results" || true
  local known_file="$state/known-broken.tsv" known_new
  local -A good_at=() fail_at=() bad=() new_good=() new_fail=()
  local now
  now=${WIP_CAPTURE_NOW:-$(date +%s)}
  load_times "$state/last-good.tsv" good_at
  load_times "$state/first-fail.tsv" fail_at
  known_new=$(mktemp "$state/known.XXXXXXXX")
  while IFS=$'\t' read -r kind repo reason; do
    count=$((count+1))
    case $kind in
      captured) captured=$((captured+1)); new_good[$repo]=$now; printf 'captured %s\n' "$repo" ;;
      synced) synced=$((synced+1)); new_good[$repo]=$now; [[ ${WIP_CAPTURE_VERBOSE:-0} != 1 ]] || printf 'synced %s\n' "$repo" ;;
      skip) skipped=$((skipped+1)); new_good[$repo]=$now; [[ ${WIP_CAPTURE_VERBOSE:-0} != 1 ]] || printf 'skip %s\n' "$repo" ;;
      known)
        known=$((known+1))
        bad[$repo]=$reason
        printf '%s\t%s\n' "$repo" "$reason" >> "$known_new"
        # Warn once per repo and reason; repeats stay out of the cron log.
        if ! grep -qxF -- "$repo"$'\t'"$reason" "$known_file" 2>/dev/null; then printf 'warning %s: %s\n' "$repo" "$reason"; fi ;;
      *) failed=$((failed+1)); bad[$repo]='capture failed' ;;
    esac
  done < "$results"
  mv -f -- "$known_new" "$known_file"
  stale_check
  printf 'summary repositories=%s captured=%s synced=%s skipped=%s known_broken=%s failures=%s\n' "$count" "$captured" "$synced" "$skipped" "$known" "$failed"
  (( failed == 0 ))
}

# One line: bash has read all of it before main runs, so a mid-run edit cannot
# be read as the rest of this script.
main "$@"; exit $?
