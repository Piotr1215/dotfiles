#!/usr/bin/env bash
#
# dfind - Dotfiles Navigator: Unified search across your entire dotfiles ecosystem
#
# A beautiful, fast command palette for discovering and using:
# - Scripts, aliases, functions, abbreviations, shortcuts
# - With live previews, usage stats, and instant actions
#
# Usage: dfind [query]
#
# Keybindings:
#   Enter    - Execute script or copy command to clipboard
#   Ctrl-E   - Edit the source file in $EDITOR
#   Ctrl-Y   - Copy to clipboard (without executing)
#   Ctrl-O   - Show detailed info/documentation

set -euo pipefail

# Colors for output
readonly COLOR_SCRIPT="\033[38;5;81m"    # Cyan
readonly COLOR_ALIAS="\033[38;5;220m"    # Yellow
readonly COLOR_FUNCTION="\033[38;5;141m" # Purple
readonly COLOR_ABBREV="\033[38;5;114m"   # Green
readonly COLOR_SHORTCUT="\033[38;5;213m" # Pink
readonly COLOR_RESET="\033[0m"

# Dotfiles directory
DOTFILES_DIR="${HOME}/dotfiles"
SCRIPTS_DIR="${DOTFILES_DIR}/scripts"

# Temp file for collected data
TEMP_DATA=$(mktemp)
trap 'rm -f "$TEMP_DATA"' EXIT

# Function to extract description from script files
extract_script_description() {
    local file="$1"
    local name=$(basename "$file")
    local desc=""

    # Try to find description in first 20 lines (after shebang)
    # Look for: "# Description: ...", or first "# ..." comment, or inline comment in function
    desc=$(sed -n '2,20p' "$file" | grep -m1 -E "^#[[:space:]]+(Description:|.*)" | sed 's/^#[[:space:]]*Description:[[:space:]]*//; s/^#[[:space:]]*//' || echo "")

    if [[ -z "$desc" ]]; then
        desc="Script: $name"
    fi

    echo "$desc"
}

# Function to get usage count from shell history
get_usage_count() {
    local cmd="$1"
    local count=0

    if [[ -f "${HOME}/.zsh_history" ]]; then
        # Search in zsh history (format: : timestamp:0;command)
        count=$(grep -c "$cmd" "${HOME}/.zsh_history" 2>/dev/null || echo 0)
    fi

    echo "$count"
}

# Collect scripts
collect_scripts() {
    if [[ ! -d "$SCRIPTS_DIR" ]]; then
        return
    fi

    while IFS= read -r script; do
        [[ ! -x "$script" ]] && continue

        local name=$(basename "$script")
        local desc=$(extract_script_description "$script")
        local usage=$(get_usage_count "$name")

        printf "[SCRIPT]|%s|%s|%s|%s\n" "$name" "$desc" "$script" "$usage"
    done < <(find "$SCRIPTS_DIR" -maxdepth 1 -type f -name "*.sh" -o -name "*.py" -o -name "*.pl" 2>/dev/null || true)
}

