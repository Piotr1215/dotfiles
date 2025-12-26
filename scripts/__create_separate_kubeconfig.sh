#!/usr/bin/env bash

# Check if a folder name was provided
# If not, output a message and exit the script
if [ -z "$1" ]; then
	echo "Please provide the name of the folder to create."
	exit 1
fi

# Create the folder with the provided name
mkdir -p "$1"

# Create a new 'config' file in the created folder
touch "$1/config"

# Create the .envrc file with the desired content
# This file will be used to set environment variables when the directory is entered
cat <<EOL >"$1/.envrc"
source_up
KUBECONFIG=./config
EOL

cd "$1" && direnv allow

# Output the message to indicate success
echo "Folder $1 and .envrc file have been created."
