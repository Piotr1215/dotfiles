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
#   Alt+c    copy its card: every fact about it except the value, never a tap
#   Alt+a    add a secret to pass or the YubiKey bastion
#   Alt+e    edit key, value and description in one buffer
#   Alt+y    move it to the YubiKey (drops the .envrc references with it)
#   Alt+p    move it to pass (costs a tap, since the value has to be read out)
#   Alt+l    reference it from an .envrc via _pass_export
#   Alt+x    delete it here (the references go too; a Bitwarden copy stays)
#   Alt+b    save a copy to Bitwarden (asks before replacing an item). One tap per
#            push: the unlock is reused for BW_SESSION_TTL seconds after the last
#            push, so only the first push after a pause taps twice, and each tap
#            gets a popup naming what it is for
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
SECRET_ADD_GUI="${SECRET_ADD_GUI:-$SCRIPT_DIR/__secret_add_gui.py}"

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
# Alt+a/c/e/y/p/l/o/x are free in stock rofi (Alt is taken only by b, f, S,
# period, grave and the digits). Alt+b is not: stock rofi moves a word back on
# it. Bitwarden takes it anyway, the same way __value_picker.sh takes Control+a,
# by rebinding move-word-back to its other default, Control+Left, alone.
#
# The move keys name where the secret goes: Alt+y the YubiKey, Alt+p pass, Alt+b
# Bitwarden. They were promote and demote (Alt+p, Alt+d) until Bitwarden became a
# third destination, when "promote" stopped saying where to and Alt+p, which went
# to the YubiKey, read as "pass".
rofi_pick() {
	local prompt="$1" rows="${2:-10}"
	((rows < 3)) && rows=3
	((rows > 26)) && rows=26
	rofi_theme 1800 "$rows"
	rofi -dmenu -i -p "$prompt" -format i -mesg "$MESG" \
		-kb-custom-1 "Alt+e" -kb-custom-2 "Alt+y" -kb-custom-3 "Alt+p" \
		-kb-custom-4 "Alt+l" -kb-custom-5 "Alt+x" -kb-custom-6 "Alt+o" \
		-kb-custom-7 "Alt+a" -kb-custom-8 "Alt+c" -kb-custom-9 "Alt+b" \
		-kb-move-word-back "Control+Left" \
		"${ROFI_THEME[@]}"
}

# The secret holding the Bitwarden master password. In the bastion, Alt+b reads
# it with a YubiKey tap instead of a typed prompt: the tap is the confirm. In
# pass it is read with no tap at all, which makes every pushed bastion secret as
# readable as a pass one; that trade is yours to make with Alt+p. Missing, a
# typed prompt. Store it once with Alt+a under this name. Override per machine.
BW_MASTER_SECRET="${BW_MASTER_SECRET:-BW_MASTER_PASSWORD}"

# How long an unlock is reused after the last push, in seconds. The YubiKey here
# has touch policy Always: every age decrypt is its own touch, so a bastion
# secret pushed through a fresh unlock costs two (master, then value). Reusing
# the session is the only way to one tap that keeps the master in the bastion.
# 15 minutes is Bitwarden's own default vault timeout. 0 locks after each push.
BW_SESSION_TTL="${BW_SESSION_TTL:-900}"

