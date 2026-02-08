#!/usr/bin/env bash
set -eo pipefail

# Port of autokey "CreateTask.py" for Wayland
# Uses wofi instead of zenity for project selection

projects=$(task _projects 2>/dev/null || true)
[[ -z "$projects" ]] && { notify-send "Task" "No projects found"; exit 0; }

description=$(zenity --entry --title="Task Description" --text="Enter task description:" --width=600 2>/dev/null) || exit 0
[[ -z "$description" ]] && exit 0

project=$(echo "$projects" | wofi --dmenu --prompt "Project" 2>/dev/null) || exit 0
[[ -z "$project" ]] && exit 0

tag="+work"
[[ "$project" == home* ]] && tag="+home"

~/dev/dotfiles/scripts/__create_task.sh "$description" "$tag" "project:$project"
notify-send "Task" "Created: $description ($project)"
