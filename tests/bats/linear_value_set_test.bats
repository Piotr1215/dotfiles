#!/usr/bin/env bats

setup() {
    repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export FILE_SUGGESTION_TOML="$BATS_TEST_TMPDIR/file-suggestion.toml"
}

@test "linear value set runs the @lin query and types Claude's quoted token" {
    cat > "$FILE_SUGGESTION_TOML" <<'TOML'
[[prefixes]]
name = "task"
exec = "echo wrong-prefix"

[[prefixes]]
name = "lin"
exec = "printf '%s\\n' 'DEVOPS-2 second | issue' 'DEVOPS-1 first issue'"
TOML
    run "$repo_root/.config/value-sets/linear"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '@"DEVOPS-2 second | issue"\tDEVOPS-2 second | issue\n@"DEVOPS-1 first issue"\tDEVOPS-1 first issue')" ]
}

@test "linear value set fails loudly when the lin prefix is missing" {
    cat > "$FILE_SUGGESTION_TOML" <<'TOML'
[[prefixes]]
name = "task"
exec = "echo wrong-prefix"
TOML
    run "$repo_root/.config/value-sets/linear"
    [ "$status" -ne 0 ]
    [[ "$output" == *"lin"* ]]
}
