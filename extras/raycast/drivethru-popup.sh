#!/bin/bash

# Raycast Script Command: open the drivethru picker in a popup terminal.
# Bind it to a hotkey in Raycast (see docs/hotkeys.md).
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title drivethru
# @raycast.mode silent
#
# Optional parameters:
# @raycast.packageName drivethru
# @raycast.description Fuzzy-find a Google Drive item in a popup terminal and copy its link.

# Raycast runs scripts in a non-login shell and only appends /usr/local/bin to
# PATH, so add the usual Homebrew and user locations.
export PATH="/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:$HOME/.local/bin:$PATH"

if ! command -v drivethru >/dev/null 2>&1; then
  printf '%s\n' "drivethru is not installed (or not on PATH)"
  exit 1
fi

# `drivethru popup` opens a terminal window and returns at once. Its stdout and
# stderr go to /dev/null and a file rather than Raycast's pipes, so nothing it
# starts can keep this script (and Raycast) waiting.
errfile=$(/usr/bin/mktemp -t drivethru-raycast) || exit 1
trap '/bin/rm -f "$errfile"' EXIT

if ! drivethru popup >/dev/null 2>"$errfile"; then
  # Silent mode shows the last stdout line as a HUD: make it the error.
  msg=$(/usr/bin/tail -n 1 "$errfile")
  printf '%s\n' "${msg:-drivethru popup failed}"
  exit 1
fi
