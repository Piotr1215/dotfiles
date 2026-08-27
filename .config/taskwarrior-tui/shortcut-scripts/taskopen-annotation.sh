#!/usr/bin/env bash
# PROJECT: task-resume-annotations
# See: ~/.claude/commands/ops-annotate-task.md, ~/.claude/scripts/__taskopen_claude_resume.sh
# Issue: https://github.com/Piotr1215/claude/issues/42
# Opens annotations via taskopen
#
# Deliberately does nothing after taskopen. Tiling used to live here, which
# meant every annotation type rearranged the desktop, even a file opened in
# nvim. Each opener now owns its own layout: __taskopen_url_open.sh tiles
# browser + terminal for url/link/pr, __slack_open.sh tiles Slack beside the
# terminal, and file, note, brief and claude annotations leave the windows
# alone.
set -euo pipefail

taskopen "$1"
