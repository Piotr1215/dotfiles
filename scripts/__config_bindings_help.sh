#!/usr/bin/env bash
set -eo pipefail

# Parse all config bindings and show in fzf popup
# Uses confhelp for parsing, adds tealdeer integration
# Enter = jump to line | Ctrl+G = tealdeer pages

DOTFILES="$HOME/dev/dotfiles"
TEMP_FILE=$(mktemp)

FZF_COLORS='fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4'

main_loop() {
    local mode="bindings"

    while true; do
        if [[ "$mode" == "bindings" ]]; then
            local selection
            selection=$(confhelp -b "$DOTFILES" | column -t -s'|' | fzf \
                --header='Enter=jump | Ctrl+G=tealdeer pages' \
                --bind='ctrl-g:become(echo SWITCH_TLDR)' \
                --height=100% \
                --layout=reverse \
                --info=inline \
                --border=sharp \
                --prompt='bindings: ' \
                --color="$FZF_COLORS" \
                || true)

            if [[ "$selection" == "SWITCH_TLDR" ]]; then
                mode="tldr"
                continue
            elif [[ -n "$selection" ]]; then
                local file_line=$(echo "$selection" | awk '{print $NF}')
                local file=$(echo "$file_line" | cut -d: -f1)
                local line=$(echo "$file_line" | cut -d: -f2)
                echo "FILE:${DOTFILES}/${file}:${line}" > "$TEMP_FILE"
                break
            else
                break
            fi
        else
            # tldr mode
            local custom_file=$(mktemp)
            ls -1 "${DOTFILES}/tealdeer-pages/common"/*.page.md 2>/dev/null | xargs -I{} basename {} .page.md > "$custom_file"
            local selection
            selection=$( {
                sed 's/$/ [custom]/' "$custom_file"
                tldr --list 2>/dev/null | grep -vxFf "$custom_file"
            } | fzf \
                --header='Enter=view | Ctrl+G=bindings | Ctrl+N=new | Ctrl+E=edit' \
                --bind='ctrl-g:become(echo SWITCH_BINDINGS)' \
                --bind='ctrl-n:become(echo NEW_PAGE)' \
                --bind='ctrl-e:become(echo EDIT_PAGE:{})' \
                --preview='page={};page=${page% \[custom\]};tldr "$page" 2>/dev/null || echo "No preview"' \
                --preview-window=right:60%:wrap \
                --height=100% \
                --layout=reverse \
                --info=inline \
                --border=sharp \
                --prompt='tldr: ' \
                --color="$FZF_COLORS" \
                || true)
            rm -f "$custom_file"

            if [[ "$selection" == "SWITCH_BINDINGS" ]]; then
                mode="bindings"
                continue
            elif [[ "$selection" == "NEW_PAGE" ]]; then
                echo "NEW_PAGE" > "$TEMP_FILE"
                break
            elif [[ "$selection" == EDIT_PAGE:* ]]; then
                echo "$selection" > "$TEMP_FILE"
                break
            elif [[ -n "$selection" ]]; then
                selection="${selection% \[custom\]}"
                echo "TLDR:${selection}" > "$TEMP_FILE"
                break
            else
                break
            fi
        fi
    done
}

export -f main_loop
export DOTFILES TEMP_FILE FZF_COLORS

# Calculate center position
read screen_w screen_h < <(xdpyinfo | awk '/dimensions:/{print $2}' | tr 'x' ' ')
cols=220
lines=50
win_w=$((cols * 9))
win_h=$((lines * 20))
pos_x=$(( (screen_w - win_w) / 2 ))
pos_y=$(( (screen_h - win_h) / 2 ))

alacritty --class config-bindings-popup \
    --config-file /dev/null \
    -o window.dimensions.columns=$cols \
    -o window.dimensions.lines=$lines \
    -o window.position.x=$pos_x \
    -o window.position.y=$pos_y \
    -e bash -c "main_loop"

# Handle final result
if [[ -f "$TEMP_FILE" ]]; then
    result=$(cat "$TEMP_FILE")
    rm -f "$TEMP_FILE"

    case "$result" in
        FILE:*)
            target="${result#FILE:}"
            file=$(echo "$target" | cut -d: -f1)
            line=$(echo "$target" | cut -d: -f2)
            nohup alacritty -e nvim "+$line" "$file" >/dev/null 2>&1 &
            ;;
        TLDR:*)
            page="${result#TLDR:}"
            tmux display-popup -w 80% -h 80% -E "tldr --color always '$page' | less -R"
            ;;
        NEW_PAGE)
            name=$(zenity --entry --title="New tldr page" --text="Page name:" 2>/dev/null || true)
            if [[ -n "$name" ]]; then
                page_file="${DOTFILES}/tealdeer-pages/common/${name}.page.md"
                cat > "$page_file" << 'TEMPLATE'
Short description of the tool/topic.
  More information: <https://example.com>.

  Example command or shortcut:

      command --option

  Another example:

      another-command
TEMPLATE
                nohup alacritty -e nvim "$page_file" >/dev/null 2>&1 &
            fi
            ;;
        EDIT_PAGE:*)
            page="${result#EDIT_PAGE:}"
            page="${page% \[custom\]}"
            page_file="${DOTFILES}/tealdeer-pages/common/${page}.page.md"
            if [[ -f "$page_file" ]]; then
                nohup alacritty -e nvim "$page_file" >/dev/null 2>&1 &
            fi
            ;;
    esac
fi