# A Bitwarden session for this push. An already exported BW_SESSION is used as is
# and left alone. Then a session cached by an earlier push, if bw still calls it
# unlocked and it was used within BW_SESSION_TTL. Otherwise a fresh unlock with
# the master password from $BW_MASTER_SECRET or a rofi password field; it reaches
# bw through the environment, never an argv. `bw login` stays a one-time terminal
# step a picker cannot do: it can ask for a 2FA code, a device approval or SSO.
# $1 labels the unlock tap, so "1 of 2" says up front that a second one follows.
bw_session() {
	local state pw owner
	command -v bw >/dev/null 2>&1 || fail "bw CLI not found"
	[[ -n "${BW_SESSION:-}" ]] && return 0
	if bw_session_cached; then
		bw_session_keep
		return 0
	fi
	state=$(bw status 2>/dev/null | jq -r '.status // empty') || state=""
	[[ "$state" == unauthenticated ]] && fail "Bitwarden is logged out. Run 'bw login' once in a terminal, then Alt+b again."
	owner=$(secret_locate "$BW_MASTER_SECRET" 2>/dev/null | cut -f2)
	case "$owner" in
	age)
		# The tap that reads the master password is the confirmation. A missed tap
		# returns nothing, so unlock fails below rather than on an empty password.
		touch_cue_on "Touch the YubiKey${1:+ ($1)}: unlock Bitwarden"
		pw=$(secret_read "$BW_MASTER_SECRET" 2>/dev/null) ||
			{ touch_cue_off; fail "no tap registered, Bitwarden not unlocked. Press Alt+b again and touch the key."; }
		touch_cue_off
		BW_UNLOCK_TAPPED=1
		;;
	pass)
		pw=$(secret_read "$BW_MASTER_SECRET" 2>/dev/null) || fail "could not read $BW_MASTER_SECRET from pass (gpg-agent down?)"
		;;
	*)
		# rofi 1.7 dropped -lines; the empty list is hidden through the theme instead.
		rofi_theme 900 1
		pw=$(rofi -dmenu -password -p "Bitwarden master password" "${ROFI_THEME[@]}" \
			-theme-str 'listview { enabled: false; }' </dev/null) || exit 0
		;;
	esac
	[[ -n "$pw" ]] || exit 0
	BW_SESSION=$(BW_MASTER="$pw" bw unlock --raw --passwordenv BW_MASTER 2>/dev/null) || BW_SESSION=""
	unset pw
	[[ -n "$BW_SESSION" ]] || fail "Bitwarden unlock failed (wrong master password, or the stored $BW_MASTER_SECRET is wrong)."
	export BW_SESSION
	# Kept before the push runs, so a missed second tap retries with one tap.
	bw_session_keep
}

# The cached session, if bw still calls it unlocked and it was used within the
# TTL. Checked rather than trusted: a `bw lock` or logout elsewhere kills it, and
# the lock timer below runs on monotonic time, which stands still in suspend.
bw_session_cached() {
	local sess idle
	((BW_SESSION_TTL > 0)) && [[ -r "$BW_SESSION_FILE" ]] || return 1
	idle=$(($(date +%s) - $(stat -c %Y "$BW_SESSION_FILE")))
	if ((idle >= BW_SESSION_TTL)); then
		rm -f "$BW_SESSION_FILE"
		bw lock >/dev/null 2>&1 || true
		return 1
	fi
	sess=$(<"$BW_SESSION_FILE")
	if [[ "$(BW_SESSION="$sess" bw status 2>/dev/null | jq -r '.status // empty')" != unlocked ]]; then
		rm -f "$BW_SESSION_FILE"
		return 1
	fi
	BW_SESSION="$sess"
	export BW_SESSION
}

# Cache the session in tmpfs, 0600 in the 0700 runtime dir, and (re)arm the lock.
# The window slides: every push restarts it. Each push leaves a sleeper behind;
# a sleeper that wakes to a file touched since its own deadline leaves it be, so
# only the one armed by the last push locks. setsid, so closing rofi spares it.
# With BW_SESSION_TTL=0 nothing is cached and the vault locks when this exits.
bw_session_keep() {
	if ((BW_SESSION_TTL <= 0)); then
		BW_LOCK_ON_EXIT=1
		return 0
	fi
	(
		umask 077
		printf '%s' "$BW_SESSION" >"$BW_SESSION_FILE"
	)
	# shellcheck disable=SC2016 # expands in the child bash, from its own $1 and $2
	setsid -f bash -c '
		sleep "$1"
		[[ -f "$2" ]] || exit 0
		(($(date +%s) - $(stat -c %Y "$2") >= $1)) || exit 0
		rm -f "$2"
		bw lock >/dev/null 2>&1
	' secret-picker-bw-lock "$BW_SESSION_TTL" "$BW_SESSION_FILE" </dev/null >/dev/null 2>&1 || true
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
BW_SESSION_FILE="$BADGE_DIR/secret-picker-bw-session"
TOUCH_POPUP=""

# Yellow flashes: the value is on the clipboard.
blink_key() { touch "$BADGE_DIR/secret-picker-blink"; }

# Red flashing T: age is blocked on the key and wants a touch. The trap matters
# more than the on/off pair does. `fail` exits from inside the wait, and without
# it the T would still be asking for a touch nobody owes.
#
# $1, when given, also raises a popup saying what the touch is for. The Bitwarden
# push uses it: there a touch can be the first of two, and a badge alone did not
# say a second one was owed. The popup is closed by id the moment the touch
# lands, so it never outlives the wait the way the old card did.
touch_cue_on() {
	touch "$TOUCH_CUE"
	TOUCH_POPUP=""
	[[ -n "${1:-}" ]] && { TOUCH_POPUP=$(notify-send -p -e -u critical "Secret picker" "$1" 2>/dev/null) || TOUCH_POPUP=""; }
	trap on_exit EXIT
}
touch_cue_off() {
	rm -f "$TOUCH_CUE"
	if [[ "$TOUCH_POPUP" =~ ^[0-9]+$ ]]; then
		gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
			--method org.freedesktop.Notifications.CloseNotification "$TOUCH_POPUP" >/dev/null 2>&1 || true
	fi
	TOUCH_POPUP=""
}
on_exit() {
	touch_cue_off
	[[ -n "${BW_LOCK_ON_EXIT:-}" ]] && { bw lock >/dev/null 2>&1 || true; }
	return 0
}

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
#   nf-md-cloud_lock U+F11F1  Bitwarden holds an item with this name
ICON_AGE=$'\uf132'
ICON_PASS=$'\uf084'
ICON_REF=$'\uf0c1'
ICON_ALERT=$'\uf071'
ICON_BW=$'\U000f11f1'

# Keys on one line, what the badges mean on the next. The badge legend is here
# because a glyph nobody can name is noise: the link count in particular reads as
# decoration until it says "this many .envrc files import this secret".
MESG="Enter copy   Alt+c card   Alt+a add   Alt+e edit   Alt+o open .envrc uses   Alt+l add .envrc   Alt+y move to YubiKey   Alt+p move to pass   Alt+b copy to Bitwarden   Alt+x delete
$ICON_AGE YubiKey, one tap    $ICON_PASS pass, no tap    $ICON_BW in Bitwarden    ${ICON_REF}N referenced by N .envrc"

icon_for() {
	case "$1" in
	age) printf '%s' "$ICON_AGE" ;;
	pass) printf '%s' "$ICON_PASS" ;;
	*) printf '%s' "$ICON_ALERT" ;;
	esac
}

