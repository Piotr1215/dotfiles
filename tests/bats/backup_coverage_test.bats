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
