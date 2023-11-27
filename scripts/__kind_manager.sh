#!/bin/bash

# Function to start a kind cluster
start_cluster() {
	local cluster_name=$1
	echo "Starting cluster: $cluster_name"
	local containers=$(docker ps -a --filter "name=${cluster_name}-.*" --format "{{.ID}}")
	echo "Containers to start: $containers"
	if [ -z "$containers" ]; then
		echo "No stopped containers found for cluster ${cluster_name}"
		return
	fi
	docker start $containers
}

# Function to stop a kind cluster
stop_cluster() {
	local cluster_name=$1
	echo "Stopping cluster: $cluster_name"
	local containers=$(docker ps --filter "name=${cluster_name}-.*" --format "{{.ID}}")
	echo "Containers to stop: $containers"
	if [ -z "$containers" ]; then
		echo "No running containers found for cluster ${cluster_name}"
		return
	fi
	docker stop $containers
}

# Main logic
case $1 in
--start)
	start_cluster $2
	;;
--stop)
	stop_cluster $2
	;;
*)
	echo "Usage: $0 --start|--stop <cluster_name>"
	exit 1
	;;
esac
