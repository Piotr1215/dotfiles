#!/usr/bin/env bash
# PROJECT: secret-picker
# Global rofi surface over every secret on this machine, one row per secret.
# Bound to <alt>+<ctrl>+p by the autokey script Scripts/SecretPicker.py.
#
# A secret is one object and the stores are properties of it (see
# __lib_secret_object.sh for the model and the invariant). This script is only
# the surface: it draws the object, and every write it performs is a call into
# that library, so the rules hold identically from the CLI.
#
#   Enter    copy the value to the clipboard (a bastion row taps, a pass row does not)
#   Alt+e    edit key, value and description in one buffer
#   Alt+p    promote to the bastion (drops the .envrc references with it)
#   Alt+d    demote to pass (costs a tap, since the value has to be read out)
#   Alt+l    reference it from an .envrc via _pass_export
#   Alt+x    delete it (from pass, the references go too)
#
# The tier MUST stay visible per row. A row that hid which store serves it would
# have you reach for a secret believing a tap guards it when nothing does. The
# icon says which, and the behaviour matches: the key copies instantly, the shield blinks.
#
# A name in both stores at once breaks the invariant, so it gets one row flagged
# with the alert glyph rather than two neutral rows that read as unrelated neighbours. That
# presentation is what let FRED_API_KEY drift into both stores unnoticed, where
# the tap-free copy silently made the bastion's tap decorative. The same flag
# covers an _pass_export whose entry is gone, which otherwise shows up only as a
# cd that quietly stops exporting.
#
# Listing everything costs nothing: names are not secret (pass names are already
# plaintext filenames), and nothing is decrypted until you pick a row. Keep it
# that way. Reading descriptions out of the entries themselves would mean
# decrypting the whole store to draw a menu, which is why they live in the
# plaintext ~/.secrets/.descriptions sidecar for both stores.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/__lib_rofi_theme.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/__lib_secret_object.sh"

# $1 = prompt, $2 = row count. Rows track the number of secrets instead of the
# stock lines count, which cut off the tail of the list and made whole secrets
# look missing until you thought to scroll. Capped so a growing store cannot
# produce a menu taller than the screen; past the cap you filter by typing (-i)
# and rofi draws a scrollbar, which a fixed count never admitted to.
#
# 1800px, not 1200px: rows are "badge NAME description" and the longest today is
# ~113 chars, which 900px silently truncated. The cap rose with the shared font
# bump, since taller rows fit fewer of them on the same screen.
#
# Alt+e/p/d/l/x are free in stock rofi (Alt is taken only by b, f, S, period,
# grave and the digits), so unlike Control+a in __value_picker.sh none of these
# needs its default unbound first.
rofi_pick() {
	local prompt="$1" rows="${2:-10}"
	((rows < 3)) && rows=3
	((rows > 26)) && rows=26
	rofi_theme 1800 "$rows"
	rofi -dmenu -i -p "$prompt" -format i -mesg "$MESG" \
		-kb-custom-1 "Alt+e" -kb-custom-2 "Alt+p" -kb-custom-3 "Alt+d" \
		-kb-custom-4 "Alt+l" -kb-custom-5 "Alt+x" -kb-custom-6 "Alt+o" \
		"${ROFI_THEME[@]}"
}

# A short list to choose from (pass subtree, .envrc path, yes/no). Text back, not
# an index: these lists are built and consumed in the same breath.
rofi_menu() {
	rofi_theme 1800 8
	rofi -dmenu -i -p "$1" "${ROFI_THEME[@]}"
}

# An indexed picker with no action keys, for the property list.
rofi_index() {
	local prompt="$1" rows="${2:-6}"
	((rows < 3)) && rows=3
	((rows > 26)) && rows=26
	rofi_theme 1800 "$rows"
	rofi -dmenu -i -p "$prompt" -format i "${ROFI_THEME[@]}"
}

# Editor spawn, the terminal probe from __snippet_picker.sh's Ctrl+E path: rofi
# has no tty, so anything editor-shaped needs its own window. Blocking, because
# both callers act on the result, one by reading the file back and one by
# re-allowing the .envrc files the edit just invalidated.
run_editor() {
	local term
	for term in alacritty ghostty x-terminal-emulator; do
		command -v "$term" >/dev/null 2>&1 || continue
		"$term" -e "${EDITOR:-nvim}" "$@"
		return 0
	done
	fail "no terminal found to run ${EDITOR:-nvim}"
}

