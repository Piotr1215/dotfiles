export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
# The launcher reads the ufp mode on every open; a fixed browser here would go
# stale in every shell the moment ufp switches modes.
export BROWSER="$HOME/dev/dotfiles/scripts/__open_browser.sh"
