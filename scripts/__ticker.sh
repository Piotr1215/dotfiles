#!/bin/bash

TARGET_DATE="2024-05-31"

DAYS_LEFT=$(($(date -d "$TARGET_DATE" +%s) - $(date +%s)))
DAYS_LEFT=$(($DAYS_LEFT / 86400)) # Convert seconds to days

# Calculate days passed since 15th April of the current year
DAYS_FROM=$(($(date +%s) - $(date -d "$(date +%Y)-04-15" +%s)))
DAYS_FROM=$(($DAYS_FROM / 86400)) # Convert seconds to days

if [ $DAYS_LEFT -lt 0 ]; then
	echo "The date has passed!"
else
	echo -e "$DAYS_LEFT days left\n$DAYS_FROM passed" | figlet -f term | boxes -d peek -a c
fi
