#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

themes_folder="$HOME/.config/alacritty/themes/"
config_file="$HOME/.config/alacritty/alacritty.toml"

preview_theme() {
	sed -i "s|^import = \[.*\]|import = [\"$themes_folder$1\"]|g" "$config_file"
	echo "Previewing: $1"
}

export -f preview_theme
export themes_folder config_file

tree "$themes_folder" -i | head -n-2 | tail -n+2 |
	fzf --preview 'bash -c "preview_theme {}"' \
		--bind 'ctrl-n:down+change-preview:bash -c "preview_theme {}"' \
		--bind 'ctrl-p:up+change-preview:bash -c "preview_theme {}"' \
		--bind 'up:up+change-preview:bash -c "preview_theme {}"' \
		--bind 'down:down+change-preview:bash -c "preview_theme {}"' \
		--header "Use up/down or ctrl-p/n to preview themes. Press enter to select."
