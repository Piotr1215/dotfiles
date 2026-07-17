#!/usr/bin/env bash
# PROJECT: secret-picker
# Global rofi picker over BOTH local secret stores, in one surface:
#   🔐 age bastion (~/.secrets/*.age)  -> needs a YubiKey tap
#   🔑 pass        (~/.password-store) -> no tap, decrypts unattended
# Pick a name and the value lands on the clipboard. Bound to <alt>+<ctrl>+p by
# the autokey script Scripts/SecretPicker.py.
#
# Why one surface: the two stores are tiers, not duplicates. pass is for secrets
# something needs with nobody at the keyboard (argos, cron, waybar), so its
# ceiling is LUKS at rest. The bastion is for secrets worth a physical tap.
# Keeping the lists apart is what let FRED_API_KEY drift into both unnoticed,
# where the tap-free copy silently made the bastion's tap decorative. Merged,
# a duplicate is two rows with the same name and you see it.
#
# The tier MUST stay visible per row. A row that hides which store serves it
# would have you reach for a secret believing a tap guards it when nothing does.
# The icon says which, and the behaviour matches: 🔑 copies instantly, 🔐 blinks.
#
# Listing both costs nothing: names are not secret (pass names are already
# plaintext filenames), and nothing is decrypted until you pick a row.
set -eo pipefail

SECRETS_DIR="$HOME/.secrets"
AGE_ID="$HOME/.config/age/yubikey-pass-bastion.txt"
DESC_FILE="$SECRETS_DIR/.descriptions"
PASS_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

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

# Shared rofi look (mirrors __value_picker.sh, but sized for this list).
#
# $1 = prompt, $2 = row count. Rows track the number of secrets instead of the
# stock lines:10, which cut off the tail of the list and made whole secrets look
# missing until you thought to scroll. Capped so a growing store cannot produce a
# menu taller than the screen; past the cap you filter by typing (-i) and rofi
# draws a scrollbar, which the fixed lines:10 never admitted to.
#
# 1200px, not 900px: rows are "tier NAME description" across two merged stores,
# and the longest today is ~113 chars, which 900px silently truncated (it already
# truncated the 104-char rows before the tier column existed).
rofi_pick() {
	local prompt="$1" rows="${2:-10}"
	(( rows < 3 )) && rows=3
	(( rows > 22 )) && rows=22
	rofi -dmenu -i -p "$prompt" -format i \
		-theme-str '* {font: "JetBrainsMono Nerd Font 12";}' \
		-theme-str 'window {width: 1200px; background-color: argb:ff282a36; border: 2px solid; border-color: argb:ffbd93f9; border-radius: 8px;}' \
		-theme-str 'mainbox {background-color: transparent;}' \
		-theme-str 'inputbar {background-color: argb:ff44475a; text-color: argb:fff8f8f2; padding: 8px;}' \
		-theme-str 'prompt {text-color: argb:ffbd93f9;}' \
		-theme-str 'entry {text-color: argb:fff8f8f2;}' \
		-theme-str "listview {background-color: transparent; lines: ${rows};}" \
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

# Parallel arrays: stores[i]/names[i] describe menu[i]. The selection comes back
# as an index (rofi -format i), never as text to re-parse. Stripping the label off
# the chosen row instead would break the moment a description contains " | ", and
# the tier column makes that parsing worse, not better.
stores=()
names=()
menu=()

# Tier icons are Nerd Font glyphs, NOT emoji: the font here is JetBrainsMono Nerd
# Font, whose nf-* glyphs are single-width, so the name column stays aligned.
# Emoji (🔐/🔑) render double-width in monospace and would ragged every row.
#   nf-fa-shield () = yubikey, a tap guards it
#   nf-fa-key    () = pass, no tap
icon_for() {
	case "$1" in
	yubikey) printf '' ;;
	pass) printf '' ;;
	esac
}

add_row() {
	local store="$1" name="$2" desc="$3"
	stores+=("$store")
	names+=("$name")
	if [[ -n "$desc" ]]; then
		menu+=("$(printf '%s  %-38s %s' "$(icon_for "$store")" "$name" "$desc")")
	else
		menu+=("$(printf '%s  %s' "$(icon_for "$store")" "$name")")
	fi
}

# 🔐 age bastion. Missing identity is not fatal here any more: it only blocks the
# age half, and hard-exiting would take the pass half down with it for no reason.
if [[ -r "$AGE_ID" ]]; then
	while IFS= read -r n; do
		[[ -n "$n" ]] && add_row yubikey "$n" "$(desc_for "$n")"
	done < <(find "$SECRETS_DIR" -maxdepth 1 -type f -name '*.age' -printf '%f\n' 2>/dev/null |
		sed 's/\.age$//' | sort)
fi

# 🔑 pass. Full store path, not a bare leaf: pass is hierarchical, leaves can
# collide across directories, and the path documents itself well enough that the
# age-only description sidecar does not need to grow a second backend.
if [[ -d "$PASS_DIR" ]]; then
	while IFS= read -r p; do
		[[ -n "$p" ]] && add_row pass "$p" ""
	done < <(find "$PASS_DIR" -type f -name '*.gpg' -not -path '*/.git/*' -printf '%P\n' 2>/dev/null |
		sed 's/\.gpg$//' | sort)
fi

((${#menu[@]})) || {
	notify-send -u critical "Secret picker" "no secrets found in $SECRETS_DIR or $PASS_DIR"
	exit 1
}

idx=$(printf '%s\n' "${menu[@]}" | rofi_pick "secret" "${#menu[@]}") || exit 0
[[ -n "$idx" ]] || exit 0

store="${stores[$idx]}"
choice="${names[$idx]}"

# Pipe straight to the clipboard so the value never lands in a shell variable,
# same rule `sec` follows. pipefail makes a decrypt failure fail the pipeline.
case "$store" in
yubikey)
	# Cue the tap: age blocks until the key is touched and there is no terminal
	# here to print to, so without this the wait just looks like nothing happened.
	notify-send -u normal -t 12000 "🔐 YubiKey" "Touch the key to unlock $choice"

	# A missed touch is by far the most common failure, and age-plugin-yubikey
	# reports it as "Failed to decrypt YubiKey stanza", which reads like a
	# key/recipient fault and sends you debugging the wrong thing. Say what it is.
	if ! age -d -i "$AGE_ID" "$SECRETS_DIR/$choice.age" 2>/dev/null | clip; then
		notify-send -u critical "🔐 Secret picker" "no tap registered, $choice not copied. Press again and touch the key."
		exit 1
	fi
	;;
pass)
	# No tap by design, so no cue: this store decrypts unattended, which is the
	# whole reason argos and cron can use it. head -n1 follows pass's own `-c`
	# convention that line 1 is the value and any later lines are metadata.
	if ! pass show "$choice" 2>/dev/null | head -n1 | clip; then
		notify-send -u critical "🔑 Secret picker" "pass show $choice failed (gpg-agent down, or entry unreadable)"
		exit 1
	fi
	;;
esac

notify-send -t 5000 "Secret picker" "$store: $choice copied to clipboard"
