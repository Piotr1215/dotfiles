#!/bin/bash

set -e

# Ensure we're on the main branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "main" ]; then
	echo "Error: Please run this script from the main branch."
	exit 1
fi

# Update local repository and remove references to deleted remote branches
echo "Updating local repository..."
git fetch --all --prune

# Delete local branches that were merged and deleted on remote
echo "Deleting local branches..."
git branch -vv |
	grep ': gone]' |
	awk '{print $1}' |
	xargs -r -n 1 git branch -d

echo "Cleanup complete!"
