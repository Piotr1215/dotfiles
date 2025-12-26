#!/usr/bin/env bash
set -eo pipefail

# Check required commands
command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl is required but not installed."; exit 1; }
command -v fzf >/dev/null 2>&1 || { echo "Error: fzf is required but not installed."; exit 1; }

# Step 1: Select namespace
NAMESPACE=$(kubectl get namespaces --no-headers -o custom-columns=":metadata.name" | fzf --prompt='Select Namespace: ')

# Check if the namespace was selected
if [ -z "$NAMESPACE" ]; then
	echo "No namespace selected. Exiting."
	exit 1
fi

# Step 2: Select pod
POD=$(kubectl -n "$NAMESPACE" get pods --no-headers -o custom-columns=":metadata.name" | fzf --prompt='Select Pod: ')

# Check if the pod was selected
if [ -z "$POD" ]; then
	echo "No pod selected. Exiting."
	exit 1
fi

# Step 3: Select container
CONTAINER=$(kubectl -n "$NAMESPACE" get pod "$POD" -o jsonpath='{.spec.containers[*].name}' | tr ' ' '\n' | fzf --prompt='Select Container: ')

# Check if the container was selected
if [ -z "$CONTAINER" ]; then
	echo "No container selected. Exiting."
	exit 1
fi

# Step 4: Construct and execute the kubectl debug command
# Allow custom debug image via environment variable
DEBUG_IMAGE="${DEBUG_IMAGE:-ghcr.io/superbrothers/debug}"
KUBECTL_COMMAND="kubectl -n $NAMESPACE debug -it $POD --image=$DEBUG_IMAGE --target=$CONTAINER"
echo "Running command: $KUBECTL_COMMAND"
eval "$KUBECTL_COMMAND"
