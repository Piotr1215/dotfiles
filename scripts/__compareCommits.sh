#!/bin/bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -euo pipefail
# Set new line and tab for word splitting
IFS=$'\n\t'


echo -n "Main last commit: " && git show main | rg commit | cut -d ' ' -f2
echo "----"
echo -n "${1} last commit: " && git show ${1} | rg commit | cut -d ' ' -f2
