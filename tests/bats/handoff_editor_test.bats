#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/scripts" "$HOME/.local/state/gordon/handoffs" "$HOME/dev/dotfiles/scripts"
  cat > "$HOME/.claude/scripts/__handoffs_file.py" <<'S'
#!/usr/bin/env bash
sleep "${TEST_SAVE_DELAY:-0}"
if [[ "$1" == neighbor ]]; then
  if [[ "$3" == next ]]; then printf '%s\n' "$HOME/.local/state/gordon/handoffs/22222222-2222-4222-8222-222222222222.md"; else printf '%s\n' "$HOME/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md"; fi
  exit 0
fi
printf 'save %s\n' "${2:-}" >> "$BATS_TEST_TMPDIR/events"
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
  { echo 'local api = vim.api'; sed -n '/^-- Gordon handoff files/,$p' "$REPO_ROOT/.config/nvim/lua/autocommands.lua"; } > "$BATS_TEST_TMPDIR/block.lua"
  cat > "$HOME/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md" <<'S'
## 0341  first
<!-- handoff: 11111111-1111-4111-8111-111111111111 -->

### What
first item
### Reply
>
S
  cat > "$HOME/.local/state/gordon/handoffs/22222222-2222-4222-8222-222222222222.md" <<'S'

## 0342  second
<!-- handoff: 22222222-2222-4222-8222-222222222222 -->

### What
second item
### Reply
>
S
  cat > "$HOME/.local/state/gordon/handoffs/index.md" <<'S'
# Gordon handoffs

- [first](11111111-1111-4111-8111-111111111111.md)
- [second](22222222-2222-4222-8222-222222222222.md)
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
local path = vim.env.HOME .. '/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md'
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

@test "index is read-only and Enter opens the linked handoff" {
  cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
local path = vim.env.HOME .. '/.local/state/gordon/handoffs/index.md'
vim.cmd.edit(vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
assert(vim.bo[buf].readonly and not vim.bo[buf].modifiable, 'index is editable')
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.fn.maparg('<CR>', 'n', false, true).callback()
assert(vim.fn.expand('%:t') == '22222222-2222-4222-8222-222222222222.md', 'Enter did not open link')
S
  run_nvim
}

@test "index navigation opens the adjacent handoff file" {
  cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs/index.md'))
vim.fn.maparg(']]', 'n', false, true).callback()
assert(vim.fn.expand('%:t') == '22222222-2222-4222-8222-222222222222.md', 'next did not open adjacent file')
S
  run_nvim
}

@test "actions use the UUID of the section under the cursor and close the buffer" {
  for pair in 'CR enter' 's spawn' 'd done'; do
    read -r key action <<< "$pair"
    export TEST_KEY="$key"
    cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs/22222222-2222-4222-8222-222222222222.md'))
local handoff = vim.api.nvim_get_current_buf()
vim.cmd('vsplit')
vim.cmd('enew')
vim.cmd('wincmd p')
local handoff_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 7, 0 })
local key = vim.env.TEST_KEY == 'CR' and '<CR>' or vim.env.TEST_KEY
vim.fn.confirm = function() return 1 end
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
  sed -i 's/handoff: 22222222-2222-4222-8222-222222222222/handoff: malformed/' "$HOME/.local/state/gordon/handoffs/22222222-2222-4222-8222-222222222222.md"
  cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs/22222222-2222-4222-8222-222222222222.md'))
vim.api.nvim_win_set_cursor(0, { 7, 0 })
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
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md'))
local handoff = vim.api.nvim_get_current_buf()
vim.cmd('vsplit')
vim.cmd('enew')
vim.cmd('wincmd p')
local handoff_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 6, 0 })
vim.api.nvim_buf_set_lines(handoff, 6, 7, false, { '> reply' })
vim.fn.confirm = function() return 1 end
vim.fn.maparg('d', 'n', false, true).callback()
assert(vim.wait(5000, function() return not vim.api.nvim_win_is_valid(handoff_window) end, 20), 'handoff window was not closed')
assert(vim.api.nvim_get_current_buf() ~= handoff, 'still viewing handoffs')
S
  run_nvim
  [ "$(cat "$BATS_TEST_TMPDIR/events")" = "$(printf 'save %s\naction <--action> <done> <11111111-1111-4111-8111-111111111111>' "$HOME/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md")" ]
}

@test "q and escape close an unmodified handoffs buffer" {
  for key in q Esc; do
    export TEST_KEY="$key"
    cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md'))
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
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md'))
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
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md'))
local handoff = vim.api.nvim_get_current_buf()
local window = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 6, 0 })
vim.api.nvim_buf_set_lines(handoff, 6, 7, false, { '> reply' })
vim.fn.confirm = function() return 1 end
vim.fn.maparg('d', 'n', false, true).callback()
assert(vim.api.nvim_win_is_valid(window), 'view closed after failed save')
assert(vim.api.nvim_get_current_buf() == handoff, 'handoff no longer displayed')
S
  run_nvim
  [ "$(cat "$BATS_TEST_TMPDIR/events")" = "save $HOME/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md" ]
}

