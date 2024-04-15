#!/bin/bash

# Target date in YYYY-MM-DD format
TARGET_DATE="2024-05-31"

# Current date in YYYY-MM-DD format
CURRENT_DATE=$(date +%Y-%m-%d)

# Calculate the difference in days using the date command
DAYS_LEFT=$(($(date -d "$TARGET_DATE" +%s) - $(date -d "$CURRENT_DATE" +%s)))
DAYS_LEFT=$(($DAYS_LEFT / 86400)) # Convert seconds to days

# Check if the date is past and adjust the message
if [ $DAYS_LEFT -lt 0 ]; then
	echo "The date has passed!"
else
	# Use figlet for fancy large text and boxes to draw a box around it
	echo $DAYS_LEFT days | figlet -f term | boxes -d peek -a c
fi
