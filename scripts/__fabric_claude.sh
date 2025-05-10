#!/usr/bin/env bash

# PROJECT: fabric-mcp
CONTEXT_DIR="$HOME/dev/dotfiles/fabriccontexts"

# Execute fabric pattern
run_fabric() {
    local pattern="$1"
    local input="$2"
    local session="${3:-claude_$(date +%s)}"
    local context="${4:-}"
    
    # Build command
    local cmd=("fabric" "-p" "$pattern" "--session=$session")
    
    # Add context if provided
    if [[ -n "$context" ]]; then
        cmd+=("--context=$context")
    fi
    
    # Execute fabric command
    echo "$input" | "${cmd[@]}" | grep -v "Creating new session:" || true
}

# Main execution
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <pattern_name> <input_text> [session_name] [context_file]"
    exit 1
fi

pattern="$1"
input="$2"
session="${3:-claude_$(date +%s)}"
context="${4:-}"

run_fabric "$pattern" "$input" "$session" "$context"
