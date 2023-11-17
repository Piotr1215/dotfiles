#!/bin/bash

# Function to process each file and extract the required information
process_file() {
	local file=$1
	local dir=$(dirname "$file")
	echo "Directory: $dir"

	# Extract the required fields and sort by kind
	yq e '.spec.resources[] | (.base.kind + ", " + (.name // "N/A") + ", " + .base.apiVersion)' "$file" |
		sort |
		awk -F, -v dir="$dir" '
            {
                kind = $1;
                info[kind] = info[kind] ? info[kind] "\n- " $2 ", " $3 : "- " $2 ", " $3;
                count[kind]++;
            }
            END {
                for (kind in info) {
                    print kind " (" count[kind] "):\n" info[kind];
                }
            }'
	echo # Print a newline for separation
}

# Exporting the function to be used by xargs
export -f process_file

# Searching for the specific files and processing each one
find . -type f -name '*composition*.yaml' | xargs -I {} bash -c 'process_file "{}"'
