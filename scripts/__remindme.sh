#!/bin/env bash

set e

remindme() {
set -x
  # Check that our requirements exist
  command -v yad >/dev/null 2>&1 || return 1

  # Scope (ish) our vars to this function
  local time msg

  # Use parameter expansion to provide basic "has an arg been given?" validation
  # The next step beyond this would be testing that it's actually an integer
  # An imperfect but common method for this would be [ "${time}" -eq "${time}" ]
  time="${1:?No time parameter given}"
  time=$(( time * 60 )) || return 1

  # Move it on over...
  shift 1

  # Whatever parameters are left are sucked up into the message.  Yay, I guess?
  echo msg="${*}"
  msg="${*}"

  # You could validate this too.  Here's one possible approach
  # This is the shell equivalent of str.len or similarly named tests in other languages
  (( "${#msg}" > 0 )) || return 1

  # Now that we have robustly and defensively prepared for the things, do the things.
  sleep "${time}"
  yad --text "${msg}"
set +x
}
