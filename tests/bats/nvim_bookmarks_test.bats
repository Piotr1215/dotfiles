#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BOOKMARKS_LUA="$REPO_ROOT/.config/nvim/lua/user_functions/bookmarks.lua"
  TARGET_FILE="$BATS_TEST_TMPDIR/settings.conf"
  BOOKMARKS_FILE="$BATS_TEST_TMPDIR/bookmarks.conf"
  printf 'one\ntwo\nthree\nfour\n' > "$TARGET_FILE"
  : > "$BOOKMARKS_FILE"
}

@test "bookmark targets parse an optional line number" {
  run nvim --headless -u NONE \
    "+lua local m=dofile('$BOOKMARKS_LUA'); local p,l=m.parse_bookmark_target('/tmp/file;42'); assert(p == '/tmp/file'); assert(l == 42)" \
    "+lua local m=dofile('$BOOKMARKS_LUA'); local p,l=m.parse_bookmark_target('/tmp/file'); assert(p == '/tmp/file'); assert(l == nil)" \
    +qa

  [ "$status" -eq 0 ]
}

@test "visual mode exposes the line bookmark mapping" {
  run nvim --headless -u NONE \
    "+lua dofile('$BOOKMARKS_LUA'); local m=vim.fn.maparg('<leader>ba', 'x', false, true); assert(m.desc == 'Add selected line to bookmarks')" \
    +qa

  [ "$status" -eq 0 ]
}

@test "a visual selection bookmarks its first line" {
  run env BOOKMARK_TARGET_FILE="$TARGET_FILE" nvim --headless -u NONE \
    "+edit $TARGET_FILE" \
    "+lua local m=dofile('$BOOKMARKS_LUA'); local saved; m.add_path_to_bookmarks=function(path, line) saved={path,line} end; vim.api.nvim_buf_set_mark(0, '<', 4, 0, {}); vim.api.nvim_buf_set_mark(0, '>', 2, 0, {}); m.add_current_selection_to_bookmarks(); assert(saved[1] == vim.env.BOOKMARK_TARGET_FILE); assert(saved[2] == 2)" \
    +qa

  [ "$status" -eq 0 ]
}

@test "opening a line bookmark moves the cursor to that line" {
  run env BOOKMARK_TARGET_FILE="$TARGET_FILE" nvim --headless -u NONE \
    "+lua local m=dofile('$BOOKMARKS_LUA'); m.open_bookmark(vim.env.BOOKMARK_TARGET_FILE, 3); assert(vim.fn.line('.') == 3)" \
    +qa

  [ "$status" -eq 0 ]
}

@test "several line bookmarks can coexist for one file" {
  run env BOOKMARKS_FILE="$BOOKMARKS_FILE" BOOKMARK_TARGET_FILE="$TARGET_FILE" nvim --headless -u NONE \
    "+lua local m=dofile('$BOOKMARKS_LUA'); local d={'first','second'}; vim.ui.input=function(_, cb) cb(table.remove(d, 1)) end; m.add_path_to_bookmarks(vim.env.BOOKMARK_TARGET_FILE, 2); m.add_path_to_bookmarks(vim.env.BOOKMARK_TARGET_FILE, 4)" \
    "+lua local lines=vim.fn.readfile(vim.env.BOOKMARKS_FILE); assert(#lines == 2); assert(lines[1]:match(';2$')); assert(lines[2]:match(';4$'))" \
    +qa

  [ "$status" -eq 0 ]
}
