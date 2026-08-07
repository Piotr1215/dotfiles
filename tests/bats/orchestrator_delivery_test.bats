#!/usr/bin/env bats

# How the picker decides between pasting into the target pane and falling back to
# the clipboard. `tmux display-message -t` reports an unknown pane by printing
# nothing while still exiting 0, so a status-based check is always true and the
# fallback can never fire. The stub reproduces exactly that: STUB_PANE empty is a
# tmux that cannot resolve the pane.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	PICKER="$REPO_ROOT/scripts/__orchestrator.sh"
	FIXTURE_ROOT="$BATS_TEST_TMPDIR/picker"
	BIN="$FIXTURE_ROOT/bin"
	mkdir -p "$BIN" "$FIXTURE_ROOT/skills/demo-skill"

	printf '%s\n' '---' 'name: demo-skill' 'description: Fixture skill' '---' '' '# demo' \
		> "$FIXTURE_ROOT/skills/demo-skill/SKILL.md"

	# tmux stub: display-message answers with $STUB_PANE, empty meaning "no such
	# pane". Everything else logs and succeeds.
	cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$FIXTURE_ROOT/tmux.log"
case "\$1" in
	display-message) printf '%s\n' "\${STUB_PANE-}"; exit 0 ;;
	show-option)     exit 0 ;;
	*)               exit 0 ;;
esac
EOF

	# fzf stub: always "select" the fixture skill, so delivery is what gets tested.
	cat > "$BIN/fzf" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'skill\tdemo-skill\t/tmp/demo/SKILL.md\t/demo-skill\tpersonal\n'
EOF

	cat > "$BIN/xclip" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
EOF

	chmod +x "$BIN/tmux" "$BIN/fzf" "$BIN/xclip"
}

run_picker() {
	run env \
		PATH="$BIN:$PATH" \
		STUB_PANE="$1" \
		CAPABILITY_PICKER_AGENT=claude \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/skills" \
		CLAUDE_COMMANDS_ROOT="$FIXTURE_ROOT/missing-commands" \
		CLAUDE_BIN="$FIXTURE_ROOT/no-such-cli" \
		CLAUDE_INSTALLED_PLUGINS="$FIXTURE_ROOT/missing.json" \
		CLAUDE_SETTINGS_FILE="$FIXTURE_ROOT/missing-settings.json" \
		CAPABILITY_PICKER_DISABLE_CACHE=1 \
		bash "$PICKER" '%1'
}

@test "a live pane receives the invocation as a paste" {
	run_picker '%1'

	[ "$status" -eq 0 ]
	grep -q 'paste-buffer' "$FIXTURE_ROOT/tmux.log"
	[[ "$output" != *"Copied to clipboard"* ]]
}

@test "an unresolvable pane falls back to the clipboard instead of pasting nowhere" {
	run_picker ''

	[ "$status" -eq 0 ]
	[[ "$output" == *"Copied to clipboard: demo-skill"* ]]
	! grep -q 'paste-buffer' "$FIXTURE_ROOT/tmux.log"
}
