# __gh_cli.sh: A collection of GitHub utility functions for Zsh

# Check for dependencies
for cmd in gh jq git fzf xclip; do
	if ! command -v $cmd &>/dev/null; then
		echo "$cmd is not installed. Please install it and try again."
		return 1
	fi
done

# Help Menu
function ghshowhelp() {
	echo "Available commands:"
	echo "  ghissues          - Search for my open issues"
	echo "  ghprs             - Search for my open PRs"
	echo "  ghprsreview       - Search for PRs where review is requested"
	echo "  ghrepoprs         - List and select a PR in the current repository"
	echo "  ghrepobranches    - Select a git branch and open its URL"
	echo "  ghgistweb         - Select gist, preview it, output to terminal and go to web view"
	echo "  ghgist            - Select gist, preview it, output to terminal and copy to clipboard"
	echo "  ghnewrepo         - Create a private repo with the current directory name and description"
	echo "  ghissuescomments  - Search for issues where I commented"
	echo "  ghprcomments      - Search for prs where I commented"
	echo "  ghruns            - Interactive workflow runs viewer"
	echo "  gitstatusmon      - Display git status summary (for tmux panes)"
	echo "  ghhelp            - Show this help message"
}

# Common function to format and open URLs
function format_and_open() {
	local data="$1"
	if [ -z "$data" ]; then
		echo "No data to display."
		return 1
	fi

	echo "$data" | fzf --bind 'ctrl-y:execute-silent(echo -n {2} | xclip -selection clipboard)+change-prompt(URL copied! > )' \
		--delimiter='###' --with-nth=1 \
		--header "Press Ctrl+Y to copy URL to clipboard" \
		--prompt "Select item > " |
		awk -F '###' '{print $2}' |
		xargs -r xdg-open >/dev/null 2>&1
}

# Unified search function
function _ghsearch() {
	local search_type="$1"
	local review_requested="$2"
	local -a flags=(--state=open --json url,repository,title)

	# Add author or review-requested based on the flag
	if [ "$review_requested" = "true" ]; then
		flags+=(--review-requested "@me")
	else
		flags+=(--author "@me")
	fi

	# Format the title and URL with '###' separator and display both
	local data=$(gh search "$search_type" "${flags[@]}" 2>/dev/null |
		jq -r '.[] | "\(.title) ### \(.url)"') # Use '###' as a delimiter

	if [ -z "$data" ]; then
		echo "No data found."
		return 1
	fi

	format_and_open "$data"
}

# Search for my open issues and open the selected one in a web browser
function ghissues() {
	_ghsearch "issues"
}

# Search for my open PRs and open the selected one in a web browser
function ghprs() {
	_ghsearch "prs" "false"
}

# Search for PRs where review is requested from me
function ghprsreview() {
	_ghsearch "prs" "true"
}

# Search for issues where I commented across ALL repositories and open the selected one in a web browser
function ghissuescomments() {
	data=$(gh api \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"/search/issues?q=is:issue+is:open+commenter:Piotr1215" \
		--paginate \
		--jq '.items[] | "\(.title) ### \(.html_url)"')
	# Call the format_and_open function with the retrieved data
	format_and_open "$data"
}
function ghprcomments() {
	local data=$(gh api \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"/search/issues?q=is:pr+is:open+commenter:Piotr1215" \
		--paginate \
		--jq '.items[] | "\(.title) \(.html_url)"')

	if [ -z "$data" ]; then
		echo "No data to display."
		return 1
	fi

	echo "$data" | fzf --bind 'ctrl-y:execute-silent(echo -n {} | awk -F "https" "{print \"https\"\$2}" | xclip -selection clipboard)+change-prompt(URL copied! > )' \
		--delimiter="###" --with-nth=1 \
		--header "Press Ctrl+Y to copy URL to clipboard" \
		--prompt "Select item > " |
		awk -F 'https' '{print "https"$2}' |
		xargs -r xdg-open >/dev/null 2>&1
}

