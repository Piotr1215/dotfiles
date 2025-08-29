#!/usr/bin/env bash
set -eo pipefail

# Script to view PRs you're involved with
# Can be invoked with different modes: simple, fzf, or dash

MODE="${1:-fzf}"

get_all_prs() {
    # Try to get the actual GitHub username if not set
    local username="${GH_USERNAME:-$(gh api user --jq .login 2>/dev/null || echo "@me")}"
    
    # Run all queries in parallel for speed
    (gh search prs --author "$username" --state "open" --limit 50 \
        --json url,title,repository,updatedAt,number,isDraft,author 2>/dev/null || echo "[]") > /tmp/authored_raw.json &
    local pid1=$!
    
    (gh search prs --review-requested "$username" --state "open" --limit 50 \
        --json url,title,repository,updatedAt,number,isDraft,author 2>/dev/null || echo "[]") > /tmp/review_raw.json &
    local pid2=$!
    
    (gh search prs --involves "$username" --state "open" --limit 50 \
        --json url,title,repository,updatedAt,number,isDraft,author 2>/dev/null || echo "[]") > /tmp/involved_raw.json &
    local pid3=$!
    
    (gh search prs --mentions "$username" --state "open" --limit 50 \
        --json url,title,repository,updatedAt,number,isDraft,author 2>/dev/null || echo "[]") > /tmp/mentioned_raw.json &
    local pid4=$!
    
    # Also get approved PRs to mark them (without owner filter to catch all orgs)
    (gh search prs --involves "$username" --state "open" --review approved --limit 100 \
        --json url 2>/dev/null || echo "[]") > /tmp/approved_raw.json &
    local pid5=$!
    
    # Wait for all parallel queries to complete
    wait $pid1 $pid2 $pid3 $pid4 $pid5
    
    # Read the results
    local authored_prs=$(cat /tmp/authored_raw.json)
    local review_prs=$(cat /tmp/review_raw.json)
    local involved_prs=$(cat /tmp/involved_raw.json)
    local mentioned_prs=$(cat /tmp/mentioned_raw.json)
    local approved_urls=$(cat /tmp/approved_raw.json | jq -r '.[].url' | paste -sd '|' -)
    
    # Combine all results and remove duplicates, adding type field
    echo "$authored_prs" | jq '. | map(. + {type: "authored"})' > /tmp/authored.json
    echo "$review_prs" | jq '. | map(. + {type: "review"})' > /tmp/review.json
    echo "$involved_prs" | jq '. | map(. + {type: "involved"})' > /tmp/involved.json
    echo "$mentioned_prs" | jq '. | map(. + {type: "mentioned"})' > /tmp/mentioned.json
    
    # Merge and deduplicate based on URL, keeping track of all types and approval status
    jq -s --arg approved_urls "$approved_urls" '
        flatten | 
        group_by(.url) | 
        map({
            url: .[0].url,
            title: .[0].title,
            repository: .[0].repository,
            updatedAt: .[0].updatedAt,
            number: .[0].number,
            isDraft: .[0].isDraft,
            author: .[0].author.login,
            isApproved: (if $approved_urls != "" then (.[0].url | test($approved_urls)) else false end),
            types: [.[] | .type] | unique | join(",")
        }) |
        sort_by(.updatedAt) | 
        reverse
    ' /tmp/authored.json /tmp/review.json /tmp/involved.json /tmp/mentioned.json
    
    # Clean up all temporary files
    rm -f /tmp/authored.json /tmp/review.json /tmp/involved.json /tmp/mentioned.json
    rm -f /tmp/authored_raw.json /tmp/review_raw.json /tmp/involved_raw.json /tmp/mentioned_raw.json /tmp/approved_raw.json
}

