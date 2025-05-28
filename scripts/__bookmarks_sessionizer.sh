#!/usr/bin/env bash

# Select bookmark and create/switch to tmux session
RESULT=$(cat ~/dev/dotfiles/scripts/__bookmarks.conf | fzf --header 'Bookmarks' --prompt 'bookmarks> ')

if [ -z "$RESULT" ]; then
  exit 0
fi

# Extract the path part after the semicolon
RESULT=$(echo "$RESULT" | cut -d ';' -f 2)

# Expand tilde to home directory
RESULT=$(echo "$RESULT" | sed -e "s|^~/|$HOME/|")

# Resolve symlinks to get the real path
REAL_PATH=$(readlink -f "$RESULT")

# Use file command to determine if it's a file or directory
FILE_TYPE=$(file -b "$REAL_PATH")

if [[ "$FILE_TYPE" == *"directory"* ]]; then
  # It's a directory
  FOLDER=$(basename "$REAL_PATH")
  SESSION_NAME=$(echo "$FOLDER" | tr ' ' '_' | tr '.' '_' | tr ':' '_')
  DIR_PATH="$REAL_PATH"
  IS_FILE=false
else
  # It's a file
  DIR_PATH=$(dirname "$REAL_PATH")
  FILE_NAME=$(basename "$REAL_PATH")
  SESSION_NAME=$(echo "$FILE_NAME" | tr ' ' '_' | tr '.' '_' | tr ':' '_')
  IS_FILE=true
fi

# Check if session already exists
if tmux list-sessions -F '#S' 2>/dev/null | grep -q "^$SESSION_NAME$"; then
  SESSION="$SESSION_NAME"
else
  SESSION=""
fi

if [ -z "$TMUX" ]; then                              # not currently in tmux
  if [ -z "$SESSION" ]; then                         # session does not exist
    if [ "$IS_FILE" = true ]; then
      tmux new-session -s "$SESSION_NAME" -c "$DIR_PATH" "nvim '$REAL_PATH'"
    else
      tmux new-session -s "$SESSION_NAME" -c "$DIR_PATH"
    fi
  else                                               # session exists
    tmux attach -t "$SESSION"
  fi
else                                                    # currently in tmux
  if [ -z "$SESSION" ]; then                            # session does not exist
    if [ "$IS_FILE" = true ]; then
      tmux new-session -d -s "$SESSION_NAME" -c "$DIR_PATH" "nvim '$REAL_PATH'"
      tmux switch-client -t "$SESSION_NAME"
    else
      tmux new-session -d -s "$SESSION_NAME" -c "$DIR_PATH"
      tmux switch-client -t "$SESSION_NAME"
    fi
  else                                                  # session exists
    tmux switch-client -t "$SESSION"
  fi
fi