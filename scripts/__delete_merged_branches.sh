#!/bin/bash

# Get the list of merged branches, excluding the current branch
branches=$(git branch --merged main | grep -v '^\*' | sed 's/^ *//')

# Check if there are any branches to delete
if [ -z "$branches" ]; then
	echo "No merged branches to delete."
	exit 0
fi

# Iterate through each branch
echo "The following branches are merged into main:"
echo "$branches"
echo

for branch in $branches; do
	# Prompt the user
	read -p "Delete branch '$branch'? (y/n): " choice

	case "$choice" in
	y | Y)
		git branch -d "$branch"
		echo "Deleted branch $branch"
		;;
	n | N)
		echo "Skipped branch $branch"
		;;
	*)
		echo "Invalid choice. Skipped branch $branch"
		;;
	esac
	echo
done

echo "Branch cleanup complete."
