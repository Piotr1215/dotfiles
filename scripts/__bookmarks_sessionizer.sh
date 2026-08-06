#!/usr/bin/env bash
set -eo pipefail

# Select bookmark and create/switch to tmux session

BOOKMARKS_FILE="${BOOKMARKS_FILE:-$HOME/dev/dotfiles/scripts/__bookmarks.conf}"

RESULT=$(fzf --header 'Bookmarks' --prompt 'bookmarks> ' < "$BOOKMARKS_FILE" || true)

if [ -z "$RESULT" ]; then
  exit 0
fi

# Extract the path and optional line number after the description.
RESULT=$(echo "$RESULT" | cut -d ';' -f 2-)
LINE_NUMBER=""
if [[ "$RESULT" =~ ^(.*)\;([0-9]+)$ ]]; then
  RESULT="${BASH_REMATCH[1]}"
  LINE_NUMBER="${BASH_REMATCH[2]}"
fi

# Expand tilde to home directory
RESULT="${RESULT/#\~\//$HOME/}"

# Resolve symlinks to get the real path
REAL_PATH=$(readlink -f "$RESULT")

# Stop before the type check. `file -b` on a missing path answers "cannot open
# ... (No such file or directory)", and that string contains the word directory,
# so a stale bookmark used to be treated as a folder and tmux was asked to open a
# session in a path that is not there.
if [ -z "$REAL_PATH" ] || [ ! -e "$REAL_PATH" ]; then
  echo "Bookmark does not resolve: $RESULT" >&2
  echo "Fix or remove it in $BOOKMARKS_FILE" >&2
  exit 1
fi

if [ -d "$REAL_PATH" ]; then
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

NVIM_COMMAND="nvim"
[ -z "$LINE_NUMBER" ] || NVIM_COMMAND="$NVIM_COMMAND +$LINE_NUMBER"
NVIM_COMMAND="$NVIM_COMMAND '$REAL_PATH'"

# Check if session already exists
if tmux list-sessions -F '#S' 2>/dev/null | grep -q "^$SESSION_NAME$"; then
  SESSION="$SESSION_NAME"
else
  SESSION=""
fi

if [ -z "$TMUX" ]; then                              # not currently in tmux
  if [ -z "$SESSION" ]; then                         # session does not exist
    if [ "$IS_FILE" = true ]; then
      tmux new-session -s "$SESSION_NAME" -c "$DIR_PATH" "$NVIM_COMMAND"
    else
      tmux new-session -s "$SESSION_NAME" -c "$DIR_PATH"
    fi
  else                                               # session exists
    tmux attach -t "$SESSION"
  fi
else                                                    # currently in tmux
  if [ -z "$SESSION" ]; then                            # session does not exist
    if [ "$IS_FILE" = true ]; then
      tmux new-session -d -s "$SESSION_NAME" -c "$DIR_PATH" "$NVIM_COMMAND"
      tmux switch-client -t "$SESSION_NAME"
    else
      tmux new-session -d -s "$SESSION_NAME" -c "$DIR_PATH"
      tmux switch-client -t "$SESSION_NAME"
    fi
  else                                                  # session exists
    tmux switch-client -t "$SESSION"
  fi
fi
