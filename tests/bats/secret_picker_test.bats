#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	PICKER="${SECRET_PICKER_UNDER_TEST:-$REPO_ROOT/scripts/__secret_picker.sh}"
	GTK_GUI="${SECRET_ADD_GUI_CHECK_UNDER_TEST:-$REPO_ROOT/scripts/__secret_add_gui.py}"
	export HOME="$BATS_TEST_TMPDIR/home"
	export SECRETS_DIR="$HOME/.secrets"
	export PASSWORD_STORE_DIR="$HOME/.password-store"
	export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
	export DIRENV_ALLOW_DIR="$BATS_TEST_TMPDIR/allow"
	export AGE_RECIPIENTS="$BATS_TEST_TMPDIR/recipients.txt"
	export FORM_RESULT="$BATS_TEST_TMPDIR/form-result"
	export GUI_LOG="$BATS_TEST_TMPDIR/gui.log"
	export NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"
	export CLIP="$BATS_TEST_TMPDIR/clipboard"
	export STORE_LOG="$BATS_TEST_TMPDIR/store.log"
	unset WAYLAND_DISPLAY

	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_BIN" "$SECRETS_DIR" "$PASSWORD_STORE_DIR"/{personal,work} \
		"$XDG_RUNTIME_DIR" "$DIRENV_ALLOW_DIR"
	: >"$AGE_RECIPIENTS"

	export ROFI_IN="$BATS_TEST_TMPDIR/rofi-in"
	cat >"$STUB_BIN/rofi" <<'EOF'
#!/usr/bin/env bash
cat >>"$ROFI_IN"
[[ -n "${ROFI_PICK:-}" ]] && printf '%s\n' "$ROFI_PICK"
exit "${ROFI_EXIT:-16}"
EOF
	export SECRET_ADD_GUI="$STUB_BIN/secret-add-gui"
	cat >"$SECRET_ADD_GUI" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$GUI_LOG"
cat "$FORM_RESULT"
EOF
	cat >"$STUB_BIN/pass" <<'EOF'
#!/usr/bin/env bash
store="$PASSWORD_STORE_DIR"
printf 'pass %s\n' "$*" >>"$STORE_LOG"
cmd="$1"
shift
while [[ "${1:-}" == -* ]]; do shift; done
case "$cmd" in
insert) mkdir -p "$store/$(dirname "$1")"; cat >"$store/$1.gpg" ;;
show) cat "$store/$1.gpg" ;;
rm) rm -f "$store/$1.gpg" ;;
*) exit 1 ;;
esac
EOF
	cat >"$STUB_BIN/age" <<'EOF'
#!/usr/bin/env bash
printf 'age %s\n' "$*" >>"$STORE_LOG"
while (($#)); do
	case "$1" in
	-o) out="$2"; shift 2 ;;
	-R) shift 2 ;;
	*) shift ;;
	esac
done
cat >"$out"
EOF
	cat >"$STUB_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
[[ " $* " == *" -p "* ]] && echo 42
exit 0
EOF
	cat >"$STUB_BIN/gdbus" <<'EOF'
#!/usr/bin/env bash
printf 'close %s\n' "${@: -1}" >>"$NOTIFY_LOG"
EOF
	cat >"$STUB_BIN/xsel" <<'EOF'
