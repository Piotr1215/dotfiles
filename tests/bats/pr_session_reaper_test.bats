#!/usr/bin/env bats

# __pr_session_reaper.sh runs git worktree remove --force once every PR for a
# worker is merged. It guarded only against uncommitted edits, so a commit made
# after the last push lived in the worktree alone and the reaper would have
# deleted it. has_unpushed_commits is the guard; these tests pin its contract.

setup() {
  REAPER="${BATS_TEST_DIRNAME}/../../scripts/__pr_session_reaper.sh"
  WORK="$(mktemp -d)"
  export HOME="${WORK}/home"
  mkdir -p "$HOME"
  export GIT_CONFIG_GLOBAL="${WORK}/gitconfig"
  git config --global user.email t@example.com
  git config --global user.name test
  git config --global init.defaultBranch trunk

  git init -q --bare "${WORK}/origin.git"
  git clone -q "${WORK}/origin.git" "${WORK}/repo" 2>/dev/null
  git -C "${WORK}/repo" commit -q --allow-empty -m base
  git -C "${WORK}/repo" push -q origin trunk
  git -C "${WORK}/repo" worktree add -q -b feature "${WORK}/wt"
  WT="${WORK}/wt"

  # shellcheck source=/dev/null
  source "$REAPER"
}

teardown() {
  rm -rf "$WORK"
}

@test "pushed worktree has no unpushed commits" {
  git -C "$WT" commit -q --allow-empty -m work
  git -C "$WT" push -q origin feature
  run has_unpushed_commits "$WT"
  [ "$status" -eq 1 ]
}

@test "local commit never pushed blocks the reap" {
  git -C "$WT" commit -q --allow-empty -m work
  run has_unpushed_commits "$WT"
  [ "$status" -eq 0 ]
}

@test "commit after the merged PR head blocks the reap" {
  git -C "$WT" commit -q --allow-empty -m work
  git -C "$WT" push -q origin feature
  head=$(git -C "$WT" rev-parse HEAD)
  git -C "$WT" commit -q --allow-empty -m "after merge"
  run has_unpushed_commits "$WT" "$head"
  [ "$status" -eq 0 ]
}

@test "PR head covers commits whose remote branch was pruned" {
  git -C "$WT" commit -q --allow-empty -m work
  git -C "$WT" push -q origin feature
  head=$(git -C "$WT" rev-parse HEAD)
  git -C "$WT" push -q origin --delete feature
  git -C "$WT" fetch -q --prune
  run has_unpushed_commits "$WT" "$head"
  [ "$status" -eq 1 ]
}

@test "unknown PR head is ignored, not trusted" {
  git -C "$WT" commit -q --allow-empty -m work
  run has_unpushed_commits "$WT" 0123456789abcdef0123456789abcdef01234567
  [ "$status" -eq 0 ]
}

@test "path outside git has nothing to lose" {
  mkdir "${WORK}/plain"
  run has_unpushed_commits "${WORK}/plain"
  [ "$status" -eq 1 ]
}

@test "sourcing the script does not run the reaper" {
  run bash -c "source '$REAPER'; echo sourced"
  [ "$status" -eq 0 ]
  [ "$output" = "sourced" ]
}
