#!/usr/bin/env zsh

cols=$(tput cols)
rows=$(tput lines)

center_text() {
	local input="$1"
	local pad=$(((cols - ${#input}) / 2))
	printf '%*s' "$pad" ''
	echo "$input"
}

# Fetch a motivational quote from the ZenQuotes API
quote_response=$(curl -s https://zenquotes.io/api/quotes)

# Extract the quote and author using jq
quote=$(echo $quote_response | jq -r '.[0].q')
author=$(echo $quote_response | jq -r '.[0].a')

# Calculate the number of empty lines to print at the top to center vertically
vertical_padding=$(((rows / 2) - 2))

# Print the vertical padding
for ((i = 0; i < vertical_padding; i++)); do
	echo ""
done

# Center the motivational quote
center_text "$quote"
center_text "- $author"
center_text ""
center_text "You got this 🦾"
