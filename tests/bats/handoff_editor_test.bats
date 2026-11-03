#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/scripts" "$HOME/.local/state/gordon" "$HOME/dev/dotfiles/scripts"
  cat > "$HOME/.claude/scripts/__handoffs_file.py" <<'S'
#!/usr/bin/env bash
sleep "${TEST_SAVE_DELAY:-0}"
printf 'save\n' >> "$BATS_TEST_TMPDIR/events"
exit "${TEST_SAVE_EXIT:-0}"
S
  cat > "$HOME/dev/dotfiles/scripts/__task_brief.sh" <<'S'
#!/usr/bin/env bash
printf 'action' >> "$BATS_TEST_TMPDIR/events"
printf ' <%s>' "$@" >> "$BATS_TEST_TMPDIR/events"
printf '\n' >> "$BATS_TEST_TMPDIR/events"
exit "${TEST_ACTION_EXIT:-0}"
S
  chmod +x "$HOME/.claude/scripts/__handoffs_file.py" "$HOME/dev/dotfiles/scripts/__task_brief.sh"
  { echo 'local api = vim.api'; sed -n '/^-- Gordon handoffs file/,$p' "$REPO_ROOT/.config/nvim/lua/autocommands.lua"; } > "$BATS_TEST_TMPDIR/block.lua"
  cat > "$HOME/.local/state/gordon/handoffs.md" <<'S'
## 0341  first
<!-- handoff: 11111111-1111-4111-8111-111111111111 -->

### What
first item
### Reply
>

## 0342  second
<!-- handoff: 22222222-2222-4222-8222-222222222222 -->

### What
second item
### Reply
>
S
  cat > "$BATS_TEST_TMPDIR/runner.lua" <<'S'
local ok, err = pcall(function()
  dofile(vim.env.BATS_TEST_TMPDIR .. '/block.lua')
  dofile(vim.env.BATS_TEST_TMPDIR .. '/scenario.lua')
end)
if not ok then
  io.stderr:write(tostring(err) .. '\n')
  vim.cmd('cquit 1')
end
vim.cmd('qa!')
S
}

run_nvim() {
  run timeout 15 nvim --headless -u NONE -l "$BATS_TEST_TMPDIR/runner.lua"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
}

@test "mappings apply only to the handoffs buffer in normal mode" {
  cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
local path = vim.env.HOME .. '/.local/state/gordon/handoffs.md'
vim.cmd.edit(vim.fn.fnameescape(path))
for _, key in ipairs({ '<CR>', 's', 'd', 'q', '<Esc>' }) do
  local m = vim.fn.maparg(key, 'n', false, true)
  assert(m.buffer == 1 and type(m.callback) == 'function', 'missing local normal mapping: ' .. key)
  assert(vim.tbl_isempty(vim.fn.maparg(key, 'i', false, true)), 'insert mapping: ' .. key)
end
vim.cmd.edit(vim.fn.fnameescape(vim.env.BATS_TEST_TMPDIR .. '/other.md'))
for _, key in ipairs({ '<CR>', 's', 'd', 'q', '<Esc>' }) do
  assert(vim.tbl_isempty(vim.fn.maparg(key, 'n', false, true)), 'mapping leaked to other file: ' .. key)
end
S
  run_nvim
}

@test "actions use the UUID of the section under the cursor and close the buffer" {
  for pair in 'CR enter' 's spawn' 'd done'; do
    read -r key action <<< "$pair"
    export TEST_KEY="$key"
    cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs.md'))
local handoff = vim.api.nvim_get_current_buf()
vim.cmd('vsplit')
vim.cmd('enew')
vim.cmd('wincmd p')
local handoff_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 14, 0 })
local key = vim.env.TEST_KEY == 'CR' and '<CR>' or vim.env.TEST_KEY
vim.fn.maparg(key, 'n', false, true).callback()
assert(vim.wait(5000, function() return not vim.api.nvim_win_is_valid(handoff_window) end, 20), 'handoff window was not closed')
assert(vim.api.nvim_get_current_buf() ~= handoff, 'still viewing handoffs')
S
    run_nvim
    [ "$(cat "$BATS_TEST_TMPDIR/events")" = "action <--action> <$action> <22222222-2222-4222-8222-222222222222>" ]
    rm "$BATS_TEST_TMPDIR/events"
  done
}

