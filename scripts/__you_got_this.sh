#!/usr/bin/env zsh
cols=$(tput cols)
rows=$(tput lines)

center_text() {
	local input="$1"
	local pad=$(((cols - ${#input}) / 2))
	printf '%*s' "$pad" ''
	echo "$input"
}

# Read the output of your ticker script into an array
ticker_output=("${(@f)$(~/dev/dotfiles/scripts/__ticker.sh)}")

# Calculate the number of empty lines to print at the top to center vertically
ticker_lines=${#ticker_output[@]}
vertical_padding=$(( ((rows - ticker_lines) / 2) - 30 ))

# Print the vertical padding
for ((i = 0; i < vertical_padding; i++)); do
	echo ""
done

# Now center each line of the ticker output horizontally
for line in "${ticker_output[@]}"; do
	center_text "$line"
done

# Center the "You got this" message
center_text "You got this 🦾"
