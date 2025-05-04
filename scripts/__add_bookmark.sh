#!/usr/bin/env bash
set -eo pipefail

# Script to add a bookmark to the bookmarks file

BOOKMARKS_FILE="$HOME/dev/dotfiles/scripts/__bookmarks.conf"

# Function to show usage
show_usage() {
  echo "Usage: __add_bookmark.sh [OPTIONS] <path>"
  echo "Add a bookmark to the bookmarks file."
  echo ""
  echo "Options:"
  echo "  -d, --description DESCRIPTION    Description for the bookmark (required)"
  echo "  -h, --help                      Display this help message"
  echo ""
  echo "Example:"
  echo "  __add_bookmark.sh -d \"My Config\" ~/.config/my-app.conf"
  echo "  __add_bookmark.sh --description \"Project Folder\" ~/dev/my-project"
  exit 1
}

# Parse arguments
DESCRIPTION=""
FILE_PATH=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--description)
      DESCRIPTION="$2"
      shift 2
      ;;
    -h|--help)
      show_usage
      ;;
    *)
      FILE_PATH="$1"
      shift
      ;;
  esac
done

# Validate input
if [ -z "$DESCRIPTION" ]; then
  echo "Error: Description is required. Use -d or --description option."
  show_usage
fi

if [ -z "$FILE_PATH" ]; then
  echo "Error: Path is required."
  show_usage
fi

# Expand path if it starts with ~
if [[ "$FILE_PATH" == ~* ]]; then
  FILE_PATH="${FILE_PATH/#\~/$HOME}"
fi

# Check if the path exists
if [ ! -e "$FILE_PATH" ]; then
  echo "Error: Path does not exist: $FILE_PATH"
  exit 1
fi

# Convert to absolute path
FILE_PATH=$(realpath "$FILE_PATH")

# Check if bookmark already exists
if grep -q "^.*;$FILE_PATH$" "$BOOKMARKS_FILE"; then
  echo "Warning: Bookmark for this path already exists."
  grep "^.*;$FILE_PATH$" "$BOOKMARKS_FILE"
  read -p "Update description? (y/n): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Remove existing entry
    sed -i "\#^.*;$FILE_PATH\$#d" "$BOOKMARKS_FILE"
  else
    echo "Operation cancelled."
    exit 0
  fi
fi

# Add bookmark
echo "$DESCRIPTION;$FILE_PATH" >> "$BOOKMARKS_FILE"
echo "Bookmark added: $DESCRIPTION -> $FILE_PATH"

# Sort the bookmarks file alphabetically by description
sort -f "$BOOKMARKS_FILE" -o "$BOOKMARKS_FILE"

echo "Bookmarks file updated and sorted."
echo ""
echo "To use this bookmark in a tmux session, run:"
echo "  __sessionizer.sh  # and press Ctrl+L to access bookmarks"
echo ""
echo "To debug issues with bookmarks, set DEBUG environment variable:"
echo "  DEBUG=1 __sessionizer.sh  # for detailed information"