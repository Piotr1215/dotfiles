#!/usr/bin/env bash
set -euo pipefail

marker='--- FABRIC PROMPT ---'

variables() {
	awk '
	{
		line = $0
		while (match(line, /\{\{[[:alpha:]_][[:alnum:]_]*\}\}/)) {
			token = substr(line, RSTART, RLENGTH)
			name = substr(token, 3, length(token) - 4)
			if (!seen[name]++) print name
			line = substr(line, RSTART + RLENGTH)
		}
	}'
}

normalize_prompt() {
	local prompt normalized
	prompt="$(cat)"
	if [[ "$prompt" == *'{{input}}'* ]]; then
		# Some old personal patterns carried both syntaxes. Keep the modern input
		# token and discard a legacy marker only when it occupies its own line.
		printf '%s\n' "$prompt" | awk '$0 !~ /^[[:space:]]*\$user_request[[:space:]]*$/'
		return
	fi

	normalized="$(printf '%s\n' "$prompt" | awk '
		/^[[:space:]]*\$user_request[[:space:]]*$/ { print "{{input}}"; found = 1; next }
		{ print }
		END { if (!found) print "{{input}}" }
	')"
	printf '%s\n' "$normalized"
}

prepare() {
	local prompt prompt_variables variable
	prompt="$(normalize_prompt)"
	prompt_variables="$(printf '%s\n' "$prompt" | variables)"

	printf 'input=\n'
	while IFS= read -r variable; do
		[[ -n "$variable" && "$variable" != input ]] && printf '%s=\n' "$variable"
	done <<< "$prompt_variables"
	printf '\n# Fill values above. Blank values keep their {{placeholder}}.\n'
	printf '# Edit the prompt body directly for multiline values.\n\n%s\n\n%s\n' "$marker" "$prompt"
}

replace_literal() {
	local text="$1" needle="$2" replacement="$3" prefix
	while [[ "$text" == *"$needle"* ]]; do
		prefix="${text%%"$needle"*}"
		text="${prefix}${replacement}${text#*"$needle"}"
	done
	printf '%s' "$text"
}

render() {
	local line name value rendered_line
	local in_prompt=false skip_first_blank=false found_marker=false
	declare -A values=()

	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$in_prompt" == false ]]; then
			if [[ "$line" == "$marker" ]]; then
				in_prompt=true
				found_marker=true
				skip_first_blank=true
			elif [[ "$line" =~ ^([[:alpha:]_][[:alnum:]_]*)=(.*)$ ]]; then
				name="${BASH_REMATCH[1]}"
				values["$name"]="${BASH_REMATCH[2]}"
			fi
			continue
		fi

		if [[ "$skip_first_blank" == true && -z "$line" ]]; then
			skip_first_blank=false
			continue
		fi
		skip_first_blank=false
		rendered_line="$line"
		for name in "${!values[@]}"; do
			value="${values[$name]}"
			[[ -n "$value" ]] || continue
			rendered_line="$(replace_literal "$rendered_line" "{{$name}}" "$value")"
		done
		printf '%s\n' "$rendered_line"
	done

	[[ "$found_marker" == true ]] || {
		echo "Template marker not found." >&2
		return 1
	}
}

case "${1:-}" in
variables) variables ;;
prepare) prepare ;;
render) render ;;
*)
	echo "Usage: $(basename "$0") {variables|prepare|render}" >&2
	exit 2
	;;
esac