format_pr_line() {
    get_all_prs | jq -r '.[] | 
        # Create tab-separated values for clean fzf parsing
        # Format: date \t org/repo \t pr# \t author \t title_with_icons \t url
        (.updatedAt | split("T")[0]) + "\t" +
        .repository.nameWithOwner + "\t" +
        "#" + (.number | tostring) + "\t" +
        .author + "\t" +
        # Title with icons and draft indicator
        .title + 
        (if .isDraft then " 📝" else "" end) +
        (if .isApproved then " ✅" else "" end) + " " +
        (.types | split(",") | map(
            if . == "authored" then "✍"
            elif . == "review" then "👀"
            elif . == "involved" then "💬"
            elif . == "mentioned" then "📢"
            else "" end
        ) | join("")) + "\t" +
        .url'
}

case "$MODE" in
    simple)
        # Simple markdown list output
        get_all_prs | jq -r '.[] | 
            "* [\(.title)](\(.url)) - \(.repository.nameWithOwner) - @\(.author) - [\(.types)] - " +
            (if .isApproved then "✅ - " else "" end) +
            "\(.updatedAt | split("T")[0])"'
        ;;
    
    fzf)
        # FZF-based interactive picker
        if ! command -v fzf &>/dev/null; then
            echo "fzf is not installed. Falling back to simple mode."
            exec "$0" simple
        fi
        
        # Get PRs data
        pr_data=$(format_pr_line)
        
        if [ -z "$pr_data" ]; then
            echo "No PRs found."
            exit 0
        fi
        
        # Count PRs
        pr_count=$(echo "$pr_data" | wc -l)
        
        # Format for display with proper column alignment
        display_data=$(echo "$pr_data" | awk -F'\t' '{
            # Fixed width columns for alignment
            printf "%-10s │ %-35s │ %7s │ %-15s │ %s\n", 
                $1,                                    # Date (10 chars)
                substr($2, 1, 35),                     # Org/Repo (35 chars max)
                $3,                                     # PR# (7 chars)
                substr($4, 1, 15),                     # Author (15 chars max)
                $5                                      # Title with icons
        }')
        
        # Store pr_data in a temp file for fzf to access
        pr_data_file=$(mktemp)
        echo "$pr_data" > "$pr_data_file"
        
        # Interactive selection without preview  
        selected=$(echo "$display_data" | fzf --ansi \
            --no-preview \
            --header $'Date       │ Repository                          │     PR# │ Author          │ Title\n───────────┼─────────────────────────────────────┼─────────┼─────────────────┼─────────────────────\n✍=author  👀=review  💬=involved  📢=mentioned  📝=draft  ✅=approved   '"$pr_count"$' PRs\nEnter: Open  │  Ctrl-Y: Copy URL  │  Ctrl-S: Clone & Open  │  Ctrl-R: Refresh' \
            --bind 'ctrl-y:execute-silent(echo {} | awk -F" │ " "{print \$3}" | tr -d " #" | xargs -I PR awk -F"\t" "\$3 == \"#PR\" {print \$6; exit}" '"$pr_data_file"' | xclip -selection clipboard)+change-prompt(URL copied! > )' \
            --bind 'ctrl-s:execute(
                org_repo=$(echo {} | awk -F" │ " "{print \$2}" | xargs);
                pr_num=$(echo {} | awk -F" │ " "{print \$3}" | tr -d " #");
                org=$(echo "$org_repo" | cut -d"/" -f1);
                repo=$(echo "$org_repo" | cut -d"/" -f2);
                repo_path="/home/decoder/loft/$repo";
                session_name="$repo-pr$pr_num";
                stashed=false;
                if [ ! -d "$repo_path" ]; then
                    echo "Cloning $org_repo...";
                    mkdir -p "$(dirname "$repo_path")";
                    gh repo clone "$org_repo" "$repo_path";
                else
                    echo "Repository exists, checking status...";
                    if git -C "$repo_path" status --porcelain | grep -q .; then
                        echo "Repository has uncommitted changes, stashing...";
                        git -C "$repo_path" stash push -m "Auto-stash before PR $pr_num checkout";
                        stashed=true;
                    fi;
                    echo "Fetching latest changes for $repo...";
                    git -C "$repo_path" fetch origin --prune;
                    if git -C "$repo_path" rev-parse --verify origin/main >/dev/null 2>&1; then
                        git -C "$repo_path" checkout main >/dev/null 2>&1 || true;
                        git -C "$repo_path" pull origin main --ff-only >/dev/null 2>&1 || true;
                    elif git -C "$repo_path" rev-parse --verify origin/master >/dev/null 2>&1; then
                        git -C "$repo_path" checkout master >/dev/null 2>&1 || true;
                        git -C "$repo_path" pull origin master --ff-only >/dev/null 2>&1 || true;
                    fi;
                fi;
                echo "Checking out PR #$pr_num...";
                cd "$repo_path";
                pr_checkout_success=false;
                if gh pr checkout "$pr_num" 2>/dev/null; then
                    pr_checkout_success=true;
                    # If we stashed changes and PR checkout succeeded, pop the stash
                    if [ "$stashed" = true ]; then
                        echo "Applying stashed changes...";
                        if git stash pop 2>/dev/null; then
                            echo "Successfully applied stashed changes";
                        else
                            echo "Warning: Could not apply stashed changes (conflicts or stash may be empty)";
                        fi;
                    fi;
                else
                    echo "Could not checkout PR (might be from a fork)";
                    # If PR checkout failed but we stashed, pop the stash back
                    if [ "$stashed" = true ]; then
                        echo "Restoring stashed changes since PR checkout failed...";
                        git stash pop 2>/dev/null || echo "Warning: Could not restore stashed changes";
                    fi;
                fi;
                tmux new-session -d -s "$session_name" -c "$repo_path" 2>/dev/null;
                if [ "$stashed" = true ] && [ "$pr_checkout_success" = false ]; then
                    tmux send-keys -t "$session_name" "echo \"⚠️  Auto-stashed changes were restored (PR checkout failed)\"" C-m;
                elif [ "$stashed" = true ]; then
                    tmux send-keys -t "$session_name" "echo \"✅  Auto-stashed changes were applied after PR #$pr_num checkout\"" C-m;
                fi;
                tmux switch-client -t "$session_name" || tmux attach-session -t "$session_name"
            )+abort' \
            --bind 'ctrl-r:reload(bash '"$0"' fzf)')
        
        # Process the selection
        if [ -n "$selected" ]; then
            # Extract PR number from selection using awk instead of cut
            pr_num=$(echo "$selected" | awk -F' │ ' '{print $3}' | tr -d ' #')
            if [ -n "$pr_num" ]; then
                url=$(awk -F'\t' "\$3 == \"#$pr_num\" {print \$6; exit}" "$pr_data_file")
                if [ -n "$url" ]; then
                    echo "Opening: $url" >&2
                    tmux run-shell "xdg-open '$url' && wmctrl -a Firefox"
                fi
            fi
        fi
        
        # Clean up temp file
        rm -f "$pr_data_file"
        ;;
    
    fzf-data)
        # Internal mode for refresh functionality - outputs raw tab-separated data
        format_pr_line
        ;;
    
    dash)
        # Use gh dash if available
        if ! gh extension list | grep -q "gh dash"; then
            echo "gh dash is not installed. Install with: gh extension install dlvhdr/gh-dash"
            echo "Falling back to fzf mode."
            exec "$0" fzf
        fi
        
        # Create a minimal config for just viewing your PRs
        config_file="/tmp/gh-dash-my-prs.yml"
        cat > "$config_file" << 'EOF'
prSections:
  - title: My Open PRs
    filters: is:open author:@me
  - title: Review Requested
    filters: is:open review-requested:@me
  - title: Mentioned
    filters: is:open mentions:@me
layout:
  author:
    hidden: true
  updatedAt:
    width: 10
  repo:
    width: 20
  title:
    grow: true
keybindings:
  prs:
    - key: enter
      command: >
        tmux run-shell "xdg-open '{{.PrUrl}}' && wmctrl -a Firefox"
EOF
        
        # Launch gh dash with the custom config
        gh dash --config "$config_file"
        ;;
    
    *)
        echo "Usage: $0 [simple|fzf|dash]"
        echo "  simple - Output markdown list of PRs"
        echo "  fzf    - Interactive FZF picker (default)"
        echo "  dash   - Use gh dash extension"
        exit 1
        ;;
esac
