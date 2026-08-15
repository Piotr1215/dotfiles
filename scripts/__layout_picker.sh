#!/usr/bin/env bash
# PROJECT: window-manager
set -eo pipefail

LAYOUTS_SCRIPT="$HOME/dev/dotfiles/scripts/__layouts.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/__lib_rofi_theme.sh"

# Detect running apps (wmctrl for accurate count including minimized)
count_browsers() {
    if [[ -f /tmp/timeoff_mode ]]; then
        wmctrl -l -x | grep -iE "librewolf|firefox|navigator" | wc -l
    else
        wmctrl -l -x | grep -iE "google-chrome" | wc -l
    fi
}
has_terminal() { wmctrl -l -x | grep -qi alacritty; }
has_slack() { wmctrl -l -x | grep -qi slack; }

# Build dynamic menu based on running apps
build_menu() {
    local browsers terminals slacks
    browsers=$(count_browsers)
    terminals=0; has_terminal && terminals=1
    slacks=0; has_slack && slacks=1

    local total=$((browsers + terminals + slacks))

    # Need at least 3 apps for this picker
    if [[ $total -lt 3 ]]; then
        echo "NOT_ENOUGH|0|"
        return
    fi

    local n=1
    # Generate valid 3-window combos
    # 2 browsers + terminal
    if [[ $browsers -ge 2 && $terminals -ge 1 ]]; then
        echo "$n. code: 󰖟 󰖟 ⌨|7|browser,browser,alacritty"
        ((n++))
    fi

    # browser + terminal + slack
    if [[ $browsers -ge 1 && $terminals -ge 1 && $slacks -ge 1 ]]; then
        echo "$n. chat: 󰒱 󰖟 ⌨|10|slack,browser,alacritty"
        ((n++))
    fi

    # slack + 2 browsers
    if [[ $slacks -ge 1 && $browsers -ge 2 ]]; then
        echo "$n. docs: 󰒱 󰖟 󰖟|11|slack,browser,browser"
        ((n++))
    fi

    # Generate valid 4-window combos
    # 2 browsers + terminal + slack
    if [[ $browsers -ge 2 && $terminals -ge 1 && $slacks -ge 1 ]]; then
        echo "$n. full: 󰖟 󰖟 ⌨ 󰒱|13|browser,browser,alacritty,slack"
    fi
}

# Show picker
menu_output=$(build_menu)

# Check if enough apps
if [[ "$menu_output" == "NOT_ENOUGH|0|" ]]; then
    notify-send "Layout Picker" "Need 3+ apps running (browsers, terminal, slack)"
    exit 0
fi

display_menu=$(echo "$menu_output" | cut -d'|' -f1)
# 900px/10, narrower than the shared default: layout names are short, and a
# window sized for file paths would be mostly empty here.
rofi_theme 900 10
selection=$(echo "$display_menu" | rofi -dmenu -i -p "Layout" -format 'i' -auto-select \
    "${ROFI_THEME[@]}")

[[ -z "$selection" || "$selection" == "-1" ]] && exit 0

# Get full line from menu using index
full_line=$(echo "$menu_output" | sed -n "$((selection + 1))p")
[[ -z "$full_line" ]] && exit 0
layout_num=$(echo "$full_line" | cut -d'|' -f2)

# Execute layout
"$LAYOUTS_SCRIPT" "$layout_num"
