#!/usr/bin/env bash

set -eo pipefail
# Find all .yaml files in current and subdirectories
files=$(find . -name "*.yaml")

# readarray resources < <(yq -o=j -I=0 '.spec.resources[].base | {"apiVersion": .apiVersion, "kind": .kind}' $files | uniq)
readarray resources < <(yq -o=j -I=0 '. | {"apiVersion": .apiVersion, "kind": .kind}' $files | uniq)
for resource in "${resources[@]}"; do
	apiVersion=$(echo "$resource" | yq e '.apiVersion' -)
	kind=$(echo "$resource" | yq e '.kind' -)
	echo "API Version: $apiVersion"
	# echo "API Version: $apiVersion, Kind: $kind"
done
