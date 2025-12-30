#!/usr/bin/env bash
set -eo pipefail

# Parse all config bindings and show in fzf popup
# Enter = jump to line | Ctrl+G = tealdeer pages

DOTFILES="$HOME/dev/dotfiles"
TEMP_FILE=$(mktemp)

parse_configs() {
    python3 << 'PYEOF'
import re
import os

DOTFILES = os.path.expanduser("~/dev/dotfiles")

def parse_tmux():
    path = f"{DOTFILES}/.tmux.conf"
    if not os.path.exists(path): return
    with open(path) as f:
        for i, line in enumerate(f, 1):
            if re.match(r'^bind', line.strip()):
                m = re.match(r'bind(?:-key)?\s+(?:-n\s+)?(\S+)', line.strip())
                if m:
                    key = m.group(1)
                    cmd = line.strip()[len(m.group(0)):].strip()[:50]
                    print(f"[tmux]|{key}|{cmd}|.tmux.conf:{i}")

def parse_zsh_bindkeys():
    path = f"{DOTFILES}/.zshrc"
    if not os.path.exists(path): return
    with open(path) as f:
        for i, line in enumerate(f, 1):
            if 'bindkey' in line and not line.strip().startswith('#'):
                m = re.search(r"bindkey\s+(?:-s\s+)?['\"]([^'\"]+)['\"]", line)
                if m:
                    key = m.group(1)
                    comment = line.split('#')[1].strip() if '#' in line else ''
                    func = re.search(r"['\"][^'\"]+['\"]\s+(\S+)", line)
                    desc = comment if comment else (func.group(1) if func else line.strip()[:40])
                    print(f"[bind]|{key}|{desc}|.zshrc:{i}")

def parse_aliases():
    for fname in ['.zsh_aliases', '.zsh_claude']:
        path = f"{DOTFILES}/{fname}"
        if not os.path.exists(path): continue
        with open(path) as f:
            for i, line in enumerate(f, 1):
                m = re.match(r"alias\s+(?:-[gs]\s+)?([^=]+)=", line.strip())
                if m:
                    name = m.group(1).strip()
                    val = line.split('=', 1)[1][:50].strip().strip("'\"")
                    print(f"[alias]|{name}|{val}|{fname}:{i}")

def parse_abbrevs():
    path = f"{DOTFILES}/.zsh_abbreviations"
    if not os.path.exists(path): return
    with open(path) as f:
        content = f.read()
    match = re.search(r'abbrevs=\((.*?)\)', content, re.DOTALL)
    if match:
        pairs = re.findall(r'"([^"]+)"\s+\'([^\']+)\'', match.group(1))
        for key, val in pairs:
            print(f"[abbr]|{key}|{val}|.zsh_abbreviations:1")

def parse_functions():
    path = f"{DOTFILES}/.zsh_functions"
    if not os.path.exists(path): return
    with open(path) as f:
        for i, line in enumerate(f, 1):
            m = re.match(r'(?:function\s+)?(\w+)\s*\(\)\s*\{?', line.strip())
            if m and not line.strip().startswith('#'):
                print(f"[func]|{m.group(1)}|(function)|.zsh_functions:{i}")

parse_tmux()
parse_zsh_bindkeys()
parse_aliases()
parse_abbrevs()
parse_functions()
PYEOF
}

# Main loop runs inside single alacritty - no window reopening
main_loop() {
    local mode="bindings"

    while true; do
        if [[ "$mode" == "bindings" ]]; then
            local selection
            selection=$(parse_configs | column -t -s'|' | fzf \
                --header='Enter=jump | Ctrl+G=tealdeer pages' \
                --bind='ctrl-g:become(echo SWITCH_TLDR)' \
                --height=100% \
                --layout=reverse \
                --info=inline \
                --border=sharp \
                --prompt='bindings: ' \
                --color='fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4' \
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
                --color='fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4' \
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

export -f parse_configs
export -f main_loop
export DOTFILES
export TEMP_FILE

# Single alacritty window runs the loop
alacritty --class config-bindings-popup \
    --config-file /dev/null \
    -o window.dimensions.columns=130 \
    -o window.dimensions.lines=40 \
    -o window.position.x=1380 \
    -o window.position.y=660 \
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
