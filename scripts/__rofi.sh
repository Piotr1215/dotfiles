#!/usr/bin/env bash
# Apply the shared responsive theme to direct rofi modes such as drun and
# clipboard history. Picker scripts call rofi_theme themselves for custom caps.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/__lib_rofi_theme.sh"

rofi_theme
exec rofi "$@" "${ROFI_THEME[@]}"
