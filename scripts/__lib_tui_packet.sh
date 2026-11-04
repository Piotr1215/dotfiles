#!/usr/bin/env bash
# Build a picker token from a single task export on stdin. No trailing space.
tui_task_packet() {
  local uuid=$1 default_repo=$2
  jq -er --arg id "$uuid" --arg default_repo "$default_repo" 'def flat: tostring | gsub("[\u0000-\u001f\u007f-\u009f]"; " ") | gsub("\\s+"; " ") | gsub("^ +| +$"; ""); def fallback($default): (. // "" | flat) | if . == "" then $default else . end; select(type == "array" and length == 1) | .[0] | select(.uuid == $id and (.description | type == "string")) | "@\"\(.uuid)|\(.linear_issue_id | fallback("-"))|\(.repo | fallback($default_repo))|\(.description | flat)\""'
}
