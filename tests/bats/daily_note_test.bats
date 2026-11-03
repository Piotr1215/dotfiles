#!/usr/bin/env bats
# __daily_note.sh creates today's note from the vault's template and prints its
# path; --pin makes it pin 2 in Gordon's pane store. tmux is stubbed to list
# the panes in $BATS_TEST_TMPDIR/panes, so no tmux server is touched.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	SCRIPT="$REPO_ROOT/scripts/__daily_note.sh"
	export DAILY_NOTE_VAULT="$BATS_TEST_TMPDIR/vault"
	export DAILY_NOTE_DATE=2026-10-26
	export GORDON_PINS_DIR="$BATS_TEST_TMPDIR/pins"
	export HANDOFFS_FILE=/state/gordon/handoffs/index.md
	unset TMUX_PANE
	mkdir -p "$DAILY_NOTE_VAULT/.obsidian" "$DAILY_NOTE_VAULT/Templates"
	printf '{"folder": "_Current", "template": "Templates/Daily", "format": "YYYY-MM-DD"}\n' \
		>"$DAILY_NOTE_VAULT/.obsidian/daily-notes.json"
	printf '# {{date}}\n\n## Calls\n\n## Log\n' >"$DAILY_NOTE_VAULT/Templates/Daily.md"
	NOTE="$DAILY_NOTE_VAULT/_Current/2026-10-26.md"
	OLD="$DAILY_NOTE_VAULT/_Current/2026-10-23.md"

	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_BIN"
	cat >"$STUB_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == list-panes && -f "$BATS_TEST_TMPDIR/panes" ]] || exit 1
cat "$BATS_TEST_TMPDIR/panes"
EOF
	chmod +x "$STUB_BIN/tmux"
	export PATH="$STUB_BIN:$PATH"
}

# panes <row>...: the panes tmux lists, each `id agent window session`.
panes() {
	printf '%s\n' "$@" | tr ' ' '\t' >"$BATS_TEST_TMPDIR/panes"
}

# store <n> <line>...: pane %<n>'s pins.tsv, each line `kind text`.
store() {
	local n=$1
	shift
	mkdir -p "$GORDON_PINS_DIR/panes/$n"
	printf '%s\n' "$@" | sed 's/ /\t/' >"$GORDON_PINS_DIR/panes/$n/pins.tsv"
}

# pins_of <n>: pane %<n>'s pins.tsv with the tab after the kind shown as a space.
pins_of() {
	sed 's/\t/ /' "$GORDON_PINS_DIR/panes/$1/pins.tsv"
}

@test "creates the note from the template with the date filled in" {
	run "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$output" = "$NOTE" ]
	[ "$(head -1 "$NOTE")" = "# 2026-10-26" ]
	grep -qx '## Calls' "$NOTE"
}

@test "leaves an existing note as it is" {
	mkdir -p "${NOTE%/*}"
	printf 'kept\n' >"$NOTE"
	run "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$output" = "$NOTE" ]
	[ "$(cat "$NOTE")" = "kept" ]
}

@test "a missing template is an error" {
	rm "$DAILY_NOTE_VAULT/Templates/Daily.md"
	run "$SCRIPT"
	[ "$status" -eq 1 ]
	[ ! -e "$NOTE" ]
}

@test "--pin puts today's note second, drops the old daily pin, keeps the rest in order" {
	panes '%2 intake task kendra' '%5 triage task todo'
	store 5 "note $HANDOFFS_FILE" "note $OLD" 'note /some/case.md' 'linear DEVOPS-1'
	run "$SCRIPT" --pin
	[ "$status" -eq 0 ]
	[ "$output" = "$NOTE" ]
	[ "$(pins_of 5)" = "$(printf '%s\n' "note $HANDOFFS_FILE" "note $NOTE" 'note /some/case.md' 'linear DEVOPS-1')" ]
}

@test "--pin puts the handoffs file first when it was elsewhere or missing" {
	panes '%5 triage task todo'
	store 5 'note /some/case.md' "note $HANDOFFS_FILE"
	run "$SCRIPT" --pin
	[ "$(pins_of 5)" = "$(printf '%s\n' "note $HANDOFFS_FILE" "note $NOTE" 'note /some/case.md')" ]
	store 5 'note /some/case.md'
	run "$SCRIPT" --pin
	[ "$(pins_of 5)" = "$(printf '%s\n' "note $HANDOFFS_FILE" "note $NOTE" 'note /some/case.md')" ]
}

@test "--pin twice leaves the store unchanged" {
	panes '%5 triage task todo'
	store 5 "note $HANDOFFS_FILE" 'note /some/case.md'
	"$SCRIPT" --pin >/dev/null
	before=$(pins_of 5)
	touch -d '2000-01-01' "$GORDON_PINS_DIR/panes/5/pins.tsv"
	"$SCRIPT" --pin >/dev/null
	[ "$(pins_of 5)" = "$before" ]
	[ "$(stat -c %Y "$GORDON_PINS_DIR/panes/5/pins.tsv")" = "$(date -d 2000-01-01 +%s)" ]
}

@test "--pin prefers TMUX_PANE when it is a Gordon pane" {
	panes '%5 triage task todo' '%9 gordon gordon gordon'
	TMUX_PANE=%9 run "$SCRIPT" --pin
	[ "$status" -eq 0 ]
	[ -f "$GORDON_PINS_DIR/panes/9/pins.tsv" ]
	[ ! -e "$GORDON_PINS_DIR/panes/5/pins.tsv" ]
}

@test "--pin with no Gordon pane pins nothing and still prints the path" {
	panes '%2 intake task kendra' '%7 worker-x repo bash'
	run "$SCRIPT" --pin
	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = "$NOTE" ]
	[ ! -d "$GORDON_PINS_DIR" ]
	rm "$BATS_TEST_TMPDIR/panes"
	run "$SCRIPT" --pin
	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = "$NOTE" ]
}
