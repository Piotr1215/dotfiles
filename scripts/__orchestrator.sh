#!/bin/bash

execute_fabric() {
	local pattern="$1"
	local input="$2"
	local session="$3"
	local context="$4"
	local command="fabric -p \"$pattern\" --session=\"$session\""

	if [ -n "$context" ]; then
		command+=" --context=\"$context\""
	fi

	echo "Executing: $command" >&2
	echo "$input" | eval "$command" | grep -v "Creating new session:"
}

select_pattern() {
	fabric -l | fzf --prompt='Select Fabric Pattern (Ctrl+X to select context): ' \
		--preview 'cat ~/.config/fabric/patterns/{}/system.md' \
		--preview-window=right:70% \
		--bind 'ctrl-x:execute(echo {} > /tmp/selected_pattern)+abort'
}

select_context() {
	local CONTEXT_DIR="$HOME/dev/dotfiles/fabriccontexts"
	local context_files=$(find -L "$CONTEXT_DIR" -type f -name "*.md" -print)
	if [ -z "$context_files" ]; then
		echo "No context files found."
		return
	fi
	selected_context=$(echo "$context_files" | fzf --prompt='Select Context: ' \
		--preview 'cat {}' \
		--preview-window=right:70% || echo "")
	if [ -n "$selected_context" ]; then
		context=$(basename "$selected_context")
	else
		context=""
	fi
}

chain_patterns() {
	local patterns=()
	local current_output=""
	local session_name=$(tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 4 | head -n 1)

	while true; do
		echo "Selecting pattern..."
		local pattern=$(select_pattern)

		local context=""
		if [ -z "$pattern" ]; then
			if [ -f /tmp/selected_pattern ]; then
				pattern=$(cat /tmp/selected_pattern)
				echo "Pattern selected via Ctrl+X: $pattern"
				rm /tmp/selected_pattern
				echo "Selecting context..."
				select_context
			else
				echo "No pattern selected, exiting..."
				break
			fi
		fi

		if [ -n "$pattern" ]; then
			patterns+=("$pattern")
			echo "Pattern '$pattern' added to the chain."

			if [ ${#patterns[@]} -eq 1 ]; then
				session_name="${pattern}_${session_name}"
			fi

			echo "Enter or edit input (press Ctrl-D when finished):"
			if [ -z "$current_output" ]; then
				user_input=$(echo "" | vipe --suffix=md)
			else
				user_input=$(echo "$current_output" | vipe --suffix=md)
			fi

			echo "Executing fabric..."
			current_output=$(execute_fabric "$pattern" "$user_input" "$session_name" "$context")
			echo "Output from '$pattern':"
			echo "$current_output"
		fi

		read -p "Add another pattern? (y/n): " add_another
		if [[ $add_another != "y" ]]; then
			break
		fi
	done

	if [ -n "$current_output" ]; then
		echo "Opening final output in Neovim..."
		echo "$current_output" | nvim -c "setlocal buftype=nofile bufhidden=wipe" -c "set ft=markdown" -c "nnoremap <buffer> q :q!<CR>" -
	else
		echo "No output to display."
	fi

	if [ -n "$session_name" ]; then
		fabric --wipesession="$session_name" || echo "Failed to wipe session $session_name"
		echo "Session $session_name has been processed."
	fi
}

chain_patterns
