# Area A — Plugin Manager: lazy.nvim → vim.pack

Neovim 0.12.2 ships `vim.pack`, a native plugin manager. This evaluates whether the
local config at `lua/plugins.lua` (108 specs, 503 lines) should move off lazy.nvim.
Read-only investigation; no config files were modified.

---

## VERDICT

**Worth it? NO-GO for the 108 plugins. PARTIAL — adopt `vim.pack` only for the 2 bundled built-ins (nvim-undotree, nvim-difftool), if wanted.**

The single fact that decides this: **5 plugins use `dev = true`** (local development from
`/home/decoder/dev`). `vim.pack` has no local-path / `dev` equivalent. Migrating means
either symlinking into the pack dir by hand or pulling the GitHub copy instead of the
local working tree — which breaks the user's plugin-development workflow outright.

### What's LOST (ranked by severity — honest about the data)

The task framing says "heavy lazy-loading." The data says otherwise: lazy-loading loss is
**minor**. The real blockers are local-dev, build hooks, and dependency ordering.

| # | Lost capability | Specs affected | vim.pack equivalent |
|---|-----------------|----------------|---------------------|
| 1 | **`dev = true` local plugins** (hard blocker) | 5: pairup.nvim (L24), typeit.nvim (L335), docusaurus.nvim (L339), beam.nvim (L365), presenterm.nvim (L388) | **None.** No local-path linking. Configured via `dev = { path = "/home/decoder/dev" }` at L498-502. |
| 2 | **Build hooks** | 4: telescope-fzf-native `make` (L184), nvim-treesitter `:TSUpdate` (L189), LuaSnip `make install_jsregexp` (L237), markdown-preview `cd app && yarn install` (L323) | Partial. PackChanged autocmd post-install hook exists but each must be rewired manually; no per-spec `build=` field. |
| 3 | **Dependency ordering** | 10 `dependencies = {}` blocks (e.g. telescope L173, nvim-cmp L258, dap-ui L248, lualine L437) | **None.** No dependency graph. Load order is registration order only; must be hand-sequenced. |
| 4 | Lazy-loading triggers | **~7-8 specs only** (see breakdown) | None (vim.pack loads everything at startup). |

**Lazy-loading breakdown (deduped to SPECS, not raw grep hits):**
Of ~108 specs, only **~7-8 are actually lazy-loaded today**. The rest (~100) **already load
eagerly** — lazy.nvim's opts block (L494-503) sets no `defaults = { lazy = true }`, so the
default is eager.

