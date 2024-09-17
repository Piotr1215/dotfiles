#!/bin/zsh

# Step 1: Execute Command and Capture Output
temp_file=$(mktemp)
task current-projects | uniq >"$temp_file"

# Step 2: Clean Up the Output
sed -i '/--------/,$!d' "$temp_file" # Delete all lines before --------
sed -i '/--------/d' "$temp_file"    # Delete the line with --------
sed -i '/^$/,$d' "$temp_file"        # Delete all lines from the first empty line

# Step 3: Load the Project Names
projects=()
while IFS= read -r line; do
	projects+=("$line")
done <"$temp_file"

# Clean up the temporary file
rm "$temp_file"

# Debug: Print the projects array
echo "Projects array: ${projects[@]}"

# Step 4: Load the Last Sent Index
index_file="/tmp/project_index.txt"
if [[ -f "$index_file" ]]; then
	index=$(<"$index_file")
else
	index=1 # Start from 1 due to Zsh's 1-based indexing
fi

# Debug: Print the current index
echo "Current index: $index"

# Step 5: Check if All Projects Have Been Processed
if [[ $index -gt ${#projects[@]} ]]; then
	echo "All projects have been processed, resetting filter."
	echo 1 >"$index_file"     # Reset the index file to 1
	tmux send-keys "/" Escape # Reset the filter
	exit 0
fi

# Step 6: Send Keys for the Current Project
project=${projects[$index]}
if [[ -z "$project" ]]; then
	((index++))
	echo $index >"$index_file"
	exit 0
fi

# Debug: Print the current project
echo "Current project: $project"

# Escape any special characters in the project name
escaped_project=$(printf '%q' "$project")

tmux send-keys "/"
tmux send-keys Escape
tmux send-keys Escape
tmux send-keys "/"

# Use exact match in the filter
tmux send-keys "project.is:$escaped_project"
tmux send-keys Enter

# Step 7: Increment the index and save it
((index++))
echo $index >"$index_file"