@test "missing section marker does not dispatch the previous UUID" {
  sed -i 's/handoff: 22222222-2222-4222-8222-222222222222/handoff: malformed/' "$HOME/.local/state/gordon/handoffs.md"
  cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs.md'))
vim.api.nvim_win_set_cursor(0, { 12, 0 })
vim.fn.maparg('s', 'n', false, true).callback()
vim.wait(300)
assert(vim.api.nvim_buf_is_valid(vim.api.nvim_get_current_buf()), 'buffer closed for missing marker')
S
  run_nvim
  [ ! -e "$BATS_TEST_TMPDIR/events" ]
}

@test "modified buffer saves before dispatch" {
  export TEST_SAVE_DELAY=0.3
  cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs.md'))
local handoff = vim.api.nvim_get_current_buf()
vim.cmd('vsplit')
vim.cmd('enew')
vim.cmd('wincmd p')
local handoff_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 6, 0 })
vim.api.nvim_buf_set_lines(handoff, 6, 7, false, { '> reply' })
vim.fn.maparg('d', 'n', false, true).callback()
assert(vim.wait(5000, function() return not vim.api.nvim_win_is_valid(handoff_window) end, 20), 'handoff window was not closed')
assert(vim.api.nvim_get_current_buf() ~= handoff, 'still viewing handoffs')
S
  run_nvim
  [ "$(cat "$BATS_TEST_TMPDIR/events")" = $'save\naction <--action> <done> <11111111-1111-4111-8111-111111111111>' ]
}

@test "q and escape close an unmodified handoffs buffer" {
  for key in q Esc; do
    export TEST_KEY="$key"
    cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs.md'))
local handoff = vim.api.nvim_get_current_buf()
vim.cmd('vsplit')
vim.cmd('enew')
vim.cmd('wincmd p')
local handoff_window = vim.api.nvim_get_current_win()
local key = vim.env.TEST_KEY == 'Esc' and '<Esc>' or vim.env.TEST_KEY
vim.fn.maparg(key, 'n', false, true).callback()
assert(not vim.api.nvim_win_is_valid(handoff_window), 'handoff window was not closed')
assert(vim.api.nvim_get_current_buf() ~= handoff, 'still viewing handoffs')
S
    run_nvim
  done
}

@test "q and escape ask before discarding changes" {
  for key in q Esc; do
    export TEST_KEY="$key"
    cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs.md'))
local handoff = vim.api.nvim_get_current_buf()
vim.cmd('vsplit')
vim.cmd('enew')
vim.cmd('wincmd p')
local handoff_window = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(handoff, 6, 7, false, { '> unsaved reply' })
local asked = false
vim.fn.confirm = function() asked = true; return 2 end
local key = vim.env.TEST_KEY == 'Esc' and '<Esc>' or vim.env.TEST_KEY
vim.fn.maparg(key, 'n', false, true).callback()
assert(asked, 'close did not ask about unsaved changes')
assert(vim.api.nvim_buf_is_valid(handoff), 'cancel discarded the buffer')
assert(vim.bo[handoff].modified, 'cancel lost the modified state')
S
    run_nvim
  done
}

@test "failed save blocks the action and leaves the view open" {
  export TEST_SAVE_EXIT=1
  cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs.md'))
local handoff = vim.api.nvim_get_current_buf()
local window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 6, 0 })
vim.api.nvim_buf_set_lines(handoff, 6, 7, false, { '> reply' })
vim.fn.maparg('d', 'n', false, true).callback()
assert(vim.api.nvim_win_is_valid(window), 'view closed after failed save')
assert(vim.api.nvim_get_current_buf() == handoff, 'handoff no longer displayed')
S
  run_nvim
  [ "$(cat "$BATS_TEST_TMPDIR/events")" = 'save' ]
}

@test "failed action leaves the view open" {
  export TEST_ACTION_EXIT=1
  cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs.md'))
local handoff = vim.api.nvim_get_current_buf()
local window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 6, 0 })
vim.fn.maparg('s', 'n', false, true).callback()
assert(vim.api.nvim_win_is_valid(window), 'view closed after failed action')
assert(vim.api.nvim_get_current_buf() == handoff, 'handoff no longer displayed')
S
  run_nvim
  [ "$(cat "$BATS_TEST_TMPDIR/events")" = 'action <--action> <spawn> <11111111-1111-4111-8111-111111111111>' ]
}
