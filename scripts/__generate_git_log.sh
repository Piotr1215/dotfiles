#!/usr/bin/env bash

source __trap.sh

# Set the default number of commits to 10
num_commits="${1:-10}"

# Get the remote URL for the current Git repository
remote_url=$(git remote get-url origin)

# Get the git log
git_log_output=$(git log --oneline --decorate=short -n "$num_commits" 2>&1)
exit_status=$?

# If git log exits with a non-zero status, exit the script with an error
if [ $exit_status -ne 0 ]; then
	echo "ERROR: ${git_log_output}"
	exit 1
fi

# Process the git log output
processed_git_log=$(echo "${git_log_output}" | awk -v remote_url="${remote_url}" '{ gsub(/^[a-z0-9]+/, "&@"); printf "- [%s](%s/%s) - %s\n", substr($1, 1, 7), remote_url, substr($1, 1, 40), substr($0, index($0,$2)) }')

# Print the processed git log
echo -e "${processed_git_log}"
