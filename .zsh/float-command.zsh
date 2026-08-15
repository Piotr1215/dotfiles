# Treat one unquoted F as an execution marker for a tmux floating pane.
# The rest of the line is parsed again by the Zsh inside the pane, so global
# aliases remain composable: `ls F W` becomes `ls W` in the floating pane.

_float_command_without_marker() {
    emulate -L zsh

    local word
    local -a words kept
    local -i markers=0

    words=( ${(z)1} )
    for word in "${words[@]}"; do
        if [[ $word == F ]]; then
            (( markers++ ))
        else
            kept+=( "$word" )
        fi
    done

    (( markers > 0 )) || return 1
    (( markers == 1 )) || return 2
    (( ${#kept} > 0 )) || return 3

    REPLY=${(j: :)kept}
}

_float_command_launch() {
    emulate -L zsh

    local pane_id
    local -i float_x=176 float_y=2

    if tmux list-panes -t "$TMUX_PANE" -F '#{pane_floating_flag}' 2>/dev/null \
        | command grep -q '^1$'; then
        float_x=172
        float_y=4
    fi

    pane_id=$(tmux new-pane -P -F '#{pane_id}' -c "$PWD" \
        -x 117 -y 36 -X "$float_x" -Y "$float_y" zsh) || return 1
    [[ -n $pane_id ]] || return 1

    tmux send-keys -t "$pane_id" -l -- "$1" || return 1
    tmux send-keys -t "$pane_id" Enter
}

_float_command_accept_line() {
    emulate -L zsh

    local original=$BUFFER command error
    local -i rc

    _float_command_without_marker "$original"
    rc=$?
    case $rc in
        0) command=$REPLY ;;
        1) zle .accept-line; return ;;
        2) zle -M 'floating command: use exactly one unquoted F'; return 1 ;;
        3) zle -M 'floating command: F needs a command'; return 1 ;;
    esac

    if error=$(_float_command_launch "$command" 2>&1); then
        print -s -- "$original"
        [[ -n $HISTFILE ]] && fc -AI "$HISTFILE"
        BUFFER=
        CURSOR=0
        zle reset-prompt
    else
        zle -M "floating command failed: ${error:-unknown error}"
        return 1
    fi
}

if [[ -o interactive ]]; then
    zle -N _float_command_accept_line
    bindkey '^M' _float_command_accept_line
    bindkey '^J' _float_command_accept_line
fi
