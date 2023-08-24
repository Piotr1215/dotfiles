#!/bin/bash

# Accept services as input arguments
services=("$@")

# Check if no services are provided
if [ ${#services[@]} -eq 0 ]; then
	echo "Please provide services to disable."
	exit 1
fi

# Loop through each service and disable it
for service in "${services[@]}"; do
	echo "Disabling $service..."
	sudo systemctl disable $service
	sudo systemctl stop $service
	echo "$service has been disabled and stopped."
	echo "-----------------------------"
done

echo "All specified services have been disabled and stopped."
