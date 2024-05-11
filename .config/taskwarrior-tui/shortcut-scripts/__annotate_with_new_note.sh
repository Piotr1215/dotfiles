#!/usr/bin/env bash

# UUID of the task to annotate
uuid="$@"

# Directory where notes are stored
notes_dir="/home/decoder/dev/obsidian/decoder/Notes/projects"
templates_dir="/home/decoder/dev/obsidian/decoder/Templates"

# Prompt for the new note name
read -p "Enter the name for the new note: " new_note_name
copy_note="$templates_dir/projects.md"
filepath="$notes_dir/$new_note_name.md"

# Check if file with this name already exists
if [ -f "$filepath" ]; then
	echo "File with this name already exists. Annotating the task with the existing note."
else
	nvim -n -c "ObsidianNew $new_note_name" --headless >/dev/null 2>&1 &
	cp "$copy_note" "$filepath"
	echo "New note created and opened in Neovim."
fi

# Annotate the task with the filepath
task_output=$(task rc.bukl=0 rc.confirmation=off "$uuid" annotate "$filepath")

# Check if annotation was successful
if [[ "$task_output" == *"Annotated"* ]]; then
	echo "Successfully annotated the task with the note."
else
	echo "Failed to annotate the task."
fi

nvim "$filepath"
