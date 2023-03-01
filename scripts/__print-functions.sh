#!/bin/bash

# Set the filename of the script containing the functions
FILE=~/.zsh_functions

# Parse the file for function names and comments
declare -a functions=()
while read -r line; do
	# If the line starts with "function" or contains "()" and "{", it's a function definition
	while IFS= read -r comment; do
		if [[ $comment =~ ^# ]]; then
			com="${comment#*#}"
			IFS= read -r next_line
			f_name="${next_line#function}"
			f_name="${f_name%%()*}"
			functions+=("$f_name|$com")
		else
			continue
		fi
	done
done <"$FILE"

# Sort the functions alphabetically by name
IFS=$'\n' sorted=($(sort <<<"${functions[*]}"))
unset IFS

# Print out the sorted functions
for f in "${sorted[@]}"; do
	f_name="${f%|*}"
	com="${f#*|}"
	printf "Function: %-15s - %s\n" "$f_name" "$com"
done
