#!/usr/bin/env bash
USE_POPUP=true
if [ "$1" = "--no-popup" ]; then
  USE_POPUP=false
  shift # Remove --no-popup from the argument list
fi

if [ "$1" = "-h" ] || [ "$1" == "--help" ]; then # help argument
  printf "\n"
  printf "\033[1m  sessionizer - simple tmux session manager\033[0m\n"
  printf "\n"
  exit 0
fi

tmux ls &>/dev/null
TMUX_STATUS=$?

get_fzf_prompt() {
  local fzf_prompt
  local fzf_default_prompt='>  '
  if [ $TMUX_STATUS -eq 0 ]; then # tmux is running
    fzf_prompt="$(tmux show -gqv '@t-fzf-prompt')"
  fi
  [ -n "$fzf_prompt" ] && echo "$fzf_prompt" || echo "$fzf_default_prompt"
}

HOME_REPLACER=""                                          # default to a noop
echo "$HOME" | grep -E "^[a-zA-Z0-9\-_/.@]+$" &>/dev/null # chars safe to use in sed
HOME_SED_SAFE=$?
if [ $HOME_SED_SAFE -eq 0 ]; then # $HOME should be safe to use in sed
  HOME_REPLACER="s|^$HOME/|~/|"
fi

BORDER_LABEL=" sessionizer - simple tmux session manager "
HEADER=" ctrl-s: sessions / ctrl-x: zoxide / ctrl-d: directory / ctrl-l: bookmarks"
PROMPT=$(get_fzf_prompt)
SESSION_BIND="ctrl-s:change-prompt(sessions> )+reload(tmux list-sessions -F '#S')"
ZOXIDE_BIND="ctrl-x:change-prompt(zoxide> )+reload(zoxide query -l | sed -e \"$HOME_REPLACER\")"

if fd --version &>/dev/null; then # fd is installed
  DIR_BIND="ctrl-d:change-prompt(directory> )+reload(cd $HOME && echo $HOME; fd --type d --hidden --absolute-path --color never --exclude .git --exclude node_modules)"
else # fd is not installed
  DIR_BIND="ctrl-d:change-prompt(directory> )+reload(cd $HOME && find ~+ -type d -name node_modules -prune -o -name .git -prune -o -type d -print)"
fi

# Bookmarks binding (Ctrl+l)
BOOKMARKS_BIND="ctrl-l:change-prompt(bookmarks> )+reload(cat ~/dev/dotfiles/scripts/__bookmarks.conf)"

