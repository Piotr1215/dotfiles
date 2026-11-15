#!/usr/bin/env bash
set -euo pipefail

# Emit the skills that can be invoked in a Claude or Codex pane. Rows are:
# kind<TAB>display name<TAB>SKILL.md<TAB>invocation<TAB>source

claude_skills_root="${CLAUDE_SKILLS_ROOT:-$HOME/.claude/skills}"
claude_commands_root="${CLAUDE_COMMANDS_ROOT:-$HOME/.claude/commands}"
claude_installed_plugins="${CLAUDE_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}"
claude_settings_file="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
claude_bin="${CLAUDE_BIN:-claude}"
codex_skills_root="${CODEX_SKILLS_ROOT:-$HOME/.codex/skills}"
shared_skills_root="${SHARED_SKILLS_ROOT:-$HOME/.claude/skills}"
codex_plugin_cache_root="${CODEX_PLUGIN_CACHE_ROOT:-$HOME/.codex/plugins/cache}"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/capability-picker"

frontmatter_value() {
	local file="$1" key="$2"
	awk -v key="$key" '
		NR == 1 && $0 == "---" { in_frontmatter = 1; next }
		in_frontmatter && $0 == "---" { exit }
		in_frontmatter && $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
			line = $0
			sub("^[[:space:]]*" key ":[[:space:]]*", "", line)
			gsub(/^['\''\"]|['\''\"]$/, "", line)
			print line
			exit
		}
	' "$file"
}

# Read name and user-invocable from the frontmatter of every NUL-separated path
# on stdin, in one awk pass. Two awk forks per file made a rebuild of ~80
# personal skills cost 0.66s; one pass costs a few milliseconds.
# Rows are: file<TAB>name<TAB>user-invocable (either field may be empty).
frontmatter_rows() {
	# shellcheck disable=SC2016 # an awk program, $0 is awk's
	xargs -0 -r awk '
		function flush() { if (file != "") printf "%s\t%s\t%s\n", file, name, invocable }
		function value(line, key) {
			sub("^[[:space:]]*" key ":[[:space:]]*", "", line)
			gsub(/^['\''"]|['\''"]$/, "", line)
			return line
		}
		FNR == 1 { flush(); file = FILENAME; name = ""; invocable = ""; in_fm = ($0 == "---"); next }
		!in_fm { next }
		$0 == "---" { in_fm = 0; next }
		name == "" && /^[[:space:]]*name:/ { name = value($0, "name") }
		invocable == "" && /^[[:space:]]*user-invocable:/ { invocable = value($0, "user-invocable") }
		END { flush() }
	'
}

emit_skill_tree() {
	local root="$1" agent="$2" namespace="$3" source="$4"
	local file name invocable display invocation prefix row_source relative_file shared_file
	[[ -d "$root" ]] || return 0
	[[ "$agent" == claude ]] && prefix=/ || prefix='$'

	while IFS=$'\t' read -r file name invocable; do
		[[ "$invocable" != false ]] || continue
		[[ -n "$name" ]] || name="$(basename "$(dirname "$file")")"
		if [[ -n "$namespace" && "$name" != "$namespace:"* ]]; then
			display="$namespace:$name"
		else
			display="$name"
		fi
		invocation="$prefix$display"
		row_source="$source"
		if [[ "$agent" == codex && "$source" == codex && "$root" == "$codex_skills_root" ]]; then
			relative_file="${file#"${root%/}/"}"
			shared_file="${shared_skills_root%/}/$relative_file"
			if [[ -e "$shared_file" && "$file" -ef "$shared_file" ]]; then
				row_source=claude
			fi
		fi
		printf 'skill\t%s\t%s\t%s\t%s\n' "$display" "$file" "$invocation" "$row_source"
	done < <(find -L "$root" -type f -name SKILL.md -print0 2>/dev/null | frontmatter_rows)
}

# Custom commands are invoked the same way skills are, and `/skills` lists them
# alongside skills, so the picker has to carry them too. They are flat .md files,
# not directories with a SKILL.md.
emit_command_tree() {
	local root="$1" agent="$2" source="$3"
	local file name prefix
	[[ -d "$root" ]] || return 0
	[[ "$agent" == claude ]] && prefix=/ || prefix='$'

	while IFS= read -r -d '' file; do
		name="${file##*/}"
		name="${name%.md}"
		# Same rule the Codex bridge enforces (VALID_NAME in
		# sync-claude-command-skills.py), so both catalogs agree on what counts as
		# a command. A slash command is always lowercase-kebab, so this drops docs
		# that merely live in the commands directory: README.md was being offered
		# as an invocable command and bridged into Codex as invalid.
		[[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || continue
		printf 'command\t%s\t%s\t%s%s\t%s\n' "$name" "$file" "$prefix" "$name" "$source"
	done < <(find -L "$root" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)
}

emit_project_skills() {
	local agent="$1" cwd="$2" current
	[[ -d "$cwd" ]] || return 0
	current="$(cd "$cwd" && pwd -P)"
	while :; do
		if [[ "$agent" == claude ]]; then
			emit_skill_tree "$current/.claude/skills" "$agent" '' project
			emit_command_tree "$current/.claude/commands" "$agent" project
		else
			emit_skill_tree "$current/.codex/skills" "$agent" '' project
			emit_skill_tree "$current/.agents/skills" "$agent" '' project
		fi
		[[ "$current" == / ]] && break
		current="$(dirname "$current")"
	done
}

# Index every file a plugin could expose a capability from, keyed by the name it
# would be invoked under. Declared locations win over vendored copies elsewhere in
# the checkout, so a preview opens the canonical file.
index_plugin_files() {
	local root="$1" base file key declared
	for base in "$root/skills" "$root/commands" "$root"; do
		[[ -d "$base" ]] || continue
		while IFS= read -r -d '' file; do
			case "$file" in
			*/SKILL.md)
				# A skill answers to its declared name, which need not match its
				# directory: terraform-skill ships SKILL.md at the plugin root.
				key="${file%/SKILL.md}"
				key="${key##*/}"
				declared="$(frontmatter_value "$file" name)"
				[[ -n "$declared" && ! -v "plugin_file[$declared]" ]] && plugin_file["$declared"]="$file"
				;;
			*)
				key="${file##*/}"
				key="${key%.md}"
				;;
			esac
			[[ -v "plugin_file[$key]" ]] || plugin_file["$key"]="$file"
		done < <(find -L "$base" \( -name node_modules -o -name .git \) -prune -o \
			-type f \( -name SKILL.md -o -path '*/commands/*.md' \) -print0 2>/dev/null | sort -z)
	done
}

# Emit one plugin's capabilities. The CLI decides WHICH names the plugin owns; the
# tree is consulted only to find the file behind a name. Without that split a
# monorepo checkout donates every sibling plugin's skills to whichever entry
# happens to point at the repo root, which is how /ai-platform:helm got invented.
emit_claude_plugin() {
	local plugin="$1" root="$2" entry file
	local -A plugin_file=()
	index_plugin_files "$root"

	"$claude_bin" plugin details "$plugin" 2>/dev/null |
		sed -n 's/^[[:space:]]*Skills ([0-9][0-9]*)[[:space:]]*//p' |
		tr ',' '\n' |
		while IFS= read -r entry; do
			entry="${entry#"${entry%%[![:space:]]*}"}"
			entry="${entry%"${entry##*[![:space:]]}"}"
			[[ -n "$entry" ]] || continue
			file="${plugin_file[$entry]:-}"
			[[ -n "$file" ]] || continue
			printf 'skill\t%s:%s\t%s\t/%s:%s\tplugin:%s\n' \
				"$plugin" "$entry" "$file" "$plugin" "$entry" "$plugin"
		done
}

# One `plugin details` call costs ~0.7s, so a dozen plugins serially would stall the
# popup for the whole of a cache miss. Fan them out and reassemble in listing order.
emit_claude_plugins() {
	local id install_path plugin_name work index=0
	command -v jq >/dev/null 2>&1 || return 0
	command -v "$claude_bin" >/dev/null 2>&1 || return 0

	work="$(mktemp -d)" || return 0
	while IFS=$'\t' read -r id install_path; do
		[[ -n "$id" && -d "$install_path" ]] || continue
		plugin_name="${id%%@*}"
		emit_claude_plugin "$plugin_name" "$install_path" > "$work/$(printf '%03d' "$index")" &
		index=$((index + 1))
	done < <("$claude_bin" plugin list --json 2>/dev/null |
		jq -r '.[] | select(.enabled) | [.id, .installPath] | @tsv' 2>/dev/null)
	wait

	[[ "$index" -gt 0 ]] && cat "$work"/*
	rm -rf "$work"
}

emit_codex_plugins() {
	local manifest plugin_root plugin_name skills_path
	[[ -d "$codex_plugin_cache_root" ]] || return 0
	command -v jq >/dev/null 2>&1 || return 0

	while IFS= read -r -d '' manifest; do
		plugin_root="$(dirname "$(dirname "$manifest")")"
		plugin_name="$(jq -r '.name // empty' "$manifest")"
		skills_path="$(jq -r '.skills // empty' "$manifest")"
		[[ -n "$plugin_name" && -n "$skills_path" ]] || continue
		emit_skill_tree "$plugin_root/${skills_path#./}" codex "$plugin_name" "plugin:$plugin_name"
	done < <(find -L "$codex_plugin_cache_root" -type f -path '*/.codex-plugin/plugin.json' -print0 2>/dev/null)
}

# Personal, command and project rows: cheap to build, but they change with every
# skill edit, so they are cached apart from the plugin rows.
list_local_rows() {
	local agent="$1" cwd="$2"
	if [[ "$agent" == claude ]]; then
		emit_skill_tree "$claude_skills_root" claude '' personal
		emit_command_tree "$claude_commands_root" claude personal
		emit_project_skills claude "$cwd"
	else
		emit_skill_tree "$codex_skills_root" codex '' codex
		emit_skill_tree "$shared_skills_root" codex '' claude
		emit_project_skills codex "$cwd"
	fi
}

# Plugin rows: one `claude plugin details` call per plugin, ~2.6s for two dozen,
# but they change only when a plugin is installed, updated or toggled.
list_plugin_rows() {
	if [[ "$1" == claude ]]; then emit_claude_plugins; else emit_codex_plugins; fi
}

# Local rows win a name clash, as they always have: they are emitted first.
merge_rows() {
	awk -F '\t' '!seen[$2]++' | sort -t $'\t' -k2,2
}

list_skills_uncached() {
	local agent="$1" cwd="${2:-$PWD}"
	{
		list_local_rows "$agent" "$cwd"
		list_plugin_rows "$agent"
	} | merge_rows
}

emit_tree_signature() {
	local root="$1"
	[[ -d "$root" ]] || return 0
	find -L "$root" -type f -name SKILL.md \
		-printf '%p\t%T@\t%s\n' 2>/dev/null
}

emit_command_signature() {
	local root="$1"
	[[ -d "$root" ]] || return 0
	find -L "$root" -maxdepth 1 -type f -name '*.md' \
		-printf '%p\t%T@\t%s\n' 2>/dev/null
}

emit_project_signature() {
	local agent="$1" cwd="$2" current
	[[ -d "$cwd" ]] || return 0
	current="$(cd "$cwd" && pwd -P)"
	while :; do
		if [[ "$agent" == claude ]]; then
			emit_tree_signature "$current/.claude/skills"
			emit_command_signature "$current/.claude/commands"
		else
			emit_tree_signature "$current/.codex/skills"
			emit_tree_signature "$current/.agents/skills"
		fi
		[[ "$current" == / ]] && break
		current="${current%/*}"
		current="${current:-/}"
	done
}

local_signature() {
	local agent="$1" cwd="$2"
	printf 'local-v2\t%s\t%s\n' "$agent" "$(stat -c '%Y:%s' "${BASH_SOURCE[0]}")"
	if [[ "$agent" == claude ]]; then
		printf '%s\t%s\n' "$claude_skills_root" "$claude_commands_root"
		emit_tree_signature "$claude_skills_root"
		emit_command_signature "$claude_commands_root"
	else
		printf '%s\t%s\n' "$codex_skills_root" "$shared_skills_root"
		emit_tree_signature "$codex_skills_root"
		emit_tree_signature "$shared_skills_root"
	fi
	emit_project_signature "$agent" "$cwd"
}

# settings.json is rewritten for hooks and permissions far more often than for
# plugins, so only its enabledPlugins block counts.
plugin_signature() {
	local agent="$1" install_path
	printf 'plugin-v2\t%s\t%s\n' "$agent" "$(stat -c '%Y:%s' "${BASH_SOURCE[0]}")"
	if [[ "$agent" == claude ]]; then
		printf '%s\t%s\n' "$claude_bin" "$claude_installed_plugins"
		[[ -f "$claude_installed_plugins" ]] && stat -c '%n\t%Y\t%s' "$claude_installed_plugins"
		command -v jq >/dev/null 2>&1 || return 0
		[[ -f "$claude_settings_file" ]] && jq -c '.enabledPlugins // {}' "$claude_settings_file" 2>/dev/null
		if [[ -f "$claude_installed_plugins" ]]; then
			while IFS= read -r install_path; do
				emit_tree_signature "$install_path"
				emit_command_signature "$install_path/commands"
			done < <(jq -r '.plugins[][].installPath' "$claude_installed_plugins" 2>/dev/null)
		fi
	else
		printf '%s\n' "$codex_plugin_cache_root"
		emit_tree_signature "$codex_plugin_cache_root"
	fi
}

# Print the rows cached under NAME and KEY (the config paths the rows come from)
# when SIGNATURE still matches; otherwise run the builder command that follows,
# store its rows and print them. One file per name and key, rewritten in place.
cached_rows() {
	local name="$1" key="$2" signature="$3" cached="" cache_file
	shift 3
	cache_file="$cache_root/$name-$(printf '%s' "$key" | cksum | awk '{ print $1 }').tsv"
	[[ -f "$cache_file.signature" ]] && IFS= read -r cached < "$cache_file.signature"
	signature="$(printf '%s' "$signature" | cksum)"
	if [[ -f "$cache_file" && "$signature" == "$cached" ]]; then
		cat "$cache_file"
		return
	fi
	mkdir -p "$cache_root"
	"$@" > "$cache_file.tmp.$$"
	printf '%s\n' "$signature" > "$cache_file.signature.tmp.$$"
	mv "$cache_file.tmp.$$" "$cache_file"
	mv "$cache_file.signature.tmp.$$" "$cache_file.signature"
	cat "$cache_file"
}

# Plugin rows, served stale. The picker never waits on 49 plugin trees or the
# CLI: the last rows print at once and a detached job rechecks the signature and
# rebuilds if it moved, so a plugin change shows up on the next open. Only a
# missing cache builds in the foreground. flock keeps rapid opens from stacking
# rebuilds; fd 3 is closed so a bats `run` does not wait on the job.
stale_plugin_rows() {
	local agent="$1" key="$2" cache_file
	cache_file="$cache_root/plugins-$agent-$(printf '%s' "$key" | cksum | awk '{ print $1 }').tsv"
	if [[ ! -f "$cache_file" ]]; then
		cached_rows "plugins-$agent" "$key" "$(plugin_signature "$agent")" list_plugin_rows "$agent"
		return
	fi
	cat "$cache_file"
	(
		flock -n 9 || exit 0
		cached_rows "plugins-$agent" "$key" "$(plugin_signature "$agent")" list_plugin_rows "$agent" >/dev/null
	) 9>"$cache_file.lock" </dev/null >/dev/null 2>&1 3>&- &
}

list_skills() {
	local agent="$1" cwd="${2:-$PWD}"
	if [[ "$agent" != claude && "$agent" != codex ]]; then
		echo "Unknown agent: $agent" >&2
		return 2
	fi
	if [[ "${CAPABILITY_PICKER_DISABLE_CACHE:-0}" == 1 ]]; then
		list_skills_uncached "$agent" "$cwd"
		return
	fi
	local local_key plugin_key
	local_key="$cwd $claude_skills_root $claude_commands_root $codex_skills_root $shared_skills_root"
	plugin_key="$claude_bin $claude_installed_plugins $claude_settings_file $codex_plugin_cache_root"
	{
		cached_rows "local-$agent" "$local_key" "$(local_signature "$agent" "$cwd")" \
			list_local_rows "$agent" "$cwd"
		stale_plugin_rows "$agent" "$plugin_key"
	} | merge_rows
}

detect_agent() {
	local command_name="${1##*/}"
	case "$command_name" in
	*claude*) printf 'claude\n' ;;
	*codex*) printf 'codex\n' ;;
	*) printf 'unknown\n' ;;
	esac
}

case "${1:-}" in
list) list_skills "${2:-}" "${3:-$PWD}" ;;
agent) detect_agent "${2:-}" ;;
*)
	echo "Usage: $(basename "$0") {list claude|codex [cwd]|agent command}" >&2
	exit 2
	;;
esac
