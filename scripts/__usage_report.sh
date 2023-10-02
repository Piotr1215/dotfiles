#!/bin/bash

# Path to the JSON file
json_file="/home/decoder/dev/dotfiles/.script_usage.json"

# Path to the scripts folder and subfolder
scripts_folder="/home/decoder/dev/dotfiles/scripts"
subfolder="/home/decoder/dev/dotfiles/scripts/uxp-setup"

# Path to the .zsh_functions and .zsh_aliases files
functions_file="/home/decoder/.zsh_functions"
aliases_file="/home/decoder/.zsh_aliases"

# Read the JSON into a variable
json_data=$(cat $json_file)

# Function to process and sort data
process_and_sort() {
	local -n data_ref=$1
	local title=$2

	echo "=== $title ==="
	printf "%-40s | %s\n" "Name" "Count"                                     # Header
	printf "%-40s-|-%s\n" "----------------------------------------" "-----" # Separator

	for key in "${!data_ref[@]}"; do
		printf "%-40s | %s\n" "$key" "${data_ref[$key]}"
	done | sort -t'|' -k2,2nr

	echo ""
}

# Initialize associative arrays for scripts, functions, and aliases
declare -A script_data
declare -A function_data
declare -A alias_data

# Populate the associative array with script data
for script in $(find $scripts_folder -maxdepth 1 -type f -printf "%f\n"); do
	count=$(echo $json_data | jq -r ".[\"$script\"] // .[\"./$script\"] // \"0\"")
	script_data["$script"]=$count
done

# Include the 'justfile' from the subfolder
justfile_count=$(echo $json_data | jq -r ".[\"justfile\"] // \"0\"")
script_data["justfile (uxp-setup)"]=$justfile_count

# Populate the associative array with function data
while read -r function_line; do
	if [[ "$function_line" =~ ^function\ ([a-zA-Z0-9_]+)\ \( ]]; then
		function_name=${BASH_REMATCH[1]}
		count=$(echo $json_data | jq -r ".[\"$function_name\"] // \"0\"")
		function_data["$function_name"]=$count
	fi
done <$functions_file

# Populate the associative array with alias data
while read -r alias_line; do
	if [[ "$alias_line" =~ ^alias\ ([a-zA-Z0-9_-]+)= ]]; then
		alias_name=${BASH_REMATCH[1]}
		count=$(echo $json_data | jq -r ".[\"$alias_name\"] // \"0\"")
		alias_data["$alias_name"]=$count
	fi
done <$aliases_file

# Print the sorted reports
process_and_sort script_data "Script Usage Report"
process_and_sort function_data "Function Usage Report"
process_and_sort alias_data "Alias Usage Report"
