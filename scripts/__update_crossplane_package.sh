#!/bin/bash

# Validate the number of arguments
if [[ "$#" -ne 3 ]]; then
	echo "Usage: $0 <file-path> <new-version> <new-provider-origin>"
	exit 1
fi

# Assign arguments to variables
file_path=$1
new_version=$2
new_provider_origin=$3

# Update the version field and provider strings under dependsOn section only if they contain /upbound/
yq eval -i '(.spec.dependsOn[] | select(.provider | contains("/upbound/"))).version = ">='$new_version'"' "$file_path"
yq eval -i '(.spec.dependsOn[] | select(.provider | contains("/upbound/"))).provider |= sub("/upbound/"; "/'$new_provider_origin'/")' "$file_path"
