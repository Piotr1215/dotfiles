#!/usr/bin/env bash

# Source generic error handling funcion
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __set_wallpaper.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

WALLPAPER_DIR="${HOME}/wallpapers"

# Check if the wallpaper directory is empty
if [[ -z "$(ls -A "${WALLPAPER_DIR}")" ]]; then
	echo "No wallpapers found in ${WALLPAPER_DIR}. Please add some images to the directory."
	exit 1
fi

set_wallpaper() {
	local file_path="${1}"
	local file_uri="file://${file_path}"

	if [[ -f "${file_path}" ]]; then
		gsettings set org.gnome.desktop.background picture-uri "${file_uri}"
		gsettings set org.gnome.desktop.background picture-uri-dark "${file_uri}"
	else
		echo "File not found: ${file_path}"
		exit 1
	fi
}

CURRENT_WALLPAPER_FILE="${WALLPAPER_DIR}/CURRENT_WALLPAPER"
cd "${WALLPAPER_DIR}" && ranger --choosefile "${CURRENT_WALLPAPER_FILE}"

if [[ -f "${CURRENT_WALLPAPER_FILE}" ]]; then
	selected_wallpaper=$(cat "${CURRENT_WALLPAPER_FILE}")
	set_wallpaper "${selected_wallpaper}"
	echo "Wallpaper has been set successfully to ${selected_wallpaper}."
else
	echo "Error: Unable to select a wallpaper."
	exit 1
fi
