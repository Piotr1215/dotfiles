#!/usr/bin/env bash

set -e

LOG="${HOME}/dotfiles.log"

process() {
  STEP=1
  echo "$(date) PROCESSING:  $@" >> $LOG
  printf "$(tput setaf 6) STEP:${STEP} %s...$(tput sgr0)\n" "$@"
  STEP=$((STEP+1))
}

process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"