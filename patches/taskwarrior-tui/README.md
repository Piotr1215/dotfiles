# Taskwarrior TUI rebuild

The patches in this directory are retired and kept for history. The rebuild script
clones `Piotr1215/taskwarrior-tui` main and does not apply them. Merge the fork
reconciliation before using the new rebuild path.

Run the Rust tests and build a release binary:

```sh
scripts/__build_taskwarrior_tui.sh
```

To install, run the same build and the isolated selection smoke test first. The
script backs up the current binary and replaces it only when both checks pass:

```sh
scripts/__build_taskwarrior_tui.sh --install
```

The script prints the fork commit, build source, binary and backup paths. Build
artifacts stay in `${XDG_CACHE_HOME:-$HOME/.cache}/taskwarrior-tui-build`;
backups stay in `${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tui/backups`.
Running views retain their old executable until restarted.

To exercise an existing binary with isolated tasks, a test hook and stub desktop
commands:

```sh
python3 tests/python/taskwarrior_tui_selection_smoke.py /path/to/taskwarrior-tui \
  --start-hook tests/fixtures/taskwarrior-tui/on-modify-handoff.py
```

The smoke test covers selection signals, uppercase S, and lowercase s start and
stop. A started row must only stop. A started `+piotr` row must preserve window
layout and focus, with `HANDOFF_SWITCH=1` suppressing stop navigation. A row
without a start attribute keeps its handoff action. The test does not touch the
live task database or running views.

The retired patches were based on upstream v0.27.0 (`aeb778f`) and captured
customizations from the fork and subsequent handoff changes. Fork main is now
the source of truth for those features and the Projects view.
