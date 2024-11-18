#!/bin/bash

# PROJECT: project_renamer
# __update_project_mappings.sh
#
# Purpose:
#   This script automatically updates a project mappings file for Taskwarrior projects.
#   It's designed to be called by a Taskwarrior hook when a task's project is changed.
#
# Usage:
#   __update_project_mappings.sh <new_project_name>
#
# Description:
#   When a new project is added in Taskwarrior, this script:
#   1. Checks if the project already exists in the mappings file.
#   2. If it's a new project, uses a Fabric CLI to generate a description.
#   3. Adds the new project and its description to the mappings file.
#
# The script maintains a file with project descriptions in the format:
#   declare -A project_descriptions=(
#       ["project_name"]="Project Description"
#   )
#
# Dependencies:
#   - jq (for JSON parsing in the calling hook script)
#
# File Locations:
#   - Project Mappings File: /home/decoder/dev/dotfiles/scripts/__project_mappings.conf
#   - This script: /home/decoder/dev/dotfiles/__update_project_mappings.sh
#
# Integration:
#   This script is called by the Taskwarrior hook:
#   ~/.task/hooks/on-modify.update-project-mappings

MAPPINGS_FILE="/home/decoder/dev/dotfiles/scripts/__project_mappings.conf"

# New project name passed as an argument
new_project="$1"

# Read the current content of the mappings file
current_content=$(cat "$MAPPINGS_FILE")

# Extract existing project names
existing_projects=$(grep -oP '(?<=\[")[^"]+(?="\])' "$MAPPINGS_FILE")

# Check if the new project already exists
if ! echo "$existing_projects" | grep -q "^$new_project$"; then

	# Transform new_project to have spaces and capitalized words
	new_description=$(echo "$new_project" | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g')

	# Remove the closing parenthesis from the current content
	updated_content="${current_content%)*}"

	# Add the new project with its description
	updated_content+="    $new_description"$'\n'

	# Add the closing parenthesis on a new line
	updated_content+=")"

	# Write the updated content to the file
	echo "$updated_content" >"$MAPPINGS_FILE"
fi
