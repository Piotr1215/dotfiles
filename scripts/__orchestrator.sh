#!/usr/bin/env bash
set -euo pipefail

# Pick an installed skill or command and insert its invocation into the pane that
# opened us. Nothing is submitted: the user keeps the final say.

target_pane="${1:-}"
error_log="${XDG_CACHE_HOME:-$HOME/.cache}/capability-picker.log"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_catalog="$script_dir/__skill_catalog.sh"

report_error() {
	local status=$? failed_command="${BASH_COMMAND:-unknown}" line="${BASH_LINENO[0]:-unknown}"
	mkdir -p "$(dirname "$error_log")"
	printf '%(%Y-%m-%dT%H:%M:%S%z)T status=%s line=%s command=%q\n' \
		-1 "$status" "$line" "$failed_command" >> "$error_log"
	printf '\nCapability picker failed (status %s).\nLog: %s\n' "$status" "$error_log" >&2
	if [[ -t 0 ]]; then
		read -r -p 'Press Enter to close...' _
	fi
	exit "$status"
}

trap report_error ERR

if [[ -z "$target_pane" ]] && command -v tmux >/dev/null 2>&1; then
	target_pane="$(tmux show-option -gqv @capability_picker_target 2>/dev/null || true)"
fi
target_pane="${target_pane:-${TMUX_PANE:-}}"

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
		tmux set-option -gu @capability_picker_target 2>/dev/null || true
	elif printf '%s' "$content" | copy_to_clipboard; then
		echo "Copied to clipboard: $label" >&2
	else
		echo "No target tmux pane or clipboard command available." >&2
		return 1
	fi
}

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

# Every capability is an agent invocation, so an agentless pane has nothing to
# receive one. Say which pane was inspected: the usual cause is firing the picker
# at a plain shell rather than at a running claude or codex.
if [[ "$agent" != claude && "$agent" != codex ]]; then
	echo "No claude or codex session in the target pane (${target_pane:-none}); nothing to insert." >&2
	exit 1
fi

capabilities="$(bash "$skill_catalog" list "$agent" "$pane_path")"
if [[ -z "$capabilities" ]]; then
	echo "No skills or commands found for $agent." >&2
	exit 1
fi

selection="$(printf '%s\n' "$capabilities" | fzf \
	--delimiter=$'\t' \
	--with-nth='{1}  {5}  {2}' \
	--prompt="Library ($agent)> " \
	--header='Enter: insert  Ctrl-e: edit source  Esc: cancel' \
	--bind='ctrl-e:execute(nvim {3})+refresh-preview' \
	--preview='bat --style=plain --language=markdown --color=always {3}' \
	--preview-window='right:60%:wrap')" || exit 0

IFS=$'\t' read -r _capability_kind capability_name _capability_file invocation _capability_source <<< "$selection"

deliver_text "$invocation" "$capability_name"
