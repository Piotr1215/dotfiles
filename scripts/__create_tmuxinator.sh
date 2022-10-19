#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -euo pipefail

# Add source and line number wher running in debug mode: bash -xv test.sh
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# Set new line and tab for word splitting
IFS=$'\n\t'

display_help() {
	{
		cat <<EOF
		Create a new tmuxinator project based on
		current git repository and an active branch
EOF
	}
}

# Detect if git repo and exit if not
is_git_repo() {
	if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		echo "This is not a git repo" && return 2
	fi
}

# Gather information about the repo
parse_repository() {
	branch=$(git rev-parse --abbrev-ref HEAD)
	repo_path=$(git rev-parse --show-toplevel)
	repo_name=$(basename $(git rev-parse --show-toplevel))
	full_name="$repo_name-$branch"
}

# Looks like this project already exists, should we start it?
start_existing_project() {
	if tmuxinator list | grep -q "$full_name"; then
		read -p -r "This tmuxinator project already exists, you you want to start it? [y/n] " input

		case $input in
		[yY][eE][sS] | [yY])
			tmuxinator start "$full_name"
			;;
		[nN][oO] | [nN])
			echo "Exiting" && return 0
			;;
		*)
			echo "Invalid input..."
			return 1
			;;
		esac
	fi
}

# Create new tmuxinator project
create_new_project() {
	echo "Creating a new tmuxinator project $full_name"
	cp ~/.config/tmuxinator/poke.yml ~/.config/tmuxinator/"$full_name".yaml
	new_project="$HOME/.config/tmuxinator/$full_name.yaml"

	# Change base values
	sed -i "s#^name: poke#name: $full_name#" "$new_project"
	sed -i "s#^root: ~/dev/#root: $repo_path#" "$new_project"
}

main() {
	set +u
	if [[ "$1" =~ (-h|--help) ]]; then
		display_help "$1"
		return 0
	fi
	set -u
	is_git_repo
	parse_repository
	start_existing_project
	create_new_project
	tmuxinator start "$full_name"
}

main "$@"
