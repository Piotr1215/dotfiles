#!/usr/bin/env zsh

# Parse options
zparseopts -D -E \
	-resource:=resource_arg \
	-batch-size:=batch_size_arg

# Check if options are present
if ((!${#resource_arg})) || ((!${#batch_size_arg})); then
	echo "Missing parameters. Usage: $0 -resource {resource_name} -batch-size {batch_size}"
	exit 1
fi

# Extract option values
resource_name=${resource_arg[2]}
batch_size=${batch_size_arg[2]}

# Main logic
crds=$(kubectl --kubeconfig=$KUBECONFIG get $resource_name | awk 'NR>1 {print $1}' | head -$batch_size)
echo "$crds" | while IFS=$'\n' read -r line; do kubectl delete "$resource_name/$line"; done
