#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	WRAPPER="$REPO_ROOT/scripts/__accept_editor.sh"
	EDIT_FILE="$BATS_TEST_TMPDIR/prompt.md"
	ACCEPT_FILE="$BATS_TEST_TMPDIR/accepted"
	printf 'unchanged prompt\n' > "$EDIT_FILE"
}

@test "closing the editor without a write does not mark the prompt accepted" {
	run env \
		CAPABILITY_PICKER_ACCEPT_FILE="$ACCEPT_FILE" \
		CAPABILITY_PICKER_EDITOR=true \
		bash "$WRAPPER" "$EDIT_FILE"

	[ "$status" -eq 0 ]
	[ ! -e "$ACCEPT_FILE" ]
}

@test "writing the file marks the prompt accepted even when content stays unchanged" {
	local editor="$BATS_TEST_TMPDIR/write-editor"
	cat > "$editor" <<'EOF'
#!/usr/bin/env bash
touch "$1"
EOF
	chmod +x "$editor"

	run env \
		CAPABILITY_PICKER_ACCEPT_FILE="$ACCEPT_FILE" \
		CAPABILITY_PICKER_EDITOR="$editor" \
		bash "$WRAPPER" "$EDIT_FILE"

	[ "$status" -eq 0 ]
	[ -e "$ACCEPT_FILE" ]
}

@test "editor failures propagate and do not accept the prompt" {
	run env \
		CAPABILITY_PICKER_ACCEPT_FILE="$ACCEPT_FILE" \
		CAPABILITY_PICKER_EDITOR=false \
		bash "$WRAPPER" "$EDIT_FILE"

	[ "$status" -ne 0 ]
	[ ! -e "$ACCEPT_FILE" ]
}