#!/usr/bin/env bash
cat >"$CLIP"
EOF
	chmod +x "$STUB_BIN"/*
	export PATH="$STUB_BIN:$PATH"
}

# An .envrc direnv allows, so secret_refs finds it.
allow_envrc() {
	printf '%s\n' "$1" >"$DIRENV_ALLOW_DIR/$(basename "$(dirname "$1")")"
}

# A bastion file whose header names a YubiKey and a backup key, with a marker
# where the payload would be, so a card that dumped the file would show it.
write_age_file() {
	printf 'age-encryption.org/v1\n-> piv-p256 Tg1 abc\nbody\n-> X25519 def\nbody\n--- mac\nAGE_PAYLOAD_LEAK\n' \
		>"$SECRETS_DIR/$1.age"
}

write_form() {
	printf '%s\x1f%s\x1f%s\x1f%s\x1f%s' "$1" "$2" "$3" "$4" "$5" >"$FORM_RESULT"
}

@test "Alt+a adds a pass secret from one form" {
	write_form pass work P_NEW 'pipe|safe' 'created in the picker'

	run "$PICKER"

	[ "$status" -eq 0 ]
	[ "$(cat "$PASSWORD_STORE_DIR/work/P_NEW.gpg")" = 'pipe|safe' ]
	grep -qx 'P_NEW | created in the picker' "$SECRETS_DIR/.descriptions"
	grep -qx -- '--subtree' "$GUI_LOG"
	grep -qx -- 'work' "$GUI_LOG"
	grep -q 'P_NEW added to pass/work' "$NOTIFY_LOG"
}

@test "Alt+a adds a YubiKey bastion secret without writing pass" {
	write_form YubiKey personal Y_NEW yubivalue 'needs a tap to read'

	run "$PICKER"

	[ "$status" -eq 0 ]
	[ "$(cat "$SECRETS_DIR/Y_NEW.age")" = yubivalue ]
	[ ! -e "$PASSWORD_STORE_DIR/personal/Y_NEW.gpg" ]
	grep -qx 'Y_NEW | needs a tap to read' "$SECRETS_DIR/.descriptions"
	grep -q 'Y_NEW added to the YubiKey bastion' "$NOTIFY_LOG"
}

@test "the add form refuses an empty value" {
	write_form pass work EMPTY '' 'must not exist'

	run "$PICKER"

	[ "$status" -ne 0 ]
	[ ! -e "$PASSWORD_STORE_DIR/work/EMPTY.gpg" ]
	grep -q 'value is required' "$NOTIFY_LOG"
}

@test "the GTK form is centered, shows values, and defaults to work" {
	if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
		run "$GTK_GUI" --check --subtree personal --subtree work
	else
		run xvfb-run -a "$GTK_GUI" --check --subtree personal --subtree work
	fi

	[ "$status" -eq 0 ]
	[ "$output" = "GTK 3 ready; position=center-always; value-hidden=false; default-subtree=work" ]
}

@test "Alt+c copies a pass secret's card with its .envrc references and no value" {
	printf 'PASS_VALUE_LEAK' >"$PASSWORD_STORE_DIR/personal/P_CARD.gpg"
	printf 'GPGKEY1\n' >"$PASSWORD_STORE_DIR/.gpg-id"
	printf 'P_CARD | used by the card test\n' >"$SECRETS_DIR/.descriptions"
	mkdir -p "$BATS_TEST_TMPDIR/proj"
	envrc="$BATS_TEST_TMPDIR/proj/.envrc"
	printf 'export X=1\n_pass_export P_CARD personal/P_CARD\n_pass_export OTHER_VAR personal/P_CARD\n' >"$envrc"
	allow_envrc "$envrc"
	export ROFI_PICK=0 ROFI_EXIT=17

	run "$PICKER"

	[ "$status" -eq 0 ]
	grep -qx 'Secret:       P_CARD' "$CLIP"
	grep -qx 'Store:        pass, no tap' "$CLIP"
	grep -qx 'Description:  used by the card test' "$CLIP"
	grep -qx 'Pass entry:   personal/P_CARD' "$CLIP"
	grep -qx "File:         $PASSWORD_STORE_DIR/personal/P_CARD.gpg" "$CLIP"
	grep -qx 'Encrypted to: gpg: GPGKEY1' "$CLIP"
	grep -Eqx 'Created:      [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' "$CLIP"
	grep -qx '.envrc refs:  2' "$CLIP"
	grep -qx "  $envrc:2  P_CARD" "$CLIP"
	grep -qx "  $envrc:3  OTHER_VAR" "$CLIP"
	! grep -q 'PASS_VALUE_LEAK' "$CLIP"
	! grep -q '^pass show' "$STORE_LOG" 2>/dev/null
	[ -e "$XDG_RUNTIME_DIR/secret-picker-blink" ]
}

@test "Alt+c on a bastion secret reads the age header, not the key" {
	write_age_file Y_CARD
	export ROFI_PICK=0 ROFI_EXIT=17

	run "$PICKER"

	[ "$status" -eq 0 ]
	grep -qx 'Store:        bastion, one YubiKey tap to read' "$CLIP"
	grep -qx 'Encrypted to: age: piv-p256, X25519' "$CLIP"
	grep -qx '.envrc refs:  0' "$CLIP"
	! grep -q 'AGE_PAYLOAD_LEAK' "$CLIP"
	[ ! -e "$STORE_LOG" ]
	[ ! -e "$XDG_RUNTIME_DIR/secret-picker-touch" ]
}

@test "Alt+c still copies the card of a secret in both stores" {
	write_age_file BOTH
	printf 'PASS_VALUE_LEAK' >"$PASSWORD_STORE_DIR/work/BOTH.gpg"
	export ROFI_PICK=0 ROFI_EXIT=17

	run "$PICKER"

	[ "$status" -eq 0 ]
	grep -qx 'Status:       conflict' "$CLIP"
	grep -qx "File:         $SECRETS_DIR/BOTH.age" "$CLIP"
	grep -qx "File:         $PASSWORD_STORE_DIR/work/BOTH.gpg" "$CLIP"
	! grep -q 'LEAK' "$CLIP"
}

# A fake bw: argv to a log, created items decoded to a file. BW_STATUS sets what
# `bw status` reports, except that the session "sess" a real unlock hands out
# stays unlocked, as a cached one would. setsid only records the lock timer: a
# real one would hold bats' output pipe open for the whole TTL.
stub_bw() {
	export BW_LOG="$BATS_TEST_TMPDIR/bw.log" BW_CREATED="$BATS_TEST_TMPDIR/bw-created"
	export BW_TIMER_LOG="$BATS_TEST_TMPDIR/bw-timer.log"
	export BW_SESSION_FILE_UNDER_TEST="$XDG_RUNTIME_DIR/secret-picker-bw-session"
	cat >"$STUB_BIN/setsid" <<'STUB'
#!/usr/bin/env bash
printf 'timer %s\n' "${*: -2}" >>"$BW_TIMER_LOG"
STUB
	cat >"$STUB_BIN/bw" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BW_LOG"
case "$1" in
status) s="${BW_STATUS:-unlocked}"; [[ "${BW_SESSION:-}" == sess ]] && s=unlocked; printf '{"status":"%s"}\n' "$s" ;;
sync | lock) ;;
unlock) [[ "$2 $3" == "--raw --passwordenv" && "${!4}" == master-pw ]] && printf 'sess' || exit 1 ;;
list) [[ "${BW_SESSION:-}" == sess || "${BW_SESSION:-}" == fake ]] && printf '[]' || exit 1 ;;
encode) base64 -w0 ;;
create) base64 -d >"$BW_CREATED" ;;
*) exit 1 ;;
esac
STUB
	chmod +x "$STUB_BIN/bw" "$STUB_BIN/setsid"
}

# An age stub that also decrypts: the .age file holds the plaintext here, so
# secret_read returns it without a real key or a real tap.
stub_age_decrypt() {
	cat >"$STUB_BIN/age" <<'STUB'
#!/usr/bin/env bash
printf 'age %s\n' "$*" >>"$STORE_LOG"
dec=0 out="" file=""
while (($#)); do
	case "$1" in
	-d) dec=1; shift ;;
	-o) out="$2"; shift 2 ;;
	-i | -R) shift 2 ;;
	*) file="$1"; shift ;;
	esac
done
if ((dec)); then cat "$file"; else cat >"$out"; fi
STUB
	chmod +x "$STUB_BIN/age"
}

# rofi answers from a script: one "output exit-code" line per call, and every
# call's prompt is logged, so a test can read what a confirm asked.
stub_rofi_seq() {
	export ROFI_SEQ="$BATS_TEST_TMPDIR/rofi-seq" ROFI_ARGS="$BATS_TEST_TMPDIR/rofi-args"
	printf '%s\n' "$@" >"$ROFI_SEQ"
	cat >"$STUB_BIN/rofi" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "$*" >>"$ROFI_ARGS"
read -r out code <"$ROFI_SEQ"
sed -i 1d "$ROFI_SEQ"
printf '%s\n' "$out"
exit "$code"
STUB
	chmod +x "$STUB_BIN/rofi"
}

@test "Alt+w saves a pass secret to Bitwarden, the value only on stdin" {
	stub_bw
	printf 'bwvalue' >"$PASSWORD_STORE_DIR/work/BW_ROW.gpg"
	export BW_SESSION=fake ROFI_PICK=0 ROFI_EXIT=18

	run "$PICKER"

	[ "$status" -eq 0 ]
	[ "$(jq -r .name "$BW_CREATED")" = BW_ROW ]
	[ "$(jq -r .login.password "$BW_CREATED")" = bwvalue ]
	! grep -q bwvalue "$BW_LOG"
	! grep -qx lock "$BW_LOG"
	grep -q 'BW_ROW saved to Bitwarden' "$NOTIFY_LOG"
}

@test "Alt+w while logged out asks for bw login and sends nothing" {
	stub_bw
	printf 'bwvalue' >"$PASSWORD_STORE_DIR/work/BW_ROW.gpg"
	unset BW_SESSION
	export BW_STATUS=unauthenticated ROFI_PICK=0 ROFI_EXIT=18

	run "$PICKER"

	[ "$status" -ne 0 ]
	[ ! -e "$BW_CREATED" ]
	grep -q "Run 'bw login' once in a terminal" "$NOTIFY_LOG"
}

@test "Alt+w on a bastion row with a missed tap sends nothing" {
	stub_bw
	: >"$SECRETS_DIR/BW_TAP.age"
	printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB_BIN/age"
	export BW_SESSION=fake ROFI_PICK=0 ROFI_EXIT=18

	run "$PICKER"

	[ "$status" -ne 0 ]
	[ ! -e "$BW_CREATED" ]
	[ ! -e "$XDG_RUNTIME_DIR/secret-picker-touch" ]
	grep -q 'no tap registered, BW_TAP not sent to Bitwarden' "$NOTIFY_LOG"
}

@test "Alt+w unlocks with the master password from rofi and keeps the session" {
	stub_bw
	printf 'bwvalue' >"$PASSWORD_STORE_DIR/work/BW_ROW.gpg"
	unset BW_SESSION
	export BW_STATUS=locked
	# First rofi call is the pick (Alt+w on row 0), the second the password field.
	stub_rofi_seq '0 18' 'master-pw 0'

	run "$PICKER"

	[ "$status" -eq 0 ]
	[ "$(jq -r .login.password "$BW_CREATED")" = bwvalue ]
	! grep -q master-pw "$BW_LOG"
	# kept for the next push, owner-only, with the lock timer armed
	[ "$(cat "$BW_SESSION_FILE_UNDER_TEST")" = sess ]
	[ "$(stat -c %a "$BW_SESSION_FILE_UNDER_TEST")" = 600 ]
	grep -qx "timer 900 $BW_SESSION_FILE_UNDER_TEST" "$BW_TIMER_LOG"
	! grep -qx lock "$BW_LOG"
}

@test "Alt+w with BW_SESSION_TTL=0 caches nothing and locks on exit" {
	stub_bw
	printf 'bwvalue' >"$PASSWORD_STORE_DIR/work/BW_ROW.gpg"
	unset BW_SESSION
	export BW_STATUS=locked BW_SESSION_TTL=0
	stub_rofi_seq '0 18' 'master-pw 0'

	run "$PICKER"

	[ "$status" -eq 0 ]
	[ "$(jq -r .login.password "$BW_CREATED")" = bwvalue ]
	[ ! -e "$BW_SESSION_FILE_UNDER_TEST" ]
	[ ! -e "$BW_TIMER_LOG" ]
	[ "$(tail -1 "$BW_LOG")" = lock ]
}

@test "Alt+w reads the master password from the bastion with a tap, no typing" {
	stub_bw
	stub_age_decrypt
	# Two rows, alphabetical: BW_MASTER_PASSWORD (index 0), BW_ROW (index 1).
	printf 'master-pw' >"$SECRETS_DIR/BW_MASTER_PASSWORD.age"
	printf 'bwvalue' >"$PASSWORD_STORE_DIR/work/BW_ROW.gpg"
	unset BW_SESSION
	export BW_STATUS=locked ROFI_PICK=1 ROFI_EXIT=18

	run "$PICKER"

	[ "$status" -eq 0 ]
	[ "$(jq -r .name "$BW_CREATED")" = BW_ROW ]
	[ "$(jq -r .login.password "$BW_CREATED")" = bwvalue ]
	# the master password was read from the bastion, not typed
	grep -q 'BW_MASTER_PASSWORD.age' "$STORE_LOG"
	# and never reaches a bw argv
	! grep -q master-pw "$BW_LOG"
	# the tap had a popup saying what it was for, closed once it landed; a pass
	# row needs no second tap, so it is not numbered
	grep -q 'Touch the YubiKey: unlock Bitwarden' "$NOTIFY_LOG"
	grep -qx 'close 42' "$NOTIFY_LOG"
	[ ! -e "$XDG_RUNTIME_DIR/secret-picker-touch" ]
}

@test "Alt+w on a bastion row after a fresh unlock numbers both taps" {
	stub_bw
	stub_age_decrypt
	printf 'master-pw' >"$SECRETS_DIR/BW_MASTER_PASSWORD.age"
	printf 'tapvalue' >"$SECRETS_DIR/BW_TAP.age"
	unset BW_SESSION
	# Rows: BW_MASTER_PASSWORD (0), BW_TAP (1).
	export BW_STATUS=locked ROFI_PICK=1 ROFI_EXIT=18

	run "$PICKER"

	[ "$status" -eq 0 ]
	[ "$(jq -r .login.password "$BW_CREATED")" = tapvalue ]
	grep -q 'Touch the YubiKey (1 of 2): unlock Bitwarden' "$NOTIFY_LOG"
	grep -q 'Touch the YubiKey (2 of 2): send BW_TAP to Bitwarden' "$NOTIFY_LOG"
	[ "$(grep -cx 'close 42' "$NOTIFY_LOG")" -eq 2 ]
}

@test "Alt+w with a cached session taps once, for the value only" {
	stub_bw
	stub_age_decrypt
	printf 'master-pw' >"$SECRETS_DIR/BW_MASTER_PASSWORD.age"
	printf 'tapvalue' >"$SECRETS_DIR/BW_TAP.age"
	printf 'sess' >"$XDG_RUNTIME_DIR/secret-picker-bw-session"
	unset BW_SESSION
	export BW_STATUS=locked ROFI_PICK=1 ROFI_EXIT=18

	run "$PICKER"

	[ "$status" -eq 0 ]
	[ "$(jq -r .login.password "$BW_CREATED")" = tapvalue ]
	# no unlock, no master read: the only age decrypt is the value's
	! grep -q '^unlock' "$BW_LOG"
	! grep -q 'BW_MASTER_PASSWORD.age' "$STORE_LOG"
	[ "$(grep -c '^age -d' "$STORE_LOG")" -eq 1 ]
	grep -q 'Touch the YubiKey: send BW_TAP to Bitwarden' "$NOTIFY_LOG"
	! grep -q 'of 2' "$NOTIFY_LOG"
	# and the window slides from this push
	grep -qx "timer 900 $BW_SESSION_FILE_UNDER_TEST" "$BW_TIMER_LOG"
}

@test "Alt+w drops a cached session idle past the TTL and unlocks afresh" {
	stub_bw
	printf 'bwvalue' >"$PASSWORD_STORE_DIR/work/BW_ROW.gpg"
	printf 'old-sess' >"$XDG_RUNTIME_DIR/secret-picker-bw-session"
	touch -d '-20 minutes' "$XDG_RUNTIME_DIR/secret-picker-bw-session"
	unset BW_SESSION
	export BW_STATUS=locked
	stub_rofi_seq '0 18' 'master-pw 0'

	run "$PICKER"

	[ "$status" -eq 0 ]
	grep -qx lock "$BW_LOG"
	grep -q '^unlock' "$BW_LOG"
	[ "$(cat "$BW_SESSION_FILE_UNDER_TEST")" = sess ]
}

@test "a push records the name, and the row shows the Bitwarden badge" {
	stub_bw
	printf 'bwvalue' >"$PASSWORD_STORE_DIR/work/BW_ROW.gpg"
	printf 'other' >"$PASSWORD_STORE_DIR/work/NOT_PUSHED.gpg"
	export BW_SESSION=fake ROFI_PICK=0 ROFI_EXIT=18

	run "$PICKER"

	[ "$status" -eq 0 ]
	grep -qx BW_ROW "$SECRETS_DIR/.bitwarden"
	! grep -q NOT_PUSHED "$SECRETS_DIR/.bitwarden"

	: >"$ROFI_IN"
	export ROFI_PICK="" ROFI_EXIT=1
	run "$PICKER"

	bw_glyph=$'\U000f11f1'
	grep "BW_ROW" "$ROFI_IN" | grep -qF "$bw_glyph"
	! grep "NOT_PUSHED" "$ROFI_IN" | grep -qF "$bw_glyph"
}

@test "Alt+x deletes the local copy and says the Bitwarden copy stays" {
	printf 'bwvalue' >"$PASSWORD_STORE_DIR/work/MOVED.gpg"
	printf 'MOVED\n' >"$SECRETS_DIR/.bitwarden"
	stub_rofi_seq '0 14' 'yes 0'

	run "$PICKER"

	[ "$status" -eq 0 ]
	[ ! -e "$PASSWORD_STORE_DIR/work/MOVED.gpg" ]
	grep -q 'delete MOVED from pass; the Bitwarden copy stays?' "$ROFI_ARGS"
	grep -q 'MOVED deleted from pass; the Bitwarden copy stays' "$NOTIFY_LOG"
	grep -qx MOVED "$SECRETS_DIR/.bitwarden"
}
