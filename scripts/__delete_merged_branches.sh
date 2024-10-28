#!/bin/bash

# Fetch the latest changes from the remote
git fetch origin

# Get the list of local branches
local_branches=$(git for-each-ref --format='%(refname:short)' refs/heads/)

# Array to store deleted branches
deleted_branches=()

# Loop through each local branch
for branch in $local_branches; do
	# Skip the current branch (usually main)
	if [ "$branch" = "$(git rev-parse --abbrev-ref HEAD)" ]; then
		continue
	fi

	# Check if the branch has been merged into origin/main
	if git merge-base --is-ancestor "$branch" origin/main; then
		# Attempt to delete the branch
		if git branch -d "$branch" &>/dev/null; then
			deleted_branches+=("$branch")
		fi
	fi
done

# Output the list of deleted branches
if [ ${#deleted_branches[@]} -eq 0 ]; then
	echo "No branches were deleted."
else
	echo "The following local branches were deleted:"
	printf '%s\n' "${deleted_branches[@]}"
fi
