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

# Step 4: Load the Last Sent Index
index_file="/tmp/project_index.txt"
if [[ -f "$index_file" ]]; then
	index=$(<"$index_file")

else
	index=0
fi
# Step 5: Send Keys for the Next Project
if [[ ${#projects[@]} -eq 0 ]]; then
	echo "No project names found, exiting."
	exit 1
else
	while [[ $index -lt ${#projects[@]} ]]; do
		project=${projects[$index]}
		if [[ -z "$project" ]]; then # Skip empty project
			let "index++"
			echo $index >"$index_file" # Update the index file
			continue
		fi
		tmux send-keys "/"
		tmux send-keys Escape
		tmux send-keys Escape
		tmux send-keys "/"
		tmux send-keys "project:$project"
		tmux send-keys Enter
		let "index++"
		echo $index >"$index_file" # Update the index file
		break                      # Exit the while loop after sending keys for a non-empty project
	done

	if [[ $index -ge ${#projects[@]} ]]; then
		echo "All projects have been processed, resetting."
		echo 0 >"$index_file" # Reset the index file
		sleep 0.1
		tmux send-keys "/" Escape
	fi
fi