@test "failed action leaves the view open" {
  export TEST_ACTION_EXIT=1
  cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md'))
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

@test "cancelling close leaves the edited buffer untouched" {
  for answer in n Esc Enter; do
    export TEST_ANSWER="$answer"
    cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md'))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 6, 0 })
vim.api.nvim_buf_set_lines(buf, 6, 7, false, { '> unsaved' })
local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local input = ({ n = 'n', Esc = '<Esc>', Enter = '<CR>' })[vim.env.TEST_ANSWER]
vim.fn.feedkeys(vim.api.nvim_replace_termcodes(input, true, false, true), 't')
vim.fn.maparg('d', 'n', false, true).callback()
assert(vim.bo[buf].modified and vim.deep_equal(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
S
    run_nvim
    [ ! -e "$BATS_TEST_TMPDIR/events" ]
  done
}

@test "real popup entry loads the full config and selects the requested reply" {
  mkdir -p "$HOME/.config" "$HOME/dev/obsidian/decoder"
  ln -s "$REPO_ROOT/.config/nvim" "$HOME/.config/nvim"
  export XDG_DATA_HOME=/home/decoder/.local/share
  export HANDOFFS_FILE="$HOME/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md"
  export HANDOFFS_STATE="$BATS_TEST_TMPDIR/state.json"
  export FOCUS_TASK_CMD="$BATS_TEST_TMPDIR/task"
  export TASK_BRIEF_TASK_COMMAND="$BATS_TEST_TMPDIR/task"
  export TASK_BRIEF_TMUX_COMMAND="$BATS_TEST_TMPDIR/tmux"
  export TASK_BRIEF_HANDOFFS_COMMAND=/home/decoder/.claude/scripts/__handoffs_file.py
  export TASK_BRIEF_NVIM_COMMAND="$BATS_TEST_TMPDIR/nvim"
  cat > "$BATS_TEST_TMPDIR/task" <<'S'
#!/usr/bin/env bash
printf '%s\n' '[{"uuid":"11111111-1111-4111-8111-111111111111","status":"pending","tags":["piotr"],"description":"first"},{"uuid":"22222222-2222-4222-8222-222222222222","status":"pending","tags":["piotr"],"description":"second"}]'
S
  cat > "$BATS_TEST_TMPDIR/tmux" <<'S'
#!/usr/bin/env bash
[[ "$1" == display-popup ]] || exit 1
bash -c "${!#}"
S
  cat > "$BATS_TEST_TMPDIR/nvim" <<'S'
#!/usr/bin/env bash
exec nvim --headless "$@" -c "lua vim.api.nvim_create_autocmd('VimEnter',{once=true,callback=function() vim.defer_fn(function() local lines={vim.fn.getline('.'),vim.wo.winbar,vim.fn.getline(vim.fn.search('^## ', 'bnW'))}; for _,k in ipairs({'<CR>','s','d','q','<Esc>'}) do local m=vim.fn.maparg(k,'n',false,true); table.insert(lines,k..':'..tostring(m.buffer)) end; vim.fn.writefile(lines,vim.env.BATS_TEST_TMPDIR..'/entry-result'); vim.cmd('qa!') end,900) end})"
S
  chmod +x "$BATS_TEST_TMPDIR"/{task,tmux,nvim}
  : > "$HOME/.local/state/gordon/handoffs.md"
  HANDOFFS_FILE="$HOME/.local/state/gordon/handoffs.md" \
    HANDOFFS_DIR="$HOME/.local/state/gordon/handoffs" \
    HANDOFFS_STATE="$BATS_TEST_TMPDIR/state.json" \
    FOCUS_TASK_CMD="$BATS_TEST_TMPDIR/task" \
    HANDOFFS_TW="$BATS_TEST_TMPDIR/task" \
    "$TASK_BRIEF_HANDOFFS_COMMAND" migrate
  run timeout 20 "$REPO_ROOT/scripts/__task_brief.sh" --actions 2222
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
  [ "$(head -1 "$BATS_TEST_TMPDIR/entry-result")" = '>' ]
  grep -q '^## 2222  second$' "$BATS_TEST_TMPDIR/entry-result"
  grep -q 'd: close (confirm)' "$BATS_TEST_TMPDIR/entry-result" || { cat "$BATS_TEST_TMPDIR/entry-result"; printf "%s\n" "$output"; return 1; }
  [ "$(grep -c ':1$' "$BATS_TEST_TMPDIR/entry-result")" -eq 5 ]
}

@test "handoff navigation skips subsections and lands on each reply" {
  cat > "$BATS_TEST_TMPDIR/scenario.lua" <<'S'
vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. '/.local/state/gordon/handoffs/11111111-1111-4111-8111-111111111111.md'))
vim.api.nvim_win_set_cursor(0, { 7, 0 })
assert(vim.wait(2000, function() return type(vim.fn.maparg(']]', 'n', false, true).callback) == 'function' end), 'navigation missing')
vim.fn.maparg(']]', 'n', false, true).callback()
assert(vim.fn.expand('%:t') == '22222222-2222-4222-8222-222222222222.md', 'next did not open second file')
assert(vim.fn.getline('.') == '>', 'next did not reach second reply')
assert(vim.wait(2000, function() return type(vim.fn.maparg('[[', 'n', false, true).callback) == 'function' end), 'previous mapping missing after file change')
vim.fn.maparg('[[', 'n', false, true).callback()
assert(vim.fn.expand('%:t') == '11111111-1111-4111-8111-111111111111.md', 'previous did not open first file')
assert(vim.fn.getline('.') == '>', 'previous did not reach first reply')
S
  run_nvim
}
