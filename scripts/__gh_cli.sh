#!/usr/bin/env bash

# gh_cli.sh: A CLI for GitHub utilities
# Check for dependencies
for cmd in "gh" "jq" "git"; do
	if ! command -v $cmd &>/dev/null; then
		echo "$cmd is not installed. Please install it and try again."
		exit 1
	fi
done
# Help Menu
function show_help() {
	echo "Usage: gh_cli.sh [command]"
	echo "Available commands:"
	echo "  ghmyissues        - Search for my open issues"
	echo "  ghmyrepos         - Search for my repositories"
	echo "  ghmyprs           - Search for my open PRs"
	echo "  ghrepoprs         - List and select a PR in the current repository"
	echo "  ghrepobranches    - Select a git branch and open its URL"
	echo "  ghgistweb         - Select gist, preview it, output to terminal and go to web view"
	echo "  ghgist            - Select gist, preview it, output to terminal and copy to clipboard"
	echo "  ghnewrepo         - Create a private repo with the current directory name and description"
}
# Print error statement and exit

print_error() {
	local exit_code="$?"
	local line_number="$1"
	local cmd="$2"

	if [[ "$exit_code" -eq "130" ]] || [[ "$exit_code" -eq "123" ]]; then
		echo "Script interrupted by user." >&2
		exit 1
	fi
	echo "ERROR: An error occurred in the script \"$0\" on line $line_number" >&2
	echo "Exit Code: $exit_code" >&2
	echo "Command: $cmd" >&2

	# Print a simple stack trace
	echo "Stack Trace:" >&2
	for i in "${!FUNCNAME[@]}"; do
		echo "  ${FUNCNAME[$i]}() called at line ${BASH_LINENO[$i - 1]} in ${BASH_SOURCE[$i]}" >&2
	done

	exit 1
}

# Common function to format and open URLs
format_and_open() {
	local data="$1"
	local longest=$(echo "$data" | awk -F'|' '{ if (length($1) > max) max = length($1) } END { print max }')
	echo "$data" | awk -v max="$longest" -F'|' '{ printf "%-" max "s | %s\n", $1, $2 }' |
		fzf | awk -F'|' '{print $2}' | xargs xdg-open >/dev/null 2>&1
}

# Unified search function
function _ghsearch() {
	local search_type="$1"
	local review_requested="$2"
	local flags=(--state=open --json url,repository,title)

	# Add author or review-requested based on the flag
	if [ "$review_requested" = "true" ]; then
		flags+=(--review-requested "@me")
	else
		flags+=(--author "@me")
	fi

	local data=$(gh search "$search_type" "${flags[@]}" |
		jq -r '.[] | select(.title) | "\(.title) | \(.url)"')
	[ -z "$data" ] && echo "No data found." && return 1

	format_and_open "$data"
}

# Search for my open PRs and open the selected one in a web browser
function ghmyissues() {
	_ghsearch "issues"
}

# Search for my repositories and open the selected one in a web browser
function ghmyrepos() {
	local data=$(gh search repos --owner "@me" --limit 300 --json url,name,owner |
		jq -r '.[] | "\(.name) | \(.url)"')

	format_and_open "$data"
}

# Search for my open PRs and open the selected one in a web browser
function ghmyprs() {
	_ghsearch "prs" "false"
}
function ghmyprsreview() {
	_ghsearch "prs" "true"
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
function ghnewrepo() {
	if [ -z "$2" ]; then
		echo "Please provide a repo description"
		exit 1
	fi
	local repo_description="$1"
	gh repo create "$(basename "$PWD")" --private --source=. --description "$repo_description"
}

# Set the error trap
trap 'print_error $LINENO "$BASH_COMMAND"' ERR

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
ghmyprsreview)
	ghmyprsreview
	;;
ghgist)
	ghgist
	;;
ghnewrepo)
	ghnewrepo "$@"
	;;
*)
	echo "Invalid command"
	show_help
	;;
esac
