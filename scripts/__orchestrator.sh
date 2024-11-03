#!/usr/bin/env bash
set -eu pipefail
IFS=$'\n\t'

CONTEXT_DIR="$HOME/dev/dotfiles/fabriccontexts"

execute_fabric() {
	local pattern="$1" input="$2" session="$3" context="${4:-}"
	local cmd=("fabric" "-p" "$pattern" "--session=$session")
	local cmd_display="fabric -p \"$pattern\" --session=\"$session\""

	if [[ -n "$context" ]]; then
		cmd+=("--context=$context")
		cmd_display+=" --context=\"$context\""
	fi

	echo "Executing: $cmd_display" >&2

	echo "$input" | "${cmd[@]}" | grep -v "Creating new session:" || true
}

select_pattern() {
	fabric -l | fzf --prompt='Select Fabric Pattern (Ctrl+X to select context): ' \
		--preview 'bat --style=plain --language=markdown --color=always ~/.config/fabric/patterns/{}/system.md' \
		--preview-window=right:70% \
		--bind 'ctrl-x:execute(echo {} > /tmp/selected_pattern)+abort' || echo ""
}

select_context() {
	local context_files
	context_files=$(find -L "$CONTEXT_DIR" -type f -name "*.md" -print)
	if [[ -z "$context_files" ]]; then
		echo "No context files found." >&2
		return
	fi

	local selected_context
	selected_context=$(echo "$context_files" | fzf --prompt='Select Context: ' \
		--preview 'bat --style=plain --language=markdown --color=always {}' \
		--preview-window=right:70%) || return

	if [[ -n "$selected_context" ]]; then
		basename "$selected_context"
	else
		echo ""
	fi
}

chain_patterns() {
	local patterns=() current_output=""
	local session_name
	session_name=$(tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 4 | head -n 1)
	local pattern="" context="" user_input choice

	while true; do
		if [[ -z "$pattern" ]]; then
			echo "Selecting pattern..."
			pattern=$(select_pattern)
			if [[ -z "$pattern" ]]; then
				if [[ -f /tmp/selected_pattern ]]; then
					pattern=$(cat /tmp/selected_pattern)
					echo "Pattern selected: $pattern"
					rm /tmp/selected_pattern
					echo "Selecting context..."
					context=$(select_context)
				else
					echo "No pattern selected, exiting..." >&2
					break
				fi
			fi
			patterns+=("$pattern")
			echo "Pattern '$pattern' added to the chain."
			if [[ ${#patterns[@]} -eq 1 ]]; then
				session_name="${pattern}_${session_name}"
			fi
		fi

		echo "Enter or edit input (press Ctrl-D when finished):"
		user_input=$(echo "${current_output:-}" | vipe --suffix=md)
		echo "Executing fabric..."
		current_output=$(execute_fabric "$pattern" "$user_input" "$session_name" "$context")
		echo "Output from '$pattern':"
		echo "$current_output"

		echo "What would you like to do next?"
		echo "1) Run with the same pattern"
		echo "2) Select a new pattern"
		echo "3) Finish and exit"
		read -rp "Enter your choice (1/2/3): " choice

		case $choice in
		1)
			echo "Running with the same pattern: $pattern"
			;;
		2)
			pattern=""
			context=""
			;;
		3)
			break
			;;
		*)
			echo "Invalid choice. Please enter 1, 2, or 3."
			pattern=""
			context=""
			;;
		esac
	done

	if [[ -n "$current_output" ]]; then
		echo "Opening final output in Neovim..."
		echo "$current_output" | nvim -c "setlocal buftype=nofile bufhidden=wipe" \
			-c "set ft=markdown" -c "nnoremap <buffer> q :q!<CR>" -
	else
		echo "No output to display." >&2
	fi

	if [[ -n "$session_name" ]]; then
		if ! fabric --wipesession="$session_name"; then
			echo "Failed to wipe session $session_name" >&2
		else
			echo "Session $session_name has been processed."
		fi
	fi
}

chain_patterns
