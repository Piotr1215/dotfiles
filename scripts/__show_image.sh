#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -euo pipefail
# Set new line and tab for word splitting

[ -z "$5" ] && echo "Usage: $0 <image> <x> <y> <max height> <max width>" && exit

source "$(ueberzug library)"

ImageLayer 0< <(
	ImageLayer::add [identifier]="example0" [x]="$2" [y]="$3" [max_width]="$5" [max_height]="$4" [path]="$1"
	read
)
