#!/usr/bin/env bash

set -eo pipefail

# Set new line and tab for word splitting
IFS=$'\n\t'

# Check if argument is provided
if [ $# -ne 1 ]; then
	echo "Usage: $0 <file/directory>"
	exit 1
fi

# Get absolute path of source
SOURCE=$(readlink -f "$1")
DOTFILES_DIR="$HOME/dev/dotfiles"

# Check if source exists
if [ ! -e "$SOURCE" ]; then
	echo "Error: $SOURCE does not exist"
	exit 1
fi

# Get relative path from home directory
REL_PATH=$(realpath --relative-to="$HOME" "$SOURCE")
DOTFILES_PATH="$DOTFILES_DIR/$REL_PATH"

# Check if already in dotfiles
if [ -e "$DOTFILES_PATH" ]; then
	echo "$REL_PATH already exists in dotfiles"
	exit 0
fi

# Create parent directories if needed
mkdir -p "$(dirname "$DOTFILES_PATH")"

# Move to dotfiles
mv "$SOURCE" "$DOTFILES_PATH"

# Use Stow to create the symlink
cd "$DOTFILES_DIR"
stow -v -t "$HOME" .

echo "Successfully added $REL_PATH to dotfiles and created symlink using Stow"
