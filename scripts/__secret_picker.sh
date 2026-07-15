#!/usr/bin/env bash
# PROJECT: secret-picker
# Global rofi picker over the age/YubiKey bastion secrets in ~/.secrets/*.age.
# Same list `sec <TAB>` completes in zsh, but reachable from any window: pick a
# name, tap the YubiKey once, and the value lands on the clipboard.
# Bound to <alt>+<ctrl>+p by the autokey script Scripts/SecretPicker.py.
set -eo pipefail

SECRETS_DIR="$HOME/.secrets"
AGE_ID="$HOME/.config/age/yubikey-pass-bastion.txt"
DESC_FILE="$SECRETS_DIR/.descriptions"

# Description for a secret, from the plaintext sidecar ("NAME | description").
# Plaintext by necessity: the menu has to render before any tap, so this cannot
# live inside the .age files. Empty output means "no description, show bare name".
desc_for() {
	[[ -r "$DESC_FILE" ]] || return 0
	awk -F' *\\| *' -v want="$1" '
		/^[[:space:]]*#/ { next }
		NF < 2 { next }
		$1 == want { print $2; exit }
	' "$DESC_FILE"
}

# Shared rofi look (mirrors __value_picker.sh).
rofi_pick() {
	rofi -dmenu -i -p "$1" \
		-theme-str '* {font: "JetBrainsMono Nerd Font 12";}' \
		-theme-str 'window {width: 600px; background-color: argb:ff282a36; border: 2px solid; border-color: argb:ffbd93f9; border-radius: 8px;}' \
		-theme-str 'mainbox {background-color: transparent;}' \
		-theme-str 'inputbar {background-color: argb:ff44475a; text-color: argb:fff8f8f2; padding: 8px;}' \
		-theme-str 'prompt {text-color: argb:ffbd93f9;}' \
		-theme-str 'entry {text-color: argb:fff8f8f2;}' \
		-theme-str 'listview {background-color: transparent; lines: 10;}' \
		-theme-str 'element {padding: 8px; background-color: transparent; text-color: argb:fff8f8f2;}' \
		-theme-str 'element.selected {background-color: argb:ff44475a; text-color: argb:ff50fa7b;}'
}

# Copy to whichever clipboard this session uses (mirrors .totp-copy.sh).
clip() {
	if [[ -n "$WAYLAND_DISPLAY" ]] && command -v wl-copy >/dev/null 2>&1; then
		wl-copy
	else
		xsel --clipboard
	fi
}

[[ -r "$AGE_ID" ]] || {
	notify-send -u critical "Secret picker" "age identity not readable: $AGE_ID"
	exit 1
}

mapfile -t names < <(find "$SECRETS_DIR" -maxdepth 1 -type f -name '*.age' -printf '%f\n' 2>/dev/null |
	sed 's/\.age$//' | sort)

((${#names[@]})) || {
	notify-send -u critical "Secret picker" "no secrets found in $SECRETS_DIR"
	exit 1
}

# Show "NAME | description" where one exists, bare NAME where it does not.
menu=()
for n in "${names[@]}"; do
	d=$(desc_for "$n")
	[[ -n "$d" ]] && menu+=("$n | $d") || menu+=("$n")
done

choice=$(printf '%s\n' "${menu[@]}" | rofi_pick "secret") || exit 0
[[ -n "$choice" ]] || exit 0

# Strip the label back off, same as __value_picker.sh does with its VALUE | label.
choice="${choice%% | *}"

# Cue the tap: age blocks until the key is touched and there is no terminal here
# to print to, so without this the wait just looks like nothing happened.
notify-send -u normal -t 12000 "🔐 YubiKey" "Touch the key to unlock $choice"

# Pipe straight to the clipboard so the value never lands in a shell variable,
# same rule `sec` follows. pipefail makes an age failure fail the whole pipeline.
#
# A missed touch is by far the most common failure, and age-plugin-yubikey reports
# it as "Failed to decrypt YubiKey stanza", which reads like a key/recipient fault
# and sends you debugging the wrong thing. Say what it actually is.
if ! age -d -i "$AGE_ID" "$SECRETS_DIR/$choice.age" 2>/dev/null | clip; then
	notify-send -u critical "🔐 Secret picker" "no tap registered, $choice not copied. Press again and touch the key."
	exit 1
fi

notify-send -t 5000 "🔐 Secret picker" "$choice copied to clipboard"
