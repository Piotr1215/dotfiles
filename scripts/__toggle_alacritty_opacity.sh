#!/usr/bin/env bash
set -euo pipefail
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
IFS=$'\n\t'

# PROJECT: alacritty_transparency
config_file="$HOME/.config/alacritty/alacritty.toml"

# Toggle Alacritty opacity
current_opacity=$(grep 'opacity = ' "$config_file" | cut -d'=' -f2 | tr -d ' ')

case "$current_opacity" in
0.7)
	sed -i 's/opacity = .*/opacity = 1.0/' "$config_file"
	# When going opaque, set dark backgrounds
	tmux set-window-option -g window-active-style 'bg=#000000'
	tmux set-window-option -g window-style 'bg=#0B0B0B'
	;;
1.0 | *)
	sed -i 's/opacity = .*/opacity = 0.7/' "$config_file"
	# When going transparent, set default backgrounds
	tmux set-window-option -g window-active-style 'bg=default'
	tmux set-window-option -g window-style 'bg=default'
	;;
esac
