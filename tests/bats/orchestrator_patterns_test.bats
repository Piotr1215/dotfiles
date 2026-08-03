#!/usr/bin/env bats

# The picker offers custom fabric patterns only. The upstream library stays on disk
# for the `fabric` CLI, so these pin that it is not walked back into the list.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	PICKER="$REPO_ROOT/scripts/__orchestrator.sh"
	FAKE_HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$FAKE_HOME"
}

make_pattern() {
	local root="$1" name="$2"
	mkdir -p "$FAKE_HOME/$root/$name"
	printf '# %s\n' "$name" > "$FAKE_HOME/$root/$name/system.md"
}

@test "custom patterns are listed and the upstream library is not" {
	make_pattern dev/dotfiles/.config/fabric/custom_patterns mine
	make_pattern .config/fabric/patterns extract_skills

	run env HOME="$FAKE_HOME" bash "$PICKER" --list

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -Fx mine
	[[ "$output" != *extract_skills* ]]
}

@test "the stow-installed copy is listed when dotfiles is absent" {
	make_pattern .config/fabric/custom_patterns installed_only

	run env HOME="$FAKE_HOME" bash "$PICKER" --list

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -Fx installed_only
}

@test "a dotfiles pattern wins over its stow-installed copy" {
	make_pattern dev/dotfiles/.config/fabric/custom_patterns shared
	make_pattern .config/fabric/custom_patterns shared

	run env HOME="$FAKE_HOME" bash "$PICKER" --list

	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | grep -Fxc shared)" -eq 1 ]
}
