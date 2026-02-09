#!/usr/bin/env bash
# PROJECT: window-manager
set -eo pipefail

LAYOUTS_SCRIPT="$HOME/dev/dotfiles/scripts/__layouts.sh"

# Detect running apps (wmctrl for accurate count including minimized)
count_browsers() {
    wmctrl -l -x | grep -iE "librewolf|firefox|navigator" | wc -l
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
        echo "$n. chat: 󰒱 󰖟 ⌨|11|slack,browser,alacritty"
        ((n++))
    fi

    # slack + 2 browsers
    if [[ $slacks -ge 1 && $browsers -ge 2 ]]; then
        echo "$n. docs: 󰒱 󰖟 󰖟|12|slack,browser,browser"
        ((n++))
    fi

    # Generate valid 4-window combos
    # 2 browsers + terminal + slack
    if [[ $browsers -ge 2 && $terminals -ge 1 && $slacks -ge 1 ]]; then
        echo "$n. full: 󰖟 󰖟 ⌨ 󰒱|14|browser,browser,alacritty,slack"
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
selection=$(echo "$display_menu" | rofi -dmenu -i -p "Layout" -format 'i' -auto-select \
    -theme-str '* {font: "JetBrainsMono Nerd Font 12";}' \
    -theme-str 'window {width: 400px; background-color: argb:ff282a36; border: 2px solid; border-color: argb:ffbd93f9; border-radius: 8px;}' \
    -theme-str 'mainbox {background-color: transparent;}' \
    -theme-str 'inputbar {background-color: argb:ff44475a; text-color: argb:fff8f8f2; padding: 8px;}' \
    -theme-str 'prompt {text-color: argb:ffbd93f9;}' \
    -theme-str 'entry {text-color: argb:fff8f8f2;}' \
    -theme-str 'listview {background-color: transparent; lines: 6;}' \
    -theme-str 'element {padding: 8px; background-color: transparent; text-color: argb:fff8f8f2;}' \
    -theme-str 'element.selected {background-color: argb:ff44475a; text-color: argb:ff50fa7b;}')

[[ -z "$selection" || "$selection" == "-1" ]] && exit 0

# Get full line from menu using index
full_line=$(echo "$menu_output" | sed -n "$((selection + 1))p")
[[ -z "$full_line" ]] && exit 0
layout_num=$(echo "$full_line" | cut -d'|' -f2)

# Execute layout
"$LAYOUTS_SCRIPT" "$layout_num"
