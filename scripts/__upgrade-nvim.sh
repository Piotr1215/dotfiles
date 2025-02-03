#!/usr/bin/env bash

set -euo pipefail

# curl -LO https://github.com/neovim/neovim/releases/download/nightly/nvim.appimage
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage
chmod u+x nvim-linux-x86_64.appimage
sudo mv nvim-linux-x86_64.appimage /usr/local/bin/nvim

