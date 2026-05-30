# Bucket F — nvim-undotree & nvim-difftool (0.12 bundled built-ins)

## VERDICT

**Mostly SKIP. One narrow, genuinely-new candidate: `nvim-undotree`.**

- **`nvim-difftool` → SKIP.** Fully covered by fugitive + gitsigns + custom commands.
  Adopting it means wiring `[diff] difftool` git config to a built-in that overlaps
  the existing `:Gvdiffsplit` merge/diff flow. No gap to fill.
- **`nvim-undotree` → OPTIONAL / DEFER.** There is **no undo-tree visualizer installed
  today** (no `mbbill/undotree`). So this would *add* a capability rather than churn a
  working one. But the user has lived without a tree visualizer; the only undo-navigation
  today is `mini.bracketed`'s linear `[u`/`]u` hops. Adopt only if the user actually wants
  branch-aware undo browsing. Not required by the 0.12 upgrade.

### What's lost by skipping
- `nvim-difftool`: nothing. Existing diff/merge tooling is unaffected.
- `nvim-undotree`: a visual, branching undo history navigator (`:UndoTree`). The current
  setup can only walk undo states linearly, not see/jump across undo *branches*.

### What conflicts (if adopted anyway)
- **Both install via `vim.pack.add` (the new native manager).** This config is **pure
  lazy.nvim** — `grep -rni vim.pack` across `lua/`, `init.lua`, `plugin/`, `after/` returns
  **NONE**. Adopting either built-in pulls `vim.pack` into the boot path *just for them*,
  running two plugin managers side by side.
  **→ HARD DEPENDENCY ON BUCKET A.** If A's verdict is "stay on lazy.nvim, don't adopt
  vim.pack," then F is automatically SKIP for both — the cost (second manager) outweighs
  the benefit (one optional undo viewer that also exists as a lazy-installable plugin
  `mbbill/undotree`).
- `nvim-difftool` adopted as git `difftool` would compete with the existing
  `[mergetool "fugitive"]` mental model (one tool for merge, another for diff).

---

## Evidence (file:line)

### Undo — no tree visualizer exists
- No `mbbill/undotree` or equivalent in `lua/plugins.lua` (full plugin list scanned).
- `lua/settings/plugins-setup.lua:326` — `undo = { suffix = "", options = {} }` is a key
  in the **`mini.bracketed`** setup block (header at `:316`), i.e. `[u`/`]u` linear
  undo-state traversal. **Not** a tree UI.
- `<leader>u*` keymaps (`lua/mappings.lua:597-598`) are bound to `UrlView`, unrelated to undo.
- Net: `nvim-undotree` fills a real (if low-priority) gap.

### Diff/merge — already well covered, no difftool gap that needs a *new* plugin
- `lua/plugins.lua:142` — `lewis6991/gitsigns.nvim`
- `lua/plugins.lua:143` — `tpope/vim-fugitive`
- `lua/settings/plugins-setup.lua:86` — `<leader>hd` → `gitsigns.diffthis` (hunk/buffer diff)
- `lua/mappings.lua:398` — `gd` → `:Gvdiffsplit<CR>` (fugitive vertical diff split)
- `lua/mappings.lua:399` — `gu` → `:Gdiffu<CR>`
- `lua/autocommands.lua:187` — custom `:Gdiff` (`git diff --no-index`)
- `lua/autocommands.lua:191` — custom `:Gdiffu` (unified diff to floating scratch)
- `lua/autocommands.lua` — custom `:Ghistory` (`git log -p --all`)
- No `diffview.nvim`, no `neogit`.

### Git config (split via includeIf; ~/dev/** → personal, ~/loft/** → work)
- `~/.gitconfig-personal` and `~/.gitconfig-work` are **identical** on the relevant keys:
  - `[merge] tool = fugitive`
  - `[mergetool "fugitive"] cmd = nvim -f -c "Gvdiffsplit!" "$MERGED"`
  - `[core] editor = nvim`
  - `[core] pager = delta --side-by-side`; `[interactive] diffFilter = delta --color-only`
  - **No `[diff] tool` and no `[difftool]` section in either file.**
- So `git difftool` today has **no** nvim integration — it would fall back to git defaults.
  This is the one slot `nvim-difftool` *could* fill, but the user clearly diffs from inside
  nvim (fugitive/gitsigns), not via `git difftool` from the shell. Low value.

---

## IF (and only if) adopting — minimal recipe

> Prerequisite: Bucket A adopts `vim.pack`. If not, stop — do not pull vim.pack in for this.

### A. nvim-undotree (the only one worth considering)
Add near the top of plugin loading (after leader is set), e.g. a new
`lua/settings/native-plugins.lua` sourced from `init.lua`:

```lua
vim.pack.add({ "nvim-undotree" })   -- ships with 0.12; opt-in
-- optional keymap, mirrors the unused <leader>u namespace:
vim.keymap.set("n", "<leader>ut", "<Cmd>UndoTree<CR>", { desc = "Undo tree" })
```

Cheaper alternative that needs **no** vim.pack: `mbbill/undotree` as a normal lazy spec in
`lua/plugins.lua`. Same UX, no second plugin manager. **Prefer this if A says no to vim.pack.**

### B. nvim-difftool (only if a shell `git difftool` workflow is actually wanted)
```lua
vim.pack.add({ "nvim-difftool" })
```
Then in `~/.gitconfig-personal` (and `-work` to match):
```ini
[diff]
  tool = nvim-difftool
[difftool "nvim-difftool"]
  cmd = nvim -d "$LOCAL" "$REMOTE"   # or the plugin's documented invocation
[difftool]
  prompt = false
```
Not recommended: duplicates existing in-editor diffing and adds a second git tool concept.

---

## Bottlenecks / dependencies (for the GH issue comment)
1. **Hard gate on Bucket A (vim.pack).** Both built-ins install only via `vim.pack.add`;
   config is currently pure lazy.nvim (zero vim.pack usage). If A stays on lazy → F = SKIP both.
2. **`nvim-difftool` is pure duplication** of fugitive + gitsigns + custom `:Gdiff*` commands;
   no `[difftool]` gap the user actually exercises. SKIP.
3. **`nvim-undotree` is the only real gap** (no undo-tree viewer installed), but it's
   optional and equally available as a lazy plugin (`mbbill/undotree`) without touching
   vim.pack — so even here, adopting the *built-in* specifically is not worth it unless A
   already commits to vim.pack.
