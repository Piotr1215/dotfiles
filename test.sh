#!/usr/bin/env bash

set -e

LOG="${HOME}/dotfiles.log"

process() {
  echo "$(date) PROCESSING:  $@" >> $LOG
  printf "$(tput setaf 6) %s...$(tput sgr0)\n" "$@"
}

process "→ Creating directory at ${DIR} and setting permissions"