#!/bin/bash

# Check if a folder name was provided
if [ -z "$1" ]; then
	echo "Please provide the name of the folder to create."
	exit 1
fi

# Create the folder
mkdir -p "$1"

touch "$1/config"

# Create the .envrc file with the desired content
cat <<EOL >"$1/.envrc"
source_up
KUBECONFIG=./config
EOL

# Output the message to indicate success
echo "Folder $1 and .envrc file have been created."