# Collect aliases
collect_aliases() {
    local alias_file="${DOTFILES_DIR}/.zsh_aliases"
    [[ ! -f "$alias_file" ]] && return

    # Parse aliases: alias name='command'
    while IFS= read -r line; do
        [[ ! "$line" =~ ^alias[[:space:]] ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ alias[[:space:]]+([^=]+)=[[:space:]]*[\'\"]?(.+)[\'\"]?$ ]]; then
            local name="${BASH_REMATCH[1]}"
            local cmd="${BASH_REMATCH[2]}"
            cmd="${cmd%\'}"  # Remove trailing quote
            cmd="${cmd#\'}"  # Remove leading quote
            local usage=$(get_usage_count "$name")

            printf "[ALIAS]|%s|%s|%s|%s\n" "$name" "$cmd" "$alias_file" "$usage"
        fi
    done < "$alias_file"
}

# Collect functions
collect_functions() {
    local func_file="${DOTFILES_DIR}/.zsh_functions"
    [[ ! -f "$func_file" ]] && return

    # Parse function definitions and try to extract description
    local current_func=""
    local current_desc=""
    local func_line=0

    while IFS= read -r line; do
        # Function definition: function_name() { or function function_name {
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+)\(\)[[:space:]]*\{|^function[[:space:]]+([a-zA-Z0-9_-]+) ]]; then
            if [[ -n "$current_func" ]]; then
                local usage=$(get_usage_count "$current_func")
                printf "[FUNCTION]|%s|%s|%s|%s\n" "$current_func" "${current_desc:-Function: $current_func}" "$func_file:$func_line" "$usage"
            fi
            current_func="${BASH_REMATCH[1]:-${BASH_REMATCH[2]}}"
            current_desc=""
            func_line=$(($(grep -n "^${current_func}\(\)" "$func_file" | head -1 | cut -d: -f1) ))
        # Comment that might be description
        elif [[ "$line" =~ ^[[:space:]]*#[[:space:]]*(.+) ]] && [[ -n "$current_func" ]] && [[ -z "$current_desc" ]]; then
            current_desc="${BASH_REMATCH[1]}"
        fi
    done < "$func_file"

    # Don't forget the last function
    if [[ -n "$current_func" ]]; then
        local usage=$(get_usage_count "$current_func")
        printf "[FUNCTION]|%s|%s|%s|%s\n" "$current_func" "${current_desc:-Function: $current_func}" "$func_file:$func_line" "$usage"
    fi
}

# Collect abbreviations
collect_abbreviations() {
    local abbrev_file="${DOTFILES_DIR}/.zsh_abbreviations"
    [[ ! -f "$abbrev_file" ]] && return

    # Parse abbreviations: abbr -g NAME='expansion' or similar
    while IFS= read -r line; do
        [[ ! "$line" =~ (abbr|abbreviation) ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Try to match: abbr ... NAME='expansion'
        if [[ "$line" =~ ([a-zA-Z0-9_-]+)=[\'\":](.+)[\'\"] ]]; then
            local name="${BASH_REMATCH[1]}"
            local expansion="${BASH_REMATCH[2]}"
            expansion="${expansion%\'}"
            expansion="${expansion#\'}"
            expansion="${expansion%\"}"
            expansion="${expansion#\"}"
            local usage=$(get_usage_count "$name")

            printf "[ABBREV]|%s|%s|%s|%s\n" "$name" "→ $expansion" "$abbrev_file" "$usage"
        fi
    done < "$abbrev_file"
}

# Collect shortcuts from shortcuts.yaml
collect_shortcuts() {
    local shortcuts_file="${DOTFILES_DIR}/shortcuts.yaml"
    [[ ! -f "$shortcuts_file" ]] && return

    # Simple YAML parsing for shortcuts
    local current_app=""
    while IFS= read -r line; do
        # Application header (e.g., "mpv:")
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
            current_app="${BASH_REMATCH[1]}"
        # Shortcut entry (e.g., "  - key: value")
        elif [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.+) ]] && [[ -n "$current_app" ]]; then
            local shortcut="${BASH_REMATCH[1]}"
            printf "[SHORTCUT]|%s: %s|%s|%s|%s\n" "$current_app" "$shortcut" "Keyboard shortcut" "$shortcuts_file" "0"
        fi
    done < "$shortcuts_file"
}

# Generate preview content
generate_preview() {
    local type="$1"
    local name="$2"
    local source="$3"

    echo -e "${COLOR_SCRIPT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    echo -e "${type} ${COLOR_FUNCTION}${name}${COLOR_RESET}"
    echo -e "${COLOR_SCRIPT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
    echo ""

    case "$type" in
        "[SCRIPT]")
            if [[ -f "$source" ]]; then
                echo -e "${COLOR_ALIAS}📄 Source: ${source}${COLOR_RESET}"
                echo ""
                # Show first 50 lines with syntax highlighting if bat is available
                if command -v bat &>/dev/null; then
                    bat --style=numbers,grid --color=always --line-range=:50 "$source" 2>/dev/null || head -50 "$source"
                else
                    head -50 "$source"
                fi
            fi
            ;;
        "[ALIAS]")
            echo -e "${COLOR_ALIAS}📎 Defined in: ${source}${COLOR_RESET}"
            echo ""
            echo -e "${COLOR_FUNCTION}Full definition:${COLOR_RESET}"
            grep "alias ${name}=" "$source" 2>/dev/null || echo "alias $name='...'"
            ;;
        "[FUNCTION]")
            if [[ "$source" =~ ^(.*):([0-9]+)$ ]]; then
                local file="${BASH_REMATCH[1]}"
                local line="${BASH_REMATCH[2]}"
                echo -e "${COLOR_ALIAS}📦 Defined in: ${file}:${line}${COLOR_RESET}"
                echo ""
                # Show function definition (next 30 lines from the function start)
                if command -v bat &>/dev/null; then
                    bat --style=numbers,grid --color=always --line-range="${line}:$((line+30))" "$file" 2>/dev/null || sed -n "${line},$((line+30))p" "$file"
                else
                    sed -n "${line},$((line+30))p" "$file"
                fi
            fi
            ;;
        "[ABBREV]")
            echo -e "${COLOR_ALIAS}⚡ Defined in: ${source}${COLOR_RESET}"
            echo ""
            echo -e "${COLOR_FUNCTION}This abbreviation expands as you type${COLOR_RESET}"
            grep -A2 -B2 "${name}=" "$source" 2>/dev/null || echo "Abbreviation: $name"
            ;;
        "[SHORTCUT]")
            echo -e "${COLOR_ALIAS}⌨️  Defined in: ${source}${COLOR_RESET}"
            echo ""
            echo -e "${COLOR_FUNCTION}Keyboard shortcut${COLOR_RESET}"
            ;;
    esac
}

# Main collection function
collect_all() {
    {
        collect_scripts
        collect_aliases
        collect_functions
        collect_abbreviations
        # collect_shortcuts  # Can be noisy, uncomment if desired
    } | sort -t'|' -k5 -rn > "$TEMP_DATA"  # Sort by usage count
}

# FZF preview script
preview_script() {
    local line="$1"
    IFS='|' read -r type name desc source usage <<< "$line"
    generate_preview "$type" "$name" "$source"
}

# Export for fzf to use
export -f generate_preview
export COLOR_SCRIPT COLOR_ALIAS COLOR_FUNCTION COLOR_ABBREV COLOR_SHORTCUT COLOR_RESET

# Main execution
main() {
    local initial_query="${1:-}"

    echo "🔍 Indexing your dotfiles..." >&2
    collect_all

    local total_items=$(wc -l < "$TEMP_DATA")
    echo "✨ Found ${total_items} items (scripts, aliases, functions, abbreviations)" >&2

    # Format for display: colorize type tags and add usage stats
    local selected
    selected=$(cat "$TEMP_DATA" | while IFS='|' read -r type name desc source usage; do
        local usage_display=""
        if [[ "$usage" -gt 0 ]]; then
            usage_display=" ${COLOR_ABBREV}[used ${usage}×]${COLOR_RESET}"
        fi

        local color_type
        case "$type" in
            "[SCRIPT]")   color_type="${COLOR_SCRIPT}${type}${COLOR_RESET}" ;;
            "[ALIAS]")    color_type="${COLOR_ALIAS}${type}${COLOR_RESET}" ;;
            "[FUNCTION]") color_type="${COLOR_FUNCTION}${type}${COLOR_RESET}" ;;
            "[ABBREV]")   color_type="${COLOR_ABBREV}${type}${COLOR_RESET}" ;;
            "[SHORTCUT]") color_type="${COLOR_SHORTCUT}${type}${COLOR_RESET}" ;;
            *)            color_type="$type" ;;
        esac

        echo -e "${color_type} ${COLOR_FUNCTION}${name}${COLOR_RESET}${usage_display} - ${desc}|${type}|${name}|${source}|${usage}"
    done | fzf \
        --ansi \
        --query="$initial_query" \
        --delimiter="|" \
        --with-nth=1 \
        --preview="echo {} | cut -d'|' -f2-5 | xargs -I {} bash -c 'source ${BASH_SOURCE[0]} && generate_preview {}'" \
        --preview-window=right:60%:wrap \
        --bind="ctrl-e:execute(echo {} | cut -d'|' -f4 | xargs -I {} \$EDITOR {})" \
        --bind="ctrl-y:execute-silent(echo {} | cut -d'|' -f3 | xclip -selection clipboard)+abort" \
        --header="Enter=Execute/Copy | Ctrl-E=Edit | Ctrl-Y=Copy | ESC=Cancel" \
        --height=100% \
        --border=rounded \
        --margin=1 \
        --padding=1 \
        --prompt="🔍 dotfiles > " \
        --pointer="▶" \
        --marker="✓" \
        --color="fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4"
    ) || return 0

    # Parse selection
    IFS='|' read -r _ type name source _ <<< "$selected"

    # Execute based on type
    case "$type" in
        "[SCRIPT]")
            if [[ -x "$source" ]]; then
                echo -e "\n${COLOR_SCRIPT}▶ Executing: ${source}${COLOR_RESET}"
                "$source"
            fi
            ;;
        "[ALIAS]"|"[FUNCTION]")
            # Copy to clipboard if available
            if command -v xclip &>/dev/null; then
                echo "$name" | xclip -selection clipboard
                echo -e "${COLOR_FUNCTION}✓ Copied '${name}' to clipboard${COLOR_RESET}"
            else
                echo -e "${COLOR_FUNCTION}Command: ${name}${COLOR_RESET}"
            fi
            ;;
        "[ABBREV]")
            if command -v xclip &>/dev/null; then
                echo "$name" | xclip -selection clipboard
                echo -e "${COLOR_ABBREV}✓ Copied abbreviation '${name}' to clipboard${COLOR_RESET}"
            fi
            ;;
    esac
}

# Allow sourcing for function exports
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