confirm() {
	local answer
	answer=$(printf 'no\nyes\n' | rofi_menu "$1") || return 1
	[[ "$answer" == yes ]]
}

# Copy to whichever clipboard this session uses (mirrors .totp-copy.sh).
clip() {
	if [[ -n "$WAYLAND_DISPLAY" ]] && command -v wl-copy >/dev/null 2>&1; then
		wl-copy
	else
		xsel --clipboard
	fi
}

note() { notify-send -t 5000 "Secret picker" "$1"; }

# Both of this script's signals are markers the panel badge watches
# (.config/argos/totp.1s.sh), not notifications. A notification for a copy you
# just asked for is noise: it outlives the copy, steals a corner of the screen
# and puts the secret's name there, and reading it costs more than the copy did.
# The badge says the same thing without taking focus and is gone before you
# paste. Same for the tap cue, which used to leave a dead "Touch the key" card
# on screen long after the key had been touched.
BADGE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
TOUCH_CUE="$BADGE_DIR/secret-picker-touch"

# Yellow flashes: the value is on the clipboard.
blink_key() { touch "$BADGE_DIR/secret-picker-blink"; }

# Red flashing T: age is blocked on the key and wants a touch. The trap matters
# more than the on/off pair does. `fail` exits from inside the wait, and without
# it the T would still be asking for a touch nobody owes.
touch_cue_on() {
	touch "$TOUCH_CUE"
	trap 'rm -f "$TOUCH_CUE"' EXIT
}
touch_cue_off() { rm -f "$TOUCH_CUE"; }

fail() {
	notify-send -u critical "Secret picker" "$1"
	exit 1
}

# Tier icons are Nerd Font glyphs, NOT emoji: the font here is JetBrainsMono Nerd
# Font, whose nf-* glyphs are single-width, so the name column stays aligned.
# Emoji render double-width in monospace and would ragged every row.
#
# Written as \u escapes rather than pasted literals. A pasted glyph is invisible
# to review and survives nothing: this file already shipped once with an empty
# string where the shield belonged, which read as "1PASSWORD_PW has no icon"
# because that is simply the first bastion row in the list.
#   nf-fa-shield  U+F132  bastion, a tap guards it
#   nf-fa-key     U+F084  pass, no tap
#   nf-fa-link    U+F0C1  .envrc references, with their count
#   nf-fa-warning U+F071  the invariant is broken on this row
ICON_AGE=$'\uf132'
ICON_PASS=$'\uf084'
ICON_REF=$'\uf0c1'
ICON_ALERT=$'\uf071'

# Keys on one line, what the badges mean on the next. The badge legend is here
# because a glyph nobody can name is noise: the link count in particular reads as
# decoration until it says "this many .envrc files import this secret".
MESG="Enter copy   Alt+e edit   Alt+o open .envrc uses   Alt+l add .envrc   Alt+p promote   Alt+d demote   Alt+x delete
$ICON_AGE bastion, one tap    $ICON_PASS pass, no tap    ${ICON_REF}N referenced by N .envrc"

icon_for() {
	case "$1" in
	age) printf '%s' "$ICON_AGE" ;;
	pass) printf '%s' "$ICON_PASS" ;;
	*) printf '%s' "$ICON_ALERT" ;;
	esac
}

# Parallel arrays: the selection comes back as an index (rofi -format i), never
# as text to re-parse. Stripping the badge off the chosen row instead would break
# the moment a description contains the separator.
names=()
owners=()
entries=()
statuses=()
menu=()

