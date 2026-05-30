# B — Replace custom nvim restart with native `:restart` (0.12)

## VERDICT: GO

Native `:restart` (ships in 0.12, default mapping `ZR`) fully replaces the custom
tmux-respawn script and does it better. Delete the script. No nvim keymap change is
needed (`ZR` is built in). The only manual step lives outside the repo: reflash the
Moonlander macro.

### Worth it?
**GO.** The script is a workaround for a capability nvim lacked until 0.12: restarting
the editor in place. 0.12 provides exactly that natively, in-process, with no tmux
dependency, no sleep/race, and optional full session restore.

### What's lost
**Nothing of value — and you gain capability.** The script does NOT do session
save/restore. Its entire "restoration" is relaunching as `lvim`, an alias that opens
nvim and jumps to the last edit position via the `'0` shada mark (one file).

| Behavior | Script (`__restart_nvim.sh`) | Native `:restart` |
|---|---|---|
| Save before quit | Forces `:wq` (current buffer only) | `:restart` runs `:qall`, **aborts if any buffer is dirty** (does not auto-save) |
| Force / discard | n/a (always force-saves) | `:restart +qall!` discards; `ZR` with a count = force (`[count]ZR`) |
| Buffer/layout restore | One file via `'0` mark (shada) | None by default, BUT supports full session restore via `[command]` |
| Requires tmux | Yes (`exit 1` if `$TMUX` unset) | No |
| Mechanism | Detached nohup + `sleep 0.5` respawn of tmux pane | In-process, UIs re-attach to fresh server |

Net regression risk: the only thing the script auto-did that `ZR` alone does not is
**save-on-restart**. Trivially preserved by sending `:wa` first (see steps). And the
`'0` last-position jump is superseded — `:restart` can restore the *entire* session,
not just one file.

### What conflicts
- **Stale memory note.** The note "called from moonlander macro via nvim keybinding
  `<leader>-`" is WRONG on the nvim binding. `<leader>-` is bound to **Yazi**
  (`plugins.lua:85-88`, `"<cmd>Yazi<cr>"`). **No nvim keymap triggers the restart
  script.** Grep across the whole repo finds zero callers of `__restart_nvim.sh` — its
  sole consumer is the Moonlander firmware macro. Correct the memory note.
- No keymap conflict with `ZR` in this config (no existing `ZR` mapping found).

---

## Evidence (file:line)

- **Script** — `scripts/__restart_nvim.sh`:
  - `:9-12` hard-requires `$TMUX` or exits 1.
  - `:14-16` grabs pane id, sends `:wq` (force-save current buffer + quit).
  - `:18` `sleep 0.5`; `:22` detached `nohup` respawns the pane running `lvim`.
- **`lvim` alias** — `.zsh_aliases:109`: `alias lvim='nvim -c "normal '\''0"'`
  → plain nvim that jumps to the `'0` mark (last edit position). This is the script's
  entire "restore" mechanism.
- **No nvim caller** — repo-wide grep for `restart_nvim` / `RestartNvim` returns only
  a comment in the script itself.
- **`<leader>-` is Yazi** — `lua/plugins.lua:85-88`.
- **Native `:restart` semantics** — installed `:help :restart` (gui.txt):
  - Step 1: stops via `:qall` (or `+cmd`) → aborts on unsaved changes.
  - Step 2: restarts with same `v:argv` **except file args** (no buffer reopen).
  - Step 3: attaches UIs to new server, runs optional `[command]`.
  - Doc's own session-restore recipe: `:mksession! Session.vim | restart source Session.vim`.
  - Caveat: "Only works if the UI and server are on the same system" (fine for TUI).
- **`ZR` default mapping** — `:help ZR`: `[count]ZR` performs `:restart`; a count
  restarts without checking for changes (`:restart +qall!`).

---

## Migration steps

### 1. Delete the script (in repo)
Remove `scripts/__restart_nvim.sh`. Also drop the `# PROJECT: nvim-restart` reference
and the stale memory note pointing at it.

### 2. nvim keymap — nothing required
`ZR` ships built-in in 0.12. No edit to `mappings.lua`/`plugins.lua` needed.

Optional polish — if you want save-before-restart bound inside nvim (to mirror the
script's old `:wq` behavior in one keystroke), add a thin user mapping, e.g.:

```lua
-- save all, then native restart
vim.keymap.set("n", "<leader>R", "<cmd>wa<bar>restart<cr>", { desc = "Save all + restart nvim" })
```

For full session restore on restart (better than the old `'0` jump):

```lua
vim.keymap.set("n", "<leader>R",
  "<cmd>mksession! /tmp/nvim-restart.vim | restart source /tmp/nvim-restart.vim<cr>",
  { desc = "Restart nvim, restore session" })
```

Recommendation: keep it minimal — rely on `ZR`, skip the custom mapping unless you
miss auto-save.

### 3. Moonlander firmware (OUTSIDE the repo — manual reflash)
The macro currently drives the tmux respawn (types the script path or replays its
keystrokes). The firmware is opaque and not in this repo, so this is a manual change
in Oryx/QMK, then reflash.

Replace whatever the macro sends with one of:
- **`ZR`** (normal mode) — simplest; aborts if buffers are dirty (safe).
- **`:wa<CR>:restart<CR>`** — to preserve the old save-first behavior.
- **type a count then `ZR`** (e.g. `1ZR`) — force restart, discard changes.

Pick `:wa<CR>:restart<CR>` to most closely match the deleted script's "save and
restart" semantics.

---

## Top bottlenecks / watch-outs
1. **Moonlander macro is the real work** — it's outside the repo; deleting the script
   without reflashing leaves the macro firing a missing command. Sequence: reflash
   first (or simultaneously), then delete.
2. **`:restart` aborts on unsaved buffers** unlike the old force-`:wq`. Use
   `:wa<CR>:restart<CR>` in the macro if you relied on auto-save.
3. **Lost `'0` jump** is cosmetic and superseded by optional `mksession` restore;
   without it, restart opens a bare nvim (no file). Add the session mapping if the
   last-file jump mattered.
4. **Correct the stale memory note** (`<leader>-` ≠ restart; it's Yazi).
