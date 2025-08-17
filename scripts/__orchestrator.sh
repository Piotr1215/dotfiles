#!/usr/bin/env bash
set -eu pipefail
IFS=$'\n\t'

CONTEXT_DIR="$HOME/.config/fabric/contexts"
THINKING_MODE=""  # Global thinking mode setting
MODEL="gpt-4o"  # Default to GPT-4o (faster than GPT-5)

parse_variables() {
	local input="$1"
	local -a variables=()
	
	# Parse lines that match VARIABLE="value" or VARIABLE=value
	while IFS= read -r line; do
		# Match lines like VARIABLE="value" or VARIABLE=value
		if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
			local var_name="${BASH_REMATCH[1]}"
			local var_value="${BASH_REMATCH[2]}"
			# Remove surrounding quotes if present
			var_value="${var_value%\"}"
			var_value="${var_value#\"}"
			variables+=("-v=${var_name}:${var_value}")
		fi
	done <<< "$input"
	
	# Return the variables array
	printf '%s\n' "${variables[@]}"
}

extract_content() {
	local input="$1"
	local content=""
	
	# Extract non-variable lines as content
	while IFS= read -r line; do
		# Skip variable assignment lines
		if ! [[ "$line" =~ ^[A-Z_]+=.*$ ]]; then
			if [[ -n "$content" ]]; then
				content+=$'\n'
			fi
			content+="$line"
		fi
	done <<< "$input"
	
	echo "$content"
}

execute_fabric() {
	local pattern="$1" input="$2" session="$3" context="${4:-}"
	local cmd=("fabric" "-p" "$pattern" "--session=$session")
	local cmd_display="fabric -p \"$pattern\" --session=\"$session\""

	# Parse variables from input
	local -a variables=()
	mapfile -t variables < <(parse_variables "$input")
	
	# Extract content (non-variable lines)
	local content
	content=$(extract_content "$input")
	
	# Add variables to command
	for var in "${variables[@]}"; do
		if [[ -n "$var" ]]; then
			cmd+=("$var")
			cmd_display+=" $var"
		fi
	done

	if [[ -n "$context" ]]; then
		cmd+=("--context=$context")
		cmd_display+=" --context=\"$context\""
	fi

	# Add model if set
	if [[ -n "$MODEL" ]]; then
		cmd+=("--model=$MODEL")
		cmd_display+=" --model=\"$MODEL\""
		# Note: Streaming is disabled by default (no --stream flag)
		# OpenAI models require org verification for streaming
	fi

	# Add thinking mode if set (only for Claude models)
	if [[ -n "$THINKING_MODE" && "$THINKING_MODE" != "off" ]]; then
		# Check if model is Claude
		if [[ "$MODEL" == claude* ]]; then
			# For Claude thinking mode, use lower numeric values to avoid max_tokens issue
			# Fabric doesn't properly handle max_tokens for Claude thinking mode
			local thinking_value="$THINKING_MODE"
			if [[ "$THINKING_MODE" == "high" ]]; then
				thinking_value="3000"  # Reduced from 10000
			elif [[ "$THINKING_MODE" == "medium" ]]; then
				thinking_value="2000"  # Reduced from 5000
			elif [[ "$THINKING_MODE" == "low" ]]; then
				thinking_value="1000"  # Reduced from 2000
			fi
			cmd+=("--thinking=$thinking_value")
			cmd_display+=" --thinking=\"$thinking_value\""
			# When thinking is enabled for Claude, temperature must be 1
			cmd+=("--temperature=1")
			cmd_display+=" --temperature=1"
		fi
	fi


	echo "Executing: $cmd_display" >&2

	# Pass only the content (non-variable lines) to fabric
	echo "$content" | "${cmd[@]}" | grep -v "Creating new session:" || true
}

select_pattern() {
	local context_param="${1:-}"
	local context_display="${context_param:-none}"
	
	local prompt_line1="Model (C-o): ${MODEL:-gpt-4o} | Thinking (C-t): ${THINKING_MODE:-off} | Context (C-x): ${context_display}"
	
	fabric -l | fzf --prompt="$prompt_line1
> " \
		--preview 'bat --style=plain --language=markdown --color=always ~/.config/fabric/patterns/{}/system.md' \
		--preview-window=right:60% \
		--bind 'ctrl-x:execute(echo {} > /tmp/selected_pattern && touch /tmp/select_context)+abort' \
		--bind 'ctrl-t:execute(touch /tmp/select_thinking)+abort' \
		--bind 'ctrl-o:execute(touch /tmp/select_model)+abort' || echo ""
}

