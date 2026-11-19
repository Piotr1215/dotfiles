#!/usr/bin/env bats

setup() {
    sets="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/.config/value-sets"
}

@test "env value set lists VAR=value rows, sorted, with the value typed whole" {
    run env -i PATH="$PATH" ZED='a | b' ALPHA=1 "$sets/env"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -qxF "$(printf 'ALPHA=1\tALPHA=1')"
    printf '%s\n' "$output" | grep -qxF "$(printf 'ZED=a | b\tZED=a | b')"
    [ "$(printf '%s\n' "$output" | cut -f1 | LC_ALL=C sort)" = "$(printf '%s\n' "$output" | cut -f1)" ]
}

@test "env value set skips multi-line values" {
    run env -i PATH="$PATH" MULTI="$(printf 'one\ntwo')" SINGLE=ok "$sets/env"
    [ "$status" -eq 0 ]
    ! printf '%s\n' "$output" | grep -q 'MULTI\|^two'
    printf '%s\n' "$output" | grep -qxF "$(printf 'SINGLE=ok\tSINGLE=ok')"
}

make_tree() {
    root="$BATS_TEST_TMPDIR/root"
    mkdir -p "$root/a/b/c" "$root/.hidden" "$root/node_modules" "$root/.git"
    touch "$root/top.sh" "$root/a/b/deep.md" "$root/a/b/c/deeper.md" \
        "$root/.hidden/conf" "$root/node_modules/skip.js" "$root/.git/HEAD"
}

@test "dot value set shows paths inside the repo, types absolute ones, includes hidden files" {
    make_tree
    VALUE_SET_ROOT="$root" run "$sets/dot"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\t%s\n' \
        "$root/.hidden/conf" .hidden/conf \
        "$root/a/b/c/deeper.md" a/b/c/deeper.md \
        "$root/a/b/deep.md" a/b/deep.md \
        "$root/top.sh" top.sh)" ]
}

@test "loft value set stops at depth 3 and skips hidden files" {
    make_tree
    VALUE_SET_ROOT="$root" run "$sets/loft"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\t%s\n' \
        "$root/a/b/deep.md" a/b/deep.md \
        "$root/top.sh" top.sh)" ]
}

@test "obs value set reaches depth 5 and skips hidden files" {
    make_tree
    mkdir -p "$root/1/2/3/4/5"
    touch "$root/1/2/3/4/five.md" "$root/1/2/3/4/5/six.md"
    VALUE_SET_ROOT="$root" run "$sets/obs"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\t%s\n' \
        "$root/1/2/3/4/five.md" 1/2/3/4/five.md \
        "$root/a/b/c/deeper.md" a/b/c/deeper.md \
        "$root/a/b/deep.md" a/b/deep.md \
        "$root/top.sh" top.sh)" ]
}
