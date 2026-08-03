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
		CLAUDE_COMMANDS_ROOT="$FIXTURE_ROOT/missing-commands" \
		CLAUDE_BIN="$FIXTURE_ROOT/no-such-cli" \
		CLAUDE_INSTALLED_PLUGINS="$FIXTURE_ROOT/missing.json" \
		CLAUDE_SETTINGS_FILE="$FIXTURE_ROOT/missing-settings.json" \
		bash "$CATALOG_TOOL" list claude "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	[[ "$output" == $'skill\trag-eval\t'*$'\t/rag-eval\tpersonal' ]]
}

# Stand in for the real CLI. `plugin list --json` reports what is enabled and where
# it lives; `plugin details <name>` reports which capability names that plugin owns.
make_claude_stub() {
	local listing="$1" pair
	shift
	mkdir -p "$FIXTURE_ROOT/bin"
	{
		echo '#!/usr/bin/env bash'
		echo 'case "$1 $2" in'
		echo '"plugin list")'
		printf '\tcat <<'"'"'JSON'"'"'\n%s\nJSON\n\t;;\n' "$listing"
		echo '"plugin details")'
		echo '	case "$3" in'
		for pair in "$@"; do
			# The count in "Skills (N)" is discarded by the parser, so it need not be real.
			printf '\t%s) echo "  Skills (9)  %s" ;;\n' "${pair%%=*}" "${pair#*=}"
		done
		echo '	*) echo "  Skills (0)" ;;'
		echo '	esac'
		echo '	;;'
		echo 'esac'
	} > "$FIXTURE_ROOT/bin/claude"
	chmod +x "$FIXTURE_ROOT/bin/claude"
}

@test "claude includes only enabled plugins and namespaces what the CLI reports" {
	make_skill "$FIXTURE_ROOT/enabled/skills/compare/SKILL.md" compare
	make_skill "$FIXTURE_ROOT/disabled/skills/hidden/SKILL.md" hidden
	make_claude_stub \
		"[{\"id\":\"costs@market\",\"enabled\":true,\"installPath\":\"$FIXTURE_ROOT/enabled\"},
		  {\"id\":\"hidden@market\",\"enabled\":false,\"installPath\":\"$FIXTURE_ROOT/disabled\"}]" \
		"costs=compare"

	run env \
		CAPABILITY_PICKER_DISABLE_CACHE=1 \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/empty" \
		CLAUDE_COMMANDS_ROOT="$FIXTURE_ROOT/empty-commands" \
		CLAUDE_BIN="$FIXTURE_ROOT/bin/claude" \
		bash "$CATALOG_TOOL" list claude "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	[[ "$output" == *$'skill\tcosts:compare\t'*$'\t/costs:compare\tplugin:costs' ]]
	[[ "$output" != *hidden* ]]
}

# The regression that motivated the CLI split: three plugin entries pointed at one
# monorepo checkout, and each claimed every skill in it under its own namespace.
@test "a plugin only claims the capabilities the CLI attributes to it" {
	local repo="$FIXTURE_ROOT/monorepo"
	make_skill "$repo/skills/engineering/helm/SKILL.md" helm
	make_skill "$repo/skills/ai-enablement/ai-platform/SKILL.md" ai-platform
	make_claude_stub \
		"[{\"id\":\"ai-platform@loft\",\"enabled\":true,\"installPath\":\"$repo\"},
		  {\"id\":\"engineering@loft\",\"enabled\":true,\"installPath\":\"$repo\"}]" \
		"ai-platform=ai-platform" "engineering=helm"

	run env \
		CAPABILITY_PICKER_DISABLE_CACHE=1 \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/empty" \
		CLAUDE_COMMANDS_ROOT="$FIXTURE_ROOT/empty-commands" \
		CLAUDE_BIN="$FIXTURE_ROOT/bin/claude" \
		bash "$CATALOG_TOOL" list claude "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -F $'\t/engineering:helm\t'
	printf '%s\n' "$output" | grep -F $'\t/ai-platform:ai-platform\t'
	[[ "$output" != *ai-platform:helm* ]]
	[[ "$output" != *engineering:ai-platform* ]]
}

@test "custom commands are listed alongside skills and invoked verbatim" {
	mkdir -p "$FIXTURE_ROOT/commands"
	printf '%s\n' '# Daily brief' > "$FIXTURE_ROOT/commands/daily-rss.md"
	make_claude_stub '[]'

	run env \
		CAPABILITY_PICKER_DISABLE_CACHE=1 \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/empty" \
		CLAUDE_COMMANDS_ROOT="$FIXTURE_ROOT/commands" \
		CLAUDE_BIN="$FIXTURE_ROOT/bin/claude" \
		bash "$CATALOG_TOOL" list claude "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	[[ "$output" == $'command\tdaily-rss\t'*$'\t/daily-rss\tpersonal' ]]
}

@test "non-user-invocable skills are excluded" {
	make_skill "$FIXTURE_ROOT/claude-skills/internal/SKILL.md" internal 'user-invocable: false'

	run env \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/claude-skills" \
		CLAUDE_COMMANDS_ROOT="$FIXTURE_ROOT/missing-commands" \
		CLAUDE_BIN="$FIXTURE_ROOT/no-such-cli" \
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
