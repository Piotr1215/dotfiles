#!/usr/bin/env bash

# Simple script to show all AutoKey key bindings
# Usage: __show_autokey_bindings.sh [--fzf]

set -eo pipefail

AUTOKEY_SCRIPTS_DIR="/home/decoder/dev/dotfiles/.config/autokey/data/Scripts"

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

case "${1:-}" in
    --fzf)
        command -v fzf >/dev/null 2>&1 && show_bindings_fzf || echo "fzf not installed"
        ;;
    *)
        show_bindings
        ;;
esac