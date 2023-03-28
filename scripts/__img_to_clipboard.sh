#!/usr/bin/env bash

# Source generic error handling funcion
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __img_to_clipboard.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

if [ -z "$1" ]; then
	echo "Usage: img_to_clipboard.sh <image-file>"
	exit 1
fi

file_extension=$(echo "${1##*.}" | tr '[:upper:]' '[:lower:]')

case $file_extension in
png)
	mime_type="image/png"
	;;
jpg | jpeg)
	mime_type="image/jpeg"
	;;
gif)
	mime_type="image/gif"
	;;
*)
	echo "Unsupported image format: $file_extension"
	exit 1
	;;
esac

xclip -selection clipboard -t $mime_type -i "$1"
