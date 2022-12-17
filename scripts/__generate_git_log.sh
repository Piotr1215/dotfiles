#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eu

# Add source and line number wher running in debug mode: bash -xv __generate_git_log.sh
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# Set new line and tab for word splitting
IFS=$'\n\t'

# Grab current repo name
repo=$(basename $(git rev-parse --show-toplevel))

# Take last 10 commits and wrap them in https
git log --pretty="%H| - %s" | grep -v Merge | grep -v chore | head -n 10 | sed 's/\(.*|\)/- [&]\(https:\/\/github.com\/piotr1215\/'$repo'\/&\)/g' | sed 's/|//g'