while IFS=$'\t' read -r name owner entry refs status; do
	[[ -n "$name" ]] || continue
	names+=("$name")
	owners+=("$owner")
	entries+=("$entry")
	statuses+=("$status")

	badge="$(icon_for "$owner")"
	if ((refs > 0)); then
		badge+="$(printf " %s%-2s" "$ICON_REF" "$refs")"
	else
		badge+='    '
	fi
	[[ "$status" == ok ]] || badge+=" $ICON_ALERT"

	# The name column is the object; the detail column carries the store path, so
	# a leaf like loft.rocks still reads as work/kctx/vcluster/loft.rocks without
	# ragging the names the way a full path in the name column did.
	desc=""
	[[ "$owner" == pass || "$owner" == both ]] && desc="$entry"
	described="$(secret_desc_get "$name")"
	[[ -n "$described" ]] && desc="${desc:+$desc  }$described"
	[[ "$status" == ok ]] || desc="[$status] $desc"
	menu+=("$(printf '%s  %-38s %s' "$badge" "$name" "$desc")")
done < <(secret_index)

((${#menu[@]})) || fail "no secrets found in $SECRETS_DIR or $PASS_DIR"

if idx=$(printf '%s\n' "${menu[@]}" | rofi_pick "secret" "${#menu[@]}"); then
	action=copy
else
	# rofi exits 10..14 for kb-custom-1..5 and still prints the selection.
	# Read $? first, before any other command clobbers it.
	case $? in
	10) action="edit" ;;
	11) action="promote" ;;
	12) action="demote" ;;
	13) action="link" ;;
	14) action="delete" ;;
	15) action="refs" ;;
	*) exit 0 ;;
	esac
fi

[[ "$idx" =~ ^[0-9]+$ ]] || exit 0
name="${names[$idx]}"
owner="${owners[$idx]}"
entry="${entries[$idx]}"
status="${statuses[$idx]}"

# Nothing but a copy is safe on a row whose object is ambiguous, and a copy is
# not safe either: which store answered would be a coin toss.
case "$status" in
ok) ;;
conflict) fail "$name is in both stores. Drop the copy you do not want: secrm $name, or pass rm $entry" ;;
*) fail "$name: $status. See: __lib_secret_object.sh audit" ;;
esac

case "$action" in
copy)
	if [[ "$owner" == age ]]; then
		# Cue the tap: age blocks until the key is touched and there is no terminal
		# here to print to, so without this the wait just looks like nothing happened.
		touch_cue_on
		# A missed touch is by far the most common failure, and age-plugin-yubikey
		# reports it as "Failed to decrypt YubiKey stanza", which reads like a
		# key/recipient fault and sends you debugging the wrong thing. Say what it is.
		secret_read "$name" 2>/dev/null | clip ||
			fail "no tap registered, $name not copied. Press again and touch the key."
		touch_cue_off
	else
		secret_read "$name" 2>/dev/null | clip ||
			fail "pass show $entry failed (gpg-agent down, or entry unreadable)"
	fi
	blink_key
	;;

