#!/usr/bin/env bash

uuid="$1"
# Use task _tags command to get current tags
current_tags=$(task _tags "$uuid")

if echo "$current_tags" | grep -q "wt"; then
	# Remove wt tag if present
	task rc.bulk=0 rc.confirmation=off "$uuid" modify -wt
else
	# Add wt tag if not present
	task rc.bulk=0 rc.confirmation=off "$uuid" modify +wt
fi
