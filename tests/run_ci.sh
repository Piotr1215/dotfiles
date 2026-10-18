#!/usr/bin/env bash
# Runs one test suite the way CI does: every test file in the suite except the
# ones listed in tests/ci_skip.txt. Exits non-zero when any file fails.
# Usage: tests/run_ci.sh bats|shell|python
set -eo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skip_file="$repo_root/tests/ci_skip.txt"

# Prints the skipped paths, one per line, with comments and reasons stripped.
skipped_paths() {
    [ -f "$skip_file" ] || return 0
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$skip_file" | grep -v '^$' || true
}

# Lists the test files of a suite, relative to the repo root.
suite_files() {
    case "$1" in
        bats) printf '%s\n' tests/bats/*.bats ;;
        shell) printf '%s\n' tests/shell/*_test.sh ;;
        python) printf '%s\n' tests/python/test_*.py tests/python/*_test.py ;;
    esac
}

# Runs one test file with the runner its suite and shebang call for.
# test_*.py files are pytest modules; *_test.py files are plain scripts.
run_file() {
    local file="$1" interp
    case "$file" in
        *.bats) bats "$file" ;;
        tests/shell/*)
            interp=bash
            head -1 "$file" | grep -q zsh && interp=zsh
            (cd tests/shell && "$interp" "$(basename "$file")") ;;
        tests/python/test_*) python3 -m pytest -q -p no:cacheprovider "$file" ;;
        tests/python/*) python3 "$file" ;;
    esac
}

main() {
    local suite="$1" file skips ran=0 skipped=0
    local failed=()
    # suite_files runs in a process substitution, which drops its exit status,
    # so a bad suite name is rejected here or it would pass with nothing run.
    case "$suite" in
        bats|shell|python) ;;
        *) echo "unknown suite: $suite (want bats|shell|python)" >&2; exit 1 ;;
    esac
    cd "$repo_root"
    skips="$(skipped_paths)"
    while IFS= read -r file; do
        [ -e "$file" ] || continue
        if grep -qxF "$file" <<<"$skips"; then
            echo "skip $file"
            skipped=$((skipped + 1))
            continue
        fi
        echo "::group::$file"
        ran=$((ran + 1))
        run_file "$file" || failed+=("$file")
        echo "::endgroup::"
    done < <(suite_files "$suite")
    echo "$suite: ran $ran, skipped $skipped, failed ${#failed[@]}"
    if [ "${#failed[@]}" -gt 0 ]; then
        printf 'FAILED %s\n' "${failed[@]}"
        exit 1
    fi
}

main "$@"
