#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/fixture"
  export BACKUP_COVERAGE_SOURCE="$BATS_TEST_TMPDIR/fixture/backup.sh"
  export BACKUP_COVERAGE_PATTERNS="$HOME/.backup_patterns"
  export BACKUP_COVERAGE_MANIFEST="$BATS_TEST_TMPDIR/fixture/manifest"
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__backup_coverage.sh"
  cat > "$BACKUP_COVERAGE_SOURCE" <<'SOURCE'
declare -a RESTIC_SOURCES=(
  "$HOME/restic"
  "$HOME/partial/file"
)
SOURCE
  printf '+ /mirror/\n- /*\n' > "$BACKUP_COVERAGE_PATTERNS"
  printf '.backup_patterns\tskip\tfixture configuration\n' > "$BACKUP_COVERAGE_MANIFEST"
}

@test "restic and mirror coverage, with mirror history warning" {
  mkdir "$HOME/restic" "$HOME/mirror"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'restic: restic'* ]]
  [[ "$output" == *'mirror: mirror (mirror only: no history)'* ]]
}

@test "manifest skip and unknown are reported" {
  touch "$HOME/cache" "$HOME/mystery"
  printf 'cache\tskip\trebuildable cache\nmystery\tunknown\tunreviewed file\n' >> "$BACKUP_COVERAGE_MANIFEST"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'cache: no layer; skip: rebuildable cache'* ]]
  [[ "$output" == *'mystery: no layer; unknown: unreviewed file'* ]]
}

@test "uncovered and stale entries are printed first and return 2" {
  touch "$HOME/new"
  printf 'old\tskip\tno longer here\n' >> "$BACKUP_COVERAGE_MANIFEST"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [ "${lines[0]}" = 'UNCOVERED: new' ]
  [ "${lines[1]}" = 'STALE: old' ]
}

@test "symlink and its target are visible in text and JSON" {
  ln -s missing-target "$HOME/link"
  printf 'link\tunknown\tbroken link\n' >> "$BACKUP_COVERAGE_MANIFEST"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'link -> missing-target: no layer; unknown: broken link'* ]]
  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys; x=json.load(sys.stdin); e=next(e for e in x["entries"] if e["name"] == "link"); assert e["type"] == "link" and e["target"] == "missing-target"'
}

@test "nested restic source does not cover entire top-level directory" {
  mkdir -p "$HOME/partial"
  touch "$HOME/partial/file"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'UNCOVERED: partial'* ]]
  [[ "$output" == *'partial: restic (partial)'* ]]
}

@test "root gitignore can exclude a pattern included by mirror" {
  mkdir "$HOME/mirror"
  printf 'mirror/\n' > "$HOME/.gitignore"
  printf '.gitignore\tunknown\tfixture ignore\n' >> "$BACKUP_COVERAGE_MANIFEST"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'UNCOVERED: mirror'* ]]
}

@test "malformed manifest fails closed" {
  printf 'oops\n' >> "$BACKUP_COVERAGE_MANIFEST"
  run "$SCRIPT" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'invalid manifest line'* ]]
}

@test "git remote is reported as partial and cannot hide an uncovered repo" {
  mkdir "$HOME/repo"
  git -C "$HOME/repo" init -q
  git -C "$HOME/repo" remote add origin https://example.invalid/repo.git
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'UNCOVERED: repo'* ]]
  [[ "$output" == *'repo: github-only (pushed commits only)'* ]]
}

# Add the proposed home run without running restic.
enable_home_run() {
  cat >> "$BACKUP_COVERAGE_SOURCE" <<'SOURCE'
BACKUP_SOURCE_HOME="$BACKUP_SOURCE_HOME" restic backup --tag home --exclude-larger-than 1G \
    --exclude-file "$BACKUP_SOURCE_HOME/.backup_restic_excludes" "$BACKUP_SOURCE_HOME/" || record_failure "restic home"
SOURCE
  : > "$HOME/.backup_restic_excludes"
}

@test "home run covers new entries and preserves other layers" {
  enable_home_run
  mkdir "$HOME/restic" "$HOME/mirror"
  touch "$HOME/new"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'new: restic (home)'* ]]
  [[ "$output" == *'restic: restic, restic (home)'* ]]
  [[ "$output" == *'mirror: restic (home), mirror'* ]]
}

@test "home exclusions show nearest reason and keep other layers" {
  enable_home_run
  mkdir "$HOME/restic" "$HOME/mirror"
  cat > "$HOME/.backup_restic_excludes" <<'EXCLUDES'
# first reason
${BACKUP_SOURCE_HOME}/restic
# other reason
${BACKUP_SOURCE_HOME}/mirror
EXCLUDES
  run "$SCRIPT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys; e={v["name"]:v for v in json.load(sys.stdin)["entries"]}; assert e["restic"]["layers"] == ["restic"] and e["restic"]["home_exclusion"] == "first reason"; assert e["mirror"]["layers"] == ["mirror"] and e["mirror"]["home_exclusion"] == "other reason"'
}

@test "nested exclusions leave the top level covered" {
  enable_home_run
  mkdir -p "$HOME/.kube/cache"
  cat > "$HOME/.backup_restic_excludes" <<'EXCLUDES'
# cache, rebuilt on use
${BACKUP_SOURCE_HOME}/.kube/cache
**/node_modules
EXCLUDES
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'.kube: restic (home); home excludes cache: cache, rebuilt on use'* ]]
  [[ "$output" != *'node_modules'* ]]
}

@test "glob excludes match entries without becoming stale" {
  enable_home_run
  touch "$HOME/.zcompdump" "$HOME/.zcompdump-host"
  cat > "$HOME/.backup_restic_excludes" <<'EXCLUDES'
# generated cache
${BACKUP_SOURCE_HOME}/.zcompdump*
${BACKUP_SOURCE_HOME}/absent*
EXCLUDES
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'.zcompdump: no layer; home excluded: generated cache'* ]]
  [[ "$output" == *'.zcompdump-host: no layer; home excluded: generated cache'* ]]
}

@test "stale anchored exclusions are printed first and return 2" {
  enable_home_run
  printf '# old cache\n${BACKUP_SOURCE_HOME}/gone\n' > "$HOME/.backup_restic_excludes"
  touch "$HOME/new"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [ "${lines[0]}" = 'STALE EXCLUDE: gone' ]
  [[ "$output" == *'new: restic (home)'* ]]
}

@test "missing home exclude file is printed first and returns 2" {
  enable_home_run
  rm "$HOME/.backup_restic_excludes"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [ "${lines[0]}" = "MISSING EXCLUDE FILE: $HOME/.backup_restic_excludes" ]
  run "$SCRIPT" --json
  [ "$status" -eq 2 ]
  printf '%s' "$output" | python3 -c 'import json,sys; assert json.load(sys.stdin)["exclude_errors"][0].startswith("MISSING EXCLUDE FILE:")'
}

@test "exclude file alone and commented home run do not change old behavior" {
  touch "$HOME/new" "$HOME/.backup_restic_excludes"
  printf '.backup_restic_excludes\tskip\tfixture\n' >> "$BACKUP_COVERAGE_MANIFEST"
  cat >> "$BACKUP_COVERAGE_SOURCE" <<'SOURCE'
# restic backup --tag home --exclude-file "$BACKUP_SOURCE_HOME/.backup_restic_excludes" "$BACKUP_SOURCE_HOME/"
SOURCE
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [ "${lines[0]}" = 'UNCOVERED: new' ]
  [[ "$output" == *'new: no layer'* ]]
  [[ "$output" != *'restic (home)'* ]]
}
