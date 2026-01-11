#!/usr/bin/env bash
set -eo pipefail

path=$(~/dev/dotfiles/scripts/__extract_path_from_fzf.sh "$1")

printf '%s' "$path" | xsel --clipboard --input
