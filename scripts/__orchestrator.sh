#!/usr/bin/env bash
set -euo pipefail

# Pick an installed prompt or skill and insert it into the pane that opened us.
# Prompts are editable; skill invocations are inserted as-is. Nothing is
# submitted: the user keeps the final say.

target_pane="${1:-}"
error_log="${XDG_CACHE_HOME:-$HOME/.cache}/fabric-prompt-picker.log"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_tool="$script_dir/__fabric_prompt_template.sh"
skill_catalog="$script_dir/__skill_catalog.sh"
accept_editor="$script_dir/__accept_editor.sh"

report_error() {
	local status=$? failed_command="${BASH_COMMAND:-unknown}" line="${BASH_LINENO[0]:-unknown}"
	mkdir -p "$(dirname "$error_log")"
	printf '%(%Y-%m-%dT%H:%M:%S%z)T status=%s line=%s command=%q\n' \
		-1 "$status" "$line" "$failed_command" >> "$error_log"
	printf '\nPrompt picker failed (status %s).\nLog: %s\n' "$status" "$error_log" >&2
	if [[ -t 0 ]]; then
		read -r -p 'Press Enter to close...' _
	fi
	exit "$status"
}

trap report_error ERR

if [[ -z "$target_pane" ]] && command -v tmux >/dev/null 2>&1; then
	target_pane="$(tmux show-option -gqv @fabric_prompt_target 2>/dev/null || true)"
fi
target_pane="${target_pane:-${TMUX_PANE:-}}"

declare -A pattern_files=()
pattern_roots=(
	"$HOME/dev/dotfiles/.config/fabric/custom_patterns"
	"$HOME/.config/fabric/custom_patterns"
	"$HOME/.config/fabric/patterns"
)

load_patterns() {
	local root file directory name
	for root in "${pattern_roots[@]}"; do
		[[ -d "$root" ]] || continue
		while IFS= read -r -d '' file; do
			directory="${file%/*}"
			name="${directory##*/}"
			# Prefer the first root, so dotfiles-owned prompts win over copies.
			[[ -v "pattern_files[$name]" ]] || pattern_files["$name"]="$file"
		done < <(find -L "$root" -mindepth 2 -maxdepth 2 -type f -name system.md -print0)
	done
}

list_patterns() {
	local name
	for name in "${!pattern_files[@]}"; do
		printf 'prompt\t%s\t%s\t-\tfabric\n' "$name" "${pattern_files[$name]}"
	done | sort
}

copy_to_clipboard() {
	if command -v xclip >/dev/null 2>&1; then
		xclip -selection clipboard
	else
		return 1
	fi
}

deliver_text() {
	local content="$1" label="$2" buffer_name
	if [[ -n "$target_pane" ]] && tmux display-message -p -t "$target_pane" '#{pane_id}' >/dev/null 2>&1; then
		buffer_name="capability-picker-${target_pane#%}-$$"
		printf '%s' "$content" | tmux load-buffer -b "$buffer_name" -
		# The popup owns the client until this process exits. Paste afterwards so
		# terminal UIs receive multiline text reliably.
		tmux run-shell -b "sleep 0.15; tmux paste-buffer -b '$buffer_name' -t '$target_pane' -d"
		tmux set-option -gu @fabric_prompt_target 2>/dev/null || true
	elif printf '%s' "$content" | copy_to_clipboard; then
		echo "Copied to clipboard: $label" >&2
	else
		echo "No target tmux pane or clipboard command available." >&2
		return 1
	fi
}

load_patterns

if [[ "${1:-}" == "--list" ]]; then
	list_patterns | cut -f2
	exit 0
fi

agent="${CAPABILITY_PICKER_AGENT:-unknown}"
pane_path="$PWD"
if [[ -n "$target_pane" ]] && tmux display-message -p -t "$target_pane" '#{pane_id}' >/dev/null 2>&1; then
	pane_command="$(tmux display-message -p -t "$target_pane" '#{pane_current_command}')"
	pane_path="$(tmux display-message -p -t "$target_pane" '#{pane_current_path}')"
	if [[ "$agent" == unknown ]]; then
		pane_tty="$(tmux display-message -p -t "$target_pane" '#{pane_tty}')"
		foreground_pgid="$(ps -t "${pane_tty#/dev/}" -o tpgid= 2>/dev/null | awk 'NF { print $1; exit }')"
		foreground_commands="$(ps -t "${pane_tty#/dev/}" -o pgid=,comm= 2>/dev/null |
			awk -v pgid="$foreground_pgid" '$1 == pgid { print $2 }' | tr '\n' ' ')"
		agent="$(bash "$skill_catalog" agent "$pane_command $foreground_commands")"
	fi
fi

list_capabilities() {
	list_patterns
	if [[ "$agent" == claude || "$agent" == codex ]]; then
		bash "$skill_catalog" list "$agent" "$pane_path"
	fi
}

capabilities="$(list_capabilities)"
if [[ -z "$capabilities" ]]; then
	echo "No prompts or skills found." >&2
	exit 1
fi

selection="$(printf '%s\n' "$capabilities" | fzf \
	--delimiter=$'\t' \
	--with-nth=1,2,5 \
	--prompt="Library ($agent)> " \
	--header='Enter: insert skill or edit prompt  Ctrl-e: edit source  Esc: cancel' \
	--bind='ctrl-e:execute(nvim {3})+refresh-preview' \
	--preview='bat --style=plain --language=markdown --color=always {3}' \
	--preview-window='right:60%:wrap')" || exit 0

IFS=$'\t' read -r capability_kind capability_name capability_file invocation _capability_source <<< "$selection"

if [[ "$capability_kind" == skill ]]; then
	deliver_text "$invocation" "$capability_name"
	exit 0
fi

pattern_name="$capability_name"
pattern_file="$capability_file"
prompt="$(cat "$pattern_file")"
editor_input="$(printf '%s\n' "$prompt" | bash "$template_tool" prepare)"
edit_file="$(mktemp --suffix=.md)"
printf '%s\n' "$editor_input" > "$edit_file"
accept_marker="$(mktemp)"
rm -f "$accept_marker"
if [[ -n "${VISUAL:-}" ]]; then
	editor_spec="$VISUAL"
elif [[ -n "${EDITOR:-}" ]]; then
	editor_spec="$EDITOR"
elif command -v nvim >/dev/null 2>&1; then
	editor_spec=nvim
else
	editor_spec=/usr/bin/editor
fi

if CAPABILITY_PICKER_EDITOR="$editor_spec" \
	CAPABILITY_PICKER_ACCEPT_FILE="$accept_marker" \
	bash "$accept_editor" "$edit_file"; then
	if [[ ! -e "$accept_marker" ]]; then
		rm -f "$edit_file"
		exit 0
	fi
	edited_prompt="$(cat "$edit_file")"
	rm -f "$edit_file" "$accept_marker"
else
	edit_status=$?
	rm -f "$edit_file" "$accept_marker"
	exit "$edit_status"
fi

if [[ "$edited_prompt" == *'--- FABRIC PROMPT ---'* ]]; then
	edited_prompt="$(printf '%s\n' "$edited_prompt" | bash "$template_tool" render)"
fi

if [[ -z "${edited_prompt//[[:space:]]/}" ]]; then
	echo "Prompt is empty; nothing inserted." >&2
	exit 0
fi

deliver_text "$edited_prompt" "$pattern_name"
