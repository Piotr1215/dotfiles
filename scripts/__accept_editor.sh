#!/usr/bin/env bash
set -euo pipefail

# Run an editor and record whether it wrote the temporary file, allowing the
# caller to distinguish Vim :q (cancel) from :wq (accept).

accept_file="${CAPABILITY_PICKER_ACCEPT_FILE:?accept marker path is required}"
editor_spec="${CAPABILITY_PICKER_EDITOR:-/usr/bin/editor}"
edit_file="${!#}"

before="$(stat -c '%y:%z:%s:%i' "$edit_file")"
read -r -a editor_command <<< "$editor_spec"
"${editor_command[@]}" "$@"
after="$(stat -c '%y:%z:%s:%i' "$edit_file")"

if [[ "$before" != "$after" ]]; then
	: > "$accept_file"
fi
