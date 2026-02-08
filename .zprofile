export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export BROWSER=librewolf

# Hyprland ready on TTY3 - type 'hypr' to start, or it starts on first switch
if [[ "$(tty)" = "/dev/tty3" ]] && [[ -z "$WAYLAND_DISPLAY" ]]; then
    alias hypr='exec start-hyprland'
    echo "TTY3: Type 'hypr' to start Hyprland, or Ctrl+Alt+F2 for GNOME"
fi