if [ $# -eq 0 ]; then               # no argument provided
  if [ "$TMUX" = "" ]; then         # not in tmux
    if [ $TMUX_STATUS -eq 0 ]; then # tmux is running
      RESULT=$(
        (tmux list-sessions -F '#S' && (zoxide query -l | sed -e "$HOME_REPLACER")) | fzf \
          --bind "$DIR_BIND" \
          --bind "$SESSION_BIND" \
          --bind "$ZOXIDE_BIND" \
          --bind "$BOOKMARKS_BIND" \
          --border-label "$BORDER_LABEL" \
          --header "$HEADER" \
          --prompt "$PROMPT"
      )
    else # tmux is not running
      RESULT=$(
        (zoxide query -l | sed -e "$HOME_REPLACER") | fzf \
          --bind "$DIR_BIND" \
          --bind "$BOOKMARKS_BIND" \
          --border-label "$BORDER_LABEL" \
          --header " ctrl-d: directory / ctrl-l: bookmarks" \
          --prompt "$PROMPT"
      )
    fi
  elif $USE_POPUP; then # in tmux, and using popups
    RESULT=$(
      (tmux list-sessions -F '#S' && (zoxide query -l | sed -e "$HOME_REPLACER")) | fzf-tmux \
        --bind "$DIR_BIND" \
        --bind "$SESSION_BIND" \
        --bind "$ZOXIDE_BIND" \
        --bind "$BOOKMARKS_BIND" \
        --border-label "$BORDER_LABEL" \
        --header "$HEADER" \
        --prompt "$PROMPT" \
        -p 60%,50%
    )
  else # in tmux, but not using popups
    RESULT=$(
      (tmux list-sessions -F '#S' && (zoxide query -l | sed -e "$HOME_REPLACER")) | fzf \
        --bind "$DIR_BIND" \
        --bind "$SESSION_BIND" \
        --bind "$ZOXIDE_BIND" \
        --bind "$BOOKMARKS_BIND" \
        --border-label "$BORDER_LABEL" \
        --header "$HEADER" \
        --prompt "$PROMPT"
    )
  fi
else # argument provided
  zoxide query "$1" &>/dev/null
  ZOXIDE_RESULT_EXIT_CODE=$?
  if [ $ZOXIDE_RESULT_EXIT_CODE -eq 0 ]; then # zoxide result found
    RESULT=$(zoxide query "$1")
  else # no zoxide result found
    ls "$1" &>/dev/null
    LS_EXIT_CODE=$?
    if [ $LS_EXIT_CODE -eq 0 ]; then # directory found
      RESULT=$1
    else # no directory found
      echo "No directory found."
      exit 1
    fi
  fi
fi

if [ -z "$RESULT" ]; then
  exit 0
fi

# Check if the result is a bookmark entry (contains semicolon)
if [[ "$RESULT" == *";"* ]]; then
  # Extract the path part after the semicolon
  RESULT=$(echo "$RESULT" | cut -d ';' -f 2)
fi

if [ $HOME_SED_SAFE -eq 0 ]; then
  RESULT=$(echo "$RESULT" | sed -e "s|^~/|$HOME/|") # get real home path back
fi

zoxide add "$RESULT" &>/dev/null # add to zoxide database

# Resolve symlinks to get the real path
REAL_PATH=$(readlink -f "$RESULT")

# Debug mode - if DEBUG=1 is set, show extra information
if [ "${DEBUG:-0}" = "1" ]; then
  echo "Original path: $RESULT"
  echo "Real path: $REAL_PATH"
fi

# Use file command to determine if it's a file or directory
FILE_TYPE=$(file -b "$REAL_PATH")

if [ "${DEBUG:-0}" = "1" ]; then
  echo "File type: $FILE_TYPE"
fi

if [[ "$FILE_TYPE" == *"directory"* ]]; then
  # It's a directory
  FOLDER=$(basename "$REAL_PATH")
  SESSION_NAME=$(echo "$FOLDER" | tr ' ' '_' | tr '.' '_' | tr ':' '_')
  DIR_PATH="$REAL_PATH"
  IS_FILE=false
  
  if [ "${DEBUG:-0}" = "1" ]; then
    echo "Type: Directory"
    echo "Session name: $SESSION_NAME"
    echo "Directory path: $DIR_PATH"
  fi
else
  # It's a file
  DIR_PATH=$(dirname "$REAL_PATH")
  FILE_NAME=$(basename "$REAL_PATH")
  # Use the file name (with extension) for the session name, just like the directory case
  SESSION_NAME=$(echo "$FILE_NAME" | tr ' ' '_' | tr '.' '_' | tr ':' '_')
  IS_FILE=true
  
  if [ "${DEBUG:-0}" = "1" ]; then
    echo "Type: File"
    echo "Session name: $SESSION_NAME"
    echo "Directory path: $DIR_PATH"
    echo "File name: $FILE_NAME"
  fi
fi

# Git check happens in the original code below

# Check if we're in a git repo, just like the original code
if [ -d "$RESULT/.git" ]; then
  # Run git fetch origin --prune when working with a git repo
  echo "Running git fetch with prune for $RESULT"
  git -C "$RESULT" fetch origin --prune
  GIT_BRANCH=$(git -C "$RESULT" symbolic-ref --short HEAD 2>/dev/null)
  SESSION_NAME="$SESSION_NAME-$GIT_BRANCH"
fi

if tmux list-sessions -F '#S' | grep -q "^$SESSION_NAME$"; then
  SESSION="$SESSION_NAME"
else
  SESSION=""
fi

if [ -z "$TMUX" ]; then                              # not currently in tmux
  if [ -z "$SESSION" ]; then                         # session does not exist
    if [ "$IS_FILE" = true ]; then
      # Create a session in the directory and open the file in Neovim
      tmux new-session -s "$SESSION_NAME" -c "$DIR_PATH" "nvim '$REAL_PATH'"
    else
      tmux new-session -s "$SESSION_NAME" -c "$DIR_PATH" # create session and attach
    fi
  else                                               # session exists
    tmux attach -t "$SESSION"                        # attach to session
  fi
else                                                    # currently in tmux
  if [ -z "$SESSION" ]; then                            # session does not exist
    if [ "$IS_FILE" = true ]; then
      # Create a session in the directory and open the file in Neovim
      tmux new-session -d -s "$SESSION_NAME" -c "$DIR_PATH" "nvim '$REAL_PATH'"
      tmux switch-client -t "$SESSION_NAME"               # attach to session
    else
      tmux new-session -d -s "$SESSION_NAME" -c "$DIR_PATH" # create session
      tmux switch-client -t "$SESSION_NAME"               # attach to session
    fi
  else                                                  # session exists
    tmux switch-client -t "$SESSION"                    # switch to session
  fi
fi
