#!/usr/bin/env bash
# Dedicated "share a screenshot" capture, bound to Shift+Print.
#
# Region-capture with flameshot, upload to catbox.moe, and put the resulting URL
# on the clipboard (Ctrl+V) and PRIMARY selection (middle-click) so you can paste
# the link straight into chat or docs. A desktop notification shows the URL too.
#
# The normal Print key stays plain `flameshot gui` for local image copy (Copy
# button, Save, Pin, Enter = copy to clipboard). This key is only for producing a
# shareable URL, so flameshot's --raw mode dropping the toolbar buttons is fine.
#
# Why catbox and not flameshot's own upload button: that button is hardcoded to
# Imgur, and Imgur closed new API-app registration server-side, so it always
# returns HTTP 429. catbox needs no account and no API key. curl --max-time means
# an unreachable host can never hang the keybind.
set -eo pipefail

readonly catbox_api="https://catbox.moe/user/api.php"
readonly upload_timeout=30

# notify(): thin wrapper so a missing/failing notify-send never aborts the script.
notify() {
    local urgency="$1"; shift
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" "$@" || true
    fi
}

main() {
    local png
    png="$(mktemp --suffix=.png)"
    # shellcheck disable=SC2064
    trap "rm -f '$png'" EXIT

    # --raw streams the PNG to stdout on accept; a cancel (Esc) yields empty.
    flameshot gui --raw > "$png" 2>/dev/null || true
    if [[ ! -s "$png" ]]; then
        exit 0
    fi

    local url
    url="$(curl -s --max-time "$upload_timeout" \
        -F "reqtype=fileupload" -F "fileToUpload=@$png" "$catbox_api" || true)"

    if [[ "$url" != https://files.catbox.moe/* ]]; then
        notify critical "Screenshot upload failed" "${url:-no response from catbox}"
        echo "upload failed: ${url:-no response from catbox}" >&2
        exit 1
    fi

    # URL on both selections: Ctrl+V and middle-click both paste the link.
    printf '%s' "$url" | xclip -selection clipboard
    printf '%s' "$url" | xclip -selection primary
    notify normal "Screenshot uploaded" "URL copied to clipboard:
$url"
    echo "$url"
}

main "$@"
