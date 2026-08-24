#!/usr/bin/env bash
set -euo pipefail

# Pick an installed skill or command and insert its invocation into the pane that
# opened us. Nothing is submitted: the user keeps the final say.
#
# UNBOUND since 2026-08-24. M-i was this picker and went unused; the key now
# cycles subagent sessions (__cycle_agent_session.sh). Kept because skills
# auto-fire but commands still do not, so the catalog has a reader. Run it with
# a pane id to get the old behaviour back:
#   __orchestrator.sh "$(tmux display-message -p '#{pane_id}')"

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

# Pane resolution and delivery are shared with __ddgx.sh: both are popups that
# hand text back to the pane they were opened from, and the correct way to do
# that is subtle enough that two copies means one wrong copy.
source "$script_dir/__lib_pane_deliver.sh"

target_pane="$(popup_source_pane "$target_pane")"
# Consume it immediately. Abandoning this picker used to leave the option set,
# and the next tool to read it would deliver into a pane nobody had pointed at.
clear_popup_source_pane

copy_to_clipboard() {
	if command -v xclip >/dev/null 2>&1; then
		xclip -selection clipboard
	else
		return 1
	fi
}

deliver_text() {
	local content="$1" label="$2"
	if deliver_to_pane "$target_pane" "$content"; then
		clear_popup_source_pane
	elif printf '%s' "$content" | copy_to_clipboard; then
		echo "Copied to clipboard: $label" >&2
	else
		echo "No target tmux pane or clipboard command available." >&2
		return 1
	fi
}

agent="${CAPABILITY_PICKER_AGENT:-unknown}"
pane_path="$PWD"
if pane_is_live "$target_pane"; then
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
