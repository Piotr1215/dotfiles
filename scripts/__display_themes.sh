#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -euo pipefail
# Set new line and tab for word splitting
IFS=$'\n\t'

themes_folder="$HOME/.config/alacritty/themes/"
config_file="$HOME/.config/alacritty/alacritty.yml"

files=$(tree $HOME/.config/alacritty/themes/ -i | head -n-2 | tail -n+2)

while 'true'; do

	for FILE in $files; do
		sed -i "s#\($themes_folder\)\(.*\)#$themes_folder$FILE#" "$config_file"
		echo "Featuring: $FILE"
		# read -p "Press Enter to continue" </dev/tty
		sleep 3
	done

done