add_secret() {
	local result store sub name value description error owner target
	local -a gui_args=("$SECRET_ADD_GUI")

	[[ -x "$SECRET_ADD_GUI" ]] || fail "secret add form is not executable: $SECRET_ADD_GUI"
	while IFS= read -r sub; do
		[[ -n "$sub" ]] && gui_args+=(--subtree "$sub")
	done < <(find "$PASS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.git' -printf '%f\n' 2>/dev/null | sort)

	result=$("${gui_args[@]}" 2>/dev/null) || return 0
	IFS=$'\x1f' read -r store sub name value description <<<"$result"

	[[ -n "$name" ]] || fail "name is required"
	[[ -n "$value" ]] || fail "value is required; nothing was written"
	# A physical tap in OTP mode must not become the value by accident.
	[[ ! "$value" =~ ^[cbdefghijklnrtuv]{44}$ ]] ||
		fail "that is a YubiKey OTP, not a secret value. Nothing was written."

	case "$store" in
	pass) owner=pass; target="pass/$sub" ;;
	YubiKey) owner=age; target="the YubiKey" ;;
	*) fail "choose pass or YubiKey" ;;
	esac

	if ! error=$(printf '%s' "$value" | secret_create "$name" "$owner" "$sub" 2>&1); then
		unset value result
		fail "${error#secret: }"
	fi
	unset value result
	secret_desc_set "$name" "$description" || fail "$name was added, but its description could not be saved"
	note "$name added to $target"
}

# Parallel arrays: the selection comes back as an index (rofi -format i), never
# as text to re-parse. Stripping the badge off the chosen row instead would break
# the moment a description contains the separator.
names=()
owners=()
entries=()
statuses=()
menu=()

# Read once, not per row: the cache of Bitwarden item names (see the export
# section of __lib_secret_object.sh), as of the last push.
declare -A in_bw=()
if [[ -r "$BW_NAMES_FILE" ]]; then
	while IFS= read -r bwname; do
		[[ -n "$bwname" ]] && in_bw["$bwname"]=1
	done <"$BW_NAMES_FILE"
fi

while IFS=$'\t' read -r name owner entry refs status; do
	[[ -n "$name" ]] || continue
	names+=("$name")
	owners+=("$owner")
	entries+=("$entry")
	statuses+=("$status")

	badge="$(icon_for "$owner")"
	if [[ -n "${in_bw[$name]:-}" ]]; then
		badge+=" $ICON_BW"
	else
		badge+='  '
	fi
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

