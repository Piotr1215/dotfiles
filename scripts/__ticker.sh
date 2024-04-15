#!/bin/bash

TARGET_DATE="2024-05-31"

CURRENT_DATE=$(date +%Y-%m-%d)

DAYS_LEFT=$(($(date -d "$TARGET_DATE" +%s) - $(date -d "$CURRENT_DATE" +%s)))
DAYS_LEFT=$(($DAYS_LEFT / 86400)) # Convert seconds to days

if [ $DAYS_LEFT -lt 0 ]; then
	echo "The date has passed!"
else
	echo $DAYS_LEFT days | figlet -f term | boxes -d peek -a c
fi
