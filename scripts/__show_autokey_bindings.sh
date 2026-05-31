#!/usr/bin/env bash

# Simple script to show all AutoKey key bindings
# Usage: __show_autokey_bindings.sh [--fzf]

set -eo pipefail

AUTOKEY_SCRIPTS_DIR="/home/decoder/dev/dotfiles/.config/autokey/data/Scripts"
AUTOKEY_DATA_DIR="/home/decoder/.config/autokey/data"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

show_bindings() {
    echo -e "${CYAN}AutoKey Keyboard Shortcuts${NC}"
    echo -e "${CYAN}=========================${NC}"
    echo
    
    cd "$AUTOKEY_SCRIPTS_DIR" || exit 1
    
    # Simple approach - just like the working jq command
    for f in .*.json; do
        [[ ! -f "$f" ]] && continue
        
        script="${f%.json}"
        script="${script#.}"
        
        # Skip if no .py file
        [[ ! -f "${script}.py" ]] && continue
        
        # Get hotkey
        hotkey=$(jq -r 'if .hotkey.hotKey then ((.hotkey.modifiers // [] | map(gsub("<|>"; "")) | join("+")) + "+" + .hotkey.hotKey) else "No hotkey" end' "$f" 2>/dev/null | sed 's/^+//')
        
        # Skip if no hotkey
        [[ "$hotkey" == "No hotkey" ]] && continue
        
        # Get description
        desc=$(jq -r '.description // ""' "$f" 2>/dev/null)
        [[ -z "$desc" ]] && desc="$script"
        
        echo -e "${GREEN}$hotkey${NC} → $desc"
    done | sort
    
    echo
}

show_bindings_fzf() {
    cd "$AUTOKEY_SCRIPTS_DIR" || exit 1
    
    for f in .*.json; do
        [[ ! -f "$f" ]] && continue
        
        script="${f%.json}"
        script="${script#.}"
        
        # Skip if no .py file
        [[ ! -f "${script}.py" ]] && continue
        
        # Get hotkey
        hotkey=$(jq -r 'if .hotkey.hotKey then ((.hotkey.modifiers // [] | map(gsub("<|>"; "")) | join("+")) + "+" + .hotkey.hotKey) else "No hotkey" end' "$f" 2>/dev/null | sed 's/^+//')
        
        # Skip if no hotkey
        [[ "$hotkey" == "No hotkey" ]] && continue
        
        # Get description
        desc=$(jq -r '.description // ""' "$f" 2>/dev/null)
        [[ -z "$desc" ]] && desc="$script"
        
        echo "$hotkey → $desc"
    done | sort | fzf --height=80% --border --header="AutoKey Shortcuts"
}

# List every ";;" abbreviation trigger (phrases AND scripts).
# Source of truth = AutoKey JSONs, so nothing is forgotten.
# The ";;?" discovery menu itself is excluded (don't list the opener).
collect_bangbang() {
    find "$AUTOKEY_DATA_DIR" -name '*.json' 2>/dev/null | while read -r f; do
        jq -r '(.description // "") as $d
               | (.abbreviation.abbreviations // [])[]
               | select(startswith(";;") and . != ";;?")
               | "\(.)\t→ \($d)"' "$f" 2>/dev/null
    done | sort -u
}

show_bangbang() {
    local out
    out=$(collect_bangbang | column -t -s$'\t')
    if [[ "${1:-}" == "--fzf" ]] && command -v fzf >/dev/null 2>&1; then
        echo "$out" | fzf --height=80% --reverse --border --header=";; commands"
    else
        echo -e "${CYAN}AutoKey ;; commands${NC}"
        echo -e "${CYAN}==================${NC}"
        echo "$out"
    fi
}

# Rofi version of the ;; list, for global (non-terminal) discovery.
# Prints the selected line; caller extracts the trigger (first field).
show_bangbang_rofi() {
    collect_bangbang | column -t -s$'\t' | rofi -dmenu -i -p ";;" \
        -theme-str '* {font: "JetBrainsMono Nerd Font 12";}' \
        -theme-str 'window {width: 700px; background-color: argb:ff282a36; border: 2px solid; border-color: argb:ffbd93f9; border-radius: 8px;}' \
        -theme-str 'mainbox {background-color: transparent;}' \
        -theme-str 'inputbar {background-color: argb:ff44475a; text-color: argb:fff8f8f2; padding: 8px;}' \
        -theme-str 'prompt {text-color: argb:ffbd93f9;}' \
        -theme-str 'entry {text-color: argb:fff8f8f2;}' \
        -theme-str 'listview {background-color: transparent; lines: 12;}' \
        -theme-str 'element {padding: 8px; background-color: transparent; text-color: argb:fff8f8f2;}' \
        -theme-str 'element.selected {background-color: argb:ff44475a; text-color: argb:ff50fa7b;}'
}

case "${1:-}" in
    --fzf)
        command -v fzf >/dev/null 2>&1 && show_bindings_fzf || echo "fzf not installed"
        ;;
    --bang)
        show_bangbang --fzf
        ;;
    --bang-plain)
        show_bangbang
        ;;
    --bang-rofi)
        show_bangbang_rofi
        ;;
    *)
        show_bindings
        ;;
esac