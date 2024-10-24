#!/bin/bash

# Fetch the latest changes from the remote
git fetch origin

# Get the list of local branches
local_branches=$(git for-each-ref --format='%(refname:short)' refs/heads/)

# Get the commit hash of origin/main
origin_main_hash=$(git rev-parse origin/main)

# Array to store deleted branches
deleted_branches=()

# Loop through each local branch
for branch in $local_branches; do
	# Skip the current branch (usually main)
	if [ "$branch" = "$(git rev-parse --abbrev-ref HEAD)" ]; then
		continue
	fi

	# Check if origin/main is contained in the branch
	if ! git branch --contains $origin_main_hash | grep -q "$branch"; then
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
