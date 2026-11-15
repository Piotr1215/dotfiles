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

# The commands directory holds prose as well as commands. Only lowercase-kebab
# names are invocable, which is the rule the Codex bridge already enforces, so
# both catalogs offer the same set.
@test "docs living in the commands directory are not offered as commands" {
	mkdir -p "$FIXTURE_ROOT/commands"
	printf '%s\n' '# Daily brief' > "$FIXTURE_ROOT/commands/daily-rss.md"
	printf '%s\n' '# Naming convention' > "$FIXTURE_ROOT/commands/README.md"
	make_claude_stub '[]'

	run env \
		CAPABILITY_PICKER_DISABLE_CACHE=1 \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/empty" \
		CLAUDE_COMMANDS_ROOT="$FIXTURE_ROOT/commands" \
		CLAUDE_BIN="$FIXTURE_ROOT/bin/claude" \
		bash "$CATALOG_TOOL" list claude "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	[[ "$output" == *$'command\tdaily-rss\t'* ]]
	[[ "$output" != *README* ]]
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

# The plugin rows cost one CLI call per plugin, so the stub counts its calls.
make_counting_claude_stub() {
	local plugin_root="$1" skill="$2"
	mkdir -p "$FIXTURE_ROOT/bin"
	cat > "$FIXTURE_ROOT/bin/claude" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$FIXTURE_ROOT/calls.log"
case "\$1 \$2" in
"plugin list") echo '[{"id":"costs@market","enabled":true,"installPath":"$plugin_root"}]' ;;
"plugin details") echo "  Skills (1)  $skill" ;;
esac
STUB
	chmod +x "$FIXTURE_ROOT/bin/claude"
}

run_cached_claude_catalog() {
	run env \
		XDG_CACHE_HOME="$FIXTURE_ROOT/cache" \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/claude-skills" \
		CLAUDE_COMMANDS_ROOT="$FIXTURE_ROOT/missing-commands" \
		CLAUDE_BIN="$FIXTURE_ROOT/bin/claude" \
		CLAUDE_INSTALLED_PLUGINS="$FIXTURE_ROOT/installed.json" \
		CLAUDE_SETTINGS_FILE="$FIXTURE_ROOT/settings.json" \
		bash "$CATALOG_TOOL" list claude "$FIXTURE_ROOT/project"
}

# Wait for the detached plugin refresh to finish: it holds the lock while it runs.
wait_for_refresh() {
	local lock
	for lock in "$FIXTURE_ROOT"/cache/capability-picker/plugins-*.lock; do
		[[ -e "$lock" ]] && flock "$lock" true
	done
}

# Skills are edited dozens of times a day. Each edit used to drop the whole
# cache and rerun every `claude plugin details`, a 3s stall on the next ;;skill.
@test "editing a personal skill rebuilds its rows without rerunning the plugin CLI" {
	local plugin="$FIXTURE_ROOT/plugin"
	make_skill "$plugin/skills/compare/SKILL.md" compare
	make_skill "$FIXTURE_ROOT/claude-skills/example/SKILL.md" first-name
	printf '{"plugins":{"costs@market":[{"installPath":"%s"}]}}\n' "$plugin" > "$FIXTURE_ROOT/installed.json"
	echo '{"enabledPlugins":{"costs@market":true}}' > "$FIXTURE_ROOT/settings.json"
	make_counting_claude_stub "$plugin" compare

	run_cached_claude_catalog
	[ "$status" -eq 0 ]
	[[ "$output" == *first-name* && "$output" == *costs:compare* ]]
	local calls
	calls="$(wc -l < "$FIXTURE_ROOT/calls.log")"

	sleep 0.01
	make_skill "$FIXTURE_ROOT/claude-skills/example/SKILL.md" replacement-name
	run_cached_claude_catalog
	[ "$status" -eq 0 ]
	[[ "$output" == *replacement-name* && "$output" != *first-name* ]]
	[[ "$output" == *costs:compare* ]]
	wait_for_refresh
	[ "$(wc -l < "$FIXTURE_ROOT/calls.log")" -eq "$calls" ]
}

# The picker must open at once even right after a plugin change: it shows the
# last plugin rows and a background job picks up the change for the next open.
# settings.json changes for hooks and permissions all day; only enabledPlugins
# decides which plugin rows exist, so only that may trigger the CLI.
@test "plugin rows are served at once and refresh in the background on enabledPlugins changes" {
	local plugin="$FIXTURE_ROOT/plugin"
	make_skill "$plugin/skills/compare/SKILL.md" compare
	make_skill "$plugin/skills/forecast/SKILL.md" forecast
	printf '{"plugins":{"costs@market":[{"installPath":"%s"}]}}\n' "$plugin" > "$FIXTURE_ROOT/installed.json"
	echo '{"enabledPlugins":{"costs@market":true},"hooks":{}}' > "$FIXTURE_ROOT/settings.json"
	make_counting_claude_stub "$plugin" compare

	run_cached_claude_catalog
	[[ "$output" == *costs:compare* ]]
	local calls
	calls="$(wc -l < "$FIXTURE_ROOT/calls.log")"

	echo '{"enabledPlugins":{"costs@market":true},"hooks":{"Stop":[]}}' > "$FIXTURE_ROOT/settings.json"
	run_cached_claude_catalog
	wait_for_refresh
	[ "$(wc -l < "$FIXTURE_ROOT/calls.log")" -eq "$calls" ]

	make_counting_claude_stub "$plugin" forecast
	echo '{"enabledPlugins":{"costs@market":true,"other@market":false}}' > "$FIXTURE_ROOT/settings.json"
	run_cached_claude_catalog
	[ "$status" -eq 0 ]
	[[ "$output" == *costs:compare* && "$output" != *costs:forecast* ]]

	wait_for_refresh
	[ "$(wc -l < "$FIXTURE_ROOT/calls.log")" -gt "$calls" ]
	run_cached_claude_catalog
	[[ "$output" == *costs:forecast* && "$output" != *costs:compare* ]]
}

# All SKILL.md headers are now read in one awk pass, so each file's fields must
# stay its own and only the frontmatter may count.
@test "one-pass frontmatter keeps each skill's fields and ignores the body" {
	make_skill "$FIXTURE_ROOT/claude-skills/hidden/SKILL.md" hidden 'user-invocable: false'
	make_skill "$FIXTURE_ROOT/claude-skills/shown/SKILL.md" shown
	printf '%s\n' '' 'user-invocable: false' 'name: not-this' >> "$FIXTURE_ROOT/claude-skills/shown/SKILL.md"
	mkdir -p "$FIXTURE_ROOT/claude-skills/no-frontmatter"
	printf '%s\n' '# plain' 'name: body-name' > "$FIXTURE_ROOT/claude-skills/no-frontmatter/SKILL.md"

	run env \
		CAPABILITY_PICKER_DISABLE_CACHE=1 \
		CLAUDE_SKILLS_ROOT="$FIXTURE_ROOT/claude-skills" \
		CLAUDE_COMMANDS_ROOT="$FIXTURE_ROOT/missing-commands" \
		CLAUDE_BIN="$FIXTURE_ROOT/no-such-cli" \
		bash "$CATALOG_TOOL" list claude "$FIXTURE_ROOT/project"

	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -F $'\t/shown\tpersonal'
	printf '%s\n' "$output" | grep -F $'\t/no-frontmatter\tpersonal'
	[[ "$output" != *hidden* && "$output" != *not-this* && "$output" != *body-name* ]]
}
