# Area E — ui2 / extui (experimental new UI)

Scope: decide whether to enable Neovim 0.12's experimental `vim._extui` ("ui2")
and flag conflicts with existing message/cmdline/notification plugins.
Read-only audit of `/home/decoder/dev/dotfiles/.config/nvim`.

---

## VERDICT: NO-GO (lean WAIT until it ships as default)

Do **not** enable `vim._extui` in this config now.

Two reasons, in order of weight:

1. **Direct cmdline conflict.** This config runs `mini.cmdline` — actively
   `.setup{}`-configured at `lua/settings/plugins-setup.lua:287`. ui2 replaces
   the cmdline rendering itself; both would fight to own the cmdline UI. ui2
   gives you nothing here that `mini.cmdline` (cmdline highlighting/peek) isn't
   already providing.
2. **Notify override conflict.** `vim.notify` is globally replaced with
   nvim-notify at `lua/settings/plugins-setup.lua:2`
   (`vim.notify = require "notify"`). ui2's whole selling point is routing
   messages/notifications into a normal scrollable/yankable buffer. With
   nvim-notify owning `vim.notify`, ui2's message handling overlaps and the two
   message surfaces collide.

The premise in the brief — "if the user runs noice.nvim, ui2 is redundant" —
**does not apply**: there is no noice.nvim in this config (grep across `lua/`
returns zero hits). So ui2 isn't redundant-vs-noice; it's conflicting-vs the
user's own hand-rolled stack (`mini.cmdline` + nvim-notify). Same conclusion,
different cause.

Add experimental status on top: `vim._extui` is opt-in and explicitly
experimental in 0.12 (underscore-namespaced internal module, API can change
between point releases). Not worth wiring into a daily-driver config that
already solves the same problems.

---

## What's LOST by not enabling it

Honest accounting — these are the things ui2 would have given, that you forgo:

- **No "Press ENTER to continue" elimination.** BUT — see below, this config
  does **not** currently suffer the classic hl-Press-ENTER pain the way a bare
  config would, because `cmdheight = 1` (`lua/settings/global.lua:69`) is the
  normal default and there's no aggressive message squashing. The prompt
  appears only on genuinely long `:messages`-style output. This is a minor loss.
- **No message pager as a yankable buffer.** You can't yank from the message
  area as if it were a normal buffer. Mitigation already in the toolbox:
  `:messages` + existing telescope/yank flows.
- **No built-in cmdline highlighting from core.** Already covered by
  `mini.cmdline` (`autopeek = true`, `lua/settings/plugins-setup.lua:287-294`).
- **No core Progress-message surface** (`nvim_echo()` progress / new default
  statusline diagnostics+progress). You keep lualine instead (see below).

Net: the only real loss is the yankable message buffer. Everything else is
already provided by `mini.cmdline` and nvim-notify.

---

## Conflicts — exact plugins (named) and file:line

| Plugin / setting | Where | Conflicts with ui2? | Why |
|---|---|---|---|
| **mini.cmdline** | declared `lua/plugins.lua:137`; `.setup{}` `lua/settings/plugins-setup.lua:287` | **YES — direct** | Both own the cmdline UI. Mutually exclusive. |
| **nvim-notify** (`vim.notify` override) | declared `lua/plugins.lua:132`; override `lua/settings/plugins-setup.lua:2` | **YES — overlap** | ui2 routes notifications to its message buffer; nvim-notify already owns `vim.notify`. |
| **dressing.nvim** | `lua/plugins.lua:112` | No | dressing handles `vim.ui.select`/`vim.ui.input` only; ui2 does not touch those. Safe either way. |
| **lualine.nvim** (active statusline) | declared `lua/plugins.lua:436`; `.setup{}` `lua/settings/plugins-setup.lua:591` | No (but note) | ui2 doesn't replace the statusline. The 0.12 *default* statusline w/ diagnostics+progress is irrelevant because lualine overrides it (`diagnostics` already in `lualine_b`, `lua/settings/plugins-setup.lua:598`). |
| **noice.nvim** | — | N/A | **Not present.** Zero hits in `lua/`. |
| **fidget.nvim** | — | N/A | **Not present.** Zero hits in `lua/`. |

Active statusline = **lualine** (`lua/settings/plugins-setup.lua:591`), with
`laststatus = 2` and `cmdheight = 1` (`lua/settings/global.lua:68-69`).

---

## If you ever DO adopt ui2 (don't, yet) — the one-liner + what to disable

Enable (confirm exact path against `:help vim._extui` first):

```lua
require('vim._extui').enable({})
```

To adopt without breakage you would have to **disable**:

- `mini.cmdline` — remove the `.setup{}` at `lua/settings/plugins-setup.lua:287`
  and the spec at `lua/plugins.lua:137` (otherwise double cmdline).
- The nvim-notify `vim.notify` override at `lua/settings/plugins-setup.lua:2`
  (let ui2 handle messages, or keep notify only for transient toasts — pick one
  owner, not both).

You could keep dressing.nvim and lualine as-is.

---

## What to KEEP (the NO-GO path — recommended)

Change nothing. Keep all of:

- `mini.cmdline` (`lua/settings/plugins-setup.lua:287`) — your cmdline UX.
- nvim-notify `vim.notify` override (`lua/settings/plugins-setup.lua:2`).
- dressing.nvim (`lua/plugins.lua:112`).
- lualine (`lua/settings/plugins-setup.lua:591`), `cmdheight = 1`
  (`lua/settings/global.lua:69`), `laststatus = 2` (`:68`).

Revisit when ui2 becomes the Neovim default (later release) and the
experimental flag is dropped. At that point re-evaluate whether to retire
`mini.cmdline` + nvim-notify in favor of core ui2 to shed two plugins.

---

## Stability risk (flagged)

- `vim._extui` is **experimental** and **internal** (leading underscore). API
  surface and enable path may change between 0.12 point releases — fragile to
  pin a daily config to.
- Enabling it alongside `mini.cmdline` / nvim-notify risks duplicated or
  swallowed messages and a fought-over cmdline — hard-to-debug UI glitches, not
  clean errors.
- Confirm the exact enable call against the LOCAL `:help news-0.12` /
  `:help vim._extui` before trusting `require('vim._extui').enable({})`.
