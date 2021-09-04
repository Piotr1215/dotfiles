#!/usr/bin/env bash

set -e

LOG="${HOME}/dotfiles.log"

process() {
  echo "$(date) PROCESSING:  $@" >> $LOG
  printf "$(tput setaf 6) [STEP ${STEP:-0}] %s...$(tput sgr0)\n" "$@"
  STEP=$((STEP+1))
}

process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"
process "→ Creating directory at ${LOG} and setting permissions"