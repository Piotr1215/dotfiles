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

is_user_invocable() {
	[[ "$(frontmatter_value "$1" user-invocable)" != false ]]
}

emit_skill_tree() {
	local root="$1" agent="$2" namespace="$3" source="$4"
	local file name display invocation prefix row_source relative_file shared_file
	[[ -d "$root" ]] || return 0
	[[ "$agent" == claude ]] && prefix=/ || prefix='$'

	while IFS= read -r -d '' file; do
		is_user_invocable "$file" || continue
		name="$(frontmatter_value "$file" name)"
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
	done < <(find -L "$root" -type f -name SKILL.md -print0 2>/dev/null)
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

list_skills_uncached() {
	local agent="$1" cwd="${2:-$PWD}"
	{
		if [[ "$agent" == claude ]]; then
			emit_skill_tree "$claude_skills_root" claude '' personal
			emit_command_tree "$claude_commands_root" claude personal
			emit_project_skills claude "$cwd"
			emit_claude_plugins
		elif [[ "$agent" == codex ]]; then
			emit_skill_tree "$codex_skills_root" codex '' codex
			emit_skill_tree "$shared_skills_root" codex '' claude
			emit_project_skills codex "$cwd"
			emit_codex_plugins
		else
			echo "Unknown agent: $agent" >&2
			return 2
		fi
	} | awk -F '\t' '!seen[$2]++' | sort -t $'\t' -k2,2
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

catalog_signature() {
	local agent="$1" cwd="$2" install_path
	printf 'catalog-v1\t%s\t%s\n' "$agent" "$(stat -c '%Y:%s' "${BASH_SOURCE[0]}")"
	if [[ "$agent" == claude ]]; then
		for install_path in "$claude_installed_plugins" "$claude_settings_file"; do
			[[ -f "$install_path" ]] && stat -c '%n\t%Y\t%s' "$install_path"
		done
		emit_tree_signature "$claude_skills_root"
		emit_command_signature "$claude_commands_root"
		if [[ -f "$claude_installed_plugins" ]] && command -v jq >/dev/null 2>&1; then
			while IFS= read -r install_path; do
				emit_tree_signature "$install_path"
				emit_command_signature "$install_path/commands"
			done < <(jq -r '.plugins[][].installPath' "$claude_installed_plugins")
		fi
	else
		emit_tree_signature "$codex_skills_root"
		emit_tree_signature "$shared_skills_root"
		emit_tree_signature "$codex_plugin_cache_root"
	fi
	emit_project_signature "$agent" "$cwd"
}

list_skills() {
	local agent="$1" cwd="${2:-$PWD}" cache_key cache_file signature_file signature cached_signature
	if [[ "${CAPABILITY_PICKER_DISABLE_CACHE:-0}" == 1 ]]; then
		list_skills_uncached "$agent" "$cwd"
		return
	fi

	cache_key="$(printf '%s' "$cwd" | cksum | awk '{ print $1 }')"
	cache_file="$cache_root/skills-$agent-$cache_key.tsv"
	signature_file="$cache_file.signature"
	signature="$(catalog_signature "$agent" "$cwd" | cksum | awk '{ print $1 ":" $2 }')"
	cached_signature="$(cat "$signature_file" 2>/dev/null || true)"
	if [[ -f "$cache_file" && "$signature" == "$cached_signature" ]]; then
		cat "$cache_file"
		return
	fi

	mkdir -p "$cache_root"
	list_skills_uncached "$agent" "$cwd" > "$cache_file.tmp.$$"
	printf '%s\n' "$signature" > "$signature_file.tmp.$$"
	mv "$cache_file.tmp.$$" "$cache_file"
	mv "$signature_file.tmp.$$" "$signature_file"
	cat "$cache_file"
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