edit)
	# One buffer holding what the object is, edited the way everything else on this
	# machine is edited. $XDG_RUNTIME_DIR is tmpfs and 0700, so the form never
	# touches disk-backed /tmp, and it is shredded on every exit path.
	#
	# The current value is deliberately NOT written into it. Prefilling would mean
	# decrypting to open the form, which costs a YubiKey tap just to fix a typo in
	# a description, and would put the live secret in a file for the length of an
	# editing session. Empty means unchanged; anything typed replaces it.
	form="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/secret-edit.XXXXXX")"
	chmod 600 "$form"
	trap 'shred -u "$form" 2>/dev/null || rm -f "$form"' EXIT
	described="$(secret_desc_get "$name")"
	{
		printf '# %s in %s. Edit, save, quit.\n' "$name" "$owner"
		printf '# key         renames it, and any .envrc reference follows.\n'
		printf '# value       empty keeps the current one; single line.\n'
		printf '# description shown in this picker, shared by both stores.\n'
		printf 'key: %s\n' "$name"
		printf 'value:\n'
		printf 'description: %s\n' "$described"
	} >"$form"

	run_editor "$form"

	# Whitespace around a field is always an accident here, never part of a key,
	# a token or a description, and a trailing space on the value line would be
	# saved into the secret where nothing would ever show it to you again.
	field_of() { sed -n "s/^$1:[[:space:]]*//p" "$form" | head -1 | sed 's/[[:space:]]*$//'; }
	newkey=$(field_of key)
	newval=$(field_of value)
	newdesc=$(field_of description)
	changed=()

	if [[ -n "$newkey" && "$newkey" != "$name" ]]; then
		secret_rename "$name" "$newkey" || fail "could not rename $name to $newkey"
		name="$newkey"
		changed+=(key)
	fi
	if [[ -n "$newval" ]]; then
		# A YubiKey in OTP mode types 44 modhex characters when touched, so a reflex
		# tap into this buffer would land a spent OTP in the value line and be saved
		# as the secret. Nothing legitimate here is 44 characters of modhex.
		[[ "$newval" =~ ^[cbdefghijklnrtuv]{44}$ ]] &&
			fail "that is a YubiKey OTP, not a value. $name was left alone."
		printf '%s' "$newval" | secret_set "$name" || fail "could not write $name"
		changed+=(value)
	fi
	if [[ "$newdesc" != "$described" ]]; then
		secret_desc_set "$name" "$newdesc"
		changed+=(description)
	fi

	((${#changed[@]})) || exit 0
	note "$name: ${changed[*]} updated"
	;;
promote)
	[[ "$owner" == pass ]] || fail "$name is already in the bastion"
	confirm "promote $name to the bastion? (removes it from pass and any .envrc)" || exit 0
	secret_promote "$name" || fail "promote failed for $name"
	note "$name promoted to the bastion; reads now need a tap"
	;;

demote)
	[[ "$owner" == age ]] || fail "$name is already in pass"
	sub=$(find "$PASS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.git' -printf '%f\n' |
		sort | rofi_menu "demote $name into which pass subtree") || exit 0
	[[ -n "$sub" ]] || exit 0
	touch_cue_on
	secret_demote "$name" "$sub" || fail "demote failed for $name (no tap, or pass insert failed)"
	touch_cue_off
	note "$name demoted to $sub/$name; no tap guards it now"
	;;

link)
	[[ "$owner" == pass ]] || fail "only a pass secret can be referenced from an .envrc"
	# Only files that do not already import it: the ones that do are Alt+o's job,
	# and a second _pass_export line for the same entry would export it twice.
	linked=$(secret_refs "$name" | cut -f1 | sort -u)
	choices=$(secret_envrc_files | grep -vxF -f <(printf '%s\n' "$linked") || true)
	[[ -n "$choices" ]] || fail "every allowed .envrc already imports $name"
	rfile=$(printf '%s\n' "$choices" | rofi_menu "add $name to which .envrc") || exit 0
	[[ -n "$rfile" ]] || exit 0
	secret_link "$name" "$rfile" || fail "could not add the reference to $rfile"
	note "$rfile now exports $name"
	;;

refs)
	# Almost always one line in one file, so that case opens the file on the line
	# and nothing else. The quickfix list is the fallback for the rare secret with
	# several references, which happens both across files and within one file,
	# since the same entry can be exported under more than one name.
	mapfile -t reflines < <(secret_refs "$name")
	((${#reflines[@]})) || fail "$name is not imported by any .envrc"

	if ((${#reflines[@]} == 1)); then
		IFS=$'\t' read -r rfile rline rvar rentry <<<"${reflines[0]}"
		run_editor "+$rline" "$rfile"
	else
		qf="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/secret-refs.XXXXXX")"
		trap 'rm -f "$qf"' EXIT
		for ref in "${reflines[@]}"; do
			IFS=$'\t' read -r rfile rline rvar rentry <<<"$ref"
			printf '%s:%s: _pass_export %s %s\n' "$rfile" "$rline" "$rvar" "$rentry" >>"$qf"
		done
		run_editor -q "$qf" -c copen
	fi

	# Any edit revokes direnv's hash for the file, by hand as much as by script.
	while IFS= read -r rfile; do secret_direnv_allow "$rfile"; done < <(printf '%s\n' "${reflines[@]}" | cut -f1 | sort -u)
	note "$name: .envrc references re-allowed"
	;;
delete)
	refs=$(secret_refs "$name" | wc -l)
	((refs > 0)) && also=" and its $refs .envrc reference(s)" || also=""
	confirm "delete $name from $owner$also?" || exit 0
	secret_rm "$name" || fail "delete failed for $name"
	note "$name deleted from $owner"
	;;
esac
