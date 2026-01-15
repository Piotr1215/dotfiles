#!/usr/bin/env bash
# PROJECT: task-resume-annotations
# See: ~/.claude/commands/ops-annotate-task.md, ~/.claude/scripts/__taskopen_claude_resume.sh
# Issue: https://github.com/Piotr1215/claude/issues/42
# Opens annotations via taskopen
set -euo pipefail

taskopen "$1"
