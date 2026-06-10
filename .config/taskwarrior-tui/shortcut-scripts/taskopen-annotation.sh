#!/usr/bin/env bash
# PROJECT: task-resume-annotations
# See: ~/.claude/commands/ops-annotate-task.md, ~/.claude/scripts/__taskopen_claude_resume.sh
# Issue: https://github.com/Piotr1215/claude/issues/42
# Opens annotations via taskopen
set -euo pipefail

taskopen "$1"

# After the annotation opens, split browser (left) + alacritty (right).
# `open` is async, so give the browser a moment to surface before tiling.
sleep 0.4
"$HOME/dev/dotfiles/scripts/__layouts.sh" 2 >/dev/null 2>&1 || true

# Focus the browser (Chrome for work, LibreWolf in timeoff mode).
if [[ -f /tmp/timeoff_mode ]]; then
	browser_wid=$(xdotool search --onlyvisible --classname Navigator 2>/dev/null | head -n1) || true
else
	browser_wid=$(wmctrl -l -x | grep google-chrome | head -n1 | awk '{print $1}') || true
fi
[[ -n "${browser_wid:-}" ]] && xdotool windowactivate "$browser_wid" >/dev/null 2>&1 || true
