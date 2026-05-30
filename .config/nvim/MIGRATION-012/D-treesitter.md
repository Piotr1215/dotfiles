# D — Treesitter: incremental selection (`an`/`in`) vs textobjects select/move

## VERDICT

> **⚠️ EXECUTION CORRECTION (2026-05-30): this verdict's premise is wrong.**
> Runtime keymap inspection during execution showed `an`/`in` are NOT in a free slot —
> **`mini.ai` owns them** (`around_next`/`inside_next`, `plugins-setup.lua:295`,
> `require("mini.ai").setup{}`). `maparg('an','x')` → `mini/ai.lua:1236`, not the native
> `vim/_core/defaults.lua`. So native 0.12 `an`/`in` is **shadowed** and never surfaces here.
> The static plan grepped config files and checked `nvim-various-textobjs`' `disabledDefaults`
> but missed mini.ai entirely. **Outcome: verified no-op, no change made.** Nothing is broken —
> the user actively uses mini.ai's `an`/`in`; the native feature simply doesn't light up on
> those keys. The "empty slot / works for free" claim below is retained for the record but is FALSE.

**Worth it? — Marginal / optional. No action required to migrate; small optional cleanup available.**

- **What's gained:** Native `an` (grow to outer node) / `in` (shrink to inner node) in
  visual mode, repeatable, no plugin. The user currently has **NO** incremental-selection
  config at all, so this is a brand-new capability for free — not a replacement.
- **What's lost: nothing.** The user never had `nvim-treesitter`'s old
  `incremental_selection` block (`gnn`/`grn`/`grm`/`grc`). Grep across `lua/`, `after/`,
  `ftplugin/` finds zero references. There is nothing to port or delete.
- **What conflicts: NO live collision.** `an`/`in` are listed in
  `lua/plugins.lua:292` (`in`) and `lua/plugins.lua:304` (`an`) — but inside the
  `disabledDefaults` table of `nvim-various-textobjs`. The user has **already disabled**
  those two textobjs, so the visual/operator slot is free. The new 0.12 built-in `an`/`in`
  drops into an empty slot. No shadowing of a live user map.

## CRITICAL DISTINCTION (do not conflate these two systems)

| System | What it does | Keys in this config | 0.12 status |
|---|---|---|---|
| **Incremental selection** | grow/shrink visual selection node-by-node | **none configured** | NEW built-in `an`/`in` — pure addition |
| **Textobjects select** | select a *named* node (function/class) | `af` `if` `ac` `ic` | NOT replaced — keep |
| **Textobjects move** | jump between named nodes | `]m ]] ]a ]M ][ [m [[ [a [M []` | NOT replaced — keep |

The new `an`/`in` are **node-agnostic** (whatever node the cursor sits in). The textobjects
`af`/`if`/`ac`/`ic` are **semantic** (function/class specifically). They solve different
problems and coexist. Migrating incremental selection does **not** touch the textobjects setup.

## Evidence (file:line)

- `lua/settings/plugins-setup.lua:509-521` — `require("nvim-treesitter-textobjects").setup{}`
  with `select.lookahead = true`, `selection_modes` (`@parameter.outer`=`v`,
  `@function.outer`=`V`, `@class.outer`=`<c-v>`), and `move.set_jumps = true`. **Keep as-is.**
- `lua/settings/plugins-setup.lua:526-537` — select maps: `af`/`if` (function outer/inner),
  `ac`/`ic` (class outer/inner). Buffer-agnostic, `{x,o}` modes. **Keep — NOT replaced by `an`/`in`.**
- `lua/settings/plugins-setup.lua:539-568` — move maps (`]m`/`[m` function, `]]`/`[[` class,
  `]a`/`[a` parameter, plus `]M`/`][`/`[M`/`[]` end variants). **Keep — NOT replaced.**
- `lua/settings/plugins-setup.lua:500` — `require("nvim-treesitter").setup{}` (main branch,
  already migrated). No `incremental_selection` key present.
- `lua/plugins.lua:283-308` — `nvim-various-textobjs` with `useDefaults = true` and
  `disabledDefaults` including `"in"` (`:292`) and `"an"` (`:304`). **This is why `an`/`in`
  are free** — they were deliberately turned off, so the new built-in won't fight a plugin map.
- No `incremental_selection` / `gnn` / `grn` / `grm` / `node_incremental` / `scope_incremental`
  anywhere in the config (verified across `lua/`, `after/`, `ftplugin/`).

## Markdown-default-highlight interaction (heads-up for the markdown ftplugin area)

- 0.12 enables markdown treesitter highlighting by default; this config already starts TS on
  every filetype via the `FileType` autocmd at `lua/settings/plugins-setup.lua:503-507`
  (`pcall(vim.treesitter.start)`). So markdown was already getting TS highlight — the 0.12
  default is redundant but harmless here, not a regression.
- `ftplugin/markdown.lua` sets `conceallevel = 0` and uses `nvim-markdown` with
  `no_default_key_mappings = 1`. **No `an`/`in` mapping in the markdown ftplugin** (checked the
  whole file). So the new built-in `an`/`in` is also safe inside markdown buffers.
- One thing for the markdown/ftplugin owner to watch: the extmark monkeypatch at
  `lua/settings/plugins-setup.lua:484-498` (swallows "out of range" extmark errors) is a
  0.11-era workaround. With markdown TS now default-on in 0.12, confirm whether this patch is
  still needed or can be dropped — out of scope here, flagging for cross-area coordination.

## Recommended action (optional, low priority)

1. **Do nothing and it still works** — `an`/`in` light up for free, textobjects untouched.
2. **OR** add a one-line note/comment near line 500 documenting that `an`/`in` incremental
   selection is now native (so a future reader doesn't try to re-add the old
   `incremental_selection` block or re-enable the `nvim-various-textobjs` `an`/`in` defaults,
   which WOULD then collide).
3. Leave `disabledDefaults` `in`/`an` entries in `lua/plugins.lua` **in place** — removing them
   would re-enable the number textobj on `an`/`in` and *create* the collision that currently
   does not exist.

## Top bottlenecks (for GH issue comment)

1. **No incremental_selection to migrate** — config never had it; 0.12 `an`/`in` is a pure
   additive win, zero porting work.
2. **No collision** — `an`/`in` already cleared via `nvim-various-textobjs` `disabledDefaults`
   (`lua/plugins.lua:292,304`); the built-in lands in an empty slot.
3. **Keep textobjects select/move intact** — `af/if/ac/ic` + the `]m`/`[m`-family moves
   (`plugins-setup.lua:526-568`) are semantic and NOT superseded by node-wise `an`/`in`.
4. **Cross-area flag:** the extmark out-of-range monkeypatch (`:484-498`) and markdown
   default-on TS highlight may now overlap — coordinate with the markdown ftplugin owner.
