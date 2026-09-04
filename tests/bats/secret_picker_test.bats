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

	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_BIN" "$SECRETS_DIR" "$PASSWORD_STORE_DIR"/{personal,work} \
		"$XDG_RUNTIME_DIR" "$DIRENV_ALLOW_DIR"
	: >"$AGE_RECIPIENTS"

	cat >"$STUB_BIN/rofi" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
exit 16
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
cmd="$1"
shift
while [[ "${1:-}" == -* ]]; do shift; done
case "$cmd" in
insert) mkdir -p "$store/$(dirname "$1")"; cat >"$store/$1.gpg" ;;
show) cat "$store/$1.gpg" ;;
*) exit 1 ;;
esac
EOF
	cat >"$STUB_BIN/age" <<'EOF'
#!/usr/bin/env bash
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
EOF
	chmod +x "$STUB_BIN"/*
	export PATH="$STUB_BIN:$PATH"
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

@test "the GTK form is centered, masks values, and defaults to work" {
	if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
		run "$GTK_GUI" --check --subtree personal --subtree work
	else
		run xvfb-run -a "$GTK_GUI" --check --subtree personal --subtree work
	fi

	[ "$status" -eq 0 ]
	[ "$output" = "GTK 3 ready; position=center-always; value-hidden=true; default-subtree=work" ]
}
