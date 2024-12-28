#!/bin/bash

# Set the base directory
BASE_DIR="$HOME/.config/fabric"

# Function to copy files
copy_files() {
	local src="$1"
	local dst="$2"

	# Check if source directory exists
	if [ ! -d "$src" ]; then
		echo "Source directory $src does not exist. Skipping."
		return
	fi

	# Create destination directory if it doesn't exist
	mkdir -p "$dst"

	# Copy files, overwriting existing ones
	cp -R "$src"/* "$dst"

	echo "Copied contents from $src to $dst"
}

# Copy custom_patterns to patterns
copy_files "$BASE_DIR/custom_patterns" "$BASE_DIR/patterns"

# Copy custom_contexts to contexts
copy_files "$BASE_DIR/custom_contexts" "$BASE_DIR/contexts"

echo "Copy operation completed."
