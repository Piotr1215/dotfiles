#!/usr/bin/env zsh

cols=$(tput cols)
rows=$(tput lines)

center_text() {
	local input="$1"
	local pad=$(((cols - ${#input}) / 2))
	printf '%*s' "$pad" ''
	echo "$input"
}

# Fetch one motivational quote from the ZenQuotes API; -f drops HTTP error pages
quote_response=$(curl -sf --max-time 5 https://zenquotes.io/api/random)

# Extract the quote and author. print -r keeps the JSON byte for byte, where
# zsh's echo would turn escapes such as \\ and \n into other characters.
quote=$(print -r -- "$quote_response" | jq -r '.[0].q // empty' 2>/dev/null)
author=$(print -r -- "$quote_response" | jq -r '.[0].a // empty' 2>/dev/null)

# Fall back when the API is down, slow, rate limited or returns broken JSON
if [[ -z $quote ]]; then
	quote="It always seems impossible until it's done."
	author="Nelson Mandela"
fi

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
