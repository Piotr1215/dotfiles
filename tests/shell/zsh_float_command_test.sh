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
    && ${new_pane_args[8]} == 117 \
    && ${new_pane_args[9]} == -y \
    && ${new_pane_args[10]} == 36 \
    && ${new_pane_args[11]} == -X \
    && ${new_pane_args[12]} == 176 \
    && ${new_pane_args[13]} == -Y \
    && ${new_pane_args[14]} == 2 \
    && ${new_pane_args[15]} == zsh \
    && ${#new_pane_args} == 15 ]]; then
    print -r -- "ok - creates the same persistent Zsh as M-z before the command"
    (( passed++ ))
else
    print -u2 -r -- "not ok - persistent pane launcher arguments differ"
    print -u2 -r -- "got: ${(j: | :)new_pane_args}"
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

FLOAT_EXISTING_FLOATS=1 \
FLOAT_TMUX_NEW_PANE_LOG="$tmpdir/new-pane.log" \
FLOAT_TMUX_SEND_KEYS_LOG="$tmpdir/send-keys.log" \
PATH="$tmpdir/bin:$PATH" \
    _float_command_launch 'printf second'

second_pane_args=( )
while IFS= read -r -d '' entry; do
    second_pane_args+=( "$entry" )
done < "$tmpdir/new-pane.log"
if [[ ${second_pane_args[12]} == 172 && ${second_pane_args[14]} == 4 ]]; then
    print -r -- "ok - offsets a second float like a card"
    (( passed++ ))
else
    print -u2 -r -- "not ok - second float position=${second_pane_args[12]:-missing},${second_pane_args[14]:-missing} expected=172,4"
    (( failed++ ))
fi

print -r -- "passed=$passed failed=$failed"
(( failed == 0 ))
