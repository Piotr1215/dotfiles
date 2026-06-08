#!/usr/bin/env bash

set -euo pipefail

nvim_appimage="nvim-linux-x86_64.appimage"

# Toggle release channel via first arg: "nightly" or "stable" (default).
channel="${1:-stable}"
case "$channel" in
  nightly) url="https://github.com/neovim/neovim/releases/download/nightly/${nvim_appimage}" ;;
  stable)  url="https://github.com/neovim/neovim/releases/latest/download/${nvim_appimage}" ;;
  *) echo "usage: $0 [nightly|stable]" >&2; exit 1 ;;
esac

curl -LO "$url"
chmod u+x "$nvim_appimage"
sudo mv "$nvim_appimage" /usr/local/bin/nvim
