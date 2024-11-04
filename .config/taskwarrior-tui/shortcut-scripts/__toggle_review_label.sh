#!/usr/bin/env bash

uuid="$1"
# Use task _tags command to get current tags
current_tags=$(task _tags "$uuid")

if echo "$current_tags" | grep -q "review"; then
	# Remove review tag if present
	task rc.bulk=0 rc.confirmation=off "$uuid" modify -review
else
	# Add review tag if not present
	task rc.bulk=0 rc.confirmation=off "$uuid" modify +review
fi
