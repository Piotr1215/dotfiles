# G — System-Wide nvim Dependencies + 0.12 Silent Defaults

Scope: everything OUTSIDE `.config/nvim/` that touches nvim, plus the 0.12 silent
default-value changes that a keymap/config scan misses. READ-ONLY audit.

Neovim: 0.11.x → **0.12.2**

---

## VERDICT (read this first)

**No hard breaks. Zero NEEDS-CHANGE. The adjacent surface is boring — which is the
correct, honest result.** The user already neutralized the two defaults that would have
bitten: `exrc` is never enabled, and `spellfile` is set explicitly. Everything external
falls into SAFE or cosmetic WATCH.

### Adjacent dependency ledger

| # | Dependency | Location | Tag |
|---|-----------|----------|-----|
| 1 | `$EDITOR=nvim`, `$VISUAL=nvim` | `.zshrc:152`, `.zshrc:134` | SAFE |
| 2 | git `core.editor = nvim` (personal+work) | `.gitconfig-personal`, `.gitconfig-work` | SAFE |
| 3 | git mergetool `nvim -f -c "Gvdiffsplit!"` | both gitconfigs `[mergetool "fugitive"]` | WATCH (cosmetic) |
| 4 | difftool / pager = **delta**, not nvim | `.gitconfig:core.pager` | SAFE (not nvim at all) |
| 5 | nvim wrapper aliases (`vim`, `lvim`, `vm`, `rvim`, `vn`, suffix `md/txt/yaml`) | `.zsh_aliases` | SAFE (1 WATCH: `lvim`) |
| 6 | global alias `W` (pipe → markdown scratch nvim) | `.zsh_aliases:12` | WATCH (cosmetic) |
| 7 | tmux `M-Y` capture-pane → markdown popup nvim | `.tmux.conf:96` | WATCH (cosmetic) |
| 8 | tmux `M-l` lazygit `EDITOR=nvim`, `M-m`/`C-hjkl` vim-aware nav | `.tmux.conf:134,105-111` | SAFE |
| 9 | file-opener / sessionizer / grep-open / mprev scripts launching nvim | `scripts/__*.sh` | SAFE |
| 10 | Telescope **oldfiles** pickers | `telescope-setup.lua:233`, `telescope_enhanced.lua:134` | WATCH (shada/`/tmp`) |
| 11 | `__generate_prompt_from_task.py` markdown nvim | `scripts/...py:75` | WATCH (cosmetic) |
| 12 | Moonlander macro → `__restart_nvim.sh` → `lvim` | firmware (out of repo) | SAFE for 0.12; reflash = bucket B |
| 13 | GNOME custom shortcuts | gsettings media-keys | SAFE (verified absent) |
| 14 | autokey | `~/.config/autokey` | SAFE (no nvim refs / absent) |

---

## Top surprising couplings (the ones worth a second look)

**1. shada now excludes `/tmp` from `:oldfiles` — and this user lives in `/tmp` scratch
buffers.** The `vn` alias opens `/tmp/temp-$RANDOM.md`, the `W` global alias and `M-Y`
popup dump into `/tmp/...`, and `__orchestrator.sh` / `__gh_cli.sh` open `/tmp/*.txt` in
nvim. Post-0.12 these files **stop appearing** in the Telescope oldfiles picker
(`<leader>fo`, `telescope-setup.lua:233`) and the Alt+a enhanced oldfiles
(`telescope_enhanced.lua:134`), because both read `v:oldfiles` which now omits `/tmp`.
Low severity (scratch files are disposable), but it's a real, user-visible behavior shift
in a workflow this user actually uses. **WATCH.**

**2. `lvim` jumps to a mark, and `/tmp` mark persistence is now an open question.**
`alias lvim='nvim -c "normal '\''0"'` (`.zsh_aliases:109`) restores the last cursor via the
`'0` mark — and the Moonlander restart macro re-launches via `lvim`. The `'0` mark is
restored from shada. The documented 0.12 change is about `:oldfiles`; whether the same
`/tmp` exclusion also drops the numbered file-marks for `/tmp` files is **not established
by the release facts** and should be verified empirically, not asserted. **WATCH — open
question, not a confirmed break.** For non-`/tmp` files `lvim` is unaffected.

