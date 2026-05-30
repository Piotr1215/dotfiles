# Migration 0.12 — Area C: LSP Keymaps

## VERDICT

**Worth it? Yes, but low urgency — this is pure dedup/cleanup, nothing hard-breaks.**

Every custom LSP map is either leader-prefixed (`<leader>ca/rn/D/Ic/Oc/ds/ws`) or a
plain key (`gd/gD/gI/K/<c-f>`). **None** sit on the `gr`-prefix that the new
0.11/0.12 stock defaults occupy (`grn gra grr gri grt grx`). So there are **zero hard
conflicts** — the user can adopt every stock default without colliding with anything
they already bind.

**What conflicts (specific keys): nothing.** The one real collision the user *already*
fixed: custom `gr` (references) was removed in favour of stock `grr` (see comment at
`default-lsp.lua:44`). The migration is otherwise additive.

**What's lost (muscle memory):**
- `<leader>D` (type_definition) → retire in favour of stock `grt`. One finger-habit to relearn.
- `gD` (definition-in-vsplit) → retire-able via `'switchbuf'` (see Adopt section). Mild relearn.
- Adopting the `gr*` family shadows Vim's built-in `gr` virtual-replace operator — but
  the user already accepted that by deleting custom `gr`. No new loss.

**Codelens / `grx` is useless here:** codelens is not enabled anywhere in the config
(grep for `codelens` returns nothing). The new `grx` default will be a no-op until
`vim.lsp.codelens` is turned on. No action needed; just know the key does nothing today.

## NOTE — false alarm ruled out

`lua/mappings.lua:398` `utils.lnmap("gd", ":Gvdiffsplit<CR>")` is **not** a conflict.
`lnmap` (`lua/utils.lua:14`) prepends `<leader>`, so the real key is `<leader>gd`, not
plain `gd`. It does not shadow LSP `gd`. Leave it alone.

## Keep / Retire / Rebind table

Stock defaults referenced: `grn` rename, `gra` code_action, `grr` references,
`gri` implementation, `grt` type_definition (0.12), `grx` codelens.run (0.12),
`K` hover.

| Custom map | File:line | Function | Stock covers it? | Action |
|---|---|---|---|---|
| `K` | default-lsp.lua:36 | hover | Yes — stock `K` | **Retire** (redundant; stock identical) |
| `<leader>ca` | default-lsp.lua:38 | code_action | `gra` | **Keep** (no conflict; muscle memory) |
| `gd` | default-lsp.lua:39 | definition | no stock plain `gd` | **Keep** (intentional non-`gr` binding) |
| `gD` | default-lsp.lua:40 | definition in vsplit | partial via `'switchbuf'` | **Rebind** (see Adopt — let stock + switchbuf do it) |
| `gI` | default-lsp.lua:41 | implementation | `gri` | **Keep** (no conflict; muscle memory) |
| `<leader>rn` | default-lsp.lua:45 | rename | `grn` | **Keep** (no conflict; muscle memory) |
| `<leader>D` | default-lsp.lua:46 | type_definition | `grt` (0.12) | **Retire** — exact duplicate of new default |
| `<leader>Ic` `<leader>Oc` | default-lsp.lua:42-43 | incoming/outgoing calls | no stock | **Keep** |
| `<leader>ds` `<leader>ws` | default-lsp.lua:47-48 | telescope symbols | no stock | **Keep** (telescope-specific) |
| `<c-f>` | default-lsp.lua:57 | format | no stock map | **Keep** |
| `[d` / `]d` | default-lsp.lua:33-34 | diagnostic prev/next | adjacent (see below) | **Keep — verify separately** |

### rust-setup.lua — redundant double-definitions

`rustaceanvim` is a real LSP client, so the **global `LspAttach` autocmd in
default-lsp.lua also fires on Rust buffers.** That means these per-buffer maps are
defined *twice* (once globally, once here) AND overlap stock:

| Map | File:line | Why redundant | Action |
|---|---|---|---|
| `K` | rust-setup.lua:21 | global + stock both set hover | **Retire** |
| `gd` | rust-setup.lua:23 | global already sets it | **Retire** |
| `<leader>rn` | rust-setup.lua:25 | global already sets it | **Retire** |
| `<leader>ca` | rust-setup.lua:33 | global already sets it | **Retire** |
| `[d` / `]d` | rust-setup.lua:27-28 | global already sets them | **Retire** |
| `<leader>ar` (RustLsp hover actions) | rust-setup.lua:12 | rustaceanvim-specific | **Keep** |
| `<leader>ag` (RustLsp codeAction) | rust-setup.lua:17 | rustaceanvim-specific | **Keep** |
| `<leader>tb` (dap breakpoint) | rust-setup.lua:36 | not LSP | **Keep** |

### ftplugin/ocaml.lua

| Map | File:line | Action |
|---|---|---|
| `K` (hover) | ocaml.lua:30 | **Retire** — global autocmd + stock both cover it (comment even says "K is usually default") |
| `<leader>ot/ob/or/R/ou/oi`, OcamlRun | ocaml.lua:33-68 | **Keep** — OCaml-specific, no stock equivalent |

### ftplugin/go.lua

No LSP keymaps. `<leader>gr` (GoRun) and `<leader>ggr` (GoGenReturn) are
plugin/command maps, leader-prefixed, no overlap with stock `gr*`. **Leave alone.**

## New 0.12 capabilities worth adopting

1. **`'switchbuf'` + stock jump funcs → retire `gD`.** In 0.12 the LSP jump functions
   (definition/declaration/type_definition/implementation) honour `'switchbuf'`. The
   config sets `switchbuf` nowhere (grep empty). The hand-rolled `gD`
   (`<cmd>vsplit | lua vim.lsp.buf.definition()<CR>`, default-lsp.lua:40) can be
   replaced by setting `'switchbuf'` and using stock — ties the new behavior to a
   concrete cleanup. Worth a small experiment post-migration.

2. **`:lsp` command** — new status/control command. Adopt as a discoverability tool
   (no keymap needed); good replacement for ad-hoc `:LspInfo`-style checks.

## Adjacent — verify separately (NOT in scope, NOT confirmed here)

`[d` / `]d` use `vim.diagnostic.goto_prev/goto_next` (default-lsp.lua:33-34,
rust-setup.lua:27-28). These are **diagnostics, not LSP**, and 0.12 diagnostic-jump
behavior was not in the confirmed-facts brief. Flag for the diagnostics migration
area: check whether `vim.diagnostic.jump{count=...}` is now preferred. Do not change
as part of LSP cleanup.

## Suggested execution order (when editing is authorized)

1. Delete redundant per-buffer maps in `rust-setup.lua` (K, gd, `<leader>rn`,
   `<leader>ca`, `[d`, `]d`) and `ocaml.lua` (K) — they already come from the global
   autocmd + stock.
2. Retire `<leader>D` (default-lsp.lua:46) and `K` (default-lsp.lua:36) — stock covers both.
3. Experiment with `'switchbuf'` to retire `gD`.
4. Keep `<leader>ca/rn`, `gd`, `gI` — zero cost, preserves muscle memory; the user is
   mid-migration and has only retired the map that actually collided (`gr`).
