#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -euo pipefail

# Add source and line number wher running in debug mode: bash -xv list-competed.sh
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

echo "Increase duration of task $@"
# Fetch the duration value using taskwarrior and jq
dur=$(task "$@" export | jq -r '.[0].duration')

# Check if the duration has hours
if [[ $dur == *"H"* ]]; then
	# Extract both hour and minute parts
	hour=$(echo $dur | awk -F 'T' '{split($2, a, "H"); print a[1]}')
	minute=$(echo $dur | awk -F 'H' '{split($2, a, "M"); print a[1]}')

	# Add 30 to the minutes
	new_minute=$((minute + 30))

	# Check if minutes are 60 or more
	if [[ $new_minute -ge 60 ]]; then
		# Add 1 to the hour
		new_hour=$((hour + 1))

		# Calculate new minutes
		new_minute=$((new_minute - 60))
	else
		# Keep the original hour
		new_hour=$hour
	fi

	# Create the new duration string
	new_dur="PT${new_hour}H${new_minute}M"
else
	# If duration is already 30M
	if [[ $dur == "PT30M" ]]; then
		# Make it 1H
		new_dur="PT1H"
	else
		# Extract the minute part from the duration string
		minute=$(echo $dur | awk -F 'T' '{split($2, a, "M"); print a[1]}')

		# Add 30 to the minutes
		new_minute=$((minute + 30))

		# Create the new duration string
		new_dur="PT${new_minute}M"
	fi
fi

# Print the new duration
echo "Original duration: $dur"
echo "New duration: $new_dur"

task rc.bulk=0 rc.confirmation=off rc.dependency.confirmation=off rc.recurrence.confirmation=off "$@" modify duration="$new_dur"