select_thinking_mode() {
	local modes=("off" "low" "medium" "high" "1000" "5000" "10000" "20000")
	local selected
	selected=$(printf '%s\n' "${modes[@]}" | fzf --prompt='Select Thinking Level: ' \
		--preview='echo "Thinking Mode: {}\n\noff: No thinking\nlow/medium/high: Predefined levels\n1000-20000: Token budget for reasoning"' \
		--preview-window=right:50%) || return
	echo "$selected"
}

select_model() {
	# These are the actual working cutting-edge models
	local models=(
		"gpt-5"
		"gpt-5-mini"
		"gpt-5-nano"
		"claude-3-5-sonnet-latest"
		"claude-3-7-sonnet-latest"
		"claude-opus-4-1-20250805"
		"gpt-4o"
		"gpt-4o-mini"
		"o1"
		"o1-mini"
		"o1-pro"
	)
	
	local selected
	selected=$(printf '%s\n' "${models[@]}" | fzf --prompt='Select Model: ' \
		--preview='echo "Model: {}\n\n🚀 Latest Models:\n  • GPT-5: OpenAI flagship! 400K context\n  • GPT-5-mini/nano: Faster variants\n  • claude-opus-4-1: Most capable Claude\n  • claude-3-5-sonnet: 1M context window\n  • o1-pro: Advanced reasoning"' \
		--preview-window=right:50%) || return
	echo "$selected"
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

get_pattern_variables() {
	local pattern="$1"
	local pattern_file="$HOME/.config/fabric/patterns/$pattern/system.md"
	local custom_pattern_file="$HOME/.config/fabric/custom_patterns/$pattern/system.md"
	local file_to_check=""
	
	# Check which file exists
	if [[ -f "$pattern_file" ]]; then
		file_to_check="$pattern_file"
	elif [[ -f "$custom_pattern_file" ]]; then
		file_to_check="$custom_pattern_file"
	else
		return
	fi
	
	# Extract variables between {{ and }}
	grep -o '{{[A-Z_]*}}' "$file_to_check" 2>/dev/null | sed 's/{{//g; s/}}//g' | sort -u
}

chain_patterns() {
	# Clean up any leftover temp files from previous runs
	rm -f /tmp/selected_pattern /tmp/select_thinking /tmp/select_model /tmp/select_context 2>/dev/null || true
	
	local patterns=() current_output=""
	local conversation_history=""  # Track full conversation
	local exchange_num=0  # Track exchange number
	local session_name
	session_name=$(tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 4 | head -n 1)
	local pattern="" context="" user_input choice

	while true; do
		if [[ -z "$pattern" ]]; then
			local continue_selecting=true
			while [[ "$continue_selecting" == "true" ]]; do
				# Clean up any leftover temp files at start of each iteration
				rm -f /tmp/selected_pattern /tmp/select_thinking /tmp/select_model /tmp/select_context 2>/dev/null || true
				
				echo "Selecting pattern..."
				local selected_item=$(select_pattern "$context")
				
				# Check for special mode selections
				if [[ -f /tmp/select_thinking ]]; then
					rm /tmp/select_thinking
					echo "Selecting thinking mode..."
					local new_thinking
					new_thinking=$(select_thinking_mode)
					if [[ -n "$new_thinking" ]]; then
						THINKING_MODE="$new_thinking"
						echo "Thinking mode set to: $THINKING_MODE"
					fi
					# Go back to pattern selection
				elif [[ -f /tmp/select_model ]]; then
					rm /tmp/select_model
					echo "Selecting model..."
					local new_model
					new_model=$(select_model)
					if [[ -n "$new_model" ]]; then
						MODEL="$new_model"
						echo "Model set to: $MODEL"
					fi
					# Go back to pattern selection
				elif [[ -f /tmp/select_context ]]; then
					rm /tmp/select_context
					if [[ -f /tmp/selected_pattern ]]; then
						rm /tmp/selected_pattern
					fi
					echo "Selecting context (optional, press ESC to skip)..."
					context=$(select_context)
					if [[ -n "$context" ]]; then
						echo "Context set to: $context"
					fi
					# Go back to pattern selection
				elif [[ -n "$selected_item" ]]; then
					# User just hit Enter on a pattern
					pattern="$selected_item"
					echo "Pattern selected: $pattern"
					continue_selecting=false
				else
					echo "No pattern selected, exiting..." >&2
					return
				fi
			done
			patterns+=("$pattern")
			echo "Pattern '$pattern' added to the chain."
			if [[ ${#patterns[@]} -eq 1 ]]; then
				session_name="${pattern}_${session_name}"
			fi
		fi

		# Display current settings
		echo -e "\n📋 Current Settings:"
		echo "   Model: ${MODEL:-gpt-4o}"
		[[ -n "$THINKING_MODE" && "$THINKING_MODE" != "off" ]] && echo "   Thinking: $THINKING_MODE"
		[[ -n "$context" ]] && echo "   Context: $context"
		echo ""
		
		echo "Enter or edit input (press Ctrl-D when finished):"
		
		# Prepare the vipe content with history
		local vipe_content=""
		if [[ -n "$conversation_history" ]]; then
			vipe_content="=== CONVERSATION HISTORY (DO NOT EDIT ABOVE THIS LINE) ===\n"
			vipe_content+="$conversation_history\n"
			vipe_content+="\n=== YOUR NEW INPUT BELOW ===\n"
		else
			# First exchange - check for pattern variables
			local pattern_vars
			pattern_vars=$(get_pattern_variables "$pattern")
			
			if [[ -n "$pattern_vars" ]]; then
				# Prefill with variable template
				vipe_content="# Variables for pattern: $pattern\n"
				vipe_content+="# Fill in the values below:\n\n"
				while IFS= read -r var; do
					vipe_content+="${var}=\"\"\n"
				done <<< "$pattern_vars"
				vipe_content+="\n# Additional content (optional):\n"
			elif [[ -n "$current_output" ]]; then
				# Just show the previous output if chaining
				vipe_content="${current_output:-}"
			fi
		fi
		
		# Show full history in vipe
		local full_input=$(echo -e "$vipe_content" | vipe --suffix=md)
		
		# Extract only the actual input (everything after the separator)
		if [[ "$full_input" == *"=== YOUR NEW INPUT BELOW ==="* ]]; then
			user_input=$(echo "$full_input" | sed -n '/=== YOUR NEW INPUT BELOW ===/,$p' | tail -n +2)
		else
			# Remove comment lines from the input
			user_input=$(echo "$full_input" | grep -v '^#' | sed '/^$/d')
		fi
		
		echo "Executing fabric..."
		current_output=$(execute_fabric "$pattern" "$user_input" "$session_name" "$context")
		
		# Update conversation history
		exchange_num=$((exchange_num + 1))
		if [[ -n "$conversation_history" ]]; then
			conversation_history+="\n"
		fi
		conversation_history+="[$exchange_num] You: $user_input"
		conversation_history+="\n[$exchange_num] AI: $current_output"
		echo -e "\n📝 Your input:"
		echo "$user_input"
		echo -e "\n🤖 Output from '$pattern':"
		echo "$current_output"

		echo "What would you like to do next?"
		echo "1) Run with the same pattern"
		echo "2) Select a new pattern"
		echo "3) Change thinking mode"
		echo "4) Change model"
		echo "5) Finish and exit"
		read -rp "Enter your choice (1-5): " choice

		case $choice in
		1)
			echo "Running with the same pattern: $pattern"
			;;
		2)
			pattern=""
			context=""
			;;
		3)
			echo "Selecting thinking mode..."
			THINKING_MODE=$(select_thinking_mode)
			echo "Thinking mode set to: ${THINKING_MODE:-none}"
			;;
		4)
			echo "Selecting model..."
			MODEL=$(select_model)
			echo "Model set to: ${MODEL:-default}"
			;;
		5)
			break
			;;
		*)
			echo "Invalid choice. Please enter 1-5."
			pattern=""
			context=""
			;;
		esac
	done

	if [[ -n "$current_output" ]]; then
		echo "Opening final output in Neovim..."
		# Show complete conversation history
		local full_conversation="# 📚 Complete Conversation History\n\n"
		if [[ -n "$conversation_history" ]]; then
			full_conversation+="$conversation_history\n\n"
			full_conversation+="---\n\n"
		fi
		full_conversation+="## 📝 Final Exchange:\n"
		full_conversation+="**You:** $user_input\n\n"
		full_conversation+="**AI:** $current_output"
		
		echo -e "$full_conversation" | nvim -c "setlocal bufhidden=wipe" \
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