# This function lists pull requests (PRs) from the current GitHub repository using the GitHub CLI.
# It displays the PRs in a selectable list using fzf, allowing the user to preview and open a PR in a web browser.
function ghrepoprs() {
	local pr_raw pr_data selected_pr pr_url

	# Temporarily disable color output
	local old_no_color=$NO_COLOR
	export NO_COLOR=1

	# Fetch PRs
	pr_raw=$(gh pr list --json url,number,title --limit 300 2>&1)
	fetch_status=$?

	# Restore original NO_COLOR setting
	export NO_COLOR=$old_no_color

	if [ $fetch_status -ne 0 ]; then
		echo "Error fetching PRs: $pr_raw"
		return 1
	fi

	# Process JSON
	pr_data=$(echo "$pr_raw" | jq -r '.[] | "\(.number) | \(.title) | \(.url)"' 2>&1)
	jq_status=$?
	echo "$pr_data" | head -n 3

	if [ $jq_status -ne 0 ]; then
		echo "Error processing JSON: $pr_data"
		return 1
	fi

	if [ -z "$pr_data" ]; then
		echo "No PRs found in the current repository."
		return 1
	fi

	export GH_FORCE_TTY=100

	selected_pr=$(echo "$pr_data" | fzf --ansi \
		--preview 'gh pr view $(awk -F"|" "{print \$1}" <<< {})' \
		--preview-window=right:50%:wrap \
		--bind 'ctrl-y:execute-silent(echo -n {3} | xargs | xclip -selection clipboard)')

	if [ -z "$selected_pr" ]; then
		echo "No PR selected."
		return 1
	fi

	pr_url=$(echo "$selected_pr" | awk -F'|' '{print $3}' | xargs)
	xdg-open "$pr_url" >/dev/null 2>&1
}

# Function to select a git branch and open its URL
function ghrepobranches() {
	{
		# Fetch remote branches and clean the output
		local remote_branches=$(git ls-remote --heads 2>/dev/null | awk '{print $2}' | sed 's|^refs/heads/||')

		if [ -z "$remote_branches" ]; then
			echo "No remote branches found."
			return 1
		fi

		# Select a branch using fzf
		local selected_branch=$(echo "$remote_branches" | fzf --ansi \
			--preview 'git show-branch {} | head -3' \
			--preview-window=up:5:wrap \
			--bind 'ctrl-y:execute-silent(gh repo view --branch {} --json url --jq .url | xclip -selection clipboard)')

		# If no branch was selected (e.g., fzf was exited), then exit the function
		if [ -z "$selected_branch" ]; then
			return
		fi

		# Navigate to the URL of the selected branch
		gh repo view --branch "$selected_branch" --web
	} || {
		echo "An error occurred while listing repository branches."
		return 1
	}
}

# Select gist, preview it, output to terminal and go to web view
function ghgistweb() {
	{
		GH_FORCE_TTY=100%
		local selected_gist=$(gh gist list --limit 1000 2>/dev/null | fzf --ansi \
			--preview 'GH_FORCE_TTY=100% gh gist view {1}' --preview-window up \
			--bind 'ctrl-y:execute-silent(echo {1} | xargs -I {} gh gist view --raw {} | xclip -selection clipboard)')

		if [ -z "$selected_gist" ]; then
			return
		fi

		local gist_id=$(echo "$selected_gist" | awk '{print $1}')
		gh gist view --web "$gist_id" | tee /dev/tty | xclip -selection clipboard
	} || {
		echo "An error occurred while accessing gists."
		return 1
	}
}

# Select gist, preview it, output to terminal and copy to clipboard
function ghgist() {
	{
		GH_FORCE_TTY=100%
		local selected_gist=$(gh gist list --limit 1000 2>/dev/null | fzf --ansi \
			--preview 'GH_FORCE_TTY=100% gh gist view {1}' --preview-window up \
			--bind 'ctrl-y:execute-silent(echo {1} | xargs -I {} gh gist view --raw {} | xclip -selection clipboard)')

		if [ -z "$selected_gist" ]; then
			return
		fi

		local gist_id=$(echo "$selected_gist" | awk '{print $1}')
		gh gist view --raw "$gist_id" | tee /dev/tty | xclip -selection clipboard
	} || {
		echo "An error occurred while accessing gists."
		return 1
	}
}

