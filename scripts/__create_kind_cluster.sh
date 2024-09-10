#!/bin/bash

cluster_name=$1

# Check if the cluster exists, if not, create it
if ! kind get clusters | grep -q "^${cluster_name}$"; then
	echo "Cluster ${cluster_name} does not exist. Creating..."
	kind create cluster --name "${cluster_name}"
else
	echo "Cluster ${cluster_name} already exists."
fi
