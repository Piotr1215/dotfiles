#!/usr/bin/env bash

uuid="$1"
# Use task _tags command to get current tags
current_tags=$(task _tags "$uuid")

if echo "$current_tags" | grep -q "claude"; then
	# Remove claude tag if present
	task rc.bulk=0 rc.confirmation=off "$uuid" modify -claude
else
	# Add claude tag if not present
	task rc.bulk=0 rc.confirmation=off "$uuid" modify +claude
fi
