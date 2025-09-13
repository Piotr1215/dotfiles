#!/usr/bin/env bash
set -euo pipefail

# List all specs (one per branch)

CLAUDE_DIR=".claude"
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
SAFE_BRANCH=$(echo "$CURRENT_BRANCH" | sed 's/[^a-zA-Z0-9._-]/-/g')

if [[ ! -d "$CLAUDE_DIR/specs" ]]; then
    echo "No specs found."
    exit 0
fi

echo "Specs (one per branch):"
echo ""

for spec_dir in "$CLAUDE_DIR/specs"/*; do
    if [[ -d "$spec_dir" ]]; then
        SPEC_NAME=$(basename "$spec_dir")
        
        # Mark current branch
        MARKER="  "
        if [[ "$SPEC_NAME" == "$SAFE_BRANCH" ]]; then
            MARKER="→ "
        fi
        
        echo -n "$MARKER$SPEC_NAME"
        
        # Show what it contains
        if [[ -f "$spec_dir/spec.md" ]]; then
            echo -n " [S]"
        fi
        if [[ -f "$spec_dir/plan.md" ]]; then
            echo -n " [P]"
        fi
        if [[ -f "$spec_dir/tasks.md" ]]; then
            echo -n " [T]"
        fi
        
        echo ""
    fi
done

echo ""
echo "Legend: [S]=Spec [P]=Plan [T]=Tasks"
echo "Current branch: $CURRENT_BRANCH"