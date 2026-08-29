#!/usr/bin/env bash
set -eo pipefail

# Parse all config bindings and show in fzf popup
# Uses confhelp for parsing, adds tealdeer integration
# Enter = jump to line | Ctrl+G = tealdeer pages

DOTFILES="$HOME/dev/dotfiles"
TEMP_FILE=$(mktemp)

FZF_COLORS='fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4'

format_for_clipboard() {
    local input file_line raw_line
    read -r input
    file_line=$(echo "$input" | awk '{print $NF}')
    raw_line=$(confhelp -b "$DOTFILES" | grep -F "|${file_line}" | head -1)
    if [[ -z "$raw_line" ]]; then
        printf "SOURCE | KEY | COMMAND | FILE:LINE\n%s\n" "$input"
    else
        printf "SOURCE|KEY|COMMAND|FILE:LINE\n%s\n" "$raw_line" | column -t -s'|' -o' | '
    fi
}

# The absolute path worth handing to someone else. A binding is remembered by
# its key and almost never by the file it lives in, so the useful answer is the
# script the key RUNS: M-g is defined at .tmux.conf:213 but the thing to open is
# __ddgx.sh. Falls back to the definition, with its line, when the command names
# no path of its own (plain tmux verbs, zsh aliases, nvim keymaps).
binding_payload() {
    local selection="$1" cand suffix file_line file line

    # A tmuxinator row's description IS its root directory, so the generic path
    # scan below would hand back the project dir instead of the session file
    # that actually defines the layout.
    if [[ "$selection" == *"[mux]"* ]]; then
        file_line=$(echo "$selection" | awk '{print $NF}')
        printf '%s' "${HOME}/.config/tmuxinator/${file_line%%:*}"
        return 0
    fi

    # Every path-looking token, first one that is really there wins. Taking
    # just the first match picked /dev/null out of "2>/dev/null" and stopped,
    # because a command line is full of paths that are not the target.
    while read -r cand; do
        cand="${cand%[\"\',:;)]}"
        cand="${cand/#\~/$HOME}"
        cand="${cand/#\$HOME/$HOME}"
        suffix=""
        if [[ "$cand" =~ ^(.+):([0-9]+)$ ]]; then
            cand="${BASH_REMATCH[1]}"
            suffix=":${BASH_REMATCH[2]}"
        fi
        case "$cand" in /dev/*|/proc/*) continue ;; esac
        if [[ -f "$cand" ]]; then
            printf '%s%s' "$cand" "$suffix"
            return 0
        fi
    done < <(echo "$selection" | grep -oE '(/[^ ]+|~/[^ ]+|\$HOME/[^ ]+)')

    file_line=$(echo "$selection" | awk '{print $NF}')
    file="${file_line%:*}"
    line="${file_line##*:}"
    case "$file" in
        /*) ;;
        "~"*) file="${file/#\~/$HOME}" ;;
        *.yml) file="$HOME/.config/tmuxinator/$file" ;;
        *) file="$DOTFILES/$file" ;;
    esac
    if [[ "$line" =~ ^[0-9]+$ ]]; then
        printf '%s:%s' "$file" "$line"
    else
        printf '%s' "$file"
    fi
}

main_loop() {
    local mode="bindings"

    while true; do
        if [[ "$mode" == "bindings" ]]; then
            local result key selection
            result=$(confhelp -b "$DOTFILES" | awk -F'|' '{printf "%-12s %-18s %-55s %s\n", $1, $2, $3, $4}' | fzf \
                --header='Enter=jump | Alt+H=send to pane | Ctrl+O=copy path | Ctrl+P=open | Ctrl+G=tealdeer' \
                --expect=ctrl-g,ctrl-o,ctrl-p,alt-h \
                --height=100% \
                --layout=reverse \
                --info=inline \
                --border=sharp \
                --prompt='bindings: ' \
                --color="$FZF_COLORS" \
                || true)

            key=$(echo "$result" | head -1)
            selection=$(echo "$result" | tail -1)

            case "$key" in
                ctrl-g)
                    mode="tldr"
                    continue
                    ;;
                alt-h)
                    # Hand the path to the pane the popup was opened over, the
                    # way M-g's alt-h hands over an extract. Pasted at the
                    # cursor and never submitted, because this lands in the
                    # middle of a half-typed sentence to an agent.
                    if [[ -n "$selection" ]]; then
                        echo "SEND:$(binding_payload "$selection")" > "$TEMP_FILE"
                    fi
                    break
                    ;;
                ctrl-o)
                    # The path, not the row. Copying the rendered row pasted
                    # three padded columns and a repo-relative .tmux.conf:213
                    # that resolves against nothing on the far end.
                    if [[ -n "$selection" ]]; then
                        binding_payload "$selection" | xsel -ib
                    fi
                    break
                    ;;
                ctrl-p)
                    if [[ -n "$selection" ]]; then
                        local path
                        path=$(echo "$selection" | grep -oE '(/[^ ]+|~[^ ]+|\$HOME[^ ]+)' | head -1)
                        path="${path%\"}"  # strip trailing quote
                        path="${path/#\~/$HOME}"
                        path="${path/#\$HOME/$HOME}"
                        if [[ -e "$path" ]]; then
                            echo "OPEN_PATH:$path" > "$TEMP_FILE"
                        fi
                    fi
                    break
                    ;;
                *)
                    # Enter pressed or empty. Same resolver alt-h uses, so both
                    # keys land on the same file. The row's own last column is
                    # not it: for a generated row that column is the index,
                    # __fzf_bindings.conf, and editing the index edits nothing.
                    if [[ -n "$selection" ]]; then
                        echo "FILE:$(binding_payload "$selection")" > "$TEMP_FILE"
                    fi
                    break
                    ;;
            esac
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

export -f main_loop format_for_clipboard binding_payload
export DOTFILES TEMP_FILE FZF_COLORS

# Calculate center position
read screen_w screen_h < <(xdpyinfo | awk '/dimensions:/{print $2}' | tr 'x' ' ')
cols=150
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
            # The line is optional: a binding that names a script has no line to
            # give, and nvim "+" with an empty count refuses to open the file.
            if [[ "$target" =~ ^(.+):([0-9]+)$ ]]; then
                nohup alacritty -e nvim "+${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}" >/dev/null 2>&1 &
            else
                nohup alacritty -e nvim "$target" >/dev/null 2>&1 &
            fi
            ;;
        MUX_EDIT:*)
            session_file="${result#MUX_EDIT:}"
            nohup alacritty -e nvim "$session_file" >/dev/null 2>&1 &
            ;;
        OPEN_PATH:*)
            path="${result#OPEN_PATH:}"
            nohup alacritty -e nvim "$path" >/dev/null 2>&1 &
            ;;
        SEND:*)
            payload="${result#SEND:}"
            # No @popup_source_pane to read: this popup is its own alacritty
            # window, not a tmux display-popup, so the target is tmux's active
            # pane, which is still the one the shortcut was pressed over.
            source "${DOTFILES}/scripts/__lib_pane_deliver.sh"
            target=$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)
            if ! deliver_to_pane "$target" "$payload"; then
                printf '%s' "$payload" | xsel -ib
                notify-send "confhelp" "no live pane, copied instead" 2>/dev/null || true
            fi
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
