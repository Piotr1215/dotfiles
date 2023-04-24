#!/usr/bin/env bash

set -euo pipefail

curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
# curl -LO https://github.com/neovim/neovim/releases/download/nightly/nvim.appimage
sudo chmod u+x nvim.appimage
sudo mv nvim.appimage /usr/local/bin/nvim