# Create a new private repository with the current directory name and description
function ghnewrepo() {
	if [ -z "$1" ]; then
		echo "Usage: ghnewrepo \"Repository description\""
		return 1
	fi
	local repo_description="$1"

	gh repo create "$(basename "$PWD")" --private --source=. --description "$repo_description" || {
		echo "An error occurred while creating the repository."
		return 1
	}
}

# Interactive workflow runs viewer
function ghruns() {
	# Fetch workflow runs with proper formatting
	local runs=$(gh run list --limit 50 --json databaseId,status,conclusion,workflowName,headBranch,createdAt 2>/dev/null | \
		jq -r 'sort_by(.createdAt) | reverse | .[] | 
			# Format status indicator
			(if .conclusion == "success" then "✓"
			elif .conclusion == "failure" then "✗"
			elif .conclusion == "skipped" then "-"
			elif .status == "in_progress" then "⟳"
			else "?" end) as $status |
			# Format: ID | date | status | branch | workflow
			"\(.databaseId) \(.createdAt | split("T")[0]) \($status) \(.headBranch[0:25]) \(.workflowName)"')
	
	if [ -z "$runs" ]; then
		echo "No workflow runs found"
		return 1
	fi
	
	# Use fzf for interactive selection
	local selected=$(echo "$runs" | fzf --ansi \
		--header $'Keys: Enter=browser | v=view logs | r=rerun\nStatus: ✓=success ✗=failed -=skipped ⟳=running' \
		--preview 'gh run view {1} 2>/dev/null || echo "Loading..."' \
		--preview-window=bottom:50%:wrap \
		--bind 'v:execute(gh run view {1} --log | sed "s/\xEF\xBB\xBF//g" > /tmp/gh-run-log.txt && nvim -c "set nowrap" /tmp/gh-run-log.txt)' \
		--bind 'r:execute-silent(gh run rerun {1})+reload(exit)')
	
	if [ -n "$selected" ]; then
		local run_id=$(echo "$selected" | awk '{print $1}')
		gh run view "$run_id" --web
	fi
}

# Git status monitor for tmux pane
function gitstatusmon() {
	# Branch info
	echo -e "\033[1;36m📍 Branch:\033[0m $(git branch --show-current) -> $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo 'no upstream')"
	
	# Quick status summary
	local staged=$(git diff --cached --numstat | wc -l)
	local unstaged=$(git diff --numstat | wc -l)
	local untracked=$(git ls-files --others --exclude-standard | wc -l)
	echo -e "\033[1;32m✓ Staged:\033[0m $staged | \033[1;33m✎ Modified:\033[0m $unstaged | \033[1;31m? Untracked:\033[0m $untracked"
	
	# Show actual changes if any
	if [ $staged -gt 0 ]; then
		echo -e "\n\033[1;32m=== Staged Changes ===\033[0m"
		git diff --cached --stat | head -5
	fi
	
	if [ $unstaged -gt 0 ]; then
		echo -e "\n\033[1;33m=== Unstaged Changes ===\033[0m"
		git diff --stat | head -5
	fi
	
	# Last commit
	echo -e "\n\033[1;34m=== Last Commit ===\033[0m"
	git log -1 --pretty=format:"%C(yellow)%h%C(reset) - %s %C(green)(%cr)%C(reset)"
	
	# PR info if exists
	echo -e "\n\n\033[1;35m=== PR Status ===\033[0m"
	if pr_info=$(gh pr view --json state,title 2>/dev/null); then
		echo "$pr_info" | jq -r '"\(.state): \(.title)"'
	else
		echo "No PR for current branch"
	fi
}

# Show help message
function ghhelp() {
	ghshowhelp
}