**3. Two gitconfigs both carry the fugitive mergetool — diffopt cosmetics land there.**
`[mergetool "fugitive"] cmd = nvim -f -c "Gvdiffsplit!"` exists in BOTH
`.gitconfig-personal` and `.gitconfig-work`. 0.12's new `diffopt` defaults
(`indent-heuristic`, `inline:char`) change how that merge view *renders*. It's an
interactive view a human reads; nothing parses it, and the git pager/difftool is **delta**
(not nvim), so no downstream tooling sees nvim diff output. **WATCH (cosmetic only).**

---

## Silent-default checklist — applicability to THIS user

| 0.12 silent default | Applies here? | Evidence |
|---|---|---|
| `'exrc'` now searches PARENT dirs for `.nvim.lua`/`.exrc` | **NO** | exrc never set: `grep exrc lua/` → none. Upward-search surprise cannot trigger. SAFE. |
| markdown treesitter highlighting ON by default | **YES, cosmetic** | Scratch buffers force `filetype=markdown`: `W` (`.zsh_aliases:12`), `M-Y` popup (`.tmux.conf:96`), `__generate_prompt_from_task.py:75`, `vn` (`/tmp/*.md`), suffix-alias `md=nvim`. All just gain highlighting. Only note: `M-Y` captures 3000 lines + `W` pipes arbitrary output → treesitter on a large non-markdown blob is a minor perf/visual WATCH. |
| `'diffopt'` += `indent-heuristic`, `inline:char` | **YES, cosmetic** | Touchpoint = fugitive mergetool in both gitconfigs. Interactive view only; pager/difftool = delta. No parser downstream. WATCH. |
| `'shada'` excludes `/tmp` & `/private` from `:oldfiles` | **YES** | Telescope oldfiles (`telescope-setup.lua:233`, `telescope_enhanced.lua:134`) + heavy `/tmp` scratch usage (`vn`, `W`, orchestrator, gh_cli). `/tmp` recents disappear. WATCH. |
| `'spellfile'` defaults to `stdpath('data')/site/spell/` | **NO** | Explicitly overridden: `global.lua:52` sets `stdpath('config').."/spell/en.utf-8.add"`. Default change mooted. SAFE. |
| `'smartcase'` applies to completion; `matchfuzzy()` uses fzy | **Negligible** | No external tooling depends on completion-filter casing or `matchfuzzy()` ordering. In-editor only. SAFE. |
| `stdpath("log")` → `stdpath("state")/logs`; `BufModifiedSet` removed | **NO external reader** | grep across dotfiles for `shada/oldfiles/stdpath.*log/nvim.log/BufModifiedSet` → only in-config hits. No script/tmux/git tool reads nvim's log or state path. SAFE. |

---

## Coverage notes (honest gaps)

- **GNOME custom shortcuts — VERIFIED ABSENT.** `gsettings` binary is present
  (`/usr/bin/gsettings`) and `org.gnome.settings-daemon.plugins.media-keys` returned no
  nvim/restart_nvim/alacritty-nvim reference. This is "checked, none found," not
  "couldn't check." SAFE.
- **autokey — absent / no refs.** No nvim references under `~/.config/autokey`.
- **Moonlander firmware — out of repo.** The macro calls `__restart_nvim.sh`, which only
  does `tmux send-keys :wq` then relaunches `lvim`. The **script needs nothing for 0.12**;
  it's purely a tmux/alias dance. Any reflash decision is owned by **bucket B**
  (`B-restart.md` already proposes removing the script in favor of native `:restart`);
  coordinate there. No system-wide action required from G.

## Bottom line

Ship 0.12 system-wide as-is. Optional follow-ups, all low priority:
1. If `/tmp` scratch files in oldfiles matter, add `set shada+=...` tuning — but the user
   may prefer the cleaner recents. Decision, not a fix.
2. Empirically confirm `lvim`'s `'0` mark still restores for `/tmp` files after 0.12.
3. Treesitter-on for the 3000-line `M-Y` popup: watch for lag on huge captures.
