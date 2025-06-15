#!/usr/bin/env bash
set -eo pipefail

# PROJECT: shortcuts
TEMP_FILE=$(mktemp)

load_shortcuts_from_yaml() {
    local yaml_file="/home/decoder/dev/dotfiles/shortcuts.yaml"
    
    if [[ ! -f "$yaml_file" ]]; then
        echo "Error: shortcuts.yaml not found" >&2
        return 1
    fi
    
    # Use Python to parse YAML (more reliable than yq for complex operations)
    python3 -c "
import yaml
import sys
import os

yaml_file = '$yaml_file'
if not os.path.exists(yaml_file):
    print(f'Error: YAML file not found at {yaml_file}', file=sys.stderr)
    sys.exit(1)

try:
    with open(yaml_file, 'r') as f:
        data = yaml.safe_load(f)
    
    for app, info in data.items():
        app_upper = app.upper()
        for shortcut in info['shortcuts']:
            print(f\"{app_upper} - {shortcut['description']} - {shortcut['binding']}\")
except Exception as e:
    print(f'Error loading YAML: {e}', file=sys.stderr)
    sys.exit(1)
    "
}

show_all_shortcuts() {
    load_shortcuts_from_yaml
}

show_categories() {
    local yaml_file="/home/decoder/dev/dotfiles/shortcuts.yaml"
    
    if [[ ! -f "$yaml_file" ]]; then
        echo "Error: shortcuts.yaml not found" >&2
        return 1
    fi
    
    # Use Python to parse YAML
    python3 -c "
import yaml
import sys
import os

yaml_file = '$yaml_file'
if not os.path.exists(yaml_file):
    print(f'Error: YAML file not found at {yaml_file}', file=sys.stderr)
    sys.exit(1)

try:
    with open(yaml_file, 'r') as f:
        data = yaml.safe_load(f)
    
    for app, info in data.items():
        app_upper = app.upper()
        print(f\"{app_upper} - {info['description']}\")
except Exception as e:
    print(f'Error loading YAML: {e}', file=sys.stderr)
    sys.exit(1)
    "
}

show_category_shortcuts() {
    local category="$1"
    show_all_shortcuts | grep "^${category} -"
}

handle_category_selection() {
    local category=$(show_categories | fzf \
        --delimiter=' - ' \
        --with-nth=1,2 \
        --preview='echo {} | awk -F" - " "{print \"Category: \" \$1 \"\nDescription: \" \$2}"' \
        --preview-window=up:2:wrap \
        --header='Select Category (Ctrl+C to exit, Ctrl+A for all shortcuts, Enter to browse category)' \
        --bind='ctrl-a:execute(echo "ALL_MODE" > '"$TEMP_FILE"')+abort' \
        --height=100% \
        --layout=reverse \
        --info=inline \
        --border=sharp \
        --prompt='📂 Categories: ' \
        --color='fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4')
    
    # Check if user pressed Ctrl+A to go back to all mode
    if [[ -f "$TEMP_FILE" && "$(cat "$TEMP_FILE")" == "ALL_MODE" ]]; then
        rm -f "$TEMP_FILE"
        handle_shortcut_selection
    elif [[ -n "$category" ]]; then
        local cat_name=$(echo "$category" | awk -F" - " '{print $1}')
        
        # Show shortcuts for selected category
        local selection=$(show_category_shortcuts "$cat_name" | fzf \
            --delimiter=' - ' \
            --with-nth=1,2,3 \
            --preview='echo {} | awk -F" - " "{print \"App: \" \$1 \"\nAction: \" \$2 \"\nShortcut: \" \$3}"' \
            --preview-window=up:3:wrap \
            --header="$cat_name Shortcuts (Ctrl+C to exit, Ctrl+A for all shortcuts, Ctrl+G for categories, Enter to open help)" \
            --bind='ctrl-a:execute(echo "ALL_MODE" > '"$TEMP_FILE"')+abort' \
            --bind='ctrl-g:execute(echo "CATEGORY_MODE" > '"$TEMP_FILE"')+abort' \
            --height=100% \
            --layout=reverse \
            --info=inline \
            --border=sharp \
            --prompt="🔍 $cat_name: " \
            --color='fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4')
        
        # Check what the user selected
        if [[ -f "$TEMP_FILE" ]]; then
            local mode=$(cat "$TEMP_FILE")
            rm -f "$TEMP_FILE"
            case "$mode" in
                "ALL_MODE")
                    handle_shortcut_selection
                    ;;
                "CATEGORY_MODE")
                    handle_category_selection
                    ;;
            esac
        elif [[ -n "$selection" ]]; then
            local app=$(echo "$selection" | awk -F" - " '{print tolower($1)}')
            echo "$app" > "$TEMP_FILE"
        fi
    fi
}

