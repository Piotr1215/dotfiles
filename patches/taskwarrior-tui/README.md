# Twoy handoff selection

This patch set preserves the installed 0.27.0 customizations, then adds the selected
task signal and uppercase S for handoffs. Uppercase S adds navigation before
normal key dispatch, preserving explicit key remaps. It does not start tasks
with the default bindings. Tmux prefix S retains its existing behavior.

Lowercase s still starts or stops the task through Taskwarrior. The existing
`~/.task/hooks/on-modify-openurl-or-program.py` hook, tracked in the separate
`~/.task` repository, sends a new `+piotr` start to the same navigation helper
once. Its other description actions remain unchanged for non-handoff tasks.

Sources:

- Upstream `kdheepak/taskwarrior-tui` tag `v0.27.0`, commit
  `aeb778fae3c7b1a5c29d0f9b4cc2febfe09797d6`.
- Existing customizations: `Piotr1215/taskwarrior-tui`, commit
  `114c6142cac27aed8f85ea1d68387ff3aaf73744`. Its release binary exactly matched
  the installed binary before this change (SHA256
  `62fb17cebcd0201785ac815552c67fca6dcdcdd940cda969606c060336144a97`).
- Patch 0001 contains that source delta, excluding GitHub automation. Patch 0002
  contains the handoff integration: `git diff da49d34 db1294e` in the fork
  (selection signal, S, the b brief key with row placement, Tab to the brief),
  excluding GitHub automation. The freshly fetched fork main at `da49d34` has the
  same source tree as `114c614`.

| Trigger | Reads | Writes | Failure behavior |
| --- | --- | --- | --- |
| Selection changes or report refresh, after the draw | Current task UUID and its drawn screen row | Atomic `<uuid> <row>` line in the runtime signal file | Missing runtime directory or filesystem error must not stop the UI |
| Selected report becomes empty | Current report | Remove stale selection signal | No stale task should remain selected |
| Uppercase S on a `+piotr` task | Selected UUID | Queue `__handoff_navigate.sh` with UUID as one argument | Existing background command error reporting |
| Uppercase S on another task | Task tags | None | Preserve no-op |
| Lowercase s starts a `+piotr` task | Existing start hook and selected UUID | Launch the same helper once | Skip legacy description openers for this event; retain hook JSON output |
| Rebuild and install | Pinned source and both patches | Tested release binary and backup of old binary | Failed tests prevent installation |

The signal directory is `$XDG_RUNTIME_DIR/taskwarrior-tui`, mode 0700. The filename
is `selected-${TMUX_PANE#%}`, or `selected` without a tmux pane. Unchanged selections
do not rewrite the file. The floater owns whether it observes this signal while
visible; the TUI does not launch a poller or change focus.

Build and run upstream plus patch tests:

```sh
scripts/__build_taskwarrior_tui.sh
```

Install after the tests pass, backing up the executable found by
`command -v taskwarrior-tui` first:

```sh
scripts/__build_taskwarrior_tui.sh --install
```

The script prints the build source, binary and backup paths. Build artifacts stay
in `${XDG_CACHE_HOME:-$HOME/.cache}/taskwarrior-tui-build`; backups stay in
`${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tui/backups`. Existing running
views keep the old executable until they restart.

Acceptance: UUIDs match j/k and paging; refresh follows the selected task rather
than a row number; empty reports clear the signal; patch and upstream tests pass;
installation preserves a verified backup.

Exercise the installed binary with isolated tasks and a stub navigation helper:

```sh
python3 tests/python/taskwarrior_tui_selection_smoke.py "$(command -v taskwarrior-tui)" \
  --start-hook "$HOME/.task/hooks/on-modify-openurl-or-program.py"
```

This covers S without starting a task, lowercase s start/stop through a copy of
the real hook, and the selection checks above. It leaves Piotr's running views
and task database untouched.
