#!/usr/bin/env bats

# __desktop_bindings_gen.sh replaced a hand-typed list that had drifted: it
# advertised a hotkey AutoKey had disabled and never gained the ones added
# since. These tests pin the three rules that drift broke.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	GEN="$REPO_ROOT/scripts/__desktop_bindings_gen.sh"

	export AUTOKEY_DATA="$BATS_TEST_TMPDIR/autokey"
	export AUTOKEY_OUT="$BATS_TEST_TMPDIR/autokey.conf"
	export GNOME_OUT="$BATS_TEST_TMPDIR/gnome.conf"
	mkdir -p "$AUTOKEY_DATA/Scripts"

	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_BIN"
	export PATH="$STUB_BIN:$PATH"
}

# AutoKey names an item's JSON with a leading dot and its body without one.
write_item() {
	local name="$1" json="$2"
	printf '%s' "$json" > "$AUTOKEY_DATA/Scripts/.${name}.json"
	printf 'pass\n' > "$AUTOKEY_DATA/Scripts/${name}.py"
}

stub_gsettings() {
	cat > "$STUB_BIN/gsettings" <<'EOF'
#!/usr/bin/env bash
case "$*" in
	*"media-keys custom-keybindings") printf "['/custom0/']\n" ;;
	*"custom-keybinding:/custom0/ binding") printf "'<Primary><Shift><Alt>c'\n" ;;
	*"custom-keybinding:/custom0/ name") printf "'Claude'\n" ;;
	*"custom-keybinding:/custom0/ command") printf "'/bin/true'\n" ;;
esac
EOF
	chmod +x "$STUB_BIN/gsettings"
}

@test "a hotkey with the trigger enabled is emitted, in reading order" {
	write_item SecretPicker '{"description":"SecretPicker","modes":[3],"hotkey":{"modifiers":["<alt>","<ctrl>"],"hotKey":"p"}}'
	stub_gsettings
	bash "$GEN"
	grep -q '^ctrl+alt+p (M-C-p)|SecretPicker  ' "$AUTOKEY_OUT"
}

@test "a hotkey record whose trigger is off is skipped" {
	write_item CreateTask '{"description":"CreateTask","modes":[],"hotkey":{"modifiers":["<alt>","<ctrl>"],"hotKey":"t"}}'
	stub_gsettings
	bash "$GEN"
	run grep -c 'CreateTask' "$AUTOKEY_OUT"
	[ "$output" = "0" ]
}

@test "a folder record is labelled by title and carries no script path" {
	printf '%s' '{"type":"folder","title":"My Phrases","modes":[3],"hotkey":{"modifiers":["<ctrl>"],"hotKey":"<f7>"}}' \
		> "$AUTOKEY_DATA/Scripts/.folder.json"
	stub_gsettings
	bash "$GEN"
	grep -qx 'ctrl+f7 (C-f7)|My Phrases (folder menu)' "$AUTOKEY_OUT"
}

@test "gnome modifiers normalize to the same order as autokey" {
	stub_gsettings
	bash "$GEN"
	grep -q '^ctrl+alt+shift+c (M-C-S-c)|Claude  /bin/true$' "$GNOME_OUT"
}

@test "a bare gnome key keeps its key name" {
	cat > "$STUB_BIN/gsettings" <<'EOF'
#!/usr/bin/env bash
case "$*" in
	*"media-keys custom-keybindings") printf "['/custom0/']\n" ;;
	*"custom-keybinding:/custom0/ binding") printf "'<Shift>Print'\n" ;;
	*"custom-keybinding:/custom0/ name") printf "'Flameshot share'\n" ;;
	*"custom-keybinding:/custom0/ command") printf "'/bin/true'\n" ;;
esac
EOF
	chmod +x "$STUB_BIN/gsettings"
	bash "$GEN"
	grep -q '^shift+print (S-Print)|Flameshot share  /bin/true$' "$GNOME_OUT"
}

@test "without gsettings the gnome index is left alone, not emptied" {
	printf 'keep me\n' > "$GNOME_OUT"
	write_item SecretPicker '{"description":"SecretPicker","modes":[3],"hotkey":{"modifiers":["<alt>","<ctrl>"],"hotKey":"p"}}'
	# A PATH holding every tool the generator needs except gsettings, which
	# lives in the same system bindir and so cannot simply be shadowed.
	local bare="$BATS_TEST_TMPDIR/bare"
	mkdir -p "$bare"
	for t in bash python3 sed grep sort tr; do ln -sf "$(command -v "$t")" "$bare/$t"; done
	run env PATH="$bare" bash "$GEN"
	[ "$status" -eq 0 ]
	grep -qx 'keep me' "$GNOME_OUT"
	grep -q '^ctrl+alt+p (M-C-p)|' "$AUTOKEY_OUT"
}

@test "a key carries its tmux-notation alias, so 'm-c-h' finds it" {
	write_item OpenCustomHelp '{"description":"OpenCustomHelp","modes":[3],"hotkey":{"modifiers":["<alt>","<ctrl>"],"hotKey":"h"}}'
	stub_gsettings
	bash "$GEN"
	grep -q 'M-C-h' "$AUTOKEY_OUT"
}

@test "every generated key is indexed by confhelp" {
	command -v confhelp >/dev/null || skip "confhelp not installed"
	run confhelp -b "$REPO_ROOT"
	[ "$status" -eq 0 ]
	# The comment header carries a '|' and must not be parsed as a binding.
	[[ "$output" != *"<key>"* ]]
	[[ "$output" == *"[autokey]|ctrl+alt+p (M-C-p)|SecretPicker"* ]]
	[[ "$output" == *"[gnome]|ctrl+alt+space (M-C-space)|Layout Picker"* ]]
}