handle_shortcut_selection() {
    local selection=$(show_all_shortcuts | fzf \
        --delimiter=' - ' \
        --with-nth=1,2,3 \
        --preview='echo {} | awk -F" - " "{print \"App: \" \$1 \"\nAction: \" \$2 \"\nShortcut: \" \$3}"' \
        --preview-window=up:3:wrap \
        --header='App Shortcuts Help (Ctrl+C to exit, Ctrl+G for categories, Enter to open help)' \
        --bind='ctrl-g:execute(echo "CATEGORY_MODE" > '"$TEMP_FILE"')+abort' \
        --height=100% \
        --layout=reverse \
        --info=inline \
        --border=sharp \
        --prompt='🔍 Search: ' \
        --color='fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4')
    
    # Check if user pressed Ctrl+G for category mode
    if [[ -f "$TEMP_FILE" && "$(cat "$TEMP_FILE")" == "CATEGORY_MODE" ]]; then
        rm -f "$TEMP_FILE"
        handle_category_selection
    elif [[ -n "$selection" ]]; then
        # Extract the app name
        local app=$(echo "$selection" | awk -F" - " '{print tolower($1)}')
        echo "$app" > "$TEMP_FILE"
    fi
}

export -f handle_shortcut_selection
export -f handle_category_selection
export -f show_all_shortcuts
export -f show_categories
export -f show_category_shortcuts
export -f load_shortcuts_from_yaml
export TEMP_FILE

alacritty --class app-shortcuts-popup \
    --config-file /dev/null \
    -o window.dimensions.columns=120 \
    -o window.dimensions.lines=40 \
    -o window.position.x=1440 \
    -o window.position.y=660 \
    -e bash -c "handle_shortcut_selection"

if [[ -f "$TEMP_FILE" ]]; then
    app=$(cat "$TEMP_FILE")
    rm -f "$TEMP_FILE"
    
    if [[ -n "$app" ]]; then
        # Open help for the selected app
        case "$app" in
            mpv)
                if man mpv >/dev/null 2>&1; then
                    alacritty -e man mpv &
                else
                    alacritty -e bash -c "mpv --help 2>&1 | less" &
                fi
                ;;
            vim)
                alacritty -e vim -c ':help' -c ':only' &
                ;;
            tmux|tmuxinator)
                alacritty -e man tmux &
                ;;
            taskwarrior)
                if man task >/dev/null 2>&1; then
                    alacritty -e man task &
                else
                    alacritty -e bash -c "task help 2>&1 | less" &
                fi
                ;;
            moreutils)
                # Open moreutils man page or general info
                alacritty -e bash -c "man moreutils 2>/dev/null || echo 'Moreutils: Collection of additional Unix utilities' | less" &
                ;;
            *)
                # Generic handler - try man page first
                if man "$app" >/dev/null 2>&1; then
                    alacritty -e man "$app" &
                else
                    # Try --help flag
                    alacritty -e bash -c "$app --help 2>&1 | less" &
                fi
                ;;
        esac
    fi
fi
