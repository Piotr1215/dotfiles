#!/usr/bin/env bats

@test "task value set ignores context and preserves labels and order" {
    repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/task" <<'STUB'
#!/usr/bin/env bash
[[ "$*" == 'rc.context=none status:pending export' ]] || exit 1
printf '%s\n' '[{"uuid":"one","description":"private task","tags":["private"]},{"uuid":"two","linear_issue_id":"D-2","repo":"repo","description":"work | task"}]'
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/task"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    run "$repo_root/.config/value-sets/task"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '@"one|-|-|private task"\tprivate task\n@"two|D-2|repo|work | task"\twork | task   D-2   repo')" ]
}
