#!/usr/bin/env bash
# Tests for scripts/__kiwix_search.sh with a fake kiwix-search and ZIM dir.
set -o pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/scripts/__kiwix_search.sh"
tmp=$(mktemp -d)
fails=0

# cleanup removes the temp dir
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/zim"
touch "$tmp/zim/wikipedia_en_medicine_maxi.zim" "$tmp/zim/zimgit-water_en.zim"
cat > "$tmp/bin/kiwix-search" <<'EOF'
#!/usr/bin/env bash
echo "hit for $2 in $(basename "$1")"
EOF
chmod +x "$tmp/bin/kiwix-search"

# assert_eq compares expected and actual output
assert_eq() {
    if [[ "$1" != "$2" ]]; then
        echo "FAIL $3: expected [$1] got [$2]"; fails=$((fails + 1))
    else
        echo "ok $3"
    fi
}

run() { PATH="$tmp/bin:$PATH" KIWIX_ZIM_DIR="$tmp/zim" bash "$script" "$@"; }

test_searches_all_books() {
    assert_eq "[wikipedia_en_medicine_maxi] hit for burn in wikipedia_en_medicine_maxi.zim
[zimgit-water_en] hit for burn in zimgit-water_en.zim" "$(run burn)" "all books"
}

test_book_filter_and_multiword_query() {
    assert_eq "[zimgit-water_en] hit for boil water in zimgit-water_en.zim" "$(run -b water boil water)" "book filter"
}

test_list() {
    assert_eq "wikipedia_en_medicine_maxi
zimgit-water_en" "$(run -l)" "list"
}

test_unknown_book_fails() {
    run -b nope x >/dev/null 2>&1; assert_eq 1 $? "unknown book exits 1"
}

test_missing_dir_fails() {
    KIWIX_ZIM_DIR="$tmp/missing" bash "$script" x >/dev/null 2>&1; assert_eq 1 $? "missing dir exits 1"
}

if [[ -n "$1" ]]; then "$1"; else
    test_searches_all_books; test_book_filter_and_multiword_query; test_list; test_unknown_book_fails; test_missing_dir_fails
fi
exit $((fails > 0))
