#!/usr/bin/env zsh
emulate -L zsh

ROOT=${0:A:h:h:h}
source "$ROOT/.zsh/float-command.zsh"

typeset -i passed=0 failed=0

check_transform() {
    local name=$1 input=$2 expected=$3
    REPLY=
    _float_command_without_marker "$input"
    local rc=$?

    if (( rc == 0 )) && [[ $REPLY == "$expected" ]]; then
        print -r -- "ok - $name"
        (( passed++ ))
    else
        print -u2 -r -- "not ok - $name (status=$rc got=[$REPLY] expected=[$expected])"
        (( failed++ ))
    fi
}

check_status() {
    local name=$1 input=$2 expected=$3
    REPLY=
    _float_command_without_marker "$input"
    local rc=$?

    if (( rc == expected )); then
        print -r -- "ok - $name"
        (( passed++ ))
    else
        print -u2 -r -- "not ok - $name (status=$rc expected=$expected)"
        (( failed++ ))
    fi
}

check_transform "removes F and keeps later aliases" \
    'ls F W' \
    'ls W'
check_transform "preserves quoted arguments" \
    'printf "%s\n" "a b" F W' \
    'printf "%s\n" "a b" W'
check_transform "does not remove a quoted F" \
    'printf "%s\n" "F" F W' \
    'printf "%s\n" "F" W'
check_transform "preserves pipelines and substitutions" \
    'printf "%s\n" "$(printf nested)" | sed s/n/N/ F G Nested' \
    'printf "%s\n" "$(printf nested)" | sed s/n/N/ G Nested'
check_status "leaves ordinary commands to normal Enter" 'printf ordinary' 1
check_status "rejects more than one marker" 'printf value F F' 2
check_status "rejects an empty floating command" 'F' 3

tmpdir=$(mktemp -d /tmp/zsh-float-command-test.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT
mkdir "$tmpdir/bin"
cat > "$tmpdir/bin/tmux" <<'STUB'
#!/usr/bin/env zsh
case $1 in
    list-panes)
        [[ ${FLOAT_EXISTING_FLOATS:-0} == 1 ]] && print -r -- 1
        ;;
    new-pane)
        for arg in "$@"; do
            print -rn -- "$arg"$'\0'
        done > "$FLOAT_TMUX_NEW_PANE_LOG"
        print -r -- '%42'
        ;;
    move-pane)
        print -r -- "$*" >> "$FLOAT_TMUX_MOVE_PANE_LOG"
        ;;
    send-keys)
        print -rn -- __CALL__$'\0' >> "$FLOAT_TMUX_SEND_KEYS_LOG"
        for arg in "$@"; do
            print -rn -- "$arg"$'\0'
        done >> "$FLOAT_TMUX_SEND_KEYS_LOG"
        ;;
esac
STUB
chmod +x "$tmpdir/bin/tmux"

FLOAT_TMUX_NEW_PANE_LOG="$tmpdir/new-pane.log" \
FLOAT_TMUX_MOVE_PANE_LOG="$tmpdir/move-pane.log" \
FLOAT_TMUX_SEND_KEYS_LOG="$tmpdir/send-keys.log" \
PATH="$tmpdir/bin:$PATH" \
    _float_command_launch 'printf "%s\n" "a b" W'

new_pane_args=( )
while IFS= read -r -d '' entry; do
    new_pane_args+=( "$entry" )
done < "$tmpdir/new-pane.log"
if [[ ${new_pane_args[1]} == new-pane \
    && ${new_pane_args[2]} == -P \
    && ${new_pane_args[3]} == -F \
    && ${new_pane_args[4]} == '#{pane_id}' \
    && ${new_pane_args[5]} == -c \
    && ${new_pane_args[6]} == "$PWD" \
    && ${new_pane_args[7]} == -x \
    && ${new_pane_args[8]} == 50% \
    && ${new_pane_args[9]} == -y \
    && ${new_pane_args[10]} == 50% \
    && ${new_pane_args[11]} == zsh \
    && ${#new_pane_args} == 11 ]]; then
    print -r -- "ok - opens a quarter-window persistent Zsh before the command"
    (( passed++ ))
else
    print -u2 -r -- "not ok - persistent pane launcher arguments differ"
    print -u2 -r -- "got: ${(j: | :)new_pane_args}"
    (( failed++ ))
fi

if [[ "$(<"$tmpdir/move-pane.log")" == "move-pane -t %42 -P top-right" ]]; then
    print -r -- "ok - snaps the first float to the top-right corner"
    (( passed++ ))
else
    print -u2 -r -- "not ok - first float snap: $(<"$tmpdir/move-pane.log" 2>/dev/null)"
    (( failed++ ))
fi

send_keys_calls=( )
while IFS= read -r -d '' entry; do
    send_keys_calls+=( "$entry" )
done < "$tmpdir/send-keys.log"
expected_send_keys=(
    __CALL__ send-keys -t %42 -l -- 'printf "%s\n" "a b" W'
    __CALL__ send-keys -t %42 Enter
)
if [[ "${(j:\n:)send_keys_calls}" == "${(j:\n:)expected_send_keys}" ]]; then
    print -r -- "ok - injects the command into the persistent shell"
    (( passed++ ))
else
    print -u2 -r -- "not ok - command injection differs"
    print -u2 -r -- "got:      ${(j: | :)send_keys_calls}"
    print -u2 -r -- "expected: ${(j: | :)expected_send_keys}"
    (( failed++ ))
fi

: > "$tmpdir/move-pane.log"
FLOAT_EXISTING_FLOATS=1 \
FLOAT_TMUX_NEW_PANE_LOG="$tmpdir/new-pane.log" \
FLOAT_TMUX_MOVE_PANE_LOG="$tmpdir/move-pane.log" \
FLOAT_TMUX_SEND_KEYS_LOG="$tmpdir/send-keys.log" \
PATH="$tmpdir/bin:$PATH" \
    _float_command_launch 'printf second'

second_pane_args=( )
while IFS= read -r -d '' entry; do
    second_pane_args+=( "$entry" )
done < "$tmpdir/new-pane.log"
if [[ ${second_pane_args[8]} == 50% && ${second_pane_args[10]} == 50% \
    && ${second_pane_args[12]} == 48% && ${second_pane_args[14]} == 2 \
    && ! -s "$tmpdir/move-pane.log" ]]; then
    print -r -- "ok - offsets a second quarter float like a card, unsnapped"
    (( passed++ ))
else
    print -u2 -r -- "not ok - second float: ${(j: | :)second_pane_args} snap=$(<"$tmpdir/move-pane.log")"
    (( failed++ ))
fi

print -r -- "passed=$passed failed=$failed"
(( failed == 0 ))
