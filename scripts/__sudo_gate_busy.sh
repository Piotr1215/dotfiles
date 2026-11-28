#!/usr/bin/env bash
# Check for a pending root touch, or hold the touch lock across a command.
# A refusal goes to stderr, never a desktop notification: the argos label is the
# only root request signal (Piotr, 28 Nov: "I don't want to see notifications").
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
applet="$script_dir/../.config/argos/sudo-gate.1s.sh"
if (($# == 0)); then
    "$applet" --busy
    exit $?
fi
if [[ "$1" != --run || $# -lt 2 ]]; then
    printf 'usage: %s [--run command [args...]]\n' "$0" >&2
    exit 2
fi
shift
lock_file=${SUDO_GATE_LOCK_FILE:-/etc/sudo-agent-gate/.touch-lock}
if [[ -e "$lock_file" ]]; then
    exec {lock_fd}<"$lock_file" || { printf '%s\n' 'Cannot verify root requests; unlock blocked' >&2; exit 75; }
    flock -x "$lock_fd" || { printf '%s\n' 'Cannot verify root requests; unlock blocked' >&2; exit 75; }
else
    "$applet" --busy
    state=$?
    if [[ "$state" == 0 ]]; then
        printf '%s\n' 'A root request is waiting for the YubiKey: touch or refuse it first (top bar)' >&2
        exit 75
    elif [[ "$state" != 1 ]]; then
        printf '%s\n' 'Cannot verify root requests; unlock blocked' >&2
        exit 75
    fi
    "$applet" --state-present
    state=$?
    if [[ "$state" != 1 ]]; then
        printf '%s\n' 'Cannot verify root requests; unlock blocked' >&2
        exit 75
    fi
fi
"$applet" --busy
state=$?
if [[ "$state" == 0 ]]; then
    printf '%s\n' 'A root request is waiting for the YubiKey: touch or refuse it first (top bar)' >&2
    exit 75
elif [[ "$state" != 1 ]]; then
    printf '%s\n' 'Cannot verify root requests; unlock blocked' >&2
    exit 75
fi
popup=""
cleanup_cue() {
    if [[ "${SUDO_GATE_CUE_KIND:-}" == picker ]]; then
        rm -f "$SUDO_GATE_CUE_FILE"
    fi
    if [[ "$popup" =~ ^[0-9]+$ ]]; then
        gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.CloseNotification "$popup" >/dev/null 2>&1 || :
    fi
}
case "${SUDO_GATE_CUE_KIND:-}" in
picker)
    touch "$SUDO_GATE_CUE_FILE"
    trap cleanup_cue EXIT
    if [[ -n "${SUDO_GATE_CUE_MESSAGE:-}" ]]; then
        popup=$(notify-send -p -e -u critical 'Secret picker' "$SUDO_GATE_CUE_MESSAGE" 2>/dev/null) || popup=""
    fi
    ;;
sec)
    printf 'sec: TOUCH your YubiKey to unlock '\''%s'\'' (it is blinking) ...\n' "$SUDO_GATE_CUE_NAME" >&2
    trap cleanup_cue EXIT
    popup=$(notify-send -p -u normal -t 12000 '🔐 YubiKey' "Touch the key to unlock $SUDO_GATE_CUE_NAME" 2>/dev/null) || popup=""
    ;;
esac
"$@"
