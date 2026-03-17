export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
if [[ -f /tmp/timeoff_mode ]]; then
    export BROWSER=librewolf
else
    export BROWSER=google-chrome
fi
