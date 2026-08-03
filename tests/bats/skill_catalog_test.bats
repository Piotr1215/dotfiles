#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	CATALOG_TOOL="$REPO_ROOT/scripts/__skill_catalog.sh"
	FIXTURE_ROOT="$BATS_TEST_TMPDIR/catalog"
	mkdir -p "$FIXTURE_ROOT"
}

make_skill() {
	local path="$1" name="$2" extra="${3:-}"
	mkdir -p "$(dirname "$path")"
	printf '%s\n' '---' "name: $name" 'description: Fixture skill' "$extra" '---' '' "# $name" > "$path"
}

@test "claude lists personal skills with slash invocations" {
	make_skill "$FIXTURE_ROOT/claude-skills/rag-eval/SKILL.md" rag-eval

	run env \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/claude-skills" \
		CLAUDE_INSTALLED_PLUGINS="$FIXTURE_ROOT/missing.json" \
		CLAUDE_SETTINGS_FILE="$FIXTURE_ROOT/missing-settings.json" \
		bash "$CATALOG_TOOL" list claude "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	[[ "$output" == $'skill\trag-eval\t'*$'\t/rag-eval\tpersonal' ]]
}

@test "claude includes only enabled installed plugin skills and namespaces them" {
	make_skill "$FIXTURE_ROOT/enabled/skills/compare/SKILL.md" compare
	make_skill "$FIXTURE_ROOT/disabled/skills/hidden/SKILL.md" hidden
	cat > "$FIXTURE_ROOT/installed.json" <<EOF
{"plugins":{"costs@market":[{"installPath":"$FIXTURE_ROOT/enabled"}],"hidden@market":[{"installPath":"$FIXTURE_ROOT/disabled"}]}}
EOF
	cat > "$FIXTURE_ROOT/settings.json" <<'EOF'
{"enabledPlugins":{"costs@market":true,"hidden@market":false}}
EOF

	run env \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/empty" \
		CLAUDE_INSTALLED_PLUGINS="$FIXTURE_ROOT/installed.json" \
		CLAUDE_SETTINGS_FILE="$FIXTURE_ROOT/settings.json" \
		bash "$CATALOG_TOOL" list claude "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	[[ "$output" == *$'skill\tcosts:compare\t'*$'\t/costs:compare\tplugin:costs' ]]
	[[ "$output" != *hidden* ]]
}

@test "non-user-invocable skills are excluded" {
	make_skill "$FIXTURE_ROOT/claude-skills/internal/SKILL.md" internal 'user-invocable: false'

	run env \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/claude-skills" \
		CLAUDE_INSTALLED_PLUGINS="$FIXTURE_ROOT/missing.json" \
		CLAUDE_SETTINGS_FILE="$FIXTURE_ROOT/missing-settings.json" \
		bash "$CATALOG_TOOL" list claude "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "codex distinguishes native and shared Claude skills" {
	make_skill "$FIXTURE_ROOT/codex-skills/.system/skill-creator/SKILL.md" skill-creator
	make_skill "$FIXTURE_ROOT/shared-skills/rag-eval/SKILL.md" rag-eval

	run env \
		CODEX_SKILLS_ROOT="$FIXTURE_ROOT/codex-skills" \
		SHARED_SKILLS_ROOT="$FIXTURE_ROOT/shared-skills" \
		CODEX_PLUGIN_CACHE_ROOT="$FIXTURE_ROOT/missing-cache" \
		bash "$CATALOG_TOOL" list codex "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -F $'\t$rag-eval\tclaude'
	printf '%s\n' "$output" | grep -F $'\t$skill-creator\tcodex'
}

@test "codex symlinks to Claude skills retain their real source" {
	make_skill "$FIXTURE_ROOT/shared-skills/security-assessor/SKILL.md" security-assessor
	mkdir -p "$FIXTURE_ROOT/codex-skills"
	ln -s "$FIXTURE_ROOT/shared-skills/security-assessor" "$FIXTURE_ROOT/codex-skills/security-assessor"

	run env \
		CAPABILITY_PICKER_DISABLE_CACHE=1 \
		CODEX_SKILLS_ROOT="$FIXTURE_ROOT/codex-skills" \
		SHARED_SKILLS_ROOT="$FIXTURE_ROOT/shared-skills" \
		CODEX_PLUGIN_CACHE_ROOT="$FIXTURE_ROOT/missing-cache" \
		bash "$CATALOG_TOOL" list codex "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | grep -c $'^skill\tsecurity-assessor\t')" -eq 1 ]
	printf '%s\n' "$output" | grep -F $'\t$security-assessor\tclaude'
}

@test "codex plugin skills use the manifest name as namespace" {
	local plugin="$FIXTURE_ROOT/codex-cache/market/github/1.0"
	make_skill "$plugin/skills/yeet/SKILL.md" yeet
	mkdir -p "$plugin/.codex-plugin"
	cat > "$plugin/.codex-plugin/plugin.json" <<'EOF'
{"name":"github","skills":"./skills/"}
EOF

	run env \
		CODEX_SKILLS_ROOT="$FIXTURE_ROOT/empty" \
		SHARED_SKILLS_ROOT="$FIXTURE_ROOT/also-empty" \
		CODEX_PLUGIN_CACHE_ROOT="$FIXTURE_ROOT/codex-cache" \
		bash "$CATALOG_TOOL" list codex "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	[[ "$output" == $'skill\tgithub:yeet\t'*$'\t$github:yeet\tplugin:github' ]]
}

@test "agent detection recognizes claude and codex process names" {
	run bash "$CATALOG_TOOL" agent claude
	[ "$status" -eq 0 ]
	[ "$output" = claude ]

	run bash "$CATALOG_TOOL" agent codex-linux-x64
	[ "$status" -eq 0 ]
	[ "$output" = codex ]

	run bash "$CATALOG_TOOL" agent 'bash node codex'
	[ "$status" -eq 0 ]
	[ "$output" = codex ]

	run bash "$CATALOG_TOOL" agent zsh
	[ "$status" -eq 0 ]
	[ "$output" = unknown ]
}

@test "catalog cache invalidates when a skill changes" {
	local skill_file="$FIXTURE_ROOT/codex-skills/example/SKILL.md"
	make_skill "$skill_file" first-name

	run env \
		XDG_CACHE_HOME="$FIXTURE_ROOT/cache" \
		CODEX_SKILLS_ROOT="$FIXTURE_ROOT/codex-skills" \
		SHARED_SKILLS_ROOT="$FIXTURE_ROOT/empty" \
		CODEX_PLUGIN_CACHE_ROOT="$FIXTURE_ROOT/missing-cache" \
		bash "$CATALOG_TOOL" list codex "$FIXTURE_ROOT/project"
	[ "$status" -eq 0 ]
	[[ "$output" == *first-name* ]]

	make_skill "$skill_file" replacement-name
	run env \
		XDG_CACHE_HOME="$FIXTURE_ROOT/cache" \
		CODEX_SKILLS_ROOT="$FIXTURE_ROOT/codex-skills" \
		SHARED_SKILLS_ROOT="$FIXTURE_ROOT/empty" \
		CODEX_PLUGIN_CACHE_ROOT="$FIXTURE_ROOT/missing-cache" \
		bash "$CATALOG_TOOL" list codex "$FIXTURE_ROOT/project"
	[ "$status" -eq 0 ]
	[[ "$output" == *replacement-name* ]]
	[[ "$output" != *first-name* ]]
}