- `event = "VeryLazy"`: 2 — yazi.nvim (L81), nvim-various-textobjs (L285)
- `ft = ...`: 5 — yaml.nvim (L154), lazydev (L196), rustaceanvim (L275, but also `lazy=false`), markdown-preview (L327), vimtex (L460)
- `cmd = ...`: 2 — Pairup (L25), markdown-preview (L322). *(L53 `cmd = "...__claude_with_monitor.sh"` is pairup's provider command, NOT a lazy trigger.)*
- `keys = ...`: 2 — Pairup (L26), yazi (L82)
- `lazy = true`: 2 — plenary.nvim (L116), luvit-meta (L205)
- `lazy = false` (forced eager): 2 — nvim-lspconfig (L220), rustaceanvim (L274)

After dedup (pairup = cmd+keys, yazi = event+keys, markdown-preview = cmd+ft), the genuinely
deferred set is roughly: **pairup, yazi, plenary, yaml.nvim, lazydev, luvit-meta,
markdown-preview, vimtex** — ~8 specs. The meaningful startup cost is concentrated in just
**vimtex** and **markdown-preview** (both heavy, both correctly gated by filetype today).
Eager-loading those two on every launch is the only material regression from losing
lazy-loading — and it is not quantified here (static analysis cannot produce a startup-ms
figure; `nvim --startuptime` would give a real number if needed, read-only).

### What CONFLICTS

- **Treesitter runtime-path hack — `lua/settings/plugins-setup.lua:501`**:
  `vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/nvim-treesitter/runtime")` hardcodes
  lazy.nvim's install directory. **But nvim-treesitter is NOT a bundled built-in** — the 0.12
  built-ins are nvim-undotree and nvim-difftool. So the recommended PARTIAL path never touches
  treesitter and never trips this hack. It is a blocker *only* for the rejected
  "migrate treesitter to vim.pack" branch, where the path would have to change to
  `…/site/pack/core/opt/nvim-treesitter/runtime`.
- **PlantUML previewer path — `lua/settings/plugins-setup.lua:643`**: also hardcodes `/lazy/`
  (`~/.local/share/nvim/lazy/plantuml-previewer.vim/viewer`). Same class of coupling; only
  relevant if that plugin moves to vim.pack (it does not under PARTIAL).
- Bootstrap at `lua/plugins.lua:2-16` clones lazy.nvim and prepends its path. Untouched under
  PARTIAL.

---

## PARTIAL path (the only recommended change)

The two managers coexist safely: lazy.nvim manages `~/.local/share/nvim/lazy/`, vim.pack
manages `~/.local/share/nvim/site/pack/`. Separate directories, no collision. The 2 built-ins
are **new opt-in additions** — the user loses nothing, vim.pack is just their delivery
mechanism. This is the hinge that makes PARTIAL coherent: it is additive, not a migration.

### Steps

1. **Keep lazy.nvim exactly as-is** for all 108 specs. No change to `lua/plugins.lua`,
   no change to the treesitter rtp hack, no change to bootstrap.
2. **If** the user wants the new built-in tools (undotree / difftool), add a small standalone
   block (e.g. a new `lua/settings/builtins-012.lua`, required from `init.lua` after
   `require "plugins"`):
   ```lua
   -- Neovim 0.12 native built-ins via vim.pack (opt-in, additive)
   vim.pack.add({
     { src = "https://github.com/neovim/nvim-undotree" },
     { src = "https://github.com/neovim/nvim-difftool" },
   })
   ```
   (Confirm exact upstream `src` URLs against `:h news-0.12` before applying; the built-ins
   ship *through* vim.pack and are opt-in per the confirmed facts.)
3. Update via `vim.pack.update()` / `:packupdate`; remove via `:packdel`. Independent of
   lazy's `:Lazy` flow.

### Do NOT

- Do not move the 108 specs to vim.pack — kills 5 dev plugins, 10 dependency graphs, 4 build
  hooks, and eager-loads vimtex + markdown-preview.
- Do not move nvim-treesitter to vim.pack — triggers the rtp hack at plugins-setup.lua:501.

---

## Evidence index (file:line)

- `lua/plugins.lua:2-16` — lazy bootstrap (clones to `…/lazy/lazy.nvim`)
- `lua/plugins.lua:24,335,339,365,388` — the 5 `dev = true` plugins
- `lua/plugins.lua:498-502` — `dev = { path = "/home/decoder/dev", fallback = false }`
- `lua/plugins.lua:184,189,237,323` — 4 build steps
- `lua/plugins.lua:81,285` — `event = "VeryLazy"`
- `lua/plugins.lua:154,196,275,327,460` — `ft =` gated
- `lua/plugins.lua:25,322` — `cmd =` gated (L53 is a provider cmd, not a trigger)
- `lua/plugins.lua:26,82` — `keys =` gated
- `lua/plugins.lua:116,205` — `lazy = true`
- `lua/plugins.lua:220,274` — `lazy = false` forced eager
- `lua/plugins.lua:494-503` — lazy opts: no `defaults.lazy`, so ~100 specs eager by default
- `lua/settings/plugins-setup.lua:501` — treesitter rtp hack coupled to `/lazy/`
- `lua/settings/plugins-setup.lua:643` — plantuml previewer path coupled to `/lazy/`
- `init.lua:5` — `require "plugins"` (resolves to `plugins.lua`; `lua/plugins/inline-shell.lua` is dormant, not auto-imported)