secret_count=${#menu[@]}
((secret_count)) || menu=("No secrets yet. Press Alt+a to add one.")

if idx=$(printf '%s\n' "${menu[@]}" | rofi_pick "secret" "${#menu[@]}"); then
	((secret_count)) && action=copy || action=add
else
	# rofi exits 10..18 for kb-custom-1..9 and still prints the selection.
	# Read $? first, before any other command clobbers it.
	case $? in
	18) action="bitwarden" ;;
	17) action="card" ;;
	10) action="edit" ;;
	11) action="to_yubikey" ;;
	12) action="to_pass" ;;
	13) action="link" ;;
	14) action="delete" ;;
	15) action="refs" ;;
	16) action="add" ;;
	*) exit 0 ;;
	esac
fi

if [[ "$action" == add ]]; then
	add_secret
	exit 0
fi

[[ "$idx" =~ ^[0-9]+$ ]] || exit 0
name="${names[$idx]}"
owner="${owners[$idx]}"
entry="${entries[$idx]}"
status="${statuses[$idx]}"

# Before the status gate on purpose: the card reads no store, so it is safe on a
# broken row, and a broken row is where its facts are most wanted.
if [[ "$action" == card ]]; then
	card=$(secret_card "$name") || fail "no card for $name"
	printf '%s\n' "$card" | clip
	blink_key
	exit 0
fi

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
	stale=""
	[[ " ${changed[*]} " == *" value "* ]] && secret_bw_has "$name" &&
		stale="; Bitwarden still has the old value, Alt+b to update it"
	note "$name: ${changed[*]} updated$stale"
	;;
to_yubikey)
	[[ "$owner" == pass ]] || fail "$name is already on the YubiKey"
	confirm "move $name to the YubiKey? (removes it from pass and any .envrc)" || exit 0
	secret_promote "$name" || fail "could not move $name to the YubiKey"
	note "$name moved to the YubiKey; reads now need a tap"
	;;

to_pass)
	[[ "$owner" == age ]] || fail "$name is already in pass"
	sub=$(find "$PASS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.git' -printf '%f\n' |
		sort | rofi_menu "move $name to which pass subtree") || exit 0
	[[ -n "$sub" ]] || exit 0
	touch_cue_on
	secret_demote "$name" "$sub" || fail "could not move $name to pass (no tap, or pass insert failed)"
	touch_cue_off
	note "$name moved to pass as $sub/$name; no tap guards it now"
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
bitwarden)
	# The value goes picker → library → bw over pipes only, the same path a copy
	# takes to the clipboard. secret_bw_push refuses an empty read, so a missed tap
	# can never blank the password in Bitwarden.
	trap on_exit EXIT
	if [[ "$owner" == age ]]; then bw_session "1 of 2"; else bw_session; fi
	bw sync >/dev/null 2>&1 || true
	# Rebuilt here, not only after a push: an open session is the one moment the
	# names can be read, and a push that ends at "replace?" with no still has to
	# leave the badges right, including items pushed before the badge existed.
	secret_bw_names_refresh 2>/dev/null || true
	existing=$(secret_bw_item_id "$name" 2>&1) || fail "${existing#secret: }"
	if [[ -n "$existing" ]]; then
		confirm "replace the password in the Bitwarden item $name?" || exit 0
	fi
	if [[ "$owner" == age ]]; then
		step=""
		[[ -n "${BW_UNLOCK_TAPPED:-}" ]] && step=" (2 of 2)"
		touch_cue_on "Touch the YubiKey$step: send $name to Bitwarden"
	fi
	if ! error=$(secret_read "$name" 2>/dev/null | secret_bw_push "$name" 2>&1); then
		[[ "$owner" == age && "$error" == *"empty value"* ]] &&
			fail "no tap registered, $name not sent to Bitwarden. Press again and touch the key."
		fail "${error#secret: }"
	fi
	touch_cue_off
	if [[ -n "$existing" ]]; then note "$name updated in Bitwarden"; else note "$name saved to Bitwarden"; fi
	;;

delete)
	# Delete is local. A Bitwarden copy is where a moved secret lives on, so it is
	# left alone, and the row goes: it lists what this machine holds.
	refs=$(secret_refs "$name" | wc -l)
	((refs > 0)) && also=" and its $refs .envrc reference(s)" || also=""
	kept=""
	secret_bw_has "$name" && kept="; the Bitwarden copy stays"
	confirm "delete $name from $owner$also$kept?" || exit 0
	secret_rm "$name" || fail "delete failed for $name"
	note "$name deleted from $owner$kept"
	;;
esac
