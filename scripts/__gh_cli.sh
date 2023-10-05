#!/bin/bash
# gh_cli.sh: A CLI for GitHub utilities

# Help Menu
function show_help() {
	echo "Usage: gh_cli.sh [command]"
	echo "Available commands:"
	echo "  ghmyissues      - Search for my open issues"
	echo "  ghmyrepos       - Search for my repositories"
	echo "  ghmyprs         - Search for my open PRs"
	echo "  ghrepoprs       - List and select a PR in the current repository"
	echo "  ghrepobranches  - Select a git branch and open its URL"
	echo "  ghgistweb       - Select gist, preview it, output to terminal and go to web view"
	echo "  ghgist          - Select gist, preview it, output to terminal and copy to clipboard"
}

# Search for my open issues and open the selected one in a web browser
function _ghsearch() {
	local search_type="$1"
	pr_data=$(gh search "$search_type" --author "@me" --state=open --json url,repository,title |
		jq -r '.[] | select(.title) | "\(.title) | \(.url)"')

	longest=$(echo "$pr_data" | awk -F'|' '{ if (length($1) > max) max = length($1) } END { print max }')

	echo "$pr_data" | awk -v max="$longest" -F'|' '{ printf "%-" max "s | %s\n", $1, $2 }' |
		fzf | awk -F'|' '{print $2}' | xargs xdg-open >/dev/null 2>&1
}

# Search for my open PRs and open the selected one in a web browser
function ghmyissues() {
	_ghsearch "issues"
}

# Search for my repositories and open the selected one in a web browser
function ghmyrepos() {
	pr_data=$(gh search repos --owner "@me" --limit 300 --json url,name,owner |
		jq -r '.[] | "\(.name) | \(.url)"')

	longest=$(echo "$pr_data" | awk -F'|' '{ if (length($1) > max) max = length($1) } END { print max }')

	echo "$pr_data" | awk -v max="$longest" -F'|' '{ printf "%-" max "s | %s\n", $1, $2}' |
		fzf | awk -F'|' '{print $2}' | xargs xdg-open >/dev/null 2>&1
}

# Search for my open PRs and open the selected one in a web browser
function ghmyprs() {
	_ghsearch "prs"
}

# Function to list and select a PR in the current repository, then open its URL
function ghrepoprs() {
	# Fetch PRs in the current repository
	pr_data=$(gh pr list --json url,number,title --limit 300 |
		sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' |
		jq -r '.[] | "\(.number) | \(.title) | \(.url)"')

	export GH_FORCE_TTY=100%

	# Select a PR using fzf with a preview panel
	selected_pr=$(echo "$pr_data" | fzf --ansi \
		--preview 'gh pr view $(awk -F"|" "{print \$1}" <<< {})' \
		--preview-window=up:40:wrap)

	# If no PR was selected (e.g., fzf was exited), then exit the function
	[ -z "$selected_pr" ] && return

	# Extract the PR URL and remove leading/trailing whitespace
	pr_url=$(echo "$selected_pr" | awk -F'|' '{print $3}' | xargs)

	# Open the selected PR's URL in the web browser
	xdg-open "$pr_url" >/dev/null 2>&1
}

# Function to select a git branch and open its URL
function ghrepobranches() {
	# Fetch remote branches and clean the output
	remote_branches=$(git ls-remote --heads 2>/dev/null | awk '{print $2}' | sed 's/^refs\/heads\///')

	# Select a branch using fzf
	selected_branch=$(echo "$remote_branches" | fzf --ansi \
		--preview 'git show-branch {} | head -3' \
		--preview-window=up:5:wrap)

	# If no branch was selected (e.g., fzf was exited), then exit the function
	[ -z "$selected_branch" ] && return

	# Navigate to the URL of the selected branch
	gh repo view --branch "$selected_branch" --web
}

# Select gist, preview it, output to terminal and go to web view
function ghgistweb() {
	GH_FORCE_TTY=100% gh gist list --limit 1000 | fzf --ansi --preview 'GH_FORCE_TTY=100% gh gist view {1}' --preview-window up | awk '{print $1}' | xargs gh gist view --web | tee /dev/tty | xsel --clipboard
}

# Select gist, preview it, output to terminal and copy to clipboard
function ghgist() {
	GH_FORCE_TTY=100% gh gist list --limit 1000 | fzf --ansi --preview 'GH_FORCE_TTY=100% gh gist view {1}' --preview-window up | awk '{print $1}' | xargs gh gist view --raw | tee /dev/tty | xsel --clipboard
}

# Argument Parsing with Help Menu
case "$1" in
-h | --help)
	show_help
	;;
ghmyissues)
	ghmyissues
	;;
ghmyrepos)
	ghmyrepos
	;;
ghmyprs)
	ghmyprs
	;;
ghrepoprs)
	ghrepoprs
	;;
ghrepobranches)
	ghrepobranches
	;;
ghgistweb)
	ghgistweb
	;;
ghgist)
	ghgist
	;;
*)
	echo "Invalid command"
	show_help
	;;
esac
